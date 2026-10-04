# Settings

`hi --configure` asks every setting under a live preview and writes the
answers to `settings.sh` ([The wizard](#the-wizard)). That file, and every
other file of yours hi reads, lives **outside the checkout**, in the overlay
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` (`$_HI_CONFIG_DIR`), so `git pull`
applies cleanly and the tree can be root-owned or package-installed; the
tree's `config/` holds the shipped defaults. The overlay rides to every host
you say `hi` to ([The overlay](#the-overlay), [How it works](HOW-IT-WORKS.md)).

## Contents

- [The wizard](#the-wizard)
- [Presets](#presets)
- [The overlay](#the-overlay)
- [Every setting](#every-setting)
  - [Not settings](#not-settings)
- [Header details](#header-details)
  - [Others](#others)
  - [Shells you drop into inside a session](#shells-you-drop-into-inside-a-session)
  - [Extensions](#extensions)
  - [Switching a plugin off](#switching-a-plugin-off)
  - [A tool hi does not know](#a-tool-hi-does-not-know)
- [The editor rcs come from where you keep them](#the-editor-rcs-come-from-where-you-keep-them)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)

## The wizard

`hi --configure` opens on the keys (`[p]reset`, `[h]eader preset`, `[s]ave`,
`[q]uit`) and a preview - the header and the prompt line as they would draw
at your current settings - over one summary line per section: its letter,
its item numbers, and how many of its switches are on. The letter opens the
section's page, with the same preview over just that section's settings,
and `[b]` comes back. Every setting keeps one number across the pages, and
a number works from any of them:

- **Header** `[i]` — the header and the greeting on or off, then everything
  in [Header details](#header-details): the banner, the header's items in
  the order they print (`up N`/`down N` moves one), all as a grid, then the
  width, the package groups (each listed with what it holds, flipped by
  number or name), and the hidden addresses. Outside the menu,
  `hi --preview header` prints the header at the saved settings, and
  `hi --preview packages` the check's legend.
- **Prompt** `[r]` — the preview's last line: the colored prompt on or off, git
  status and the environment segment, who draws each shell's prompt (auto,
  hi's own, or one of the prompt programs), and the character each of the
  three shells' prompts ends with, wired up on this machine or not.
- **Plugins** `[g]` — the carried configs that stay home, listed by group
  and checked while they ride: a number, or a plugin, member, or group by
  name, flips one ([Switching a plugin off](#switching-a-plugin-off)).
- **Aliases** `[a]` — whether `cat`, `ls`, and `sudo` get hi's aliases; both
  opt-ins, off until turned on.
- **This machine** `[m]` — whether hi styles the machine you run it on as well
  (`_HI_DISABLE_LOCAL`).
- **Advanced** `[v]` — the leading space, the header's right edge, the `--mux`
  and `--keep` defaults, and 24-bit color.

A row away from its default says the default beside it (`(default 2)`,
`(default on)`). The menu draws to your terminal's width: help text is cut
rather than wrapped, the header grid folds to fewer columns when narrow, and
the preview box clips a line wider than the room. At 80 columns every page
fits a 24-row terminal.

A number flips a yes/no item or asks for a value, and the preview and list
redraw with the change. `[p]` applies a preset (`[e]verything`, `[b]alanced`,
or `[m]inimal`, below) and `[h]` a header preset (`[f]ull`, `[c]ompact`,
`[q]uiet`). The wizard does not ask about colors: `_HI_COLOR_SCHEME` and
`_HI_PACKAGES_PALETTE` are written into `settings.sh` by hand
([Colors](COLORS.md)), and it keeps whatever they hold.

`[s]` writes the settings once, `[q]` leaves `settings.sh` untouched, and
nothing is written before either. End of input at the menu counts as `[s]`;
three answers in a row that are not menu items count as `[q]`; with no
terminal (`hi --configure </dev/null`, a script) there is no menu — the file
is written back as it stands, and none is created when there is nothing to
say. A line you wrote into `settings.sh` by hand is adopted into hi's block
the next time the wizard writes that setting, never duplicated beside it.

## Presets

The menu's `[p]`, or `hi --configure --preset <name>` without the menu:

| preset       | what it answers                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | the shipped defaults: every feature and header item on, the alias opt-ins off                                                                            |
| `balanced`   | everything but the noise: a shorter package check (`_HI_PACKAGES_GROUPS=core,deprecated`)                                                                |
| `minimal`    | on targets only the colored prompt: no header, git status, or editors (`_HI_PLUGINS_OFF=editors`) — and nothing on this machine (`_HI_DISABLE_LOCAL=1`). |

A preset is an absolute answer over the feature toggles, the banner, the package
check's groups, and the plugins kept home: what it names is set and the rest of
those return to their defaults. Everything else — the header order, the width,
the hidden addresses, the colors, the prompt program and separators, the
advanced settings — keeps what it holds. From the menu its answers are only what
the preview shows until `[s]` saves them. The rows are `scripts/configure.sh`'s
`_HI_PRESETS`.

## The overlay

Every file hi reads from `~/.config/say-hi/`, and the shipped file each
one overrides. Each resolves in one order: the copy here, else your own file
where its tool keeps it on this machine
([below](#the-editor-rcs-come-from-where-you-keep-them)), else the shipped
default. A shell's own rc - `bashrc`, `zshrc`, `config.fish` - has no middle
step: it rides only from here, never found at home
([HI.61](GLOSSARY.md#hi61-one-overlay-priority)).

| overlay file                            | overrides         | what it is                                                                                                                                                                                                     |
| --------------------------------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.config/say-hi/settings.sh`          | -                 | what `hi --configure` writes; no in-tree counterpart                                                                                                                                                           |
| `~/.config/say-hi/colors`               | `config/colors`   | your color pins; `hi --set-color` copies the tree's in before its first write ([COLORS.md](COLORS.md))                                                                                                         |
| `~/.config/say-hi/packages`             | `config/packages` | what the package check looks for; `hi --add-package` copies the tree's in before its first write ([COLORS.md](COLORS.md#the-package-checks-rows))                                                              |
| `~/.config/say-hi/vim/vimrc`            | -                 | your vim config for the `vim` alias and `$VIMINIT`; only needed when it should differ from your `~/.vimrc`, which hi carries anyway ([below](#the-editor-rcs-come-from-where-you-keep-them))                   |
| `~/.config/say-hi/nvim/init.lua`        | -                 | the same for neovim - the `nvim` alias, and `vim` where a target has nvim - over your `~/.config/nvim/init.lua`                                                                                                |
| `~/.config/say-hi/helix/config.toml`    | -                 | the same for the `hx` or `helix` alias (`-c`), over your `~/.config/helix/config.toml`                                                                                                                         |
| `~/.config/say-hi/helix/languages.toml` | -                 | helix's language settings, over your `~/.config/helix/languages.toml`; `hx` has no flag for it, so a target reads it through the `xdg` wire ([below](#a-tool-hi-does-not-know))                                |
| `~/.config/say-hi/kak/kakrc`            | -                 | kakoune's `kak/kakrc`, over your own: on a target `$KAKOUNE_CONFIG_DIR` names the overlay, so kak's system kakrc and its syntax files still load                                                               |
| `~/.config/say-hi/kak/colors/`          | -                 | kakoune colorschemes, file by file, beside your `~/.config/kak/colors/`: the scheme a `kak/kakrc` names with `colorscheme` is there on a target                                                                |
| `~/.config/say-hi/nano/nanorc`          | -                 | the same for the `nano` alias, over your `~/.nanorc`                                                                                                                                                           |
| `~/.config/say-hi/emacs/init.el`        | -                 | the same for the `emacs` alias (`emacs -nw -q -l`), over your `~/.emacs`                                                                                                                                       |
| `~/.config/say-hi/tmux/tmux.conf`       | -                 | the same for the `tmux` alias (`tmux -f`), over your `~/.tmux.conf`; with neither, `tmux` is left alone                                                                                                        |
| `~/.config/say-hi/screenrc`             | -                 | the same for the `screen` alias (`screen -c`), over your `~/.screenrc`                                                                                                                                         |
| `~/.config/say-hi/zellij/`              | -                 | zellij's `config.kdl`, `layouts/`, and `themes/`, each file over the one in your zellij config directory; the `zellij` alias's `--config-dir` names it                                                         |
| `~/.config/say-hi/micro/`               | -                 | micro's `settings.json`, `bindings.json`, and `init.lua`, each over the one in your micro config directory; the `micro` alias's `-config-dir` names it                                                         |
| `~/.config/say-hi/aliases.sh`           | -                 | your own aliases, sourced **last** so they replace hi's of the same name - same POSIX+fish subset; see [below](#shells-you-drop-into-inside-a-session)                                                         |
| `~/.config/say-hi/plugins`              | -                 | a plugin for each tool hi does not know, or your own for one it does; read here and not sent; see [below](#a-tool-hi-does-not-know)                                                                            |
| `~/.config/say-hi/extensions/`          | -                 | extensions in the same subset, sourced after the aliases in name order; see [below](#extensions)                                                                                                               |
| `~/.config/say-hi/header/`              | -                 | header cells of your own, a bash file each defining `_hi_cell_<word>` for `_HI_HEADER_ORDER` to name; see [Integrations](INTEGRATIONS.md#header-cells-of-your-own)                                             |
| `~/.config/say-hi/bashrc`               | -                 | your bash preferences, sourced at the end of `common/bash.sh` - history sizing, `shopt`s, readline bindings - or a copy or symlink of your whole `~/.bashrc` ([below](#shells-you-drop-into-inside-a-session)) |
| `~/.config/say-hi/zshrc`                | -                 | the same for zsh - history, keybindings, `zstyle` completion rules                                                                                                                                             |
| `~/.config/say-hi/config.fish`          | -                 | the same for fish - keybindings and the `fish_color_*` / `fish_pager_color_*` palette                                                                                                                          |
| `~/.config/say-hi/oh-my-posh.json`      | -                 | your oh-my-posh config (or `.yaml` / `.toml`), `$POSH_CONFIG` on every target that hands the prompt to oh-my-posh; over the one `$POSH_CONFIG` or your rc's `oh-my-posh init --config` names                   |

starship's, powerlevel10k's, tide's, bat's, eza's, rg's, fzf's, lazygit's, and
readline's own configs, and your oh-my-zsh, oh-my-bash, and bash-it themes, need
no copy here: every target gets the one each tool reads on your machine
([Integrations](INTEGRATIONS.md#prompt-programs)). A `starship.toml`,
`p10k.zsh`, `oh-my-zsh.zsh-theme`, `oh-my-bash.theme.sh`, `bash-it.theme.bash`,
`tide.vars`, `bat/config`, `eza/theme.yml`, `ripgreprc`, `fzfrc`,
`lazygit/config.yml`, or `inputrc` in `~/.config/say-hi/` is the override:
targets get it instead, and at home the tool keeps reading its own. A prompt
program's copy rides only when that program is one a target is handed, and
`hi --doctor` says when it is not.

The overlay starts empty: `hi --install` writes `settings.sh` and nothing
else. To override `colors`, copy the shipped file in and edit the copy:

```sh
mkdir -p ~/.config/say-hi
cp "$_HI_ROOT/config/colors" ~/.config/say-hi/colors
```

`hi --add-package core bat,batcat` does that copy for the package check, then
adds the row; `hi --set-color hostname bastion yellow` does it for `colors`,
then adds the pin.

A copy stops tracking what `hi --update` delivers for that file; delete it to
track the tree's again, and `hi --doctor` names which of the two is in force. A
member is named as its tool names the file, under a directory of the tool's name
where the tool keeps one in `~/.config`, so the overlay is shaped like the
`~/.config` it stands in for: `nvim/init.lua`, `bat/config`,
`lazygit/config.yml`, and `starship.toml` or `inputrc` at the top, where their
tools keep them. Before 1.0 a member had other names (`vim.rc`, then `vimrc`,
for `vim/vimrc`; `bat.conf` for `bat/config`; `bash.sh` for `bashrc`); a file
still under an old name is not read, and `hi --doctor` names it with the `mv`
that fixes it. Versioning the directory is yours to do — a `git init` there, or
[a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager).

`packages` in `name:N` rows, `colors` in `type,name,color` rows, and a
`settings.sh` setting `_HI_PACKAGES_MIN_PRIORITY` are an older hi's shapes,
which this one does not read. `hi --install` and `hi --configure` convert them
before the menu opens, and `hi --update` does so with the new tag's converter
after checking it out; by hand,
`scripts/convert_settings.sh [--dry-run] [<dir>]`. Each converted file keeps its
original beside it as `<file>.old`, a file already in the current shape is left
alone, and `hi --doctor` flags one still in the old shape. A `packages` or
`colors` file holding one TOML row is in the current shape, whatever else it
holds; a `packages` line hi does not read is `hi --doctor`'s to name. A
packages row goes to the group its highest `N` named (3 `core`, 2 `useful`, 1
`extras`, 0 `trivia`), alternatives sorted highest `N` first; an old `-` row
becomes a `+` row (in `base` at `N` 0-1), and an old `+` row a plain row in
`platform`.
`_HI_PACKAGES_MIN_PRIORITY` becomes a `_HI_PACKAGES_GROUPS` line - 0 all seven
groups, 1 `core useful deprecated extras base`, 3 `core deprecated`, 4 or more
`none` - and is dropped at 2, the default, or when `settings.sh` already sets
`_HI_PACKAGES_GROUPS`. An editor's or a multiplexer's `_HI_DISABLE_*` toggle,
which the list of plugins replaced, becomes its word in `_HI_PLUGINS_OFF`:
`_HI_DISABLE_EDITORS=1` is `editors`, `_HI_DISABLE_VIM=1` both `vim` and `nvim`,
and one set to `0` just goes.

## Every setting

Every setting below is an environment variable, checked where it is used.
`hi --configure` writes your answers to `settings.sh` — a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh, and fish — which
every shell sources ahead of `common/paths.sh`. Exporting one by hand works
too, for a name `settings.sh` does not set: the file is sourced after the
environment, so its line wins. Neither reaches programs started from a hi
shell: once the rc has run, every `_HI_*` name except six is a plain shell
variable ([HI.47](GLOSSARY.md#hi47-what-a-child-inherits) says which, and
why). A setting a child must see is an `export` in
[your own `bashrc`/`zshrc`/`config.fish`](#shells-you-drop-into-inside-a-session).

The whole vocabulary a `settings.sh` may use, grouped roughly by what each
setting changes - the header, the features, the prompt, the advanced ones - and
then the settings nothing asks about; the linked sections explain. The **set
by** column:

- **you** — supported surface nothing asks about: export it, or write an
  `export` line into `settings.sh` by hand. The wizard carries such a line
  over, never drops it.
- **`hi --configure`** — the same, with a menu item attached. **advanced**
  marks the items under the menu's _Advanced_ heading.

The table is written from `scripts/settings`, one row a setting, which
`hi --configure` reads its menu items from too, so a new setting is one row
there. A value written by hand that the code would silently fall back from - a
width under 40, a header word or prompt program hi does not know, an editor off
the ladder - is a red `hi --doctor` row, judged by the same rules the wizard
takes an answer by.

| variable                 | default                                                                           | set by                    | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_BANNER`     | `0`                                                                               | `hi --configure`          | hides the `=== Connected ===` line ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_DISABLE_HEADER`     | `0`                                                                               | `hi --configure`          | turns off the whole header: a connect's, a disconnect's, and the greeting a local interactive shell prints; a connect then leaves `header.sh` and the package list out of the payload                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_DISABLE_GREETING`   | `0`                                                                               | `hi --configure`          | hides the `hi loaded:` line and its init/copy/load timers; not part of the header, so `_HI_DISABLE_HEADER` leaves it alone ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_HEADER_ORDER`       | the table in [Header details](#header-details)                                    | `hi --configure`          | which header items show, in what order; empty is the default list                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_MAX_WIDTH`          | `80`                                                                              | `hi --configure`          | terminal columns the header and banner are drawn to, narrowed to a smaller real terminal; 40 is the least the wizard takes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_PACKAGES_GROUPS`    | `core useful deprecated`                                                          | `hi --configure`          | the `config/packages` groups the header's check runs, space- or comma-separated, or `none`, and the main dial on its length: `extras` adds optional tools, `trivia`, `base`, and `platform` the rest of the file. A group of your own is named the same way; drop `check` from `_HI_HEADER_ORDER` to turn the check off. See [The package check's rows](COLORS.md#the-package-checks-rows)                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_IP_HIDE`            | `172.*`                                                                           | `hi --configure`          | globs the header's `ip` cell drops; `none` hides nothing ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_DISABLE_GIT_STATUS` | `0`                                                                               | `hi --configure`          | turns off the git segment in the prompt                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_DISABLE_ENV_STATUS` | `0`                                                                               | `hi --configure`          | turns off the prompt's environment segment - the leading `(myproj)` naming the active venv, conda, direnv, nix, guix, devbox, or version-manager environment. See [Integrations](INTEGRATIONS.md#the-environment-segment)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `_HI_TOOL_ALIASES`       | `0`                                                                               | `hi --configure`          | `1` turns on the styled tool aliases: `cat`/`catn` as `bat` with `_HI_BAT_OPTS`, `bat`/`batcat`/`batn`, and `ls`/`exa`/`eza` through the list ladder. Off, none of them exists and the `_HI_*_BIN` lookups are skipped. See [Integrations](INTEGRATIONS.md#bat-and-eza)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_SUDO_ALIAS`         | `0`                                                                               | `hi --configure`          | `1` turns on the `sudo` alias - the trailing-space alias in bash/zsh that lets `sudo vim` keep the vim alias's flags, and fish's wrapper function that does the same for its alias functions                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_DISABLE_LOCAL`      | `0`                                                                               | `hi --configure`          | turns off everything above, the two alias opt-ins included whatever they say, and the banner, **on this machine only** - hi still styles the hosts you visit ([Others](#others))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `_HI_DISABLE_PROMPT`     | `0`                                                                               | `hi --configure`          | turns off the colored `user@host` prompt, leaving your shell's own                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_PROMPT_TOOL`        | unset                                                                             | `hi --configure`          | who draws the prompt: a space-separated list of `powerlevel10k`, `oh-my-zsh`, `oh-my-bash`, `bash-it`, `tide`, `starship`, `oh-my-posh`, `powerline-go`, and `hi` (hi's own), each shell taking the first entry that fits it and that the target has. An entry written `<shell>:<program>` (`bash:starship`) is tried first, by that shell alone, so `bash:starship hi` draws starship in bash and hi's prompt in zsh and fish. With no plain entry, or unset, the rest is every program installed on this machine, frameworks first, so a prompt you already use follows you; `hi` keeps hi's prompt everywhere. `hi --configure` asks shell by shell. hi keeps its header and aliases either way, and installs nothing. See [Integrations](INTEGRATIONS.md#prompt-programs) |
| `_HI_PROMPT_END_BASH`    | `\$`                                                                              | `hi --configure`          | bash's prompt separator (`\$` is bash's escape for "`$`, or `#` for root"); also the plain `sh` prompt hi bakes on the client for a bash-less target                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_PROMPT_END_ZSH`     | `>`                                                                               | `hi --configure`          | zsh's prompt separator - zsh prompt escapes work, so `%#` behaves as anywhere else in `PS1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_PROMPT_END_FISH`    | `\|`                                                                              | `hi --configure`          | fish's prompt separator; unset, root gets `#` in its place, and a value you set is used for root too                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_DISABLE_LEAD_SPACE` | `0`                                                                               | `hi --configure` advanced | `1` drops the leading space before the prompt's `user@host`, the git segment, the banner line, and the first cell of every header row                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_DISABLE_RIGHT_EDGE` | `0`                                                                               | `hi --configure` advanced | `1` drops the closing \| from every header row and the greeting line, so each ends at its last cell instead of at the banner's column                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_PLUGINS_OFF`        | unset                                                                             | `hi --configure`          | the plugins, groups, or members that stay home, a space or a comma apart; `hi --plugin-off` and `hi --plugin-on` write it too ([Switching a plugin off](#switching-a-plugin-off))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_MUX`                | `0`                                                                               | `hi --configure` advanced | `1` makes every connect a `--mux` one, in a local tmux, zellij, or screen session; `--no-mux` overrides it for one connect                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_KEEP`               | `0`                                                                               | `hi --configure` advanced | `1` makes every ssh connect a `--keep` one: the session runs in tmux, zellij, or screen on the target and outlives the connection ([Integrations](INTEGRATIONS.md#terminal-multiplexers)); `--no-keep` overrides it for one connect                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_KEEP_TIMEOUT`       | `24h`                                                                             | you                       | how long a kept session waits with nobody attached before it closes and its directory is removed: a number of seconds, or one with `s`, `m`, `h`, or `d`; `0` is never. Read on the target, so it belongs in `settings.sh`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_KEEP_RETRY`         | `5m`                                                                              | you                       | how long a connect inside a local tmux, zellij, or screen keeps retrying a target whose kept session it lost the link to: a duration as above; `0` is never                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_TRUECOLOR`          | by terminal                                                                       | `hi --configure` advanced | `1`/`0` forces or refuses 24-bit color; unset, the client decides ([Colors](COLORS.md))                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_EDITOR`             | unset                                                                             | you                       | the editor a target session exports as `$EDITOR`, `$VISUAL`, and `$SUDO_EDITOR`, by command name (`nvim`, `micro`, ...); used when the target has it. Unset, `$EDITOR` is your own `$EDITOR`'s command (else your `$VISUAL`'s) and `$VISUAL` your `$VISUAL`'s (else your `$EDITOR`'s) where the target has it, else the first of `nvim vim micro hx nano emacs` it does have; `$SUDO_EDITOR` follows `$EDITOR`. Each carries hi's config flags so `git commit` and `sudo -e` get the editor the alias gives you                                                                                                                                                                                                                                                               |
| `_HI_PACKAGES_PALETTE`   | unset                                                                             | you                       | the color the check paints each group's tier in: eight color names, four installed then four missing. Unset, or anything but eight names, is the shipped ramp (`cyan green brcyan brgreen blue magenta bryellow brred`). See [The package check's ramp](COLORS.md#the-package-checks-ramp)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_COLOR_SCHEME`       | unset                                                                             | you                       | what the palette names render as on a terminal that reports 24-bit color: twenty-four or forty-eight six-digit hex words. Unset is the terminal's own sixteen colors. See [Colors](COLORS.md)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `_HI_POWERLINE_GO_OPTS`  | unset                                                                             | you                       | extra flags for [powerline-go](https://github.com/justjanne/powerline-go) when it draws the prompt, word-split (`-modules venv,cwd,git -mode flat`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_SYMBOL_SSH`         | `»` (`>` in ASCII)                                                                | you                       | the symbol an ssh host carries in `hi <TAB>`'s list - fish's description column, beside the name when bash 4+ lists matches, zsh's display. Any text; an empty value counts as unset                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_SYMBOL_CONTAINER`   | `▣` (`#`)                                                                         | you                       | the same for a docker, podman, nerdctl, or finch container                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_SYMBOL_NOMAD`       | `◆` (`*`)                                                                         | you                       | the same for a nomad allocation                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_SYMBOL_KUBE`        | `⎈` (`@`)                                                                         | you                       | the same for a kubernetes pod                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `NO_COLOR`               | unset                                                                             | you                       | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything without color, shipped to the target next to [`_HI_ASCII`](#not-settings)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_LS_OPTS`            | the rung's own flags below, else `-F -l` (and `--color=auto` where `ls` takes it) | you                       | the flags the `ls`/`eza`/`exa` alias runs with - set it and it is the whole answer, whichever binary the ladder picked                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_EZA_OPTS`           | `-F -1 -l -m --group-directories-first --smart-group` + a time format             | you                       | what `_HI_LS_OPTS` defaults to when eza is the rung that answered                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_EXA_OPTS`           | the same leading flags + `--group --no-filesize`                                  | you                       | the same for exa, whose column set its successor dropped                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_BAT_OPTS`           | `-P --tabs 2 --style changes,grid`                                                | you                       | the flags the `bat`/`batn` aliases attach; no `--theme`, so your bat config's theme is the one you see                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_CAT_BIN`            | first of `bat`, `batcat`, `ccat`, `cat` on PATH                                   | you                       | which binary the `bat` and `cat` aliases run (Debian ships bat as `batcat`; the tail keeps `cat` working where none is installed). Like the other two `_BIN`s, looked up only under `_HI_TOOL_ALIASES=1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_BAT_BIN`            | first of `bat`, `batcat` on PATH                                                  | you                       | the bat-only tier behind it, what parses `_HI_BAT_OPTS` - two rungs shorter on purpose; set with it, or leave both alone                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_LS_BIN`             | first of `eza`, `exa`, `ls` on PATH                                               | you                       | which binary the `ls`, `eza`, and `exa` aliases all run - one ladder, and `_HI_LS_OPTS` follows the rung it answered with                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

### Not settings

More names look like settings and are not:

- `$_HI_CONFIG_DIR` and `$_HI_HOME` (the **parent** of your `say-hi`
  directory) are read **before** `settings.sh` is sourced, so a line there is
  too late: export them, as `hi.sh` and `install.sh`'s rc line do. Unset, each
  entry point derives `$_HI_HOME` from its own path. `$_HI_XDG_CONFIG` is the
  `$XDG_CONFIG_HOME`-or-`~/.config` base resolved beside them — set
  `$XDG_CONFIG_HOME` instead.
- `$_HI_ROOT`, `$_HI_SSH_CONFIG` (where ssh hosts and their `# Tags:` comments
  are read from), `$_HI_COLORS`, and `$_HI_PACKAGES` are re-derived by
  `common/paths.sh` on every source, from `$_HI_HOME`, `$HOME`, and the overlay,
  so an exported value does not survive: put your file in the overlay.
- `$_HI_VIMRC`, `$_HI_NVIMRC`, and `$_HI_NANORC` are a session's: the path of a
  config that rode, set on a target by `wiring.sh`
  ([HI.62](GLOSSARY.md#hi62-generated-wiring)). At home nothing reads them.
- `$_HI_KEEP_MUX` and `$_HI_KEEP_NAME` are a kept session's: `hi.sh` hands
  them to the session's first pane, which is how `load.sh` knows it owns the
  session ([HI.65](GLOSSARY.md#hi65-kept-session)).
- `$_HI_ASCII` is the _client's_ verdict, from its locale, on whether its
  terminal renders multibyte glyphs, shipped to the session next to
  `$NO_COLOR`: the glyphs land in the terminal you sit at, so a target whose
  `LANG` is `C` still shows them when yours does.
- `$_HI_REMOTE_SESSION` is hi's "this is a session" mark: `load.sh` exports
  it as `1` on a target, no local rc ever does, and it is how the local-only
  toggle tells the two apart. Written into `settings.sh`, it tells every shell
  it is somewhere it is not.
- Five test levers - `_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT`,
  `_HI_PAYLOAD_CACHE`, `_HI_CTL_PERSIST`, and `_HI_HEADER_VERSION` - take
  effect like any row above but exist for the suites, the bench, and the
  demos ([TESTING.md's _Test levers_](TESTING.md#test-levers)). They are not
  part of the 1.x contract and may change in a minor.
- `$_HI_RELEASE` is the version `packaging/stamp.sh` stamps at build time,
  and `$_HI_SESSION_RC` the `mktemp -d` holding a session's per-shell rc
  files ([HI.46](GLOSSARY.md#hi46-session-rc-directory)).
- `$_HI_TARGET_COLOR` and `$_HI_TARGET_TAG` (the color and `# Tags:` value the
  target resolved to) and `$_HI_LOCAL_USER`/`$_HI_LOCAL_HOSTNAME` (the header's
  "from" half) are set from the client;
  `$_HI_HOST_COLOR`/`$_HI_USER_COLOR`/`$_HI_HOST_ESC`/`$_HI_USER_ESC` are the
  resolved prompt colors, for
  [your own prompt](COLORS.md#using-the-hash-in-your-own-prompt) to read.
  Setting one by hand tells the shell something untrue about where it is.

Everything else beginning `_HI_` is internal state, named that way to stay
out of your namespace.

## Header details

`_HI_DISABLE_BANNER=1` hides the `=== Connected [host] ===` line, on connect
_and_ disconnect; it always leads, so it takes a switch rather than a place in
the order below. `_HI_DISABLE_HEADER=1` turns off everything in this section
without erasing it: `hi --configure` keeps a stored order while the header is
off. The wizard's _Header_ items edit all of it under the rendered header
([The wizard](#the-wizard)). The `hi loaded:` line and its init/copy/load timers
are not part of this section - they survive `_HI_DISABLE_HEADER` and answer to
`_HI_DISABLE_GREETING` of their own.

Everything else the header prints is one flat list of reorderable items, with
no fixed rows. `_HI_HEADER_ORDER` is a space-separated subset of these words,
in the order they should print:

| word         | what it is                                          |
| ------------ | --------------------------------------------------- |
| `utc`        | the UTC clock                                       |
| `version`    | hi's own version                                    |
| `localtime`  | your local clock                                    |
| `os`         | the OS name/version                                 |
| `arch`       | the CPU architecture                                |
| `cores`      | core count and load percentage                      |
| `cpu`        | clock speed                                         |
| `ram`        | used/total memory                                   |
| `ip`         | this box's routable IPv4 address(es)                |
| `gitid`      | the masked git identity (`user.email`)              |
| `containers` | the docker/podman container count, when either runs |
| `jobs`       | the nomad job count, when nomad answers             |
| `pods`       | the reachable kube pod count, when kubectl answers  |
| `auth`       | the `~/.ssh/authorized_keys` line count             |
| `pub`        | the `~/.ssh/*.pub` file count                       |
| `uptime`     | this box's uptime                                   |
| `check`      | the installed-packages check (`config/packages`)    |

A word left out is not printed, and an unknown word is ignored. A word of your
own is a file of the overlay's `header/`
([Integrations](INTEGRATIONS.md#header-cells-of-your-own)).
`containers`/`jobs`/`pods` render only when their backend answers; listing them
decides whether hi asks at all. They are in the default order on purpose, the
one exception to a header probing only what you asked for: every local shell
with it runs docker, podman, nomad, and kubectl, each capped by
`_HI_PROBE_TIMEOUT`. An order without the three words starts none. Each word has
a fixed color, swapped for an alternate when it would repeat the cell before it,
so no order puts two same-colored cells side by side
([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)). Unset or empty is the
table's order:
`utc version localtime os arch cores cpu ram ip gitid containers jobs pods auth pub uptime check`.

The `ip` cell's `_HI_IP_HIDE` globs match the dotted quad; the `172.*` default
keeps a docker or podman bridge address from being the first thing a
container's header says, and `10.* 192.168.1.?` is two globs. When every
address a box has is hidden the cell is dropped rather than drawn as `?`,
which still means no routable address was found at all.

A physical line that overflows `_HI_MAX_WIDTH` does not wrap within itself:
whatever does not fit opens the next line, cascading forward through the order
until the packages check (the one variable-length item) absorbs the rest, or -
with `check` left out - prints as its own trailing line.

### Others

`_HI_DISABLE_LOCAL` is "leave my own machine alone, but give me hi everywhere I
connect to"; a session is told apart by [`$_HI_REMOTE_SESSION`](#not-settings).
A prompt or shell framework of your own on this machine is
[Integrations' _On your own machine_](INTEGRATIONS.md#on-your-own-machine), and
what hi writes there outside `~/.config/say-hi/` is
[FILES.md](FILES.md#what-hi-creates-on-this-machine).

Every styled hi prompt (not the bash-less `sh` one) emits
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
marks where each prompt, command, and output begins, and OSC 7 with the working
directory (percent-encoded), for terminals that read them — kitty, WezTerm,
ghostty, foot, iTerm2, Konsole; the rest drop them. None go out on `TERM=dumb`,
to anything but a terminal, or while kitty's, ghostty's, WezTerm's, or iTerm2's
own shell integration is sending its set, which each prompt checks for. A shell
left from its prompt (Ctrl-D) closes the last prompt's pair on its way out, so
Konsole's semantic hints stop there instead of shading the parent shell's lines.
`load.sh` sends the closing "command finished" mark a session's `exit` never
gets to — without it Konsole sends ↑ as ← until the next prompt — and a session
that ends any other way gets it from the client, with a reset of the terminal
modes a remote program may have left on
([HI.53](GLOSSARY.md#hi53-terminal-reset-after-a-failed-session)).

### Shells you drop into inside a session

A `bash`, `zsh`, `fish`, or `dash` started _inside_ a session keeps hi's
aliases, prompt, and paths, with nothing written to the target. `load.sh`
writes one rc per shell into a scratch directory, `$_HI_SESSION_RC`: zsh finds
its rc through `$ZDOTDIR` and sh/dash/ash through `$ENV`, both exported, so
however the shell is started; bash and fish have no such variable (bash's
`$BASH_ENV` covers only _non_-interactive shells), so `common/aliases.sh`
wraps each. Every rc sources the target's own rc first and hi's on top
([HI.46](GLOSSARY.md#hi46-session-rc-directory)).

Two things no wrapper reaches. A bash or fish shell nothing typed - a `tmux`
pane spawning a login shell, an editor shelling out - comes up as the host's
own, because hi writes to no login file on any host you visit
([COMPATIBILITY.md](COMPATIBILITY.md#what-would-change-an-answer) has the
reasoning). Nor does a change of user: `sudo -i`, `sudo -s`, `su -`, and
`doas -s` start _that_ user's login shell from _that_ user's rc files. What
survives is `sudo <command>`, whose one command gets hi's aliases through the
`sudo` alias.

hi ships nobody's shell preferences — no history sizing, keybindings, `zstyle`
rules, or fish palette; each rc carries the prompt, the completions, and the git
segment. Your readline bindings ride on their own, as the
[`inputrc`](INTEGRATIONS.md#readline) you already keep. Shell code of your own
goes in one of three overlay files, which differ in dialect, in when they load,
and in whether an `export` there reaches programs started from the shell
([HI.47](GLOSSARY.md#hi47-what-a-child-inherits)):

| file                             | dialect                                                        | sourced                                                       | an `export` reaches children |
| -------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------- |
| `aliases.sh`                     | the POSIX+fish subset: `export`, `alias`, `&&` chains, no `if` | after hi's aliases, before the prompt is built                | no                           |
| `extensions/<name>`              | the same subset                                                | after `aliases.sh`, in name order ([Extensions](#extensions)) | no                           |
| `bashrc`, `zshrc`, `config.fish` | that shell's own, in full                                      | last, at the end of hi's rc for that shell                    | yes                          |

The per-shell file is sourced at the end of hi's, in the same dialect, and
wins - `HISTFILE` included; hi sets none. At home it may source your own
`~/.bashrc` or `~/.zshrc`: re-entered while it loads, hi's rc returns at once
([HI.55](GLOSSARY.md#hi55-re-entrant-rc-guard)). On a target that line does
nothing - `~/.bashrc` there is the target's, which the session already read
first, and a `source` of a path hi does not carry goes out disabled
([below](#the-editor-rcs-come-from-where-you-keep-them)).

To take your whole rc along instead, make the overlay file a copy or symlink
of it:

```sh
ln -s ~/.bashrc ~/.config/say-hi/bashrc
ln -s ~/.zshrc ~/.config/say-hi/zshrc
```

Every session then sources it after hi's rc, on this machine too. Lines that
read a file the target will not have - a second rc beside it, a plugin manager's
bootstrap - are disabled on the way out and named by `hi --doctor`; a
`# hi-allow` comment above one sends it as written (`# hi-quiet` drops it
without the row), and the file rides comment-stripped, so a long rc costs a few
KB on the wire ([Integrations](INTEGRATIONS.md#config-sizes)). Your `aliases.sh`
likewise loads **after** `common/aliases.sh`, so an `alias` there replaces hi's
of the same name, and can build on hi's flags rather than restate them:

```sh
alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"      # hi's flags, plus one
alias cat=cat                                    # this one alias back to plain
```

The `_HI_*_OPTS` and `_HI_*_BIN` values and the two opt-ins hi's aliases are
built from go in `settings.sh`, which loads first; set in `aliases.sh` they
arrive too late, and `hi --doctor` flags them. It also names an alias of yours
that replaces one hi points at a carried config (`alias nano=...` over
`nano --rcfile`), since that config then goes unused on a target.

Keep your aliases in `~/.aliases` already? With no `aliases.sh` in the
overlay, that file is what rides to targets, where it loads in the same place
and keeps to the same subset bash, zsh, and fish all parse. At home your own
rc goes on sourcing it; hi does not source it again.

### Extensions

Something hi does not do - another tool's init, a prompt segment of your own -
goes in a file of its own under `~/.config/say-hi/extensions/`, and rides to
every target with the rest of the overlay. An extension uses the same subset as
`aliases.sh` (`export`, `alias`, `&&` chains, no `if`/`fi`), so bash, zsh, and
fish all read the one file. Extensions load right after the aliases and before
the prompt is built, in name order (`10-` before `20-`). One a shell cannot
parse is skipped in that shell with a yellow line saying so, and
`hi --doctor` lists what loads and flags what does not parse.

An extension talks to hi through hook variables. `_HI_SEGMENT` is a command hi
runs on every prompt it draws, showing its output, if any, after the
environment prefix:

```sh
command -v kubectl >/dev/null 2>&1 &&
  export _HI_SEGMENT='kubectl config current-context'
```

It is a command and its words, split at spaces and run as they stand - no pipe,
quote, `$( )`, or glob - before every prompt, so keep it fast; for more, name a
script of your own. Each extension sets its own; hi collects them in load order.
The whole contract is [HI.59](GLOSSARY.md#hi59-extensions). Before 1.0 the
directory was `plugins.d`; one still under that name is not read, and
`hi --doctor` names it with the `mv` that fixes it.

### Switching a plugin off

A plugin is the configs of one tool that hi carries to a target: its files,
the tool that reads them, and what points the tool at them there. `hi --plugins` lists them,
a table a group and a row a member, drawn as `hi --doctor` draws its files:
where the file is found, and whether it is sent or why not:

```text
 ------------------------------------  cli  ------------------------------------
+---+------------------------------+--------------------------------+
| + | bat/config (bat)             | used ~/.config/bat/config      |
|   | lazygit/config.yml (lazygit) | switched off (_HI_PLUGINS_OFF) |
|   | none anywhere                | eza/ ripgreprc fzfrc inputrc   |
+---+------------------------------+--------------------------------+
```

`hi --plugin-off lazygit` keeps it home, and `hi --plugin-on lazygit` lets
it ride again. A name is a plugin, a member (`bat/config`), one file of a
member that is a directory (`extensions/10-kube`), or a group, which
switches all of its kind: `editors`, `mux`, `prompt`, `cli`, `shell`, or
a table of your own `plugins` file. What is off sends no file, an overlay
copy included, and sets nothing on a target, so the tool there keeps the
target's own config. hi's own files (`settings.sh`, `colors`, `packages`)
are not plugins and always ride.

The list is `_HI_PLUGINS_OFF` in `settings.sh`, words a space or a comma
apart, and the wizard's Plugins page toggles the same words. It is about
what rides: at home a tool reads its own config, whatever the list says.
With `editors` in it a target also keeps its own `$EDITOR`, `$VISUAL`, and
`$SUDO_EDITOR`.

### A tool hi does not know

Every config hi carries belongs to a plugin of the tree's `config/plugins`,
in as much of TOML as hi reads: a `[<group>.<name>]` table for each tool, a
`key = "value"` to a line. A config hi has no plugin for rides once
`~/.config/say-hi/plugins` has one, written by hand or by `hi --add-plugin`,
and a plugin there of a name the tree's file has replaces the tree's whole:

```toml
[cli.task]
wire = "env:TASKRC"
home = "$TASKRC : $XDG_CONFIG_HOME/task/taskrc : ~/.taskrc"
files = "taskrc"

[cli.mytool]
wire = "flagdir:mytool --config-dir"
home = "~/.config/mytool/"
files = "mytool/rc mytool/keys.lua"

[cli.mytool."mytool/keys.lua"]
dialect = "lua"

[mine.notes]
tool = "-"
home = "~/notes.txt"
files = "notes.txt"
```

- **group** is the table's first name, the word that switches every plugin
  under it with `hi --plugin-off`: one of hi's (`editors`, `mux`, `prompt`,
  `cli`, `shell`) or one of your own.
- **name** is its second, the plugin: its own word for `hi --plugin-off`, and
  what a report calls it. Letters, digits, `_`, and `-`.
- **files** is the members, a space apart, each the name a file rides under:
  one hi does not use already, a tool's own file under its directory
  (`vim/vimrc`), or a directory whose files ride one by one
  (`zellij/layouts/`). A file of that name in `~/.config/say-hi/` is carried
  instead of home's.
- **tool** is the command that reads them, or several: home's copy rides only
  with one of them on this machine. Left out, it is the plugin's name; `-`
  asks about nothing.
- **wire** is how a target's tool finds a file: `env:` and the variables to
  set to the file's path, `envdir:` and the variable to set to its directory,
  `flag:` and the command and flag to alias it with (`flagdir:` for the
  directory; a flag written `--rc=` takes the path in the same word;
  several wires a `;` apart), `xdg:` and the command to alias with
  `$XDG_CONFIG_HOME` set to the overlay, or nothing when something of yours
  points at `$_HI_CONFIG_DIR/<member>`, an [extension](#extensions)'s alias
  say. `xdg:` is the fallback, for a file a tool has no variable and no
  flag for, such as helix's `languages.toml`: it reads the file as
  `<tool>/<file>`, the shape the member's name gives it, but every program
  the command starts inherits the variable, so a `git` under lazygit would
  not read the target's `~/.config/git`
  ([INTEGRATIONS.md](INTEGRATIONS.md#a-tool-with-no-variable-and-no-flag)).
- **home** is where a file is here, candidates a `:` apart, the first that
  exists winning. A candidate starts at `/`, at `~/`, or at a variable's name
  (`$XDG_CONFIG_HOME/...`), and is skipped while that variable is unset; written
  as several a `,` apart (`$TASKRC , ~/.taskrc`), it is the first of them not
  skipped, the way a tool looks in its default place only once its variable is
  unset. One ending in `/` is a directory each file is looked for in, by its
  name under the tool's own. Nothing else in it expands, and nothing in it
  runs.
- **dialect**, left out, has a file ride as written. Named, it is read the
  way hi reads its own configs: a line that sources a file no target has is
  disabled on the way out and named by `hi --doctor`, and comments are
  stripped. The dialects are `sh`, `fish`, `vim`, `lua`, `elisp`, `nano`,
  `tmux`, `screen`, `readline`, `kak`, `kdl`, `omp`, `omp-json`, and `conf`
  (`#` comments and nothing to source).

A file whose wire, home, or dialect is not its plugin's has a table of its own
under it, `[<group>.<name>."<member>"]`, holding the keys that differ; a wire
of `-` there gives that file none.

`hi --add-plugin cli task taskrc wire=env:TASKRC 'home=$TASKRC : ~/.taskrc'`
writes a table like the first above, the files first and any of `tool=`,
`wire=`, `home=`, and `dialect=` after them, quoted so the shell leaves a `$`
and a `~` alone, and refuses one hi could not read;
`hi --remove-plugin task` takes it out, its files' tables with it. A file's
own table is written by hand. `hi --plugins` and `hi --doctor` name each file
a plugin carries, and each line hi could not read, with the reason. The
variable or alias is set on a target only; at home the tool goes on reading
its own config. `hi --configure` rewrites a file of the rows this replaced,
`"<member>" = "<tool> | <wire> | <home> | <dialect>"` under a `[group]`
line. The whole contract is [HI.63](GLOSSARY.md#hi63-plugins-rows).

## The editor rcs come from where you keep them

The editor, tmux, screen, micro, and zellij rows of the overlay usually need
no file: hi carries the config each tool **already reads on this machine**,
so there is one copy to edit:

| member                 | hi looks at                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `vim/vimrc`            | `~/.vimrc`, else `~/.vim/vimrc`, else `$XDG_CONFIG_HOME/vim/vimrc`                                                  |
| `nvim/init.lua`        | `$XDG_CONFIG_HOME/nvim/init.lua`                                                                                    |
| `helix/config.toml`    | `$XDG_CONFIG_HOME/helix/config.toml`                                                                                |
| `helix/languages.toml` | `$XDG_CONFIG_HOME/helix/languages.toml`                                                                             |
| `kak/kakrc`            | `${KAKOUNE_CONFIG_DIR:-$XDG_CONFIG_HOME/kak}/kakrc`                                                                 |
| `kak/colors/`          | `${KAKOUNE_CONFIG_DIR:-$XDG_CONFIG_HOME/kak}/colors/`, file by file                                                 |
| `nano/nanorc`          | `~/.nanorc`, else `$XDG_CONFIG_HOME/nano/nanorc`                                                                    |
| `emacs/init.el`        | `~/.emacs.el`, else `~/.emacs`, else `~/.emacs.d/init.el`, else `$XDG_CONFIG_HOME/emacs/init.el`                    |
| `tmux/tmux.conf`       | `~/.tmux.conf`, else `$XDG_CONFIG_HOME/tmux/tmux.conf`                                                              |
| `screenrc`             | `${SCREENRC:-~/.screenrc}`                                                                                          |
| `micro/<file>`         | `${MICRO_CONFIG_HOME:-$XDG_CONFIG_HOME/micro}/<file>`, for `settings.json`, `bindings.json`, and `init.lua`         |
| `zellij/<file>`        | `${ZELLIJ_CONFIG_DIR:-$XDG_CONFIG_HOME/zellij}/<file>`, for `config.kdl` and every file of `layouts/` and `themes/` |

An overlay copy still wins — that is how you give a target an editor config
that differs from your local one. With neither, nothing rides and the tool
starts on the target's own config; a home config rides only with its tool
installed here. On a target the lookup is off: `$HOME` there is the
target's, and the file your client picked has already arrived.

The aliases are a target's. There `vim`, `nvim`, `hx` or `helix`, `nano`,
`emacs`, `micro`, `tmux`, `screen`, and `zellij` each name the file that rode,
where the target has the command. Here none of them is aliased, overlay copy or
not: every tool reads its own config, and `vim -u` or `nano --rcfile` would skip
the system rc besides.

Your own config is written for a machine with your plugins on it, and a target
has none. So hi reads each of these files — and the overlay's `settings.sh`,
`aliases.sh`, `extensions/` and `header/` members, per-shell rc files, and the
prompt configs it carries — for lines naming something it cannot carry: vim's
`source`, lua's `require`/`dofile` (and micro's `AddRuntimeFile`), nano's
`include`, elisp's `load`, tmux's `source-file` and TPM, screen's `source`,
readline's `$include` of anything but `/etc/inputrc`, zellij's
`layout_dir`/`theme_dir` and file plugins, oh-my-posh's `extends` of a local
file (emptied, since JSON has no comment), a shell's `source`/`.` of a file
outside `$_HI_CONFIG_DIR` (a framework theme may also source its own tree -
`$ZSH`, `$OSH`, `$BASH_IT` - see
[INTEGRATIONS.md](INTEGRATIONS.md#prompt-programs)), and every plugin manager's
bootstrap. Those are disabled on the way out, and `hi --doctor` names each, file
and line, in yellow. One naming a file of the tool's own directory -
`source-file ~/.config/tmux/theme.conf`, vim's `source ~/.vim/keys.vim` - is
carried instead: the file rides beside the member and the include reads it there
([HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan)). Two comments
on the line above one, in the file's own syntax (`# hi-allow`, or `" hi-allow`
in vim), decide that line alone:

- `hi-allow` sends it as written and silences its row - for a file you know
  every target has.
- `hi-quiet` still drops it, and silences its row - for a line you know no
  target needs, so the doctor stops saying so.

A pair of comments decides every line between them the same way, so a guarded
block takes one pair rather than a comment a line: `hi-allow-start` and
`hi-allow-end`, or `hi-quiet-start` and `hi-quiet-end`.

```vim
" hi-quiet-start
call plug#begin()
Plug 'tpope/vim-surround'
call plug#end()
" hi-quiet-end
```

A start with no end of its own below it decides nothing, and `hi --doctor`
names it; an end with no start is ignored. An allow pair inside a quiet one
keeps its lines.

There is no switch that sends them all.
[HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan) is the whole
mechanism, including what it cannot see.

## Keeping the overlay in a dotfile manager

There is no say-hi plugin for chezmoi, yadm, GNU Stow, or a bare `$HOME` repo,
and there should not be: the overlay is a **plain directory of plain files**,
so pointing your tool at `~/.config/say-hi` is the whole integration. The
first two properties below are pinned by `tests/hi/payload_test.sh`.

**Symlinks are fine, so Stow works.** hi dereferences on the way out, so a
target receives real file contents — a symlink per file, or the whole `say-hi`
directory as one link.

**Nothing but the overlay files travels.** `$_HI_OVERLAY_FILES` is an allow
list, so your manager's metadata (`.chezmoiignore`, templates), a `.git` of
your own, editor swap files, and anything private sharing that directory stay
on your machine. What a plugin of your `plugins` names rides too, since the
plugin is you asking, and the file itself stays home. The one file beside them is hi's own `wiring.sh`
([HI.62](GLOSSARY.md#hi62-generated-wiring)), written as the overlay is
packed.

**Pick one keeper for the files a manager owns.** `hi --configure` writes
`settings.sh` in the **live** directory; if your manager also owns it, the two
drift. Either let hi own `settings.sh` (exclude it from the manager), or keep
it managed and run the manager's re-add step
(`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.
Per-file managers leave what they do not own alone, so a partly-managed
directory is normal.
