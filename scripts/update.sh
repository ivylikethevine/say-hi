#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --update`: move the say-hi checkout this hi runs from to a release tag.
#
# Here and not in hi.sh, for the reason common/core.sh states about
# scripts/lib.sh - hi.sh ships in the ssh payload under a size budget, and
# this is the one subcommand that cannot succeed anywhere the payload copy is
# what is running: a disposable tree is /tmp/<x>/say-hi with no .git, and
# that is what every session runs, even on a target with a say-hi of its own.
# It goes through
# _hi_dispatch_subcommand like every other subcommand.
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
# shellcheck source=lib.sh
source "$_hi_d/scripts/lib.sh"

# Strict mode for the rest of this script: core.sh (sourced above) ends with
# `set +euo pipefail`, so a `set` line placed before it is silently undone.
# packaging/lib.sh does the same. GLOSSARY: HI.15
set -euo pipefail

# the script's own usage line names what was typed, the way doctor.sh does
me="${_HI_ARGV0:-hi --update}" _HI_ME="${_HI_ARGV0:-hi --update}"
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
[ -d "$root/.git" ] || _hi_die "no .git in $_HI_ROOT - a packaged install updates through its package manager (apt/dnf/apk upgrade say-hi, or brew upgrade say-hi); a tarball install unpacks the next release from https://github.com/ivylikethevine/say-hi/releases over this one; a hi session updates on the machine say-hi lives on"
case "${1:-}" in
-*)
  _hi_die "unknown option $1 (one release tag, or nothing for the newest)"
  ;;
esac
[ $# -le 1 ] || _hi_die "one release tag at most ($*)"
tag="${1:-}"
dirty="$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)"
[ -z "$dirty" ] || _hi_die "uncommitted changes in $root; commit or stash them first"
git -C "$root" fetch --tags --quiet || _hi_die "git fetch failed in $root (see above)"
if [ -z "$tag" ]; then
  # newest release by version (v0.0.10 above v0.0.9); a pre-release
  # (v1.0.0-rc.1) is never chosen unasked - name it to move there. No match is
  # not a pipeline failure: grep -v exits 1 on an empty list, and the check
  # right below is what answers that, not `set -e`.
  tag="$(git -C "$root" tag --list 'v*' --sort=-v:refname | grep -v -- - | head -n 1)" || true
  [ -n "$tag" ] || _hi_die "no release tags in $root"
elif ! git -C "$root" show-ref --verify -q "refs/tags/$tag"; then
  _hi_die "no release tag named $tag; git -C $root tag lists them"
fi
here="$(exec git -C "$root" describe --tags --exact-match 2>/dev/null)" || here=""
if [ "$here" = "$tag" ]; then
  _hi_cecho "$me: already on $tag" "$GREEN"
  exit 0
fi
# The tag's signature, read off gpg's status lines rather than verify-tag's
# exit code, which is 1 for "bad", "unsigned", and "signed by a key you have not
# imported" alike. Only a bad signature refuses: an unsigned tag is what a
# fork or a mirror has, and a missing key is most first installs - both are
# said out loud and allowed, so the check never strands an update that plain
# git would have made.
#
# An ssh-signed tag (every release) is not checked at all without an
# allowed-signers file, so one is always named: this checkout's own
# .github/allowed_signers - the copy already trusted, not the tag's - else
# git config's, else an empty one, which still catches a tampered signature.
signers="$root/.github/allowed_signers"
[ -f "$signers" ] || signers="$(exec git -C "$root" config --path --get gpg.ssh.allowedSignersFile)" || signers=""
sig="$(git -C "$root" -c gpg.ssh.allowedSignersFile="$signers" verify-tag --raw "refs/tags/$tag" 2>&1)" || true
case "$sig" in
*'[GNUPG:] BADSIG'* | *'[GNUPG:] REVKEYSIG'* | *'Signature verification failed'*)
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
  # an ssh-signed tag the allowed-signers file vouches for
  signer="${sig#*Good \"git\" signature for }"
  signer="${signer%% with*}"
  _hi_cecho "$me: $tag has a good ssh signature from $signer" "$GREEN"
  ;;
*'Good "git" signature with '*)
  # intact, but from a key no allowed signer names: the ssh twin of NO_PUBKEY
  _hi_cecho "$me: $tag is signed by a key not in the allowed signers; checked nothing about who signed it" "$YELLOW"
  ;;
*'[GNUPG:] NO_PUBKEY'* | *'[GNUPG:] ERRSIG'*)
  _hi_cecho "$me: $tag is signed by a key not in your keyring; checked nothing about the signature" "$YELLOW"
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
git -C "$root" checkout -q "refs/tags/$tag" || _hi_die "git checkout of $tag failed in $root (see above)"
_hi_cecho "$me: now on $tag (detached)" "$GREEN"
# the checked-out tag's converter, which knows every format that tag reads
[ ! -f "$root/scripts/convert_settings.sh" ] ||
  _HI_HOME="${root%/*}" bash "$root/scripts/convert_settings.sh" || true
exit 0
