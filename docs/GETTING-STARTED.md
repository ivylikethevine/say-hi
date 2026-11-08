# Getting started

The words these docs use, where to begin for the way you work, and a story
per feature. What hi is and the first install are in
[the README](../README.md). Every flag is in [USAGE.md](USAGE.md), every
setting in [SETTINGS.md](SETTINGS.md), and fixes in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Contents

- [The words these docs use](#the-words-these-docs-use)
- [Pick a path](#pick-a-path)
  - [A machine and a few hosts](#a-machine-and-a-few-hosts)
  - [Several machines and your own dotfiles](#several-machines-and-your-own-dotfiles)
  - [The least hi can do](#the-least-hi-can-do)
- [A tour](#a-tour)
  - [Your aliases, in every shell, on every host](#your-aliases-in-every-shell-on-every-host)
  - [Your editors and your git](#your-editors-and-your-git)
  - [Know where you are at a glance](#know-where-you-are-at-a-glance)
  - [One command, every backend](#one-command-every-backend)
  - [Survive a dropped link](#survive-a-dropped-link)
  - [The header tells you what's missing](#the-header-tells-you-whats-missing)
  - [Every target in one tab](#every-target-in-one-tab)
- [Installing without a terminal](#installing-without-a-terminal)

## The words these docs use

| word    | what it means                                                                                             |
| ------- | --------------------------------------------------------------------------------------------------------- |
| target  | where a session opens: an ssh host, a container, an allocation, or a pod                                  |
| client  | the machine you type `hi` on                                                                              |
| session | the shell hi starts on a target, from connect to exit                                                     |
| backend | how a target is reached: `ssh`, `docker` (and the CLIs that work like it), `nomad`, or `kube`             |
| payload | hi's own files, sent to the target on every connect                                                       |
| overlay | `~/.config/say-hi/`, your files that hi sends beside the payload                                          |
| rides   | is sent to targets; "stays home" is the opposite                                                          |
| member  | one file of the overlay, by the name it rides under (`vim/vimrc`, `aliases.sh`)                           |
| plugin  | one tool's configs and the wiring that points the tool at them on a target; `hi --plugins` lists them     |
| header  | the block of host facts hi prints on connect, with the package check                                      |
| tier    | how much of hi a target's shell runs: bash gets everything, other shells get aliases and a colored prompt |
| wired   | of a shell on the client: its rc file loads hi, which `hi --install` sets up                              |

## Pick a path

### A machine and a few hosts

Install as in [the README](../README.md#in-sixty-seconds). The install asks
which [preset](SETTINGS.md#presets) to start from; `balanced`, the default,
leaves this machine as it is. Then, roughly in the order they come
up:

- `hi --doctor` says what is wired and what would be sent; `hi --doctor <host>`
  checks one host too.
- `hi --configure` opens every setting in your editor.
- `hi <TAB>` lists the hosts in `~/.ssh/config` and every running container.
- `hi --add-tag <host> prod`, then `prod = "red"` under `[hosttag]` in
  `hi --edit colors`, colors the hosts you should be careful on
  ([COLORS.md](COLORS.md)).
- `hi --uninstall` takes it all back out.

### Several machines and your own dotfiles

Keep two things in step between machines:

- **The rc lines.** `hi --install --print-rc` prints each shell's block
  without writing it. Put it in the rc your dotfile manager deploys; it works
  on a machine with say-hi cloned, packaged, or absent.
- **The overlay.** Point the manager at `~/.config/say-hi/`
  ([who owns `settings.sh`](SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)).

Configs you already keep ride from where their tools read them: `~/.vimrc`,
`~/.tmux.conf`, a starship or powerlevel10k config
([SETTINGS.md](SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).
Shell rcs are the exception, since that is where tokens live: one rides only
once you link it into the overlay.

### The least hi can do

For hosts where everything sent and run has to be accounted for:

```sh
~/say-hi/scripts/install.sh --preset lean
```

`lean` sends hi's own files and nothing of yours, draws hi's own prompt
everywhere, leaves this machine's shells alone, and starts no backend CLI
([SETTINGS.md](SETTINGS.md#presets)). To let your ssh config's
`ControlMaster` line decide too, add to `~/.config/say-hi/settings.sh`:

```sh
export _HI_DISABLE_CONTROLMASTER=1
```

- `hi --doctor` lists every changed setting and every file that rides, and
  flags a line that looks like a secret.
- `hi --plain <host>` sends nothing at all. `export _HI_PLAIN=1` in
  `settings.prod.sh` makes that the rule for hosts tagged `prod`
  ([SETTINGS.md](SETTINGS.md#settings-by-host-tag)).
- What hi writes on a target and how a release is verified:
  [SECURITY.md](SECURITY.md) and
  [PACKAGING.md](PACKAGING.md#verifying-a-release-download).

## A tour

One story per feature: a problem, the GIF of hi answering it, and the config
it was recorded with. Most turn hi off on the laptop
(`_HI_DISABLE_LOCAL=1`), so hi's styling starts at the target.

### Your aliases, in every shell, on every host

_Your aliases live in one rc file on one machine, and the boxes you work on
have none of them; some don't even run your shell._ Rio, in fish at a
workstation, uses one `aliases.sh` alias in a bash session on a debian
container and a fish session on an alpine box. A box with no bash still gets
the aliases ([COMPATIBILITY.md](COMPATIBILITY.md#the-shell-you-end-up-in)).

**Config:** fish's own prompt at home and hi's on the boxes, a header trimmed
to the clocks and backend counts, a blue-to-red `[palette]` in `colors`, and
the styled tool aliases (`_HI_TOOL_ALIASES=1`).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your editors and your git

_On a shared box, `vim` opens on the box's settings, `sudo vim` on root's, and
`git` knows none of your aliases._ Maya, in zsh on a Mac, opens nano and vim
on the team's dev box with the nanorc and vimrc kept at home, then `sudo vim`
on the same vimrc, then `git st` and `git lg`. The git identity rides; the
credential helper and keys stay home ([INTEGRATIONS.md](INTEGRATIONS.md#git)).

**Config:** the box's starship draws the prompt (`_HI_PROMPT_TOOL=starship`),
the sudo alias (`_HI_SUDO_ALIAS=1`), the git plugin
(`hi --enable-plugin git`), and the compact header.

![nano and vim with the carried rc files, sudo vim on the same vimrc, and git aliases, inside a session](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know where you are at a glance

_A prod terminal and a dev terminal look the same until the wrong command runs
in one._ Kai, in bash on a laptop, tags the prod database with
`hi --add-tag`, checks every host's color with `hi --preview colors`, and
connects: prod lands in red with a longer header from its tag's
`settings.prod.sh`, and dev in green. Kai's own fish prompt rides along,
drawn in the colors hi picked.

**Config:** hosttag pins and a hex `[scheme]` in `colors`, hi's prompt on the
laptop too (`_HI_PROMPT_TOOL=hi`), and a `settings.prod.sh`
([Settings by host tag](SETTINGS.md#settings-by-host-tag)).

![hi --add-tag, hi --preview colors, then hi into a prod-tagged host with a red prompt and a longer header and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One command, every backend

_ssh, `docker exec`, `nomad alloc exec`, and `kubectl exec` each want their own
syntax, and none of them knows your aliases._ Chen, in zsh on a Fedora
laptop, loops `hi <target> distro` (an alias from `aliases.sh`) over an ssh
host, a docker container, a nomad allocation, and a kubernetes pod. The pod
has no bash, so hi says so once and runs the alias anyway. `-F` is ssh's own
flag, passed through.

**Config:** an `aliases.sh` overlay; a one-off command draws no header.

![a for loop running one alias through hi over an ssh host, a docker container, a nomad allocation, and a kubernetes pod](https://ivylikethevine.github.io/say-hi/docs/tapes/run.gif)

### Survive a dropped link

_A long job over a flaky link dies with the link._ Noor, on call over hotel
wifi, starts a backfill on the prod database under `hi --keep`. The link
drops; hi retries every five seconds and is back in the same tmux pane with
the job still running ([how kept sessions work](INTEGRATIONS.md#terminal-multiplexers)).

**Config:** a three-cell header. `_HI_KEEP=1` makes every connect a kept one.

![hi --keep into a prod box, a backfill running, the link dropping, hi retrying, and the same tmux pane back with the job still going](https://ivylikethevine.github.io/say-hi/docs/tapes/keep.gif)

### The header tells you what's missing

_You find out a box lacks `rsync` or `tmux` halfway through the job that needed
it._ Sam keeps a homelab toolbox in a `packages` file, then connects to the
nas and the pihole: one quiet line on the box that has everything, a loud one
on the box that does not ([the package check](COLORS.md#the-package-checks-rows)).

**Config:** hi's prompt off (`_HI_DISABLE_PROMPT=1`), so each box keeps its
own while the header and aliases still ride; the `core` and `useful` groups;
every address shown (`_HI_IP_HIDE=none`).

![hi's header package check on a box with the tools installed and on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### Every target in one tab

_Which box is an ssh host, and which a container, an allocation, or a pod?_
`hi <TAB>` lists the `Host` entries in `~/.ssh/config` _and_ every running
container, allocation, and pod, each tagged with its backend. `hi --<TAB>`
lists hi's own flags without waking a backend.

**Config:** no cached list (`_HI_TARGETS_TTL=0`).

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

## Installing without a terminal

With no terminal the install asks nothing and takes `balanced`, or the preset
you name:

```sh
git clone https://github.com/ivylikethevine/say-hi "$HOME/say-hi"
"$HOME/say-hi/scripts/install.sh" --preset balanced --shell bash,zsh </dev/null
```

From a package, each user runs `hi --install --preset balanced`.

- It exits 0 only when every rc file was written. An rc that fails its syntax
  check stops the run before any write (`--yes` goes on anyway).
- `--print-rc` prints the lines instead of writing them.
- `--link none` skips the `~/.local/bin/hi` link; the wired shells alias `hi`
  either way.
- `--dry-run` prints every write and makes none.
- Re-running is safe: it repairs hi's own lines and leaves the rest.
