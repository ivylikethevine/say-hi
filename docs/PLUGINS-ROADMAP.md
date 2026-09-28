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
| The same with a quirk (vim, nano, nvim)   | yes, row and built-in | the same row; the quirk stays code in the tree                   |
| Shell code of the user's own              | already               | `plugins.d` ([HI.59](GLOSSARY.md#hi59-plugins)), unchanged       |
| The tool aliases (bat, ls, sudo)          | yes                   | the same on/off list; the code stays in `common/aliases.sh`      |
| A header cell added by the user           | yes                   | a bash `header.d/<word>` defining `_hi_cell_<word>`              |
| The built-in header cells                 | no                    | two probes feed eleven cells; a file each ships more, saves none |
| The git and environment prompt segments   | no                    | drawn with no fork, written once per shell family                |
| The prompt-program handoff                | already a table       | a loader nobody was handed can stay home                         |
| Transport, targets, backends, session rcs | no                    | the core                                                         |

## What exists

Three ways in, each its own shape:

- **`$_HI_OVERLAY_TABLE`** in `hi.sh`, a row per carried member:
  the member, its `common/paths.sh` variable, whether `config/` holds a
  default, and where it is looked for at home
  ([HI.61](GLOSSARY.md#hi61-one-overlay-priority)). Built-in only.
- **`plugins.d/`**, the user's files in the subset bash, zsh, and fish all
  parse, sourced at every shell start on both sides, with one hook,
  `_HI_SEGMENT`.
- **Word lists and toggles**: `_HI_HEADER_ORDER`, `_HI_PACKAGES_GROUPS`,
  `_HI_PROMPT_TOOL`, and the `_HI_DISABLE_*` set.

## What one carried config costs

`ripgreprc` is the simplest kind, a file one variable names, and it is
written down in:

| Where               | What                                                                                                              |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `hi.sh`             | its `$_HI_OVERLAY_TABLE` row                                                                                      |
| `hi.sh`             | `_hi_tool_here`: the member to its binary                                                                         |
| `common/paths.sh`   | the target's `export RIPGREP_CONFIG_PATH=`                                                                        |
| `scripts/doctor.sh` | `_hi_doc_member`: the member to its tool's label                                                                  |
| six docs            | FILES.md, SETTINGS.md, INTEGRATIONS.md, GLOSSARY.md, CONTRIBUTING.md's _What 1.x will not break_, and `docs/hi.1` |
| five suites         | `payload_test`, `rc_test` for bash and fish, `doctor_test`, `paths_test`, `framework_test`                        |

A config pointed at by a flag adds a `common/aliases.sh` line. One with a
dialect adds `$_HI_STRIP_NAMES` and a name test in the include scan
([HI.57](GLOSSARY.md#hi57-carried-configs-and-the-include-scan)). One with a
toggle adds `_HI_TOGGLES`, `common/config.fish`'s mirror, `paths.sh`'s
`_HI_DISABLE_LOCAL` block, and `scripts/configure.sh`'s
`_HI_FEATURE_PROMPTS`.

So a member is one record kept in four to eight rosters, and `paths_test`
and `drift` exist to hold the copies together.

## The overlay by wiring

| Kind      | Rows | Members                                                                                                    | On a target                       |
| --------- | ---- | ---------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `env`     | 9    | `starship.toml`, `oh-my-posh.*`, `bat.conf`, `ripgreprc`, `fzfrc`, `lazygit.yml`, `inputrc`                | `export VAR=<file>`               |
| `envdir`  | 2    | `theme.yml`, `kakrc`                                                                                       | `export VAR=<the overlay>`        |
| `flag`    | 7    | `vimrc`, `init.lua`, `config.toml`, `nanorc`, `init.el`, `tmux.conf`, `screenrc`                           | `alias tool="tool <flag> <file>"` |
| `flagdir` | 6    | `micro/`'s three, `zellij/`'s three                                                                        | `alias tool="tool <flag> <dir>"`  |
| sourced   | 10   | `aliases.sh`, `plugins.d`, `bashrc`, `zshrc`, `config.fish`, `p10k.zsh`, the framework themes, `tide.vars` | hi's rc for that shell            |
| hi's own  | 4    | `settings.sh`, `colors`, `packages`, `ssh_tags`                                                            | read by hi                        |

The first four kinds, 24 of 38 rows, are one sentence: carry a file, point a
tool at it. Those are data. What stays code beside a row:

- oh-my-posh's home lookup reads rc files, and one program is three members.
- nvim takes an `env XDG_*_HOME=` prefix on a target.
- vim also gets `$VIMINIT`, in `load.sh`.
- nano gets `load.sh`'s `_hi_nano_fallback`.
- helix answers to two binary names; micro has default options with no
  config at all.
- tide's member is cut down to its `SETUVAR tide_` lines by the stager.

## The design

### Two halves

A member has a **client half**: find it at home, check its tool is here,
scan it, strip it, pack it, name it in `hi --doctor`. That runs in bash, in
`hi.sh` and `scripts/`, and reads the table already; `_hi_tool_here` and
`_hi_doc_member` are the two rosters left beside it.

It also has a **target half**: point the tool at the file. That runs in bash,
zsh, fish, and sh, in `common/paths.sh`'s dialect, which has no loop, no
function, and no `case`. Nothing written in it can walk a table, so every
wiring is spelled by hand, and a row of the user's own has nowhere to run.

### Generated wiring

The client writes the target half. The overlay's stager already copies in a
member packed from elsewhere; it also writes one generated member, a line in
the four-shell dialect for each member that ships:

```sh
export RIPGREP_CONFIG_PATH="$_HI_CONFIG_DIR/ripgreprc"
command -v tmux >/dev/null 2>&1 && alias tmux="tmux -f $_HI_CONFIG_DIR/tmux.conf" || true
```

`common/paths.sh` sources it in place of its own per-member lines. Then:

- A target knows no member by name, so a row added by the user needs no
  change to hi.
- Only a member that ships has a line: no `[ -f ... ]` per member per shell
  start.
- A member switched off is neither sent nor wired, so a target reads no
  toggle for it.
- `paths.sh`'s target-only lines leave the payload.
- A relayed hop forwards the generated member as written: its paths are
  under `$_HI_CONFIG_DIR`, and the middle box has no home tier to write one
  from.

The generated member is on the member list, and its text is part of the
overlay cache's key.

### The row

One row a plugin, in the table's own style:

```text
name|tools|member|home, best first|wire|dialect|group
ripgrep|rg|ripgreprc|"${RIPGREP_CONFIG_PATH:-}"|env:RIPGREP_CONFIG_PATH|-|cli
eza|eza|theme.yml|"${EZA_CONFIG_DIR:-$_HI_XDG_CONFIG/eza}/theme.yml"|envdir:EZA_CONFIG_DIR|-|cli
tmux|tmux|tmux.conf|"$HOME/.tmux.conf" "$_HI_XDG_CONFIG/tmux/tmux.conf"|flag:-f|tmux|mux
```

- **tools** stands in for `_hi_tool_here` and `_hi_doc_member`, and can feed
  the header's package check: a config carried for a tool the target lacks.
- **wire** is `env:`, `envdir:`, `flag:`, or `flagdir:`, or `-` for a member
  hi's own code reads.
- **dialect** stands in for the include scan's name tests and
  `$_HI_STRIP_NAMES`; `-` passes through untouched, as a name that is no
  dialect does now.
- **group** lets one word, `editors`, switch several.

The built-ins stay one table in the tree, not a file each: a file is a tar
header on every connect. The user's rows are one overlay member in the same
format, itself on the member list, so a relay knows the names to forward.

A row of the user's is wired on a target only. At home the tool reads its
own config unasked, the rule the `env` members keep today.

### On and off

One word list over names and groups, read on the client as it packs, in
place of a `_HI_DISABLE_*` per tool. The target is handed the result, not
the list.

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

- **`eval` of the home column.** `hi.sh` evaluates it because every value is
  a constant. A row of the user's makes it user data: their own file on
  their own machine, the trust `settings.sh` has, and never evaluated on a
  target, where `_hi_overlay_home` returns first. Either
  [SECURITY.md](SECURITY.md) says so, or hi expands a fixed set of forms by
  hand.
- **The allow list.** A row can name any file, a credentials file included.
  It was asked for, which a `~/.bashrc` found at home was not, but
  `hi --doctor` has to name every file a user's row carries, by path.
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
- **Flags at home.** Generated wiring is a target's. An overlay copy of an
  editor rc needs its alias at home too, so `common/aliases.sh` keeps the
  built-in flag lines; generating them at home as well needs a cache and a
  rule for when it is stale.

## The work

In order; the first two change no behavior.

1. [ ] **A member's tool is a column** — `_hi_tool_here` and
       `_hi_doc_member` are two more rosters of what the table knows.
       **Do:** add the tools column and read it from both callers. **Ticks
       when:** neither function names a member.

2. [ ] **A target's wiring is generated** — **Do:** the `wire` column, the
       generated member for `env` and `envdir`, and `common/paths.sh`
       sourcing it. **Ticks when:** `paths.sh` names no member behind
       `_HI_REMOTE_SESSION = 1`, and `rc_test`'s target cases pass off the
       generated member.

3. [ ] **A tool's config rides without a change to hi** — adding a tool hi
       does not know means a `plugins.d` member or a change to hi. **Do:**
       read the user's rows from the overlay, through the same order and
       include scan. **Ticks when:** a tool of the user's own reads its home
       config on a target with no code change, and
       [SETTINGS.md](SETTINGS.md) shows how.

4. [ ] **Everyday CLI configs ride** — shipped: `ripgreprc`
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

5. [ ] **One list switches a plugin** — **Do:** the `dialect` and `group`
       columns, the on/off list, and generated `flag` and `flagdir` lines on
       a target. **Ticks when:** a member switched off by name, and one by
       group, reach no target, and `$_HI_STRIP_NAMES` and the include scan
       name no member.

6. [ ] **An editor's side files ride with its rc** — kakoune's `colors/` (a
       `colorscheme` the `kakrc` names) stays home, so the target falls back
       to the default scheme, and helix's `languages.toml` has no flag to
       point `hx` at. **Do:** carry kak's `colors/` member by member, as
       zellij's `themes/` rides, in the row's own directory; find out
       whether helix can take a `languages.toml` on a target, and write the
       verdict into [INTEGRATIONS.md](INTEGRATIONS.md). **Ticks when:** a
       `kakrc` with `colorscheme <own>` shows that scheme on a target.

7. [ ] **The header probes only what was asked** — the default
       `$_HI_HEADER_ORDER` counts containers, jobs, and pods, so every local
       terminal or tmux pane runs docker, podman, nomad, and kubectl.
       **Do:** leave the backend cells out of the local default (a session
       keeps them), or run them after the first prompt. **Ticks when:** a
       local shell with the default order starts no backend CLI. **Open
       question:** drop the containers, jobs, and pods cells from the local
       default header, or keep them and fill them in after the first prompt?
       Either changes what a local header shows today.

8. [ ] **A header cell of the user's own** — every cell is one
       `_hi_cell_<word>` behind a dispatch, and a `plugins.d` member can
       only set a prompt segment. **Do:** `header.d`, as
       [Header cells](#header-cells) has it. **Ticks when:** a `header.d`
       member's cell draws on a target where `$_HI_HEADER_ORDER` puts it,
       and [INTEGRATIONS.md](INTEGRATIONS.md) shows how.

9. [ ] **A prompt loader nobody was handed stays home** — **Do:** cut the
       framework loaders outside the handed list from the payload. **Ticks
       when:** a connect handed starship alone ships no framework's loader,
       and `--group bench` reads the smaller payload.
