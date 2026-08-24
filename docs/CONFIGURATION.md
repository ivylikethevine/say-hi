# Configuration

Your config lives **outside the checkout**, in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` (`$_HI_CONFIG_DIR`). `colors`,
`packages` there override the tree's copies, one file at a
time - anything you haven't overridden keeps tracking the default the tree
ships, so `hi --update` still delivers changes to the rest. `aliases.sh` is the
one that adds rather than replaces, loading after the tree's own so yours win.
`settings.sh` has no in-tree counterpart at all: `hi --configure` only ever
writes it here.

| overlay file                   | overrides                   | what it is                                                                                                                                   |
| ------------------------------ | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.config/say-hi/settings.sh` | -                           | what `hi --configure` writes                                                                                                                 |
| `~/.config/say-hi/colors`      | `misc/colors`               | your color pins                                                                                                                              |
| `~/.config/say-hi/packages`    | `misc/packages`             | what the package check looks for                                                                                                             |
| `~/.config/say-hi/personal.sh` | -                           | your answer to hi's own preference aliases - sourced right after `misc/personal.sh`, before your `aliases.sh`, in the same POSIX+fish subset |
| `~/.config/say-hi/aliases.sh`  | -                           | your own aliases, sourced **last** of everything above so yours win - additive, never a replacement, and in the same POSIX+fish subset       |
| `~/.config/say-hi/bash.sh`     | `shells/bash_personal.sh`   | your bash preferences, sourced **after** hi's so yours win - history sizing, `shopt`s, readline bindings                                     |
| `~/.config/say-hi/zsh.zsh`     | `shells/zsh_personal.zsh`   | the same for zsh - history, keybindings, `zstyle` completion rules                                                                           |
| `~/.config/say-hi/config.fish` | `shells/fish_personal.fish` | the same for fish - keybindings and the `fish_color_*` / `fish_pager_color_*` palette                                                        |

This is what keeps configuring say-hi from dirtying the checkout (so
`hi --update`'s `git pull` keeps applying cleanly), and why the tree never has
to be writable at all - it can be root-owned, installed by a package manager.
All of it rides along to every host you say `hi` to, in its own small archive.

Want history on it? `hi --overlay-init` makes `~/.config/say-hi` a git repo _in
place_: from then on `hi --configure` commits its own settings writes,
`hi --doctor` reports the commit count, and a push remote is one
`git remote add` away. Entirely optional - and if you already keep dotfiles in
chezmoi, yadm, GNU Stow or a bare repo, [that directory is the whole
integration](#keeping-the-overlay-in-a-dotfile-manager).

Everything in the tables below is an environment variable, checked where it's
used. `hi --configure` writes your answers to `~/.config/say-hi/settings.sh`,
which every shell sources ahead of `common/paths.sh` - a plain `#!/bin/sh` script of
`export NAME=value` lines, valid in sh, bash, zsh and fish alike. You never have
to use `hi --configure`: exporting any of these by hand works just as well, and
takes precedence for that shell. [Every setting](#every-setting) is the roster
of what those names are; the exceptions - the handful `common/paths.sh` derives
on every source, so an exported value never lasts - are named under it.

## Contents

- [How it works](#how-it-works)
- [Every setting](#every-setting)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)
- [Features](#features)
- [Colors](#colors)
- [Two sessions to the same host](#two-sessions-to-the-same-host)
- [Header details](#header-details)
- [Everything else](#everything-else)

## How it works

1. `hi.sh` runs on the client, tars `say-hi/` and sends it to the target, which
   unpacks it into a `/tmp` directory. `$_HI_PAYLOAD` at the top of `hi.sh` is
   the authoritative allow list — no `.git`, `scripts/`, `tests/`, `docs/` or
   CI. Your overlay (the table above) follows in a second,
   much smaller archive, landing in a `config/` of its own so your `aliases.sh`
   stays additive. A target that already has its own `say-hi` gets neither: hi
   loads that tree in place and it reads its own overlay.
2. Both are base64-armored into one script and written over the **stdin** of an
   ssh connection the session then reuses — not argv, which Linux caps at 128KB
   however big `ARG_MAX` says it is. Every shell file is comment-stripped on
   the way into that archive — the checkout keeps its comments, the wire does
   not, which is about 40% of it; set `_HI_KEEP_COMMENTS=1` to ship the tree
   verbatim when you need to read the real source on a target.
3. That assembled script is what `hi` prints the size of on connect, and what
   the payload badge measures — for a _default_ configuration, since a client
   whose overlay turns off the editor overrides, the OSC 52 clipboard or
   `hi_notify` sends less. Read it as the per-session wire cost, not as the package badge beside
   it: that one is what a release downloads and what it occupies on disk, which
   is the larger figure, `scripts/` and the docs shipping in a package and
   never over the wire.
4. On the target, `load.sh` prints the header, appends hi's shell configs to
   the host's own rc files, and drops you into **your login shell** when hi
   styles it (bash, zsh, fish), else the best the target has of
   `$_HI_SHELL_TREE` — `fish > zsh > bash > dash > ash > sh`.
   `_HI_SHELL_PREFERENCE` is that rule as a setting. Where there is no bash at
   all the choice comes from `$_HI_SHELL_LADDER`, that same list with bash
   taken out.
5. On exit, `load.sh`'s `trap` strips those additions back out and the `/tmp`
   directory is removed.
6. `hi <target> 'some command'` skips the session and runs the command there
   instead, the way `ssh` does.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session — the best plain shell it has, with the aliases loaded, rather than the
full `load.sh`. For ssh targets hi first checks, over the same connection so it
costs no extra authentication, whether a permanent say-hi is already there; if
so it uses that in place and copies nothing. It does not assume `~/say-hi`: the
check reads the `_HI_HOME` line `install.sh` wrote into that target's login rc
files (or `/etc/profile.d` for a packaged install), then falls back to the home
directory, and finally to the places an install lands when nothing declared it —
`~/.local/share`, `/usr/local/share`, `/opt`, `/usr/share` and Homebrew's
default keg prefixes, which is what finds a `brew install`ed target that never
had its shells wired up. A tree installed anywhere is still found and reused.
`hi --doctor` prints the wire size and the unpacked size, labeled.

## Every setting

The tables further down explain what each setting _does_, and each is organised
around what it turns off. This one answers the other question - "what am I
allowed to put in `settings.sh`?" - by naming the whole vocabulary in one place,
in the order `hi --configure` asks for it. It is the index; the sections it
links to are the explanations.

The **set by** column says what a name is _for_:

- **you** - supported surface, and nothing asks you about it: export it, or
  write an `export` line into `settings.sh` by hand.
- **`hi --configure`** - the same, with a question attached. These are the only
  variables the wizard writes, so the column doubles as the list of what it can
  round-trip.
- **hi** - hi's own, listed because a `settings.sh` _can_ set it and something
  will happen, not because you should. hi sets these per session, from the
  client; overriding one is telling the target something untrue about where it
  is.

`common/core.sh`'s `_HI_TOGGLES` is checked against this table by the fast
group, so a tenth toggle cannot land without a row here.

| variable                     | default                     | set by           | what it does                                                                                  |
| ---------------------------- | --------------------------- | ---------------- | --------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`         | `0`                         | `hi --configure` | [Features](#features) - the whole connect/disconnect header                                   |
| `_HI_DISABLE_PROMPT`         | `0`                         | `hi --configure` | [Features](#features) - the colored `user@host` prompt                                        |
| `_HI_DISABLE_PERSONAL`       | `0`                         | `hi --configure` | [Features](#features) - hi's own shell preferences (not yours)                                |
| `_HI_DISABLE_GIT_STATUS`     | `0`                         | `hi --configure` | [Features](#features) - the git segment in the prompt                                         |
| `_HI_DISABLE_EDITORS`        | `0`                         | `hi --configure` | [Features](#features) - the `vim`/`nano` config overrides                                     |
| `_HI_DISABLE_ALIASES`        | `0`                         | `hi --configure` | [Features](#features) - the personal aliases in `misc/personal.sh`                            |
| `_HI_DISABLE_OSC52`          | `0`                         | `hi --configure` | [Features](#features) - the OSC 52 clipboard                                                  |
| `_HI_DISABLE_NOTIFY`         | `0`                         | `hi --configure` | [Features](#features) - the `hi_notify` desktop-notification alias                            |
| `_HI_DISABLE_LOCAL`          | `0`                         | `hi --configure` | [Features](#features) - all of the above, on this machine only                                |
| `_HI_REMOTE_SESSION`         | `0`                         | hi               | `1` inside a hi session, which is what `_HI_DISABLE_LOCAL` reads to tell local from remote    |
| `_HI_HEADER_BANNER`          | `1`                         | `hi --configure` | [Header details](#header-details) - the `~~~ Connected ~~~` line                              |
| `_HI_HEADER_TIMESTAMP`       | `1`                         | `hi --configure` | [Header details](#header-details) - the date/time line                                        |
| `_HI_HEADER_SYSINFO`         | `1`                         | `hi --configure` | [Header details](#header-details) - the OS/CPU/RAM line                                       |
| `_HI_HEADER_IDENTITY`        | `1`                         | `hi --configure` | [Header details](#header-details) - the git identity/containers/ssh key line                  |
| `_HI_HEADER_CHECK`           | `1`                         | `hi --configure` | [Header details](#header-details) - the installed-packages check                              |
| `_HI_HEADER_GHZ`             | `0`                         | you              | [Everything else](#everything-else) - GHz instead of MHz on the CPU line                      |
| `_HI_PACKAGES_MIN_PRIORITY`  | `1`                         | `hi --configure` | [Everything else](#everything-else) - how far down `misc/packages` the check reports          |
| `_HI_MAX_WIDTH`              | `80`                        | `hi --configure` | [Everything else](#everything-else) - columns the header and banner are drawn to              |
| `_HI_PROMPT`                 | unset                       | you              | [Everything else](#everything-else) - `starship` hands the prompt to starship                 |
| `_HI_PROMPT_END`             | per shell                   | you              | [Everything else](#everything-else) - one prompt separator for every shell                    |
| `_HI_PROMPT_END_BASH`        | `\$`                        | `hi --configure` | [Everything else](#everything-else) - bash's separator; wins over `_HI_PROMPT_END`            |
| `_HI_PROMPT_END_ZSH`         | `>`                         | `hi --configure` | [Everything else](#everything-else) - zsh's separator                                         |
| `_HI_PROMPT_END_FISH`        | `\|`                        | `hi --configure` | [Everything else](#everything-else) - fish's separator                                        |
| `_HI_PROMPT_END_SH`          | `\$`                        | you              | the separator on a bash-less target, where hi bakes a plain `sh` prompt on the client         |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE` | you              | [Everything else](#everything-else) - which shell a session runs in                           |
| `_HI_TERM_FALLBACK`          | `1`                         | you              | [Everything else](#everything-else) - swap an unknown `TERM` for `xterm-256color`             |
| `_HI_ASCII`                  | by locale                   | you              | [Everything else](#everything-else) - force ASCII stand-ins (`1`) or glyphs (`0`)             |
| `NO_COLOR`                   | unset                       | you              | [Everything else](#everything-else) - not hi's variable; any non-empty value drops color      |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                         | you              | [Everything else](#everything-else) - fish only: give every alias a real `abbr`               |
| `_HI_KEEP_COMMENTS`          | `0`                         | you              | `1` ships the tree verbatim rather than comment-stripped, for reading real source on a target |
| `_HI_TARGETS_TTL`            | `5`                         | you              | [Everything else](#everything-else) - seconds `hi <TAB>` reuses its target list for           |
| `_HI_PROBE_TIMEOUT`          | `2`                         | you              | [Everything else](#everything-else) - seconds any one backend CLI gets                        |
| `_HI_TARGET`                 | -                           | hi               | the target as you typed it on the client                                                      |
| `_HI_TARGET_COLOR`           | -                           | hi               | the color that target resolved to, decided on the client so it matches everywhere             |
| `_HI_TARGET_TAG`             | -                           | hi               | the target's `# Tags:` value out of your `~/.ssh/config`                                      |
| `_HI_LOCAL_USER`             | -                           | hi               | who you are on the client, for the header's "from" half                                       |
| `_HI_LOCAL_HOSTNAME`         | -                           | hi               | where you came from, likewise                                                                 |
| `_HI_RELEASE`                | -                           | hi               | the client's version, so a session says which say-hi it is running                            |

### Not settings

Four more names look like settings and are not. `$_HI_CONFIG_DIR` and
`$_HI_HOME` are read **before** `settings.sh` is sourced - `common/core.sh`
needs the first to find the file at all - so a line in that file is too late for
either; export them in your environment instead, which is what `hi.sh` and
`install.sh`'s rc line do. `$_HI_ROOT` and `$_HI_SSH_CONFIG` are derived from
those two by `common/paths.sh` on every source, so an exported value does not
survive; point `$_HI_HOME` or `$HOME` somewhere else if you need them elsewhere.

`$_HI_CONFIG_DIR` is also the answer to "I want my config somewhere else":
exporting it moves the whole overlay, which is why the directory's own name is
not a setting and why a proposal to rename it away from the XDG base was
declined -
[UNSUPPORTED.md](UNSUPPORTED.md#changes-proposed-and-not-made) carries that
reasoning.

Everything else beginning `_HI_` is internal state - glyph sets, color escapes,
completion caches, the shell and rc rosters - named that way to stay out of your
namespace, not to be set.

## Features

Each is **on by default**; set it to `1` to turn that piece off.

| variable                 | turns off                                                                                                                                                                                                                              |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`     | the whole connect/disconnect header, every line of it                                                                                                                                                                                  |
| `_HI_DISABLE_PROMPT`     | the colored `user@host` prompt, leaving your shell's own                                                                                                                                                                               |
| `_HI_DISABLE_PERSONAL`   | hi's own shell preferences - history size, keybindings, completion and color styling. Setting it also keeps the three `shells/*_personal.*` files off the ssh payload entirely; **your** copies in the config directory are unaffected |
| `_HI_DISABLE_GIT_STATUS` | the git segment in the prompt                                                                                                                                                                                                          |
| `_HI_DISABLE_EDITORS`    | the `vim`/`nano` config overrides                                                                                                                                                                                                      |
| `_HI_DISABLE_ALIASES`    | the personal aliases in `misc/personal.sh` - not the editor and `hi_copy` aliases `misc/aliases.sh` installs, which are the product. Setting it also keeps `personal.sh` off the ssh payload entirely                                  |
| `_HI_DISABLE_OSC52`      | the OSC 52 clipboard - yanks in `vim` and the `hi_copy` alias                                                                                                                                                                          |
| `_HI_DISABLE_NOTIFY`     | the `hi_notify` alias - desktop notifications when a command finishes. Setting it also keeps `shells/notify.sh` off the ssh payload entirely                                                                                           |
| `_HI_DISABLE_LOCAL`      | all of the above **on this machine only** - hi still styles the hosts you visit                                                                                                                                                        |

## Header details

Each is **on by default**; set it to `0` to hide that line. All are ignored when
`_HI_DISABLE_HEADER=1`.

| variable               | hides                                                            |
| ---------------------- | ---------------------------------------------------------------- |
| `_HI_HEADER_BANNER`    | the `~~~ Connected [host] ~~~` line, on connect _and_ disconnect |
| `_HI_HEADER_TIMESTAMP` | the date/time line                                               |
| `_HI_HEADER_SYSINFO`   | the OS / CPU / RAM line                                          |
| `_HI_HEADER_IDENTITY`  | the git identity / containers / ssh key line                     |
| `_HI_HEADER_CHECK`     | the installed-packages check (`misc/packages`)                   |

### Others

`_HI_DISABLE_LOCAL` is the odd one out: "leave my own machine alone, but give me
hi everywhere I connect to". It's told apart from a real session by
`_HI_REMOTE_SESSION`, which `load.sh` exports on a target and a local shell's
own rc never does.

`_HI_DISABLE_OSC52` turns off the one feature that reaches back _through_ the
connection: a yank in `vim` on a target, or anything piped into `hi_copy`, is
base64'd into an
[OSC 52](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Operating-System-Commands)
escape and written to the tty, so your local terminal emulator - not the host -
puts it on **your** clipboard. No X11 forwarding, no clipboard daemon, nothing
installed on the target. Only the unnamed register is sent, so `"ay` stays
local. Terminal support varies (tmux needs `set -g allow-passthrough on`; zellij
handles OSC 52 itself, so under `$ZELLIJ` the escape goes through raw and
unwrapped), which is why it's a toggle like everything else; `shells/osc52.sh`
is the whole implementation if you want to read what gets emitted.

`_HI_DISABLE_NOTIFY` turns off the other feature that reaches back through the
connection, and works the same way. `hi_notify <command>` runs the command on
the target, then writes an
[OSC 9](https://iterm2.com/documentation-escape-codes.html) escape (and iTerm2's
older OSC 777 spelling of it) to the tty, so **your** terminal emulator raises
the notification - a long build finishing behind a switched-away window says so
without anything being installed on the host. The body is the command line and
whether it succeeded, and `hi_notify` exits with the command's own status, so it
drops into a pipeline or a `&&` chain unchanged.

It is opt-in per invocation on purpose, never a hook on the prompt: a
notification after every command is noise rather than signal, which is the same
reason `hi_copy` is opt-in per yank. Both escapes go out because which one a
client understands is not knowable from a target - `$TERM_PROGRAM` does not
cross an ssh connection the way `$TERM` does - so an emulator that implements
both will show the notification twice. Multiplexer support is the same open
question OSC 52 lives with, handled by the same rule: tmux needs passthrough
allowed, and under `$ZELLIJ` the escape goes out raw.
`shells/notify.sh` is the whole implementation.

`_HI_DISABLE_PERSONAL` is the one toggle whose name is about **whose** taste
rather than which feature. What each shell ships beyond the prompt and the
aliases - bash's history sizing and readline bindings, zsh's keybindings and
`zstyle` completion rules, fish's keybindings and color palette - is one
person's preference, so it lives in `shells/bash_personal.sh`,
`shells/zsh_personal.zsh` and `shells/fish_personal.fish` rather than inside the
rc files, and the toggle takes all three off the wire as well as out of the
session.

Your own `bash.sh`, `zsh.zsh` or `config.fish` in the
config directory is sourced **after** hi's, in the same dialect, so yours wins -
and it is _not_ behind the toggle, because the toggle turns off hi's taste, not
yours. Setting `_HI_DISABLE_PERSONAL=1` and keeping your own file is the
supported way to say "none of hi's preferences, all of mine". They ride the
overlay archive to every target like the rest of the directory.

## Keeping the overlay in a dotfile manager

There is no say-hi plugin for chezmoi, yadm, GNU Stow or a bare `$HOME` repo,
and there should not be: the overlay is a **plain directory of plain files**, so
pointing whichever tool you already use at `~/.config/say-hi` is the whole
integration. What follows is checked rather than assumed - the properties that
make it true are pinned by cases in `tests/hi/payload_test.sh`.

**Symlinks are fine, so Stow works.** Stow does not copy files, it links them,
and hi dereferences on the way out: a target receives real file contents, not a
link into a dotfiles path that does not exist there. Both shapes work - a
symlink per file, or the whole `say-hi` directory as one link.

**Nothing but the overlay files travels.** `$_HI_OVERLAY_FILES` is an allow
list, so whatever else shares that directory stays on your machine: your
manager's own metadata (`.chezmoiignore`, templates), the `.git` that
`hi --overlay-init` creates, editor swap files, backups, and anything private
that has no business on a host you are visiting. You do not have to tidy the
directory to make it safe to ship.

**Pick one keeper for the files a manager owns.** This is the only real friction
and it is worth stating plainly: `hi --configure` writes `settings.sh` in the
**live** directory. If your manager also owns that file, the two drift - the
manager's copy and the live one diverge, and whichever runs last wins. Either

- let hi own `settings.sh` (exclude it from the manager) and keep the rest
  managed, or
- keep it managed and run your manager's re-add step
  (`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.

Managers that work per-file - chezmoi among them - leave everything they do not
own alone, so a partly-managed directory is a normal state rather than a broken
one, and `hi --overlay-init`'s git repo coexists with them untouched. Running
both keepers on the same file is what causes the drift, not running both tools.

## Colors

Every username and hostname resolves to a color derived from its own name, so an
unpinned host looks the same from every machine you say `hi` from - nothing to
generate, nothing that can go missing. Pin the ones that matter in
`~/.config/say-hi/colors`: `username,root,red`, `hostname,bastion,yellow`, or
`hosttag,prod,red` to color every host carrying a `# Tags: prod` comment above
its `Host` line - or a `Match host` line, so a fleet grouped with `Host prod-*`
or `Match host prod-*` gets colored by the wildcard block itself, not just an
exact alias - in `~/.ssh/config`. A pin always beats the hash.

`hi --color-preview` answers what that adds up to - every host in your ssh
config and every user it knows of, drawn in the colors themselves, each row
naming the rule it matched:

![hi --color-preview: every ssh host and user, in the colors they resolve to](https://ivylikethevine.github.io/say-hi/docs/demos/color_preview.gif)

## Two sessions to the same host

hi grafts its rc block into the target's `~/.bashrc` (and `~/.zshrc`, and fish's
config) on connect, and strips it on exit. The block is grafted **once** and
removed by **whoever leaves first** - not by whoever put it there. So of two
overlapping sessions to one host, the first to exit takes the block away from
the one still running.

Nothing you are already using breaks. A running shell read its rc when it
started, the session trees are per-`mktemp` so neither session can delete the
other's, and the graft is guarded on `$_HI_HOME` so it could never source a
stranger's tree anyway. What you lose is a shell started **afterwards** inside
the surviving session - `su`, a nested login - which comes up
bare, exactly as if you had ssh'd in without hi.

This is deliberate rather than unnoticed. Refcounting the graft is the
alternative, and a refcount has to live somewhere on the target that survives a
crashed session - persistent state on a machine hi promises to leave as it found
it ([SECURITY.md](SECURITY.md)'s footprint section). Reconnecting is the
workaround, and `tests/load/load_test.sh` pins the behaviour so it cannot change
by accident.

## Everything else

| variable                     | default                     | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_HI_MAX_WIDTH`              | `80`                        | terminal columns the header and banner are drawn to                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_HOME`                   | derived                     | the **parent** of your `say-hi` directory - everything resolves `$_HI_HOME/say-hi`. Each entry point derives it from its own path when unset; set it to override                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_TARGETS_TTL`            | `5`                         | seconds `hi <TAB>` reuses its target list for; `0` disables the cache                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_PROBE_TIMEOUT`          | `2`                         | seconds any one backend CLI gets, during completion and in the header                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_SSH_CONFIG`             | `~/.ssh/config`             | read-only: where ssh hosts and their `# Tags:` comments are read from. Derived from `$HOME` by `common/paths.sh` every time it is sourced, so exporting your own value does not survive - point `$HOME` at another tree if you need a different config                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_ASCII`                  | by locale                   | `1` forces ASCII stand-ins for the banner/prompt/packages glyphs (`^ ok x` for `↑ ✓ ✗`), `0` forces the glyphs; unset asks the locale, so a `LANG=C` target degrades cleanly instead of printing mojibake                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `NO_COLOR`                   | unset                       | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything - header, prompts, git segment - without color, and hi ships your client-side choice to the target next to `_HI_ASCII`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_PROMPT`                 | unset                       | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, keeping hi's header and aliases. Never auto-detected, and a target without starship silently keeps hi's own. hi does not ship starship - a multi-MB binary against a ~48KB payload                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE` | which shell a session runs in: an ordered list of `bash`/`zsh`/`fish`, plus `login` for "your own login shell". The default tail is `common/core.sh`'s `$_HI_SHELL_TREE` (`fish zsh bash dash ash sh`) filtered to the shells hi styles, i.e. `fish zsh bash` - the same list `hi.sh`'s no-bash `$_HI_SHELL_LADDER` is cut from, so the two orderings cannot disagree. First one installed on the target wins; `bash` is the floor, since that is what `load.sh` needs to run at all.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_PROMPT_END`             | per shell                   | the character each prompt ends with, when you want the same one everywhere; the three below win over it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_PROMPT_END_BASH`        | `\$`                        | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root")                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_PROMPT_END_ZSH`         | `>`                         | zsh's prompt separator - zsh prompt escapes work here, so `%#` behaves as it does anywhere else in `PS1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `_HI_PROMPT_END_FISH`        | `\|`                        | fish's prompt separator; root still gets `#` regardless                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_TERM_FALLBACK`          | `1`                         | on ssh targets missing a terminfo entry for your `TERM` (ghostty's `xterm-ghostty`, typically), swap it for `xterm-256color` before the session starts; `0` keeps the original `TERM`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_HEADER_GHZ`             | `0`                         | `1` shows the header's CPU line as `x.xxx/x.xxx GHz` instead of the default whole-MHz pair; ignored when `_HI_HEADER_SYSINFO=0`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `_HI_PACKAGES_MIN_PRIORITY`  | `1`                         | the lowest `misc/packages` priority the header's check will print, and the main dial on how long that check is. The file ranks every entry 0-5, and every rank reports what is _missing_ as well as what is there - a target you visit often is where a nudge to install your own preferred tools belongs - so this is what decides how far down that list you want to hear about. On a well-equipped machine: `1` is what ships and drops the trivia tier (about ten lines), `0` puts it back and prints everything (a dozen), `2` drops the optional extras too (about four), `3` leaves your favorites and what your workflow depends on (two), and above `5` the check prints nothing at all rather than a blank line. Rank 4 is the one that behaves differently by design: it is silent when those tools are present and speaks only when they are not, so a bare target still says what it is missing at any floor up to 4. `hi --configure` asks for this one with a live preview - it re-renders the real check at each value you type, so you pick the length you want by looking at it. `hi --packages-preview` marks the ranks it silences `below floor` and counts them under the legend, so the setting is legible before you connect anywhere |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                         | fish only, off by default: `1` gives every alias hi defines a real `abbr`, so it expands to the full command on the line before you run it - it rewrites what your command line and history literally say, hence opt-in (`hi_abbr_aliases` does the work and is callable by hand in any fish shell). Not in the `_HI_DISABLE_*` table above since it's fish-specific, not one of `core.sh`'s shared toggles                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

`_HI_TARGETS_TTL` and `_HI_PROBE_TIMEOUT` exist because completion runs on
**every TAB** and the header runs **before you get a shell**: a docker daemon
that's down or a `kubectl` pointed at a dead cluster would otherwise hang there
with no upper bound.
