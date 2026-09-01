#!/usr/bin/env bash
# Turns the packages mkpkg.sh built into a subscribable repository for apt, dnf
# and apk - the tree release.yml ships as `package-repo.tar.gz` and pages.yml
# serves from https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}.
#
# No second packaging description: the inputs are the one .deb, .rpm and .apk
# in dist/, and the only things generated here are indexes over them plus the
# keys a client needs. The three index builders that are not plain shell run
# in throwaway containers (apk-tools from Alpine, createrepo_c from Debian),
# so a dev box needs docker and gpg and nothing else, and builds the bytes CI
# does. The
# apt indexes are written here directly - apt-ftparchive is Debian-only and
# the Packages/Release format is small.
#
# Signing: --gpg-key takes an armored, passphrase-free secret key and signs
# the apt Release (InRelease and Release.gpg) and the rpm repomd.xml; its
# public half lands in the repo as say-hi.asc. --apk-key takes the RSA key the
# apk itself was signed with and signs each APKINDEX, named after
# packaging/apk/say-hi.rsa.pub as apk-tools expects. Either flag left off
# builds that half unsigned, loudly: a client then needs `trusted=yes`,
# `gpgcheck=0` or `--allow-untrusted`, which is fine for a local look and
# nothing to publish.
#
# Layout written under --outdir (default dist/repo):
#   apt/dists/stable/{InRelease,Release,Release.gpg}
#   apt/dists/stable/main/binary-{amd64,arm64,all}/Packages{,.gz}
#   apt/pool/main/s/say-hi/<deb>
#   rpm/<rpm>  rpm/repodata/{repomd.xml,repomd.xml.asc,...}
#   apk/{x86_64,aarch64}/{<apk>,APKINDEX.tar.gz}
#   say-hi.asc  say-hi.rsa.pub  say-hi.repo

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# after the source, not before: core.sh (which lib.sh pulls in) ends with
# `set +euo pipefail`, so an earlier line here would be undone by it
set -euo pipefail

_HI_DIST="$_HI_ROOT/dist"
_HI_OUT=""
_HI_GPG_KEY=""
_HI_GPG_PUBLIC=""
_HI_APK_KEY=""
_HI_BASE_URL="https://ivylikethevine.github.io/say-hi"
_HI_TARBALL=""
# the noarch packages are listed under every architecture a client asks for
_HI_DEB_ARCHES="amd64 arm64 all"
_HI_APK_ARCHES="x86_64 aarch64"
_HI_ALPINE_IMAGE="alpine:3.24"
# createrepo_c: Alpine 3.24 does not package it, Debian stable does
_HI_DEBIAN_IMAGE="debian:bookworm-slim"
_HI_USAGE="Usage: mkrepo.sh [--dist <dir>] [--outdir <dir>] [--gpg-key <file> [--public-key <asc>]] [--apk-key <file>] [--base-url <url>] [--tarball <file>]"

function usage() {
  cat <<EOF
$_HI_USAGE
Builds an apt, an rpm and an apk repository out of the packages in --dist.
  --dist <dir>       Where mkpkg.sh left the .deb/.rpm/.apk. Default: dist/
  --outdir <dir>     Where to write the repository. Default: <dist>/repo
  --gpg-key <file>   Armored, passphrase-free GPG secret key: signs the apt
                     Release and the rpm repomd.xml. Absent, both go unsigned.
  --public-key <asc> Refuse a --gpg-key that is not the key this public key
                     names (release.yml passes packaging/gpg/say-hi.asc).
  --apk-key <file>   The RSA key the apk was signed with (mkpkg.sh's
                     HI_APK_KEY): signs each APKINDEX. Absent, unsigned.
  --base-url <url>   Where the repository will be served from, written into
                     say-hi.repo. Default: $_HI_BASE_URL
  --tarball <file>   Also write the whole tree as one .tar.gz - the release
                     asset pages.yml unpacks.
Needs docker (apk-tools runs in $_HI_ALPINE_IMAGE, createrepo_c in
$_HI_DEBIAN_IMAGE) and gpg.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --dist | --outdir | --gpg-key | --public-key | --apk-key | --base-url | --tarball)
    [ $# -ge 2 ] || {
      echo "mkrepo.sh: $1 requires a value" >&2
      exit 1
    }
    case "$1" in
    --dist) _HI_DIST="$2" ;;
    --outdir) _HI_OUT="$2" ;;
    --gpg-key) _HI_GPG_KEY="$2" ;;
    --public-key) _HI_GPG_PUBLIC="$2" ;;
    --apk-key) _HI_APK_KEY="$2" ;;
    --base-url) _HI_BASE_URL="$2" ;;
    --tarball) _HI_TARBALL="$2" ;;
    esac
    shift
    ;;
  --dist=*) _HI_DIST="${1#*=}" ;;
  --outdir=*) _HI_OUT="${1#*=}" ;;
  --gpg-key=*) _HI_GPG_KEY="${1#*=}" ;;
  --public-key=*) _HI_GPG_PUBLIC="${1#*=}" ;;
  --apk-key=*) _HI_APK_KEY="${1#*=}" ;;
  --base-url=*) _HI_BASE_URL="${1#*=}" ;;
  --tarball=*) _HI_TARBALL="${1#*=}" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "mkrepo.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done
: "${_HI_OUT:=$_HI_DIST/repo}"

# one_package <ext> - the single dist/*.<ext>, the same one-artifact rule
# mkpkg.sh's write_checksums enforces
function one_package() {
  local f
  local -a found=()
  for f in "$_HI_DIST"/*."$1"; do [ -f "$f" ] && found+=("$f"); done
  [ "${#found[@]}" -eq 1 ] || {
    _hi_cecho " expected exactly one .$1 in $_HI_DIST, found ${#found[@]} - run packaging/mkpkg.sh first" "$RED" >&2
    return 1
  }
  printf '%s' "${found[0]}"
}

function need() {
  command -v "$1" >/dev/null 2>&1 || {
    _hi_cecho " $1 is not installed${2:+ - $2}" "$RED" >&2
    return 1
  }
}

# in_container <image> <mounted-dir> <sh -c script> - run one script in a
# throwaway container with <dir> at /work, handing the files back owned by
# the caller rather than root. Network is needed for the package install
# each script starts with.
function in_container() {
  local image="$1" dir="$2" script="$3"
  docker run --rm -v "$dir:/work" -w /work \
    -e "HI_UID=$(id -u)" -e "HI_GID=$(id -g)" -e "HI_ARCH=${HI_ARCH:-}" "$image" \
    sh -ec "$script"$'\n''chown -R "$HI_UID:$HI_GID" /work'
}

# --- gpg ------------------------------------------------------------------

_HI_GNUPGHOME=""
function gpg_setup() {
  local have want
  [ -n "$_HI_GPG_KEY" ] || return 0
  [ -f "$_HI_GPG_KEY" ] || {
    _hi_cecho " no such GPG key file: $_HI_GPG_KEY" "$RED" >&2
    return 1
  }
  need gpg
  _HI_GNUPGHOME="$(mktemp -d -t hi.gnupg.XXXXXX)"
  chmod 700 "$_HI_GNUPGHOME"
  gpg --batch --quiet --homedir "$_HI_GNUPGHOME" --import "$_HI_GPG_KEY"
  have="$(gpg --batch --homedir "$_HI_GNUPGHOME" --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
  if [ -n "$_HI_GPG_PUBLIC" ]; then
    want="$(gpg --batch --quiet --homedir "$_HI_GNUPGHOME" --with-colons --show-keys "$_HI_GPG_PUBLIC" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
    [ -n "$want" ] || {
      _hi_cecho " $_HI_GPG_PUBLIC is missing or not a key" "$RED" >&2
      return 1
    }
    [ "$have" = "$want" ] || {
      _hi_cecho " --gpg-key is $have, not the key $_HI_GPG_PUBLIC names ($want)" "$RED" >&2
      return 1
    }
  fi
  gpg --batch --quiet --homedir "$_HI_GNUPGHOME" --armor --export >"$_HI_OUT/say-hi.asc"
  _hi_cecho " | signing with $have" "$BLUE"
}

# gpg_sign <clearsign|detach> <in> <out>
function gpg_sign() {
  local mode="$1" in="$2" out="$3"
  case "$mode" in
  clearsign) gpg --batch --yes --quiet --homedir "$_HI_GNUPGHOME" --digest-algo SHA256 --clearsign -o "$out" "$in" ;;
  detach) gpg --batch --yes --quiet --homedir "$_HI_GNUPGHOME" --digest-algo SHA256 --armor --detach-sign -o "$out" "$in" ;;
  esac
}

# --- apt ------------------------------------------------------------------

# deb_control <deb> - the package's control paragraph, straight out of the
# archive: ar and tar are everywhere, dpkg-deb is not
function deb_control() {
  local member
  member="$(ar t "$1" | grep '^control\.tar' | head -1)"
  case "$member" in
  control.tar.gz) ar p "$1" "$member" | gzip -dc | tar -xOf - ./control ;;
  control.tar.xz) ar p "$1" "$member" | xz -dc | tar -xOf - ./control ;;
  control.tar) ar p "$1" "$member" | tar -xOf - ./control ;;
  *)
    _hi_cecho " unexpected control member in $1: '$member'" "$RED" >&2
    return 1
    ;;
  esac
}

function build_apt() {
  local deb name pool dists arch packages
  deb="$(one_package deb)"
  name="${deb##*/}"
  pool="$_HI_OUT/apt/pool/main/s/say-hi"
  dists="$_HI_OUT/apt/dists/stable"
  _hi_h2 "apt: $name"
  mkdir -p "$pool" "$dists"
  cp -p "$deb" "$pool/$name"
  # one Packages paragraph, with the fields apt-ftparchive would add
  packages="$(mktemp -t hi.packages.XXXXXX)"
  {
    deb_control "$deb" | sed '/^$/d'
    printf 'Filename: pool/main/s/say-hi/%s\n' "$name"
    printf 'Size: %s\n' "$(wc -c <"$deb" | tr -d ' ')"
    printf 'MD5sum: %s\n' "$(openssl dgst -md5 -r "$deb" | cut -d' ' -f1)"
    printf 'SHA1: %s\n' "$(openssl dgst -sha1 -r "$deb" | cut -d' ' -f1)"
    printf 'SHA256: %s\n' "$(sha256_of "$deb")"
    printf '\n'
  } >"$packages"
  for arch in $_HI_DEB_ARCHES; do
    mkdir -p "$dists/main/binary-$arch"
    cp "$packages" "$dists/main/binary-$arch/Packages"
    gzip -9 -n -c "$packages" >"$dists/main/binary-$arch/Packages.gz"
  done
  rm -f "$packages"
  # the Release file: metadata, then a size and hash per index it covers
  {
    printf 'Origin: say-hi\nLabel: say-hi\nSuite: stable\nCodename: stable\n'
    printf 'Date: %s\n' "$(LC_ALL=C TZ=UTC date -u '+%a, %d %b %Y %H:%M:%S UTC')"
    printf 'Architectures: %s\nComponents: main\n' "$_HI_DEB_ARCHES"
    printf 'Description: say-hi - your shell config, on every host you say hi to\n'
    release_hashes "$dists" MD5Sum md5
    release_hashes "$dists" SHA256 sha256
  } >"$dists/Release"
  if [ -n "$_HI_GNUPGHOME" ]; then
    gpg_sign clearsign "$dists/Release" "$dists/InRelease"
    gpg_sign detach "$dists/Release" "$dists/Release.gpg"
  else
    _hi_cecho " | no --gpg-key: the apt Release is unsigned (a client needs [trusted=yes])" "$YELLOW"
  fi
}

# release_hashes <dists-dir> <heading> <openssl-digest> - one hash block of a
# Release file: " <hash> <size> <path relative to dists/stable>" per index
function release_hashes() {
  local dists="$1" heading="$2" algo="$3" f rel
  printf '%s:\n' "$heading"
  for f in "$dists"/main/binary-*/Packages "$dists"/main/binary-*/Packages.gz; do
    rel="${f#"$dists"/}"
    printf ' %s %16s %s\n' "$(openssl dgst "-$algo" -r "$f" | cut -d' ' -f1)" "$(wc -c <"$f" | tr -d ' ')" "$rel"
  done
}

# --- rpm ------------------------------------------------------------------

function build_rpm() {
  local rpm name
  rpm="$(one_package rpm)"
  name="${rpm##*/}"
  _hi_h2 "rpm: $name"
  mkdir -p "$_HI_OUT/rpm"
  cp -p "$rpm" "$_HI_OUT/rpm/$name"
  # rpm-common alongside: librpm wants /usr/lib/rpm/rpmrc and complains on
  # stderr without it
  in_container "$_HI_DEBIAN_IMAGE" "$_HI_OUT/rpm" 'apt-get -qq update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends createrepo-c rpm-common >/dev/null
    createrepo_c --quiet /work'
  if [ -n "$_HI_GNUPGHOME" ]; then
    gpg_sign detach "$_HI_OUT/rpm/repodata/repomd.xml" "$_HI_OUT/rpm/repodata/repomd.xml.asc"
  else
    _hi_cecho " | no --gpg-key: repomd.xml is unsigned (a client needs repo_gpgcheck=0)" "$YELLOW"
  fi
  # the file a dnf user drops into /etc/yum.repos.d/; gpgcheck covers the
  # package (signed by nfpm), repo_gpgcheck the index (signed above)
  cat >"$_HI_OUT/say-hi.repo" <<EOF
[say-hi]
name=say-hi
baseurl=$_HI_BASE_URL/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$_HI_BASE_URL/say-hi.asc
EOF
}

# --- apk ------------------------------------------------------------------

function build_apk() {
  local apk name arch dir keydir="" pkgname pkgver
  apk="$(one_package apk)"
  # apk-tools fetches <pkgname>-<pkgver>.apk, whatever the file was called
  # when it was built, so the repository copy takes that name; both fields
  # come out of the package's own .PKGINFO
  pkgname="$(gzip -dc "$apk" | tar -xOf - .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p' | head -1)"
  pkgver="$(gzip -dc "$apk" | tar -xOf - .PKGINFO 2>/dev/null | sed -n 's/^pkgver = //p' | head -1)"
  [ -n "$pkgname" ] && [ -n "$pkgver" ] || {
    _hi_cecho " no pkgname/pkgver in $apk's .PKGINFO" "$RED" >&2
    return 1
  }
  name="$pkgname-$pkgver.apk"
  _hi_h2 "apk: ${apk##*/} -> $name"
  # the public key served is the one that signed the index - derived from the
  # key in hand, so what a client verifies with is never a stale copy; with
  # no key, the committed one at least names what a release is signed with
  if [ -n "$_HI_APK_KEY" ]; then
    [ -f "$_HI_APK_KEY" ] || {
      _hi_cecho " no such apk key file: $_HI_APK_KEY" "$RED" >&2
      return 1
    }
    openssl rsa -in "$_HI_APK_KEY" -pubout -out "$_HI_OUT/say-hi.rsa.pub" 2>/dev/null
  else
    cp -p "$_HI_ROOT/packaging/apk/say-hi.rsa.pub" "$_HI_OUT/say-hi.rsa.pub"
    _hi_cecho " | no --apk-key: the APKINDEX files are unsigned (a client needs --allow-untrusted)" "$YELLOW"
  fi
  for arch in $_HI_APK_ARCHES; do
    dir="$_HI_OUT/apk/$arch"
    mkdir -p "$dir"
    cp -p "$apk" "$dir/$name"
    if [ -n "$_HI_APK_KEY" ]; then
      # abuild-sign names the signature after the key file plus .pub, and
      # apk-tools looks that name up in /etc/apk/keys - so the key is staged
      # under the name nfpm.yaml's key_name promises, minus the .pub. The
      # public half goes into the container's keyring first: `apk index`
      # refuses a package it cannot verify, which is the check that the apk
      # was signed by this very key.
      keydir="$dir/.keys"
      mkdir -p "$keydir"
      cp "$_HI_APK_KEY" "$keydir/say-hi.rsa"
      cp "$_HI_OUT/say-hi.rsa.pub" "$keydir/say-hi.rsa.pub"
      chmod 600 "$keydir/say-hi.rsa"
      # shellcheck disable=SC2016 # the container's shell expands these
      HI_ARCH="$arch" in_container "$_HI_ALPINE_IMAGE" "$dir" 'cp /work/.keys/say-hi.rsa.pub /etc/apk/keys/
        apk add --no-cache -q abuild >/dev/null
        apk index --quiet --rewrite-arch "$HI_ARCH" -o APKINDEX.tar.gz ./*.apk
        abuild-sign -q -k /work/.keys/say-hi.rsa APKINDEX.tar.gz'
      rm -rf "$keydir"
    else
      # shellcheck disable=SC2016 # the container's shell expands these
      HI_ARCH="$arch" in_container "$_HI_ALPINE_IMAGE" "$dir" 'apk index --quiet --allow-untrusted --rewrite-arch "$HI_ARCH" -o APKINDEX.tar.gz ./*.apk'
    fi
  done
}

# --- main -----------------------------------------------------------------

# sourcing this file defines its functions without building anything, which is
# how the offline packaging suite reaches the index builders. GLOSSARY: HI.06
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

need docker "createrepo_c and apk-tools run in $_HI_ALPINE_IMAGE"
docker info >/dev/null 2>&1 || {
  _hi_cecho " docker is installed but not reachable" "$RED" >&2
  exit 1
}
need ar "binutils"
need openssl

_hi_h1 "Building the package repository"
_hi_cecho " | packages: $_HI_DIST | repo: $_HI_OUT" "$BLUE"
rm -rf "$_HI_OUT"
mkdir -p "$_HI_OUT"
# single quotes on purpose: $_HI_GNUPGHOME is set by gpg_setup, after this
function cleanup() { [ -z "$_HI_GNUPGHOME" ] || rm -rf "$_HI_GNUPGHOME"; }
trap cleanup EXIT
gpg_setup
build_apt
build_rpm
build_apk

if [ -n "$_HI_TARBALL" ]; then
  tar -C "$_HI_OUT" -czf "$_HI_TARBALL" .
  _hi_cecho " $_HI_TARBALL :)" "$GREEN"
fi
_hi_h1 "Repository built"
(cd "$_HI_OUT" && find . -type f | sort | sed 's/^\.\// | /')
