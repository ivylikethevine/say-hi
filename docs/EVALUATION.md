# Evaluation

## Design

### D2. bash 3.2 as the floor shapes everything

No associative arrays, no `mapfile`, no namerefs — so tables are `|`-joined
strings read back with `IFS='|' read` (`_HI_SHELL_TABLE`, `_HI_BACKENDS`,
`_HI_TRIM_TABLE`, `common/flags`), arrays are filled through `eval`
(`_hi_read_lines`, `core.sh:159-165`), and every toggle is defaulted via
`eval ": \"\${$_hi_t:=0}\""`. The evals take fixed names and are safe; the
cost is that every reader has to check that each time. The floor exists for
the macOS _client_ (bash 3.2 as `/bin/bash`). Homebrew bash is the norm on
any admin's Mac, and a `#!/usr/bin/env bash` already picks it up. Requiring
bash 4 on the client and keeping the 3.2 floor only for what runs on the
_target_ would remove most of the eval and half the table plumbing.

## Customizability

### C1. Shipped aliases and exports cannot be turned off as a set

`settings/aliases.sh` unconditionally sets `EDITOR`, `IDE`, `EZA_CONFIG_DIR`,
`GCC_COLORS`, and defines `l`, `le`, `lr`, `lsx`, `now`, `zed`, `micro`, `sudo`
and a dozen more. The user's `aliases.sh` runs last and can override any one
of them, but there is no `_HI_DISABLE_ALIASES` and no way to ship _only_ the
user's. Clobbering `EDITOR` on a target where the admin deliberately set it
is the one most people will hit first. (`_HI_DISABLE_BAT_ALIAS` covers `cat`,
which is the right idea applied to one alias.)
