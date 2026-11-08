# Settings

`hi --configure` starts you from a preset and opens `settings.sh` in your
editor, every setting a line of it. That file, and every other file of yours
hi reads, lives in the overlay, `${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/`
(`$_HI_CONFIG_DIR`), outside the checkout. The overlay rides to every host
you say `hi` to; the tree's `config/` holds the shipped defaults.

## Contents

- [Configuring](#configuring)
- [Presets](#presets)
- [The overlay](#the-overlay)
  - [The site tier](#the-site-tier)
- [Every setting](#every-setting)
  - [Not settings](#not-settings)
- [Settings by host tag](#settings-by-host-tag)
- [Header details](#header-details)
  - [Others](#others)
  - [Shells you drop into inside a session](#shells-you-drop-into-inside-a-session)
  - [Extensions](#extensions)
  - [Scripts of your own](#scripts-of-your-own)
  - [Switching a plugin off](#switching-a-plugin-off)
  - [Shell hooks](#shell-hooks)
  - [Variables that ride](#variables-that-ride)
  - [A tool hi does not know](#a-tool-hi-does-not-know)
  - [The TOML hi reads](#the-toml-hi-reads)
- [The editor rcs come from where you keep them](#the-editor-rcs-come-from-where-you-keep-them)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)

## Configuring

`hi --configure` asks which [preset](#presets) to start from (Enter keeps
your current settings), writes `settings.sh`, and opens it in your editor
(`$VISUAL`, `$EDITOR`, `_HI_EDITOR`, or the first editor installed). Every
setting is a line: one you set is an `export`, and the rest are commented
out at their defaults. To change one, edit its value and remove the `#`.

```sh
export _HI_DISABLE_LOCAL=1                    # added by hi during install
# export _HI_MAX_WIDTH=80                     # added by hi during install
```

- `hi --configure --preset <name>` writes a preset with no question and no
  editor. With no terminal, `hi --configure` refuses rather than guess.
- `hi --edit settings.sh` opens the file without the question.
- Each run rewrites hi's block (the lines ending in its marker) and keeps your
  values. A setting you wrote elsewhere in the file moves into the block.
- `hi --doctor` flags a value hi would ignore; `hi --preview header` draws the
  header with your settings.
- Colors are not settings: they live in the [colors file](COLORS.md).

## Presets

A preset sets the feature toggles, package groups, and plugins it names, and
resets the rest of those to their defaults. Other settings (header order,
width, colors, prompt, timeouts) are left alone. The first install asks for
one, `balanced` by default.

| preset       | what it sets                                                                                                                        |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | every feature and header item, and the `useful` package group (`_HI_PACKAGES_GROUPS=core,useful,deprecated`); the alias opt-ins off |
| `balanced`   | everything, with a shorter package check (`core,deprecated`), and nothing on this machine (`_HI_DISABLE_LOCAL=1`)                   |
| `minimal`    | the colored prompt and your configs; no header, git status, or editor configs; nothing on this machine                              |
| `lean`       | `minimal`, and nothing of yours rides: every plugin stays home, hi's own prompt everywhere, ssh the only backend                    |

`lean` is the least hi can send: only `settings.sh`, `colors`, and `packages`
ride, no prompt program runs on a target, and no backend CLI starts. It also
sets `_HI_PROMPT_TOOL=hi` and `_HI_BACKENDS_OFF=all`, which other presets do
not reset; comment those two lines out to leave it.

For your configs with each target's own prompt, start from `minimal`, set
`_HI_DISABLE_PROMPT=1`, and take the editors out of `_HI_PLUGINS_OFF`.

## The overlay

Every file in the overlay, what it replaces, and what reads it is
[FILES.md's overlay table](FILES.md#the-overlay). Each file is looked for in
one order: the overlay copy, else the config its tool already reads on this
machine ([below](#the-editor-rcs-come-from-where-you-keep-them)), else the
shipped default. Shell rcs (`bashrc`, `zshrc`, `config.fish`) ride only from
the overlay ([HI.61](GLOSSARY.md#hi61-one-overlay-priority)).

The overlay starts with only `settings.sh`. `hi --edit colors` and
`hi --edit packages` copy the shipped file in and open it. A copy stops
following updates to the shipped file; delete it to go back, and
`hi --doctor` says which one is in force. Version the directory yourself if
you want to: a `git init` there, or
[a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager).

**Files from an older hi.** `hi --install`, `hi --configure`, and
`hi --update` convert files in an older shape, keeping each original as
`<file>.old` (`scripts/convert_settings.sh` by hand, and its header lists
every conversion). `hi --doctor` flags a file still in an old shape or under
an old name, with the `mv` that fixes it.

### The site tier

A team's defaults for every account on a box live in `/etc/say-hi/` (or the
first `say-hi/` under `$XDG_CONFIG_DIRS`): `settings.sh`, `colors`,
`packages`, and `plugins`, shaped like the overlay's. They sit between the
tree's defaults and yours:

- a site `settings.sh` is read before yours, so your lines win;
- a site `colors` or `packages` replaces the tree's until you copy one into
  the overlay;
- a site `plugins` adds to the tree's, and yours replaces one of the same name.

`hi --doctor` says which tier each file came from. No package ships anything
there, and a target never reads its own site directory: what rode applies.

## Every setting

Every setting is an environment variable. `settings.sh` is a plain
`export NAME=value` script every shell reads, after the environment, so its
lines win over your own exports. Programs started from a hi shell do not see
them ([HI.47](GLOSSARY.md#hi47-what-a-child-inherits)); for that, `export`
in your own [`bashrc`, `zshrc`, or `config.fish`](#shells-you-drop-into-inside-a-session).

The **set by** column: **you** means only you set it; **a preset, or you**
means every preset also sets it ([Presets](#presets)). `hi --doctor` flags a
value hi would ignore (a width under 40, an unknown header word). The table
is written from `scripts/settings`.

| variable                    | default                                                                                                                                        | set by           | what it does                                                                                                                                                                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_HI_DISABLE_HEADER`        | `0`                                                                                                                                            | a preset, or you | turns off the whole header, on connect, on disconnect, and in a local shell; a connect then sends no header code                                                                                                                     |
| `_HI_HEADER_ORDER`          | the table in [Header details](#header-details)                                                                                                 | you              | which header items show, and in what order; empty is the default list                                                                                                                                                                |
| `_HI_MAX_WIDTH`             | `80`                                                                                                                                           | you              | the columns the header is drawn to, or fewer on a narrower terminal; 40 at least                                                                                                                                                     |
| `_HI_PACKAGES_GROUPS`       | `core deprecated`                                                                                                                              | a preset, or you | the `config/packages` groups the header's check runs, or `none`; `base` adds the tools hi itself uses ([the package check](COLORS.md#the-package-checks-rows))                                                                       |
| `_HI_IP_HIDE`               | `docker* br-* podman* cni-podman* virbr* lxdbr* incusbr*`                                                                                      | you              | globs of addresses or interface names the header's `ip` cell hides; `none` hides nothing ([Header details](#header-details))                                                                                                         |
| `_HI_DISABLE_GIT_STATUS`    | `0`                                                                                                                                            | a preset, or you | turns off the prompt's git segment                                                                                                                                                                                                   |
| `_HI_DISABLE_ENV_STATUS`    | `0`                                                                                                                                            | a preset, or you | turns off the prompt's `(myproj)` environment segment ([Integrations](INTEGRATIONS.md#the-environment-segment))                                                                                                                      |
| `_HI_TOOL_ALIASES`          | `0`                                                                                                                                            | a preset, or you | `1` turns on the `cat`, `bat`, `ls`, and `eza` aliases ([Integrations](INTEGRATIONS.md#bat-and-eza))                                                                                                                                 |
| `_HI_SUDO_ALIAS`            | `0`                                                                                                                                            | a preset, or you | `1` turns on the `sudo` alias, so `sudo vim` keeps the vim alias's flags                                                                                                                                                             |
| `_HI_DISABLE_LOCAL`         | `0`                                                                                                                                            | a preset, or you | turns off everything above, and the banner, **on this machine only**; targets still get hi ([Others](#others))                                                                                                                       |
| `_HI_DISABLE_PROMPT`        | `0`                                                                                                                                            | a preset, or you | turns off hi's prompt, leaving your shell's own                                                                                                                                                                                      |
| `_HI_PROMPT_TOOL`           | unset                                                                                                                                          | you              | who draws the prompt: a list of `powerlevel10k`, `oh-my-zsh`, `oh-my-bash`, `bash-it`, `tide`, `starship`, `oh-my-posh`, `powerline-go`, and `hi`; unset, every one installed here ([Integrations](INTEGRATIONS.md#prompt-programs)) |
| `_HI_PROMPT_END_BASH`       | `\$`                                                                                                                                           | you              | bash's prompt separator (`\$` is `$`, or `#` for root); also the prompt of a target without bash                                                                                                                                     |
| `_HI_PROMPT_END_ZSH`        | `%(!.#.>)`                                                                                                                                     | you              | zsh's prompt separator; zsh prompt escapes work                                                                                                                                                                                      |
| `_HI_PROMPT_END_FISH`       | `\|`                                                                                                                                           | you              | fish's prompt separator; unset, root gets `#`                                                                                                                                                                                        |
| `_HI_DISABLE_LEAD_SPACE`    | `0`                                                                                                                                            | you              | `1` drops the leading space before the prompt and each header row                                                                                                                                                                    |
| `_HI_DISABLE_RIGHT_EDGE`    | `0`                                                                                                                                            | you              | `1` drops the closing \| from every header row                                                                                                                                                                                       |
| `_HI_PLUGINS_ON`            | unset                                                                                                                                          | you              | plugins that are off by default (`hooks`, `env`, `git`) to turn on; `hi --enable-plugin` writes it ([Switching a plugin off](#switching-a-plugin-off))                                                                               |
| `_HI_PLUGINS_OFF`           | unset                                                                                                                                          | a preset, or you | plugins or files that stay home; `hi --disable-plugin` writes it ([Switching a plugin off](#switching-a-plugin-off))                                                                                                                 |
| `_HI_KEEP`                  | `0`                                                                                                                                            | you              | `1` makes every ssh connect a `--keep` one; `--no-keep` skips it once ([Integrations](INTEGRATIONS.md#terminal-multiplexers))                                                                                                        |
| `_HI_UPDATE_UNSIGNED`       | `0`                                                                                                                                            | you              | `1` lets `hi --update` take a tag it cannot verify (unsigned, an unknown key, or no gpg), saying which; a bad signature refuses either way ([Security](SECURITY.md#what-hi-does---and-deliberately-doesnt))                          |
| `_HI_PLAIN`                 | `0`                                                                                                                                            | a preset, or you | `1` makes every connect a `--plain` one, sending nothing; `--no-plain` skips it once. Most useful in a tag's file ([Settings by host tag](#settings-by-host-tag))                                                                    |
| `_HI_KEEP_TIMEOUT`          | `24h`                                                                                                                                          | you              | how long a kept session waits with nobody attached before it closes; `0` is never. Read on the target                                                                                                                                |
| `_HI_HOLD_TIMEOUT`          | `15m`                                                                                                                                          | you              | how long a dropped session's files wait for a reconnect on a target with no multiplexer; `0` holds nothing. Read on the target                                                                                                       |
| `_HI_KEEP_RETRY`            | `5m`                                                                                                                                           | you              | how long hi retries a kept session after the link drops; `0` is never                                                                                                                                                                |
| `_HI_DISABLE_KEEP`          | `0`                                                                                                                                            | you              | `1` turns kept sessions off: `--keep` and `--end` are refused, and `tmux`, `zellij`, and `screen` are the plain tools ([Integrations](INTEGRATIONS.md#terminal-multiplexers))                                                        |
| `_HI_SHELL_PREFERENCE`      | `login`                                                                                                                                        | you              | the shells a session tries, in order: `login` (your login shell on the target), `bash`, `zsh`, or `fish`; the first the target has wins. Read on the target                                                                          |
| `_HI_BACKENDS_OFF`          | unset                                                                                                                                          | you              | backends hi never asks (`docker`, `podman`, `nerdctl`, `finch`, `nomad`, `kube`), or `all` for ssh alone; `--use` still reaches one ([Compatibility](COMPATIBILITY.md#what-ships))                                                   |
| `_HI_DISABLE_CONTROLMASTER` | `0`                                                                                                                                            | you              | `1` stops hi passing ssh its `ControlMaster` options, so your ssh config decides; a connect then authenticates twice ([Security](SECURITY.md#trust-boundaries))                                                                      |
| `_HI_TRUECOLOR`             | by terminal                                                                                                                                    | you              | `1` or `0` forces or refuses 24-bit color; unset, the terminal decides ([Colors](COLORS.md))                                                                                                                                         |
| `_HI_EDITOR`                | unset                                                                                                                                          | you              | the editor a session sets as `$EDITOR`, `$VISUAL`, and `$SUDO_EDITOR`, where the target has it; unset, your own `$EDITOR`, else the first of `nvim vim micro hx helix kak nano emacs` the target has                                 |
| `_HI_POWERLINE_GO_OPTS`     | unset                                                                                                                                          | you              | extra flags for [powerline-go](https://github.com/justjanne/powerline-go) (`-modules venv,cwd,git -mode flat`)                                                                                                                       |
| `NO_COLOR`                  | unset                                                                                                                                          | you              | [the convention](https://no-color.org): any non-empty value turns off color, on targets too                                                                                                                                          |
| `_HI_LS_OPTS`               | `-F -1 -l -m --group-directories-first --smart-group` + a time format where eza answers, else `-F -l` (and `--color=auto` where `ls` takes it) | you              | the flags of the `ls`/`eza` alias; set, it replaces hi's                                                                                                                                                                             |
| `_HI_BAT_OPTS`              | `-P --tabs 2 --style changes,grid`                                                                                                             | you              | the flags of the `bat`/`batn` aliases; no `--theme`, so your bat config's theme shows                                                                                                                                                |

### Not settings

Names that look like settings but are not:

- `$_HI_HOME`, `$_HI_ROOT`, and `$_HI_CONFIG_DIR` are read **before**
  `settings.sh`, so a line there is too late: export them in your
  environment.
- `$_HI_SSH_CONFIG`, `$_HI_COLORS`, and `$_HI_PACKAGES` are recomputed on
  every load: put your file in the overlay instead.
- `$_HI_CAT_BIN`, `$_HI_BAT_BIN`, and `$_HI_LS_BIN` are the binaries the tool
  aliases resolved, for your `aliases.sh` to build on.
- `$_HI_HOST_COLOR`, `$_HI_USER_COLOR`, `$_HI_HOST_ESC`, and `$_HI_USER_ESC`
  are the resolved prompt colors, for
  [your own prompt](COLORS.md#using-the-hash-in-your-own-prompt).
- `$_HI_REMOTE_SESSION` marks a session; set by hand, it tells a shell it is
  somewhere it is not.
- `$_HI_TARGETS_TTL`, `$_HI_PROBE_TIMEOUT`, `$_HI_PAYLOAD_CACHE`,
  `$_HI_CTL_PERSIST`, `$_HI_HEADER_VERSION`, and `$_HI_WATCH_STEP` are test
  levers ([TESTING.md](TESTING.md#test-levers)), not part of the 1.x
  contract.

The rest of hi's variables are listed in
[FILES.md's _Variables hi sets_](FILES.md#variables-hi-sets).

## Settings by host tag

A file named `settings.<tag>.sh` in the overlay holds settings for the
targets carrying that tag, in `settings.sh`'s shape:

```sh
# ~/.config/say-hi/settings.prod.sh
export _HI_PLAIN=1
```

```sh
# ~/.config/say-hi/settings.dev.sh
export _HI_KEEP=1
export _HI_PLUGINS_OFF='tmux'
```

A host's tags come from its `# Tags:` or `Tag` line in `~/.ssh/config`
(`hi --add-tag` writes one) or the name of its file in `~/.ssh/config.d`
([Colors](COLORS.md)). A container, allocation, or pod carries its
backend's word (`docker`, `podman`, `nerdctl`, `finch`, `nomad`, `kube`), and
a pod its context and namespace too.

- hi reads the tag files after `settings.sh`, so their lines win; with
  several tags, the last listed wins. The target is sent one `settings.sh`
  with them joined on, so `settings.prod.sh` reaches only `prod` hosts.
- A pod reads `settings.kube.sh`, then its context's file, then its
  namespace's. The six backend words are reserved for tags.
- A tag names a file only when it is letters, digits, `_`, and `-`.
- `hi --configure` writes only `settings.sh`; write a tag's file by hand.
- A `hi` run inside a session reads none; it inherits what it was sent.
- `hi --doctor` checks every tag file, and `hi --doctor <target>` names the
  ones that target reads.

## Header details

`_HI_HEADER_ORDER` is a space-separated list of these words, in the order to
print them; `banner` always comes first and `greeting` last. Unset or empty
is the table's order. `hi --preview header` draws the result.
`_HI_DISABLE_HEADER=1` turns it all off except the greeting, and keeps your
order for when you turn it back on.

| word         | what it is                                                     |
| ------------ | -------------------------------------------------------------- |
| `banner`     | the `=== Connected [host] ===` line, on connect and disconnect |
| `utc`        | the UTC clock                                                  |
| `version`    | hi's own version                                               |
| `localtime`  | your local clock                                               |
| `os`         | the OS name/version                                            |
| `arch`       | the CPU architecture                                           |
| `cores`      | core count and load percentage                                 |
| `cpu`        | clock speed                                                    |
| `ram`        | used/total memory                                              |
| `ip`         | this box's routable IPv4 address(es)                           |
| `gitid`      | the masked git identity (`user.email`)                         |
| `containers` | the docker/podman container count, when either runs            |
| `jobs`       | the nomad job count, when nomad answers                        |
| `pods`       | the reachable kube pod count, when kubectl answers             |
| `auth`       | the `~/.ssh/authorized_keys` line count                        |
| `pub`        | the `~/.ssh/*.pub` file count                                  |
| `uptime`     | this box's uptime                                              |
| `check`      | the installed-packages check (`config/packages`)               |
| `greeting`   | a session's `hi loaded:` line and its timers, header off too   |

- A word left out is not printed; an unknown word is ignored. Your own words
  are [header cells](INTEGRATIONS.md#header-cells-of-your-own).
- `containers`, `jobs`, and `pods` ask docker, podman, nomad, and kubectl on
  every header, each capped by `_HI_PROBE_TIMEOUT`. Leave them out and none
  is started.
- No two cells side by side share a color
  ([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)).
- A line too long for `_HI_MAX_WIDTH` continues on the next, until the
  package check absorbs the rest.
- `_HI_IP_HIDE` globs match an address or its interface name. The default
  hides docker, podman, libvirt, LXD, and Incus bridges; `eth*` would also
  hide a container's own address. When every address is hidden, the cell is
  dropped.

### Others

`_HI_DISABLE_LOCAL=1` means "leave my own machine alone, but give me hi
everywhere I connect". What hi writes on your machine is
[FILES.md](FILES.md#what-hi-creates-on-this-machine).

hi's prompt sends
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
prompt and command marks and OSC 7 with the working directory, for terminals
that read them (kitty, WezTerm, ghostty, foot, iTerm2, Konsole). It sends
none on `TERM=dumb`, off a terminal, or while the terminal's own shell
integration is sending them. A prompt program hi starts gets the same marks,
except powerlevel10k and oh-my-posh, which send their own. When a session
ends badly, the client resets the terminal modes a remote program left on
([HI.53](GLOSSARY.md#hi53-terminal-reset-after-a-failed-session)).

### Shells you drop into inside a session

A `bash`, `zsh`, `fish`, or `dash` started inside a session keeps hi's
aliases, prompt, and paths, with nothing written to the target
([HI.46](GLOSSARY.md#hi46-session-rc-directory)). Two things it cannot
reach:

- **A shell nothing typed**, such as a new tmux pane or an editor's shell,
  is the host's own, since hi writes no login file. Use a
  [kept session](INTEGRATIONS.md#terminal-multiplexers) for panes that are
  hi's.
- **A change of user** (`sudo -i`, `su -`, `doas -s`) starts that user's own
  shell. `sudo <command>` keeps hi's aliases through the `sudo` alias.

hi ships no history sizing, keybindings, or shell palette. Your shell code
goes in one of three overlay files:

| file                             | dialect                                                        | sourced                                                       | an `export` reaches children |
| -------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------- |
| `aliases.sh`                     | the POSIX+fish subset: `export`, `alias`, `&&` chains, no `if` | after hi's aliases, before the prompt is built                | yes, but no `_HI_*` name     |
| `extensions/<name>`              | the same subset                                                | after `aliases.sh`, in name order ([Extensions](#extensions)) | yes, but no `_HI_*` name     |
| `bashrc`, `zshrc`, `config.fish` | that shell's own, in full                                      | last, at the end of hi's rc for that shell                    | yes                          |

The per-shell file loads last and wins, `HISTFILE` included. To take your
whole rc along, link it:

```sh
ln -s ~/.bashrc ~/.config/say-hi/bashrc
ln -s ~/.zshrc ~/.config/say-hi/zshrc
```

It then loads after hi's rc here too; hi's rc returns at once if your rc
sources it again ([HI.55](GLOSSARY.md#hi55-re-entrant-rc-guard)). Lines that
read a file the target will not have go out
[disabled](#the-editor-rcs-come-from-where-you-keep-them). The file rides
comment-stripped ([sizes](INTEGRATIONS.md#config-sizes)).

`aliases.sh` loads **after** hi's aliases, so an alias there replaces hi's
and can build on its flags:

```sh
alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"      # hi's flags, plus one
alias cat=cat                                    # this one alias back to plain
```

- `_HI_LS_OPTS`, `_HI_BAT_OPTS`, and the alias opt-ins belong in
  `settings.sh`; in `aliases.sh` they come too late, and `hi --doctor` says
  so.
- `hi --doctor` also flags an alias of yours that replaces one hi points at a
  carried config (`alias nano=...`).
- With no `aliases.sh`, your `~/.aliases` or `~/.bash_aliases` rides instead.
  fish skips a file written for bash, with a line saying so.

### Extensions

Anything hi does not do, such as another tool's init or a prompt segment of
your own, goes in a file under `~/.config/say-hi/extensions/`. Extensions use
the `aliases.sh` subset, so bash, zsh, and fish all read them. They load
after the aliases, in name order (`10-` before `20-`). One a shell cannot
parse is skipped with a warning, and `hi --doctor` flags it.

An extension talks to hi through hook variables:

- `_HI_SEGMENT`: a command run on every prompt, its output shown after the
  environment segment. Plain words only (no pipe, quote, `$( )`, or glob),
  and keep it fast.

  ```sh
  command -v kubectl >/dev/null 2>&1 &&
    export _HI_SEGMENT='kubectl config current-context'
  ```

- `_HI_PROMPT_INIT`: a prompt program's init, `{shell}` for the shell's name
  (`'oh-my-posh init {shell}'`), run in place of hi's prompt.
- `_HI_PROMPT_DRAWN=1`: the extension drew the prompt itself.

The whole contract is [HI.59](GLOSSARY.md#hi59-extensions).

### Scripts of your own

An executable script in `~/.config/say-hi/bin/` rides to every target and
runs there by name; the directory is last on `$PATH`, so it never shadows a
target's command. A file that is not executable, has no `#!` line, holds a
NUL, or is over 16384 characters stays home, and `hi --doctor` says why. It
is the `bin` plugin, so `hi --disable-plugin bin` keeps it home
([HI.58](GLOSSARY.md#hi58-overlay-directory-members)).

### Switching a plugin off

A plugin is one tool's configs that hi carries: the files, the tool that
reads them, and how the tool finds them on a target. `hi --plugins` lists
them, with where each file was found and whether it rides:

```text
 ------------------------------------  cli  ------------------------------------
+---+------------------------------+--------------------------------+
| + | bat/config (bat)             | used ~/.config/bat/config      |
|   | lazygit/config.yml (lazygit) | switched off (_HI_PLUGINS_OFF) |
|   | none anywhere                | eza/ ripgreprc fzfrc inputrc   |
+---+------------------------------+--------------------------------+
```

- `hi --disable-plugin lazygit` keeps it home (in `_HI_PLUGINS_OFF`), and
  `hi --enable-plugin lazygit` lets it ride again.
- Plugins off by default (`hooks`, `env`, `git`) turn on through
  `_HI_PLUGINS_ON`, which the same two commands edit.
- A name is a plugin, a file (`bat/config`), or one file of a directory
  (`extensions/10-kube`).
- What is off sends nothing, overlay copy included, so the target's tool
  keeps its own config. At home, every tool reads its own config whatever
  the list says.
- hi's own files (`settings.sh`, `colors`, `packages`) always ride.
- An editor that is off is not used for `$EDITOR` on a target.

### Shell hooks

A plugin with an `init` runs its tool's shell hook on a target that has the
tool, after the aliases and extensions. zoxide, atuin, direnv, and mise ship
in the `hooks` group, off by default because each keeps state under the
target's `$HOME`. `hi --enable-plugin zoxide` turns one on. A hook of your
own is one table of your `plugins` file (`hi --edit plugins`):

```toml
[hooks.fnm]
init = "fnm env --use-on-cd --shell {shell}"
default = "off"
```

`shells = "zsh fish"` limits it to those shells, and `quiet = "yes"` hides
what it prints as it starts. The mechanism is
[HI.67](GLOSSARY.md#hi67-shell-hooks).

### Variables that ride

A plugin's `env` names variables whose values on your machine a session
exports: `$LESS`, `$LS_COLORS`, and the like. The shipped `env` plugin names
the pager and color variables and is off by default:

```sh
hi --enable-plugin env
```

An unset variable sends nothing. A value with a quote, backslash, or line
break stays home, and so does a name that looks secret (`*TOKEN*`,
`*SECRET*`, `*PASSWORD*`, `*_KEY`). Your own variables are a table of your
`plugins`:

```toml
[shell.mine]
env = "PAGER MANROFFOPT TZ"
```

### A tool hi does not know

Every config hi carries belongs to a plugin in the tree's `config/plugins`.
For a tool hi does not know, add a plugin to `~/.config/say-hi/plugins`
(`hi --edit plugins`). A plugin there with a tree plugin's name replaces it;
one with no `files` keeps the tree's files, so it can change just a hook's
`init` or `shells`.

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

- **group**, the table's first name: the section `hi --plugins` lists it
  under, one of hi's (`editors`, `mux`, `prompt`, `cli`, `shell`, `hooks`) or
  your own.
- **name**, the second: the plugin's word for `--disable-plugin`. Letters,
  digits, `_`, and `-`.
- **files**: the members, space-separated, each the name it rides under
  (`vim/vimrc`), or a directory whose files ride one by one
  (`zellij/layouts/`). An overlay file of that name rides instead of home's.
- **tool**: the command, or commands, that read them; home's copy rides only
  if one is installed here. Default: the plugin's name; `-` checks nothing.
- **wire**: how the target's tool finds the file. `env:VAR` sets a variable
  to its path (`NAME=word` sets it to a word), `envdir:VAR` to its directory,
  `flag:cmd --flag` aliases the command with the path (`flagdir:` for the
  directory; `--rc=` takes the path in the same word), and `xdg:cmd` points
  `$XDG_CONFIG_HOME` at the overlay
  ([a last resort](INTEGRATIONS.md#a-tool-with-no-variable-and-no-flag)).
  Several wires go `;` apart. Leave it empty when your own extension points
  at `$_HI_CONFIG_DIR/<member>`.
- **home**: where the file is on this machine, candidates `:` apart, first
  found wins. Each starts at `/`, `~/`, or a variable (skipped while unset);
  `,` between candidates means "the first not skipped", as a tool checks its
  variable before its default. A trailing `/` is a directory. Nothing else
  expands or runs.
- **dialect**: left out, the file rides as written. Named (`sh`, `fish`,
  `vim`, `lua`, `elisp`, `nano`, `tmux`, `screen`, `readline`, `kak`, `kdl`,
  `omp`, `omp-json`, `conf`), comments are stripped and includes are
  [checked](#the-editor-rcs-come-from-where-you-keep-them).
- **init**: the tool's shell hook, `{shell}` for the shell's name
  (`zoxide init {shell}`). Plain words only. A plugin with an init needs no
  **files**.
- **prompt** = `yes`: the init draws the prompt, so the plugin joins
  `_HI_PROMPT_TOOL`'s list ([Integrations](INTEGRATIONS.md#prompt-programs)).
- **shells**: the shells the init runs in; default all three.
- **quiet** = `yes`: hides what the init prints as a shell starts.
- **env**: variables to send ([above](#variables-that-ride)). Needs no
  **files**.
- **default** = `off`: stays home until `hi --enable-plugin <name>`.

A file whose wire, home, or dialect differs from its plugin's gets its own
table, `[<group>.<name>."<member>"]`, with just the keys that differ; a wire
of `-` gives it none. `hi --plugins` and `hi --doctor` name each file a
plugin carries and each line they could not read. The whole contract is
[HI.63](GLOSSARY.md#hi63-plugins-rows).

### The TOML hi reads

`colors`, `packages`, and `plugins` use this much of TOML:

- a table header on its own line: `[a]`, `[a.b]`, or `[a.b."file"]`, quoting
  a name with anything but letters, digits, `_`, and `-`;
- a row on one line, `key = "string"` or `key = ["string", ...]`; anything
  after the closing `"` or `]` (a comment) is ignored;
- `#` comment lines and blank lines.

Nothing else: no multi-line arrays, inline tables, numbers, booleans, dates,
dotted keys, single-quoted strings, or escapes (a `\` is a backslash). Each
file's tables and rows are in [COLORS.md](COLORS.md) (`colors`, and
`packages` under [the package check](COLORS.md#the-package-checks-rows)) and
[above](#a-tool-hi-does-not-know) (`plugins`). A line outside the subset is
skipped, and `hi --doctor` names it.

## The editor rcs come from where you keep them

hi carries the config each tool **already reads on this machine**, so there
is one copy to edit; [FILES.md](FILES.md#configs-read-from-where-their-tool-keeps-them)
lists where it looks for each. An overlay copy still wins, which is how you
give targets a different config. With neither, the tool on the target uses
its own. On a target the aliases (`vim`, `nvim`, `hx`, `nano`, `emacs`,
`micro`, `tmux`, `screen`, `zellij`) point at the file that rode; at home
nothing is aliased.

**Lines that need a file the target lacks.** Your config is written for a
machine with your plugins, and a target has none. hi reads every carried
file for includes (vim's `source`, lua's `require`, tmux's `source-file`,
TPM, a shell's `source` of a file outside the overlay, plugin manager
bootstraps, and the like) and disables them on the way out; `hi --doctor`
names each by file and line. An include of a file in the tool's own
directory (`source-file ~/.config/tmux/theme.conf`) is carried instead, and
so is a neovim `require` of a module under its `lua/`
([HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan)).

A comment on the line above, in the file's own syntax (`# hi-allow`, or
`" hi-allow` in vim), changes what happens to that line:

| comment    | the line                                                           | `hi --doctor` |
| ---------- | ------------------------------------------------------------------ | ------------- |
| `hi-allow` | is sent as written, for a file every target has                    | silent        |
| `hi-quiet` | is dropped                                                         | silent        |
| `hi-carry` | is sent pointing at a copy of each file under your home it names   | names a miss  |
| `hi-drop`  | is dropped whatever it says, for a setting older tools cannot read | silent        |

Each also comes as a `-start`/`-end` pair for a block; a start with no end
does nothing and `hi --doctor` names it.

```vim
" hi-quiet-start
call plug#begin()
Plug 'tpope/vim-surround'
call plug#end()
" hi-quiet-end
```

```sh
# hi-carry
--ignore-file=/home/you/.config/fd/ignore
```

There is no switch that sends every line.

## Keeping the overlay in a dotfile manager

The overlay is a **plain directory of plain files**, so pointing chezmoi,
yadm, Stow, or a bare `$HOME` repo at `~/.config/say-hi` is the whole
integration.

- **Symlinks are fine.** hi sends the real contents, so Stow works.
- **Only overlay files travel.** Your manager's metadata, a `.git`, and swap
  files stay home (`tests/hi/payload_overlay_test.sh` checks both).
- **The rc lines can be the manager's too.** `hi --install` writes into the
  deployed `~/.bashrc`, which the manager's next apply removes. Instead,
  `hi --install --print-rc` prints each shell's block for the manager's copy.
  The block finds a clone, a package, or a Homebrew install, and does nothing
  on a machine without say-hi.
- **Pick one owner for `settings.sh`.** `hi --configure` writes the live
  file. Either leave it out of the manager, or run the manager's re-add
  (`chezmoi re-add ~/.config/say-hi/settings.sh`) after each
  `hi --configure`.
