# CLAUDE.md — working on say-hi

Only what a session cannot derive from the code and the docs. The human
contract — the gate, what a review bounces on, what CI runs, which docs change
with what — is [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md); this file links to
it rather than copying it.

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
and CI, which has them, fails what that run let through. Run both groups at
the **end** of a multi-step change; after touching a shipped file add
`--group bench`. Before calling an ssh or container change done, try `--group
e2e` and `--group backends` too, and read the STATUS/SKIP columns: a yellow
SKIPPED means "did not run", never green.

- A new suite's home, preamble (GLOSSARY: HI.34), and registration are
  [docs/TESTING.md's _Where a suite lives_](docs/TESTING.md#where-a-suite-lives).
- `_HI_PAR_WIDTH=1` runs a parallel container suite one case at a time;
  `_HI_SC_WIDTH=1` does the same for the lint fan-out — for a flaky case or a
  transcript that needs reading live.
- Rank coverage gaps off `tests/coverage_v2.sh` (bashcov), and rule out the
  artifacts its header lists before writing a test against a number; write
  tests for untested behavior, never bare line-executions
  ([docs/TESTING.md](docs/TESTING.md#coverage-and-profiling)).

## Hard constraints

[CONTRIBUTING.md's _What a review will bounce on_](docs/CONTRIBUTING.md#what-a-review-will-bounce-on)
is the list, with the why — the bash 3.2 floor, the dialect-constrained
files, and the payload budget chief among them. Read it before touching
`common/`, `config/`, `load.sh`, or `hi.sh`. One more, for sessions only:

### `_HI_HOME` points at this checkout

Set `_HI_HOME` explicitly on every hi.sh, script, or test invocation, to the
directory **holding this checkout** (the tree is `$_HI_HOME/say-hi`) — never
to a real install of hi, even one on the same machine. Symptom of getting it
wrong: suites report fewer/MISSING cases, or a script runs "clean" against the
wrong tree.

**Clear inherited `_HI_*` first.** A session launched from a shell with hi
installed inherits that install's `_HI_*` (`_HI_HOME`, `_HI_ROOT`,
`_HI_TEST_LIB`, … — around sixty names, or six from an install carrying
HI.47). Those paths exist, so nothing fails loudly. Check with
`env | grep '^_HI_'` and clear with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

With no `_HI_*` set, every entry point derives the tree from its own path
(GLOSSARY: HI.33).

**`fish -c` reads `config.fish`.** Where hi is installed, `~/.bashrc`,
`~/.zshrc`, and `~/.config/fish/config.fish` each carry its install block (an
`_HI_HOME=` line plus a `source`). `bash -c` and `zsh -c` read neither, but
**`fish -c` always reads `config.fish`**, so it runs against the installed
tree whatever you exported. The suites dodge it through `tests/test_lib.sh`'s
`XDG_CONFIG_HOME` isolation; a fish command typed by hand needs
`XDG_CONFIG_HOME` pointed at a throwaway directory.

## Traps

**`_HI_HOME` alone does not run one suite directly.** A suite sources
`${_HI_TEST_LIB:-…}`, so an inherited `_HI_TEST_LIB` loads the harness from
another tree while `common/paths.sh` re-derives `$_HI_ROOT` from the
`_HI_HOME` you set — half-succeeding against two trees, and nothing warns. Go
through the runner, which sources the harness from its own `_HI_HOME`:

```sh
_HI_HOME="$(dirname "$PWD")" tests/test_runner.sh <suite>
```

or, when a suite has to run alone, set both:

```sh
export _HI_HOME="$(dirname "$PWD")"
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

**Check [docs/SYNTAX.md](docs/SYNTAX.md) before writing a pipe, a `sed`, or
a `date`.** Each row there is a spelling that passed here and failed on
another target; the ones a pattern can see fail `drift`, the rest only a CI
round trip finds.

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
a prose-only diff, but `.github/workflows/*.yml`,
`.github/pull_request_template.md`, `docs/GLOSSARY.md`, `docs/SETTINGS.md`'s
_Every setting_ table, `docs/hi.1`, `docs/tldr.md`, every doc's `## Contents`
block, `docs/PACKAGING.md`'s `minisign -Vm` line, and
`packaging/nfpm/nfpm.yaml` are all machine-read by a suite, and `README.md`'s
payload badge by `--group bench`.

## Docs rules

- Which doc a change updates is
  [CONTRIBUTING.md's _Which docs change with what_](docs/CONTRIBUTING.md#which-docs-change-with-what);
  every fact has one home, mapped by [docs/README.md](docs/README.md). Link
  to that home, don't copy it — this file included.
- `README.md`'s Roadmap is a to-do list, not a changelog (same section).
  Beyond that: entries whose code half shipped but which wait on a human step
  stay unticked, rewritten to say what shipped and what the tick now means.

## Repository mechanics

- **CI tiers** — gate, advisory, and required before a merge to `main` — are
  [CONTRIBUTING.md's _What CI runs_](docs/CONTRIBUTING.md#what-ci-runs).
- **A pushed, signed `v*` tag is a release**: `release.yml` runs unattended
  behind its `gate` job ([docs/RELEASING.md](docs/RELEASING.md)).
- **Tool pins** move in `.github/actions/setup-tool/tools.txt`, pin and sha256
  together, never in a workflow; markdownlint-cli2 and prettier are
  `.github/package-lock.json`'s
  ([docs/TESTING.md's _The lint gate_](docs/TESTING.md#the-lint-gate)).

## Machine-specific notes

Absolute paths, which tree on this host is a real install, and the host's
`/bin/sh` live in an untracked `CLAUDE.local.md` beside this file.
