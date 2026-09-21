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
  - [Plugins](#plugins)
- [The editor rcs come from where you keep them](#the-editor-rcs-come-from-where-you-keep-them)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)

## The wizard

`hi --configure` opens on a preview — the header and the prompt line as they
would draw at your current settings — over one numbered list of every setting
it asks, under four headings, with no submenus - the header's own items first, right under the header they change:

- **Header** — first, under the rendered header it edits: everything in [Header details](#header-details): the banner,
  the header's items in the order they print (`up N`/`down N` moves one), the
  width, the package check's depth, and the hidden addresses. Outside the
  menu, `hi --preview header` prints the header at the saved settings, and
  `hi --preview packages` the check's legend.
- **Features** — the `_HI_DISABLE_*` toggles in [Every setting](#every-setting),
  but the prompt's own, which sits under _Prompt_.
- **Prompt** — the colored prompt on or off, hi's own over the prompt
  programs found here, and the character each of the three shells' prompts
  ends with, wired up on this machine or not.
- **Advanced** — the leading space, the `--mux` default, and 24-bit color.

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

| preset       | what it answers                                                                                                                              |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | every feature and every header item on — the shipped defaults                                                                                |
| `balanced`   | everything but the noise: a shorter package check (`_HI_PACKAGES_MIN_PRIORITY=3`)                                                            |
| `minimal`    | on targets only the colored prompt and the aliases: no header, git status, or editors — and nothing on this machine (`_HI_DISABLE_LOCAL=1`). |

A preset is an absolute answer over the feature toggles, the banner, and the
package check's depth: what it names is set and the rest of those return to
their defaults. Everything else — the header order, the width, the hidden
addresses, the colors, the prompt program and separators, the advanced
settings — keeps what it holds. From the menu its answers are only what the
preview shows until `[s]` saves them. The rows are `scripts/configure.sh`'s
`_HI_PRESETS`.

## The overlay

Every file hi reads from `~/.config/say-hi/`, and the shipped file each
one overrides. Each resolves in one order: the copy here, else your own file
where its tool keeps it on this machine
([below](#the-editor-rcs-come-from-where-you-keep-them)), else the shipped
default. A shell's own rc - `bashrc`, `zshrc`, `config.fish` - has no middle
step: it rides only from here, never found at home
([HI.61](GLOSSARY.md#hi61-one-overlay-priority)).

| overlay file                       | overrides            | what it is                                                                                                                                                                                                                     |
| ---------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `~/.config/say-hi/settings.sh`     | -                    | what `hi --configure` writes; no in-tree counterpart                                                                                                                                                                           |
| `~/.config/say-hi/colors`          | `config/colors`      | your color pins                                                                                                                                                                                                                |
| `~/.config/say-hi/packages`        | `config/packages`    | what the package check looks for; `hi --add-package` copies the tree's in before its first write ([COLORS.md](COLORS.md#the-package-checks-rows))                                                                              |
| `~/.config/say-hi/vimrc`           | `config/vimrc`       | your vim config for the `vim` alias and `$VIMINIT`, replacing hi's default wholesale; only needed when it should differ from your `~/.vimrc`, which hi carries anyway ([below](#the-editor-rcs-come-from-where-you-keep-them)) |
| `~/.config/say-hi/init.lua`        | `config/init.lua`    | the same for neovim - the `nvim` alias, and `vim` where a target has nvim - over your `~/.config/nvim/init.lua`                                                                                                                |
| `~/.config/say-hi/config.toml`     | `config/config.toml` | the same for the `hx` alias (`-c`), over your `~/.config/helix/config.toml`                                                                                                                                                    |
| `~/.config/say-hi/nanorc`          | `config/nanorc`      | the same for the `nano` alias, over your `~/.nanorc`                                                                                                                                                                           |
| `~/.config/say-hi/init.el`         | `config/init.el`     | the same for the `emacs` alias (`emacs -q -l`), over your `~/.emacs`                                                                                                                                                           |
| `~/.config/say-hi/tmux.conf`       | -                    | the same for the `tmux` alias (`tmux -f`), over your `~/.tmux.conf`; with neither, `tmux` is left alone                                                                                                                        |
| `~/.config/say-hi/screenrc`        | -                    | the same for the `screen` alias (`screen -c`), over your `~/.screenrc`                                                                                                                                                         |
| `~/.config/say-hi/zellij/`         | -                    | zellij's `config.kdl`, `layouts/`, and `themes/`, each file over the one in your zellij config directory; the `zellij` alias sets `$ZELLIJ_CONFIG_DIR` to it                                                                   |
| `~/.config/say-hi/micro/`          | -                    | micro's `settings.json`, `bindings.json`, and `init.lua`, each over the one in your micro config directory; the `micro` alias's `-config-dir` names it                                                                         |
| `~/.config/say-hi/aliases.sh`      | -                    | your own aliases, sourced **last** so they replace hi's of the same name - same POSIX+fish subset; see [below](#shells-you-drop-into-inside-a-session)                                                                         |
| `~/.config/say-hi/plugins.d/`      | -                    | drop-in plugins in the same subset, sourced after the aliases in name order; see [below](#plugins)                                                                                                                             |
| `~/.config/say-hi/bashrc`          | -                    | your bash preferences, sourced at the end of `common/bash.sh` - history sizing, `shopt`s, readline bindings - or a copy or symlink of your whole `~/.bashrc` ([below](#shells-you-drop-into-inside-a-session))                 |
| `~/.config/say-hi/zshrc`           | -                    | the same for zsh - history, keybindings, `zstyle` completion rules                                                                                                                                                             |
| `~/.config/say-hi/config.fish`     | -                    | the same for fish - keybindings and the `fish_color_*` / `fish_pager_color_*` palette                                                                                                                                          |
| `~/.config/say-hi/oh-my-posh.json` | -                    | your oh-my-posh config (or `.yaml` / `.toml`), `$POSH_CONFIG` on every target that hands the prompt to oh-my-posh; over the one `$POSH_CONFIG` or your rc's `oh-my-posh init --config` names                                   |

starship's, powerlevel10k's, tide's, bat's, and eza's own configs, and your
oh-my-zsh, oh-my-bash, and bash-it themes, need no copy here: every target
gets the one each tool reads on your machine
([Integrations](INTEGRATIONS.md#prompt-programs)). A `starship.toml`,
`p10k.zsh`, `oh-my-zsh.zsh-theme`, `oh-my-bash.theme.sh`, `bash-it.theme.bash`,
`tide.vars`, `bat.conf`, or
`theme.yml` in `~/.config/say-hi/` is the override: targets get it instead,
and at home the tool keeps reading its own. A prompt program's copy rides only
when that program is one a target is handed, and `hi --doctor` says when it is
not.

The overlay starts empty: `hi --install` writes `settings.sh` and nothing
else. To override `colors`, copy the shipped file in and edit the copy:

```sh
mkdir -p ~/.config/say-hi
cp "$_HI_ROOT/config/colors" ~/.config/say-hi/colors
```

`hi --add-package bat:3,batcat:3` does that copy for the package check, then
adds the row.

A copy stops tracking what `hi --update` delivers for that file; delete it to
track the tree's again, and `hi --doctor` names which of the two is in force.
Before 1.0 seven members were renamed to what their tool calls the file
(`vim.rc` to `vimrc`, `nano.rc` to `nanorc`, `emacs.el` to `init.el`,
`bash.sh` to `bashrc`, `zsh.zsh` to `zshrc`, and the two framework themes to
`oh-my-zsh.zsh-theme` and `oh-my-bash.theme.sh`); a file still under an old
name is not read, and `hi --doctor` names it with the `mv` that fixes it.
Versioning the directory is yours to do — a `git init` there, or
[a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager).

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

The whole vocabulary a `settings.sh` may use, grouped the way the wizard's
menu is - _Header_, _Features_, _Prompt_, _Advanced_ - and then the
settings nothing asks about; the linked sections explain. The **set by** column:

- **you** — supported surface nothing asks about: export it, or write an
  `export` line into `settings.sh` by hand. The wizard carries such a line
  over, never drops it.
- **`hi --configure`** — the same, with a menu item attached. **advanced**
  marks the items under the menu's _Advanced_ heading.

The lint group derives the roster from the tree (`common/core.sh`'s
`_HI_TOGGLES`, the wizard's tables, the aliases' `_OPTS`/`_BIN` names), so a
new setting cannot land without a row here. A value written by hand that the
code would silently fall back from - a width under 40, a header word or
prompt program hi does not know, an editor off the ladder - is a red
`hi --doctor` row, judged by the same rules the wizard takes an answer by.

| variable                    | default                                                                                                   | set by                    | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| --------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_BANNER`        | `0`                                                                                                       | `hi --configure`          | hides the `~~~ Connected ~~~` line ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_DISABLE_GREETING`      | `0`                                                                                                       | `hi --configure`          | hides the `hi loaded with...` line and its init/copy/load timers; not part of the header, so `_HI_DISABLE_HEADER` leaves it alone ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_HEADER_ORDER`          | the table in [Header details](#header-details)                                                            | `hi --configure`          | which header items show, in what order; empty is the default list                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_MAX_WIDTH`             | `80`                                                                                                      | `hi --configure`          | terminal columns the header and banner are drawn to, narrowed to a smaller real terminal; 40 is the least the wizard takes                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_PACKAGES_MIN_PRIORITY` | `2`                                                                                                       | `hi --configure`          | the lowest `config/packages` priority (0-3) the header's check prints, and the main dial on its length: `2` keeps useful tools and up, `1` adds optional extras, `0` prints everything, `3` just favorites and core alerts; drop `check` from `_HI_HEADER_ORDER` to turn it off. `hi --preview packages` marks the ranks it silences `below floor`                                                                                                                                                                                              |
| `_HI_IP_HIDE`               | `172.*`                                                                                                   | `hi --configure`          | globs the header's `ip` cell drops; `none` hides nothing ([Header details](#header-details))                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_HI_DISABLE_HEADER`        | `0`                                                                                                       | `hi --configure`          | turns off the whole header: a connect's, a disconnect's, and the greeting a local interactive shell prints                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_DISABLE_GIT_STATUS`    | `0`                                                                                                       | `hi --configure`          | turns off the git segment in the prompt                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_DISABLE_ENV_STATUS`    | `0`                                                                                                       | `hi --configure`          | turns off the prompt's environment segment - the leading `(myproj)` naming the active venv, conda, direnv, nix, guix, devbox, or version-manager environment. See [Integrations](INTEGRATIONS.md#the-environment-segment)                                                                                                                                                                                                                                                                                                                       |
| `_HI_DISABLE_EDITORS`       | `0`                                                                                                       | `hi --configure`          | turns off the editor config overrides (vim, neovim, nano, emacs, micro, helix) and, on a target, the `$EDITOR`/`$VISUAL`/`$SUDO_EDITOR` export that carries them into `git commit`, `crontab -e`, and `sudo -e`; tmux's `-f` override is a tool alias, under `_HI_DISABLE_TOOL_ALIASES`                                                                                                                                                                                                                                                         |
| `_HI_DISABLE_VIM`           | `0`                                                                                                       | `hi --configure`          | turns off hi's vim config alone - the `vim` and `nvim` aliases (`vimrc` for vim, `init.lua` for neovim) and `$VIMINIT`; `$EDITOR` can still pick it, bare                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_DISABLE_NANO`          | `0`                                                                                                       | `hi --configure`          | the same for nano's alias                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_DISABLE_EMACS`         | `0`                                                                                                       | `hi --configure`          | the same for emacs's alias                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_DISABLE_MICRO`         | `0`                                                                                                       | `hi --configure`          | the same for micro's alias, with its `_HI_MICRO_OPTS` flags and `-config-dir`                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_DISABLE_HELIX`         | `0`                                                                                                       | `hi --configure`          | the same for `hx`'s alias - hi's `config.toml`, `-c`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_DISABLE_TOOL_ALIASES`  | `0`                                                                                                       | `hi --configure`          | turns off the styled tool aliases: `cat`/`catn` as `bat`, `ls`/`exa`/`eza` through the list ladder, and `tmux -f` your tmux config; `bat`/`batn` keep their flags either way. See [Integrations](INTEGRATIONS.md#bat-and-eza)                                                                                                                                                                                                                                                                                                                   |
| `_HI_DISABLE_SUDO_ALIAS`    | `0`                                                                                                       | `hi --configure`          | turns off the `sudo` alias - the trailing-space alias in bash/zsh that lets `sudo vim` keep the vim alias's flags, and fish's wrapper function that does the same for its alias functions                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_DISABLE_LOCAL`         | `0`                                                                                                       | `hi --configure`          | turns off everything above, and the banner, **on this machine only** - hi still styles the hosts you visit ([Others](#others))                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_DISABLE_PROMPT`        | `0`                                                                                                       | `hi --configure`          | turns off the colored `user@host` prompt, leaving your shell's own                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `_HI_PROMPT_TOOL`           | unset                                                                                                     | `hi --configure`          | who draws the prompt: a space-separated list of `powerlevel10k`, `oh-my-zsh`, `oh-my-bash`, `bash-it`, `tide`, `starship`, `oh-my-posh`, `powerline-go`, and `hi` (hi's own), each shell taking the first entry that fits it and that the target has. Unset is every program installed on this machine, frameworks first, so a prompt you already use follows you; `hi` (the menu's switch) keeps hi's prompt everywhere. hi keeps its header and aliases either way, and installs nothing. See [Integrations](INTEGRATIONS.md#prompt-programs) |
| `_HI_PROMPT_END_BASH`       | `\$`                                                                                                      | `hi --configure`          | bash's prompt separator (`\$` is bash's escape for "`$`, or `#` for root"); also the plain `sh` prompt hi bakes on the client for a bash-less target                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_PROMPT_END_ZSH`        | `>`                                                                                                       | `hi --configure`          | zsh's prompt separator - zsh prompt escapes work, so `%#` behaves as anywhere else in `PS1`                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `_HI_PROMPT_END_FISH`       | `\|`                                                                                                      | `hi --configure`          | fish's prompt separator; unset, root gets `#` in its place, and a value you set is used for root too                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_DISABLE_LEAD_SPACE`    | `0`                                                                                                       | `hi --configure` advanced | `1` drops the leading space before the prompt's `user@host`, the git segment, the banner line, and the first cell of every header row                                                                                                                                                                                                                                                                                                                                                                                                           |
| `_HI_DISABLE_RIGHT_EDGE`    | `0`                                                                                                       | `hi --configure` advanced | `1` drops the closing \| from every header row, so a row ends at its last cell instead of at the banner's column                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_HI_MUX`                   | `0`                                                                                                       | `hi --configure` advanced | `1` makes every connect a `--mux` one, in a local tmux, zellij, or screen session; `--no-mux` overrides it for one connect                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_TRUECOLOR`             | by terminal                                                                                               | `hi --configure` advanced | `1`/`0` forces or refuses 24-bit color; unset, the client decides ([Colors](COLORS.md))                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `_HI_EDITOR`                | unset                                                                                                     | you                       | the editor a target session exports as `$EDITOR`, `$VISUAL`, and `$SUDO_EDITOR`, by command name (`nvim`, `micro`, ...); used when the target has it, else the first of `nvim vim micro hx nano emacs` it does have, with hi's config flags so `git commit` and `sudo -e` get the editor the alias gives you                                                                                                                                                                                                                                    |
| `_HI_PACKAGES_PALETTE`      | unset                                                                                                     | you                       | the color the check paints each priority in: eight color names, four installed then four missing. Unset, or anything but eight names, is the shipped ramp (`cyan green brcyan brgreen blue magenta bryellow brred`). See [The package check's ramp](COLORS.md#the-package-checks-ramp)                                                                                                                                                                                                                                                          |
| `_HI_COLOR_SCHEME`          | unset                                                                                                     | you                       | what the palette names render as on a terminal that reports 24-bit color: twenty-four or forty-eight six-digit hex words. Unset is the terminal's own sixteen colors. See [Colors](COLORS.md)                                                                                                                                                                                                                                                                                                                                                   |
| `_HI_POWERLINE_GO_OPTS`     | unset                                                                                                     | you                       | extra flags for [powerline-go](https://github.com/justjanne/powerline-go) when it draws the prompt, word-split (`-modules venv,cwd,git -mode flat`)                                                                                                                                                                                                                                                                                                                                                                                             |
| `_HI_SYMBOL_SSH`            | `»` (`>` in ASCII)                                                                                        | you                       | the symbol an ssh host carries in `hi <TAB>`'s list - fish's description column, beside the name when bash 4+ lists matches, zsh's display. Any text; an empty value counts as unset                                                                                                                                                                                                                                                                                                                                                            |
| `_HI_SYMBOL_CONTAINER`      | `▣` (`#`)                                                                                                 | you                       | the same for a docker, podman, nerdctl, or finch container                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_HI_SYMBOL_NOMAD`          | `◆` (`*`)                                                                                                 | you                       | the same for a nomad allocation                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `_HI_SYMBOL_KUBE`           | `⎈` (`@`)                                                                                                 | you                       | the same for a kubernetes pod                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `NO_COLOR`                  | unset                                                                                                     | you                       | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything without color, shipped to the target next to [`_HI_ASCII`](#not-settings)                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_LS_OPTS`               | the rung's own flags below, else `-F -l`                                                                  | you                       | the flags the `ls`/`eza`/`exa` alias runs with - set it and it is the whole answer, whichever binary the ladder picked                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `_HI_EZA_OPTS`              | `-F -1 -l -m --group-directories-first --smart-group` + a time format                                     | you                       | what `_HI_LS_OPTS` defaults to when eza is the rung that answered                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_EXA_OPTS`              | the same leading flags + `--group --no-filesize`                                                          | you                       | the same for exa, whose column set its successor dropped                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_BAT_OPTS`              | `-P --tabs 2`, the Monokai Extended Bright theme (none under an overlay `bat.conf`), `changes,grid` style | you                       | the flags the `bat`/`batn` aliases attach                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `_HI_MICRO_OPTS`            | `-backup false -savehistory false -mkparents true -diffgutter true`                                       | you                       | the `micro` alias's flags - any micro setting works as `-name value`; with an overlay `micro/` the default is the first two alone, so its `settings.json` wins                                                                                                                                                                                                                                                                                                                                                                                  |
| `_HI_CAT_BIN`               | first of `bat`, `batcat`, `ccat`, `cat` on PATH                                                           | you                       | which binary the `bat` and `cat` aliases run (Debian ships bat as `batcat`; the tail keeps `cat` working where none is installed)                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_HI_BAT_BIN`               | first of `bat`, `batcat` on PATH                                                                          | you                       | the bat-only tier behind it, what parses `_HI_BAT_OPTS` - two rungs shorter on purpose; set with it, or leave both alone                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_HI_LS_BIN`                | first of `eza`, `exa`, `ls` on PATH                                                                       | you                       | which binary the `ls`, `eza`, and `exa` aliases all run - one ladder, and `_HI_LS_OPTS` follows the rung it answered with                                                                                                                                                                                                                                                                                                                                                                                                                       |

### Not settings

More names look like settings and are not:

- `$_HI_CONFIG_DIR` and `$_HI_HOME` (the **parent** of your `say-hi`
  directory) are read **before** `settings.sh` is sourced, so a line there is
  too late: export them, as `hi.sh` and `install.sh`'s rc line do. Unset, each
  entry point derives `$_HI_HOME` from its own path. `$_HI_XDG_CONFIG` is the
  `$XDG_CONFIG_HOME`-or-`~/.config` base resolved beside them — set
  `$XDG_CONFIG_HOME` instead.
- `$_HI_ROOT`, `$_HI_SSH_CONFIG` (where ssh hosts and their `# Tags:` comments
  are read from), `$_HI_COLORS`, `$_HI_PACKAGES`,
  `$_HI_VIMRC`, `$_HI_NVIMRC`, `$_HI_HELIXRC`, `$_HI_NANORC`, `$_HI_EMACSRC`,
  `$_HI_TMUX_CONF`, `$_HI_SCREENRC`, `$_HI_MICRO_DIR`, and `$_HI_ZELLIJ_DIR`
  are re-derived by `common/paths.sh`
  on every source, from `$_HI_HOME`, `$HOME`, and the overlay, so an exported
  value does not survive: put your file in the overlay.
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
- `$_HI_TARGET_COLOR` and `$_HI_TARGET_TAG` (the color and `# Tags:` value
  the target resolved to) and `$_HI_LOCAL_USER`/`$_HI_LOCAL_HOSTNAME` (the
  header's "from" half) are set from the client;
  `$_HI_HOST_COLOR`/`$_HI_USER_COLOR`/`$_HI_HOST_ESC`/`$_HI_USER_ESC` are the
  resolved prompt colors, for
  [your own prompt](COLORS.md#using-the-hash-in-your-own-prompt) to read. Setting one
  by hand tells the shell something untrue about where it is.

Everything else beginning `_HI_` is internal state, named that way to stay
out of your namespace.

## Header details

`_HI_DISABLE_BANNER=1` hides the `~~~ Connected [host] ~~~` line, on connect
_and_ disconnect; it always leads, so it takes a switch rather than a place in
the order below. `_HI_DISABLE_HEADER=1` turns off everything in this section
without erasing it: `hi --configure` keeps a stored order while the header is
off. The wizard's _Header_ items edit all of it under the rendered header
([The wizard](#the-wizard)). The `hi loaded with...` line and its
init/copy/load timers are not part of this section - they survive
`_HI_DISABLE_HEADER` and answer to `_HI_DISABLE_GREETING` of their own.

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

A word left out is not printed, and an unknown word is ignored.
`containers`/`jobs`/`pods` render only when their backend answers; listing
them decides whether hi asks at all. Each word has a fixed color, swapped for
an alternate when it would repeat the cell before it, so no order puts two
same-colored cells side by side
([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)). Unset or empty is the
table's order: `utc version localtime os arch cores cpu ram ip gitid
containers jobs pods auth pub uptime check`.

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
connect to"; a session is told apart by
[`$_HI_REMOTE_SESSION`](#not-settings). A prompt or shell framework of your
own on this machine is
[Integrations' _On your own machine_](INTEGRATIONS.md#on-your-own-machine),
and what hi writes there outside `~/.config/say-hi/` is
[FILES.md](FILES.md#what-hi-creates-on-this-machine).

Every styled hi prompt (not the bash-less `sh` one) emits
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
marks where each prompt, command, and output begins, and OSC 7 with the
working directory, for terminals that read them — kitty, WezTerm, ghostty,
foot, iTerm2, Konsole; the rest drop them. `load.sh` sends the closing
"command finished" mark a session's `exit` never gets to — without it Konsole
sends ↑ as ← until the next prompt — and a session that ends any other way
gets it from the client, with a reset of the terminal modes a remote program
may have left on ([HI.53](GLOSSARY.md#hi53-terminal-reset-after-a-failed-session)).

### Shells you drop into inside a session

A `bash`, `zsh`, `fish`, or `dash` started _inside_ a session keeps hi's
aliases, prompt, and paths, with nothing written to the target. `load.sh`
writes one rc per shell into a scratch directory, `$_HI_SESSION_RC`: zsh finds
its rc through `$ZDOTDIR` and sh/dash/ash through `$ENV`, both exported, so
however the shell is started; bash and fish have no such variable (bash's
`$BASH_ENV` covers only _non_-interactive shells), so `config/aliases.sh`
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
rules, or fish palette; each rc carries the prompt, the completions, and the
git segment. Shell code of your own goes in one of three overlay files, which
differ in dialect, in when they load, and in whether an `export` there reaches
programs started from the shell ([HI.47](GLOSSARY.md#hi47-what-a-child-inherits)):

| file                             | dialect                                                        | sourced                                                 | an `export` reaches children |
| -------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------- | ---------------------------- |
| `aliases.sh`                     | the POSIX+fish subset: `export`, `alias`, `&&` chains, no `if` | after hi's aliases, before the prompt is built          | no                           |
| `plugins.d/<name>`               | the same subset                                                | after `aliases.sh`, in name order ([Plugins](#plugins)) | no                           |
| `bashrc`, `zshrc`, `config.fish` | that shell's own, in full                                      | last, at the end of hi's rc for that shell              | yes                          |

The per-shell file is sourced at the end of hi's, in the same dialect, and
wins - `HISTFILE` included; hi sets none. At home it may source your own `~/.bashrc` or
`~/.zshrc`: re-entered while it loads, hi's rc returns at once
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
read a file the target will not have - a second rc beside it, a plugin
manager's bootstrap - are disabled on the way out and named by `hi --doctor`;
a `# hi-allow` comment above one sends it as written (`# hi-quiet` drops it
without the row), and the file rides
comment-stripped, so a long rc costs a few KB on the wire
([Integrations](INTEGRATIONS.md#config-sizes)). Your `aliases.sh` likewise
loads **after** `config/aliases.sh`, so an `alias` there replaces hi's of
the same name, and can build on hi's flags rather than restate them:

```sh
alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"      # hi's flags, plus one
alias cat=cat                                    # this one alias back to plain
```

The `_HI_*_OPTS`, `_HI_*_BIN`, and `_HI_DISABLE_*` values hi's aliases are
built from go in `settings.sh`, which loads first; set in `aliases.sh` they
arrive too late, and `hi --doctor` flags them.

Keep your aliases in `~/.aliases` already? With no `aliases.sh` in the
overlay, that file is what rides to targets, where it loads in the same place
and keeps to the same subset bash, zsh, and fish all parse. At home your own
rc goes on sourcing it; hi does not source it again.

### Plugins

Something hi does not do - another tool's init, a prompt segment of your own -
goes in a file of its own under `~/.config/say-hi/plugins.d/`, and rides to
every target with the rest of the overlay. A plugin uses the same subset as
`aliases.sh` (`export`, `alias`, `&&` chains, no `if`/`fi`), so bash, zsh, and
fish all read the one file. Plugins load right after the aliases and before
the prompt is built, in name order (`10-` before `20-`). One a shell cannot
parse is skipped in that shell with a yellow line saying so, and
`hi --doctor` lists what loads and flags what does not parse.

A plugin talks to hi through hook variables. `_HI_SEGMENT` is a command hi
runs on every prompt it draws, showing its output, if any, after the
environment prefix:

```sh
command -v kubectl >/dev/null 2>&1 &&
  export _HI_SEGMENT='kubectl config current-context'
```

The command runs in the session's own shell before every prompt, so keep it
to syntax all three share, and fast. Each plugin sets its own; hi collects
them in load order. The whole contract is
[HI.59](GLOSSARY.md#hi59-plugins).

## The editor rcs come from where you keep them

The editor, tmux, screen, micro, and zellij rows of the overlay usually need
no file: hi carries the config each tool **already reads on this machine**,
so there is one copy to edit:

| member          | hi looks at                                                                                                         |
| --------------- | ------------------------------------------------------------------------------------------------------------------- |
| `vimrc`         | `~/.vimrc`, else `~/.vim/vimrc`, else `$XDG_CONFIG_HOME/vim/vimrc`                                                  |
| `init.lua`      | `$XDG_CONFIG_HOME/nvim/init.lua`                                                                                    |
| `config.toml`   | `$XDG_CONFIG_HOME/helix/config.toml`                                                                                |
| `nanorc`        | `~/.nanorc`, else `$XDG_CONFIG_HOME/nano/nanorc`                                                                    |
| `init.el`       | `~/.emacs.el`, else `~/.emacs`, else `~/.emacs.d/init.el`, else `$XDG_CONFIG_HOME/emacs/init.el`                    |
| `tmux.conf`     | `~/.tmux.conf`, else `$XDG_CONFIG_HOME/tmux/tmux.conf`                                                              |
| `screenrc`      | `~/.screenrc`                                                                                                       |
| `micro/<file>`  | `${MICRO_CONFIG_HOME:-$XDG_CONFIG_HOME/micro}/<file>`, for `settings.json`, `bindings.json`, and `init.lua`         |
| `zellij/<file>` | `${ZELLIJ_CONFIG_DIR:-$XDG_CONFIG_HOME/zellij}/<file>`, for `config.kdl` and every file of `layouts/` and `themes/` |

An overlay copy still wins — that is how you give hi's sessions an editor
config that differs from your local one — and hi's shipped default applies
when neither is there; a home config, and hi's default with it, rides only
with its tool installed here. On a target the lookup is off: `$HOME` there is the
target's, and the file your client picked has already arrived.

Your own config is written for a machine with your plugins on it, and a target
has none. So hi reads each of these files — and the overlay's `settings.sh`,
`aliases.sh`, `plugins.d/` members, per-shell rc files, and the prompt configs
it carries — for lines naming something it cannot carry: vim's `source`,
lua's `require`/`dofile` (and micro's `AddRuntimeFile`), nano's `include`,
elisp's `load`, tmux's `source-file` and TPM, screen's `source`, zellij's
`layout_dir`/`theme_dir` and file plugins, oh-my-posh's `extends` of a
local file (emptied, since JSON has no comment), a shell's `source`/`.` of a
file outside `$_HI_CONFIG_DIR` (a framework theme may also source its own
tree - `$ZSH`, `$OSH`, `$BASH_IT` - see
[INTEGRATIONS.md](INTEGRATIONS.md#prompt-programs)), and every plugin
manager's bootstrap. Those are disabled on the way out, and
`hi --doctor` names each, file and line, in yellow. Two comments on the line
above one, in the file's own syntax (`# hi-allow`, or `" hi-allow` in vim),
decide that line alone:

- `hi-allow` sends it as written and silences its row - for a file you know
  every target has.
- `hi-quiet` still drops it, and silences its row - for a line you know no
  target needs, so the doctor stops saying so.

There is no switch that sends them all.
[HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan) is the whole mechanism,
including what it cannot see.

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
on your machine.

**Pick one keeper for the files a manager owns.** `hi --configure` writes
`settings.sh` in the **live** directory; if your manager also owns it, the two
drift. Either let hi own `settings.sh` (exclude it from the manager), or keep
it managed and run the manager's re-add step
(`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.
Per-file managers leave what they do not own alone, so a partly-managed
directory is normal.
