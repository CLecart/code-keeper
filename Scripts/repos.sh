#!/usr/bin/env bash
# The five GitLab repositories (group code-keeper) are kept in repos/<name>/ of
# this repository. Their content is synchronised, not their history: GitLab
# keeps its own (merge requests merged there included), this repository keeps
# the one of its folders. Only committed changes are published.
#   Scripts/repos.sh push [name...]   repos/<name> -> main of code-keeper/<name>
#   Scripts/repos.sh pull [name...]   main of code-keeper/<name> -> repos/<name>
# push replaces the files of main by the committed files of repos/<name>, in one
# commit (a fast-forward). It refuses when main holds a version this repository
# has never had, e.g. a merge request merged in GitLab: pull it first, or it
# would be undone. pull copies main into repos/<name> and commits it here.
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

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

for name in "${names[@]}"; do
  if [[ ! -d "$ROOT/repos/$name" ]]; then
    echo "No folder repos/$name" >&2
    exit 1
  fi
  url="git@$gitlab_ip:$GROUP/$name.git"
  clone="$work/$name"
  files="$work/$name.files"
  mkdir "$files"
  echo "== $action $name ($url)"
  git clone --quiet --branch main "$url" "$clone"

  case "$action" in
    push)
      # Has this repository ever had the content of main? Trees are named by
      # their content, so the same files give the same tree in both repositories.
      remote_tree="$(git -C "$clone" rev-parse 'HEAD^{tree}')"
      known=""
      while read -r commit; do
        if [[ "$(git -C "$ROOT" rev-parse --verify --quiet "$commit:repos/$name" || true)" == "$remote_tree" ]]; then
          known="$commit"
          break
        fi
      done < <(git -C "$ROOT" log --format=%H -- "repos/$name")
      if [[ -z "$known" ]]; then
        echo "error: main of $name holds changes that repos/$name never had (merged in GitLab?):" >&2
        echo "       run Scripts/repos.sh pull $name first" >&2
        exit 1
      fi
      # The committed files of the folder only (git archive: nothing ignored or
      # uncommitted), in place of the files of main.
      git -C "$ROOT" archive HEAD "repos/$name" | tar -x -C "$files" --strip-components=2
      rsync -a --delete --exclude=.git/ "$files/" "$clone/"
      git -C "$clone" add -A
      if git -C "$clone" diff --cached --quiet; then
        echo "already up to date"
        continue
      fi
      # Title: the last change of the folder here; body: every change published.
      {
        git -C "$ROOT" log -1 --format=%s -- "repos/$name"
        echo
        echo "From repos/$name of code-keeper:"
        git -C "$ROOT" log --reverse --format='- %s' "$known..HEAD" -- "repos/$name"
      } | git -C "$clone" commit --quiet -F -
      git -C "$clone" push --quiet origin main
      echo "main of $name is now $(git -C "$clone" rev-parse --short HEAD)"
      ;;
    pull)
      if ! git -C "$ROOT" diff --quiet HEAD -- "repos/$name"; then
        echo "error: repos/$name has uncommitted changes" >&2
        exit 1
      fi
      git -C "$clone" archive HEAD | tar -x -C "$files"
      # Tracked files that main no longer has; ignored files (node_modules,
      # .terraform...) stay untouched.
      git -C "$ROOT" ls-files -z -- "repos/$name" | while IFS= read -r -d '' path; do
        [[ -e "$files/${path#"repos/$name/"}" ]] || git -C "$ROOT" rm --quiet -- "$path"
      done
      cp -a "$files/." "$ROOT/repos/$name/"
      git -C "$ROOT" add -A -- "repos/$name"
      if git -C "$ROOT" diff --cached --quiet -- "repos/$name"; then
        echo "already up to date"
        continue
      fi
      git -C "$ROOT" commit --quiet -m "chore: pull $name from GitLab ($(git -C "$clone" rev-parse --short HEAD))" -- "repos/$name"
      echo "repos/$name now matches main of $name"
      ;;
  esac
done
