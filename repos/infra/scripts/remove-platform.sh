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
# A new DESTROY pipeline after an interrupted one skips the Kubernetes part when
# it is already done: the cluster is gone or being deleted, or the access entry
# of the caller is gone (terraform destroy removes it among its first deletions,
# and destroy-<env> only runs once this script has succeeded).
#
# Usage: scripts/remove-platform.sh staging|prod
set -euo pipefail

NAMESPACE="code-keeper"
env="${1:-}"
[[ "$env" == staging || "$env" == prod ]] || { echo "usage: $0 staging|prod" >&2; exit 2; }
region="${AWS_REGION:-eu-west-3}"
cluster="code-keeper-$env"
err="$(mktemp)"
trap 'rm -f "$err"' EXIT

# Only a missing cluster means that there is nothing to do: any other error
# (token, network, throttling) stops the job, otherwise destroy-<env> would
# delete the cluster and leave the volumes of the claims behind.
if ! status="$(aws eks describe-cluster --region "$region" --name "$cluster" \
  --query cluster.status --output text 2>"$err")"; then
  if grep -q ResourceNotFoundException "$err"; then
    echo "no cluster $cluster: nothing to delete inside Kubernetes"
    exit 0
  fi
  cat "$err" >&2
  exit 1
fi
if [[ "$status" == DELETING ]]; then
  echo "cluster $cluster is being deleted: nothing to delete inside Kubernetes"
  exit 0
fi

# The role of the CI job, or the user (or role) of an administrator running
# this script by hand.
principal="${AWS_ROLE_ARN:-$(aws sts get-caller-identity --query Arn --output text |
  sed -E 's#^arn:aws:sts::([0-9]+):assumed-role/([^/]+)/.*#arn:aws:iam::\1:role/\2#')}"
if ! aws eks describe-access-entry --region "$region" --cluster-name "$cluster" \
  --principal-arn "$principal" >/dev/null 2>"$err"; then
  if grep -q ResourceNotFoundException "$err"; then
    echo "no access entry for $principal in $cluster: a previous destroy already went past this step"
    exit 0
  fi
  cat "$err" >&2
  exit 1
fi

aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$cluster" >/dev/null

volumes="$(kubectl --context "$cluster" get pv -o \
  "jsonpath={range .items[?(@.spec.claimRef.namespace==\"$NAMESPACE\")]}{.spec.csi.volumeHandle}{\" \"}{end}")"
echo "== EBS volumes of namespace $NAMESPACE: ${volumes:-none}"

# A namespace that is already being deleted refuses a second delete (conflict).
phase="$(kubectl --context "$cluster" get namespace "$NAMESPACE" --ignore-not-found -o jsonpath='{.status.phase}')"
case "$phase" in
  "") echo "== namespace $NAMESPACE already deleted" ;;
  Terminating)
    echo "== namespace $NAMESPACE already being deleted: waiting"
    kubectl --context "$cluster" wait --for=delete "namespace/$NAMESPACE" --timeout=10m ||
      [[ -z "$(kubectl --context "$cluster" get namespace "$NAMESPACE" --ignore-not-found -o name)" ]]
    ;;
  *)
    echo "== deleting namespace $NAMESPACE of $cluster"
    kubectl --context "$cluster" delete namespace "$NAMESPACE" --wait=true --timeout=10m
    ;;
esac

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
