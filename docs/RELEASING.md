# Releasing

The maintainer's runbook: how `hi` ships through each package manager, what a
`v*` tag sets off, the settings that gate it, and [regenerating the demo
GIFs](#regenerating-the-demo-gifs). Nothing in it is needed to install or use
hi; the user's half - the channels, [checking a download you did not
build](PACKAGING.md#verifying-a-release-download), and what a package leaves
for you to do - is [PACKAGING.md](PACKAGING.md). Nothing publishes without an
intentional act: a signed `v*` tag only you can push, a PR you merge, or a
dispatch by hand.

**Runners.** Every job runs on a plain GitHub-hosted label (`ubuntu-latest`,
`macos-latest`, `windows-latest`); none substitutes a machine from a repo/org
Actions variable.

## Contents

- [The one idea](#the-one-idea)
- [Layout](#layout)
- [Channels weighed and not shipped](#channels-weighed-and-not-shipped)
- [Cutting a release](#cutting-a-release)
  - [Signing the tag](#signing-the-tag)
  - [The release environment](#the-release-environment)
  - [Hardening the release jobs](#hardening-the-release-jobs)
- [Publishing each channel](#publishing-each-channel)
  - [AUR](#aur)
  - [Homebrew tap](#homebrew-tap)
  - [deb / rpm / apk](#deb--rpm--apk)
  - [Package repository](#package-repository)
- [Verifying a packaged build locally](#verifying-a-packaged-build-locally)
  - [Reproducibility](#reproducibility)
- [Regenerating the demo GIFs](#regenerating-the-demo-gifs)

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

**nix**: looked at, and no for now. The derivation would be the Homebrew
formula's shape (`$out/share/say-hi` plus a wrapped `$out/bin/hi` exporting
`_HI_HOME`), not `scripts/install.sh --prefix` - `install_tree` hardcodes
`/usr/bin` and `/etc/profile.d`, neither of which exists in a store path, and
that's a _third_ copy of `_HI_PACKAGE_CONTENTS` for `packaging_test.sh` to
guard before anything ships. It would start as a `flake.nix` here and reach
nixpkgs — where nix users actually look, and which wants upstream review and a
standing maintainer entry — later. The one thing it buys:
[reproducibility](#reproducibility) becomes a property of hermetic builds
rather than a CI check.

## Cutting a release

```bash
git tag -s v1.0.0 -m v1.0.0 && git push origin v1.0.0
```

The tag never moves: the manifests carry checksums of a tarball that cannot
exist before the tag does, so the workflow does the bump. That tarball is one
the release builds, not GitHub's `/archive/` one (nothing could be signed over
it): `packaging/srctar.sh` writes a `git archive --prefix say-hi-<version>/`
of the tag, and that one file is what `bump.sh` checksums, what `mkpkg.sh`
lists in `SHA256SUMS`/`ARTIFACTS`, and what the release attaches.

1. `git tag -s v1.0.0 -m v1.0.0 && git push origin v1.0.0` — the workflow
   starts.
2. The `gate` job refuses a tag that is not `vX.Y.Z` or `vX.Y.Z-<pre>`, whose
   commit is not on `main`, that is lightweight or not signed by a key in
   `.github/allowed_signers` ([Signing the tag](#signing-the-tag)), or whose
   `ci.yml` push run on `main` did not conclude success (it waits for a run
   still going). A red or missing run means fix `main` and cut a new tag.
3. The `build` job builds `say-hi-1.0.0.tar.gz` from the tag, runs the fast
   suites, runs `bump.sh --tarball <that file> 1.0.0` (writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines) —
   in that job's own disposable checkout, never committed — verifies with
   `bump.sh --check`, runs the packaging drift guards, and builds the
   deb/rpm/apk with one `SHA256SUMS` over the lot. Nothing has published.
4. The `publish` job runs unattended over the exact artifacts `build`
   produced — no approval step (see
   [The release environment](#the-release-environment)). Packages, the source tarball,
   `SHA256SUMS`, and manifests land on the release, and the package repository
   redeploys to the Pages site (`gh workflow run pages.yml`, since its own
   `workflow_run` trigger cannot fire off a tag push). This workflow never
   writes to `main`, so the manifests committed in `packaging/aur/` and
   `packaging/homebrew/` stay permanent `v0.0.0` templates.
5. `brew` installs, tests, and audits the formula on a hosted mac against the
   published tarball, and when it passes, `tap` opens a PR against
   [homebrew-tap](https://github.com/ivylikethevine/homebrew-tap) with it
   (`HOMEBREW_TAP_TOKEN`). The tap runs its own CI on that PR (`brew style`,
   `brew audit`, install, and test on macOS and Linux); merging it is yours.
6. Once `AUR_SSH_KEY` exists, dispatch `publish-external.yml` with `tag:
v1.0.0` to push the AUR — a separate, later, manual step so nothing reaches
   that channel just because a tag was pushed. It reads the manifest off the
   release itself (`gh release download`), never the template. Until the key
   exists, copy the manifest by hand per [AUR](#aur).

**A release candidate is a GitHub Release and nothing more.** A prerelease
tag - anything with a `-` in it, `v1.0.0-rc.1` - takes steps 1-4 unchanged and
is created `--prerelease --latest=false`, so "the latest release" (README's
badge, the [package repository](#package-repository)) never resolves to a
candidate.
The packages, the source tarball, `SHA256SUMS`, and the manifests are attached
as on any release, but no channel job runs and the Pages redeploy is skipped
too - the newest non-prerelease release is unchanged, so there is nothing new
for the site to serve: `0.1.0-rc.1` is valid semver (nfpm's `version_schema`
accepts it; the deb sorts as `0.1.0~rc.1`) and not a legal `pkgver` (`-` is
makepkg's `pkgver-pkgrel` separator), and the AUR is where the manifests go.
The final tag is the first to walk the tap, the AUR, and `brew audit`.

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
below it, the
[verification checklist](PACKAGING.md#verifying-a-release-download) below
those. A section left at `none` contributes nothing, and a release nobody
wrote a note for falls back to the titles alone. Every non-draft PR is
linted for the section by `release-note.yml` (the `release note (pr body)`
check, re-run on each body edit): a missing heading, or one with only
whitespace and comments under it, fails; `none` passes. `dev` → `main` PRs
are held to it too - theirs is the body a release lists - and only
Dependabot's skip. Skim
`gh pr list --state merged` before tagging and fix a PR's section in place if
it reads badly; the release run reads the bodies as they are then.

**The body opens with the tag's own badges.** README's tests, kcov, and
bashcov badges track the newest green `main`; the release body freezes the
same three figures at the tag, looked up by this commit's sha
(`.github/actions/fetch-latest-artifact` with `head-sha`). A figure that is
not there - a tag cut before the sweep finished, an artifact past its 14-day
retention - reads `unknown` in grey rather than failing the release. Only a
release the run creates gets them: an existing body is never rewritten.

### Signing the tag

Tags are SSH-signed (`gpg.format=ssh`), and the trust root is
`.github/allowed_signers`: three SSH keys, each one of the maintainer's
signing keys registered on GitHub. The `gate` job runs `git tag -v` against
that file as committed on `main`, with the global and system git configs
ignored, so a lightweight tag, an unsigned one, or one signed by any other
key is refused before `build` starts. Checking a tag locally before pushing
it is the same command:

```sh
git -c gpg.ssh.allowedSignersFile=.github/allowed_signers tag -v v1.0.0
```

**Rotating a key:** add the new key's line to `.github/allowed_signers` in a
PR and merge it to `main` _before_ tagging with it - the gate reads `main`'s
copy, so a tag signed by a key only on a branch is refused. Drop a retired
key only once no tag still to be released needs it.

### The release environment

Two repository settings under _Settings → Environments_ that no file in the
tree can set; `release.yml` only names them.

- **`release`** — what `release.yml`'s `publish` (and `build`, on a tag push)
  and `publish-external.yml`'s `aur` run in (`tap` runs behind `publish` in
  the same run and needs no gate of its own: it opens a PR). _Required reviewers_: **none** - the gates
  are the tag protection on `v*`, so whoever can push the tag has already made
  the decision, and the `gate` job, so the tag is well-formed, signed by an
  allowed key, and on a commit CI already passed on `main`; a release runs
  unattended from tag to tap PR. (Adding a reviewer here is what would
  pause it, and nothing in the tree can set that.)
  _Deployment branches and tags_: a **tag** rule, `v*`, for `build` and
  `publish` running on the tag ref - a policy listing only `main` refuses
  every release at `build`. The rule is checked when the job starts,
  so once it exists _Re-run failed jobs_ on that run goes straight through;
  no new tag is needed. `aur` runs on `workflow_dispatch`, not a tag ref, so add `main`
  (or wherever the dispatch is run from) to the same rule or it hits the
  identical refusal.
- **`manual-dispatch`** — the rehearsal gate: `gate` runs in it on a
  `workflow_dispatch` (and only then, so a tag push never waits on it), and
  `build` waits on `gate`. _Required reviewers_: you, or a rehearsal starts a
  build with nobody asked. A rehearsal's `build` runs
  outside `release`, so it never sees the signing keys and its apk and rpm
  come out unsigned. A branch rule `main` fits here: a dispatch runs on a
  branch.
- **`MINISIGN_SECRET_KEY`**, **`APK_SIGNING_KEY`**, **`GPG_SIGNING_KEY`**,
  **`AUR_SSH_KEY`** — environment secrets on `release`, never repository
  secrets, so only a job running in that environment can read them: `build`
  and `publish` on a tag push, and `publish-external.yml`'s `aur`. A
  rehearsal's `build` runs outside it and sees none. The two package keys are covered under
  [Package repository](#package-repository)'s _What signs what_; the rest of
  this entry is the minisign key's. `MINISIGN_SECRET_KEY` is an environment secret (an
  environment secret shadows a repository one of the same name; edit the one
  that exists). Its value is the **whole** `minisign.key` file `minisign -G -W`
  writes - both lines, unwrapped and unindented; anything less fails the
  signing step. Generate it with `-W`, or the runner, having no tty, stops at
  `Password:` (`minisign -C -W -s minisign.key` strips a passphrase from an
  existing pair). Before pasting, check the file signs and matches the public
  key [PACKAGING.md](PACKAGING.md#verifying-a-release-download) publishes:

  ```sh
  minisign -R -s minisign.key -p /tmp/check.pub &&
    diff <(sed -n 2p /tmp/check.pub) \
      <(sed -n "s/^minisign -Vm SHA256SUMS -P '\([^']*\)'.*/\1/p" docs/PACKAGING.md)
  ```

  A different pair means a new line under
  [Verifying a release download](PACKAGING.md#verifying-a-release-download)
  in the same commit, since `publish` reads the key out of it.

### Hardening the release jobs

Every job in `release.yml` and `publish-external.yml` starts with
`step-security/harden-runner`. Most run it in `audit`, which records each
job's outbound connections without refusing any. The three that hold a
publishing credential run `block` with an allowlist instead: `publish` (the
signing keys and a `contents: write` token), `tap` (`HOMEBREW_TAP_TOKEN`),
and `publish-external.yml`'s `aur` (`AUR_SSH_KEY`). Each allowlist was read
off the job's steps rather than a recorded run, and its comment names what
each host is for. A release's run summary links the harden-runner insights
for every job: tighten or extend an allowlist from those - a host that
`block` refused shows there - rather than by guessing. `brew` stays on
`audit`, since harden-runner has no block mode on macOS.

## Publishing each channel

The tap is a PR you merge; the AUR is a dispatch you run against an
already-published tag (`gh workflow run publish-external.yml -f tag=v1.0.0`,
or the Actions UI). Each section's checks are yours to run first.

`brew`, `tap`, and `aur` all skip on the tag name, so neither a `v0.0.x` debug
tag nor a candidate (`-` in the name) reaches a channel; the GitHub Release is
still created with the packages attached.

### AUR

Not currently doable: AUR registration is closed to new accounts because of
spam; what an Arch user does meanwhile is [PACKAGING.md's
AUR](PACKAGING.md#aur). Run the gate for **each** package, `aur/say-hi-git`
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

**The end-to-end check:**

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Then push `PKGBUILD` + `.SRCINFO`, only those two, to
`ssh://aur@aur.archlinux.org/say-hi-git.git`, `say-hi-git` first since it
needs no tag. **That first push is the manual one**, where namcap gates. After
it, dispatching `publish-external.yml` pushes the versioned `say-hi` for any
release but a `v0.0.x` or prerelease tag; `say-hi-git` has no version to bump
and no workflow ever touches it. Never submit the versioned package with
`b2sums=('SKIP')`; `SKIP` is correct only on `say-hi-git`.

### Homebrew tap

What the tap is, for the people installing from it, is
[PACKAGING.md's Homebrew tap](PACKAGING.md#homebrew-tap): a plain repo, so
nothing on Homebrew's side reviews what lands there, which is why
`brew audit --strict` is a hard gate here.

**The copy, the checks, and the PR are automated; merging it is not.**
`release.yml`'s `brew` job runs the three commands below on a hosted mac
against the published tarball right after `publish`, filtering out the two
expected findings further down and recording the verdict in its run summary;
when it passes, the `tap` job opens a PR against the tap with the regenerated
formula (its header rewritten for the tap by `.github/scripts/tap_formula.sh`),
linking that run, and links that PR (or the tap's formula, when it is already
current) from the release body. The
[tap](https://github.com/ivylikethevine/homebrew-tap) runs its own CI on the
PR: `brew style`, `brew audit`, install, and test, on macOS and Linux. It
needs the `HOMEBREW_TAP_TOKEN` repo secret (a fine-grained PAT
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

The description starts with a capital and there is no
`uses_from_macos "openssh"` — that macro is for formulae macOS provides _to
Homebrew_. The formula declares no dependencies; `ssh` and
`base64` ship with macOS and any Linux that would install this. Use a real mac
before the first publish: the container exercises Linuxbrew's paths, not
`/opt/homebrew`.

### deb / rpm / apk

Built by `mkpkg.sh` and attached to the GitHub Release; how a user installs
one is [PACKAGING.md's deb / rpm / apk](PACKAGING.md#deb--rpm--apk).

A quirk: the apk lists its contents per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` rather than riding the `type: tree` entry deb/rpm use, because
nfpm 2.47.0's tree walker writes directory modes apk-tools rejects. The
packaging suite keeps that copy honest, and CI's packaging-smoke installs the
signed apk on Alpine every PR.

### Package repository

What a subscriber gets is
[PACKAGING.md's Package repository](PACKAGING.md#package-repository); this is
how it is built and signed.

**How it is built.** `packaging/mkrepo.sh` turns the packages `mkpkg.sh`
built into `dist/repo/` - `apt/` (`dists/stable`, `pool/`), `rpm/`
(`repodata/`), `apk/{x86_64,aarch64}/`, plus `say-hi.asc`, `say-hi.rsa.pub`,
and `say-hi.repo`. The apt indexes it writes itself (`apt-ftparchive` is
Debian-only and the format is small); `createrepo_c` and `apk index` run in
throwaway containers, so a dev box needs docker and gpg and nothing else.
`release.yml`'s `publish` job runs it after the upload, behind the same
gates, and attaches the tree as `package-repo.tar.gz`; `pages.yml` unpacks
that asset from the newest **non-prerelease** release into the site. Only the
latest release is in the repository - older packages stay on their release
pages - and a candidate never reaches a subscriber. `ci.yml`'s packaging-smoke
builds a repository on every PR, and `tests/packaging/repo_test.sh` (the
`e2e` group, on every PR too) installs from one as all three clients,
signatures verified - then installs a `0.0.1` build of the same tree first
and takes the repository's `0.0.2` release as an **upgrade** through
`apt-get`, `dnf upgrade`, and `apk add -u`, with a `~/.config/say-hi/colors`
written in between and checked after. Both
versions are named in `repo_test.sh` rather than derived, so the ordering the
upgrade depends on holds in a shallow, tagless checkout too.

**What signs what.** One GPG key, the `GPG_SIGNING_KEY` secret:
`build` signs the rpm with it through nfpm (`HI_GPG_KEY`, checked by
`dnf gpgcheck=1`), and `publish` signs the apt `Release` (`InRelease`,
`Release.gpg`) and the rpm `repomd.xml` (`repo_gpgcheck=1`). Its public half
is committed as `packaging/gpg/say-hi.asc` and served as `say-hi.asc`; both
jobs refuse a secret whose fingerprint is not that file's, so the key a
client is told to trust is always the one that signed. The `APKINDEX` is
signed with the apk's own key (`APK_SIGNING_KEY`), whose public half the
repository serves as `say-hi.rsa.pub`. Both are environment secrets on
`release`, so only a tag push's `build` and `publish` can read them; a
rehearsal builds unsigned. Without the
secret the rpm builds unsigned and `publish` ships no repository, both
loudly. A signed rpm is the one artifact that is not byte-reproducible
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
in [README.md's Installation](../README.md#installation) from a clean box.
Locally, `packaging/mkpkg.sh && packaging/mkrepo.sh` builds an unsigned
`dist/repo/` for a look (`--gpg-key`/`--apk-key` sign it), and
`tests/test_runner.sh repo` is the full proof with throwaway keys.

## Verifying a packaged build locally

For a package **you** just built; [Verifying a release
download](PACKAGING.md#verifying-a-release-download) is for one somebody
downloaded.

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

The signed rpm is the exception, because a GPG signature carries its signing
time: two builds with `HI_GPG_KEY` set differ in that header alone. The
packaging-smoke double build is unsigned for that reason, and a third, signed
build feeds `mkrepo.sh`. The released rpm's provenance is the attestation and
the signature itself, not a rebuild.

The end-to-end check for the `/etc/profile.d` snippet, which no unit test can
prove:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/say-hi_*_all.deb && echo "$_HI_HOME" && hi'
```

## Regenerating the demo GIFs

[`docs/tapes/generate.sh`](https://github.com/ivylikethevine/say-hi/blob/main/docs/tapes/generate.sh) renders all of them: one `vhs`
run per tape, cheapest first, `fixtures.sh down` in between, and a summary of
what rendered, stood down, or failed. Name tapes for a subset
(`generate.sh docker kube`); `--list` shows them, `--down` clears up after a
crashed run. `--version <v>` puts `<v>` in the header's version cell (and in
`hi --version`, on both ends of the wire) instead of `git describe`, so a
release's GIFs can be rendered before its tag exists.

**Six of the seven render themselves.**
[`.github/workflows/demos.yml`](https://github.com/ivylikethevine/say-hi/blob/main/.github/workflows/demos.yml) runs every tape
but `demo` in CI (installing podman, nomad, and kind on a hosted runner as
`ci.yml`'s `e2e-backends` job does) for each release, weekly, or on dispatch,
and hands the GIFs to the Pages build, which serves them from `docs/tapes/`
beside each tape and the committed `demo.gif`. One runner per tape, in
parallel - a `collect` job merges the six into the single `demo-gifs` artifact
Pages fetches, and is skipped if any tape failed, so the site never mixes a
fresh render with a stale one. For a release, `release.yml`'s publish job
dispatches the workflow at the tag, and its `attach` job uploads the
`packages` GIF to that release as `demo.gif` and embeds it in the body. A tape added to `generate.sh`'s roster has to
be added to that workflow's `tape` matrix as well. Nothing is committed back:
branch protection refuses a bot commit, the same reason the tests badge is
published rather than written into README.

The top-of-README `demo.gif` claims to be the stock defaults, so it is stale
the moment the header, the prompt, or the tape changes; re-render it by hand
when one of those moves.

Each tape's header names the persona it is shot for, and which header
configuration and whose prompt is in the frame; `fixtures.sh`'s `up:<name>`
arm writes exactly that settings.sh. Change the two together, and README's
section for the GIF with them. Both sides of every GIF are staged — the
outside shell gets hi's own prompt under a chosen `user@host`, and every
target an explicit hostname rather than a random hex ID.

The set is organised by **feature**, not backend, with the backends spread
across the tapes so every one is on screen somewhere. A hand render is one
`vhs docs/tapes/<name>.tape` from the repo root with the backend up; the two
things it has to get right that `generate.sh` handles (which `hi` is on
`$PATH`, and a dirty tree's client/target split) are that script's header.
