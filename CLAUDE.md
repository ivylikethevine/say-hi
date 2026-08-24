# CLAUDE.md — working on say-hi

Conventions for agent sessions in this repo. The README and docs/ describe the
product; this file is only what a session needs to work here safely.

## The one hard rule: `_HI_HOME`

Always set `_HI_HOME` explicitly — to this checkout's parent, e.g.
`_HI_HOME=/home/ivy/projects/claude` — on every hi.sh, script, or test
invocation. Symptom of forgetting: suites report fewer/MISSING cases, or a
script runs "clean" because it ran against the wrong tree.

There are two say-hi trees on this machine, and neither is wired into the
user's shell any more:

- `~/projects/claude/say-hi` — **this dev checkout**, deliberately not
  installed, so work here never runs in the user's live shell.
- `~/projects/say-hi` — the user's real install, moved there from the old
  `~/hi.d`. Never inspect or touch it, even if it looks dirty. The rename has
  landed on `main`, so it is a `git pull` away from being current — whether it
  has pulled is not this checkout's business either way.

There are two hazards, and the first one this file used to deny.

**The rc wiring is still on disk.** `~/.bashrc`, `~/.zshrc` and
`~/.config/fish/config.fish` each still carry hi's install block —
`_HI_HOME=/home/ivy/projects` plus a `source` of that tree — so the claim that
nothing on disk exports `_HI_*` was wrong (`/etc/profile.d/` and
`/etc/environment` really are clean). It bites exactly one shell, which is why
it went unnoticed: `bash -c` and `zsh -c` are non-interactive and read neither
file, but **`fish -c` reads `config.fish` always**, so a bare `fish -c` runs
against `~/projects/say-hi` no matter what `_HI_HOME` you exported — silently,
against a tree that exists, with no error to read. The suites dodge it by
accident of `tests/test_lib.sh`'s `XDG_CONFIG_HOME` isolation, which moves
fish's config out of reach; a fish command typed by hand gets no such help. Set
`XDG_CONFIG_HOME` to a throwaway directory when checking anything in fish
outside the runner.

**The second is inherited process state.** A long-lived shell started back when
`~/hi.d` existed still carries a full `_HI_*` set (`_HI_HOME=/home/ivy`,
`_HI_ROOT=/home/ivy/hi.d`, `_HI_TEST_LIB=/home/ivy/hi.d/tests/test_lib.sh`,
~50 more) and hands it to every child, agent sessions included. Those paths
point at a tree that no longer exists, so the runner dies at its `source` line
with a bare `No such file or directory` naming a path nobody typed — before
`_hi_host_tree_check` (`tests/lib/report.sh`) ever gets to warn. Check with
`env | grep '^_HI_'`, and clear it with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

In a bash or zsh shell with no `_HI_*` set, no override is needed at all — every
entry point derives the tree from its own path (GLOSSARY: HI.33), and
`tests/test_runner.sh <suite>` just works.

**`_HI_HOME` alone is not enough to run one suite directly.** An inherited
environment also carries `_HI_ROOT` and `_HI_TEST_LIB`, and a suite's source
line is `${_HI_TEST_LIB:-…}` — the inherited value wins, so the *harness* is
loaded out of the old tree while `core.sh` quietly corrects `$_HI_ROOT` to the
tree you asked for. The run half-succeeds against two trees at once. Either go
through the runner, which sources the harness by absolute path:

```sh
_HI_HOME=/home/ivy/projects/claude tests/test_runner.sh <suite>
```

or, when a suite really has to run on its own, set both:

```sh
export _HI_HOME=/home/ivy/projects/claude
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

## Testing

- `tests/test_runner.sh` runs everything; `--group fast` is the CI gate. Lint
  (shellcheck, shfmt, checkbashisms, the bash-4 construct grep) is enforced by
  the fast group itself — there is no separate lint step.
- Run the suite at the **end** of a multi-step change, not between its steps.
  A structural refactor breaks loudly at source time, and each run costs ~2
  minutes — twice through a six-step change buys nothing the last run doesn't.
- The layout rule, the lint gate's ten halves, and the coverage caveat are
  [docs/TESTING.md](docs/TESTING.md)'s job — read it rather than this file for
  those. The two that bite a session most often: a suite lives in
  `tests/<the directory it tests>/` and sources the `tests/test_lib.sh` façade
  and nothing else (`docs/GLOSSARY.md`'s HI.34), and a new suite has to be
  registered in `test_runner.sh`'s `_HI_TESTS` table or no group runs it.
- Skip the suite when the diff is prose only — it costs ~2 minutes, most of it
  shellcheck, and no case reads ordinary `.md`. "Only `.yml`/`.md`" is _not_
  the same test, though: the fast group reads several of both. Run it when the
  diff touches `.github/workflows/*.yml` (`runner_test.sh` checks that every
  `--group` name `ci.yml` invokes exists; `packaging_test.sh` asserts against
  `release.yml` and scans every workflow for its `tool:` pins),
  `docs/GLOSSARY.md` (drift-checked against the tree's `GLOSSARY:` tags) or
  `docs/CONFIGURATION.md` (whose _Every setting_ table is drift-checked against
  `_HI_TOGGLES` and `install.sh`'s prompt rosters) — both by
  `tests/lint/shellcheck_test.sh` — or `packaging/nfpm/nfpm.yaml`. `README.md`'s
  payload badge is read by `bench_test.sh` — `--group bench`, not fast.
- `_HI_PAR_WIDTH=1` puts a parallel container suite back on one case at a
  time, and `_HI_SC_WIDTH=1` does the same for the lint fan-out — reach for
  them when a case is flaky or a transcript needs reading live rather than
  replayed.
- `shfmt -w .` is **not** the fix for a red shfmt gate: the gate reads the same
  `*.sh` list shellcheck does, and `.` also reformats `shells/zsh.zsh`, which
  is zsh and ships. Reformat the paths the failure names.
- The e2e suites (ssh, docker, podman, nomad, kube) need real backends, and
  they do run in this environment (the sandbox allows the docker socket as of
  Aug 2026). A suite that stands down reports yellow **SKIPPED**, never green;
  `--require-run` turns skips into failures. Try e2e first and read the
  STATUS/SKIP columns rather than assuming.
- `tests/coverage.sh`'s numbers are untrustworthy — its own header explains
  why. Don't write tests to move those figures.

## Hard constraints

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion. The lint suite greps for violations.
- `common/`, `misc/`, `shells/`, `load.sh` and `hi.sh` itself ship in the ssh
  payload (`$_HI_PAYLOAD`). It is CI-enforced twice, and the two are different
  numbers: `bench_payload_size` budgets the gzipped tar (65536 B), while the
  README badge tracks `_hi_wire_bytes` — the assembled script a session
  actually sends, which is what `hi` prints on connect — to within 5%. They
  move independently: putting a file _into_ the tar raises the first and
  lowers the second. Both measure a **default** configuration - `_hi_payload_tar`
  trims `misc/vim.rc`, `misc/nano.rc`, `shells/osc52.sh`, `shells/notify.sh`
  and `misc/personal.sh`
  when the overlay has turned them off, so a configured client sends less than
  either number. Tooling-only helpers must not go into `common/core.sh`; check
  both numbers when touching shipped files.
- Several files are dialect-constrained and say so at the top: paths.sh's
  four-shell plain-export subset, aliases.sh's POSIX+fish subset, and
  targets.sh's standalone POSIX. Respect the stated subset over "cleaner" bash.

## Workflow

- `docs/ROADMAP.md` is a to-do list, not a changelog: finished entries are
  deleted (git history is the ledger); entries whose code half shipped but
  which wait on a human step stay unticked, rewritten to say what shipped and
  what the tick now means.
