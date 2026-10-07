#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Renders docs/USAGE.md's images: each row of docs/tapes/usage run as
# `hi <flag> <example>` and drawn by freeze as <out>/usage-<flag>[-<n>].svg.
# .github/workflows/usage.yml renders them and pages.yml serves them beside the
# demo GIFs; nothing commits them. The page's text is not written here: the
# docs prettier plugin builds it from the same table and common/flags.
#
# Every example runs in a fresh throwaway home - an ssh config with a tagged
# host, a vimrc and an aliases file for --plugins to find, a git identity for
# the header - after its row's setup command. That home and the directory
# holding this checkout both print as /home/you, so no image shows the
# renderer's own paths. Nothing inherited reaches hi: each run starts from
# `env -i`.
#
#   docs/tapes/usage.sh [<out>]    (default: docs/tapes)
set -euo pipefail

_HI_USAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
_HI_USAGE_HOME="${_HI_USAGE_ROOT%/*}"
_HI_USAGE_OUT="${1:-$_HI_USAGE_ROOT/docs/tapes}"
_HI_USAGE_SHOWN=/home/you

if ! command -v freeze >/dev/null 2>&1; then
  echo "usage.sh: freeze is not installed (.github/actions/setup-tool/tools.txt pins it)" >&2
  exit 1
fi
mkdir -p "$_HI_USAGE_OUT"

_HI_USAGE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hi-usage.XXXXXX")"
# Never the exit status: a rootless podman a preview asks leaves storage in
# the fixture home that only its user namespace can remove
function usage_cleanup() {
  case "$_HI_USAGE_TMP" in */hi-usage.??????) rm -rf "$_HI_USAGE_TMP" 2>/dev/null || : ;; esac
}
trap usage_cleanup EXIT

# usage_home <dir> - the fixture home
function usage_home() {
  mkdir -p "$1/.ssh" "$1/.config"
  printf '%s\n' '# Tags: prod' 'Host db-prod' '  HostName 10.0.0.5' \
    'Host web-dev' '  HostName 10.0.0.6' 'Host bastion' '  HostName 10.0.0.2' \
    >"$1/.ssh/config"
  printf '%s\n' 'set number' >"$1/.vimrc"
  printf '%s\n' "alias ll='ls -l'" >"$1/.aliases"
  printf '%s\n' '[user]' '  name = You' '  email = you@example.com' >"$1/.gitconfig"
}

# usage_hi <home> <word...> - hi in <home>, stdout and stderr together
function usage_hi() {
  local home="$1"
  shift
  env -i HOME="$home" PATH="$home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 _HI_HOME="$_HI_USAGE_HOME" \
    "$_HI_USAGE_ROOT/hi.sh" "$@" </dev/null 2>&1
}

# usage_render <slug> <flag> <example> <setup> - one image; 1 when the
# setup or the example exits non-zero, which is never drawn
function usage_render() {
  local slug="$1" flag="$2" example="$3" setup="$4" home out rc=0
  local -a words=() pre=()
  home="$_HI_USAGE_TMP/$slug"
  usage_home "$home"
  [ -z "$example" ] || read -r -a words <<<"$example"
  if [ -n "$setup" ]; then
    read -r -a pre <<<"$setup"
    if ! out="$(usage_hi "$home" "${pre[@]}")"; then
      printf ' | %-20s FAILED  setup (hi %s):\n%s\n' "$slug" "$setup" "$out"
      return 1
    fi
  fi
  out="$(usage_hi "$home" "$flag" ${words[@]+"${words[@]}"})" || rc=$?
  out="${out//"$home"/$_HI_USAGE_SHOWN}"
  out="${out//"$_HI_USAGE_HOME"/$_HI_USAGE_SHOWN}"
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    printf ' | %-20s FAILED  hi %s %s exited %s:\n%s\n' "$slug" "$flag" "$example" "$rc" "$out"
    return 1
  fi
  printf '\033[1;32m$\033[0m hi %s%s\n%s\n' "$flag" "${example:+ $example}" "$out" |
    freeze --language ansi --window --theme monokai --line-height 1 --font.family monospace \
      --output "$_HI_USAGE_OUT/usage-$slug.svg" >/dev/null
  printf ' | %-20s ok\n' "$slug"
}

failed=0
done_n=0
last=""
n=0
while IFS='|' read -r flag example setup || [ -n "$flag" ]; do
  case "$flag" in '#'* | '') continue ;; esac
  if [ "$flag" = "$last" ]; then n=$((n + 1)); else n=1; fi
  last="$flag"
  [ "$example" != - ] || continue
  slug="${flag#--}"
  [ "$n" -eq 1 ] || slug="$slug-$n"
  if usage_render "$slug" "$flag" "$example" "$setup"; then
    done_n=$((done_n + 1))
  else
    failed=$((failed + 1))
  fi
done <"$_HI_USAGE_ROOT/docs/tapes/usage"

printf ' | %s rendered, %s failed, into %s\n' "$done_n" "$failed" "$_HI_USAGE_OUT"
[ "$failed" -eq 0 ]
