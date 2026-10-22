#!/usr/bin/env bash
# Builds, scans and pushes the platform images whose tag is not in ECR yet,
# then writes images.env (dotenv report of the CI job) with the tag of every
# image for the deployment jobs. A tag is never pushed twice (the ECR
# repositories are immutable), so an unchanged image is skipped.
#
# The scan (Trivy) blocks the push when the image has a HIGH or CRITICAL
# vulnerability that already has a fix.
#
# Runs on the builder runner (protected branches only), which mounts the
# Docker socket of the runner machine.
#
# Usage: scripts/build-images.sh
# Environment: ECR_REGISTRY, AWS_REGION (CI variables), AWS credentials (OIDC)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES=(inventory-database billing-database rabbitmq-server)
TRIVY_IMAGE="public.ecr.aws/aquasecurity/trivy:0.76.1"

registry="${ECR_REGISTRY:?ECR_REGISTRY must be set}"
region="${AWS_REGION:-eu-west-3}"
dotenv="$ROOT/images.env"

aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"

: >"$dotenv"
for name in "${IMAGES[@]}"; do
  tag="$("$ROOT/scripts/image-tag.sh" "$name")"
  var="${name^^}_TAG"
  echo "${var//-/_}=$tag" >>"$dotenv"
  ref="$registry/code-keeper/$name:$tag"

  if aws ecr describe-images --region "$region" --repository-name "code-keeper/$name" \
    --image-ids imageTag="$tag" >/dev/null 2>&1; then
    echo "== $name:$tag already in ECR"
    continue
  fi

  echo "== build $name:$tag"
  # A single-platform image without provenance or SBOM attestations: Docker 29
  # would otherwise push an index that ECR shows as an extra untagged artifact.
  docker build --pull --provenance=false --sbom=false --tag "$ref" "$ROOT/images/$name"

  echo "== scan $name:$tag"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY_IMAGE" image \
    --no-progress --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$ref"

  echo "== push $name:$tag"
  docker push "$ref"
done

cat "$dotenv"
