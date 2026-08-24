# Testing

Every script resolves against `$_HI_HOME/say-hi`. The runner defaults `_HI_HOME`
to this checkout's parent, so a fresh clone works with no setup - but never
point anything at your real say-hi install:

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
- [Relaying](#relaying)
- [Local-only](#local-only)

## Running the tests

Run everything with `tests/test_runner.sh` (reachable as `hi --test` once
installed) - it times each suite and prints a colored pass/fail summary at the
end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --group fast       # what CI runs on every push/PR
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

A passing suite's transcript collapses to one status line; failures replay in
full and are recapped under the summary table. `--verbose` (`_HI_VERBOSE=1`)
streams every transcript live instead, which is what you want when a case fails
only under the runner. A suite whose backend is missing reports **SKIPPED**,
never a green pass, and `--require-run` (what CI's e2e/backends jobs pass) turns
those skips into failures.

`--host-report` (`_HI_HOST_REPORT=1`) prints one block before the first suite:
bash, the OS, whether the userland is GNU/BSD/busybox, the locale's glyph
verdict, which tree `$_HI_HOME` actually resolves to, which backends answer, and
the lint tools' versions - the questions asked every time a suite passes on one
machine and fails on another. CI passes it on every job. The `_HI_HOME` half of
it prints on **every** run, flag or not - but only when the tree the suites are
testing isn't the one you invoked the runner from, which is the quietest way to
get a wrong result here.

Four groups (`--group <name>`), matching CI's four jobs. `--list` prints the
membership, which is the copy to trust —
`tests/test_runner.sh --group fast --list`:

- **`fast`** — dependency-free, the first thing CI runs on every push/PR. Every
  suite except the three groups below, including `test_lib`, `test_lib_report`,
  `test_lib_par` and `test_runner`, which are the harness testing itself.
- **`bench`** — hot-path timings checked against ceilings, plus the payload's
  two size budgets.
- **`e2e`** — `ssh`, `ssh_disconnect`, `ssh_relay`, `install_methods`,
  `docker`, `framework`: real throwaway containers driving `hi.sh`'s actual
  connection paths, covering both halves of it (`_say_hi` and
  `_say_hi_container`).
- **`backends`** — `podman`, `nomad`, `kube`: split from `e2e` because they need
  extra runner setup (podman, nomad, kind) beyond docker; a separate, slower CI
  job.

Every e2e/backends suite skips cleanly with a warning rather than failing when
its backend isn't installed. Every test script also runs directly, e.g.
`tests/lint/shellcheck_test.sh`.

The same doctrine reaches individual fast cases, through two guards that differ
only in what they look for. `_hi_check_requires <bin>` skips the case when a
_command_ is missing. `_hi_check_capable <capability>` skips it when a
_facility_ is - something `command -v` cannot answer. The roster lives in
`_hi_capable` (`tests/lib/fixtures.sh`) and is two entries long: `symlink`
makes one and tests `[ -L ]`, so a filesystem that refuses _or_ silently copies
both read as no; `pty` is python3 being able to `import pty`, not python3
merely existing. Both are there for Git Bash, where `ln -s` wants Developer
Mode and `pty` is Unix-only - and both are probes rather than OS sniffs, so
nothing here has to know what MSYS is. `_hi_par_check_capable` is the twin a
parallel suite uses.

### Where a suite lives

`tests/<the directory it tests>/`. `tests/common/`, `tests/settings/`,
`tests/scripts/` and `tests/packaging/` mirror the tree; `tests/hi/` and
`tests/load/` cover the two scripts at the root; `tests/lint/` is the lint
gate, `tests/bench/` the timings, `tests/targets/` the container/ssh e2e
suites, and `tests/harness/` the suites that test the harness. The harness
itself is `tests/test_lib.sh` — a façade over `tests/lib/`, which is where its
parts live. A suite sources the façade and nothing else (`docs/GLOSSARY.md`'s
HI.34).

### The container suites run their cases in parallel

`ssh`, `ssh_relay`, `install_methods`, `docker`, `podman`, `framework` and
`kube` spend nearly all
their wall clock waiting on one container at a time, so their cases run in a
batch: `_hi_par_case` in `tests/lib/parallel.sh` submits a case to a background
subshell, `_hi_par_wait` collects the batch. Each case writes its verdict to a
file that the parent tallies (a subshell's counter increments would die with
it), registers what it started on a teardown ledger the exit trap sweeps, and
buffers its output to be replayed **in submission order** - so a parallel run's
transcript reads exactly like a serial one, only the timings overlap. Cases that
read another case's files stay serial: `ssh_test.sh`'s two
`_hi_transcript_is_clean` checks run after the batch, not in it.

The batch is capped, and every run says how wide it went
(`| login-shell cases: 4 at a time, …`). The default is four, or the CPU count
if that is smaller; unbounded fan-out thrashes the docker daemon on a laptop and
is both slower and flakier. `_HI_PAR_WIDTH` overrides it:

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, down the same code path - what to use when bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

`nomad` pins itself to `_HI_PAR_WIDTH=1`: its jobs are tracked in a shell array
its cleanup hook purges, which is the one fixture in the tree that is not
case-scoped.

### The install-method suite

`install_methods` is the sibling of `ssh_test.sh`, split on what each one
varies: `ssh` runs one install against every login shell, `install_methods`
runs one login shell against every way say-hi gets onto a machine — the `.deb`,
the `.rpm`, the `.apk`, a Homebrew-shaped keg, a system-wide
`install.sh --prefix`, and a tree whose `/etc/profile.d` announcement has been
removed. They share the case runner in `tests/lib/ssh.sh`.

Every case asserts the same thing: `$_HI_ROOT` is the path the installer left,
and no payload was copied. A session that merely works proves nothing here — hi
shipping its whole tree over the top produces one of those too, which is the
waste the permanent-install path exists to avoid.

The three package cases build what they install with `packaging/mkpkg.sh`, so
they need `nfpm`; without it they stand down yellow. That is a **per-case**
skip, which `--require-run` does not catch (it reads suite-level skips), so
`ci.yml`'s e2e job pins nfpm through `setup-tool` to make them actually run.
The other three need nothing beyond docker.

### Coverage and profiling

Three hand-run tools sit beside the suites, all deliberately out of CI. Two of
them measure coverage, they disagree, and neither is right — read both or
neither.

`tests/coverage.sh` runs the fast suites under kcov when you want to know which
arms of `install.sh`/`bump.sh` the cases never touch. Its numbers are currently
untrustworthy: kcov loses the DEBUG trap once the harness is sourced, so a
figure describes what ran while things were _loading_ rather than what the
suites cover — `common/git_prompt.sh` reads 2.56% with seventeen cases passing
against it. Don't write tests to move those figures.

`tests/coverage_v2.sh` is the same sweep under
[bashcov](https://github.com/infertux/bashcov), which reads bash's own `xtrace`
instead of driving a DEBUG trap and so cannot fail that way — it puts
`common/git_prompt.sh` at 92.68%, and an uncalled function correctly reads 0.
It fails the other way instead: every line of a **heredoc body** counts as
covered, including lines that are pure text, so anything that generates scripts
reads high. `hi.sh` is the worst case at 97.38%, where `_say_hi` and
`_say_hi_container` both report 100% — 182 lines nothing in `--group fast`
calls. Files with no heredocs (all of `common/` and `settings/`) are the ones
to believe.

It needs a gem rather than a source build: `gem install --user-install bashcov`,
which needs ruby. The script finds a `--user-install` binary off `$PATH` by
itself. It writes a `.simplecov` into the checkout for the length of the run and
removes it afterwards, and refuses to start rather than overwrite one you have.

README's **kcov** and **bashcov** badges are those two aggregates, published by
the dispatch-only `coverage.yml` and `coverage-v2.yml` and picked up by
`pages.yml` from the last successful run of each. Both are grey, and say
`load-time` and `heredoc-inflated` rather than green and `coverage`, for exactly
the reasons above; until someone dispatches the workflow each reads
`not measured`. Neither gates anything.

`tests/profile.sh` is what to run when a `--group bench` ceiling trips:
`_hi_bench` says _whether_ a path got slower, and this says _which command in
it_ did. It profiles the four bash paths the bench guards through
[timep](https://github.com/jkool702/timep), and it runs **in a container** —
`tests/dockerfiles/timep.Dockerfile`, the one file there that is a tool
environment rather than a target.

The container is not incidental. timep is packaged nowhere and is not a binary:
`timep.bash` carries base64-encoded loadable-builtin `.so` files, unpacks them
at source time and `enable -f`'s them into the running shell, so it is worth
sandboxing on its own. The box also settles three requirements timep has and
does not check — glibc ≥ 2.38, a bash with `enable -f`, and a writable
**exec-capable** `/dev/shm` (Docker mounts that `noexec`, hence
`--tmpfs /dev/shm:rw,exec`). Missing any of them, timep exits 0 and writes
arithmetic errors instead of times, which is why `profile.sh` grades the output
and not the status.

The checkout is mounted read-only and only the output directory is writable, so
nothing the profiler runs can touch the tree. timep is fetched inside the box;
set `$_HI_TIMEP` to mount a local copy you have read instead. The numbers
therefore come from that container rather than from your machine — one more
reason the header says to read the ranking, not the milliseconds.

### The images are files; the build contexts are not

Every container image an e2e suite builds is a real Dockerfile under
[`tests/dockerfiles/`](../tests/dockerfiles) - `sshd-debian`, `sshd-alpine` and
`sshd-fedora` for the ssh targets, `alpine-shell` for the bare shell ones,
`installed-*` for the install-method targets, `framework-*` for the nine shell
frameworks, and so on. What stays generated per case is the
_build context_: the throwaway keypair's `entrypoint.sh`, and for the
pre-installed case the repo itself. Suites reach a file through
`_hi_dockerfile <stem>` and pass it with `-f`; the variants that differ only by
a package list or a base image are one file plus a `--build-arg` (`PKGS`,
`BASE`) rather than a file each.

`docs/tapes/fixtures.sh` builds from the same folder, spelling the path out
rather than using the helper - a tape render happens outside the test harness,
so it does not source `test_lib.sh`.

The lint gate checks both directions: no Dockerfile without a caller, no caller
naming a Dockerfile that isn't there. Inline heredocs could not get that wrong;
files can, and the failure would otherwise surface as "the image just didn't
build" in an e2e run on a machine with a container backend.

### What is pinned, and what deliberately is not

Scorecard's Pinned-Dependencies check reports every line below and will keep
reporting some of them. The answer, so it does not get re-decided each time that
report is read:

**Base images are digest-pinned, and that is not negotiable.** Every `FROM` in
`tests/dockerfiles/` carries a `@sha256:` - `alpine`, `debian:bookworm-slim`,
`debian:trixie-slim`, `bash:3.2` and `fedora` (the rpm target the
install-method suite installs a real `.rpm` on). A
digest is what makes a failed e2e run reproducible, and it is what makes a
base-image move a deliberate, reviewable act instead of a green run going red
for reasons nobody changed. Dependabot bumps the digests weekly. The upgrade
from Alpine 3.20 to 3.24 in August 2026 is the case for it: 3.20 had been past
EOL since 2026-04-01 and the pin is why nothing had silently drifted off it in
the meantime, and why the bump could be run against the whole e2e set as one
change.

**The same tags named in shell and YAML are guarded, not watched.** `alpine:`
and `debian:` also appear as plain tags in `tests/lib/backend.sh`,
`docs/tapes/fixtures.sh` and `ci.yml`'s packaging smoke - places Dependabot
cannot see, because it reads Dockerfiles. Rather than leave them to drift,
`lint_image_tags` fails the build when a tag named anywhere in the tree
disagrees with the digest-pinned one in `tests/dockerfiles/`. Dependabot bumps
one place; the gate makes the others follow.

**The three `curl | sh` framework installers are deliberately not pinned.**
`framework-atuin`, `framework-mise` and `framework-starship` each exist to test
hi against whatever that framework _currently_ installs. Pinning them would test
a frozen framework, which is the opposite of the question they are asked. They
carry `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` so a 404 fails the build
rather than shipping an image with the framework missing - that, not a pin, is
what makes them trustworthy.

Nothing in `tests/dockerfiles/` reaches a release; the workflows and actions the
release path uses are SHA-pinned separately.

## The lint gate

`tests/test_runner.sh shellcheck` is one suite with ten halves, and CI runs all
of them.

One check runs **before** all of them and is fatal rather than counted: every
`source` of a `$_HI_CONFIG_DIR/...` path must carry a `# shellcheck source=`
directive above it. `.shellcheckrc` sets `source-path=SCRIPTDIR`, so under
`shellcheck -x` the basename resolves against the sourcing file's _own_
directory - and where it names that file, the linter follows it into itself and
re-parses until the kernel OOM-kills it. That is not hypothetical: it reached
~33GB resident twice on a 38GB machine with no swap, taking the editor down with
the run. The check is a precondition rather than an eleventh half precisely
because of ordering - the damage happens in the fan-out below, so anything
reporting afterwards never gets to speak. It aborts the suite naming the file
and line, in well under a second.

1. **shellcheck** over every `*.sh` (CI pins the version - see
   `.github/actions/setup-tool/tools.txt`). It is the whole cost of the fast
   group, so the file list is dealt into one invocation per CPU and replayed in
   order; `_HI_SC_WIDTH=1` puts it back on a single process.
2. **Native syntax checks**: `zsh -n` / `fish --no-execute` over the files those
   shells parse for themselves.
3. **The bash-3.2 grep**: no `mapfile`, no associative arrays, no namerefs, no
   `${x,,}` - macOS ships bash 3.2 and hi runs there. Every deliberately-odd
   construct this forces is explained once in [GLOSSARY.md](GLOSSARY.md); code
   references entries by their stable `HI.NN` code with `GLOSSARY: HI.NN` tags
   rather than re-explaining.
4. **The `$HOME` default sweep**: nothing may fall back to `$HOME` when it
   derives the say-hi tree - a guessed tree is how a session ends up reading
   someone else's. Wider than the shellcheck list, covering `*.zsh`, `*.fish`
   and `*.md` too, since the docs teach the rule as much as the code obeys it.
5. **shfmt** as a formatting gate over the same `*.sh` list. The style comes
   from `.editorconfig`; fix a red run with `shfmt -w` on the paths it names,
   not `shfmt -w .` - that would also reformat `common/zsh.zsh`, which is not in
   the gate and is zsh, not bash.
6. **checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
   really do parse on minimal targets.
7. **GLOSSARY tags**: every `GLOSSARY: HI.NN` in the tree has to name a code
   [GLOSSARY.md](GLOSSARY.md) defines, so a deleted entry can't strand the tags
   pointing at it. Codes are matched, not titles - retitling an entry touches no
   shipped file. Matched anywhere on a line, so a mid-sentence
   `(GLOSSARY: HI.33)` counts; keep the code on the same line as the marker,
   since a reference wrapped onto the next comment line is not seen.
8. **The settings roster**: every name the tree treats as a setting - the
   `_HI_TOGGLES` array in `common/core.sh`, and the variable column of
   `scripts/install.sh`'s `_HI_FEATURE_PROMPTS` and `_HI_HEADER_PROMPTS` - has
   to have a row in [CONFIGURATION.md](CONFIGURATION.md)'s _Every setting_
   table, and every row there has to name a variable the tree still reads. Only
   that one section is matched, not the whole document: the point of the table
   is that "what can I set?" is answerable from one place, which a name
   mentioned in passing three sections away does not achieve. A name hi
   assembles at run time (`_HI_PROMPT_END_$SHELL`) is matched by its literal
   prefix, since it never appears whole.
9. **tests/dockerfiles/**: every image definition has a caller and every caller
   has an image definition - see above.
10. **Image tags**: every `alpine:3.24`/`debian:bookworm-slim`/`bash:3.2` named
    as a plain tag in shell or YAML has to agree with the digest-pinned version
    in `tests/dockerfiles`. Dependabot bumps the Dockerfile digests and cannot
    see the rest; this is what makes them follow.

Halves 5 and 6 skip yellow when the tool isn't installed locally; CI always
enforces them.

## Relaying

`hi` chains: from a session on B you can `hi C`, and the second hop is a full hi
session. That works from a _disposable_ session too, because `hi.sh` rides every
bash-capable one — it is a member of `$_HI_PAYLOAD`, so it arrives in the
payload tar with the rest of the tree, exec bit and all (which is why the
write-back is `cat` and not `mv`, GLOSSARY HI.09). `ssh_relay` is the proof: A → B → C, config
intact on the final hop, cleanup traps firing on **both** B and C, on a clean
exit and on the link being killed mid-relay. The one tier that cannot relay is
the container transport's bash-less fallback, which ships `aliases.sh` alone and
never loads `paths.sh` — there `hi` is simply not defined.

## Local-only

The tests are local-only: `tests/` is stripped from the payload, so `hi --test`
on a target says so rather than running. It is not alone — every flag that needs
`scripts/`, `tests/` or a `.git` answers the same way there, and two of them
(`--test` and `--update`) answer that way in a package-manager install too,
which ships `scripts/` but neither of the other two.

**Which flag needs what is `docs/hi.1`'s OPTIONS section**, where the grouping is
drift-checked against `common/targets.sh`'s completion roster by
`tests/hi/parse_test.sh`. This file used to keep a fourth copy of that list and
it had already gone stale — it omitted `--doctor`, which is exactly the flag the
man page itself was wrong about — so it now points rather than repeats.

`hi --packages-preview` is the one that does not refuse: its legend lives in
`scripts/`, but the check it previews lives in the shipped `common/header.sh`,
so on a target it runs that half instead.
