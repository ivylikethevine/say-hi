# Packaging

Installing `hi` from a package: [which channels exist](#install-channels),
[checking a download you did not build](#verifying-a-release-download), and
[what a package leaves for you to do](#after-installing-from-a-package). How
each channel is built, signed, and published is the maintainer's runbook,
[RELEASING.md](RELEASING.md).

## Contents

- [Install channels](#install-channels)
  - [Package repository](#package-repository)
  - [deb / rpm / apk](#deb--rpm--apk)
  - [Homebrew tap](#homebrew-tap)
  - [AUR](#aur)
  - [ubi / mise](#ubi--mise)
- [Verifying a release download](#verifying-a-release-download)
- [After installing from a package](#after-installing-from-a-package)

## Install channels

**Live today: releases, the package repository, and the Homebrew tap; not the
AUR.** Tagged releases exist from `v0.1.0` on, the apt/rpm/apk repository is
live and signed at `https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}`,
and `brew install ivylikethevine/tap/say-hi` installs from
[ivylikethevine/homebrew-tap](https://github.com/ivylikethevine/homebrew-tap).
A clone plus `scripts/install.sh` needs none of these
([README.md's Installation](../README.md#installation)). Channels weighed and
not shipped, with the reason, are
[RELEASING.md's list](RELEASING.md#channels-weighed-and-not-shipped).

### Package repository

The same deb, rpm, and apk, served as an apt, a dnf, and an apk repository from
the Pages site, so a package manager upgrades say-hi like anything else; the
subscribe commands are in [README.md's Installation](../README.md#installation).
Only the latest release is in the repository - older packages stay on their
release pages - and a release candidate never reaches a subscriber.

**Signed end to end.** One GPG key, served as `say-hi.asc`, signs the rpm and
the apt/rpm repository metadata; an RSA key, served as `say-hi.rsa.pub`, signs
the apk and its `APKINDEX`. Which secret signs what, and how the keys were
made, is [RELEASING.md's Package repository](RELEASING.md#package-repository).

**No maintainer scripts, no `conffiles`, on purpose.** Everything a user
writes lives outside the package's paths - the overlay under
`$XDG_CONFIG_HOME` - and the package owns only
[files no user edits](FILES.md#packaged-installs). So an upgrade is a plain
file replacement with nothing to preserve, merge, or prompt about;
`tests/packaging/repo_test.sh`'s upgrade cases, which write a
`~/.config/say-hi/colors` between two versions and check it after, keep that
claim true.

### deb / rpm / apk

Attached to every GitHub Release. Subscribe to the
[package repository](#package-repository) or install the file:

```bash
sudo apt install ./say-hi_*_all.deb   # the version you downloaded
```

The apk is signed with a key apk verifies against `/etc/apk/keys/`, so Alpine
users install the public key once and never pass `--allow-untrusted`:

```sh
wget -O /etc/apk/keys/say-hi.rsa.pub \
  https://ivylikethevine.github.io/say-hi/say-hi.rsa.pub
apk add ./say-hi_*_noarch.apk   # the version you downloaded
```

### Homebrew tap

The tap is [ivylikethevine/homebrew-tap](https://github.com/ivylikethevine/homebrew-tap):
a plain repo with a `Formula/` directory, so `brew install
ivylikethevine/tap/say-hi` works with no review and no approval on Homebrew's
side. Then run `hi --install` once, as for any package. The formula declares
no dependencies: `ssh` and `base64` ship with macOS and any Linux that would
install this.

Each release (not a candidate) opens a PR against the tap with the new
formula, checked by the tap's own CI before it is merged, so the tap can trail
a release by that merge. Bugs in hi go to this repository
([SUPPORT.md](SUPPORT.md)), not the tap. How the formula is generated and
gated is [RELEASING.md's Homebrew tap](RELEASING.md#homebrew-tap).

### AUR

Not yet: AUR registration is closed to new accounts because of spam. Until it
reopens, an Arch user runs `makepkg -si` in `packaging/aur/say-hi-git` and
upgrades with `git pull` and the same command, or runs it over the `PKGBUILD`
and `SRCINFO` attached to a release (the checkout's `aur/say-hi` is a
`v0.0.0` template). The publishing gate for once it reopens is
[RELEASING.md's AUR](RELEASING.md#aur).

### ubi / mise

Neither is a channel this project publishes to - both just point at the
GitHub release. `ubi`'s auto-detection looks in the source tarball for a file
named exactly `say-hi`, or one starting with it; the entry point is `hi.sh`,
which matches neither, so it needs an explicit hint:

```bash
ubi --project ivylikethevine/say-hi --exe hi.sh
# or, through mise's ubi backend:
mise use "ubi:ivylikethevine/say-hi[exe=hi.sh]"
```

`tests/packaging/packaging_ci_test.sh`'s `test_src_tarball_ships_an_executable_hi_sh`
holds the tree's half: `hi.sh` at the tarball root, executable bit intact.

## Verifying a release download

Releases ship a `SHA256SUMS`, signed build provenance, an SPDX SBOM, and a
detached [minisign](https://jedisct1.github.io/minisign/) signature over the
sums (the offline half — no `gh`, no network, one static public key):

```sh
sha256sum -c --ignore-missing SHA256SUMS                        # the bytes match the release
minisign -Vm SHA256SUMS -P 'RWR2I3MAqExrIMvAdepnWzlWlaWyvb6bEJiFmsU6lAoE10FnZPSizkAA'
gh attestation verify say-hi_*_all.deb --repo ivylikethevine/say-hi # which CI run built them
```

**That `minisign` line is load-bearing.** `release.yml`'s publish job `sed`s
the public key out of it into every release body's checklist and fails the
release if the pattern stops matching, so the key has one copy in the tree.
Keep it a single line starting `minisign -Vm SHA256SUMS -P '`, with the key in
single quotes.

The sums and the attestation cover the deb, rpm, apk, and
`say-hi-<version>.tar.gz`:
`gh attestation verify say-hi-*.tar.gz --repo ivylikethevine/say-hi` answers
for the sources as the line above does for the `.deb`. The other assets (the
manifests, the SBOM, `package-repo.tar.gz`, and `demo.gif`, uploaded later by
[the demos workflow](RELEASING.md#regenerating-the-demo-gifs)) are not in
`SHA256SUMS`.

## After installing from a package

The tree is root-owned and holds nobody's settings. Each user runs, once:

```bash
hi --install
```

The package's `/usr/bin/hi` is already on `PATH` and runs this tree, so the
install makes no link of its own (and never touches a link a package owns).
Answers go to `~/.config/say-hi/`, never into the tree. `hi --update` refuses
to move a packaged tree and points at the package manager.

**Saying `hi` _to_ a packaged machine works whether or not anyone ran that.**
A session ships its own tree to every ssh target and runs out of that, so the
package on the far end is neither needed nor read — it is there for that
machine's own shells, which its `/etc/profile.d/say-hi.sh` wires up at login.
`tests/targets/install_methods_test.sh` installs a real `.deb`, `.rpm`, and
`.apk` on real targets and asserts exactly that: the session works, out of its
own tree, and the installed one is untouched afterwards. Where every packaged
file lands is [FILES.md's Packaged installs](FILES.md#packaged-installs).
