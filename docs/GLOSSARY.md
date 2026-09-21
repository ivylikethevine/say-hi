# Glossary of Deliberate Oddities

say-hi's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `config/aliases.sh`, and
`settings.sh` natively). Targets also split between **GNU and BSD userlands**.
Each entry is a construct that looks odd until you know which master it serves.

Every entry carries a stable `HI.NN` code; a file references it with a
`# GLOSSARY: HI.NN` tag — one code, or two joined with `+`, optional prose
after — instead of re-explaining. The tag is _mandatory_ in `common/`,
`config/`, `load.sh`, and `hi.sh`. Tags point at codes, so an entry can be
retitled without touching a tagged file; codes are never reused once retired.
`tests/lint/drift_test.sh` fails the build if a tag names a code this file
doesn't define, or if an entry here is referenced by nothing. This file never
ships (`docs/` is not in `$_HI_PAYLOAD`).

## Contents

- [HI.01 empty-array guard](#hi01-empty-array-guard)
- [HI.02 _hi_read_lines](#hi02-_hi_read_lines)
- [HI.03 parallel arrays](#hi03-parallel-arrays)
- [HI.04 dynamic-name assignment](#hi04-dynamic-name-assignment)
- [HI.05 printf -v out-var](#hi05-printf--v-out-var)
- [HI.06 source guard](#hi06-source-guard)
- [HI.07 toggle defaulting](#hi07-toggle-defaulting)
- [HI.08 sed tempfile rewrite](#hi08-sed-tempfile-rewrite)
- [HI.09 cat-over-mv](#hi09-cat-over-mv)
- [HI.10 strftime %e over %-e](#hi10-strftime-e-over--e)
- [HI.11 LC_ALL=C sort](#hi11-lc_allc-sort)
- [HI.12 bytes vs columns](#hi12-bytes-vs-columns)
- [HI.13 command -v fallthrough](#hi13-command--v-fallthrough)
- [HI.14 _hi_on_exit](#hi14-_hi_on_exit)
- [HI.15 strict-mode bracketing](#hi15-strict-mode-bracketing)
- [HI.16 no-fork reads](#hi16-no-fork-reads)
- [HI.17 base64 armor](#hi17-base64-armor)
- [HI.18 sh -c wrapping](#hi18-sh--c-wrapping)
- [HI.19 stdin transport](#hi19-stdin-transport)
- [HI.20 fallback rc](#hi20-fallback-rc)
- [HI.21 baked prompt](#hi21-baked-prompt)
- [HI.22 TERM fallback probe](#hi22-term-fallback-probe)
- [HI.23 bash --rcfile -i](#hi23-bash---rcfile--i)
- [HI.25 session-shell ranking](#hi25-session-shell-ranking)
- [HI.26 completion probe knobs](#hi26-completion-probe-knobs)
- [HI.29 apostrophes in substitution comments](#hi29-apostrophes-in-substitution-comments)
- [HI.30 indirect invocation](#hi30-indirect-invocation)
- [HI.31 porcelain branch.oid](#hi31-porcelain-branchoid)
- [HI.32 starship deference](#hi32-starship-deference)
- [HI.33 derived tree location](#hi33-derived-tree-location)
- [HI.34 test suite preamble](#hi34-test-suite-preamble)
- [HI.35 payload comment and whitespace strip](#hi35-payload-comment-and-whitespace-strip)
- [HI.37 zsh pattern-in-variable](#hi37-zsh-pattern-in-variable)
- [HI.38 split tar and gzip](#hi38-split-tar-and-gzip)
- [HI.39 payload staging](#hi39-payload-staging)
- [HI.40 hand-rolled sh quoting](#hi40-hand-rolled-sh-quoting)
- [HI.41 overlay stream](#hi41-overlay-stream)
- [HI.43 container target grammar](#hi43-container-target-grammar)
- [HI.44 wire size token](#hi44-wire-size-token)
- [HI.46 session rc directory](#hi46-session-rc-directory)
- [HI.47 what a child inherits](#hi47-what-a-child-inherits)
- [HI.48 header cell hue resolution](#hi48-header-cell-hue-resolution)
- [HI.50 truecolor color schemes](#hi50-truecolor-color-schemes)
- [HI.51 docker-compatible CLI family](#hi51-docker-compatible-cli-family)
- [HI.52 client multiplexer wrap](#hi52-client-multiplexer-wrap)
- [HI.53 terminal reset after a failed session](#hi53-terminal-reset-after-a-failed-session)
- [HI.54 who draws the environment prefix](#hi54-who-draws-the-environment-prefix)
- [HI.55 re-entrant rc guard](#hi55-re-entrant-rc-guard)
- [HI.56 listing-only completion symbols](#hi56-listing-only-completion-symbols)
- [HI.57 carried configs and the include scan](#hi57-carried-configs-and-the-include-scan)
- [HI.58 overlay directory members](#hi58-overlay-directory-members)
- [HI.59 plugins](#hi59-plugins)
- [HI.60 a shell that outlives the tree](#hi60-a-shell-that-outlives-the-tree)

## HI.01 empty-array guard

`${a[@]+"${a[@]}"}` wherever an array may be empty under `set -u`: bash 3.2
treats expanding an _empty_ array as a fatal "unbound variable".

**Exception - the index form.** `"${!a[@]}"` is already empty-safe and must
NOT get the guard: bash 3.2 reads `${!a[@]+...}` as expanding to nothing, and
bash 5 reads it as an indirect reference and errors. The lint table rejects
the guarded index form.

## HI.02 _hi_read_lines

`mapfile`/`readarray` are bash 4. `_hi_read_lines <array-name>`
(`common/core.sh`) is the stand-in: a `while read` loop assigning through
`eval`, keeping a last line without a trailing newline the way `mapfile -t`
does. Use it as `_hi_read_lines lines < <(cmd)`.

## HI.03 parallel arrays

Associative arrays are bash 4 — on 3.2 the _declaration alone_ is fatal. Where
a map is needed: parallel indexed arrays sharing one index with a keys array
(`_hi_group_index` in `scripts/preview.sh`), or `"<key>=<value>"`
strings via `_hi_kv_get`/`_hi_kv_set` (`tests/lib/fixtures.sh`).

## HI.04 dynamic-name assignment

bash 3.2 has no namerefs, so writing into a caller-named variable goes through
`eval` (`_hi_read_lines`, `_hi_widen_to`) or `printf -v` for a single string.
Reading a caller's `local` works through bash's dynamic scoping — which cuts
both ways: a helper that writes an out-var by name must not declare a `local`
of the same name, or it writes into its own (`_hi_setting_get`'s locals are
prefixed for that reason).

## HI.05 printf -v out-var

`out="$(fn)"` forks a subshell per call; `fn outvar` with `printf -v "$outvar"`
doesn't. Used on hot paths (`_hi_git_prompt`'s optional out-var, `_hi_repeat`,
`_hi_prompt_end`), usually as `[outvar]` with `_hi_out` as the tail; zsh's
`printf` takes `-v` too, so `common/zsh.zsh`'s precmds use the same form.

Never `printf -v x ''` (a bare empty format, zero arguments) to clear a
variable: bash 3.2 skips the assignment outright when there is nothing to
format, leaving `$x` untouched. `printf -v x '%s' ''` clears it everywhere.

## HI.06 source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`hi.sh`, `scripts/install.sh`, `scripts/doctor.sh`, `scripts/preview.sh`,
`packaging/bump.sh`, `packaging/mkpkg.sh`, and `packaging/mkrepo.sh` carry it.

## HI.07 toggle defaulting

fish has no `${X:-0}`, and it sources `aliases.sh`/`paths.sh`/`settings.sh`
natively — so every `_HI_DISABLE_*` toggle is read _bare_, and a bare read of
an unset variable is fatal under bash's `set -u`. The toggles must always
exist: `common/core.sh` defaults the `_HI_TOGGLES` list (defaulted, never
assigned, so settings.sh and paths.sh's gate still win), `common/config.fish`
mirrors it with `set -q X; or set -gx X 0`, and `hi.sh`'s `_hi_fallback_rc`
emits `export X=0` lines from the same list for bash-less targets.

## HI.08 sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back — see HI.09 for why with `cat`.

## HI.09 cat-over-mv

A tempfile goes back over an existing file through the existing inode:
`cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in `scripts/lib.sh`;
`rewrite` in `packaging/stamp.sh` is the boundary-forced copy). `mv` would
transplant mktemp's 0600 mode onto the target and sever any hardlink/ACL — a
dotfile manager's hardlinked `~/.bashrc` must see the new content.
Non-atomicity is fine for single-user rc files; `common/targets.sh`'s cache
swap keeps `mv` for atomicity over a file it owns, and the payload stager
keeps it over a stage nothing links to (HI.39).

`_hi_write_back` also reads the target's mode before the `cat` and `chmod`s it
back after: a Windows Git Bash run lost a `604` mode across this exact rewrite
despite going through the existing inode. The `stat -c`/`stat -f` fallback is
the GNU/BSD split `common/config.fish`'s mtime probe already uses.

## HI.10 strftime %e over %-e

`date +%-e` (no-padding) is a GNU extension; BSD strftime prints the literal
characters. `%e` is the portable day-of-month.

## HI.11 LC_ALL=C sort

Under a UTF-8 locale, BSD `sort` exits "Illegal byte sequence" on non-UTF-8
input, having printed nothing while the pipeline carries on. Any sort whose
input isn't guaranteed clean UTF-8 is pinned to `LC_ALL=C`.

## HI.12 bytes vs columns

`${#var}` counts bytes, not display columns; multibyte characters inflate it,
and a banner padded by it comes out narrow. Width math around user-visible
strings computes column counts explicitly (`changes_w` in `common/header.sh`,
`_hi_visible_len` in `scripts/table.sh`).

## HI.13 command -v fallthrough

`export _HI_LS_BIN="$(command -v eza || command -v exa || command -v ls)"` in
`config/aliases.sh`, with the aliases built on the result: resolved at
source time, valid in sh, bash, zsh _and_ fish, and ending in a binary every
target has, so no alias points at a missing one.

A second, **narrower** chain over the same family delivers flags only to the
tier that parses them: `$_HI_BAT_BIN` is `bat || batcat` where
`$_HI_CAT_BIN` is `bat || batcat || ccat || cat`, so bat-syntax options
attach behind `[ -n "$_HI_BAT_BIN" ] && alias ... || true` and ccat and
coreutils `cat` get the bare binary.

Every chain runs before any alias exists, the overlay's `aliases.sh`
included (it is sourced last): in zsh and dash `command -v name` returns an
_alias's_ definition once one exists, so an overlay `alias cat=...` ahead of
the chains would leave `$_HI_CAT_BIN` holding the alias body.
`tests/config/alias_fallthrough_test.sh` is the regression test.

## HI.14 _hi_on_exit

bash's `trap "$cmd" EXIT` fires at real shell exit wherever it was set. zsh's
does not: an `EXIT` trap (`TRAPEXIT` included) set inside a function fires
when _that function_ returns — and `_hi_on_exit` (`common/core.sh`) is itself
a function, so every caller's cleanup fired at once, silently. `add-zsh-hook`'s
`zshexit` array is the one mechanism exempt from that scoping (zsh's own
completion system uses it for the same reason), so the zsh arm autoloads it
and registers a uniquely-named function there instead of touching
`trap`/`TRAPEXIT`. Outside a subshell, `_hi_on_exit` is the only way shared
code registers a cleanup trap.

## HI.15 strict-mode bracketing

Files sourced into an interactive shell (`common/core.sh`, `hi.sh`,
`common/git_prompt.sh`, `common/env_prompt.sh`, ...) set `set -euo pipefail`
at the top _and disable it at the end of their own code_: left on, any later
non-zero status or unset variable kills the user's session. `common/bash.sh`
never enables it at all. The bootloader and fallback
rc do the same on targets — forgetting it there breaks `hi <target> <command>`
outright.

## HI.16 no-fork reads

On per-prompt/per-startup paths, builtins over binaries: `read -r x < file`
instead of `$(cat file)`, `${target%/*}` instead of `$(dirname ...)`,
`${row%%$'\t'*}` instead of `| cut -f1`. A few forks per prompt is the whole
latency budget.

## HI.17 base64 armor

The payload is armored with `base64` first: pure ASCII transport encoding
(no crypto), shipped on strictly more hosts than `openssl` — coreutils,
busybox, macOS/BSD, and Git Bash. `openssl base64` stands in where `base64`
is missing, on either end: stock OpenBSD ships LibreSSL and no `base64(1)`.
Decode tries GNU/busybox `-d` first, then old BSD/macOS `-D`; the failed flag
parse consumes no stdin, so the fallback still sees the whole stream. `tr`
runs first because GNU `base64 -d` tolerates newlines but not spaces, and a
transport that folds newlines into spaces would otherwise break it. openssl
gets every space and newline stripped and `-A` instead: LibreSSL's line mode
silently garbles one long line, which is what macOS's `base64` writes.
The decoder is picked by `command -v`, not chained after `-D`: a `-d` that
failed on a corrupt stream has read it, leaving openssl nothing to decode.
openssl exits 0 on bad input, so a corrupt stream surfaces at `tar`.
`$_HI_UNARMOR` only ever runs inside the sh bootloader — the login shell
never parses its braces (fish couldn't).

## HI.18 sh -c wrapping

Every command hi sends meets the target's _login_ shell first, which may be
fish — and fish parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is the transport's job, not per-site care
(unwrapped, the boot probe's `if ...; then ... fi` does not even parse on a
fish-login host). Quoting is single-quote-and-escape rather than `printf %q`, which
backslash-escapes every space — unreadable in the code and in an `ssh -v`
log, and one more thing for fish to differ about.

## HI.19 stdin transport

The bootloader travels over **stdin of the first of two ssh calls multiplexed
on one connection** (one authentication), never as an argument: Linux caps a
_single_ argv entry at 128KB (`MAX_ARG_STRLEN`) however large `ARG_MAX` is —
a hard ceiling on payload growth that stdin does not have. Two calls because
the second's stdin belongs to the interactive session. The script goes as
plain text and is `cat` into place; only the streams _inside_ it are armored —
armoring the whole script spent a third of every session's bytes re-encoding
ASCII.

The write doubles as the probe (`_hi_boot_probe`), and `_hi_boot_why` reads
its status: the directory came back and the session runs; `sh` ran but found
neither `base64` nor `openssl` (exit 64) or nowhere to `mktemp` (65), and hi
names the missing piece and hands over the host's own session; something that
was not `sh` answered — a `ForceCommand` or a `command=` key, told by an exit
of 0 or any stdout, neither of which a missing `sh` produces — and hi says so
and hands over the same; or nothing ran at all (stock Windows OpenSSH), and
the session falls through to the PowerShell branch rather than half-landing.

## HI.20 fallback rc

The no-bash target's rc is consumed by sh, zsh _and_ fish (`_say_hi`'s
`fish -C` branch), so every line must be valid in all three — `export
NAME=value` and `[ -f x ] && . x` are; anything shell-specific is appended by
that shell's own arm. Toggle defaults come first so the files after them still
win. `_HI_REMOTE_SESSION=1` is exported because this path never reaches
`load.sh`. `settings.sh` keeps its `[ -f ]` guard because a bare `.` on a
missing file abandons the rest of the file in ash/dash. `_HI_CONFIG_DIR` points
at the target's own `overlay/`, where the shipped overlay was unpacked.

## HI.21 baked prompt

The bash-less tiers' PS1 is baked on the client — colors resolved once, the
username read once — because busybox ash does not run command substitution
inside PS1 at all: handed a live `$( )`, it prints the substitution's _text_.

## HI.22 TERM fallback probe

ssh forwards the client `TERM` verbatim, and a TERM the target has no terminfo
entry for (ghostty's `xterm-ghostty`, kitty's `xterm-kitty`) breaks
clear/backspace before hi even matters. The bootloader skips the probe for
ubiquitous names; anything else must be found in a terminfo tree — plain dirs
and the BSD/macOS single-hex-char layout both checked — or is swapped for
`xterm-256color`. Always on: there is no setting to keep a TERM the target
cannot render.

## HI.23 bash --rcfile -i

`bash --rcfile X -i` needs both flags, in that order: without `-i` bash decides
it isn't interactive and ignores the rcfile (`hi <target> <cmd>` doing nothing
from a script or cron), and `-i` must come _after_ `--rcfile` because bash's
long-option pass ends at the first short option. fish differs twice: `exit`
inside a sourced file only unwinds the source, so the fish arm feeds the rc to
`-C` instead — and `exit` inside `-C` does not stop fish starting its
interactive reader when stdin is a tty, so the command from `hi <target> <cmd>`
rides `-c`, which fish runs after `-C` and then exits from. sh and zsh get the
command appended to their rc (`_hi_command_append`).

## HI.25 session-shell ranking

The session shell is the user's login shell when hi styles it, else the first
installed of the names hi styles; bash is the floor because `load.sh` only
runs where bash exists. The tail is not a literal: `_hi_session_shell` walks
`common/core.sh`'s `$_HI_SHELL_TREE` (`fish zsh bash dash ash sh`) and drops
the tiers that need bash to be _missing_, leaving `fish > zsh > bash`;
`hi.sh`'s `$_HI_SHELL_LADDER` is the same tree with bash removed. One list,
two consumers.

`login` leads because a ranking that leads with fish hands it to anyone whose
box has it, so a user whose login shell is zsh-with-oh-my-zsh would never see
their own setup.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi` and a space — say-hi's most
latency-sensitive path and its slowest (every backend but ssh is a
subprocess, one per CLI on `$PATH`). Two internal knobs keep it honest -
environment variables the suites and the bench set, not settings.

`_HI_PROBE_TIMEOUT` — seconds a backend CLI gets (default 2; needs GNU or
busybox `timeout`; shared with `common/core.sh`'s `_hi_probe`). It bounds the
**whole sweep**: backends start together and are read back in roster order,
so four wedged daemons cost one ceiling. A host with no writable scratch
directory falls back to the in-turn sweep — slow, not wrong. The cap is a
SIGTERM with a SIGKILL 200ms behind it (`timeout -k 0.2`): a CLI may defer a
TERM while it finishes something — rootless podman does for the whole of its
runtime setup, which on a fresh `$HOME` can outlast the cap — and without the
KILL the ceiling is a request.

`_HI_TARGETS_TTL` — seconds a result is reused (default 5, 0 disables); a
just-started container may not appear until it expires. **Nothing invalidates
it** but the clock. Two offset windows stack — the file cache in `targets.sh`
stamps when it was written, the in-shell memo in
`common/bash.sh`/`common/zsh.zsh` when that shell last read the file — so
worst-case staleness is close to **twice** the TTL. Only `_HI_TARGETS_TTL=0`
turns both off.

Past the TTL the file is not discarded at once. Until the copy is ten minutes
old (`stale_for` in `targets.sh`) a TAB is answered **from it, immediately**,
and the replacing sweep runs behind it - no TAB inside a working session waits
on a daemon. A lock directory beside the cache allows one refresh at a time,
taken over if it outlives any real sweep. Older than that, the sweep is waited
on again, like a first TAB. `_HI_TARGETS_TTL=0` skips all of this.

## HI.29 apostrophes in substitution comments

bash 3.2 scans a `$( ... )` command substitution with a simple quote matcher: a
comment line _inside_ one containing a lone `'` reads as an unterminated
string, and the whole file dies at parse time. bash 4+ parses substitutions
recursively, which is why this only surfaces on macOS. Keep comments inside
`$( )` apostrophe-free, or hoist them above the assignment. The lint greps
cannot see this one; `tests/targets/ssh_test.sh` runs `bash -n` over every file
in a real 3.2 container.

## HI.30 indirect invocation

Test suites hand their case functions to `_hi_check`/`_hi_case`/`_hi_par_case`
as `"$@"`, or register them as trap hooks, so nothing in the file calls them by
name. shellcheck reads that as dead code (SC2329), so every suite carries a
file-level `# shellcheck disable=SC2329`.

## HI.31 porcelain branch.oid

`git status --porcelain=v2 --branch` already carries HEAD's sha on its
`# branch.oid` line, so the detached-HEAD label reads it out of the stream the
prompt is already parsing instead of forking `git rev-parse`. The `rev-parse`
beneath it is a fallback for a porcelain stream too old to carry that header.

## HI.32 starship deference

`_HI_PROMPT_TOOL` hands the prompt to a prompt program - starship,
oh-my-posh, powerline-go, powerlevel10k, oh-my-zsh, oh-my-bash, bash-it, or
tide - keeping hi's header and aliases. It is a list, each shell taking the
first entry that fits it and is present; `hi` is hi's own prompt and ends the
walk.
Unset is the whole roster (`common/core.sh`'s `_HI_PROMPT_TABLE`, one row
per program - the shells it fits, how it is found, the overlay member its
home config rides as - frameworks ahead of the programs that fit every
shell; `_hi_prompt_row` answers to a program's name or a member's), so a
prompt already in use at home is the default rather than something hi draws
over; `hi` is the opt-in back, and the one entry that unhooks a program the
rc already started (bash's PROMPT_COMMAND, zsh's precmd_functions, fish's
right and mode prompts) - an unset list, or one that ran out, leaves that
program drawing. A target never looks for itself: `hi.sh`'s
`_hi_prompt_list` resolves the list on the client - the setting, else what
this machine has installed - and ships it as a session variable (HI.47), so
an unset setting on a target is hi's prompt, not whatever the box happens to
carry.

`common/core.sh`'s `_hi_prompt_tool <shell>` is the single predicate:
starship, oh-my-posh, and powerline-go count where the binary is, and a
framework through the shell's own `_hi_prompt_fw` - loaded by the rc
already, or, on a target only, installed where its README puts it and with
home's file to draw. At home the rc is the user's whole answer, so an
installed-but-unloaded framework (a distro's powerlevel10k package nobody
adopted) is never started there.
`common/config.fish` mirrors the rule since fish cannot call it. Each program
is started the way its README wires it: starship and oh-my-posh by `eval`ing
`init <shell>`; powerline-go from PROMPT_COMMAND, a precmd, or fish_prompt;
powerlevel10k and oh-my-zsh's libraries and oh-my-bash sourced when the rc
did not (oh-my-zsh's libraries alone, oh-my-bash without plugins, and hi's
aliases put back over theirs); bash-it the same way, `BASH_IT_THEME` pointed
straight at home's packed theme file when the rc had not loaded it already -
its own loader takes a literal path there, so unlike oh-my-bash this needs no
separate theme-file step; tide by leaving its autoloaded fish_prompt alone.

Unhooking a program the rc already started (`_HI_PROMPT_TOOL=hi`) means
different surfaces per program: bash's `PROMPT_COMMAND` string for starship,
oh-my-posh, and powerline-go's own hooks, but bash-it's real hook lives in
the `precmd_functions` array bash-preexec keeps (most bundled themes call its
`safe_append_prompt_command` rather than assigning `PROMPT_COMMAND`
directly), so `common/bash.sh` clears that array too - bash has no zsh-style
`:#` array filter, so a rebuild loop rather than one substitution.

Home's config rides the overlay (HI.41) and applies on a target only
(`_HI_REMOTE_SESSION=1`), over whatever the target has: `$STARSHIP_CONFIG` /
`$POSH_CONFIG` (and `$POSH_THEME`, which older oh-my-posh releases read) from
`common/paths.sh` (paths.sh because fish sources it
natively), `p10k.zsh` sourced after powerlevel10k, the oh-my-zsh, oh-my-bash,
or bash-it theme file the home rc names sourced over the framework, and
tide's `tide_*` universal variables exported as globals - exported because
tide renders in a background `fish -c` that must see them over the target's
own. Absent every program, the prompt is hi's, silently.

## HI.33 derived tree location

`$_HI_HOME` is the directory _containing_ `say-hi`. Every file that needs the
tree derives it from its own path rather than defaulting to `$HOME`: the
default was right for a standard install and wrong everywhere else, and when
wrong it silently read _another tree_ (the platform e2e jobs sourced a tree
under `/Users/runner` that was never there). Each file asks only when
`$_HI_HOME` is unset, so an outer export still wins and costs no fork.

`common/core.sh` owns the answer; everything that merely _needs_ the tree
reaches core.sh through its own path. The files that derive have nothing above
them to ask through:

| where                                                           | how                                                                                                                                                                                    |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `common/core.sh`                                                | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`; answers for every file sourced through it                                                                                              |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh`               | the same behind a `readlink` walk, so `~/.local/bin/hi` (a package's `/usr/bin/hi`) answers the tree it links to. Three copies: each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh`                               | `${BASH_SOURCE[0]}` - entry points that _export_ for children                                                                                                                          |
| `tests/test_lib.sh`                                             | `${BASH_SOURCE[0]}` only, `$_HI_HOME` or not - the harness sits in the tree it tests, and `_hi_host_tree_check` warns when `$_HI_ROOT` names another                                   |
| `scripts/doctor.sh`, `scripts/preview.sh`, `scripts/update.sh`  | `${BASH_SOURCE[0]}`, then `$_HI_HOME` if set - the standalone-entry form below                                                                                                         |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; bash cannot parse `%x`, so core.sh's arm is `eval`'d                                                                                         |
| fish (`common/config.fish`)                                     | `sh -c 'cd -P "$1/../.." && pwd'` - a builtin-only substitution would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical                    |
| `common/bash.sh`                                                | `$_HI_HOME` first, its own path as the fallback - `hi.sh`'s preamble and `install.sh`'s rc line both set it before this file is sourced                                                |

**The standalone-entry form, and why `$_HI_HOME` wins in it.** A script run
on its own derives from `${BASH_SOURCE[0]}` only as the fallback:

```sh
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
```

With `$_HI_HOME` set, _everything_ comes from there, core.sh included:
reaching core.sh through the script's own path while `$_HI_ROOT` came from
`$_HI_HOME` runs two trees in one process, silently.

No file falls back silently: `hi.sh` prints `set _HI_HOME to the directory
that holds it` and exits when the derived path holds no tree. A _target_ needs
no such rule — a session's tree is the one hi just unpacked, its `$_HI_HOME`
exported by the script that unpacked it; a say-hi the target already has is
that machine's own install, and a session never reads it.

`tests/lint/drift_test.sh`'s `lint_home_default` greps the tree, `.md`
included, for the retired `$HOME` default — a doc teaching it is what a
packager reads.

## HI.34 test suite preamble

Every suite under `tests/` opens with the same four lines — four separate
mechanisms, not boilerplate:

```sh
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
```

`$_HI_TEST_LIB` is exported by `common/paths.sh`, so under `test_runner.sh` the
harness is found through the tree the runner resolved. The `${...:-}` tail is
the fallback for running a suite directly; its `../` depth is the suite's
distance from `tests/`, so a suite that moves has to have it re-counted.

`test_lib.sh` sources `common/core.sh` itself; a suite sources the harness and
never core.sh, or core.sh initialises twice, the second time after the harness
has moved `$XDG_CONFIG_HOME` into the scratch dir. The `# shellcheck source=`
line is a directive the linter follows, and `# shellcheck disable=SC2329` is
HI.30. Both stay verbatim above their statement.

## HI.35 payload comment and whitespace strip

Every file `hi.sh`'s `$_HI_STRIP_NAMES` matches — the shell files, `*.lua`,
and data files such as `colors`, `vimrc`, and `tmux.conf`, whose prose
headers document the _installed_ copies — is comment-stripped by
`_hi_strip_awk` on its way into the payload or overlay; about 40% of the
shipped shell is comment. vimrc's comment character is `"`, init.el's `;`,
and lua's `--`, each its own rule. Lua's `--[[` block form is deliberately
not one: the strip is line-wise, so a block opener would go and its body stay
— which is why the shipped `init.lua` uses line comments only.
`bench_payload_readme_badge` checks README's badge against the result, through
`packaging/stamp_badge.sh --check`.

**Blank lines and leading indentation go the same way**: no dialect the
payload carries reads either, and the indentation alone is 3% of the payload.
Both are trimmed under the heredoc rule below, so a body a target reads as
data keeps its shape (`<<-` still strips its tabs, on the target). A line
continuing a `word\` keeps its indentation too: there it is the only
separator, and `"a:b\⏎ c:d"` stripped would read `a:bc:d`. Trailing
whitespace is not handled: the lint forbids it in the tree already.

Two rules keep it safe. **Full-line comments only**: an inline `#` cannot be
told from `${x#y}`, `$#`, or a `#` in a string without a real parser. **Never
inside a heredoc**: those bodies are data the target reads, one of them
`hi --help`. The comment test runs _before_ the heredoc-open test: a comment
mentioning `<<WORD` would otherwise open a heredoc that never closes and
silently stop stripping the rest of the file.

`tests/hi/payload_test.sh` pins the rest: no full-line comment survives outside
`hi.sh`'s heredocs, every code line survives but for its own indentation,
nothing blank or indented survives outside a heredoc while an indented heredoc
body does, the result still parses, and `hi.sh` keeps its exec bit (HI.39).

## HI.37 zsh pattern-in-variable

`_hi_ssh_pattern_hit` (`common/core.sh`) matches a name against `Host`/`Match
host` glob patterns from `~/.ssh/config`. `*` and `?` mean the same in ssh's
syntax as in a `case` pattern; the difficulty is trying each pattern in a way
that survives both bash and zsh.

The tokens are peeled off by parameter expansion, never `for pat in
$patterns`: zsh does not word-split an unquoted variable, so that loop never
iterates, and bash also pathname-expands it, so a bare `*` — the commonest
`Host` line — becomes the cwd's file list. Then zsh does not treat `*` in a
_variable's_ value as a wildcard unless `GLOB_SUBST` is set — a `case` that
never matches. `${~pat}` turns it on for that one substitution rather than
the whole function; bash cannot parse it, so the zsh arm is `eval`'d behind
`$ZSH_VERSION`.

A `!`-prefixed token (ssh's per-pattern negation) is not honored as exclusion —
it survives as a literal pattern nothing is ever named, so it is inert rather
than wrong; the cost, a wrongly-colored excluded host, is cosmetic.

## HI.38 split tar and gzip

`_hi_tar_gz` (`hi.sh`) runs `tar -c -f - | gzip -n` rather than `tar -c -z -f -`. The
two userlands pad differently, and only one pads something that survives
compression: GNU tar rounds the _uncompressed_ archive up to the 10240-byte
blocking factor and then gzips it, so its trailing NULs cost about thirty
bytes; bsdtar — macOS's `/usr/bin/tar` — pads the _compressed output stream_,
appending raw NULs after the gzip member, so a one-step payload built on a BSD
client is a multiple of 10240: about 27% waste on a stock payload and a flat 54× on
a two-file overlay (189 B against 10240). Split, the steps agree with GNU tar
to within a few bytes under both userlands and are byte-stable run to run.

`${PIPESTATUS[@]}`, not `$?`: `hi.sh` turns `pipefail` back off for
interactive sourcing, so a failing tar would otherwise hide behind a
successful gzip and ship a truncated payload — both halves are checked.

A client with no `gzip` falls back to `tar -c -z -f -`, which is a working
payload on exactly one userland: libarchive's tar (macOS's `/usr/bin/tar`)
compresses in-process, padded as above, while GNU's and OpenBSD's implement
`-z` by exec'ing `gzip(1)` off `$PATH` and have nothing left to try. So the
fallback is not "no gzip is survivable" — it is "a tar that compresses on its
own is". `_hi_can_gzip` asks which one this is (free where `gzip` is present,
else one real `tar -c -z` of `hi.sh` — `/dev/null` is not reliably stat'able
under Git Bash), `_hi_require_packer` refuses by name in both `_say_hi` and
`_say_hi_container` rather than letting the target receive an empty archive,
and `hi --doctor` reports the same three verdicts.

Every tar in `hi.sh`, client and target side, takes dash-style options:
OpenBSD's tar reads each word after an old-style `cf <file>` as a member name,
so `tar cf - -C dir` archives a file called `-C` there.

## HI.39 payload staging

`_hi_payload_tar` (`hi.sh`) ships the tree, comment-stripped (HI.35), through
`_hi_stage_tar`, which the overlay shares. What ships never depends on a
toggle: `$_HI_PAYLOAD` is whole directories, every toggle is read where it
applies, and a session that switched something off carries the file and
leaves it alone (a per-toggle trim would save about a kilobyte at the cost of
a cache key, a second table, and an exclusion list).

**Staged, in a subshell, under a trap.** The strip rewrites files and the tree
is not hi's to touch, so it is copied to a `mktemp -d` stage through an
intermediate tar _file_ (`-h` resolves symlinks) — a `tar | tar` pipe ends in
EPIPE when the reader stops before a GNU writer's record padding. The subshell
lets cleanup be an `EXIT` trap rather than an `rm` on each way out, so a ^C
mid-build leaves nothing in the client's tmp. `INT` and `TERM` are trapped
explicitly to `exit`, since a signal that kills the subshell outright never
reaches the `EXIT` trap; set in the function's own shell, the trap would
replace the one `_hi` installed for its error log.

**One `find -exec awk +`, and no rename.** The stripper buffers each file and
writes it back over itself in `END`, once every file in the batch has been
read. The shape before it put each stripped copy in `<file>.strip` and renamed
it back, which cost one `mv` a file — 40 in a `hi --doctor`, which stages
twice, and the largest external cost that command had — and renaming over a
file a runner still held open broke the Windows jobs. Writing in place leaves
every mode alone too, so the exec bit `hi.sh` needs for the relay survives
with nothing to note and restore; either way nothing links to a stage just
unpacked, so HI.09's four-process `cat` buys nothing here.

## HI.40 hand-rolled sh quoting

`_hi_shquote` (`hi.sh`) turns a value into one single-quoted `sh` word by
walking it with prefix/suffix removal rather than the obvious
`${2//\'/\'\\\'\'}`: bash 3.2 — the floor, and the bash macOS ships — leaves
the quoting of the replacement word in the result, so that spelling emits a
word no `sh` can parse. Prefix and suffix removal answer the same on every
bash.

Everything `hi.sh` bakes into a script for the target is text the target's
shell will parse, and some of it is data: `$DOMAIN` off argv,
`$_HI_TARGET_TAG` out of a free-text `# Tags:` comment, `$_HI_RELEASE` off
`git describe --dirty`. An unescaped `$`, quote, or backtick in any of them
breaks the bootloader's parse and lets the target run a command substitution
it should not. `_hi_ssh_sh` quotes its `sh -c` word through the same function,
so the transports cannot drift into two dialects, and `_hi_env_each` hands
its per-transport format values already quoted (`%s=%s`, never `%s="%s"`), so
quoting is one decision rather than one per transport.

## HI.41 overlay stream

The user's config overlay (`$_HI_OVERLAY_FILES` in `hi.sh`) lives outside the
tree, so it travels as a second, much smaller archive rather than inside the
payload. It lands in an `overlay/` of its own beside `config/`, with
`$_HI_CONFIG_DIR` pointing there, never over `config/`: `config/aliases.sh`
sources `$_HI_CONFIG_DIR/aliases.sh` last, so one directory would make it
source itself forever. It is omitted when there is nothing to send.

The prompt programs' configs, eza's `theme.yml`, and bat's `bat.conf` ride it
so a tool's config on every target is the one in force at home:
`_hi_overlay_src` packs the overlay's copy when there is one, else the file
the tool itself reads on the client (a prompt program's only when
`_hi_prompt_list` names it), so there is one copy to edit and none to drift.
`common/paths.sh` points each tool's own variable (`$STARSHIP_CONFIG`,
`$EZA_CONFIG_DIR` - the directory, since eza fixes the file name - ...) at
the overlay on a target only, and the shell files source or read the
frameworks' (HI.32). The stager keeps nothing of fish's universal variables
but the `tide_` lines, since `set -U` holds whatever a user ever put there.

The editor rcs, `tmux.conf`, and micro's `micro/` files ride it for the same
reason `colors` and `packages.d` do: the tree copy is a default, and
`common/paths.sh` points each `$_HI_*RC` at the overlay's when there is one
(HI.57). Left out of the stream, that guard could only fire on the client — an
override working locally and silently reverting on every target, the
asymmetry `paths_test.sh`'s guard/roster pin catches one layer up.

That cascade is wholesale, so a member that shadows a tree default makes the
default dead weight: a connect hands `_hi_payload_excl` its member list, and
`_hi_payload_tar` drops those files (`$_HI_OVERLAY_SHADOWS`; never
`aliases.sh`, which is additive) from the stage, cached under a key of its
own. Dropped from the stage rather than with tar's `--exclude`, which
OpenBSD's tar lacks. Only a caller holding the list cuts anything:
`_hi_wire_bytes` has none and measures the stock tree (HI.44), and the
container arm, where the two archives travel separately, sends the defaults
after all when the overlay's copy fails. A file still under a pre-1.0 name
(`$_HI_OVERLAY_RENAMES`) is not a member, so it cuts nothing and the default
it no longer overrides keeps riding.

`ssh_tags` is the one member with no file behind it on the client:
`_hi_ssh_tags_file` cuts the `# Tags:` lines and the `Host`/`Match host` line
under each out of `~/.ssh/config` into the runtime dir, in ssh_config's own
shape, so `_hi_ssh_host_tag` on a relaying box walks it with the walker it
already has - after its own config, and only in a remote session. Only tagged
blocks ride, so an untagged block that would have answered first at home is
not there to: a name both it and a later tagged wildcard match reads as
tagged on the second hop.

## HI.43 container target grammar

A container target may name what to run _in_ as well as where: `pod/container`
for kube, `alloc/task` for nomad — one spelling for both, since a task and a
container are the same idea here, and a suffix rather than a flag so completion
can offer the pairs (`_hi_outer` / `_hi_inner` in `hi.sh`). Only those two
split: a container name on any of the docker-compatible family (HI.51) is
taken whole, having no inner unit and `/` being legal in it.

kube adds `[[context:]namespace:]pod[/container]` (`_hi_kube_split`). `:` is
the separator because no ssh host, container name, or allocation id may carry
one, so a prefixed name can only mean a pod; no prefix means whatever kubectl
points at, and `common/targets.sh`'s `list_kube` emits the same spelling for
pods outside the current namespace. A multi-container pod resolves on the pod
half; kubectl checks the container half when the session runs and fails loudly
on a missing name — better than declining silently and falling through to ssh.

docker and podman also answer to a compose service name
(`_hi_compose_container`) when exactly one running container carries that
label. Ambiguous (two projects, same service) and absent both fail rather than
guess — a wrong guess lands a session in someone else's container — and the
lookup runs only when the literal name does not resolve, so the common case
pays one inspect. nerdctl and finch are left out as unverified: a `.Label`
template or `label=` filter one of them rejects would fail the lookup rather
than decline it.

## HI.44 wire size token

The connect line prints the size of the script the session sent, but the
script cannot know its own size while being assembled. `_say_hi` (`hi.sh`)
builds it with `$_HI_SIZE_TOKEN` (`@@SIZE@@`, wider than any figure) standing
in, measures `${#script}`, and substitutes the human figure back — honest to a
few bytes, since the streams inside are already armored and the script goes
over the wire as it stands. `_hi_wire_bytes` — what `hi --doctor` and the
README badge quote — assembles the same script through the same
`_hi_remote_script` rather than summing the armored streams:
summing skips the boilerplate around them and reads ~6KB low, and a badge has
to show the number the user sees. No overlay is counted, since which files
ride is a question about a target - and none of the tree defaults one would
shadow is cut (HI.41), so the figure is the stock tree's on any client.

## HI.46 session rc directory

`load.sh`'s `_hi_session_rc_setup` writes one rc per shell into a `mktemp -d`
of hi's own and exports `$_HI_SESSION_RC` at it. The shell a user types at is
**not** the one `hi.sh` starts: `bash --rcfile hi.bashrc` starts the
_bootloader_, which sources `load.sh` and calls `load()`, which starts the
session shell. A bare `$shell -i` there would read the target's `~/.bashrc`,
so the session shell is pointed at hi's own rc and the target's rc files are
never written.

Each generated rc sources the target's own first (`~/.bashrc`, `~/.zshrc`, and
`~/.zshenv` — `ZDOTDIR` moves _all_ of zsh's startup files, not just `.zshrc`),
then hi's on top, so the host's configuration still applies underneath.

Three variables are exported; which shell needs which is the design:

| shell         | reached by      | inherited by a nested shell?   |
| ------------- | --------------- | ------------------------------ |
| zsh           | `$ZDOTDIR`      | yes — free                     |
| sh, dash, ash | `$ENV`          | yes — free, interactive shells |
| bash          | `--rcfile`      | no — needs a wrapper           |
| fish          | `-C 'source …'` | no — needs a wrapper           |

`$ZDOTDIR` and `$ENV` reach any zsh or POSIX shell started inside the session,
however it was started, including by something that is not a shell. bash and
fish have no equivalent (`$BASH_ENV` is for _non_-interactive bash only), so
`config/aliases.sh` defines a `bash` and a `fish` wrapper off
`$_HI_SESSION_RC`. Both bodies begin with `command`: fish's `alias` builds a
function of that name, and without it `fish` would call itself forever.

The wrappers cannot cover a bash or fish shell nothing typed — a `tmux` pane
spawning a login shell, an editor's shell-out — which comes up as the host's
own. hi writes nothing into a target's login files
([COMPATIBILITY.md](COMPATIBILITY.md#what-would-change-an-answer) has the reasoning).

## HI.47 what a child inherits

`env | grep ^_HI_` in a process started from an interactive hi shell shows
core.sh's `_HI_CHILD_ENV` roster and nothing else with the prefix. The roster
is six names:

- `$_HI_HOME` and `$_HI_CONFIG_DIR` — the overlay on a target is wherever
  `hi.sh` put it, and cannot be re-derived;
- `$_HI_REMOTE_SESSION`;
- `$_HI_SESSION_RC` — HI.46's wrappers are re-defined in every nested shell;
- `_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT` — the knobs `sh targets.sh` reads
  straight off its environment from a completion.

It works by taking the attribute off, not by never setting it. fish parses
`common/paths.sh` alongside sh, zsh, and bash, and the one assignment all four
accept is `export NAME=value`, so every name it sets arrives exported —
over fifty. Each interactive rc (`bash.sh`, `zsh.zsh`, `config.fish`)
un-exports the lot as the last thing in its required block: `_hi_unexport` in
core.sh (bash `export -n`, zsh `typeset -g +x` — a bare `typeset` inside a
function declares a local), and a `set -gu NAME $NAME` loop in config.fish.
The values stay as shell variables: the header's clock reads
`$_HI_HUMAN_CENTRIC_DATE` on every render, the prompt reads the colour memos, and a `$( )` is a fork
rather than an exec; an alias that names a path expanded it at definition
time. Last in the block so the overlay's per-shell rc, which runs after it,
can `export` whatever it wants a child to see.

The flip alone is not enough because of the client's verdicts — `hi.sh`'s
`_hi_session_env`, pinned to core.sh's `_HI_SESSION_VARS`. Two of them
(`_HI_LOCAL_USER`, `_HI_LOCAL_HOSTNAME`) name the operator's workstation, the
one thing a target's process table should never learn from hi; they are not in
the roster, so a nested shell cannot inherit them. `load.sh`'s
`_hi_session_rc_setup` writes them into each session rc instead (HI.46), as
plain assignments between the target's own rc and hi's; fish, which shells out
to bash for the header and the colours, hands them to that one `bash -c`
through `__hi_bash`'s function-scoped exports (`set -fx`; a `-l` inside the
loop would be block-scoped and gone before the command runs).

Not covered: a POSIX `sh` started inside a session reads `$ENV`, which sources
`paths.sh` and exports the roster into _that_ shell again — dash has no
un-export. The bash-less fallback rc (HI.20) has the same shape for the same
reason. Both are tiers below what `load.sh` styles.
`tests/common/exports_test.sh` pins the contract: the child environment in
all three shells, config.fish's two mirrors against core.sh, `_hi_session_env`
against `_HI_SESSION_VARS`, every env read in targets.sh against the roster,
and the session rc's quoting round-trip in each dialect.

## HI.48 header cell hue resolution

`$_HI_HEADER_ORDER` (`common/header.sh`) lets any subset of seventeen words
print in any order, each cell carrying its own hardcoded color. The shipped
default is laid out so no two neighbors share a hue, but a user's order can
put any two of the sixteen colored words side by side; `check`, the
seventeenth, resets the hue tracking instead (below).

`_hi_collect_header_word` fixes this in one pass, no lookahead or backtrack:
it tracks the previous cell's hue in `$_HI_PREV_HUE`, and when a word's own
color would repeat it, swaps in that word's hand-picked alternate
(`_hi_header_word_alt`). "Hue" ignores the bold bit (`_hi_cell_hue`):
`\e[0;36m` and `\e[1;36m` both read as cyan and collide.

A single pass suffices because **every word's alternate has a different hue
than that word's own primary**, so a substituted cell can never itself
collide with what came before it. The shell does not enforce this; it is a
property of the hand-written table, and `tests/common/header_test.sh`'s
`test_header_word_alt_differs_from_its_own_primary` checks it mechanically.

An empty cell (`containers`/`jobs`/`pods` when that backend never answered)
leaves `$_HI_PREV_HUE` untouched rather than resetting it to empty —
resetting it would let the _next_ word compare against nothing and skip a
real collision two cells later. `check` resets it explicitly: the packages
block has its own palette (`$_HI_YES`/`$_HI_NO`), unrelated to header cell
hues.

## HI.50 truecolor color schemes

`_HI_COLOR_SCHEME` (`common/core.sh`) remaps what the twenty-four palette
names render as; it never adds a name. `_hi_hash_color`, the
`config/colors` pins, `_hi_color_escape`, and `hi --preview colors` all keep
the same vocabulary, so a scheme is invisible to everything that reasons
about a color by name - only the bytes a name turns into change. The names
are the terminal's twelve plus twelve extras (orange, pink, teal, ...) that
no 16-color code spells: `_HI_COLOR_FALLBACK` gives every slot its
`<bold><hue>` pair - an extra's is the nearest of the sixteen - and with no
scheme the first twelve render as that pair alone while the extras carry a
built-in hex, so a truecolor terminal shows an orange host as orange without
anyone choosing a scheme. `_hi_color_base` is the pair as a name, for zsh's
`%F{}` and fish's `set_color`, which know the sixteen and nothing else.

A `config/colors` row may also carry its own hex, in an optional fourth
column, and that is the one thing that outranks the scheme — for that pin
only. `_hi_colors_scan` joins it to the name (`brred#ff5f5f`) and
`_hi_color_split` takes the two apart again, so the pinned color travels as
one string through the memos, `$_HI_TARGET_COLOR` over the wire and
`hi --preview colors`' grouping, and only the three readers above know it is
two halves: the name is still the 16-color half of the escape (and all a
terminal without truecolor is given), the hex replaces the scheme's word in
the `38;2` triple.

Those bytes are **one SGR**, `\e[<bold>;3<n>;38;2;<r>;<g>;<b>m`: the
16-color pair first, the 24-bit triple after it. A terminal that ignores
`38;2` keeps the first; a capable one applies the last foreground it was
given. One escape rather than two keeps every reader of a cell's leading
escape working unchanged - `_hi_visible_width` strips one prefix,
`_hi_collect_header_word` cuts at the first `m`, `scripts/table.sh` and the
suites' `_hi_strip_ansi` match `\e[[0-9;]*m` - and `_hi_cell_hue` (HI.48)
needed only to accept `;` as well as `m` after the slot digit, which is
still the hue.

The hex table is a fixed-width string sliced by offset (`_hi_scheme_hex`):
no arrays, because zsh indexes them from 1 and sources this file; no
separate data file, because the payload strips comments and the twenty-four
six-digit words are the only bytes that cost anything on the wire. hi ships
**no named schemes** — the only table in the tree is the default one, whose
first twelve slots are `000000` (meaning "the terminal's own") and whose
twelve extras carry a built-in hex. A scheme is always the user's own.
`_hi_assign_palette` builds the exported `$RED..$BRCYAN` through the same
primitive as `_hi_color_escape`, so the two can never disagree and
`scripts/configure.sh`'s previews can rebuild the palette under a pending
answer.

**The scheme is that same string, in the setting.**
`_hi_scheme_words` reads `$_HI_COLOR_SCHEME` by the same offsets and answers
24, 48, or 0: exactly that many six-digit hex words one space apart is a
scheme, anything else — a leftover name, a typo, nothing — renders as the
default. Forty-eight words are two banks of the twenty-four names:
`_hi_scheme_hex` takes slot indexes 0-47 and folds 24-47 onto 0-23 for every
table but a 48-word list, and `_hi_color_escape_at` reads the 16-color half
at the index mod 24, so a second-bank escape wears its name's
`\e[<bold>;3<n>` and every hue and width reader above still works. Only
`common/header.sh`'s packages check reads the second bank:
`_hi_packages_palette` rebuilds `_HI_YES`/`_HI_NO` from it per render, after
resolving the ramp, because the ramps are the palette variables and those are
the first bank by contract. `scripts/lib.sh`'s `_hi_scheme_ok` and
`_hi_scheme_label` are the validator and the preview/doctor label; core.sh
only ever renders.

**The packages check's ramp is the same shape, one level down.**
`$_HI_PACKAGES_PALETTE` is eight `_HI_COLOR_NAMES` words — four for
installed, four for missing — and `_hi_ramp_ok` (`common/core.sh`, beside
the vocabulary it checks against, so `scripts/doctor.sh` reaches it without
sourcing `header.sh`) is the one judge: `_hi_packages_palette` falls back to
`$_HI_PACKAGES_RAMP`, the shipped ramp as one string, whenever it says no,
and `scripts/lib.sh`'s `_hi_ramp_label` names the same three shapes the
scheme label does. Like the scheme, there are no named ramps to pick from —
`hi --configure` does not ask about either, and neither is in a preset's
vocabulary.

The gate is `_hi_has_truecolor`: `COLORTERM` (`truecolor` or `24bit`), with
`_HI_TRUECOLOR` overriding both ways. ssh never forwards `COLORTERM`, so
`hi.sh`'s `_hi_session_env` ships the client's verdict as `_HI_TRUECOLOR`
beside `_HI_ASCII` - the escapes render in the client's terminal, and the
target must not guess from its own environment. The scheme name itself needs
no transport: `settings.sh` is in the overlay. zsh takes `%F{#rrggbb}` from
5.7 (`common/zsh.zsh`, behind `is-at-least`) and fish takes `set_color hex
name`, a list it resolves to the first entry it can render, so both fall
back to the plain name on their own.

## HI.51 docker-compatible CLI family

docker, podman, nerdctl, and finch take the same `ps --format`, `exec -i[t]`,
and `container inspect -f` grammar, so hi has one container arm and tries all
four, in that order. Each member is its own kind: `common/targets.sh` builds
its roster from the family and emits `<name>\t<cli>` per lane, `hi.sh`
generates one `_HI_BACKENDS` row and one predicate per member at load, and
`common/header.sh` starts one probe lane per member on `$PATH`. A member that
is absent costs a builtin `command -v` on TAB and one background subshell per
`hi <target>` in `_hi_resolve_backend`; a present one is one parallel lane,
capped like every other (HI.26). That is the whole cost of a member nobody
has installed, which is why the family is the same four words everywhere and
not a setting: there was nothing for a shorter list to buy.

The words are spelled twice: `common/core.sh`'s `$_HI_CONTAINER_CLIS`, read
by `hi.sh` and `common/header.sh`, and `common/targets.sh`'s `clis`, since
that standalone POSIX file cannot source core.sh. `tests/lint/drift_test.sh`'s
`lint_container_family` pins the two together.

Two members can front one daemon — `podman-docker` ships a `docker` that
execs podman, nerdctl and finch share a containerd — and would list every
container twice. `targets.sh`'s `dedupe_family` keeps the first lane's row in
roster order (so a shim host sees `docker`), and the header unions the lane
files, since the IDs are the daemon's.

`--use <backend>` forces any arm by name, ssh and every roster row included,
and is the only way to: there is no per-backend flag, so a member added to
the family is reachable with no second spelling. Names stay plain identifiers
(`[A-Za-z0-9_]`): `hi.sh`'s per-member predicate is `eval`-defined.

## HI.52 client multiplexer wrap

`hi --mux <target>` re-executes the connect inside a local multiplexer
session named `hi-<target>` and never returns; a second `hi --mux` to the same
target joins the running session. It is the client-side answer to a dropped
link - a disposable tree cannot outlive its own session, so there is no
target-side multiplexer. `_hi_mux_tool` picks the first of tmux, zellij, and
screen on `PATH`, each driven in its own idiom:

- **tmux**: `new-session -A -s <name> <one string>`; the `-A` is the reattach.
- **screen**: `-D -R -S <name> sh -c <one string>`; `-D -R` reattaches a
  session of that name (detaching it elsewhere first) or creates it running
  the command.
- **zellij**: takes a session's command only from a layout file, never from
  argv, so `_hi_mux_wrap` writes `hi.mux.<name>.kdl` under hi's runtime
  directory (one per target, rewritten each connect, each word a KDL string
  via `_hi_kdl_quote`) and starts it with `--new-session-with-layout`; a name
  already in `list-sessions --short` is `attach`ed instead.

Five rules in `_hi_mux_wrap`:

- **Where it sits.** After `_hi_parse`, before `_hi_select_arm`, so one
  insertion point covers every arm (ssh, `--plain`, docker, nomad, kube). The
  inner argv is rebuilt from the parsed state (`--use`, `--plain`, the ssh
  options, `$DOMAIN`, the command), not replayed from `"$@"`, so the target it
  settled on rides along.
- **The guard.** The inner command is `env _HI_MUX_INNER=1 <launcher> ...`;
  the wrap returns at once when that is set. The inner argv carries no
  `--mux`/`--no-mux` of its own, so the inner hi re-reads `$_HI_MUX` - without
  the guard, `_HI_MUX=1` would nest forever. `_hi` also skips the wrap without
  a terminal on stdin (nothing to attach), and it stands down without a
  multiplexer to use.
- **One string.** tmux hands the command to its `default-shell`, which may be
  fish, and screen to `sh -c`, so the argv is joined into one string with
  `_hi_shquote` (HI.40): single quotes are the one form every shell reads the
  same way, where `%q`'s `$'...'` is bash's alone. zellij gets the words.
- **The name.** `_hi_mux_name` keeps `[[:alnum:]_-]` and turns everything
  else into `-`: tmux refuses `:` and `.` in a session name, zellij takes
  the same class, and `/` and `@` read badly in a status line, so a kube
  `ctx:ns:pod/ctr` is `hi-ctx-ns-pod-ctr`.
- **Already inside one.** tmux (`$TMUX` set) refuses to nest, so the session
  is created detached and the client switched to it. screen (`$STY`) has no
  client switch: a new window in the current session (`screen -t <name>`),
  and hi exits once it is made. zellij (`$ZELLIJ`) likewise gets a new tab
  from the same layout (`zellij action new-tab --name <name> --layout`).

## HI.53 terminal reset after a failed session

`_hi_reset_terminal` (hi.sh) runs when a connect's exit status is not 0 and
both stdin and stdout are terminals. ssh restores the tty's termios on its way
out, but nothing restores the _terminal emulator's_ modes a remote program
switched on and never got to switch off when the link went: application
cursor keys (`CSI ?1 l`), the application keypad (`ESC >`), bracketed paste
(`CSI ?2004 l`), a pushed kitty keyboard mode (`CSI < u`), the alternate
screen (`CSI ?1049 l`, wrapped - below) and a hidden cursor (`CSI ?25 h`). It
also closes the OSC 133 prompt-mark pair with a `D` carrying the status: hi's
remote prompt emits `C` before every command, `exit` included, and `load.sh`
sends the closing `D` on a clean exit - a drop never reaches that line, and
Konsole, left "inside a command", sends ↑ as ← until a `D` arrives. `stty sane`
last, for the container arms whose exec does not always restore termios on a
lost link. Never on exit 0 (the session closed itself down), never on a pipe
(`hi host cmd | ...` gets the command's output and nothing else).

Every byte is a no-op on a terminal already in its normal state, so the caller
need not know which mode applied - the alternate-screen exit only once wrapped
in `ESC 7`/`ESC 8` (DECSC/DECRC). Konsole answers `CSI ?1049 l` with an
unconditional cursor restore, and on the normal screen that slot holds what
nothing ever saved, i.e. home: the failed connect's message landed at the top
and painted over the session still on screen. Saving first makes the restore
land where the cursor already is; a terminal really in the alternate screen
saves to _that_ screen's slot, so `CSI ?1049 l` still restores the pre-alt
cursor and the DECRC only repeats it.

## HI.54 who draws the environment prefix

`common/env_prompt.sh` names every active environment manager as the prompt's
leading `(mise|direnv:proj|myproj)`. The awkward part is not the detection -
every tool exports a variable, so a draw is parameter expansion and nothing
else - it is that two of those tools draw a prefix of their own, and whether
that prefix survives is a property of the _shell_, not of the tool.

`python -m venv`'s activate script prepends to `$PS1` (bash, zsh) or copies
`fish_prompt` to `_old_fish_prompt` and wraps it (fish); conda prepends
`$CONDA_PROMPT_MODIFIER` unless `changeps1` is off. zsh and fish keep what
those scripts did: zsh.zsh assigns `$PS1` once at rc time, and fish's
`fish_prompt` is the very function activate wrapped. bash does not -
`common/bash.sh`'s `ps1()` is a `PROMPT_COMMAND` hook that rebuilds `$PS1`
from `$HI_PS1` on every draw, so the activate script's edit is gone by the
second prompt.

So `$_HI_ENV_DEFER` carries the shell's verdict rather than the tool's:
zsh.zsh and config.fish set it to 1 and the venv and conda rows stand down
when the tool's own marker is present (`$_OLD_VIRTUAL_PS1`, the
`_old_fish_prompt` function, a non-empty `$CONDA_PROMPT_MODIFIER`); bash.sh
sets it to 0, because there is provably nothing there to defer to. A venv is
therefore named in all three shells - in its own styling under zsh and fish,
in hi's under bash - and the tools with no prefix of their own are hi's
everywhere. The alternative, exporting `VIRTUAL_ENV_DISABLE_PROMPT=1` to
silence the tools and always draw hi's, would have hi overriding a setting
the user configured for every other shell they open.

config.fish carries its own copy of the source list, as it does of the git
glyphs: it cannot call the bash function, and a `bash -c` on every prompt draw
is exactly the fork this prompt refuses everywhere else.
`tests/hi/prompt_test.sh` pins the two lists together.

mise is the one row that is more than parameter expansion. `$MISE_SHELL` is
set wherever mise is activated, and a `~/.tool-versions` covers every
directory under it, so `(mise)` is named only where a config file between the
directory and `~` overrides the global one: a builtins-only walk up from
`$PWD`, memoized on it (HI.16).

## HI.55 re-entrant rc guard

An rc that leads back into itself recurses until the shell dies. Two shapes
reach hi. On macOS, `hi --install` adds lines to `~/.bash_profile` that source
`~/.profile` and `~/.bashrc`, and a `~/.bashrc` that sources
`~/.bash_profile` back - a common fix under tmux, whose panes are login
shells - makes the pair ping-pong. And an overlay `bashrc`, `zshrc`, or
`config.fish` that sources the user's own rc re-enters hi's, which sources
the overlay again.

Both are cut by a plain, never-exported shell variable held only while
loading: `common/bash.sh`, `common/zsh.zsh`, and `common/config.fish` return
at once while `_hi_rc_loading` is set, and the `.bash_profile` lines skip
while `_hi_login` is. Unexported, so a child shell - a new tmux pane - loads
normally; cleared at the end, so a later `source ~/.bashrc` reloads. A load
interrupted by ^C leaves it set in that one shell.

## HI.56 listing-only completion symbols

bash's completion has no description column - every `COMPREPLY` entry is a
word readline may put on the command line - so a backend symbol beside a
target name (`web ▣`) is safe only while readline _lists_ matches, never when
it inserts one. `_hi_complete` reads `$COMP_TYPE`: `?`, `!`, and `@` (63, 33, 64) list, so their entries carry the symbol; a plain `TAB` (9) inserts the
common prefix and menu-complete (37) cycles whole entries, so both get bare
names. A name two backends share is listed once with both symbols
(`dup »▣`), or the entries' common prefix would run past the name into the
space. bash 3.2 has no `$COMP_TYPE`, so its list stays bare. fish and zsh
carry the symbol in a column of their own (`__hi_targets`' description,
`_hi`'s `-d` display) and need none of this.

## HI.57 carried configs and the include scan

hi carries a `vimrc`, `init.lua`, `nanorc`, and `init.el` to every target
and starts the editor on it (`-u`, `--rcfile`, `-q -l`), so the question is
which file. `tmux.conf` (`tmux -f`) takes the same three tiers minus a tree
copy, so with none the value is empty and `tmux` has no alias. micro takes a
_directory_ of fixed names, so its three files ride under `micro/`,
`$_HI_MICRO_DIR` is the overlay's `micro/` or nothing, and `_hi_overlay_src`
resolves each file itself - the overlay's, else micro's own directory on the
client. `common/paths.sh` answers it in three tiers, lowest first since the
last assignment wins: the tree's copy, then the config that editor already
reads on this machine (`~/.vimrc`, `$XDG_CONFIG_HOME/nvim/init.lua`,
`~/.nanorc`, `~/.emacs`, ..., in the editor's own precedence), then
`$_HI_CONFIG_DIR`'s copy. The middle tier is
[HI.32](#hi32-starship-deference)'s argument applied to editors - one copy to
edit, no duplicate in the overlay to keep in step - and `_hi_overlay_src`
reads the resolved `$_HI_VIMRC`/`$_HI_NVIMRC`/... rather than a second roster.
A value still equal to the tree's means there is no config to carry, and the
tree's copy already rides the payload, so nothing goes in the overlay stream.

The middle tier is client-only (`[ "$_HI_REMOTE_SESSION" != 1 ]`): on a
target `$HOME` is the _target's_, whose rcs are exactly what the `-u` exists
to keep out of a visiting session, and the file the client picked is already
unpacked at `$_HI_CONFIG_DIR`.

Carrying a real config makes a second problem real with it. Every overlay
member - these rcs, the shell overlay files, the prompt configs - ships into
an `overlay/` of its own, so a line naming a _path_ - a
second rc beside it, a plugin directory, a manager's bootstrap - names
something no target has, and the editor or shell fails on it rather than hi.
`hi.sh`'s `_hi_lint_awk` finds exactly those lines; the per-dialect grammar,
and what it deliberately leaves alone, is the comment above it. One pass
serves both readers: `_hi_stage_tar` runs it in `fix` mode ahead of
[HI.35](#hi35-payload-comment-and-whitespace-strip)'s stripper, so a finding
goes out disabled in its own dialect and the strip drops it for free, and
`hi --doctor` runs it in `report` mode, so its yellow rows name exactly what
went missing. The dialect comes from the member name passed in, not the path,
so doctor reads `~/.vimrc` as vim - and a member whose name is no dialect
(`colors`, a `theme.yml`) passes through untouched, so every member goes in
and there is no second roster of what has includes. A line directly under a `hi-allow` comment
in the file's own syntax is neither reported nor touched; one under `hi-quiet`
is disabled like any other finding but not reported; `_HI_INCLUDES=keep` does
what `hi-allow` does for every line.

Disabling must leave a file that parses. vim and nano are line-oriented, so a
finding is one line (tmux's takes its `\` continuations). lua and elisp are
not, so the comment runs to the end of the bracket-balanced expression the
finding opened - commenting only the matched line of `require("lazy").setup({`
would leave its `})` behind. `bal()` counts that depth blind to strings, and
takes `'` as a string delimiter for lua only: in elisp it is the quote
operator, and reading `'load-path` as an opening quote swallows the rest of
the file. sh and fish are the reverse problem: commenting out `. ~/x` inside
`if ...; then` leaves an empty body. So only the verb and its one file word
become `:` (`true` in fish), and the guard, the `&&`, the case arm around it
stay. What the pass cannot see is a value the dropped line was meant to bind -
a `local m = require("x")` used twenty lines down - so a plugin-heavy config
can still error on the target; the doctor rows make that legible.

## HI.58 overlay directory members

A `$_HI_OVERLAY_FILES` entry ending in `.d` names a directory, and its
members ride one by one: `hi.sh`'s `_hi_overlay_files` lists each as
`<dir>/<name>`, in name order, and the rest of the stream - `_hi_overlay_src`,
the cache key, the stager, [HI.35](#hi35-payload-comment-and-whitespace-strip)'s
strip (a `-path` entry in `$_HI_STRIP_NAMES`) - treats that path like any
member. The directory stays an allow list: `core.sh`'s `_hi_dir_member_ok`
admits a plain name only (a letter or digit first, then `[A-Za-z0-9_.-]`, not
ending `.bak`/`.orig`/`.rej`/`.tmp`), and the target reads the directory back
through the same function, so a file hi would not send is one hi would not
read either. The archive carries no directory entry; every tar hi unpacks with
creates the parent, busybox's included.

`packages.d` is the first: each member is a group of the package check.
`header.sh`'s `full_check` walks `_hi_package_files` - every `$_HI_PACKAGES_D`
member, no distinguished first one - and `_hi_check_file` runs each through
`check_line` under its own palette and sorts it alone, so a group is a
contiguous run after the group before it. The palette is a file's `color=`
line (`_hi_group_color`), made a ramp by `_hi_group_ramp` - one name in all
eight slots, or eight as written - and handed to `_hi_packages_palette`,
where it outranks `$_HI_PACKAGES_PALETTE`; the ramp in force is put back when
the check ends. The line is not a comment on purpose: the strip would take
it. With no member at all the check prints nothing. Unlike `plugins.d`,
`$_HI_PACKAGES_D` has a real tree default (`config/packages.d`, shipping
`default` and `extra`) and a `-d` guard in `common/paths.sh`, the same
tree-default/overlay-override cascade `$_HI_COLORS` uses - so a
`packages.d/` of the user's own **replaces** the tree's wholesale, the way a
hand-made `~/.config/say-hi/colors` already replaces `config/colors`.
That is why `hi --add-package` seeds the tree's members into a fresh overlay
directory on its first write: without it, the first custom group would
silently drop every shipped check.

## HI.59 plugins

`plugins.d` is the second [HI.58](#hi58-overlay-directory-members) directory:
each member is a plugin, a file in the POSIX+fish subset `config/aliases.sh`
keeps (`export`, `alias`, `&&` chains), so one file serves all three shells
and something new - another tool's init, a prompt segment - rides to every
target with no edit to the tree. `common/paths.sh` exports `$_HI_PLUGINS_D`
unguarded; the overlay is its only home.

The moment is stated: right after `$_HI_ALIASES` (so a plugin sees, and can
replace, hi's aliases and the overlay's) and before the prompt is built, in
name order - `core.sh`'s `_hi_load_plugins` for bash and zsh, and its fish
copy in `common/config.fish`, which cannot call bash. Each member is parsed
first by the shell loading it (`bash -n`, `zsh -n`, `fish --no-config -n`); one
that does not parse is skipped with a yellow `hi: plugin <name> does not
parse in <shell>; skipped` on stderr rather than half-run, which is also what
a fish-only or sh-only construct costs in the other shell. The parse is a fork
per plugin per shell start, and nothing without a plugin. The zsh glob sits in
its own function (`_hi_plugin_files`) so `null_glob` can be local there:
`local_options` in the loader would also undo every `setopt` a plugin makes.
That function tests `-d "$_HI_PLUGINS_D"` before it globs: unset, the pattern
is `/*` and the loader would source what parses at the root of the disk
([HI.60](#hi60-a-shell-that-outlives-the-tree) is how it comes to be unset).
fish's copy needs no such test - an empty variable takes the whole word with
it there.

Hooks are variables, since the subset cannot define a function all three
shells read. The loader unsets each before a plugin runs and collects it after,
so plugins compose without `${var:+...}`, which fish lacks. The set:

| hook          | what hi does with it                                                                                                                                                                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_SEGMENT` | a command, run in the session's own shell on every prompt hi draws; non-empty output is drawn after the environment prefix, followed by a space. bash marks any color in it for readline, zsh doubles its `%`. Ignored under a prompt tool. |

`hi --doctor` lists the plugins in load order and warns for each a shell on
this machine cannot parse, and for a directory entry that is not a member.

## HI.60 a shell that outlives the tree

An interactive shell is long-lived and the tree under it is not: `hi --update`
and a package upgrade both rewrite `say-hi/` in place, and every shell already
running keeps what it loaded. A tmux pane is the extreme case - panes last
weeks, and the usual reflex after an upgrade is

```sh
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' |
  xargs -I {} tmux send-keys -t {} 'source ~/.bashrc' Enter
```

which re-sources the new tree's rc in all of them at once.

`common/core.sh`'s preamble is guarded by `$_hi_core_loaded` so a second
source in one process is a no-op, and scripts rely on that: `configure.sh`
stages values the re-run of `common/paths.sh` would write back over. The
guard is wrong in exactly one place, the rc, where the second source is not a
second source at all but a _different version's_. Functions below the
preamble are redefined either way, so the guard left the new tree's code
running against the old tree's paths, and every `_HI_*` path added between
the two versions stayed empty. The damage is quiet and cumulative: `source ""`
for a name that did not exist yet (`bash: : No such file or directory`),
`_hi_env_prompt: command not found` on every prompt draw, the header's package
row gone, and `"$_HI_PLUGINS_D"/*` globbing `/` - which
[HI.59](#hi59-plugins)'s loader then `bash -n`s and _sources_, file by file,
in every pane at once.

So `common/bash.sh` and `common/zsh.zsh` `unset _hi_core_loaded` before they
source core.sh. `load.sh` already did, for the same reason on the far side (a
target whose own `~/.bashrc` wires a say-hi of its own loads that tree's
core.sh first), and `common/config.fish` never had a guard to clear.
`_hi_plugin_files` tests `-d "$_HI_PLUGINS_D"` before it globs, so no later
name arriving empty can reach the root of the disk again.
