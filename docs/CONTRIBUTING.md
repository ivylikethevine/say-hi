# Contributing to say-hi

say-hi is [EXPERIMENTAL UNTIL v1.0.0](../README.md):
interfaces can still move, and [README's Roadmap](../README.md#roadmap) is
what is left to do. The test runbook is [docs/TESTING.md](TESTING.md); the
named idioms are [docs/GLOSSARY.md](GLOSSARY.md).

## Contents

- [Before you start](#before-you-start)
- [The gate](#the-gate)
  - [Don't reach for `act`](#dont-reach-for-act)
- [What CI runs](#what-ci-runs)
- [What a review will bounce on](#what-a-review-will-bounce-on)
- [What 1.x will not break](#what-1x-will-not-break)
- [Which docs change with what](#which-docs-change-with-what)
- [Opening the pull request](#opening-the-pull-request)
- [When a push is refused](#when-a-push-is-refused)
- [Governance](#governance)

## Before you start

**Check it isn't already decided.** [docs/SUPPORT.md](SUPPORT.md) holds a
verdict and a reason for every runtime, shell, and feature answered no,
[docs/PACKAGING.md](PACKAGING.md#channels-weighed-and-not-shipped) for every
packaging channel, and [docs/ALTERNATIVES.md](ALTERNATIVES.md) for the tools
say-hi is not trying to be. A "no" there is settled, not an oversight — though
a reason that has stopped being true is worth an issue, and a good
implementation would be considered.

**Anything exploitable goes to
[SECURITY.md](SECURITY.md#reporting-a-vulnerability)**, privately, not to a
public issue or pull request.

## The gate

```sh
tests/test_runner.sh --group fast
tests/test_runner.sh --group lint
```

That is what CI runs on every push; both should be green before you open the
pull request. If your change touches an ssh or container path, run the `e2e`
or `backends` group too and say in the pull request whether it ran or stood
down. What each group contains, and how a skip is reported, is
[docs/TESTING.md](TESTING.md#running-the-tests)'s job.

### Don't reach for `act`

[act](https://github.com/nektos/act) is **not** the way to check a change
here: its container runs as root, which fails fast-group cases a real runner
passes, and `--container-options "--user 1000"` doesn't rescue it. Run the
suites directly instead — and `actionlint -color` for the workflows, since
zizmor fails on act's empty `github.token`. `advisory-lint` is the one job
green under act, and every tool in it runs directly anyway; the macOS/Windows
jobs have no container to run in, and `bench`, `packaging-smoke`, and the two
`e2e` jobs want the Docker socket.

```sh
act -W .github/workflows/ci.yml -j advisory-lint -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

## What CI runs

Every job `ci.yml` runs on your pull request, and whether a red one fails the
run or only reports — sixteen workflow files is more than `ci.yml`'s per-job
comments are convenient to read through by eye.

| Job                                                 | Runs on your PR                                                     | Gate or advisory?                       |
| --------------------------------------------------- | ------------------------------------------------------------------- | --------------------------------------- |
| `fast suites (ubuntu-latest)`                       | Skipped on a workflow-only diff                                     | Gate                                    |
| `fast suites (ubuntu-24.04-arm)`                    | Skipped on a workflow-only diff                                     | Gate                                    |
| `lint suites (ubuntu-latest)`                       | Always                                                              | Gate                                    |
| `fast suites (macos-latest)`                        | Skipped on a workflow-only diff; same-repo PRs also `hi` itself     | Gate                                    |
| `fast suites (Alpine client)`                       | Skipped on a workflow-only diff                                     | Gate                                    |
| `workflow lint` (actionlint + zizmor)               | Always                                                              | Gate                                    |
| `advisory lint` (markdownlint, hadolint)            | Always                                                              | Advisory — reports, never fails the job |
| `hot-path benchmarks`                               | Always                                                              | Gate                                    |
| `hot-path profiles (timep)`                         | Skipped on a workflow-only diff                                     | Advisory — `continue-on-error`          |
| `package build (deb, rpm, apk)`                     | Skipped on a workflow-only diff                                     | Gate                                    |
| `e2e (ssh, docker)`                                 | Beside the fast suites; skipped on a workflow-only diff             | Gate                                    |
| `e2e (podman, nomad, kube)`                         | Beside the fast suites; skipped on a workflow-only diff             | Gate                                    |
| `e2e (Windows)` / `e2e (FreeBSD)` / `e2e (OpenBSD)` | Same-repo PRs and pushes to `main`, after both fast-suite jobs pass | Gate, but see below                     |
| `fast suites (Windows client)`                      | Same-repo PRs and pushes to `main`; four x64 and four arm64 runners | Gate, but see below                     |

Nothing runs on a draft: every job skips until the PR is marked ready, which
fires a full run. Until then GitHub lists both `fast suites` checks and both
`e2e` aggregates as Expected, since it never names the entries of a skipped
matrix job; a draft cannot merge either way.

"Skipped on a workflow-only diff" is `ci.yml`'s `changes` job: a PR that only touches
`.github/workflows/**` can't move those jobs' results, so they report
`skipped` instead of re-running. Every other job carries no `changes` guard
and runs on each push and ready pull request — a workflow-only change is exactly
what `workflow lint` audits, and a docs-only change is exactly when
`advisory lint` and the README-badge half of `hot-path benchmarks` should run.

None of it runs twice on the same code: the push that merges a same-repo PR
whose last run went green, and whose tree `main` still matches, finds that
run's `ci-tree-<tree>` marker and skips every job, and `carry-forward` puts
the run's badge artifacts and platform checks on the merged commit.
`coverage.yml` reuses the PR's figures the same way.

"Gate" means the job itself fails loudly rather than reporting and continuing
— not, on its own, that GitHub's merge button is blocked by it. `main`
requires seven of the jobs above before a merge: both `fast suites` jobs,
`lint suites (ubuntu-latest)`, `workflow lint`, `package build (deb, rpm,
apk)`, `e2e (ssh, docker)` and `e2e (podman, nomad, kube)` — every gate that
actually runs on a pull request, by its aggregate name rather than a
per-shard one, since the shard count is a knob. `e2e (Windows)` /
`e2e (FreeBSD)` / `e2e (OpenBSD)` and `fast suites (Windows client)` run on a
pull request only when its head branch lives in this repository: each stands
up an sshd and authorizes a throwaway key, which is not something to hand a
fork's PR (the first three sit behind `e2e-gate`; the macOS job's loopback
steps skip on a fork's PR for the same reason). They stay off the required
list for that reason — a fork PR would never report them and could never
merge. `fast suites (Alpine client)` and `fast suites (ubuntu-24.04-arm)`
are off it too, until they have a track record. On a same-repo PR they are real checks all the same: none carries
`continue-on-error`, so a red suite fails the run.

Every other file in `.github/workflows/` runs on a schedule, a push to
`main`, a tag, or a manual dispatch, never on your pull request, and most
report through a self-closing tracking issue rather than a red run; each
file's header says which and why. The exception is `cancel-closed-pr.yml`,
which runs once your PR is merged or closed and cancels whatever is still in
flight for it.

## What a review will bounce on

These are constraints the tree enforces, not requests:

- **Style follows the [Google Shell Style
  Guide](https://google.github.io/styleguide/shellguide.html), with the
  deviations this list and [GLOSSARY.md](GLOSSARY.md) spell out** — the bash
  3.2 floor and the dialect-constrained files below chief among them.
  `shellcheck` (`.shellcheckrc`) and `shfmt` (style from `.editorconfig`) are
  the enforcement, both required by `lint suites` in [What CI
  runs](#what-ci-runs); a style exception is a `# shellcheck disable=` comment
  at the line it covers, not a blanket suppression.
- **bash 3.2 is the floor.** No `mapfile`/`readarray`, associative arrays,
  namerefs, or `${x,,}`; the lint suite greps for all four. Every deliberately
  odd construct that forces is explained once in [GLOSSARY.md](GLOSSARY.md),
  and code points at it with a `GLOSSARY: HI.NN` tag — drift-checked, so an
  entry can't be deleted out from under them.
- **Several files are a smaller dialect than bash, and say so at the top.**
  `common/paths.sh` is the four-shell plain-`export` subset,
  `settings/aliases.sh` is POSIX+fish, `common/targets.sh` is standalone POSIX.
  The stated subset wins over anything cleaner.
- **Nothing may guess the tree from `$HOME`.** Each entry point derives it from
  its own path (`GLOSSARY: HI.33`). The lint sweep covers the docs too.
- **The payload is budgeted twice.** `common/`, `settings/`, `load.sh`, and
  `hi.sh` ship to every target; the gzipped tar and the assembled wire script
  are CI-enforced against separate numbers. Touch a shipped file, run
  `--group bench`, and check both. Tooling-only helpers do not belong in
  `common/core.sh`.
- **A new suite has a home and a registration** —
  [TESTING.md's _Where a suite lives_](TESTING.md#where-a-suite-lives).
- **A red `shfmt` is fixed on the paths it names**, not with `shfmt -w .`,
  which would also reformat `common/zsh.zsh` — zsh, not bash, and shipped.

## What 1.x will not break

The opposite of _experimental_, in force from the `v1.0.0` tag: these are the
interfaces a 1.x release keeps, and a change to any of them is a 2.0.

- **The twelve flags in `common/flags`** — name, argument shape, and what
  each needs (`-`, `scripts`, `git`). New flags may arrive; none is renamed
  or removed. Anything hi does not answer still passes to `ssh`.
- **The flag grammar** — `-h`/`-V` as the short forms of `--help`/`--version`,
  taking nothing after them; `--option=value` for every option whose first
  argument is a word (`--use`, `--preview`, `--update`), refused on the rest; every `--word` is hi's (an unknown one is
  hi's error); and everything after the target is the remote command.
- **The sub-command switches** — `--doctor --json`, `--install`'s
  `-y`/`--yes`, `--link {none,user,system}`, `--preset <name>`, and
  `-n`/`--dry-run`, `--uninstall --dry-run`, `--configure --preset <name>`
  and `--configure --dry-run`, `--update --dry-run`,
  `scripts/install.sh --prefix <dir>` — name and meaning (`-n` is the short
  form of `--dry-run` wherever it appears, `-y` of `--install --yes`; no
  other switch has one); and the `--json` document's top-level keys
  (`version`, `target`, `findings`, `rows`) with each row's four fields.
- **Exit status** — 0 for "did what it says", 1 for "hi refused before
  connecting" or "a finding", 64 and 65 for a target with neither `base64`
  nor `openssl`, or no scratch directory, and a connect's own status passed through.
- **Every row of [SETTINGS.md](SETTINGS.md)'s _Every setting_ table** — name
  and default (the type is what the row's prose says: `0`/`1`, a number, a
  word list, a name from a fixed set). A toggle that has to go is a 2.0. A
  new `_HI_DISABLE_*` toggle is a minor, and lands in `_HI_TOGGLES`,
  `config.fish`'s mirror, and `_HI_DISABLE_LOCAL`'s block in `common/paths.sh`
  together, or "all of the above" quietly stops meaning all of them.
- **The overlay** — `$_HI_OVERLAY_FILES` (`settings.sh`, `colors`, `packages`,
  `vim.rc`, `init.lua`, `nano.rc`, `emacs.el`, `aliases.sh`, the per-shell rc files,
  `oh-my-posh.json`, and the names starship's, eza's, and bat's own configs travel under), their
  formats, the XDG path, and the `_HI_CONFIG_DIR` override.
- **The installed layout** — `$_HI_HOME/say-hi` and
  `/etc/profile.d/say-hi.sh` for packages, the rc lines `install.sh` writes,
  and `_HI_RELEASE` as the version stamp `packaging/stamp.sh` fills.
- **Target behaviour** — nothing hi writes outside the session directory,
  and the directory removed on any exit
  ([SECURITY.md](SECURITY.md#what-hi-writes-on-a-target)).

Versioning is semver: a fix is a patch, an addition a minor, a break to the
list above a major. Not covered: the exact header and prompt text, colors,
completion ordering, the wording of any message or report row, `hi_info`,
the test levers [SETTINGS.md](SETTINGS.md#not-settings) lists, the `exa`
alias name and its `_HI_EXA_OPTS` row (exa has been archived since 2023; the
`ls`/`eza` names and the `_HI_LS_*` rows are the contract, and the exa half
may leave in a minor),
and anything under `tests/` or `scripts/` a package does not ship.

## Which docs change with what

| you changed                           | update                                       |
| ------------------------------------- | -------------------------------------------- |
| a flag, or `_hi_parse`                | `docs/hi.1` (and `docs/tldr.md` when one of its eight examples shows it) |
| an environment variable or toggle     | `docs/SETTINGS.md` (enforced, see below)     |
| what hi leaves on a target            | `docs/SECURITY.md`                           |
| a target hi does or doesn't answer to | `docs/SUPPORT.md`                            |
| a tool hi wires in, or its hook       | `docs/INTEGRATIONS.md`                       |
| a new idiom worth a name              | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag |
| a release channel or the release flow | `docs/PACKAGING.md`                          |
| the harness or the lint gate          | `docs/TESTING.md`                            |
| a new document under `docs/`          | `docs/README.md`'s index                     |
| a heading in a doc with a `Contents`  | that doc's `Contents` list (enforced)        |

Four rows are checked by the lint suite: a `GLOSSARY:` tag naming a missing
entry fails, so does a toggle in `common/core.sh` with no row in
[SETTINGS.md](SETTINGS.md)'s _Every setting_ table, so does a `docs/tldr.md`
example whose flag is not a `common/flags` row (or a ninth example), and so
does a heading with no `Contents` entry. The rest are on your honour and on
review.

Markdown is formatted with prettier (`.prettierrc.yaml`; Zed does it on save,
`npx prettier --write '**/*.md'` by hand) and linted with markdownlint
(`.markdownlint.yaml`, advisory in CI); the two agree by construction.

[README's Roadmap](../README.md#roadmap) is a to-do list, not a changelog:
finishing an entry means **deleting** it. What a _user_ reads is the pull
request's `## Release note` section (the template has it): `release.yml`
collects those from the PRs merged since the last tag
into the release body, titles as the fallback. Write it as the sentence you
would want on the release page, or `none` when nothing a user sees changes.

## Opening the pull request

- **Base it on `dev`** unless an issue says otherwise. `main` is protected: it
  takes pull requests from `dev`, and releases are built off it.
- **Simple, concise commits** — enough to see what is going on; the pull
  request body is where the detail lives.
- **Say if AI wrote part of it.** [README's AI Usage](../README.md#ai-usage) is
  the standard, and it applies to contributions: the tool is fine, and the code
  is still yours to have understood, reviewed, and stood behind.

## When a push is refused

Secret scanning and push protection are on for this repository; push
protection refuses the push outright, so the first thing you see is GitHub's
own error.

**That refusal is the guard working.** Take the credential out of the commit —
amend, or rewrite the branch — and push again. Do not force it and do not
bypass and clean up later: a secret that reaches the remote for even one push
is a secret to rotate. For a false positive, GitHub's error links the bypass
flow, which records why; take that route rather than reshaping the string.

Four credentials are handled by hand — the two signing keys, `AUR_SSH_KEY`, and
`HOMEBREW_TAP_TOKEN`, each generated locally, pasted into a settings page, and
deleted; [PACKAGING.md](PACKAGING.md) walks each. GitHub's scanner is used
rather than gitleaks or trufflehog because it runs on the push path, where a
third-party action cannot.

## Governance

Small on purpose, and written down so nobody has to guess:

- **One maintainer** — [ivylikethevine](https://github.com/ivylikethevine)
  owns the repository, reviews and merges every change, holds the release
  and signing keys, and makes final decisions on scope and direction (the
  model usually filed under BDFL). There are no other roles today; a
  recurring contributor who wants one starts a conversation in an issue.
- **Continuity** — everything needed to carry the project on is public: the
  tree is MIT-licensed, releases are reproducible from it
  ([PACKAGING.md](PACKAGING.md)), and nothing load-bearing lives outside
  this repository. If the maintainer goes permanently quiet, fork and carry
  on — the license is the succession plan.
- **Your certification** — by opening a pull request you certify that you
  wrote the contribution or otherwise have the right to submit it under the
  MIT license (the
  [Developer Certificate of Origin](https://developercertificate.org/), in
  spirit; no `Signed-off-by` line is required).
- **Sensitive access** — repository settings, secrets (signing and
  publishing keys) and the `release` environment are reachable by the
  maintainer alone; two-factor authentication is enabled on that account.
