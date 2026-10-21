#!/usr/bin/env bash
# Starts or stops the GitLab and runner machines. Stopped, they only cost their
# disks and Elastic IPs (about 13.80 USD/month); running, about 0.23 USD/h.
#   Scripts/tooling.sh start|stop|status
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="eu-west-3"

ids=$(terraform -chdir="$ROOT/bootstrap" output -json instance_ids | jq -r '.gitlab, .runner')
read -r -d '' -a instances <<<"$ids" || true

if [[ ${#instances[@]} -ne 2 ]]; then
  echo "Instance IDs not found in the bootstrap outputs." >&2
  exit 1
fi

status() {
  # shellcheck disable=SC2016 # the backticks are JMESPath literals, not shell
  aws ec2 describe-instances --region "$REGION" --instance-ids "${instances[@]}" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,PublicIpAddress]' \
    --output text
}

case "${1:-status}" in
  start)
    aws ec2 start-instances --region "$REGION" --instance-ids "${instances[@]}" >/dev/null
    aws ec2 wait instance-running --region "$REGION" --instance-ids "${instances[@]}"
    status
    echo "GitLab needs a few minutes after boot before it answers."
    ;;
  stop)
    aws ec2 stop-instances --region "$REGION" --instance-ids "${instances[@]}" >/dev/null
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids "${instances[@]}"
    status
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: $0 start|stop|status" >&2
    exit 2
    ;;
esac
