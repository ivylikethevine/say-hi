# Glossary of Deliberate Oddities

say-hi's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `settings/aliases.sh` and
`settings.sh` natively). Targets also split between **GNU and BSD userlands**.
Each entry is a construct that looks odd until you know which master it serves.

Every entry carries a stable `HI.NN` code; a file references it with a
`# GLOSSARY: HI.NN` tag — one code, or two joined with `+`, optional prose
after — instead of re-explaining. The tag is _mandatory_ in `common/`,
`settings/`, `load.sh` and `hi.sh`. Tags point at codes, so an entry can be
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
- [HI.35 payload comment strip](#hi35-payload-comment-strip)
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
strings via `_hi_kv_get`/`_hi_kv_set` (`tests/test_lib.sh`).

## HI.04 dynamic-name assignment

bash 3.2 has no namerefs, so writing into a caller-named variable goes through
`eval` (`_hi_read_lines`, `_hi_widen`) or `printf -v` for a single string.
Reading a caller's `local` works through bash's dynamic scoping — which cuts
both ways: a helper that writes an out-var by name must not declare a `local`
of the same name, or it writes into its own (`_hi_setting_get`'s locals are
prefixed for that reason).

## HI.05 printf -v out-var

`out="$(fn)"` forks a subshell per call; `fn outvar` with `printf -v "$outvar"`
doesn't. Used on hot paths (`_hi_git_prompt`'s optional out-var, `_hi_repeat`,
`_hi_prompt_end`) — but only in bash: zsh's `printf` has no `-v`, so zsh
callers keep the stdout form.

Never `printf -v x ''` (a bare empty format, zero arguments) to clear a
variable: on bash 3.2, that form leaves `$x` untouched rather than emptying
it, since printf skips the assignment outright when there is nothing to
format. `printf -v x '%s' ''` (one `%s` conversion, one empty argument) is
the form that actually clears it on every bash this project targets.

## HI.06 source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`scripts/install.sh`, `packaging/bump.sh`, `packaging/mkpkg.sh`,
`packaging/mkrepo.sh` and `scripts/preview.sh` all carry it.

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
`cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in `common/core.sh`;
`rewrite` in `packaging/stamp.sh` is the boundary-forced copy). `mv` would
transplant mktemp's 0600 mode onto the target and sever any hardlink/ACL — a
dotfile manager's hardlinked `~/.bashrc` must see the new content, and `hi.sh`
must stay executable in the payload. Non-atomicity is fine for single-user rc
files; `common/targets.sh`'s cache swap keeps `mv` for atomicity over a file
it owns.

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

`alias x="$(command -v tool-a || command -v tool-b || command -v fallback)"` in
`settings/aliases.sh`: resolved at source time, valid in sh, bash, zsh _and_
fish, and never leaves the alias pointing at a missing binary. The
`|| command -v echo` tail keeps `set -u`/`set -e` shells alive when nothing
matches.

A second, **narrower** chain over the same family delivers flags only to the
tier that parses them: `$_HI_BAT_BIN` is `bat || batcat` where
`$_HI_CAT_BIN` is `bat || batcat || ccat || cat`, so bat-syntax options
attach behind `[ -n "$_HI_BAT_BIN" ] && alias ... || true` and ccat and
coreutils `cat` get the bare binary.

Every such chain runs before any alias exists, the user's overlay
`aliases.sh` included (it is sourced last): in zsh and dash (not bash, not
fish) `command -v name` returns an _alias's_ definition once one exists, so
an overlay `alias cat=...` sourced ahead of the chains would leave
`_HI_CAT_BIN` holding the alias body instead of a binary path.
`alias_fallthrough_test.sh` is the regression test.

## HI.14 _hi_on_exit

bash's `trap "$cmd" EXIT` fires at real shell exit wherever it was set. zsh's
does not: an `EXIT` trap (`TRAPEXIT` included) set inside a function fires
when _that function_ returns — and `_hi_on_exit` (`common/core.sh`) is itself
a function, so every caller's cleanup fired at once, silently. `add-zsh-hook`'s
`zshexit` array is the one mechanism exempt from that scoping (zsh's own
completion system uses it for the same reason), so the zsh arm autoloads it
and registers a uniquely-named function there instead of touching
`trap`/`TRAPEXIT`. `_hi_on_exit` is the only way shared code registers a
cleanup trap.

## HI.15 strict-mode bracketing

Files that run inside an interactive shell (`common/core.sh`, `hi.sh`,
`common/bash.sh`, `common/git_prompt.sh`, ...) set `set -euo pipefail` at the
top _and disable it at the end of their own code_: left on, any later non-zero
status or unset variable kills the user's session. The bootloader and fallback
rc do the same on targets — forgetting it there breaks `hi <target> <command>`
outright.

## HI.16 no-fork reads

On per-prompt/per-startup paths, builtins over binaries: `read -r x < file`
instead of `$(cat file)`, `${target%/*}` instead of `$(dirname ...)`,
`${row%%$'\t'*}` instead of `| cut -f1`. A few forks per prompt is the whole
latency budget.

## HI.17 base64 armor

The payload is armored with `base64`, not `openssl`: pure ASCII transport
encoding (no crypto), shipped on strictly more targets — coreutils, busybox,
macOS/BSD, Git Bash. Decode tries GNU/busybox `-d` first, then old BSD/macOS
`-D`; the failed flag parse consumes no stdin, so the fallback still sees the
whole stream. `tr` runs first because GNU `base64 -d` tolerates newlines but
not spaces, and a transport that folds newlines into spaces would otherwise
break it. `$_HI_UNARMOR` only ever runs inside the sh bootloader — the login
shell never parses its braces (fish couldn't).

## HI.18 sh -c wrapping

Every command hi sends meets the target's _login_ shell first, which may be
fish — and fish parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is the transport's job, not per-site care
(unwrapped, the install probe answers "nothing installed" on every fish-login
host). Quoting is single-quote-and-escape rather than `printf %q`, which
backslash-escapes every space — unreadable in the code and in an `ssh -v`
log, and one more thing for fish to differ about.

## HI.19 stdin transport

The bootloader travels over **stdin of the first of two ssh calls multiplexed
on one connection** (one authentication), never as an argument: Linux caps a
_single_ argv entry at 128KB (`MAX_ARG_STRLEN`) however large `ARG_MAX` is,
and the payload is within a few KB of it. Two calls because the second's stdin
belongs to the interactive session. The script goes as plain text and is `cat`
into place; only the three binary streams _inside_ it are armored — armoring
the whole script spent a third of every session's bytes re-encoding ASCII.
The write doubles as the probe, and its status says what happened: the
directory came back and the session runs; `sh` ran but found no `base64`
(exit 64) or nowhere to `mktemp` (65), and hi names the missing piece and hands
over the host's own session; something that was not `sh` answered — a
`ForceCommand` or a `command=` key, told by an exit of 0 or any stdout,
neither of which a missing `sh` produces — and hi says so and hands over the
same; or nothing ran at all (stock Windows OpenSSH), and the session falls
through to the PowerShell branch rather than half-landing.

## HI.20 fallback rc

The no-bash target's rc is consumed by sh, zsh _and_ fish (`_say_hi`'s
`fish -C` branch), so every line must be valid in all three — `export
NAME=value` and `[ -f x ] && . x` are; anything shell-specific is appended by
that shell's own arm. Toggle defaults come first so the files after them still
win. `_HI_REMOTE_SESSION=1` is exported because this path never reaches
`load.sh`. `settings.sh` keeps its `[ -f ]` guard because a bare `.` on a
missing file abandons the rest of the file in ash/dash. `_HI_CONFIG_DIR` points
at the target's own `config/`, where the shipped overlay was unpacked.

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

Past the TTL the file is not discarded at once. For ten minutes after expiry
(`stale_for` in `targets.sh`) a TAB is answered **from the stale copy,
immediately**, and the replacing sweep runs behind it - no TAB inside a
working session waits on a daemon. A lock directory beside the cache allows
one refresh at a time, taken over if the lock outlives any real sweep. After
ten idle minutes the sweep is waited on again, like a first TAB.
`_HI_TARGETS_TTL=0` skips the file, and so this, entirely.

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

`_HI_PROMPT_TOOL=starship` hands the prompt to [starship](https://starship.rs) when
the target has it, and `_HI_PROMPT_TOOL=oh-my-posh` to
[oh-my-posh](https://ohmyposh.dev), keeping hi's header and aliases either
way. `common/core.sh`'s `_hi_wants_prompt_tool` is the single predicate (a
setting naming one of the two _and_ the binary); `common/bash.sh` and
`common/zsh.zsh` each `eval` their own `"$_HI_PROMPT_TOOL" init <shell>` behind it,
`common/config.fish` mirrors the rule since fish cannot call it. Both tools
take `init <shell>`, which is what lets one predicate and one stub (the rc
suite's `_hi_prompt_stub_dir`) cover both. `common/paths.sh` points the tool
at the overlay's `starship.toml` / `oh-my-posh.json` (`$STARSHIP_CONFIG` /
`$POSH_THEME`) on a target only (`_HI_REMOTE_SESSION=1`) and only when the
file came along, so the prompt on every host is the one configured at home; at
home the tool's own config is left in force. paths.sh rather than core.sh
because fish sources paths.sh natively and the variables have to reach a fish
session too. Absent the tool, the setting is ignored silently.

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

| where                                                           | how                                                                                                                                                                                                                        |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `common/core.sh`                                                | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`; answers for every file sourced through it                                                                                                                                  |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh`               | the same behind a `readlink` walk - `$_HI_LINK` is `~/.local/bin/hi` (a package's is `/usr/bin/hi`), and unresolved it answers the link's own parent. Three copies: each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh`                               | `${BASH_SOURCE[0]}` - entry points that _export_ for children                                                                                                                                                              |
| `scripts/doctor.sh`, `scripts/preview.sh`, `tests/test_lib.sh`  | `${BASH_SOURCE[0]}`, then `$_HI_HOME` if set - the standalone-entry form below                                                                                                                                             |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; bash cannot parse `%x`, so core.sh's arm is `eval`'d                                                                                                                             |
| fish (`common/config.fish`)                                     | `sh -c 'cd -P "$1/../.." && pwd'` - a builtin-only substitution would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical                                                        |
| `common/bash.sh`                                                | `$_HI_HOME` first, its own path as the fallback - `hi.sh`'s preamble and `install.sh`'s rc line both set it before this file is sourced                                                                                    |

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

One place keeps a fallback, and says so out loud: `hi.sh` prints
`set _HI_HOME to the directory that holds it` and exits when the derived path
holds no tree. A _target_ needs no such rule — a session's tree is the one hi
just unpacked there, and its `$_HI_HOME` is exported by the script that
unpacked it, so nothing on the far end has to go looking. A say-hi the target
already has is its own install, for that machine's own shells; hi does not
read it from a session.

`tests/lint/drift_test.sh`'s `lint_home_default` greps the tree, `.md`
included, for the retired spellings — a doc teaching a retired spelling is
what a packager reads.

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

## HI.35 payload comment strip

Every `*.sh`, `*.zsh` and `*.fish` file — and the `flags`/`colors`/`packages`/
`vim.rc`/`nano.rc`/`emacs.el`/`helix.toml`/`kak.rc` data files, whose prose headers document the _installed_
copies — is comment-stripped on its way into the payload (`_hi_strip_awk` and
`_hi_payload_tar` in `hi.sh`); about 40% of the shipped shell is comment.
vim.rc's comment character is `"` and emacs.el's is `;`, each its own rule in
the stripper.
`bench_payload_readme_badge` checks README's badge against the result.

Two rules keep it safe. **Full-line comments only**: an inline `#` cannot be
told from `${x#y}`, `$#` or a `#` in a string without a real parser. **Never
inside a heredoc**: those bodies are data the target reads, one of them
`hi --help`. The comment test runs _before_ the heredoc-open test: a comment
mentioning `<<WORD` would otherwise open a heredoc that never closes and
silently stop stripping the rest of the file.

`tests/hi/payload_test.sh` pins the rest: no full-line comment survives outside
`hi.sh`'s heredocs, every code line survives byte for byte, the result still
parses, and `hi.sh` keeps its exec bit — the write-back is HI.09's `cat`, for
the same reason.

## HI.37 zsh pattern-in-variable

`_hi_ssh_pattern_hit` (`common/core.sh`) matches a name against `Host`/`Match
host` glob patterns from `~/.ssh/config`. `*` and `?` mean the same in ssh's
syntax as in a `case` pattern; the difficulty is trying each pattern in a way
that survives both bash and zsh.

Two zsh divergences stack. zsh does not word-split an unquoted variable, so
`for pat in $patterns` never iterates; `setopt localoptions shwordsplit` fixes
that, scoped to the function. And zsh does not treat `*` in a _variable's_
value as an active wildcard unless `GLOB_SUBST` is set — same symptom, a
`case` that never matches. The tempting `setopt globsubst` breaks the first
fix: the split tokens are then also glob-expanded against real files, and a
pattern matching nothing on disk errors the loop out. `${~pat}` is the escape,
a per-expansion toggle treating that one substitution as a pattern; bash does
not understand it, so the function branches on `$ZSH_VERSION`.

A `!`-prefixed token (ssh's per-pattern negation) is not honored as exclusion —
it survives as a literal pattern nothing is ever named, so it is inert rather
than wrong; the cost, a wrongly-colored excluded host, is cosmetic.

## HI.38 split tar and gzip

`_hi_tar_gz` (`hi.sh`) runs `tar cf - | gzip -n` rather than `tar czf -`. The
two userlands pad differently, and only one pads something that survives
compression: GNU tar rounds the _uncompressed_ archive up to the 10240-byte
blocking factor and then gzips it, so its trailing NULs cost about thirty
bytes; bsdtar — macOS's `/usr/bin/tar` — pads the _compressed output stream_,
appending raw NULs after the gzip member, so every payload a BSD client built
was a multiple of 10240: about 27% waste on a stock payload and a flat 54× on
a two-file overlay (189 B against 10240). Split, the steps agree with GNU tar
to within a few bytes under both userlands and are byte-stable run to run.

`${PIPESTATUS[@]}`, not `$?`: `hi.sh` turns `pipefail` back off for
interactive sourcing, so a failing tar would otherwise hide behind a
successful gzip and ship a truncated payload — both halves are checked. A
client with no `gzip` degrades to `tar czf -` rather than failing: padded
again on bsdtar, but a working payload.

## HI.39 payload staging

`_hi_payload_tar` (`hi.sh`) ships the tree, comment-stripped (HI.35). What
ships never depends on a toggle: `$_HI_PAYLOAD` is whole directories, every
toggle is read where it applies, and a session that switched something off
carries the file and leaves it alone (a per-toggle trim of the tar would
save about a kilobyte at the cost of a cache key, a second table and an
exclusion list).

**Staged, in a subshell, under a trap.** The strip rewrites files and the tree
is not hi's to touch, so a `tar | tar` pair copies it to a `mktemp -d` stage
(`-h` resolves symlinks so the stage holds real files).
The subshell lets cleanup be an `EXIT` trap rather than an `rm` on each way
out — a ^C during a slow build would otherwise leave the stage in the client's
tmp. `INT` and `TERM` are trapped explicitly to `exit`, since a signal that
kills the subshell outright never reaches the `EXIT` trap; set in the
function's own shell the trap would replace the one `_hi` installed for its
error log.

**One awk, then `_hi_write_back`.** A single awk invocation strips every file
(each lands in `<file>.strip`), and the result goes back with HI.09's `cat`,
not `mv`, for the same exec-bit reason as HI.35.

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
`git describe --dirty`. An unescaped `$`, quote or backtick in any of them
breaks the bootloader's parse and lets the target run a command substitution
it should not. `_hi_ssh_sh` quotes its `sh -c` word through the same function,
so the transports cannot drift into two dialects, and `_hi_env_each` takes
values already quoted (`%s=%s`, never `%s="%s"`), so quoting is one decision
rather than one per transport.

## HI.41 overlay stream

The user's config overlay (`$_HI_OVERLAY_FILES` in `hi.sh`) lives outside the
tree, so it travels as a second, much smaller archive rather than inside the
payload. It lands in a `config/` of its own beside `settings/`, with
`$_HI_CONFIG_DIR` pointing there, never over `settings/`: `settings/aliases.sh`
sources `$_HI_CONFIG_DIR/aliases.sh` last, so one directory would make it
source itself forever. It is omitted when there is nothing to send.

The prompt tools' `starship.toml` / `oh-my-posh.json`, eza's `theme.yml` and
bat's `bat.conf` (`$BAT_CONFIG_PATH`) ride it so a tool's config on every target is the one configured at home;
`common/paths.sh` points each tool's own variable (`$STARSHIP_CONFIG`,
`$POSH_THEME`, `$EZA_CONFIG_DIR` - the overlay directory itself, since eza
fixes the file name) at the overlay on a target only (HI.32).

The editor rcs (`vim.rc`, `nano.rc`, `emacs.el`, `helix.toml`, `kak.rc`) ride
it for the same reason `colors` and `packages` do: the tree copy is a default,
and `common/paths.sh` points each `$_HI_*RC` at the overlay's when there is one. Left out of the stream, that
guard could only fire on the client — an editor override working locally and
silently reverting on every target, the asymmetry `paths_test.sh`'s
guard/roster pin catches one layer up.

## HI.43 container target grammar

A container target may name what to run _in_ as well as where: `pod/container`
for kube, `alloc/task` for nomad — one spelling for both, since a task and a
container are the same idea here, and a suffix rather than a flag so completion
can offer the pairs (`_hi_outer` / `_hi_inner` in `hi.sh`). Only those two
split: a container name on any of the docker-compatible family (HI.51) is
taken whole, having no inner unit and `/` being legal in it.

kube adds `[[context:]namespace:]pod[/container]` (`_hi_kube_split`). `:` is
the separator because no ssh host, container name or allocation id may carry
one, so a prefixed name can only mean a pod; no prefix means whatever kubectl
points at, and `common/targets.sh`'s `list_kube` emits the same spelling for
pods outside the current namespace. A multi-container pod resolves on the pod
half; kubectl checks the container half when the session runs and fails loudly
on a missing name — better than declining silently and falling through to ssh.

docker and podman also answer to a compose service name
(`_hi_compose_container`) when exactly one running container carries that
label. Ambiguous (two
projects, same service) and absent both fail rather than guess — a wrong guess
lands a session in someone else's container — and the lookup runs only when
the literal name does not resolve, so the common case pays one inspect.

## HI.44 wire size token

The connect line prints the size of the script the session sent, but the
script cannot know its own size while being assembled. `_say_hi` (`hi.sh`)
builds it with `$_HI_SIZE_TOKEN` (`@@SIZE@@`, wider than any figure) standing
in, measures `${#script}`, and substitutes the human figure back — honest to a
few bytes, since the streams inside are already armored and the script goes
over the wire as it stands. `_hi_wire_bytes` — what `hi --doctor` and the
README badge quote — assembles the same script through the same
`_preamble`/`_middle`/`_suffix` rather than summing the armored streams:
summing skips the boilerplate around them and reads ~6KB low, and a badge has
to show the number the user sees. No overlay is counted, since which files
ride is a question about a target.

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
`settings/aliases.sh` defines a `bash` and a `fish` wrapper off
`$_HI_SESSION_RC`. Both bodies begin with `command`: fish's `alias` builds a
function of that name, and without it `fish` would call itself forever.

The wrappers cannot cover a bash or fish shell nothing typed — a `tmux` pane
spawning a login shell, an editor's shell-out — which comes up as the host's
own. hi writes nothing into a target's login files
([SUPPORT.md](SUPPORT.md#what-would-change-an-answer) has the reasoning).

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
`common/paths.sh` alongside sh, zsh and bash, and the one assignment all four
accept is `export NAME=value`, so every name it sets arrives exported —
nearly forty. Each interactive rc (`bash.sh`, `zsh.zsh`, `config.fish`)
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

`$_HI_HEADER_ORDER` (HI's header, `common/header.sh`) lets any subset of
seventeen words print in any order, each carrying its own hardcoded color.
Nothing about the order guarantees two adjacent cells differ in color —
`jobs` and `pods` are adjacent in the shipped default order and wear the
same hue (`BRCYAN`/`CYAN`, differing only in the bold bit), and any
user-supplied order can create the same collision between any two of
the sixteen `_hi_header_word_alt` carries an alternate for - `check` is the
seventeenth word, and resets the hue tracking explicitly instead (below).

`_hi_collect_header_word` fixes this in one pass, no lookahead or backtrack:
it tracks the previous cell's hue in `$_HI_PREV_HUE`, and when a word's own
color would repeat it, swaps in that word's hand-picked alternate
(`_hi_header_word_alt`) instead. "Hue" ignores the bold bit — `\e[0;36m` and
`\e[1;36m` both read as cyan (`_hi_cell_hue`), so a bold/non-bold pair still
counts as a collision; `\e[0;34m` (blue) does not collide with either.

The one property that makes a single pass sufficient, with no ring walk and
no retry loop: **every word's alternate has a different hue than that same
word's own primary**, so a substituted cell can never itself collide with
what came before it. This is not something the shell enforces - it is a
property of the hand-written `_hi_header_word_alt` table, and
`tests/common/header_test.sh`'s `test_header_word_alt_differs_from_its_own_primary`
checks it mechanically rather than trusting the table by eye.

An empty cell (`containers`/`jobs`/`pods` when that backend never answered)
leaves `$_HI_PREV_HUE` untouched rather than resetting it to empty —
resetting it would let the _next_ word compare against nothing and skip a
real collision two cells later. `check` resets it explicitly: the packages
block has its own palette (`$_HI_YES`/`$_HI_NO`), unrelated to header cell
hues.

## HI.50 truecolor color schemes

`_HI_COLOR_SCHEME` (`common/core.sh`) remaps what the twenty-four palette
names render as; it never adds a name. `_hi_hash_color`, the
`settings/colors` pins, `_hi_color_escape` and `hi --preview colors` all keep
the same vocabulary, so a scheme is invisible to everything that reasons
about a color by name - only the bytes a name turns into change. The names
are the terminal's twelve plus twelve extras (orange, pink, teal, ...) that
no 16-color code spells: `_HI_COLOR_FALLBACK` gives every slot its
`<bold><hue>` pair - an extra's is the nearest of the sixteen - and with no
scheme the first twelve render as that pair alone while the extras carry a
built-in hex, so a truecolor terminal shows an orange host as orange without
anyone choosing a scheme. `_hi_color_base` is the pair as a name, for zsh's
`%F{}` and fish's `set_color`, which know the sixteen and nothing else.

A `settings/colors` row may also carry its own hex, in an optional fourth
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
24, 48 or 0: exactly that many six-digit hex words one space apart is a
scheme, anything else — a leftover name, a typo, nothing — renders as the
default. Forty-eight words are two banks of the
twenty-four names. `_hi_scheme_hex` takes slot indexes 0-47 and folds 24-47
onto 0-23 for every table but a 48-word list, and `_hi_color_escape_at`
reads the 16-color half off `_HI_COLOR_FALLBACK` at the index mod 24, so a
second-bank escape wears the same `\e[<bold>;3<n>` as its name, so every hue
and width reader above still works. Only `common/header.sh`'s packages check reads the
second bank: `_hi_packages_palette` rebuilds `_HI_YES`/`_HI_NO` from it after
resolving the ramp, per render rather than at source time, because the
ramps are the palette variables and those are the first bank by contract.
The two `_hi_scheme_words` calls a render costs are offset arithmetic, no
fork. `scripts/lib.sh`'s `_hi_scheme_ok` and `_hi_scheme_label` are the
validator and the preview/doctor label; core.sh only ever renders.

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

docker, podman, nerdctl and finch take the same `ps --format`, `exec -i[t]`
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

The three files spell those words themselves - `hi.sh` builds a bash array,
`common/targets.sh` is standalone POSIX that no bash file can source, and
`common/header.sh` reads neither - so `tests/lint/drift_test.sh` pins the
three spellings to each other.

Two members can front one daemon — `podman-docker` ships a `docker` that
execs podman, nerdctl and finch share a containerd — and would list every
container twice. `targets.sh`'s `dedupe_family` keeps the first lane's row in
roster order (so a shim host sees `docker`), and the header unions the lane
files, since the IDs are the daemon's. The compose-service alias is
docker's and podman's: both render the `.Label` template and take the matching
`label=` filter, while nerdctl and finch are unverified, and a template one
rejects would empty its lane.

`--use <backend>` forces any arm by name, ssh and every roster row included,
and is the only way to: there is no per-backend flag, so a member added to
the family is reachable with no second spelling. Names stay plain identifiers
(`[A-Za-z0-9_]`): `hi.sh`'s per-member predicate is `eval`-defined.

## HI.52 client multiplexer wrap

`hi --mux <target>` re-executes the connect inside a local
multiplexer session named `hi-<target>` and never returns; a second `hi --mux`
to the same target joins the running session. It is the client-side answer to
a dropped link - there is no target-side multiplexer, because a disposable
tree cannot outlive its own session, and this leaves the target untouched. `_hi_mux_tool` picks the multiplexer: the first of tmux, zellij,
screen on `PATH`, each driven in its own idiom:

- **tmux**: `new-session -A -s <name> <one string>`; the `-A` is the reattach.
- **screen**: `-D -R -S <name> sh -c <one string>`; `-D -R` reattaches a
  session of that name (detaching it elsewhere first) or creates it running
  the command.
- **zellij**: takes a session's command only from a layout file, never from
  argv, so `_hi_mux_wrap` writes `hi.mux.<name>.kdl` under hi's runtime
  directory (one per target, rewritten each connect: `pane command="env"
close_on_exit=true { args ... }`, each word a KDL string via
  `_hi_kdl_quote`) and starts `--session <name> --new-session-with-layout`;
  a name already in `list-sessions --short` is `attach`ed instead.

Five rules in `_hi_mux_wrap`:

- **Where it sits.** After `_hi_parse`, before `_hi_select_arm`, so one
  insertion point covers every arm (ssh, `--plain`, docker, nomad, kube). The
  inner argv is rebuilt from the parsed state (`--use`, `--plain`, the ssh
  options, `$DOMAIN`, the command), not replayed from `"$@"`, so the target it
  settled on rides along.
- **The guard.** The inner command is `env _HI_MUX_INNER=1 <launcher> ...`;
  the wrap returns at once when that is set. The inner hi re-reads the flag it
  was handed, so without the guard an `alias hi='hi --mux'` - which is how you
  make the wrap your default, there being no setting for it - would nest
  forever. It also stands down, un-wrapped, without a terminal on stdin
  (nothing to attach) or without a multiplexer to use.
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
also closes the OSC 133 prompt-mark pair with a `D` carrying the status (unless
`_HI_DISABLE_MARKS=1`): hi's remote prompt emits `C` before every command,
`exit` included, and `load.sh` sends the closing `D` on a clean exit - a drop
never reaches that line, and Konsole, left "inside a command", sends ↑ as ←
until a `D` arrives. `stty sane` last, for the container arms whose exec does
not always restore termios on a lost link. Every byte is a no-op on a terminal
already in its normal state, which is why the caller need not know which
mode applied - but the alternate-screen exit only once it is wrapped in a
`ESC 7`/`ESC 8` (DECSC/DECRC) pair. Konsole answers `CSI ?1049 l` with an
unconditional cursor restore, and on a terminal still on its normal screen
that slot holds what nothing ever saved, i.e. home: the failed connect's own
message then landed at the top of the screen and painted over the session
still on it. Saving first makes that restore a return to where the cursor
already is; a terminal genuinely in the alternate screen saves to *that*
screen's slot, so `CSI ?1049 l` still restores the pre-alt cursor and the
DECRC only repeats it. Never on exit 0 (the session closed itself down),
never on a pipe (`hi host cmd | ...` gets the command's output and nothing
else).

## HI.54 who draws the environment prefix

`common/env_prompt.sh` names every active environment manager as the prompt's
leading `(mise|direnv:proj|myproj)`. The awkward part is not the detection -
every tool exports a variable, so a draw is parameter expansion and nothing
else - it is that two of those tools draw a prefix of their own, and whether
that prefix survives is a property of the *shell*, not of the tool.

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

fish carries a third copy of the source list, for the reason config.fish
carries a second copy of the git glyphs: it cannot call the bash function, and
a `bash -c` on every prompt draw is exactly the fork this prompt refuses
everywhere else. `tests/hi/prompt_test.sh` pins the two lists together.

mise is the one row that is more than parameter expansion. `$MISE_SHELL` is
set wherever mise is activated, and a `~/.tool-versions` covers every
directory under it, so `(mise)` is named only where a config file between the
directory and `~` overrides the global one: a builtins-only walk up from
`$PWD`, memoized on it (HI.16). `_HI_ENV_ORDER` still drops the word outright.
