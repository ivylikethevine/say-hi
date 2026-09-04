#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The one implementation of `hi --version`'s build-time stamp, called by every
# channel: mkpkg.sh (deb/rpm/apk), both PKGBUILDs, and the Homebrew formula.
#
# The stamp cannot live in git. packaging/bump.sh's manifest pass only runs
# after the tag exists, so a committed _HI_RELEASE= would always be one release
# stale in the very tarball the tag produces. Each channel therefore seds it
# into the copy it installs, and they all call this rather than spelling that
# sed out four times with nothing but greps holding the four together.
#
# Standalone on purpose: it sources no packaging/lib.sh. lib.sh derives
# $_HI_HOME as <script>/../.. and then sources $_HI_HOME/say-hi/common/core.sh,
# which needs the checkout to be named exactly say-hi. That holds for mkpkg and
# both PKGBUILDs (the AUR recipe symlinks $srcdir/say-hi in prepare()), but
# Homebrew unpacks to say-hi-<version>, where sourcing lib.sh would abort before
# this script ran. The `rewrite` below is scripts/lib.sh's _hi_rewrite, copied for that
# reason - the same boundary that makes this script carry its own locator.
set -euo pipefail

_HI_USAGE="Usage: stamp.sh --version <v> [--date <YYYY-MM-DD>] [--root <dir>]
                [--launcher <file>] [--man <file>]

Writes the version into the launcher's _HI_RELEASE= line and the man page's
.TH line. --root names a tree laid out the way scripts/install.sh --prefix
lays one out (mkpkg's staging, a PKGBUILD's \$pkgdir); --launcher and --man
name the two files directly, which is what a Homebrew keg needs since its
two targets are unrelated paths. The date is \$SOURCE_DATE_EPOCH's day unless
--date says otherwise."

_HI_VERSION=""
_HI_DATE=""
_HI_ROOT_DIR=""
_HI_LAUNCHER_FILE=""
_HI_MAN_FILE=""

while [ $# -gt 0 ]; do
  # --x=y becomes --x y first, so each flag below is spelled once
  case "$1" in --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;; esac
  case "$1" in
  -h | --help)
    echo "$_HI_USAGE"
    exit 0
    ;;
  --version | --date | --root | --launcher | --man)
    # one guard for every value flag: typed with its value left off, a flag
    # would otherwise silently eat the *next* flag
    [ $# -ge 2 ] || {
      echo "stamp.sh: $1 requires a value" >&2
      exit 1
    }
    case "$1" in
    --version) _HI_VERSION="$2" ;;
    --date) _HI_DATE="$2" ;;
    --root) _HI_ROOT_DIR="$2" ;;
    --launcher) _HI_LAUNCHER_FILE="$2" ;;
    --man) _HI_MAN_FILE="$2" ;;
    esac
    shift
    ;;
  *)
    echo "stamp.sh: unknown argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done

[ -n "$_HI_VERSION" ] || {
  echo "stamp.sh: --version is required" >&2
  exit 1
}

# --root fills in whichever of the two targets was not named explicitly, so a
# channel can take the layout wholesale or point at one file and not the other
if [ -n "$_HI_ROOT_DIR" ]; then
  [ -n "$_HI_LAUNCHER_FILE" ] || _HI_LAUNCHER_FILE="$_HI_ROOT_DIR/usr/share/say-hi/hi.sh"
  [ -n "$_HI_MAN_FILE" ] || _HI_MAN_FILE="$_HI_ROOT_DIR/usr/share/man/man1/hi.1"
fi
[ -n "$_HI_LAUNCHER_FILE" ] || {
  echo "stamp.sh: nothing to stamp - pass --root or --launcher" >&2
  exit 1
}

# No `date +%F` fallback. A silent "today" is exactly the irreproducible build
# $SOURCE_DATE_EPOCH exists to prevent, so a channel with neither must say
# which date it means (the Homebrew formula passes --date, having no epoch).
if [ -z "$_HI_DATE" ]; then
  [ -n "${SOURCE_DATE_EPOCH:-}" ] || {
    echo "stamp.sh: no --date and no \$SOURCE_DATE_EPOCH - refusing to guess" >&2
    exit 1
  }
  # GNU -d first, BSD -r second, the dual shape mkpkg.sh's touch_epoch uses
  _HI_DATE="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d 2>/dev/null ||
    date -u -r "$SOURCE_DATE_EPOCH" +%Y-%m-%d)"
fi

# rewrite <file> <sed-expr>... - a copy of scripts/lib.sh's _hi_rewrite, and
# the copy has to exist: this script sources nothing (see the header). A temp
# file rather than
# `sed -i` (whose in-place flag differs BSD/GNU), written back with cat, not mv
# - mv would put mktemp's 0600 on the target, losing the launcher's exec bit.
function rewrite() {
  local file="$1" e tmp
  shift
  local -a exprs=()
  for e in "$@"; do exprs+=(-e "$e"); done
  tmp="$(mktemp -t hi.stamp.XXXXXX)"
  sed "${exprs[@]}" "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# A bare sed per channel makes a renamed line a silent no-op - which is how
# say-hi-git can ship answering "unknown (no stamp, no git)". Counting the
# matches first turns that into a build failure.
function require_one_match() {
  local file="$1" pattern="$2" n
  n="$(grep -c "$pattern" "$file" || true)"
  [ "$n" = 1 ] || {
    echo "stamp.sh: expected exactly one /$pattern/ in $file, found $n" >&2
    exit 1
  }
}

[ -f "$_HI_LAUNCHER_FILE" ] || {
  echo "stamp.sh: no launcher at $_HI_LAUNCHER_FILE" >&2
  exit 1
}
require_one_match "$_HI_LAUNCHER_FILE" '^_HI_RELEASE='
rewrite "$_HI_LAUNCHER_FILE" "s/^_HI_RELEASE=.*/_HI_RELEASE=\"$_HI_VERSION\"/"

# The man page is a soft skip when absent: install_tree leaves it out on a host
# with no gzip. Present but unstampable is still an error.
if [ -n "$_HI_MAN_FILE" ]; then
  _hi_page="${_HI_MAN_FILE%.gz}"
  _hi_gz=""
  [ -f "$_hi_page.gz" ] && _hi_gz="$_hi_page.gz"

  if [ -n "$_hi_gz" ] || [ -f "$_hi_page" ]; then
    # -9n, and no timestamp in the member header, so a re-run reproduces the
    # same bytes; mkpkg's touch_epoch clamps the mtime afterwards
    [ -n "$_hi_gz" ] && gzip -d "$_hi_gz"
    require_one_match "$_hi_page" '^\.TH '
    rewrite "$_hi_page" \
      "s/^\.TH .*/.TH HI 1 \"$_HI_DATE\" \"say-hi $_HI_VERSION\" \"User Commands\"/"
    [ -n "$_hi_gz" ] && gzip -9n "$_hi_page"
  fi
fi

exit 0
