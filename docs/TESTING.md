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

Five groups (`--group <name>`; `--list` prints the membership):

- **`fast`** — dependency-free unit suites, the first thing CI runs on every
  platform job; `test_lib`, `test_lib_report`, `test_lib_par` and
  `test_runner` are the harness testing itself. Suites run **side by side**
  (up to four, or the CPU count), each in its own workdir with its own tally
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
`_hi_capable` (`tests/lib/fixtures.sh`), has two entries, both for Git Bash
and both probes rather than OS sniffs: `symlink` makes one and tests `[ -L ]`,
so a filesystem that refuses _or_ silently copies reads as no; `pty` is
python3 being able to `import pty`. `_hi_par_check_capable` is the parallel
twin.

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
thrashes the docker daemon on a laptop. `_HI_PAR_WIDTH` overrides it:

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, same code path - for bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

`nomad` pins itself to `_HI_PAR_WIDTH=1`: its jobs are tracked in a shell array
its cleanup hook purges, the one fixture in the tree that is not case-scoped.

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

Three hand-run tools, all out of CI. Two measure coverage, they disagree, and
neither is right:

- `tests/coverage.sh` runs the fast suites under kcov, which loses the DEBUG
  trap once the harness is sourced, so a figure describes what ran while
  things were _loading_ — `common/git_prompt.sh` reads 2.56% with seventeen
  cases passing against it. Don't write tests to move those figures.
- `tests/coverage_v2.sh` is the same sweep under
  [bashcov](https://github.com/infertux/bashcov), which reads bash's `xtrace`
  and puts `common/git_prompt.sh` at 92.68%. It fails the other way: every
  line of a **heredoc body** counts as covered, so anything that generates
  scripts reads high — `hi.sh` at 97.38%, `_say_hi` and `_say_hi_container`
  at 100% though nothing in `--group fast` calls them. Files with no heredocs
  (all of `common/` and `settings/`) are the ones to believe. It needs
  `gem install --user-install bashcov`; the script finds the binary off
  `$PATH`, writes a `.simplecov` into the checkout for the run, removes it
  after, and refuses to start rather than overwrite one you have.

The dispatch-only `coverage.yml` and `coverage-v2.yml` publish the two
aggregates as shields endpoints (`badges/coverage.json`,
`badges/coverage-v2.json`) via `pages.yml`, labelled `load-time` /
`heredoc-inflated` rather than `coverage`. README shows them under an explicit
disclaimer — the labels say what each number actually is, never a green
"coverage: N%" — and neither gates anything. Both stay: kcov cannot over-count
and bashcov cannot under-count, so a file that reads low in bashcov is
genuinely uncovered and a line that reads covered in kcov genuinely ran.
`coverage.sh`'s header is the measured record of _why_ kcov cannot be the
tool.

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
`frameworks/`). Only the _build context_ is generated per case: the throwaway
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
`tests/dockerfiles/` that names an upstream image (10 of 18 - alpine, ubuntu,
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

**The three `curl | sh` framework installers are pinned to a release each, not
a hash.** `frameworks/atuin.sh` (v18.20.1, in the download URL),
`frameworks/mise.sh` (v2026.8.14, via `MISE_VERSION`) and
`frameworks/starship.sh` (v1.26.0, via `--version`) each name the pin in their
own header and are bumped by hand when that framework's own bugs are worth
chasing, not on a schedule; `ci.yml`'s weekly run re-tests them against
whatever else moved but does not touch the pin. Scorecard still reports all
three as unpinned `downloadThenRun` dependencies: its probe has no "pinned to
a version" state for a download piped to a shell, only pinned-by-hash or not.
Each script runs under `pipefail`, so a 404 or a checksum mismatch fails the
build rather than shipping an image with the framework silently missing.

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
  separate from Scorecard), and the answers live there now; the draft that
  used to sit in docs/ is git history. The score reflects registration the
  next time Scorecard runs. _Passing_ still waits on the first release —
  three MUST criteria are release-shaped.
- **Signed-Releases reads -1 (excluded from the average)**, not a fixable 0 —
  Scorecard hasn't seen a release yet. `release.yml` already ships
  `dist/SHA256SUMS.minisig` and a build-provenance attestation, and `.minisig`
  is an extension the check recognizes, so this resolves on its own once
  [a release ships](ROADMAP.md#quick-wins).

## The lint gate

`--group lint` is four suites, seventeen checks between them, and CI runs all
of them. Each suite is its own process (`tests/test_runner.sh shellcheck`,
`dialects`, `tools`, `drift`) with its own file/failure/skip tally in the
summary table, so a failure in one never hides what the others found.

**`shellcheck`** (`tests/lint/shellcheck_test.sh`) — one check, and the whole
cost of the group. A fatal guard runs **before** it: every `source` of a
`$_HI_CONFIG_DIR/...` path must carry a `# shellcheck source=` directive.
`.shellcheckrc` sets `source-path=SCRIPTDIR`, so under `shellcheck -x` a bare
basename resolves against the sourcing file's own directory, and where it
names that file the linter follows it into itself and re-parses until the
kernel OOM-kills it (~33GB resident on a 38GB machine, editor included). The
guard comes first because the damage happens in the fan-out right after it.

- **1. shellcheck** over every `*.sh` (CI pins the version in
  `.github/actions/setup-tool/tools.txt`). The file list is dealt into one
  invocation per CPU and replayed in order; `_HI_SC_WIDTH=1` puts it back on a
  single process.

**`dialects`** (`tests/lint/dialects_test.sh`) — four shell-dialect syntax
checks. 3-5 skip yellow without docker, but with docker _present_ an image
that will not build is a **failure**, not a skip: the base is digest-pinned
and the only other thing in each file is an apt install with a version
assertion, so "would not build" means the distro moved off the version the
check claims — the news the check exists to carry.

- **2. Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
  those shells parse for themselves, using whatever `zsh` and `fish` this
  machine has.
- **3. The fish 3.7 floor**: the same files parsed inside a digest-pinned
  **fish 3.7.0** (`tests/dockerfiles/fish37.Dockerfile`, Ubuntu 24.04's fish,
  which is CI's). Check 2 cannot cover this: fish 4 accepts constructs 3.7
  rejects, so a developer on current fish gets a green run and CI does not.
  The construct that earned it was a _comment inside a `{ ... }` block_ in
  `common/paths.sh` — `{` opens a brace expansion to fish and `#` is not a
  comment inside one, so the file died with "Mismatched braces", taking
  `$_HI_TARGETS`, every path and every alias with it; fish 4.8 parsed it,
  3.7 did not. The rule at the block: nothing but `export NAME=value` lines
  between those braces.
- **4. The fish 4 ceiling**: the same files inside a digest-pinned **fish 4**
  (`tests/dockerfiles/fish4.Dockerfile`, Ubuntu 26.04's fish), catching a
  construct 3.7 accepts that fish 4 rejects or has removed. CI's runners are
  24.04, so nothing else in CI parses these files under fish 4.
- **5. The zsh 5.8 floor** does more than parse. zsh's risky constructs here —
  `add-zsh-hook zshexit`, the `${(%):-%x}` the tree is derived with,
  `${~pat}`, the `KSH_ARRAYS` divergence — parse on every zsh and only
  misbehave on an old one, so `zsh -n` would wave them all through. This one
  parses the files, then _sources_ `common/zsh.zsh` in a real interactive
  zsh inside a pinned **zsh 5.8** (`tests/dockerfiles/zsh58.Dockerfile`,
  Debian oldstable's) and asks for the four things a session depends on: a
  prompt, the aliases, a resolved host color and the prompt separator. 5.8
  because bookworm, noble, alpine and macOS all ship 5.9 — no machine anyone
  develops on is the floor.

**`tools`** (`tests/lint/tools_test.sh`) — four external-tool wrappers, each
skipping yellow when its tool isn't installed locally (CI has all four):

- **6. shfmt** over the same `*.sh` list shellcheck reads, style from
  `.editorconfig`. Fix a red run with `shfmt -w` on the paths it names, not
  `shfmt -w .`, which would also reformat `common/zsh.zsh`.
- **7. checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
  really do parse on minimal targets.
- **8. mandoc** over `docs/hi.1` (`mandoc -T lint -W warning`): the page ships
  in every package, and a roff mistake renders as garbage on `man hi` while
  failing nothing else.
- **9. typos** over the whole tree; the allowlist is `.typos.toml` at the root,
  one commented line per term the checker reads wrong.

**`drift`** (`tests/lint/drift_test.sh`) — eight repo-consistency sweeps, each
a grep or small parser checking that something written down elsewhere still
agrees with the tree:

- **10. The bash-3.2 grep**: no `mapfile`, associative arrays, namerefs or
  `${x,,}`. Every odd construct this forces is explained once in
  [GLOSSARY.md](GLOSSARY.md); code references entries by `GLOSSARY: HI.NN`
  tag.
- **11. The `$HOME` default sweep**: nothing may fall back to `$HOME` when it
  derives the say-hi tree. Wider than the shellcheck list — `*.zsh`,
  `*.fish` and `*.md` too, since the docs teach the rule as much as the code
  obeys it.
- **12. GLOSSARY tags**: every `GLOSSARY: HI.NN` in the tree names a code
  GLOSSARY.md defines, and every entry is referenced. Codes are matched, not
  titles, anywhere on a line — keep the code on the same line as the
  marker.
- **13. The settings roster**: every name the tree treats as a setting
  (`_HI_TOGGLES` in `common/core.sh`, the variable column of every
  `_HI_*_PROMPTS` table in `scripts/configure.sh`) has a row in
  [SETTINGS.md](SETTINGS.md)'s _Every setting_ table, and every row there
  names a variable the tree still reads. Only that section is matched; a
  name assembled at run time (`_HI_PROMPT_END_$SHELL`) is matched by its
  literal prefix.
- **14. Liquid syntax**: no page Jekyll's Pages build renders (derived from
  `_config.yml`'s `exclude:` block, not hand-kept) may carry a raw Liquid
  delimiter outside a guarded span — Liquid tokenizes before Markdown, so a
  fence gives no shelter. The construct that does it is a fenced GitHub
  Actions expression whose `format('{0}-{1}', …)` hands the tokenizer a
  lone closing brace mid-expression. A page that means to show a delimiter
  wraps the span in a raw/endraw guard, each half inside an HTML comment so
  the guard never renders; otherwise it stays off the site.
- **15. tests/dockerfiles/**: every image definition has a caller and vice
  versa.
- **16. Image tags**: every image tag named as a plain tag in shell or YAML is
  one of the digest-pinned `FROM` tags in `tests/dockerfiles/` — the set,
  not one tag per image, since `debian` and `ubuntu` are each pinned twice
  on purpose.
- **17. Image digests**: two Dockerfiles may pin the same `image:tag` (the sshd
  and demo debian bases, the two alpines) but must agree on its digest.
  Check 16 strips the digest before comparing, so it cannot see one tag
  pinned to two digests — how a "same pin as the sshd base" header claim
  goes quietly false. This one reads the digests back in and fails any tag
  with more than one.

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
