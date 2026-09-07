#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# `hi --update`: move the say-hi checkout this hi runs from to a release tag.
#
# Here and not in hi.sh, for the reason common/core.sh states about
# scripts/lib.sh - hi.sh ships in the ssh payload under a size budget, and
# this is the one subcommand that cannot succeed anywhere the payload copy is
# what is running: a disposable tree is /tmp/<x>/say-hi with no .git, and a
# target with a permanent install runs its own hi.sh. It went through
# _hi_dispatch_subcommand like every other subcommand once it had a script to
# name. $_HI_NO_GIT lives here too, for the same reason.
#
# SC2317/SC2329: shellcheck follows the `source "$_HI_LAUNCHER"` chain into
# hi.sh's trailing `_hi "$@"` and marks what follows unreachable - it does not
# model hi.sh's BASH_SOURCE guard (same story as scripts/doctor.sh).
# shellcheck disable=SC2317,SC2329
set -euo pipefail

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"

_HI_NO_GIT="no .git in $_HI_ROOT - a packaged install updates through its package manager (apt/dnf/apk upgrade say-hi, or brew upgrade say-hi); a tarball install unpacks the next release from https://github.com/ivylikethevine/say-hi/releases over this one; a hi session updates on the machine say-hi lives on"

# the script's own usage line names what was typed, the way doctor.sh does
me="${_HI_ARGV0:-hi --update}"
root="$_HI_ROOT" tag="" dirty="" here=""
# --help anywhere on the line, and ahead of the .git check so a package gets
# the text too
for _hi_arg in "$@"; do
  case "$_hi_arg" in -h | --help) set -- --help ;; esac
done
unset _hi_arg
case "${1:-}" in
-h | --help)
  cat <<EOF
Usage: $me [<tag>]

Moves the say-hi checkout this hi runs from to a release tag (needs its
.git; a package has none, so it says so and stops):
$me           the newest release tag, after fetching them
$me <tag>     that release

Either way the checkout is left detached on the tag. A tree with
uncommitted changes is refused. \`git -C $root tag\` lists the releases;
following a branch instead is \`git -C $root pull\`, by hand.
EOF
  exit 0
  ;;
esac
[ -d "$root/.git" ] || {
  _hi_cecho "$me: $_HI_NO_GIT" "$RED" >&2
  exit 1
}
case "${1:-}" in
-*)
  _hi_cecho "$me: unknown option $1 (one release tag, or nothing for the newest)" "$RED" >&2
  exit 1
  ;;
esac
[ $# -le 1 ] || {
  _hi_cecho "$me: one release tag at most ($*)" "$RED" >&2
  exit 1
}
tag="${1:-}"
dirty="$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)"
[ -z "$dirty" ] || {
  _hi_cecho "$me: uncommitted changes in $root; commit or stash them first" "$RED" >&2
  exit 1
}
git -C "$root" fetch --tags --quiet || {
  _hi_cecho "$me: git fetch failed in $root (see above)" "$RED" >&2
  exit 1
}
if [ -z "$tag" ]; then
  # newest release by version (v0.0.10 above v0.0.9); a pre-release
  # (v1.0.0-rc.1) is never chosen unasked - name it to move there
  tag="$(git -C "$root" tag --list 'v*' --sort=-v:refname | grep -v -- - | head -n 1)"
  [ -n "$tag" ] || {
    _hi_cecho "$me: no release tags in $root" "$RED" >&2
    exit 1
  }
elif ! git -C "$root" show-ref --verify -q "refs/tags/$tag"; then
  _hi_cecho "$me: no release tag named $tag; git -C $root tag lists them" "$RED" >&2
  exit 1
fi
here="$(exec git -C "$root" describe --tags --exact-match 2>/dev/null)" || here=""
if [ "$here" = "$tag" ]; then
  _hi_cecho "$me: already on $tag" "$GREEN"
  exit 0
fi
git -C "$root" checkout -q "refs/tags/$tag" || {
  _hi_cecho "$me: git checkout of $tag failed in $root (see above)" "$RED" >&2
  exit 1
}
_hi_cecho "$me: now on $tag (detached)" "$GREEN"
exit 0
