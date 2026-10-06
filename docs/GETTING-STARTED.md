# Getting started

What hi is, the words these docs use for it, and where to begin for the way
you work. Every flag is in [USAGE.md](USAGE.md) and every setting in
[SETTINGS.md](SETTINGS.md); when something does not behave,
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Contents

- [What hi is](#what-hi-is)
- [The words these docs use](#the-words-these-docs-use)
- [Pick a path](#pick-a-path)
  - [A machine and a few hosts](#a-machine-and-a-few-hosts)
  - [Several machines and your own dotfiles](#several-machines-and-your-own-dotfiles)
  - [The least hi can do](#the-least-hi-can-do)
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
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # the directory has to be named say-hi
~/say-hi/scripts/install.sh
exec $SHELL
hi <host>
```

The install wires your login shell, asks whether hi styles this machine too,
and makes no other choice for you. Then, in the order they tend to come up:

- `hi --doctor` says what is wired and what would be sent; `hi --doctor <host>`
  adds one host.
- `hi --configure` is the settings menu, under a preview of each change.
- `hi <TAB>` lists the hosts of `~/.ssh/config` and every running container.
- `hi --add-tag <host> prod` and `hi --set-color hosttag prod red` color the
  hosts you should be careful on ([COLORS.md](COLORS.md)).
- `hi --uninstall` takes it all back out.

### Several machines and your own dotfiles

hi has two things of yours to keep in step between machines: the rc lines and
the overlay.

- **The rc lines.** `scripts/install.sh --print-rc` prints each shell's block
  and writes no rc file. Put the block in the rc your dotfile manager deploys:
  it names the tree through `$HOME` and tests for it first, so the one rc
  works on a machine without say-hi.
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
starts no backend CLI ([SETTINGS.md](SETTINGS.md#presets)). Two more, each a
line in `~/.config/say-hi/settings.sh`:

```sh
export _HI_DISABLE_CONTROLMASTER=1   # your ssh config's ControlMaster line decides
export _HI_UPDATE_SIGNED=1           # hi --update takes only a tag it can verify
```

- `hi --doctor` lists every setting away from its default and every file that
  rides, and flags a secret-shaped line in one.
- `hi --plain <host>` is a session with nothing sent at all, and
  `export _HI_PLAIN=1` in `~/.config/say-hi/settings.prod.sh` makes it the
  rule for every host tagged `prod`
  ([SETTINGS.md](SETTINGS.md#settings-by-host-tag)).
- What hi writes on a target, what a target is trusted with, and how a
  release is verified are [SECURITY.md](SECURITY.md) and
  [PACKAGING.md](PACKAGING.md#verifying-a-release-download).

## Installing without a terminal

With no terminal the install asks nothing: it takes the defaults, or a preset.

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
