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
- [Why the harness is hand-rolled](#why-the-harness-is-hand-rolled)
- [The lint gate](#the-lint-gate)
- [Relaying](#relaying)
- [Local-only](#local-only)

## Running the tests

`tests/test_runner.sh` (`hi --test` once installed) times each suite and prints
a colored pass/fail summary:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --group fast       # what CI runs on every push/PR
tests/test_runner.sh --group fast --shard 1/2 # half of it, as a CI shard runs
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

- A passing suite's transcript collapses to one status line; failures replay
  in full and are recapped under the summary table. `--verbose`
  (`_HI_VERBOSE=1`) streams every transcript live, for a case that fails only
  under the runner.
- A suite whose backend is missing reports **SKIPPED**, never green; so does a
  single case (an image that would not build, a tool not installed).
  `--require-run` — what CI's lint, e2e and backends jobs pass — turns both
  into failures: the suite goes red, its transcript replays, and each
  stood-down case is named in the recap.
- `--host-report` (`_HI_HOST_REPORT=1`) prints one block before the first
  suite: bash, the OS, GNU/BSD/busybox userland, the locale's glyph verdict,
  which tree `$_HI_HOME` resolves to, which backends answer, and the lint
  tools' versions. CI passes it on every job. The `_HI_HOME` half prints on
  **every** run when the tree under test is not the one you invoked the
  runner from — the quietest way to get a wrong result here.
- Every test script also runs directly, e.g. `tests/lint/shellcheck_test.sh`.
- Under a wrapper that leaves the process a controlling terminal but puts it
  in a background process group — `timeout` from a shell prompt, or a
  `wsl.exe` session, whose stdio are pipes but whose session still has a
  terminal — run it as `setsid -w timeout … tests/test_runner.sh …`. The
  `load` and `install_location` suites start `bash -i`/`zsh -i`/`fish -i`
  sessions with stderr redirected; bash then opens `/dev/tty` for job control,
  finds itself in the background, and stops on SIGTTIN until the wrapper's
  deadline. `setsid` outside `timeout`, not inside, so `timeout` still kills
  the runner's own process group. GitHub's ubuntu runner has no controlling
  terminal, which is why the same run is clean there without it.
- Under WSL 2, drop the `/mnt/` entries from `$PATH` before running (the
  `wsl-suites` job in `windows-e2e.yml` does). WSL's interop default appends
  the Windows PATH, some fifty `/mnt/c/...` directories served over 9p, and
  the package check is 279 `command -v` lookups per render with no miss
  caching: one `full_check` took 30–37s there against 30ms on ext4, which
  is past the `configure` suite's 30s pty cases and, over the `header` and
  `preview` suites too, past the job's 900s kill.

Five groups (`--group <name>`; `--list` prints the membership):

- **`fast`** — dependency-free unit suites, the first thing CI runs on every
  platform job; `test_lib`, `test_lib_report`, `test_lib_par` and
  `test_runner` are the harness testing itself. Suites run **side by side**
  (one per CPU), each in its own workdir with its own tally
  files, transcripts replayed in table order, so the run reads like a serial
  one and takes about as long as its slowest suite. `_HI_RUNNER_WIDTH=1` puts
  it back to one at a time; `--verbose` implies that, since two live
  transcripts would interleave. `--shard <i>/<n>` keeps every n-th suite of
  the selection from the i-th on, so one group can be split across runners:
  the Windows client job runs `fast` as two shards, because backgrounded
  suites barely overlap under MSYS and only more machines shorten that run.
- **`lint`** — [The lint gate](#the-lint-gate), run once as its own CI job on
  ubuntu against pinned tool versions, side by side with `fast`'s job. The
  macOS, Windows and FreeBSD jobs run `fast` alone: linting text does not
  depend on the userland.
- **`bench`** — hot-path timings against ceilings, plus the payload's two size
  budgets. Serial, since it measures.
- **`e2e`** — `ssh`, `ssh_disconnect`, `ssh_relay`, `ssh_wire`,
  `install_methods`, `repo`, `docker`, `framework`: throwaway containers
  driving `hi.sh`'s actual connection paths (`_say_hi` and
  `_say_hi_container`). `ssh_wire` measures: a session to a bare target and
  to one with say-hi installed, each through a byte-counting `ProxyCommand`,
  checked against the figure hi prints on its connect line. `repo` is the
  one suite about packaging rather than sessions: it builds the package
  repository with throwaway keys and installs from it as an apt, a dnf and an
  apk client, signatures verified.
- **`backends`** — `podman`, `nomad`, `kube`: split from `e2e` because they
  need extra runner setup; a separate, slower CI job. `e2e` and `backends`
  run one suite at a time — they contend on one container daemon.

Fast cases stand down through two guards: `_hi_check_requires <bin>` skips a
case when a _command_ is missing, `_hi_check_capable <capability>` when a
_facility_ is — something `command -v` cannot answer. The roster,
`_hi_capable` (`tests/lib/fixtures.sh`), has five entries. Two are probes
rather than OS sniffs, both for Git Bash: `symlink` makes one and tests
`[ -L ]`, so a filesystem that refuses _or_ silently copies reads as no; `pty`
is python3 being able to `import pty`. The other three are `uname`-based
guards for the same MSYS/Cygwin tier: `lockout` (a `chmod 555` directory
actually refuses a write, rather than the runtime looking the other way),
`fork_concurrency` (background subshells genuinely overlap) and `mode_bits`
(a reported permission string reflects `chmod`'s own bits). `_hi_par_check_capable`
is the parallel twin.

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
submission order**, so the transcript reads like a serial one. Cases that read
another case's files stay serial.

The batch is capped at four, or the CPU count if smaller — unbounded fan-out
thrashes the docker daemon on a laptop. A suite whose cases are plain local
processes (`configure`'s pty runs, `install_location`'s shells, the harness
suites' nested runners) sets `_HI_PAR_LOCAL=1` at its top and gets the whole
CPU count instead. `_HI_PAR_WIDTH` overrides both:

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, same code path - for bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

`nomad` pins itself to `_HI_PAR_WIDTH=1`: its jobs are tracked in a shell array
its cleanup hook purges, the one fixture in the tree that is not case-scoped.

The pty-driven cases (`configure`, `install`) kill their child after 30s and
count that as a failure; `_HI_CASE_TIMEOUT` raises the deadline on a host that
is slow for a reason the suites cannot fix, the way `_HI_SSH_CASE_TIMEOUT`
(90s) does for the ssh cases.

### The install-method suite

`install_methods` is `ssh_test.sh`'s sibling: `ssh` runs one install against
every login shell; `install_methods` runs one login shell against every way
say-hi gets onto a machine — the `.deb`, `.rpm`, `.apk`, a Homebrew-shaped
keg, a system-wide `install.sh --prefix`, and a tree with no `/etc/profile.d`
announcement. They share the case runner in `tests/lib/ssh.sh`.

Every case asserts the same thing: `$_HI_ROOT` is the path the installer left,
and no payload was copied — a session that merely works proves nothing, since
hi shipping its whole tree over the top produces one of those too.

The three package cases build what they install with `packaging/mkpkg.sh`, so
they need `nfpm`; without it they stand down yellow **per case**, which
`--require-run` catches. `ci.yml`'s e2e job pins nfpm through `setup-tool` so
they actually run.

### Coverage and profiling

Two coverage tools and a profiler. The coverage pair runs by hand (unsharded,
the whole sweep in one process) and in CI (`coverage.yml`, after every green
CI battery on a push to `main`) over the full suite sweep — every suite the
box's backends can host — and their aggregates land within a few points of
each other. That makes the figures usable: for finding untested arms in the
per-file report and for watching the trend, never as a gate. Both sweeps pin
`_HI_PAR_WIDTH=1`: a suite's cases share one trace stream, and a batch writing
into it side by side loses lines. `_HI_SC_WIDTH` is unrelated (the shellcheck
suite's own fan-out) and moot here besides — both drivers drop `shellcheck`
from the sweep.

In CI, each tool is sharded 4 ways (`--shard i/4`, the same knob
`windows-client.yml` and `ci.yml`'s `e2e` job use) and merged by a gather job
— `kcov --merge` over the four shards' `parts/` directories for kcov, a plain
JSON hash union over the four shards' `--command-name`-keyed `.resultset.json`
files for bashcov, since shards partition the suite table and so never share a
suite name. No change to either driver script was needed: `_hi_cov_select_suites`
already passes `--shard` straight through to `test_runner.sh`.

- `tests/coverage.sh` runs the sweep under kcov. An earlier kcov lost its
  DEBUG trap once the harness was sourced and read whole suites as
  load-time-only (`common/git_prompt.sh` at 2.56% with seventeen cases
  passing against it); the header keeps the measured record of that
  failure, and its probe is the thing to re-run if the two badges ever
  diverge again.
- `tests/coverage_v2.sh` is the same sweep under
  [bashcov](https://github.com/infertux/bashcov), which reads bash's
  `xtrace`. Its residual skews run the other way from kcov's: every line of
  a **heredoc body** counts as covered whether or not it ran, and children
  under `env -i` or inside containers drop out of the trace — so a single
  file reads a few points off in either direction while the pair brackets
  the truth. It needs `gem install --user-install bashcov`; the script
  finds the binary off `$PATH`, writes a `.simplecov` into the checkout for
  the run, removes it after, and refuses to start rather than overwrite one
  you have.

`coverage.yml` publishes both aggregates as shields endpoints
(`badges/coverage.json`, `badges/coverage-v2.json`) via `pages.yml`, each
labelled by its measurer and computed over the shipped product only — the
badge math excludes `tests/` and `docs/`, the same subject both reports
declare. Each refreshes as soon as its sweep finishes — `pages.yml` redeploys
on a completed Coverage run as well as on a green CI — so a badge is only ever
as old as the sweep, never a push behind. Neither gates anything. Both stay
because they cannot err in the
same direction: a file that reads low in bashcov is genuinely uncovered, a
line that reads covered in kcov genuinely ran, and the two agreeing is what
makes the aggregate worth believing.

Two shipped files sit outside what either tool can report at all:
`common/zsh.zsh` and `common/config.fish`. Both instrumentation methods need
a bash process — kcov's DEBUG trap and bashcov's `xtrace` are bash
mechanisms — and neither zsh nor fish provides one, so no line-coverage
percentage for these two is honest at any number. What stands in instead:
`tests/lint/dialects_test.sh` sources `common/zsh.zsh` into a real
interactive zsh and asserts four behaviors (the prompt, the aliases, a
resolved host color, the prompt separator), and separately parses both files
under real zsh and fish; `tests/common/exports_test.sh` and
`tests/hi/prompt_test.sh` drift-check `common/config.fish` against
`common/core.sh` (glyphs, colors, the prompt separator, the 32-column branch
shorten) line by line rather than by running it.

`tests/profile.sh` is for a tripped `--group bench` ceiling: `_hi_bench` says
_whether_ a path got slower, this says _which command in it_ did. It profiles
the four bash paths the bench guards through
[timep](https://github.com/jkool702/timep), **in a container**
(`tests/dockerfiles/timep.Dockerfile`): timep `enable -f`s base64-encoded
loadable-builtin `.so` files into the running shell, so it is worth
sandboxing, and the box settles three requirements timep does not check —
glibc ≥ 2.38, a bash with `enable -f`, and an **exec-capable** `/dev/shm`
(`--tmpfs /dev/shm:rw,exec`). Missing any, timep exits 0 and writes arithmetic
errors instead of times, so `profile.sh` grades the output, not the status.
The checkout is mounted read-only; `$_HI_TIMEP` mounts a local copy of timep
you have read. Read the ranking, not the milliseconds — they come from the
container.

### The images are files; the build contexts are not

Every container image an e2e suite builds is a real Dockerfile under
[`tests/dockerfiles/`](../tests/dockerfiles): `sshd-debian`, `sshd-alpine` and
`sshd-fedora` for the ssh targets, `alpine-shell` for the bare shell ones,
`installed-*` for the install-method targets (`installed-pkg` takes the
`.deb`/`.rpm`/`.apk` as a build arg), `framework` for the nine shell
frameworks (one Dockerfile, the framework a build arg naming a script under
`frameworks/`), `apt-client` for the `repo` suite's apt subscriber (ubuntu with
openssh-client in place and no Ubuntu archive on its sources list, so the
cases fetch from the repository under test and nowhere else). Only the _build context_ is generated per case: the throwaway
keypair's `entrypoint.sh`, and for the pre-installed case the repo itself.
Suites reach a file through `_hi_dockerfile <stem>`; variants differing only
by a package list or base image are one file plus a `--build-arg` (`PKGS`,
`BASE`). `docs/tapes/fixtures.sh` builds from the same folder, spelling the
path out, since a tape render does not source `test_lib.sh`. The lint gate
checks both directions: no Dockerfile without a caller, no caller naming a
Dockerfile that isn't there.

### What is pinned, and what deliberately is not

Scorecard's Pinned-Dependencies check reports every line below and will keep
reporting some of them.

**Upstream base images are digest-pinned, non-negotiably.** Every `FROM` in
`tests/dockerfiles/` that names an upstream image (11 of 19 - alpine, ubuntu,
debian, fedora, bash) carries a `@sha256:`: a digest is what makes a failed
e2e run reproducible and a base-image move a deliberate, reviewable act.
Dependabot bumps the digests weekly; the Alpine 3.20 → 3.24 upgrade (3.20 past
EOL since 2026-04-01) is the case for it. The other 8 are `FROM ${BASE}` over
an image the suite builds locally (`hi-test-sshd`, `hi-demo-sshd-base`,
`hi-test-installed-prefix` - see `--build-arg BASE=` in
`tests/targets/*_test.sh`), with no upstream digest to pin against; Scorecard
flags them as unpinned `containerImage` dependencies with no fix available,
and `.scorecard.yml` annotates the check `test-data` rather than pretending
it's clean.

**The same tags named in shell and YAML are guarded, not watched.** `alpine:`
and `debian:` also appear as plain tags in `tests/lib/backend.sh`,
`docs/tapes/fixtures.sh` and `ci.yml`'s packaging smoke — places Dependabot
cannot see. `lint_image_tags` fails the build when a tag named anywhere in the
tree disagrees with the digest-pinned ones in `tests/dockerfiles/`;
`lint_image_digests` when two Dockerfiles pin one tag to different digests.

**The three `curl | sh` framework installers are pinned to a release, and the
fetched script itself to a hash.** `frameworks/atuin.sh` (v18.20.1, in the
download URL), `frameworks/mise.sh` (v2026.8.14, via `MISE_VERSION`) and
`frameworks/starship.sh` (v1.26.0, via `--version`) each name the version pin
in their own header and are bumped by hand when that framework's own bugs are
worth chasing, not on a schedule; `ci.yml`'s weekly run re-tests them against
whatever else moved but does not touch the pin. Each now downloads to a file
first and `sha256sum -c`s it before running `sh` on it, rather than piping
`curl` straight into a shell. Atuin's URL names the release tag, so the hash
tracks the version pin above it and both are bumped together. mise's and
starship's own install scripts are generic bootstrap endpoints
(`mise.run`, `starship.rs/install.sh`) that install whatever version their env
var or flag names, so the hash pins _that day's copy of the installer_, not
the app version - a hash mismatch means the framework's own installer
changed, not that the pinned app version did, and needs a fresh hash rather
than a version bump. Each script runs under `pipefail`, so a 404, a checksum
mismatch or the framework's installer changing shape fails the build rather
than shipping an image with the framework silently missing.

Nothing in `tests/dockerfiles/` reaches a release; the workflows and actions
the release path uses are SHA-pinned separately. What Scorecard still dings
here, and how it's annotated, is [`.scorecard.yml`](../.scorecard.yml).

### The score has a ceiling here

Scorecard weights each check (Binary-Artifacts, License and the rest that sit
at 10 count fully) and averages. Which of the low scores are fixable here:

- **Code-Review sits at 0** — 0 of the last several changesets carry an
  approved review: one maintainer, nobody else to approve a PR. A
  `Reviewed-by:` trailer would satisfy the scanner without a review having
  happened; that's not going to be added. The largest fixable-looking gap in
  the report, and not fixable without a second person.
- **Fuzzing sits at 0** — say-hi is bash; Scorecard's probe detects OSS-Fuzz,
  ClusterFuzzLite, Go native fuzzing, cargo-fuzz and OneFuzz, none of which
  targets shell. `.scorecard.yml` marks it `not-applicable`.
- **Contributors sits at 3** — the check wants ≥2 contributing organizations
  among recent contributors; there's one. `not-applicable` in
  `.scorecard.yml` too.
- **CII-Best-Practices** — the project is registered at
  [bestpractices.dev](https://www.bestpractices.dev/) (the OpenSSF Best
  Practices badge in README's badge block, a self-assessment questionnaire
  separate from Scorecard). The score reflects registration; three MUST
  criteria are release-shaped, and tagged releases now exist (`v0.1.0`
  onward) - re-check the live questionnaire rather than assuming _Passing_
  still waits on one.
- **Signed-Releases** was `-1` (excluded from the average) before any tag
  existed. `release.yml` ships `dist/SHA256SUMS.minisig` on every release,
  which the check's signature probe recognizes for 8/10; the build-provenance
  attestation `build` creates was invisible to it until `publish` also
  downloads that attestation and re-uploads it as `dist/say-hi.intoto.jsonl` -
  the literal filename the check's provenance probe looks for among release
  assets, for the full 10/10. Re-check the live score against a tag cut after
  that change; it doesn't move retroactively on tags that already shipped.
- **Pinned-Dependencies reads low for a reason outside this repo.** GitHub
  shipped same-repository `uses: $/...` references in July 2026
  ([changelog](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)):
  a local action or reusable workflow resolves at the exact commit running,
  with no `./` plus checkout and no separately-pinnable ref. `ci.yml` explains
  why `actionlint` is pinned to a fork that understands it (upstream doesn't
  yet); Scorecard's own dependency extraction is the same story - as of this
  writing it reads every `$/...` reference as an unresolvable third-party
  action with no `@sha`, which is where most of the check's "unpinned"
  count comes from. The actual third-party (non-`$/`) actions in the tree are
  100% SHA-pinned; re-run the numbers by hand
  (`grep -rhoE 'uses: +[^ ]+' .github/workflows .github/actions`) before
  assuming a `$/` reference is the gap. Not something to revert to `./` to
  chase a parser that hasn't caught up - that would trade a real improvement
  for a score built on a five-week-old blind spot.
- **Branch-Protection sits at 8, by choice.** The next tier up requires
  "include administrators", which would remove the maintainer's own ability to
  push past a failing check or merge without the full gate - kept, since
  that's the emergency valve for a one-person project. 10 additionally needs
  two required approving reviews, which needs a second person regardless.

## Why the harness is hand-rolled

The roadmap once asked whether to try [bats-core], [shellspec] and a
python/pytest driver against `configure`, `doctor`, `ssh` and one lint suite,
and either keep this harness or replace it. What follows is that decision.
It's a paper study, not a bake-off: no suite was ported, and nothing below is
a timing number. Speed was one of the things asked for, and a paper study
can't produce it honestly - the reasoning for why it probably wouldn't have
decided the answer anyway is at the end. Every other axis here is a
documented fact about a candidate or a demonstrable fact about this tree,
checked on 2026-09-05.

The three candidates aren't really competing with `test_runner.sh` - nothing
about `--group`, `--shard`, `--host-report`, the summary table or the
`::group::`/`::error` folding that eight workflows are wired to changes if
the suites underneath it move. What a candidate replaces is
`tests/test_lib.sh` and the 2,517 lines of `tests/lib/*.sh` behind it, and
then has to hand `test_runner.sh` back something it can still collect through
`$_HI_COUNTS_FILE`/`$_HI_FAILS_FILE`. Scored on that basis:

|                          | this harness                                               | [bats-core]                                                                       | [shellspec]                                                               | a pytest driver                                                       |
| ------------------------ | ---------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| macOS bash 3.2           | native (it's what's shipped)                               | claimed, "Bash 3.2 or above"                                                      | bash 3.2.57 named and CI-tested                                           | n/a - drives shells, isn't one                                        |
| Git Bash, install step   | none - it's the tree                                       | source-only; no MSYS2/Cygwin/WSL tier documented                                  | Git Bash, msys2, cygwin, busybox-w32, WSL all tested                      | `import pty` fails - Unix only, stdlib says so                        |
| runtime-generated cases  | plain bash `for`, unrestricted                             | `bats_test_function` (workaround; order is issue #860)                            | `Parameters:dynamic` allows a `for` loop, but no function/variable access | `parametrize`/`pytest_generate_tests`, fully dynamic                  |
| skip vs. `--require-run` | three tiers, wrapper turns every skip into a fail          | `skip`; no fail-mode documented                                                   | `Skip`/`Pending`; no fail-mode documented                                 | needs `pytest-error-for-skips`, a second package                      |
| parallel, ordered replay | own scheduler, submission-order replay                     | needs GNU parallel; **order not guaranteed**                                      | own `--jobs`; ordering undocumented                                       | needs `pytest-xdist`; reorders for scheduling                         |
| coverage topology        | suite = top-level process, kcov + bashcov merged           | kcov known to read 0% on some `.bats` files (kcov#462)                            | built-in `--kcov`, same bash/zsh/ksh DEBUG-trap limit as ours             | coverage.py measures Python only - subprocess bash is invisible to it |
| lint-gate reach          | already `*.sh`; shellcheck, shfmt, checkbashisms all apply | shellcheck parses `.bats` since 0.7; shfmt/checkbashisms don't know the extension | DSL keywords (`It`/`When`/`Then`); no shellcheck dialect found            | not shell at all - opts the driver out of the gate entirely           |
| new dependency           | none                                                       | GNU parallel                                                                      | none found required                                                       | pytest + xdist + a pty replacement on Windows                         |

Two blockers a pytest driver can't route around: `pty`/`tty` are Unix-only in
CPython's own docs (`_hi_capable pty`, `tests/lib/fixtures.sh:206`, exists
because Windows' `python3` fails `import pty`), and `coverage.py` never sees
the bash it would be shelling out to - a different topology from
`tests/coverage.sh`'s one-tracer-per-suite design, not a port of it.
**bats-core** gets the bash-3.2 floor right but needs GNU parallel for
`--jobs` (a new dependency, with its own "ordering not guaranteed" caveat)
and `bats_test_function` in place of the plain `for` loops the ~230
`_hi_check` call sites are written as today (its own open issue on execution
order). **shellspec** is the strongest on paper - its shell matrix is
better-documented than this harness's own `_hi_capable` probes - but no
shellcheck dialect exists for its DSL, so the `source=` guard and the
shellcheck fan-out stop applying the moment a suite becomes a `.spec`, and its
`--kcov` integration carries the same bash/zsh/ksh-only limit kcov already
has here.

**Keep it.** Every candidate adds a dependency this repo doesn't vendor for
anything else, gives up ordered parallel replay, drops out of the lint gate's
`*.sh` reach, or breaks the coverage topology - usually more than one at
once, and the sweep's wall clock is dominated by container boot and e2e
deadlines rather than per-case dispatch overhead, so this doesn't turn on the
missing speed numbers. Reopen it if Git Bash leaves the platform matrix, both
coverage tools go unmaintained at once, or one of these three documents an
ordered parallel mode and a skip-as-failure flag without a second package.

[bats-core]: https://bats-core.readthedocs.io/
[shellspec]: https://shellspec.info/
[wexpect]: https://wexpect.readthedocs.io/

## The lint gate

`--group lint` is four suites, eighteen checks between them, and CI runs all
of them. Each suite is its own process (`tests/test_runner.sh shellcheck`,
`dialects`, `tools`, `drift`) with its own file/failure/skip tally in the
summary table, so a failure in one never hides what the others found.

**`shellcheck`** (`tests/lint/shellcheck_test.sh`) — one check, and the whole
cost of the group. A fatal guard runs **before** it: every `source` of a
`$_HI_CONFIG_DIR/...` path must carry a `# shellcheck source=` directive, or
`.shellcheckrc`'s `source-path=SCRIPTDIR` under `shellcheck -x` resolves a
bare basename to the sourcing file itself and re-parses it until the kernel
OOM-kills it (~33GB resident).

- **1. shellcheck** over every `*.sh`, one invocation per CPU, replayed in
  order (`_HI_SC_WIDTH=1` for one at a time).

**`dialects`** (`tests/lint/dialects_test.sh`) — four shell-dialect syntax
checks. 3-5 skip yellow without docker, but with docker present a base image
that won't build is a **failure**, not a skip: it's digest-pinned, so "won't
build" means the distro moved off the version the check claims.

- **2. Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
  those shells parse for themselves, using whatever `zsh` and `fish` this
  machine has.
- **3. The fish 3.7 floor**: the same files inside a digest-pinned fish 3.7.0
  (`tests/dockerfiles/fish37.Dockerfile`, Ubuntu 24.04's, and CI's) - check 2
  alone misses this, since fish 4 accepts constructs 3.7 rejects. The
  construct that earned it: a _comment inside a `{ ... }` block_ in
  `common/paths.sh` - `{` opens a brace expansion to fish and `#` isn't a
  comment inside one, so the file died with "Mismatched braces", taking
  `$_HI_TARGETS` and every alias with it, on 3.7 only. The rule at the block:
  nothing but `export NAME=value` lines inside.
- **4. The fish 4 ceiling**: the same files inside a digest-pinned fish 4
  (`tests/dockerfiles/fish4.Dockerfile`, Ubuntu 26.04's), catching a
  construct 3.7 accepts that fish 4 rejects.
- **5. The zsh 5.8 floor** does more than parse: it sources `common/zsh.zsh`
  in a real interactive zsh inside a pinned zsh 5.8
  (`tests/dockerfiles/zsh58.Dockerfile`) and asks for a prompt, the aliases,
  a resolved host color and the prompt separator - `zsh -n` alone would wave
  through the risky constructs here that only misbehave on an old zsh. 5.8,
  not 5.9, because 5.9 is what bookworm, noble, alpine and macOS all ship -
  no machine anyone develops on is the floor, so the image is upstream's own
  `zshusers/zsh:5.8` rather than a distro apt install
  (which failed on hosted runners only).

**`tools`** (`tests/lint/tools_test.sh`) — four external-tool wrappers, each
skipping yellow when its tool isn't installed locally (CI has all four):

- **6. shfmt** over the same `*.sh` list, style from `.editorconfig`. Fix a
  red run with `shfmt -w` on the paths it names, not `shfmt -w .`, which also
  reformats `common/zsh.zsh` (zsh, ships as-is).
- **7. checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
  really do parse on minimal targets.
- **8. mandoc** over `docs/hi.1` (`mandoc -T lint -W warning`).
- **9. typos** over the whole tree, allowlisted by `.typos.toml`.

**`drift`** (`tests/lint/drift_test.sh`) — nine repo-consistency sweeps, each
a grep or small parser checking that something written down elsewhere still
agrees with the tree:

- **10. The bash-3.2 grep**: no `mapfile`, associative arrays, namerefs or
  `${x,,}` - each explained once in [GLOSSARY.md](GLOSSARY.md) by its
  `GLOSSARY: HI.NN` tag.
- **11. The `$HOME` default sweep**: nothing may fall back to `$HOME` when it
  derives the say-hi tree - over `*.zsh`, `*.fish` and `*.md` too, since the
  docs teach the rule as much as the code obeys it.
- **12. GLOSSARY tags**: every `GLOSSARY: HI.NN` in the tree names a code
  GLOSSARY.md defines, and every entry is referenced; matched by code, not
  title, anywhere on a line.
- **13. The settings roster**: every name the tree treats as a setting
  (`_HI_TOGGLES`, the `_HI_*_PROMPTS` tables) has a row in
  [SETTINGS.md](SETTINGS.md)'s _Every setting_ table, and every row there
  names a variable the tree still reads.
- **14. Liquid syntax**: no page the Pages build renders may carry a raw
  Liquid delimiter outside a guarded span - Liquid tokenizes before Markdown,
  so a fence gives no shelter.
- **15. The tldr page**: every `hi --flag` example in `docs/tldr.md` names a
  `common/flags` row, and there are at most eight examples - the upstream
  cap.
- **16. tests/dockerfiles/**: every image definition has a caller and vice
  versa.
- **17. Image tags**: every plain image tag named in shell or YAML is one of
  the digest-pinned `FROM` tags in `tests/dockerfiles/`.
- **18. Image digests**: two Dockerfiles pinning the same `image:tag` must
  agree on its digest - check 17 strips the digest before comparing, so it
  can't see one tag pinned to two; this one reads the digests back in.

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

`tests/` is stripped from the payload, so `hi --doctor` on a target says so
rather than running. Every flag that needs `scripts/`, `tests/` or a `.git`
answers the same way there, and `--update` answers that way in a
package-manager install too, which ships `scripts/` but neither of the others.
**Which flag needs what is `docs/hi.1`'s OPTIONS section**, drift-checked
against `common/targets.sh`'s completion roster by `tests/hi/parse_test.sh`.
`hi --preview packages` and `hi --preview header` do not refuse: their full
forms live in `scripts/`, but the check and the header they preview live in
the shipped `common/header.sh`, so on a target they run that half instead.
