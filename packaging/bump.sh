#!/bin/bash
# Sets the release version across every manifest, with real checksums, so that
# cutting a release is one command rather than four hand-edits that can
# disagree. The version of record is packaging/aur/say-hi/PKGBUILD's pkgver -
# packaging/mkpkg.sh reads it back from there.
#
# Two modes:
#   bump.sh <version>            rewrite the manifests (builds the tarball)
#   bump.sh --check <version>    verify they already say <version>, offline
#
# --check is what CI runs on a tag: the release workflow refuses to build if the
# committed manifests and the tag disagree, rather than quietly rewriting files
# nobody reviewed.
set -euo pipefail

# the locator, core.sh, and the shared primitives (sha256_of/b2_of/
# pkgbuild_version) all come from lib.sh, found beside this script
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# One overridable seam - the test suite points it at a fixture directory with
# the same layout; the three paths always derive from it.
: "${_HI_PKG_DIR:=$_HI_ROOT/packaging}"
_HI_PKGBUILD="$_HI_PKG_DIR/aur/say-hi/PKGBUILD"
_HI_SRCINFO="$_HI_PKG_DIR/aur/say-hi/.SRCINFO"
_HI_FORMULA="$_HI_PKG_DIR/homebrew/say-hi.rb"
_HI_REPO_URL="https://github.com/ivylikethevine/say-hi"
# what a manifest reads before any release has been cut; --check rejects both
_HI_PLACEHOLDER_SHA="0000000000000000000000000000000000000000000000000000000000000000"
_HI_USAGE="Usage: bump.sh [--check] [--tarball <file>] <version>"

# The source tarball's release-asset URL. Both channels build from this rather
# than from GitHub's /archive/ tarball: the asset is one this release built, so
# it is in SHA256SUMS and under the build-provenance attestation, which the
# auto-generated archive never was. The filename is $pkgname-$pkgver.tar.gz, so
# the AUR source= needs no `::` rename to get the name prepare() expects.
function asset_url() {
  printf '%s/releases/download/v%s/say-hi-%s.tar.gz' "$_HI_REPO_URL" "$1" "$1"
}

# One verify-and-report row of --check: <ok-msg> <fail-msg> <predicate...>.
# Green ":)" or red plus bad=1 - `bad` is check_manifests' local, reached
# through bash's dynamic scoping, which is what replaces seven copies of the
# same if/else plumbing.
function _hi_manifest_check() {
  local ok_msg="$1" bad_msg="$2"
  shift 2
  if "$@"; then
    _hi_cecho " $ok_msg :)" "$GREEN"
  else
    _hi_cecho " $bad_msg" "$RED"
    bad=1
  fi
}

# a checksum field carrying an actual sum, not its pre-release sentinel
# ($2: SKIP for the PKGBUILD, the zero-sha placeholder for the formula)
function _hi_real_sum() {
  [ -n "$1" ] && [ "$1" != "$2" ]
}

function _hi_nonempty_match() {
  [ -n "$1" ] && [ "$1" = "$2" ]
}

function check_manifests() {
  local bad=0 pkgver sha b2 srcinfo_b2
  _hi_h2 "Checking the manifests say $_HI_VERSION"

  # errors (a PKGBUILD with no pkgver line) become an empty string here, so
  # they read as a red mismatch row rather than a set -e abort
  pkgver="$(pkgbuild_version 2>/dev/null || true)"
  b2="$(sed -n "s/^b2sums=('\\(.*\\)')/\\1/p" "$_HI_PKGBUILD" | head -1)"
  sha="$(sed -n 's/^  sha256 "\(.*\)"/\1/p' "$_HI_FORMULA" | head -1)"
  # the AUR consumes .SRCINFO, not the PKGBUILD, so its b2sums/source lines
  # are checked too - pkgver alone lets a stale checksum through
  srcinfo_b2="$(sed -n 's/^[[:space:]]*b2sums = //p' "$_HI_SRCINFO" | head -1)"

  _hi_manifest_check "PKGBUILD pkgver=$pkgver" \
    "PKGBUILD pkgver=$pkgver, expected $_HI_VERSION" \
    [ "$pkgver" = "$_HI_VERSION" ]
  _hi_manifest_check "PKGBUILD b2sums is a real sum" \
    "PKGBUILD b2sums is still SKIP - run bump.sh $_HI_VERSION" \
    _hi_real_sum "$b2" SKIP
  _hi_manifest_check "formula url points at the v$_HI_VERSION release asset" \
    "formula url does not point at the v$_HI_VERSION release asset" \
    grep -qF "$(asset_url "$_HI_VERSION")" "$_HI_FORMULA"
  _hi_manifest_check "formula sha256 is a real sum" \
    "formula sha256 is still the placeholder - run bump.sh $_HI_VERSION" \
    _hi_real_sum "$sha" "$_HI_PLACEHOLDER_SHA"
  _hi_manifest_check ".SRCINFO pkgver=$_HI_VERSION" \
    ".SRCINFO is stale - regenerate with makepkg --printsrcinfo" \
    grep -qF "pkgver = $_HI_VERSION" "$_HI_SRCINFO"
  _hi_manifest_check ".SRCINFO b2sums matches the PKGBUILD's" \
    ".SRCINFO b2sums does not match the PKGBUILD's - regenerate it" \
    _hi_nonempty_match "$b2" "$srcinfo_b2"
  _hi_manifest_check ".SRCINFO source points at the v$_HI_VERSION release asset" \
    ".SRCINFO source does not point at the v$_HI_VERSION release asset" \
    grep -qF "$(asset_url "$_HI_VERSION")" "$_HI_SRCINFO"

  return "$bad"
}

# write_manifests [tarball] - with a tarball argument, checksum that file: what
# the release passes, since it builds the asset itself and must sum the exact
# bytes it is about to upload. Without one, build the same shape from the local
# tag, and fall back to downloading the published asset only if there is no such
# tag here. Downloading can never be the first choice any more: on a fresh tag
# the asset does not exist until publish, so a fetch-first order would deadlock
# at exactly the moment a release runs.
function write_manifests() {
  local url tarball="${1:-}" sha b2
  if [ -n "$tarball" ]; then
    _hi_h2 "Using the local tarball $tarball"
    [ -f "$tarball" ] || {
      _hi_cecho " no such file: $tarball" "$RED" >&2
      return 1
    }
  else
    tarball="$(mktemp -t hi.tarball.XXXXXX)"
    _hi_on_exit "rm -f '$tarball'"
    if git -C "$_HI_ROOT" rev-parse -q --verify "refs/tags/v$_HI_VERSION" >/dev/null 2>&1; then
      _hi_h2 "Building the source tarball from refs/tags/v$_HI_VERSION"
      src_tarball "$_HI_VERSION" "v$_HI_VERSION" "$tarball" || {
        _hi_cecho " git archive failed" "$RED" >&2
        return 1
      }
    else
      url="$(asset_url "$_HI_VERSION")"
      _hi_h2 "No local v$_HI_VERSION tag - fetching $url"
      curl -fsSL -o "$tarball" "$url" || {
        _hi_cecho " could not fetch it - has v$_HI_VERSION been released, or is its tag in this checkout?" "$RED" >&2
        return 1
      }
    fi
  fi
  # both sums from the same bytes, so the two channels can never disagree about
  # what they are checksumming
  sha="$(sha256_of "$tarball")"
  b2="$(b2_of "$tarball")"
  _hi_cecho " sha256 $sha" "$BLUE"
  _hi_cecho " b2     $b2" "$BLUE"

  _hi_h2 "Writing the manifests"
  _hi_rewrite "$_HI_PKGBUILD" \
    "s/^pkgver=.*/pkgver=$_HI_VERSION/" \
    "s/^b2sums=.*/b2sums=('$b2')/"
  _hi_cecho " $_HI_PKGBUILD :)" "$GREEN"

  _hi_rewrite "$_HI_FORMULA" \
    "s|^  url \".*\"|  url \"$(asset_url "$_HI_VERSION")\"|" \
    "s/^  sha256 \".*\"/  sha256 \"$sha\"/"
  _hi_cecho " $_HI_FORMULA :)" "$GREEN"

  if command -v makepkg >/dev/null 2>&1; then
    (cd "$(dirname "$_HI_PKGBUILD")" && makepkg --printsrcinfo >.SRCINFO)
    _hi_cecho " $_HI_SRCINFO :)" "$GREEN"
  else
    rewrite_srcinfo_lines "$b2"
    _hi_cecho " $_HI_SRCINFO (pkgver/source/b2sums only - rerun makepkg --printsrcinfo on an Arch box if any other PKGBUILD field changed)" "$YELLOW"
  fi
}

# The no-makepkg fallback (any non-Arch box, incl. the ubuntu release runner):
# the three lines a bump changes are derivable, so rewrite them in place. The
# \([[:space:]]*\) capture keeps .SRCINFO's leading tab.
function rewrite_srcinfo_lines() {
  local b2="$1"
  _hi_rewrite "$_HI_SRCINFO" \
    "s/^\\([[:space:]]*\\)pkgver = .*/\\1pkgver = $_HI_VERSION/" \
    "s|^\\([[:space:]]*\\)source = .*|\\1source = $(asset_url "$_HI_VERSION")|" \
    "s/^\\([[:space:]]*\\)b2sums = .*/\\1b2sums = $b2/"
}

# GLOSSARY: HI.06
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_HI_CHECK_ONLY=""
_HI_TARBALL=""
while [ $# -gt 0 ]; do
  case "$1" in
  --check) _HI_CHECK_ONLY=1 ;;
  --tarball)
    [ $# -ge 2 ] || {
      echo "bump.sh: --tarball requires a path" >&2
      exit 1
    }
    _HI_TARBALL="$2"
    shift
    ;;
  --tarball=*) _HI_TARBALL="${1#--tarball=}" ;;
  -h | --help)
    cat <<EOF
$_HI_USAGE

Writes <version> (no leading v) into packaging/aur/say-hi/PKGBUILD, its
.SRCINFO, and packaging/homebrew/say-hi.rb, along with the b2sum and sha256 of
the source tarball that release ships - built here from the v<version> tag with
git archive, which is the same artifact release.yml attaches, checksums into
SHA256SUMS and attests over.

  --check            Verify the manifests already agree on <version> and
                     carry real checksums, then exit non-zero if not.
                     Touches nothing and needs no network. This is the
                     release workflow's gate.
  --tarball <file>   Checksum this exact file instead of building one. This
                     is what release.yml passes: it builds the asset once and
                     sums the same bytes it uploads. With no local v<version>
                     tag and no --tarball, the published asset is downloaded
                     instead.

packaging/aur/say-hi-git/ is untouched: its pkgver() derives from the branch.
EOF
    exit 0
    ;;
  -*)
    echo "bump.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  *) _HI_VERSION="$1" ;;
  esac
  shift
done

[ -n "${_HI_VERSION:-}" ] || {
  echo "bump.sh: a version is required" >&2
  echo "$_HI_USAGE" >&2
  exit 1
}
# v-prefixes belong on the tag, not in pkgver/sha256 lookups; accept either
_HI_VERSION="${_HI_VERSION#v}"

if [ -n "$_HI_CHECK_ONLY" ]; then
  _hi_h1 "Checking manifests for $_HI_VERSION"
  if check_manifests; then
    _hi_h1 "Manifests agree!"
    exit 0
  fi
  _hi_h1 "Manifests disagree" "$RED"
  exit 1
fi

_hi_h1 "Bumping say-hi to $_HI_VERSION"
write_manifests "$_HI_TARBALL"
_hi_h1 "Bumped!"
_hi_cecho " | review the diff, commit it - the release workflow re-derives and verifies the same sums from the tag" "$BLUE"
