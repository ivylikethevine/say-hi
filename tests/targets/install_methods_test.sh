#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Every way say-hi gets onto a target, driven over real ssh: the .deb, the .rpm,
# the .apk, a Homebrew-shaped keg, a system-wide `install.sh --prefix`, and a
# packaged tree whose /etc/profile.d announcement has been taken away.
#
# One question in all six: the method leaves a *working* say-hi on that box,
# and a hi session to it is unaffected by one being there. hi ships its payload
# to every ssh target now - it does not read a say-hi the target already has -
# so each case asserts the session runs out of its own tree ($_HI_ROOT is not
# the installed path) and that the installed tree is still sitting there,
# whole, when the session is gone.
#
# ssh_test.sh is the sibling suite, and the split is deliberate: that one varies
# the login shell against one install, this one varies the install against one
# login shell. They share the case runner in tests/lib/ssh.sh.
#
# The three package cases need nfpm to build what they install; without it they
# stand down yellow rather than passing on nothing.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# containers and images this suite owns, so a concurrent ssh_test.sh run cannot
# collide with one of ours (tests/lib/ssh.sh's _hi_ssh_run_case reads this)
_HI_SSH_CASE_PREFIX=hi-instmethods
_HI_IMAGES=()

# _hi_pkg_context <label> <artifact-glob> <dest-name> - a build context holding
# exactly one freshly built package, renamed to the fixed name its Dockerfile
# COPYs. The rename is what keeps the version out of the Dockerfiles: mkpkg.sh
# names its output from the PKGBUILD's pkgver, and no fixture should have to
# track that.
function _hi_pkg_context() {
  local ctx="$_HI_WORKDIR/ctx-$1" glob="$2" dest="$3"
  local -a found=()
  mkdir -p "$ctx"
  # shellcheck disable=SC2206 # the glob is the point
  found=($_HI_PKG_DIST/$glob)
  [ -f "${found[0]:-}" ] || {
    _hi_cecho " | no $glob in $_HI_PKG_DIST" "$RED"
    return 1
  }
  cp "${found[0]}" "$ctx/$dest"
  printf '%s' "$ctx"
}

# The packages every package case installs, built once from this checkout by
# the same script the release runs. Sets $_HI_PKG_DIST on success.
#
# --outdir is deliberately not used: nfpm.yaml's contents are relative to the
# repo root, so the staging tree it reads has to be the default dist/. The
# directory is gitignored and the build is a plain user-level one.
function _hi_build_packages() {
  _hi_h2 "Building the packages to install"
  _HI_PKG_DIST="$_HI_ROOT/dist"
  # registered before the build (the ledger's rule): the exit trap removes
  # dist/ only when this suite is the one that created it
  [ -d "$_HI_PKG_DIST" ] || _hi_track_dir "$_HI_PKG_DIST"
  if ! (cd "$_HI_ROOT" && packaging/mkpkg.sh) >"$_HI_WORKDIR/mkpkg.log" 2>&1; then
    _hi_dump_log "mkpkg.sh failed, skipping the package cases:" "$_HI_WORKDIR/mkpkg.log" "$YELLOW"
    return 1
  fi
  _hi_cecho " | $(tr '\n' ' ' <"$_HI_PKG_DIST/ARTIFACTS")" "$BLUE"
  return 0
}

# _hi_method_case <label> <image> <login-shell> <installed-root> <post> - one
# installation method. The probe command is half the assertion: the session
# has to work *and* run out of a tree that is not the installed one. <post>
# runs inside the container afterwards, for the half a transcript cannot show
# - that the installed tree is still there and untouched.
function _hi_method_case() {
  local label="$1" image="$2" shell="$3" root="$4" post="${5:-}"
  _hi_ssh_run_case "$label" "$image" "$shell" \
    "$(_hi_probe_cmd "$_HI_TEST_MARKER" rooted_elsewhere "$root")" \
    "$post"
}

# shellcheck disable=SC2034 # the <method>_ok flags are read as ${!okvar} at the dispatch loop
function run_install_methods_tests() {
  _hi_require_backend docker

  _hi_workdir instmethods
  _hi_h1 "Testing hi against every way say-hi gets installed on a target"
  _hi_ssh_keypair

  _HI_TEST_MARKER="HI_INSTALL_METHOD_OK"

  _hi_h2 "Building test images"
  local debian_ok=1 fedora_ok=0 alpine_ok=0 pkgs_ok=0
  local deb_ok=0 rpm_ok=0 apk_ok=0 brew_ok=0 prefix_ok=0 unann_ok=0 ctx

  # All eight possible image names, registered upfront rather than as each
  # build is attempted: a chain that never ran (its prerequisite failed, or
  # a later step in it never got a base to build on) needs no image removed,
  # and `docker image rm -f` on a name that was never built is already a
  # no-op - the same rule the half-built-tag case always relied on.
  _HI_IMAGES=(
    "$_HI_SSH_CASE_PREFIX-deb-img-$$" "$_HI_SSH_CASE_PREFIX-fedora-$$" "$_HI_SSH_CASE_PREFIX-rpm-img-$$"
    "$_HI_SSH_CASE_PREFIX-alpine-$$" "$_HI_SSH_CASE_PREFIX-apk-img-$$" "$_HI_SSH_CASE_PREFIX-brew-img-$$"
    "$_HI_SSH_CASE_PREFIX-prefix-img-$$" "$_HI_SSH_CASE_PREFIX-unann-img-$$"
  )

  # Two independent prerequisites every chain below needs at least one of,
  # backgrounded together. $_HI_PKG_DIST and $_HI_SSHD_IMAGE are both fixed
  # paths a chain's own subshell can already see (set here and by
  # tests/lib/ssh.sh respectively, neither one a build's own output), so
  # nothing downstream needs to cross back out of a subshell to reach them.
  _HI_PKG_DIST="$_HI_ROOT/dist"
  (
    if _hi_sshd_image "every install method"; then printf '1' >"$_HI_WORKDIR/debian.built"; else printf '0' >"$_HI_WORKDIR/debian.built"; fi
  ) >"$_HI_WORKDIR/debian.par.log" 2>&1 &
  (
    if _hi_build_packages; then printf '1' >"$_HI_WORKDIR/pkgs.built"; else printf '0' >"$_HI_WORKDIR/pkgs.built"; fi
  ) >"$_HI_WORKDIR/pkgs.par.log" 2>&1 &
  wait
  cat "$_HI_WORKDIR/debian.par.log"
  debian_ok="$(cat "$_HI_WORKDIR/debian.built" 2>/dev/null || printf 0)"
  cat "$_HI_WORKDIR/pkgs.par.log"
  pkgs_ok="$(cat "$_HI_WORKDIR/pkgs.built" 2>/dev/null || printf 0)"

  # Five chains, independent of each other (none reads another's image or
  # verdict), backgrounded together: within one, a step still waits on the
  # step before it (rpm on fedora, unann on prefix) - that ordering is real
  # and stays inside the chain's own subshell. Each writes its verdict(s) to
  # $_HI_WORKDIR/<suffix>.built (one flag=value line per step of the chain)
  # and its own heading/log-dump text to <suffix>.par.log, replayed in table
  # order below once every chain is done.
  (
    if [ "$pkgs_ok" -eq 1 ] && [ "$debian_ok" -eq 1 ] &&
      ctx="$(_hi_pkg_context deb '*.deb' pkg.deb)"; then
      if _hi_build_image deb "$_HI_SSH_CASE_PREFIX-deb-img-$$" "the .deb case" \
        --build-arg "BASE=$_HI_SSHD_IMAGE" \
        --build-arg "PKG=pkg.deb" -f "$(_hi_dockerfile installed-pkg)" "$ctx"; then
        printf 'deb_ok=1\n' >"$_HI_WORKDIR/deb.built"
      fi
    fi
  ) >"$_HI_WORKDIR/deb.par.log" 2>&1 &

  (
    if [ "$pkgs_ok" -eq 1 ] && ctx="$(_hi_pkg_context rpm '*.rpm' pkg.rpm)"; then
      mkdir -p "$_HI_WORKDIR/fedora"
      # shellcheck disable=SC2016 # entrypoint.sh content, resolved on the container
      _hi_sshd_entrypoint "$_HI_WORKDIR/fedora" /bin/bash 'usermod -s "${LOGIN_SHELL:-/bin/bash}" hitest'
      if _hi_build_image fedora "$_HI_SSH_CASE_PREFIX-fedora-$$" "the .rpm case's base" \
        -f "$(_hi_dockerfile sshd-fedora)" "$_HI_WORKDIR/fedora"; then
        printf 'fedora_ok=1\n' >"$_HI_WORKDIR/rpm.built"
        if _hi_build_image rpm "$_HI_SSH_CASE_PREFIX-rpm-img-$$" "the .rpm case" \
          --build-arg "BASE=$_HI_SSH_CASE_PREFIX-fedora-$$" \
          --build-arg "PKG=pkg.rpm" -f "$(_hi_dockerfile installed-pkg)" "$ctx"; then
          printf 'rpm_ok=1\n' >>"$_HI_WORKDIR/rpm.built"
        fi
      fi
    fi
  ) >"$_HI_WORKDIR/rpm.par.log" 2>&1 &

  (
    if [ "$pkgs_ok" -eq 1 ] && ctx="$(_hi_pkg_context apk '*.apk' pkg.apk)"; then
      mkdir -p "$_HI_WORKDIR/alpine"
      _hi_sshd_entrypoint "$_HI_WORKDIR/alpine" /bin/sh
      if _hi_build_image alpine "$_HI_SSH_CASE_PREFIX-alpine-$$" "the .apk case's base" \
        --build-arg "PKGS=" \
        -f "$(_hi_dockerfile sshd-alpine)" "$_HI_WORKDIR/alpine"; then
        printf 'alpine_ok=1\n' >"$_HI_WORKDIR/apk.built"
        if _hi_build_image apk "$_HI_SSH_CASE_PREFIX-apk-img-$$" "the .apk case" \
          --build-arg "BASE=$_HI_SSH_CASE_PREFIX-alpine-$$" \
          --build-arg "PKG=pkg.apk" -f "$(_hi_dockerfile installed-pkg)" "$ctx"; then
          printf 'apk_ok=1\n' >>"$_HI_WORKDIR/apk.built"
        fi
      fi
    fi
  ) >"$_HI_WORKDIR/apk.par.log" 2>&1 &

  (
    if [ "$debian_ok" -eq 1 ] && _hi_build_image brew "$_HI_SSH_CASE_PREFIX-brew-img-$$" "the Homebrew keg case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed-brew)" "$_HI_ROOT"; then
      printf 'brew_ok=1\n' >"$_HI_WORKDIR/brew.built"
    fi
  ) >"$_HI_WORKDIR/brew.par.log" 2>&1 &

  (
    if [ "$debian_ok" -eq 1 ] && _hi_build_image prefix "$_HI_SSH_CASE_PREFIX-prefix-img-$$" "the --prefix case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed-prefix)" "$_HI_ROOT"; then
      printf 'prefix_ok=1\n' >"$_HI_WORKDIR/prefix.built"
      mkdir -p "$_HI_WORKDIR/unann"
      if _hi_build_image unann "$_HI_SSH_CASE_PREFIX-unann-img-$$" "the unannounced-tree case" \
        --build-arg "BASE=$_HI_SSH_CASE_PREFIX-prefix-img-$$" \
        -f "$(_hi_dockerfile installed-unannounced)" "$_HI_WORKDIR/unann"; then
        printf 'unann_ok=1\n' >>"$_HI_WORKDIR/prefix.built"
      fi
    fi
  ) >"$_HI_WORKDIR/prefix.par.log" 2>&1 &

  wait

  local chain assign
  for chain in deb rpm apk brew prefix; do
    cat "$_HI_WORKDIR/$chain.par.log"
    [ -f "$_HI_WORKDIR/$chain.built" ] || continue
    while IFS= read -r assign; do eval "$assign"; done <"$_HI_WORKDIR/$chain.built"
  done

  _hi_suite_begin
  _hi_pty_stdin auto
  _hi_par_begin "install methods"

  # Every case's post-check says the same thing in its own words: the tree the
  # installer put there is still whole once the session has gone, and the
  # session's own disposable tree took itself with it (load.sh's clean_all).
  # A leftover /tmp/*.hi.* is the failure this half exists to catch.
  local intact='! ls -d /tmp/*.hi.* >/dev/null 2>&1'

  # <label>:<suffix>:<installed root>:<skip reason>:<extra post-check>. The
  # suffix names both the <suffix>_ok flag the build phase above set and the
  # $_HI_SSH_CASE_PREFIX-<suffix>-img-$$ image it built; the extra post-check
  # (last field, so its spaces survive the split) joins $intact with &&. Each
  # case checks the installer's own hi.sh is still executable where it put it,
  # and the three tiers whose fixture plants a sentinel check that too.
  local -a methods=(
    "deb:deb:/usr/share/say-hi:no nfpm to build the .deb, or the image failed:"
    "rpm:rpm:/usr/share/say-hi:no nfpm to build the .rpm, or the fedora image failed:"
    "apk:apk:/usr/share/say-hi:no nfpm to build the .apk, or the alpine image failed:"
    "brew:brew:/home/linuxbrew/.linuxbrew/opt/say-hi/libexec/say-hi:the sshd image failed:test -f /home/linuxbrew/.linuxbrew/opt/say-hi/libexec/say-hi/.installed_sentinel"
    "prefix:prefix:/usr/local/share/say-hi:the sshd image failed:test -f /usr/local/share/say-hi/.installed_sentinel"
    "unannounced:unann:/usr/local/share/say-hi:the --prefix image it builds on is missing:test -f /usr/local/share/say-hi/.installed_sentinel && ! test -e /etc/profile.d/say-hi.sh"
  )

  local spec label suffix root reason extra okvar
  for spec in "${methods[@]}"; do
    IFS=: read -r label suffix root reason extra <<<"$spec"
    okvar="${suffix}_ok" # ${!okvar} is bash 2, not a bash-4 form
    if [ "${!okvar}" -eq 1 ]; then
      _hi_par_case "$label" _hi_method_case "$label" "$_HI_SSH_CASE_PREFIX-$suffix-img-$$" /bin/bash \
        "$root" "$intact && test -x $root/hi.sh${extra:+ && $extra}"
    else
      _hi_skip "[$label]" "$reason"
    fi
  done

  _hi_par_wait

  [ "${#_HI_IMAGES[@]}" -eq 0 ] ||
    docker image rm -f "${_HI_IMAGES[@]}" >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "hi reused the permanent install for every method tested ($_HI_TOTAL cases)" \
    "hi FAILED to reuse the install: $_HI_FAILED/$_HI_TOTAL cases"
}

run_install_methods_tests
