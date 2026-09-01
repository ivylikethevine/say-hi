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
- [What 1.x will not break](#what-1x-will-not-break)
- [Which docs change with what](#which-docs-change-with-what)
- [Opening the pull request](#opening-the-pull-request)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## Before you start

**Check it isn't already decided.** [docs/SUPPORT.md](SUPPORT.md) holds a
verdict and a reason for every runtime, shell and feature answered no,
[docs/PACKAGING.md](PACKAGING.md#channels-weighed-and-not-shipped) for every
packaging channel, and [docs/ALTERNATIVES.md](ALTERNATIVES.md) for the tools
say-hi is not trying to be. A "no" there is settled, not an oversight — though
a reason that has stopped being true is worth an issue, and a good
implementation would be considered.

## The gate

```sh
tests/test_runner.sh --group fast
tests/test_runner.sh --group lint
```

That is what CI runs on every push; both should be green before you open the
pull request. What each group contains is [docs/TESTING.md](TESTING.md)'s job.

The `e2e` and `backends` groups need real backends and stand down **yellow
SKIPPED** when they can't run, never green. If your change touches one of
those paths, run that group (or the suite by name) and say in the pull request
whether it ran or skipped; `--require-run` turns a skip into a failure.

### Don't reach for `act`

[act](https://github.com/nektos/act) is **not** the way to check a change here
(measured with act 0.2.89): its container runs as root, so `act -j test` fails
six fast-group cases a real runner passes — five fish prompt-separator cases
in `tests/common/rc_test.sh`, plus `install: Degrades when sudo can't link` —
and `--container-options "--user 1000"` doesn't rescue it, since the image has
no passwordless sudo for the apt installs the job opens with. `advisory-lint`
is the one job green under act, and every tool in it runs directly anyway.
`workflow-lint`'s zizmor fails on act's empty `github.token`, so run
`actionlint -color` directly instead. The macOS/Windows jobs have no container
to run in; `bench`, `packaging-smoke` and the two `e2e` jobs want the Docker
socket.

```sh
act -W .github/workflows/ci.yml -j advisory-lint -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

## What CI runs

Every job `ci.yml` runs on your pull request, and whether a red one fails the
run or only reports — seventeen workflow files is more than `ci.yml`'s per-job
comments are convenient to read through by eye.

| Job                                                      | Runs on your PR                                                      | Gate or advisory?                       |
| -------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------- |
| `fast suites (ubuntu-latest)` (also runs the lint group) | Skipped on a workflow-only diff                                      | Gate                                    |
| `fast suites (macos-latest)`                             | Skipped on a workflow-only diff                                      | Gate                                    |
| `workflow lint` (actionlint + zizmor)                    | Always                                                               | Gate                                    |
| `advisory lint` (markdownlint, hadolint, demo-staleness) | Always                                                               | Advisory — reports, never fails the job |
| `hot-path benchmarks`                                    | Skipped on a workflow-only diff                                      | Gate                                    |
| `package build (deb, rpm, apk)`                          | Skipped on a workflow-only diff                                      | Gate                                    |
| `e2e (ssh, docker)`                                      | Beside the fast suites; skipped on a workflow-only diff              | Gate                                    |
| `e2e (podman, nomad, kube)`                              | Beside the fast suites; skipped on a workflow-only diff              | Gate                                    |
| `e2e (macOS)` / `e2e (Windows)` / `e2e (FreeBSD)`        | Push to `main` only, after both fast-suite jobs pass — never on a PR | Gate                                    |
| `fast suites (Windows client)`                           | Push to `main` only — never on a PR; two runners, half the table     | Gate, but see below                     |

"Skipped on a workflow-only diff" is `changes.yml`: a PR that only touches
`.github/workflows/**` can't move those jobs' results, so they report
`skipped` instead of re-running. `workflow-lint` and `advisory-lint` are
exempt — a workflow-only change is exactly what the first audits, and a
docs-only change is exactly when the second should run.

"Gate" means the job itself fails loudly rather than reporting and continuing
— not that GitHub's merge button is blocked by it. No job on this list is a
configured required status check yet — requiring `fast suites
(ubuntu-latest)` would lift Scorecard's Branch-Protection score from 6 to 8 of
10, and its higher tiers need two reviewers a solo maintainer can't supply;
`fast suites (Windows client)`
carries no `continue-on-error`, so a red suite there fails that run, but it
doesn't stop a merge either way.

The rest of `.github/workflows/` — `release.yml`, `snapshot.yml`,
`pages.yml`, `codeql.yml`, `scorecard.yml`, `image-scan.yml`,
`tool-versions.yml`, `link-check.yml`, `demos.yml`, and the dispatch-only
`coverage.yml` and `coverage-v2.yml` (the kcov and bashcov aggregates,
published as shields endpoints) — run on a schedule, a push to `main`, a tag
or a manual dispatch, not on your pull request. `demos.yml` is the one partial
exception: it also runs on a PR that touches `docs/tapes/**`. Most report
through a self-closing tracking issue rather than a red run; each file's
header says why. `cancel-closed-pr.yml` runs once your PR is merged or
closed and cancels whatever of the above is still in flight for it.

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

## What 1.x will not break

The opposite of _experimental_, in force from the `v1.0.0` tag: these are the
interfaces a 1.x release keeps, and a change to any of them is a 2.0.

- **The eighteen flags in `common/flags`** — name, argument shape and what
  each needs (`-`, `scripts`, `tests`, `git`). New flags may arrive; none is
  renamed or removed. Anything hi does not answer still passes to `ssh`.
- **Every row of [SETTINGS.md](SETTINGS.md)'s _Every setting_ table** — name,
  type and default. A toggle that has to go **warns for one minor release**
  (`hi --doctor` and the session header both say so), then is removed in the
  next.
- **The overlay** — `$_HI_OVERLAY_FILES` (`settings.sh`, `colors`, `packages`,
  `vim.rc`, `nano.rc`, `aliases.sh` and the per-shell rc files), their
  formats, the XDG path and the `_HI_CONFIG_DIR` / `_HI_COLORS` /
  `_HI_PACKAGES` / `_HI_VIMRC` / `_HI_NANORC` overrides.
- **The installed layout** — `$_HI_HOME/say-hi` and
  `/etc/profile.d/say-hi.sh` for packages, the rc lines `install.sh` writes,
  and `_HI_RELEASE` as the version stamp `packaging/stamp.sh` fills.
- **Target behaviour** — nothing written outside the session directory by
  default, and the directory removed on any exit
  ([SECURITY.md](SECURITY.md#what-hi-writes-on-a-target)).

Versioning is semver: a fix is a patch, an addition a minor, a break to the
list above a major. Not covered: the exact header and prompt text, colors,
completion ordering, `--doctor`'s report shape, and anything under `tests/` or
`scripts/` a package does not ship.

## Which docs change with what

| you changed                           | update                                       |
| ------------------------------------- | -------------------------------------------- |
| a flag, or `_hi_parse`                | `docs/hi.1` and `docs/tldr.md`               |
| an environment variable or toggle     | `docs/SETTINGS.md` (enforced, see below)     |
| what hi leaves on a target            | `docs/SECURITY.md`                           |
| a target hi does or doesn't answer to | `docs/SUPPORT.md`                            |
| a new idiom worth a name              | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag |
| a release channel or the release flow | `docs/PACKAGING.md`                          |

Two rows are checked by the lint suite: a `GLOSSARY:` tag naming a missing
entry fails, and so does a toggle in `common/core.sh` with no row in
[SETTINGS.md](SETTINGS.md)'s _Every setting_ table. The rest are on your
honour and on review.

Markdown is formatted with prettier (`.prettierrc.yaml`; Zed does it on save,
`npx prettier --write '**/*.md'` by hand) and linted with markdownlint
(`.markdownlint.yaml`, advisory in CI). The two agree by construction, and
`.moxide.toml` keeps markdown-oxide from arguing with either.

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
