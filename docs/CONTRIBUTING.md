# Contributing to say-hi

say-hi is [EXPERIMENTAL UNTIL v1.0.0](../README.md): interfaces can still
move, and [README's Roadmap](../README.md#roadmap) is what is left to do. The
test runbook is [docs/TESTING.md](TESTING.md); the named idioms are
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
- [AI-assisted contributions](#ai-assisted-contributions)
- [When a push is refused](#when-a-push-is-refused)
- [Governance](#governance)

## Before you start

**Check it isn't already decided.** [docs/COMPATIBILITY.md](COMPATIBILITY.md)
holds a verdict and a reason for every runtime, shell, and feature answered
no, [docs/RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped) for
every packaging channel, and [docs/ALTERNATIVES.md](ALTERNATIVES.md) for the
tools say-hi is not trying to be. A "no" there is settled, not an oversight —
though a reason that has stopped being true is worth an issue.

**Develop on Linux.** Working on say-hi itself - packaging and publishing
above all, and the test suites around them - has only been tested thoroughly
on Linux, not on Windows, macOS, FreeBSD, or OpenBSD. hi itself runs on all
of them, and CI runs the fast suites on each; but the release tooling
(`packaging/`, `.github/scripts/`, and the `ci` group that checks them) runs
only on Ubuntu. On another host expect rough edges, and name the host in the
pull request.

**Anything exploitable goes to
[SECURITY.md](SECURITY.md#reporting-a-vulnerability)**, privately, not to a
public issue or pull request.

## The gate

```sh
npm ci --prefix .github   # once, or the lint group skips its Markdown checks
tests/test_runner.sh --group fast
tests/test_runner.sh --group lint
```

CI runs both on every push; both should be green before you open the pull
request. If your change touches an ssh or container path, run the `e2e` or
`backends` group too and say in the pull request whether it ran or stood down.
What each group contains, and how a skip is reported, is
[docs/TESTING.md](TESTING.md#running-the-tests)'s job.

### Don't reach for `act`

[act](https://github.com/nektos/act) is **not** the way to check a change
here: its container runs as root, which fails fast-group cases a real runner
passes (`--container-options "--user 1000"` doesn't rescue it), zizmor fails on
its empty `github.token`, and the macOS, Windows, and Docker-socket jobs have
nowhere to run. Run the suites directly, and `actionlint -color` for the
workflows.

## What CI runs

Every check on your pull request, and whether a red one fails the run or only
reports. All but the last four rows are `ci.yml`'s.

| Job                                                                     | Runs on your PR                                                            | Gate or advisory?                                                |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `fast suites (ubuntu-latest)`                                           | Skipped on a workflow- or docs-only diff; the `ci` group runs here only    | Gate                                                             |
| `fast suites (ubuntu-24.04-arm)`                                        | Skipped on a workflow- or docs-only diff                                   | Gate                                                             |
| `lint suites (ubuntu-latest)` (the lint group, markdownlint + prettier) | Always                                                                     | Gate                                                             |
| `fast suites (macos-latest)`                                            | Skipped on a workflow- or docs-only diff; same-repo PRs also ssh to itself | Gate                                                             |
| `fast suites (Alpine client)`                                           | Skipped on a workflow- or docs-only diff                                   | Gate                                                             |
| `workflow lint` (actionlint + zizmor)                                   | Always                                                                     | Gate                                                             |
| `secret scan (gitleaks)`                                                | Always; the full history, findings redacted                                | Gate                                                             |
| `advisory lint` (hadolint)                                              | Always                                                                     | Advisory — reports, never fails the job                          |
| `hot-path benchmarks`                                                   | Always                                                                     | Gate                                                             |
| `hot-path profiles (timep)`                                             | Skipped on a workflow- or docs-only diff                                   | Advisory — `continue-on-error`                                   |
| `package build (deb, rpm, apk)`                                         | Skipped on a workflow- or docs-only diff                                   | Gate                                                             |
| `e2e (ssh, docker)`                                                     | Beside the fast suites; skipped on a workflow- or docs-only diff           | Gate                                                             |
| `e2e (podman, nomad, kube)`                                             | Beside the fast suites; skipped on a workflow- or docs-only diff           | Gate                                                             |
| `e2e (Windows)` / `e2e (FreeBSD)` / `e2e (OpenBSD)`                     | Same-repo PRs, after both ubuntu fast-suite jobs pass                      | Gate, but see below                                              |
| `fast suites (Windows client)`                                          | Same-repo PRs, skipped on a workflow- or docs-only diff; eight runners     | Gate, but see below                                              |
| `release note (pr body)` (`release-note.yml`)                           | Every body edit and push; Dependabot's PRs skip                            | Gate                                                             |
| `dependency review` (`dependency-review.yml`)                           | Always; fails on a new dependency with a high or critical advisory         | Gate                                                             |
| `CodeQL (actions)` (`codeql.yml`)                                       | Always                                                                     | Blocks a merge on a high alert (`main`'s ruleset)                |
| `coverage.yml`'s kcov and bashcov sweep                                 | Same-repo PRs; posts both figures as a comment                             | Advisory — never blocks a PR; a failed suite publishes no figure |

Nothing runs on a draft: every job skips until the PR is marked ready, which
fires a full run. "Skipped on a workflow- or docs-only diff" is `ci.yml`'s
`changes` job: a PR touching only `.github/workflows/**` or Markdown can't move
those results. The "Always" jobs are the ones such a diff can: a new action
arrives through a workflow, and a docs change is what `lint suites`
(markdownlint, prettier, and lychee's offline link and `#fragment` check) and
the README-badge half of `hot-path benchmarks` read. `dependency review` diffs
a PR's base against its head, so it runs on pull requests only.

None of it runs twice on the same code: a push to `main` whose tree a
same-repo PR's green run already tested finds that run's `ci-tree-<tree>`
marker and skips every job, and `detect changes` puts the run's badge
artifacts and platform checks on the merged commit. `coverage.yml` reuses the PR's
figures the same way.

"Gate" means the job fails loudly rather than reporting and continuing — not,
on its own, that it blocks the merge button. `main`'s ruleset requires six
checks, on a branch up to date with `main`: `fast suites (ubuntu-latest)`,
`fast suites (macos-latest)`, `lint suites (ubuntu-latest)`,
`package build (deb, rpm, apk)`, `e2e (ssh, docker)`, and
`e2e (podman, nomad, kube)` — the e2e pair by aggregate name, since the shard
count is a knob — plus CodeQL reporting no high-or-higher alert.
`workflow lint`, `secret scan (gitleaks)`, `dependency review`, and
`release note (pr body)` belong on that list under exactly those names; until
then each still fails its run.

`e2e (Windows)`, `e2e (FreeBSD)`, `e2e (OpenBSD)`, and
`fast suites (Windows client)` run on a pull request only when its head branch
lives in this repository: each stands up an sshd and authorizes a throwaway
key, which is not something to hand a fork's PR (the first three sit behind
`e2e-gate`; the macOS job's loopback steps skip on a fork for the same reason).
A fork's PR would never report them, so they stay off the required list;
`fast suites (Alpine client)` and `fast suites (ubuntu-24.04-arm)` are off it
until they have a track record. None carries `continue-on-error`, so a red one
still fails the run.

Every other workflow runs on a schedule, after CI on `main`, on a tag, or on
dispatch, never on your pull request — except `cancel-closed-pr.yml`, which
cancels a merged or closed PR's in-flight runs. Each file's header says when
it runs and how it reports.

## What a review will bounce on

These are constraints the tree enforces, not requests:

- **Style follows the [Google Shell Style
  Guide](https://google.github.io/styleguide/shellguide.html)**, with the
  deviations this list and [GLOSSARY.md](GLOSSARY.md) spell out. `shellcheck`
  (`.shellcheckrc`) and `shfmt` (style from `.editorconfig`) enforce it in
  `lint suites`; a style exception is a `# shellcheck disable=` comment at the
  line it covers, not a blanket suppression.
- **bash 3.2 is the floor.** No `mapfile`/`readarray`, associative arrays,
  namerefs, or `${x,,}`; the lint suite greps for all four. Every deliberately
  odd construct that forces is explained once in [GLOSSARY.md](GLOSSARY.md),
  and code points at it with a `GLOSSARY: HI.NN` tag — drift-checked, so an
  entry can't be deleted out from under them.
- **A command is spelled the way every target runs it** —
  [SYNTAX.md](SYNTAX.md) lists each spelling that has cost a CI round trip
  (`sed -E`, not `sed -r` or `sed -i`; `printf`, not `echo -e`; no `grep -q`
  on a pipe under `pipefail`), and `drift` fails the build on the ones a
  pattern can see.
- **Several files are a smaller dialect than bash, and say so at the top.**
  `common/paths.sh` is the four-shell plain-`export` subset,
  `config/aliases.sh` what bash, zsh, and fish all parse, and
  `common/targets.sh` standalone POSIX. The stated subset wins over anything
  cleaner.
- **Nothing may guess the tree from `$HOME`.** Each entry point derives it from
  its own path (`GLOSSARY: HI.33`). The lint sweep covers the docs too.
- **The payload is budgeted twice.** `common/`, `config/`, `load.sh`, and
  `hi.sh` ship to every target; the gzipped tar and the assembled wire script
  are CI-enforced against separate numbers. Touch a shipped file, run
  `--group bench`, and check both; when README's payload badge goes red,
  `packaging/stamp_badge.sh` restamps it. Tooling-only helpers do not belong in
  `common/core.sh`.
- **A new suite has a home and a registration** —
  [TESTING.md's _Where a suite lives_](TESTING.md#where-a-suite-lives).
- **A red `shfmt` is fixed on the paths it names**, not with `shfmt -w .`,
  which would also reformat `common/zsh.zsh` — zsh, not bash, and shipped.
- **Every workflow job starts with `step-security/harden-runner`**
  (`egress-policy: block` with an allowlist taken from a real run's audit log
  on every Ubuntu job; `audit` only where there is no block mode - macOS and
  Windows - and on `link-check.yml`, whose job is reaching any URL; a Linux
  arm64 job goes without, having no agent) and
  sets `timeout-minutes`. Beside it: third-party actions pinned to a full SHA
  with a `# vX.Y.Z` comment, every checkout with `persist-credentials: false`,
  least-privilege `permissions:`, and untrusted input passed through `env:`
  rather than an inline expression in a `run:`. The `packaging_ci` suite
  and `workflow lint` enforce them.

## What 1.x will not break

The opposite of _experimental_, in force from the `v1.0.0` tag: these are the
interfaces a 1.x release keeps, and a change to any of them is a 2.0.

- **The fourteen flags in `common/flags`** — name, argument shape, and what
  each needs (`-`, `scripts`, `git`). New flags may arrive; none is renamed
  or removed. Anything hi does not answer still passes to `ssh`.
- **The flag grammar** — `-h`/`-V` as the short forms of `--help`/`--version`,
  taking nothing after them; `--option=value` for every option whose first
  argument is a word (`--use`, `--preview`, `--update`), refused on the rest;
  every `--word` is hi's (an unknown one is hi's error); and everything after
  the target is the remote command.
- **The sub-command switches** — `--doctor --json` and
  `--doctor --problems`, `--install`'s
  `-y`/`--yes`, `--link {none,user,system}`, `--preset <name>`, and
  `-n`/`--dry-run`, `--uninstall --purge` and `--uninstall --dry-run`,
  `--configure --preset <name>` and `--configure --dry-run`,
  `--update --dry-run`, `--add-package --dry-run`, `--add-tag --dry-run`,
  `scripts/install.sh --prefix <dir>` — name and meaning
  (`-n` is the short form of `--dry-run` wherever it appears, `-y` of
  `--install --yes`; no other switch has one); and the `--json` document's
  top-level keys (`version`, `target`, `findings`, `rows`) with each row's four
  fields.
- **Exit status** — 0 for "did what it says", 1 for "hi refused before
  connecting" or "a finding", and a connect's own status passed through (a
  target hi cannot boot gets its own plain session, not an exit status).
- **Every row of [SETTINGS.md](SETTINGS.md)'s _Every setting_ table** — name
  and default (the type is what the row's prose says: `0`/`1`, a number, a
  word list, a name from a fixed set). A toggle that has to go is a 2.0. A
  new `_HI_DISABLE_*` toggle is a minor, and lands in `_HI_TOGGLES`,
  `config.fish`'s mirror, and `_HI_DISABLE_LOCAL`'s block in `common/paths.sh`
  together, or "all of the above" quietly stops meaning all of them.
- **The overlay** — `$_HI_OVERLAY_FILES` (`settings.sh`, `colors`,
  `packages`, `plugins.d/` and its hook names,
  `vimrc`, `init.lua`, `config.toml`, `nanorc`, `init.el`, `tmux.conf`,
  `screenrc`, `micro/`'s `settings.json`/`bindings.json`/`init.lua`,
  `zellij/`'s `config.kdl`/`layouts/`/`themes/`, `aliases.sh`,
  `bashrc`, `zshrc`, `config.fish`, `oh-my-posh.json`/`.yaml`/`.toml`,
  `starship.toml`, `p10k.zsh`, `oh-my-zsh.zsh-theme`, `oh-my-bash.theme.sh`,
  `bash-it.theme.bash`, `tide.vars`, `theme.yml`, `bat.conf`, and
  `ssh_tags`), their
  formats, the XDG path, and the
  `_HI_CONFIG_DIR` override. The rule behind the names: a member is called
  what its tool calls the file where the tool has a fixed name, and carries
  the tool's name and extension where it has none.
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
may leave in a minor), and anything under `tests/` or `scripts/` a package
does not ship.

## Which docs change with what

| you changed                                            | update                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------------ |
| a flag, or `_hi_parse`                                 | `docs/hi.1` (and `docs/tldr.md` when one of its eight examples shows it) |
| an environment variable or toggle                      | `docs/SETTINGS.md` (enforced)                                            |
| what hi leaves on a target                             | `docs/SECURITY.md`                                                       |
| a target hi does or doesn't answer to                  | `docs/COMPATIBILITY.md`                                                  |
| a tool hi wires in, or its hook                        | `docs/INTEGRATIONS.md`                                                   |
| a color: the hash, a pin, the scheme, the package ramp | `docs/COLORS.md`                                                         |
| the transport, the payload, or the session's lifecycle | `docs/HOW-IT-WORKS.md`                                                   |
| a new idiom worth a name                               | `docs/GLOSSARY.md`, plus the `GLOSSARY:` tag (enforced)                  |
| how a user installs or verifies a package              | `docs/PACKAGING.md`                                                      |
| a release channel or the release flow                  | `docs/RELEASING.md`                                                      |
| the harness or the lint gate                           | `docs/TESTING.md`                                                        |
| a new document under `docs/`                           | `docs/README.md`'s index                                                 |
| a heading in a doc with a `Contents`                   | that doc's `Contents` list (enforced)                                    |

"Enforced" is the lint suite, alongside a `docs/tldr.md` example whose flag is
not a `common/flags` row, or a ninth example; the rest are on your honour and
on review.

Markdown is formatted with prettier (`.prettierrc.yaml`; Zed does it on save,
`.github/node_modules/.bin/prettier --write <files>` by hand) and linted with
markdownlint (`.markdownlint.yaml`); the two agree by construction. A link from
a page the site builds into a path the site leaves out (a dot-path such as
`.github/`, or anything `_config.yml` excludes) is an absolute github.com URL,
or it 404s on Pages; the lint group checks that too.

[README's Roadmap](../README.md#roadmap) is a to-do list, not a changelog:
finishing an entry means **deleting** it. What a _user_ reads is the pull
request's `## Release note` section (the template has it), which
[`release.yml` collects into the release body](RELEASING.md#cutting-a-release):
write the sentence you would want on the release page, or `none` when nothing
a user sees changes. `release note (pr body)` fails a body with no such
section, or an empty one. There is deliberately no `CHANGELOG` file: it would
be a second copy of those notes to keep in step by hand.

## Opening the pull request

- **Base it on `dev`** unless an issue says otherwise. `main` is protected: it
  takes pull requests from `dev`, and releases are built off it.
- **Simple, concise commits** — enough to see what is going on; the pull
  request body is where the detail lives.
- **Say if AI wrote part of it**, in the template's AI disclosure.

## AI-assisted contributions

Generative AI is allowed here, for contributions exactly as for the
maintainer's own work ([README's AI usage](../README.md#ai-usage)). The tool is
fine; the change is still yours. Tick the pull request template's AI
disclosure when a tool wrote part of it, and only open the pull request once
you have understood, reviewed, and can stand behind every line as if you had
written it by hand. "The agent said so" is not an answer to a review comment.

## When a push is refused

Secret scanning and push protection are on for this repository; push
protection refuses the push outright, so the first thing you see is GitHub's
own error.

**That refusal is the guard working.** Take the credential out of the commit —
amend, or rewrite the branch — and push again. Do not force it and do not
bypass and clean up later: a secret that reaches the remote for even one push
is a secret to rotate. For a false positive, GitHub's error links the bypass
flow, which records why; take that route rather than reshaping the string.

Five credentials are handled by hand — the three signing keys, `AUR_SSH_KEY`,
and `HOMEBREW_TAP_TOKEN`, each generated locally, pasted into a settings page,
and deleted; [RELEASING.md](RELEASING.md#the-release-environment) walks each.
Push protection is the guard because it runs on the push path, where no action
can; behind it, `secret scan (gitleaks)` sweeps the full history for anything
that got past.

## Governance

Who decides, the roles, contributor certification, and continuity are
[docs/GOVERNANCE.md](GOVERNANCE.md).
