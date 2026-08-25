# Packaging & releases

Everything needed to ship `hi` through a package manager, plus two things that
hang off a release: [checking a download you did not
build](#verifying-a-release-download) and [regenerating the demo
GIFs](#regenerating-the-demo-gifs). Nothing here publishes on its own — the
publishing job waits on a manual approval, and the AUR and Homebrew tap are
copies you make by hand. Both signing keys are in place; the AUR deploy key
and the tap token are still one-time setup, with exact commands in
[docs/ROADMAP.md](ROADMAP.md)'s _Homebrew tap_ and _AUR_ entries.

**Runners.** Every workflow's `runs-on:` reads a repo/org Actions variable
first — `vars.RUNNER_LABEL`, or `vars.MACOS_RUNNER_LABEL` /
`vars.WINDOWS_RUNNER_LABEL` for the two OS-locked e2e jobs — falling back to
the GitHub-hosted label when unset. `ci.yml`'s `runner` job resolves the pair
once; a pull request from a _fork_ gets the hosted label whatever the variable
says, so a stranger's branch never runs on your machine. Jobs that install apt
packages or touch the Docker socket (`test`, `bench`, `packaging-smoke`, `e2e`,
`e2e-backends`, `coverage.yml`, `demos.yml`'s `publish`) need a substituted
runner to provide `sudo apt-get` and a docker daemon; `macos-e2e.yml` and
`windows-e2e.yml` need a same-OS one. The four lint jobs (`actionlint`,
`zizmor`, `markdownlint`, `hadolint`) are pinned to `ubuntu-latest` outright:
they install nothing and open no socket.

**Serialization on the self-hosted box is job-level `concurrency`, not a
`needs:` chain.** `bench`, `packaging-smoke`, `e2e` and `e2e-backends` each
carry a group that resolves to the shared `hi-selfhosted-workspace` when the
runner label is substituted, and to a per-job-per-run group otherwise — so a
self-hosted run queues them one at a time while a hosted run keeps full
parallelism. (A `needs:` chain also serialized hosted runs, and did not solve
the problem: two _different_ PRs still put jobs on the box together.) What
stays in `needs:` is the real data dependency — `e2e` and `e2e-backends` gate
on `test`, hence `!cancelled() && needs.test.result == 'success'`. The shared
group queues across runs too, and `demos.yml`'s `publish` joins it; every other
workflow reading `RUNNER_LABEL` stays out, as does `ci.yml`'s `test`. One
registered runner process per box is what actually makes "never two at once"
true.

**Every job shares one directory on the box**, `_work/<repo>/<repo>`, and the
container suites can leave a file the runner user cannot delete (root-owned
from a docker step, subuid-owned from rootless podman). `actions/checkout`'s
cleanup then throws, the throw is swallowed (`persist-credentials: false` runs a
`Removing auth` teardown in `finally` against the now-`.git`-less directory),
and the real error is replaced with:

```text
fatal: --local can only be used inside a git repository
The process '/usr/bin/git' failed with exit code 128
```

Read that as "something in the workspace could not be deleted", not a git
problem; it does not clear on retry. The `Reclaim the workspace` step ahead of
each checkout is the guard — a `sudo chown -R` back to the runner user, skipped
on hosted runners. If a box has wedged, look at what survived
(`find . ! -user "$(id -un)"`, plus `mount` for a stale mount point) before
clearing it.

**Two repo settings must exist before pointing any variable at a self-hosted
runner**: the fork-PR approval, and the environments `release.yml` names —
`manual-dispatch` on its rehearsal gate and `release` on `publish`/`tap`/`aur`.
An `environment:` naming one that does not exist gates nothing. The two e2e
workflows carry none: `ci.yml` calls them on every push to `main`, where a
required reviewer would stall the run.

## Contents

- [The one idea](#the-one-idea)
- [Layout](#layout)
- [Cutting a release](#cutting-a-release)
- [Channels weighed and not shipped](#channels-weighed-and-not-shipped)
- [Publishing each channel](#publishing-each-channel)
  - [AUR](#aur)
  - [Homebrew tap](#homebrew-tap)
  - [deb / rpm / apk](#deb--rpm--apk)
- [Verifying a packaged build locally](#verifying-a-packaged-build-locally)
  - [Reproducibility](#reproducibility)
- [After installing from a package](#after-installing-from-a-package)
- [Regenerating the demo GIFs](#regenerating-the-demo-gifs)
- [Verifying a release download](#verifying-a-release-download)

## The one idea

`hi.sh` locates itself — it walks `$0` through any symlinks and takes the tree
from where it lands, so `/usr/bin/hi` pointing into a package prefix resolves
on its own (GLOSSARY: HI.33). Everything then resolves against
`$_HI_ROOT="$_HI_HOME/say-hi"`. What a channel owes is the layout and the
handoff: put the tree in a directory literally named `say-hi`, and make sure
`_HI_HOME` names that directory's **parent** in the environment, because a
_new_ process with no tree to derive from — a login shell, tmux's
`update-environment`, another machine's `hi` probing this one — has nothing
else to read.

| channel            | tree                   | how `_HI_HOME` gets set                                    |
| ------------------ | ---------------------- | ---------------------------------------------------------- |
| AUR, deb, rpm, apk | `/usr/share/say-hi`    | `/etc/profile.d/say-hi.sh`, written by `install_tree`      |
| Homebrew           | `<keg>/libexec/say-hi` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this and
is the single decider of what a packaged install contains —
`_HI_PACKAGE_CONTENTS` and `install_tree()`. Both AUR PKGBUILDs and `mkpkg.sh`
call it. Only the Homebrew formula repeats the list, because `install_tree`
hardcodes `/usr/bin` and `/etc/profile.d`, neither of which exists in a brew
prefix; `tests/packaging/packaging_test.sh` fails if that copy drifts.

## Layout

| path                 | what it is                                                                          |
| -------------------- | ----------------------------------------------------------------------------------- |
| `mkpkg.sh`           | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                       |
| `stamp.sh`           | writes the version into a built tree's `hi.sh` and man page; every channel calls it |
| `bump.sh`            | writes the version + real checksums into every manifest; `--check` verifies         |
| `lib.sh`             | the tree locator and shared primitives `bump.sh` and `mkpkg.sh` source              |
| `srctar.sh`          | builds the source tarball a release attaches; `bump.sh` checksums the same bytes    |
| `aur/say-hi/`        | the versioned AUR package (`PKGBUILD`, `.SRCINFO`)                                  |
| `aur/say-hi-git/`    | the same package built from `main`                                                  |
| `homebrew/say-hi.rb` | the tap formula                                                                     |
| `nfpm/nfpm.yaml`     | deb/rpm/apk, built from the staged tree                                             |

**The version stamp.** `stamp.sh` writes `_HI_RELEASE=` into the `hi.sh` a
channel installs and the version into the man page's `.TH` line; all four
channels call it. It cannot live in git: `bump.sh` runs only after the tag
exists (its checksums need the tarball), so a committed stamp would always be
one release stale in the very tarball Homebrew and the AUR build from. A
checkout answers `hi --version` with `git describe` instead. The formula passes
`--date <version>`, having no `SOURCE_DATE_EPOCH`; `stamp.sh` refuses to guess
one. `packaging_test.sh` guards all of it.

## Channels weighed and not shipped

nix is the one looked at and answered no for now. The reasoning — the
derivation shape, why it would ship as a flake first, the drift guard that has
to grow a case, and what `/etc/profile.d` has no store-path equivalent for —
lives in [UNSUPPORTED.md's _packaging channels_
section](UNSUPPORTED.md#packaging-channels-weighed-and-not-shipped).

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That is the whole local ceremony. The tag never moves: the manifests carry
checksums of a tarball that cannot exist before the tag does, so the workflow
does the bump itself.

**The tarball is one the release builds**, not GitHub's auto-generated
`/archive/` one — the archive is the only artifact a release could ship with
nothing signed over it. `packaging/srctar.sh` writes a
`git archive --prefix say-hi-<version>/` of the tag, and that file is what
`bump.sh` checksums, what `mkpkg.sh` lists in `SHA256SUMS`/`ARTIFACTS`, and
what the release attaches. One set of bytes, summed once.

1. `git tag v1.0.0 && git push origin v1.0.0` — the workflow starts.
2. The `build` job builds `say-hi-1.0.0.tar.gz` from the tag, runs the fast
   suites, runs `bump.sh --tarball <that file> 1.0.0` (writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines),
   verifies with `bump.sh --check`, runs the packaging drift guards, and builds
   the deb/rpm/apk with one `SHA256SUMS` over the lot. Nothing has published.
3. Approve the `publish` job in the Actions UI — your review point, over the
   exact artifacts the build produced. Packages, the source tarball,
   `SHA256SUMS` and manifests land on the release, and the regenerated
   manifests come back to `main` as a `manifests-v1.0.0` **pull request**,
   since `main` refuses a direct push.
4. Both channels update themselves once their secrets exist: the tap gets a PR
   (`HOMEBREW_TAP_TOKEN`), the AUR gets a push (`AUR_SSH_KEY`). **Neither waits
   on the manifest PR** — both read the manifests out of the `packages`
   artifact. Until the secrets exist, copy the manifests by hand per the
   sections below.
5. Merge the manifest PR.

`bump.sh 1.0.0` still works by hand if CI is unavailable — with the tag in
your checkout it builds the identical tarball itself, `--tarball <file>` takes
one you have, and it downloads the published asset only when neither is
available (during a release the asset does not exist yet, which is why the
download cannot be the first thing it tries). `bump.sh --check 1.0.0` confirms
the manifests match a cut release.

**Release notes are the PR titles.** The publish job asks GitHub's
`releases/generate-notes` endpoint for the notes — the PR titles merged since
the last tag — and puts them at the top of the release body, with the
[verification checklist](#verifying-a-release-download) appended below. Title
PRs the way you'd want them read, and skim `gh pr list --state merged` before
tagging. It is composed rather than passed as `--generate-notes --notes`
because `gh` appends generated notes **after** `--notes`, which would bury them
under the checklist.

## Publishing each channel

Every channel below is gated on the manual approval in `release.yml`; the AUR
and the tap are pushed by CI once their secrets exist, but the checks each
section describes are still yours to run first.

**A `v0.0.x` tag reaches none of them.** Those are debug tags for exercising the
release path, so the `tap` and `aur` jobs skip on the tag name itself. The
GitHub Release is still created, with the packages attached.

### AUR

Not currently doable: AUR registration is closed to new accounts because of
spam. Everything below is ready for the day it reopens. Run the gate for
**each** package — `aur/say-hi-git` today, `aur/say-hi` once v1.0.0 exists.
namcap is the hard step: push nothing while either its `PKGBUILD` or its
built-package run has complaints.

```bash
cd packaging/aur/say-hi-git        # then again in packaging/aur/say-hi
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/say-hi/..., /usr/bin/hi, /etc/profile.d/say-hi.sh
```

**What a clean run looks like.** `namcap PKGBUILD` is silent. `namcap` on the
built package prints exactly three warnings, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding. (`coreutils` is deliberately not in `depends`
— it is in `base`.)

**The end-to-end check**, which caught the `say-hi-git` package shipping no
version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have been through all of this against a local clone: built,
linted, installed into a clean Arch container, exercised, and removed with
nothing left behind.

Then push `PKGBUILD` + `.SRCINFO` — only those two — to
`ssh://aur@aur.archlinux.org/say-hi-git.git`, `say-hi-git` first since it needs
no tag. **That first push is the manual one**, because it is where namcap
gates. After it, `release.yml`'s `aur` job pushes the versioned `say-hi` on
every release but a `v0.0.x` tag; `say-hi-git` has no version to bump and CI
never touches it. Never submit the versioned package with `b2sums=('SKIP')` —
`SKIP` is correct only on `say-hi-git`.

### Homebrew tap

A tap is a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/say-hi.rb` to `Formula/say-hi.rb` there and
`brew install ivy/tap/say-hi` works — no review, no approval, which is why
`brew audit --strict` is a hard gate here.

**The copy and the checks are automated; the merge is not.** `release.yml`'s
`tap` job (behind the same approval as `publish`) opens a PR against
`<owner>/homebrew-tap` with the regenerated formula and the three commands
below as its checklist. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a
fine-grained PAT scoped to that repo with contents + pull-requests write — and
without it says so and does nothing. Its sibling `brew` job runs the three
commands on a hosted mac against the published tarball, with the two expected
findings below filtered out, and records the verdict in its run summary.
Merging the PR is yours, as is repeating these on a mac of your own:

```bash
brew install --build-from-source ./packaging/homebrew/say-hi.rb
brew test say-hi
brew audit --strict --new say-hi
```

`brew audit` needs a _named_ formula: `brew tap-new ivy/tap`, copy the file
into its `Formula/`, then `brew audit --strict --new ivy/tap/say-hi`.

**What a clean run looks like** — run in the `homebrew/brew` container against
a local tarball: install and test exit 0, and audit reports only these two,
which are the unpublished repo and nothing else:

```text
* The homepage URL https://github.com/ivylikethevine/say-hi is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/say-hi.git is not a valid Git URL
```

Two real findings came out of that run and are fixed: the description had to
start with a capital, and `uses_from_macos "openssh"` was rejected (that macro
is for formulae macOS provides _to Homebrew_). The formula declares no
dependencies at all: `ssh` and `base64` ship with macOS and any Linux that
would install this. A real mac is still worth using before the first publish,
since the container exercises Linuxbrew's paths rather than `/opt/homebrew`.

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

A quirk: the apk enumerates its contents per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` rather than riding the `type: tree` entry deb/rpm use, because
nfpm 2.47.0's tree walker writes directory modes apk-tools rejects. The
packaging suite keeps that copy honest, and CI's packaging-smoke installs the
signed apk on Alpine every PR.

No `apt upgrade` — the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if
people ask for a repo to subscribe to.

## Verifying a packaged build locally

The half you run on a package **you** just built. Its near-namesake at the
bottom, [Verifying a release download](#verifying-a-release-download), is what
somebody who downloaded a release runs.

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
else from the same variable. CI's packaging-smoke job enforces it with a double
build on every PR. Locally, run them sequentially — `nfpm.yaml` hardcodes
`./dist/staging`:

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

CI pins nfpm 2.47.0 (`.github/actions/setup-tool/tools.txt`) while `mkpkg.sh`
takes whatever nfpm is on PATH, so a different local nfpm can produce different
(still internally reproducible) bytes.

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
The package's `/etc/profile.d/say-hi.sh` is what `hi.sh`'s `_hi_remote_root`
probe reads to find `/usr/share/say-hi` and use it in place, and `/usr/share`
is on the probe's install-prefix list even if that snippet is gone
(GLOSSARY: HI.33). `tests/targets/install_methods_test.sh` installs a real
`.deb`, `.rpm` and `.apk` on real targets and asserts exactly that.

## Regenerating the demo GIFs

[`docs/tapes/generate.sh`](tapes/generate.sh) renders all of them: one `vhs`
run per tape, cheapest first, with a `fixtures.sh down` in between, and a
summary of what rendered, stood down, or failed. Name tapes to render a subset
(`generate.sh docker kube`); `--list` shows them, `--down` clears up after a
crashed run.

**Seven of the eight render themselves.**
[`.github/workflows/demos.yml`](../.github/workflows/demos.yml) runs every tape
but `demo` in CI — installing podman, nomad and kind on a hosted runner the way
`ci.yml`'s `e2e-backends` job does, or on the box `RUNNER_LABEL` names — on a
tape change, weekly, or on dispatch, and hands the GIFs to the Pages build,
which lays them over the committed copies at the same paths. Nothing is
committed back: branch protection refuses a bot commit, the same reason the
tests badge is published rather than written into README.

The top-of-README `demo.gif` is the one that goes quietly wrong: it claims to
be the stock defaults, so it is stale the moment the header, the prompt or the
tape changes. [`.githooks/demo_staleness.sh`](../.githooks/demo_staleness.sh)
compares its last commit against the tape, the fixtures and the shipped tree.
`ci.yml`'s `demo-staleness` job runs it on every pull request as a warning; to
hear it before the push:

```sh
git config core.hooksPath .githooks
```

It only ever warns — rendering a binary nobody looked at is what this section
argues against.

By hand it is one `vhs docs/tapes/<name>.tape` per GIF from the repo root, with
the backend running and `hi` on PATH; `docs/tapes/fixtures.sh` builds every
target the tapes connect to, `fixtures.sh down` removes them. One more lives in
[CONFIGURATION.md](CONFIGURATION.md#colors) — `color_preview.tape`, the only
one needing no backend. Two things to get right that way, which the script
takes care of: `hi` on `$PATH` must be _this_ checkout (the script shims its
own onto the front of `$PATH`), and the target image builds from `HEAD`, so
uncommitted work shows on the client side of the GIF but not the target's —
render from a commit, or set `HI_DEMO_SOURCE=worktree`, which the script picks
on a dirty tree.

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
the public key out of it to build the checklist in every release body, and
fails the release if the pattern stops matching — one copy of the key in the
tree rather than two that can drift. Keep it a single line starting
`minisign -Vm SHA256SUMS -P '`, with the key in single quotes.

That covers **every** file on the release, `say-hi-<version>.tar.gz` included:
`gh attestation verify say-hi-*.tar.gz --repo ivylikethevine/say-hi` answers
for the sources the same way the line above answers for the `.deb`.
