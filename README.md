# hi.sh -> sshrc supercharged

---

## EXPERIMENTAL UNTIL v1.0.0-stable RELEASES

A hobby project in active development: interfaces can still move, and the
current state is not a representation of final, published quality.

---

<!-- CI status. macOS/Windows/FreeBSD/Windows-client are workflow_call targets
     invoked from ci.yml, so a badge naming the workflow file itself
     (img.shields.io/github/actions/workflow/status/.../macos-e2e.yml) reads
     that workflow's own run list - which workflow_call invocations never
     enter; only that file's stray workflow_dispatch runs do, so the badge
     shows the last manual dispatch, sometimes months stale, never the last
     real CI run. Each call still shows up as its own check-run on the commit
     ci.yml ran against, under "<ci.yml job name> / <called workflow's job
     name>" (GitHub composes that name; both halves are plain `name:` keys in
     ci.yml and the called file, so a rename on either side has to be mirrored
     into the nameFilter below or the badge goes to "no check runs"). The
     four badges below read that instead: img.shields.io/github/check-runs,
     filtered by that exact compound name - live per-job status from the
     actual CI run, not a shields.io feature specific to reusable workflows.
     The release badge deliberately omits include_prereleases: every push to
     main publishes its own `snapshot-<sha>` prerelease (snapshot.yml), and
     the badge should name the last real tag, not that. -->

![requires](https://img.shields.io/badge/requires-ssh%20%2B%20base64-0A6E8A)
![ssh payload](https://img.shields.io/badge/ssh_payload-48KB_per_session-4c1)
![code size](https://img.shields.io/github/languages/code-size/ivylikethevine/say-hi)
[![Linux](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/ci.yml?branch=main&label=Linux)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28macOS%29%20%2F%20hi%20localhost%20%28BSD%20both%20ends%29&label=macOS)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![FreeBSD](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28FreeBSD%29%20%2F%20hi%20localhost%20%28FreeBSD%20both%20ends%29&label=FreeBSD)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![Windows](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28Windows%29%20%2F%20hi%20at%20stock%20Windows%20OpenSSH%20%28PowerShell%20fallback%29&label=Windows)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![Windows MSYS2](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=fast%20suites%20%28Windows%20client%29%20%2F%20fast%20suites%20%28Git%20Bash%29&label=Windows%20client)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/codeql.yml?branch=main&label=CodeQL)](https://github.com/ivylikethevine/say-hi/actions/workflows/codeql.yml)
![license](https://img.shields.io/badge/license-MIT-blue)
[![release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases)
[![downloads](https://img.shields.io/github/downloads/ivylikethevine/say-hi/total)](https://github.com/ivylikethevine/say-hi/releases)
[![Repology](https://repology.org/badge/tiny-repos/say-hi.svg)](https://repology.org/project/say-hi/versions)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
<!-- [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/<ID>/badge)](https://www.bestpractices.dev/projects/<ID>) -->
<!-- [![OpenSSF Baseline](https://www.bestpractices.dev/projects/<ID>/baseline)](https://www.bestpractices.dev/projects/<ID>) -->

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

![hi into a container: the header and its package check, the git segment inside a checkout on the target, cat through the box's bat, and the empty /tmp it leaves behind](docs/tapes/demo.gif)

## In sixty seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi
~/say-hi/scripts/install.sh    # wires your rc files, asks about each feature
exec $SHELL                    # reload
hi some-host                   # ssh, with your prompt, aliases and editors along
```

`hi <name>` takes anything `ssh` takes — plus a running docker/podman
container, a nomad allocation or a kubernetes pod by name — lands you in a
session that looks like your own shell, and removes every trace when you
leave. `hi <TAB>` lists all of them. Nothing is installed on the far end.

`hi <name> <command ...>` runs one command instead, **inside** that session —
so it has hi's aliases and environment, and it runs on a pty when your stdin is
one. Only the command's output goes to stdout. When you want a plain,
pty-free remote command, that is still `ssh`'s job.

## Contents

- [What comes with you](#what-comes-with-you)
  - [the header tells you what the box is missing](#the-header-tells-you-what-the-box-is-missing)
  - [your editors, your clipboard](#your-editors-your-clipboard)
  - [no target at all — recent first](#no-target-at-all--recent-first)
  - [one config directory, every host, every shell](#one-config-directory-every-host-every-shell)
  - [know where you are at a glance](#know-where-you-are-at-a-glance)
  - [completion, every backend at once](#completion-every-backend-at-once)
  - [one command, every backend](#one-command-every-backend)
- [Requirements](#requirements)
- [Installation/Usage](#installationusage)
- [Configuration](#configuration)
  - [Hostname, username, and group/tag colors](#hostname-username-and-grouptag-colors)
- [Built from/with/in mind](#built-fromwithin-mind)
  - [Docker / Podman containers](#docker--podman-containers)
  - [Nomad allocations](#nomad-allocations)
  - [Kubernetes pods](#kubernetes-pods)
  - [Windows hosts](#windows-hosts)
- [say-hi and the alternatives](#say-hi-and-the-alternatives)
  - [Compatibility](#compatibility)
- [Testing](#testing)
  - [Coverage and Profiling](#coverage-and-profiling)
- [More docs](#more-docs)
- [AI Usage](#ai-usage)

## What comes with you

Every GIF here shows one thing hi brings along, not one place it can reach —
the backends (ssh, docker, podman, nomad, kubernetes) are spread across the
set so each is still on screen somewhere, and the client shell changes with
the theme (bash warm, zsh and fish cool). The GIF at the top is the stock
defaults; each one below turns something on or ships something of its own.
How they are rendered is in
[docs/PACKAGING.md](docs/PACKAGING.md#regenerating-the-demo-gifs).

### the header tells you what the box is missing

A `packages` overlay of the tools you care about, with a priority each, and
the header's check reads it on every target: one quiet line on a box that has
them, a loud one on a box that does not. Client: bash, into two docker
containers. Showing a `packages` overlay and `_HI_PACKAGES_MIN_PRIORITY=3`.

![hi's header package check on a box with the tools installed, then on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### your editors, your clipboard

`nano` opens with hi's nanorc and `vim` with hi's vimrc on a box that has
neither; `hi_copy` puts a target's output on _your_ clipboard and `hi_notify`
raises a desktop notification in _your_ terminal when a command finishes —
both ride the pty back as escapes, so nothing is installed or running on the
target. Client: zsh, into a docker container. (The two escapes go to the
terminal emulator, which a recording cannot show — the comments say where
each landed.)

![nano and vim with hi's rc files inside a session, then hi_copy and hi_notify](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### no target at all — recent first

`hi` on its own does not fall through to ssh's usage message: it offers the
list, backend-tagged and most-used-and-most-recent first, and connects to what
you pick — so the box you were on last is the top row, and Enter takes it.
`fzf` or `sk` if you have one, a numbered menu if you do not; it runs on the
client and never reaches a target, and a `hi` in a script or a CI job still
fails the way it always has rather than waiting on a menu nobody can answer.
Client: bash, into a docker container. Showing `_HI_RECENT` (on by default).

![bare hi offering its target list through fzf with the most recent target on top, then landing a session in it](https://ivylikethevine.github.io/say-hi/docs/tapes/pick.gif)

### one config directory, every host, every shell

`~/.config/say-hi/` ships to every target. An alias in its `aliases.sh` works
in a bash session on a debian container and in a fish session on an alpine
box — reached through docker and podman, from a fish client, so no two of
client, target shell and backend match. Client: fish. Showing an `aliases.sh`
overlay with one alias and `_HI_BAT_OPTS`, and `_HI_SHELL_PREFERENCE=fish` for
the second target. (A box with no bash at all gets the aliases-only tier,
which carries hi's own aliases but not the overlay — see
[Compatibility](#compatibility).)

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on a fish-only alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### know where you are at a glance

`# Tags:` lines in `~/.ssh/config`, a `colors` overlay pinning each tag, and
`hi --color-preview` to see what every host resolves to — then a prod host
lands in red and a dev host in green (`-F` for the same reason as the loop
below: the recording's ssh config is a throwaway). The targets carry their own `~/say-hi`
(the permanent-install path: nothing ships over the wire, and each reads its
own config, which is why their headers are shorter). Client: bash, into two
ssh hosts. Showing a `colors` overlay with `hosttag` pins.

![hi --color-preview, then hi into a prod-tagged host with a red prompt and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### completion, every backend at once

`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation and pod, each tagged with its backend.
Targets you connect to most, and most recently, come first (zsh and fish keep
that order; `_HI_RECENT=0` turns it off).
`hi --<TAB>` answers hi's own flags without probing any backend. Client: fish,
for the description column its pager gives every row. Showing
`_HI_TARGETS_TTL=0`, so the sweep is never served from cache.

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

The list stops at eleven rows because fish hands its pager half the screen —
that is completion behaving normally, not the GIF cut short.

### one command, every backend

`hi <name> <command>` runs one command inside the session — with hi's aliases
and environment — and only its output comes back. The same loop over an ssh
host, a docker container, a nomad allocation and a kubernetes pod (the `-F` is
ssh's, passed through unchanged, because the recording's ssh config is a
throwaway rather than the renderer's own). The pod is busybox
`ash` with no bash at all, which is hi's aliases-only tier — hi says so, once,
and runs the command anyway. Client: zsh.

![a for loop running hi target cat over an ssh host, a docker container, a nomad allocation and a kubernetes pod](https://ivylikethevine.github.io/say-hi/docs/tapes/run.gif)

## Requirements

- **Client**: `bash` 3.2+ and `base64` (armors the payload through the login
  shell; coreutils, busybox, macOS/BSD and Git Bash all ship one), plus
  `ssh` itself for ssh targets and
  `docker`/`podman`/`nomad`/`kubectl` for those backends. hi never speaks a
  protocol of its own — `ssh` is the transport, and `base64` is armor, not
  crypto ([docs/SECURITY.md](docs/SECURITY.md)).
- **Target**: `base64` for ssh targets; nothing extra for container/alloc/pod
  targets. `bash` gets the full experience; without it `hi` lands you in the
  best shell the target has, with a smaller session — see
  [Compatibility](#compatibility).
- **The other two shells** hi styles have floors of their own — **fish 3.7+**
  (Ubuntu 24.04's) and **zsh 5.8+** (Debian oldstable's) — and the lint gate
  checks both inside a pinned container on every run rather than claiming
  them ([docs/TESTING.md](docs/TESTING.md#the-lint-gate)).
- **bash 3.2** is the floor on both ends (macOS still ships it), so hi uses no
  bash-4-only construct: no `mapfile`/`readarray` (`_hi_read_lines` in
  `common/core.sh` does that job), associative arrays, namerefs or `${x,,}`.
  `tests/lint/drift_test.sh` greps for those, and `tests/targets/ssh_test.sh`
  runs a real bash 3.2 target.
- Everything else is plain POSIX/bash/zsh/fish — no compiled artifacts, no
  package manager, no build step.

## Installation/Usage

- `say-hi/scripts/install.sh`, or `hi --install` once hi is on your `PATH`.
  Before touching `~/.bashrc`, `~/.zshrc` or `~/.config/fish/config.fish` it
  validates each with that shell's own syntax checker and asks whether to
  continue if any has issues.
- reload your shell!
- `hi --configure` revisits the settings in short sections, starting from a
  preset if you like (`everything`, `balanced`, `minimal`;
  `--preset <name>` applies one without asking) — features (header,
  prompt, git status, editors, clipboard, notifications, prompt marks, and
  whether hi styles this machine too), header details, package-check depth,
  terminal width, the prompt (starship deference, separators), and an
  _advanced_ section you can skip with one Enter (session shell, glyphs vs
  ASCII, TERM fallback, recent targets, completion timing) — without touching
  the rc wiring. Every question says what it is set to now and previews what
  it decides where it can; Enter keeps the current answer; nothing is written
  until the end, and the run closes with what changed. Answers land in
  `~/.config/say-hi/settings.sh` (see [Configuration](#configuration)).
- `hi --check-configs` re-runs just the rc validation, and parses the overlay's
  shell files too (`aliases.sh` under both `sh` and `fish`, since every target
  sources it in whichever shell it lands in).
- `hi --overlay-init` puts `~/.config/say-hi` under git _in place_; from then
  on `hi --configure` commits its own writes. Optional — see
  [docs/SETTINGS.md](docs/SETTINGS.md).
- `hi --help` (or `-h`): the synopsis, the target resolution order, and every
  flag hi answers itself; `man hi` is the long version. Anything hi does not
  answer passes to `ssh` unchanged.
- `hi --version`: the packaged version, or `git describe` in a checkout.
- `hi --doctor [<target>]` when something is slow or failing: the tree, the
  config overlay, every backend probed and timed with the same ceilings the
  header and completion use, and — with a target — which backend it resolves
  to plus an ssh reachability check. All read-only. `--json` prints the same
  rows as one JSON document — what a bug report should carry.
- TAB: `hi <TAB>` completes every target, `hi --<TAB>` completes hi's flags.
  bash, zsh and fish read the same list (`common/targets.sh`), so the three
  cannot drift. GIF above: [completion](#completion-every-backend-at-once).
- `hi` on its own offers that same list and connects to what you pick — `fzf`
  or `sk` if you have one, a numbered menu if not. GIF above:
  [no target at all](#no-target-at-all--recent-first).
- configure `~/.ssh/config` tags via sshm
- [optional] pin colors in `~/.config/say-hi/colors` (copy
  `say-hi/settings/colors` to start); `hi --color-preview` shows what every
  ssh host and your user resolve to.
- [optional] copy `say-hi/settings/packages` to `~/.config/say-hi/packages`
  and edit; `hi --packages-preview` shows what each priority and mode
  character (`-` speaks only when missing, `+` only when installed) means and
  the check as a connect will print it.
- [optional] either of those files can live somewhere else instead —
  `export _HI_COLORS=~/dotfiles/hi-colors` in `settings.sh` moves that one file
  without moving the rest of the overlay (`_HI_PACKAGES`, `_HI_VIMRC` and
  `_HI_NANORC` likewise); see
  [docs/SETTINGS.md](docs/SETTINGS.md#pointing-one-file-somewhere-else).
- done with it? `say-hi/scripts/uninstall.sh`, or `hi --uninstall`, strips
  hi's lines from your rc files, removes the `settings.sh` it wrote, and
  unlinks `/usr/bin/hi`. It leaves the `say-hi` directory and your
  `colors`/`packages` alone.

Usage: `hi foo` (just like ssh!)

## Configuration

Your config lives **outside the checkout**, in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/`, and rides along to every host you
say `hi` to. `colors` and `packages` overlay the tree's copies, `aliases.sh`
adds to the shipped alias set, and a `bash.sh`/`zsh.zsh`/`config.fish` there
is sourced at the end of hi's own per-shell rc so yours win. `settings.sh`
(what `hi --configure` writes) has no in-tree counterpart. The overlay file
table, every toggle and every environment variable hi reads are in
[docs/SETTINGS.md](docs/SETTINGS.md); how a session gets to the
target is [How it works](docs/SETTINGS.md#how-it-works) there.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`,
`~/.config/fish/config.fish`, etc. — anything in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` is copied to every host you say
`hi` to. Treat every file in it as readable by every host you visit: a token,
an internal hostname or a private path in your `aliases.sh` lands on each of
them. See [docs/SECURITY.md](docs/SECURITY.md)._**

By default hi writes nothing to a target outside its own temp directory — not
your login files, not your shell history. The two settings that change that
are opt-in and spelled out in
[What hi writes on a target](docs/SECURITY.md#what-hi-writes-on-a-target).

### Hostname, username, and group/tag colors

Every username and hostname gets a color derived from its name. To pin one,
add a line to `~/.config/say-hi/colors`: `username,root,red`,
`hostname,prod-db,yellow` or `hosttag,desktop,green`. `hosttag` matches the
_leftmost_ tag in a `# Tags: ...` comment directly above a `Host` or
`Match host` line in `~/.ssh/config`; a wildcard block (`Host prod-*`) tags
every name it covers. `hi --color-preview` shows the result in the actual
colors. The long version, and using the hash in your own prompt, is
[docs/SETTINGS.md](docs/SETTINGS.md#colors).

## Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) — _from_ — (became `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) — _with_ — (optional, but _highly_
  recommended to configure `~/.ssh/config` hosttags)
- [bat](https://github.com/sharkdp/bat) — _in mind_ — (essentially my reason to
  get the aliases.sh fallthrough logic to work as portably as possible)
- [fish](https://github.com/fish-shell/fish-shell) — _with_ — (my preferred
  shell: its defaults/built-ins are easy to understand, but it is not POSIX)

### Docker / Podman containers

If `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by
name or ID, docker checked first), `hi` copies its tree in and chainloads
`load.sh` exactly as the ssh path does. No armoring is needed (`exec -i` passes
stdin as raw bytes), and cleanup happens on exit. Without `bash` in the
container `hi` drops you into the best plain shell `$_HI_SHELL_LADDER` finds,
with the aliases and a warning.

### Nomad allocations

`hi <alloc-id>` matches a running allocation by ID/prefix, after the ssh-host
and container checks. `nomad alloc exec` has no `docker cp`/`-e` equivalent,
so files stream in with `exec -i` + `cat >` and env vars go through a
`sh -c "export ...; exec ..."` wrapper. `hi <alloc-id>/<task>` picks a task in
a multi-task allocation (`nomad alloc exec -task <name>`); completion offers
the pairs for any allocation that has more than one.

### Kubernetes pods

`hi <pod-name>` is checked last, using `kubectl exec` against whatever
context/namespace your `kubectl` currently points at; `hi <ns>:<pod>` and
`hi <context>:<ns>:<pod>` reach one elsewhere (the prefixes become
`--namespace`/`--context`). `hi <pod>/<container>` picks a container
(`kubectl exec -c <name>`); without the suffix `kubectl` falls back to the
pod's first container with a warning. Completion offers `pod/container` for
every pod that has more than one, and `ns:pod` for pods outside the current
namespace.

### Windows hosts

- **WSL, Git Bash, Cygwin or MSYS2 on `PATH`**: the full experience, same code
  path as any other ssh host.
- **Stock Windows OpenSSH with no `bash`**: `hi` falls back to a plain
  interactive PowerShell session (no styling) rather than failing. It costs
  one authentication: hi writes its bootloader over the first of two calls
  multiplexed on the _same ssh connection_, and a target where that write
  cannot run `sh -c` has no POSIX shell, which is what the fallback is for.
  `DefaultShell` set to PowerShell lands in the same place.

**Installing hi _on_ Windows:** use WSL. The `.deb` installs into a WSL
distribution unchanged.

## say-hi and the alternatives

How say-hi compares to similar tools, and when to use something else:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

### Compatibility

Two questions, answered at two moments: **can hi land a session on that OS at
all**, and **what shell do you end up in**. Both tables, with a legend and what
proves each row, are in [docs/SUPPORT.md](docs/SUPPORT.md) — along with
everything weighed and answered **no**, with the argument attached.

## Testing

`tests/test_runner.sh` (`hi --test` once installed) runs the suite and prints
a colored pass/fail summary; `--group fast` (the unit suites, side by side)
then `--group lint` is what CI runs on every push/PR. The runbook is
[docs/TESTING.md](docs/TESTING.md).

### Coverage and Profiling

Two coverage tools sit beside the suites and disagree — kcov reads far too
low, bashcov far too high — which is why README carries no coverage badge and
neither gates anything. Why each is wrong, and the profiler to reach for when
a bench ceiling trips, is
[docs/TESTING.md](docs/TESTING.md#coverage-and-profiling).

## More docs

- [docs/SETTINGS.md](docs/SETTINGS.md) — the config overlay, every toggle and
  environment variable hi reads
- [docs/SUPPORT.md](docs/SUPPORT.md) — every target hi answers to, which OSes
  land a full session, which shell you end up in, and every runtime, shell,
  channel and feature answered **no**, and why
- [docs/ALTERNATIVES.md](docs/ALTERNATIVES.md) — sshrc, xxh, kyrat, sshdot and
  homeshick side by side
- [docs/TESTING.md](docs/TESTING.md) — the runner, suite groups, parallel
  cases, the lint gate, relaying
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — the named idioms the code's
  `GLOSSARY:` tags point at; drift-checked by the lint suite
- [docs/SECURITY.md](docs/SECURITY.md) — reporting, and what hi touches on a
  target
- [docs/PACKAGING.md](docs/PACKAGING.md) — the publishing runbook, the
  reproducibility contract, verifying a download, regenerating the demo GIFs
- [docs/ROADMAP.md](docs/ROADMAP.md) — what is planned, what it is blocked on,
  and what is research only
- [docs/CII-BEST-PRACTICES-DRAFT.md](docs/CII-BEST-PRACTICES-DRAFT.md) — the
  OpenSSF Best Practices questionnaire, answered against this tree, scratch
  until it's transcribed to bestpractices.dev
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) — the gate to run before a pull
  request, and which doc changes with what

## AI Usage

Heavily inspired by
[Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency).

This started as code written entirely by
[me](https://github.com/ivylikethevine), but I have used generative AI to write
large parts of it. All of the code here is my _responsibility_ regardless: AI
is a tool, not an owner of a project. I have personally understood, reviewed
and approved all of the AI-generated code in this repository, and _mainline
releases_ carry the same accountability to me as anything I write and publish
myself.
