# Glossary of Deliberate Oddities

say-hi's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `common/aliases.sh`, and
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
- [HI.53 terminal reset after a failed session](#hi53-terminal-reset-after-a-failed-session)
- [HI.54 who draws the environment prefix](#hi54-who-draws-the-environment-prefix)
- [HI.55 re-entrant rc guard](#hi55-re-entrant-rc-guard)
- [HI.56 listing-only completion symbols](#hi56-listing-only-completion-symbols)
- [HI.57 carried configs and the include scan](#hi57-carried-configs-and-the-include-scan)
- [HI.58 overlay directory members](#hi58-overlay-directory-members)
- [HI.59 extensions](#hi59-extensions)
- [HI.60 a shell that outlives the tree](#hi60-a-shell-that-outlives-the-tree)
- [HI.61 one overlay priority](#hi61-one-overlay-priority)
- [HI.62 generated wiring](#hi62-generated-wiring)
- [HI.63 plugins rows](#hi63-plugins-rows)
- [HI.64 what is switched off](#hi64-what-is-switched-off)
- [HI.65 kept session](#hi65-kept-session)
- [HI.66 the packer stays home](#hi66-the-packer-stays-home)
- [HI.67 shell hooks](#hi67-shell-hooks)

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
`eval` for an array (`_hi_read_lines`) or `printf -v` for a single string,
and reading one through `${!name}` where only bash reads the file.
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
emits `export X=0` lines from the same list for bash-less targets. The two
opt-ins, `_HI_TOOL_ALIASES` and `_HI_SUDO_ALIAS`, sit outside the list:
`common/aliases.sh`'s backstop line defaults them to `0`, and every reader
compares against `1`, so unset is off.

## HI.08 sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back — see HI.09 for why with `cat`.

## HI.09 cat-over-mv

A tempfile goes back over an existing file through the existing inode:
`cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in `scripts/lib.sh`).
`mv` would transplant mktemp's 0600 mode onto the target and sever any
hardlink/ACL — a dotfile manager's hardlinked `~/.bashrc` must see the new
content.
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

## HI.12 bytes vs columns

`${#var}` counts bytes, not display columns; multibyte characters inflate it,
and a banner padded by it comes out narrow. Width math around user-visible
strings computes column counts explicitly (`changes_w` in `common/header.sh`,
`_hi_visible_len` in `scripts/table.sh`).

The glyph set is the client's call, since glyphs render in its terminal, but
counting them is the target shell's, so the preamble (`_hi_locale_probe`)
checks the target can: a session locale `locale -a` does not list, which a
forwarded `LANG` often is, leaves the shell in C. It sets `LC_CTYPE` to the
first of the session's locale, the client's (`_HI_CLIENT_LOCALE`), and
`C.UTF-8` that the target has, and falls back to ASCII where it has none, or
where an `LC_ALL` of the user's names another. A target with no `locale`, as
musl's often is, is left as it was.

## HI.13 command -v fallthrough

**Every alias ends in a binary the target has.** `common/aliases.sh`
resolves each tool chain at source time
(``_HI_LS_BIN="`command -v eza || command -v ls`"``) and builds the aliases
on the result. Only under
`_HI_TOOL_ALIASES=1`; off, the forks are skipped.

**A rung per dialect**: `_hi_path_lookup` for bash and zsh, a backtick line
for sh, `command -v ... | read VAR && export VAR` for fish (a bare `read`
passes checkbashisms and sets a fish global). `[ -n "$FISH_VERSION" ]` keeps
the last two to their shells. Backticks, not `$( )`: fish before 3.4 refuses
`$( )` anywhere in a sourced file and reads a backtick as text, which is also
why shfmt skips the file.

**A narrower chain for flags**: `$_HI_BAT_BIN` is `bat || batcat`, while
`$_HI_CAT_BIN` adds `ccat || cat`, so bat-syntax options attach only behind
`[ -n "$_HI_BAT_BIN" ]`.

**Before any alias exists**, the overlay's included: in zsh and dash
`command -v` returns an alias's body once one is defined. An alias that was
there before hi (a target's `alias ls='ls --color=auto'`, or hi's own on a
re-source) is cleared in the backtick line's subshell with
`type unalias >/dev/null 2>&1 && unalias -a || true &&`; bash and zsh need
none, since `_hi_path_lookup` walks `$PATH` and sees no alias.
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

Files sourced into an interactive shell (`common/core.sh`, `hi.sh`, ...) that
run anything as they load set `set -euo pipefail` at the top _and disable it
at the end of their own code_: left on, any later
non-zero status or unset variable kills the user's session. The `common/`
files end with `_hi_opts_restore`, which gives an interactive shell back the
`-e`, `-u`, and `pipefail` it had before the file loaded; a script keeps them
off. A user's file (`settings.sh`) is sourced with strict mode off, so one
failing line cannot stop a shell starting. `common/bash.sh` never enables it
at all. The bootloader and fallback rc do the same on targets — forgetting it
there breaks `hi <target> <command>` outright.

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

Every command hi sends meets the target's _login_ shell first, which may be fish
— and fish parses neither `x=1` nor `{ ...; }` nor `||` as sh does. Wrapping
everything in `sh -c '...'` is the transport's job, not per-site care
(unwrapped, the boot probe's `if ...; then ... fi` does not even parse on a
fish-login host). Quoting is single-quote-and-escape rather than `printf %q`,
which backslash-escapes every space — unreadable in the code and in an `ssh -v`
log, and one more thing for fish to differ about.

## HI.19 stdin transport

**Stdin, not argv.** The bootloader goes over stdin of the first of two
calls, the arm's `cp`, never as an argument: Linux caps one argv entry at
128KB (`MAX_ARG_STRLEN`) whatever `ARG_MAX` says. Two calls, because the
second's stdin (the `attach`) belongs to the session; over ssh both share one
connection and one authentication. The script goes as text, the two archives
after it as they are (`_hi_boot_stream`), behind a line of the three byte
counts; the probe checks the total and splits it with `dd` and `tail -c`.
Armoring the archives cost a third of every session's bytes, so only the
bootloader and a few rc lines are base64 now.

**The write is the probe** (`_hi_boot_probe`), read by `_hi_boot_why`: the
directory comes back and the session runs; or `sh` ran and exited 64 (no
`base64` or `openssl`), 67 (no `tar` that reads gzip), 65 (no `mktemp`), or 66
(short landing, retried twice: nomad's and kube's `exec -i` can close stdin
early), and hi names the gap and hands over the host's session; or a forced
command answered (exit 0, or any stdout), which hi names and hands over; or
nothing ran (stock Windows OpenSSH), and the PowerShell branch takes over. A
container exec that fails outright is reported in its own words.

**Over ssh the two calls overlap** (`_hi_connect_overlap`), saving about two
round trips a cold connect. `cp` starts as soon as the target is known
(`_hi_overlap_start`) and makes the ControlMaster; the session opens once its
socket exists, with a short stub as its command (far under Dropbear's ~9000
byte limit, and the script never in an argv, where `/proc` would show it).
The client names the directory (`hi.boot.` plus 16 random hex digits); `cp`
makes it with `mkdir` under `umask 077` (refusing one that exists) and
renames the script in whole, and the stub runs it only from a directory of
this user's. The stub sleeps on a FIFO the probe writes once the script is
whole, opened before its last look so the wake cannot slip past.

A failed probe stops the stub; a forced command is only named; `MaxSessions
1` refusing either channel sends it again in series. Without a tty nothing
would end a stub the client gave up on, and sshd would hold the session slot,
so its stdin comes through the client (`_hi_overlap_relay`): a `go` line
once the boot is in, then the client's stdin, or end of file, which has the
stub remove the directory and exit. A child reads that line, so the start
still waits only on the probe's FIFO, and is never waited on, so an open
stdin cannot hold the channel.

## HI.20 fallback rc

The no-bash target's rc is consumed by sh, zsh _and_ fish (`_say_hi`'s `fish -C`
branch), so every line must be valid in all three — `export NAME=value` and
`[ -f x ] && . x` are; anything shell-specific is appended by that shell's own
arm. Toggle defaults come first so the files after them still win.
`_HI_REMOTE_SESSION=1` is exported because this path never reaches `load.sh`.
`settings.sh` keeps its `[ -f ]` guard because a bare `.` on a missing file
abandons the rest of the file in ash/dash. `_HI_CONFIG_DIR` points at the
target's own `config/`, where the shipped overlay was unpacked.

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
cannot render. A TERM the client can describe rides as its own entry instead
(`_hi_terminfo_line`): `infocmp -x` on the client, `tic -x -o` into the
session tree on a target with `tic`, the tree on `TERMINFO_DIRS` ahead of the
target's own, and the TERM put back; the swap stays where there is no `tic`,
and for a kept session's reattach, which runs ahead of the tree. The
ubiquitous names are `$_HI_TERM_KNOWN`, which both ends read.

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

The session shell is the first installed of `$_HI_SHELL_PREFERENCE`'s words,
`login` by default, then of the names hi styles; bash is the floor because
`load.sh` only runs where bash exists. `login` stands for the user's login
shell on the target, taken where hi styles it. The tail is not a literal:
`_hi_session_shell` walks `common/core.sh`'s `$_HI_SHELL_TREE`
(`fish zsh bash dash ash sh`) and drops the tiers that need bash to be
_missing_, leaving `fish > zsh > bash`; `hi.sh`'s `$_HI_SHELL_LADDER` is the
same tree with bash removed. One list, two consumers.

`login` leads the default because a ranking that leads with fish hands it to
anyone whose box has it, so a user whose login shell is zsh-with-oh-my-zsh
would never see their own setup. The setting is for the other user, whose
login shell on a target is bash and who wants zsh or fish wherever the target
has one: `zsh fish` says so, and a word naming no shell hi styles is passed
over. Read on the target, from the `settings.sh` that rode.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi`, and every backend but ssh is a
subprocess, so two internal knobs (environment variables for the suites and
bench, not settings) bound it.

**`_HI_PROBE_TIMEOUT`** (default 2s, shared with core.sh's `_hi_probe`) caps
each backend CLI, and since backends start together and are read back in
roster order it bounds the whole sweep. The cap is `timeout -k 0.2`: rootless
podman defers a TERM through its runtime setup, so without the KILL the
ceiling is only a request. The first probe settles BusyBox's forms (no `-k`
before 1.35, `-t SECS` before 1.30); `kubectl` also gets `--request-timeout`
for when there is no `timeout` (stock macOS). With no writable scratch
directory the sweep runs in turn: slow, not wrong.

**`_HI_TARGETS_TTL`** (default 5s; 0 disables) reuses a result, so a new
container may not appear at once. Nothing but the clock invalidates it, and
two caches stack (`targets.sh`'s file and the shell's memo), so staleness
can approach twice the TTL. Past the TTL, a copy under ten minutes old
(`stale_for`) still answers at once while a refresh runs behind it, one at a
time under a lock directory; older, the sweep is waited on.

ble.sh's as-you-type completion (`auto` in `comp_type`) gets the names the
shell already holds and never sweeps.

## HI.29 apostrophes in substitution comments

bash 3.2 scans a `$( ... )` command substitution with a simple quote matcher: a
comment line _inside_ one containing a lone `'` reads as an unterminated
string, and the whole file dies at parse time. The same matcher ends the
substitution at a bare `case` pattern's `)`, a syntax error found only when
the line runs. bash 4+ parses substitutions recursively, which is why this
only surfaces on macOS. Keep comments inside `$( )` apostrophe-free, or hoist
them above the assignment, and hoist a `case` into a function. The lint greps
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

**Hand over the prompt, keep the rest.** `_HI_PROMPT_TOOL` names prompt
programs to draw the prompt while hi keeps its header and aliases; each shell
takes the first entry that fits and is present, `<shell>:<program>` entries
first, and `hi` ends the walk with hi's prompt. With no plain entry the rest
is the whole roster (`_HI_PROMPT_TABLE`: shells, how found, overlay member,
frameworks first), so a prompt used at home is the default rather than drawn
over. Only `hi` unhooks a program the rc already started. The list is
resolved on the client (`_hi_prompt_list`) and sent with the session
([HI.47](#hi47-what-a-child-inherits)), so a target never picks a program it
happens to have.

**One predicate**, `_hi_prompt_tool <shell>` (core.sh; config.fish mirrors
it): a binary on `$PATH`, or a framework through the shell's `_hi_prompt_fw`,
which at home means the rc loaded it (an installed but unused framework is
never started there) and on a target means installed where its README puts
it, with home's file to draw. Each starts the way its README says:
`init <shell>` for starship and oh-my-posh, a prompt hook for powerline-go,
sourced for powerlevel10k, oh-my-zsh's libraries, oh-my-bash, and bash-it
(hi's aliases put back after), and tide left alone. Each framework's loader
is its own `common/fw_<name>.<ext>`, cut from the payload for a target not
handed it ([HI.41](#hi41-overlay-stream)); a missing loader passes to the
next entry. The git and environment segments stay hi's: they cost no fork.

**Unhooking** clears bash's `PROMPT_COMMAND`, and bash-preexec's
`precmd_functions` array too (bash-it's hook lives there), with a rebuild
loop since bash has no `:#` filter; zsh's precmd hooks; fish's right and mode
prompts.

**Home's config** rides the overlay and applies on targets only:
`$STARSHIP_CONFIG` and `$POSH_CONFIG` (and `$POSH_THEME`) from the wiring
([HI.62](#hi62-generated-wiring)), `p10k.zsh` sourced after powerlevel10k,
the framework theme file sourced over its framework, and tide's `tide_*`
variables exported (tide renders in a background `fish -c`).

**A prompt with no hand-over stays the user's** where hi can tell: a known
framework's marker, a non-default `fish_prompt`, or at home a `$PS1` that
`_hi_ps1_stock` does not recognize as a shell's or distro's default (or hi's
own, so a re-sourced rc redraws, [HI.60](#hi60-a-shell-that-outlives-the-tree)).
A missing distro default costs its users hi's prompt at home until added.
Never asked on a target, where hi's prompt draws.

## HI.33 derived tree location

`$_HI_ROOT` is the tree (a checkout under any name, or a package's
`/usr/share/say-hi`) and `$_HI_HOME` the directory above it; a session's
tree is always `$_HI_HOME/say-hi`. Every file takes the tree by one rule: a
set `$_HI_ROOT` that sits in `$_HI_HOME` (or with `$_HI_HOME` unset), else
`$_HI_HOME/say-hi` where `$_HI_HOME` is set, else its own path. Never
`$HOME`: that default silently read another tree wherever the install was
elsewhere. An inherited `_HI_ROOT` of another tree never beats an exported
`_HI_HOME`. `install.sh` and `packaging/lib.sh` always use their own path,
since an install acts on the tree it sits in. The rc line names a tree called
`say-hi` by `_HI_HOME` and any other by `_HI_ROOT` (`rc.sh`'s `tmpdir_line`);
the payload stages it as `say-hi/` whatever its name.

`common/core.sh` owns the answer; everything that merely _needs_ the tree
reaches core.sh through its own path. The files that derive have nothing above
them to ask through:

| where                                                           | how                                                                                                                                                                                    |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `common/core.sh`                                                | `${BASH_SOURCE[0]}`, then `cd -P .. && pwd`; answers for every file sourced through it                                                                                                 |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh`               | the same behind a `readlink` walk, so `~/.local/bin/hi` (a package's `/usr/bin/hi`) answers the tree it links to. Three copies: each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh`                               | `${BASH_SOURCE[0]}` - entry points that _export_ for children                                                                                                                          |
| `tests/test_lib.sh`                                             | `${BASH_SOURCE[0]}` only, `$_HI_HOME` or not - the harness sits in the tree it tests, and `_hi_host_tree_check` warns when `$_HI_ROOT` names another                                   |
| `scripts/doctor.sh`, `preview.sh`, `update.sh`, `add_tag.sh`    | `${BASH_SOURCE[0]}`, then `$_HI_HOME`'s `say-hi` or `$_HI_ROOT` by the rule - the standalone-entry form below                                                                          |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; bash cannot parse `%x`, so core.sh's arm is `eval`'d                                                                                         |
| fish (`common/config.fish`)                                     | `sh -c 'cd -P "$1/.." && pwd'` - a builtin-only substitution would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical                       |
| `common/bash.sh`                                                | the rule, its own path as the fallback - `hi.sh`'s preamble and `install.sh`'s rc line both set a name before this file is sourced                                                     |

**The standalone-entry form.** A script run on its own falls back to
`${BASH_SOURCE[0]}` only when no name is set:

```sh
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
[ -z "${_HI_ROOT:-}" ] || [ "${_HI_ROOT%/*}" != "${_HI_HOME:-${_HI_ROOT%/*}}" ] || _hi_d="$_HI_ROOT"
```

With a name set, everything comes from there, core.sh included, so one
process never runs two trees. `hi.sh` refuses, naming both variables, when
the derived path holds no tree. A target needs no rule: its tree is the one
hi just unpacked, and its own install is never read. `drift_test.sh`'s
`lint_home_default` greps the tree, docs included, for the retired `$HOME`
default.

## HI.34 test suite preamble

Every suite under `tests/` opens with the same four lines — four separate
mechanisms, not boilerplate. Two kinds differ, on purpose: a part of a
split suite (`<suite>_<part>_test.sh`, as `doctor_json_test.sh` is to
`doctor_test.sh`) names its part and sources its parent suite in place of the
harness, which the parent then sources once, for the helpers the parts share;
and a suite with no function it
reaches only indirectly (the lint suites, docker's and podman's) drops the
SC2329 line:

```sh
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
```

`$_HI_TEST_LIB` is exported by `test_lib.sh`, so under `test_runner.sh` the
harness is found through the tree the runner resolved. The `${...:-}` tail is
the fallback for running a suite directly; its `../` depth is the suite's
distance from `tests/`, so a suite that moves has to have it re-counted.

`test_lib.sh` sources `common/core.sh` itself; a suite sources the harness and
never core.sh, or core.sh initialises twice, the second time after the harness
has moved `$XDG_CONFIG_HOME` into the scratch dir. The `# shellcheck source=`
line is a directive the linter follows, and `# shellcheck disable=SC2329` is
HI.30. Both stay verbatim above their statement.

## HI.35 payload comment and whitespace strip

Every tree file `scripts/pack.sh`'s `$_HI_STRIP_NAMES` matches — the shell
files and the data files under `config/` — and every overlay member whose dialect
(`$_HI_DIALECTS`) has `<strip>` 1, such as `vim/vimrc` and `tmux/tmux.conf`,
whose prose headers document the _installed_ copies, is comment-stripped by
`_hi_strip_awk` on its way into the payload or overlay; about 40% of the
shipped shell is comment. A member's comment leader is its dialect's, handed
to the stripper as `c=` ahead of the file: vimrc's `"`, init.el's `;`, and
lua's `--`, beside `#`. Lua's `--[[` block form is deliberately
not one: the strip is line-wise, so a block opener would go and its body stay
— which is why the shipped `nvim/init.lua` uses line comments only.
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

`_hi_ssh_pattern_hit` (`common/core.sh`) matches a name against
`Host`/`Match host` glob patterns from `~/.ssh/config`. `*` and `?` mean the
same in ssh's syntax as in a `case` pattern; the difficulty is trying each
pattern in a way that survives both bash and zsh.

The tokens are peeled off by parameter expansion, never `for pat in $patterns`:
zsh does not word-split an unquoted variable, so that loop never iterates, and
bash also pathname-expands it, so a bare `*` — the commonest `Host` line —
becomes the cwd's file list. Then zsh does not treat `*` in a _variable's_ value
as a wildcard unless `GLOB_SUBST` is set — a `case` that never matches.
`${~pat}` turns it on for that one substitution rather than the whole function;
bash cannot parse it, so the zsh arm is `eval`'d behind `$ZSH_VERSION`.

A `!`-prefixed token (ssh's per-pattern negation) is not honored as exclusion —
it survives as a literal pattern nothing is ever named, so it is inert rather
than wrong; the cost, a wrongly-colored excluded host, is cosmetic.

## HI.38 split tar and gzip

`_hi_tar_gz` (`hi.sh`) runs `tar -c -f - | gzip -9 -n` rather than
`tar -c -z -f -`. The two userlands pad differently, and only one pads something
that survives compression: GNU tar rounds the _uncompressed_ archive up to the
10240-byte blocking factor and then gzips it, so its trailing NULs cost about
thirty bytes; bsdtar — macOS's `/usr/bin/tar` — pads the _compressed output
stream_, appending raw NULs after the gzip member, so a one-step payload built
on a BSD client is a multiple of 10240: about 27% waste on a stock payload and a
flat 54× on a two-file overlay (189 B against 10240). Split, the steps agree
with GNU tar to within a few bytes under both userlands and are byte-stable run
to run. `-9`, since the cache pays for the slower pass once and every connect
sends the result.

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
under Git Bash), `_say_hi` refuses by name rather than letting the target receive an empty archive,
and `hi --doctor` reports the same three verdicts.

Every tar in `hi.sh`, client and target side, takes dash-style options:
OpenBSD's tar reads each word after an old-style `cf <file>` as a member name,
so `tar cf - -C dir` archives a file called `-C` there.

## HI.39 payload staging

`_hi_payload_tar` (`scripts/pack_stream.sh`) ships the tree, comment-stripped
(HI.35), through `_hi_stage_tar`, which the overlay shares; a session's own
`_hi_payload_tar` stages nothing ([HI.66](#hi66-the-packer-stays-home)). What
ships never depends on a toggle: `$_HI_PAYLOAD` is whole directories, every
toggle is read where it applies, and a session that switched something off
carries the file and leaves it alone (a per-toggle trim would save about a
kilobyte at the cost of a cache key, a second table, and an exclusion list).

**Staged, in a subshell, under a trap.** The strip rewrites files and the tree
is not hi's to touch, so it is copied to a `mktemp -d` stage with `cp -R -L`
(`-L` resolves symlinks) and made writable there. Not through tar: busybox's
sets a directory's mode as it makes it, so a tree of read-only directories,
the nix store's, could not be filled. The subshell
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
bash. They re-slice the rest of the value at every `'`, though, quadratic in
its length and slower still in UTF-8, so a value past 512 characters goes to
`_hi_shquote_long`, which splits on `'` with `read` under `LC_ALL=C` and joins
the parts: 81 KB of script in about 40 ms rather than nearly a second.

Everything `hi.sh` bakes into a script for the target is text the target's
shell will parse, and some of it is data: `$DOMAIN` off argv,
`$_HI_TARGET_TAG` out of a free-text `# Tags:` comment, `$_HI_RELEASE` off
`git describe --dirty`. An unescaped `$`, quote, or backtick in any of them
breaks the bootloader's parse and lets the target run a command substitution
it should not. `_hi_on_target` quotes ssh's `sh -c` word through the same
function, and `_hi_env_each` prints its export lines already quoted, so quoting
is one decision.

## HI.41 overlay stream

**A second archive.** The overlay (`$_HI_OVERLAY_FILES`, `scripts/pack.sh`)
lives outside the tree, so it travels as its own small archive and unpacks
into the tree's `config/` over the defaults it shadows: one directory,
`$_HI_CONFIG_DIR`, for a session to read. hi's aliases are
`common/aliases.sh`, so the user's `aliases.sh` collides with nothing (and
`common/aliases.sh` refuses to source itself). Nothing to send, no archive.

**Tool configs ride from where they are.** `_hi_overlay_src` packs the
overlay copy, else the file the tool reads on the client (HI.61; a prompt
program's only when `_hi_prompt_list` names it), so there is one copy to
edit. The [wiring](#hi62-generated-wiring) points each tool's variable at the
overlay on a target only (`$EZA_CONFIG_DIR` names the directory, since eza
fixes the file name). Of fish's universal variables only the `tide_` lines
ride.

**`colors` and `packages`** ride because `common/paths.sh` points
`$_HI_COLORS` and `$_HI_PACKAGES` at the overlay's copy when there is one;
left behind, an override would work at home and silently revert on every
target (`paths_test.sh` pins the two lists together).

**Shadowed defaults stay home.** `_hi_payload_excl` takes the member list
and `_hi_payload_tar` drops the defaults they shadow
(`$_HI_OVERLAY_SHADOWS`, never `aliases.sh`, which adds), cached under its
own key. With the header off (read as HI.64's `_hi_toggle_on`), `header.sh`
and `config/packages` are dropped too, about 11 KB; a target reads the
missing `header.sh` as the header off. Files are dropped from the stage,
since OpenBSD's tar has no `--exclude`. `_hi_wire_bytes` has no list and
measures the stock tree (HI.44). A file under a pre-1.0 name
(`$_HI_OVERLAY_RENAMES`) is no member and cuts nothing. An alias or
`$VIMINIT` asks for the rc as well as the binary, so a box whose editor got
no config keeps its own.

**`ssh_tags`** has no file on the client: `_hi_ssh_tags_file` cuts each
tagged `Host`/`Match host` line, with its `# Tags:` line, from
`~/.ssh/config` into the runtime dir, so a relay's `_hi_ssh_host_tag` walks
it as a config, after its own and only in a session. A `Tag` line or a
`config.d` file's name (read off `targets.sh`'s `# hi-file:` comments) is
written as the `# Tags:` line it stands for, so an older ssh on the middle box
reads it. Only tagged blocks ride, so an untagged block that answers first at
home is not there: a name it and a later tagged wildcard both match reads as
tagged on the second hop.

## HI.43 container target grammar

**What to run in, as a suffix**: `pod/container` for kube, `alloc/task` for
nomad, a suffix rather than a flag so completion can offer the pairs. The
docker-compatible family (HI.51) takes a name whole: `/` is legal in it.

**Three commands per arm** (`_hi_transport_cmds`): `probe` (no stdin, no
tty), `cp` (stdin), `attach` (a tty where there is one), an exec in each
backend's spelling or ssh over the ControlMaster. `_hi_on_target` runs a
script through one, as argv for an exec and as one quoted string for ssh
([HI.18](#hi18-sh--c-wrapping)). Every arm boots in one `cp` and runs in one
`attach` ([HI.19](#hi19-stdin-transport)), so containers get the same script,
no-bash ladder, and [kept session](#hi65-kept-session). Only ssh has the
ControlMaster, keepalive, retry, and PowerShell notice.

**kube's prefixes**: `[[context:]namespace:]pod[/container]`
(`_hi_kube_split`). `:` is safe because no ssh host, container, or
allocation name can hold one; `list_kube` emits the same spelling for other
namespaces. The container half is checked by kubectl at session time, failing
loudly rather than falling through to ssh. Likewise no container, allocation,
or pod holds `@`, so `user@host` with no `:` goes straight to ssh
(`_hi_select_arm`), while `admin@cluster:ns:pod` is still asked.

**Compose services**: docker and podman resolve a service name to its one
running container (`_hi_compose_container`), only after the literal name
fails. Two matches or none fail rather than guess, since a wrong guess lands
in someone else's container. nerdctl and finch are unverified for the label
template, so left out.

## HI.44 wire size token

The connect line prints the size of the script the session sent, but the script
cannot know its own size while being assembled. `_say_hi` (`hi.sh`) builds it
with `$_HI_SIZE_TOKEN` (`@@SIZE@@`, wider than any figure) standing in, measures
`${#script}` and the archives that ride after it, and substitutes the human
figure back — honest to a few bytes, since what goes over the wire is the
script as it stands and the archives as their files hold them.
`_hi_wire_bytes` — what `hi --doctor` and the README badge quote — assembles
the same script through the same `_hi_remote_script`, from the same payload
cache `_say_hi` reads, and adds the tree's archive and the count line, rather
than summing the streams alone: summing skips the boilerplate around them and
reads ~6KB low, and a badge has to show the number the user sees. No overlay is counted, since which files ride is a
question about a target - and none of the tree defaults one would shadow is cut
(HI.41), so the figure is the stock tree's on any client.

## HI.46 session rc directory

**The target's rc files are never written.** `bash --rcfile hi.bashrc`
starts the bootloader, which runs `load()`, which starts the session shell;
a bare `$shell -i` would read the target's `~/.bashrc` alone. So
`_hi_session_rc_setup` writes one rc per shell into a `mktemp -d` of its own
(`$_HI_SESSION_RC`), each sourcing the target's rc first and hi's on top.
`ZDOTDIR` moves all of zsh's startup files, so `~/.zshenv` is sourced too,
with `ZDOTDIR` unset (it may set its own), and then pointed back.

**How each shell is reached:**

| shell         | reached by      | inherited by a nested shell? |
| ------------- | --------------- | ---------------------------- |
| zsh           | `$ZDOTDIR`      | yes                          |
| sh, dash, ash | `$ENV`          | yes, interactive shells      |
| bash          | `--rcfile`      | no: a wrapper                |
| fish          | `-C 'source …'` | no: a wrapper                |

bash and fish have no such variable (`$BASH_ENV` is non-interactive only), so
`common/aliases.sh` wraps both off `$_HI_SESSION_RC`, each body starting with
`command` so fish's alias cannot call itself. A shell nothing typed (a tmux
pane, an editor's shell-out) is the host's own, except in a
[kept session](#hi65-kept-session).

## HI.47 what a child inherits

**Only the roster is exported.** A process started from a hi shell sees
core.sh's `_HI_CHILD_ENV` and no other `_HI_` name:

- `$_HI_HOME`, `$_HI_ROOT`, `$_HI_CONFIG_DIR`: a target's overlay and a
  clone's name cannot be re-derived ([HI.33](#hi33-derived-tree-location));
- `$_HI_SITE_DIR` ([HI.61](#hi61-one-overlay-priority)), for completion;
- `$_HI_REMOTE_SESSION`;
- `$_HI_SESSION_RC`, for HI.46's wrappers in nested shells;
- `_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT`, `_HI_BACKENDS_OFF`, which
  `sh targets.sh` reads from its environment.

**By un-exporting, not by never exporting.** `paths.sh` is read by fish, sh,
zsh, and bash, whose one shared assignment is `export NAME=value`, so its
fifty-odd names arrive exported. Each interactive rc un-exports them last in
its required block: `_hi_unexport` (bash `export -n`, zsh `typeset -g +x`)
or a `set -gu` loop in fish. The values stay as shell variables. Being last
lets the overlay's per-shell rc `export` what it wants children to see.

**The client's verdicts** (`_hi_session_env`, pinned to `_HI_SESSION_VARS`)
include `_HI_LOCAL_USER` and `_HI_LOCAL_HOSTNAME`, which name the operator's
machine and must never reach a target's process table. They are no roster
names: `_hi_session_rc_setup` writes them into each session rc as plain
assignments (HI.46), and fish hands them to its one `bash -c` through
`__hi_bash`'s `set -fx` (a `-l` in the loop would be gone by then).

**Not covered**: a POSIX `sh` started in a session re-sources `paths.sh`
through `$ENV` and dash cannot un-export; the bash-less fallback rc (HI.20)
likewise. `tests/common/exports_test.sh` pins all of it: the child
environment in each shell, config.fish's mirrors, `_hi_session_env`, every
variable targets.sh reads, and the session rc's quoting.

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

A cell of the user's own, from the overlay's `header/` (`header.sh`'s
`_hi_header_cells_load`, admitted past the word gate by name), has no row of
alternates: `_hi_header_word_alt` gives it the bright color of the next hue
round the ring from its own (red to green, ..., cyan to red), which keeps the
property for it too.

An empty cell (`containers`/`jobs`/`pods` when that backend never answered)
leaves `$_HI_PREV_HUE` untouched rather than resetting it to empty —
resetting it would let the _next_ word compare against nothing and skip a
real collision two cells later. `check` resets it explicitly: the packages
block has its own palette (`$_HI_YES`/`$_HI_NO`), unrelated to header cell
hues.

## HI.50 truecolor color schemes

**A scheme remaps names, never adds one.** `_HI_COLOR_SCHEME` (filled by
`_hi_color_tables` from the colors file's `[scheme]`) changes what the
twenty-four names render as; the hash, the pins, `_hi_color_escape`, and
`hi --preview colors` all keep the same names. Twelve are the terminal's;
twelve extras (orange, pink, ...) have no 16-color code, so
`_HI_COLOR_FALLBACK` gives every slot its nearest `<bold><hue>` pair, and
with no scheme the extras carry a built-in hex. `_hi_color_base` names the
pair for zsh's `%F{}` and fish's `set_color`.

**A pin's own hex outranks the scheme**, for that pin only.
`_hi_colors_scan` joins it to the name (`brred#ff5f5f`) and `_hi_color_split`
parts it, so it travels as one string (memos, `$_HI_TARGET_COLOR`, the
preview's grouping) and only the three color readers know it has two halves.

**One SGR**: `\e[<bold>;3<n>;38;2;<r>;<g>;<b>m`, the 16-color pair first, so
a terminal ignoring `38;2` keeps it. One escape keeps every reader of a
cell's leading escape working (`_hi_visible_width`, the header's cut at the
first `m`, `\e[[0-9;]*m` matches); `_hi_cell_hue` (HI.48) accepts `;` after
the hue digit.

**A fixed-width string** sliced by offset (`_hi_scheme_hex`): no arrays (zsh
indexes from 1) and no data file. hi ships no named schemes; the default's
first twelve slots are `000000` (the terminal's own). `_hi_assign_palette`
builds `$RED..$BRCYAN` through the same primitive, so a suite can rebuild the
palette under another scheme.

**Only the colors file sets it**: a `settings.sh` line of that name is
overwritten, and `hi --doctor` says so. `_hi_scheme_words` answers 24, 48, or
0; anything but exactly that many hex words renders the default. A 48-word
scheme's second bank (slots 24-47, the 16-color half taken at the index mod 24) paints only the package check (`_hi_packages_palette`, per render), since
the palette variables are the first bank. `scripts/lib.sh`'s `_hi_scheme_ok`
and `_hi_scheme_label` validate and label; core.sh only renders.

**The package ramp is the same shape**: `$_HI_PACKAGES_PALETTE`, eight names
from `[palette]`, judged by `_hi_ramp_ok` (in core.sh, so doctor reaches it
without header.sh), falling back to `$_HI_PACKAGES_RAMP`.

**The gate** is `_hi_has_truecolor`: `COLORTERM` of `truecolor` or `24bit`,
overridden by `_HI_TRUECOLOR`. ssh drops `COLORTERM`, so `_hi_session_env`
sends the client's verdict as `_HI_TRUECOLOR`: the escapes render in the
client's terminal. zsh takes `%F{#rrggbb}` from 5.7 (`is-at-least`), and
fish's `set_color hex name` picks what it can render.

## HI.51 docker-compatible CLI family

docker, podman, nerdctl, and finch take the same `ps --format`, `exec -i[t]`,
and `container inspect -f` grammar, so hi has one container arm and tries all
four, in that order. Each member is its own kind: `common/targets.sh` builds
its roster from the family and emits `<name>\t<cli>` per lane, `hi.sh`
generates one `_HI_BACKENDS` row per member at load, and
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

**Detection is cheap; the prefix is the shell's question.**
`common/env_prompt.sh` names every active environment manager as the
prompt's leading `(mise|direnv:proj|myproj)` from variables the tools export.
But venv's activate script and conda (unless `changeps1` is off) draw a
prefix of their own, and whether it survives depends on the shell: zsh sets
`$PS1` once and fish's `fish_prompt` is the very function activate wrapped,
so theirs stays; bash's `__hi_ps1` rebuilds `$PS1` every draw, so it is gone
by the second prompt.

So `$_HI_ENV_DEFER` is the shell's verdict: 1 in zsh and fish, where the
venv and conda rows stand down when the tool's marker is present
(`$_OLD_VIRTUAL_PS1`, `_old_fish_prompt`, `$CONDA_PROMPT_MODIFIER`), and 0
in bash, where hi draws them. A venv is named in all three shells. While a
tool's prefix stands, hi drops its own lead space. hi never sets
`VIRTUAL_ENV_DISABLE_PROMPT=1` itself, since every other shell the user
opens reads it.

config.fish keeps its own copy of the list, since a `bash -c` per prompt is a
fork; `tests/hi/prompt_test.sh` pins the two. mise shows only where a project
config between `$PWD` and `~` overrides the global one (a `~/.tool-versions`
covers everything), found by a builtins-only walk memoized on `$PWD` (HI.16).

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

bash's completion has no description column - every `COMPREPLY` entry is a word
readline may put on the command line - so a backend symbol beside a target name
(`web ▣`) is safe only while readline _lists_ matches, never when it inserts
one. `_hi_complete` reads `$COMP_TYPE`: `?`, `!`, and `@` (63, 33, 64) list, so
their entries carry the symbol; a plain `TAB` (9) inserts the common prefix and
menu-complete (37) cycles whole entries, so both get bare names. A name two
backends share is listed once with both symbols (`dup »▣`), or the entries'
common prefix would run past the name into the space. bash 3.2 has no
`$COMP_TYPE`, so its list stays bare. fish and zsh carry the symbol in a column
of their own (`__hi_targets`' description, `_hi`'s `-d` display) and need none
of this.

## HI.57 carried configs and the include scan

**Which file.** hi starts each editor on a carried config (`-u`, `--rcfile`,
`-nw -q -l`, `-c`, kakoune through `$KAKOUNE_CONFIG_DIR` since `kak -n` would
drop its system kakrc), as do tmux (`-f`) and screen (`-c`); micro and zellij
take a directory. Which file is [HI.61](#hi61-one-overlay-priority)'s order:
the overlay copy, else the config the tool reads on this machine. hi ships
none of its own, so with neither there is no alias. The alias is the
target's alone, a line of `wiring.sh` ([HI.62](#hi62-generated-wiring)): at
home every tool reads its own config, and `vim -u` would skip the system
vimrc.

**The scan.** A carried config can name a path no target has (a second rc, a
plugin directory, a manager's bootstrap), and the tool would fail there.
`scripts/pack_scan.sh`'s `_hi_lint_awk` finds those lines, by the grammar of
the member's `<dialect>` row in `$_HI_DIALECTS` (the comment above it lists
each dialect's rules). `_hi_stage_tar` runs it in `fix` mode before the
[strip](#hi35-payload-comment-and-whitespace-strip), so a finding goes out
disabled and costs no bytes; `hi --doctor` runs it in `report` mode. A member
with no dialect rides untouched. There is no switch to turn it off; the
marker comments (`hi-allow`, `hi-quiet`, `hi-carry`, `hi-drop`, each with a
`-start`/`-end` pair; docs/SETTINGS.md) are the per-line answer. Pairs are
found by reading the file once before the scan, since a start's end is known
only at the end; an unclosed start is an `unclosed` row.

**Disabling leaves a file that parses.** vim and nano are line-oriented
(tmux takes its `\` continuations). lua, elisp, and kdl comment out the whole
bracket-balanced expression, so `require("lazy").setup({` leaves no stray
`})`; `bal()` ignores strings, and `'` delimits only in lua (in elisp it is
the quote operator). sh and fish turn only the verb and its file word into `:`
or `true`, since an empty `then` body does not parse. A value the dropped
line bound (`local m = require("x")`) can still fail later; the doctor rows
name the line.

**Carried includes.** An include of a file in the tool's own directory (its
source's directory, `$XDG_CONFIG_HOME/<tool>`, `~/.<tool>`, `~/.<tool>.d`) is
carried instead (`_hi_stage_carry`): the file rides as `<tool>/<path>`,
scanned in turn, and the include's path becomes `@@HI_CONFIG@@/<tool>/...`,
which the target rewrites to its overlay directory as it unpacks
(`_hi_overlay_fixup`). A relay sends its copy, its own directory as the word
([HI.66](#hi66-the-packer-stays-home)). The overlay cache watches the carried
files. A `hi-carry` line's files under `$HOME` ride as written (no scan, no
strip) under `<tool>/carried/` or `<member>.carried/`.

**neovim's `require`** names a module: one under `lua/` in those directories
(`lua/x/y.lua`, else `lua/x/y/init.lua`) rides as `nvim/lua/...` and is
scanned in turn (`_hi_require_carry`). The line stays, under a `hi-allow`,
and the staged `init.lua` first adds `@@HI_CONFIG@@/nvim` to the
`runtimepath`. A `require` that resolves nowhere is dropped.

**git** is read for what is private, matched as lower-cased
`<section>.<key>`: the keys docs/INTEGRATIONS.md's _git_ lists are `private`
rows, dropped with their continuations. Headers stay. Under a `hi-allow` a
private line rides and is an `allowed` row for `hi --plugins`
(`_hi_allowed_lines`).

**nano's syntax includes** are given back. A dropped `*.nanorc` include
outside `/usr/share/nano` keeps its comment through the strip, and `load.sh`'s
`_hi_nano_fallback` adds an include under it each session: the same path
where the target has those files, else the stock set. Each `extendsyntax`
takes the target's spelling of its syntax, compared without case (`GO` and
`go`), or becomes a kept `# hi dropped:` comment. It is rewritten from the
comments every session, since the copy rides on to a next hop.

## HI.58 overlay directory members

A `$_HI_OVERLAY_FILES` entry ending in `/` names a directory, and its members
ride one by one: `scripts/pack.sh`'s `_hi_overlay_files` lists each as
`<dir>/<name>`, in name order, over the overlay's directory and home's, each name once and the
overlay's copy first (zellij's `layouts/` and `themes/`, kakoune's `colors/`),
or over the overlay's alone where the row has no home (`extensions/`,
`header/`, `bin/`), and the rest of the stream - `_hi_overlay_src`, the cache key, the
stager, [HI.35](#hi35-payload-comment-and-whitespace-strip)'s strip (by the
directory row's dialect) - treats that path like any member. The directory stays
an allow list: `core.sh`'s `_hi_dir_member_ok` admits a plain name only (a
letter or digit first, then `[A-Za-z0-9_.-]`, not ending
`.bak`/`.orig`/`.rej`/`.tmp`), and the target reads the directory back through
the same function, so a file hi would not send is one hi would not read either.
The archive carries no directory entry; every tar hi unpacks with creates the
parent, busybox's included.

`bin/` is scripts for a session's `$PATH`. `_hi_bin_ok` admits a file that is
executable, opens with `#!`, and holds no NUL and no more than `$_HI_BIN_MAX`
characters, read with builtins since every connect asks; the row has no
dialect, so a script rides as written with its mode. `load.sh` appends the
directory to `$PATH` as it is sourced, where `hi <target> <cmd>` and the
session shell both inherit it, and last, so nothing in it stands in for a
command of the target's; a kept session's pane launcher appends it too, since
the multiplexer's server never had it.

The two directories of code, `extensions/` and `header/`, are listed by one
function, `core.sh`'s `_hi_dir_members`: the members in name order, and every
other entry apart, for `hi --doctor` to name. Each loader parses a member
before it sources it, and skips one that does not parse with a line on stderr.

## HI.59 extensions

**Code of the user's, in one file for three shells.** `extensions/` is a
directory member ([HI.58](#hi58-overlay-directory-members)) with no home tier:
each file is in `common/aliases.sh`'s POSIX+fish subset, so another tool's
init or a prompt segment rides to every target with no change to the tree.
(A plugin is something else: a config hi carries,
[HI.64](#hi64-what-is-switched-off).)

**Loaded right after the aliases** (so it can replace them) and before the
prompt is built, in name order: `_hi_load_extensions` for bash and zsh, a
copy in `config.fish`. Each file is parsed first (`bash -n`, `zsh -n`,
`fish --no-config -n`, a fork each); one that fails is skipped with a yellow
line rather than half-run. The glob lives in `_hi_dir_members` so zsh's
`null_glob` stays local, and it tests `-d` first, since an unset directory
([HI.60](#hi60-a-shell-that-outlives-the-tree)) would glob `/*`.

**Hooks are variables**, since the subset cannot define a function all three
read. Each is unset before an extension runs and collected after, so
extensions compose:

| hook               | what hi does with it                                                                                                                                                  |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_HI_SEGMENT`      | a command and words, split at spaces and run as is (no syntax, glob, or `eval`) every prompt; output drawn after the environment segment. Ignored under a prompt tool |
| `_HI_PROMPT_INIT`  | a prompt program's init ([HI.67](#hi67-shell-hooks)'s shape, `{shell}` the shell's name), run in place of hi's prompt where its command exists                        |
| `_HI_PROMPT_DRAWN` | `1`: the extension drew the prompt, and hi's stands down                                                                                                              |

**The overlay's `aliases.sh` is parsed the same way** (`_hi_parses`), since
its home tier (`~/.aliases`, `~/.bash_aliases`) may hold bash functions.
`common/aliases.sh` cannot tell which shell it is in, so each rc hands it
the check as `$_HI_ALIAS_GUARD` (`true` for plain `sh` and for `load.sh`'s
`$EDITOR` read). `hi --doctor` lists the extensions in load order and flags
any that do not parse here, and any stray directory entry
(`doctor_code_dir`).

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
row gone, and `"$_HI_EXTENSIONS"/*` globbing `/` - which
[HI.59](#hi59-extensions)'s loader then `bash -n`s and _sources_, file by file,
in every pane at once.

So `common/bash.sh` and `common/zsh.zsh` `unset _hi_core_loaded` before they
source core.sh. `load.sh` already did, for the same reason on the far side (a
target whose own `~/.bashrc` wires a say-hi of its own loads that tree's
core.sh first), and `common/config.fish` never had a guard to clear.
`_hi_dir_members` tests `-d` on the directory it is handed before it globs, so
no later name arriving empty can reach the root of the disk again.

## HI.61 one overlay priority

**One order for every member**: the overlay copy; else, for `settings.sh`,
`colors`, `packages`, and `plugins`, the site tier's (`$_HI_SITE_DIR`:
`/etc/say-hi`, else the first `say-hi/` under `$XDG_CONFIG_DIRS`, read on the
client only); else the user's own file at home; else the tree's default. A
site `settings.sh` is joined under the user's (`_hi_tag_settings`), a site
`colors` or `packages` rides as an overlay copy would (`_hi_overlay_site`),
and a site `plugins` is read between the tree's and the user's. Tiers may be
added in a minor, never reordered.

**Written once**, as `scripts/pack.sh`'s `$_HI_OVERLAY_TABLE` (hi's own
files, never switched off) plus the plugins rows ([HI.63](#hi63-plugins-rows));
the table's comment lists the columns. `_hi_overlay_src`, the cache, the
include scan, and `hi --doctor` all read it; `_hi_overlay_home` walks a
member's home candidates. `paths.sh` cannot read a table (no loop in its
dialect), so it spells out hi's own rows, and `paths_test.sh` checks them
tier by tier. `doctor_files` walks the same rows, marking each location used
or passed over.

**The home tier is this machine's**: the client only (a relay packs nothing
of the middle box's, [HI.66](#hi66-the-packer-stays-home)), and only with the
member's tool here (`_hi_tool_here`). Whichever tier answers, the
[include scan](#hi57-carried-configs-and-the-include-scan) runs over it.

**Shell rcs have no home tier.** `bashrc`, `zshrc`, and `config.fish` are
where tokens get exported, so a `~/.bashrc` found at home would run on every
box unasked; they ride only from the overlay ([SUPPORT.md](SUPPORT.md) keeps
the same line).

**Members are named like `~/.config`**: `<tool>/<file>` where the tool keeps
a directory there, else the bare name (`starship.toml`, `inputrc`), so no two
tools collide. A trailing `/` on a home candidate is a directory to look in:
micro's and zellij's fixed file names resolve one by one, and zellij's
`layouts/` and `themes/` are directory members
([HI.58](#hi58-overlay-directory-members)).

## HI.62 generated wiring

**The client writes the target's lines.** Pointing a tool at its carried
config is a line every target shell must parse, in `common/paths.sh`'s
four-shell dialect, which has no loop; so `_hi_overlay_wiring` writes them
into `wiring.sh`, staged beside the members, and `paths.sh` sources it on a
target only. A row's wire says how:

- `env:<vars>` exports each as the member's path; `<var>=<word>` sets a
  word (git's `GIT_CONFIG_COUNT=1` and `GIT_CONFIG_KEY_0=include.path` beside
  `GIT_CONFIG_VALUE_0`). `envdir:<var>` names the directory (eza's fixed
  `theme.yml`). An `env:` over one of hi's names (`$_HI_VIMRC`, `$_HI_NVIMRC`,
  `$_HI_NANORC`) tells `load.sh` a path without naming a member.
- `flag:<command> <words>` aliases the command with the words and path, where
  the target has it (a flag ending in `=` takes the path in the same word);
  `flagdir:` the directory. `<names>=<command>` adds names, and `VAR=value`
  words before the command are its environment (neovim answers to `vim` too).
  The path goes in unquoted, since `load.sh` reads an alias body back for
  `$EDITOR`.
- `xdg:<command>` aliases with `$XDG_CONFIG_HOME` at the overlay, the last
  resort, since everything the command starts inherits it (helix's
  `languages.toml`, whose row follows the flag row so its alias wins).
- `-` leaves the member to hi's code. Several wires go `;` apart, later
  aliases winning.

micro gets `-backup false -savehistory false`, since its config directory is
the session's tree.

**So a target knows no member by name**, tests no file per shell start, and
gets no line for a member that stayed home. Paths stay under
`$_HI_CONFIG_DIR`, unexpanded, so the file holds on a relay. `wiring.sh` is
no member: one in the overlay is not read.

**A plugin's `env`** is the one line with a value from this machine:
`export NAME='value'` for each named variable set here. A value holding a
quote, backslash, or line break stays home (`_hi_env_rides`); a secret-looking
name is refused ([HI.63](#hi63-plugins-rows)).

The lines are part of `_hi_overlay_cache_key`, since a newer packer may wire
the same members differently. Nothing is written behind a setting's test:
what is off is decided on the client ([HI.64](#hi64-what-is-switched-off)).
An alias line ends `|| true`, since `core.sh` sources `paths.sh` under
`set -e`.

## HI.63 plugins rows

**Plugins are TOML tables.** The tree's `config/plugins` and the overlay's
`plugins` share one shape, the subset `_hi_toml_row` reads
(docs/SETTINGS.md's _A tool hi does not know_ has the keys).
`_hi_plugins_load` reads both into `$_HI_PLUGIN_ROWS`, a row per file in the
overlay table's shape ([HI.61](#hi61-one-overlay-priority)), so everything
downstream (order, tool check, include scan, cache,
[wiring](#hi62-generated-wiring), `hi --doctor`) treats the user's rows as
hi's. The overlay's is read second; a plugin of a tree plugin's name replaces
it in place. The tool is the record because the tool is what is switched,
wired, and reported, and a new key is a line a 1.x can add where a column was
a break.

**A home column is data, never evaluated.** `_hi_path_list` reads
`:`-separated candidates starting at `/`, `~/`, or `$NAME` (dropped while
unset); `,` within one takes the first not dropped (`$NAME/rc , ~/.rc` is
`${NAME:-$HOME}`'s place). Nothing else expands. A grammar can grow in a 1.x
where an `eval` could never narrow. `@<function>` homes are the packer's own,
for the tree's file only.

**What the table cannot hold is left out** and recorded in
`$_HI_PLUGIN_BAD` (file, line, reason) for `hi --doctor`: unknown keys or
lines, a malformed or duplicate table, a plugin with no files, a member that
is not `<name>`, `<dir>/<name>`, or `<dir>/` (`_hi_plugin_member_ok`) or is
taken (hi's own, another plugin's, `wiring.sh`, `plugins`), a bad tool, wire,
dialect, `shells`, or `env` (including one of hi's names or a secret-looking
one). A file turned down takes nothing of its plugin with it. The wire is
checked because it becomes a line every target sources: nothing in it may run
or expand beyond `$NAME`. The check and `_hi_overlay_wiring` share one parser,
`_hi_wire_read`, so what is admitted is what is written.

**Neither file rides.** The packer stays home
([HI.66](#hi66-the-packer-stays-home)), so the tree's file is cut from the
payload (`$_HI_PAYLOAD_CUT`) and `plugins` is no member. A relay sends the
`config/` it was given.

**The reading is cached** as `hi.plugins.<key>` in the runtime dir (parsing
was a third of a connect's client work), read back line by line, never
sourced, and refreshed when a plugins file or `scripts/` is newer, or a
plugins file appears, goes, or changes size.

## HI.64 what is switched off

**A plugin** is a `[<group>.<name>]` table ([HI.63](#hi63-plugins-rows)). A
row with no group is hi's own file, which only its off column switches
(`packages`, under `_HI_DISABLE_HEADER`). `_hi_plugin_off` says a member is
off when `$_HI_PLUGINS_OFF` names its plugin, its row's member, or itself
(one file of a directory row, `extensions/10-kube`), or a toggle in its off
column is 1.

**Decided on the client**, at the two gates every member passes
(`_hi_overlay_src`, `_hi_overlay_files`): what is off is not packed, has no
wiring line ([HI.62](#hi62-generated-wiring)), and is not in the cache key.
An overlay copy stays home too, since off outranks a file. A prompt program
that is off is left out of the list a target gets (`_hi_prompt_here`) unless
`_HI_PROMPT_TOOL` names it.

**Cheap and right.** The usual verdict, nothing off, is memoized on the
values in force (the list and `$_HI_OFF_TOGGLES`). Under `_HI_DISABLE_LOCAL=1`
`paths.sh` sets every toggle for this machine, so `_hi_toggle_on` reads
`settings.sh`'s own `export` lines as text, the last of a name winning.

`scripts/plugins.sh` and `hi --configure` write the list as one
`_HI_PLUGINS_OFF` line in the same spelling, so each rewrites the other's.
On a target `load.sh` reads it from the `settings.sh` that rode: an editor in
it is skipped for `$EDITOR`, and `vim` or `nvim` sets no `$VIMINIT`.

## HI.65 kept session

`hi --keep <target>` (or `_HI_KEEP=1`) runs the session in the target's tmux,
zellij, or screen so it outlives the connection; with none of the three, the
session's tree is held through a drop instead. It is the bash tier's, on
every arm; only an ssh drop is retried. `common/keep.sh` holds both halves:
the client's (sourced by `hi.sh`) and the target's (by `load.sh`).

`$_HI_DISABLE_KEEP=1` turns it all off through `_hi_keep_off`: no connect
carries the attach, start, sweep, or hold; `--keep` and `--end` are refused
(`_hi_keep_refuse`); and `keep.sh` and `mux.sh` stay out of the payload. A
session's `hi.sh` and `load.sh` read their absence as the switch and define
no-op stand-ins, so a relay carries none of it either.

- **The name.** `hi-<target>-<id>` (`_hi_mux_name`): the target as typed,
  with anything outside `[[:alnum:]_-]` turned to `-` (tmux refuses `:` and
  `.`), then a hash of the client's username, so people sharing an account
  keep their own sessions without naming themselves in the target's process
  table ([HI.47](#hi47-what-a-child-inherits)).
- **Reattach first.** Every interactive connect carries `_hi_keep_attach`
  between the preamble and the unpack: `_hi_kept` asks tmux
  (`has-session -t =<name>`), zellij (`ls -n`, exited sessions dropped, since
  attaching would resurrect one), then screen (`-ls`, dead entries dropped).
  A hit attaches and the script ends, nothing unpacked. `--no-keep` and a
  one-off command leave it out.
- **The owner pane.** Otherwise `_hi_keep_start` replaces the bash handoff
  with the multiplexer's start running the same `bash --rcfile hi.bashrc -i`.
  `load.sh` runs there as in any session, so its exit hook still removes the
  tree. The session's variables go as an `env NAME=value ...` argv, since a
  running server hands new panes its own environment, and are unset before
  the exec so a new server keeps none of them. `$_HI_KEEP_MUX` and
  `$_HI_KEEP_NAME` tell `load.sh` it is the owner.
- **zellij** takes a first command only from a layout, so the start writes
  `hi.keep.kdl` (the `env` argv as escaped KDL strings, under zellij's own
  bars), with `--session-serialization false` (nothing to resurrect),
  `--on-force-close detach`, and the startup popups off, each only where
  `zellij options --help` lists it, since an unknown option stops zellij.
- **The trap stands down.** bash as `sh` runs the bootstrap's exit trap on a
  hangup, so on a keeping connect the trap is guarded by `_hi_kept ||`.
- **No multiplexer: the hold.** The bootstrap traps the hangup
  (`trap : HUP`) and hands off with `$_HI_KEEP_HOLD`. `load()` holds when it
  is no owner pane, has a disposable tree and a terminal, and
  `$_HI_HOLD_TIMEOUT` is not 0 (`_hi_keep_holds`), once `hi.hold` names the
  session (written by `load()`, or later by `hi --keep` typed inside,
  `_hi_keep_hold_here`). A per-shell hook writes `$PWD` to `hi.cwd`. When the
  terminal is gone the exit hook leaves the tree under `hi.held` (watcher
  pid, shell pid, name) instead of removing it; an `exit` still removes it.
- **The timer.** `_hi_tree_watch`, which every session runs, waits
  `$_HI_HOLD_TIMEOUT` (15m) once `hi.held` names its shell, then removes the
  tree; `hi.end` (from `hi --end`) stops it early, and a tree whose `hi.pid`
  changed is left to its new session.
- **Taking a held tree.** After the sweep, at a terminal, `_hi_keep_held`
  adopts a sibling tree whose `hi.held` carries the name, only in a
  directory the account owns and never through a symlink. It writes its pid
  to `hi.pid` and removes `hi.held` (the step one of two connects wins),
  drops its own empty tree, re-points `$_HI_HOME`, and changes to `hi.cwd`.
  The unpack is skipped; the header says `Resumed`.
- **A bare multiplexer.** In a session, `tmux`, `zellij`, and `screen` are
  aliases to `common/mux.sh`. Typed bare at a terminal, outside a
  multiplexer, it asks `[y/N]`, saying what stays and for how long; `y` runs
  `hi --keep` with `$_HI_KEEP_WITH` naming the tool. With arguments it runs
  the tool on the carried config, unasked.
- **Kept from inside.** `hi --keep` with no target keeps the current session
  (`_hi_keep_here`): the attach block exported `$_HI_KEEP_AS` (the target as
  typed), and `load()` wrote `hi.keep` (`NAME=value` lines: the name, the
  client's verdicts, the tree, its own pid as `$_HI_KEEP_OUTER`), which
  `hi.sh` reads since a child inherits none of them. Two sessions now share
  the tree: `hi.kept` stops the first session's `clean_all` and trap, and the
  owner pane leaves the tree while `$_HI_KEEP_OUTER` runs. A session with no
  `hi.keep`, or already in a multiplexer, says it cannot be kept.
- **Other panes.** A new pane runs the host's default shell, which reads none
  of hi's rc ([HI.46](#hi46-session-rc-directory)), so `_hi_keep_panes`
  writes a launcher, `hi.pane`, and sets it as this session's tmux
  `default-command`, screen `shell`, or (at start) zellij `--default-shell`.
  The owner's `clean_all` kills the session after removing the tree.
- **Closing.** When the owner pane's shell exits with a client attached,
  `_hi_keep_stays` asks; anything but `y` detaches and starts a fresh shell
  (zellij cannot detach, so it names the key). tmux's `detach-on-destroy` is
  set `on` for the session. `hi --end` kills the session over one `probe`
  call, waits up to two seconds for a pane to go (zellij may SIGKILL bash
  before its hook runs), then sweeps.
- **A session that died.** A target that goes down runs no exit hook. So
  `load()` claims its tree (`_hi_keep_claim`): `hi.kept` for an owner pane
  (its pid, then `$_HI_KEEP_OUTER`'s), `hi.pid` otherwise, `hi.held` for a
  held tree. Once a looking connect has its own tree, `_hi_keep_sweep`
  removes each sibling (`<user>.hi.*`) whose claim names no live process.
  Pids are asked, not the multiplexer, which another socket directory hides;
  an empty claim or none is left alone. `_hi_tree_watch` covers the case in
  between: a detached job that ignores the hangup and runs the exit hook if
  the shell and the bootstrap were both killed.
- **The client's record.** An empty `hi.kept.<key>` in the runtime directory
  (`<key>` as the control socket's) marks a target seen with a kept session.
  The script ends 86 when it leaves one behind and 0 otherwise, run as
  `sh -c '...; e=$?; rm -rf <scratch>; exit $e'` so the status survives
  cleanup. `_hi_keep_connect` sets the record on 86, clears it on 0, and
  leaves it on anything else; a keeping connect writes it up front, and
  `hi --end` removes it. With it set, a connect that finds no session (on a
  target with a multiplexer) says the kept session is gone.
- **The retry.** At a terminal, an ssh session that was up, ends 255, and has
  the record is retried every five seconds for `$_HI_KEEP_RETRY` (5m), with
  `ConnectTimeout=10` and the boot call's stderr held until the target
  answers. A try that drops within ten seconds keeps the window. The drop's
  line names how long the target keeps the session (`_hi_keep_until`, from
  the boot probe's `HIMUX`), and `_hi_keep_wait` draws a dot a second. `~.`
  also ends 255, so Ctrl+C is how to leave. A frozen link becomes a drop via
  `ServerAliveInterval=15`, `ServerAliveCountMax=3`, where the ssh config
  sets no interval (`_hi_keep_alive`).
- **The timeout.** `_hi_keep_watch`, an owner-pane job polling each minute,
  kills the session after `$_HI_KEEP_TIMEOUT` (24h) with nobody attached;
  `clean_all` kills the job's process group. A zellij that cannot list its
  clients counts as attached.

## HI.66 the packer stays home

What a connect sends is built by `scripts/pack.sh`, which `hi.sh` sources
where it finds it: the overlay table and the plugins rows, home's lookups, the
include scan, the comment strip, the staged tars and their caches. Only the
machine that owns the config runs any of it, and `scripts/` never rides, so
none of it costs a byte on the wire.

A session's tree has no `scripts/`, and needs no packer: the tree _is_ the
payload, already stripped, with the overlay unpacked over `config/`. There
`hi.sh` defines the packer's side of a connect itself, in five short
functions: no overlay members, no cut list, no cache, and a `_hi_payload_tar`
that tars `$_HI_PAYLOAD` as it stands. A relay sends what it was sent.

- **The seam.** `_say_hi` reaches the packer through
  `_hi_overlay_files`, `_hi_payload_excl`, `_hi_payload_cached`,
  `_hi_payload_tar`, and `_hi_payload_stream`, the five a session defines, and
  through three that run only with an overlay to send or outside a session
  (`_hi_overlay_cached`, `_hi_overlay_stream`, `_hi_prompt_here`). `payload_test.sh` holds `hi.sh` to that list.
- **Carried includes.** An include the client carried names the config
  directory of the hop it landed on, once `_hi_overlay_fixup` has run there.
  A relay hands that path on as the token, so the next hop's fixup makes it its
  own; a path a script cannot hold bare is no token, and nothing is rewritten.
- **Not a broken install.** Outside a session a tree without the packer is
  incomplete, and `_hi` refuses before anything is sent.

---

## HI.67 shell hooks

**A plugin's `init` is its tool's own shell setup**: a command that prints
shell code (`{shell}` the shell's name), as each tool documents with
`eval "$(<tool> init bash)"`. hi runs it in one place, `_hi_run_init` (and
its fish copy), where the command exists, after the aliases and extensions
and before the prompt: the one site that evaluates a tool's own output, held
as the `tool` row of `tests/lint/eval_roster`.

**The client decides.** `_hi_overlay_wiring` writes `_HI_HOOKS`
(`<group>.<name>=<init>` rows, `;` apart) for each init plugin whose tool is
here and which is on; a prompt plugin (`prompt = "yes"`) goes to
`_HI_PROMPT_INITS` and `_HI_PROMPT_PLUGINS` instead, so only the prompt
hand-over ([HI.32](#hi32-starship-deference)) starts it, and `_hi_prompt_row`
picks such a program like a table one. In each row a leading `-` means off by
default (on only when `_HI_PLUGINS_ON` names it, `_hi_hook_on`; the shipped
`hooks` group, whose tools keep state in a target's `$HOME`), `~` means
`quiet` (both streams to `/dev/null` while it activates), and `:<shells>`
limits the shells.

**Only the session's tree runs them.** A target's own wired hi would read the
session's `wiring.sh` through the inherited `$_HI_CONFIG_DIR`, so `_HI_HOOKS`
is set only where `$_HI_CONFIG_DIR` is `$_HI_ROOT/config`. Each shell runs
them once (`_hi_hooks_ran`); `load.sh` sets that flag over the bootloader's
profile chain, where nobody types.

**An init is data**: a command and words, refused with a quote, `;`, `|`,
`&`, `$`, backtick, or bracket, since what runs is its output, not the line.
