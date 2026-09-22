#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Stamps README.md's ssh_payload badge with what a session sends -
# _hi_wire_estimate - so the number is measured, never typed. Run it after a
# change that moves the payload, and commit the README it rewrites.
# `--check` is `--group bench`'s half: it rewrites nothing, and fails unless
# the badge is within 5KB of what this would stamp.
#
# Usage: packaging/stamp_badge.sh [--check] [readme]
#   readme   the file holding the badge (default: the tree's README.md) - the
#            packaging suite points it at a scratch copy
#
# The script a session sends carries the sender's session values (user, host,
# TERM, settings.sh's exports), so the figure is taken in a pinned environment
# - no _HI_* inherited, an empty $HOME, a fixed user and host - or the machine
# that stamps and the runner that checks would disagree by a few bytes, and a
# figure near a rounding edge would flip between them.
set -euo pipefail

_hi_sb_tree="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_hi_sb_home="$(mktemp -d "${TMPDIR:-/tmp}/hi-badge.XXXXXX")"
trap 'rm -rf "$_hi_sb_home"' EXIT

# shellcheck disable=SC2016 # expands in the pinned child, not here
_hi_sb_figure="$(env -i PATH="$PATH" HOME="$_hi_sb_home" TERM=xterm-256color \
  _HI_LOCAL_USER=user _HI_LOCAL_HOSTNAME=host \
  bash -c 'd="$1" && set -- && source "$d/hi.sh" && _hi_wire_estimate' _ "$_hi_sb_tree")B"
_hi_sb_check=0
[ "${1:-}" = --check ] && _hi_sb_check=1 && shift
_hi_sb_readme="${1:-$_hi_sb_tree/README.md}"
_hi_sb_badge="$(sed -n 's/.*ssh_payload-\([0-9.]*KB\)-.*/\1/p' "$_hi_sb_readme" | head -1)"
[ -n "$_hi_sb_badge" ] || {
  echo "stamp_badge.sh: no ssh_payload-<n>KB badge in $_hi_sb_readme" >&2
  exit 1
}

if [ "$_hi_sb_check" = 1 ]; then
  # 5KB of slack either way, so a small payload change does not need a restamp
  awk -v a="${_hi_sb_badge%KB}" -v b="${_hi_sb_figure%KB}" 'BEGIN { exit !(a - b <= 5 && b - a <= 5) }' </dev/null &&
    echo "README payload badge: $_hi_sb_badge, measured $_hi_sb_figure (within 5KB)" && exit 0
  echo "README payload badge says $_hi_sb_badge but a session sends $_hi_sb_figure - run packaging/stamp_badge.sh" >&2
  exit 1
fi
sed "s/ssh_payload-[0-9.]*KB-/ssh_payload-$_hi_sb_figure-/" "$_hi_sb_readme" >"$_hi_sb_readme.tmp"
mv -f "$_hi_sb_readme.tmp" "$_hi_sb_readme"
echo "${_hi_sb_readme##*/}: ssh_payload-$_hi_sb_figure"
