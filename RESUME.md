# Coverage work: where it stands

Saved 2026-10-13 at about 20:45 on bertha. Everything under _Done_ is committed and
pushed as `b2fa3a0` ("added more tests", on `dev`). This file is untracked on
purpose; delete it when the list below is done. The staged driver patch is
`local/patch-coverage-v2-credit.py` (gitignored).

## Done

### Coverage tooling (`tests/coverage*.sh`, `tests/lib/coverage.sh`, `coverage.yml`)

- **One subject filter:** `_HI_COV_NOT_SUBJECT` (tests, docs, scratch, .github),
  applied to both tools' rankings and badge figures.
- **Same denominator:** kcov parses the product's directories
  (`--bash-parse-files-in-dir`, `--include-pattern=.sh`), so a file no suite loads
  reads 0%.
- **Joined table:** `tests/coverage.sh --join [kcov files] [bashcov files]`, with
  a `!` on a gap of 15 points or more or a one-sided file. It is in the comment
  job's summary.
- **Changed lines:** each sweep writes `missed` (path:line) beside `files`.
  `tests/coverage.sh --untested <rev>` lists the changed lines both tools missed,
  and the PR comment carries up to 20 rows. The comment job checks out with
  `fetch-depth: 2` to diff against `HEAD^1`.
- **bashcov merge moved out of the workflow:** `gather-bashcov` checks out and
  runs `tests/coverage_v2.sh --merge`.
- **kcov runs with `--bash-method=DEBUG`.** Its default PS4 method stops
  recording on bash 5.3 after a traced value holding a quote and a newline
  (`tests/dockerfiles/sshd-entrypoint.sh`). The probe is in the driver's header.
- **bashcov's trace pipe is made blocking:** `tests/lib/coverage_env.sh`, loaded
  through `BASH_ENV`. Ruby opens the pipe non-blocking and bash drops lines when
  it fills, about 2/3 of a tight loop's hits. The cost is roughly 2x the traced
  run time; `shard-bashcov`'s timeout went from 25 to 45 minutes.
- **The driver no longer leaks the developer's settings:** `tests/lib/coverage.sh`
  un-exports what `core.sh` read from `~/.config/say-hi/settings.sh`. That leak
  made `core_target` and `doctor_json` fail under either tracer locally.
- **Trace variables pass through `env -i`:** `_hi_trace_env` in
  `tests/lib/fixtures.sh`, used by `_hi_login_env`, `_hi_bare_bash` and
  `rc_test.sh`'s `_hi_rc_shell`.
- **Harness half of copy-crediting:** `tests/lib/workdir.sh` keeps `$_HI_WORKDIR`
  and lists it in `$_HI_COV_KEEP` when that is set. It is inert until the driver
  half (below) is applied.

### Tests added

The changed suites passed when run on their own. The full groups have **not** been
rerun since.

| Suite              | New case(s)                                                          |
| ------------------ | -------------------------------------------------------------------- |
| `test_runner_ci`   | `--join`, `--untested`, `coverage_v2.sh --merge` (2 cases)           |
| `hi_keep`          | `mux.sh` linked, not copied, in its fixture (bashcov now credits it) |
| `configure_pty`    | three-strikes quit fixed (the old input never reached it)            |
| `header`           | `Auth:` and `Pub:` key counts                                        |
| `configure_wizard` | plugin descriptions by kind; `_hi_setting_flip` both ways            |
| `configure`        | `_hi_menu_rows` default; switch keys find only real rows             |
| `rc`               | prompt stands down for `_HI_PROMPT_DRAWN` / `_HI_PROMPT_INIT`        |
| `rc_lines`         | macOS `--print-rc` for the `.bash_profile` lines                     |
| `hi_payload_scan`  | relay carry token; second carried file of a name                     |
| `load`             | kept `~/` nano include counts its syntaxes                           |
| `packaging`        | OpenBSD `sha256 -r` and python blake2b fallbacks                     |
| `load_session`     | `_hi_keep_holds`: when a session may hold its tree                   |

### Docs

- `docs/TESTING.md`: the subject filter, `--join`, `missed` and `--untested`, the
  `DEBUG` method, the blocking pipe, and the new cases.
- `README.md` roadmap: entries 8 (changed lines, shipped, waits on a PR), 9
  (artifact markers) and 10 (`DEBUG`, waits on a full CI sweep). All three are
  labelled _Before 1.0_; relabel if they shouldn't gate the tag.

## Not done

Updated 2026-10-13, late. Uncommitted in the working tree: the driver half of
copy-crediting (`tests/coverage_v2.sh`, from `local/patch-coverage-v2-credit.py`,
linted, never run), one new doctor case, and roadmap entry 4's code (below).

1. **Get the coverage changes through CI.** PR 213 merged as `e03e834` at
   `b8a0892`, so neither `b2fa3a0` nor this tree's changes have run there. Open
   a `dev` PR; `dev` also lacks `e03e834` itself.
2. **Read that run's gaps.** PR 213's bashcov data (`b8a0892`) lists 452 missed
   product lines, but nearly every `scripts/` one has a case that runs from a
   `_hi_scratch_tree` copy, which bashcov dropped before copy-crediting. Grep
   for a case first. The one real gap found, doctor's "not wired - not your
   login shell" row, now has a case in `doctor_target`. Reading artifacts:
   `gh run download` is refused by a hook; pipe
   `gh api .../actions/artifacts/<id>/zip` into `python3 -I` and read
   `.resultset.json` in memory.
3. **Rerun `--group fast,ci`, `--group lint` and `--group bench`.** The last
   green run was before the newest cases; `load.sh` and `common/header.sh`
   changed since.
4. **Add the fast-group baseline to the memory note** once a sweep has run:
   dated, with commit, both figures. The note is
   `/workspace/dotfiles/dot_claude/projects/private_-workspace-say-hi/exact_memory/say-hi.md`,
   bertha section.

## Not coverable with these tracers

- zsh-only arms
- macOS, Windows and AMD sysinfo arms, which read fixed `/proc` paths and so
  can't be faked without a product change
- bash before 4.2 (macOS's 3.2 leg)
- `packaging/bump.sh`'s `makepkg` branch (Arch only)
- empty `case` arms and redirect lines, which xtrace never prints

## Figures

PR 213's CI data, recomputed with the new filter: bashcov **95.82%**, kcov
**90.76%**. No full sweep has run with the current changes.

## Housekeeping

- About 440 `/tmp/hi.*.XXXXXX` scratch directories from this session's runs are
  left; not deleted.
- Installed on bertha: kcov 43, bashcov 4.0.0, checkbashisms 2.26.12, mandoc
  1.14.6. The memory note has the details.
- The push runs PR 213's coverage workflow with every change above for the first
  time: the merge modes, the by-file summary, the changed-lines comment, the
  45-minute bashcov shards, and kcov under `DEBUG`. Check that run first.
