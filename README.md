# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

`hi <host>` is `ssh <host>` with your shell setup along: the session opens
with your prompt, your aliases, and your editor configs, on a host that has
none of them, and what hi put there is removed when it ends. Nothing is
installed on the host. The same command opens a session in a container, a
Nomad allocation, or a Kubernetes pod.

![Payload](https://img.shields.io/badge/ssh_payload-82KB-4c1)
[![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

![hi into a container: the header and its package check, the git segment inside a checkout on the target, cat through the box's bat, hi's tree in /tmp during the session, and the empty /tmp it leaves behind](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).
>
> New here: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) has the words
> these docs use and a starting path for the way you work.
> [docs/README.md](docs/README.md) indexes the rest, the man page and the tldr
> draft included.

## Contents

- [In Sixty Seconds](#in-sixty-seconds)
- [What You Get](#what-you-get)
  - [Your Aliases, in Every Shell, on Every Host](#your-aliases-in-every-shell-on-every-host)
  - [Your Editors and Your Git](#your-editors-and-your-git)
  - [Know Where You Are at a Glance](#know-where-you-are-at-a-glance)
  - [One Command, Every Backend](#one-command-every-backend)
  - [Survive a Dropped Link](#survive-a-dropped-link)
  - [The Header Tells You What's Missing](#the-header-tells-you-whats-missing)
  - [Every Target in One Tab](#every-target-in-one-tab)
- [Target Requirements](#target-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Hostname, Username, and Group/Tag Colors](#hostname-username-and-grouptag-colors)
- [Built from/with/in mind](#built-fromwithin-mind)
- [say-hi and the alternatives](#say-hi-and-the-alternatives)
- [Testing](#testing)
- [Getting help and contributing](#getting-help-and-contributing)
- [AI usage](#ai-usage)
- [Roadmap](#roadmap)
- [Release Stages](#release-stages)
- [License](#license)

---

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # or any directory you like
~/say-hi/scripts/install.sh    # wires your shell's rc file and asks one question
exec $SHELL                    # reload
hi <anything>                  # ssh, with your prompt, aliases, and editors along
```

No sudo: the install links `~/.local/bin/hi` and writes only to your rc files
and `~/.config/say-hi`. `--preset balanced` answers without asking,
`--dry-run` shows every write first, and `hi --configure` has the settings
menu.

## What You Get

Each story is a problem, what its GIF shows, and the config it was recorded
with; [docs/SETTINGS.md](docs/SETTINGS.md) has every setting. Most leave the
laptop as it is (`_HI_DISABLE_LOCAL=1`), so the outside prompt is its own and
hi begins at the target.

### Your Aliases, in Every Shell, on Every Host

_Your aliases live in one rc file on one machine, and the boxes you work on
have none of them - some don't even run your shell._ `~/.config/say-hi/` rides
along on every connect: Rio, an operator in fish at a workstation, uses one
`aliases.sh` alias in a bash session on a debian container (docker) and a fish
session on an alpine box (podman). A box with no bash gets the aliases-only
tier ([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).

**Config:** fish's own prompt at home and hi's on the boxes, the header
trimmed to the clocks, the backend counts, and the check on a blue-to-red
`_HI_PACKAGES_PALETTE`, and the styled tool aliases (`_HI_TOOL_ALIASES=1`).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your Editors and Your Git

_On a shared box, `vim` opens on the box's settings, `sudo vim` on root's, and
`git` knows none of your aliases._ Maya, a developer in zsh on a Mac, opens
nano and vim on the team's dev box with the nanorc and vimrc kept at home
(line numbers, a status line), then `sudo vim` on the same vimrc, then
`git st` and `git lg`. The git identity rides; the credential helper and the
keys stay home ([docs/INTEGRATIONS.md](docs/INTEGRATIONS.md#git)). Nothing is
installed on the box or left running there.

**Config:** the box's starship draws the prompt (`_HI_PROMPT_TOOL=starship`)
and hi keeps the rest, the sudo alias (`_HI_SUDO_ALIAS=1`), the git plugin
(`hi --enable-plugin git`), and the compact header.

![nano and vim with the carried rc files, sudo vim on the same vimrc, and git aliases, inside a session](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know Where You Are at a Glance

_A prod terminal and a dev terminal look the same until the wrong command runs
in one._ Kai, a sysadmin in bash on a laptop, tags the prod database with
`hi --add-tag`, checks what every host resolves to with `hi --preview colors`,
and connects: the prod host lands in red with the longer header its tag's
`settings.prod.sh` asks for, and the dev host in green. Both boxes are fish,
and Kai's own two-line fish prompt rides along, drawn on the colors hi
resolved.

**Config:** hosttag pins in a `colors` overlay, a hex `_HI_COLOR_SCHEME`, hi's
prompt on the laptop too (`_HI_PROMPT_TOOL=hi`), and a `settings.prod.sh`
([Settings by host tag](docs/SETTINGS.md#settings-by-host-tag)).

![hi --add-tag, hi --preview colors, then hi into a prod-tagged host with a red prompt and a longer header and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One Command, Every Backend

_ssh, `docker exec`, `nomad alloc exec`, and `kubectl exec` each want their own
syntax, and none of them knows your aliases._ Chen, a researcher in zsh on a
Fedora laptop, loops `hi <target> distro` - an alias from their `aliases.sh` -
over an ssh host, a docker container, a nomad allocation, and a kubernetes
pod, and only each command's output comes back. The pod is busybox `ash` with
no bash, the aliases-only tier: hi says so, once, and the alias runs there
too. `-F` is ssh's, passed through unchanged; the recording's ssh config is a
throwaway.

**Config:** an `aliases.sh` overlay; a one-off command draws no header.

![a for loop running one alias through hi over an ssh host, a docker container, a nomad allocation, and a kubernetes pod](https://ivylikethevine.github.io/say-hi/docs/tapes/run.gif)

### Survive a Dropped Link

_A long job over a flaky link dies with the link._ Noor, on call in zsh on a
MacBook over hotel wifi, starts a backfill on the prod database box under
`hi --keep`. The link drops mid-job (the recording cuts it from the box's
end); hi says how long the box keeps the session, retries every five seconds,
and is back in the same tmux pane with the job still running. A box with no
tmux, zellij, or screen keeps the session's files and directory through the
drop instead ([HI.65](docs/GLOSSARY.md#hi65-kept-session)).

**Config:** a three-cell header. `_HI_KEEP=1`, in `settings.sh` or a tag's
file, makes every connect a kept one.

![hi --keep into a prod box, a backfill running, the link dropping, hi retrying, and the same tmux pane back with the job still going](https://ivylikethevine.github.io/say-hi/docs/tapes/keep.gif)

### The Header Tells You What's Missing

_You find out a box lacks `rsync` or `tmux` halfway through the job that needed
it._ Sam, running a homelab from bash on an Ubuntu laptop, adds tools to the
check with `hi --add-package`, then connects to the nas and the pihole: one
quiet line on the box that has them, a loud one on the box that does not.
Groups switch on and off, and a `packages` file of your own replaces the
shipped one ([docs/COLORS.md](docs/COLORS.md#the-package-checks-rows)).

**Config:** hi's prompt off (`_HI_DISABLE_PROMPT=1`), so each box keeps its
distro's own while the header, the check, and the aliases ride anyway, the
`core` and `useful` groups on, and every address shown (`_HI_IP_HIDE=none`).

![hi --add-package, then hi's header package check on a box with the tools installed and on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### Every Target in One Tab

_Which box is an ssh host, and which a container, an allocation, or a pod?_
`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation, and pod, each tagged with its backend;
`hi --<TAB>` answers hi's own flags without waking a backend. Rio again, in
fish, whose pager shows the backend column.

**Config:** no cached sweep (`_HI_TARGETS_TTL=0`).

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

## Target Requirements

<!-- Seven shields endpoint badges, published by pages.yml
     (.github/scripts/platform_badges.sh) - which says why
     img.shields.io/github/check-runs cannot answer per job here, and is where
     a renamed CI job has to be mirrored. A badge added here reads
     "inaccessible" until the next Pages deploy publishes its file. -->

![Minimal](https://img.shields.io/badge/minimal-ssh%20%2B%20base64%20%2B%20tar-0A6E8A)
![Full](https://img.shields.io/badge/full-bash%203.2-0A8E8A)
![Linux](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Flinux.json)
![macOS](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fmacos.json)
![FreeBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ffreebsd.json)
![OpenBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fopenbsd.json)
![Alpine client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Falpine.json)
![Windows](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows.json)
![Windows client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows-client.json)

Which OSes hi lands a session on, which shell you end up in, what proves each
row, and everything answered **no**, and why:
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

- **Client**: `bash` 3.2+, `tar` and `gzip` (a libarchive `tar` compresses on
  its own and needs no `gzip`), and `base64` (coreutils, busybox, macOS/BSD, and Git
  Bash all ship one; `openssl base64` stands in where none does), `ssh` for
  ssh targets, any of `docker`/`podman`/`nerdctl`/`finch` and
  `nomad`/`kubectl` for those backends. hi has no protocol of its own: `ssh`
  is the transport, `base64` is armor, not crypto
  ([docs/SECURITY.md](docs/SECURITY.md)).
- **Target**: `base64` (or `openssl`), `mktemp`, and a `tar` that reads
  gzip (`tar -z`), on every backend: the payload lands the same way over
  ssh and an exec. `bash` gets the full session; without it you
  land in the best shell the target has, with a smaller one
  ([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).
- **A slow link**: the ssh wire is meant to stay at or under 128 KB — 8 s over
  a 128 kbps link — and the gzipped payload is held to 64 KB by the bench
  group. The payload badge above is today's wire size.
- **bash 3.2** is the floor on both ends (macOS still ships it; what that rules
  out of the code is
  [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on)),
  **fish 3.3** (Ubuntu 22.04's) and **zsh 5.5** (RHEL 8's) for the other two
  shells hi styles.
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

  # Fedora, RHEL, and derivatives
  sudo curl -fsSLo /etc/yum.repos.d/say-hi.repo https://ivylikethevine.github.io/say-hi/say-hi.repo
  sudo dnf install say-hi

  # Alpine
  wget -O /etc/apk/keys/say-hi.rsa.pub https://ivylikethevine.github.io/say-hi/say-hi.rsa.pub
  echo https://ivylikethevine.github.io/say-hi/apk >>/etc/apk/repositories
  apk add say-hi
  ```

  A packaged install still needs `hi --install` once per user, for the rc
  lines; it leaves the package's `/usr/bin/hi` to the package manager. macOS:
  `brew install ivylikethevine/tap/say-hi`
  ([the tap](docs/PACKAGING.md#homebrew-tap)), then `hi --install`.

- `say-hi/scripts/install.sh`, or `hi --install` once hi is on your `PATH`.
  It syntax-checks `~/.bashrc`, `~/.zshrc`, and `~/.config/fish/config.fish`
  with each shell's own checker first and asks before continuing if any fails
  (`--yes` answers it). Your login shell is wired, and any other of the three
  with an rc file already; `--shell bash,zsh` names them instead, and `all` is
  every one installed. Each line tests for the tree first, so a deleted
  checkout costs a shell nothing. On macOS `~/.bash_profile` is taught to read
  `~/.bashrc`. A first install asks one thing, which preset to start from
  ([docs/SETTINGS.md](docs/SETTINGS.md#presets)), and nothing else. For an rc file a dotfile manager owns, `--print-rc` prints
  each block and writes none
  ([docs/SETTINGS.md](docs/SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)). `hi` is linked at `~/.local/bin/hi` (`--link system`
  for `/usr/bin/hi`, `--link none` for no link — the wired shells alias it
  either way). Then reload your shell. zsh completes `hi` through the
  `compinit` your `~/.zshrc` runs, before hi's line or after it; hi runs none
  of its own.
- `hi --configure` reopens the settings menu: pick a preset, or flip any setting
  on its pages — Header, its cells and package check, Prompt, Plugins — or
  by a switch's key on the first, and save to `~/.config/say-hi/settings.sh` ([Configuration](#configuration)).
- `hi --doctor [<target>]` when something is slow or failing (`--problems` for
  only what needs fixing, `--json` for a bug report); it also reports which rc
  files are wired and where `hi` on your `PATH` leads.
  [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) goes symptom by symptom.
- `hi --update` moves a cloned install to the newest release tag, or on the
  `dev` branch fast-forwards it (`--dry-run` says what it would do; a package
  upgrades through its package manager).
- `hi --add-package core bat,batcat` adds a row to the `core` group of
  `~/.config/say-hi/packages`, copying the shipped roster there first;
  `hi --remove-package bat` takes it out again.
- `hi --add-tag web1 prod` writes the `# Tags: prod` line above `Host web1`
  in `~/.ssh/config`, which a `hosttag` row then colors
  ([docs/COLORS.md](docs/COLORS.md)).
- `hi --add-color hostname prod-db yellow` pins a color in
  `~/.config/say-hi/colors`, copying the shipped pins there first;
  `hi --remove-color hostname prod-db` removes the pin.
- `hi --plugins` lists every config hi carries to a target, and what rides;
  `hi --disable-plugin lazygit vim` keeps a plugin home and
  `hi --enable-plugin` brings it back; `hi --edit plugins` opens your plugins
  file in your editor, for the configs of a tool hi does not know
  ([docs/SETTINGS.md](docs/SETTINGS.md#switching-a-plugin-off)).
- The whole surface is twenty-four flags: `hi --help` (or bare `hi`) lists them,
  [docs/USAGE.md](docs/USAGE.md) shows what each prints, `man hi` is the long
  form, and everything hi does not answer goes to `ssh`.
- **A dropped connection ends the session** and nothing on the target
  outlives it, unless you ask: `hi --keep <target>` runs the session in
  `tmux`, `zellij`, or `screen` on the target, the next `hi <target>`
  reattaches, and `hi --end <target>` or a day unattended closes it. On a
  target with none of the three, its files and directory wait fifteen
  minutes for you
  ([how](docs/INTEGRATIONS.md#terminal-multiplexers)).
- Done with it? `hi --uninstall` (or `scripts/install.sh --uninstall`) strips
  hi's lines from your rc files, removes the `settings.sh` it wrote, and
  unlinks `~/.local/bin/hi` (or a `/usr/bin/hi` of its own making; a
  package's stays). A one-time `<rc>.hi-orig` backup goes once the rc matches
  it again; one that differs is kept, with the differing lines printed. Left
  behind on purpose: the checkout or package (`apt remove say-hi` and
  friends), and the rest of `~/.config/say-hi` (`--purge` removes that too).
  `--dry-run` names what would go. To take it all off a cloned install:

  ```sh
  hi --uninstall --purge && rm -rf ~/say-hi
  ```

## Configuration

Your config lives in `${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` and rides
along to every host you say `hi` to. `settings.sh` is what `hi --configure`
writes; the install copies nothing else there, so the shipped `colors` and
`packages` apply until you copy one out of the tree's `config/` to edit
(`hi --add-package` and `hi --add-color` do the copying) or add an
`aliases.sh` of your own. The editor rcs need no copy: hi carries your
own `~/.vimrc`, `~/.config/nvim/init.lua`, `~/.nanorc`, or `~/.emacs`
([why that works](docs/SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).
The overlay file table, the settings menu, and every setting are in
[docs/SETTINGS.md](docs/SETTINGS.md); how a session reaches the target is
[How it works](docs/HOW-IT-WORKS.md). The tools hi wires in where a
target has them — your prompt program, mise, direnv, bat, eza, and more — are
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

**_IMPORTANT: every overlay file in that directory is copied to every host you
say `hi` to — keep local-only lines (a token, an internal hostname) in
`~/.bashrc` and friends instead._** What lands on a target, and that it is
removed on exit:
[docs/SECURITY.md](docs/SECURITY.md#what-hi-writes-on-a-target).

### Hostname, Username, and Group/Tag Colors

Every username and hostname gets a color derived from its name; a line in
`~/.config/say-hi/colors` (`prod-db = "yellow"` under `[hostname]`, which
`hi --add-color hostname prod-db yellow` writes) pins one, and
`hi --preview colors` shows what every host and your user resolve to. Tags
(`# Tags:` lines in `~/.ssh/config`, which sshm writes), patterns, truecolor
schemes of your own, and using the hash in your own prompt:
[docs/COLORS.md](docs/COLORS.md).

## Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) — _from_ — (**became** `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) — _with_ — (optional, but _highly_
  recommended for `~/.ssh/config` host tags)
- [bat](https://github.com/sharkdp/bat) — _in mind_ — (the reason the
  aliases.sh fallthrough logic works as portably as it does; `bat` is
  sometimes `batcat`)
- [eza](https://github.com/eza-community/eza) — _in mind_ — (the colorized
  `ls` upgrade, with its flags kept apart from plain `ls`'s for older hosts)
- [fish](https://github.com/fish-shell/fish-shell) — _with_ — (my preferred
  shell: its defaults/built-ins are easy to understand, but it is not POSIX)

## say-hi and the alternatives

How say-hi compares to similar tools, and when to use something else:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

## Testing

`tests/test_runner.sh` runs the suites with a colored pass/fail summary;
`--group fast` and `--group lint` are [the gate](docs/CONTRIBUTING.md#the-gate)
CI runs on every push. Runbook: [docs/TESTING.md](docs/TESTING.md).

![Tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)
[![Kcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage.json)](docs/TESTING.md#coverage-and-profiling)
[![Bashcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage-v2.json)](docs/TESTING.md#coverage-and-profiling)

Both coverage badges measure the shipped product over the full sweep and gate
nothing; read their average as the figure
([why two](docs/TESTING.md#coverage-and-profiling)).

## Getting help and contributing

A question, a bug, or an idea: [docs/SUPPORT.md](docs/SUPPORT.md) says where
each one goes and what to bring (`hi --doctor --json` answers most of it).
Anything exploitable goes privately, per
[docs/SECURITY.md](docs/SECURITY.md#reporting-a-vulnerability). A change:
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the gate, what a review
bounces on, and which docs change with what; who decides is
[docs/GOVERNANCE.md](docs/GOVERNANCE.md).

## AI usage

Heavily inspired by
[Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency).

This started as code written entirely by
[me](https://github.com/ivylikethevine), but I have used generative AI to write
large parts of it. All of the code here is my _responsibility_ regardless: AI
is a tool, not an owner of a project. I have personally understood, reviewed,
and approved all of the AI-generated code in this repository, and **mainline
releases** carry the same accountability to me as anything I write and publish
myself.

## Roadmap

The features and changes left to build; nothing here is parked or descoped.
One list, in the order the work is best done. An entry is deleted once its
**Ticks when** holds. What a release waits on is
[Release Stages](#release-stages).

- [ ] **The default preset leaves this machine alone** — shipped: `balanced`
      sets `_HI_DISABLE_LOCAL=1` and is a first install's default, its
      fallback for a name off the roster, and what one with no terminal
      writes; `everything` stays the shipped defaults, local styling
      included. `tests/scripts/install_run_test.sh` holds all three.
      **Ticks when:** the fast group runs green.

- [ ] **`hi --update` verifies by default** — shipped: only a tag signed by a
      key the checkout trusts moves it, and `_HI_UPDATE_UNSIGNED=1`, which
      replaces `_HI_UPDATE_SIGNED`, takes an unsigned or unknown one.
      `tests/scripts/update_test.sh` refuses each by default and takes each
      under the opt-out. **Ticks when:** that suite has run green on Linux,
      macOS, and Git Bash.

- [ ] **Every default and preset audited before the tag** —
      [CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break)
      freezes the name and default of all 45 rows of
      [SETTINGS.md's _Every setting_](docs/SETTINGS.md#every-setting) and the
      five presets, and a toggle removal is a 2.0. **Do:** read each row's
      default as a stranger's first run, with the two entries above as the
      known changes. **Ticks when:** the 1.0.0 release note lists the defaults
      that moved, or says none did.

- [ ] **The bootstrap names a missing `tar`** — shipped: the boot probe lists
      a 64-byte gzipped archive and exits 67 when the target's `tar` cannot,
      `hi` says "no tar that reads gzip" and hands over the host's session,
      and `hi --doctor <target>` says the same.
      `tests/hi/remote_test.sh` and `tests/hi/container_test.sh` hold both
      halves. **Ticks when:** the fast group and `--group bench` run green,
      and the payload badge is current.

- [ ] **fish 3.3 lands a fish session** — shipped: the floor is 3.3,
      Ubuntu 22.04's, through `tests/dockerfiles/fish33.Dockerfile`.
      `aliases.sh`'s sh-tier lookups are backticks, which fish reads as text,
      with a `command -v ... | read` rung for fish beside each
      ([HI.13](docs/GLOSSARY.md#hi13-command--v-fallthrough)), and the
      re-entry `return` became an `if` around `config.fish`.
      3.2 has no `--no-config` for the overlay parse gate, and 3.1's `-n`
      refuses every `export`, so both stay below it
      ([COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).
      **Ticks when:** the lint group's fish 3.3 floor and fish 4 ceiling, and
      the fast group, run green.

- [ ] **The client's terminfo rides** — an unknown `TERM`
      ([HI.22](docs/GLOSSARY.md#hi22-term-fallback-probe)) is swapped for
      `xterm-256color`, so kitty, ghostty, wezterm, foot, and rio users lose
      styled underlines and the kitty keyboard protocol on every target.
      **Do:** `infocmp -x "$TERM"` on the client (2-3 KB, those terminals
      only), `tic -x -o` into the session tree where the target has `tic`,
      `TERMINFO` exported for the session, the swap kept as the fallback.
      **Ticks when:** an `xterm-kitty` client gets `TERM=xterm-kitty` on a
      target with `tic` and `xterm-256color` on one without, each in a case.

- [ ] **Glyphs follow the target's locale** — the ASCII decision is the
      client's and ships as `_HI_ASCII`, so a target sitting in `LC_ALL=C`
      draws multibyte glyphs under a shell that counts bytes, and header lines
      wrap (`common/core.sh`'s `_hi_use_ascii` comment). **Do:** on the
      target, `locale -a` for the client's locale, else `C.UTF-8` where it
      exists, else ASCII. **Ticks when:** a target with no UTF-8 locale draws
      the header in ASCII, unwrapped, in a case.

- [ ] **The README opens with the pitch** — six persona stories run before
      _Installation_, 442 lines in all, and a stranger skims. **Do:** ten lines
      of what hi is, the install, one GIF; the stories move to
      [GETTING-STARTED.md](docs/GETTING-STARTED.md) or a tour page, their
      published GIF links unchanged. **Ticks when:** _Installation_ is on the
      first screen of the rendered README.

- [ ] **A `CHANGELOG.md` ships in the tarball** — shipped:
      `.github/scripts/changelog.sh` writes a release's entry from its PRs'
      release notes before the tag, and `release.yml`'s gate refuses a tag
      whose `CHANGELOG.md` does not open on its version
      ([RELEASING.md](docs/RELEASING.md#cutting-a-release)). **Ticks when:**
      the next release's tarball holds a `CHANGELOG.md` whose top entry is
      that release's note.

- [ ] **Apple's `container` CLI is proven, not read** — the row in
      [COMPATIBILITY.md's _Targets weighed and not shipped_](docs/COMPATIBILITY.md#targets-weighed-and-not-shipped)
      is written from Apple's command reference, and
      `.github/workflows/apple-container.yml` checks it on a hosted `macos-26`
      runner. **Do:** dispatch it. **Ticks when:** its grammar step is green
      and the row says what its runtime step found.

## Release Stages

What the 1.0 tag and the releases after it wait on, in order. An entry is
deleted once its **Ticks when** holds. _Post 1.0_ entries are outside this
checkout: an account or an upstream review that lands when it lands.

- [ ] **I.** _At the 1.0.0 tag:_ **A stability contract is written down** —
      [docs/CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break).
      **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
      versions_ prose into its version table.

- [ ] **II.** _Post 1.0:_ **tldr page** — `docs/tldr.md` matches `docs/hi.1`
      and upstream style. **Do:** open the PR against tldr-pages. **Ticks
      when:** merged.

- [ ] **III.** _Post 1.0:_ **AUR** — registration is closed to new accounts, so
      `publish-external.yml`'s `aur` job is written but unexercised. **When
      it reopens:** register, add `AUR_SSH_KEY` as a repository secret,
      and push each package once by hand
      ([docs/RELEASING.md](docs/RELEASING.md#aur)). **Ticks when:** both
      packages are live and a dispatch has kept `say-hi` current for one
      release.

- [ ] **IV.** _Post 1.0:_ **nixpkgs** — the flake in this repository is the
      nix channel until then
      ([docs/RELEASING.md](docs/RELEASING.md#channels-weighed-and-not-shipped)).
      **Do:** open the package PR against nixpkgs, with a maintainer entry.
      **Ticks when:** merged, and one release's bump has landed through the
      usual update bot or by hand.

## License

[MIT](LICENSE.md).
