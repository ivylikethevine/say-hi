#!/usr/bin/env bash
# Every way say-hi gets onto a target, driven over real ssh: the .deb, the .rpm,
# the .apk, a Homebrew-shaped keg, a system-wide `install.sh --prefix`, and a
# packaged tree whose /etc/profile.d announcement has been taken away.
#
# One question in all six: hi has to *find the tree that is already there and
# use it in place*, rather than armoring its payload over the wire on top of it.
# That is what _hi_remote_root's probe decides, and each method reaches a
# different tier of it - profile.d for the three packages, the standard install
# prefixes for the two that announce themselves nowhere. A case that merely
# produced a working session would prove nothing: hi copying its payload over
# produces one too. So every case asserts $_HI_ROOT *is* the installed path.
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
# collide with one of ours (tests/lib/ssh.sh's _hi_run_case reads this)
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
# installation method. The probe command is the whole assertion: $_HI_ROOT has
# to be the tree the installer left, which only happens when _hi_remote_root
# answered. <post> runs inside the container afterwards, for the half a
# transcript cannot show - that hi wrote no second tree anywhere.
function _hi_method_case() {
  local label="$1" image="$2" shell="$3" root="$4" post="${5:-}"
  _hi_run_case "$label" "$image" "$shell" \
    "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed_at "$root")" \
    "$post" 'local say-hi install'
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
  _hi_sshd_image "every install method" || debian_ok=0

  _hi_build_packages && pkgs_ok=1

  if [ "$pkgs_ok" -eq 1 ] && [ "$debian_ok" -eq 1 ] &&
    ctx="$(_hi_pkg_context deb '*.deb' pkg.deb)"; then
    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-deb-img-$$")
    _hi_build_image deb "$_HI_SSH_CASE_PREFIX-deb-img-$$" "the .deb case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      --build-arg "PKG=pkg.deb" -f "$(_hi_dockerfile installed-pkg)" "$ctx" && deb_ok=1
  fi

  if [ "$pkgs_ok" -eq 1 ] && ctx="$(_hi_pkg_context rpm '*.rpm' pkg.rpm)"; then
    mkdir -p "$_HI_WORKDIR/fedora"
    # shellcheck disable=SC2016 # entrypoint.sh content, resolved on the container
    _hi_sshd_entrypoint "$_HI_WORKDIR/fedora" /bin/bash 'usermod -s "${LOGIN_SHELL:-/bin/bash}" hitest'
    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-fedora-$$")
    _hi_build_image fedora "$_HI_SSH_CASE_PREFIX-fedora-$$" "the .rpm case's base" \
      -f "$(_hi_dockerfile sshd-fedora)" "$_HI_WORKDIR/fedora" && fedora_ok=1
    if [ "$fedora_ok" -eq 1 ]; then
      _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-rpm-img-$$")
      _hi_build_image rpm "$_HI_SSH_CASE_PREFIX-rpm-img-$$" "the .rpm case" \
        --build-arg "BASE=$_HI_SSH_CASE_PREFIX-fedora-$$" \
        --build-arg "PKG=pkg.rpm" -f "$(_hi_dockerfile installed-pkg)" "$ctx" && rpm_ok=1
    fi
  fi

  if [ "$pkgs_ok" -eq 1 ] && ctx="$(_hi_pkg_context apk '*.apk' pkg.apk)"; then
    mkdir -p "$_HI_WORKDIR/alpine"
    _hi_sshd_entrypoint "$_HI_WORKDIR/alpine" /bin/sh
    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-alpine-$$")
    _hi_build_image alpine "$_HI_SSH_CASE_PREFIX-alpine-$$" "the .apk case's base" \
      --build-arg "PKGS=" \
      -f "$(_hi_dockerfile sshd-alpine)" "$_HI_WORKDIR/alpine" && alpine_ok=1
    if [ "$alpine_ok" -eq 1 ]; then
      _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-apk-img-$$")
      _hi_build_image apk "$_HI_SSH_CASE_PREFIX-apk-img-$$" "the .apk case" \
        --build-arg "BASE=$_HI_SSH_CASE_PREFIX-alpine-$$" \
        --build-arg "PKG=pkg.apk" -f "$(_hi_dockerfile installed-pkg)" "$ctx" && apk_ok=1
    fi
  fi

  if [ "$debian_ok" -eq 1 ]; then
    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-brew-img-$$")
    _hi_build_image brew "$_HI_SSH_CASE_PREFIX-brew-img-$$" "the Homebrew keg case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed-brew)" "$_HI_ROOT" && brew_ok=1

    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-prefix-img-$$")
    _hi_build_image prefix "$_HI_SSH_CASE_PREFIX-prefix-img-$$" "the --prefix case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed-prefix)" "$_HI_ROOT" && prefix_ok=1
  fi

  if [ "$prefix_ok" -eq 1 ]; then
    mkdir -p "$_HI_WORKDIR/unann"
    _HI_IMAGES+=("$_HI_SSH_CASE_PREFIX-unann-img-$$")
    _hi_build_image unann "$_HI_SSH_CASE_PREFIX-unann-img-$$" "the unannounced-tree case" \
      --build-arg "BASE=$_HI_SSH_CASE_PREFIX-prefix-img-$$" \
      -f "$(_hi_dockerfile installed-unannounced)" "$_HI_WORKDIR/unann" && unann_ok=1
  fi

  _hi_suite_begin
  _hi_pty_stdin auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"
  _hi_par_begin "install methods"

  # Every case's post-check says the same thing in its own words: no tree was
  # written anywhere but where the installer put it. /tmp/*.hi.* is what a
  # payload unpack leaves, and it is the failure this whole suite exists to
  # catch - a green session over a wastefully copied tree.
  local no_copy='! ls -d /tmp/*.hi.* >/dev/null 2>&1 && ! test -e /home/hitest/say-hi'

  # <label>:<suffix>:<remote root>:<skip reason>:<extra post-check>. The
  # suffix names both the <suffix>_ok flag the build phase above set and the
  # $_HI_SSH_CASE_PREFIX-<suffix>-img-$$ image it built; the extra post-check
  # (last field, so its spaces survive the split) is ANDed onto $no_copy. The
  # brew, prefix and unannounced tiers-of-last-resort each carry the sentinel
  # their fixture planted, so the post-check proves the session landed in
  # *that* tree rather than in one hi built at the same path.
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
        "$root" "$no_copy${extra:+ && $extra}"
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
