# Integrations

hi installs and ships none of the tools below. Where a target has one, a
session wires it in the way the tool's own README does; where it does not,
the session goes on without it. The switches are rows in
[SETTINGS.md](SETTINGS.md#every-setting). `_HI_DISABLE_LOCAL=1` leaves all of
this alone on your own machine ([On your own machine](#on-your-own-machine)).

## Contents

- [At a glance](#at-a-glance)
- [Prompt programs](#prompt-programs)
- [Shell hooks of your own](#shell-hooks-of-your-own)
- [Header cells of your own](#header-cells-of-your-own)
- [The environment segment](#the-environment-segment)
  - [Tools that draw their own prefix](#tools-that-draw-their-own-prefix)
- [bat and eza](#bat-and-eza)
  - [Shipping your bat theme](#shipping-your-bat-theme)
  - [Shipping your eza theme](#shipping-your-eza-theme)
- [Terminal multiplexers](#terminal-multiplexers)
- [Debian chroots](#debian-chroots)
- [git](#git)
- [readline](#readline)
- [Shell frameworks](#shell-frameworks)
  - [On your own machine](#on-your-own-machine)
- [Which side is asked](#which-side-is-asked)
- [A tool with no variable and no flag](#a-tool-with-no-variable-and-no-flag)
- [Config sizes](#config-sizes)

## At a glance

| tool                                                                                                                                                                                                                                                                                                                                                                                           | what hi does with it                                                          | on by default               | switch                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------- | --------------------------------------------- |
| [starship](https://starship.rs), [oh-my-posh](https://ohmyposh.dev), [powerline-go](https://github.com/justjanne/powerline-go), [powerlevel10k](https://github.com/romkatv/powerlevel10k), [oh-my-zsh](https://ohmyz.sh) themes, [oh-my-bash](https://github.com/ohmybash/oh-my-bash) themes, [bash-it](https://github.com/Bash-it/bash-it) themes, [tide](https://github.com/IlanCosman/tide) | draws the prompt in hi's place, with your config from home                    | yes, where installed here   | `_HI_PROMPT_TOOL` (`hi` for hi's own)         |
| mise, asdf, pyenv, rbenv, nodenv, nix, guix, devbox, devenv, direnv, conda, venv                                                                                                                                                                                                                                                                                                               | names the active ones in the prompt's leading `(myproj)` segment              | yes                         | `_HI_DISABLE_ENV_STATUS`                      |
| [bat](https://github.com/sharkdp/bat), [eza](https://github.com/eza-community/eza)                                                                                                                                                                                                                                                                                                             | `cat`, `bat`, and `ls`/`eza` aliases with hi's flags and your theme           | no: opt-in, where installed | `_HI_TOOL_ALIASES`                            |
| tmux, zellij, screen                                                                                                                                                                                                                                                                                                                                                                           | `hi --keep` runs the session inside one on the target; your `tmux.conf` rides | no: per connect             | `--keep`, `--no-keep`, `--end`                |
| vim/neovim, nano, emacs, micro, [helix](https://helix-editor.com), [kakoune](https://kakoune.org)                                                                                                                                                                                                                                                                                              | opens with your config through an alias ([the files](FILES.md#the-overlay))   | yes                         | `hi --disable-plugin editors`, or one by name |
| oh-my-zsh, powerlevel10k, bash-it, fzf                                                                                                                                                                                                                                                                                                                                                         | loads after them and leaves their hooks working                               | -                           | [Shell frameworks](#shell-frameworks)         |

## Prompt programs

A prompt program you already use draws the prompt in hi's place, here and on
every target that has it. hi keeps the header, aliases, and editors, and
hands over only the prompt line. With `_HI_PROMPT_TOOL` unset, hi tries every
program installed here, in this order, and the first that fits the shell and
that the target has wins:

| program       | shells          | counts as installed here                                                                            | started on a target                                                    | your config from home                                                            |
| ------------- | --------------- | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| powerlevel10k | zsh             | your zsh rc loads the theme _and_ `${ZDOTDIR:-~}/.p10k.zsh` (or `$POWERLEVEL9K_CONFIG_FILE`) exists | as the rc loaded it, else from the usual install paths                 | that file, sourced after powerlevel10k                                           |
| oh-my-zsh     | zsh             | `ZSH_THEME` in `${ZDOTDIR:-~}/.zshrc` names a theme file                                            | as the rc loaded it, else only the libraries themes call               | the theme file, so a custom theme works on a box without it                      |
| oh-my-bash    | bash            | `OSH_THEME` in `~/.bashrc` names a theme file                                                       | as the rc loaded it, else without its plugins, aliases, or completions | the theme file                                                                   |
| bash-it       | bash            | `BASH_IT_THEME` in `~/.bashrc` names a theme file                                                   | as the rc loaded it, else with `BASH_IT_THEME` pointed at your theme   | the theme file                                                                   |
| tide          | fish            | its functions autoload in fish                                                                      | fish loads it; hi leaves its prompt alone                              | the `tide_*` universal variables, never the rest of `fish_variables`             |
| starship      | bash, zsh, fish | on `$PATH`                                                                                          | `starship init <shell>`                                                | `$STARSHIP_CONFIG`, else `~/.config/starship.toml`                               |
| oh-my-posh    | bash, zsh, fish | on `$PATH`                                                                                          | `oh-my-posh init <shell>`                                              | `$POSH_CONFIG` (or `$POSH_THEME`), else the file your rc's `init --config` names |
| powerline-go  | bash, zsh, fish | on `$PATH`                                                                                          | once per prompt, with `_HI_POWERLINE_GO_OPTS`                          | the flags in `_HI_POWERLINE_GO_OPTS`                                             |

The list is worked out on your machine and handed to the target, which never
looks for programs of its own: a shared box with powerlevel10k installed does
not change your prompt unless you use it too. A program whose plugin is off
(`hi --disable-plugin starship`) is left off the list unless `_HI_PROMPT_TOOL`
names it.

**Choosing.** `_HI_PROMPT_TOOL` takes a list:

- `"tide starship"` is tide in fish and starship in bash and zsh.
- `"tide hi"` is tide in fish and hi's prompt elsewhere.
- `"bash:starship hi"` is starship in bash and hi's prompt in zsh and fish. A
  `<shell>:<program>` entry is tried first, by that shell only.
- `hi` alone keeps hi's prompt everywhere, and takes the prompt back from one
  a target's own rc started.
- `_HI_DISABLE_PROMPT=1` beats all of it: no prompt from hi at all.

**Prompts hi leaves alone.** A prompt hi cannot hand over stays yours:
liquidprompt or bash-git-prompt in bash; spaceship, pure, or a promptinit
theme in zsh; any custom `fish_prompt` in fish. At home, a `PS1` or `PROMPT`
you wrote also stays; hi replaces only the shell's default and the stock
distro ones. On a target, hi's prompt draws whatever the box sets; to use your
own there, put it in the overlay's `bashrc` or `zshrc` with
`_HI_DISABLE_PROMPT=1`.

**Framework themes** are sourced on a target only where that framework is
installed, so a theme's `source "$ZSH/lib/..."` works as written; elsewhere
hi's prompt draws. Under powerlevel10k's instant prompt, hi calls
`p10k clear-instant-prompt` before the header, so p10k does not warn.

Each config from home rides the overlay; a copy in `~/.config/say-hi/` rides
instead, which is how targets get a different one. Why hi hands over only the
prompt: [HI.32](GLOSSARY.md#hi32-starship-deference).

## Shell hooks of your own

zoxide's and atuin's `init`, `direnv hook`, and `mise activate` are plugins of
the `hooks` group, off by default. `hi --enable-plugin zoxide` runs zoxide's
init on targets that have it, after the aliases and extensions
([SETTINGS.md](SETTINGS.md#shell-hooks)). They are off because each keeps
state under the target's `$HOME` (zoxide's database, atuin's history), which
hi neither writes nor cleans up.

A tool of your own is one `[hooks.<name>]` table with an `init` in your
plugins file (`hi --edit plugins`); `shells = "zsh fish"` limits where it
runs. Anything else goes in the overlay's per-shell files:

```sh
# ~/.config/say-hi/bashrc
command -v fzf >/dev/null && eval "$(fzf --bash)"
```

## Header cells of your own

A header item hi does not have is a file under `~/.config/say-hi/header/`,
named for its word, defining `_hi_cell_<word>`. The function writes the
cell's text, a color first, into the variable named by its first argument.
`_HI_HEADER_ORDER` places the word:

```sh
# ~/.config/say-hi/header/load
_hi_cell_load() {
  local _load_l
  read -r _load_l _ 2>/dev/null </proc/loadavg || _load_l="?"
  printf -v "$1" '%s' "${YELLOW}Load: $_load_l"
}
```

```sh
# ~/.config/say-hi/settings.sh
export _HI_HEADER_ORDER="banner utc version localtime os load check greeting"
```

- The file is bash, whatever shell the session runs.
- The word is the file name up to its first `.`; a built-in word's file
  replaces that item.
- Prefix the function's locals: the variable it writes is its caller's.
- Lead with one of hi's colors (`$RED`, `$GREEN`, `$YELLOW`, `$BLUE`,
  `$PURPLE`, `$CYAN`, or a `$BR` one); a cell that would repeat its
  neighbor's color takes the next hue
  ([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)).
- It runs on every header, a local greeting included, so every command it
  starts costs a fork each time.
- A file bash cannot parse is skipped with a warning; `hi --doctor` lists the
  cells and flags it.

## The environment segment

The prompt's leading `(myproj)` names every active environment manager,
outermost first: `(mise|direnv:proj|myproj)` is mise, a direnv-loaded
`proj`, and a venv inside it. It reads the variables the tools export
(`$MISE_SHELL`, `$VIRTUAL_ENV`, `$CONDA_DEFAULT_ENV`, ...), so it costs no
fork. mise shows only where a project config overrides the global one. A
`.venv` is named for the directory holding it. A
[prompt program](#prompt-programs) replaces the segment with the rest of the
prompt; `_HI_DISABLE_ENV_STATUS=1` turns it off.

### Tools that draw their own prefix

hi stands down for a tool that draws its own prefix: an activated venv keeps
its own `(myproj)` in zsh and fish. bash rebuilds `$PS1` on every draw, so
there hi draws the segment itself.

For hi's styling everywhere, silence the tool's prefix as the tool documents:
`export VIRTUAL_ENV_DISABLE_PROMPT=1` before activating a venv, and
`conda config --set changeps1 false`. hi never sets these for you, since every
other shell reads them too
([HI.54](GLOSSARY.md#hi54-who-draws-the-environment-prefix)).

## bat and eza

With `_HI_TOOL_ALIASES=1`, hi builds these aliases from what the target has:

- `cat` and `catn` run bat (or Debian's `batcat`) with `_HI_BAT_OPTS`: no
  pager, two-space tabs, `changes,grid` style, and your bat config's theme.
  `catn` adds line numbers. Without bat, `cat` is `ccat` or plain `cat`, and
  there is no `catn`.
- `ls` and `eza` are one alias running eza if the target has it, else `ls`,
  each with its own flags (`_HI_LS_OPTS`). Set `_HI_LS_OPTS` yourself and it
  wins.

Off, the default, `cat`, `ls`, and `bat` are the plain commands. No alias
names a tool the target lacks. To add one flag to hi's, redefine the alias in
[your `aliases.sh`](SETTINGS.md#shells-you-drop-into-inside-a-session).

### Shipping your bat theme

Every target gets the bat config you keep here (`$BAT_CONFIG_PATH`, else
`$BAT_CONFIG_DIR/config`, else `~/.config/bat/config`), or the overlay's
`bat/config` instead. The default `_HI_BAT_OPTS` sets no `--theme`, so the
file's theme is the one you see.

### Shipping your eza theme

Every target gets the `theme.yml` eza reads here (`$EZA_CONFIG_DIR/theme.yml`,
else `~/.config/eza/theme.yml`), or the overlay's `eza/theme.yml` instead.
Like `BAT_CONFIG_PATH`, `EZA_CONFIG_DIR` is set on a target whatever
`_HI_TOOL_ALIASES` says, so a bare `command eza` matches too.

## Terminal multiplexers

`hi --keep <target>` runs the session in tmux, zellij, or screen on the
target, the first it has. The session outlives the connection, your laptop
sleeping, or a move to another machine, and every later `hi <target>`
reattaches. `--no-keep` opens an ordinary session beside it. A colleague on
the same account gets a session of their own. `_HI_KEEP=1` makes every
connect a kept one.

It needs a target with bash, an ssh host or a container, and a terminal on
your side; anywhere else hi says so and connects as usual.

**Ending it**, which removes the session's directory:

- `exit` in the first pane, which asks first; anything but `y` detaches and
  leaves a fresh shell in the pane;
- `hi --end <target>`, from your side;
- nobody attached for `_HI_KEEP_TIMEOUT` (24h).

Detach with the multiplexer's own key. New panes and windows run hi's shell
too.

**A dropped link.** hi retries for `_HI_KEEP_RETRY` (5m) and lands you back
in the session, showing how long the target keeps it. Ctrl+C stops retrying;
`hi <target>` reattaches later. ssh's `~.` counts as a drop, so `~.` then
Ctrl+C leaves. A silent link counts as dropped after 45 seconds unless your
ssh config sets its own `ServerAliveInterval`.

**No multiplexer on the target.** The shell cannot outlive the connection, so
`--keep` holds the session directory and your working directory instead. For
`_HI_HOLD_TIMEOUT` (15m; `0` turns it off), a reconnect starts a new shell on
the same files, where the last one stood; its header says `Resumed`. What was
running is gone.

**Inside a session.** `hi --keep` with no target keeps the session you are
in: a fresh shell in a multiplexer there, sharing its directory. Typing a bare
`tmux`, `zellij`, or `screen` asks whether to make it the kept session; with
arguments (`tmux attach`) it runs as typed.

**Your configs.** A tmux on a target reads your `~/.tmux.conf` (or the
overlay's `tmux/tmux.conf`); screen reads your `~/.screenrc`, and zellij your
config directory's `config.kdl`, `layouts/`, and `themes/`. A line that names
a file the target does not have (`source-file`, TPM's plugins, zellij's
`file:` plugins) goes out disabled, and `hi --doctor` names it.

`_HI_DISABLE_KEEP=1` turns all of this off: `--keep` and `--end` are refused,
and the multiplexers in a session are the plain tools. For a container or
`--plain`, use a multiplexer of your own:
`tmux new -A -s <name> hi <target>`. How it works:
[HI.65](GLOSSARY.md#hi65-kept-session).

## Debian chroots

A chroot's `/etc/debian_chroot` leads the prompt, as the distro's own
`~/.bashrc` sets it up: `(name)` in bash and zsh, `(chroot:name)` in fish.
hi sets no `$LESSOPEN`, `$GCC_COLORS`, `$CLICOLOR`, or `$LSCOLORS`; the `env`
plugin sends your values of the color ones
([SETTINGS.md](SETTINGS.md#variables-that-ride)).

## git

The git plugin is off until `hi --enable-plugin git`. It carries your global
config (`$GIT_CONFIG_GLOBAL`, else `~/.gitconfig`, else
`$XDG_CONFIG_HOME/git/config`): your aliases, name, email, and settings such
as `pull.rebase`. It is read after the target's own config and a
repository's, so yours wins. It needs git 2.31 or newer on the target.

No key and no path to one rides. These stay home:

- every key of `[credential]`, `[gpg]`, `[includeIf]`, and `[sendemail]`;
- a `[url]`'s `insteadOf` and `pushInsteadOf`;
- in any section: `signingKey`, `gpgSign`, `forceSignAnnotated`,
  `sshCommand`, `sslKey`, `sslCert`, `cookieFile`, `extraHeader`, `askPass`,
  `proxy`, and `password`.

A `# hi-allow` comment on the line above one sends it anyway, and
`hi --plugins` lists each. An `[include]` of a file under `~/.config/git/`
rides; one elsewhere is dropped and `hi --doctor` names it
([HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan)).

## readline

Every target gets your inputrc (`$INPUTRC`, else `~/.inputrc`), or the
overlay's `inputrc` instead. bash and every readline program in the session
use it; zsh and fish have their own line editors. A set `INPUTRC` replaces
`/etc/inputrc`, so an inputrc that relies on it says `$include /etc/inputrc`,
which rides as written. Any other `$include` is dropped.

## Shell frameworks

A framework on a target loads normally, and hi's setup runs after the
shell's own rc. `tests/targets/framework_test.sh` installs twelve the way
their READMEs say (oh-my-zsh, powerlevel10k, starship, bash-it, oh-my-bash,
tide, powerline-go, fzf, zoxide, direnv, atuin, mise) plus a tmux with the
target's own config. It connects for real and checks for shell errors and
that each one's hook, key binding, or prompt still works.

### On your own machine

A prompt program your rc loads keeps drawing here. `_HI_DISABLE_LOCAL=1`
goes further: everything on this page stays as your rc set it up on this
machine, while targets still get hi's. How hi tells home from a target:
[SETTINGS.md's _Others_](SETTINGS.md#others).

## Which side is asked

- **Your machine decides what rides.** A config from home ships only when its
  tool is installed here: `vim/vimrc` with vim, `nvim/init.lua` with nvim,
  `tmux/tmux.conf` with tmux, `bat/config` with bat, `git/config` with git
  once its plugin is on, and so on; `inputrc` always. A dotfile left by a
  tool you removed does not ship.
- **An overlay copy always rides.** A file you put in `~/.config/say-hi/`
  means "targets get this", whatever is installed here.
- **A plugin that is off never rides**, overlay copy included
  ([SETTINGS.md](SETTINGS.md#switching-a-plugin-off)).
- **The target decides what is used.** Each alias is made only for a tool
  the target has and a config that rode
  ([HI.62](GLOSSARY.md#hi62-generated-wiring)), so there is never an alias to
  a missing binary or file.

## A tool with no variable and no flag

A carried config reaches its tool through a variable (`$RIPGREP_CONFIG_PATH`,
`$KAKOUNE_CONFIG_DIR`) or a flag the alias adds (`tmux -f`, `hx -c`). Some
files have neither: helix reads `languages.toml` only from its config
directory. For those, a plugin row's wire is `xdg:<command>`, and the alias
points `$XDG_CONFIG_HOME` at the overlay
([SETTINGS.md](SETTINGS.md#a-tool-hi-does-not-know)).

Use it only as a last resort: everything the command starts (a language
server under helix, `git` under lazygit) then reads its config from the
overlay instead of the target's `~/.config`.

## Config sizes

> **Estimates**, not measurements: each row pairs a plausible setup with the
> size of similar public files after hi's comment strip and `gzip -9n`.
> `hi --doctor` and the size hi prints on connect are the numbers for yours.

Everything in the overlay rides every connect. hi strips comments and blank
lines first ([HI.35](GLOSSARY.md#hi35-payload-comment-and-whitespace-strip)),
so comment-heavy files shrink most.

| user                                                        | what rides the overlay                             | on disk  | stripped | on the wire (gzip) |
| ----------------------------------------------------------- | -------------------------------------------------- | -------- | -------- | ------------------ |
| defaults, nothing configured                                | nothing                                            | 0        | 0        | 0                  |
| a few settings and aliases                                  | `settings.sh`, `aliases.sh`                        | ~2 KB    | ~1 KB    | ~0.5 KB            |
| starship with a preset                                      | `starship.toml` (the nerd-font-symbols preset)     | ~3.4 KB  | ~3.4 KB  | ~1.4 KB            |
| oh-my-posh with a stock theme                               | `oh-my-posh.json` (jandedobbeleer)                 | ~7 KB    | ~7 KB    | ~1.4 KB            |
| oh-my-zsh, robbyrussell                                     | `oh-my-zsh.zsh-theme`                              | ~0.4 KB  | ~0.4 KB  | ~0.2 KB            |
| oh-my-zsh, agnoster                                         | `oh-my-zsh.zsh-theme`                              | ~13 KB   | ~8 KB    | ~2.5 KB            |
| oh-my-bash, font or agnoster                                | `oh-my-bash.theme.sh`                              | 2-20 KB  | 1-9 KB   | 0.5-2.6 KB         |
| tide, configured by its wizard                              | `tide.vars` (its ~160 variables)                   | ~6 KB    | ~6 KB    | ~1.5 KB            |
| powerlevel10k from its wizard                               | `p10k.zsh` (lean or rainbow)                       | 90-95 KB | 24-28 KB | ~5.5 KB            |
| a tuned vim                                                 | `vim/vimrc` (like amix/vimrc's basic.vim)          | ~9.5 KB  | ~4 KB    | ~1.8 KB            |
| a neovim starter config                                     | `nvim/init.lua` (like kickstart.nvim, single file) | ~44 KB   | ~19 KB   | ~6 KB              |
| a long-lived bash setup                                     | `bashrc`, `aliases.sh`, a few extensions           | 10-30 KB | 5-15 KB  | 2-6 KB             |
| all of it: powerlevel10k, tide, neovim, vim, bash, starship | everything above that ships at once                | ~200 KB  | ~75 KB   | ~20 KB             |

A neovim config split under `~/.config/nvim/lua/` rides as `init.lua` plus
the modules it requires by name; a plugin manager's specs stay home with the
plugins.
