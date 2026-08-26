#!/usr/bin/env bash
# The devcontainer Feature's install script: say-hi *inside* the container.
#
# Every other channel packages say-hi for a machine you own. This one is for a
# machine that is rebuilt from a Dockerfile every morning, where there is no
# client to say `hi` from - the terminal VS Code or Codespaces opens is already
# on the target. So this installs the tree and then wires the remote user's own
# shell to it, which is the half `install.sh --prefix` deliberately does not do.
#
# Run by the devcontainer CLI as root at image-build time, with the Feature's
# options in the environment as VERSION / PRESET / CONFIGURESHELL (the spec
# upper-cases each option id) and the container's user in _REMOTE_USER.
#
# It is deliberately thin. What a packaged install *contains* is
# scripts/install.sh's `_HI_PACKAGE_CONTENTS` and `install_tree`, exactly as it
# is for the AUR, deb, rpm and apk - this file downloads a release, checks it,
# and hands over. tests/packaging/packaging_test.sh fails if it grows a private
# copy of that decision.
set -euo pipefail

VERSION="${VERSION:-latest}"
PRESET="${PRESET:-everything}"
CONFIGURESHELL="${CONFIGURESHELL:-true}"
USERNAME="${_REMOTE_USER:-root}"

REPO="ivylikethevine/say-hi"
PREFIX="/usr/share"

say() { printf 'say-hi: %s\n' "$*"; }
die() {
  printf 'say-hi: %s\n' "$*" >&2
  exit 1
}

# curl or wget, whichever the base image brought. Neither is universal - the
# mcr devcontainer images ship curl, a bare debian:slim ships neither - so this
# says which one it wants rather than failing on a missing binary three lines
# later.
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
else
  die "needs curl or wget in the base image (the devcontainers common-utils feature installs one)"
fi
command -v tar >/dev/null 2>&1 || die "needs tar in the base image"

work="$(mktemp -d)"
# shellcheck disable=SC2064 # $work is fixed now, and must be
trap "rm -rf '$work'" EXIT

# `main` is the branch tarball, the same thing the AUR's say-hi-git package
# builds from, and it carries the same caveat: there is no SHA256SUMS for a
# branch, so there is nothing to check the bytes against. A release version is
# the verified path and the default.
if [ "$VERSION" = main ]; then
  say "installing from the main branch - unverified, no published checksums"
  fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" "$work/src.tar.gz" ||
    die "could not download the main branch tarball"
else
  if [ "$VERSION" = latest ]; then
    # the redirect, not the API: /releases/latest/download/ needs no token and
    # no jq, and a Codespaces build has neither guaranteed
    base="https://github.com/$REPO/releases/latest/download"
    say "installing the latest release"
  else
    VERSION="${VERSION#v}"
    base="https://github.com/$REPO/releases/download/v$VERSION"
    say "installing v$VERSION"
  fi
  fetch "$base/SHA256SUMS" "$work/SHA256SUMS" ||
    die "no SHA256SUMS at $base - is that a released version?"
  # The tarball's name carries the version, which for `latest` is not known
  # until SHA256SUMS names it. One file, read out of the sums rather than
  # guessed, so the name and the checksum can never disagree.
  name="$(awk '$2 ~ /^\*?say-hi-.*\.tar\.gz$/ { sub(/^\*/, "", $2); print $2; exit }' "$work/SHA256SUMS")"
  [ -n "$name" ] || die "SHA256SUMS names no source tarball"
  # the version to stamp, read back off that name rather than off $VERSION -
  # which is "latest" half the time, and is the one string that cannot be
  # written into a launcher
  stamped_version="${name#say-hi-}"
  stamped_version="${stamped_version%.tar.gz}"
  fetch "$base/$name" "$work/$name" || die "could not download $name"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$work" && sha256sum -c --ignore-missing SHA256SUMS >/dev/null) ||
      die "checksum mismatch on $name"
    say "checksum ok: $name"
  else
    say "no sha256sum here - $name was downloaded unverified"
  fi
  mv "$work/$name" "$work/src.tar.gz"
fi

tar -xzf "$work/src.tar.gz" -C "$work"
# one top-level directory, whatever it is called: a release tarball unpacks to
# say-hi-<version>/ and codeload's to say-hi-main/
src="$(find "$work" -maxdepth 1 -type d -name 'say-hi-*' -print -quit)"
[ -n "$src" ] || die "the tarball had no say-hi-* directory in it"

# ...and then renamed, because neither of those names will do. install.sh
# derives $_HI_HOME as <checkout>/.. and looks for $_HI_HOME/say-hi, so the
# directory has to be called exactly that - the AUR PKGBUILD's prepare() and
# mkpkg.sh's staged_launcher each make the same link for the same reason.
ln -sfn "$src" "$work/say-hi"

# The one decider of what a packaged install contains, same as every other
# channel. It lays the tree at $PREFIX/say-hi, links /usr/bin/hi at it, and
# writes /etc/profile.d/say-hi.sh - which is how a *new* process in this
# container learns where the tree is, since nothing here can rewrite a
# Dockerfile's ENV. Executed rather than run through `sh`: it is bash, and a
# base image whose /bin/sh is dash refuses its `set -o pipefail` on line 12.
"$work/say-hi/scripts/install.sh" --prefix "$PREFIX"

# ...and the version stamp, packaging/stamp.sh, which is the one implementation
# every channel calls: the source tarball carries no _HI_RELEASE (bump.sh's
# manifest pass runs only after the tag exists), so without this `hi --version`
# in the container answers "unknown". Skipped for `main`, which has no version
# to claim - that install answers "unknown" honestly.
#
# The date is today's rather than $SOURCE_DATE_EPOCH's: stamp.sh refuses to
# guess one, and a devcontainer build is not a reproducible package build, so
# the day the image was built is the true answer for the man page's footer.
if [ -n "${stamped_version:-}" ]; then
  # the two files by name, the Homebrew formula's shape rather than the AUR's
  # --root: a keg and a container prefix are both layouts stamp.sh cannot
  # assume, and naming them costs one line more than assuming them.
  stamp_date=""
  [ -n "${SOURCE_DATE_EPOCH:-}" ] || stamp_date="$(date -u +%Y-%m-%d)"
  # shellcheck disable=SC2086 # ${x:+--date "$x"} is the whole point: no flag at all when empty
  "$work/say-hi/packaging/stamp.sh" --version "$stamped_version" \
    --launcher "$PREFIX/say-hi/hi.sh" \
    --man /usr/share/man/man1/hi.1.gz \
    ${stamp_date:+--date "$stamp_date"} ||
    say "could not stamp the version - hi --version will answer unknown"
fi

if [ "$CONFIGURESHELL" != true ]; then
  say "done - /usr/bin/hi works; the shell is unwired (configureShell false)"
  exit 0
fi

# ...and then the half a package manager cannot do, which is the whole reason
# this Feature exists: the terminal that opens in this container belongs to
# $_REMOTE_USER, and it is styled only if that user's rc files say so.
#
# As that user, not as root: hi --install writes to their rc files and their
# $XDG_CONFIG_HOME, and a root-owned ~/.bashrc is a broken container. `su -` so
# $HOME follows the user. --yes because nobody is watching, and --preset
# because a preset is the one way to answer every feature question at once
# without a terminal (scripts/configure.sh's _HI_PRESETS).
say "wiring $USERNAME's shell (preset: $PRESET)"
if [ "$USERNAME" = root ]; then
  "$PREFIX/say-hi/scripts/install.sh" --yes --preset "$PRESET"
else
  su - "$USERNAME" -c \
    "'$PREFIX/say-hi/scripts/install.sh' --yes --preset '$PRESET'"
fi

say "done - open a new terminal to see it"
