# CLAUDE.md — working on say-hi

Conventions for agent sessions in this repo. The README and docs/ describe the
product; this file is only what a session needs to work here safely.

## The one hard rule: `_HI_HOME`

Always set `_HI_HOME` explicitly — to this checkout's parent,
`_HI_HOME=/home/ivy/projects/claude` — on every hi.sh, script, or test
invocation. Symptom of forgetting: suites report fewer/MISSING cases, or a
script runs "clean" because it ran against the wrong tree.

There are two say-hi trees on this machine:

- `~/projects/claude/say-hi` — **this dev checkout**, deliberately not
  installed, so work here never runs in the user's live shell.
- `~/projects/say-hi` — the user's real install. Never inspect or touch it,
  even if it looks dirty.

Two hazards send a session at the wrong tree:

**The rc wiring is still on disk.** `~/.bashrc`, `~/.zshrc` and
`~/.config/fish/config.fish` each carry hi's install block
(`_HI_HOME=/home/ivy/projects` plus a `source`). `bash -c` and `zsh -c` are
non-interactive and read neither file, but **`fish -c` reads `config.fish`
always**, so a bare `fish -c` runs against `~/projects/say-hi` whatever
`_HI_HOME` you exported — silently. The suites dodge it through
`tests/test_lib.sh`'s `XDG_CONFIG_HOME` isolation; a fish command typed by
hand gets no such help. Set `XDG_CONFIG_HOME` to a throwaway directory when
checking anything in fish outside the runner.

**Inherited process state.** Agent sessions start with a full `_HI_*` set
already exported (~60 names, `_HI_HOME=/home/ivy/projects`,
`_HI_ROOT=/home/ivy/projects/say-hi`, `_HI_TEST_LIB=…/say-hi/tests/test_lib.sh`
among them) from the launching shell. Those paths are the **user's real
install**, and it exists, so nothing fails loudly. Check with
`env | grep '^_HI_'` before trusting any result, and clear it with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

With no `_HI_*` set, no override is needed at all — every entry point derives
the tree from its own path (GLOSSARY: HI.33).

**`_HI_HOME` alone is not enough to run one suite directly.** A suite's source
line is `${_HI_TEST_LIB:-…}`, so an inherited `_HI_TEST_LIB` loads the
_harness_ out of the user's install while `core.sh` corrects `$_HI_ROOT` to
the tree you asked for — half-succeeding against two trees, the shape nothing
warns about. Either go through the runner, which sources the harness by
absolute path and needs no `_HI_TEST_LIB`:

```sh
_HI_HOME=/home/ivy/projects/claude tests/test_runner.sh <suite>
```

or, when a suite really has to run on its own, set both:

```sh
export _HI_HOME=/home/ivy/projects/claude
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

## Testing

- `tests/test_runner.sh` runs everything; the CI gate is `--group fast` (the
  unit suites, run side by side, ~40s) then `--group lint` (shellcheck, shfmt,
  checkbashisms, the bash-4 grep and the doc drift checks, ~40s). Run both.
- Run the suite at the **end** of a multi-step change, not between steps — a
  structural refactor breaks loudly at source time.
- Layout rule, the lint gate's ten halves and the coverage caveat are
  [docs/TESTING.md](docs/TESTING.md)'s job. The two that bite most: a suite
  lives in `tests/<the directory it tests>/` and sources `tests/test_lib.sh`
  and nothing else (GLOSSARY: HI.34), and a new suite has to be registered in
  `test_runner.sh`'s `_HI_TESTS` table.
- **A green run here is not a green run in CI, and `/bin/sh` is why.** This box
  is Arch: `/bin/sh` is bash. CI's ubuntu is dash and macOS's `/bin/sh` is bash
  in POSIX mode, and both expand backslash escapes in `echo` where bash-as-sh
  leaves them as text. Prefer `printf` over `echo` in a fixture, and when a
  suite shells out to `sh`, sweep it before pushing:

  ```sh
  mkdir -p /tmp/dashsh && ln -sf "$(command -v dash)" /tmp/dashsh/sh
  PATH=/tmp/dashsh:$PATH _HI_HOME=/home/ivy/projects/claude \
    tests/test_runner.sh --group fast
  ```

- Skip the suite when the diff is prose only. "Only `.yml`/`.md`" is _not_
  the same thing: run it when the diff touches `.github/workflows/*.yml`
  (`runner_test.sh` checks every `--group` name `ci.yml` invokes exists;
  `packaging_test.sh` asserts against `release.yml` and scans every workflow
  for `tool:` pins), `docs/GLOSSARY.md` (drift-checked against the tree's
  `GLOSSARY:` tags), `docs/CONFIGURATION.md` (its _Every setting_ table is
  drift-checked against `_HI_TOGGLES` and `install.sh`'s prompt rosters) or
  `packaging/nfpm/nfpm.yaml`. The GLOSSARY and CONFIGURATION checks are in
  the lint group. `README.md`'s payload badge is read by
  `bench_test.sh` — `--group bench`, not fast.
- `_HI_PAR_WIDTH=1` puts a parallel container suite back on one case at a time;
  `_HI_SC_WIDTH=1` does the same for the lint fan-out — for a flaky case or a
  transcript that needs reading live.
- A `source "$_HI_CONFIG_DIR/<name>"` needs a `# shellcheck source=/dev/null`
  above it. `.shellcheckrc`'s `source-path=SCRIPTDIR` plus `shellcheck -x`
  makes the bare basename resolve to the _sourcing file itself_, and the
  linter re-parses it forever — ~33GB resident, a global OOM. The lint suite
  refuses to start when one is missing.
- `shfmt -w .` is **not** the fix for a red shfmt gate: `.` also reformats
  `common/zsh.zsh`, which is zsh and ships. Reformat the paths the failure
  names.
- The e2e suites (ssh, docker, podman, nomad, kube) need real backends, and
  they do run here (the sandbox allows the docker socket as of Aug 2026). A
  suite that stands down reports yellow **SKIPPED**, never green;
  `--require-run` turns skips into failures. Try e2e first and read the
  STATUS/SKIP columns rather than assuming.
- `tests/coverage.sh`'s numbers are untrustworthy — its header explains why.
  Don't write tests to move those figures.

## Hard constraints

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion. The lint suite greps for violations.
- `common/`, `settings/`, `load.sh` and `hi.sh` ship in the ssh payload
  (`$_HI_PAYLOAD`), CI-enforced against two different numbers:
  `bench_payload_size` budgets the gzipped tar (65536 B), and the README badge
  tracks `_hi_wire_bytes` — the assembled script a session sends — to within
  5%. Both measure a **default** configuration (`_hi_payload_tar` trims files
  the overlay has turned off). Tooling-only helpers must not go into
  `common/core.sh`; check both numbers when touching shipped files.
- Several files are dialect-constrained and say so at the top: paths.sh's
  four-shell plain-export subset, aliases.sh's POSIX+fish subset, and
  targets.sh's standalone POSIX. Respect the stated subset over "cleaner" bash.

## Workflow

- `docs/ROADMAP.md` is a to-do list, not a changelog: finished entries are
  deleted (git history is the ledger); entries whose code half shipped but
  which wait on a human step stay unticked, rewritten to say what shipped and
  what the tick now means.
