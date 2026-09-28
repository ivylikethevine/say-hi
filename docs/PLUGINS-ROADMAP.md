# Plugins roadmap

Which parts of hi become units a user switches on, switches off, and adds to,
and the work left to get there. The entries under [The work](#the-work) are
[README's Roadmap](../README.md#roadmap) entries in the same form: each is
deleted once its **Ticks when** holds. What a user does today is
[SETTINGS.md's _Plugins_](SETTINGS.md#plugins).

## Contents

- [Verdict](#verdict)
- [What exists](#what-exists)
- [What one carried config costs](#what-one-carried-config-costs)
- [The overlay by wiring](#the-overlay-by-wiring)
- [The design](#the-design)
  - [Two halves](#two-halves)
  - [Generated wiring](#generated-wiring)
  - [The row](#the-row)
  - [On and off](#on-and-off)
- [Header cells](#header-cells)
- [Prompt](#prompt)
- [Risks](#risks)
- [The work](#the-work)

## Verdict

| Aspect                                    | A plugin?             | Contract                                                         |
| ----------------------------------------- | --------------------- | ---------------------------------------------------------------- |
| A carried config a tool is pointed at     | yes, as data          | one table row; the target's wiring is generated on the client    |
| The same with a quirk (vim, nano, micro)  | yes, row and built-in | the same row; the quirk stays code in the tree                   |
| Shell code of the user's own              | already               | `plugins.d` ([HI.59](GLOSSARY.md#hi59-plugins)), unchanged       |
| The tool aliases (bat, ls, sudo)          | yes                   | the same off list; the code stays in `common/aliases.sh`         |
| A header cell added by the user           | yes                   | a bash `header.d/<word>` defining `_hi_cell_<word>`              |
| The built-in header cells                 | no                    | two probes feed eleven cells; a file each ships more, saves none |
| The git and environment prompt segments   | no                    | drawn with no fork, written once per shell family                |
| The prompt-program handoff                | already a table       | a loader nobody was handed can stay home                         |
| Transport, targets, backends, session rcs | no                    | the core                                                         |

## What exists

Four ways in:

- **`$_HI_OVERLAY_TABLE`** in `hi.sh`, a row per carried member:
  the member, its `common/paths.sh` variable, whether `config/` holds a
  default, the tool that reads it, what points the tool at it on a target,
  and where it is looked for at home
  ([HI.61](GLOSSARY.md#hi61-one-overlay-priority)).
- **`carry`**, the user's own rows in the same columns, read as data
  ([HI.63](GLOSSARY.md#hi63-carry-rows)).
- **`plugins.d/`**, the user's files in the subset bash, zsh, and fish all
  parse, sourced at every shell start on both sides, with one hook,
  `_HI_SEGMENT`.
- **Word lists and toggles**: `_HI_HEADER_ORDER`, `_HI_PACKAGES_GROUPS`,
  `_HI_PROMPT_TOOL`, `_HI_PLUGINS_OFF`, and the `_HI_DISABLE_*` set.

## What one carried config costs

`ripgreprc` is the simplest kind, a file one variable names, and it is
written down in:

| Where       | What                                                                                                              |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| `hi.sh`     | its `$_HI_OVERLAY_TABLE` row: the member, its tool, its wire, its places at home                                  |
| six docs    | FILES.md, SETTINGS.md, INTEGRATIONS.md, GLOSSARY.md, CONTRIBUTING.md's _What 1.x will not break_, and `docs/hi.1` |
| four suites | a case each in `payload_test`, `rc_test`, `doctor_test`, and `framework_test`                                     |

A config pointed at by a flag is still more than its row: a
`common/aliases.sh` line, and its variable's lines in `common/paths.sh`. One
with a dialect adds `$_HI_STRIP_NAMES` and a name test in the include scan
([HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan)). One with a
toggle adds `_HI_TOGGLES`, `common/config.fish`'s mirror, `paths.sh`'s
`_HI_DISABLE_LOCAL` block, and `scripts/configure.sh`'s
`_HI_FEATURE_PROMPTS`. `paths_test` and `drift` exist to hold those copies
together.

## The overlay by wiring

| Kind      | Rows | Members                                                                                                    | On a target                       |
| --------- | ---- | ---------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `env`     | 9    | `starship.toml`, `oh-my-posh.*`, `bat.conf`, `ripgreprc`, `fzfrc`, `lazygit.yml`, `inputrc`                | `export VAR=<file>`               |
| `envdir`  | 2    | `theme.yml`, `kakrc`                                                                                       | `export VAR=<the overlay>`        |
| `flag`    | 7    | `vimrc`, `init.lua`, `config.toml`, `nanorc`, `init.el`, `tmux.conf`, `screenrc`                           | `alias tool="tool <flag> <file>"` |
| `flagdir` | 6    | `micro/`'s three, `zellij/`'s three                                                                        | `alias tool="tool <flag> <dir>"`  |
| sourced   | 10   | `aliases.sh`, `plugins.d`, `bashrc`, `zshrc`, `config.fish`, `p10k.zsh`, the framework themes, `tide.vars` | hi's rc for that shell            |
| hi's own  | 5    | `settings.sh`, `colors`, `packages`, `ssh_tags`, `carry`                                                   | read by hi                        |

The first four kinds, 24 of 39 rows, are one sentence: carry a file, point a
tool at it. Those are data, written from the row, micro's alias excepted.
What stays code beside a row:

- oh-my-posh's home lookup reads rc files, and one program is three members.
- vim also gets `$VIMINIT`, in `load.sh`.
- nano gets `load.sh`'s `_hi_nano_fallback`.
- micro's flags are a setting, with a default on a target and none at home.
- tide's member is cut down to its `SETUVAR tide_` lines by the stager.

## The design

### Two halves

A member has a **client half**: find it at home, check its tool is here,
scan it, strip it, pack it, name it in `hi --doctor`. That runs in bash, in
`hi.sh` and `scripts/`, and reads the table.

It also has a **target half**: point the tool at the file. That runs in bash,
zsh, fish, and sh, in `common/paths.sh`'s dialect, which has no loop, no
function, and no `case`. Nothing written in it can walk a table, so a wiring
is spelled there by hand, or written for it by the client.

### Generated wiring

The client writes the target half
([HI.62](GLOSSARY.md#hi62-generated-wiring)): `wiring.sh`, a line in the
four-shell dialect for each member the overlay's archive carries, which
`common/paths.sh` sources on a target.

```sh
export RIPGREP_CONFIG_PATH="$_HI_CONFIG_DIR/ripgreprc"
export EZA_CONFIG_DIR="$_HI_CONFIG_DIR"
```

So:

- A target knows no wired member by name, and a row added by the user needs
  no change to hi.
- Only a member that ships has a line: no `[ -f ... ]` per member per shell
  start.
- A hop taken from inside a session writes the same lines: the paths are
  under `$_HI_CONFIG_DIR`, and the list is the same.
- The lines are part of the overlay cache's key.

A flag is an alias, and a target's alone: at home every tool reads its own
config, overlay copy or not.

```sh
[ "$_HI_DISABLE_TMUX" != 1 ] && command -v tmux >/dev/null 2>&1 && alias tmux="tmux -f $_HI_CONFIG_DIR/tmux.conf" || true
```

### The row

As the table has it, with the column still to come:

```text
member|variable|tree|tool|group|wire|off|home, best first   (then: dialect)
ripgreprc|-|-|rg|cli|env:RIPGREP_CONFIG_PATH|-|"${RIPGREP_CONFIG_PATH:-}"
theme.yml|-|-|eza|cli|envdir:EZA_CONFIG_DIR|-|"${EZA_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/eza}/theme.yml"
inputrc|-|-|(readline)|cli|env:INPUTRC|-|"${INPUTRC:-$HOME/.inputrc}"
```

- **tool** is the binaries that read the member, any of which on `$PATH`
  says home's copy rides; in parentheses, a name nothing looks for. It can
  also feed the header's package check: a config carried for a tool the
  target lacks.
- **wire** is `env:`, `envdir:`, `flag:`, or `flagdir:`, and `-` for a
  member hi's own code reads. The table's own flags are still
  `common/aliases.sh`'s.
- **group** is the word that switches it with its kind: `editors`, `mux`,
  `prompt`, `cli`, `shell`; `-` is hi's own file, which nothing switches.
- **off** is the toggles that keep it home, and that a target tests again
  before it takes the wire: an editor's two.
- **dialect** stands in for the include scan's name tests and
  `$_HI_STRIP_NAMES`; `-` passes through untouched, as a name that is no
  dialect does now.

The built-ins stay one table in the tree, not a file each: a file is a tar
header on every connect. The user's rows are the overlay's `carry`, four of
those columns a line ([SETTINGS.md](SETTINGS.md#a-tool-hi-does-not-know)),
itself a member, so a relay knows the names to forward.

A row of the user's is wired on a target only. At home the tool reads its
own config unasked, the rule the `env` members keep.

### On and off

`$_HI_PLUGINS_OFF` is one word list over plugins, groups, and members, read
on the client as it packs ([HI.64](GLOSSARY.md#hi64-what-is-switched-off)):
what is off sends no file and has no wiring line, and the target is handed
the result, not the list. `hi --plugins` lists, `hi --plugin-off` and
`hi --plugin-on` switch, and `hi --add-plugin` and `hi --remove-plugin`
write the carry's lines
([SETTINGS.md](SETTINGS.md#switching-a-plugin-off)).

The editors' `_HI_DISABLE_*` toggles keep a member home the same way, and
go on gating its alias, which the list does not reach.

## Header cells

`common/header.sh` is bash on every side, since zsh and fish shell out to
it, so a cell is not held to the four-shell dialect:

```sh
# header.d/kernel
function _hi_cell_kernel() { printf -v "$1" '%s' "${CYAN}$(uname -r)"; }
```

What that takes:

- `_hi_header_word_cell`'s roster gate admits the loaded cells' names beside
  `$_HI_HEADER_ORDER_DEFAULT`'s. The gate stays: `$_HI_HEADER_ORDER` is the
  user's string, and only a known word may reach a function.
- A cell with no `$_HI_HEADER_ALTS` entry gets an alternate worked out from
  its own hue, keeping the property `header_test` checks
  ([HI.48](GLOSSARY.md#hi48-header-cell-hue-resolution)).
- `_hi_row_line`'s wrap is over cells already, whoever wrote them.
- A cell of the user's forks if it has to; the shared probes
  (`_hi_probed_cell`) stay the built-ins' own.
- `header.d` is a `.d` member
  ([HI.58](GLOSSARY.md#hi58-overlay-directory-members)), scanned and stripped
  as sh.

The built-in cells stay in `header.sh`. `_hi_system_info_probe` feeds five
and `_hi_identity_probe` six, so a file a cell would ship more bytes and
call the same two probes.

## Prompt

The git and environment segments draw with no fork, in one implementation
for bash and zsh and another for fish. `_HI_SEGMENT` is a command run on
every draw. Moving the built-ins onto it buys a uniform contract with a fork
a segment a prompt, so they stay as they are, behind the toggles they have.

`$_HI_PROMPT_TABLE` is the prompt programs' roster already. The client
knows the list a target is handed before it packs
([HI.32](GLOSSARY.md#hi32-starship-deference)), so a framework loader nobody
was handed can be cut from the payload the way `_hi_payload_excl` cuts a
shadowed default.

## Risks

- **`eval` of the home column.** `hi.sh` evaluates the table's, where every
  value is a constant. A `carry` line's is data, read by `_hi_path_list`
  and never evaluated ([HI.63](GLOSSARY.md#hi63-carry-rows)); the table's
  own `eval` is one of those
  [README's Roadmap](../README.md#roadmap) counts down.
- **The allow list.** A `carry` line can name any file, a credentials file
  included. It was asked for, which a `~/.bashrc` found at home was not, and
  `hi --doctor` names every file a line carries, by path.
- **Names at the overlay's root.** `config.toml` and `theme.yml` are names
  any tool might use, and `envdir` points a tool at the whole overlay. A
  member under its plugin's name (`helix/config.toml`), as `micro/` and
  `zellij/` are, ends that; `$_HI_OVERLAY_RENAMES` covers the move.
- **The payload budget.** Rows shrink the payload; a file for each built-in
  grows it.
- **Forks at shell start.** `plugins.d` costs a parse fork a member a shell.
  A built-in takes no such path.
- **The format is an interface.**
  [_What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break) names
  every member and `plugins.d`'s hooks, so the row is settled before the
  1.0 tag.
- **A toggle the target reads.** A line behind `_HI_DISABLE_*` is tested
  where the shell starts. The client cannot stand in for it with its own
  environment: under `_HI_DISABLE_LOCAL=1` every toggle is set here and none
  on a target. There the client reads a toggle off `settings.sh`'s own
  lines, not its environment.

## The work

In order.

1. [ ] **A tool's config rides without a change to hi** — shipped: a line
       of the overlay's `carry` names the member, its tool, its wire, and
       its places at home, and rides through the same order, include scan,
       and wiring; [SETTINGS.md](SETTINGS.md#a-tool-hi-does-not-know) shows
       how. What is left is seeing it. **Ticks when:** a tool of the user's
       own reads its home config on an e2e target.

2. [ ] **Everyday CLI configs ride** — shipped: `ripgreprc`
       (`$RIPGREP_CONFIG_PATH`), `fzfrc` (`$FZF_DEFAULT_OPTS_FILE`), and
       `lazygit.yml` (`$LG_CONFIG_FILE`) are members, each carried from
       where its tool keeps it and listed in
       [FILES.md](FILES.md#configs-read-from-where-their-tool-keeps-them);
       the framework suite's `tmux` case has rg read one on a target. Left
       for rows of their own: `LS_COLORS`, ~18KB raw on every connect; skim,
       bottom, procs, and dust, which fewer boxes run, the last three behind
       a flag and so an alias. **Ticks when:** an fzf that reads
       `$FZF_DEFAULT_OPTS_FILE`, and lazygit, read theirs on a target
       (bookworm's fzf predates the variable, and it ships no lazygit).

3. [ ] **A member is its row and nothing else** — shipped: the `group`
       column, `$_HI_PLUGINS_OFF` and the commands that keep it, the toggles
       keeping a member home, and the editors' and multiplexers' aliases
       written from their rows. What is left: the `dialect` column; micro's
       alias, whose flags are a setting `common/aliases.sh` defaults; and
       the editors' and multiplexers' variables in `common/paths.sh`, which
       only `hi.sh` and `load.sh` still read. **Ticks when:**
       `common/aliases.sh` and `common/paths.sh` name no member, and
       `$_HI_STRIP_NAMES` and the include scan name none either.

4. [ ] **An editor's side files ride with its rc** — kakoune's `colors/` (a
       `colorscheme` the `kakrc` names) stays home, so the target falls back
       to the default scheme, and helix's `languages.toml` has no flag to
       point `hx` at. **Do:** carry kak's `colors/` member by member, as
       zellij's `themes/` rides, in the row's own directory; find out
       whether helix can take a `languages.toml` on a target, and write the
       verdict into [INTEGRATIONS.md](INTEGRATIONS.md). **Ticks when:** a
       `kakrc` with `colorscheme <own>` shows that scheme on a target.

5. [ ] **The header probes only what was asked** — the default
       `$_HI_HEADER_ORDER` counts containers, jobs, and pods, so every local
       terminal or tmux pane runs docker, podman, nomad, and kubectl.
       **Do:** leave the backend cells out of the local default (a session
       keeps them), or run them after the first prompt. **Ticks when:** a
       local shell with the default order starts no backend CLI. **Open
       question:** drop the containers, jobs, and pods cells from the local
       default header, or keep them and fill them in after the first prompt?
       Either changes what a local header shows today.

6. [ ] **A header cell of the user's own** — every cell is one
       `_hi_cell_<word>` behind a dispatch, and a `plugins.d` member can
       only set a prompt segment. **Do:** `header.d`, as
       [Header cells](#header-cells) has it. **Ticks when:** a `header.d`
       member's cell draws on a target where `$_HI_HEADER_ORDER` puts it,
       and [INTEGRATIONS.md](INTEGRATIONS.md) shows how.

7. [ ] **A prompt loader nobody was handed stays home** — **Do:** cut the
       framework loaders outside the handed list from the payload. **Ticks
       when:** a connect handed starship alone ships no framework's loader,
       and `--group bench` reads the smaller payload.
