#!/usr/bin/env bash
# The four GitLab repositories (group code-keeper) are kept in repos/<name>/ of
# this repository and synchronised with git subtree, which keeps the history
# in both directions. Only committed changes are published.
#   Scripts/repos.sh push [name...]   repos/<name> -> main of code-keeper/<name>
#   Scripts/repos.sh pull [name...]   main of code-keeper/<name> -> repos/<name>
# Without a name, every folder of repos/ is synchronised. Git goes over SSH
# with the key that the gitlab_projects Ansible role registers for clecart.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GROUP="code-keeper"

usage() {
  echo "Usage: $0 push|pull [name...]" >&2
  exit 2
}

action="${1:-}"
[[ "$action" == push || "$action" == pull ]] || usage
shift

gitlab_ip=$(terraform -chdir="$ROOT/bootstrap" output -raw gitlab_public_ip)

if [[ $# -gt 0 ]]; then
  names=("$@")
else
  names=()
  for dir in "$ROOT"/repos/*/; do
    names+=("$(basename "$dir")")
  done
fi

for name in "${names[@]}"; do
  if [[ ! -d "$ROOT/repos/$name" ]]; then
    echo "No folder repos/$name" >&2
    exit 1
  fi
  url="git@$gitlab_ip:$GROUP/$name.git"
  echo "== $action $name ($url)"
  case "$action" in
    push) git -C "$ROOT" subtree push --prefix="repos/$name" "$url" main ;;
    pull) git -C "$ROOT" subtree pull --prefix="repos/$name" "$url" main \
            -m "chore: pull $name from GitLab" ;;
  esac
done
