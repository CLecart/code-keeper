#!/usr/bin/env bash
# First half of the deletion of an environment, before `terraform destroy`:
# deletes the code-keeper namespace while the cluster still runs, so that its
# volume claims delete their EBS volumes (StorageClass reclaimPolicy Delete).
# Destroying the cluster alone would leave those volumes behind, still billed.
#
# The EBS volume IDs are read from the persistent volumes before the deletion,
# then the script waits until exactly those volumes are gone (staging and
# production use the same namespace name, so a tag filter could mix them up).
#
# Usage: scripts/remove-platform.sh staging|prod
set -euo pipefail

NAMESPACE="code-keeper"
env="${1:-}"
[[ "$env" == staging || "$env" == prod ]] || { echo "usage: $0 staging|prod" >&2; exit 2; }
region="${AWS_REGION:-eu-west-3}"
cluster="code-keeper-$env"

if ! aws eks describe-cluster --region "$region" --name "$cluster" >/dev/null 2>&1; then
  echo "no cluster $cluster: nothing to delete inside Kubernetes"
  exit 0
fi

aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$cluster" >/dev/null

volumes="$(kubectl --context "$cluster" get pv -o \
  "jsonpath={range .items[?(@.spec.claimRef.namespace==\"$NAMESPACE\")]}{.spec.csi.volumeHandle}{\" \"}{end}")"
echo "== EBS volumes of namespace $NAMESPACE: ${volumes:-none}"

echo "== deleting namespace $NAMESPACE of $cluster"
kubectl --context "$cluster" delete namespace "$NAMESPACE" --ignore-not-found --wait=true --timeout=10m

read -ra volume_list <<<"$volumes"
[[ ${#volume_list[@]} -gt 0 ]] || exit 0
ids="$(IFS=,; echo "${volume_list[*]}")"
for _ in $(seq 1 30); do
  # A deleted volume no longer matches the filter; describe fails on nothing.
  count="$(aws ec2 describe-volumes --region "$region" --filters "Name=volume-id,Values=$ids" \
    --query 'length(Volumes)' --output text)"
  [[ "$count" -eq 0 ]] && { echo "all volumes deleted"; exit 0; }
  echo "waiting for $count volume(s) to be deleted by the EBS CSI driver..."
  sleep 10
done
echo "error: volumes still present after 5 minutes: $ids" >&2
exit 1
