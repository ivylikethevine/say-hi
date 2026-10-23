#!/usr/bin/env bash
# The batched `resolve` for ./action.yml: every tool in $CI_TOOLS goes through
# ../setup-tool/install.sh's own resolve (so an unknown tool, a missing
# checksum, or an unsupported platform fails the same way), then the answers
# are folded into one cache key and one path list.
set -euo pipefail

: "${CI_TOOLS:?set by action.yml}"
: "${GITHUB_OUTPUT:?set by the runner}"

_ci_install="$(dirname "${BASH_SOURCE[0]}")/../setup-tool/install.sh"
_ci_out="$(mktemp)"
trap 'rm -f "$_ci_out"' EXIT

# the hosted image first (ImageOS: ubuntu24, ubuntu26, macos15; empty
# elsewhere): a source build links that image's libraries
_ci_key="${ImageOS:+ $ImageOS}"
_ci_paths=""
for _ci_t in $CI_TOOLS; do
  : >"$_ci_out"
  CI_TOOL="$_ci_t" GITHUB_OUTPUT="$_ci_out" "$_ci_install" resolve
  while IFS='=' read -r _ci_k _ci_v; do
    case "$_ci_k" in
    version) _ci_version="$_ci_v" ;;
    sha256) _ci_sha256="$_ci_v" ;;
    path) _ci_path="$_ci_v" ;;
    esac
  done <"$_ci_out"
  # the checksum's first 12 hex digits: enough for a corrected sha256 to
  # miss the old cache, short enough to keep the key readable
  _ci_key="$_ci_key $_ci_t=$_ci_version@${_ci_sha256:0:12}"
  _ci_paths="$_ci_paths$_ci_path"$'\n'
done

{
  printf 'key=%s\n' "$_ci_key"
  echo "paths<<CI_TOOLS_EOF"
  printf '%s' "$_ci_paths"
  echo "CI_TOOLS_EOF"
} >>"$GITHUB_OUTPUT"
