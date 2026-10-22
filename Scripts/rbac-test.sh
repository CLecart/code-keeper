#!/usr/bin/env bash
# Proves that the pipeline of each application may deploy its own objects and
# nothing else in Kubernetes (infra repository: platform/rbac.yaml and the
# access entries of terraform/modules/environment/eks.tf):
#
#   1. AWS: the access entry of the CI role code-keeper-ci-<application> holds
#      the group code-keeper-deploy-<application> and no EKS access policy, so
#      the role has the rights of that group and nothing more
#   2. kubectl auth can-i as a member of that group (impersonation):
#      allowed  what its deploy job does to its own workload, Service,
#               HorizontalPodAutoscaler and PodDisruptionBudget
#      refused  another application, the databases, RabbitMQ, the Secrets,
#               deleting, exec, the Roles, the quota, the network policies
#   3. the deploy job itself, as that group: kubectl apply -k of its k8s/
#      manifests passes and the same for another application is refused (both
#      server-side dry runs: nothing is changed), kubectl rollout status passes
#
# Changes nothing in the cluster or in AWS. Run by an administrator of the
# cluster (impersonation needs the admin access entry), once the infra pipeline
# has applied the change and the applications are deployed.
#
# Usage: Scripts/rbac-test.sh staging|prod
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="code-keeper"
APPS=(inventory-app billing-app api-gateway-app)
# Workload (K8S_WORKLOAD of its .gitlab-ci.yml) and Service of each application.
declare -A WORKLOAD=([inventory-app]=deployment/inventory-app [billing-app]=statefulset/billing-app [api-gateway-app]=deployment/api-gateway)
declare -A SERVICE=([inventory-app]=inventory-app [billing-app]=billing-app [api-gateway-app]=api-gateway)

env="${1:-}"
[[ "$env" == staging || "$env" == prod ]] || { echo "usage: $0 staging|prod" >&2; exit 2; }
region="${AWS_REGION:-eu-west-3}"
cluster="code-keeper-$env"
aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$cluster" >/dev/null
account="$(aws sts get-caller-identity --query Account --output text)"

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# First line of the last error, account number masked (the output may be shown).
last_error() { head -n 1 "$err" | cut -c1-200 | sed -E 's/[0-9]{12}/<account>/g'; }

failed=0
total=0
check() {
  local label="$1" got="$2" expected="$3"
  total=$((total + 1))
  if [[ "$got" == "$expected" ]]; then
    echo "  PASS  $label -> $got"
  else
    echo "  FAIL  $label -> $got (expected $expected)"
    failed=$((failed + 1))
  fi
}

# kubectl as a member of the group of the application under test ($group).
as_group() { kubectl --context "$cluster" -n "$NAMESPACE" --as=rbac-test --as-group="$group" "$@"; }

# yes or no from kubectl auth can-i; an error is reported as such, never as a "no".
can_i() {
  local answer
  answer="$(as_group auth can-i "$@" 2>"$err")" || true
  case "$answer" in
    yes) echo yes ;;
    no*) echo no ;;
    *) echo "error: $(last_error)" ;;
  esac
}
expect() {
  local expected="$1"
  shift
  check "can-i $*" "$(can_i "$@")" "$expected"
}

# Server-side dry run of kubectl apply -k: accepted, refused (every object
# forbidden), or anything else as an error.
apply_dry_run() {
  local out
  if out="$(as_group apply -k "$ROOT_DIR/repos/$1/k8s" --dry-run=server 2>&1)"; then
    echo accepted
  elif [[ "$out" == *forbidden* && "$out" != *"(server dry run)"* ]]; then
    echo refused
  else
    echo "error: $(head -n 1 <<<"$out" | cut -c1-200)"
  fi
}

echo "== Kubernetes rights of the application pipelines in $cluster"
for app in "${APPS[@]}"; do
  group="code-keeper-deploy-$app"
  workload="${WORKLOAD[$app]}"
  name="${workload#*/}"
  role="code-keeper-ci-$app"
  echo
  echo "== $app (group $group)"

  # 1. The role gets the rights of the group, and no EKS access policy.
  arn="arn:aws:iam::$account:role/$role"
  groups="$(aws eks describe-access-entry --region "$region" --cluster-name "$cluster" --principal-arn "$arn" \
    --query "accessEntry.kubernetesGroups[]" --output text 2>"$err")" || groups="error: $(last_error)"
  check "Kubernetes groups of $role" "${groups:-none}" "$group"
  policies="$(aws eks list-associated-access-policies --region "$region" --cluster-name "$cluster" --principal-arn "$arn" \
    --query "associatedAccessPolicies[].policyArn" --output text 2>"$err")" || policies="error: $(last_error)"
  check "EKS access policies of $role" "${policies:-none}" none

  # 2. What its deploy job does: apply (get, create, patch), rollout status
  #    (get, list, watch on its name), get pods.
  for verb in get patch list watch; do expect yes "$verb" "$workload"; done
  expect yes create "${workload%/*}s"
  expect yes get "service/${SERVICE[$app]}"
  expect yes patch "service/${SERVICE[$app]}"
  if [[ "$workload" == deployment/* ]]; then
    expect yes patch "horizontalpodautoscaler/$name"
    expect yes patch "poddisruptionbudget/$name"
    expect no create statefulsets
  else
    expect no create deployments
  fi
  expect yes list pods
  #    What it must never do.
  expect no delete "$workload"
  for other in "${APPS[@]}"; do
    if [[ "$other" != "$app" ]]; then
      expect no patch "${WORKLOAD[$other]}"
      expect no patch "service/${SERVICE[$other]}"
    fi
  done
  for platform in inventory-db billing-db rabbitmq; do
    expect no patch "statefulset/$platform"
    expect no delete "statefulset/$platform"
    expect no patch "service/$platform"
  done
  for secret in inventory-db-secret billing-db-secret rabbitmq-secret; do
    expect no get "secret/$secret"
  done
  expect no list secrets
  expect no create pods --subresource=exec
  expect no create rolebindings
  expect no patch "role/deploy-$app"
  expect no patch resourcequota/no-load-balancers
  expect no delete networkpolicy/default-deny-ingress

  # 3. The deploy job itself (server-side dry runs, then a read-only wait).
  check "kubectl apply -k repos/$app/k8s --dry-run=server" "$(apply_dry_run "$app")" accepted
  for other in "${APPS[@]}"; do
    if [[ "$other" != "$app" ]]; then
      check "kubectl apply -k repos/$other/k8s --dry-run=server" "$(apply_dry_run "$other")" refused
    fi
  done
  if as_group rollout status "$workload" --timeout=2m >/dev/null 2>"$err"; then rollout=passed; else rollout="error: $(last_error)"; fi
  check "kubectl rollout status $workload" "$rollout" passed
done

echo
if [[ "$failed" -eq 0 ]]; then echo "All $total RBAC checks passed"; else echo "$failed of $total RBAC checks failed"; exit 1; fi
