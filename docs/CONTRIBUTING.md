# Contributing to say-hi

say-hi is [EXPERIMENTAL UNTIL v1.0.0](../README.md#experimental-until-v100-stable-releases):
interfaces can still move, and [docs/ROADMAP.md](ROADMAP.md) is what is left
to do. The test runbook is [docs/TESTING.md](TESTING.md); the named idioms are
[docs/GLOSSARY.md](GLOSSARY.md).

## Contents

- [Before you start](#before-you-start)
- [The gate](#the-gate)
  - [Don't reach for `act`](#dont-reach-for-act)
- [What CI runs](#what-ci-runs)
- [What a review will bounce on](#what-a-review-will-bounce-on)
- [Which docs change with what](#which-docs-change-with-what)
- [Opening the pull request](#opening-the-pull-request)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## Before you start

**Check it isn't already decided.** [docs/SUPPORT.md](SUPPORT.md) covers
everything hi does reach and holds a verdict and a reason for every runtime,
shell, packaging channel and feature answered no;
[docs/ALTERNATIVES.md](ALTERNATIVES.md) does the same for the tools say-hi is
not trying to be. A "no" there is settled, not an oversight — though a reason
that has stopped being true is worth an issue, and a good implementation would
be considered.

## The gate

```sh
tests/test_runner.sh --group fast
tests/test_runner.sh --group lint
```

That is what CI runs on every push: the unit suites (side by side, ~40s), then
the linter sweep (shellcheck, shfmt, checkbashisms, the bash-4 grep and the doc
drift checks). Both should be green before you open the pull request.

The `e2e` and `backends` groups need real backends (a reachable sshd, a docker
or podman socket, a nomad agent, a cluster) and stand down **yellow SKIPPED**
when they can't run, never green. If your change touches one of those paths,
run that group (or the suite by name) and say in the pull request whether it
ran or skipped; `--require-run` turns a skip into a failure.

### Don't reach for `act`

[act](https://github.com/nektos/act) is **not** the way to check a change here,
measured against this tree with act 0.2.89: `act -j test` reports **six
failures a real runner does not**, because act's container runs as root and six
fast-group cases assert non-root behaviour (five fish prompt-separator cases in
`tests/common/rc_test.sh`, plus `install: Degrades when sudo can't link`).
Running the container as a normal user does not rescue it: under
`--container-options "--user 1000"` the image has no passwordless sudo for the
apt installs the job opens with.

`tests/test_runner.sh --group fast` is the same gate with none of that. If you
want a workflow run anyway, `advisory-lint` (markdownlint, hadolint,
demo-staleness) is green under act and every tool in it you can also run
directly. `workflow-lint` bundles actionlint with zizmor, and zizmor fails on
act's empty `github.token`, so a run of that job shows red under act even when
actionlint itself is clean — run `actionlint -color` directly instead if
that's what you're checking. The macOS/Windows jobs have no container to run
in; `bench`, `packaging-smoke` and the two `e2e` jobs want the Docker socket.

```sh
act -W .github/workflows/ci.yml -j advisory-lint -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

## What CI runs

"The gate" above is the two commands to run yourself; this is every job
`ci.yml` runs on your pull request, and whether a red one actually fails the
run or only reports. Ported from sharerr's `docs/CONTRIBUTING.md`, which keeps
the same table for the same reason — sixteen workflow files is more than the
per-job comments in `ci.yml` are convenient to read through by eye.

| Job                                                      | Runs on your PR                                                      | Gate or advisory?                       |
| -------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------- |
| `fast suites (ubuntu-latest)` (also runs the lint group) | Skipped on a workflow-only diff                                      | Gate                                    |
| `fast suites (macos-latest)`                             | Skipped on a workflow-only diff                                      | Gate                                    |
| `workflow lint` (actionlint + zizmor)                    | Always                                                               | Gate                                    |
| `advisory lint` (markdownlint, hadolint, demo-staleness) | Always                                                               | Advisory — reports, never fails the job |
| `hot-path benchmarks`                                    | Skipped on a workflow-only diff                                      | Gate                                    |
| `package build (deb, rpm, apk)`                          | Skipped on a workflow-only diff                                      | Gate                                    |
| `e2e (ssh, docker)`                                      | After the ubuntu fast suite passes; skipped on a workflow-only diff  | Gate                                    |
| `e2e (podman, nomad, kube)`                              | After the ubuntu fast suite passes; skipped on a workflow-only diff  | Gate                                    |
| `e2e (macOS)` / `e2e (Windows)` / `e2e (FreeBSD)`        | Push to `main` only, after both fast-suite jobs pass — never on a PR | Gate                                    |
| `fast suites (Windows client)`                           | Push to `main` only — never on a PR                                  | Gate, but see below                     |

"Skipped on a workflow-only diff" is `changes.yml`: a PR that only touches
`.github/workflows/**` can't move any of these jobs' results, so they report
`skipped` instead of re-running. `workflow-lint` and `advisory-lint` are
deliberately exempt — a workflow-only change is exactly what the first audits,
and a docs-only change is exactly when the second should run.

"Gate" here means the job itself fails loudly rather than reporting and
continuing — not that GitHub's merge button is blocked by it. No job on this
list is a configured required status check yet ([docs/ROADMAP.md](ROADMAP.md)'s
release-readiness entry has the reasoning); `fast suites (Windows client)` in
particular carries no `continue-on-error` and a red suite there fails that run,
but doesn't yet stop a merge either way.

The rest of the workflows in `.github/workflows/` — `release.yml`,
`snapshot.yml`, `pages.yml`, `codeql.yml`, `scorecard.yml`, `image-scan.yml`,
`tool-versions.yml`, `link-check.yml` and `demos.yml` — run on a schedule, a
push to `main`, or a tag, not on your pull request (`demos.yml` is the one
partial exception: it also runs on a PR that touches `docs/tapes/**`). Most of
them report through a self-closing tracking issue rather than a red run; see
each file's own header for why.

## What a review will bounce on

These are constraints the tree enforces, not requests:

- **bash 3.2 is the floor.** No `mapfile`/`readarray`, associative arrays,
  namerefs or `${x,,}`; the lint suite greps for all four. Every deliberately
  odd construct that forces is explained once in [GLOSSARY.md](GLOSSARY.md),
  and code points at it with a `GLOSSARY: HI.NN` tag — drift-checked, so an
  entry can't be deleted out from under them.
- **Several files are a smaller dialect than bash, and say so at the top.**
  `common/paths.sh` is the four-shell plain-`export` subset,
  `settings/aliases.sh` is POSIX+fish, `common/targets.sh` is standalone POSIX.
  The stated subset wins over anything cleaner.
- **Nothing may guess the tree from `$HOME`.** Each entry point derives it from
  its own path (`GLOSSARY: HI.33`). The lint sweep covers the docs too.
- **The payload is budgeted twice.** `common/`, `settings/`, `load.sh` and
  `hi.sh` ship to every target; the gzipped tar and the assembled wire script
  are CI-enforced against separate numbers. Touch a shipped file, run
  `--group bench` and check both. Tooling-only helpers do not belong in
  `common/core.sh`.
- **A new suite has a home and a registration.** It lives in
  `tests/<the directory it tests>/`, sources `tests/test_lib.sh` and nothing
  else (`GLOSSARY: HI.34`), and goes in `test_runner.sh`'s `_HI_TESTS` table.
- **A red `shfmt` is fixed on the paths it names**, not with `shfmt -w .`,
  which would also reformat `common/zsh.zsh` — zsh, not bash, and shipped.

## Which docs change with what

| you changed                           | update                                        |
| ------------------------------------- | --------------------------------------------- |
| a flag, or `_hi_parse`                | `docs/hi.1` and `docs/tldr.md`                |
| an environment variable or toggle     | `docs/SETTINGS.md` (enforced, see below)      |
| what hi leaves on a target            | `docs/SECURITY.md`                            |
| a target hi does or doesn't answer to | `docs/SUPPORT.md`                             |
| a new idiom worth a name              | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag  |
| a release channel or the release flow | `docs/PACKAGING.md`                           |

Two rows are checked by the lint suite: a `GLOSSARY:` tag naming a missing
entry fails, and so does a toggle in `common/core.sh` with no row in
[SETTINGS.md](SETTINGS.md)'s _Every setting_ table. The rest are on
your honour and on review.

`docs/ROADMAP.md` is a to-do list, not a changelog: finishing an entry means
**deleting** it — git history is the ledger.

## Opening the pull request

- **Base it on `dev`** unless an issue says otherwise. `main` is protected: it
  takes pull requests from `dev`, and releases are built off it.
- **Simple, concise commits** — enough to see what is going on; the pull
  request body is where the detail lives.
- **Say if AI wrote part of it.** [README's AI Usage](../README.md#ai-usage) is
  the standard, and it applies to contributions: the tool is fine, and the code
  is still yours to have understood, reviewed and stood behind.

## Reporting a vulnerability

Report anything exploitable privately, per
[docs/SECURITY.md](SECURITY.md#reporting-a-vulnerability) — not as a public
issue.
