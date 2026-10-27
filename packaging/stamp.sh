#!/usr/bin/env bash
# The one implementation of `hi --version`'s build-time stamp, called by every
# channel: mkpkg.sh (deb/rpm/apk), both PKGBUILDs, and the Homebrew formula.
#
# The stamp cannot live in git. packaging/bump.sh's manifest pass only runs
# after the tag exists, so a committed _HI_RELEASE= would always be one release
# stale in the very tarball the tag produces. Each channel therefore seds it
# into the copy it installs, and they all call this rather than spelling that
# sed out four times with nothing but greps holding the four together.

# the locator, core.sh, strict mode, and _hi_rewrite all come from lib.sh,
# found beside this script
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
_HI_ME=stamp.sh

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    echo "$_HI_USAGE"
    exit 0
    ;;
  --version | --version=*) _hi_flag_word_or_die _HI_VERSION "--version requires a value" "$@" || shift ;;
  --date | --date=*) _hi_flag_word_or_die _HI_DATE "--date requires a value" "$@" || shift ;;
  --root | --root=*) _hi_flag_word_or_die _HI_ROOT_DIR "--root requires a value" "$@" || shift ;;
  --launcher | --launcher=*) _hi_flag_word_or_die _HI_LAUNCHER_FILE "--launcher requires a value" "$@" || shift ;;
  --man | --man=*) _hi_flag_word_or_die _HI_MAN_FILE "--man requires a value" "$@" || shift ;;
  *)
    echo "stamp.sh: unknown argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done

[ -n "$_HI_VERSION" ] || _hi_die "--version is required"

# --root fills in whichever of the two targets was not named explicitly, so a
# channel can take the layout wholesale or point at one file and not the other
if [ -n "$_HI_ROOT_DIR" ]; then
  [ -n "$_HI_LAUNCHER_FILE" ] || _HI_LAUNCHER_FILE="$_HI_ROOT_DIR/usr/share/say-hi/hi.sh"
  [ -n "$_HI_MAN_FILE" ] || _HI_MAN_FILE="$_HI_ROOT_DIR/usr/share/man/man1/hi.1"
fi
[ -n "$_HI_LAUNCHER_FILE" ] || _hi_die "nothing to stamp - pass --root or --launcher"

# No `date +%F` fallback. A silent "today" is exactly the irreproducible build
# $SOURCE_DATE_EPOCH exists to prevent, so a channel with neither must say
# which date it means (the Homebrew formula passes --date, having no epoch).
if [ -z "$_HI_DATE" ]; then
  [ -n "${SOURCE_DATE_EPOCH:-}" ] || _hi_die "no --date and no \$SOURCE_DATE_EPOCH - refusing to guess"
  # GNU -d first, BSD -r second, the dual shape packaging/lib.sh's touch_epoch uses
  _HI_DATE="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d 2>/dev/null ||
    date -u -r "$SOURCE_DATE_EPOCH" +%Y-%m-%d)"
fi

# A bare sed per channel makes a renamed line a silent no-op - which is how
# say-hi-git can ship answering "unknown (no stamp, no git)". Counting the
# matches first turns that into a build failure.
function require_one_match() {
  local file="$1" pattern="$2" n
  n="$(grep -c "$pattern" "$file" || true)"
  [ "$n" = 1 ] || _hi_die "expected exactly one /$pattern/ in $file, found $n"
}

[ -f "$_HI_LAUNCHER_FILE" ] || _hi_die "no launcher at $_HI_LAUNCHER_FILE"
require_one_match "$_HI_LAUNCHER_FILE" '^_HI_RELEASE='
_hi_rewrite "$_HI_LAUNCHER_FILE" "s/^_HI_RELEASE=.*/_HI_RELEASE=\"$_HI_VERSION\"/"

# The man page is a soft skip when absent: install_tree leaves it out on a host
# with no gzip. Present but unstampable is still an error.
if [ -n "$_HI_MAN_FILE" ]; then
  _hi_page="${_HI_MAN_FILE%.gz}"
  _hi_gz=""
  [ -f "$_hi_page.gz" ] && _hi_gz="$_hi_page.gz"

  if [ -n "$_hi_gz" ] || [ -f "$_hi_page" ]; then
    # -9n, and no timestamp in the member header, so a re-run reproduces the
    # same bytes; mkpkg's touch_epoch clamps the mtime afterwards. -f
    # tolerates a decompressed file left over from an interrupted prior run -
    # gzip -d otherwise refuses to overwrite one.
    [ -n "$_hi_gz" ] && gzip -df "$_hi_gz"
    require_one_match "$_hi_page" '^\.TH '
    _hi_rewrite "$_hi_page" \
      "s/^\.TH .*/.TH HI 1 \"$_HI_DATE\" \"say-hi $_HI_VERSION\" \"User Commands\"/"
    # Caught here, with the actual line, rather than downstream (a package
    # build, or tests/packaging's own read of the staged .gz) discovering a
    # .TH that silently came out wrong - a platform's sed or its quoting of
    # $_HI_DATE/$_HI_VERSION is the kind of thing that can misbehave quietly.
    _hi_th="$(grep '^\.TH ' "$_hi_page")"
    case "$_hi_th" in
    ".TH HI 1 \"$_HI_DATE\" \"say-hi $_HI_VERSION\" "*) ;;
    *) _hi_die "the man page's .TH line came out wrong: $_hi_th" ;;
    esac
    # Streamed through -c, like install_tree's own gzip call, rather than
    # named on the command line: given a filename, OpenBSD's gzip refuses a
    # recompression that would grow the file - even with -f - and exits 2,
    # leaving no .gz behind. A stdout stream has no file for it to protect.
    if [ -n "$_hi_gz" ]; then
      gzip -9n <"$_hi_page" >"$_hi_gz"
      rm -f "$_hi_page"
    fi
  fi
fi

exit 0
