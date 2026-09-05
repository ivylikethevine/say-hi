# Packaging & Releases

How `hi` ships through a package manager, plus [checking a download you did
not build](#verifying-a-release-download) and [regenerating the demo
GIFs](#regenerating-the-demo-gifs). Nothing publishes on its own: the
publishing job waits on a manual approval; the Homebrew tap gets a PR from
the same run once `brew` has passed the formula, and the AUR is updated only
when someone dispatches `publish-external.yml` by hand, once its key exists.
Both signing keys and the tap token are in place; the AUR deploy key is
one-time setup ([AUR](#aur)), tracked in
[README's Roadmap](../README.md#roadmap).

**What is live today: releases, the package repository and the Homebrew
tap, not the AUR.** Every channel on this page is built and tested in CI on
each push; tagged releases exist (`v0.1.1`, `v0.1.2`, …), the apt/rpm/apk
repository is live and signed at
`https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}`, and
`brew install ivylikethevine/tap/say-hi` installs from
[ivylikethevine/homebrew-tap](https://github.com/ivylikethevine/homebrew-tap),
first published by hand and gated on a real Mac. There is still no AUR package (registration is closed); this page
describes that channel as it will ship once there is.

**Runners.** Every job runs on a plain GitHub-hosted label (`ubuntu-latest`,
`macos-latest`, `windows-latest`); none substitutes a machine from a repo/org
Actions variable.

## Contents

- [The one idea](#the-one-idea)
- [Layout](#layout)
- [Channels weighed and not shipped](#channels-weighed-and-not-shipped)
- [Cutting a release](#cutting-a-release)
  - [The release environment](#the-release-environment)
- [Publishing each channel](#publishing-each-channel)
  - [AUR](#aur)
  - [Homebrew tap](#homebrew-tap)
  - [deb / rpm / apk](#deb--rpm--apk)
  - [Package repository](#package-repository)
- [Verifying a packaged build locally](#verifying-a-packaged-build-locally)
  - [Reproducibility](#reproducibility)
- [After installing from a package](#after-installing-from-a-package)
- [Regenerating the demo GIFs](#regenerating-the-demo-gifs)
- [Verifying a release download](#verifying-a-release-download)

## The one idea

`hi.sh` locates itself: it walks `$0` through symlinks and takes the tree from
where it lands, so `/usr/bin/hi` pointing into a package prefix resolves on its
own (GLOSSARY: HI.33), and everything resolves against
`$_HI_ROOT="$_HI_HOME/say-hi"`. A channel owes two things: the tree in a
directory literally named `say-hi`, and `_HI_HOME` exported as that
directory's **parent**, because a _new_ process with no tree to derive from (a
login shell, tmux's `update-environment`, another machine's `hi` probing this
one) has nothing else to read.

| channel            | tree                   | how `_HI_HOME` gets set                                    |
| ------------------ | ---------------------- | ---------------------------------------------------------- |
| AUR, deb, rpm, apk | `/usr/share/say-hi`    | `/etc/profile.d/say-hi.sh`, written by `install_tree`      |
| Homebrew           | `<keg>/libexec/say-hi` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this;
its `_HI_PACKAGE_CONTENTS` and `install_tree()` decide what a packaged install
contains. Both AUR PKGBUILDs and `mkpkg.sh` call it. Only the Homebrew formula
repeats the list, because `install_tree` hardcodes `/usr/bin` and
`/etc/profile.d` and neither exists in a brew prefix;
`tests/packaging/packaging_test.sh` fails if that copy drifts.

## Layout

| path                 | what it is                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| `mkpkg.sh`           | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                                    |
| `stamp.sh`           | writes the version into a built tree's `hi.sh` and man page; every channel calls it              |
| `bump.sh`            | writes the version + real checksums into a release's own manifests; `--check` verifies the write |
| `lib.sh`             | the tree locator and shared primitives `bump.sh` and `mkpkg.sh` source                           |
| `srctar.sh`          | builds the source tarball a release attaches; `bump.sh` checksums the same bytes                 |
| `mkrepo.sh`          | turns the built packages into the apt/rpm/apk [package repository](#package-repository)          |
| `aur/say-hi/`        | the versioned AUR package (`PKGBUILD`, `.SRCINFO`)                                               |
| `aur/say-hi-git/`    | the same package built from `main`                                                               |
| `homebrew/say-hi.rb` | the tap formula                                                                                  |
| `nfpm/nfpm.yaml`     | deb/rpm/apk, built from the staged tree                                                          |
| `gpg/say-hi.asc`     | the public half of the key that signs the rpm and the apt/rpm repository metadata                |
| `apk/say-hi.rsa.pub` | the public half of the key that signs the apk and its `APKINDEX`                                 |

**The version stamp.** `stamp.sh` writes `_HI_RELEASE=` into the installed
`hi.sh` and the version into the man page's `.TH` line. It cannot live in git:
`bump.sh` runs only after the tag exists (its checksums need the tarball), so
a committed stamp would always be one release stale in the tarball Homebrew
and the AUR build from; a checkout answers `hi --version` with `git describe`.
The formula passes `--date <version>`, having no `SOURCE_DATE_EPOCH`;
`stamp.sh` refuses to guess one. `packaging_test.sh` guards all of it.

## Channels weighed and not shipped

**nix**: looked at, and no for now. The derivation is the Homebrew formula's
shape, `$out/share/say-hi` plus a wrapped `$out/bin/hi` that exports
`_HI_HOME`, not `scripts/install.sh --prefix`: `install_tree` hardcodes
`/usr/bin` and `/etc/profile.d`, and neither exists in a store path. If it
ships, it ships as a `flake.nix` in this repo first
(`nix run github:ivylikethevine/say-hi`: no external review, no source hash,
nothing new for `bump.sh`). nixpkgs is where nix users actually look
(`environment.systemPackages`) but means upstream review, a standing
maintainer entry and a fourth manifest to checksum, so it comes later.

Precondition before either: a nix derivation is a _third_ copy of
`_HI_PACKAGE_CONTENTS`, and `tests/packaging/packaging_test.sh` guards only
the formula's today, so the drift guard grows a case before anything is
published. The `/etc/profile.d` snippet, how a _new_ process reads `$_HI_HOME`,
also has no store-path equivalent: a NixOS module (`environment.etc`, or a
`programs.say-hi` option) is not committed to, and under home-manager the
answer stays `install.sh --no-link`, as the formula's `caveats` says.

What would come free: nix builds are hermetic, so the reproducibility
[mkpkg.sh works for](#reproducibility) becomes a property rather than a CI
check, and a `checkPhase` running `--group fast` makes the build itself a
test.

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The tag never moves: the manifests carry checksums of a tarball that cannot
exist before the tag does, so the workflow does the bump. That tarball is one
the release builds, not GitHub's `/archive/` one (nothing could be signed over
it): `packaging/srctar.sh` writes a `git archive --prefix say-hi-<version>/`
of the tag, and that one file is what `bump.sh` checksums, what `mkpkg.sh`
lists in `SHA256SUMS`/`ARTIFACTS`, and what the release attaches.

1. `git tag v1.0.0 && git push origin v1.0.0` — the workflow starts.
2. The `build` job builds `say-hi-1.0.0.tar.gz` from the tag, runs the fast
   suites, runs `bump.sh --tarball <that file> 1.0.0` (writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines) —
   in that job's own disposable checkout, never committed — verifies with
   `bump.sh --check`, runs the packaging drift guards, and builds the
   deb/rpm/apk with one `SHA256SUMS` over the lot. Nothing has published.
3. Approve the `publish` job in the Actions UI — your review point, over the
   exact artifacts `build` produced. Packages, the source tarball,
   `SHA256SUMS` and manifests land on the release, and the package repository
   redeploys to the Pages site (`gh workflow run pages.yml`, since its own
   `workflow_run` trigger cannot fire off a tag push). The manifests committed
   in `packaging/aur/` and `packaging/homebrew/` stay permanent `v0.0.0`
   templates — this workflow never writes to `main`.
4. `brew` installs, tests and audits the formula on a hosted mac against the
   published tarball, and when it passes, `tap` opens a PR against
   [homebrew-tap](https://github.com/ivylikethevine/homebrew-tap) with it
   (`HOMEBREW_TAP_TOKEN`). Merging that PR is yours — the tap has no review
   of its own, so the PR is where the `brew` verdict gets read.
5. Once `AUR_SSH_KEY` exists, dispatch `publish-external.yml` with `tag:
v1.0.0` to push the AUR — a separate, later, manual step so nothing reaches
   that channel just because a tag was pushed. It reads the manifest off the
   release itself (`gh release download`), which is why the templates on
   `main` never need to be current. Until the key exists, copy the manifest
   by hand per [AUR](#aur).

**A release candidate is a GitHub Release and nothing more.** A prerelease
tag - anything with a `-` in it, `v1.0.0-rc.1` - takes steps 1-2 unchanged and
is created `--prerelease --latest=false`, so "the latest release" (README's
badge, the [package repository](#package-repository)) never resolves to a
candidate.
The packages, the source tarball, `SHA256SUMS` and the manifests are attached
as on any release, but no channel job runs and the Pages redeploy is skipped
too - the newest non-prerelease release is unchanged, so there is nothing new
for the site to serve: `0.1.0-rc.1` is valid semver (nfpm's `version_schema`
accepts it; the deb sorts as `0.1.0~rc.1`) and not a legal `pkgver` (`-` is
makepkg's `pkgver-pkgrel` separator), and the AUR is where the manifests go.
The final tag is the first to walk the tap, the AUR and `brew audit`.

`bump.sh 1.0.0` works by hand if CI is unavailable: with the tag in your
checkout it builds the identical tarball itself, `--tarball <file>` takes one
you have, and it downloads the published asset only when neither is available
(during a release the asset does not exist yet). `bump.sh --check 1.0.0`
confirms the manifests match a cut release.

**Release notes are the PRs' `## Release note` sections.** The publish job
asks GitHub's `releases/generate-notes` endpoint for the PRs merged since the
last tag, then `.github/scripts/release_notes.sh` reads each one's
`## Release note` section (the pull request template's) into a
"What changed" list at the top of the release body - the generated titles
below it, the [verification checklist](#verifying-a-release-download) below
those. A section left at `none` contributes nothing, and a release nobody
wrote a note for falls back to the titles alone. Skim
`gh pr list --state merged` before tagging and fix a PR's section in place if
it reads badly; the release run reads the bodies as they are then. The body
is composed rather than passed as `--generate-notes --notes` because `gh`
appends generated notes **after** `--notes`, burying them under the
checklist.

**The body opens with the tag's own badges.** README's tests, kcov and
bashcov badges read the newest green run of `main` and drift with it; the
release body carries the same three figures as static `img.shields.io`
badges, frozen at the tag. The publish job looks each one up by this
commit's sha (`.github/actions/fetch-latest-artifact` with `head-sha`, the
`tests` artifact of `ci.yml` and the two `pct` artifacts of `coverage.yml`)
and a figure that is not there - a tag cut before the sweep finished, an
artifact past its 14-day retention - reads `unknown` in grey rather than
failing the release. Only a release the run creates gets them: an existing
body is never rewritten.

### The release environment

Two repository settings under _Settings → Environments_ that no file in the
tree can set; `release.yml` only names them.

- **`release`** — what `release.yml`'s `publish` and `publish-external.yml`'s
  `aur` both run in (`tap` runs behind `publish`'s approval in the same run
  and needs no gate of its own: it opens a PR). _Required reviewers_: you; that is the approval
  `publish` pauses for, and without it the job publishes unattended.
  _Deployment branches and tags_: a **tag** rule, `v*`, for `publish` running
  on the tag ref - a policy listing only `main` refuses every release with
  `Tag "v1.0.0" is not allowed to deploy to release due to environment
protection rules` — `build` green, `publish` failed, the tag page showing
  source archives alone. The rule is checked when the job starts, so once it
  exists _Re-run failed jobs_ on that run goes on to the approval; no new tag
  is needed. `aur` runs on `workflow_dispatch`, not a tag ref, so add `main`
  (or wherever the dispatch is run from) to the same rule or it hits the
  identical refusal.
- **`manual-dispatch`** — the rehearsal gate. _Required reviewers_: you, or a
  rehearsal's `build` reaches `APK_SIGNING_KEY` with nobody asked. A branch
  rule `main` fits here: a dispatch runs on a branch.
- **`MINISIGN_SECRET_KEY`** — an environment secret on `release` (an
  environment secret shadows a repository one of the same name; edit the one
  that exists). Its value is the **whole** `minisign.key` file `minisign -G
-W` writes: line 1 `untrusted comment: …`, line 2 a 212-character base64
  string. Nothing else works — the `.pub` (57 characters), the base64 line
  alone, or that line truncated, wrapped or indented all fail the signing
  step with `base64 conversion failed - was an actual secret key given?` or
  `Error while loading the secret key file`; a key generated without `-W`
  stops at `Password:` because the runner has no tty (`minisign -C -W -s
minisign.key` strips the passphrase and keeps the pair). Before pasting,
  check the file signs and matches the public key this runbook publishes:

  ```sh
  minisign -R -s minisign.key -p /tmp/check.pub &&
    diff <(sed -n 2p /tmp/check.pub) \
      <(sed -n "s/^minisign -Vm SHA256SUMS -P '\([^']*\)'.*/\1/p" docs/PACKAGING.md)
  ```

  A different pair means a new line under
  [Verifying a release download](#verifying-a-release-download) in the same
  commit, since `publish` reads the key out of it.

## Publishing each channel

The tap is part of the release (`release.yml`'s `tap` job, a PR you merge);
the AUR is behind the manual approval on `publish-external.yml`, which you
dispatch by hand against an already-published tag (`gh workflow run
publish-external.yml -f tag=v1.0.0`, or the Actions UI) once its key exists -
never automatically from a tag push, so the release and reaching the AUR are
two separate decisions. Each section's checks are still yours to run first.

**A `v0.0.x` tag reaches neither, and neither does a prerelease tag.**
`v0.0.x` are debug tags for exercising the release path and a `-` in the name
(`v1.0.0-rc.1`) is a candidate; `brew`, `tap` and `aur` all skip on the tag
name, and the GitHub Release is still created with the packages attached.

### AUR

Not currently doable: AUR registration is closed to new accounts because of
spam. Until it reopens an Arch user runs `makepkg -si` in
`packaging/aur/say-hi-git` (the versioned `say-hi` needs a release tarball, so
before one exists `-git` is the one that builds) and upgrades with `git pull`
and the same command. Run the gate for **each** package, `aur/say-hi-git`
today and `aur/say-hi` once v1.0.0 exists; push nothing while namcap has
complaints about either the `PKGBUILD` or the built package.

`packaging/aur/say-hi/PKGBUILD` in the checkout is a permanent `v0.0.0`
template ([Cutting a release](#cutting-a-release)) - a release never writes
its real version back to `main`. For `say-hi`, download the ones the release
actually built instead of using the checkout:

```bash
gh release download v1.0.0 --pattern PKGBUILD --pattern .SRCINFO --dir /tmp/say-hi-aur
```

```bash
cd packaging/aur/say-hi-git        # then /tmp/say-hi-aur for the say-hi run
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/say-hi/..., /usr/bin/hi, /etc/profile.d/say-hi.sh
```

**A clean run:** `namcap PKGBUILD` is silent, and `namcap` on the built
package prints exactly three warnings, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding. `coreutils` is deliberately not in `depends`;
it is in `base`.

**The end-to-end check**, which caught `say-hi-git` shipping no version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have passed all of this: built, linted, installed into a clean
Arch container, exercised, and removed with nothing left behind.

Then push `PKGBUILD` + `.SRCINFO`, only those two, to
`ssh://aur@aur.archlinux.org/say-hi-git.git`, `say-hi-git` first since it
needs no tag. **That first push is the manual one**, where namcap gates. After
it, dispatching `publish-external.yml` pushes the versioned `say-hi` for any
release but a `v0.0.x` or prerelease tag; `say-hi-git` has no version to bump
and no workflow ever touches it. Never submit the versioned package with
`b2sums=('SKIP')`; `SKIP` is correct only on `say-hi-git`.

### Homebrew tap

The tap is [ivylikethevine/homebrew-tap](https://github.com/ivylikethevine/homebrew-tap):
a plain repo with a `Formula/` directory, so `brew install
ivylikethevine/tap/say-hi` works with no review and no approval on Homebrew's
side, which is why `brew audit --strict` is a hard gate here.

**The copy, the checks and the PR are automated; merging it is not.**
`release.yml`'s `brew` job runs the three commands below on a hosted mac
against the published tarball right after `publish`, filtering out the two
expected findings further down and recording the verdict in its run summary;
when it passes, the `tap` job opens a PR against the tap with the regenerated
formula, linking that run and carrying the same three commands as its
checklist. It needs the `HOMEBREW_TAP_TOKEN` repo secret (a fine-grained PAT
scoped to the tap repo with contents + pull-requests write) and without it
warns and does nothing. Merging the PR is yours, as is repeating the commands
on a mac of your own - against the formula the release actually built, not
the checkout: `packaging/homebrew/say-hi.rb` in the tree is a permanent
`v0.0.0` template ([Cutting a release](#cutting-a-release)), so download the
real one first:

```bash
gh release download v1.0.0 --pattern say-hi.rb --dir /tmp/say-hi-tap
brew install --build-from-source /tmp/say-hi-tap/say-hi.rb
brew test say-hi
brew audit --strict --new say-hi
```

`brew audit` needs a _named_ formula: `brew tap-new ivylikethevine/tap`, copy the file
into its `Formula/`, then `brew audit --strict --new ivylikethevine/tap/say-hi`.

**A clean run** in the `homebrew/brew` container against a local tarball:
install and test exit 0, and audit reports only these two (the repository is
unreachable from that container):

```text
* The homepage URL https://github.com/ivylikethevine/say-hi is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/say-hi.git is not a valid Git URL
```

Two audit findings are already fixed: the description starts with a capital,
and there is no `uses_from_macos "openssh"` (that macro is for formulae macOS
provides _to Homebrew_). The formula declares no dependencies; `ssh` and
`base64` ship with macOS and any Linux that would install this. Use a real mac
before the first publish: the container exercises Linuxbrew's paths, not
`/opt/homebrew`.

### deb / rpm / apk

Built by `mkpkg.sh` and attached to the GitHub Release. Users subscribe to
the [package repository](#package-repository) or install the file:

```bash
sudo apt install ./say-hi_0.1.5_all.deb   # whatever version you downloaded
```

The apk is signed with a key apk verifies against `/etc/apk/keys/`, so Alpine
users install the public key once and never pass `--allow-untrusted`:

```sh
wget -O /etc/apk/keys/say-hi.rsa.pub \
  https://raw.githubusercontent.com/ivylikethevine/say-hi/main/packaging/apk/say-hi.rsa.pub
apk add ./say-hi_0.1.5_noarch.apk   # whatever version you downloaded
```

A quirk: the apk lists its contents per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` rather than riding the `type: tree` entry deb/rpm use, because
nfpm 2.47.0's tree walker writes directory modes apk-tools rejects. The
packaging suite keeps that copy honest, and CI's packaging-smoke installs the
signed apk on Alpine every PR.

### ubi / mise

Neither is a channel this project publishes to - both just point at the
GitHub release. `ubi`'s own auto-detection looks in the source tarball for a
file named exactly `say-hi`, or one starting with it; the entry point is
`hi.sh`, which matches neither, so it needs an explicit hint:

```bash
ubi --project ivylikethevine/say-hi --exe hi.sh
# or, through mise's ubi backend:
mise use "ubi:ivylikethevine/say-hi[exe=hi.sh]"
```

`tests/packaging/packaging_test.sh`'s `test_src_tarball_ships_an_executable_hi_sh`
is the half of this that lives in the tree: `hi.sh` at the tarball root, with
its executable bit intact, is what that hint actually needs to find.

### Package repository

The same deb, rpm and apk, served as an apt, a dnf and an apk repository from
the Pages site, so a package manager upgrades say-hi like anything else:

```sh
# Debian, Ubuntu
sudo curl -fsSLo /etc/apt/keyrings/say-hi.asc https://ivylikethevine.github.io/say-hi/say-hi.asc
echo 'deb [signed-by=/etc/apt/keyrings/say-hi.asc] https://ivylikethevine.github.io/say-hi/apt stable main' |
  sudo tee /etc/apt/sources.list.d/say-hi.list
sudo apt update && sudo apt install say-hi

# Fedora, RHEL and derivatives
sudo curl -fsSLo /etc/yum.repos.d/say-hi.repo https://ivylikethevine.github.io/say-hi/say-hi.repo
sudo dnf install say-hi

# Alpine
wget -O /etc/apk/keys/say-hi.rsa.pub https://ivylikethevine.github.io/say-hi/say-hi.rsa.pub
echo https://ivylikethevine.github.io/say-hi/apk >>/etc/apk/repositories
apk add say-hi
```

**How it is built.** `packaging/mkrepo.sh` turns the packages `mkpkg.sh`
built into `dist/repo/` - `apt/` (`dists/stable`, `pool/`), `rpm/`
(`repodata/`), `apk/{x86_64,aarch64}/`, plus `say-hi.asc`, `say-hi.rsa.pub`
and `say-hi.repo`. The apt indexes it writes itself (`apt-ftparchive` is
Debian-only and the format is small); `createrepo_c` and `apk index` run in
throwaway containers, so a dev box needs docker and gpg and nothing else.
`release.yml`'s `publish` job runs it after the upload, behind the same
approval, and attaches the tree as `package-repo.tar.gz`; `pages.yml` unpacks
that asset from the newest **non-prerelease** release into the site. Only the
latest release is in the repository - older packages stay on their release
pages - and a candidate never reaches a subscriber. `ci.yml`'s packaging-smoke
builds a repository on every PR, and `tests/packaging/repo_test.sh` (the
`e2e` group, on every PR too) installs from one as all three clients,
signatures verified - then installs a `0.0.1` build of the same tree first
and takes the repository's `0.0.2` release as an **upgrade** through
`apt-get`, `dnf upgrade` and `apk add -u`, with an `/etc/say-hi/settings.sh`
and a `~/.config/say-hi/colors` written in between and checked after. Both
versions are named in `repo_test.sh` rather than derived, so the ordering the
upgrade depends on holds in a shallow, tagless checkout too.

**No maintainer scripts, no `conffiles`, on purpose.** Everything a user
writes lives outside the package's paths - the system layer in `/etc/say-hi/`,
the overlay under `$XDG_CONFIG_HOME` - and the package owns only
`/usr/share/say-hi`, `/usr/bin/hi`, `/etc/profile.d/say-hi.sh` and the man
page, none of which a user edits. So an upgrade is a plain file replacement
with nothing to preserve, merge or prompt about, and `nfpm.yaml` stays a
contents list; the upgrade cases above are what keep that claim true.

**What signs what.** One GPG key, the `GPG_SIGNING_KEY` repository secret:
`build` signs the rpm with it through nfpm (`HI_GPG_KEY`, checked by
`dnf gpgcheck=1`), and `publish` signs the apt `Release` (`InRelease`,
`Release.gpg`) and the rpm `repomd.xml` (`repo_gpgcheck=1`). Its public half
is committed as `packaging/gpg/say-hi.asc` and served as `say-hi.asc`; both
jobs refuse a secret whose fingerprint is not that file's, so the key a
client is told to trust is always the one that signed. The `APKINDEX` is
signed with the apk's own key (`APK_SIGNING_KEY`), whose public half the
repository serves as `say-hi.rsa.pub`. A repository secret rather than one
sealed to the `release` environment, for the apk key's reason: `build` is
ungated and only signs what `publish` still has to approve. Without the
secret the rpm builds unsigned and `publish` ships no repository, both
loudly; a signed rpm is the one artifact that is not byte-reproducible
([Reproducibility](#reproducibility)).

**Setting it up, once:**

```sh
gpg --batch --passphrase '' --quick-generate-key 'say-hi packages <ivylikethevine@gmail.com>' rsa4096 sign never
gpg --armor --export-secret-keys 'say-hi packages' >say-hi.gpg.key # -> GPG_SIGNING_KEY, the whole file
gpg --armor --export 'say-hi packages' >packaging/gpg/say-hi.asc    # -> commit
```

RSA 4096 rather than ed25519 because every rpm a supported distro ships
verifies RSA, and EdDSA needs rpm 4.18 (RHEL 8 and 9 have older). No
passphrase, as with the minisign key: nothing at the runner can type one.
Then cut a release and, once Pages has deployed, run the three subscriptions
above from a clean box. Locally, `packaging/mkpkg.sh && packaging/mkrepo.sh`
builds an unsigned `dist/repo/` for a look (`--gpg-key`/`--apk-key` sign it),
and `tests/test_runner.sh repo` is the full proof with throwaway keys.

## Verifying a packaged build locally

For a package **you** just built; [Verifying a release
download](#verifying-a-release-download) is for one somebody downloaded.

```bash
tests/test_runner.sh packaging install header   # the offline drift guards
packaging/mkpkg.sh --stage-only               # inspect exactly what ships
find dist/staging \( -type f -o -type l \)
packaging/mkpkg.sh                            # needs nfpm on PATH
dpkg-deb -c dist/say-hi_*_all.deb
```

### Reproducibility

The same commit builds byte-identical deb/rpm/apk: `mkpkg.sh` exports
`SOURCE_DATE_EPOCH` (HEAD's commit time, respecting a value you set per the
[reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)
convention), clamps the staged tree's mtimes to it, and nfpm stamps everything
else from the same variable. CI's packaging-smoke job double-builds on every
PR. Locally, run the builds sequentially, since `nfpm.yaml` hardcodes
`./dist/staging`:

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

CI pins nfpm 2.47.0 (`.github/actions/setup-tool/tools.txt`); `mkpkg.sh`
takes whatever nfpm is on PATH, so a different local nfpm can produce
different (still internally reproducible) bytes.

The signed rpm is the exception: a GPG signature carries its signing time, so
two builds with `HI_GPG_KEY` set differ in that header alone. The
packaging-smoke double build is unsigned for that reason, and a third, signed
build feeds `mkrepo.sh`. The released rpm's provenance is the attestation and
the signature itself, not a rebuild.

The end-to-end check for the `/etc/profile.d` snippet, which no unit test can
prove:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/say-hi_*_all.deb && echo "$_HI_HOME" && hi'
```

## After installing from a package

The tree is root-owned and holds nobody's settings. Each user runs, once:

```bash
/usr/share/say-hi/scripts/install.sh --no-link
```

`--no-link` skips the `/usr/bin/hi` symlink the package owns. Answers go to
`~/.config/say-hi/`, never into the tree. `hi --update` refuses to `git pull`
and points at the package manager.

**Saying `hi` _to_ a packaged machine works whether or not anyone ran that.**
`hi.sh`'s `_hi_remote_root` probe reads the package's
`/etc/profile.d/say-hi.sh` to find `/usr/share/say-hi` and use it in place,
and `/usr/share` is on the probe's install-prefix list even without that
snippet (GLOSSARY: HI.33). `tests/targets/install_methods_test.sh` installs a
real `.deb`, `.rpm` and `.apk` on real targets and asserts exactly that.

## Regenerating the demo GIFs

[`docs/tapes/generate.sh`](tapes/generate.sh) renders all of them: one `vhs`
run per tape, cheapest first, `fixtures.sh down` in between, and a summary of
what rendered, stood down, or failed. Name tapes for a subset
(`generate.sh docker kube`); `--list` shows them, `--down` clears up after a
crashed run.

**Seven of the eight render themselves.**
[`.github/workflows/demos.yml`](../.github/workflows/demos.yml) runs every tape
but `demo` in CI (installing podman, nomad and kind on a hosted runner as
`ci.yml`'s `e2e-backends` job does) on a tape change, weekly, or on dispatch,
and hands the GIFs to the Pages build, which serves them from `docs/tapes/`
beside each tape and the committed `demo.gif`. Nothing is committed back:
branch protection refuses a bot commit, the same reason the tests badge is
published rather than written into README.

The top-of-README `demo.gif` claims to be the stock defaults, so it is stale
the moment the header, the prompt or the tape changes.
[`.github/hooks/demo_staleness.sh`](../.github/hooks/demo_staleness.sh) compares its
last commit against the tape, the fixtures and the shipped tree; `ci.yml`'s
`advisory-lint` job runs it on every pull request as a warning, and it only
ever warns. To hear it before the push:

```sh
git config core.hooksPath .github/hooks
```

Each tape's header names the persona it is shot for - the ops bastion, the
developer on a shared dev box, the homelab tinkerer, the researcher at a
workstation - and which header configuration and whose prompt is in the
frame; `fixtures.sh`'s `up:<name>` arm writes exactly that settings.sh.
Change the two together, and README's section for the GIF with them.

By hand it is one `vhs docs/tapes/<name>.tape` per GIF from the repo root,
with the backend running and `hi` on PATH; `docs/tapes/fixtures.sh` builds
every target the tapes connect to, `fixtures.sh down` removes them. The set is
organised by **feature**, not backend: each tape shows one thing hi brings
along (the hero, the packages check, the editors, the picker, the overlay, the
colors, completion, one-off commands), with the backends spread across them so
every one is on screen somewhere. Two things the script handles that a hand
run must: `hi` on `$PATH` must be _this_ checkout (the script shims its own
onto the front of `$PATH`), and the sshd target image (`colors`, `run`) builds
from `HEAD`, so uncommitted work shows on the client side of the GIF but not
the target's; render from a commit, or set `HI_DEMO_SOURCE=worktree`, which
the script picks on a dirty tree.

Both sides of every GIF are staged: each tape sources a small rc `fixtures.sh`
writes, giving the outside shell hi's own prompt under a chosen `user@host`,
and every target gets an explicit hostname rather than a random hex ID.

## Verifying a release download

Releases ship a `SHA256SUMS`, signed build provenance, and a detached
[minisign](https://jedisct1.github.io/minisign/) signature over the sums (the
offline half — no `gh`, no network, one static public key):

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

That covers **every** file on the release, `say-hi-<version>.tar.gz` included:
`gh attestation verify say-hi-*.tar.gz --repo ivylikethevine/say-hi` answers
for the sources as the line above does for the `.deb`.
