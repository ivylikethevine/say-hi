# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

<!-- The check-runs badges filter on the compound check name "<ci.yml job
     name> / <called workflow job name>": mirror a rename on either side into
     nameFilter or the badge reads "no check runs". -->

![Payload](https://img.shields.io/badge/ssh_payload-50KB-4c1)
[![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397)

![hi into a container: the header and its package check, the git segment inside a checkout on the target, cat through the box's bat, and the empty /tmp it leaves behind](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).

## Contents

- [Additional Documentation](#additional-documentation)
- [In Sixty Seconds](#in-sixty-seconds)
- [What You Get](#what-you-get)
  - [Connect Via More Than SSH](#connect-via-more-than-ssh)
  - [The Header Tells You What's Missing](#the-header-tells-you-whats-missing)
  - [One Config Directory, Every Host, Every Shell](#one-config-directory-every-host-every-shell)
  - [Your Editors & Clipboard](#your-editors--clipboard)
  - [Know Where You Are at a Glance](#know-where-you-are-at-a-glance)
  - [One Command, Any Backend](#one-command-any-backend)
  - [No Target at All?](#no-target-at-all)
- [Target Requirements](#target-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Hostname, Username, and Group/Tag Colors](#hostname-username-and-grouptag-colors)
- [Built from/with/in mind](#built-fromwithin-mind)
- [say-hi and the alternatives](#say-hi-and-the-alternatives)
- [Testing](#testing)
- [AI Usage](#ai-usage)
- [Roadmap](#roadmap)
  - [What v1.0.0 means](#what-v100-means)
  - [By scope](#by-scope)

### Additional Documentation

- [docs/ALTERNATIVES.md](docs/ALTERNATIVES.md) — sshrc, xxh, kyrat, sshdot and
  homeshick side by side
- [docs/CODE_OF_CONDUCT.md](docs/CODE_OF_CONDUCT.md) — the bar for behaviour
  in issues, pull requests and discussions, and where to report a breach
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) — the gate to run before a pull
  request, what 1.x will not break, and which doc changes with what
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — the named idioms the code's
  `GLOSSARY:` tags point at; drift-checked by the lint suite
- [docs/PACKAGING.md](docs/PACKAGING.md) — the publishing runbook, the
  reproducibility contract, verifying a download, regenerating the demo GIFs
- [docs/SECURITY.md](docs/SECURITY.md) — reporting, and what hi touches on a
  target
- [docs/SETTINGS.md](docs/SETTINGS.md) — the config overlay, every toggle and
  environment variable hi reads
- [docs/SUPPORT.md](docs/SUPPORT.md) — every target, OS and shell hi answers
  to, and every runtime, shell and feature answered **no**, and why
- [docs/TESTING.md](docs/TESTING.md) — the runner, suite groups, parallel
  cases, the lint gate, relaying

---

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi
~/say-hi/scripts/install.sh    # wires your rc files, asks about each feature
exec $SHELL                    # reload
hi <anything>                   # ssh, with your prompt, aliases and editors along
```

`hi <anything>` & land in a session with your essential aliases, your essential
packages checked, a color-coded prompt, your editor configured, and more.
Do it all via `ssh`, `docker`, `podman`, `nomad`, or `kube` with `hi <TAB>`. No
fancy requirements on any target. Even an `alpine` container with `sh` will still
respect your `ls` alias flags.

## What You Get

### Connect Via More Than SSH

`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation and pod, each tagged with its backend; the
targets you use most, and most recently, come first (zsh and fish keep that
order; `_HI_RECENT=0` turns it off). `hi --<TAB>` answers hi's own flags
without probing any backend. Client: fish, for its pager's description
column. Showing `_HI_TARGETS_TTL=0`, so the sweep is never served from cache.

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

### The Header Tells You What's Missing

A `packages` overlay of the tools you care about, each with a priority; the
header reads it on every target — one quiet line on a box that has them, a
loud one on a box that does not. Client: bash, into two docker containers.
Showing a `packages` overlay and `_HI_PACKAGES_MIN_PRIORITY=3`.

![hi's header package check on a box with the tools installed, then on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### One Config Directory, Every Host, Every Shell

`~/.config/say-hi/` ships to every target: one `aliases.sh` alias works in a
bash session on a debian container and a fish session on an alpine box,
reached through docker and podman. Client: fish. Showing an `aliases.sh`
overlay with one alias and `_HI_BAT_OPTS`, and `_HI_SHELL_PREFERENCE=fish` for
the second target. A box with no bash gets the aliases-only tier — hi's own
aliases, not the overlay
([docs/SUPPORT.md](docs/SUPPORT.md#the-shell-you-end-up-in)).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on a fish-only alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your Editors & Clipboard

`nano` opens with hi's nanorc and `vim` with hi's vimrc on a box that has
neither; `hi_copy` puts a target's output on _your_ clipboard and `hi_notify`
raises a desktop notification in _your_ terminal when a command finishes.
Both ride the pty back as escapes: nothing is installed or running on the
target. Client: zsh, into a docker container.

![nano and vim with hi's rc files inside a session, then hi_copy and hi_notify](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know Where You Are at a Glance

`# Tags:` lines in `~/.ssh/config`, a `colors` overlay pinning each tag, and
`hi --color-preview` to see what every host resolves to — then a prod host
lands in red and a dev host in green. The targets carry their own `~/say-hi`
(the permanent-install path, hence their shorter headers). Client: bash, into
two ssh hosts. Showing a `colors` overlay with `hosttag` pins.

![hi --color-preview, then hi into a prod-tagged host with a red prompt and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One Command, Any Backend

`hi <name> <command>` runs one command inside the session and only its output
comes back: the same loop over an ssh host, a docker container, a nomad
allocation and a kubernetes pod (`-F` is ssh's, passed through unchanged; the
recording's ssh config is a throwaway). The pod is busybox `ash` with no bash
— the aliases-only tier — and hi says so, once, and runs the command anyway.
Client: zsh.

![a for loop running hi target cat over an ssh host, a docker container, a nomad allocation and a kubernetes pod](https://ivylikethevine.github.io/say-hi/docs/tapes/run.gif)

### No Target at All?

`hi` on its own offers the target list, backend-tagged and
most-used-and-most-recent first, and connects to what you pick — `fzf` or `sk`
if you have one, a numbered menu if not. It runs on the client, never reaches
a target, and a `hi` in a script or CI job still fails rather than wait on a
menu. Client: bash, into a docker container. Showing `_HI_RECENT` (on by
default).

![bare hi offering its target list through fzf with the most recent target on top, then landing a session in it](https://ivylikethevine.github.io/say-hi/docs/tapes/pick.gif)

## Target Requirements

![Minimal](https://img.shields.io/badge/minimal-ssh%20%2B%20base64-0A6E8A)
![Full](https://img.shields.io/badge/full-bash%203.2-0A8E8A)
![Linux](https://img.shields.io/github/actions/workflow/status/ivylikethevine/say-hi/ci.yml?branch=main&label=Linux)
![macOS](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28macOS%29%20%2F%20hi%20localhost%20%28BSD%20both%20ends%29&label=macOS)
![FreeBSD](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28FreeBSD%29%20%2F%20hi%20localhost%20%28FreeBSD%20both%20ends%29&label=FreeBSD)
![Windows](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=e2e%20%28Windows%29%20%2F%20hi%20at%20stock%20Windows%20OpenSSH%20%28PowerShell%20fallback%29&label=Windows)
![Windows MSYS2](https://img.shields.io/github/check-runs/ivylikethevine/say-hi/main?nameFilter=fast%20suites%20%28Windows%20client%29%20%2F%20fast%20suites%20%28Git%20Bash%29&label=Windows%20client)

Two questions, answered at two moments: **can hi land a session on that OS at
all**, and **what shell do you end up in**. Both tables, with a legend and what
proves each row, are in [docs/SUPPORT.md](docs/SUPPORT.md), along with
everything weighed and answered **no**, and why.

- **Client**: `bash` 3.2+ and `base64` (armors the payload through the login
  shell; coreutils, busybox, macOS/BSD and Git Bash all ship one), `ssh` for
  ssh targets, `docker`/`podman`/`nomad`/`kubectl` for those backends. hi has
  no protocol of its own: `ssh` is the transport, `base64` is armor, not
  crypto ([docs/SECURITY.md](docs/SECURITY.md)).
- **Target**: `base64` for ssh targets; nothing extra for container/alloc/pod
  targets. `bash` gets the full experience; without it you land in the best
  shell the target has, with a smaller session
  ([docs/SUPPORT.md](docs/SUPPORT.md#the-shell-you-end-up-in)).
- **fish 3.7+** (Ubuntu 24.04's) and **zsh 5.8+** (Debian oldstable's) are the
  floors for the other two shells hi styles; the lint gate checks both in a
  pinned container on every run
  ([docs/TESTING.md](docs/TESTING.md#the-lint-gate)).
- **bash 3.2** is the floor on both ends (macOS still ships it): no
  `mapfile`/`readarray` (`_hi_read_lines` in `common/core.sh` does that job),
  associative arrays, namerefs or `${x,,}`. `tests/lint/drift_test.sh` greps
  for those; `tests/targets/ssh_test.sh` runs a real bash 3.2 target.
- Everything else is plain POSIX/bash/zsh/fish — no compiled artifacts, no
  package manager, no build step.

## Installation

- The `.deb`/`.rpm`/`.apk` are on
  [the releases page](https://github.com/ivylikethevine/say-hi/releases), and
  [the package repository](docs/PACKAGING.md#package-repository) serves them
  signed and subscribable, so upgrades ride your package manager:

  ```sh
  # Debian, Ubuntu
  sudo curl -fsSLo /etc/apt/keyrings/say-hi.asc https://ivylikethevine.github.io/say-hi/say-hi.asc
  echo 'deb [signed-by=/etc/apt/keyrings/say-hi.asc] https://ivylikethevine.github.io/say-hi/apt stable main' |
    sudo tee /etc/apt/sources.list.d/say-hi.list
  sudo apt update && sudo apt install say-hi

  # Fedora, RHEL and derivatives
  sudo curl -fsSLo /etc/yum.repos.d/say-hi.repo https://ivylikethevine.github.io/say-hi/say-hi.repo
  sudo dnf install say-hi

  # Alpine
  wget -O /etc/apk/keys/say-hi.rsa.pub https://ivylikethevine.github.io/say-hi/say-hi.rsa.pub
  echo https://ivylikethevine.github.io/say-hi/apk >>/etc/apk/repositories
  apk add say-hi
  ```

  A packaged install still needs `hi --install` once per user, for the rc
  lines. macOS: `brew install ivylikethevine/tap/say-hi` (the tap is
  [ivylikethevine/homebrew-tap](https://github.com/ivylikethevine/homebrew-tap)),
  then `hi --install`.
  From a clone instead, pass `--no-link` to `install.sh` — `/usr/bin` is
  read-only under SIP — and put `~/say-hi/hi.sh` on your `PATH` yourself.

- `say-hi/scripts/install.sh`, or `hi --install` once hi is on your `PATH`.
  It validates `~/.bashrc`, `~/.zshrc` and `~/.config/fish/config.fish` with
  each shell's own syntax checker first and asks before continuing if any has issues.
  A starship, powerlevel10k or oh-my-zsh prompt already in those files is
  found and kept on this machine (`_HI_DISABLE_LOCAL_PROMPT=1`); hi's prompt
  still draws on every target
  ([docs/SETTINGS.md](docs/SETTINGS.md#others)).
- reload your shell!
- `hi --configure` opens a menu over a live preview of the header and
  prompt: pick a preset (`everything`, `balanced`, `minimal`), or open a
  section - Header, Features, Prompt, Advanced - and save.
  `hi --configure --preset <name>` skips the menu. Answers land in
  `~/.config/say-hi/settings.sh` ([Configuration](#configuration)).
- [optional] `hi --overlay-init` puts `~/.config/say-hi` under git _in place_; from then
  on `hi --configure` commits its own writes. [docs/SETTINGS.md](docs/SETTINGS.md).
- `hi --doctor [<target>]` when something is slow or failing to help diagnose.
- TAB: `hi <TAB>` completes every target, `hi --<TAB>` completes hi's flags. GIF: [completion](#connect-via-more-than-ssh).
- `hi` on its own offers that list and connects to what you pick — `fzf` or
  `sk` if you have one, a numbered menu if not. GIF:
  [no target at all](#no-target-at-all).
- [optional] configure `~/.ssh/config` tags via sshm
- [optional] pin colors in `~/.config/say-hi/colors` (copy
  `say-hi/settings/colors` to start); `hi --color-preview` shows what every
  ssh host and your user resolve to.
- **A dropped connection ends the session.** The target's tree is removed on
  any exit, a lost link included, and nothing on the target outlives it —
  there is no `hi --tmux` ([why](docs/SUPPORT.md#features-that-were-removed)).
  For anything you would hate to lose to a flaky link, start `hi` inside
  `tmux` or `screen` **on this machine**: the local multiplexer survives the
  drop, and reconnecting is another `hi <target>`
  ([how it works](docs/SETTINGS.md#how-it-works)).
- done with it? `say-hi/scripts/uninstall.sh`, or `hi --uninstall`, strips
  hi's lines from your rc files, removes the `settings.sh` it wrote, and
  unlinks `/usr/bin/hi`. Left behind, on purpose: the checkout (or the
  package — `apt remove say-hi` and friends), the rest of `~/.config/say-hi`
  (your colors, packages and aliases), and the one-time `<rc>.hi-orig`
  backups. To take it all off a cloned install:

  ```sh
  hi --uninstall && rm -rf ~/say-hi ~/.config/say-hi ~/.bashrc.hi-orig ~/.zshrc.hi-orig ~/.config/fish/config.fish.hi-orig
  ```

## Configuration

Your config lives in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/`, and rides along to every host you
say `hi` to. `colors` and `packages` overlay the tree's copies, `aliases.sh`
adds to the shipped alias set, and a `bash.sh`/`zsh.zsh`/`config.fish` there
is sourced last in hi's per-shell rc so yours win. `settings.sh` (what
`hi --configure` writes) has no in-tree counterpart. The overlay file table,
every toggle and every environment variable are in
[docs/SETTINGS.md](docs/SETTINGS.md); how a session reaches the target is
[How it works](docs/SETTINGS.md#how-it-works).

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`,
`~/.config/fish/config.fish`, etc. — everything in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` is copied to every host you say
`hi` to, so a token, an internal hostname or a private path in your
`aliases.sh` lands on each of them. See [docs/SECURITY.md](docs/SECURITY.md)._**

By default hi writes nothing to a target outside its own temp directory.
The two opt-in settings that change that are in
[What hi writes on a target](docs/SECURITY.md#what-hi-writes-on-a-target).

### Hostname, Username, and Group/Tag Colors

Every username and hostname gets a color derived from its name. To pin one,
add a line to `~/.config/say-hi/colors`: `username,root,red`,
`hostname,prod-db,yellow` or `hosttag,desktop,green`. `hosttag` matches the
_leftmost_ tag in a `# Tags: ...` comment directly above a `Host` or
`Match host` line in `~/.ssh/config`; a wildcard block (`Host prod-*`) tags
every name it covers. A `hostname` pin holding `*` or `?` is a pattern —
`hostname,10.0.1.*,red` colors a whole subnet with no ssh-config entry at
all. `hi --color-preview` shows the result in the actual colors; the long
version, and using the hash in your own prompt, is
[docs/SETTINGS.md](docs/SETTINGS.md#colors).

## Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) — _from_ — (became `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) — _with_ — (optional, but _highly_
  recommended to configure `~/.ssh/config` hosttags)
- [bat](https://github.com/sharkdp/bat) — _in mind_ — (essentially my reason to
  get the aliases.sh fallthrough logic to work as portably as possible)
- [fish](https://github.com/fish-shell/fish-shell) — _with_ — (my preferred
  shell: its defaults/built-ins are easy to understand, but it is not POSIX)

## say-hi and the alternatives

How say-hi compares to similar tools, and when to use something else:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

## Testing

`tests/test_runner.sh` (`hi --test` once installed) runs the suite with a
colored pass/fail summary; CI runs `--group fast` (the unit suites, side by
side) then `--group lint` on every push/PR. Runbook:
[docs/TESTING.md](docs/TESTING.md).

![Tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)
[![Kcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage.json)](docs/TESTING.md#coverage-and-profiling)
[![Bashcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage-v2.json)](docs/TESTING.md#coverage-and-profiling)

Two coverage tools sit beside the suites — kcov and bashcov, each sweeping
every suite the coverage runner can host, measured over the shipped product
only. They cannot err in the same direction, so their landing within a few
points of each other is what makes the number worth reading; each badge
names its measurer, and neither gates anything. The residual per-file skews,
and the profiler for a tripped bench ceiling, are
[docs/TESTING.md](docs/TESTING.md#coverage-and-profiling).

## AI Usage

Heavily inspired by
[Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency).

This started as code written entirely by
[me](https://github.com/ivylikethevine), but I have used generative AI to write
large parts of it. All of the code here is my _responsibility_ regardless: AI
is a tool, not an owner of a project. I have personally understood, reviewed
and approved all of the AI-generated code in this repository, and **mainline
releases** carry the same accountability to me as anything I write and publish
myself.

## Roadmap

What's left, in one list ordered by **ascending scope** — the smallest work
first. Every entry is open for consideration; nothing here is parked or
descoped. Finished entries and
questions decided against are **deleted**: git history is the ledger.

### What v1.0.0 Means

- [ ] **A stability contract is written down** — shipped as
      [docs/CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break):
      the eighteen `common/flags`, every `docs/SETTINGS.md` row,
      `$_HI_OVERLAY_FILES`, the install layout, `_HI_RELEASE`, the semver rule
      and how a toggle retires. **Ticks when** the tag commit turns
      `docs/SECURITY.md`'s _Supported versions_ prose into the version table
      it promises (the **Flip to stable** entry).

### By Scope

1. [ ] **tldr page** — _scope: one upstream pull request; outside this
       checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
       by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

2. [ ] **WSL proven** — _scope: one green push._ The job is written and
       pinned: `windows-e2e.yml`'s `wsl` runs the fast suites inside an
       Ubuntu WSL distribution, lays down the package layout with
       `install.sh --prefix`, and says `hi` into it from Git Bash. **Do:**
       push, read the run, fix what a hosted runner disagrees with. **Ticks
       when:** the job is green on `main` and SUPPORT.md's WSL row reads ✅.

3. [ ] **NAS permanent-install recipe** — _scope: one docs section; blocked
       on access to real appliance hardware, which nothing in this checkout
       supplies._ SUPPORT.md's NAS rows read 🟡 ("full session expected...
       nobody has run it on the appliance") — plain disposable `hi` isn't even
       confirmed there yet, before a permanent-install recipe is worth
       writing to spare a slow link the ~48KB-a-connect payload. **Do:** get
       `hi <target>` working once on a real DSM, QTS, SCALE, Unraid or CORE
       box and flip that row to ✅; only then is `scripts/install.sh --prefix`
       (or a package, where one exists for the platform) worth walking
       end-to-end and writing up. **Ticks when:** one NAS row is ✅ and the
       recipe is linked from it.

4. [ ] **AUR** — _scope: nothing until registration reopens; then an
       account, a key, and one manual first push; outside this checkout._
       Registration is closed to new accounts (spam), and
       `publish-external.yml`'s `aur` job stays written and unexercised
       until it reopens. **When it reopens:** register; generate an ed25519
       key, add the private half as the `AUR_SSH_KEY` repo secret; the first
       push per package is manual (namcap gate against the published
       source, then only `PKGBUILD` + `.SRCINFO`), and dispatching
       `publish-external.yml` handles the versioned package after.
       **Ticks when:** both packages are live on the AUR and a dispatch has
       kept `say-hi` current for one real release. <https://archlinux.org/news/>

5. [ ] **Client-side tmux wrap** — _scope: one new flag (the CLI's first past
       eighteen, `docs/CONTRIBUTING.md#what-1x-will-not-break`'s current
       count), target-name sanitization, a suite, docs._ The target-side
       version of this shipped, then was removed and declined
       ([why](docs/SUPPORT.md#features-that-were-removed)) — a disposable
       tree cannot outlive its own session. Today's workaround is manual:
       start `hi` inside your own `tmux`/`screen` ([README](#in-sixty-seconds)).
       This automates that one step, entirely client-side, no target-side
       footprint at all — wrapping the session in `tmux new -A -s hi-<target>`,
       attaching if that name is already running rather than opening a
       second one. **Do:** a flag/toggle (chosen not to reuse the
       removed `_HI_TMUX_*`/`--tmux` names — those meant the target-side
       feature), a sanitizer for target strings tmux's session-name rules
       reject (`:` in a kube `context:namespace:pod`, `/` in a nested
       target), a suite under `tests/hi/` or `tests/targets/`, a
       `docs/SETTINGS.md` row. **Ticks when:** the toggle ships, tested and
       documented, and reconnecting to the same target reattaches instead of
       opening a second session.
