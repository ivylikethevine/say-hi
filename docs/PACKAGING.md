# Packaging & releases

Everything needed to ship `hi` through a package manager, plus the two things
that hang off a release once it exists: [checking a download you did not
build](#verifying-a-release-download), and [regenerating the demo
GIFs](#regenerating-the-demo-gifs) the release pipeline publishes to the site.
Nothing here publishes on its own — the publishing job waits on a manual
approval, and the AUR and the Homebrew tap are copies you make by hand. Both
signing keys are in place, so a release signs its sums and its apk; what is
still one-time setup is the AUR deploy key and the tap token, a checklist with
exact commands in [docs/ROADMAP.md](ROADMAP.md)'s _Homebrew tap_ and _AUR_
entries.

Every workflow's `runs-on:` reads a repo/org Actions variable first —
`vars.RUNNER_LABEL`, or `vars.MACOS_RUNNER_LABEL` / `vars.WINDOWS_RUNNER_LABEL`
for the two OS-locked e2e jobs — falling back to the GitHub-hosted label when
unset, so nothing changes until you set one. `ci.yml` reads them one job
earlier: its `runner` job resolves the pair once and the six substitutable jobs
take `needs.runner.outputs.*` from it. That job is also where the one exception
lives — a pull request from a _fork_ gets the GitHub-hosted label whatever the
variable says, so a stranger's branch never runs on your machine.

Jobs that install apt packages or touch the Docker socket (`ci.yml`'s `test`,
`bench`, `packaging-smoke`, `e2e`, `e2e-backends`, and `coverage.yml`) need a
self-hosted runner providing those; `macos-e2e.yml` and `windows-e2e.yml` need a
same-OS one if substituted. The four lint jobs — `actionlint`, `zizmor`,
`markdownlint`, `hadolint` — are the other side of that list, and are pinned to
`ubuntu-latest` outright rather than reading the variable: they install nothing
and open no socket, so pointing them at your own machine buys nothing and only
adds jobs contending for its workspace.

Those five `ci.yml` jobs run in a chain rather than in parallel — `test` →
`bench` → `packaging-smoke` → `e2e` → `e2e-backends` — so at most one of them
occupies the runner at a time. Their `needs:` are ordering, not data
dependencies, which is why each link is guarded with `!cancelled()`: a red job
still lets the next one run and report its own verdict.

Know the limit of that guarantee, though: it holds _within_ this workflow only.
`coverage.yml`, `pages.yml`, `link-check.yml`, `tool-versions.yml` and
`scorecard.yml` read `RUNNER_LABEL` too, and nothing in a workflow file can
order one workflow against another. The runner is the only thing that can: one
runner process takes one job at a time, so registering exactly one on the box is
what actually makes "never two at once" true.

Every one of those jobs also shares _one_ directory on the box —
`_work/<repo>/<repo>`, which the runner keeps between jobs rather than
recreating. `actions/checkout` cleans it itself, but it does that as the runner
user, and the container suites here can leave a file behind that the runner user
cannot delete: root-owned from a docker step, or subuid-owned from rootless
podman. That delete then throws, and the throw is swallowed — every checkout in
this repo sets `persist-credentials: false`, so a `Removing auth` teardown runs
in `finally`, fails its own `git config --local` against the now-`.git`-less
directory, and replaces the real error with

```text
fatal: --local can only be used inside a git repository
The process '/usr/bin/git' failed with exit code 128
```

Read that message as "something in the workspace could not be deleted", not as a
git problem. It does not clear on a retry either: `.git` is gone, so every later
run takes the same delete path and dies identically. The `Reclaim the workspace`
step ahead of each checkout is the guard — a `sudo chown -R` back to the runner
user, skipped on hosted runners via `runner.environment`. If a box has already
wedged, look at what survived in `_work/<repo>/<repo>`
(`find . ! -user "$(id -un)"`, plus `mount` for a stale mount point) before
clearing it; that residue is the only evidence of which step left it there.

Two repo settings have to be in place _before_ you point any of these variables
at a self-hosted runner: the fork-PR approval, and the environments
`release.yml` names — `manual-dispatch` on its rehearsal gate and `release` on
`publish`/`tap`/`aur`. Neither can be done from a workflow file, and an
`environment:` naming one that does not exist gates nothing. The two e2e
workflows deliberately carry none: `ci.yml` calls them on every push to `main`,
where a required reviewer would stall the run rather than gate it — the
`push`-only condition is what keeps a fork's pull request out of them.

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

`hi.sh` locates itself - it walks `$0` through any symlinks and takes the tree
from where it lands, so `/usr/bin/hi` pointing into a package prefix resolves
correctly on its own (GLOSSARY: HI.33). Everything then resolves against
`$_HI_ROOT="$_HI_HOME/say-hi"`. What a channel still owes is the layout and the
handoff: put the tree in a directory literally named `say-hi`, and make sure
`_HI_HOME` names that directory's **parent** in the environment, because a _new_
process with no tree to derive from - a login shell, tmux's
`update-environment`, another machine's `hi` probing this one - has nothing else
to read.

| channel            | tree                   | how `_HI_HOME` gets set                                    |
| ------------------ | ---------------------- | ---------------------------------------------------------- |
| AUR, deb, rpm, apk | `/usr/share/say-hi`    | `/etc/profile.d/say-hi.sh`, written by `install_tree`      |
| Homebrew           | `<keg>/libexec/say-hi` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this and
is the single decider of what a packaged install contains —
`_HI_PACKAGE_CONTENTS` and `install_tree()` in that file. Both AUR PKGBUILDs and
`mkpkg.sh` call it. Only the Homebrew formula repeats the list, because a
formula cannot call it: `install_tree` hardcodes `/usr/bin` and
`/etc/profile.d`, neither of which exists in a brew prefix.
`tests/packaging/packaging_test.sh` fails if that copy drifts.

## Layout

| path                 | what it is                                                                          |
| -------------------- | ----------------------------------------------------------------------------------- |
| `mkpkg.sh`           | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                       |
| `stamp.sh`           | writes the version into a built tree's `hi.sh` and man page; every channel calls it |
| `bump.sh`            | writes the version + real checksums into every manifest; `--check` verifies         |
| `aur/say-hi/`        | the versioned AUR package (`PKGBUILD`, `.SRCINFO`)                                  |
| `aur/say-hi-git/`    | the same package built from `main`                                                  |
| `homebrew/say-hi.rb` | the tap formula                                                                     |
| `nfpm/nfpm.yaml`     | deb/rpm/apk, built from the staged tree                                             |

**The version stamp.** `packaging/stamp.sh` writes `_HI_RELEASE=` into the
`hi.sh` a channel installs and the version into the man page's `.TH` line. All
four call it — `mkpkg.sh` for deb/rpm/apk, both `PKGBUILD`s' `package()`, the
formula's `install` — so there is one implementation rather than four seds. It
cannot live in git: `bump.sh` runs only after the tag exists (its checksums need
the tarball), so a committed stamp would always be one release stale in the very
tarball Homebrew and the AUR build from. A checkout answers `hi --version` with
`git describe` instead, so the committed line stays empty. The formula passes
`--date <version>`, having no `SOURCE_DATE_EPOCH`, and `stamp.sh` refuses to
guess one. `tests/packaging/packaging_test.sh` guards all of it.

## Channels weighed and not shipped

nix is the one looked at and answered so far, and the answer for now is no. The
reasoning - the derivation shape, why it would ship as a flake before a nixpkgs
submission, the `_HI_PACKAGE_CONTENTS` drift guard that has to grow a case
first, and what `/etc/profile.d` has no store-path equivalent for - lives with
every other decision against something, in [UNSUPPORTED.md's _packaging
channels_ section](UNSUPPORTED.md#packaging-channels-weighed-and-not-shipped).

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That is the whole local ceremony. The tag never moves: the manifests carry
checksums of a tarball that cannot exist before the tag does, so the workflow
does the bump itself rather than requiring a pre-tag bump and a force-retag to
reconcile the two.

**The tarball is one the release builds**, not GitHub's auto-generated
`/archive/` one. That matters because the archive is the only artifact a
release could ship with nothing signed over it: no entry in `SHA256SUMS` and no
build provenance, in a chain where every other file has both.
`packaging/srctar.sh` (over `lib.sh`'s `src_tarball`) writes a
`git archive --prefix say-hi-<version>/` of the tag — the same shape, down to
the directory the AUR package's `prepare()` symlinks — and that file is what
`bump.sh` checksums, what `mkpkg.sh` lists in `SHA256SUMS`/`ARTIFACTS`, and
what the release attaches. One set of bytes, summed once.

1. `git tag v1.0.0 && git push origin v1.0.0` — the workflow starts.
2. The `build` job builds `say-hi-1.0.0.tar.gz` from the tag, runs the fast
   suites, then `bump.sh --tarball <that file> 1.0.0` (writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines),
   verifies with `bump.sh --check`, runs the packaging drift guards against the
   fresh manifests, and builds the deb/rpm/apk — `mkpkg.sh --source-tarball`
   puts the tarball beside them and writes one `SHA256SUMS` over the lot.
   Nothing has published yet.
3. Approve the `publish` job in the Actions UI — this is your review point, over
   the exact artifacts the build produced. Packages, the source tarball,
   `SHA256SUMS`, and manifests land on the release, and the regenerated
   manifests come back to `main` as a `manifests-v1.0.0` **pull request** (they
   are consumed from the AUR/tap repos, not from inside the tarball, so they
   don't need to be in the tagged tree). `main` requires a pull request and
   refuses a direct push, so the job opens one rather than being granted an
   exception to the rule.
4. Both channels update themselves once their secrets exist: the tap gets a PR
   (`HOMEBREW_TAP_TOKEN`), the AUR gets a push (`AUR_SSH_KEY`). **Neither waits
   on the manifest PR** — both read the manifests out of the `packages`
   artifact, so merging it is bookkeeping for the next release to diff against.
   Until those secrets exist, copy the manifests from the release by hand, per
   the sections below.
5. Merge the manifest PR.

Because the tarball is in `dist/ARTIFACTS`, it reaches both the attestation and
the release upload without either step naming a `.tar.gz`: those two read that
file rather than a format list spelled out in YAML.

`bump.sh 1.0.0` still works by hand if CI is ever unavailable — with the tag in
your checkout it builds the identical tarball itself, and `--tarball <file>`
takes one you already have. It falls back to downloading the published asset
only when neither is available, which is why the download can no longer be the
first thing it tries: during a release the asset does not exist yet.
`bump.sh --check 1.0.0` stays useful locally to confirm the manifests match a
cut release.

**Release notes are the PR titles.** The publish job asks GitHub's
`releases/generate-notes` endpoint for the notes and puts them at the top of the
release body — the PR titles merged since the last tag, with no separate notes
file to write. The discipline that makes this good enough: title PRs the way
you'd want them read in release notes, and skim `gh pr list --state merged`
before tagging to retitle anything that wouldn't. Revisit git-cliff only if the
generated notes start needing curation.

Below the notes the same step appends the
[verification checklist](#verifying-a-release-download), so the two questions a
release has to answer — _what changed_ and _how do I check this download_ — are
both in the body. It is composed rather than passed as
`--generate-notes --notes`, because `gh` appends the generated notes **after**
`--notes`, which would bury the notes under the checklist.

## Publishing each channel

Every channel below is gated on the manual approval in `release.yml`, and two of
them (the AUR and the tap) are pushed by CI once their secrets exist — the
checks each section describes are still yours to run first.

**A `v0.0.x` tag reaches none of them.** Those are debug tags, pushed to
exercise the release path rather than to ship, so the `tap` and `aur` jobs skip
on the tag name itself — not merely because a secret is missing. The GitHub
Release is still created, with the packages attached.

### AUR

Not done, and not currently doable: AUR registration is closed to new accounts
because of spam, so there is no account to push from. Everything below is ready
for the day it reopens. Run the gate for **each** package — `aur/say-hi-git`
today, `aur/say-hi` once v1.0.0 exists. namcap is the hard step, not a
suggestion — push nothing while either its `PKGBUILD` or its built-package run
has complaints.

```bash
cd packaging/aur/say-hi-git        # then again in packaging/aur/say-hi
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/say-hi/..., /usr/bin/hi, /etc/profile.d/say-hi.sh
```

**What a clean run looks like.** `namcap PKGBUILD` is silent. `namcap` on the
built package prints exactly three warnings, all of them namcap being unable to
read shell scripts, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding. (`coreutils` is deliberately not in `depends` —
it is in `base`, which packaging guidelines say to assume.)

**The end-to-end check**, which is what caught the `say-hi-git` package shipping
no version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have been through all of this against a local clone (the only
substitution being `source=`, the repo not being published yet): built, linted,
installed into a clean Arch container, exercised, and removed with nothing left
behind.

Then push `PKGBUILD` + `.SRCINFO` — only those two — to
`ssh://aur@aur.archlinux.org/say-hi-git.git`, `say-hi-git` first since it needs
no tag. **That first push is the manual one**, because it is where namcap gates.
After it, `release.yml`'s `aur` job pushes the versioned `say-hi` on every
release but a `v0.0.x` debug tag, given the `AUR_SSH_KEY` secret; `say-hi-git`
has no version to bump and CI never touches it.

Never submit the versioned package with `b2sums=('SKIP')` — `SKIP` is correct
only on `say-hi-git`, whose source is a git ref.

### Homebrew tap

A tap is just a GitHub repo named `homebrew-tap` with a `Formula/` directory.
Copy `packaging/homebrew/say-hi.rb` to `Formula/say-hi.rb` there and
`brew install ivy/tap/say-hi` works — no review, no approval, which is exactly
why `brew audit --strict` is a hard gate here.

**The copy is automated, the checks are not.** `release.yml`'s `tap` job (behind
the same approval as `publish`) opens a PR against `<owner>/homebrew-tap` with
the regenerated formula and the three commands below as its checklist. It needs
a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT scoped to that repo with
contents + pull-requests write — and without it the job says so and does
nothing, which is the state until the tap repo exists. Merging the PR is yours,
as is running these first:

```bash
brew install --build-from-source ./packaging/homebrew/say-hi.rb
brew test say-hi
brew audit --strict --new say-hi
```

`brew audit` needs a _named_ formula, so it wants one in a tap:
`brew tap-new ivy/tap`, copy the file into its `Formula/`, then
`brew audit --strict --new ivy/tap/say-hi`. Passing a path is refused outright.

**What a clean run looks like** — this has been run in the `homebrew/brew`
container against a local tarball, the only substitution being `url`/`sha256`:
install and test exit 0, and audit reports only these two, which are the
unpublished repo and nothing else:

```text
* The homepage URL https://github.com/ivylikethevine/say-hi is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/say-hi.git is not a valid Git URL
```

Two real findings came out of that run and are fixed: the description had to
start with a capital, and `uses_from_macos "openssh"` was rejected — that macro
is for formulae macOS provides _to Homebrew_, and openssh is not one. The
formula now declares no dependencies at all, which is correct: `ssh` and
`base64` ship with macOS and with any Linux that would install this.

A mac is still worth using before the first publish, since the container
exercises Linuxbrew's paths rather than a keg under `/opt/homebrew` — but
nothing about the formula itself is unverified now.

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

A quirk worth knowing: the apk enumerates its contents per
`_HI_PACKAGE_CONTENTS` member in `nfpm.yaml` rather than riding the `type: tree`
entry deb/rpm use, because nfpm 2.47.0's tree walker writes directory modes
apk-tools rejects outright. The packaging suite keeps that copy honest, and CI's
packaging-smoke installs the signed apk on Alpine every PR so the channel can't
silently regress.

No `apt upgrade` — the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if
people ask for a repo to subscribe to.

## Verifying a packaged build locally

This is the half you run on a package **you** just built, before it goes
anywhere. Its near-namesake at the bottom —
[Verifying a release download](#verifying-a-release-download) — is the other
direction: what somebody who downloaded a release runs to check it is the one
this repo published.

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
else it controls from the same variable. CI's packaging-smoke job enforces it
with a double build on every PR. Locally, run them sequentially — nfpm.yaml
hardcodes `./dist/staging`, so `--outdir` cannot run two side by side:

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

One caveat: CI pins nfpm 2.47.0 (`.github/actions/setup-tool/tools.txt`) while
`mkpkg.sh` takes whatever nfpm is on PATH — a different local nfpm can produce
different (still internally reproducible) bytes.

The honest end-to-end check for the `/etc/profile.d` snippet, which is the part
no unit test can prove:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/say-hi_*_all.deb && echo "$_HI_HOME" && hi'
```

## After installing from a package

The tree is root-owned and holds nobody's settings. Each user runs, once:

```bash
/usr/share/say-hi/scripts/install.sh --no-link
```

`--no-link` skips the `/usr/bin/hi` symlink the package already owns. Answers go
to `~/.config/say-hi/`, never into the tree, which is what lets a root-owned
checkout work at all. `hi --update` correctly refuses to `git pull` and points
at the package manager instead.

**Saying `hi` _to_ a packaged machine works whether or not anyone ran that.**
The package's `/etc/profile.d/say-hi.sh` is what `hi.sh`'s `_hi_remote_root`
probe reads to find `/usr/share/say-hi` and use it in place instead of shipping
a payload over it, and `/usr/share` is on the probe's install-prefix list even
if that snippet is gone (GLOSSARY: HI.33).
`tests/targets/install_methods_test.sh` installs a real `.deb`, `.rpm` and
`.apk` on real targets and asserts exactly that.

## Regenerating the demo GIFs

[`docs/tapes/generate.sh`](tapes/generate.sh) renders all of them: one
`vhs` run per tape, cheapest first, with a `fixtures.sh down` in between — no
tape cleans up after itself — and a summary of what rendered, what stood down
for a missing backend, and what failed. Name tapes to render a subset
(`generate.sh docker kube`); `--list` shows them, `--down` clears up after a
crashed run.

**Seven of the eight render themselves.**
[`.github/workflows/demos.yml`](../.github/workflows/demos.yml) runs every tape
but `demo` on the self-hosted runner — the only machine with all four backends —
on
a tape change, weekly, or on dispatch, and hands the GIFs to the Pages build,
which lays them over the committed copies at the same paths. Nothing is
committed back: a bot commit on top of the author's is what branch protection
refuses, and it is the same reason the tests badge is published rather than
written into this file.

The top-of-README demo is the one that goes quietly wrong: it claims to be the
stock defaults, so it is stale the moment the header, the prompt or the tape
changes, and nothing about looking at it says so.
[`.githooks/demo_staleness.sh`](../.githooks/demo_staleness.sh) is the reminder
— it compares `demo.gif`'s last commit against the tape, the fixtures and the
shipped tree, and says which of them moved since. Run it by hand, or wire it up
as a pre-commit hook:

```sh
git config core.hooksPath .githooks
```

It only ever warns. Rendering a binary nobody looked at is the thing this
section exists to argue against, so the hook will not do it for you and will
never block a commit.

By hand it is one `vhs docs/tapes/<name>.tape` per GIF from the repo root, with
the backend running and `hi` on PATH; `docs/tapes/fixtures.sh` builds every
target the tapes connect to, `fixtures.sh down` removes them. There is one more
in [CONFIGURATION.md](CONFIGURATION.md#colors) — `color_preview.tape`, the
only one needing no backend at all.

Two things to get right when you do it that way — the two the script exists to
take care of. `hi` on `$PATH` must be _this_ checkout (`/usr/bin/hi` may point
elsewhere; the script shims its own onto the front of `$PATH`). And the target
image builds from `HEAD`, so uncommitted work shows on the client side of the
GIF but not the target's: render from a commit, or set
`HI_DEMO_SOURCE=worktree`, which is what the script picks for you on a dirty
tree.

Both sides of every GIF are staged, not inherited. Each tape sources a small rc
`fixtures.sh` writes, giving the outside shell hi's own prompt under a chosen
`user@host` instead of the renderer's — and every target gets an explicit
hostname rather than a backend's random hex ID. The pairs vary on purpose:
docker's client is `cache-1` and one of its targets is `cache-1` too, while the
rest say `hi` somewhere they are not.

## Verifying a release download

Releases ship a `SHA256SUMS`, signed build provenance, and a detached
[minisign](https://jedisct1.github.io/minisign/) signature over the sums (the
offline half — no `gh`, no network, one static public key):

```sh
sha256sum -c --ignore-missing SHA256SUMS                        # the bytes match the release
minisign -Vm SHA256SUMS -P 'RWTDcJ3LGWayrAxK6mbMysyOF8mNLOmMUGRl4YSWk5KIoayS+lW0Fy1L'
gh attestation verify say-hi_*_all.deb --repo ivylikethevine/say-hi # which CI run built them
```

**That `minisign` line is load-bearing, not just an example.** `release.yml`'s
publish job `sed`s the public key out of it to build the checklist it puts in
every release body, and fails the release if the pattern stops matching — one
literal copy of the key in the tree rather than two that can drift apart. Keep
it a single line starting `minisign -Vm SHA256SUMS -P '`, with the key in single
quotes; the prose and the trailing comments around it are free to change.

That covers **every** file on the release, `say-hi-<version>.tar.gz` included —
the source tarball the Homebrew formula and the AUR package build from is one
the release built and attested, not GitHub's auto-generated `/archive/` one,
which carries neither sum nor signature. So
`gh attestation verify say-hi-*.tar.gz --repo ivylikethevine/say-hi` answers for
the sources the same way the line above answers for the `.deb`.
