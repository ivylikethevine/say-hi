# A Tour of hi

One story a feature: a problem, the GIF that shows hi answering it, and the
config it was recorded with. [SETTINGS.md](SETTINGS.md) has every setting.
Most leave the laptop as it is (`_HI_DISABLE_LOCAL=1`), so the outside prompt
is its own and hi begins at the target.

## Contents

- [Your Aliases, in Every Shell, on Every Host](#your-aliases-in-every-shell-on-every-host)
- [Your Editors and Your Git](#your-editors-and-your-git)
- [Know Where You Are at a Glance](#know-where-you-are-at-a-glance)
- [One Command, Every Backend](#one-command-every-backend)
- [Survive a Dropped Link](#survive-a-dropped-link)
- [The Header Tells You What's Missing](#the-header-tells-you-whats-missing)
- [Every Target in One Tab](#every-target-in-one-tab)

## Your Aliases, in Every Shell, on Every Host

_Your aliases live in one rc file on one machine, and the boxes you work on
have none of them - some don't even run your shell._ `~/.config/say-hi/` rides
along on every connect: Rio, an operator in fish at a workstation, uses one
`aliases.sh` alias in a bash session on a debian container (docker) and a fish
session on an alpine box (podman). A box with no bash gets the aliases-only
tier ([docs/COMPATIBILITY.md](COMPATIBILITY.md#the-shell-you-end-up-in)).

**Config:** fish's own prompt at home and hi's on the boxes, the header
trimmed to the clocks, the backend counts, and the check on a blue-to-red
`_HI_PACKAGES_PALETTE`, and the styled tool aliases (`_HI_TOOL_ALIASES=1`).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

## Your Editors and Your Git

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

## Know Where You Are at a Glance

_A prod terminal and a dev terminal look the same until the wrong command runs
in one._ Kai, a sysadmin in bash on a laptop, tags the prod database with
`hi --add-tag`, checks what every host resolves to with `hi --preview colors`,
and connects: the prod host lands in red with the longer header its tag's
`settings.prod.sh` asks for, and the dev host in green. Both boxes are fish,
and Kai's own two-line fish prompt rides along, drawn on the colors hi
resolved.

**Config:** hosttag pins in a `colors` overlay, a hex `_HI_COLOR_SCHEME`, hi's
prompt on the laptop too (`_HI_PROMPT_TOOL=hi`), and a `settings.prod.sh`
([Settings by host tag](SETTINGS.md#settings-by-host-tag)).

![hi --add-tag, hi --preview colors, then hi into a prod-tagged host with a red prompt and a longer header and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

## One Command, Every Backend

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

## Survive a Dropped Link

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

## The Header Tells You What's Missing

_You find out a box lacks `rsync` or `tmux` halfway through the job that needed
it._ Sam, running a homelab from bash on an Ubuntu laptop, adds tools to the
check with `hi --add-package`, then connects to the nas and the pihole: one
quiet line on the box that has them, a loud one on the box that does not.
Groups switch on and off, and a `packages` file of your own replaces the
shipped one ([docs/COLORS.md](COLORS.md#the-package-checks-rows)).

**Config:** hi's prompt off (`_HI_DISABLE_PROMPT=1`), so each box keeps its
distro's own while the header, the check, and the aliases ride anyway, the
`core` and `useful` groups on, and every address shown (`_HI_IP_HIDE=none`).

![hi --add-package, then hi's header package check on a box with the tools installed and on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

## Every Target in One Tab

_Which box is an ssh host, and which a container, an allocation, or a pod?_
`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation, and pod, each tagged with its backend;
`hi --<TAB>` answers hi's own flags without waking a backend. Rio again, in
fish, whose pager shows the backend column.

**Config:** no cached sweep (`_HI_TARGETS_TTL=0`).

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)
