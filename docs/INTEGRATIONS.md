# Integrations

hi installs and ships none of the tools below. Where a target has one, a
session wires it in the way the tool's own README wires it into an rc; where
it does not, the session goes on without it and says nothing. The switches are
rows in [SETTINGS.md](SETTINGS.md#every-setting); `_HI_DISABLE_LOCAL=1` sets
every `_HI_DISABLE_*` one on your own machine only
([On your own machine](#on-your-own-machine)).

## Contents

- [At a glance](#at-a-glance)
- [Prompt programs](#prompt-programs)
- [Shell hooks of your own](#shell-hooks-of-your-own)
- [The environment segment](#the-environment-segment)
  - [Tools that draw their own prefix](#tools-that-draw-their-own-prefix)
- [bat and eza](#bat-and-eza)
  - [Shipping your bat theme](#shipping-your-bat-theme)
  - [Shipping your eza theme](#shipping-your-eza-theme)
- [Terminal multiplexers](#terminal-multiplexers)
- [lesspipe](#lesspipe)
- [readline](#readline)
- [Shell frameworks](#shell-frameworks)
  - [On your own machine](#on-your-own-machine)
- [Which side is asked](#which-side-is-asked)
- [Config sizes](#config-sizes)

## At a glance

| tool                                                                                                                                                                                                                                                                                                                                                                                           | what hi does with it                                                                                                                                                                                           | on by default             | switch                                                                          |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------- |
| [starship](https://starship.rs), [oh-my-posh](https://ohmyposh.dev), [powerline-go](https://github.com/justjanne/powerline-go), [powerlevel10k](https://github.com/romkatv/powerlevel10k), [oh-my-zsh](https://ohmyz.sh) themes, [oh-my-bash](https://github.com/ohmybash/oh-my-bash) themes, [bash-it](https://github.com/Bash-it/bash-it) themes, [tide](https://github.com/IlanCosman/tide) | draws the prompt in hi's place, with your config from home                                                                                                                                                     | yes, where installed here | `_HI_PROMPT_TOOL` (`hi` for hi's own)                                           |
| mise, asdf, pyenv, rbenv, nodenv, nix, guix, devbox, devenv, direnv, conda, venv                                                                                                                                                                                                                                                                                                               | names the active ones in the prompt's leading `(myproj)` segment                                                                                                                                               | yes                       | `_HI_DISABLE_ENV_STATUS`                                                        |
| [bat](https://github.com/sharkdp/bat), [eza](https://github.com/eza-community/eza), exa                                                                                                                                                                                                                                                                                                        | `cat`, `bat`, and one `ls`/`eza`/`exa` alias with hi's flags, your theme from home                                                                                                                             | yes, where installed      | `_HI_DISABLE_TOOL_ALIASES`, the `_HI_*_OPTS` and `_BIN`s                        |
| tmux, zellij, screen                                                                                                                                                                                                                                                                                                                                                                           | `hi --mux` runs the connect inside one, on the client; a tmux on a target reads your `tmux.conf`                                                                                                               | no - per connect          | `--mux`, `--no-mux`; `_HI_DISABLE_TOOL_ALIASES` for the config                  |
| lesspipe                                                                                                                                                                                                                                                                                                                                                                                       | `less` opens archives and packages, as the distro's own rc sets it up                                                                                                                                          | yes, where installed      | none                                                                            |
| vim/neovim, nano, emacs, micro, [helix](https://helix-editor.com), [kakoune](https://kakoune.org)                                                                                                                                                                                                                                                                                              | opened with hi's config, or yours, through an alias - neovim reads `init.lua`, vim `vimrc`, micro your micro directory's files, helix `config.toml`, kakoune `kakrc` through `$KAKOUNE_CONFIG_DIR` on a target | yes                       | `_HI_DISABLE_EDITORS`; the files are [SETTINGS.md](SETTINGS.md)'s overlay table |
| oh-my-zsh, powerlevel10k, bash-it, fzf                                                                                                                                                                                                                                                                                                                                                         | loads after them and leaves their hooks working                                                                                                                                                                | -                         | [Shell frameworks](#shell-frameworks)                                           |

## Prompt programs

A prompt program you already use draws the prompt in hi's place, on this
machine and on every target that has it: hi keeps the header, aliases, and
editors, and hands over only the prompt line. Out of the box
`_HI_PROMPT_TOOL` is unset, which means every program installed here, in
this order - the first that fits the shell and that the target has wins:

| program       | shells          | counts as installed here                                                                                                                                                                                                          | started on a target                                                                                               | your config from home                                                                                                       |
| ------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| powerlevel10k | zsh             | your zsh rc loads the theme (`ZSH_THEME=powerlevel10k/powerlevel10k`, a source of `powerlevel10k.zsh-theme`, or a manager naming `romkatv/powerlevel10k`) _and_ `${ZDOTDIR:-~}/.p10k.zsh` (or `$POWERLEVEL9K_CONFIG_FILE`) exists | as the rc loaded it, else from `~/powerlevel10k`, oh-my-zsh's custom themes, the distro or Homebrew path          | that file, sourced after powerlevel10k                                                                                      |
| oh-my-zsh     | zsh             | `ZSH_THEME` in `${ZDOTDIR:-~}/.zshrc` names a theme file                                                                                                                                                                          | as the rc loaded it, else only the libraries themes call                                                          | the theme file, found the way oh-my-zsh finds it - so a custom theme works on a box without it                              |
| oh-my-bash    | bash            | `OSH_THEME` in `~/.bashrc` names a theme file                                                                                                                                                                                     | as the rc loaded it, else without its plugins, aliases, or completions                                            | the theme file, likewise                                                                                                    |
| bash-it       | bash            | `BASH_IT_THEME` in `~/.bashrc` names a theme file                                                                                                                                                                                 | as the rc loaded it, else `BASH_IT_THEME` pointed straight at the home theme file and the whole framework sourced | the theme file, found the way bash-it finds it                                                                              |
| tide          | fish            | its functions autoload in fish (as fisher installs it)                                                                                                                                                                            | fish loads it; hi only leaves its prompt alone                                                                    | the `tide_*` universal variables - never the rest of `fish_variables`                                                       |
| starship      | bash, zsh, fish | on `$PATH`                                                                                                                                                                                                                        | `starship init <shell>`                                                                                           | `$STARSHIP_CONFIG`, else `~/.config/starship.toml`                                                                          |
| oh-my-posh    | bash, zsh, fish | on `$PATH`                                                                                                                                                                                                                        | `oh-my-posh init <shell>`                                                                                         | `$POSH_CONFIG` (or the older `$POSH_THEME`), else the file your rc's `oh-my-posh init --config` names (json, yaml, or toml) |
| powerline-go  | bash, zsh, fish | on `$PATH`                                                                                                                                                                                                                        | once per prompt, as its README wires it, with `_HI_POWERLINE_GO_OPTS`                                             | the flags in `_HI_POWERLINE_GO_OPTS`                                                                                        |

A framework theme from home is sourced on a target only once hi has found
that framework's tree there (`$ZSH/lib/git.zsh`, `$OSH/oh-my-bash.sh`,
`$BASH_IT/bash_it.sh`), so a theme's `source "$ZSH/lib/..."` rides as
written: on a target without oh-my-zsh the theme never runs, and hi's
prompt draws instead. Only the theme gets that pass, and only for its own
framework - the same line in a `plugins.d` member or a shell rc, which run
on every target, is disabled like any include hi cannot carry (`# hi-allow`
above it keeps one you have guarded yourself). A theme that sources a
library its target's framework version lacks fails there as it would at
home.

So a powerlevel10k-in-zsh, tide-in-fish user gets both prompts on every box
that has them, and hi's where it has neither. A prompt hi has no hand-over
for stays yours rather than being drawn over: liquidprompt or bash-git-prompt
in bash; spaceship, pure, or a promptinit theme (prezto's included) in zsh;
and in fish any `fish_prompt` that is not fish's own - your `functions/`
directory's, a theme such as pure, hydro, or bobthefish, or one your config
defines. `hi` in `_HI_PROMPT_TOOL` takes the prompt anyway. Under powerlevel10k's instant
prompt, hi calls `p10k clear-instant-prompt` before drawing the header, the
call p10k provides for an rc that prints, so it does not warn about console
output on every start. The list is worked out on this
machine and handed to the target, which never looks for programs of its own -
a shared box with powerlevel10k installed does not change your prompt unless
you use it too.

`_HI_PROMPT_TOOL=hi` (the Prompt item in `hi --configure`) keeps hi's prompt
everywhere: it starts no program on any target, and takes the prompt back
from one the _target's_ own rc started, unhooking its prompt hook. Only the
name `hi` does that - an unset list, or one no entry of which fits, leaves
the target's own choice drawing. To choose, name them: `"tide starship"` is tide in fish and starship in
bash and zsh, `"tide hi"` tide in fish and hi's prompt elsewhere.
`_HI_DISABLE_PROMPT=1` beats all of it: no prompt from hi at all, its own or a
program's.

The configs from home ride the overlay - a copy in `~/.config/say-hi/` rides
in its place, which is how targets get a different one - and apply on a
target only, over whatever the target has; at home each program's own config
is already in force. Why hi hands over the prompt and nothing else, and how
each program is started, is [HI.32](GLOSSARY.md#hi32-starship-deference).

## Shell hooks of your own

hi runs no tool's shell hook for you - zoxide's and atuin's `init`, a
`direnv hook`, a `mise activate` are yours to add, in the per-shell files the
overlay carries (`~/.config/say-hi/bashrc`, `zshrc`, and `config.fish`),
which every session sources after hi's own:

```sh
# ~/.config/say-hi/bashrc
command -v zoxide >/dev/null && eval "$(zoxide init bash)"
command -v atuin >/dev/null && eval "$(atuin init bash)"
```

In `config.fish` the same line is `command -q zoxide; and zoxide init fish | source`.
Once started, a tool keeps state of its own under the target's `$HOME` -
zoxide's directory database, atuin's history - which hi neither writes nor
cleans up.

## The environment segment

The prompt's leading `(myproj)` names every environment manager that is
active, outermost first: `(mise|direnv:proj|myproj)` is mise activated, a
direnv-loaded `proj`, and a venv inside it. It reads `$MISE_SHELL`,
`$ASDF_DIR`, `$PYENV_VERSION`/`$RBENV_VERSION`/`$NODENV_VERSION`,
`$IN_NIX_SHELL`, `$GUIX_ENVIRONMENT`, `$DEVBOX_SHELL_ENABLED`,
`$DEVENV_ROOT`, `$DIRENV_DIR`, `$CONDA_DEFAULT_ENV`, and
`$VIRTUAL_ENV_PROMPT`/`$VIRTUAL_ENV` - variables the tools export, so a draw
costs no probe and no fork. mise is named only where a config file between
the directory and `~` overrides the global one, so an activated mise with
nothing but `~/.tool-versions` stays off the prompt. A `.venv` is named for
the directory holding it, not for itself. `_HI_DISABLE_ENV_STATUS=1` turns
the whole segment off. The segment is part of hi's prompt, so a
[prompt program](#prompt-programs) replaces it along with the rest.

### Tools that draw their own prefix

hi stands down for a tool already drawing its own prefix, so nothing appears
twice: a `source .venv/bin/activate` keeps its own `(myproj)` in zsh and fish,
where the shell keeps the prompt the activate script edited. bash is the
exception - hi rebuilds `$PS1` on every draw, so that prefix cannot survive
and hi draws the segment itself. A venv is named in all three shells, then, in
its own styling or hi's; direnv, nix, and the rest have no prefix of their own
and are always hi's.

To get hi's styling and naming everywhere, silence the tool's own prefix the
way the tool documents: `VIRTUAL_ENV_DISABLE_PROMPT=1` for a venv (`export` it
before you activate) and `conda config --set changeps1 false`. hi then draws
the segment in every shell - which is also how a `.venv` stops reading as
`(.venv)`. hi never sets those two for you: every other shell and prompt you
open reads them too ([HI.54](GLOSSARY.md#hi54-who-draws-the-environment-prefix)).

## bat and eza

`common/aliases.sh` builds the styled tool aliases from whatever the target
has, first installed wins:

- `cat` and `catn` run bat (Debian's `batcat`, where that is its name) with
  `_HI_BAT_OPTS` - no pager, two-space tabs, the Monokai Extended Bright theme,
  and the `changes,grid` style - and `catn` adds line numbers. Without bat,
  `cat` falls through to `ccat`, then plain `cat`, and `catn` is not defined.
- `ls`, `eza`, and `exa` are one alias under three names, running the first of
  eza, exa, and `ls` the target has (`_HI_LS_BIN`); `eza` and `exa` answer only
  where that binary is installed. The flags follow the rung that answered,
  since the three share almost no syntax: `_HI_EZA_OPTS`, `_HI_EXA_OPTS`, or a
  plain `-F -l` for coreutils `ls`. `_HI_LS_OPTS` is whichever of those the
  ladder picked, and setting it yourself wins outright.

`_HI_DISABLE_TOOL_ALIASES=1` drops the `cat`/`catn` rebind, the list alias,
and the tmux, screen, and zellij config aliases;
`bat`, `batcat`, and `batn` (where bat is installed) and a bare `ls` stay
available by name either way. No alias names a tool the target lacks: an
editor, tmux, bat, eza, or sudo that is not installed leaves its name to the
shell's own not-found.
The flags and the binary each alias runs are rows in
[Every setting](SETTINGS.md#every-setting), set in your `settings.sh`; to add
one flag to hi's instead, redefine the alias in
[your `aliases.sh`](SETTINGS.md#shells-you-drop-into-inside-a-session).

### Shipping your bat theme

Every target gets the bat config you already keep: hi ships the file bat
reads here - `$BAT_CONFIG_PATH`, else `$BAT_CONFIG_DIR/config`, else
`~/.config/bat/config` (under `$XDG_CONFIG_HOME` when set) - or, when there
is one, the `bat.conf` in `~/.config/say-hi/` instead. On a target the file becomes
`$BAT_CONFIG_PATH`, and `common/aliases.sh` leaves `--theme` out of
the default `_HI_BAT_OPTS` whenever that variable is set, so the file's theme
is the one you see through `cat`. The same rule applies at home if you export
`BAT_CONFIG_PATH` yourself; a `_HI_BAT_OPTS` of your own always wins outright.

### Shipping your eza theme

eza reads its colors from `$EZA_CONFIG_DIR/theme.yml`, and only under that
name. hi ships the one eza reads here - `$EZA_CONFIG_DIR/theme.yml`, else
`~/.config/eza/theme.yml` (under `$XDG_CONFIG_HOME` when set) - or the
`theme.yml` in `~/.config/say-hi/` when there is one. On a target,
`common/paths.sh` points `EZA_CONFIG_DIR` at the directory holding the shipped
copy; at home the variable is left alone. Like `BAT_CONFIG_PATH`, it is
exported whatever `_HI_DISABLE_TOOL_ALIASES` says, so a bare `command eza`
matches too.

## Terminal multiplexers

`hi --mux <target>` starts the connect inside a session of the first of tmux,
zellij, and screen on **your** `PATH`, named `hi-<target>`, and a second
`hi --mux <target>` joins the one already running - so a dropped link leaves
a session to reattach to, on your side. Already inside tmux, hi switches the
client to that session rather than nesting; inside screen or zellij it
opens a new window or tab. `_HI_MUX=1` (`hi --configure`'s advanced item) makes it the default
and `--no-mux` skips it once. The target sees an ordinary session: persistent
sessions on the target
were [decided against](COMPATIBILITY.md#what-would-change-an-answer), and
[HI.52](GLOSSARY.md#hi52-client-multiplexer-wrap) is how the wrap works.

A tmux you start _on_ a target reads the config you use here: `~/.tmux.conf`
(else `$XDG_CONFIG_HOME/tmux/tmux.conf`, and an overlay `tmux.conf` over
both) rides along and the session's `tmux` alias is `tmux -f` it. screen the
same, `~/.screenrc` under `screen -c`; and zellij's config directory
(`$ZELLIJ_CONFIG_DIR`, else `$XDG_CONFIG_HOME/zellij`) - `config.kdl` and
every file of `layouts/` and `themes/`, an overlay `zellij/` copy of each
name first - under the alias's `--config-dir`. A
`source-file` of another file, TPM's `@plugin` list and its `run`, screen's
`source`, zellij's `layout_dir`/`theme_dir` and `file:` plugins name
something the target does not have, so they go out disabled and
`hi --doctor` names the line.

## lesspipe

Where a target has `/usr/bin/lesspipe` (Debian and Ubuntu ship it) and
`$LESSOPEN` is not already set, bash and zsh sessions `eval` it, so `less`
opens archives, packages, and compressed files the way the distro's own
`~/.bashrc` sets it up. A nested shell inherits the exported `$LESSOPEN` and
skips it. In the same spirit, a chroot's `/etc/debian_chroot` leads the
prompt: `(name)` in bash and zsh, `(chroot:name)` in fish.

## readline

Every target gets the inputrc you already keep: hi ships the file readline
reads here - `$INPUTRC`, else `~/.inputrc` - or the `inputrc` in
`~/.config/say-hi/` when there is one. On a target, `common/paths.sh` points
`INPUTRC` at the shipped copy, so bash's line editing and every readline
program started from the session take your bindings; zsh and fish have line
editors of their own and ignore it. At home the variable is left alone.
Nothing is asked about first: readline is a library, not a command on `PATH`.

A set `INPUTRC` replaces `/etc/inputrc` rather than adding to it, so an
inputrc that relies on the system one says `$include /etc/inputrc`, which
rides as written. An `$include` of any other file is dropped on the way out
([SETTINGS.md](SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).

## Shell frameworks

A framework on a target loads normally. hi lands you in your own login shell
when hi styles it, else the best of `fish zsh bash` the target has, and hi's
setup runs after that shell's own rc - so hi is the one positioned to break a
framework, and the one tested for it. `tests/targets/framework_test.sh`
installs twelve per their own READMEs - oh-my-zsh, powerlevel10k, starship,
bash-it, oh-my-bash, tide, powerline-go, fzf, zoxide, direnv, atuin, and
mise - plus a tmux under a `~/.tmux.conf` of the target's own, connects for
real, and asserts no shell errors and each one's hook, Ctrl-R binding, array
base, or prompt intact; the prompt programs are handed the prompt with a
marker config from home, and tmux must read the client's config over the
target's.

### On your own machine

A prompt program your rc loads keeps drawing here without asking
([Prompt programs](#prompt-programs)). `_HI_DISABLE_LOCAL=1` goes further:
every `_HI_DISABLE_*` switch on, so everything on this page stays as your own
rc set it up on this machine, while every target still gets hi's. How hi
tells home from a target is [SETTINGS.md's _Others_](SETTINGS.md#others).

## Which side is asked

Two machines could answer "is this tool installed", and hi asks each about a
different thing:

- **The client, about what rides.** A config from home - your `~/.vimrc`,
  `~/.tmux.conf`, micro's directory, bat's and eza's files - is "the one in
  force here" only with its tool here to read it, so it ships only then:
  `vimrc` with vim, `init.lua` with nvim, `config.toml` with hx, `kakrc` with
  kak, `nanorc` with
  nano, `init.el` with emacs, `tmux.conf` with tmux, `screenrc` with screen,
  `micro/` with micro, `zellij/` with zellij,
  `bat.conf` with bat (or `batcat`), `theme.yml` with eza; `inputrc` always,
  since readline is a library, not a command. A dotfile left
  behind by a tool you removed neither ships nor gets a `hi --doctor` row.
  It is the client because only the client can be asked before a connect, which
  is when the overlay is packed - the reason the
  [prompt programs](#prompt-programs) are a list worked out here too.
- **Nobody, about an overlay copy.** A file you put in `~/.config/say-hi/` is
  you saying "targets get this", and it rides whatever this machine has -
  the way to carry a `vimrc` from a laptop that only has neovim.
- **The target, about what is used.** `common/aliases.sh` builds each alias
  from what the target has, and only with its config there, so a config
  that rode to a box without its tool is a few idle bytes, and a tool whose
  config stayed home keeps its own - never an alias to a missing binary or
  file.

## Config sizes

> **Theoretical.** None of these rows is a measurement of a real user's setup
> or a promise about a connect: each pairs a plausible configuration with the
> size of public sample files like it, run through hi's comment strip and
> `gzip -9n` by hand. Real configs vary widely; `hi --doctor` and the size hi
> prints on connect are the numbers for yours.

Everything in the overlay rides every connect beside the payload (README's badge measures it), so
what a heavy config costs on the wire is the gzipped size after hi strips
comments and blank lines
([HI.35](GLOSSARY.md#hi35-payload-comment-and-whitespace-strip)). Prose-heavy
files shrink the most:
powerlevel10k's wizard output is three-quarters comments.

| user                                                        | what rides the overlay                            | on disk  | stripped | on the wire (gzip) |
| ----------------------------------------------------------- | ------------------------------------------------- | -------- | -------- | ------------------ |
| defaults, nothing configured                                | nothing                                           | 0        | 0        | 0                  |
| a few settings and aliases                                  | `settings.sh`, `aliases.sh`                       | ~2 KB    | ~1 KB    | ~0.5 KB            |
| starship with a preset                                      | `starship.toml` (the nerd-font-symbols preset)    | ~3.4 KB  | ~3.4 KB  | ~1.4 KB            |
| oh-my-posh with a stock theme                               | `oh-my-posh.json` (jandedobbeleer)                | ~7 KB    | ~7 KB    | ~1.4 KB            |
| oh-my-zsh, robbyrussell                                     | `oh-my-zsh.zsh-theme`                             | ~0.4 KB  | ~0.4 KB  | ~0.2 KB            |
| oh-my-zsh, agnoster                                         | `oh-my-zsh.zsh-theme`                             | ~13 KB   | ~8 KB    | ~2.5 KB            |
| oh-my-bash, font or agnoster                                | `oh-my-bash.theme.sh`                             | 2-20 KB  | 1-9 KB   | 0.5-2.6 KB         |
| tide, configured by its wizard                              | `tide.vars` (its ~160 variables)                  | ~6 KB    | ~6 KB    | ~1.5 KB            |
| powerlevel10k from its wizard                               | `p10k.zsh` (lean or rainbow)                      | 90-95 KB | 24-28 KB | ~5.5 KB            |
| a tuned vim                                                 | `vimrc` (like amix/vimrc's basic.vim)             | ~9.5 KB  | ~4 KB    | ~1.8 KB            |
| a neovim starter config                                     | `init.lua` (like kickstart.nvim, single file)     | ~44 KB   | ~19 KB   | ~6 KB              |
| a long-lived bash setup                                     | `bashrc`, `aliases.sh`, a few `plugins.d` members | 10-30 KB | 5-15 KB  | 2-6 KB             |
| all of it: powerlevel10k, tide, neovim, vim, bash, starship | everything above that ships at once               | ~200 KB  | ~75 KB   | ~20 KB             |

A neovim config spread over many files under `~/.config/nvim/lua/` does not
ride at all - only `init.lua` does - so its size here is the single file.
