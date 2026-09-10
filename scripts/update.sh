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
# name.
#
# SC2317/SC2329: shellcheck follows the `source "$_HI_LAUNCHER"` chain into
# hi.sh's trailing `_hi "$@"` and marks what follows unreachable - it does not
# model hi.sh's BASH_SOURCE guard (same story as scripts/doctor.sh).
# shellcheck disable=SC2317,SC2329

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"

# Strict mode for the rest of this script: core.sh (sourced above) ends with
# `set +euo pipefail`, so a `set` line placed before it is silently undone.
# packaging/lib.sh does the same. GLOSSARY: HI.15
set -euo pipefail

# the script's own usage line names what was typed, the way doctor.sh does
me="${_HI_ARGV0:-hi --update}"
root="$_HI_ROOT" tag="" dirty="" here="" dry_run=""

function _hi_update_help() {
  cat <<EOF
Usage: $me [<tag>] [--dry-run]

Moves the say-hi checkout this hi runs from to a release tag (needs its
.git; a package has none, so it says so and stops):
$me           the newest release tag, after fetching them
$me <tag>     that release

Either way the checkout is left detached on the tag. A tree with
uncommitted changes is refused. \`git -C $root tag\` lists the releases;
following a branch instead is \`git -C $root pull\`, by hand.

  -n, --dry-run    Fetch the tags and say which one would be checked out,
                   moving nothing.
EOF
}
# --help and --dry-run anywhere on the line, and ahead of the .git check so a
# package gets the help text too; what is left is the tag, if any
for _hi_arg in "$@"; do
  case "$_hi_arg" in
  -h | --help)
    _hi_update_help
    exit 0
    ;;
  -n | --dry-run) dry_run=1 ;;
  *) set -- "$@" "$_hi_arg" ;;
  esac
  shift
done
unset _hi_arg
[ -d "$root/.git" ] || {
  _hi_cecho "$me: no .git in $_HI_ROOT - a packaged install updates through its package manager (apt/dnf/apk upgrade say-hi, or brew upgrade say-hi); a tarball install unpacks the next release from https://github.com/ivylikethevine/say-hi/releases over this one; a hi session updates on the machine say-hi lives on" "$RED" >&2
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
  # (v1.0.0-rc.1) is never chosen unasked - name it to move there. No match is
  # not a pipeline failure: grep -v exits 1 on an empty list, and the check
  # right below is what answers that, not `set -e`.
  tag="$(git -C "$root" tag --list 'v*' --sort=-v:refname | grep -v -- - | head -n 1)" || true
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
# The tag's signature, read off gpg's status lines rather than verify-tag's
# exit code, which is 1 for "bad", "unsigned" and "signed by a key you have not
# imported" alike. Only a bad signature refuses: an unsigned tag is what a
# fork or a mirror has, and a missing key is most first installs - both are
# said out loud and allowed, so the check never strands an update that plain
# git would have made. docs/SECURITY.md names the key.
sig="$(git -C "$root" verify-tag --raw "refs/tags/$tag" 2>&1)" || true
case "$sig" in
*'[GNUPG:] BADSIG'* | *'[GNUPG:] REVKEYSIG'*)
  _hi_cecho "$me: the signature on $tag does not verify - refusing to check it out" "$RED" >&2
  printf '%s\n' "$sig" | grep -v '^\[GNUPG:\]' >&2
  exit 1
  ;;
*'[GNUPG:] GOODSIG'* | *'[GNUPG:] EXPKEYSIG'*)
  # EXPKEYSIG: a good signature from a key that has since expired - still the
  # maintainer's, so an update after the expiry date is not stranded
  # the status line is "[GNUPG:] GOODSIG <key id> <user id>"; NEWSIG and the
  # rest come first in the output, so cut at this line's own tag
  case "$sig" in
  *'[GNUPG:] GOODSIG '*) signer="${sig#*\[GNUPG:\] GOODSIG }" ;;
  *) signer="${sig#*\[GNUPG:\] EXPKEYSIG }" ;;
  esac
  signer="${signer#* }"
  signer="${signer%%$'\n'*}"
  _hi_cecho "$me: $tag has a good signature from $signer" "$GREEN"
  ;;
*'Good "git" signature for '*)
  # an ssh-signed tag (gpg.format=ssh) that a configured allowed-signers file
  # vouches for; ssh-keygen's other verdicts land in the last arm
  signer="${sig#*Good \"git\" signature for }"
  signer="${signer%% with*}"
  _hi_cecho "$me: $tag has a good ssh signature from $signer" "$GREEN"
  ;;
*'[GNUPG:] NO_PUBKEY'* | *'[GNUPG:] ERRSIG'*)
  _hi_cecho "$me: $tag is signed by a key not in your keyring; checked nothing about the signature (docs/SECURITY.md has the key)" "$YELLOW"
  ;;
*'no signature found'* | *'cannot verify a non-tag object'*)
  # the second is a lightweight tag - a bare ref, no tag object to sign
  _hi_cecho "$me: $tag is not signed" "$YELLOW"
  ;;
*)
  # gpg absent, or an output shape this script does not know: say so, no more
  _hi_cecho "$me: could not check the signature on $tag (${sig:-no gpg?})" "$YELLOW"
  ;;
esac
[ -z "$dry_run" ] || {
  _hi_cecho "$me: dry run - would check out $tag${here:+ (now on $here)}, moving nothing" "$BLUE"
  exit 0
}
git -C "$root" checkout -q "refs/tags/$tag" || {
  _hi_cecho "$me: git checkout of $tag failed in $root (see above)" "$RED" >&2
  exit 1
}
_hi_cecho "$me: now on $tag (detached)" "$GREEN"
exit 0
