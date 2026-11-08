#!/usr/bin/env bash
# `hi --update`: move the say-hi checkout this hi runs from to a release tag,
# or, on the dev branch, fast-forward it to the remote's dev.
#
# Not in hi.sh, which rides under a size budget, and a session's tree has no
# .git anyway.
#
# SC2317/SC2329: shellcheck follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"` and misses its BASH_SOURCE guard (as in doctor.sh).
# shellcheck disable=SC2317,SC2329

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
[ -z "${_HI_ROOT:-}" ] || [ "${_HI_ROOT%/*}" != "${_HI_HOME:-${_HI_ROOT%/*}}" ] || _hi_d="$_HI_ROOT"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=lib.sh
source "$_hi_d/scripts/lib.sh"

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

# the script's own usage line names what was typed, the way doctor.sh does
_HI_ME="${_HI_ARGV0:-hi --update}"
root="$_HI_ROOT" tag="" dirty="" here="" branch="" behind="" ahead=""

function _hi_update_help() {
  cat <<EOF
Usage: $_HI_ME [<tag>] [--dry-run]

Moves the say-hi checkout this hi runs from to a release tag (needs its
.git; a package has none, so it says so and stops):
$_HI_ME           the newest release tag, after fetching them
$_HI_ME <tag>     that release

Either way the checkout is left detached on the tag. On the dev branch,
$_HI_ME with no tag fast-forwards dev to its upstream instead (git pull
--ff-only), and refuses a dev that has diverged. A tree with uncommitted
changes is refused. \`git -C $root tag\` lists the releases.

  -n, --dry-run    Fetch, and say which tag would be checked out or how
                   many commits a pull would bring, moving nothing.
EOF
}
# --help and --dry-run anywhere on the line, and ahead of the .git check so a
# package gets the help text too; what is left is the tag, if any
_HI_DRY_RUN="" args=()
_hi_args _hi_update_help "one release tag, or nothing for the newest" "$@"
set -- ${args[@]+"${args[@]}"}
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

# _hi_update_convert - the checked-out tree's converter, which knows every
# format that tree reads
function _hi_update_convert() {
  [ ! -f "$root/scripts/convert_settings.sh" ] ||
    _HI_ROOT="$root" _HI_HOME="${root%/*}" bash "$root/scripts/convert_settings.sh" || true
}

# On dev, no tag named: follow the branch, fast-forward only
branch="$(exec git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null)" || branch=""
if [ "$branch" = dev ] && [ -z "${1:-}" ]; then
  git -C "$root" rev-parse -q --verify '@{u}' >/dev/null 2>&1 ||
    _hi_die "dev in $root has no upstream; git -C $root branch --set-upstream-to=origin/dev dev"
  git -C "$root" fetch --quiet || _hi_die "git fetch failed in $root (see above)"
  read -r behind ahead < <(git -C "$root" rev-list --left-right --count '@{u}...HEAD')
  [ "$ahead" = 0 ] || [ "$behind" = 0 ] ||
    _hi_die "dev in $root has diverged from its upstream ($ahead ahead, $behind behind); rebase or reset it by hand"
  if [ "$behind" = 0 ]; then
    _hi_cecho "$_HI_ME: dev is up to date" "$GREEN"
    exit 0
  fi
  [ -z "$_HI_DRY_RUN" ] || {
    _hi_cecho "$_HI_ME: dry run - would pull $behind commit(s) into dev, moving nothing" "$BLUE"
    exit 0
  }
  git -C "$root" merge --ff-only --quiet '@{u}' || _hi_die "fast-forward of dev failed in $root (see above)"
  _hi_cecho "$_HI_ME: dev is now at $(_hi_git_version "$root") ($behind new commit(s))" "$GREEN"
  _hi_update_convert
  exit 0
fi
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
  _hi_cecho "$_HI_ME: already on $tag" "$GREEN"
  exit 0
fi
# The tag's signature, from gpg's status lines (verify-tag's exit code is 1
# for bad, unsigned, and unknown key alike). Only a key this checkout already
# trusts moves it; a bad signature always refuses; unsigned, unknown, or no
# gpg refuses unless $_HI_UPDATE_UNSIGNED=1. git skips ssh signatures with no
# allowed-signers file, so one is always named: this checkout's own (not the
# tag's), else git config's, else an empty one.
verified=""
signers="$root/.github/allowed_signers"
[ -f "$signers" ] || signers="$(exec git -C "$root" config --path --get gpg.ssh.allowedSignersFile)" || signers=""
sig="$(git -C "$root" -c gpg.ssh.allowedSignersFile="$signers" verify-tag --raw "refs/tags/$tag" 2>&1)" || true
case "$sig" in
*'[GNUPG:] BADSIG'* | *'[GNUPG:] REVKEYSIG'* | *'Signature verification failed'*)
  _hi_cecho "$_HI_ME: the signature on $tag does not verify - refusing to check it out" "$RED" >&2
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
  _hi_cecho "$_HI_ME: $tag has a good signature from $signer" "$GREEN"
  verified=1
  ;;
*'Good "git" signature for '*)
  # an ssh-signed tag the allowed-signers file vouches for
  signer="${sig#*Good \"git\" signature for }"
  signer="${signer%% with*}"
  _hi_cecho "$_HI_ME: $tag has a good ssh signature from $signer" "$GREEN"
  verified=1
  ;;
*'Good "git" signature with '*)
  # intact, but from a key no allowed signer names: the ssh twin of NO_PUBKEY
  _hi_cecho "$_HI_ME: $tag is signed by a key not in the allowed signers; checked nothing about who signed it" "$YELLOW"
  ;;
*'[GNUPG:] NO_PUBKEY'* | *'[GNUPG:] ERRSIG'*)
  _hi_cecho "$_HI_ME: $tag is signed by a key not in your keyring; checked nothing about the signature" "$YELLOW"
  ;;
*'no signature found'* | *'cannot verify a non-tag object'*)
  # the second is a lightweight tag - a bare ref, no tag object to sign
  _hi_cecho "$_HI_ME: $tag is not signed" "$YELLOW"
  ;;
*)
  # gpg absent, or an output shape this script does not know: say so, no more
  _hi_cecho "$_HI_ME: could not check the signature on $tag (${sig:-no gpg?})" "$YELLOW"
  ;;
esac
[ "${_HI_UPDATE_UNSIGNED:-0}" = 1 ] || [ -n "$verified" ] ||
  _hi_die "$tag has no signature this checkout can vouch for - refusing to check it out (_HI_UPDATE_UNSIGNED=1 takes it anyway)"
[ -z "$_HI_DRY_RUN" ] || {
  _hi_cecho "$_HI_ME: dry run - would check out $tag${here:+ (now on $here)}, moving nothing" "$BLUE"
  exit 0
}
git -C "$root" checkout -q "refs/tags/$tag" || _hi_die "git checkout of $tag failed in $root (see above)"
_hi_cecho "$_HI_ME: now on $tag (detached)" "$GREEN"
_hi_update_convert
exit 0
