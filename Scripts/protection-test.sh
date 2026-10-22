#!/usr/bin/env bash
# Proves the protections of the GitLab projects by acting as the "developer"
# account (Developer role) through a short-lived impersonation token, revoked
# at the end:
#
#   1. pushing to main of an application                    -> refused
#   2. starting a pipeline on main (e.g. DESTROY=true on infra) -> refused
#   3. re-running a production deployment of main            -> refused
#   4. reading the CI/CD variables of a project              -> refused
#   5. pushing a branch                                      -> allowed: its
#      pipeline runs build, test and scan only (no image, no deployment), and
#      passes; the branch is deleted once that pipeline has finished
#   6. the branch pipeline cannot assume an AWS role: covered by the OIDC trust
#      policies (main only), shown by the job list of step 5
#
# Uses the Ansible API token of root (vault) to create and revoke the
# impersonation token; nothing else is changed except the test branch, deleted
# at the end (its pipeline stays in the history as evidence).
#
# Usage: Scripts/protection-test.sh [application]   (default inventory-app)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-inventory-app}"
GITLAB="https://$(terraform -chdir="$ROOT_DIR/bootstrap" output -raw gitlab_public_ip)"
API="$GITLAB/api/v4"
CA="$HOME/.local/share/code-keeper/pki/ca.crt"
ROOT_TOKEN="$(cd "$ROOT_DIR/ansible" && ansible-vault view group_vars/all/vault.yml |
  sed -n -E 's/^vault_gitlab_api_token: *"?([^"]*)"?$/\1/p')"

as_root() { curl -sS --cacert "$CA" -H "PRIVATE-TOKEN: $ROOT_TOKEN" "$@"; }
as_dev() { curl -sS --cacert "$CA" -H "PRIVATE-TOKEN: $DEV_TOKEN" "$@"; }
# HTTP status of a request made as developer.
dev_status() { as_dev -o /dev/null -w '%{http_code}' "$@"; }
enc() { printf %s "$1" | sed 's|/|%2F|g'; }

failed=0
check() {
  local label="$1" got="$2" expected="$3"
  if [[ "$got" == "$expected" ]]; then echo "  PASS  $label (HTTP $got)"; else echo "  FAIL  $label (HTTP $got, expected $expected)"; failed=$((failed + 1)); fi
}

dev_id="$(as_root "$API/users?username=developer" | jq -r '.[0].id')"
DEV_TOKEN="$(as_root -X POST "$API/users/$dev_id/impersonation_tokens" \
  --data-urlencode "name=protection-test" --data "scopes[]=api" \
  --data "expires_at=$(date -d tomorrow +%F)" | jq -r .token)"
token_id="$(as_root "$API/users/$dev_id/impersonation_tokens?state=active&per_page=100" | jq -r '[.[] | select(.name=="protection-test")][0].id')"
branch="protection-test-$(date +%Y%m%d-%H%M%S)"
cleanup() {
  as_root -o /dev/null -X DELETE "$API/projects/$(enc "code-keeper/$APP")/repository/branches/$branch" || true
  as_root -o /dev/null -X DELETE "$API/users/$dev_id/impersonation_tokens/$token_id" || true
  echo "impersonation token revoked, branch $branch deleted"
}
trap cleanup EXIT

project="$(enc "code-keeper/$APP")"
infra="$(enc code-keeper/infra)"
echo "== acting as developer (Developer role) on code-keeper/$APP"

commit_body() {
  jq -n --arg b "$1" --arg s "$2" '{branch: $b, commit_message: "test: protection check", actions: [{action: "create", file_path: "protection-test.txt", content: $s}]}'
}

check "1. push to main of $APP refused" \
  "$(commit_body main x | dev_status -X POST -H 'Content-Type: application/json' "$API/projects/$project/repository/commits" -d @-)" 403

# GitLab answers 400 (not 403) here, with an explicit permission message.
answer="$(as_dev -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' "$API/projects/$infra/pipeline" \
  -d '{"ref":"main","variables":[{"key":"DESTROY","value":"true"}]}')"
if [[ "${answer##*$'\n'}" == 400 && "$answer" == *"sufficient permission to run a pipeline on 'main'"* ]]; then
  echo "  PASS  2. pipeline on main of infra with DESTROY=true refused (HTTP 400: no permission to run a pipeline on main)"
else
  echo "  FAIL  2. pipeline on main of infra not refused as expected: ${answer:0:200}"; failed=$((failed + 1))
fi

deploy_job="$(as_root "$API/projects/$project/jobs?scope%5B%5D=success&per_page=100" | jq -r '[.[] | select(.name=="deploy-production")][0].id')"
check "3. re-running deploy-production (job $deploy_job) refused" \
  "$(dev_status -X POST "$API/projects/$project/jobs/$deploy_job/retry")" 403

check "4. reading the CI/CD variables of $APP refused" \
  "$(dev_status "$API/projects/$project/variables")" 403

echo "== 5. push of branch $branch (allowed)"
code="$(jq -n --arg b "$branch" '{branch: $b, start_branch: "main", commit_message: "test: protection check", actions: [{action: "create", file_path: "protection-test.txt", content: "branch pipeline check\n"}]}' |
  dev_status -X POST -H 'Content-Type: application/json' "$API/projects/$project/repository/commits" -d @-)"
check "5. push of a new branch accepted" "$code" 201

pipeline=""
for _ in $(seq 1 30); do
  pipeline="$(as_root "$API/projects/$project/pipelines?ref=$branch" | jq -r '.[0].id // empty')"
  [[ -n "$pipeline" ]] && break
  sleep 2
done
jobs="$(as_root "$API/projects/$project/pipelines/$pipeline/jobs?per_page=100" | jq -r '[.[].name] | sort | join(", ")')"
echo "  branch pipeline $pipeline jobs: $jobs"
if [[ "$jobs" == *containerization* || "$jobs" == *deploy* || "$jobs" == *approve* ]]; then
  echo "  FAIL  the branch pipeline holds an image or deployment job"; failed=$((failed + 1))
else
  echo "  PASS  6. the branch pipeline only builds, tests and scans (no image, no deployment, no AWS role)"
fi

# The branch must outlive its pipeline: deleted earlier, the jobs cannot fetch it.
echo "  waiting for the branch pipeline to finish (it may wait for a free runner)..."
status=""
for _ in $(seq 1 90); do
  status="$(as_root "$API/projects/$project/pipelines/$pipeline" | jq -r .status)"
  case "$status" in success | failed | canceled | skipped) break ;; esac
  sleep 10
done
check "7. the branch pipeline passes (status $status)" "$status" success

echo
if [[ "$failed" -eq 0 ]]; then echo "All protection checks passed"; else echo "$failed protection check(s) failed"; exit 1; fi
