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
#      pipeline runs build, test and scan only (no image, no deployment); the
#      branch is deleted once that pipeline has finished
#   6. the branch pipeline cannot assume an AWS role: covered by the OIDC trust
#      policies (main only), shown by the job list of step 5
#   7. that branch pipeline passes
#   8. creating a project                                    -> refused:
#      projects limit 0 for every account without admin rights (Ansible), so
#      a Developer owns no project where it could protect a branch of its own
#      and run jobs on the "builder" runner, which mounts the Docker socket
#   9. running approve-production of an application          -> refused;
#      skipped, not failed, when no pipeline of main waits for its approval
#
# Uses the Ansible API token of root (vault) to create and revoke the
# impersonation token and to find the jobs to act on; nothing else is changed
# except the test branch, deleted at the end (its pipeline stays in the history
# as evidence), and a project created if check 8 fails, marked for deletion.
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
skipped=0
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
created_project=""
cleanup() {
  as_root -o /dev/null -X DELETE "$API/projects/$(enc "code-keeper/$APP")/repository/branches/$branch" || true
  if [[ -n "$created_project" ]]; then as_root -o /dev/null -X DELETE "$API/projects/$created_project" || true; fi
  as_root -o /dev/null -X DELETE "$API/users/$dev_id/impersonation_tokens/$token_id" || true
  echo "impersonation token revoked, branch $branch deleted${created_project:+, project $created_project marked for deletion}"
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
if [[ "$status" == success ]]; then
  echo "  PASS  7. the branch pipeline passes (pipeline $pipeline: success)"
else
  echo "  FAIL  7. the branch pipeline did not pass (pipeline $pipeline: ${status:-no status})"; failed=$((failed + 1))
fi

# The accounts without admin rights have a projects limit of 0 (Ansible,
# roles/gitlab). The message is checked too: a 403 for another reason (a token
# scope, for example) would prove nothing about that limit.
answer="$(as_dev -w '\n%{http_code}' -X POST --data-urlencode "name=$branch" "$API/projects")"
code="${answer##*$'\n'}" body="${answer%$'\n'*}"
if [[ "$code" == 403 && "$body" == *"You cannot create projects in your personal namespace"* ]]; then
  echo "  PASS  8. creating a project refused (HTTP 403: projects limit 0)"
else
  echo "  FAIL  8. creating a project not refused as expected (HTTP $code, expected 403 for the projects limit): ${body:0:200}"; failed=$((failed + 1))
  if [[ "$code" == 201 ]]; then created_project="$(jq -r .id <<<"$body")"; fi
fi

# Running a manual job of main takes the right to merge into main (Maintainers),
# checked by GitLab before anything else: the newest approval waiting on main in
# an application is tried. None waiting leaves nothing to try, not a failure.
approval_app="" approval_job=""
for app in inventory-app billing-app api-gateway-app; do
  approval_job="$(as_root "$API/projects/$(enc "code-keeper/$app")/jobs?scope%5B%5D=manual&per_page=100" |
    jq -r '[.[] | select(.name == "approve-production" and .ref == "main")][0].id // empty')"
  if [[ -n "$approval_job" ]]; then approval_app="$app"; break; fi
done
if [[ -n "$approval_job" ]]; then
  check "9. running approve-production of $approval_app (job $approval_job) refused" \
    "$(dev_status -X POST "$API/projects/$(enc "code-keeper/$approval_app")/jobs/$approval_job/play")" 403
else
  echo "  SKIP  9. running approve-production not tried: no approve-production job waits on main in inventory-app, billing-app or api-gateway-app"
  skipped=$((skipped + 1))
fi

echo
note=""
if [[ "$skipped" -gt 0 ]]; then note=" ($skipped skipped)"; fi
if [[ "$failed" -eq 0 ]]; then echo "All protection checks passed$note"; else echo "$failed protection check(s) failed$note"; exit 1; fi
