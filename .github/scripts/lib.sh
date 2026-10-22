#!/usr/bin/env bash
# Shared by the CI scripts beside it; sourced, never run.

# _ci_need <me> <tool...> - every tool on PATH, or "<me>: no <tool> on PATH"
# and exit 127
function _ci_need() {
  local me="$1" tool
  shift
  for tool; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "$me: no $tool on PATH" >&2
      exit 127
    }
  done
}

# _ci_files <globs> - the tracked files that space-separated pathspec globs
# name, via git when there is a work tree (so build output and vendored trees
# stay out); a plain globstar walk otherwise. Nothing for an empty list.
function _ci_files() {
  local globs=() specs=() g
  read -ra globs <<<"$1"
  [ "${#globs[@]}" -gt 0 ] || return 0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for g in "${globs[@]}"; do specs+=(":(glob)$g"); done
    git ls-files -- "${specs[@]}"
  else
    (
      shopt -s globstar nullglob
      for g in "${globs[@]}"; do
        # shellcheck disable=SC2086 # the glob is expanded here on purpose
        printf '%s\n' $g
      done
    )
  fi | sort -u
}

# the files _ci_image_pins reads when the caller names none
_CI_IMAGE_GLOBS='Dockerfile */Dockerfile **/*.Dockerfile **/compose*.y*ml docker-compose*.y*ml'

# _ci_image_refs - `file|image|tag|digest` per tagged image reference in the
# files named on stdin, in file order: a Dockerfile `FROM` (optional
# --platform=) or a compose `image:`, the digest `sha256:<hex>` when the
# reference pins one, else empty. `FROM <stage>` and `FROM ${ARG}` carry no
# tag and drop out, as does a reference whose tag or digest is a variable.
function _ci_image_refs() {
  local f r
  while IFS= read -r f; do
    sed -nE \
      -e 's/^FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]@$]+):([^[:space:]@$:/]+)(@(sha256:[0-9a-f]{64}))?([[:space:]].*)?$/\2|\3|\5/p' \
      -e "s/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*[\"']?([^[:space:]@\$\"'*&]+):([^[:space:]@\$:/\"']+)(@(sha256:[0-9a-f]{64}))?[\"']?[[:space:]]*(#.*)?\$/\2|\3|\5/p" \
      "$f" | while IFS= read -r r; do printf '%s|%s\n' "$f" "$r"; done
  done
}

# _ci_image_pins - `image|tag|sha256:<hex>` per digest-pinned reference in the
# files named on stdin, sorted and unique
function _ci_image_pins() {
  _ci_image_refs | awk -F'|' '$4 != "" { print $2 "|" $3 "|" $4 }' | sort -u
}
