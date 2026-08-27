# hi.sh -> sshrc supercharged

---

## EXPERIMENTAL UNTIL v1.0.0-stable RELEASES

A hobby project in active development: interfaces can still move, and the
current state is not a representation of final, published quality.

---

[![tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![Linux](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/ci.yml?branch=main&label=Linux)](https://github.com/ivylikethevine/say-hi/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/macos-e2e.yml?branch=main&label=macOS)](https://github.com/ivylikethevine/say-hi/actions/workflows/macos-e2e.yml)
[![Windows](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/windows-e2e.yml?branch=main&label=Windows)](https://github.com/ivylikethevine/say-hi/actions/workflows/windows-e2e.yml)
![ssh payload](https://img.shields.io/badge/ssh_payload-48KB_per_session-4c1)
[![package](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fpackage.json)](https://github.com/ivylikethevine/say-hi/releases)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![license](https://img.shields.io/badge/license-MIT-blue)

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

![hi connecting to a container: banner, header, packages check, colored prompt, and the cleanup on exit](docs/demos/demo.gif)

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

## Contents

- [Every target, the same session](#every-target-the-same-session)
  - [ssh, with a permanent install](#ssh-with-a-permanent-install)
  - [docker](#docker)
  - [podman](#podman)
  - [nomad](#nomad)
  - [kubernetes](#kubernetes)
  - [completion, every backend at once](#completion-every-backend-at-once)
  - [no target at all](#no-target-at-all)
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

## Every target, the same session

`hi` behaves identically whatever is on the other end — an ssh host, a
container, an allocation, a pod — and whatever shell each side runs. One GIF
per backend, each with a different knob turned so the set reads as a
configurable tool; the GIF at the top is the stock defaults. How they are
rendered is in [docs/PACKAGING.md](docs/PACKAGING.md#regenerating-the-demo-gifs).

### ssh, with a permanent install

The target carries its own `~/say-hi`, so nothing ships over the wire — hi
loads the tree in place. Client: bash. Showing `_HI_HEADER_TIMESTAMP=0` and
`_HI_HEADER_SYSINFO=0`, set on the _target_: a permanent install reads its own
config.

![hi over ssh into a host with a permanent ~/say-hi](https://ivylikethevine.github.io/say-hi/docs/demos/ssh.gif)

### docker

A debian/bash container, then an alpine box whose only real shell is zsh — hi
probes and falls back without being told. Client: zsh. Showing
`_HI_PROMPT_END_ZSH` and `_HI_HEADER_CHECK=0`.

![hi into a debian container, then an alpine zsh-only container](https://ivylikethevine.github.io/say-hi/docs/demos/docker.gif)

### podman

A fish-only alpine container from a fish client: no bash anywhere in the loop.
Showing `_HI_PROMPT_END_FISH`.

![hi from fish into a fish-only alpine container via podman](https://ivylikethevine.github.io/say-hi/docs/demos/podman.gif)

### nomad

A dev agent, one docker-driver job, and `hi <alloc-id-prefix>` straight into
the allocation. Client: bash. Showing `_HI_HEADER_GHZ=1` and
`_HI_HEADER_IDENTITY=0`.

![hi into a nomad allocation by ID prefix](https://ivylikethevine.github.io/say-hi/docs/demos/nomad.gif)

### kubernetes

A kind cluster and a bare alpine pod — busybox ash is all it has, which is hi's
aliases-only fallback. Client: zsh. Showing `_HI_DISABLE_GIT_STATUS=1`.

![hi into a kubernetes pod on a kind cluster](https://ivylikethevine.github.io/say-hi/docs/demos/kube.gif)

### completion, every backend at once

`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation and pod, each tagged with its backend.
Targets you connect to most, and most recently, come first (zsh and fish keep
that order; `_HI_RECENT=0` turns it off).
`hi --<TAB>` answers hi's own flags without probing any backend. Client: fish,
for the description column its pager gives every row.

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/demos/complete.gif)

The list stops at eleven rows because fish hands its pager half the screen —
that is completion behaving normally, not the GIF cut short.

### no target at all

`hi` on its own does not fall through to ssh's usage message: it offers the
same list, backend-tagged and recently-used first, and connects to what you
pick. `fzf` or `sk` if you have one, a numbered menu if you do not — nothing
has to be installed. It runs on the client and never reaches a target, and a
`hi` in a script or a CI job still fails the way it always has rather than
waiting on a menu nobody can answer.

![bare hi offering its target list through fzf, then landing a session in the container picked from it](https://ivylikethevine.github.io/say-hi/docs/demos/pick.gif)

## Requirements

- **Client**: `bash` 3.2+ and `base64` (armors the payload through the login
  shell; coreutils, busybox, macOS/BSD and Git Bash all ship one), plus
  `docker`/`podman`/`nomad`/`kubectl` for those backends.
- **Target**: `base64` for ssh targets; nothing extra for container/alloc/pod
  targets. `bash` gets the full experience; without it `hi` lands you in the
  best shell the target has, with a smaller session — see
  [Compatibility](#compatibility).
- **bash 3.2** is the floor on both ends (macOS still ships it), so hi uses no
  bash-4-only construct: no `mapfile`/`readarray` (`_hi_read_lines` in
  `common/core.sh` does that job), associative arrays, namerefs or `${x,,}`.
  `tests/lint/shellcheck_test.sh` greps for those, and `tests/targets/ssh_test.sh`
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
  [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
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
  [no target at all](#no-target-at-all).
- configure `~/.ssh/config` tags via sshm
- [optional] pin colors in `~/.config/say-hi/colors` (copy
  `say-hi/settings/colors` to start); `hi --color-preview` shows what every
  ssh host and your user resolve to.
- [optional] copy `say-hi/settings/packages` to `~/.config/say-hi/packages`
  and edit; `hi --packages-preview` shows what each priority means and the
  check as a connect will print it.
- [optional] either of those files can live somewhere else instead —
  `export _HI_COLORS=~/dotfiles/hi-colors` in `settings.sh` moves that one file
  without moving the rest of the overlay (`_HI_PACKAGES`, `_HI_VIMRC` and
  `_HI_NANORC` likewise); see
  [docs/CONFIGURATION.md](docs/CONFIGURATION.md#pointing-one-file-somewhere-else).
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
[docs/CONFIGURATION.md](docs/CONFIGURATION.md); how a session gets to the
target is [How it works](docs/CONFIGURATION.md#how-it-works) there.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`,
`~/.config/fish/config.fish`, etc. — anything in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` is copied to every host you say
`hi` to._**

### Hostname, username, and group/tag colors

Every username and hostname gets a color derived from its name. To pin one,
add a line to `~/.config/say-hi/colors`: `username,root,red`,
`hostname,prod-db,yellow` or `hosttag,desktop,green`. `hosttag` matches the
_leftmost_ tag in a `# Tags: ...` comment directly above a `Host` or
`Match host` line in `~/.ssh/config`; a wildcard block (`Host prod-*`) tags
every name it covers. `hi --color-preview` shows the result in the actual
colors.

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
proves each row, are in [docs/SUPPORTED.md](docs/SUPPORTED.md). Everything
weighed and answered **no**, with the argument attached, is
[docs/UNSUPPORTED.md](docs/UNSUPPORTED.md).

## Testing

`tests/test_runner.sh` (`hi --test` once installed) runs the suite and prints
a colored pass/fail summary; `--group fast` (the unit suites, side by side)
then `--group lint` is what CI runs on every push/PR. The runbook is
[docs/TESTING.md](docs/TESTING.md).

### Coverage and Profiling

Two coverage tools sit beside the suites, and neither number can be taken at
face value, which is why README carries no coverage badge and neither gates
anything: **kcov** loses its `DEBUG` trap the moment
the harness is sourced, so it counts only what ran while things were loading
and reads far too low (`common/git_prompt.sh` shows 2.56% with seventeen cases
passing against it). **bashcov** reads bash's `xtrace` and gets that file
right at 92.68%, but counts every line of a _heredoc body_ as covered, so
`hi.sh` — which builds the entire remote script out of heredocs — reads far
too high.

## More docs

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — the config overlay, every
  toggle and environment variable hi reads
- [docs/SUPPORTED.md](docs/SUPPORTED.md) — every target hi answers to, which
  OSes land a full session, and which shell you end up in
- [docs/UNSUPPORTED.md](docs/UNSUPPORTED.md) — every runtime, shell, channel
  and feature answered **no**, and why
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
- [docs/ROADMAP.md](docs/ROADMAP.md) — what is planned and what it is blocked on
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
