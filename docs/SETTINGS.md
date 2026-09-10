# Settings

Your config lives **outside the checkout**, in
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` (`$_HI_CONFIG_DIR`), so `git pull`
applies cleanly and the tree can be root-owned or package-installed. `colors`
and `packages` there override the tree's copies one file at a time.
`settings.sh` has no in-tree counterpart; `hi --configure` only ever writes it
here. The tree's own `settings/` directory holds the shipped defaults. All of
it rides along to every host you say `hi` to, in its own small archive.

| overlay file                       | overrides           | what it is                                                                                                                                    |
| ---------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.config/say-hi/settings.sh`     | -                   | what `hi --configure` writes                                                                                                                  |
| `~/.config/say-hi/colors`          | `settings/colors`   | your color pins                                                                                                                               |
| `~/.config/say-hi/packages`        | `settings/packages` | what the package check looks for                                                                                                              |
| `~/.config/say-hi/vim.rc`          | `settings/vim.rc`   | your vim config, used by the `vim` alias and `$VIMINIT` - replaces hi's default wholesale                                                     |
| `~/.config/say-hi/nano.rc`         | `settings/nano.rc`  | the same for nano, used by the `nano` alias                                                                                                   |
| `~/.config/say-hi/emacs.el`        | `settings/emacs.el` | the same for emacs, used by the `emacs` alias (`emacs -q -l`)                                                                                 |
| `~/.config/say-hi/helix.toml`      | `settings/helix.toml` | the same for helix, used by the `hx` alias (`hx -c`)                                                                                        |
| `~/.config/say-hi/kak.rc`          | `settings/kak.rc`   | kakoune additions, sourced by the `kak` alias **after** the target's own kakrc (`kak -e`); micro takes no file - see `_HI_MICRO_OPTS` below   |
| `~/.config/say-hi/aliases.sh`      | -                   | your own flags and aliases, sourced **first** so your `_HI_*_OPTS`/toggles land before the shipped aliases are built - same POSIX+fish subset |
| `~/.config/say-hi/bash.sh`         | -                   | your bash preferences, sourced at the end of `common/bash.sh` - history sizing, `shopt`s, readline bindings                                   |
| `~/.config/say-hi/zsh.zsh`         | -                   | the same for zsh - history, keybindings, `zstyle` completion rules                                                                            |
| `~/.config/say-hi/config.fish`     | -                   | the same for fish - keybindings and the `fish_color_*` / `fish_pager_color_*` palette                                                         |
| `~/.config/say-hi/starship.toml`   | -                   | your starship config, `$STARSHIP_CONFIG` on every target when `_HI_PROMPT_TOOL=starship`; at home starship keeps reading its own                   |
| `~/.config/say-hi/oh-my-posh.json` | -                   | the same for oh-my-posh (`$POSH_THEME`) when `_HI_PROMPT_TOOL=oh-my-posh`                                                                          |
| `~/.config/say-hi/theme.yml`       | -                   | your [eza theme](https://github.com/eza-community/eza-themes): the overlay becomes `$EZA_CONFIG_DIR` on every target, so the `eza` alias colors files there the way it does at home                     |

**Shipping your eza theme.** eza reads its colors from `$EZA_CONFIG_DIR/theme.yml`
and insists on that file name, so hi does not rename it: drop a `theme.yml`
into the overlay and, on a target, `common/paths.sh` exports
`EZA_CONFIG_DIR` pointing at the overlay's shipped copy - the directory
itself, not the file. At home the variable is left alone and eza keeps reading
`~/.config/eza/theme.yml`. To ship the theme you already use, link it rather
than copy it - the overlay archive resolves symlinks into content, so one
file serves both:

```sh
ln -s ~/.config/eza/theme.yml ~/.config/say-hi/theme.yml
```

The file rides only when present, like every overlay member, and only the
`eza` alias (`_HI_DISABLE_TOOL_ALIASES`) is affected: a bare `command eza` on
the target reads the same variable, so it matches too.

`hi --install` seeds the overlay with the shipped
`colors`/`packages` and editor rc defaults — only for the
files you have none of, so after a normal install all seven are yours. A seeded copy stops
tracking what `hi --update` delivers for that file; delete it from the overlay
to track the tree's again. Versioning the directory is yours to do — a
`git init` there, or
[a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager).

Every setting below is an environment variable, checked where it is used.
`hi --configure` writes your answers to `settings.sh` — a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh and fish — which
every shell sources ahead of `common/paths.sh`. Exporting one by hand works
too and takes precedence for that shell. It does not reach programs started
from a hi shell: once the rc has run, every `_HI_*` name except six is a
plain shell variable ([HI.47](GLOSSARY.md#hi47-what-a-child-inherits) says
which, and why). A setting a child must see is an `export` in
[your own `bash.sh`/`zsh.zsh`/`config.fish`](#shells-you-drop-into-inside-a-session).

## Contents

- [The wizard](#the-wizard)
- [Presets](#presets)
- [How it works](#how-it-works)
- [Every setting](#every-setting)
  - [Not settings](#not-settings)
- [Header details](#header-details)
  - [Others](#others)
  - [Shells you drop into inside a session](#shells-you-drop-into-inside-a-session)
- [Keeping the overlay in a dotfile manager](#keeping-the-overlay-in-a-dotfile-manager)
- [Colors](#colors)
  - [The package check's ramp](#the-package-checks-ramp)
  - [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)

## The wizard

`hi --configure` opens on a preview — the header as it would print and the
prompt line as it would draw, at your current settings — over a short menu:

1. **Preset** — `[e]verything`, `[b]alanced` or `[m]inimal`, below.
2. **Header** — the editor for everything in [Header details](#header-details):
   the real header rendered above a numbered list of the banner and every
   item; a number toggles one, `up N`/`down N` moves it, `[p]` loads a header
   preset (`[f]ull`, `[c]ompact`, `[q]uiet`), and the width and the package
   check's depth live there too. Outside the menu,
   `hi --preview header` prints the header as it would draw at the saved
   settings, and `hi --preview packages` the check's legend.
3. **Features** — the `_HI_DISABLE_*` toggles in [Every setting](#every-setting),
   each previewed as it flips.
4. **Prompt** — starship, and the character each shell's prompt ends with.
5. **Advanced** — the _advanced_ rows, as a short walk of two questions: the
   leading space, then 24-bit color.
The wizard does not ask about colors: `_HI_COLOR_SCHEME` and
`_HI_PACKAGES_PALETTE` are both written into `settings.sh` by hand — see
[Colors](#colors) — and it keeps whatever they hold.

Every option is typed by its number or by the letter shown in brackets, and
every section returns to the menu with the preview re-rendered. `[s]` writes
the settings once, `[q]` leaves `settings.sh` untouched, and nothing is
written before either. End of input at the menu counts as `[s]`; three answers
in a row that are not menu items count as `[q]`; with no terminal
(`hi --configure </dev/null`, a script) there is no menu at all — the file is
written back as it stands, and none is created when there is nothing to say.
A line you wrote into `settings.sh`
by hand is adopted into hi's block the next time the wizard writes that
setting, never duplicated beside it.

## Presets

The menu's first item, and `hi --configure --preset <name>` applies one
without the menu:

| preset       | what it answers                                                                                                                                           |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `everything` | every feature and every header item on — the shipped defaults                                                                                             |
| `balanced`   | everything but the noise: a shorter package check (`_HI_PACKAGES_MIN_PRIORITY=3`)                                                                         |
| `minimal`    | on targets only the colored prompt and the aliases: no header, git status, editors or prompt marks — and nothing on this machine (`_HI_DISABLE_LOCAL=1`). |

A preset is an absolute answer over the feature and header settings: what it
names is set, everything else in that vocabulary returns to its default, and
the header order, the width, the package check's ramp, the hidden
addresses, the color scheme, the prompt separators, the starship choice and
the advanced settings keep what they hold. From the menu its answers are only
what the preview shows until `[s]` saves them. The rows are
`scripts/configure.sh`'s `_HI_PRESETS`; the header editor's own presets are
`_HI_HEADER_PRESETS` beside them.

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
   the way in (about 40% of it).
3. That assembled script is the size `hi` prints on connect and what the
   payload badge measures; an overlay only adds to it. It is the
   per-session wire cost, not the package badge beside it, which is what a
   release downloads (`scripts/` and the docs ship in a package, never over
   the wire).
4. On the target, `load.sh` prints the header, writes hi's per-shell rc files
   into a scratch directory of its own
   ([HI.46](GLOSSARY.md#hi46-session-rc-directory)) - never the target's own
   login files - and drops you into **your login shell** when hi styles it
   (bash, zsh, fish), else the best the target has of hi's shell tree
   (`fish > zsh > bash > dash > ash > sh`). With no bash at all the choice
   comes from the same list without bash (the ladder).
5. On exit, `load.sh`'s on-exit hook removes the `/tmp` directory and the
   scratch rc directory. It runs on `SIGHUP` too, so a dropped connection
   cleans up the same way, with nothing left to reconnect to. Run `hi` inside
   `tmux` or `screen` on the _client_ to survive drops - `hi --mux <target>`
   does that step for you and reattaches on the next connect, and
   `alias hi='hi --mux'` makes that the default (`--no-mux` skips it once);
   persistent sessions on the target were
   [decided against](SUPPORT.md#what-would-change-an-answer).
6. `hi <target> 'some command'` runs the command inside that same session -
   hi's aliases and environment, a pty when your stdin is one - and prints
   only its output; a plain, pty-free remote command is `ssh`'s job.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session in the best plain shell it has, aliases loaded. Every ssh target gets
the tree shipped to it, whether or not that machine has a say-hi of its own:
an install there is for that machine's own shells, and a session neither reads
nor touches it. `hi --doctor` prints the wire size and the unpacked size,
labeled.

## Every setting

The whole vocabulary a `settings.sh` may use, in the order `hi --configure`
writes it; the linked sections are the explanations. The **set by** column:

- **you** — supported surface nothing asks about: export it, or write an
  `export` line into `settings.sh` by hand.
- **`hi --configure`** — the same, with a menu item attached; the only
  variables the wizard asks about (a non-default value it finds in
  `settings.sh` for any other row is carried over, never dropped). **advanced** marks the ones behind the menu's
  _Advanced_ item: a run that never opens it keeps whatever they hold.

The lint group checks `common/core.sh`'s `_HI_TOGGLES` and
`scripts/configure.sh`'s prompt rosters against this table, so a new setting
cannot land without a row here.

| variable                    | default                                              | set by                    | what it does                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------- | ---------------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`        | `0`                                                  | `hi --configure`          | turns off the whole connect/disconnect header, every line of it                                                                                                                                                                                                                                                                                                  |
| `_HI_DISABLE_PROMPT`        | `0`                                                  | `hi --configure`          | turns off the colored `user@host` prompt, leaving your shell's own                                                                                                                                                                                                                                                                                               |
| `_HI_DISABLE_GIT_STATUS`    | `0`                                                  | `hi --configure`          | turns off the git segment in the prompt                                                                                                                                                                                                                                                                                                                          |
| `_HI_DISABLE_ENV_STATUS`    | `0`                                                  | `hi --configure`          | turns off the environment segment in the prompt - the leading `(myproj)` naming whatever venv, conda, direnv, nix, guix, devbox or version-manager environment is active. See [Others](#others)                                                                                                                                                                  |
| `_HI_DISABLE_EDITORS`       | `0`                                                  | `hi --configure`          | turns off the `vim`/`nano` config overrides                                                                                                                                                                                                                                                                                                                      |
| `_HI_DISABLE_TOOL_ALIASES`  | `0`                                                  | `hi --configure`          | turns off the styled tool aliases: the `cat`/`catn` rebind to `bat` and the `exa`/`eza` wrappers - `bat`/`batcat`/`batn`, `exa` and `eza` themselves stay available by name either way                                                                                                                                                                           |
| `_HI_DISABLE_MARKS`         | `0`                                                  | `hi --configure`          | turns off the semantic prompt marks (OSC 133) and cwd reporting (OSC 7) every prompt emits. See [Others](#others)                                                                                                                                                                                                                                                |
| `_HI_DISABLE_LOCAL`         | `0`                                                  | `hi --configure`          | turns off all of the above **on this machine only** - hi still styles the hosts you visit ([Others](#others) says how it tells the two apart)                                                                                                                                                                                                                                                                        |
| `_HI_DISABLE_BANNER`        | `0`                                                  | `hi --configure`          | [Header details](#header-details) - the `~~~ Connected ~~~` line                                                                                                                                                                                                                                                                                                 |
| `_HI_HEADER_ORDER`          | see [Header details](#header-details)                | `hi --configure`          | [Header details](#header-details) - which header features show, and in what order An empty value is not a way to spell "none": it falls back to the default list, so use the disable toggle for that. |
| `_HI_ENV_ORDER`             | `see [Others](#others)`                              | you                       | which environments the prompt's `(myproj)` segment names, and in what order: space-separated words from `mise asdf pyenv rbenv nodenv nix guix devbox devenv direnv conda venv`. Every one, outermost first, is the default; drop a word to silence it. See [Others](#others) An empty value is not a way to spell "none": it falls back to the default list, so use the disable toggle for that. |
| `_HI_PACKAGES_MIN_PRIORITY` | `2`                                                  | `hi --configure`          | the lowest `settings/packages` priority (0-3) the header's check prints, and the main dial on how long that check is. `2` (default) keeps useful tools and up, `1` adds the optional extras back, `0` prints everything, `3` leaves just favorites and core alerts, `4` (above every priority) turns the check off. `hi --preview packages` marks the ranks it silences `below floor`    |
| `_HI_PACKAGES_PALETTE`      | unset                                                | you                       | the color the check paints each priority in: eight color names, four for installed then four for missing. Unset is the shipped ramp (`cyan green brcyan brgreen` installed, `blue magenta bryellow brred` missing); anything that is not eight names falls back to it. See [Colors](#colors), and judge one with `hi --preview packages`                                                               |
| `_HI_COLOR_SCHEME`          | unset                                                | you                       | what the palette names render as on a terminal that reports 24-bit color: twenty-four or forty-eight six-digit hex words. Unset is the terminal's own sixteen colors. See [Colors](#colors) for the word count and order                                                                                                                                         |
| `_HI_IP_HIDE`               | `172.*`                                              | `hi --configure`          | space-separated globs; the header's `ip` cell drops every address one matches. `none` hides nothing; an empty value counts as unset. See [Header details](#header-details)                                                                                                                                                                                       |
| `_HI_MAX_WIDTH`             | `80`                                                 | `hi --configure`          | terminal columns the header and banner are drawn to, narrowed to a smaller real terminal; 40 is the least the wizard takes                                                                                                                                                                                                                                       |
| `_HI_PROMPT_TOOL`                | unset                                                | `hi --configure`          | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, `oh-my-posh` to [oh-my-posh](https://ohmyposh.dev) (by hand; the menu offers starship), keeping hi's header and aliases either way. A `starship.toml` / `oh-my-posh.json` in the overlay becomes the tool's config on every target. Never auto-detected; hi ships neither |
| `_HI_PROMPT_END_BASH`       | `\$`                                                 | `hi --configure`          | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root"); also the plain `sh` prompt hi bakes on the client for a bash-less target                                                                                                                                                                                                         |
| `_HI_PROMPT_END_ZSH`        | `>`                                                  | `hi --configure`          | zsh's prompt separator - zsh prompt escapes work, so `%#` behaves as anywhere else in `PS1`                                                                                                                                                                                                                                                                      |
| `_HI_PROMPT_END_FISH`       | `\|`                                                 | `hi --configure`          | fish's prompt separator; root still gets `#` regardless                                                                                                                                                                                                                                                                                                          |
| `_HI_DISABLE_LEAD_SPACE`         | `0`                                                  | `hi --configure` advanced | `1` drops the hardcoded leading space before the prompt's `user@host`, the git segment, the banner line, and the first cell of every header row                                                                                                                                                                                                                  |
| `_HI_TRUECOLOR`             | by terminal                                          | `hi --configure` advanced | `1`/`0`: does the terminal render 24-bit color. Unset, the client decides and ships the verdict to the session; see [Colors](#colors). The Advanced walk asks it as auto/on/off, and is the only free-text question in it                                                                                                                                                              |
| `NO_COLOR`                  | unset                                                | you                       | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything without color, shipped to the target next to [`_HI_ASCII`](#not-settings)                                                                                                                                                                                                    |
| `_HI_BAT_OPTS`              | `-P --tabs 2`, the Monokai Extended Bright theme, `changes,grid` style | you                       | the flags the `bat`/`batn` aliases attach, set in your `aliases.sh` ahead of the tree's own                                                                                                                                                                                                                                                                      |
| `_HI_EXA_OPTS`              | `-F -1 -l -m --group-directories-first --group --no-filesize`         | you                       | the `exa` alias's flags (its predecessor's column set)                                                                                                                                                                                                                                                                                                           |
| `_HI_EZA_OPTS`              | the same leading flags + smart-group + a time format | you                       | the `eza` alias's flags                                                                                                                                                                                                                                                                                                                                          |
| `_HI_MICRO_OPTS`            | `-backup false -savehistory false -mkparents true -diffgutter true` | you            | the `micro` alias's flags - micro takes settings on the command line rather than a config file, so this is its whole override; behind `_HI_DISABLE_EDITORS`                                                                                                                                                                                                  |
| `_HI_CAT_BIN`            | first of `bat`, `batcat`, `ccat`, `cat` on PATH      | you                       | which binary the `bat` and `cat` aliases run (Debian ships bat as `batcat`; the tail keeps `cat` working where none is installed). From `settings.sh` or the environment only: `settings/aliases.sh` resolves it above the overlay `aliases.sh` source, unlike the `_OPTS` above                                                                                 |
| `_HI_BAT_BIN`              | first of `bat`, `batcat` on PATH                     | you                       | the bat-only tier behind it, what parses `_HI_BAT_OPTS` - two rungs shorter on purpose; set with it, or leave both alone                                                                                                                                                                                                                                         |
| `_HI_EXA_BIN`               | first of `exa`, `eza`, `ls` on PATH                  | you                       | which binary the `exa` alias runs; the same `settings.sh`-or-environment rule                                                                                                                                                                                                                                                                                    |
| `_HI_EZA_BIN`               | first of `eza`, `exa`, `ls` on PATH                  | you                       | which binary the `eza` alias runs; likewise                                                                                                                                                                                                                                                                                                                      |

### Not settings

More names look like settings and are not:

- `$_HI_CONFIG_DIR` and `$_HI_HOME` (the **parent** of your `say-hi`
  directory - everything resolves `$_HI_HOME/say-hi`) are read **before**
  `settings.sh` is sourced, so a line there is too late. Export them in your
  environment, as `hi.sh` and `install.sh`'s rc line do; unset, each entry
  point derives `$_HI_HOME` from its own path.
- `$_HI_ROOT`, `$_HI_SSH_CONFIG` (where ssh hosts and their `# Tags:`
  comments are read from), `$_HI_COLORS`, `$_HI_PACKAGES`, `$_HI_VIMRC`,
  `$_HI_NANORC`, `$_HI_EMACSRC`, `$_HI_HELIXRC` and `$_HI_KAKRC` are derived
  from those two by `common/paths.sh` on every source - all but the first two resolving to the overlay's copy when you have one,
  else the tree's - so an exported value does not survive. Point `$_HI_HOME`
  or `$HOME` elsewhere, or put your file in the overlay.
- `$_HI_ASCII` is the *client's* verdict on whether its terminal renders
  multibyte glyphs, taken from the locale and shipped to the session next to
  `$NO_COLOR` - the glyphs land in the terminal you are sitting at, not in the
  target's. There is no question for it and no row above: a target whose own
  `LANG` is `C` still shows glyphs when your terminal does, which is the whole
  point of shipping it.
- `$_HI_REMOTE_SESSION` is hi's own "this is a session" mark: `load.sh`
  exports it as `1` on a target and no local rc ever does, and it is what
  the local-only toggle above reads to tell local from remote. Writing it into
  `settings.sh` tells every shell it is somewhere it is not.
- Five test levers - `_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT`,
  `_HI_PAYLOAD_CACHE`, `_HI_CTL_PERSIST` and `_HI_HEADER_VERSION` - take
  effect from `settings.sh` or the environment like any row above, but exist
  for the suites, the bench and the demos to pin what a real run derives:
  [TESTING.md's _Test levers_](TESTING.md#test-levers) says what each does.
  They are not part of the 1.x contract and may change in a minor.
- `$_HI_RELEASE` is the version `packaging/stamp.sh` stamps at build time,
  and `$_HI_SESSION_RC` the `mktemp -d` holding a session's per-shell rc
  files ([HI.46](GLOSSARY.md#hi46-session-rc-directory)).
- Eight are hi's own per-session facts, set from the client:
  `$_HI_TARGET_COLOR` and `$_HI_TARGET_TAG` (the color and `# Tags:` value
  the target resolved to), `$_HI_LOCAL_USER` and `$_HI_LOCAL_HOSTNAME` (the
  header's "from" half), and
  `$_HI_HOST_COLOR`/`$_HI_USER_COLOR`/`$_HI_HOST_ESC`/`$_HI_USER_ESC`, the
  resolved prompt colors for
  [your own prompt](#using-the-hash-in-your-own-prompt) to read. Setting one
  by hand tells the target something untrue about where it is.

Everything else beginning `_HI_` is internal state, named that way to stay
out of your namespace.

## Header details

`_HI_DISABLE_BANNER` (default `0`, `1` hides it) controls the
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

### Others

`_HI_DISABLE_LOCAL` is "leave my own machine alone, but give me hi everywhere I
connect to". A real session is told apart by `_HI_REMOTE_SESSION`, which
`load.sh` exports on a target and a local rc never does.

A prompt of your own on this machine (starship, powerlevel10k, oh-my-zsh) is
`_HI_PROMPT_TOOL=starship` for a starship user - hi hands the prompt to it wherever
it is installed - and `_HI_DISABLE_LOCAL=1` for the rest.

Two things hi does write on your own machine outside `~/.config/say-hi/`: the
rc lines `install.sh` adds (marker-tagged, with a one-time `.hi-orig` backup,
removed by `hi --uninstall`), and, in fish, three universal variables that
memoize your prompt colors so only the first shell after a `colors` change
pays for the bash call.

The prompt's leading `(myproj)` names every environment manager that is
active, outermost first: `(mise|direnv:proj|myproj)` is mise activated, a
direnv-loaded `proj`, and a venv inside it. It reads `$MISE_SHELL`,
`$ASDF_DIR`, `$PYENV_VERSION`/`$RBENV_VERSION`/`$NODENV_VERSION`,
`$IN_NIX_SHELL`, `$GUIX_ENVIRONMENT`, `$DEVBOX_SHELL_ENABLED`,
`$DEVENV_ROOT`, `$DIRENV_DIR`, `$CONDA_DEFAULT_ENV` and
`$VIRTUAL_ENV_PROMPT`/`$VIRTUAL_ENV` - variables the tools export, so a draw
costs no probe and no fork. A `.venv` is named for the directory holding it,
not for itself. `_HI_ENV_ORDER` reorders the list or drops words from it, and
`_HI_DISABLE_ENV_STATUS=1` turns the whole segment off.

hi stands down for a tool already drawing its own prefix, so nothing appears
twice: a `source .venv/bin/activate` keeps its own `(myproj)` in zsh and fish,
where the shell holds on to the prompt the activate script edited. bash is the
exception - hi rebuilds `$PS1` on every draw, so the activate script's prefix
cannot survive there and hi draws the segment itself. The upshot is that a
venv is named in all three shells, in the venv's styling under zsh and fish
and in hi's under bash; direnv, nix and the rest have no prefix of their own
and are always hi's.

To get hi's styling and naming everywhere instead, silence the tool's own
prefix the way the tool documents: `VIRTUAL_ENV_DISABLE_PROMPT=1` for a venv
(`export` it before you activate) and `conda config --set changeps1 false`.
With no prefix of its own on screen, hi draws the segment in every shell -
which is also how a `.venv` stops reading as `(.venv)`, since a venv names
itself after its own directory and hi names it after the project holding it.
hi never sets those two for you: they are your setting, and every other shell
and prompt you open reads them too.

`_HI_DISABLE_MARKS` turns off the two escapes every hi prompt emits for
terminals that read them — kitty, WezTerm, ghostty, foot, iTerm2, Konsole:
[OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
marks where each prompt, command and output begins, and OSC 7 reports the
working directory. A terminal that does not know an OSC drops it; only the
styled shells emit them, not the bash-less `sh` prompt. When the session
ends, `load.sh` sends the closing "command finished" mark the shell's own
`exit` never gets to — without it Konsole stays inside that last command and
sends ↑ as ← until the next prompt mark arrives. A session that ends any
other way (a dropped link, a refused connect) gets the same mark from the
client side, along with a reset of the terminal modes a remote program may
have left on: cursor-key and keypad modes, bracketed paste, the kitty keyboard
protocol, the alternate screen, a hidden cursor, and `stty sane`.

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

Two things no wrapper reaches. A bash or fish shell nothing typed - a `tmux`
pane spawning a login shell, an editor shelling out - comes up as the host's
own, because hi writes to no login file on any host you visit, under any
setting ([SUPPORT.md](SUPPORT.md#what-would-change-an-answer) has the
reasoning). Nor does a change of user: `sudo -i`, `sudo -s`, `su -` and
`doas -s` start _that_ user's login shell from _that_ user's rc files, and
root's `.bashrc` is not hi's to touch either. What survives is
`sudo <command>` — `settings/aliases.sh` wraps `sudo` so hi's aliases expand
in the one command it runs, and nothing past it.

hi ships nobody's shell preferences — no history sizing, keybindings, `zstyle`
rules or fish palette. Each rc carries the prompt, the completions and the git
segment, which are the product. Your own `bash.sh`, `zsh.zsh` or `config.fish`
in the config directory is sourced at the end of hi's, in the same dialect,
and wins - `HISTFILE` included; hi sets none. Your `aliases.sh` instead loads
**before** `settings/aliases.sh` (`sudo`, the `cat`/`bat` and `ls`/`eza`
families), so a `_HI_*_OPTS` value or `_HI_DISABLE_*` toggle set there wins
but an `alias` of the same name does not - the shipped one is defined after
and overwrites it. Turn the shipped families off with `_HI_DISABLE_TOOL_ALIASES`
and define your own instead.

## Keeping the overlay in a dotfile manager

There is no say-hi plugin for chezmoi, yadm, GNU Stow or a bare `$HOME` repo,
and there should not be: the overlay is a **plain directory of plain files**,
so pointing your tool at `~/.config/say-hi` is the whole integration. The
three properties below are pinned by `tests/hi/payload_test.sh`.

**Symlinks are fine, so Stow works.** hi dereferences on the way out, so a
target receives real file contents — a symlink per file, or the whole `say-hi`
directory as one link.

**Nothing but the overlay files travels.** `$_HI_OVERLAY_FILES` is an allow
list, so your manager's metadata (`.chezmoiignore`, templates), a `.git` of
your own, editor swap files and anything private sharing that directory stay
on your machine.

**Pick one keeper for the files a manager owns.** `hi --configure` writes
`settings.sh` in the **live** directory; if your manager also owns it, the two
drift. Either let hi own `settings.sh` (exclude it from the manager), or keep
it managed and run the manager's re-add step
(`chezmoi re-add ~/.config/say-hi/settings.sh`) after each `hi --configure`.
Per-file managers leave what they do not own alone, so a partly-managed
directory is normal.

## Colors

Every username and hostname resolves to a color derived from its own name, so
an unpinned host looks the same from every machine you say `hi` from. Pin the
ones that matter in `~/.config/say-hi/colors`: `username,root,red`,
`hostname,bastion,yellow`, or `hosttag,prod,red` to color every host carrying a
`# Tags: prod` comment above its `Host` or `Match host` line in
`~/.ssh/config` — a wildcard block (`Host prod-*`) colors every name it covers.
A fourth kind, `usertag,prod,red`, colors the _username_ on every host that
carries that tag, so `you@prod-db` reads as prod on both halves. A
`hostname` row whose name holds `*` or `?` is a pattern:
`hostname,10.0.1.*,red` or `hostname,*.prod.example.com,red` colors a whole
subnet or domain at once, no ssh-config entry needed — the first matching
pattern in the file wins. Precedence, highest first: an exact pin, then a
hosttag, then a pattern, then the hash; a pin always beats the hash.

Any of those rows takes an optional fourth column, that pin's own 24-bit
color as six hex digits (a leading `#` is fine):
`hostname,prod-db,brred,ff5f5f` renders `prod-db` in exactly that red on a
truecolor terminal. The third column is still a name from the vocabulary
below and is what a 16-color terminal gets, so name the nearest one. A
fourth column outranks `_HI_COLOR_SCHEME` for that one pin — the scheme says
what a _name_ renders as, the column says what this host or user renders as —
and anything that is not six hex digits is ignored, leaving the row to color
by its name alone.

The vocabulary is twenty-four names: the terminal's twelve (`red`, `green`,
`yellow`, `blue`, `magenta`, `cyan` and their `br` forms) and twelve more -
`orange`, `pink`, `teal`, `lime`, `violet`, `salmon`, `gold`, `sky`,
`indigo`, `mint`, `peach`, `lavender` - that a pin may name and the hash
lands on as readily as the first twelve. A pin, the hash and `hi --preview
colors` never see anything else. What each name _renders as_ is
`_HI_COLOR_SCHEME`'s: unset, the terminal's own sixteen colors for the first
twelve and a built-in 24-bit color for each extra (there is no 16-color
orange); set to a hex list of your own, that list's hex for every name. Each
is emitted as one escape that carries a 16-color
code first and the 24-bit color after it, so a terminal that ignores the
second keeps the first - an extra name's 16-color half is the nearest of the
sixteen (orange reads as bright yellow there, teal as cyan).
It paints everything hi paints - the prompt, the header's cells and packages
check, the git segment - and only on a terminal that says it can:
`COLORTERM` set to `truecolor` or `24bit`, which hi reads on the client and
ships to the session as `_HI_TRUECOLOR` (ssh drops `COLORTERM` itself).
Inside tmux or on a terminal that renders 24-bit color without announcing it,
`export _HI_TRUECOLOR=1` in `settings.sh` forces it; `0` refuses it. zsh
takes the hex from 5.7 on and keeps the plain name below that; macOS
Terminal.app never sets `COLORTERM` and so keeps its own sixteen. Judge a
scheme with `hi --preview colors` and `hi --preview packages`, which each say
which scheme they are rendering. `settings.sh` ships to every target, so a
scheme follows you.

hi ships no named schemes: the scheme _is_ the setting — twenty-four six-digit hex words,
one space apart, in the order of the names above (red, green, yellow, blue,
magenta, cyan, the six bright ones, then the twelve extras), or forty-eight -
the second twenty-four paint only the package check, so a missing favorite
can shout in a different red from the one your prompt wears. Write it into
`settings.sh` by hand:

```sh
export _HI_COLOR_SCHEME='f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 f37799 89d88b ebd391 74a8fc f2aede 6bd7ca fab387 f2cdcd 81c8be c3e88d cba6f7 eba0ac e5c890 89dceb 7287fd 8be9b0 f5a97f b4befe'
```

The quotes matter (the value holds spaces, and fish sources the file too).
Anything that is not exactly 24 or 48 hex words renders as the default,
`hi --doctor` says so, and the previews label it `(ignored - not a scheme)`;
a list that parses is labelled `custom (24)` or `custom (48)`.

### The package check's ramp

`_HI_PACKAGES_PALETTE` is the same idea one level down: which of the
twenty-four names the header's package check paints each priority in. It is
eight of those names, one space apart — four for installed, rising 0→3, then
four for missing:

```sh
export _HI_PACKAGES_PALETTE='cyan green brcyan brgreen blue magenta bryellow brred'
```

That line is the shipped ramp, so writing it changes nothing; unset means the
same. A ramp reads best when both halves climb in one direction — a missing
favorite the loudest thing on screen, installed trivia the quietest — and
stay legible on light and dark terminals alike. Anything that is not eight
names from the vocabulary above falls back to the shipped ramp, `hi --doctor`
says so, and `hi --preview packages` labels the line `default`, `custom`, or
`(ignored - not eight color names)`.

`hi --preview colors` shows every host in your ssh config and every user it
knows of, drawn in the colors themselves, each row naming the rule it matched:

![hi --preview colors: every ssh host and user in the colors they resolve to, then a prod host in red and a dev host in green](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### Using the hash in your own prompt

`_HI_DISABLE_PROMPT=1` [(Every setting)](#every-setting) turns off hi's own
`user@host` prompt; the per-host color hashing is still resolved, into
variables for your own `bash.sh` or `zsh.zsh` (sourced at the end of hi's,
[above](#shells-you-drop-into-inside-a-session)) to use:

- `$_HI_HOST_ESC`/`$_HI_USER_ESC` — the raw ANSI escape, for a bash `PS1` to
  embed directly (wrap it in `\[ \]` so readline doesn't count its width):
  `PS1="\[$_HI_HOST_ESC\]\h\[$NC\] \w "`.
- `$_HI_HOST_COLOR`/`$_HI_USER_COLOR` — the color by name, for zsh's own
  `%F{}`: `PS1='%F{$_HI_HOST_COLOR}%m%f %~ '`. One of the twelve extras is
  not a name `%F{}` knows: `_hi_color_base b "$_HI_HOST_COLOR"` gives the
  sixteen-color name behind it, and `_hi_color_hex h "$_HI_HOST_COLOR"` the
  hex for `%F{#$h}`.
- fish needs neither: `$fish_color_host`/`$fish_color_user` are already set
  by `common/config.fish`, unconditionally, for `set_color $fish_color_host`
  in your own `fish_prompt`.

All four update the moment the color pins above do.
