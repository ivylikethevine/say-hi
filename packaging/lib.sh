#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Shared plumbing for packaging/'s entry points (bump.sh, mkpkg.sh): locate
# the tree, source core.sh, and hold the primitives they share.
# scripts/install.sh keeps its own locator on purpose - it ships in packages
# *without* packaging/, so it cannot source this file; that boundary-forced
# copy is documented there, as is hi.sh's - the third copy, for the same reason.

# Locate say-hi relative to this file's own path, resolving symlinks -
# packaging/ is one level down from the tree root, so the home is its ../../.
# Self-relative rather than off the sourcer (BASH_SOURCE[1]) so this resolves
# the same way whoever sources it, wherever they are - a test harness in
# tests/packaging/ included.
# The same walk as hi.sh's and scripts/install.sh's: fix one, fix all three.
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_LINK="$(readlink "$_HI_SELF")"
  case "$_HI_SELF_LINK" in
  /*) _HI_SELF="$_HI_SELF_LINK" ;;
  *) case "$_HI_SELF" in
    */*) _HI_SELF="${_HI_SELF%/*}/$_HI_SELF_LINK" ;;
    *) _HI_SELF="$_HI_SELF_LINK" ;;
    esac ;;
  esac
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=../scripts/lib.sh
source "$_HI_HOME/say-hi/scripts/lib.sh"

# need <tool> [hint] - the tool-missing refusal every entry point spells the
# same way; the optional hint says where the tool comes from.
function need() {
  command -v "$1" >/dev/null 2>&1 || {
    _hi_cecho " $1 is not installed${2:+ - $2}" "$RED" >&2
    return 1
  }
}

# gpg_fpr <gpg args...> - the first fingerprint in gpg's --with-colons output,
# or empty. The `|| true` matters: gpg failing inside a caller's command
# substitution would otherwise kill a `set -e` + pipefail script silently,
# before the caller's guard can name the problem (a missing public-key file
# once took out release.yml's publish job exactly this way).
function gpg_fpr() {
  gpg --batch --with-colons "$@" 2>/dev/null |
    awk -F: '$1 == "fpr" { print $10; exit }' || true
}

# verify_signing_key <gpg|rsa> <secret-key-file> <public-half-file> - refuse a
# secret signing key that is not the one the committed public half names: a
# secret that is another key signs artifacts no client can verify. gpg mode
# prints the matching fingerprint on success; rsa mode compares the derived
# public key byte-for-byte against <public-half-file>. release.yml's build
# job runs both before letting a key anywhere near a package.
function verify_signing_key() {
  local mode="$1" secret="$2" public="$3" home have want
  case "$mode" in
  gpg)
    # /tmp, not `-t`: gpg-agent's socket path cap - see mkrepo.sh's gpg_setup
    home="$(mktemp -d /tmp/hi.gnupg.XXXXXX)"
    chmod 700 "$home"
    if ! gpg --batch --quiet --homedir "$home" --import "$secret" 2>/dev/null; then
      rm -rf "$home"
      _hi_cecho " could not import the secret key $secret" "$RED" >&2
      return 1
    fi
    have="$(gpg_fpr --homedir "$home" --list-secret-keys)"
    want="$(gpg_fpr --homedir "$home" --quiet --show-keys "$public")"
    gpgconf --homedir "$home" --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf "$home"
    [ -n "$want" ] || {
      _hi_cecho " $public is missing or not a key" "$RED" >&2
      return 1
    }
    [ "$have" = "$want" ] || {
      _hi_cecho " the secret key is $have, not the key $public names ($want)" "$RED" >&2
      return 1
    }
    printf '%s' "$have"
    ;;
  rsa)
    openssl rsa -in "$secret" -pubout 2>/dev/null | diff -q - "$public" >/dev/null || {
      _hi_cecho " the secret key is not the one $public is the public half of" "$RED" >&2
      return 1
    }
    ;;
  esac
}

# sha256 lines ("<sum>  <file>" per argument) and single-file sha256/blake2b,
# each with a non-coreutils fallback so these also run on a mac (no sha256sum,
# no b2sum) rather than only on the Linux CI box.
function sha256_lines() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$@"
  else
    shasum -a 256 -- "$@"
  fi
}

function sha256_of() {
  sha256_lines "$1" | awk '{ print $1 }'
}

function b2_of() {
  if command -v b2sum >/dev/null 2>&1; then
    b2sum "$1" | awk '{ print $1 }'
  else
    # BLAKE2b-512 is exactly what makepkg's b2sums holds
    openssl dgst -blake2b512 "$1" | awk '{ print $NF }'
  fi
}

# src_tarball <version> <ref> <outfile> - the source tarball a release ships.
# Built here rather than fetched: GitHub's auto-generated /archive/ tarball is
# the one released artifact with nothing signed over it, and its bytes are not
# promised stable across changes to GitHub's own gzip. This is the same shape -
# `git archive` with a say-hi-<version>/ prefix, which is what the AUR
# package's prepare() symlink expects - so nothing downstream can tell the
# difference except that this one is in SHA256SUMS and under the attestation.
#
# Deterministic for a given commit: git picks the format from the .tar.gz
# suffix and runs its own `gzip -cn`, which writes neither a name nor a
# timestamp into the header.
function src_tarball() {
  local version="$1" ref="$2" out="$3"
  git -C "$_HI_ROOT" archive --prefix "say-hi-$version/" -o "$out" "$ref"
}

# The version of record lives in the versioned PKGBUILD (a release's build
# writes it there, in its own disposable checkout - never committed back, see
# bump.sh's header); reading it back rather than keeping copies is what stops
# the channels disagreeing within one build. Reads $1, defaulting to the
# caller's $_HI_PKGBUILD.
function pkgbuild_version() {
  local file="${1:-$_HI_PKGBUILD}" v
  v="$(sed -n 's/^pkgver=//p' "$file" | head -1)"
  [ -n "$v" ] || {
    _hi_cecho " no pkgver= in $file" "$RED" >&2
    return 1
  }
  printf '%s' "$v"
}

# The URL of record the same way: the PKGBUILD's url= is what makepkg expands
# into source=, so every other place an asset URL is written (the formula, the
# no-makepkg .SRCINFO fallback) must derive from the same line - a private
# copy drifts on a repo rename with nothing red on the release runner, where
# no makepkg exists to expand the real one. Reads $1, defaulting to the
# caller's $_HI_PKGBUILD.
function pkgbuild_url() {
  local file="${1:-$_HI_PKGBUILD}" u
  u="$(sed -n 's/^url="\(.*\)"/\1/p' "$file" | head -1)"
  [ -n "$u" ] || {
    _hi_cecho " no url= in $file" "$RED" >&2
    return 1
  }
  printf '%s' "$u"
}

# What a build defaults to when nobody named one. The committed PKGBUILD is a
# template (pkgver=0.0.0) outside a release's own bump, so pkgbuild_version()
# alone would default every local and per-PR build to 0.0.0; fall through to
# this checkout's newest tag instead, and only settle for 0.0.0 when neither
# answers (a shallow clone, a checkout with no tags at all).
function default_version() {
  local v
  v="$(pkgbuild_version 2>/dev/null || true)"
  if [ -n "$v" ] && [ "$v" != 0.0.0 ]; then
    printf '%s' "$v"
    return 0
  fi
  # --match 'v*': clones can still carry snapshot-<sha> tags (from the
  # retired per-push snapshot builds), which are not release versions and
  # must never win here.
  v="$(git -C "$_HI_ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  if [ -n "$v" ]; then
    printf '%s' "${v#v}"
    return 0
  fi
  printf '0.0.0'
}

# Strict mode for every consumer, here rather than at the top of each script:
# core.sh (sourced above) ends with `set +euo pipefail`, so a `set` line
# placed before a script's own `source lib.sh` is silently undone.
set -euo pipefail
