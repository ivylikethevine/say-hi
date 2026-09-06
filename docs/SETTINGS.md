# Settings

Your config lives **outside the checkout**, in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` (`$_HI_CONFIG_DIR`). `colors` and
`packages` there override the tree's copies one file at a time, so anything
you haven't overridden keeps tracking what `hi --update` delivers.
`settings.sh` has no in-tree counterpart; `hi --configure` only ever writes it
here. The tree's own `settings/` directory holds the shipped defaults.

Four of those files can also live somewhere else — see
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

Configuring say-hi never dirties the checkout, so `git pull` applies cleanly
and the tree can be root-owned, installed by a package manager. All of it
rides along to every host you say `hi` to, in its own small archive.

`hi --overlay-init` seeds the overlay with the shipped
`colors`/`packages`/`vim.rc`/`nano.rc` defaults — only for the files you have
none of; a file already there is never touched — then makes `~/.config/say-hi`
a git repo _in place_: from then on `hi --configure` commits its own writes,
`hi --doctor` reports the commit count, and a push remote is one
`git remote add` away. A seeded copy stops tracking what `hi --update`
delivers for that file (it is yours now), and costs almost nothing on the
wire: the overlay ships comment-stripped, the way the tree does. If you
already keep dotfiles in chezmoi, yadm, GNU Stow or a bare repo,
[that directory is the whole integration](#keeping-the-overlay-in-a-dotfile-manager).

Every setting below is an environment variable, checked where it is used.
`hi --configure` writes your answers to `settings.sh` — a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh and fish — which
every shell sources ahead of `common/paths.sh`. Exporting one by hand works
too and takes precedence for that shell. It does not reach programs started
from a hi shell: once the rc has run, every `_HI_*` name except eight is a
plain shell variable ([HI.47](GLOSSARY.md#hi47-what-a-child-inherits) says
which, and why). A setting a child must see — a script of your own reading
`$_HI_COLORS`, say — is an `export` in the overlay's
`bash.sh`/`zsh.zsh`/`config.fish`, which run last.

## Contents

- [How it works](#how-it-works)
- [Every setting](#every-setting)
  - [Pointing one file somewhere else](#pointing-one-file-somewhere-else)
  - [Not settings](#not-settings)
- [System-wide settings](#system-wide-settings)
- [The wizard](#the-wizard)
- [Presets](#presets)
- [Features](#features)
- [Header details](#header-details)
  - [Others](#others)
  - [Shells you drop into inside a session](#shells-you-drop-into-inside-a-session)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)
- [Colors](#colors)
  - [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)
- [Everything else](#everything-else)

## How it works

1. `hi.sh` runs on the client, tars `say-hi/` and sends it to the target, which
   unpacks it into a `/tmp` directory. `$_HI_PAYLOAD` at the top of `hi.sh` is
   the allow list — no `.git`, `scripts/`, `tests/`, `docs/` or CI. Your
   overlay follows in a second, much smaller archive, landing in a `config/`
   of its own so your `aliases.sh` stays additive. A target with its own
   `say-hi` gets neither: hi loads that tree in place, with its own overlay.
2. Both are base64-armored into one script written over the **stdin** of an
   ssh connection the session then reuses — not argv, which Linux caps at
   128KB however big `ARG_MAX` says. Every shell file is comment-stripped on
   the way in (about 40% of it); `_HI_KEEP_COMMENTS=1` ships the tree verbatim.
3. That assembled script is the size `hi` prints on connect and what the
   payload badge measures, for a _default_ configuration — an overlay that
   turns off the editor overrides, OSC 52 or `hi_notify` sends less. It is the
   per-session wire cost, not the package badge beside it, which is what a
   release downloads (`scripts/` and the docs ship in a package, never over
   the wire).
4. On the target, `load.sh` prints the header, writes hi's per-shell rc files
   into a scratch directory of its own
   ([HI.46](GLOSSARY.md#hi46-session-rc-directory)) - never the target's own
   login files - and drops you into **your login shell** when hi styles it
   (bash, zsh, fish), else the best the target has of `$_HI_SHELL_TREE`
   (`fish > zsh > bash > dash > ash > sh`); `_HI_SHELL_PREFERENCE` is that
   rule as a setting. With no bash at all the choice comes from
   `$_HI_SHELL_LADDER`, the same list without bash.
5. On exit, `load.sh`'s on-exit hook removes the `/tmp` directory and the
   scratch rc directory. It runs on `SIGHUP` too, so a dropped connection
   cleans up the same way, with nothing left to reconnect to. Run `hi` inside
   `tmux` or `screen` on the _client_ to survive drops; persistent sessions
   on the target were
   [decided against](SUPPORT.md#what-would-change-an-answer).
6. `hi <target> 'some command'` skips the session and runs the command there,
   the way `ssh` does.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session in the best plain shell it has, aliases loaded. For ssh targets hi
first checks, over the same connection, for a permanent say-hi: the `_HI_HOME`
line `install.sh` wrote into the target's login rc files (or `/etc/profile.d`
for a packaged install), then the home directory, then the places an install
lands when nothing declared it — `~/.local/share`, `/usr/local/share`,
`/opt`, `/usr/share` and Homebrew's default keg prefixes. `hi --doctor` prints
the wire size and the unpacked size, labeled.

## Every setting

The whole vocabulary a `settings.sh` may use, in the order `hi --configure`
writes it; the linked sections are the explanations. The **set by** column:

- **you** — supported surface nothing asks about: export it, or write an
  `export` line into `settings.sh` by hand.
- **`hi --configure`** — the same, with a menu item attached; the only
  variables the wizard writes. **advanced** marks the ones behind the menu's
  _Advanced_ item: a run that never opens it keeps whatever they hold.
- **hi** — hi's own, listed because a `settings.sh` _can_ set it and something
  will happen. hi sets these per session, from the client; overriding one
  tells the target something untrue about where it is.

The lint group checks `common/core.sh`'s `_HI_TOGGLES` and
`scripts/configure.sh`'s prompt rosters against this table, so a new setting
cannot land without a row here.

| variable                     | default                                              | set by                    | what it does                                                                                                           |
| ---------------------------- | ---------------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`         | `0`                                                  | `hi --configure`          | [Features](#features) - the whole connect/disconnect header                                                            |
| `_HI_DISABLE_PROMPT`         | `0`                                                  | `hi --configure`          | [Features](#features) - the colored `user@host` prompt                                                                 |
| `_HI_DISABLE_GIT_STATUS`     | `0`                                                  | `hi --configure`          | [Features](#features) - the git segment in the prompt                                                                  |
| `_HI_DISABLE_EDITORS`        | `0`                                                  | `hi --configure`          | [Features](#features) - the `vim`/`nano` config overrides                                                              |
| `_HI_DISABLE_BAT_ALIAS`      | `0`                                                  | `hi --configure`          | [Features](#features) - rebinding `cat`/`catn` to a styled `bat`                                                       |
| `_HI_DISABLE_LS_ALIASES`     | `0`                                                  | `hi --configure`          | [Features](#features) - the `exa`/`eza` ls-family aliases                                                              |
| `_HI_DISABLE_OSC52`          | `0`                                                  | `hi --configure`          | [Features](#features) - the OSC 52 clipboard                                                                           |
| `_HI_DISABLE_NOTIFY`         | `0`                                                  | `hi --configure`          | [Features](#features) - the `hi_notify` desktop-notification alias                                                     |
| `_HI_DISABLE_MARKS`          | `0`                                                  | `hi --configure`          | [Features](#features) - OSC 133 prompt marks and OSC 7 cwd reporting                                                   |
| `_HI_DISABLE_LOCAL`          | `0`                                                  | `hi --configure`          | [Features](#features) - all of the above, on this machine only                                                         |
| `_HI_DISABLE_LOCAL_PROMPT`   | `0`                                                  | `hi --configure`          | [Features](#features) - hi's prompt on this machine only; the answer for a starship, powerlevel10k or oh-my-zsh prompt |
| `_HI_REMOTE_SESSION`         | `0`                                                  | hi                        | `1` inside a hi session, which is what `_HI_DISABLE_LOCAL` reads to tell local from remote                             |
| `_HI_HEADER_BANNER`          | `1`                                                  | `hi --configure`          | [Header details](#header-details) - the `~~~ Connected ~~~` line                                                       |
| `_HI_HEADER_ORDER`           | see [Header details](#header-details)                | `hi --configure`          | [Header details](#header-details) - which header features show, and in what order                                      |
| `_HI_PACKAGES_MIN_PRIORITY`  | `2`                                                  | `hi --configure`          | [Everything else](#everything-else) - how far down `settings/packages` the check reports                               |
| `_HI_PACKAGES_PALETTE`       | `cool`                                               | `hi --configure`          | [Everything else](#everything-else) - which named color ramp the check paints with                                     |
| `_HI_IP_HIDE`                | `172.*`                                              | `hi --configure`          | [Header details](#header-details) - addresses the `ip` cell leaves out; `none` shows every one                         |
| `_HI_COLOR_SCHEME`           | unset                                                | `hi --configure`          | [Colors](#colors) - the twelve palette names as a truecolor scheme: `catppuccin`, `monokai`, `onedark`, `vscode`       |
| `_HI_MAX_WIDTH`              | `80`                                                 | `hi --configure`          | [Everything else](#everything-else) - columns the header and banner are drawn to, narrowed to a smaller real terminal  |
| `_HI_PROMPT`                 | unset                                                | `hi --configure`          | [Everything else](#everything-else) - `starship` hands the prompt to starship                                          |
| `_HI_PROMPT_END`             | per shell                                            | you                       | [Everything else](#everything-else) - one prompt separator for every shell                                             |
| `_HI_PROMPT_END_BASH`        | `\$`                                                 | `hi --configure`          | [Everything else](#everything-else) - bash's separator; wins over `_HI_PROMPT_END`                                     |
| `_HI_PROMPT_END_ZSH`         | `>`                                                  | `hi --configure`          | [Everything else](#everything-else) - zsh's separator                                                                  |
| `_HI_PROMPT_END_FISH`        | `\|`                                                 | `hi --configure`          | [Everything else](#everything-else) - fish's separator                                                                 |
| `_HI_PROMPT_END_SH`          | `\$`                                                 | you                       | the separator on a bash-less target, where hi bakes a plain `sh` prompt on the client                                  |
| `_HI_TERM_FALLBACK`          | `1`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - swap an unknown `TERM` for `xterm-256color`                                      |
| `_HI_RECENT`                 | `1`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - `0` stops recent targets being recorded and ranked first                         |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - fish only: give every alias a real `abbr`                                        |
| `_HI_NO_LEAD_SPACE`          | `0`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - drop the hardcoded leading space in the prompt, git segment and header lines     |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE`                          | `hi --configure` advanced | [Everything else](#everything-else) - which shell a session runs in                                                    |
| `_HI_ASCII`                  | by locale                                            | `hi --configure` advanced | [Everything else](#everything-else) - force ASCII stand-ins (`1`) or glyphs (`0`)                                      |
| `_HI_TRUECOLOR`              | by terminal                                          | hi                        | [Colors](#colors) - the client's 24-bit verdict (`1`/`0`), shipped like `_HI_ASCII`; set it to force or refuse         |
| `_HI_TARGETS_TTL`            | `5`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - seconds `hi <TAB>` reuses its target list for                                    |
| `_HI_PROBE_TIMEOUT`          | `2`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - seconds any one backend CLI gets                                                 |
| `_HI_CTL_PERSIST`            | `60`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - seconds an ssh connection stays authenticated after you disconnect                |
| `_HI_PAYLOAD_CACHE`          | `1`                                                  | `hi --configure` advanced | [Everything else](#everything-else) - `0` rebuilds the payload/overlay archives fresh on every connect                 |
| `NO_COLOR`                   | unset                                                | you                       | [Everything else](#everything-else) - not hi's variable; any non-empty value drops color                               |
| `_HI_KEEP_COMMENTS`          | `0`                                                  | you                       | `1` ships the tree verbatim rather than comment-stripped, for reading real source on a target                          |
| `_HI_RECENT_FILE`            | `$XDG_STATE_HOME/say-hi/recent`                      | you                       | [Everything else](#everything-else) - where those are kept                                                             |
| `_HI_COLORS`                 | overlay, else tree                                   | you                       | [Pointing one file somewhere else](#pointing-one-file-somewhere-else) - where the color pins are read from             |
| `_HI_PACKAGES`               | overlay, else tree                                   | you                       | the same for the package check's list                                                                                  |
| `_HI_VIMRC`                  | overlay, else tree                                   | you                       | the same for the vim config the `vim` alias and `$VIMINIT` point at                                                    |
| `_HI_NANORC`                 | overlay, else tree                                   | you                       | the same for nano's                                                                                                    |
| `_HI_BAT_OPTS`               | Monokai theme, `--tabs 2`, `changes,grid` style      | you                       | the flags the `bat`/`batn` aliases attach, set in your `aliases.sh` ahead of the tree's own                            |
| `_HI_EXA_SHARED_OPTS`        | `-F -1 -l -m --group-directories-first`              | you                       | the flags the `exa`/`eza` aliases share before each one's own are appended                                             |
| `_HI_EXA_OPTS`               | `$_HI_EXA_SHARED_OPTS --group --no-filesize`         | you                       | the `exa` alias's flags (its predecessor's column set)                                                                 |
| `_HI_EZA_OPTS`               | `$_HI_EXA_SHARED_OPTS` + smart-group + a time format | you                       | the `eza` alias's flags                                                                                                |
| `_HI_EZA_OPTS_SIZE`          | `$_HI_EZA_OPTS --total-size`                         | you                       | exported for an overlay's own use; no shipped alias reads it today                                                     |
| `_HI_TARGET`                 | -                                                    | hi                        | the target as you typed it on the client                                                                               |
| `_HI_TARGET_COLOR`           | -                                                    | hi                        | the color that target resolved to, decided on the client so it matches everywhere                                      |
| `_HI_TARGET_TAG`             | -                                                    | hi                        | the target's `# Tags:` value out of your `~/.ssh/config`                                                               |
| `_HI_HOST_COLOR`             | -                                                    | hi                        | [Your own prompt](#using-the-hash-in-your-own-prompt) - the hostname color, by name (zsh's `%F{}` form)                |
| `_HI_USER_COLOR`             | -                                                    | hi                        | the same for the username                                                                                              |
| `_HI_HOST_ESC`               | -                                                    | hi                        | the hostname color, as a raw ANSI escape (bash's form)                                                                 |
| `_HI_USER_ESC`               | -                                                    | hi                        | the same for the username                                                                                              |
| `_HI_LOCAL_USER`             | -                                                    | hi                        | who you are on the client, for the header's "from" half                                                                |
| `_HI_LOCAL_HOSTNAME`         | -                                                    | hi                        | where you came from, likewise                                                                                          |
| `_HI_RELEASE`                | -                                                    | hi                        | the client's version, so a session says which say-hi it is running                                                     |

### Pointing one file somewhere else

`$_HI_CONFIG_DIR` moves the whole overlay. The four files inside it with a
path variable of their own — `colors`, `packages`, `vim.rc` and `nano.rc` —
can each be moved alone instead:

```sh
export _HI_COLORS="$HOME/dotfiles/hi-colors"     # in settings.sh, or the environment
```

That one file now comes from `~/dotfiles`; the other three resolve as before
— the overlay's copy if you made one, else the tree's. It wins even when
`~/.config/say-hi/colors` also exists, which suits a dotfile manager that
would rather keep its own paths than symlink into `~/.config/say-hi`; the
[whole-directory route](#keeping-the-overlay-in-a-dotfile-manager) is simpler
when you are moving all of it.

Two edges. A value equal to what `common/paths.sh` would have resolved anyway
is not a choice — it is what a child shell inherits from its parent, and
re-resolving it is what lets `_HI_CONFIG_DIR=elsewhere bash` mean something.
And the four are read on every source, so a running shell does not notice a
file you have only just created; open a new one.

The other five overlay files have no such variable: `aliases.sh` and the three
per-shell files are sourced by fixed name straight off `$_HI_CONFIG_DIR`, and
`settings.sh` is read before any of this happens.

### Not settings

Four more names look like settings and are not. `$_HI_CONFIG_DIR` and
`$_HI_HOME` are read **before** `settings.sh` is sourced, so a line there is
too late; export them in your environment, as `hi.sh` and `install.sh`'s rc
line do. `$_HI_ROOT` and `$_HI_SSH_CONFIG` are derived from those two by
`common/paths.sh` on every source, so an exported value does not survive;
point `$_HI_HOME` or `$HOME` elsewhere instead. Everything else beginning
`_HI_` is internal state, named that way to stay out of your namespace.

## System-wide settings

`/etc/say-hi/settings.sh`, when it exists, is sourced **before** each user's
own `settings.sh` — a platform team's defaults, in the same
sh-and-fish-parseable dialect (`export NAME=value` lines only; `hi --doctor`
parse-checks it both ways). Precedence, lowest to highest: the shipped
defaults, `/etc/say-hi/settings.sh`, the user's `settings.sh`, then a value
exported by hand in the running shell.

It applies to **this machine only**: a remote hi session is configured by the
visitor's own overlay, and the target's `/etc` has no say in it. No package
ships the file — an administrator creates it, and removing it restores
per-user settings everywhere at the next shell. (`$_HI_SYSTEM_SETTINGS`
points the read somewhere else; it exists for the test suites.)

## The wizard

`hi --configure` opens on a preview — the header as it would print and the
prompt line as it would draw, at your current settings — over a short menu:

1. **Preset** — `everything`, `balanced` or `minimal`, below.
2. **Header** — the editor for everything in [Header details](#header-details):
   the real header rendered above a numbered list of the banner and every
   item; a number toggles one, `up N`/`down N` moves it, `p` loads a header
   preset (`full`, `compact`, `quiet`), and the width, the package check's
   depth and its palette live there too.
3. **Features** — the [Features](#features) toggles, each previewed as it
   flips.
4. **Prompt** — starship, and the character each shell's prompt ends with.
5. **Advanced** — the _advanced_ rows, as a short walk of questions.

Every section returns to the menu and the preview re-renders. `s` writes the
settings once; `q` leaves `settings.sh` untouched; nothing is written before
either. With no terminal (`hi --configure </dev/null`, a script) there is no
menu: what the file holds is written back as it stands.

## Presets

The menu's first item, and `hi --configure --preset <name>` applies one
without the menu:

| preset       | what it answers                                                                                                                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | every feature and every header item on — the shipped defaults                                                                                                                                                                                            |
| `balanced`   | everything but the noise: a shorter package check (`_HI_PACKAGES_MIN_PRIORITY=3`) and no `hi_notify`                                                                                                                                                     |
| `minimal`    | on targets only the colored prompt and the aliases: no header, git status, editors, clipboard, notifications or prompt marks — and nothing on this machine (`_HI_DISABLE_LOCAL=1`). The opt-in is off in every preset; it is only ever turned on by hand |

A preset is an absolute answer over the feature, header and prompt settings:
what it names is set, everything else in that vocabulary returns to its
default, and the header order, the width, the prompt separators and the
advanced settings keep what they hold. From the menu its answers are what the
preview shows and `s` saves — a starting point, not a lock. The rows are
`scripts/configure.sh`'s `_HI_PRESETS`; the header editor's own presets are
`_HI_HEADER_PRESETS` beside them.

## Features

Each is **on by default**; set it to `1` to turn that piece off.

| variable                   | turns off                                                                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `_HI_DISABLE_HEADER`       | the whole connect/disconnect header, every line of it                                                                                |
| `_HI_DISABLE_PROMPT`       | the colored `user@host` prompt, leaving your shell's own                                                                             |
| `_HI_DISABLE_GIT_STATUS`   | the git segment in the prompt                                                                                                        |
| `_HI_DISABLE_EDITORS`      | the `vim`/`nano` config overrides                                                                                                    |
| `_HI_DISABLE_BAT_ALIAS`    | rebinding `cat`/`catn` to a styled `bat` - `bat`/`batcat`/`batn` themselves stay available by name either way                        |
| `_HI_DISABLE_LS_ALIASES`   | the styled `exa`/`eza` aliases - the `exa`/`eza` binaries themselves stay available by name either way                               |
| `_HI_DISABLE_OSC52`        | the OSC 52 clipboard - yanks in `vim` and the `hi_copy` alias                                                                        |
| `_HI_DISABLE_NOTIFY`       | the `hi_notify` alias - desktop notifications when a command finishes. Also keeps `common/notify.sh` off the ssh payload entirely    |
| `_HI_DISABLE_MARKS`        | the semantic prompt marks (OSC 133) and cwd reporting (OSC 7) every prompt emits, see below                                          |
| `_HI_DISABLE_LOCAL`        | all of the above **on this machine only** - hi still styles the hosts you visit                                                      |
| `_HI_DISABLE_LOCAL_PROMPT` | hi's prompt **on this machine only** - your starship, powerlevel10k, oh-my-zsh or hand-written `fish_prompt` stays; targets get hi's |

## Header details

`_HI_HEADER_BANNER` (default `1`, `0` hides it) controls the
`~~~ Connected [host] ~~~` line, on connect _and_ disconnect. It always leads
and is not one of the reorderable features below - it needs its own switch
for exactly that reason. Ignored, like everything in this section, when
`_HI_DISABLE_HEADER=1` - ignored, not dropped: `hi --configure` writes a
stored order back even while the header is off, so it is there again when
the header comes back on. The wizard's _Header_ menu is the editor for all
of it, with the real header rendered above the list ([The
wizard](#the-wizard)).

Everything else the header prints is one flat list of individually
toggleable, reorderable features - there is no fixed "row" grouping them
anymore. `_HI_HEADER_ORDER` is a space-separated list of these words, in the
order you want them to print, any subset:

| word         | what it is                                          |
| ------------ | --------------------------------------------------- |
| `utc`        | the UTC clock                                       |
| `version`    | hi's own version                                    |
| `localtime`  | your local clock                                    |
| `os`         | the OS name/version                                 |
| `arch`       | the CPU architecture                                |
| `cores`      | core count and load percentage                      |
| `cpu`        | base/boost clock speed                              |
| `ram`        | used/total memory                                   |
| `ip`         | this box's routable IPv4 address(es)                |
| `gitid`      | the masked git identity (`user.email`)              |
| `containers` | the docker/podman container count, when either runs |
| `jobs`       | the nomad job count, when nomad answers             |
| `pods`       | the reachable kube pod count, when kubectl answers  |
| `auth`       | the `~/.ssh/authorized_keys` line count             |
| `pub`        | the `~/.ssh/*.pub` file count                       |
| `uptime`     | this box's uptime                                   |
| `check`      | the installed-packages check (`settings/packages`)  |

A word left out is not printed - that's the whole toggle, there is nothing
else to set. Unknown words are ignored. `containers`/`jobs`/`pods` only ever
render when their backend actually answered, whether or not they're in the
list; being in the list controls whether hi bothers asking at all. Each word
also has a fixed color; whichever two land next to each other, hi swaps a
word's color for its alternate rather than let it repeat the cell before it -
so reordering never puts two same-colored cells side by side, even though the
order above is free-form
([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)). Defaults to `utc
version localtime os arch cores cpu ram ip gitid containers jobs pods auth
pub uptime check`, today's shipped order, so an unset override changes
nothing.

The `ip` cell leaves out whatever `_HI_IP_HIDE` names: space-separated globs
over the dotted quad, `172.*` by default so a docker or podman bridge
address is not the first thing a container's header says. `none` shows every
address; `10.* 192.168.1.?` is two globs. When every address a box has is
hidden the cell is dropped from the line rather than drawn as `?`, which
still means no routable address was found at all. The Header menu of
`hi --configure` asks for it under `i`.

A physical line that overflows `_HI_MAX_WIDTH` no longer wraps within itself:
whatever does not fit opens the next line instead, cascading forward through
the order above until the packages check (the one variable-length feature)
absorbs the rest, or - with `check` hidden or left out - prints as its own
trailing line.

**Migrating an existing `_HI_HEADER_ORDER`**: the old four words
(`timestamp`, `sysinfo`, `identity`, `check`) are gone along with the six
`_HI_HEADER_*` row toggles they went with (`_HI_HEADER_BANNER` is the one
exception, kept above) - none of them match anything in the new vocabulary,
so a saved value using them silently shows nothing for the words it no
longer recognizes. Replace `timestamp` with `utc version localtime`,
`sysinfo` with `arch os cores cpu ram`, and `identity` with `gitid
containers jobs pods auth pub uptime` (drop `uptime` from that if you had
`_HI_HEADER_UPTIME=0` set).

### Others

`_HI_DISABLE_LOCAL` is "leave my own machine alone, but give me hi everywhere I
connect to". A real session is told apart by `_HI_REMOTE_SESSION`, which
`load.sh` exports on a target and a local rc never does.

`_HI_DISABLE_LOCAL_PROMPT` is the narrower cut: hi's rc is sourced last in
your `~/.zshrc` / `~/.bashrc` / `config.fish`, so on your own machine its
prompt would otherwise replace the one you already have. The first
`hi --configure` (or install) with no `settings.sh` yet looks for starship,
powerlevel10k, oh-my-zsh, prezto, zimfw, oh-my-bash, bash-it, liquidprompt
or a `fish_prompt.fish` of your own in your rc files, and when it finds one
answers this `1` and says so. A preset on the command line does not undo that
answer; the Features menu does, and once `settings.sh` exists the detection
never runs again. Aliases, completion, the header and `hi` itself stay on
locally; only the prompt yields.

Two things hi does write on your own machine outside `~/.config/say-hi/`:
the rc lines `install.sh` adds (marker-tagged, with a one-time `.hi-orig`
backup), and, in fish, three universal variables (`__hi_color_user`,
`__hi_color_host`, `__hi_colors_key`) that memoize your prompt colors so only
the first shell after a `colors` change pays for the bash call. `hi
--uninstall` removes the rc lines; `set -e -U __hi_color_user __hi_color_host
__hi_colors_key` clears the three.

`_HI_DISABLE_OSC52` turns off the one feature that reaches back _through_ the
connection: a yank in `vim` on a target, or anything piped into `hi_copy`, is
base64'd into an
[OSC 52](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Operating-System-Commands)
escape and written to the tty, so your local terminal emulator puts it on
**your** clipboard — no X11 forwarding, no clipboard daemon, nothing installed
on the target. Only the unnamed register is sent, so `"ay` stays local.
Terminal support varies (tmux needs `set -g allow-passthrough on`; under
`$ZELLIJ` the escape goes through raw), hence the toggle. `common/osc52.sh` is
the whole implementation.

**The header says so when tmux is going to eat it.** `allow-passthrough` has
been off by default since tmux 3.3, and nothing fails when it is: `hi_copy`
exits 0, the escape is swallowed, and the next paste hands back your previous
clipboard. A session that finds `$TMUX` set with the option off prints one
line on connect —

```text
 | tmux passthrough off - hi_copy/hi_notify muted | set -g allow-passthrough on
```

— and nowhere else. It has no toggle of its own: turn the option on, or turn
off the two features it is about, and it stops. A tmux too old to have the
option says nothing.

`_HI_DISABLE_NOTIFY` turns off the other one. `hi_notify <command>` runs the
command on the target, then writes an
[OSC 9](https://iterm2.com/documentation-escape-codes.html) escape (and
iTerm2's older OSC 777 spelling) to the tty, so **your** terminal raises the
notification: the command line and whether it succeeded. `hi_notify` exits
with the command's own status, so it drops into a pipeline or `&&` chain
unchanged. It is opt-in per invocation, never a prompt hook — a notification
after every command is noise — as `hi_copy` is opt-in per yank. Both escapes
go out because `$TERM_PROGRAM` does not cross an ssh connection, so an
emulator implementing both shows the notification twice. Multiplexer support
follows the OSC 52 rule. `common/notify.sh` is the whole implementation.

`_HI_DISABLE_MARKS` turns off the two escapes every hi prompt emits for
terminals that read them — kitty, WezTerm, ghostty, foot, iTerm2, Konsole:
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
marks where each prompt, command and output begins (jump between prompts,
select one command's output, see a failed command's status), and OSC 7 reports
the working directory (a new tab or split opens where you were, on that host).
Nothing is installed on the target; a terminal that does not know an OSC drops
it, and fish 4 emits both itself, so there hi stays out of the way. Only the
styled shells emit them — the bash-less `sh` prompt does not.

### Shells you drop into inside a session

A `bash`, `zsh`, `fish` or `dash` started _inside_ a session keeps hi's
aliases, prompt and paths, with nothing written to the target. `load.sh`
writes one rc per shell into a scratch directory of its own and exports
`$_HI_SESSION_RC` at it:

- **zsh** through `$ZDOTDIR` and **sh/dash/ash** through `$ENV` - both
  exported, so such a shell reads hi's rc however it was started, including
  by something that is not a shell;
- **bash** and **fish** have no equivalent variable (bash's `$BASH_ENV` covers
  only _non_-interactive shells), so `settings/aliases.sh` defines a wrapper
  for each that hands it the same file.

Each rc sources the target's own `~/.bashrc` / `~/.zshrc` / `~/.zshenv` first
and hi's on top, so the host's configuration still applies underneath. The
mechanism is [HI.46](GLOSSARY.md#hi46-session-rc-directory).

What no wrapper can reach is a bash or fish shell nothing typed - a `tmux`
pane spawning a login shell, an editor shelling out - which comes up as the
host's own. hi writes nothing to any login file on any host you visit, under
any setting ([SUPPORT.md](SUPPORT.md#features-that-were-removed) has the
reasoning).

Nor can a change of user. `sudo -i`, `sudo -s`, `su -` and `doas -s` start
_that_ user's login shell from _that_ user's rc files, and hi's session rc is
neither — root's `.bashrc` is not hi's to touch, for the same reason. What
survives is `sudo <command>`: `settings/aliases.sh` wraps `sudo` so hi's
aliases expand in the one command it runs, and nothing past it.

hi ships nobody's shell preferences — no history sizing, keybindings, `zstyle`
rules or fish palette. Each rc carries the prompt, the completions and the git
segment, which are the product. Your own `bash.sh`, `zsh.zsh` or `config.fish`
in the config directory is sourced at the end of hi's, in the same dialect,
and wins - `HISTFILE` included; hi sets none. Your `aliases.sh` instead loads
**before** `settings/aliases.sh` (`sudo`, the `cat`/`bat` and `ls`/`eza`
families), so a `_HI_*_OPTS` value or `_HI_DISABLE_*` toggle set there wins
but an `alias` of the same name does not - the shipped one is defined after
and overwrites it. Turn the shipped family off with its toggle and define your
own instead.

## Keeping the overlay in a dotfile manager

There is no say-hi plugin for chezmoi, yadm, GNU Stow or a bare `$HOME` repo,
and there should not be: the overlay is a **plain directory of plain files**,
so pointing your tool at `~/.config/say-hi` is the whole integration. The
properties that make this true are pinned by cases in
`tests/hi/payload_test.sh`.

**Symlinks are fine, so Stow works.** hi dereferences on the way out, so a
target receives real file contents — a symlink per file, or the whole `say-hi`
directory as one link.

**Nothing but the overlay files travels.** `$_HI_OVERLAY_FILES` is an allow
list, so your manager's metadata (`.chezmoiignore`, templates), the `.git` that
`hi --overlay-init` creates, editor swap files and anything private sharing
that directory stay on your machine.

**Pick one keeper for the files a manager owns.** `hi --configure` writes
`settings.sh` in the **live** directory; if your manager also owns it, the two
drift. Either let hi own `settings.sh` (exclude it from the manager), or keep
it managed and run the manager's re-add step
(`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.
Per-file managers leave what they do not own alone, so a partly-managed
directory is normal, and `hi --overlay-init`'s git repo coexists with them.

## Colors

Every username and hostname resolves to a color derived from its own name, so
an unpinned host looks the same from every machine you say `hi` from. Pin the
ones that matter in `~/.config/say-hi/colors`: `username,root,red`,
`hostname,bastion,yellow`, or `hosttag,prod,red` to color every host carrying a
`# Tags: prod` comment above its `Host` or `Match host` line in
`~/.ssh/config` — a wildcard block (`Host prod-*`) colors every name it covers.
A `hostname` row whose name holds `*` or `?` is a pattern:
`hostname,10.0.1.*,red` or `hostname,*.prod.example.com,red` colors a whole
subnet or domain at once, no ssh-config entry needed — the first matching
pattern in the file wins. Precedence, highest first: an exact pin, then a
hosttag, then a pattern, then the hash; a pin always beats the hash.

The vocabulary is those twelve names, and stays so - a pin, the hash and
`hi --color-preview` never see anything else. What each name _renders as_
is `_HI_COLOR_SCHEME`'s: unset, the terminal's own sixteen colors; set to
`catppuccin`, `monokai`, `onedark` or `vscode`, that scheme's hex for each
name, emitted as one escape that carries the 16-color code first and the
24-bit color after it, so a terminal that ignores the second keeps the first.
It paints everything hi paints - the prompt, the header's cells and packages
check, the git segment - and only on a terminal that says it can:
`COLORTERM` set to `truecolor` or `24bit`, which hi reads on the client and
ships to the session as `_HI_TRUECOLOR` (ssh drops `COLORTERM` itself).
Inside tmux or on a terminal that renders 24-bit color without announcing it,
`export _HI_TRUECOLOR=1` in `settings.sh` forces it; `0` refuses it. zsh
takes the hex from 5.7 on and keeps the plain name below that; macOS
Terminal.app never sets `COLORTERM` and so keeps its own sixteen. Judge a
scheme with `hi --color-preview` and `hi --packages-preview`, which each say
which scheme they are rendering; `hi --configure`'s Colors section shows all
four side by side. `settings.sh` ships to every target, so a scheme follows
you.

`hi --color-preview` shows every host in your ssh config and every user it
knows of, drawn in the colors themselves, each row naming the rule it matched:

![hi --color-preview: every ssh host and user in the colors they resolve to, then a prod host in red and a dev host in green](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### Using the hash in your own prompt

`_HI_DISABLE_PROMPT=1` [(Features)](#features) turns off hi's own
`user@host` prompt; the per-host color hashing is still resolved, into
variables for your own `bash.sh` or `zsh.zsh` (sourced at the end of hi's,
[above](#shells-you-drop-into-inside-a-session)) to use:

- `$_HI_HOST_ESC`/`$_HI_USER_ESC` — the raw ANSI escape, for a bash `PS1` to
  embed directly (wrap it in `\[ \]` so readline doesn't count its width):
  `PS1="\[$_HI_HOST_ESC\]\h\[$NC\] \w "`.
- `$_HI_HOST_COLOR`/`$_HI_USER_COLOR` — the color by name, for zsh's own
  `%F{}`: `PS1='%F{$_HI_HOST_COLOR}%m%f %~ '`.
- fish needs neither: `$fish_color_host`/`$fish_color_user` are already set
  by `common/config.fish`, unconditionally, for `set_color $fish_color_host`
  in your own `fish_prompt`.

All four update the moment the color pins above do.

## Everything else

| variable                     | default                         | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_IP_HIDE`                | `172.*`                         | space-separated globs over the dotted quad; the header's `ip` cell drops every address one matches, and drops itself when nothing is left. `none` hides nothing. See [Header details](#header-details)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_MAX_WIDTH`              | `80`                            | terminal columns the header and banner are drawn to, narrowed to a smaller real terminal                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `_HI_HOME`                   | derived                         | the **parent** of your `say-hi` directory - everything resolves `$_HI_HOME/say-hi`. Each entry point derives it from its own path when unset; set it to override                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_TARGETS_TTL`            | `5`                             | seconds `hi <TAB>` reuses its target list for; `0` disables the cache. For ten minutes past it an expired list still answers the TAB at once while the refresh runs behind it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_RECENT`                 | `1`                             | `1` appends every target a session ended cleanly on to a recent file, and `hi <TAB>` offers those first - most used and most recent ahead (zoxide's frecency). Client-side only: a target never sees the file. `0` neither records nor ranks                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `_HI_RECENT_FILE`            | `$XDG_STATE_HOME/say-hi/recent` | that file (`~/.local/state/say-hi/recent` by default), one `<epoch>\t<target>` line per session, trimmed to the newest 300 past 500                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_PROBE_TIMEOUT`          | `2`                             | seconds any one backend CLI gets, during completion and in the header (a TERM, with a KILL 200ms behind it)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_CTL_PERSIST`            | `60`                            | seconds an ssh connection stays authenticated after you disconnect, so a second `hi <target>` within that window reuses the socket and skips the key exchange; `0` closes it right away, same as before this existed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_PAYLOAD_CACHE`          | `1`                             | caches the gzipped payload and overlay archives between connects, rebuilding only when a source file's mtime moves past the cache's own or a toggle changes what would ship; `0` rebuilds fresh on every connect, as before this existed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_SSH_CONFIG`             | `~/.ssh/config`                 | read-only: where ssh hosts and their `# Tags:` comments are read from. Derived from `$HOME` by `common/paths.sh` every time it is sourced, so exporting your own value does not survive                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_COLOR_SCHEME`           | unset                           | which truecolor scheme the twelve palette names render as everywhere hi paints - `catppuccin` (Mocha), `monokai`, `onedark`, `vscode` (Dark+) - on a terminal that reports 24-bit color, and nothing at all on one that does not. See [Colors](#colors)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_TRUECOLOR`              | by terminal                     | `1`/`0`: does the client's terminal render 24-bit color. Read off `COLORTERM` and shipped to the session beside `_HI_ASCII`, since ssh never forwards `COLORTERM`; set it yourself to force (`1`, for tmux) or refuse (`0`) a scheme's hex                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_ASCII`                  | by locale                       | `1` forces ASCII stand-ins for the banner/prompt/packages glyphs (`^ ok x` for `↑ ✓ ✗`), `0` forces the glyphs; unset asks the locale, so a `LANG=C` target degrades cleanly instead of printing mojibake                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `NO_COLOR`                   | unset                           | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything without color, and hi ships your client-side choice to the target next to `_HI_ASCII`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_PROMPT`                 | unset                           | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, keeping hi's header and aliases. Never auto-detected; a target without starship silently keeps hi's own. hi does not ship starship - a multi-MB binary against a payload of some 48KB                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `_HI_SHELL_PREFERENCE`       | `login` + `$_HI_SHELL_TREE`     | which shell a session runs in: an ordered list of `bash`/`zsh`/`fish`, plus `login` for "your own login shell". The default tail is `$_HI_SHELL_TREE` filtered to the shells hi styles (`fish zsh bash`) - the same list `hi.sh`'s no-bash `$_HI_SHELL_LADDER` is cut from. First one installed on the target wins; `bash` is the floor, since `load.sh` needs it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_PROMPT_END`             | per shell                       | the character each prompt ends with, when you want the same one everywhere; the three below win over it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_PROMPT_END_BASH`        | `\$`                            | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root")                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_PROMPT_END_ZSH`         | `>`                             | zsh's prompt separator - zsh prompt escapes work, so `%#` behaves as anywhere else in `PS1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_PROMPT_END_FISH`        | `\|`                            | fish's prompt separator; root still gets `#` regardless                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_TERM_FALLBACK`          | `1`                             | on ssh targets missing a terminfo entry for your `TERM` (ghostty's `xterm-ghostty`, typically), swap it for `xterm-256color` before the session starts; `0` keeps the original                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_PACKAGES_MIN_PRIORITY`  | `2`                             | the lowest `settings/packages` priority the header's check prints, and the main dial on how long that check is. The file ranks every entry 0-3, and a line's leading mode character decides which states speak at all: `-` only when the line is missing (core tools, where present is not news), `+` only when something is installed (platform facts, where absent is noise), no flag both ways. `2` (the default) keeps useful tools and up, `1` adds the optional extras back, `0` prints everything, `3` leaves just the favorites and core alerts, and anything above `3` mutes the check entirely. An older overlay file still renders: priorities above 3 clamp to 3, and its unflagged lines speak both ways until a mode character is added. `hi --configure` asks for this with a live preview; `hi --packages-preview` marks the ranks it silences `below floor` |
| `_HI_PACKAGES_PALETTE`       | `cool`                          | which of `common/header.sh`'s named color tables the check paints an installed and a missing package with, per priority - `cool` (cyan through green for installed, blue through red for missing), `warm` (yellow through red), or `mono` (blue through cyan for installed, yellow through red for missing). Each ramp is meant to read monotonic 0-3 in both directions and legibly on light and dark terminals; judge a candidate with `hi --packages-preview`, which names the active palette above its legend. Any other value falls back to `cool`. `hi --configure` asks for this with the check's current render shown as a preview                                                                                                                                                                                                                                   |
| `_HI_ENABLE_FISH_ALIAS_ABBR` | `0`                             | fish only: `1` gives every alias hi defines a real `abbr`, so it expands to the full command on the line before you run it - it rewrites what your command line and history say, hence opt-in (`hi_abbr_aliases` does the work and is callable by hand). Not in the `_HI_DISABLE_*` table since it is fish-specific, not one of `core.sh`'s shared toggles                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_NO_LEAD_SPACE`          | `0`                             | `1` drops the single hardcoded leading space each of these puts before its own content: the prompt's `user@host` (bash/zsh/fish), the git segment (`common/git_prompt.sh`), the banner line, and the first cell of every header row. The `\|`-separated space between later cells on the same header row is untouched - that separator is structural, not this                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_TTY`                    | `[ -t 0 ]`                      | whether the container backends hand the session a tty (`docker exec -it` vs `-i`). Answered by probing stdin; set it to `1` or `0` to override, which is what a wrapper that knows better than the probe does. `docker exec -it` refuses outright when stdin is a pipe, so `hi <container> <cmd> \| ...` depends on this being right                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_SESSION_RC`             | `mktemp -d`                     | set by hi inside a session: the directory holding the per-shell rc files a nested `bash`/`zsh`/`fish`/`sh` reads, removed when the session ends. `$ZDOTDIR` and `$ENV` are exported alongside it, see [HI.46](GLOSSARY.md#hi46-session-rc-directory)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

`_HI_TARGETS_TTL` and `_HI_PROBE_TIMEOUT` exist because completion runs on
**every TAB** and the header runs **before you get a shell**: a docker daemon
that is down or a `kubectl` pointed at a dead cluster would otherwise hang
there with no upper bound.

`_HI_CTL_PERSIST` and `_HI_PAYLOAD_CACHE` exist because a fresh `hi <target>`
otherwise pays a full key exchange and rebuilds the same payload every single
time, even against a target you connected to seconds ago. Both cache into a
private per-user directory (`$XDG_RUNTIME_DIR`, or a `mkdir -m 700` one of
hi's own under `${TMPDIR:-/tmp}`, ownership-checked the way `hi <TAB>`'s own
completion cache already is) and both fail open to today's behaviour - a
fresh socket, a fresh build - when that directory is unavailable or not
yours. The connect line's `connect: Xs` figure ([Header details](#header-details))
is the two together: a warm socket and a warm cache both show up as a smaller
number there, not as a setting you have to check.
