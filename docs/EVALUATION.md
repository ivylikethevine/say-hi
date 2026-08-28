# Evaluation

## Contents

- [Usability](#usability)
- [Design](#design)
- [Customizability](#customizability)

## Usability

### U3. The connect is chatty

A default connect prints a size, a copy time, a load time, the greeting
("only bash today :("), a three-row header with UTC/local/version, sysinfo,
and a package check; the disconnect prints a size, a duration, a second
banner and a timestamp. Every one is a toggle; none is off by default. An
admin connecting forty times a day wants `user@host $` — this half is what
the presets in `hi --configure` are for, and stays as it is here.

## Design

### D2. bash 3.2 as the floor shapes everything

No associative arrays, no `mapfile`, no namerefs — so tables are `|`-joined
strings read back with `IFS='|' read` (`_HI_SHELL_TABLE`, `_HI_BACKENDS`,
`_HI_TRIM_TABLE`, `common/flags`), arrays are filled through `eval`
(`_hi_read_lines`, `core.sh:312-318`), and every toggle is defaulted via
`eval ": \"\${$_hi_t:=0}\""`. The evals take fixed names and are safe; the
cost is that every reader has to check that each time. The floor exists for
the macOS _client_ (bash 3.2 as `/bin/bash`). Homebrew bash is the norm on
any admin's Mac, and a `#!/usr/bin/env bash` already picks it up. Requiring
bash 4 on the client and keeping the 3.2 floor only for what runs on the
_target_ would remove most of the eval and half the table plumbing.

### D4. Two independent cleanup paths

`trap 'rm -rf $_HI_CLEANUP' exit` in the bootstrap and `_hi_on_exit
clean_all` in `load.sh` (SECURITY.md calls this belt and braces). Two paths
that can each fire without the other is also two paths that can each
_fail_ without the other noticing, and the opt-in rc graft (`_HI_GRAFT_RC`)
is only undone by one of them. One owner, one trap.

## Customizability

### C1. Shipped aliases and exports cannot be turned off as a set

`settings/aliases.sh` unconditionally sets `EDITOR`, `IDE`, `EZA_CONFIG_DIR`,
`GCC_COLORS`, and defines `l`, `le`, `lr`, `lsx`, `now`, `zed`, `micro`, `sudo`
and a dozen more. The user's `aliases.sh` runs last and can override any one
of them, but there is no `_HI_DISABLE_ALIASES` and no way to ship _only_ the
user's. Clobbering `EDITOR` on a target where the admin deliberately set it
is the one most people will hit first. (`_HI_DISABLE_BAT_ALIAS` covers `cat`,
which is the right idea applied to one alias.)

### C2. The prompt is a shape, not a template

What can change: the end character per shell, the colours per host/user/tag,
starship deference. What cannot: the order of user/host/cwd, whether the
cwd is there, the git segment's format, anything after `\w`. Anyone with a
prompt they like will set `_HI_DISABLE_PROMPT=1` and use their own — at
which point the per-host colour hashing, which is hi's best idea, is gone
too. Expose the colour escapes as variables the user's own `PS1` can use
(they already exist: `_hi_host_escape_var`), and document that path.
