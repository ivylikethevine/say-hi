# Settings

Your config lives **outside the checkout**, in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` (`$_HI_CONFIG_DIR`). `colors` and
`packages` there override the tree's copies one file at a time, so anything you
haven't overridden keeps tracking what `hi --update` delivers. `aliases.sh`
loads **before** the tree's own, so any `_HI_*_OPTS` value or `_HI_DISABLE_*`
toggle you set there takes effect before hi builds anything from it; an
`alias` you define there does not win over the same name shipped after it —
turn the shipped family off with its toggle and define your own instead.
`settings.sh` has no in-tree counterpart: `hi --configure` only ever writes it
here. (The tree's own `settings/` directory is the shipped defaults those
files override; this page is what _you_ can set, and what each setting does.)

Four of those files can also live somewhere else entirely — see
[Pointing one file somewhere else](#pointing-one-file-somewhere-else).

| overlay file                   | overrides           | what it is                                                                                                                                    |
| ------------------------------ | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.config/say-hi/settings.sh` | -                   | what `hi --configure` writes                                                                                                                  |
| `~/.config/say-hi/colors`      | `settings/colors`   | your color pins                                                                                                                               |
| `~/.config/say-hi/packages`    | `settings/packages` | what the package check looks for                                                                                                              |
| `~/.config/say-hi/vim.rc`      | `settings/vim.rc`   | your vim config, used by the `vim` alias and `$VIMINIT` - replaces hi's default wholesale, so carry the OSC 52 yank block over if wanted      |
| `~/.config/say-hi/nano.rc`     | `settings/nano.rc`  | the same for nano, used by the `nano` alias                                                                                                   |
| `~/.config/say-hi/aliases.sh`  | -                   | your own flags and aliases, sourced **first** so your `_HI_*_OPTS`/toggles land before the shipped aliases are built - same POSIX+fish subset |
| `~/.config/say-hi/bash.sh`     | -                   | your bash preferences, sourced at the end of `common/bash.sh` - history sizing, `shopt`s, readline bindings                                   |
| `~/.config/say-hi/zsh.zsh`     | -                   | the same for zsh - history, keybindings, `zstyle` completion rules                                                                            |
| `~/.config/say-hi/config.fish` | -                   | the same for fish - keybindings and the `fish_color_*` / `fish_pager_color_*` palette                                                         |

This keeps configuring say-hi from dirtying the checkout (so `git pull` keeps
applying cleanly) and lets the tree be root-owned, installed by a package
manager. All of it rides along to every host you say `hi` to, in its own small
archive.

Want history on it? `hi --overlay-init` makes `~/.config/say-hi` a git repo _in
place_: from then on `hi --configure` commits its own writes, `hi --doctor`
reports the commit count, and a push remote is one `git remote add` away. If
you already keep dotfiles in chezmoi, yadm, GNU Stow or a bare repo,
[that directory is the whole integration](#keeping-the-overlay-in-a-dotfile-manager).

Every setting below is an environment variable, checked where it is used.
`hi --configure` writes your answers to `settings.sh` — a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh and fish — which
every shell sources ahead of `common/paths.sh`. Exporting any of them by hand
works just as well and takes precedence for that shell. One thing an
`export` does not do is reach programs you start from a hi shell: once the rc
has run, every `_HI_*` name except eight is a plain shell variable, so a
child sees an ordinary environment (which names, and why, is
[HI.47](GLOSSARY.md#hi47-what-a-child-inherits)). A setting you need a
child to see - a script of your own reading `$_HI_COLORS`, say - is an
`export` in the overlay's `bash.sh`/`zsh.zsh`/`config.fish`, which run last.

## Contents

- [How it works](#how-it-works)
- [Every setting](#every-setting)
  - [Pointing one file somewhere else](#pointing-one-file-somewhere-else)
  - [Not settings](#not-settings)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)
- [Presets](#presets)
- [Features](#features)
- [Colors](#colors)
  - [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)
- [Header details](#header-details)
  - [Others](#others)
- [Everything else](#everything-else)

## How it works

1. `hi.sh` runs on the client, tars `say-hi/` and sends it to the target, which
   unpacks it into a `/tmp` directory. `$_HI_PAYLOAD` at the top of `hi.sh` is
   the allow list — no `.git`, `scripts/`, `tests/`, `docs/` or CI. Your
   overlay follows in a second, much smaller archive, landing in a `config/` of
   its own so your `aliases.sh` stays additive. A target that already has its
   own `say-hi` gets neither: hi loads that tree in place and it reads its own
   overlay.
2. Both are base64-armored into one script written over the **stdin** of an ssh
   connection the session then reuses — not argv, which Linux caps at 128KB
   however big `ARG_MAX` says. Every shell file is comment-stripped on the way
   in (about 40% of it); `_HI_KEEP_COMMENTS=1` ships the tree verbatim.
3. That assembled script is what `hi` prints the size of on connect and what
   the payload badge measures, for a _default_ configuration — a client whose
   overlay turns off the editor overrides, OSC 52 or `hi_notify` sends less.
   It is the per-session wire cost, not the package badge beside it, which is
   what a release downloads (`scripts/` and the docs ship in a package, never
   over the wire).
4. On the target, `load.sh` prints the header, writes hi's per-shell rc files
   into a scratch directory of its own
   ([HI.46](GLOSSARY.md#hi46-session-rc-directory)) - the target's own login
   files are never written - and drops you into **your login shell** when hi
   styles it (bash, zsh, fish), else the best the target has of `$_HI_SHELL_TREE`
   (`fish > zsh > bash > dash > ash > sh`); `_HI_SHELL_PREFERENCE` is that rule
   as a setting. With no bash at all the choice comes from `$_HI_SHELL_LADDER`,
   the same list without bash.
5. On exit, `load.sh`'s on-exit hook removes the `/tmp` directory, the scratch
   rc directory. A dropped connection is an exit: the hook runs on `SIGHUP`
   too, so a Wi-Fi blip or a closed laptop lid ends the session and cleans
   up, with nothing left to reconnect to. Run `hi` inside `tmux` or `screen`
   on the _client_ if you need to survive drops; persistent sessions on the
   target are [not scheduled](ROADMAP.md#not-scheduled).
6. `hi <target> 'some command'` skips the session and runs the command there,
   the way `ssh` does.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session — the best plain shell it has, with the aliases loaded. For ssh targets
hi first checks, over the same connection, whether a permanent say-hi is
already there: it reads the `_HI_HOME` line `install.sh` wrote into that
target's login rc files (or `/etc/profile.d` for a packaged install), then
falls back to the home directory, then to the places an install lands when
nothing declared it — `~/.local/share`, `/usr/local/share`, `/opt`,
`/usr/share` and Homebrew's default keg prefixes. `hi --doctor` prints the wire
size and the unpacked size, labeled.

## Every setting

The whole vocabulary a `settings.sh` may use, in the order `hi --configure`
asks for it; the sections it links to are the explanations. The **set by**
column says what a name is for:

- **you** — supported surface nothing asks you about: export it, or write an
  `export` line into `settings.sh` by hand.
- **`hi --configure`** — the same, with a question attached; these are the only
  variables the wizard writes. **advanced** marks the ones behind the wizard's
  last question, which one Enter skips: they keep whatever they hold.
- **hi** — hi's own, listed because a `settings.sh` _can_ set it and something
  will happen. hi sets these per session, from the client; overriding one tells
  the target something untrue about where it is.

`common/core.sh`'s `_HI_TOGGLES` and `scripts/configure.sh`'s prompt rosters are checked
against this table by the lint group, so a new setting cannot land without a
row here.

| variable                     | default                                              | set by                    | what it does                                                                                               |
| ---------------------------- | ---------------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`         | `0`                                                  | `hi --configure`          | [Features](#features) - the whole connect/disconnect header                                                |
| `_HI_DISABLE_PROMPT`         | `0`                                                  | `hi --configure`          | [Features](#features) - the colored `user@host` prompt                                                     |
| `_HI_DISABLE_GIT_STATUS`     | `0`                                                  | `hi --configure`          | [Features](#features) - the git segment in the prompt                                                      |
| `_HI_DISABLE_EDITORS`        | `0`                                                  | `hi --configure`          | [Features](#features) - the `vim`/`nano` config overrides                                                  |
| `_HI_DISABLE_BAT_ALIAS`      | `0`                                                  | `hi --configure`          | [Features](#features) - rebinding `cat`/`catn` to a styled `bat`                                           |
| `_HI_DISABLE_EZA_CONFIG`     | `0`                                                  | `hi --configure`          | [Features](#features) - styling `eza` itself from hi's theme                                               |
| `_HI_DISABLE_LS_ALIASES`     | `0`                                                  | `hi --configure`          | [Features](#features) - the `exa`/`eza` ls-family aliases                                                  |
| `_HI_DISABLE_OSC52`          | `0`                                                  | `hi --configure`          | [Features](#features) - the OSC 52 clipboard                                                               |
| `_HI_DISABLE_NOTIFY`         | `0`                                                  | `hi --configure`          | [Features](#features) - the `hi_notify` desktop-notification alias                                         |
| `_HI_DISABLE_MARKS`          | `0`                                                  | `hi --configure`          | [Features](#features) - OSC 133 prompt marks and OSC 7 cwd reporting                                       |
| `_HI_DISABLE_LOCAL`          | `0`                                                  | `hi --configure`          | [Features](#features) - all of the above, on this machine only                                             |
| `_HI_REMOTE_SESSION`         | `0`                                                  | hi                        | `1` inside a hi session, which is what `_HI_DISABLE_LOCAL` reads to tell local from remote                 |
| `_HI_HEADER_BANNER`          | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the `~~~ Connected ~~~` line                                           |
| `_HI_HEADER_TIMESTAMP`       | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the date/time line                                                     |
| `_HI_HEADER_SYSINFO`         | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the OS/CPU/RAM line                                                    |
| `_HI_HEADER_IDENTITY`        | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the git identity/containers/ssh key line                               |
| `_HI_HEADER_CHECK`           | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the installed-packages check                                           |
| `_HI_PACKAGES_MIN_PRIORITY`  | `1`                                                  | `hi --configure`          | [Everything else](#everything-else) - how far down `settings/packages` the check reports                   |
| `_HI_MAX_WIDTH`              | `80`                                                 | `hi --configure`          | [Everything else](#everything-else) - columns the header and banner are drawn to                           |
| `_HI_PROMPT`                 | unset                                                | `hi --configure`          | [Everything else](#everything-else) - `starship` hands the prompt to starship                              |
| `_HI_PROMPT_END`             | per shell                                            | you                       | [Everything else](#everything-else) - one prompt separator for every shell                                 |
| `_HI_PROMPT_END_BASH`        | `\$`                                                 | `hi --configure`          | [Everything else](#everything-else) - bash's separator; wins over `_HI_PROMPT_END`                         |
| `_HI_PROMPT_END_ZSH`         | `>`                                                  | `hi --configure`          | [Everything else](#everything-else) - zsh's separator                                                      |
| `_HI_PROMPT_END_FISH`        | `\|`                                                 | `hi --configure`          | [Everything else](#everything-else) - fish's separator                                                     |
| `_HI_PROMPT_END_SH`          | `\$`                                                 | you                       | the separator on a bash-less target, where hi bakes a plain `sh` prompt on the client                      |
| `_HI_TERM_FALLBACK`          | `1`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - swap an unknown `TERM` for `xterm-256color`                          |
| `_HI_RECENT`                 | `1`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - `0` stops recent targets being recorded and ranked first             |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - fish only: give every alias a real `abbr`                            |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE`                          | `hi --configure` advanced | [Everything else](#everything-else) - which shell a session runs in                                        |
| `_HI_ASCII`                  | by locale                                            | `hi --configure` advanced | [Everything else](#everything-else) - force ASCII stand-ins (`1`) or glyphs (`0`)                          |
| `_HI_TARGETS_TTL`            | `5`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - seconds `hi <TAB>` reuses its target list for                        |
| `_HI_PROBE_TIMEOUT`          | `2`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - seconds any one backend CLI gets                                     |
| `NO_COLOR`                   | unset                                                | you                       | [Everything else](#everything-else) - not hi's variable; any non-empty value drops color                   |
| `_HI_KEEP_COMMENTS`          | `0`                                                  | you                       | `1` ships the tree verbatim rather than comment-stripped, for reading real source on a target              |
| `_HI_RECENT_FILE`            | `$XDG_STATE_HOME/say-hi/recent`                      | you                       | [Everything else](#everything-else) - where those are kept                                                 |
| `_HI_COLORS`                 | overlay, else tree                                   | you                       | [Pointing one file somewhere else](#pointing-one-file-somewhere-else) - where the color pins are read from |
| `_HI_PACKAGES`               | overlay, else tree                                   | you                       | the same for the package check's list                                                                      |
| `_HI_VIMRC`                  | overlay, else tree                                   | you                       | the same for the vim config the `vim` alias and `$VIMINIT` point at                                        |
| `_HI_NANORC`                 | overlay, else tree                                   | you                       | the same for nano's                                                                                        |
| `_HI_BAT_OPTS`               | Monokai theme, `--tabs 2`, `changes,grid` style      | you                       | the flags the `bat`/`batn` aliases attach, set in your `aliases.sh` ahead of the tree's own                |
| `_HI_EXA_SHARED_OPTS`        | `-F -1 -l -m --group-directories-first`              | you                       | the flags the `exa`/`eza` aliases share before each one's own are appended                                 |
| `_HI_EXA_OPTS`               | `$_HI_EXA_SHARED_OPTS --group --no-filesize`         | you                       | the `exa` alias's flags (its predecessor's column set)                                                     |
| `_HI_EZA_OPTS`               | `$_HI_EXA_SHARED_OPTS` + smart-group + a time format | you                       | the `eza` alias's flags                                                                                    |
| `_HI_EZA_OPTS_SIZE`          | `$_HI_EZA_OPTS --total-size`                         | you                       | exported for an overlay's own use; no shipped alias reads it today                                         |
| `_HI_TARGET`                 | -                                                    | hi                        | the target as you typed it on the client                                                                   |
| `_HI_TARGET_COLOR`           | -                                                    | hi                        | the color that target resolved to, decided on the client so it matches everywhere                          |
| `_HI_TARGET_TAG`             | -                                                    | hi                        | the target's `# Tags:` value out of your `~/.ssh/config`                                                   |
| `_HI_HOST_COLOR`             | -                                                    | hi                        | [Your own prompt](#using-the-hash-in-your-own-prompt) - the hostname color, by name (zsh's `%F{}` form)    |
| `_HI_USER_COLOR`             | -                                                    | hi                        | the same for the username                                                                                  |
| `_HI_HOST_ESC`               | -                                                    | hi                        | the hostname color, as a raw ANSI escape (bash's form)                                                     |
| `_HI_USER_ESC`               | -                                                    | hi                        | the same for the username                                                                                  |
| `_HI_LOCAL_USER`             | -                                                    | hi                        | who you are on the client, for the header's "from" half                                                    |
| `_HI_LOCAL_HOSTNAME`         | -                                                    | hi                        | where you came from, likewise                                                                              |
| `_HI_RELEASE`                | -                                                    | hi                        | the client's version, so a session says which say-hi it is running                                         |

### Pointing one file somewhere else

`$_HI_CONFIG_DIR` moves the whole overlay. The four files inside it that have a
path variable of their own — `colors`, `packages`, `vim.rc` and `nano.rc` — can
each be moved on their own instead:

```sh
export _HI_COLORS="$HOME/dotfiles/hi-colors"     # in settings.sh, or the environment
```

That one file now comes from `~/dotfiles`; the other three go on resolving the
way they always did — the overlay's copy when you have made one, the tree's
otherwise. It wins even when `~/.config/say-hi/colors` also exists, which is
what makes it useful to a dotfile manager that would rather keep its own paths
than symlink into `~/.config/say-hi` (the whole-directory route is
[still there](#keeping-the-overlay-in-a-dotfile-manager) and is simpler when
you are moving all of it).

Two edges worth knowing. A value equal to what `common/paths.sh` would have
resolved to anyway is not treated as a choice — it is what a child shell
inherits from its parent, and re-resolving it is what lets
`_HI_CONFIG_DIR=elsewhere bash` mean something. And the four are read on every
source, so a shell already running does not notice a file you have only just
created; open a new one.

The other five overlay files have no such variable. `aliases.sh` and the three
per-shell files are sourced by a fixed name straight off `$_HI_CONFIG_DIR`, and
`settings.sh` is read before any of this happens.

### Not settings

Four more names look like settings and are not. `$_HI_CONFIG_DIR` and
`$_HI_HOME` are read **before** `settings.sh` is sourced, so a line in that
file is too late; export them in your environment instead, as `hi.sh` and
`install.sh`'s rc line do. `$_HI_ROOT` and `$_HI_SSH_CONFIG` are derived from
those two by `common/paths.sh` on every source, so an exported value does not
survive; point `$_HI_HOME` or `$HOME` elsewhere if you need them elsewhere.

`$_HI_CONFIG_DIR` is also the answer to "I want my config somewhere else":
exporting it moves the whole overlay, which is why a proposal to rename the
directory was declined —
[SUPPORT.md](SUPPORT.md#changes-proposed-and-not-made) has the
reasoning. Everything else beginning `_HI_` is internal state, named that way
to stay out of your namespace.

## Presets

`hi --configure` opens with a choice of starting point, and
`hi --configure --preset <name>` applies one without asking:

| preset       | what it answers                                                                                                                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | every feature and every header line on — the shipped defaults                                                                                                                                                                                            |
| `balanced`   | the header keeps its banner, system info and a shorter package check (`_HI_PACKAGES_MIN_PRIORITY=3`); the timestamp, identity line and `hi_notify` are off                                                                                               |
| `minimal`    | on targets only the colored prompt and the aliases: no header, git status, editors, clipboard, notifications or prompt marks — and nothing on this machine (`_HI_DISABLE_LOCAL=1`). The opt-in is off in every preset; it is only ever turned on by hand |

A preset is an absolute answer over the feature, header and prompt questions:
what it names is set, everything else in that vocabulary goes back to its
default, and the width, the prompt separators and the advanced settings keep
what they hold. Interactively, a preset's answers become the defaults for the
questions that follow, so it is a starting point rather than a lock; a second
prompt offers to take it as final and skip them. The rows are
`scripts/configure.sh`'s `_HI_PRESETS`.

## Features

Each is **on by default**; set it to `1` to turn that piece off.

| variable                 | turns off                                                                                                                         |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`     | the whole connect/disconnect header, every line of it                                                                             |
| `_HI_DISABLE_PROMPT`     | the colored `user@host` prompt, leaving your shell's own                                                                          |
| `_HI_DISABLE_GIT_STATUS` | the git segment in the prompt                                                                                                     |
| `_HI_DISABLE_EDITORS`    | the `vim`/`nano` config overrides                                                                                                 |
| `_HI_DISABLE_BAT_ALIAS`  | rebinding `cat`/`catn` to a styled `bat` - `bat`/`batcat`/`batn` themselves stay available by name either way                     |
| `_HI_DISABLE_LS_ALIASES` | the styled `exa`/`eza` aliases - the `exa`/`eza` binaries themselves stay available by name either way                            |
| `_HI_DISABLE_OSC52`      | the OSC 52 clipboard - yanks in `vim` and the `hi_copy` alias                                                                     |
| `_HI_DISABLE_NOTIFY`     | the `hi_notify` alias - desktop notifications when a command finishes. Also keeps `common/notify.sh` off the ssh payload entirely |
| `_HI_DISABLE_MARKS`      | the semantic prompt marks (OSC 133) and cwd reporting (OSC 7) every prompt emits, see below                                       |
| `_HI_DISABLE_LOCAL`      | all of the above **on this machine only** - hi still styles the hosts you visit                                                   |

## Header details

Each is **on by default**; set it to `0` to hide that line. All are ignored when
`_HI_DISABLE_HEADER=1`.

| variable               | hides                                                            |
| ---------------------- | ---------------------------------------------------------------- |
| `_HI_HEADER_BANNER`    | the `~~~ Connected [host] ~~~` line, on connect _and_ disconnect |
| `_HI_HEADER_TIMESTAMP` | the date/time line                                               |
| `_HI_HEADER_SYSINFO`   | the OS / CPU / RAM line                                          |
| `_HI_HEADER_IDENTITY`  | the git identity / containers / ssh key line                     |
| `_HI_HEADER_CHECK`     | the installed-packages check (`settings/packages`)               |

### Others

`_HI_DISABLE_LOCAL` is "leave my own machine alone, but give me hi everywhere I
connect to". It is told apart from a real session by `_HI_REMOTE_SESSION`,
which `load.sh` exports on a target and a local shell's own rc never does.

`_HI_DISABLE_OSC52` turns off the one feature that reaches back _through_ the
connection: a yank in `vim` on a target, or anything piped into `hi_copy`, is
base64'd into an
[OSC 52](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Operating-System-Commands)
escape and written to the tty, so your local terminal emulator puts it on
**your** clipboard — no X11 forwarding, no clipboard daemon, nothing installed
on the target. Only the unnamed register is sent, so `"ay` stays local.
Terminal support varies (tmux needs `set -g allow-passthrough on`; under
`$ZELLIJ` the escape goes through raw), which is why it is a toggle.
`common/osc52.sh` is the whole implementation.

**The header says so when tmux is going to eat it.** `allow-passthrough` has
been off by default since tmux 3.3, and nothing fails when it is: `hi_copy`
exits 0, the escape is swallowed on the way past, and the paste afterwards
hands back your previous clipboard. So a session that finds `$TMUX` set with
the option off prints one line on connect —

```text
 | tmux passthrough off - hi_copy/hi_notify muted | set -g allow-passthrough on
```

— and nowhere else. It has no toggle of its own: turn the option on, or turn
off the two features it is about, and it stops. A tmux too old to have the
option says nothing, since there would be no setting to point at.

`_HI_DISABLE_NOTIFY` turns off the other one. `hi_notify <command>` runs the
command on the target, then writes an
[OSC 9](https://iterm2.com/documentation-escape-codes.html) escape (and
iTerm2's older OSC 777 spelling) to the tty, so **your** terminal raises the
notification. The body is the command line and whether it succeeded, and
`hi_notify` exits with the command's own status, so it drops into a pipeline or
`&&` chain unchanged. It is opt-in per invocation, never a prompt hook — a
notification after every command is noise — for the same reason `hi_copy` is
opt-in per yank. Both escapes go out because `$TERM_PROGRAM` does not cross an
ssh connection, so an emulator implementing both shows the notification twice.
Multiplexer support follows the OSC 52 rule. `common/notify.sh` is the whole
implementation.

`_HI_DISABLE_MARKS` turns off the two escapes every hi prompt emits for
terminals that read them — kitty, WezTerm, ghostty, foot, iTerm2, Konsole:
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
marks where each prompt, command and output begins (jump between prompts,
select one command's output, see a failed command's status), and OSC 7 reports
the working directory (a new tab or split opens where you were, on that host).
Nothing is installed on the target and a terminal that does not know an OSC
drops it; fish 4 emits both itself, so there hi stays out of the way. Only the
styled shells emit them — the bash-less `sh` prompt does not.

### Shells you drop into inside a session

A `bash`, `zsh`, `fish` or `dash` started _inside_ a session keeps hi's
aliases, prompt and paths, and nothing had to be written to the target to
arrange it. `load.sh` writes one rc per shell into a scratch directory of its
own and exports `$_HI_SESSION_RC` at it:

- **zsh** through `$ZDOTDIR` and **sh/dash/ash** through `$ENV` - both are
  exported, so any such shell started in the session reads hi's rc however it
  was started, including by something that is not a shell;
- **bash** and **fish** have no equivalent variable (bash's `$BASH_ENV` covers
  only _non_-interactive shells), so `settings/aliases.sh` defines a wrapper
  for each that hands it the same file.

Each of those rc files sources the target's own `~/.bashrc` / `~/.zshrc` /
`~/.zshenv` first and hi's on top, so the host's configuration still applies
underneath. The mechanism is [HI.46](GLOSSARY.md#hi46-session-rc-directory).

What no wrapper can reach is a bash or fish shell nothing typed - a `tmux`
pane spawning a login shell, an editor shelling out - which comes up as the
host's own. hi writes nothing to any login file on any host you visit, under
any setting ([SUPPORT.md](SUPPORT.md#features-that-were-removed) has the
reasoning).

hi ships nobody's shell preferences — no history sizing, keybindings,
`zstyle` rules or fish palette of its own. Each rc carries the prompt, the
completions and the git segment, which are the product. Your own
`bash.sh`, `zsh.zsh` or `config.fish` in the config directory is sourced at
the end of hi's, in the same dialect, and wins - your own `HISTFILE`
included; hi sets none.
Your `aliases.sh` is different: it loads **before**
`settings/aliases.sh` (`sudo`, the `cat`/`bat` and `ls`/`eza` families), so a
`_HI_*_OPTS` value or `_HI_DISABLE_*` toggle you set there wins, but an
`alias` of the same name does not - the shipped one is defined after and
overwrites it.

## Keeping the overlay in a dotfile manager

There is no say-hi plugin for chezmoi, yadm, GNU Stow or a bare `$HOME` repo,
and there should not be: the overlay is a **plain directory of plain files**,
so pointing whichever tool you use at `~/.config/say-hi` is the whole
integration. The properties that make this true are pinned by cases in
`tests/hi/payload_test.sh`.

**Symlinks are fine, so Stow works.** hi dereferences on the way out, so a
target receives real file contents — a symlink per file, or the whole `say-hi`
directory as one link.

**Nothing but the overlay files travels.** `$_HI_OVERLAY_FILES` is an allow
list, so your manager's metadata (`.chezmoiignore`, templates), the `.git` that
`hi --overlay-init` creates, editor swap files and anything private sharing
that directory stay on your machine.

**Pick one keeper for the files a manager owns.** `hi --configure` writes
`settings.sh` in the **live** directory. If your manager also owns that file,
the two drift. Either let hi own `settings.sh` (exclude it from the manager),
or keep it managed and run your manager's re-add step
(`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.
Per-file managers leave everything they do not own alone, so a partly-managed
directory is a normal state, and `hi --overlay-init`'s git repo coexists with
them.

## Colors

Every username and hostname resolves to a color derived from its own name, so
an unpinned host looks the same from every machine you say `hi` from. Pin the
ones that matter in `~/.config/say-hi/colors`: `username,root,red`,
`hostname,bastion,yellow`, or `hosttag,prod,red` to color every host carrying a
`# Tags: prod` comment above its `Host` or `Match host` line in
`~/.ssh/config` — a wildcard block (`Host prod-*`) colors every name it covers.
A pin always beats the hash.

`hi --color-preview` shows every host in your ssh config and every user it
knows of, drawn in the colors themselves, each row naming the rule it matched:

![hi --color-preview: every ssh host and user in the colors they resolve to, then a prod host in red and a dev host in green](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### Using the hash in your own prompt

`_HI_DISABLE_PROMPT=1` [(Features)](#features) turns off hi's own
`user@host` prompt, but the per-host color hashing above is still resolved -
just into variables instead of a prompt, ready for your own `bash.sh` or
`zsh.zsh` (sourced at the end of hi's,
[above](#shells-you-drop-into-inside-a-session)) to use:

- `$_HI_HOST_ESC`/`$_HI_USER_ESC` — the raw ANSI escape, for a bash `PS1` to
  embed directly (wrap it in `\[ \]` so readline doesn't count its width):
  `PS1="\[$_HI_HOST_ESC\]\h\[$NC\] \w "`.
- `$_HI_HOST_COLOR`/`$_HI_USER_COLOR` — the color by name, for zsh's own
  `%F{}`: `PS1='%F{$_HI_HOST_COLOR}%m%f %~ '`.
- fish needs neither: `$fish_color_host`/`$fish_color_user` are already set
  by `common/config.fish`, unconditionally, for `set_color $fish_color_host`
  in your own `fish_prompt`.

All four update the moment the color pins above do - nothing to re-derive by
hand.

## Everything else

| variable                     | default                         | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ---------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_MAX_WIDTH`              | `80`                            | terminal columns the header and banner are drawn to                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_HOME`                   | derived                         | the **parent** of your `say-hi` directory - everything resolves `$_HI_HOME/say-hi`. Each entry point derives it from its own path when unset; set it to override                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_TARGETS_TTL`            | `5`                             | seconds `hi <TAB>` reuses its target list for; `0` disables the cache. For ten minutes past it an expired list still answers the TAB at once while the refresh runs behind it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_RECENT`                 | `1`                             | `1` appends every target a session ended cleanly on to a recent file, and `hi <TAB>` offers those first - most used and most recent ahead (zoxide's frecency). Client-side only: a target never sees the file. `0` neither records nor ranks                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_RECENT_FILE`            | `$XDG_STATE_HOME/say-hi/recent` | that file (`~/.local/state/say-hi/recent` by default), one `<epoch>\t<target>` line per session, trimmed to the newest 300 past 500                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_PROBE_TIMEOUT`          | `2`                             | seconds any one backend CLI gets, during completion and in the header (a TERM, with a KILL 200ms behind it)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_SSH_CONFIG`             | `~/.ssh/config`                 | read-only: where ssh hosts and their `# Tags:` comments are read from. Derived from `$HOME` by `common/paths.sh` every time it is sourced, so exporting your own value does not survive                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_ASCII`                  | by locale                       | `1` forces ASCII stand-ins for the banner/prompt/packages glyphs (`^ ok x` for `↑ ✓ ✗`), `0` forces the glyphs; unset asks the locale, so a `LANG=C` target degrades cleanly instead of printing mojibake                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `NO_COLOR`                   | unset                           | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything without color, and hi ships your client-side choice to the target next to `_HI_ASCII`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_PROMPT`                 | unset                           | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, keeping hi's header and aliases. Never auto-detected; a target without starship silently keeps hi's own. hi does not ship starship - a multi-MB binary against a payload of some 50KB                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE`     | which shell a session runs in: an ordered list of `bash`/`zsh`/`fish`, plus `login` for "your own login shell". The default tail is `$_HI_SHELL_TREE` filtered to the shells hi styles (`fish zsh bash`) - the same list `hi.sh`'s no-bash `$_HI_SHELL_LADDER` is cut from. First one installed on the target wins; `bash` is the floor, since `load.sh` needs it                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_PROMPT_END`             | per shell                       | the character each prompt ends with, when you want the same one everywhere; the three below win over it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_PROMPT_END_BASH`        | `\$`                            | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root")                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_PROMPT_END_ZSH`         | `>`                             | zsh's prompt separator - zsh prompt escapes work, so `%#` behaves as anywhere else in `PS1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_PROMPT_END_FISH`        | `\|`                            | fish's prompt separator; root still gets `#` regardless                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_TERM_FALLBACK`          | `1`                             | on ssh targets missing a terminfo entry for your `TERM` (ghostty's `xterm-ghostty`, typically), swap it for `xterm-256color` before the session starts; `0` keeps the original                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_PACKAGES_MIN_PRIORITY`  | `1`                             | the lowest `settings/packages` priority the header's check prints, and the main dial on how long that check is. The file ranks every entry 0-3, and a line's leading mode character decides which states speak at all: `-` only when the line is missing (core tools, where present is not news), `+` only when something is installed (platform facts, where absent is noise), no flag both ways. `1` (the default) drops the trivia tier, `0` prints everything, `2` keeps useful tools and up, `3` leaves just the favorites and core alerts, and anything above `3` mutes the check entirely. An older overlay file still renders: priorities above 3 clamp to 3, and its unflagged lines speak both ways until a mode character is added. `hi --configure` asks for this with a live preview; `hi --packages-preview` marks the ranks it silences `below floor` |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                             | fish only: `1` gives every alias hi defines a real `abbr`, so it expands to the full command on the line before you run it - it rewrites what your command line and history say, hence opt-in (`hi_abbr_aliases` does the work and is callable by hand). Not in the `_HI_DISABLE_*` table since it is fish-specific, not one of `core.sh`'s shared toggles                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_TTY`                    | `[ -t 0 ]`                      | whether the container backends hand the session a tty (`docker exec -it` vs `-i`). Answered by probing stdin; set it to `1` or `0` to override, which is what a wrapper that knows better than the probe does. `docker exec -it` refuses outright when stdin is a pipe, so `hi <container> <cmd> \| ...` depends on this being right                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_SESSION_RC`             | `mktemp -d`                     | set by hi inside a session: the directory holding the per-shell rc files a nested `bash`/`zsh`/`fish`/`sh` reads, removed when the session ends. `$ZDOTDIR` and `$ENV` are exported alongside it, see [HI.46](GLOSSARY.md#hi46-session-rc-directory)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |

`_HI_TARGETS_TTL` and `_HI_PROBE_TIMEOUT` exist because completion runs on
**every TAB** and the header runs **before you get a shell**: a docker daemon
that is down or a `kubectl` pointed at a dead cluster would otherwise hang
there with no upper bound.
