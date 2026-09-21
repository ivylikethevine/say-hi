# Releasing

The maintainer's runbook: how `hi` ships through each package manager, what a
`v*` tag sets off, the settings that gate it, and [regenerating the demo
GIFs](#regenerating-the-demo-gifs). Installing, verifying a download, and what
a package leaves the user to do are [PACKAGING.md](PACKAGING.md). Nothing
publishes without an intentional act: a signed `v*` tag only you can push, a
PR you merge, or a dispatch by hand.

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
contains, and both AUR PKGBUILDs and `mkpkg.sh` call it. Two places repeat the
list, and `tests/packaging/packaging_test.sh` fails if either drifts: the
Homebrew formula, because `install_tree` hardcodes `/usr/bin` and
`/etc/profile.d` and neither exists in a brew prefix, and `nfpm.yaml`'s apk
entries ([deb / rpm / apk](#deb--rpm--apk)).

## Layout

Under `packaging/`:

| path                 | what it is                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| `mkpkg.sh`           | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                                    |
| `stamp.sh`           | writes the version into a built tree's `hi.sh` and man page; every channel calls it              |
| `stamp_badge.sh`     | writes README's `ssh_payload` badge from a pinned measurement; `--check` is `--group bench`'s    |
| `bump.sh`            | writes the version + real checksums into a release's own manifests; `--check` verifies the write |
| `lib.sh`             | the tree locator and shared primitives the other scripts (and `release.yml`) source              |
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
`_HI_HOME`), not `scripts/install.sh --prefix`, for the same reason the
formula is — and that is one more copy of `_HI_PACKAGE_CONTENTS` for
`packaging_test.sh` to guard. It would start as a `flake.nix` here and reach
nixpkgs (where nix users look, and which wants upstream review and a standing
maintainer entry) later. The one thing it buys:
[reproducibility](#reproducibility) becomes a property of hermetic builds
rather than a CI check.

## Cutting a release

The tag never moves: the manifests carry checksums of a tarball that cannot
exist before the tag does, so the workflow does the bump. That tarball is one
the release builds, not GitHub's `/archive/` one (nothing could be signed over
it): `packaging/srctar.sh` writes a `git archive --prefix say-hi-<version>/`
of the tag, and that one file is what `bump.sh` checksums, what `mkpkg.sh`
lists in `SHA256SUMS`/`ARTIFACTS`, and what the release attaches.

1. `git tag -s v1.0.0 -m v1.0.0 && git push origin v1.0.0` — `release.yml`
   starts.
2. The `gate` job refuses a tag that is not `vX.Y.Z` or `vX.Y.Z-<pre>`, whose
   commit is not on `main`, that is lightweight or not signed by a key in
   `.github/allowed_signers` ([Signing the tag](#signing-the-tag)), or whose
   `ci.yml` push run on `main` did not conclude success (it waits for a run
   still going). A red or missing run means fix `main` and cut a new tag.
   Once it passes, the `upgrade` job walks
   [HI.60](GLOSSARY.md#hi60-a-shell-that-outlives-the-tree) from the previous
   `v*` tag: a bash, zsh, and fish shell each load that release's rc, the
   tag's tree replaces it underneath, and the rc is sourced again
   (`.github/scripts/upgrade_path.sh`); any stderr, or a path left empty,
   refuses the build.
3. The `build` job builds `say-hi-1.0.0.tar.gz` from the tag and runs
   `bump.sh --tarball <that file> 1.0.0` (writes `pkgver`, `b2sums`, the
   formula `url`/`sha256`, and the derivable `.SRCINFO` lines) in its own
   disposable checkout, never committed, then `bump.sh --check`. The fast
   group (the packaging drift guards included, now against the bumped
   manifests) and the lint group run next; then it builds the deb/rpm/apk with
   one `SHA256SUMS` over them and the tarball, and attests their provenance
   and an SBOM. Nothing has published.
4. The `publish` job runs unattended over exactly what `build` produced (see
   [The release environment](#the-release-environment)): it signs
   `SHA256SUMS` with minisign, creates the release, attaches the packages,
   tarball, sums, signature, manifests, SBOM, and attestation bundle, builds
   and attaches the [package repository](#package-repository), and dispatches
   `pages.yml` (its own `workflow_run` trigger cannot fire off a tag push) and
   `demos.yml`. This workflow never writes to `main`, so the manifests
   committed in `packaging/aur/` and `packaging/homebrew/` stay permanent
   `v0.0.0` templates — for a channel, always use the ones the release
   attached (`gh release download v1.0.0 --pattern …`).
5. `brew` installs, tests, and audits the formula on a hosted mac, and when it
   passes, `tap` opens a PR against the tap ([Homebrew tap](#homebrew-tap));
   merging it is yours.
6. Once `AUR_SSH_KEY` exists, dispatch `publish-external.yml` with
   `tag: v1.0.0` to push the AUR, a separate, later, manual step. It reads
   the manifest off the release itself, never the template. Until the key
   exists, copy the manifest by hand per [AUR](#aur).

**A rehearsal** — dispatching `release.yml` with a `version` — runs `gate`
(waiting on `manual-dispatch` approval) and `build` against the branch's HEAD,
unsigned, and publishes nothing.

**A release candidate is a GitHub Release and nothing more.** A tag with a `-`
(`v1.0.0-rc.1`) runs steps 1-4, is created `--prerelease --latest=false` so
"the latest release" (README's badge, the package repository) never resolves
to it, and skips the Pages redeploy, since the newest non-prerelease release
is unchanged. `brew`, `tap`, and `aur` skip it, as they skip a `v0.0.x` debug
tag: `0.1.0-rc.1` is valid semver (nfpm's `version_schema` accepts it; the deb
sorts as `0.1.0~rc.1`) but not a legal `pkgver` (`-` is makepkg's
`pkgver-pkgrel` separator).

`bump.sh 1.0.0` works by hand if CI is unavailable: with the tag in your
checkout it builds the identical tarball itself, `--tarball <file>` takes one
you have, and it downloads the published asset only when neither is available
(during a release the asset does not exist yet). `bump.sh --check 1.0.0`
confirms the manifests match a cut release.

**Release notes are the PRs' `## Release note` sections.** `publish` asks
GitHub's `releases/generate-notes` endpoint for the PRs merged since the last
tag, and `.github/scripts/release_notes.sh` puts each one's section (the pull
request template's) into a "What changed" list at the top of the body, above
the generated titles and the
[verification checklist](PACKAGING.md#verifying-a-release-download). A section
reading `none` contributes nothing; a release with no notes falls back to the
titles. `release-note.yml` (the `release note (pr body)` check, re-run on each
body edit) fails any non-draft PR, `dev` → `main` included and only
Dependabot's exempt, whose section is missing or holds only whitespace and
comments. Skim `gh pr list --state merged` before tagging and fix a section in
place if it reads badly; the release reads the bodies as they are then.

**The body opens with the tag's own badges.** README's tests, kcov, and
bashcov badges track the newest green `main`; the release body freezes the
same three figures at the tag, looked up by its commit's sha
(`.github/actions/fetch-latest-artifact` with `head-sha`). A figure that is
not there (a tag cut before the sweep finished, an artifact past its
retention) reads `unknown` in grey rather than failing the release. Only a
release the run creates gets them: an existing body is never rewritten.

### Signing the tag

Tags are SSH-signed (`gpg.format=ssh`), and the trust root is
`.github/allowed_signers`: three SSH keys, each one of the maintainer's
signing keys registered on GitHub. The `gate` job runs `git tag -v` against
that file as of the tagged commit, which it has already required to be on
`main`, with the global and system git configs ignored. Checking a tag
locally before pushing it is the same command:

```sh
git -c gpg.ssh.allowedSignersFile=.github/allowed_signers tag -v v1.0.0
```

**Rotating a key:** merge the new key's line to `main` _before_ the commit you
tag with it — a tag on an older commit reads that commit's copy and is
refused. Drop a retired key only once no tag still to be released needs it.

### The release environment

Two environments under _Settings → Environments_ and five secrets, none of
which a file in the tree can set; the workflows only name them.

- **`release`** — what `release.yml`'s `publish` (and `build`, on a tag push)
  and `publish-external.yml`'s `aur` run in. `tap` runs behind `publish` and
  needs no gate of its own: it opens a PR. _Required reviewers_: **none** -
  the gates are the tag protection on `v*` (whoever can push the tag has made
  the decision) and the `gate` job, so a release runs unattended from tag to
  tap PR; a reviewer here is what would pause it. _Deployment branches and
  tags_: a **tag** rule, `v*`, for `build` and `publish` on the tag ref (a
  policy listing only `main` refuses every release at `build`), plus `main`,
  or wherever `aur` is dispatched from, since a dispatch runs on a branch. The
  rule is checked when the job starts, so once it is fixed _Re-run failed
  jobs_ goes straight through; no new tag is needed.
- **`manual-dispatch`** — the rehearsal gate: `gate` runs in it on a
  `workflow_dispatch` only, so a tag push never waits on it. _Required
  reviewers_: you, or a rehearsal starts a build with nobody asked. A branch
  rule `main` fits.
- **`MINISIGN_SECRET_KEY`**, **`APK_SIGNING_KEY`**, **`GPG_SIGNING_KEY`**,
  **`AUR_SSH_KEY`** — environment secrets on `release`, never repository
  secrets (an environment secret shadows a repository one of the same name;
  edit the one that exists), so only a job in that environment reads them and
  a rehearsal's `build` sees none. Each is optional and its step skips
  loudly without it. The package keys are
  [Package repository](#package-repository)'s _What signs what_.
- **`HOMEBREW_TAP_TOKEN`** — the one repository secret, since `tap` runs in
  no environment: a fine-grained PAT scoped to the tap repo with contents and
  pull-requests write.

`MINISIGN_SECRET_KEY`'s value is the **whole** `minisign.key` file
`minisign -G -W` writes: both lines, unwrapped and unindented, or the signing
step fails. Generate it with `-W`, or the runner, having no tty, stops at
`Password:` (`minisign -C -W -s minisign.key` strips a passphrase from an
existing pair). Before pasting, check the file signs and matches the public
key [PACKAGING.md](PACKAGING.md#verifying-a-release-download) publishes:

```sh
minisign -R -s minisign.key -p /tmp/check.pub &&
  diff <(sed -n 2p /tmp/check.pub) \
    <(sed -n "s/^minisign -Vm SHA256SUMS -P '\([^']*\)'.*/\1/p" docs/PACKAGING.md)
```

A different pair means a new key on that line in the same commit, since
`publish` reads the key out of it.

### Hardening the release jobs

Every job in `release.yml` and `publish-external.yml` runs on a GitHub-hosted
runner and starts with `step-security/harden-runner`. Most run it in `audit`,
which records each job's outbound connections without refusing any. The three
that hold a publishing credential run `block` with an allowlist: `publish`
(the signing keys and a `contents: write` token), `tap`
(`HOMEBREW_TAP_TOKEN`), and `aur` (`AUR_SSH_KEY`). Each allowlist was read off
the job's steps, and its comment names what each host is for; tighten or
extend one from the harden-runner insights a release's run summary links (a
host `block` refused shows there), not by guessing. `brew` stays on `audit`,
since harden-runner has no block mode on macOS.

## Publishing each channel

The tap is a PR you merge; the AUR is a dispatch you run against an
already-published tag (`gh workflow run publish-external.yml -f tag=v1.0.0`,
or the Actions UI). Neither reaches a `v0.0.x` debug tag or a candidate. Each
section's checks are yours to run first.

### AUR

Blocked: AUR registration is closed to new accounts; what an Arch user does
meanwhile is [PACKAGING.md's AUR](PACKAGING.md#aur). Each package's first push
is by hand, gated on namcap; after that a `publish-external.yml` dispatch
pushes the versioned `say-hi` for each release, and no workflow touches
`say-hi-git`, which has no version to bump. Build `say-hi-git` from the
checkout and `say-hi` from the manifests a release attached:

```bash
gh release download v1.0.0 --pattern PKGBUILD --pattern SRCINFO --dir /tmp/say-hi-aur
mv /tmp/say-hi-aur/SRCINFO /tmp/say-hi-aur/.SRCINFO   # the asset drops the dot; the AUR wants it
cd packaging/aur/say-hi-git      # or /tmp/say-hi-aur
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/say-hi/..., /usr/bin/hi, /etc/profile.d/say-hi.sh, man page, license
```

**A clean run:** `namcap PKGBUILD` is silent, and `namcap` on the built
package prints exactly three warnings, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding; push nothing until it is fixed. `coreutils`
is deliberately not in `depends`; it is in `base`.

**The end-to-end check:**

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Then push `PKGBUILD` and `.SRCINFO`, only those two, to
`ssh://aur@aur.archlinux.org/<package>.git`, `say-hi-git` first since it needs
no release. Never submit the versioned package with `b2sums=('SKIP')`; `SKIP`
is correct only on `say-hi-git`.

### Homebrew tap

The tap is a plain repo ([PACKAGING.md's Homebrew tap](PACKAGING.md#homebrew-tap)):
nothing on Homebrew's side reviews what lands there, which is why
`brew audit --strict` is a hard gate here.

**The checks and the PR are automated; merging is not.** Right after
`publish`, `release.yml`'s `brew` job puts the release's formula in a
throwaway tap on a hosted mac, runs the commands below against the published
tarball, filters out the two expected findings further down, and records the
verdict in its run summary. When it passes, `tap` opens a PR against
[the tap](https://github.com/ivylikethevine/homebrew-tap) with the formula
(its header rewritten for the tap by `.github/scripts/tap_formula.sh`),
linking that run, and links the PR (or the tap's formula, when already
current) from the release body. The tap's own CI runs `brew style`,
`brew audit`, install, and test on macOS and Linux against the PR. Without
`HOMEBREW_TAP_TOKEN`, `tap` warns and does nothing.

Repeating the checks on a mac of your own takes the same throwaway tap:
`brew audit` needs a _named_ formula, and current Homebrew will not install
one from a bare path.

```bash
gh release download v1.0.0 --pattern say-hi.rb --dir /tmp/say-hi-tap
brew tap-new --no-git local/check
cp /tmp/say-hi-tap/say-hi.rb "$(brew --repository local/check)/Formula/"
brew trust --tap local/check   # Homebrew 6+: an untrusted tap's formulae are ignored
brew install --build-from-source local/check/say-hi
brew test say-hi
brew audit --strict --new local/check/say-hi
```

**A clean run:** install and test exit 0, and audit reports only these two
where the repository is unreachable (the `homebrew/brew` container, or a
private repository):

```text
* The homepage URL https://github.com/ivylikethevine/say-hi is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/say-hi.git is not a valid Git URL
```

Why the formula has no dependencies (no `uses_from_macos "openssh"` either)
and a capitalised `desc` is in its own comments.

### deb / rpm / apk

Built by `mkpkg.sh` and attached to every release; how a user installs one is
[PACKAGING.md's deb / rpm / apk](PACKAGING.md#deb--rpm--apk).

`nfpm.yaml` lists the apk's contents per `_HI_PACKAGE_CONTENTS` member rather
than through the `type: tree` entry deb and rpm use, because nfpm 2.47.0's
tree walker writes directory modes apk-tools rejects. The packaging suite keeps
that copy honest, and `ci.yml`'s `packaging-smoke` installs the signed apk on
Alpine on every code PR.

### Package repository

What a subscriber gets is
[PACKAGING.md's Package repository](PACKAGING.md#package-repository); this is
how it is built and signed.

**How it is built.** `packaging/mkrepo.sh` turns the packages `mkpkg.sh`
built into `dist/repo/`: `apt/` (`dists/stable`, `pool/`), `rpm/`
(`repodata/`), `apk/{x86_64,aarch64}/`, plus `say-hi.asc`, `say-hi.rsa.pub`,
and `say-hi.repo`. It writes the apt indexes itself (`apt-ftparchive` is
Debian-only and the format is small) and runs `createrepo_c` and `apk index`
in throwaway containers, so a dev box needs docker and gpg and nothing else.
`publish` runs it after the upload and attaches the tree as
`package-repo.tar.gz`; `pages.yml` unpacks that asset from the newest
non-prerelease release into the site. `packaging-smoke` builds a repository
on every code PR, and `tests/packaging/repo_test.sh` (the `e2e` group)
installs from one as all three clients, signatures verified, then installs a
`0.0.1` build and takes the repository's `0.0.2` as an **upgrade** through
`apt-get`, `dnf upgrade`, and `apk add -u`, with a `~/.config/say-hi/colors`
written in between and checked after. Both versions are literals in
`repo_test.sh`, so the upgrade ordering holds in a shallow, tagless checkout.

**What signs what.** One GPG key, `GPG_SIGNING_KEY`: `build` signs the rpm
with it through nfpm (`HI_GPG_KEY`, checked by `dnf gpgcheck=1`), and
`publish` signs the apt `Release` (`InRelease`, `Release.gpg`) and the rpm
`repomd.xml` (`repo_gpgcheck=1`). Its public half is committed as
`packaging/gpg/say-hi.asc` and served as `say-hi.asc`; both jobs refuse a
secret whose fingerprint is not that file's, so the key a client is told to
trust is always the one that signed. `APK_SIGNING_KEY` signs the apk and each
`APKINDEX`; `build` refuses it unless it matches `packaging/apk/say-hi.rsa.pub`,
served as `say-hi.rsa.pub`. Without `GPG_SIGNING_KEY` the rpm builds unsigned
and `publish` ships no repository; without `APK_SIGNING_KEY` the apk and its
indexes ship unsigned. A signed rpm is the one artifact that is not
byte-reproducible ([Reproducibility](#reproducibility)).

**Setting it up, once:**

```sh
gpg --batch --passphrase '' --quick-generate-key 'say-hi packages <ivylikethevine@gmail.com>' rsa4096 sign never
gpg --armor --export-secret-keys 'say-hi packages' >say-hi.gpg.key # -> GPG_SIGNING_KEY, the whole file
gpg --armor --export 'say-hi packages' >packaging/gpg/say-hi.asc    # -> commit
openssl genrsa -out say-hi.rsa 4096                                   # -> APK_SIGNING_KEY, the whole file
openssl rsa -in say-hi.rsa -pubout -out packaging/apk/say-hi.rsa.pub  # -> commit
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

Linux only, as far as anyone has tested - packaging and publishing have not
been tried on Windows, macOS, or the BSDs
([CONTRIBUTING.md's _Before you start_](CONTRIBUTING.md#before-you-start)).

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

The `/etc/profile.d` snippet, which no unit test can prove, needs a login
shell on a real install:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/say-hi_*_all.deb && echo "$_HI_HOME" && hi'
```

### Reproducibility

The same commit builds byte-identical deb/rpm/apk: `mkpkg.sh` exports
`SOURCE_DATE_EPOCH` (HEAD's commit time, respecting a value you set per the
[reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)
convention), clamps the staged tree's mtimes to it, and nfpm stamps everything
else from the same variable. CI's `packaging-smoke` double-builds on every
code PR. Locally, run the builds sequentially, since `nfpm.yaml` hardcodes
`./dist/staging`:

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

CI pins nfpm in `.github/actions/setup-tool/tools.txt`; `mkpkg.sh` takes
whatever nfpm is on PATH, so a different local nfpm can produce different
(still internally reproducible) bytes.

The signed rpm is the exception, because a GPG signature carries its signing
time: two builds with `HI_GPG_KEY` set differ in that header alone. The
`packaging-smoke` double build leaves the rpm unsigned for that reason, and a
third, signed build feeds `mkrepo.sh`. The released rpm's provenance is the
attestation and the signature itself, not a rebuild.

## Regenerating the demo GIFs

[`docs/tapes/generate.sh`](https://github.com/ivylikethevine/say-hi/blob/main/docs/tapes/generate.sh)
renders all of them: one `vhs` run per tape, cheapest first, `fixtures.sh down`
in between, and a summary of what rendered, stood down, or failed. Name tapes
for a subset (`generate.sh packages colors`); `--list` shows them, `--down`
clears up after a crashed run. `--version <v>` puts `<v>` in the header's
version cell (and in `hi --version`, on both ends of the wire) instead of
`git describe`, so a release's GIFs can be rendered before its tag exists. A
hand render of one tape is `vhs docs/tapes/<name>.tape` from the repo root
with the backend up, minding the two things `generate.sh` handles for you
(which `hi` is on `$PATH`, and a dirty tree's client/target split; see its
header).

**Six of the seven render themselves.**
[`.github/workflows/demos.yml`](https://github.com/ivylikethevine/say-hi/blob/main/.github/workflows/demos.yml)
renders every tape but `demo` in CI, one runner per tape (installing podman,
nomad, and kind as `ci.yml`'s `e2e-backends` does), for each release, weekly,
or on dispatch. A `collect` job merges them into the one `demo-gifs` artifact
the Pages build serves beside each tape, and is skipped if any tape failed, so
the site never mixes a fresh render with a stale one. For a release,
`publish` dispatches the workflow at the tag, and its `attach` job uploads the
`packages` GIF to the release as `demo.gif` and embeds it in the body. A tape
added to `generate.sh`'s roster goes in that workflow's `tape` matrix too.
Nothing is committed back: branch protection refuses a bot commit, the same
reason the tests badge is published rather than written into README. The
committed top-of-README `demo.gif` claims the stock defaults, so re-render it
by hand whenever the header, the prompt, or its tape moves.

The set is organised by **feature**, not backend, with the backends spread
across the tapes so every one is on screen somewhere. Each tape's header names
the persona it is shot for, the header configuration, and whose prompt is in
the frame; `fixtures.sh`'s `up:<name>` arm writes exactly that settings.sh.
Change the two together, and README's section for the GIF with them. Both
sides of every GIF are staged: the outside shell gets hi's own prompt under a
chosen `user@host`, and every target an explicit hostname rather than a random
hex ID.
