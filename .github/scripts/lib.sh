#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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
