# CLAUDE.md — working on say-hi

Only what a session cannot derive from the code and the docs. The human
contract — the gate, what a review bounces on, what CI runs, which docs change
with what — is [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md); this file links to
it rather than copying it, and adds what an agent needs beyond it.

## Contents

- [Verification loop](#verification-loop)
- [Hard constraints](#hard-constraints)
  - [`_HI_HOME` points at this checkout](#_hi_home-points-at-this-checkout)
- [Traps](#traps)
- [Docs rules](#docs-rules)
- [Repository mechanics](#repository-mechanics)
- [Machine-specific notes](#machine-specific-notes)

## Verification loop

From the checkout root, with no inherited `_HI_*` set
([below](#_hi_home-points-at-this-checkout)):

```sh
npm ci --prefix .github   # once, and after the lockfile moves
_HI_HOME="$(dirname "$PWD")" tests/test_runner.sh --group fast   # ~15s
_HI_HOME="$(dirname "$PWD")" tests/test_runner.sh --group lint   # ~30s
```

Without the `npm ci`, the lint group skips markdownlint and prettier yellow,
and CI's lint job, which has them, fails what that run let through.

The two groups are CI's gate, two parallel jobs; run both at the **end** of a multi-step
change. After touching a shipped file (`common/`, `settings/`, `load.sh`,
`hi.sh`) add `--group bench`. The e2e suites (ssh, docker) and
`--group backends` (podman, nomad, kube) need real backends; try them before
calling an ssh or container change done, and read the STATUS/SKIP columns.

- A suite lives in `tests/<the directory it tests>/`, sources
  `tests/test_lib.sh` and nothing else (GLOSSARY: HI.34), and is registered
  in `test_runner.sh`'s `_HI_TESTS` table. The rest of the layout and the
  lint gate's checks are [docs/TESTING.md](docs/TESTING.md).
- `_HI_PAR_WIDTH=1` runs a parallel container suite one case at a time;
  `_HI_SC_WIDTH=1` does the same for the lint fan-out — for a flaky case or a
  transcript that needs reading live.
- Rank coverage gaps off `tests/coverage_v2.sh` (bashcov), and rule out the
  artifacts its header lists before writing a test against a number; write
  tests for untested behavior, never bare line-executions
  ([docs/TESTING.md](docs/TESTING.md#coverage-and-profiling)).

## Hard constraints

The full list, with the why, is
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on).

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion; the lint suite greps for them.
- `common/`, `settings/`, `load.sh`, and `hi.sh` ship in the ssh payload,
  budgeted twice (the gzipped tar, and the README's wire-bytes badge to
  within 5%); tooling-only helpers stay out of `common/core.sh`, and
  `--group bench` checks both numbers after touching a shipped file.
- paths.sh, aliases.sh, and targets.sh are dialect-constrained and say so at
  the top; the stated subset wins over "cleaner" bash.

### `_HI_HOME` points at this checkout

Set `_HI_HOME` explicitly on every hi.sh, script, or test invocation, to the
directory **holding this checkout** (the tree is `$_HI_HOME/say-hi`) — never
to a real install of hi, even one on the same machine. Symptom of getting it
wrong: suites report fewer/MISSING cases, or a script runs "clean" against the
wrong tree.

**Clear inherited `_HI_*` first.** A session launched from a shell with hi
installed starts with that install's `_HI_*` set (`_HI_HOME`, `_HI_ROOT`,
`_HI_TEST_LIB`, … — around sixty names, or six from an install carrying
HI.47). Those paths exist, so nothing fails loudly. Check with
`env | grep '^_HI_'` and clear with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

With no `_HI_*` set, no override is needed — every entry point derives the
tree from its own path (GLOSSARY: HI.33).

**`fish -c` reads `config.fish`.** On a machine where hi is installed, the rc
files (`~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`) each carry hi's
install block (an `_HI_HOME=` line plus a `source`). `bash -c` and `zsh -c`
read neither, but **`fish -c` always reads `config.fish`**, so a bare `fish -c`
runs against the installed tree whatever you exported. The suites dodge it
through `tests/test_lib.sh`'s `XDG_CONFIG_HOME` isolation; a fish command
typed by hand needs `XDG_CONFIG_HOME` pointed at a throwaway directory.

## Traps

**`_HI_HOME` alone does not run one suite directly.** A suite sources
`${_HI_TEST_LIB:-…}`, so an inherited `_HI_TEST_LIB` loads the harness from
another tree while `core.sh` corrects `$_HI_ROOT` to the one you asked for —
half-succeeding against two trees, and nothing warns. Go through the runner,
which sources the harness by absolute path:

```sh
_HI_HOME="$(dirname "$PWD")" tests/test_runner.sh <suite>
```

or, when a suite has to run alone, set both:

```sh
export _HI_HOME="$(dirname "$PWD")"
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

**A green run where `/bin/sh` is bash is not a green run in CI.** CI's ubuntu
is dash and macOS's `/bin/sh` is bash in POSIX mode; both expand backslash
escapes in `echo` where bash-as-sh leaves them as text. Prefer `printf` in
fixtures, and when a suite shells out to `sh`, sweep it with dash before
pushing:

```sh
mkdir -p /tmp/dashsh && ln -sf "$(command -v dash)" /tmp/dashsh/sh
PATH=/tmp/dashsh:$PATH _HI_HOME="$(dirname "$PWD")" \
  tests/test_runner.sh --group fast
```

**"Only `.yml`/`.md`" is _not_ prose only.** Skipping the suites is right for
a prose-only diff, but `.github/workflows/*.yml`, `docs/GLOSSARY.md`,
`docs/SETTINGS.md`'s _Every setting_ table, `docs/hi.1`, `docs/tldr.md`,
every doc's `## Contents` block, `docs/PACKAGING.md`'s `minisign -Vm` line,
and `packaging/nfpm/nfpm.yaml` are all machine-read by a suite. `README.md`'s
payload badge is read by `--group bench`.

**A bare `source "$_HI_CONFIG_DIR/<name>"` sends `shellcheck -x` into an
OOM.** It needs `# shellcheck source=/dev/null` above it; the lint suite
refuses to start without it.

**`shfmt -w .` reformats a zsh file that ships.** A red shfmt is fixed on the
paths it names, never the whole tree (that also rewrites `common/zsh.zsh`).

**A suite that stands down reports yellow SKIPPED, never green.** Read it as
"did not run"; `--require-run` turns skips into failures.

## Docs rules

- Which doc a change updates is
  [CONTRIBUTING.md's _Which docs change with what_](docs/CONTRIBUTING.md#which-docs-change-with-what);
  every fact has one home, mapped by [docs/README.md](docs/README.md). Link
  to that home, don't copy it — this file included.
- `README.md`'s Roadmap is a to-do list, not a changelog
  ([CONTRIBUTING.md](docs/CONTRIBUTING.md#which-docs-change-with-what)).
  Beyond that: entries whose code half shipped but which wait on a human step
  stay unticked, rewritten to say what shipped and what the tick now means.

## Repository mechanics

- **CI tiers.** Which jobs gate, which are advisory, and which are required
  before a merge to `main` is
  [CONTRIBUTING.md's _What CI runs_](docs/CONTRIBUTING.md#what-ci-runs); each
  other workflow's header says when it runs and why.
- **Releases.** A pushed, signed `v*` tag runs `release.yml` unattended,
  gated by tag protection and the `gate` job (tag format, on `main`, signed
  by a key in `.github/allowed_signers`, green CI); the runbook, the environments, and each channel's
  steps are [docs/RELEASING.md](docs/RELEASING.md). How users install and
  verify is [docs/PACKAGING.md](docs/PACKAGING.md).
- **Tool pins.** CI's tools are pinned in
  `.github/actions/setup-tool/tools.txt`, eight columns
  (`name|pin|kind|url|verify|check|tag-prefix|sha256`, documented in its
  header) with the sha256 either one hash or one per platform, and
  drift-checked by `tool-versions.yml` plus this repo's
  `.github/scripts/check_tool_versions.local.sh` hook; move a pin there, pin
  and sha256 together, not in a workflow. markdownlint-cli2 and prettier are
  `.github/package-lock.json`'s instead.

## Machine-specific notes

Machine-specific notes (absolute paths, which tree on this host is a real
install, the host's `/bin/sh`) live in an untracked `CLAUDE.local.md` beside
this file; `.gitignore` keeps it out of the repository.
