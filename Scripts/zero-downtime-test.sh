#!/usr/bin/env bash
# Proves that replacing the pods of an application cuts no request: requests
# are sent without pause through the public API Gateway while the pods are
# replaced, and every answer other than HTTP 200 is counted.
#
# Usage: Scripts/zero-downtime-test.sh staging|prod api-gateway|inventory-app [rollout|drain|watch [seconds]]
#   api-gateway    requests GET /health
#   inventory-app  requests GET /api/movies/ with a Cognito token
#   rollout        (default) kubectl rollout restart: the same rolling update as
#                  a deployment by the pipeline
#   drain          kubectl drain of the node of a replica, limited to the pods of
#                  the application: what a node maintenance (EKS node group
#                  update) does to them; the node is uncordoned at the end
#   watch          nothing is changed: the requests run for <seconds> (default 180)
#                  while a deployment made by the pipeline itself happens (click
#                  approve-production during the window); the image before and
#                  after is printed to show that the deployment took place
#
# Exit status: 0 when every request answered 200 during the whole test.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env="${1:-}"
app="${2:-}"
mode="${3:-rollout}"
seconds="${4:-180}"
usage="usage: $0 staging|prod api-gateway|inventory-app [rollout|drain|watch [seconds]]"
[[ "$env" == staging || "$env" == prod ]] || { echo "$usage" >&2; exit 2; }
[[ "$mode" == rollout || "$mode" == drain || "$mode" == watch ]] || { echo "$usage" >&2; exit 2; }
[[ "$seconds" =~ ^[0-9]+$ ]] || { echo "$usage" >&2; exit 2; }
case "$app" in
  api-gateway) path=/health; token="" ;;
  inventory-app) path=/api/movies/; token="$("$ROOT_DIR/Scripts/api-token.sh" "$env")" ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

region="${AWS_REGION:-eu-west-3}"
context="code-keeper-$env"
url="$(aws apigatewayv2 get-apis --region "$region" \
  --query "Items[?Name=='code-keeper-$env'].ApiEndpoint | [0]" --output text)$path"
aws eks update-kubeconfig --region "$region" --name "code-keeper-$env" --alias "$context" >/dev/null

results="$(mktemp)"
sender=""
node=""
# Also on failure: stop the requests, and never leave a node cordoned.
cleanup() {
  if [[ -n "$sender" ]]; then
    touch "$results.stop"
    wait "$sender" || true
  fi
  [[ -z "$node" ]] || kubectl --context "$context" uncordon "$node" || true
  rm -f "$results" "$results.stop"
}
trap cleanup EXIT

# About 5 requests per second, below the API Gateway throttling (20/s).
send_requests() {
  local headers=()
  [[ -n "$token" ]] && headers=(--header "Authorization: Bearer $token")
  while [[ ! -e "$results.stop" ]]; do
    # One line per request: time and HTTP code (000: no answer within 5 s).
    code="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' "${headers[@]}" "$url")" || code="${code:-000}"
    echo "$(date +%T) $code" >>"$results"
    sleep 0.2
  done
}

echo "== $app in $env: requests to $url during a $mode"
send_requests &
sender=$!
sleep 5
image() {
  kubectl --context "$context" -n code-keeper get "deployment/$app" \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
}
if [[ "$mode" == rollout ]]; then
  kubectl --context "$context" -n code-keeper rollout restart "deployment/$app"
elif [[ "$mode" == watch ]]; then
  image_before="$(image)"
  echo "watching for ${seconds}s: approve the deployment now"
  sleep "$seconds"
else
  # The node of the first replica. Like a node update, kubectl drain goes
  # through the eviction API, which honours the PodDisruptionBudget.
  node="$(kubectl --context "$context" -n code-keeper get pods -l "app=$app" \
    -o jsonpath='{.items[0].spec.nodeName}')"
  kubectl --context "$context" drain "$node" --pod-selector "app=$app" \
    --ignore-daemonsets --delete-emptydir-data --timeout=5m
fi
# Until every replica is ready again.
kubectl --context "$context" -n code-keeper rollout status "deployment/$app" --timeout=5m
# Keep sending a little after the end (old pods still terminating).
sleep 15
touch "$results.stop"
wait "$sender"
sender=""
# Registry and account left out: repository and tag only.
[[ "$mode" != watch ]] || echo "image: ${image_before##*/} -> $(image | sed 's|.*/||')"
rm -f "$results.stop"

total="$(wc -l <"$results")"
errors="$(awk '$2 != "200"' "$results" | wc -l)"
echo "requests: $total, answers other than 200: $errors"
awk '{print $2}' "$results" | sort | uniq -c | sed 's/^/  /'
awk '$2 != "200" {print "  failed at " $1 ": " $2}' "$results" | head -20
[[ "$errors" -eq 0 ]]
