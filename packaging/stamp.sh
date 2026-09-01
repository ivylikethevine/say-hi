#!/usr/bin/env bash
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

# Five flags took a value and each spelled the same guard out: without one, a
# flag typed with its value left off silently eats the *next* flag. One table
# instead, mapping flag -> variable and the noun its error says; `eval` to
# assign through a name is the bash-3.2-safe form (no namerefs).
_HI_OPTS='--version:_HI_VERSION:a value
--date:_HI_DATE:a value
--root:_HI_ROOT_DIR:a path
--launcher:_HI_LAUNCHER_FILE:a path
--man:_HI_MAN_FILE:a path'

while [ $# -gt 0 ]; do
  _hi_opt=""
  case "$1" in
  -h | --help)
    echo "$_HI_USAGE"
    exit 0
    ;;
  *)
    # The table is the list of flags that take a value, so their names are
    # spelled there and nowhere else - a `case` arm repeating them is the
    # second home that goes stale. A literal prefix match, not `grep "^$1:"`:
    # that reads the argument as a regex (`--.*` would match a real row) and
    # costs a fork besides.
    while IFS= read -r _hi_row; do
      case "$_hi_row" in "$1":*)
        _hi_opt="$_hi_row"
        break
        ;;
      esac
    done <<EOF
$_HI_OPTS
EOF
    [ -n "$_hi_opt" ] || {
      echo "stamp.sh: unknown argument: $1" >&2
      echo "$_HI_USAGE" >&2
      exit 1
    }
    _hi_var="${_hi_opt#*:}"
    _hi_noun="${_hi_var#*:}"
    _hi_var="${_hi_var%%:*}"
    [ $# -ge 2 ] || {
      echo "stamp.sh: $1 requires $_hi_noun" >&2
      exit 1
    }
    eval "$_hi_var=\$2"
    shift
    ;;
  esac
  shift
done
unset _hi_opt _hi_row _hi_var _hi_noun

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
