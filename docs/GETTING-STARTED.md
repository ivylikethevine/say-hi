# Getting started

What hi is, the words these docs use for it, where to begin for the way you
work, and a story a feature. Every flag is in [USAGE.md](USAGE.md) and every
setting in [SETTINGS.md](SETTINGS.md); when something does not behave,
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Contents

- [What hi is](#what-hi-is)
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

## What hi is

`hi <host>` is `ssh <host>` with your shell setup along. The session opens
with your prompt, your aliases, and your editor configs, on a host that has
none of them, and what hi put there is removed when the session ends. hi
installs nothing on the host and writes to none of its files: everything
lands in one temporary directory
([SECURITY.md](SECURITY.md#what-hi-writes-on-a-target)).

The same command opens a session in a running container, a Nomad allocation,
or a Kubernetes pod, and anything hi does not recognize goes to `ssh`
unchanged.

## The words these docs use

| word    | what it means                                                                                                                                                                                 |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| target  | where a session opens: an ssh host, a container, an allocation, or a pod                                                                                                                      |
| client  | the machine you type `hi` on                                                                                                                                                                  |
| session | the shell hi starts on a target, from connect to exit                                                                                                                                         |
| backend | how a target is reached: `ssh`, `docker` and the CLIs that speak its grammar, `nomad`, or `kube`                                                                                              |
| payload | hi's own files, sent to the target on every connect; the README's badge is its size                                                                                                           |
| overlay | `~/.config/say-hi/`, the directory of your files that hi sends beside the payload                                                                                                             |
| rides   | is sent to targets. "Your `~/.vimrc` rides" means every target gets it; "stays home" is the opposite                                                                                          |
| member  | one file of the overlay, by the name it rides under (`vim/vimrc`, `aliases.sh`)                                                                                                               |
| plugin  | one tool's configs and what points the tool at them on a target; `hi --plugins` lists them                                                                                                    |
| header  | the block of host facts hi prints on connect, with the package check                                                                                                                          |
| tier    | how much of hi a target's shell can run: the full session needs `bash`, and a target without it gets aliases and a colored prompt ([Compatibility](COMPATIBILITY.md#the-shell-you-end-up-in)) |
| wired   | of a shell on the client: its rc file sources hi, which `hi --install` sets up                                                                                                                |

## Pick a path

### A machine and a few hosts

For a first install, with the defaults.

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # or any directory you like
~/say-hi/scripts/install.sh
exec $SHELL
hi <host>
```

The install wires your login shell, asks which preset to start from
([SETTINGS.md](SETTINGS.md#presets); `balanced`, the default, leaves this machine as it is), and makes
no other choice for you. Then, in the order they tend to come up:

- `hi --doctor` says what is wired and what would be sent; `hi --doctor <host>`
  adds one host.
- `hi --configure` picks a preset, then opens every setting in your editor.
- `hi <TAB>` lists the hosts of `~/.ssh/config` and every running container.
- `hi --add-tag <host> prod`, then `prod = "red"` under `[hosttag]` in
  `hi --edit colors`, colors the hosts you should be careful on
  ([COLORS.md](COLORS.md)).
- `hi --uninstall` takes it all back out.

### Several machines and your own dotfiles

hi has two things of yours to keep in step between machines: the rc lines and
the overlay.

- **The rc lines.** `scripts/install.sh --print-rc` prints each shell's block
  and writes no rc file. Put the block in the rc your dotfile manager deploys:
  it looks for the tree in `$HOME` and where a package puts it, and tests for
  it first, so the one rc works on a machine with either and on one without
  say-hi.
- **The overlay.** Point the manager at `~/.config/say-hi/`; it is plain
  files, symlinks included
  ([SETTINGS.md](SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager) on who
  owns `settings.sh`).
- **A new machine** is then a clone and one command
  ([Installing without a terminal](#installing-without-a-terminal)).

Configs you already keep ride from where their tools read them, with nothing
to copy: `~/.vimrc`, `~/.tmux.conf`, a starship or powerlevel10k config
([SETTINGS.md](SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)). A
shell rc is the exception, since it is where tokens live: it rides only once
you link it into the overlay. `hi --keep <host>` holds a session open across
a dropped link or a change of machine
([INTEGRATIONS.md](INTEGRATIONS.md#terminal-multiplexers)).

### The least hi can do

For hosts where what is sent, and what runs, has to be accounted for.

```sh
~/say-hi/scripts/install.sh --preset lean
```

`lean` sends hi's own files and nothing of yours, draws hi's own prompt so no
prompt program runs on a target, leaves this machine's shells alone, and
starts no backend CLI ([SETTINGS.md](SETTINGS.md#presets)). One more, a line
in `~/.config/say-hi/settings.sh`:

```sh
export _HI_DISABLE_CONTROLMASTER=1   # your ssh config's ControlMaster line decides
```

`hi --update` already takes only a tag it can verify.

- `hi --doctor` lists every setting away from its default and every file that
  rides, and flags a secret-shaped line in one.
- `hi --plain <host>` is a session with nothing sent at all, and
  `export _HI_PLAIN=1` in `~/.config/say-hi/settings.prod.sh` makes it the
  rule for every host tagged `prod`
  ([SETTINGS.md](SETTINGS.md#settings-by-host-tag)).
- What hi writes on a target, what a target is trusted with, and how a
  release is verified are [SECURITY.md](SECURITY.md) and
  [PACKAGING.md](PACKAGING.md#verifying-a-release-download).

## A tour

One story a feature: a problem, the GIF that shows hi answering it, and the
config it was recorded with. Most leave the laptop as it is
(`_HI_DISABLE_LOCAL=1`), so the outside prompt is its own and hi begins at the
target.

### Your aliases, in every shell, on every host

_Your aliases live in one rc file on one machine, and the boxes you work on
have none of them - some don't even run your shell._ `~/.config/say-hi/` rides
along on every connect: Rio, an operator in fish at a workstation, uses one
`aliases.sh` alias in a bash session on a debian container (docker) and a fish
session on an alpine box (podman). A box with no bash gets the aliases-only
tier ([docs/COMPATIBILITY.md](COMPATIBILITY.md#the-shell-you-end-up-in)).

**Config:** fish's own prompt at home and hi's on the boxes, the header
trimmed to the clocks, the backend counts, and the check on a blue-to-red
`[palette]` in a `colors` overlay, and the styled tool aliases
(`_HI_TOOL_ALIASES=1`).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your editors and your git

_On a shared box, `vim` opens on the box's settings, `sudo vim` on root's, and
`git` knows none of your aliases._ Maya, a developer in zsh on a Mac, opens
nano and vim on the team's dev box with the nanorc and vimrc kept at home
(line numbers, a status line), then `sudo vim` on the same vimrc, then
`git st` and `git lg`. The git identity rides; the credential helper and the
keys stay home ([docs/INTEGRATIONS.md](INTEGRATIONS.md#git)). Nothing is
installed on the box or left running there.

**Config:** the box's starship draws the prompt (`_HI_PROMPT_TOOL=starship`)
and hi keeps the rest, the sudo alias (`_HI_SUDO_ALIAS=1`), the git plugin
(`hi --enable-plugin git`), and the compact header.

![nano and vim with the carried rc files, sudo vim on the same vimrc, and git aliases, inside a session](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know where you are at a glance

_A prod terminal and a dev terminal look the same until the wrong command runs
in one._ Kai, a sysadmin in bash on a laptop, tags the prod database with
`hi --add-tag`, checks what every host resolves to with `hi --preview colors`,
and connects: the prod host lands in red with the longer header its tag's
`settings.prod.sh` asks for, and the dev host in green. Both boxes are fish,
and Kai's own two-line fish prompt rides along, drawn on the colors hi
resolved.

**Config:** hosttag pins and a hex `[scheme]` in a `colors` overlay, hi's
prompt on the laptop too (`_HI_PROMPT_TOOL=hi`), and a `settings.prod.sh`
([Settings by host tag](SETTINGS.md#settings-by-host-tag)).

![hi --add-tag, hi --preview colors, then hi into a prod-tagged host with a red prompt and a longer header and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One command, every backend

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

### Survive a dropped link

_A long job over a flaky link dies with the link._ Noor, on call in zsh on a
MacBook over hotel wifi, starts a backfill on the prod database box under
`hi --keep`. The link drops mid-job (the recording cuts it from the box's
end); hi says how long the box keeps the session, retries every five seconds,
and is back in the same tmux pane with the job still running. A box with no
tmux, zellij, or screen keeps the session's files and directory through the
drop instead ([HI.65](GLOSSARY.md#hi65-kept-session)).

**Config:** a three-cell header. `_HI_KEEP=1`, in `settings.sh` or a tag's
file, makes every connect a kept one.

![hi --keep into a prod box, a backfill running, the link dropping, hi retrying, and the same tmux pane back with the job still going](https://ivylikethevine.github.io/say-hi/docs/tapes/keep.gif)

### The header tells you what's missing

_You find out a box lacks `rsync` or `tmux` halfway through the job that needed
it._ Sam, running a homelab from bash on an Ubuntu laptop, keeps the homelab
toolbox in a `packages` file of their own, then connects to the nas and the
pihole: one quiet line on the box that has them, a loud one on the box that
does not.
Groups switch on and off, and a `packages` file of your own replaces the
shipped one ([docs/COLORS.md](COLORS.md#the-package-checks-rows)).

**Config:** hi's prompt off (`_HI_DISABLE_PROMPT=1`), so each box keeps its
distro's own while the header, the check, and the aliases ride anyway, the
`core` and `useful` groups on, and every address shown (`_HI_IP_HIDE=none`).

![hi's header package check on a box with the tools installed and on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### Every target in one tab

_Which box is an ssh host, and which a container, an allocation, or a pod?_
`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation, and pod, each tagged with its backend;
`hi --<TAB>` answers hi's own flags without waking a backend. Rio again, in
fish, whose pager shows the backend column.

**Config:** no cached sweep (`_HI_TARGETS_TTL=0`).

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

## Installing without a terminal

With no terminal the install asks nothing: it takes `balanced`, or the preset
named.

```sh
git clone https://github.com/ivylikethevine/say-hi "$HOME/say-hi"
"$HOME/say-hi/scripts/install.sh" --preset balanced --shell bash,zsh </dev/null
```

From a package, the tree is already in place and each user runs
`hi --install --preset balanced`.

- The exit status is 0 only when every rc file was written: an rc that fails
  its syntax check stops the run before any write (`--yes` goes on), and one
  hi cannot write is named, with its lines, at the end.
- `--print-rc` in place of the write, for an rc the script does not own.
- `--link none` where `~/.local/bin` is not yours to link into; the wired
  shells alias `hi` either way.
- `--dry-run` prints every write and makes none.
- Re-running is safe: it repairs hi's own lines and leaves the rest.
