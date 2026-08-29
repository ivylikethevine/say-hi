# Future work

Not scheduled. Everything in [ROADMAP.md](ROADMAP.md) is queued work with a
tier reflecting how hard it is; nothing here gates a release, and nothing here
is queued — it is research and decisions nobody has made yet. An entry moves
to ROADMAP when someone commits to it, the same way a finished ROADMAP entry
is deleted rather than checked off: git history is the ledger.

Each entry keeps ROADMAP's shape — an italic **scope** line, closing with
_in-repo_ or _outside this checkout_, and a **Ticks when:** line describing
what "done" looks like if it is ever picked up.

## Contents

- [Persistent sessions on a disposable target](#persistent-sessions-on-a-disposable-target)
- [Raise the client's bash floor to 4, keep 3.2 only for the target](#raise-the-clients-bash-floor-to-4-keep-32-only-for-the-target)

## Persistent sessions on a disposable target

_Scope: the largest entry here — cleanup semantics on both paths, a findable
tree path and something to reap it, and SECURITY.md's footprint promise
rewritten; in-repo._ This is research, not queued work.

A dropped connection loses the session outright today (the tree is deleted
on exit). Goal: keep the tree across a drop, reconnect into the same
session, delete only on a definitive exit or a configurable timeout.
**Opt-in, not the default** — a bare `hi <target>` stays disposable.

- `hi --session <name> <target>` writes a deterministic tree
  (`${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>`, mode 0700, `<name>`
  restricted to alnum/`-`/`_`) instead of `mktemp`'s random one; a second
  call finds it, skips re-copying an unchanged payload, and reattaches.
- `load.sh`'s on-exit hook (proven by
  `tests/targets/ssh_disconnect_test.sh`) needs to become conditional, not
  weaker — add a case for dropped-with-`--session` keeping the tree.
- Reaping defaults to zero footprint: a tree older than
  `_HI_PERSIST_TIMEOUT` (unset means keep until `hi --session <name>
--end`) is deleted the moment the _next_ `hi` touches that target. A
  detached watchdog (`sh -c 'sleep N; rm -rf ...' &`) is the stronger
  opt-in. SECURITY.md's _Footprint and cleanup_ needs both modes described.
- Reattachment rides whatever multiplexer the target already has: `tmux` →
  `screen` → `dtach`, in that order; a target with none declines
  persistence with a clear message rather than pretending.
- **Ticks when:** `--session` survives a dropped connection and reattaches,
  a bare `hi <target>` is unchanged, the timeout and watchdog are
  documented settings, SECURITY.md describes both cleanup modes, and the
  disconnect suite covers both paths.

## Raise the client's bash floor to 4, keep 3.2 only for the target

_Scope: reshapes the eval/table plumbing across `common/`; in-repo._ No
associative arrays, `mapfile`, or namerefs under bash 3.2, so tables are
`|`-joined strings read back with `IFS='|' read` (`_HI_SHELL_TABLE`,
`_HI_BACKENDS`, `_HI_TRIM_TABLE`, `common/flags`) and arrays are filled
through `eval` (`_hi_read_lines`, `core.sh:159-165`) — safe, but every reader
has to check it. The floor only matters for the macOS _client_ (Homebrew bash
is the norm there already; `#!/usr/bin/env bash` picks it up); target-only
code could stay at 3.2. **Ticks when:** the decision is written down, and —
if raising the floor — client-side tables move to bash 4 associative
arrays/`mapfile` and the lint suite's 3.2-floor grep is scoped to
target-only files.
