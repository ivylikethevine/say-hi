# Integrations

hi installs none of the tools below and ships none of them. Where a target
already has one, a session wires it in the way the tool's own README tells you
to wire it into an rc; where it does not, the session goes on without it and
says nothing. Each is either on wherever the tool is found or an opt-in, and
every one has a switch in [SETTINGS.md](SETTINGS.md#every-setting).

## Contents

- [At a glance](#at-a-glance)
- [Prompt programs](#prompt-programs)
- [zoxide and atuin](#zoxide-and-atuin)
- [The environment segment](#the-environment-segment)
  - [Tools that draw their own prefix](#tools-that-draw-their-own-prefix)
- [bat and eza](#bat-and-eza)
  - [Shipping your bat theme](#shipping-your-bat-theme)
  - [Shipping your eza theme](#shipping-your-eza-theme)
- [Terminal multiplexers](#terminal-multiplexers)
- [lesspipe](#lesspipe)
- [Shell frameworks](#shell-frameworks)
  - [On your own machine](#on-your-own-machine)

## At a glance

| tool                                                                                    | what hi does with it                                                          | on by default        | switch                                                   |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------- | -------------------------------------------------------- |
| [starship](https://starship.rs), [oh-my-posh](https://ohmyposh.dev)                     | draws the prompt in hi's place, with your config from home                    | no - opt-in          | `_HI_PROMPT_TOOL`                                        |
| [zoxide](https://github.com/ajeetdsouza/zoxide), [atuin](https://atuin.sh)              | runs the tool's `init <shell>`                                                | yes, where installed | `_HI_DISABLE_TOOL_INIT`                                  |
| mise, asdf, pyenv, rbenv, nodenv, nix, guix, devbox, devenv, direnv, conda, venv        | names the active ones in the prompt's leading `(myproj)` segment              | yes                  | `_HI_DISABLE_ENV_STATUS`, `_HI_ENV_ORDER`                |
| [bat](https://github.com/sharkdp/bat), [eza](https://github.com/eza-community/eza), exa | `cat`, `bat`, `eza`, and `exa` aliases with hi's flags, your theme from home   | yes, where installed | `_HI_DISABLE_TOOL_ALIASES`, the `_HI_*_OPTS` and `_BIN`s |
| tmux, zellij, screen                                                                    | `hi --mux` runs the connect inside one, on the client                         | no - per connect     | `--mux`, `--no-mux`                                      |
| lesspipe                                                                                | `less` opens archives and packages, as the distro's own rc sets it up         | yes, where installed | none                                                     |
| vim/neovim, nano, emacs, helix, kakoune, micro                                          | opened with hi's config, or yours, through an alias                           | yes                  | `_HI_DISABLE_EDITORS`; the files are [SETTINGS.md](SETTINGS.md)'s overlay table |
| oh-my-zsh, powerlevel10k, bash-it, fzf                                                  | nothing: hi loads after them and leaves their hooks working                   | -                    | [Shell frameworks](#shell-frameworks)                    |

`_HI_DISABLE_LOCAL=1` turns every `_HI_DISABLE_*` switch above on, prompt
included, on your own machine only, and leaves every target as it was
([On your own machine](#on-your-own-machine)).

## Prompt programs

`_HI_PROMPT_TOOL=starship` hands the prompt to starship on every target that
has it, and `_HI_PROMPT_TOOL=oh-my-posh` to oh-my-posh, through the tool's own
`init <shell>` in bash, zsh, and fish. Only the prompt line changes hands: hi
still prints the header and sets up the aliases and editors. A target without
the tool keeps hi's prompt and says nothing. The setting is never
auto-detected, so a box that happens to carry starship does not change your
prompt until you ask for it. `hi --configure` offers starship under Prompt;
oh-my-posh is a line you write into `settings.sh` by hand.
`_HI_DISABLE_PROMPT=1` beats both: hi starts no prompt at all, its own or the
tool's.

A `starship.toml` or `oh-my-posh.json` in `~/.config/say-hi/` rides the overlay
and on a target becomes `$STARSHIP_CONFIG` or `$POSH_THEME`, so the prompt on
every host is the one you configured at home. At home hi leaves both variables
alone and the tool reads its own config. With no `starship.toml` in the
overlay, the one starship reads here - `$STARSHIP_CONFIG`, else
`~/.config/starship.toml` - travels under that name, so the config you already
keep follows you with no second copy to fall behind; an overlay copy wins, for
a target prompt that differs from home's. oh-my-posh has no default file, so
its config rides only from the overlay.

A prompt of your own at home that is neither (powerlevel10k, an oh-my-zsh
theme, a hand-written `PS1`) is what `_HI_DISABLE_LOCAL=1` is for; see
[On your own machine](#on-your-own-machine). Why hi hands over the prompt and
nothing else is [HI.32](GLOSSARY.md#hi32-starship-deference).

## zoxide and atuin

Where a target has zoxide or atuin, every session runs the tool's
`init <shell>`: zoxide's ranked `z` and `zi` jumps, atuin's Ctrl-R history
search, in bash, zsh, and fish alike. A tool something has already wired in is
left alone - each leaves a function behind (`__zoxide_z`; atuin's
`_atuin_search` in zsh and fish, `__atuin_history` in bash), and hi checks for
it first - so the `init` your own rc runs at home is never run twice.
`_HI_DISABLE_TOOL_INIT=1` turns both off; `hi --configure` lists it under
Features, and the `minimal` preset answers it off.

hi writes nothing for either, but once started the tools keep state of their
own: zoxide's directory database and atuin's history, wherever each keeps them
under the target's `$HOME`. A target where that matters wants
`_HI_DISABLE_TOOL_INIT=1`;
[SECURITY.md](SECURITY.md#what-hi-writes-on-a-target) lists what each tool
leaves behind.

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
the directory holding it, not for itself. `_HI_ENV_ORDER` reorders the list
or drops words from it, and `_HI_DISABLE_ENV_STATUS=1` turns the whole
segment off. The segment is part of hi's prompt, so a
[prompt program](#prompt-programs) replaces it along with the rest.

### Tools that draw their own prefix

hi stands down for a tool already drawing its own prefix, so nothing appears
twice: a `source .venv/bin/activate` keeps its own `(myproj)` in zsh and fish,
where the shell holds on to the prompt the activate script edited. bash is the
exception - hi rebuilds `$PS1` on every draw, so the activate script's prefix
cannot survive there and hi draws the segment itself. The upshot is that a
venv is named in all three shells, in the venv's styling under zsh and fish
and in hi's under bash; direnv, nix, and the rest have no prefix of their own
and are always hi's.

To get hi's styling and naming everywhere instead, silence the tool's own
prefix the way the tool documents: `VIRTUAL_ENV_DISABLE_PROMPT=1` for a venv
(`export` it before you activate) and `conda config --set changeps1 false`.
With no prefix of its own on screen, hi draws the segment in every shell -
which is also how a `.venv` stops reading as `(.venv)`, since a venv names
itself after its own directory and hi names it after the project holding it.
hi never sets those two for you: they are your setting, and every other shell
and prompt you open reads them too
([HI.54](GLOSSARY.md#hi54-who-draws-the-environment-prefix) has the why).

## bat and eza

`settings/aliases.sh` builds the styled tool aliases from whatever the target
has, first installed wins:

- `cat` and `catn` run bat (Debian's `batcat`, where that is its name) with
  `_HI_BAT_OPTS` - no pager, two-space tabs, the Monokai Extended Bright theme,
  and the `changes,grid` style - and `catn` adds line numbers. Without bat
  they fall through to `ccat`, then plain `cat`.
- `exa` and `eza` run whichever of the two the target has, with
  `_HI_EXA_OPTS` or `_HI_EZA_OPTS`.

`_HI_DISABLE_TOOL_ALIASES=1` drops the `cat`/`catn` rebind and the `exa`/`eza`
wrappers; `bat`, `batcat`, and `batn` stay available by name either way. The
flags and the binary each alias runs are rows in
[Every setting](SETTINGS.md#every-setting), set in your `settings.sh`; to add
one flag to hi's instead, redefine the alias in your `aliases.sh`, which loads
after hi's: `alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS --icons"`.

### Shipping your bat theme

The bat config you already keep travels as-is: with no `bat.conf` in the
overlay, the file bat reads here - `$BAT_CONFIG_PATH`, else
`$BAT_CONFIG_DIR/config`, else `~/.config/bat/config` (under
`$XDG_CONFIG_HOME` when set) - rides it under that name. A
`~/.config/say-hi/bat.conf` of its own (`--theme="Catppuccin Mocha"`, one flag
per line) wins, for targets that should differ from home. On a target the file
becomes `$BAT_CONFIG_PATH`, and `settings/aliases.sh` leaves `--theme` out of
the default `_HI_BAT_OPTS` whenever that variable is set, so the file's theme
is the one you see through `cat`. The same rule applies at home if you export
`BAT_CONFIG_PATH` yourself; a `_HI_BAT_OPTS` of your own always wins outright.

### Shipping your eza theme

eza reads its colors from `$EZA_CONFIG_DIR/theme.yml` and insists on that
file name, so hi does not rename it. With no `theme.yml` in the overlay, the
one eza reads here - `$EZA_CONFIG_DIR/theme.yml`, else
`~/.config/eza/theme.yml` (under `$XDG_CONFIG_HOME` when set) - travels in its
place; a `theme.yml` dropped into the overlay wins. On a target,
`common/paths.sh` exports `EZA_CONFIG_DIR` pointing at the shipped copy - the
directory itself, not the file. At home the variable is left alone.

The file rides only when there is one, like every overlay member, and only the
`eza` alias (`_HI_DISABLE_TOOL_ALIASES`) is affected: a bare `command eza` on
the target reads the same variable, so it matches too.

## Terminal multiplexers

`hi --mux <target>` starts the connect inside a session of the first of tmux,
zellij, and screen on **your** `PATH`, named `hi-<target>`, and a second
`hi --mux <target>` joins the one already running - so a dropped link leaves
a session to reattach to, on your side. Already inside tmux, hi switches the
client to that session rather than nesting; inside screen or zellij it
opens a new window or tab. `_HI_MUX=1` (`hi --configure`'s advanced item) makes it the default
and `--no-mux` skips it once. The target sees an ordinary session: persistent
sessions on the target
were [decided against](SUPPORT.md#what-would-change-an-answer), and
[HI.52](GLOSSARY.md#hi52-client-multiplexer-wrap) is how the wrap works.

## lesspipe

Where a target has `/usr/bin/lesspipe` (Debian and Ubuntu ship it) and
`$LESSOPEN` is not already set, bash and zsh sessions `eval` it, so `less`
opens archives, packages, and compressed files the way the distro's own
`~/.bashrc` sets it up. A nested shell inherits the exported `$LESSOPEN` and
skips it. In the same spirit, a chroot's `/etc/debian_chroot` leads the bash
and zsh prompts as `(name)`.

## Shell frameworks

A framework on a target loads normally. hi lands you in your own login shell
when hi styles it, else the best of `fish zsh bash` the target has, and hi's
setup runs after that shell's own rc - so hi is the one positioned to break a
framework, and the one tested for it. `tests/targets/framework_test.sh`
installs nine per their own READMEs - oh-my-zsh, powerlevel10k, starship,
bash-it, fzf, zoxide, direnv, atuin, and mise - connects for real, and asserts
no shell errors and the framework's own hook left intact: zsh's array base
unchanged under oh-my-zsh and powerlevel10k, `PROMPT_COMMAND` chained rather
than replaced for zoxide, direnv, and mise, and fzf's and atuin's `bind -x`
Ctrl-R bindings in place. The starship case is starship started from the
target's own rc; `_HI_PROMPT_TOOL` is the rc suite's.

### On your own machine

`_HI_DISABLE_LOCAL=1` leaves your framework's prompt, and everything else on
this page, as your own rc set it up on this machine, while every target still
gets hi's. A starship or oh-my-posh user can have both instead:
`_HI_PROMPT_TOOL` hands the prompt to the tool wherever it is installed, home
included. How hi tells home from a target is
[SETTINGS.md's _Others_](SETTINGS.md#others).
