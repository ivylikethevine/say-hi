#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The package repository, end to end: packaging/mkpkg.sh builds the deb, rpm
# and apk signed with throwaway keys, packaging/mkrepo.sh turns them into the
# apt, rpm and apk repositories release.yml publishes, and three throwaway
# clients - Ubuntu's apt, Fedora's dnf, Alpine's apk - subscribe to the result
# over file:// and install say-hi from it with every signature verified: no
# `trusted=yes`, no `gpgcheck=0`, no `--allow-untrusted`. Each client then runs
# `hi --version` from a login shell, so the /etc/profile.d wiring is on trial
# as well.
#
# What it proves that tests/packaging/packaging_test.sh cannot: that the
# indexes mkrepo.sh writes are ones a real client accepts, and that the keys a
# client is told to trust are the ones the artifacts were signed with. The
# unit suite guards the workflow wiring; this one is the wire.
#
# Needs docker, nfpm (to build the packages), gpg and openssl (the keys).
# Without any of them the suite stands down yellow.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_REPO=""
_HI_REPO_VERSION=""
# The release before this one, as far as an upgrade case is concerned: the
# same tree built and signed a second time under a lower version, so a client
# can install it first and then take the repository's as an upgrade. The
# mechanics on trial are the package manager's - files replaced, the symlink
# and profile.d snippet still there, the version stamp moved - and that
# nothing the user wrote (/etc/say-hi/settings.sh, ~/.config/say-hi) is
# touched; those hold whatever version the packages carry.
#
# Both versions are named here, not derived, so the ordering the upgrade
# depends on is structural rather than borrowed from whatever this checkout's
# tags happen to say: default_version() (packaging/lib.sh) falls through a
# shallow, tagless clone - the shape ci.yml's e2e checkout actually is - to
# the literal 0.0.0, which is *lower* than a hardcoded 0.0.1 fixture and would
# turn every "upgrade" below into a downgrade apt/dnf/apk silently no-op.
_HI_PREV=""
_HI_PREV_VERSION="0.0.1"
_HI_CUR_VERSION="0.0.2"

# _hi_repo_keys - a throwaway GPG signing key and a throwaway apk RSA key in
# the workdir. RSA 4096 as the runbook prescribes for the real one.
function _hi_repo_keys() {
  local gnupg="$_HI_WORKDIR/gnupg"
  mkdir -p "$gnupg"
  chmod 700 "$gnupg"
  GNUPGHOME="$gnupg" gpg --batch --quiet --passphrase '' \
    --quick-generate-key 'say-hi test <test@example.invalid>' rsa4096 sign never 2>/dev/null
  GNUPGHOME="$gnupg" gpg --batch --quiet --armor --export-secret-keys >"$_HI_WORKDIR/gpg.key"
  GNUPGHOME="$gnupg" gpg --batch --quiet --armor --export >"$_HI_WORKDIR/gpg.asc"
  openssl genrsa -out "$_HI_WORKDIR/apk.rsa" 4096 2>/dev/null
}

# _hi_repo_build - mkpkg.sh then mkrepo.sh, both signed. --outdir is not
# passed to mkpkg.sh: nfpm.yaml's contents are relative to the repo root, so
# the staging tree has to be the default dist/ (install_methods_test.sh has
# the same note); the repository itself lands in the workdir.
function _hi_repo_build() {
  _HI_REPO="$_HI_WORKDIR/repo"
  # named, not derived from mkpkg.sh's own default_version(): that falls
  # through a shallow, tagless checkout to the literal 0.0.0, which would
  # sort below the hardcoded $_HI_PREV_VERSION fixture and turn every
  # upgrade case into a downgrade. $_HI_CUR_VERSION is what every client's
  # `hi --version` has to print back.
  _HI_REPO_VERSION="$_HI_CUR_VERSION"
  # registered before the build (the ledger's rule): the exit trap removes
  # dist/ only when this suite is the one that created it
  [ -d "$_HI_ROOT/dist" ] || _hi_track_dir "$_HI_ROOT/dist"
  # The previous release first, moved out of dist/ before the real build:
  # nfpm.yaml hardcodes ./dist/staging, so the two builds are sequential
  # rather than --outdir'd apart, as ci.yml's byte-identical check is.
  _hi_h2 "Building the previous release ($_HI_PREV_VERSION), signed"
  _HI_PREV="$_HI_WORKDIR/prev"
  if ! (cd "$_HI_ROOT" && HI_GPG_KEY="$_HI_WORKDIR/gpg.key" HI_APK_KEY="$_HI_WORKDIR/apk.rsa" packaging/mkpkg.sh --version "$_HI_PREV_VERSION") >"$_HI_WORKDIR/mkpkg-prev.log" 2>&1; then
    _hi_dump_log "mkpkg.sh --version $_HI_PREV_VERSION failed:" "$_HI_WORKDIR/mkpkg-prev.log" "$RED"
    return 1
  fi
  mv "$_HI_ROOT/dist" "$_HI_PREV"
  _hi_h2 "Building the packages, signed"
  if ! (cd "$_HI_ROOT" && HI_GPG_KEY="$_HI_WORKDIR/gpg.key" HI_APK_KEY="$_HI_WORKDIR/apk.rsa" packaging/mkpkg.sh --version "$_HI_CUR_VERSION") >"$_HI_WORKDIR/mkpkg.log" 2>&1; then
    _hi_dump_log "mkpkg.sh --version $_HI_CUR_VERSION failed:" "$_HI_WORKDIR/mkpkg.log" "$RED"
    return 1
  fi
  _hi_h2 "Building the repository"
  if ! "$_HI_ROOT/packaging/mkrepo.sh" --dist "$_HI_ROOT/dist" --outdir "$_HI_REPO" \
    --gpg-key "$_HI_WORKDIR/gpg.key" --public-key "$_HI_WORKDIR/gpg.asc" \
    --apk-key "$_HI_WORKDIR/apk.rsa" --tarball "$_HI_WORKDIR/package-repo.tar.gz" \
    >"$_HI_WORKDIR/mkrepo.log" 2>&1; then
    _hi_dump_log "mkrepo.sh failed:" "$_HI_WORKDIR/mkrepo.log" "$RED"
    return 1
  fi
  return 0
}

# the release asset is the tree, byte for byte: pages.yml serves the unpacked
# tarball, not the directory mkrepo.sh wrote
function test_tarball_is_the_repository() {
  local unpacked="$_HI_WORKDIR/unpacked"
  mkdir -p "$unpacked"
  tar -xzf "$_HI_WORKDIR/package-repo.tar.gz" -C "$unpacked"
  diff -r "$_HI_REPO" "$unpacked" >/dev/null
}

# the signed pieces exist - the cheap check before a client is asked
function test_repository_is_signed() {
  [ -s "$_HI_REPO/apt/dists/stable/InRelease" ] &&
    [ -s "$_HI_REPO/apt/dists/stable/Release.gpg" ] &&
    [ -s "$_HI_REPO/rpm/repodata/repomd.xml.asc" ] &&
    [ -s "$_HI_REPO/apk/x86_64/APKINDEX.tar.gz" ] &&
    [ -s "$_HI_REPO/apk/aarch64/APKINDEX.tar.gz" ] &&
    [ -s "$_HI_REPO/say-hi.asc" ] && [ -s "$_HI_REPO/say-hi.rsa.pub" ] && [ -s "$_HI_REPO/say-hi.repo" ]
}

# _hi_repo_client <label> <image> <shell> <script> - one throwaway client
# with the repository at /repo, read-only. The script subscribes, installs
# and prints `hi --version` from a login shell as its last line; the case
# passes when that line is the version the packages were stamped with, and
# the transcript replays on failure.
function _hi_repo_client() {
  local label="$1" image="$2" shell="$3" script="$4" log="$_HI_WORKDIR/$1.log" last
  if ! docker run --rm -v "$_HI_REPO:/repo:ro" -v "$_HI_PREV:/prev:ro" "$image" "$shell" -ec "$script" >"$log" 2>&1; then
    _hi_dump_log "$label client failed:" "$log" "$RED"
    return 1
  fi
  last="$(tail -n 1 "$log")"
  [ "$last" = "$_HI_REPO_VERSION" ] || {
    _hi_dump_log "$label: hi --version printed '$last', not $_HI_REPO_VERSION:" "$log" "$RED"
    return 1
  }
}

# apt: the key goes to /etc/apt/keyrings, the sources line names it with
# signed-by and nothing says trusted=yes - so a bad InRelease signature fails
# `apt-get update`, and a missing one fails it louder
function test_apt_client_installs_from_the_repository() {
  _hi_repo_client apt ubuntu:24.04 bash '
    mkdir -p /etc/apt/keyrings
    cp /repo/say-hi.asc /etc/apt/keyrings/say-hi.asc
    echo "deb [signed-by=/etc/apt/keyrings/say-hi.asc] file:///repo/apt stable main" >/etc/apt/sources.list.d/say-hi.list
    apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y say-hi >/dev/null
    dpkg -s say-hi | grep -q "^Status: install ok installed"
    bash -lc "hi --version"'
}

# dnf: gpgcheck=1 verifies the rpm nfpm signed, repo_gpgcheck=1 the
# repomd.xml mkrepo.sh signed; both keyed by the say-hi.asc the repo serves
function test_dnf_client_installs_from_the_repository() {
  _hi_repo_client dnf fedora:44 bash '
    printf "[say-hi]\nname=say-hi\nbaseurl=file:///repo/rpm\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///repo/say-hi.asc\n" >/etc/yum.repos.d/say-hi.repo
    dnf -y -q install say-hi >/dev/null
    rpm -q say-hi >/dev/null
    rpm -K /repo/rpm/*.rpm | grep -q "signatures OK"
    bash -lc "hi --version"'
}

# apk: the served say-hi.rsa.pub into /etc/apk/keys, the repository line, and
# no --allow-untrusted anywhere - the index signature and the package
# signature are both on trial
function test_apk_client_installs_from_the_repository() {
  _hi_repo_client apk alpine:3.24 sh '
    cp /repo/say-hi.rsa.pub /etc/apk/keys/
    echo /repo/apk >>/etc/apk/repositories
    apk add -q say-hi
    apk info -e say-hi >/dev/null
    sh -lc "hi --version"'
}

# The upgrade every subscriber takes: the previous release installed from its
# package file, a system layer and an overlay written, then the repository's
# release taken as an upgrade through the same manager. Each script checks
# what it can only check from the inside - the version that was there before,
# both config files intact after, the symlink and profile.d snippet still in
# place - and ends on `hi --version` for _hi_repo_client's verdict. The
# upgrade is asked for the way a user would ask (`apt-get install`, `dnf
# upgrade`, `apk add -u`), not with a path to the new file.
_HI_UPGRADE_CONFIG='
    mkdir -p /etc/say-hi /root/.config/say-hi
    echo "export _HI_DISABLE_NOTIFY=1" >/etc/say-hi/settings.sh
    echo "hostname,prod,red" >/root/.config/say-hi/colors'
_HI_UPGRADE_ASSERT='
    grep -q "_HI_DISABLE_NOTIFY=1" /etc/say-hi/settings.sh
    grep -q "hostname,prod,red" /root/.config/say-hi/colors
    test -L /usr/bin/hi && test -f /etc/profile.d/say-hi.sh && test -f /usr/share/say-hi/hi.sh'

function test_apt_client_upgrades_in_place() {
  # shellcheck disable=SC2016 # the $( ) runs inside the container
  _hi_repo_client apt-upgrade ubuntu:24.04 bash '
    mkdir -p /etc/apt/keyrings
    cp /repo/say-hi.asc /etc/apt/keyrings/say-hi.asc
    apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y /prev/say-hi_*_all.deb >/dev/null
    test "$(bash -lc "hi --version")" = "'"$_HI_PREV_VERSION"'"'"$_HI_UPGRADE_CONFIG"'
    echo "deb [signed-by=/etc/apt/keyrings/say-hi.asc] file:///repo/apt stable main" >/etc/apt/sources.list.d/say-hi.list
    apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y say-hi >/dev/null
    dpkg -s say-hi | grep -q "^Status: install ok installed"'"$_HI_UPGRADE_ASSERT"'
    bash -lc "hi --version"'
}

function test_dnf_client_upgrades_in_place() {
  # shellcheck disable=SC2016 # the $( ) runs inside the container
  _hi_repo_client dnf-upgrade fedora:44 bash '
    rpm --import /repo/say-hi.asc
    dnf -y -q install /prev/say-hi-*.noarch.rpm >/dev/null
    test "$(bash -lc "hi --version")" = "'"$_HI_PREV_VERSION"'"'"$_HI_UPGRADE_CONFIG"'
    printf "[say-hi]\nname=say-hi\nbaseurl=file:///repo/rpm\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///repo/say-hi.asc\n" >/etc/yum.repos.d/say-hi.repo
    dnf -y -q upgrade say-hi >/dev/null
    rpm -q say-hi >/dev/null'"$_HI_UPGRADE_ASSERT"'
    bash -lc "hi --version"'
}

function test_apk_client_upgrades_in_place() {
  # shellcheck disable=SC2016 # the $( ) runs inside the container
  _hi_repo_client apk-upgrade alpine:3.24 sh '
    cp /repo/say-hi.rsa.pub /etc/apk/keys/
    apk add -q /prev/say-hi_*_noarch.apk
    test "$(sh -lc "hi --version")" = "'"$_HI_PREV_VERSION"'"'"$_HI_UPGRADE_CONFIG"'
    echo /repo/apk >>/etc/apk/repositories
    apk add -q -u say-hi
    apk info -e say-hi >/dev/null'"$_HI_UPGRADE_ASSERT"'
    sh -lc "hi --version"'
}

function run_repo_tests() {
  _hi_require_backend docker
  _hi_require nfpm "not installed - it builds the packages the repository indexes"
  _hi_require gpg
  _hi_require openssl

  _hi_workdir repotest
  _hi_h1 "Testing the package repository, from mkpkg.sh to three subscribed clients"
  _hi_repo_keys
  local built=0
  _hi_repo_build && built=1

  _hi_suite_begin
  _hi_check "mkpkg.sh and mkrepo.sh build a signed repository" [ "$built" -eq 1 ]
  if [ "$built" -eq 1 ]; then
    _hi_check "package-repo.tar.gz is the repository" test_tarball_is_the_repository
    _hi_check "Every index is signed and every key served" test_repository_is_signed
    _hi_h2 "Testing: subscribed clients"
    _hi_check "apt (ubuntu:24.04) installs with signed-by" test_apt_client_installs_from_the_repository
    _hi_check "dnf (fedora:44) installs with gpgcheck and repo_gpgcheck" test_dnf_client_installs_from_the_repository
    _hi_check "apk (alpine:3.24) installs with the served key" test_apk_client_installs_from_the_repository
    _hi_h2 "Testing: the upgrade from $_HI_PREV_VERSION, config kept"
    _hi_check "apt upgrades in place" test_apt_client_upgrades_in_place
    _hi_check "dnf upgrades in place" test_dnf_client_upgrades_in_place
    _hi_check "apk upgrades in place" test_apk_client_upgrades_in_place
  else
    _hi_skip "[clients]" "no repository to subscribe to"
  fi
  _hi_suite_end "" \
    "every client installed say-hi $_HI_REPO_VERSION from the repository, signatures verified ($_HI_TOTAL cases)" \
    "the package repository FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_repo_tests
