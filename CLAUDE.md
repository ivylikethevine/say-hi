# CLAUDE.md — working on say-hi

Conventions for agent sessions in this repo. The README and docs/ describe the
product; this is only what a session needs to work here safely.

## Table of contents

- [The one hard rule: `_HI_HOME`](#the-one-hard-rule-_hi_home)
- [Testing](#testing)
- [Hard constraints](#hard-constraints)
- [Workflow](#workflow)

## The one hard rule: `_HI_HOME`

Set `_HI_HOME=/home/ivy/claude` (this checkout's parent) explicitly on every
hi.sh, script or test invocation. Symptom of forgetting: suites report
fewer/MISSING cases, or a script runs "clean" against the wrong tree.

Two say-hi trees exist on this machine:

- `~/claude/say-hi` — **this dev checkout**, deliberately not installed.
- `~/projects/say-hi` — the user's real install. Never inspect or touch it,
  even if it looks dirty.

Two hazards send a session at the wrong tree:

**The rc wiring is on disk.** `~/.bashrc`, `~/.zshrc` and
`~/.config/fish/config.fish` each carry hi's install block
(`_HI_HOME=/home/ivy/projects` plus a `source`). `bash -c` and `zsh -c` read
neither, but **`fish -c` always reads `config.fish`**, so a bare `fish -c`
runs against `~/projects/say-hi` whatever you exported. The suites dodge it
through `tests/test_lib.sh`'s `XDG_CONFIG_HOME` isolation; a fish command
typed by hand needs `XDG_CONFIG_HOME` pointed at a throwaway directory.

**Inherited process state.** Sessions start with a full `_HI_*` set (~60
names: `_HI_HOME=/home/ivy/projects`, `_HI_ROOT=/home/ivy/projects/say-hi`,
`_HI_TEST_LIB=…/say-hi/tests/test_lib.sh`, …) exported from the launching
shell. Those paths are the user's real install and exist, so nothing fails
loudly. (An install carrying HI.47 exports six names instead; same check.)
Check with `env | grep '^_HI_'` and clear with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

With no `_HI_*` set, no override is needed — every entry point derives the
tree from its own path (GLOSSARY: HI.33).

**`_HI_HOME` alone does not run one suite directly.** A suite sources
`${_HI_TEST_LIB:-…}`, so an inherited `_HI_TEST_LIB` loads the harness from
the user's install while `core.sh` corrects `$_HI_ROOT` to the tree you asked
for — half-succeeding against two trees, and nothing warns. Go through the
runner, which sources the harness by absolute path:

```sh
_HI_HOME=/home/ivy/claude tests/test_runner.sh <suite>
```

or, when a suite has to run alone, set both:

```sh
export _HI_HOME=/home/ivy/claude
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

## Testing

- The CI gate is `--group fast` (~15s) and `--group lint` (~30s), two
  parallel jobs; run both, at the **end** of a multi-step change.
- A suite lives in `tests/<the directory it tests>/`, sources
  `tests/test_lib.sh` and nothing else (GLOSSARY: HI.34), and is registered
  in `test_runner.sh`'s `_HI_TESTS` table. The rest of the layout and the
  lint gate's checks are [docs/TESTING.md](docs/TESTING.md).
- **A green run here is not a green run in CI: `/bin/sh` is bash on this Arch
  box.** CI's ubuntu is dash and macOS's `/bin/sh` is bash in POSIX mode; both
  expand backslash escapes in `echo` where bash-as-sh leaves them as text.
  Prefer `printf` in fixtures, and when a suite shells out to `sh`, sweep it
  before pushing:

  ```sh
  mkdir -p /tmp/dashsh && ln -sf "$(command -v dash)" /tmp/dashsh/sh
  PATH=/tmp/dashsh:$PATH _HI_HOME=/home/ivy/claude \
    tests/test_runner.sh --group fast
  ```

- Skip the suite when the diff is prose only. "Only `.yml`/`.md`" is _not_
  prose only: `.github/workflows/*.yml`, `docs/GLOSSARY.md`,
  `docs/SETTINGS.md`'s _Every setting_ table, `docs/hi.1`, `docs/tldr.md`,
  every doc's `## Contents` block and `packaging/nfpm/nfpm.yaml` are all
  machine-read by a suite. `README.md`'s payload badge is read by
  `--group bench`.
- `_HI_PAR_WIDTH=1` runs a parallel container suite one case at a time;
  `_HI_SC_WIDTH=1` does the same for the lint fan-out — for a flaky case or a
  transcript that needs reading live.
- A `source "$_HI_CONFIG_DIR/<name>"` needs `# shellcheck source=/dev/null`
  above it, or `shellcheck -x` recurses to an OOM; the lint suite refuses to
  start without it.
- A red shfmt is fixed on the paths it names, never `shfmt -w .` (that also
  reformats `common/zsh.zsh`, which is zsh and ships).
- The e2e suites (ssh, docker) and `--group backends` (podman, nomad, kube)
  need real backends and do run here (the sandbox allows the docker socket).
  A suite that stands down
  reports yellow **SKIPPED**, never green; `--require-run` turns skips into
  failures. Try e2e first and read the STATUS/SKIP columns.
- Rank coverage gaps off `tests/coverage_v2.sh` (bashcov), and rule out the
  artifacts its header lists before writing a test against a number; write
  tests for untested behavior, never bare line-executions
  ([docs/TESTING.md](docs/TESTING.md#coverage-and-profiling)).

## Hard constraints

The full list, with the why, is
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on).

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion; the lint suite greps for them.
- `common/`, `settings/`, `load.sh` and `hi.sh` ship in the ssh payload,
  budgeted twice (the gzipped tar, and the README's wire-bytes badge to
  within 5%); tooling-only helpers stay out of `common/core.sh`, and
  `--group bench` checks both numbers after touching a shipped file.
- paths.sh, aliases.sh and targets.sh are dialect-constrained and say so at
  the top; the stated subset wins over "cleaner" bash.

## Workflow

- `README.md`'s Roadmap section is a to-do list, not a changelog: finished
  entries are deleted (git history is the ledger); entries whose code half
  shipped but which wait on a human step stay unticked, rewritten to say what
  shipped and what the tick now means.
