# Packaging & releases

How `hi` ships through a package manager, plus [checking a download you did
not build](#verifying-a-release-download) and [regenerating the demo
GIFs](#regenerating-the-demo-gifs). Nothing publishes on its own: the
publishing job waits on a manual approval, and the AUR and Homebrew tap stay
hand-copied until their secrets exist. Both signing keys are in place; the AUR
deploy key and the tap token are one-time setup ([AUR](#aur), [Homebrew
tap](#homebrew-tap)), tracked in [docs/ROADMAP.md](ROADMAP.md).

**Runners.** Every job runs on a plain GitHub-hosted label (`ubuntu-latest`,
`macos-latest`, `windows-latest`); none substitutes a machine from a repo/org
Actions variable.

## Contents

- [The one idea](#the-one-idea)
- [Layout](#layout)
- [Channels weighed and not shipped](#channels-weighed-and-not-shipped)
- [Cutting a release](#cutting-a-release)
- [Snapshot builds](#snapshot-builds)
- [Publishing each channel](#publishing-each-channel)
  - [AUR](#aur)
  - [Homebrew tap](#homebrew-tap)
  - [deb / rpm / apk](#deb--rpm--apk)
  - [devcontainer Feature](#devcontainer-feature)
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

| channel              | tree                   | how `_HI_HOME` gets set                                           |
| -------------------- | ---------------------- | ----------------------------------------------------------------- |
| AUR, deb, rpm, apk   | `/usr/share/say-hi`    | `/etc/profile.d/say-hi.sh`, written by `install_tree`             |
| Homebrew             | `<keg>/libexec/say-hi` | the `bin/hi` wrapper, plus the rc line `install.sh` writes        |
| devcontainer Feature | `/usr/share/say-hi`    | the same `/etc/profile.d/say-hi.sh` - it calls `install_tree` too |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this;
its `_HI_PACKAGE_CONTENTS` and `install_tree()` decide what a packaged install
contains. Both AUR PKGBUILDs and `mkpkg.sh` call it. Only the Homebrew formula
repeats the list, because `install_tree` hardcodes `/usr/bin` and
`/etc/profile.d` and neither exists in a brew prefix;
`tests/packaging/packaging_test.sh` fails if that copy drifts.

## Layout

| path                 | what it is                                                                           |
| -------------------- | ------------------------------------------------------------------------------------ |
| `mkpkg.sh`           | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                        |
| `stamp.sh`           | writes the version into a built tree's `hi.sh` and man page; every channel calls it  |
| `bump.sh`            | writes the version + real checksums into every manifest; `--check` verifies          |
| `lib.sh`             | the tree locator and shared primitives `bump.sh` and `mkpkg.sh` source               |
| `srctar.sh`          | builds the source tarball a release attaches; `bump.sh` checksums the same bytes     |
| `aur/say-hi/`        | the versioned AUR package (`PKGBUILD`, `.SRCINFO`)                                   |
| `aur/say-hi-git/`    | the same package built from `main`                                                   |
| `homebrew/say-hi.rb` | the tap formula                                                                      |
| `nfpm/nfpm.yaml`     | deb/rpm/apk, built from the staged tree                                              |
| `devcontainer/src/`  | the devcontainer Feature, one directory per feature (the publishing action's layout) |

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
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines),
   verifies with `bump.sh --check`, runs the packaging drift guards, and builds
   the deb/rpm/apk with one `SHA256SUMS` over the lot. Nothing has published.
3. Approve the `publish` job in the Actions UI — your review point, over the
   exact artifacts `build` produced. Packages, the source tarball, `SHA256SUMS`
   and manifests land on the release; the regenerated manifests come back to
   `main` as a `manifests-v1.0.0` **pull request**, since `main` refuses a
   direct push.
4. Once their secrets exist, the tap gets a PR (`HOMEBREW_TAP_TOKEN`) and the
   AUR a push (`AUR_SSH_KEY`); **neither waits on the manifest PR**, both read
   the `packages` artifact. Until then, copy the manifests by hand per the
   sections below.
5. Merge the manifest PR.

**A release candidate is a GitHub Release and nothing more.** A prerelease
tag - anything with a `-` in it, `v1.0.0-rc.1` - takes steps 1-3 unchanged and
is created `--prerelease --latest=false`, so "the latest release" (the
devcontainer Feature's default, README's badge) never resolves to a candidate.
The packages, the source tarball, `SHA256SUMS` and the manifests are attached
as on any release, but no manifest PR opens and no channel job runs:
`0.1.0-rc.1` is valid semver (nfpm's `version_schema` accepts it; the deb
sorts as `0.1.0~rc.1`) and not a legal `pkgver` (`-` is makepkg's
`pkgver-pkgrel` separator), and the AUR is where the manifests go. The final
tag is the first to walk the tap, the AUR and `brew audit`.

`bump.sh 1.0.0` works by hand if CI is unavailable: with the tag in your
checkout it builds the identical tarball itself, `--tarball <file>` takes one
you have, and it downloads the published asset only when neither is available
(during a release the asset does not exist yet). `bump.sh --check 1.0.0`
confirms the manifests match a cut release.

**Release notes are the PR titles.** The publish job asks GitHub's
`releases/generate-notes` endpoint for the PR titles merged since the last tag
and puts them at the top of the release body, the [verification
checklist](#verifying-a-release-download) below. Title PRs the way you'd want
them read; skim `gh pr list --state merged` before tagging. The body is
composed rather than passed as `--generate-notes --notes` because `gh` appends
generated notes **after** `--notes`, burying them under the checklist.

## Snapshot builds

Every push to `main` produces one **prerelease**, tagged
`snapshot-<short-sha>` for the commit
[`.github/workflows/snapshot.yml`](../.github/workflows/snapshot.yml) built it
from. It carries what a tag release carries (deb/rpm/apk, the source tarball,
`SHA256SUMS`, `ARTIFACTS`, a build-provenance attestation over the lot), built
by the same `srctar.sh` → `mkpkg.sh` path, versioned `0.0.0-main.<date>.<sha>`
(what `hi --version` prints from one), and gated on the fast suites alone.

- **Only one exists at a time.** `publish` deletes every previous `snapshot-*`
  release and tag, and any bare rolling `snapshot` one, before creating its
  own. No tag is ever retargeted: each push's tag is new, so a clone holding
  an old one keeps a harmless local copy nothing upstream asks to move.
- **It reaches no channel.** No `bump.sh` (the manifests checksum a
  `releases/download/v<ver>/` URL a snapshot never has), no manifest PR, no
  tap, no AUR, no ghcr; all of that is `release.yml`'s and waits on a `v*` tag
  pushed by hand ([Cutting a release](#cutting-a-release)).
  `tests/packaging/packaging_test.sh` pins the split: `snapshot.yml` may run
  only on `main` and may not name a channel, `bump.sh` or the `release`
  environment.
- **It is unsigned.** `MINISIGN_SECRET_KEY` is sealed to the `release`
  environment, which the snapshot job never enters, so its `SHA256SUMS` has no
  `.minisig` and the release body says so; the attestation is its provenance.
- **It is `--prerelease --latest=false`**, as a release candidate is, so the
  newest final `v*` stays "Latest" and nothing that installs "the latest
  release" (the devcontainer Feature's default, `brew`, the AUR) sees a
  snapshot or a candidate.
- **Two repository settings:** `main` may need no reviewer (no environment
  holds it), and no tag-protection ruleset may cover `snapshot-*`; a rule
  blocking creation or deletion of a matching tag fails `publish`.

## Publishing each channel

Every channel below is gated on the manual approval in `release.yml`; CI
pushes the AUR and the tap once their secrets exist, but each section's checks
are still yours to run first.

**A `v0.0.x` tag reaches none of them, and neither does a prerelease tag.**
`v0.0.x` are debug tags for exercising the release path and a `-` in the name
(`v1.0.0-rc.1`) is a candidate; every channel job skips on the tag name, and
the GitHub Release is still created with the packages attached.

### AUR

Not currently doable: AUR registration is closed to new accounts because of
spam. Until it reopens an Arch user runs `makepkg -si` in
`packaging/aur/say-hi-git` (the versioned `say-hi` needs a release tarball, so
before one exists `-git` is the one that builds) and upgrades with `git pull`
and the same command. Run the gate for **each** package, `aur/say-hi-git`
today and `aur/say-hi` once v1.0.0 exists; push nothing while namcap has
complaints about either the `PKGBUILD` or the built package.

```bash
cd packaging/aur/say-hi-git        # then again in packaging/aur/say-hi
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
it, `release.yml`'s `aur` job pushes the versioned `say-hi` on every release
but a `v0.0.x` tag; `say-hi-git` has no version to bump and CI never touches
it. Never submit the versioned package with `b2sums=('SKIP')`; `SKIP` is
correct only on `say-hi-git`.

### Homebrew tap

A tap is a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/say-hi.rb` to `Formula/say-hi.rb` there and
`brew install ivy/tap/say-hi` works, with no review and no approval, which is
why `brew audit --strict` is a hard gate here.

**The copy and the checks are automated; the merge is not.** `release.yml`'s
`tap` job (behind the same approval as `publish`) opens a PR against
`<owner>/homebrew-tap` with the regenerated formula and the three commands
below as its checklist. It needs a `HOMEBREW_TAP_TOKEN` repo secret (a
fine-grained PAT scoped to that repo with contents + pull-requests write) and
without it says so and does nothing. Its sibling `brew` job runs the three
commands on a hosted mac against the published tarball, filtering out the two
expected findings below, and records the verdict in its run summary. Merging
the PR is yours, as is repeating these on a mac of your own:

```bash
brew install --build-from-source ./packaging/homebrew/say-hi.rb
brew test say-hi
brew audit --strict --new say-hi
```

`brew audit` needs a _named_ formula: `brew tap-new ivy/tap`, copy the file
into its `Formula/`, then `brew audit --strict --new ivy/tap/say-hi`.

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

Built by `mkpkg.sh` and attached to the GitHub Release. Users install the file:

```bash
sudo apt install ./say-hi_1.0.0_all.deb
```

The apk is signed with a key apk verifies against `/etc/apk/keys/`, so Alpine
users install the public key once and never pass `--allow-untrusted`:

```sh
wget -O /etc/apk/keys/say-hi.rsa.pub \
  https://raw.githubusercontent.com/ivylikethevine/say-hi/main/packaging/apk/say-hi.rsa.pub
apk add ./say-hi_1.0.0_noarch.apk
```

A quirk: the apk lists its contents per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` rather than riding the `type: tree` entry deb/rpm use, because
nfpm 2.47.0's tree walker writes directory modes apk-tools rejects. The
packaging suite keeps that copy honest, and CI's packaging-smoke installs the
signed apk on Alpine every PR.

No `apt upgrade`: the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if
people ask for a repo to subscribe to.

### devcontainer Feature

**The one channel that installs say-hi on the far side.** Every other one
packages it for a machine you say `hi` _from_. From outside a devcontainer is
a docker container like any other ([SUPPORT.md](SUPPORT.md)), but a Codespace
or a _Reopen in Container_ has no client: the terminal that opens is already
standing on the target. So this Feature puts say-hi _inside_ the image, and
the terminal is styled with nothing connecting to it.

A user adds it to their `devcontainer.json`:

```jsonc
"features": {
  "ghcr.io/ivylikethevine/say-hi/say-hi:0": {}
}
```

| option           | default      | what it does                                                                                       |
| ---------------- | ------------ | -------------------------------------------------------------------------------------------------- |
| `version`        | `latest`     | the newest release, a release version like `1.0.0`, or `main` for the branch                       |
| `preset`         | `everything` | which of [SETTINGS.md's presets](SETTINGS.md#presets) the user's settings start from               |
| `configureShell` | `true`       | run `hi --install` for `$_REMOTE_USER`; off leaves `/usr/bin/hi` working and the terminal unstyled |

`packaging/devcontainer/src/say-hi/install.sh` is deliberately thin, and the
packaging suite keeps it so. It downloads the release source tarball, checks
it against the release's own `SHA256SUMS`, links the unpacked directory to the
name `say-hi` (`install.sh` derives `$_HI_HOME` as `<checkout>/..` and looks
for `$_HI_HOME/say-hi`; the AUR's `prepare()` makes the same link), and hands
over to `scripts/install.sh --prefix /usr/share` and `packaging/stamp.sh`, so
what a packaged install _contains_ stays `_HI_PACKAGE_CONTENTS`' business.
Then the half a package manager cannot do: `hi --install --yes --preset`, as
`$_REMOTE_USER` rather than root, so the rc files it writes belong to the
person who will open the terminal; `--preset` is the one way to answer every
feature question with no terminal to ask on.

**`version: main` is the unverified arm** and says so on the way past: there
is no `SHA256SUMS` for a branch, the same trade the `say-hi-git` AUR package
makes. A release version is the default and the checked path.

**Publishing is `release.yml`'s `feature` job**, behind the same approval as
the tap and the AUR, pushing to ghcr with the workflow's own `GITHUB_TOKEN`;
no secret to create. **The Feature's `version` is its own**, not the
release's: the registry refuses a re-push of a version, so it moves when
`devcontainer-feature.json` changes, not when say-hi does; the Feature's
`version` option picks a say-hi version at container-build time.

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
[`.githooks/demo_staleness.sh`](../.githooks/demo_staleness.sh) compares its
last commit against the tape, the fixtures and the shipped tree; `ci.yml`'s
`advisory-lint` job runs it on every pull request as a warning, and it only
ever warns. To hear it before the push:

```sh
git config core.hooksPath .githooks
```

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
minisign -Vm SHA256SUMS -P 'RWTDcJ3LGWayrAxK6mbMysyOF8mNLOmMUGRl4YSWk5KIoayS+lW0Fy1L'
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
