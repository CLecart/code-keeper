#!/usr/bin/env bash
# Read-only inventory of the billable resources in every enabled AWS Region,
# run at the end of a work session (after the DESTROY pipeline and
# Scripts/tooling.sh stop).
#
# Expected to stay: the GitLab and runner machines (stopped), their disks and
# their Elastic IPs, all tagged Stack=bootstrap (about 13.80 USD/month). Anything
# else is reported: running instances, other disks or IPs, NAT gateways, load
# balancers, EKS clusters, RDS, Lambda.
#
# Exit status: 0 when only the expected tooling remains, 1 otherwise, 2 on an
# AWS error.
#
# Usage: Scripts/inventory.sh
set -euo pipefail

COLUMNS_HEADER="REGION RUNNING OTHER-EC2 OTHER-EBS OTHER-EIP NAT ELB EKS RDS LAMBDA"

# Counts are computed by AWS itself (JMESPath length), never by counting lines.
# The tooling stack (tag Stack=bootstrap) is left out of the OTHER-* columns.
count_region() {
  local r="$1"
  local q=(--region "$r" --output text)
  # shellcheck disable=SC2016 # the backticks are JMESPath literals, not shell
  local not_tooling='!(Tags[?Key==`Stack` && Value==`bootstrap`])'
  printf '%s %s %s %s %s %s %s %s %s %s\n' "$r" \
    "$(aws ec2 describe-instances "${q[@]}" --filters Name=instance-state-name,Values=pending,running,stopping,shutting-down --query 'length(Reservations[].Instances[])')" \
    "$(aws ec2 describe-instances "${q[@]}" --filters Name=instance-state-name,Values=stopped --query "length(Reservations[].Instances[?$not_tooling][])")" \
    "$(aws ec2 describe-volumes "${q[@]}" --query "length(Volumes[?$not_tooling])")" \
    "$(aws ec2 describe-addresses "${q[@]}" --query "length(Addresses[?$not_tooling])")" \
    "$(aws ec2 describe-nat-gateways "${q[@]}" --filter Name=state,Values=pending,available,deleting --query 'length(NatGateways)')" \
    "$(aws elbv2 describe-load-balancers "${q[@]}" --query 'length(LoadBalancers)')" \
    "$(aws eks list-clusters "${q[@]}" --query 'length(clusters)')" \
    "$(aws rds describe-db-instances "${q[@]}" --query 'length(DBInstances)')" \
    "$(aws lambda list-functions "${q[@]}" --query 'length(Functions)')"
}
export -f count_region

regions="$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
echo "# Inventory, $(date '+%F %H:%M:%S'), $(wc -w <<<"$regions") Regions"

# Each line must hold the Region and nine numbers, otherwise an AWS call failed.
# $regions is split on purpose (one Region per line); the single quotes keep $1 for bash -c.
# shellcheck disable=SC2016,SC2086
if ! rows="$(printf '%s\n' $regions | xargs -P 8 -I{} bash -c 'count_region "$1"' _ {} | sort)"; then
  echo "error: an AWS call failed during the inventory" >&2
  exit 2
fi
if grep -q -v -E '^[a-z0-9-]+( [0-9]+){9}$' <<<"$rows"; then
  echo "error: unexpected AWS answer:" >&2
  grep -v -E '^[a-z0-9-]+( [0-9]+){9}$' <<<"$rows" >&2
  exit 2
fi

{ echo "$COLUMNS_HEADER"; echo "$rows"; } | column -t
unexpected="$(awk '{ for (i = 2; i <= NF; i++) s += $i } END { print s + 0 }' <<<"$rows")"

echo
echo "# Kept on purpose (tooling stack, Stack=bootstrap):"
# shellcheck disable=SC2016 # the backticks are JMESPath literals, not shell
aws ec2 describe-instances --region "${AWS_REGION:-eu-west-3}" \
  --filters Name=tag:Stack,Values=bootstrap \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name]' --output text | sed 's/^/  /'
aws ec2 describe-volumes --region "${AWS_REGION:-eu-west-3}" --filters Name=tag:Stack,Values=bootstrap \
  --query 'Volumes[].[VolumeId,Size]' --output text | sed 's/^/  disk (GB) /'
aws ecr describe-repositories --region "${AWS_REGION:-eu-west-3}" \
  --query 'repositories[].[repositoryName]' --output text | sed 's/^/  ECR /'

echo
if [[ "$unexpected" -eq 0 ]]; then
  echo "OK: only the stopped tooling stack remains in the $(wc -w <<<"$regions") Regions."
else
  echo "WARNING: $unexpected unexpected billable resource(s), see the table above." >&2
  exit 1
fi
