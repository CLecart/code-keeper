#!/usr/bin/env bash
# Prints the tag of a platform image: the short hash of the last commit that
# changed images/<name>. An unchanged image keeps its tag, so it is built and
# pushed once, and the databases are not restarted by an unrelated commit.
#
# Usage: scripts/image-tag.sh inventory-database|billing-database|rabbitmq-server
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?usage: $0 <image name>}"

[[ -d "$ROOT/images/$name" ]] || { echo "error: no images/$name" >&2; exit 1; }

tag="$(git -C "$ROOT" log -1 --format=%h -- "images/$name")"
[[ -n "$tag" ]] || { echo "error: no commit touches images/$name (shallow clone?)" >&2; exit 1; }
echo "$tag"
