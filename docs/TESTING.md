# Testing

Every script resolves against `$_HI_HOME/say-hi`. The runner defaults
`_HI_HOME` to this checkout's parent, so a fresh clone works with no setup —
but never point anything at your real say-hi install:

```sh
export _HI_HOME=/path/to/parent-of-say-hi
tests/test_runner.sh
```

## Contents

- [Running the tests](#running-the-tests)
  - [Where a suite lives](#where-a-suite-lives)
  - [The container suites run their cases in parallel](#the-container-suites-run-their-cases-in-parallel)
  - [The install-method suite](#the-install-method-suite)
  - [Coverage and profiling](#coverage-and-profiling)
  - [The images are files; the build contexts are not](#the-images-are-files-the-build-contexts-are-not)
    - [What is pinned, and what deliberately is not](#what-is-pinned-and-what-deliberately-is-not)
  - [The score has a ceiling here](#the-score-has-a-ceiling-here)
- [The lint gate](#the-lint-gate)
- [Relaying](#relaying)
- [Local-only](#local-only)

## Running the tests

`tests/test_runner.sh` (`hi --test` once installed) times each suite and prints
a colored pass/fail summary at the end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --group fast       # what CI runs on every push/PR
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

A passing suite's transcript collapses to one status line; failures replay in
full and are recapped under the summary table. `--verbose` (`_HI_VERBOSE=1`)
streams every transcript live, for a case that fails only under the runner. A
suite whose backend is missing reports **SKIPPED**, never green, and so does a
single case inside a suite that otherwise runs (an image that would not build,
a tool that is not installed). `--require-run` — what CI's lint, e2e and
backends jobs pass — turns both kinds of skip into failures: the suite goes
red, its transcript replays, and each stood-down case is named in the recap
under the summary table.

`--host-report` (`_HI_HOST_REPORT=1`) prints one block before the first suite:
bash, the OS, GNU/BSD/busybox userland, the locale's glyph verdict, which tree
`$_HI_HOME` resolves to, which backends answer, and the lint tools' versions —
the questions asked when a suite passes on one machine and fails on another.
CI passes it on every job. The `_HI_HOME` half prints on **every** run when
the tree under test is not the one you invoked the runner from — the quietest
way to get a wrong result here.

Five groups (`--group <name>`); `--list` prints the membership:

- **`fast`** — dependency-free unit suites, the first thing CI runs, on every
  platform job. Includes `test_lib`, `test_lib_report`, `test_lib_par` and
  `test_runner`, which are the harness testing itself. Its suites run **side
  by side** (up to four, or the CPU count), each in its own workdir with its
  own tally files, and the transcripts are replayed in table order — so the
  run reads exactly like a serial one and takes about as long as its slowest
  suite. `_HI_RUNNER_WIDTH=1` puts it back to one at a time; `--verbose`
  implies that, since two live transcripts would interleave.
- **`lint`** — the linter sweep ([The lint gate](#the-lint-gate)), run once,
  as its own CI step on the ubuntu job against pinned tool versions. The
  macOS, Windows and FreeBSD jobs run `fast` alone: linting text does not
  depend on the userland underneath it.
- **`bench`** — hot-path timings against ceilings, plus the payload's two size
  budgets. Serial, since it measures.
- **`e2e`** — `ssh`, `ssh_disconnect`, `ssh_relay`, `ssh_wire`,
  `install_methods`, `docker`, `framework`: throwaway containers driving
  `hi.sh`'s actual connection paths (`_say_hi` and `_say_hi_container`).
  `ssh_wire` is the one that measures: a session to a bare target and to one
  with say-hi installed, each through a byte-counting `ProxyCommand`, with
  the counts set against the figure hi prints on its connect line.
- **`backends`** — `podman`, `nomad`, `kube`: split from `e2e` because they
  need extra runner setup; a separate, slower CI job. `e2e` and `backends`
  run their suites one at a time — they contend on one container daemon.

Every test script also runs directly, e.g. `tests/lint/shellcheck_test.sh`.

Individual fast cases stand down the same way, through two guards:
`_hi_check_requires <bin>` skips a case when a _command_ is missing;
`_hi_check_capable <capability>` when a _facility_ is — something `command -v`
cannot answer. The roster is `_hi_capable` (`tests/lib/fixtures.sh`), two
entries long: `symlink` makes one and tests `[ -L ]`, so a filesystem that
refuses _or_ silently copies reads as no; `pty` is python3 being able to
`import pty`. Both exist for Git Bash, and both are probes rather than OS
sniffs. `_hi_par_check_capable` is the twin a parallel suite uses.

### Where a suite lives

`tests/<the directory it tests>/`. `tests/common/`, `tests/settings/`,
`tests/scripts/` and `tests/packaging/` mirror the tree; `tests/hi/` and
`tests/load/` cover the two root scripts; `tests/lint/` is the lint gate,
`tests/bench/` the timings, `tests/targets/` the container/ssh e2e suites, and
`tests/harness/` the suites that test the harness. The harness itself is
`tests/test_lib.sh`, a façade over `tests/lib/`. A suite sources the façade and
nothing else (`docs/GLOSSARY.md`'s HI.34).

### The container suites run their cases in parallel

`ssh`, `ssh_relay`, `install_methods`, `docker`, `podman`, `framework` and
`kube` spend nearly all their wall clock waiting on one container at a time, so
their cases run in a batch: `_hi_par_case` (`tests/lib/parallel.sh`) submits a
case to a background subshell, `_hi_par_wait` collects the batch. Each case
writes its verdict to a file the parent tallies, registers what it started on
a teardown ledger the exit trap sweeps, and buffers its output to replay **in
submission order** — a parallel transcript reads exactly like a serial one.
Cases that read another case's files stay serial.

The batch is capped at four, or the CPU count if smaller — unbounded fan-out
thrashes the docker daemon on a laptop. `_HI_PAR_WIDTH` overrides it:

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, same code path - for bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

`nomad` pins itself to `_HI_PAR_WIDTH=1`: its jobs are tracked in a shell array
its cleanup hook purges, the one fixture in the tree that is not case-scoped.

### The install-method suite

`install_methods` is `ssh_test.sh`'s sibling, split on what each varies: `ssh`
runs one install against every login shell; `install_methods` runs one login
shell against every way say-hi gets onto a machine — the `.deb`, `.rpm`,
`.apk`, a Homebrew-shaped keg, a system-wide `install.sh --prefix`, and a tree
whose `/etc/profile.d` announcement has been removed. They share the case
runner in `tests/lib/ssh.sh`.

Every case asserts the same thing: `$_HI_ROOT` is the path the installer left,
and no payload was copied — a session that merely works proves nothing, since
hi shipping its whole tree over the top produces one of those too.

The three package cases build what they install with `packaging/mkpkg.sh`, so
they need `nfpm`; without it they stand down yellow **per case** — caught by
`--require-run` like any other stand-down, and `ci.yml`'s e2e job pins nfpm
through `setup-tool` so they actually run.

### Coverage and profiling

Three hand-run tools sit beside the suites, all out of CI. Two measure
coverage, they disagree, and neither is right.

`tests/coverage.sh` runs the fast suites under kcov. Its numbers are
untrustworthy: kcov loses the DEBUG trap once the harness is sourced, so a
figure describes what ran while things were _loading_ — `common/git_prompt.sh`
reads 2.56% with seventeen cases passing against it. Don't write tests to move
those figures.

`tests/coverage_v2.sh` is the same sweep under
[bashcov](https://github.com/infertux/bashcov), which reads bash's `xtrace`
and so cannot fail that way — it puts `common/git_prompt.sh` at 92.68%. It
fails the other way: every line of a **heredoc body** counts as covered, so
anything that generates scripts reads high — `hi.sh` at 97.38%, with `_say_hi`
and `_say_hi_container` at 100% though nothing in `--group fast` calls them.
Files with no heredocs (all of `common/` and `settings/`) are the ones to
believe. It needs `gem install --user-install bashcov`; the script finds the
binary off `$PATH`, writes a `.simplecov` into the checkout for the run and
removes it after, and refuses to start rather than overwrite one you have.

The dispatch-only `coverage.yml` and `coverage-v2.yml` publish those two
aggregates as shields endpoints (`badges/coverage.json`,
`badges/coverage-v2.json`) via `pages.yml`, labelled `load-time` /
`heredoc-inflated` rather than `coverage`. README deliberately does not show
them: a badge whose own docs say to ignore it costs the row beside it
credibility. Neither gates anything.

`tests/profile.sh` is what to run when a `--group bench` ceiling trips:
`_hi_bench` says _whether_ a path got slower, this says _which command in it_
did. It profiles the four bash paths the bench guards through
[timep](https://github.com/jkool702/timep), **in a container**
(`tests/dockerfiles/timep.Dockerfile`). The container is not incidental: timep
carries base64-encoded loadable-builtin `.so` files and `enable -f`s them into
the running shell, so it is worth sandboxing; the box also settles three
requirements timep does not check — glibc ≥ 2.38, a bash with `enable -f`, and
an **exec-capable** `/dev/shm` (`--tmpfs /dev/shm:rw,exec`). Missing any,
timep exits 0 and writes arithmetic errors instead of times, which is why
`profile.sh` grades the output and not the status. The checkout is mounted
read-only; set `$_HI_TIMEP` to mount a local copy of timep you have read. Read
the ranking, not the milliseconds — they come from the container.

### The images are files; the build contexts are not

Every container image an e2e suite builds is a real Dockerfile under
[`tests/dockerfiles/`](../tests/dockerfiles): `sshd-debian`, `sshd-alpine` and
`sshd-fedora` for the ssh targets, `alpine-shell` for the bare shell ones,
`installed-*` for the install-method targets (`installed-pkg` takes the
`.deb`/`.rpm`/`.apk` as a build arg), `framework` for the nine shell
frameworks (one Dockerfile, the framework a build arg naming a script under
`frameworks/`). What stays generated per case is the _build context_: the
throwaway keypair's `entrypoint.sh`, and for the pre-installed case the repo
itself. Suites reach a file through `_hi_dockerfile <stem>`; variants differing
only by a package list or base image are one file plus a `--build-arg`
(`PKGS`, `BASE`). `docs/tapes/fixtures.sh` builds from the same folder,
spelling the path out, since a tape render does not source `test_lib.sh`.

The lint gate checks both directions: no Dockerfile without a caller, no caller
naming a Dockerfile that isn't there.

### What is pinned, and what deliberately is not

Scorecard's Pinned-Dependencies check reports every line below and will keep
reporting some of them. The answer, so it is not re-decided each time:

**Upstream base images are digest-pinned, non-negotiably.** Every `FROM` in
`tests/dockerfiles/` that names an upstream image (8 of 16 - alpine, ubuntu,
debian, fedora, bash) carries a `@sha256:`. A digest is what makes a failed
e2e run reproducible and a base-image move a deliberate, reviewable act.
Dependabot bumps the digests weekly; the Alpine 3.20 → 3.24 upgrade in
August 2026 (3.20 past EOL since 2026-04-01) is the case for it.

The other 8 are `FROM ${BASE}` over an image the suite builds locally
(`hi-test-sshd`, `hi-demo-sshd-base`, `hi-test-installed-prefix` - see
`--build-arg BASE=` in `tests/targets/*_test.sh`), which has no upstream
digest to pin against. Scorecard's Pinned-Dependencies check flags these as
unpinned `containerImage` dependencies with no fix available; `.scorecard.yml`
annotates the check `test-data` rather than pretending it's clean.

**The same tags named in shell and YAML are guarded, not watched.** `alpine:`
and `debian:` also appear as plain tags in `tests/lib/backend.sh`,
`docs/tapes/fixtures.sh` and `ci.yml`'s packaging smoke — places Dependabot
cannot see. `lint_image_tags` fails the build when a tag named anywhere in the
tree disagrees with the digest-pinned one in `tests/dockerfiles/`.

**The three `curl | sh` framework installers are pinned to a release each, not
a hash.** `frameworks/atuin.sh` (v18.20.1, in the download URL),
`frameworks/mise.sh` (v2026.8.14, via `MISE_VERSION`) and
`frameworks/starship.sh` (v1.26.0, via `--version`) each name the pin in their
own header and are bumped by hand when that framework's own bugs are worth
chasing — not on a schedule; `ci.yml`'s weekly run re-tests them against
whatever else moved but does not touch the pin. Scorecard's
Pinned-Dependencies check still reports all three as unpinned `downloadThenRun`
dependencies: its probe has no "pinned to a version" state for a download
piped to a shell, only pinned-by-hash or not. Each script runs under
`pipefail`, so a 404 or a checksum mismatch fails the build rather than
shipping an image with the framework silently missing.

Nothing in `tests/dockerfiles/` reaches a release; the workflows and actions
the release path uses are SHA-pinned separately.

What Scorecard still dings here, and how it's annotated, is in
[`.scorecard.yml`](../.scorecard.yml) at the repo root.

### The score has a ceiling here

Scorecard weights each check (Binary-Artifacts, License and the rest that sit
at 10 count fully) and averages, so it's worth writing down which of the low
scores are actually fixable in this tree and which aren't, rather than
re-deciding it each time the report is read:

- **Code-Review sits at 0** — 0 of the last several changesets carry an
  approved review, because there is one maintainer and nobody else to approve
  a PR. A `Reviewed-by:` trailer would satisfy the scanner without a review
  having happened; that's not going to be added. This is the single largest
  fixable-looking gap in the report and it isn't fixable without a second
  person.
- **Fuzzing sits at 0** — say-hi is bash, and Scorecard's fuzzing probe
  detects OSS-Fuzz, ClusterFuzzLite, Go native fuzzing, cargo-fuzz and
  OneFuzz integrations. None targets shell. `.scorecard.yml` marks this
  `not-applicable`.
- **Contributors sits at 3** — the check wants ≥2 contributing organizations
  among recent contributors; there's one. `.scorecard.yml` marks this
  `not-applicable` too.
- **CII-Best-Practices sits at 0** — no project is registered yet at
  [bestpractices.dev](https://www.bestpractices.dev/) (the OpenSSF Best
  Practices badge, a self-assessment questionnaire separate from Scorecard).
  The answers are drafted at
  [CII-BEST-PRACTICES-DRAFT.md](CII-BEST-PRACTICES-DRAFT.md); the score moves
  off 0 as soon as the project is registered there and the draft is
  transcribed, which needs no code change. Passing still waits on the first
  release — three MUST criteria are release-shaped.
- **Signed-Releases reads -1 (excluded from the average)**, not a fixable 0 —
  Scorecard hasn't seen a release yet. `release.yml` already ships
  `dist/SHA256SUMS.minisig` and a build-provenance attestation, and `.minisig`
  is one of the extensions the check recognizes, so this should resolve on
  its own with no further change once
  [a release ships under branch protection](ROADMAP.md#quick-wins).

## The lint gate

`--group lint` is four suites, sixteen checks between them, and CI runs all of
them. Each suite is its own process (`tests/test_runner.sh shellcheck`,
`dialects`, `tools`, `drift`), so a failure in one never hides what the others
found; each reports its own file/failure/skip tally to the runner's summary
table the same way every other suite does.

**`shellcheck`** (`tests/lint/shellcheck_test.sh`) — one check, and the whole
cost of the group:

One check runs **before** it and is fatal rather than counted: every `source`
of a `$_HI_CONFIG_DIR/...` path must carry a `# shellcheck source=` directive
above it. `.shellcheckrc` sets `source-path=SCRIPTDIR`, so under
`shellcheck -x` the basename resolves against the sourcing file's own
directory — and where it names that file, the linter follows it into itself and
re-parses until the kernel OOM-kills it (~33GB resident on a 38GB machine,
editor included). It runs first because the damage happens in the fan-out
right after it.

1. **shellcheck** over every `*.sh` (CI pins the version in
   `.github/actions/setup-tool/tools.txt`). The file list is dealt into one
   invocation per CPU and replayed in order; `_HI_SC_WIDTH=1` puts it back on a
   single process.

**`dialects`** (`tests/lint/dialects_test.sh`) — the shell-dialect syntax
checks, four of them:

2. **Native syntax checks**: `zsh -n` / `fish --no-execute` over the files those
   shells parse for themselves — using whatever `zsh` and `fish` this machine
   has.
3. **The fish 3.7 floor**: the same files fish reads, parsed again inside a
   digest-pinned **fish 3.7.0** (`tests/dockerfiles/fish37.Dockerfile`, Ubuntu
   24.04's fish, which is CI's). Check 2 cannot cover this: fish 4 accepts
   constructs 3.7 rejects, so a developer on current fish gets a green run and
   CI does not. The construct that earned this check was a *comment inside a
   `{ ... }` block* in `common/paths.sh` — `{` opens a brace expansion to fish
   and `#` is not a comment inside one, so the file died with "Mismatched
   braces", taking `$_HI_TARGETS`, every path and every alias with it. fish 4.8
   parsed it; 3.7 did not; every fish case in CI failed at once. The rule that
   follows is written at the block itself: nothing but `export NAME=value`
   lines between those braces. Skips yellow without docker.
4. **The fish 4 ceiling**: the same files, parsed again inside a digest-pinned
   **fish 4** (`tests/dockerfiles/fish4.Dockerfile`, Ubuntu 26.04's fish) —
   the floor's counterpart, catching a construct 3.7 accepts that fish 4
   rejects or has removed. It exists because CI's runners are 24.04, so
   without it nothing in CI parses these files under fish 4 either. Skips
   yellow without docker.
5. **The zsh 5.8 floor**: the same idea one shell over, and it does more than
   parse. zsh's risky constructs here — `add-zsh-hook zshexit`, the
   `${(%):-%x}` the tree is derived with, `${~pat}`, the `KSH_ARRAYS`
   divergence — parse on every zsh and only misbehave on an old one, so a
   `zsh -n` sweep would wave all of them through. This one parses the files and
   then *sources* `common/zsh.zsh` in a real interactive zsh inside a pinned
   **zsh 5.8** (`tests/dockerfiles/zsh58.Dockerfile`, Debian oldstable's), and
   asks for the four things a session depends on: a prompt, the aliases, a
   resolved host color and the prompt separator. 5.8 because bookworm, noble,
   alpine and macOS all ship 5.9 — no machine anyone develops on is the floor.
   Skips yellow without docker.

The floor and ceiling checks are the exception to the skip rule in one
direction: with docker *present*, an image that will not build is a
**failure**, not a skip. The base is digest-pinned and the only other thing in
any of the three files is an apt install with a version assertion on it, so
"would not build" means the distro moved off the version that check claims to
be — which is the news the check exists to carry.

**`tools`** (`tests/lint/tools_test.sh`) — the external-tool wrappers, four of
them, each skipping yellow when its tool isn't installed locally (CI always
has all four):

6. **shfmt** as a formatting gate over the same `*.sh` list shellcheck reads,
   style from `.editorconfig`. Fix a red run with `shfmt -w` on the paths it
   names, not `shfmt -w .`, which would also reformat `common/zsh.zsh`.
7. **checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
   really do parse on minimal targets.
8. **mandoc** over `docs/hi.1` (`mandoc -T lint -W warning`): the page ships
   in every package, and a roff mistake renders as garbage on `man hi` while
   failing nothing else.
9. **typos** over the whole tree; the allowlist is `_typos.toml` at the root,
   one commented line per term the checker reads wrong.

**`drift`** (`tests/lint/drift_test.sh`) — the repo-consistency sweeps, seven
of them: nothing here wraps an external tool, every one is a grep or a
small parser checking that something written down elsewhere still agrees with
what the tree does.

10. **The bash-3.2 grep**: no `mapfile`, associative arrays, namerefs or
    `${x,,}`. Every deliberately odd construct this forces is explained once in
    [GLOSSARY.md](GLOSSARY.md); code references entries by `GLOSSARY: HI.NN`
    tag.
11. **The `$HOME` default sweep**: nothing may fall back to `$HOME` when it
    derives the say-hi tree. Wider than the shellcheck list — `*.zsh`, `*.fish`
    and `*.md` too, since the docs teach the rule as much as the code obeys it.
12. **GLOSSARY tags**: every `GLOSSARY: HI.NN` in the tree has to name a code
    [GLOSSARY.md](GLOSSARY.md) defines, and every entry has to be referenced.
    Codes are matched, not titles; matched anywhere on a line, so keep the code
    on the same line as the marker.
13. **The settings roster**: every name the tree treats as a setting
    (`_HI_TOGGLES` in `common/core.sh`, the variable column of
    every `_HI_*_PROMPTS` table in `scripts/configure.sh`) has
    a row in [CONFIGURATION.md](CONFIGURATION.md)'s _Every setting_ table, and
    every row there names a variable the tree still reads. Only that section is
    matched. A name assembled at run time (`_HI_PROMPT_END_$SHELL`) is matched
    by its literal prefix.
14. **Liquid syntax**: every page Jekyll's Pages build actually renders (derived
    from `_config.yml`'s `exclude:` block, not hand-kept) may not carry a raw
    Liquid delimiter outside a guarded span — Liquid tokenizes the page before
    Markdown, so a fenced GitHub Actions expression gets no shelter from the
    fence. This is what broke the Pages build on
    `docs/SELFHOSTED-RUNNERS.md` once already; that file's own comment names
    the exact construct and the guard around it.
15. **tests/dockerfiles/**: every image definition has a caller and vice versa.
16. **Image tags**: every `alpine:3.24`/`debian:bookworm-slim`/`debian:bullseye-slim`/`bash:3.2`/`ubuntu:24.04`/`ubuntu:26.04` named
    as a plain tag in shell or YAML agrees with the digest-pinned version in
    `tests/dockerfiles`.

## Relaying

`hi` chains: from a session on B you can `hi C`, and the second hop is a full
hi session — from a _disposable_ session too, because `hi.sh` is a member of
`$_HI_PAYLOAD` and arrives with its exec bit (which is why the write-back is
`cat` and not `mv`, GLOSSARY HI.09). `ssh_relay` is the proof: A → B → C,
config intact on the final hop, cleanup traps firing on **both** B and C, on a
clean exit and on the link being killed mid-relay. The one tier that cannot
relay is the container transport's bash-less fallback, which ships
`aliases.sh` alone and never loads `paths.sh` — there `hi` is not defined.

## Local-only

`tests/` is stripped from the payload, so `hi --test` on a target says so
rather than running. Every flag that needs `scripts/`, `tests/` or a `.git`
answers the same way there, and `--test` and `--update` answer that way in a
package-manager install too, which ships `scripts/` but neither of the others.
**Which flag needs what is `docs/hi.1`'s OPTIONS section**, drift-checked
against `common/targets.sh`'s completion roster by `tests/hi/parse_test.sh`.
`hi --packages-preview` is the one that does not refuse: its legend lives in
`scripts/`, but the check it previews lives in the shipped `common/header.sh`,
so on a target it runs that half instead.
