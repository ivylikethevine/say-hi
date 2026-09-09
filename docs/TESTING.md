# Testing

Every script resolves against `$_HI_HOME/say-hi`. The runner defaults
`_HI_HOME` to this checkout's parent, so a fresh clone works with no setup.
With a second say-hi tree on the machine (an installed one beside a dev
checkout), set it explicitly on every invocation: a shell that has sourced an
install exports the whole `_HI_*` set at paths that all exist, and a suite run
against the wrong tree reports fewer cases rather than failing.

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
  `wsl.exe` session — run it as `setsid -w timeout … tests/test_runner.sh …`,
  `setsid` outside `timeout` so `timeout` still kills the runner's own process
  group. Without it the interactive sessions the `load` and `install_location`
  suites start stop on SIGTTIN until the wrapper's deadline. GitHub's ubuntu
  runner has no controlling terminal and needs none of this.
- Under WSL 2, drop the `/mnt/` entries from `$PATH` before running (the
  `wsl-suites` job in `windows-e2e.yml` does). Interop appends some fifty
  `/mnt/c/...` directories served over 9p, and the package check is 272
  `command -v` lookups per render with no miss caching: one `full_check` takes
  30–37s there against 30ms on ext4, past the `configure` suite's 30s pty
  cases and, over the `header` and `preview` suites too, past the job's 900s
  kill.

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
  the Windows client job runs `fast` as four shards, because backgrounded
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
_facility_ is — something `command -v` cannot answer. The roster is
`_hi_capable` (`tests/lib/fixtures.sh`); `_hi_par_check_capable` is the
parallel twin. Every entry exists for the MSYS/Cygwin tier, and the four
probes ask the system rather than sniffing `uname`:

| Capability         | How it answers                         | Why it can be no                                                    |
| ------------------ | -------------------------------------- | ------------------------------------------------------------------- |
| `symlink`          | probe: makes one, tests `[ -L ]`       | a filesystem that refuses _or_ silently copies reads as no          |
| `pty`              | probe: python3 can `import pty`        | no pty layer to drive an interactive case with                      |
| `mkdir_mode`       | probe: a `mkdir -m` whose mode lands   | a Windows-owned temp tree makes the directory and refuses the chmod |
| `gpg_agent`        | probe: an agent in a throwaway homedir | Git for Windows ships gpg with no agent it can start                |
| `lockout`          | `uname`                                | a `chmod 555` directory has to actually refuse a write              |
| `fork_concurrency` | `uname`                                | background subshells have to genuinely overlap                      |
| `mode_bits`        | `uname`                                | a reported permission string has to reflect `chmod`'s own bits      |

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
box's backends can host. The two aggregates have tracked each other within a
few points for many commits and both are reliable: **read the average of the
two badges** as the coverage figure, and the per-file reports for finding
untested arms. Only a massive divergence between them (tens of points, not
the usual few) means one tool has lost the plot and needs its probe re-run
before either is believed. Never a gate. Both sweeps pin
`_HI_PAR_WIDTH=1`: a suite's cases share one trace stream, and a batch writing
into it side by side loses lines.

In CI, each tool is sharded 4 ways (`--shard i/4`, the same knob
`windows-client.yml` and `ci.yml`'s `e2e` job use) and merged by a gather job
— `kcov --merge` over the four shards' `parts/` directories for kcov, a plain
JSON hash union over the four shards' `--command-name`-keyed `.resultset.json`
files for bashcov, since shards partition the suite table and so never share a
suite name. `_hi_cov_select_suites` passes `--shard` straight through to
`test_runner.sh`.

- `tests/coverage.sh` runs the sweep under kcov. Its failure mode is losing
  the DEBUG trap once the harness is sourced, which reads whole suites as
  load-time-only; the script's header carries the probe to re-run if the two
  badges ever diverge massively.
- **`kcov --merge` re-reads the sources.** Every shard records absolute
  paths, and the merge opens each one again to count its lines — so a gather
  job with no working tree merges to `"files": []` and a run-wide `0.00`,
  which is a well-formed report, not an error, and publishes a badge reading
  `0.00%`. `coverage.yml`'s `gather-kcov` therefore checks the tree out
  before merging; `tests/harness/runner_test.sh` asserts that every job in
  that workflow running `kcov --merge` does. `gather-bashcov` needs no
  checkout: its ruby reads only the resultset's per-line arrays.
- `tests/coverage_v2.sh` is the same sweep under
  [bashcov](https://github.com/infertux/bashcov), which reads bash's
  `xtrace`. Its residual skews run the other way from kcov's: every line of
  a **heredoc body** counts as covered whether or not it ran, and children
  under `env -i` or inside containers drop out of the trace — so a single
  file reads a few points off in either direction while the pair brackets
  the truth. Three more readings are artifacts, not gaps: a script a suite
  runs from a scratch-tree copy under `$_HI_WORKDIR` is filed under the
  copy's path and reads 0% for the repo file (`scripts/update.sh`); an
  `eval` anywhere inside a `$( )` zeroes every line of that subshell; a
  zsh-only arm is invisible to both tools; and a `#!/bin/sh` file a suite
  executes as `sh …` (`common/targets.sh`) is
  traced only where `sh` is bash — under a dash `/bin/sh` the whole file
  reads 0%, which is why `coverage.yml` puts a bash-as-`sh` first on PATH
  before each shard. Rule those out before writing a test against a
  number. It needs `gem install --user-install bashcov`; the script
  finds the binary off `$PATH`, writes a `.simplecov` into the checkout for
  the run, removes it after, and refuses to start rather than overwrite one
  you have.

`coverage.yml` publishes both aggregates as shields endpoints
(`badges/coverage.json`, `badges/coverage-v2.json`) via `pages.yml`, each
labelled by its measurer and computed over the shipped product only — the
badge math excludes `tests/` and `docs/`, the same subject both reports
declare. Each refreshes as soon as its sweep finishes — `pages.yml` redeploys
on a completed Coverage run as well as on a green CI — so a badge is only ever
as old as the sweep, never a push behind. Both stay because they cannot err in
the same direction: a file that reads low in bashcov is genuinely uncovered, a
line that reads covered in kcov genuinely ran.

Two shipped files sit outside what either tool can report at all:
`common/zsh.zsh` and `common/config.fish`. Both instrumentation methods need
a bash process — kcov's DEBUG trap and bashcov's `xtrace` are bash
mechanisms — and neither zsh nor fish provides one, so no line-coverage
percentage for these two is honest at any number. What stands in instead:
`tests/lint/dialects_test.sh`'s native roster ([check 5](#the-lint-gate)), and
`tests/common/exports_test.sh` and `tests/hi/prompt_test.sh`, which drift-check
`common/config.fish` against `common/core.sh` line by line rather than by
running it.

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
container. `ci.yml`'s `profile` job runs it beside `bench` on every push and
uploads the four profiles as the `profiles` artifact (14 days); it is
advisory (`continue-on-error`), the bench ceilings stay the gate.

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

**Upstream base images are digest-pinned, non-negotiably.** Every `FROM` in
`tests/dockerfiles/` that names an upstream image (11 of 19 - alpine, ubuntu,
debian, fedora, bash) carries a `@sha256:`: a digest is what makes a failed
e2e run reproducible and a base-image move a deliberate, reviewable act.
Dependabot bumps the digests weekly, which is how a base image reaching EOL
gets noticed. The other 8 are `FROM ${BASE}` over
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
download URL), `frameworks/mise.sh` (v2026.8.14, in the download URL) and
`frameworks/starship.sh` (v1.26.0, via `--version`) each name the version pin
in their own header and are bumped by hand when that framework's own bugs are
worth chasing, not on a schedule; `ci.yml`'s weekly run re-tests them against
whatever else moved but does not touch the pin. Each downloads to a file and
`sha256sum -c`s it before running `sh` on it, rather than piping `curl`
straight into a shell. Atuin's and mise's URLs name the release tag,
so the hash tracks the version pin above it and both are bumped together —
`mise.run` is regenerated per release whatever `MISE_VERSION` says, so pinning
it alone drifts. starship's install
script is a generic bootstrap endpoint (`starship.rs/install.sh`) that
installs whatever version the flag names, so its hash pins _that day's copy
of the installer_, not the app version - a hash mismatch there means the
installer changed, not the pinned app, and needs a fresh hash rather than a
version bump. Each script runs under `pipefail`, so a 404, a checksum
mismatch or the framework's installer changing shape fails the build rather
than shipping an image with the framework silently missing.

Nothing in `tests/dockerfiles/` reaches a release; the workflows and actions
the release path uses are SHA-pinned separately. What Scorecard dings here, and
how it's annotated, is [`.scorecard.yml`](../.scorecard.yml).

## The lint gate

`--group lint` is four suites, nineteen checks between them, and CI runs all
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

**`drift`** (`tests/lint/drift_test.sh`) — ten repo-consistency sweeps, each
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
- **15. Contents blocks**: in every page the Pages build renders, each `##`
  and `###` heading has an entry in that doc's `## Contents` list and each
  entry names a real heading, with an `###`'s entry indented under an `##`'s.
  `_config.yml` runs just-the-docs with no page front matter, so these lists
  are the site's only in-page navigation and nothing regenerates them.
- **16. The tldr page**: every `hi --flag` example in `docs/tldr.md` names a
  `common/flags` row, and there are at most eight examples - the upstream
  cap.
- **17. tests/dockerfiles/**: every image definition has a caller and vice
  versa.
- **18. Image tags**: every plain image tag named in shell or YAML is one of
  the digest-pinned `FROM` tags in `tests/dockerfiles/`.
- **19. Image digests**: two Dockerfiles pinning the same `image:tag` must
  agree on its digest - check 18 strips the digest before comparing, so it
  can't see one tag pinned to two; this one reads the digests back in.

## Test levers

Five environment variables are read by the tree but are not settings: they
exist so a suite, the bench or a demo can pin what a real run derives.
`_HI_TARGETS_TTL` (seconds `targets.sh` reuses its list; `0` sweeps every
call), `_HI_PROBE_TIMEOUT` (seconds one backend CLI gets), `_HI_PAYLOAD_CACHE`
(`0` builds the payload and overlay archives fresh), `_HI_CTL_PERSIST` (`0`
gives a connect a private ssh control socket, closed after) and
`_HI_HEADER_VERSION` (the header's version cell, otherwise `git describe` —
what `docs/tapes/generate.sh --version` sets). Their defaults are the shipped
behaviour; nothing in `hi --configure` writes them. `_HI_LOAD_NO_INIT=1` is
adjacent but not a lever: it makes `load.sh` define its functions without
running the profile chain, for `scripts/install.sh` to source.

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

## Why the harness is hand-rolled

[bats-core], [shellspec] and a python/pytest driver were weighed as
replacements for `tests/test_lib.sh` and `tests/lib/*.sh` (a paper study, no
suite was ported, no timings). `test_runner.sh` stays either way: a
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

**Keep it.** Every candidate loses at least one row above, usually more, and
the sweep's wall clock is container boot and e2e deadlines rather than
per-case dispatch, so speed would not have decided it. Reopen it if Git Bash
leaves the platform matrix, both coverage tools go unmaintained at once, or
one of these three documents an ordered parallel mode and a skip-as-failure
flag without a second package.

[bats-core]: https://bats-core.readthedocs.io/
[shellspec]: https://shellspec.info/
