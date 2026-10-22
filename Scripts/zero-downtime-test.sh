#!/usr/bin/env bash
# Proves that a rolling update cuts no request: while the pods of an
# application are replaced (kubectl rollout restart, the same rolling update as
# a deployment by the pipeline), requests are sent without pause through the
# public API Gateway, and every answer other than HTTP 200 is counted.
#
# Usage: Scripts/zero-downtime-test.sh staging|prod api-gateway|inventory-app
#   api-gateway    requests GET /health
#   inventory-app  requests GET /api/movies/ with a Cognito token
#
# Exit status: 0 when every request answered 200 during the whole rollout.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env="${1:-}"
app="${2:-}"
[[ "$env" == staging || "$env" == prod ]] || { echo "usage: $0 staging|prod api-gateway|inventory-app" >&2; exit 2; }
case "$app" in
  api-gateway) path=/health; token="" ;;
  inventory-app) path=/api/movies/; token="$("$ROOT_DIR/Scripts/api-token.sh" "$env")" ;;
  *) echo "usage: $0 staging|prod api-gateway|inventory-app" >&2; exit 2 ;;
esac

region="${AWS_REGION:-eu-west-3}"
context="code-keeper-$env"
url="$(aws apigatewayv2 get-apis --region "$region" \
  --query "Items[?Name=='code-keeper-$env'].ApiEndpoint | [0]" --output text)$path"
aws eks update-kubeconfig --region "$region" --name "code-keeper-$env" --alias "$context" >/dev/null

results="$(mktemp)"
trap 'rm -f "$results"' EXIT

# About 5 requests per second, below the API Gateway throttling (20/s).
send_requests() {
  local headers=()
  [[ -n "$token" ]] && headers=(--header "Authorization: Bearer $token")
  while [[ ! -e "$results.stop" ]]; do
    curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}\n' "${headers[@]}" "$url" >>"$results" || echo 000 >>"$results"
    sleep 0.2
  done
}

echo "== $app in $env: requests to $url during a rolling update"
send_requests &
sender=$!
sleep 5
kubectl --context "$context" -n code-keeper rollout restart "deployment/$app"
kubectl --context "$context" -n code-keeper rollout status "deployment/$app" --timeout=5m
# Keep sending a little after the end of the rollout (old pods still terminating).
sleep 15
touch "$results.stop"
wait "$sender"
rm -f "$results.stop"

total="$(wc -l <"$results")"
errors="$(grep -c -v '^200$' "$results" || true)"
echo "requests: $total, answers other than 200: $errors"
sort "$results" | uniq -c | sed 's/^/  /'
[[ "$errors" -eq 0 ]]
