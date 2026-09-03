#!/usr/bin/env bash
# Builds the distributable packages: stage the tree with scripts/install.sh's
# packaging mode, then hand that staging root to nfpm for .deb/.rpm/.apk.
#
# Named mkpkg.sh because the obvious name is taken: .gitignore's `**build**`
# rule would silently swallow a build.sh (see the note at the top of
# .gitignore). Not to be confused with Arch's makepkg - Arch is deliberately
# not built here (below).
#
# Arch is deliberately not built here even though nfpm can: packaging/aur/ makes
# a better Arch package (real optdepends, a -git variant, AUR updates), and two
# Arch packages for one project would only conflict.

# the locator, core.sh, strict mode and the shared primitives (sha256_lines/
# default_version) all come from lib.sh, found beside this script
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

_HI_PACKAGERS=(deb rpm apk)
_HI_NFPM_CONFIG="$_HI_ROOT/packaging/nfpm/nfpm.yaml"
_HI_PKGBUILD="$_HI_ROOT/packaging/aur/say-hi/PKGBUILD"
_HI_DIST="$_HI_ROOT/dist"
_HI_STAGE_ONLY=""
_HI_VERSION=""
_HI_SRC_TARBALL=""
_HI_USAGE="Usage: mkpkg.sh [--version <x.y.z>] [--stage-only] [--outdir <dir>] [--source-tarball <file>]"

# install.sh insists on a checkout named exactly say-hi ($_HI_HOME/say-hi is how it
# finds everything). A clone directory called anything else - say-hi-main, a
# worktree, a CI checkout path - would otherwise fail here rather than in the
# packager's build, so give it the name it wants under a scratch parent.
function staged_launcher() {
  local shim
  if [ "$(basename "$_HI_ROOT")" = say-hi ]; then
    printf '%s' "$_HI_ROOT/scripts/install.sh"
    return 0
  fi
  shim="$_HI_DIST/shim"
  rm -rf "$shim"
  mkdir -p "$shim"
  ln -sfn "$_HI_ROOT" "$shim/say-hi"
  printf '%s' "$shim/say-hi/scripts/install.sh"
}

function stage_tree() {
  local installer
  installer="$(staged_launcher)"
  _hi_h2 "Staging the tree"
  rm -rf "$_HI_DIST/staging"
  mkdir -p "$_HI_DIST/staging"
  DESTDIR="$_HI_DIST/staging" "$installer" --prefix /usr/share
  # `hi --version` and `man hi`'s footer, stamped at build time by the one
  # script every channel calls - never in git, because bump.sh only runs after
  # the tag exists and a committed stamp would always be a release stale.
  # touch_epoch follows it: the man page is recompressed above, so its mtime
  # needs clamping after, not before.
  "$_HI_ROOT/packaging/stamp.sh" --root "$_HI_DIST/staging" --version "$_HI_VERSION"
  touch_epoch
}

# Clamp every staged mtime to $SOURCE_DATE_EPOCH: install_tree's cp stamps
# each file "now", which nfpm faithfully preserves into the package as the one
# run-to-run difference. Files and directories only - the staged /usr/bin/hi
# symlink points at its installed (not-yet-existing) target, and nfpm builds
# its own symlink entry from nfpm.yaml anyway. GNU touch takes -d @epoch;
# BSD/macOS needs -t with a stamp its own date -r builds (TZ pinned, -t reads
# local time) - the same dual-implementation shape as bump.sh's checksums.
function touch_epoch() {
  local stamp
  if touch -d "@$SOURCE_DATE_EPOCH" "$_HI_DIST/staging" 2>/dev/null; then
    find "$_HI_DIST/staging" \( -type f -o -type d \) \
      -exec touch -d "@$SOURCE_DATE_EPOCH" {} +
  else
    stamp="$(TZ=UTC date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)"
    find "$_HI_DIST/staging" \( -type f -o -type d \) \
      -exec env TZ=UTC touch -t "$stamp" {} +
  fi
}

function run_nfpm() {
  local packager
  need nfpm "it is a single Go binary" || {
    _hi_cecho "   go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest" "$YELLOW" >&2
    _hi_cecho "   or grab a release from https://github.com/goreleaser/nfpm/releases" "$YELLOW" >&2
    return 1
  }
  for packager in "${_HI_PACKAGERS[@]}"; do
    _hi_h2 "Building $packager"
    # cd to the tree root: nfpm.yaml's contents are relative to the config's
    # working directory, and they are written relative to the repo root
    (cd "$_HI_ROOT" && HI_VERSION="$_HI_VERSION" nfpm package \
      -f "$_HI_NFPM_CONFIG" -p "$packager" -t "$_HI_DIST")
  done
  write_checksums
}

# One artifact per packager, plus the source tarball when the caller has one,
# plus a SHA256SUMS over the lot for release users to verify downloads against.
# _HI_PACKAGERS is the single home of "what a release consists of" - the
# workflows call this rather than repeating the format list in YAML. The sums
# come from lib.sh's sha256_lines (mac fallback included).
#
# The source tarball is optional because only a release has one: it is built
# from a tag before the version is known here (bump.sh writes the pkgver this
# reads), so it arrives as a file rather than being made here. ci.yml's
# packaging smoke passes none and is unaffected, including its double-build
# reproducibility diff.
function write_checksums() {
  local packager f
  local -a built=()
  for packager in "${_HI_PACKAGERS[@]}"; do
    for f in "$_HI_DIST"/*."$packager"; do
      [ -f "$f" ] || {
        _hi_cecho " nfpm exited 0 but built no .$packager" "$RED" >&2
        return 1
      }
      built+=("${f##*/}")
    done
  done
  if [ -n "$_HI_SRC_TARBALL" ]; then
    [ -f "$_HI_SRC_TARBALL" ] || {
      _hi_cecho " no such source tarball: $_HI_SRC_TARBALL" "$RED" >&2
      return 1
    }
    # -ef rather than comparing paths: a caller who already wrote the tarball
    # into $_HI_DIST (or reached it by another route to the same file) gets a
    # no-op instead of cp's "are the same file" error
    [ "$_HI_SRC_TARBALL" -ef "$_HI_DIST/${_HI_SRC_TARBALL##*/}" ] ||
      cp -p "$_HI_SRC_TARBALL" "$_HI_DIST/${_HI_SRC_TARBALL##*/}"
    built+=("${_HI_SRC_TARBALL##*/}")
  fi
  (cd "$_HI_DIST" && sha256_lines "${built[@]}" >SHA256SUMS)
  _hi_cecho " $_HI_DIST/SHA256SUMS :)" "$GREEN"

  # ...and the same list as plain lines, which is what makes the claim above
  # true: release.yml reads this instead of respelling *.deb *.rpm *.apk in
  # YAML, so adding a packager is one edit to _HI_PACKAGERS.
  printf '%s\n' "${built[@]}" SHA256SUMS >"$_HI_DIST/ARTIFACTS"
  _hi_cecho " $_HI_DIST/ARTIFACTS :)" "$GREEN"
}

# GLOSSARY: HI.06
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

while [ $# -gt 0 ]; do
  # --x=y becomes --x y first, so each flag below is spelled once
  case "$1" in --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;; esac
  case "$1" in
  --stage-only) _HI_STAGE_ONLY=1 ;;
  --version | --outdir | --source-tarball)
    [ $# -ge 2 ] || {
      echo "mkpkg.sh: $1 requires a value" >&2
      exit 1
    }
    case "$1" in
    --version) _HI_VERSION="$2" ;;
    --outdir) _HI_DIST="$2" ;;
    --source-tarball) _HI_SRC_TARBALL="$2" ;;
    esac
    shift
    ;;
  -h | --help)
    cat <<EOF
$_HI_USAGE

Stages say-hi the way a package manager would (scripts/install.sh --prefix
/usr/share, into dist/staging) and then builds ${_HI_PACKAGERS[*]} packages
from that staging root with nfpm.

  --version <x.y.z>  Version to stamp. Defaults to the pkgver in
                     packaging/aur/say-hi/PKGBUILD, which packaging/bump.sh
                     owns - that file is the one version of record.
  --stage-only       Stop after staging. Needs no nfpm, and is the quickest
                     way to see exactly what a package would contain.
  --outdir <dir>     Where to stage and write packages. Default: dist/
  --source-tarball <file>
                     Also ship this source tarball: copied into the outdir,
                     listed in SHA256SUMS and ARTIFACTS, and so covered by the
                     release's build-provenance attestation. release.yml
                     builds it with packaging/lib.sh's src_tarball.
EOF
    exit 0
    ;;
  *)
    echo "mkpkg.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done

: "${_HI_VERSION:=$(default_version)}"

# Reproducible builds: nfpm stamps the timestamps it controls from
# $SOURCE_DATE_EPOCH, and touch_epoch clamps the staged tree's mtimes to it,
# so two runs over the same commit produce byte-identical packages. HEAD's
# commit time (on a release checkout, the tag's), respecting a caller's value
# per the reproducible-builds.org convention; with no git history the build
# still works but stamps "now", and says so.
: "${SOURCE_DATE_EPOCH:=$(git -C "$_HI_ROOT" log -1 --no-show-signature --format=%ct 2>/dev/null || true)}"
if [ -z "$SOURCE_DATE_EPOCH" ]; then
  SOURCE_DATE_EPOCH="$(date +%s)"
  _hi_cecho " no git history - SOURCE_DATE_EPOCH stamps 'now'; this build is not reproducible" "$YELLOW" >&2
fi
export SOURCE_DATE_EPOCH

_hi_h1 "Packaging say-hi $_HI_VERSION"
_hi_cecho " | root: $_HI_ROOT | outdir: $_HI_DIST" "$BLUE"

stage_tree

if [ -n "$_HI_STAGE_ONLY" ]; then
  _hi_h1 "Staged!"
  _hi_cecho " | $_HI_DIST/staging - nothing built, pass no --stage-only to build" "$BLUE"
  exit 0
fi

run_nfpm

_hi_h1 "Packaged!"
_hi_cecho " | $_HI_DIST" "$BLUE"
