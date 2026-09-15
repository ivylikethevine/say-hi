#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Reading ./tools.txt, shared by ./install.sh, ../setup-tools, and
# .github/scripts/check_tool_versions.sh - every consumer of the roster goes
# through here, so none keeps a copy of the format.

# tools.txt sits beside this file, so every consumer finds it the same way
# whether it was sourced from $GITHUB_ACTION_PATH or the repo root.
# CI_TOOLS_TXT overrides it for a local test against a scratch roster.
_CI_TOOLS_TXT="${CI_TOOLS_TXT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools.txt}"

# _ci_tool_rows - every data row, comments and blank lines dropped
function _ci_tool_rows() {
  grep -v '^[[:space:]]*\(#\|$\)' "$_CI_TOOLS_TXT"
}

# _ci_tool_row <tool> - that tool's row, or a message and non-zero
function _ci_tool_row() {
  local row
  # awk, not grep: a tool name is a literal, and `.` in one is not a wildcard
  row="$(_ci_tool_rows | awk -F'|' -v t="$1" '$1 == t { print; exit }')"
  [ -n "$row" ] || {
    echo "setup-tool: no row for '$1' in $_CI_TOOLS_TXT" >&2
    return 1
  }
  printf '%s\n' "$row"
}

# _ci_platform - this machine as tools.txt's sha256 column names it:
# linux-x86_64, linux-aarch64, darwin-x86_64 or darwin-aarch64. uname says
# arm64 on macOS and aarch64 on Linux for the same CPU; one spelling here.
function _ci_platform() {
  local os arch
  case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) os="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
  esac
  case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) arch="$(uname -m)" ;;
  esac
  printf '%s-%s\n' "$os" "$arch"
}

# _ci_sha256_pick <sha256-column> <platform> - prints "<hex>|<slug>" for that
# platform, or a message and non-zero. A bare hex is one asset for every
# platform (slug empty); a `platform[:slug]=hex,...` list is one asset per
# platform, slug defaulting to the platform name. See tools.txt's header.
function _ci_sha256_pick() {
  local col="$1" platform="$2" entry key hex slug
  case "$col" in
  "")
    echo "setup-tool: empty sha256 column - every row needs one" >&2
    return 1
    ;;
  *=*) ;;
  *)
    _ci_is_sha256 "$col" || {
      echo "setup-tool: sha256 column '$col' is neither 64 hex digits nor a platform list" >&2
      return 1
    }
    printf '%s|\n' "$col"
    return 0
    ;;
  esac
  local IFS=,
  for entry in $col; do
    key="${entry%%=*}"
    hex="${entry#*=}"
    slug="${key#*:}"
    key="${key%%:*}"
    [ "$key" = "$platform" ] || continue
    _ci_is_sha256 "$hex" || {
      echo "setup-tool: sha256 for $platform is not 64 hex digits: '$hex'" >&2
      return 1
    }
    printf '%s|%s\n' "$hex" "$slug"
    return 0
  done
  echo "setup-tool: no sha256 entry for $platform (this row covers: $col)" >&2
  return 1
}

# _ci_is_sha256 <string> - exactly 64 lowercase hex digits
function _ci_is_sha256() {
  [ "${#1}" -eq 64 ] && case "$1" in *[!0-9a-f]*) false ;; esac
}

# _ci_row_sha256_ok <sha256-column> - the column is well-formed for every
# platform it names (install.sh only ever checks the one it runs on)
function _ci_row_sha256_ok() {
  local entry key
  case "$1" in
  *=*) ;;
  *)
    _ci_is_sha256 "$1"
    return
    ;;
  esac
  local IFS=,
  for entry in $1; do
    key="${entry%%=*}"
    case "${key%%:*}" in
    linux-x86_64 | linux-aarch64 | darwin-x86_64 | darwin-aarch64) ;;
    *) return 1 ;;
    esac
    _ci_is_sha256 "${entry#*=}" || return 1
  done
}
