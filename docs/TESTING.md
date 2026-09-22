# Testing

Every script resolves against `$_HI_HOME/say-hi`, and the runner defaults
`_HI_HOME` to this checkout's parent, so a fresh clone needs no setup. With a
second say-hi tree on the machine (an install beside a dev checkout), set it
on every invocation: a shell that sourced an install exports the whole `_HI_*`
set at paths that exist, and a suite run against the wrong tree reports fewer
cases rather than failing.

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
  - [Timing and shared state](#timing-and-shared-state)
  - [The images are files; the build contexts are not](#the-images-are-files-the-build-contexts-are-not)
    - [What is pinned, and what deliberately is not](#what-is-pinned-and-what-deliberately-is-not)
- [The lint gate](#the-lint-gate)
- [Test levers](#test-levers)
- [Relaying](#relaying)
- [Local-only](#local-only)
- [Why the harness is hand-rolled](#why-the-harness-is-hand-rolled)

## Running the tests

`tests/test_runner.sh` times each suite and prints a colored pass/fail
summary:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --group fast       # what CI runs on every platform
tests/test_runner.sh --group fast,ci    # ...plus the ci group, as ubuntu runs it
tests/test_runner.sh --group fast --shard 1/2 # half of it, as a CI shard runs
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

- `ci` is the checks a second platform could only repeat - the workflows
  and manifests read as text, and the release tooling only Ubuntu runs
  (`packaging_ci`, a file of its own beside `packaging`'s portable half, and
  `test_runner_ci`, `runner_test.sh`'s ci part).
  Ubuntu's fast job runs it; `release.yml` runs it against the bumped
  manifests.
- A passing suite's transcript collapses to one status line; failures replay
  in full and are recapped under the summary table. `--verbose`
  (`_HI_VERBOSE=1`) streams every transcript live, for a case that fails only
  under the runner.
- A failed case is run once more under `set -x` - once, never more. A second
  failure is FAILED, with the last lines of that trace under it: the
  comparison that failed, with its values, so a case with no message of its
  own still names its cause. A pass the second time is **FLAKY**, and a sign
  the case needs making sturdier. On Windows (WSL included), the BSDs, and
  arm64 (macOS included) it is not counted as a failure - it is listed under
  _Flaky cases_ at the end of the run, a GitHub warning on CI. On native Linux
  x64, the least loaded platform, a flake is a failure like any other
  (`_HI_FLAKY_OK=1`/`0` overrides either way). Not for a failure
  that took over 20s, nor under the coverage sweeps (`_HI_TRACE_RERUN=0`).
- Suites running side by side replay only once the last one finishes, so a
  progress line fills the wait (finished suites, cases, failures, elapsed,
  what is still running): redrawn in place at a terminal, a line per finished
  suite plus a 30s heartbeat on CI. `_HI_PROGRESS=0`/`1` overrides.
- A suite whose backend is missing reports **SKIPPED**, never green; so does a
  single case (an image that would not build, a tool not installed).
  `--require-run` (CI's lint, e2e, and backends jobs pass it) turns both into
  failures: the suite goes red, its transcript replays, and each stood-down
  case is named in the recap.
- `--host-report` (`_HI_HOST_REPORT=1`) prints one block before the first
  suite: bash, OS, CPU and memory, userland (GNU/BSD/busybox), the locale's
  glyph verdict, which tree `$_HI_HOME` resolves to, which backends answer,
  and tool versions. Every CI job but the lint runs and `release.yml`'s `ci`
  run passes it. The tree half prints on
  **every** run when the tree under test is not the one the runner was
  invoked from — the quietest way to get a wrong result here.
- Every test script also runs directly, e.g. `tests/lint/shellcheck_test.sh`.
- Under a wrapper that leaves a controlling terminal but a background process
  group (`timeout` from a prompt, a `wsl.exe` session), run
  `setsid -w timeout … tests/test_runner.sh …` — `setsid` outside, so
  `timeout` still kills the runner's group. Without it the interactive
  sessions the `load` and `install_location` suites start stop on SIGTTIN
  until the deadline. GitHub's ubuntu runner has no controlling terminal.
- Under WSL 2, drop the `/mnt/` entries from `$PATH` first: interop's ~50
  `/mnt/c/...` directories are served over 9p, and the package check's
  uncached `command -v` misses make one `full_check` take 30–37s instead of
  30ms - half a minute a check, when the pty cases' deadline was 30s. `windows-e2e.yml`'s `wsl-suites`
  job does this and has the measurements.

Six groups (`--group <name>`, or a comma list; `--list` prints the
membership) - `ci` above, and:

- **`fast`** — dependency-free unit suites, the first thing every CI platform
  job runs; `test_lib`, `test_lib_report`, `test_lib_par`, and `test_runner`
  are the harness testing itself. Suites run **side by side** (one per CPU),
  each with its own workdir and tally files, transcripts replayed in table
  order, so the run reads like a serial one and takes about as long as its
  slowest suite. `_HI_RUNNER_WIDTH=1` runs one at a time, as `--verbose`
  does. `--shard <i>/<n>` keeps every n-th suite of the selection from the
  i-th on, to split a group across runners: `windows-client.yml` runs `fast`
  as four slices (1/4 to 4/4) on each of x64 and arm64, eight jobs rolled into
  one `fast suites (Git Bash)` check (backgrounded suites barely overlap
  under MSYS, so only more machines shorten it), and `ci.yml` shards `e2e`
  and `backends`.
- **`lint`** — [the lint gate](#the-lint-gate): its own ubuntu CI job,
  beside `fast`'s; the macOS, Windows, and BSD jobs run `fast` alone, since
  linting text does not depend on the userland. Run
  `npm ci --prefix .github` first, or its two Markdown checks skip.
- **`bench`** — hot-path timings against ceilings, plus the payload's two size
  budgets.
- **`e2e`** — `ssh`, `ssh_disconnect`, `ssh_relay`, `ssh_wire`,
  `install_methods`, `repo`, `docker`, `framework`: throwaway containers
  driving `hi.sh`'s real connection paths (`_say_hi` and
  `_say_hi_container`). `ssh_wire` counts one session's bytes through a
  `ProxyCommand` and checks them against the figure hi prints on its connect
  line. `repo` is about packaging rather than sessions: it builds the package
  repository with throwaway keys and installs from it as apt, dnf, and apk
  clients, signatures verified.
- **`backends`** — `podman`, `nomad`, `kube`: split from `e2e` because they
  need extra runner setup.

`bench`, `e2e`, and `backends` always run one suite at a time: the bench
measures, and the other two contend on one container daemon.

A case stands down through two guards: `_hi_check_requires <bin>` when a
_command_ is missing, `_hi_check_capable <capability>` when a _facility_ is —
something `command -v` cannot answer (`_hi_par_check_capable` is the parallel
twin for a fast case; an e2e case asks `_hi_capable` directly and skips
inline). The roster is `_hi_capable` in `tests/lib/fixtures.sh`:

| Capability         | How it answers                         | Why it can be no                                                    |
| ------------------ | -------------------------------------- | ------------------------------------------------------------------- |
| `symlink`          | probe: makes one, tests `[ -L ]`       | a filesystem that refuses _or_ silently copies reads as no          |
| `pty`              | probe: python3 can `import pty`        | no pty layer to drive an interactive case with                      |
| `mkdir_mode`       | probe: a `mkdir -m` whose mode lands   | a Windows-owned temp tree makes the directory and refuses the chmod |
| `gpg_agent`        | probe: an agent in a throwaway homedir | Git for Windows ships gpg with no agent it can start                |
| `lockout`          | probe: writes into a `chmod 555` dir   | root bypasses the bits, so the write succeeds                       |
| `fork_concurrency` | `uname` (MSYS/Cygwin)                  | background subshells have to genuinely overlap                      |
| `mode_bits`        | `uname` (MSYS/Cygwin)                  | a reported permission string has to reflect `chmod`'s own bits      |
| `netem`            | `/proc/modules` or `/sys/module`       | `modprobe sch_netem` has not run on the host; a container can't     |

The `starved` case in the ssh e2e suite is the one that asks for `netem`: it
shapes a container's own link with `tc qdisc … netem`, which needs the
module loaded on the host kernel, not just present in it. `ci.yml`'s e2e job
loads it in its setup step, so the capability gate mainly matters on a local
or dev machine that hasn't `modprobe`'d it.

### Where a suite lives

`tests/<the directory it tests>/`. `tests/common/`, `tests/config/`,
`tests/scripts/`, and `tests/packaging/` mirror the tree; `tests/hi/` and
`tests/load/` cover the two root scripts; `tests/lint/` is the lint gate,
`tests/bench/` the timings, `tests/targets/` the container/ssh e2e suites, and
`tests/harness/` the suites that test the harness. The harness itself is
`tests/test_lib.sh`, a façade over `tests/lib/`; a suite sources the façade and
nothing else ([HI.34](GLOSSARY.md#hi34-test-suite-preamble)).

### The container suites run their cases in parallel

`ssh`, `ssh_relay`, `install_methods`, `docker`, `podman`, `framework`, and
`kube` spend nearly all their wall clock waiting on containers, so their
cases run in batches: `_hi_par_case` (`tests/lib/parallel.sh`) submits a case
to a background subshell, `_hi_par_wait` collects the batch. Each case writes
its verdict to a file the parent tallies, registers what it started on a
teardown ledger the exit trap sweeps, and buffers its output to replay **in
submission order**. Cases that read another case's files stay serial.

A batch is capped at four, or the CPU count if smaller — unbounded fan-out
thrashes the docker daemon on a laptop. A suite whose cases are plain local
processes (`configure`'s pty runs, `install_location`'s shells, the harness
suites' nested runners) sets `_HI_PAR_LOCAL=1` and gets the whole CPU count.
`_HI_PAR_WIDTH` overrides both; `nomad` pins itself to 1, since its single-node
dev agent gains nothing from two cases at once.

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, same code path - for bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

The pty-driven cases (`configure`, `install`, `rc_lines`) kill their child
after 60s and count it a failure; `_HI_CASE_TIMEOUT` raises that deadline on a
host slow for reasons the suites cannot fix, as `_HI_SSH_CASE_TIMEOUT` (90s)
does for the ssh cases. The login shells `_hi_login_env` starts
(`install_location`'s dialect pass) are bounded the same way at 180s by
`_HI_LOGIN_TIMEOUT`: unbounded, one that wedges shows only as a case count that
stops moving, for as long as the job allows.

### The install-method suite

`install_methods` is `ssh`'s sibling: `ssh` runs one install against every
login shell; `install_methods` runs one login shell against every way say-hi
gets onto a machine — the `.deb`, `.rpm`, `.apk`, a Homebrew-shaped keg, a
system-wide `install.sh --prefix`, and a packaged tree with its
`/etc/profile.d` announcement removed. They share the case runner in
`tests/lib/ssh.sh`.

hi ships its payload to every ssh target and never reads a say-hi already
there, so every case asserts the same two things: the session runs out of its
own tree (`$_HI_ROOT` is _not_ the installed path), and the installed tree is
still whole once the session is gone.

The three package cases build what they install with `packaging/mkpkg.sh`, so
they need `nfpm`; without it they stand down yellow **per case**, which
`--require-run` catches. `ci.yml`'s e2e job installs the pinned nfpm so they
run.

### Coverage and profiling

Two coverage tools, kcov (`tests/coverage.sh`) and
[bashcov](https://github.com/infertux/bashcov) (`tests/coverage_v2.sh`), each
run over the full suite sweep — every suite the box's backends can host —
by hand or by `coverage.yml`: after every green CI run on a push to `main`, and
on every same-repo, non-draft PR, where the `comment` job posts both figures
beside main's in one comment edited in place, with the PR's passed-case count
from its CI run beside main's (the push that merges the PR reuses them). The two aggregates have tracked each other within a few points
for many commits: **the average of the two badges** is the coverage figure,
and the per-file reports are for finding untested arms. Only a divergence of
tens of points means one tool has lost the plot. Never a gate: the pull
request template's 90% is a target, and the PR comment flags an average below
it without failing anything. Both sweeps pin `_HI_PAR_WIDTH=1`, since a batch
writing into a suite's one trace stream side by side loses lines, and both put
a bash-as-`sh` first on their own `PATH`: neither tracer follows a dash child,
so a `#!/bin/sh` file a suite executes as `sh …` (`common/targets.sh`) would
read 0% where `/bin/sh` is dash.

In CI each tool is sharded 4 ways (`--shard i/4`, which
`_hi_cov_select_suites` passes straight to `test_runner.sh`) and merged by a
gather job: `kcov --merge` over the shards' `parts/` directories, and a plain
JSON hash union of bashcov's `--command-name`-keyed `.resultset.json` files,
safe because shards partition the suite table.

- **kcov**'s known failure mode is losing its DEBUG trap once the harness is
  sourced, which reads whole suites as load-time-only; the script's header
  keeps the probe to re-run if the badges diverge. **`kcov --merge` re-reads
  the sources** at the absolute paths each shard recorded, so a merge with no
  working tree yields `"files": []` and a well-formed `0.00%` badge, not an
  error. `coverage.yml`'s `gather-kcov` checks the tree out before calling
  `tests/coverage.sh --merge` (a local sweep's own merge, ranking, and
  all-zero refusal), and the `test_runner_ci` suite (`runner_test.sh`'s ci
  part) asserts every job
  calling it does. `gather-bashcov` needs no checkout.
- **bashcov** reads bash's `xtrace`, and skews the other way: a **heredoc
  body** counts as covered whether or not it ran, and children under `env -i`
  or inside containers drop out of the trace — so a single file reads a few
  points off either way while the pair brackets the truth. More readings are
  artifacts, not gaps, and `tests/coverage_v2.sh`'s header is their list: a
  scratch-tree copy, an `eval` inside a `$( )`, a zsh-only arm, the `sh …`
  case above, lines a passing case asserts but that still read 0, and the lines `xtrace`
  never prints (an empty case arm, a redirect line). Rule those out before
  writing a test against a number. It needs
  `gem install --user-install bashcov` (found off the gem bin directory if
  not on `$PATH`), and writes a `.simplecov` into the checkout for the run,
  refusing to start rather than overwrite one you have.

`pages.yml` publishes both aggregates as shields endpoints
(`badges/coverage.json`, `badges/coverage-v2.json`), each labelled by its tool
and computed over the shipped product only (`tests/` and `docs/` excluded).
A completed Coverage run is `pages.yml`'s only automatic trigger, so a badge
is never older than its sweep.

`common/zsh.zsh` and `common/config.fish` sit outside both tools: kcov's DEBUG
trap and bashcov's `xtrace` are bash mechanisms, so no line-coverage figure for
them is honest. What stands in: `tests/lint/dialects_test.sh`'s floor checks
([checks 2–5](#the-lint-gate)), and `tests/common/exports_test.sh` and
`tests/hi/prompt_test.sh`, which drift-check `common/config.fish` against
`common/core.sh` line by line.

`tests/profile.sh` is for a tripped `--group bench` ceiling: `_hi_bench` says
_whether_ a path got slower, this says _which command in it_ did. It profiles
the four bash paths the bench guards through
[timep](https://github.com/jkool702/timep), **in a container**
(`tests/dockerfiles/timep.Dockerfile`): timep `enable -f`s base64-encoded
loadable-builtin `.so` files into the running shell, which is worth
sandboxing, and the box settles three requirements timep does not check —
glibc ≥ 2.38, a bash with `enable -f`, and an **exec-capable** `/dev/shm`.
Missing any, timep exits 0 and writes arithmetic errors instead of times, so
`profile.sh` grades the output, not the status. The checkout is mounted
read-only; `$_HI_TIMEP` mounts a local copy of timep you have read. Read the
ranking, not the milliseconds. `ci.yml`'s `profile` job runs it beside `bench`
and uploads the `profiles` artifact (14 days); it is advisory
(`continue-on-error`), the bench ceilings stay the gate.

### Timing and shared state

The Windows and BSD runners are where a timing assumption shows up, so the
harness makes these choices on purpose:

- **Isolation per suite.** `test_lib.sh` gives each suite a fresh
  `mktemp -d` root holding its `XDG_CONFIG_HOME` (absent until a case makes
  it) and `XDG_RUNTIME_DIR`, so parallel suites never share hi's payload,
  overlay, or ssh-tags caches, nor a developer's real sockets. Cleanup removes
  that root by its recorded path - never whatever an XDG variable points at
  by then.
- **Pinned caps.** `_HI_PROBE_TIMEOUT` is 10 in the suites (a user's 2s is
  for real CLIs; the suites probe shell shims); the pty cases' cap is 60s,
  `_hi_login_env`'s 180s. A cap bounds a wedge, never a pace.
- **Meetings over sleeps.** A case proving concurrency has its shims wait
  for each other (bounded) rather than sleep a fixed time and hope.
- **The pty rig's verdict is a file.** Each child writes its verdict line to
  `<label>/verdict` as well as the pty; a BSD pty can drop a fast child's
  last output.

Written down as not races:

- **`kill -0` as "still running".** `_hi_wait_pid` and `_hi_par_slot` poll
  it, and a pid bash has reaped can be reused. The job table would say
  better, but only through `$(jobs)`, and whether a command substitution sees
  the parent's jobs varies: where it did not (Git Bash, OpenBSD), the
  timeout stopped counting and a hung case hung its shard. So the poll stays;
  a reused pid needs the old one to exit and a stranger to take its number
  inside one poll's window.
- **Wall-clock deadlines.** `$SECONDS` is the wall clock, chosen over
  counted iterations (process.sh says why); a VM whose clock NTP steps
  mid-run can shorten one, a trade taken knowingly.
- **One `HOME` for the parallel fresh-shell cases** in
  `install_location_test.sh`: zsh's compdump, fish's variables, and shell
  history each write through their own lock or append, and no case reads
  another's.
- **Build-once fixture helpers** (`_hi_fake_path`, `_hi_real_path`,
  `_hi_git_fixture`, `_hi_stub_tools`, `_hi_can_mkdir_mode`): safe while
  their callers are serial, as every caller is; build one before a
  `_hi_par_begin`, never inside a parallel case.

Instrumented, not yet explained: on Windows arm64, `hi_payload`'s include
scan cases have left an empty overlay stream with no error of their own
(gzip then reports "unexpected end of file"). The suite wraps
`_hi_overlay_tar` to print its exit status and stderr, so the next one names
its cause.

### The images are files; the build contexts are not

Every image a suite builds is a real Dockerfile under
[`tests/dockerfiles/`](https://github.com/ivylikethevine/say-hi/tree/main/tests/dockerfiles):
`sshd-debian`, `sshd-alpine`, `sshd-fedora`, and `sshd-bash32` for the ssh
targets, `alpine-shell` for the bare shell ones, `installed-*` for the
pre-installed targets (`installed-pkg` takes the `.deb`/`.rpm`/`.apk` as a
build arg), `framework` for the thirteen shell frameworks and tools (the
framework a build arg naming a script under `frameworks/`), `apt-client` for
the `repo` suite's apt subscriber (openssh-client preinstalled, no Ubuntu
archive in its sources, so the cases fetch from the repository under test
alone), and `fish37`, `fish4`, `zsh58`, and `timep` for the lint gate and the
profiler. Only the _build context_ is generated per case: the `entrypoint.sh`,
and for the pre-installed cases the repo itself. Suites reach a file through
`_hi_dockerfile <stem>`; variants differing only by a package list or base
image are one file plus a `--build-arg` (`PKGS`, `BASE`).
`docs/tapes/fixtures.sh` builds its `demo-*` images from the same folder,
spelling the path out, since a tape render does not source `test_lib.sh`. The
lint gate checks both directions: no Dockerfile without a caller, no caller
naming a missing Dockerfile.

### What is pinned, and what deliberately is not

**Upstream base images are digest-pinned, non-negotiably.** Every `FROM` in
`tests/dockerfiles/` that names an upstream image (11 of 19: alpine, ubuntu,
debian, fedora, bash, zshusers/zsh) carries a `@sha256:` — what makes a failed
e2e run reproducible and a base-image move a deliberate, reviewable act.
Dependabot bumps the digests weekly, which is how a base image reaching EOL
gets noticed. The other 8 are `FROM ${BASE}` over an image a suite builds
locally (`hi-test-sshd` and the like; see `--build-arg BASE=` in
`tests/targets/*_test.sh`), with no upstream digest to pin; Scorecard flags
them as unpinned `containerImage` dependencies, and
[`.scorecard.yml`](https://github.com/ivylikethevine/say-hi/blob/main/.scorecard.yml)
annotates the check `test-data` rather than pretending it's clean. Nothing in
`tests/dockerfiles/` reaches a release; the release path's workflows and
actions are SHA-pinned separately.

**The same tags named in shell and YAML are guarded, not watched.** `alpine:`
and `debian:` also appear as plain tags in `tests/lib/backend.sh`,
`docs/tapes/fixtures.sh`, and `ci.yml`'s packaging smoke, where Dependabot
cannot see them. `lint_image_tags` fails when a tag named anywhere in the tree
disagrees with the digest-pinned ones; `lint_image_digests` when two
Dockerfiles pin one tag to different digests.

**Every framework fetch is pinned.** Five to a release and a hash, each
downloaded to a file and `sha256sum -c`d before use: `frameworks/plgo.sh`'s
release binary (v1.26), `frameworks/tide.sh`'s fisher (4.4.5, installing tide
v6.2.0), and the atuin, mise, and starship installers. `atuin.sh` (v18.20.1)
and `mise.sh` (v2026.8.14) name the release tag in the download URL, so hash
and version move together (`mise.run` is regenerated per release whatever
`MISE_VERSION` says, so pinning that alone drifts); `starship.sh` (v1.26.0,
via `--version`) fetches the generic `starship.rs/install.sh`, so its hash
pins _that day's copy of the installer_ — a mismatch needs a fresh hash, not a
version bump. The frameworks without releases are pinned by commit: the
oh-my-zsh and oh-my-bash installers by commit and hash, each fed its framework
through a local mirror fetched at a commit (`omz.sh`, `p10k.sh`, `omb.sh`), the
bash-it and powerlevel10k checkouts by commit, and atuin's bash-preexec by
commit and hash. Every pin is named in its script and bumped by hand. The image
builds under `pipefail`, so a 404, a checksum mismatch, or an installer
changing shape fails the build rather than shipping an image with the
framework missing.

## The lint gate

`--group lint` is four suites, thirty checks between them. Each suite is
its own process (`shellcheck`, `dialects`, `tools`, `drift`) with its own
tally in the summary table, so a failure in one never hides what the others
found.

CI's `lint suites` job passes `--require-run`, so a check that skips yellow
locally for want of a tool fails there. Its binaries are pinned in
`.github/actions/setup-tool/tools.txt`: eight columns,
`name|pin|kind|url|verify|check|tag-prefix|sha256` (the file's header
documents each), the last a sha256 of the download, one for every platform or
one per platform (`linux-x86_64=<hex>,darwin-aarch64=<hex>`), so a pin moves
only with its checksum. `tool-versions.yml` drift-checks every row weekly, and
`.github/scripts/check_tool_versions.local.sh` adds this repo's inline pins
and image checks. markdownlint-cli2 and prettier are pinned in
`.github/package-lock.json` instead, installed by `npm ci --prefix .github`
and run from `.github/node_modules/.bin`. After the group, the same job runs
lychee (settings in `lychee.toml`) offline over the tracked Markdown, so a
broken relative link or `#fragment` fails the PR that makes it;
`link-check.yml`'s weekly sweep checks the external URLs.

**`shellcheck`** (`tests/lint/shellcheck_test.sh`) — one check, and most of
the group's cost. A fatal guard runs **before** it: every `source` of a
`$_HI_CONFIG_DIR/...` path must carry a `# shellcheck source=` directive, or
`.shellcheckrc`'s `source-path=SCRIPTDIR` under `shellcheck -x` resolves a
bare basename to the sourcing file itself and re-parses it until the kernel
OOM-kills it (~33GB resident).

- **1. shellcheck** over every `*.sh`, one invocation per CPU, replayed in
  order (`_HI_SC_WIDTH=1` for one at a time).

**`dialects`** (`tests/lint/dialects_test.sh`) — four shell-dialect checks.
3–5 skip yellow without docker, but with docker present a base image that
won't build is a **failure**: it's digest-pinned, so "won't build" means the
image no longer carries the version the check claims.

- **2. Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
  those shells parse for themselves, with whatever `zsh` and `fish` this
  machine has.
- **3. The fish 3.7 floor**: the same files in a pinned fish 3.7.0
  (`tests/dockerfiles/fish37.Dockerfile`, Ubuntu 24.04's and so CI's), since
  fish 4 accepts constructs 3.7 rejects. The one it caught: a _comment inside
  a `{ ... }` block_ in `common/paths.sh` — `{` opens a brace expansion to
  fish, `#` isn't a comment inside one, and the file dies with "Mismatched
  braces", taking `$_HI_TARGETS` and every alias with it. Hence the rule at
  that block: nothing but `export NAME=value` lines inside.
- **4. The fish 4 ceiling**: the same files in a pinned fish 4
  (`tests/dockerfiles/fish4.Dockerfile`, Ubuntu 26.04's), for a construct 3.7
  accepts that fish 4 rejects.
- **5. The zsh 5.8 floor** sources `common/zsh.zsh` in a real interactive zsh
  5.8 (`tests/dockerfiles/zsh58.Dockerfile`) and asks for a prompt, the
  aliases, a resolved host color, and the prompt separator — zsh's risky
  constructs parse everywhere and only misbehave on an old zsh. 5.8 because
  bookworm, noble, alpine, and macOS all ship 5.9, so no development machine
  is the floor; the image is upstream's `zshusers/zsh:5.8`, since a distro apt
  install failed on hosted runners only.

**`tools`** (`tests/lint/tools_test.sh`) — nine external-tool wrappers, each
skipping yellow when its tool isn't installed (CI has all nine):

- **6. shfmt** over the same `*.sh` list, style from `.editorconfig`. Fix a
  red run with `shfmt -w` on the paths it names, not `shfmt -w .`, which also
  reformats `common/zsh.zsh` (zsh, ships as-is).
- **7. checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
  really do parse on minimal targets.
- **8. mandoc** over `docs/hi.1` (`mandoc -T lint -W warning`).
- **9–11. The shipped editor rcs**, each loaded by its editor the way the alias
  does: `config/vimrc` under `vim -u … -es`, `config/init.lua` under
  `nvim --headless -u`, `config/init.el` under `emacs --batch -q -l`. The
  payload suites treat those files as bytes, so a syntax error would otherwise
  ride the wire to every target.
- **12. typos** over the whole tree, allowlisted by `.typos.toml`.
- **13. markdownlint** (markdownlint-cli2, rules in `.markdownlint.yaml`)
  over the Markdown git knows about, tracked or new.
- **14. prettier --check** over the same list, style in `.prettierrc.yaml`,
  skipping `.prettierignore`'s files. Fix with `prettier --write` on the paths
  it names.

**`drift`** (`tests/lint/drift_test.sh`) — sixteen repo-consistency sweeps,
each checking that something written down elsewhere still agrees with the tree:

- **15. The bash-3.2 grep**: no `mapfile`, associative arrays, namerefs,
  `${x,,}`, `wait -n`, or `${!a[@]+…}` — each explained in [GLOSSARY.md](GLOSSARY.md) by its
  `GLOSSARY: HI.NN` tag.
- **16. One-userland spellings**: [SYNTAX.md](SYNTAX.md)'s enforced rows -
  `echo -e`, `sed -r` and `-i`, `grep -P`, `readlink -f`, `xargs -r`,
  `head -n -N`, `date %-X`, gawk-only functions, `mktemp -t` with no X's, and
  basic-sed alternation.
- **17. Paired spellings**: `stat -c` only beside its `stat -f` twin, and
  strict mode switched off again in every file an interactive shell sources
  ([HI.15](GLOSSARY.md#hi15-strict-mode-bracketing)).
- **18. The `$HOME` default sweep**: nothing may fall back to `$HOME` when it
  derives the say-hi tree — over `*.zsh`, `*.fish`, and `*.md` too, since the
  docs teach the rule as much as the code obeys it.
- **19. Ignored payload**: no file the payload or a package ships is one
  `.gitignore` swallows, asked of git itself — the suites read the working
  tree, so nothing else would notice it never reached a commit.
- **20. GLOSSARY tags**: every `GLOSSARY: HI.NN` in the tree names a code
  GLOSSARY.md defines, and every entry is referenced; matched by code, not
  title.
- **21. The settings roster**: every name the tree treats as a setting
  (`_HI_TOGGLES`, the `_HI_*_PROMPTS` tables) has a row in
  [SETTINGS.md](SETTINGS.md)'s _Every setting_ table, and every row names a
  variable the tree still reads.
- **22. The docker-compatible family**: `common/core.sh`'s
  `$_HI_CONTAINER_CLIS` and `common/targets.sh`'s copy name the same CLIs
  ([HI.51](GLOSSARY.md#hi51-docker-compatible-cli-family)), since neither file
  can read the other.
- **23. The runtime directory**: `common/core.sh`'s `_hi_runtime_dir` and
  `common/targets.sh`'s cache directory build the same path, with the same
  ownership guards, in their two dialects.
- **24. Liquid syntax**: no page the Pages build renders may carry a raw
  Liquid delimiter outside a guarded span — Liquid tokenizes before Markdown,
  so a fence gives no shelter.
- **25. Site links**: a relative link on a page the site builds lands on a
  page the site builds too, not a dot-path or anything `_config.yml` excludes
  (which renders on GitHub and 404s on Pages); link those as absolute
  github.com URLs.
- **26. Contents blocks**: in every rendered page, each `##` and `###` heading
  has an entry in that doc's `## Contents` list and each entry names a real
  heading, an `###`'s entry indented under an `##`'s. just-the-docs runs with
  no front matter here, so these lists are the site's only in-page navigation.
- **27. The tldr page**: every `hi --flag` example in `docs/tldr.md` names a
  `common/flags` row, and there are at most eight examples (the upstream cap).
- **28. tests/dockerfiles/**: every image definition has a caller and vice
  versa.
- **29. Image tags**: every plain image tag named in shell or YAML is one of
  the digest-pinned `FROM` tags in `tests/dockerfiles/`.
- **30. Image digests**: two Dockerfiles pinning the same `image:tag` agree on
  its digest — check 29 strips digests before comparing, so it can't see one
  tag pinned two ways.

## Test levers

Five environment variables the tree reads that are not settings: they exist so
a suite, the bench, or a demo can pin what a real run derives.
`_HI_TARGETS_TTL` (seconds `targets.sh` reuses its list; `0` sweeps every
call), `_HI_PROBE_TIMEOUT` (seconds one backend CLI gets), `_HI_PAYLOAD_CACHE`
(`0` builds the payload and overlay archives fresh), `_HI_CTL_PERSIST`
(seconds a shared ssh control socket lingers; `0` gives a connect a private
one, closed after) and `_HI_HEADER_VERSION` (the header's version cell,
otherwise the release stamp or `git describe` — what
`docs/tapes/generate.sh --version` sets). Their defaults are the shipped
behaviour; `hi --configure` writes none of them. `_HI_LOAD_NO_INIT=1` is
adjacent but not a lever: it makes `load.sh` define its functions without
running the profile chain, for `scripts/install.sh` to source.

## Relaying

`hi` chains: from a session on B you can `hi C`, and the second hop is a full
hi session — from a _disposable_ session too, because `hi.sh` is a member of
`$_HI_PAYLOAD` and arrives with its exec bit (hence the `cat` write-back,
[HI.09](GLOSSARY.md#hi09-cat-over-mv)). `ssh_relay` is the proof: A → B → C,
config intact on the final hop, cleanup traps firing on **both** B and C, on a
clean exit and on the link being killed mid-relay. The one tier that cannot
relay is the container transport's bash-less fallback, which ships
`aliases.sh` alone and never loads `paths.sh` — there `hi` is not defined.

## Local-only

The payload carries no `scripts/`, `tests/`, or `.git`, so on a target
every local command (`hi --doctor`, `--preview`, `--install`, …) says it needs
the full checkout rather than running, and `--update` says so in a package
install too, which ships `scripts/` but no `.git`. Which flag needs what is
`common/flags`' `<needs>` column; `docs/hi.1` is the long form, drift-checked
against the flags by `tests/hi/parse_test.sh`.

## Why the harness is hand-rolled

[bats-core], [shellspec], and a python/pytest driver were weighed as
replacements for `tests/test_lib.sh` and `tests/lib/*.sh` (a paper study: no
suite was ported, no timings). `test_runner.sh` stays either way, so a
candidate has to hand it something it can still collect through
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

**Keep it.** Every candidate loses at least one row, usually more, and the
sweep's wall clock is container boot and e2e deadlines rather than per-case
dispatch, so speed would not have decided it. Reopen it if Git Bash leaves the
platform matrix, both coverage tools go unmaintained at once, or one of the
three documents an ordered parallel mode and a skip-as-failure flag without a
second package.

[bats-core]: https://bats-core.readthedocs.io/
[shellspec]: https://shellspec.info/
