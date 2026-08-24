# Contributing to say-hi

[docs/TESTING.md](TESTING.md) - the test runbook and
[docs/GLOSSARY.md](GLOSSARY.md) - the named idioms

say-hi is [EXPERIMENTAL UNTIL v1.0.0](../README.md#experimental-until-v100-stable-releases).
Interfaces can still move, and [docs/ROADMAP.md](ROADMAP.md) is what is
left to do — including the entries that are deliberately not being done.

## Contents

- [Before you start](#before-you-start)
- [The gate](#the-gate)
- [What a review will bounce on](#what-a-review-will-bounce-on)
- [Which docs change with what](#which-docs-change-with-what)
- [Opening the pull request](#opening-the-pull-request)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## Before you start

- **Check it isn't already decided.** [docs/UNSUPPORTED.md](UNSUPPORTED.md)
  holds a verdict and a reason for every runtime, shell, packaging channel and
  feature answered no, and [docs/SUPPORTED.md](SUPPORTED.md) for everything hi
  does reach; [docs/ALTERNATIVES.md](ALTERNATIVES.md) does the same for the
  tools say-hi is not trying to be. A "no" there is a settled answer with its
  reasoning attached, not an oversight — though a reason that has stopped being
  true is worth an issue, and if a good implementation appears, I would consider it.

## The gate

```sh
tests/test_runner.sh --group fast
```

That is what CI runs on every push, and the lint suite is inside it — there is
no separate lint step to remember. `--group fast` should be green before you
open the pull request, and the summary line it prints is what the template asks
you to paste.

The `e2e` and `backends` groups need real backends — a reachable sshd, a docker
or podman socket, a nomad agent, a cluster — and stand down **yellow SKIPPED**
when they can't run, never green. If your change touches one of those paths, run
that group (`--group e2e`, `--group backends`, or the suite by name) and say in
the pull request whether it ran or skipped. `--require-run` turns a skip into a
failure when you want to be certain it really ran.

Everything else about the runner — the groups, `--skip`, the parallel container
cases, why the coverage figures are not to be trusted — is in
[docs/TESTING.md](TESTING.md).

## What a review will bounce on

These are the constraints the tree enforces rather than requests:

- **bash 3.2 is the floor.** No `mapfile`/`readarray`, no associative arrays, no
  namerefs, no `${x,,}` case conversion. macOS ships bash 3.2 and hi runs there,
  so the lint suite greps for all four. Every deliberately-odd construct that
  forces is explained once in [GLOSSARY.md](GLOSSARY.md), and code points
  at it with a `GLOSSARY: HI.NN` tag rather than re-explaining — those tags are
  drift-checked, so an entry can't be deleted out from under them.
- **Several files are a smaller dialect than bash, and say so at the top.**
  `common/paths.sh` is the four-shell plain-`export` subset, `misc/aliases.sh`
  is POSIX+fish, `common/targets.sh` is standalone POSIX. The stated subset wins
  over anything cleaner.
- **Nothing may guess the tree from `$HOME`.** Each entry point derives it from
  its own path (`GLOSSARY: HI.33`); a guessed tree is how a session ends up
  reading someone else's. The lint sweep covers the docs here too, since the
  docs teach the rule as much as the code obeys it.
- **The payload is budgeted twice.** `common/`, `misc/`, `shells/`, `load.sh`
  and `hi.sh` ship to every target, and both the gzipped tar and the assembled
  wire script are CI-enforced against separate numbers. If you touch a shipped
  file, run `--group bench` and check both. Tooling-only helpers do not belong
  in `common/core.sh`.
- **A new suite has a home and a registration.** It lives in `tests/<the
directory it tests>/`, sources the `tests/test_lib.sh` façade and nothing else
  (`GLOSSARY: HI.34`), and goes in `test_runner.sh`'s `_HI_TESTS` table — no
  group runs it otherwise.
- **A red `shfmt` is fixed on the paths it names**, not with `shfmt -w .`, which
  would also reformat `shells/zsh.zsh` — zsh, not bash, and shipped.

## Which docs change with what

Nothing here has a docs-only counterpart that can be skipped:

| you changed                           | update                                        |
| ------------------------------------- | --------------------------------------------- |
| a flag, or `_hi_parse`                | `docs/hi.1` and `docs/tldr.md`                |
| an environment variable or toggle     | `docs/CONFIGURATION.md`                       |
| what hi leaves on a target            | `docs/SECURITY.md`                            |
| a target hi does or doesn't answer to | `docs/SUPPORTED.md`, or `docs/UNSUPPORTED.md` |
| a new idiom worth a name              | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag  |
| a release channel or the release flow | `docs/PACKAGING.md`                           |

`docs/ROADMAP.md` is a to-do list, not a changelog: finishing an entry means
**deleting** it, since git history is the ledger.

## Opening the pull request

- **Base it on the dev branch** unless an issue says otherwise. `main` is
  protected: it takes pull requests from `dev`, and then releases are built off it.
  `dev` is where community input is merged and tested while preparing for
  new builds and releases.
- **Simple, concise commits**. Keep it simple, but allow some idea of what is
  going on. The Pull Request body is where the bullet point will live.
- **Say if AI wrote part of it.** [README's AI Usage](../README.md#ai-usage)
  statement is the standard the project holds itself to, and it applies to
  contributions: the tool is fine, and the code is still yours to have
  understood, reviewed and stood behind.

## Reporting a vulnerability

If you feel there is a critical security failing (keeping in mind this is, at its
heart, a shell script), please report it privately here: [docs/SECURITY.md](SECURITY.md#reporting-a-vulnerability)
