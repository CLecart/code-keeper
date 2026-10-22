#!/usr/bin/env bash
# Prints a Cognito access token (valid one hour) for the public API of an
# environment, creating the test user on the first run.
#
# The user pool and its client are found by name (code-keeper-<environment>,
# code-keeper-<environment>-api), so no Terraform state is needed. The user
# (default "auditor") gets a random password, saved in
# .cognito-test-user-<environment> (mode 600, ignored by Git). The password
# reaches the AWS CLI through a private temporary file, never the command line.
#
# Usage: Scripts/api-token.sh staging|prod
#   e.g. Scripts/test-api.sh staging   (calls this script itself)
#
# Environment:
#   COGNITO_USERNAME  user to sign in as (default auditor)
#   AWS_REGION        default eu-west-3
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | cut -c3-
}

env="${1:-}"
case "$env" in
  staging | prod) ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

CRED_FILE="$ROOT_DIR/.cognito-test-user-$env"
USERNAME="${COGNITO_USERNAME:-auditor}"
region="${AWS_REGION:-eu-west-3}"

pool="$(aws cognito-idp list-user-pools --region "$region" --max-results 60 \
  --query "UserPools[?Name=='code-keeper-$env'].Id | [0]" --output text)"
if [[ -z "$pool" || "$pool" == None ]]; then
  echo "error: no Cognito user pool code-keeper-$env (is the environment created?)" >&2
  exit 1
fi
client="$(aws cognito-idp list-user-pool-clients --region "$region" --user-pool-id "$pool" \
  --query "UserPoolClients[?ClientName=='code-keeper-$env-api'].ClientId | [0]" --output text)"

saved() { sed -n "s/^$1=//p" "$CRED_FILE" 2>/dev/null; }

# The AWS CLI cannot read --cli-input-json from a pipe: use a file in a private
# directory (mktemp -d creates it with mode 700), removed on exit.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir:?}"' EXIT
aws_json() {
  local json=$1
  shift
  (umask 077 && printf '%s' "$json" >"$tmp_dir/input.json")
  aws "$@" --cli-input-json "file://$tmp_dir/input.json"
}

# A new user (or a recreated user pool) gets a new random password.
if [[ "$(saved pool)" != "$pool" || "$(saved username)" != "$USERNAME" ]]; then
  # 24 random letters and digits, plus one character of each required class.
  # (Not `tr </dev/urandom | head`: tr would die of SIGPIPE and pipefail stop the script.)
  password="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24)Aa1!"
  if ! aws cognito-idp admin-get-user --region "$region" --user-pool-id "$pool" --username "$USERNAME" >/dev/null 2>&1; then
    aws cognito-idp admin-create-user --region "$region" --user-pool-id "$pool" \
      --username "$USERNAME" --message-action SUPPRESS >/dev/null
  fi
  aws_json "$(printf '{"UserPoolId":"%s","Username":"%s","Password":"%s","Permanent":true}' "$pool" "$USERNAME" "$password")" \
    cognito-idp admin-set-user-password --region "$region"
  (umask 077 && printf 'pool=%s\nusername=%s\npassword=%s\n' "$pool" "$USERNAME" "$password" >"$CRED_FILE")
  echo "created the Cognito user $USERNAME in code-keeper-$env (credentials in .cognito-test-user-$env)" >&2
fi

aws_json "$(printf '{"ClientId":"%s","AuthFlow":"USER_PASSWORD_AUTH","AuthParameters":{"USERNAME":"%s","PASSWORD":"%s"}}' \
  "$client" "$USERNAME" "$(saved password)")" \
  cognito-idp initiate-auth --region "$region" --query 'AuthenticationResult.AccessToken' --output text
