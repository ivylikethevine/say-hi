# Troubleshooting

What it looks like, why, and the fix. `hi --doctor` checks most of these in
one pass, and `hi --doctor <target>` adds one target; start there. What is not
here goes to [SUPPORT.md](SUPPORT.md).

## Contents

- [Installing](#installing)
  - [`hi: command not found` after the install](#hi-command-not-found-after-the-install)
  - [The install says it cannot write an rc file](#the-install-says-it-cannot-write-an-rc-file)
  - [My dotfile manager keeps removing hi's lines](#my-dotfile-manager-keeps-removing-his-lines)
  - [On macOS, a new Terminal window in bash has no hi](#on-macos-a-new-terminal-window-in-bash-has-no-hi)
  - [A shell errors at start after I deleted the checkout](#a-shell-errors-at-start-after-i-deleted-the-checkout)
- [On your own machine](#on-your-own-machine)
  - [My own prompt changed, or every new shell prints a header](#my-own-prompt-changed-or-every-new-shell-prints-a-header)
  - [Opening a shell or pressing TAB is slow](#opening-a-shell-or-pressing-tab-is-slow)
- [Connecting](#connecting)
  - [`hi <name>` opened a container, not the host (or the reverse)](#hi-name-opened-a-container-not-the-host-or-the-reverse)
  - [I am asked to authenticate twice](#i-am-asked-to-authenticate-twice)
  - [No header, and a plain prompt, with a notice](#no-header-and-a-plain-prompt-with-a-notice)
  - [hi says its bootstrap never ran, then gives a plain session](#hi-says-its-bootstrap-never-ran-then-gives-a-plain-session)
  - [The session is gone after the connection dropped](#the-session-is-gone-after-the-connection-dropped)
- [In a session](#in-a-session)
  - [A line of my rc or my vimrc does nothing on a target](#a-line-of-my-rc-or-my-vimrc-does-nothing-on-a-target)
  - [neovim errors about a missing module](#neovim-errors-about-a-missing-module)
  - [My aliases are missing after `sudo -i` or `su -`](#my-aliases-are-missing-after-sudo--i-or-su--)
  - [A new tmux pane on the target is not hi's](#a-new-tmux-pane-on-the-target-is-not-his)
- [Still stuck](#still-stuck)

## Installing

### `hi: command not found` after the install

The shell you are in started before the install. Run `exec $SHELL`, or open a
new terminal. If it persists, that shell was not wired: the install wires
your login shell and any shell with an rc file already, so name the one you
use, `scripts/install.sh --shell zsh`. A script or another program needs
`~/.local/bin` on `PATH`; an interactive shell does not, since the wired
shells alias `hi`.

### The install says it cannot write an rc file

The file is read-only or belongs to a dotfile manager. Nothing was changed.
Run `hi --install --print-rc` and add the block it prints to the copy the
manager deploys
([SETTINGS.md](SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)).

### My dotfile manager keeps removing hi's lines

The same cause: the install wrote into the deployed file. Use `--print-rc`
as above.

### On macOS, a new Terminal window in bash has no hi

A login bash reads `~/.bash_profile`, not `~/.bashrc`. `hi --install` adds
the line that chains them, unless `~/.bash_login` is what your login bash
reads; `hi --doctor`'s `login-bash` row says which, with the line to add.

### A shell errors at start after I deleted the checkout

The rc still holds a block from before hi's lines tested for the tree. Remove
the lines ending `# added by hi during install` from that rc file.

## On your own machine

### My own prompt changed, or every new shell prints a header

hi styles the client too unless told not to. `hi --configure`, _This
machine_, or `export _HI_DISABLE_LOCAL=1` in `~/.config/say-hi/settings.sh`,
leaves this machine alone and keeps hi on targets.

### Opening a shell or pressing TAB is slow

A backend CLI that is installed but not answering is waited on, up to two
seconds: a docker with no daemon, a kubectl with an unreachable cluster.
`hi --doctor`'s backends section names it. Name the ones you never `hi` into
in `_HI_BACKENDS_OFF` ([SETTINGS.md](SETTINGS.md#every-setting)), or take
`containers`, `jobs`, and `pods` out of the header's order.

## Connecting

### `hi <name>` opened a container, not the host (or the reverse)

A `Host` entry in `~/.ssh/config` wins; any other name is tried as a
container, an allocation, and a pod before ssh. `hi --use ssh <name>` names
the backend outright ([COMPATIBILITY.md](COMPATIBILITY.md#what-ships)).

### I am asked to authenticate twice

hi makes two ssh calls a connect and shares one connection between them. That
sharing is off on a Git Bash or Cygwin client, and under
`_HI_DISABLE_CONTROLMASTER=1`.

### No header, and a plain prompt, with a notice

The target has no `bash`. hi's header and git segment need it; what is left
is the aliases and a colored prompt
([COMPATIBILITY.md](COMPATIBILITY.md#the-shell-you-end-up-in)).

### hi says its bootstrap never ran, then gives a plain session

The host forces a command on every login (`ForceCommand`, or `command=` on
the key), so nothing hi sends is run. That is the host's policy, not a fault
([SECURITY.md](SECURITY.md#what-runs-where)).

### The session is gone after the connection dropped

A session lasts as long as its connection, and its files go with it.
`hi --keep <host>` runs it in a multiplexer on the host, where the next
`hi <host>` reattaches; on a host with none, its files and directory wait
fifteen minutes for you
([INTEGRATIONS.md](INTEGRATIONS.md#terminal-multiplexers)).

## In a session

### A line of my rc or my vimrc does nothing on a target

A line that reads a file hi does not carry, or starts a plugin manager, is
disabled on the way out. `hi --doctor` names each by file and line; a
`# hi-allow` comment above one sends it as written
([SETTINGS.md](SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).

### neovim errors about a missing module

Only `init.lua` rides. A `require` of a module under `~/.config/nvim/lua/`
finds nothing on a target, and `hi --doctor` says how many files stay home.
An `nvim/init.lua` in the overlay that needs none is what targets get
instead.

### My aliases are missing after `sudo -i` or `su -`

A change of user starts that user's own shell from their own rc files.
`sudo <command>` keeps hi's aliases once the `sudo` alias is on
(`_HI_SUDO_ALIAS=1`).

### A new tmux pane on the target is not hi's

hi writes to no login file, so a shell that nothing typed is the host's own.
A kept session, `hi --keep`, opens every pane in hi's shell.

## Still stuck

`hi --doctor --json`, and for a target `hi --doctor --json <target>`, is what
a report needs ([SUPPORT.md](SUPPORT.md#what-to-include)).
