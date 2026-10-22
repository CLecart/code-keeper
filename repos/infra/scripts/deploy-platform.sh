#!/usr/bin/env bash
# Installs the platform layer of an environment, after `terraform apply`:
#
#   1. kubeconfig of the cluster code-keeper-<environment>
#   2. Helm charts: Cluster Autoscaler, monitoring (Prometheus + Grafana) and
#      logging (Fluent Bit), before the workloads so their first logs are shipped
#   3. namespace, then the database and RabbitMQ secrets: random, created once,
#      never printed (the databases keep the password of their first start)
#   4. platform/ manifests with the images of ECR
#   5. waits until both databases and RabbitMQ are ready
#
# Usage: scripts/deploy-platform.sh staging|prod
#
# Environment:
#   AWS_REGION    Region of the cluster (default eu-west-3)
#   ECR_REGISTRY  registry of the images (CI variable)
#   INVENTORY_DATABASE_TAG, BILLING_DATABASE_TAG, RABBITMQ_SERVER_TAG
#                 image tags (default: scripts/image-tag.sh, needs the Git history)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE="code-keeper"
IMAGES=(inventory-database billing-database rabbitmq-server)
# Chart versions pinned so every run installs exactly the same thing; Renovate
# (code-keeper/renovate) proposes their updates through the comments below.
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_VERSION="92.11.0"
# renovate: datasource=helm depName=fluent-bit registryUrl=https://fluent.github.io/helm-charts
FLUENT_BIT_VERSION="0.58.3"
# renovate: datasource=helm depName=cluster-autoscaler registryUrl=https://kubernetes.github.io/autoscaler
CLUSTER_AUTOSCALER_VERSION="9.59.0"

env="${1:-}"
[[ "$env" == staging || "$env" == prod ]] || { echo "usage: $0 staging|prod" >&2; exit 2; }
region="${AWS_REGION:-eu-west-3}"
registry="${ECR_REGISTRY:?ECR_REGISTRY must be set}"
cluster="code-keeper-$env"

for tool in aws kubectl helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed" >&2; exit 1; }
done

tag_of() {
  local var="${1^^}_TAG"
  var="${var//-/_}"
  if [[ -n "${!var:-}" ]]; then echo "${!var}"; else "$ROOT/scripts/image-tag.sh" "$1"; fi
}

# 32 hexadecimal characters (128 bits).
random_secret() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

create_secret() {
  local name="$1" user="$2"
  if kubectl -n "$NAMESPACE" get secret "$name" >/dev/null 2>&1; then
    echo "kept secret $name"
    return
  fi
  kubectl -n "$NAMESPACE" create secret generic "$name" \
    --from-literal=username="$user" --from-literal=password="$(random_secret)" >/dev/null
  kubectl -n "$NAMESPACE" label secret "$name" app.kubernetes.io/part-of=code-keeper >/dev/null
  echo "created secret $name"
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== cluster $cluster ($region)"
aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$cluster" >/dev/null
kubectl config use-context "$cluster" >/dev/null

# Values that depend on the environment: CLUSTER_NAME placeholders.
for values in cluster-autoscaler fluent-bit; do
  sed "s/CLUSTER_NAME/$cluster/g" "$ROOT/platform/helm/$values.yaml" >"$work/$values.yaml"
done

echo "== node autoscaling: Cluster Autoscaler"
helm upgrade --install cluster-autoscaler cluster-autoscaler \
  --repo https://kubernetes.github.io/autoscaler --version "$CLUSTER_AUTOSCALER_VERSION" \
  --namespace kube-system \
  --values "$work/cluster-autoscaler.yaml" --wait --timeout 5m

echo "== monitoring: Prometheus + Grafana"
helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  --namespace monitoring --create-namespace \
  --values "$ROOT/platform/helm/kube-prometheus-stack.yaml" --wait --timeout 10m

echo "== logging: Fluent Bit -> CloudWatch Logs"
helm upgrade --install fluent-bit fluent-bit \
  --repo https://fluent.github.io/helm-charts --version "$FLUENT_BIT_VERSION" \
  --namespace logging --create-namespace \
  --values "$work/fluent-bit.yaml" --wait --timeout 5m

echo "== namespace and secrets"
kubectl apply -f "$ROOT/platform/namespace.yaml"
create_secret inventory-db-secret inventory_user
create_secret billing-db-secret billing_user
create_secret rabbitmq-secret rabbit_user

echo "== platform manifests"
# Overlay generated at every run: only the image names change.
mkdir -p "$work/overlay"
cp -r "$ROOT/platform" "$work/platform"
{
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  echo "resources:"
  echo "  - ../platform"
  echo "images:"
  for image in "${IMAGES[@]}"; do
    echo "  - name: $image"
    echo "    newName: $registry/code-keeper/$image"
    echo "    newTag: \"$(tag_of "$image")\""
  done
} >"$work/overlay/kustomization.yaml"
kubectl apply -k "$work/overlay"

echo "== waiting for the databases and RabbitMQ"
for workload in statefulset/inventory-db statefulset/billing-db statefulset/rabbitmq; do
  kubectl -n "$NAMESPACE" rollout status "$workload" --timeout=10m
done

kubectl -n "$NAMESPACE" get pods -o wide
