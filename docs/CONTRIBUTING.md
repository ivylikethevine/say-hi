# Contributing to say-hi

say-hi is [EXPERIMENTAL UNTIL v1.0.0](../README.md#experimental-until-v100-stable-releases):
interfaces can still move, and [docs/ROADMAP.md](ROADMAP.md) is what is left
to do. The test runbook is [docs/TESTING.md](TESTING.md); the named idioms are
[docs/GLOSSARY.md](GLOSSARY.md).

## Contents

- [Before you start](#before-you-start)
- [The gate](#the-gate)
  - [Don't reach for `act`](#dont-reach-for-act)
- [What a review will bounce on](#what-a-review-will-bounce-on)
- [Which docs change with what](#which-docs-change-with-what)
- [Opening the pull request](#opening-the-pull-request)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## Before you start

**Check it isn't already decided.** [docs/UNSUPPORTED.md](UNSUPPORTED.md) holds
a verdict and a reason for every runtime, shell, packaging channel and feature
answered no; [docs/SUPPORTED.md](SUPPORTED.md) covers everything hi does reach;
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
drift checks). Both should be green before you open the pull request, and the
fast group's summary line is what the template asks you to paste.

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
want a workflow run anyway, `actionlint`, `hadolint` and
`markdownlint (advisory)` are green under act and are all linters you can run
directly; `zizmor` fails on act's empty `github.token`; the macOS/Windows jobs
have no container to run in; `bench`, `packaging-smoke` and the two `e2e` jobs
want the Docker socket and the self-hosted workspace.

```sh
act -W .github/workflows/ci.yml -j actionlint -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

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
| an environment variable or toggle     | `docs/CONFIGURATION.md` (enforced, see below) |
| what hi leaves on a target            | `docs/SECURITY.md`                            |
| a target hi does or doesn't answer to | `docs/SUPPORTED.md`, or `docs/UNSUPPORTED.md` |
| a new idiom worth a name              | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag  |
| a release channel or the release flow | `docs/PACKAGING.md`                           |

Two rows are checked by the lint suite: a `GLOSSARY:` tag naming a missing
entry fails, and so does a toggle in `common/core.sh` with no row in
[CONFIGURATION.md](CONFIGURATION.md)'s _Every setting_ table. The rest are on
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
