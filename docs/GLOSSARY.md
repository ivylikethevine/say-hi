# Glossary of deliberate oddities

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
- [HI.36 overlay toggle source](#hi36-overlay-toggle-source)
- [HI.37 zsh pattern-in-variable](#hi37-zsh-pattern-in-variable)
- [HI.38 split tar and gzip](#hi38-split-tar-and-gzip)
- [HI.39 payload staging](#hi39-payload-staging)
- [HI.40 hand-rolled sh quoting](#hi40-hand-rolled-sh-quoting)
- [HI.41 overlay stream](#hi41-overlay-stream)
- [HI.42 recent targets](#hi42-recent-targets)
- [HI.43 container target grammar](#hi43-container-target-grammar)
- [HI.44 wire size token](#hi44-wire-size-token)
- [HI.46 session rc directory](#hi46-session-rc-directory)
- [HI.47 what a child inherits](#hi47-what-a-child-inherits)

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
(`_hi_group_index` in `scripts/color_preview.sh`), or `"<key>=<value>"`
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

## HI.06 source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`scripts/install.sh`, `packaging/bump.sh`, `packaging/mkpkg.sh`,
`scripts/color_preview.sh` and `scripts/packages_preview.sh` all carry it.

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
tier that parses them: `$_HI_BAT_REAL` is `bat || batcat` where
`$_HI_BATCAT_BIN` is `bat || batcat || ccat || cat`, so bat-syntax options
attach behind `[ -n "$_HI_BAT_REAL" ] && alias ... || true` and ccat and
coreutils `cat` get the bare binary.

Every such chain sits **above** the user's overlay `aliases.sh` source in
`settings/aliases.sh`, though the overlay is otherwise sourced first: in zsh
and dash (not bash, not fish) `command -v name` returns an _alias's_
definition once one exists, so an overlay `alias cat=...` sourced first would
leave `_HI_BATCAT_BIN` holding the alias body instead of a binary path.
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
`xterm-256color`. `_HI_TERM_FALLBACK=0` keeps the original.

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

`$_HI_SHELL_PREFERENCE` is an ordered list of names hi styles, plus the token
`login` for the user's login shell; the first entry installed wins, and bash is
the floor because `load.sh` only runs where bash exists. Its default tail is
not a literal: `_hi_session_shell` walks `common/core.sh`'s `$_HI_SHELL_TREE`
(`fish zsh bash dash ash sh`) and drops the tiers that need bash to be
_missing_, leaving `fish > zsh > bash`; `hi.sh`'s `$_HI_SHELL_LADDER` is the
same tree with bash removed. One list, two consumers.

`login` leads because a ranking that leads with fish hands it to anyone whose
box has it, so a user whose login shell is zsh-with-oh-my-zsh would never see
their own setup.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi` and a space — say-hi's most
latency-sensitive path and its slowest (four of five backends are a subprocess
each). Two knobs keep it honest.

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
immediately**, and the replacing sweep runs behind it with every descriptor on
`/dev/null` — no TAB inside a working session waits on a daemon, and the next
one is current. A lock directory beside the cache allows one refresh at a
time; a lock older than any sweep runs is a dead refresher's and is taken
over. After ten idle minutes the sweep is waited on again, like a first TAB:
one pause rather than a page of names that no longer exist.
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

`_HI_PROMPT=starship` hands the prompt to [starship](https://starship.rs) when
the target has it, keeping hi's header and aliases. `common/core.sh`'s
`_hi_wants_starship` is the single predicate (the setting _and_ the binary);
`common/bash.sh` and `common/zsh.zsh` each `eval` their own `starship init`
behind it. Absent starship, the setting is ignored silently.

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

| where                                                                                               | how                                                                                                                                                                      |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `common/core.sh`                                                                                    | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`; answers for every file sourced through it                                                                                |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh`                                                   | the same behind a `readlink` walk - `$_HI_LINK` is `/usr/bin/hi`, and unresolved it answers `/usr`. Three copies: each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh`                                                                   | `${BASH_SOURCE[0]}` - entry points that _export_ for children                                                                                                            |
| `scripts/doctor.sh`, `scripts/color_preview.sh`, `scripts/packages_preview.sh`, `tests/test_lib.sh` | `${BASH_SOURCE[0]}`, then `$_HI_HOME` if set - the standalone-entry form below                                                                                           |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it)                                     | `${(%):-%x}` with zsh's `:A:h` modifiers; bash cannot parse `%x`, so core.sh's arm is `eval`'d                                                                           |
| fish (`common/config.fish`)                                                                         | `sh -c 'cd -P "$1/../.." && pwd'` - a builtin-only substitution would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical      |
| `common/bash.sh`                                                                                    | `$_HI_HOME` first, its own path as the fallback - `hi.sh`'s preamble and `install.sh`'s rc line both set it before this file is sourced                                  |

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

Two places keep a fallback, and both say so out loud. `hi.sh` prints
`set _HI_HOME to the directory that holds it` and exits when the derived path
holds no tree. On a _target_ — the one machine with no checkout to derive
from — `_hi_remote_root`'s probe asks in order:

1. `export _HI_HOME=` / `set -gx _HI_HOME` in `~/.bashrc`, `~/.zshrc`,
   `~/.config/fish/config.fish`, and `/etc/profile.d/say-hi.sh` for a packaged
   install — read as _files_, since the probe runs under `sh -c` over ssh,
   which sources none of them.
2. `$HOME`.
3. Where an install lands when nothing declared it: `~/.local/share`,
   `/usr/local/share`, `/opt`, `/usr/share`, and Homebrew's four default keg
   prefixes (`~/.linuxbrew`, `/home/linuxbrew/.linuxbrew`, `/opt/homebrew`,
   `/usr/local`, each under `opt/say-hi/libexec`). Homebrew's formula writes no
   rc line, so without this tier a brew-installed target gets the payload
   copied over a tree already there. Best-effort, strictly a fallback, two
   builtins per candidate and no forks.

Each candidate is tried as `<home>/say-hi`. The probe's `sed`:

- uses separate `-e` expressions, not `\(a\|b\)` — BRE alternation is a GNU
  extension;
- is followed by a second `sed` that unwraps the value, because
  `config_shell` writes the path quoted _and_ pads a
  `# added by hi during install` marker onto every line it owns;
- is **ordered**: the comment strip first, addressed to lines that do _not_
  begin with a quote (`/^"/!`), the unquoting second — the other order would
  strip from a `#` inside the quotes;
- loops over candidates with `IFS` set to a newline, so an install directory
  with a space is one candidate.

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
`vim.rc`/`nano.rc` data files, whose prose headers document the *installed*
copies — is comment-stripped on its way into the payload (`_hi_strip_awk` and
`_hi_payload_tar` in `hi.sh`); about 40% of the shipped shell is comment.
vim.rc's comment character is `"`, its own rule in the stripper.
`bench_payload_readme_badge` checks README's badge against the result.

Two rules keep it safe. **Full-line comments only**: an inline `#` cannot be
told from `${x#y}`, `$#` or a `#` in a string without a real parser. **Never
inside a heredoc**: those bodies are data the target reads, one of them
`hi --help`. The comment test runs _before_ the heredoc-open test: a comment
mentioning `<<WORD` would otherwise open a heredoc that never closes and
silently stop stripping the rest of the file.

`_HI_KEEP_COMMENTS=1` ships the tree verbatim. `tests/hi/payload_test.sh` pins
the rest: no full-line comment survives outside `hi.sh`'s heredocs, every code
line survives byte for byte, the result still parses, and `hi.sh` keeps its
exec bit — hence HI.09's `cat` for the write-back; the target's probe tests
`[ -x .../hi.sh ]` before it trusts a tree.

## HI.36 overlay toggle source

`_hi_overlay_toggle` (`hi.sh`, over `common/core.sh`'s `_hi_setting_get`)
reads `$_HI_CONFIG_DIR/settings.sh` as a _file_, not off the exported
environment: settings.sh rides along and is sourced on the target, so the file
holds the value that will apply there. The client's exported copy means
something else — `_HI_DISABLE_LOCAL=1` is "leave my machine alone but style
the hosts I visit", and trimming the payload on it would stop shipping files
to targets that never disabled them. `_hi_setting_get` sources the file in a
subshell and reads one name back, so it sees what a real `.` would — quoted or
bare values, the install marker after a bare one, last assignment wins — and
nothing in the subshell reaches the caller.

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

`_hi_payload_tar` (`hi.sh`) ships the tree minus whatever the overlay has
switched off, comment-stripped (HI.35).

**Trimmed by toggle, on the client.** `$_HI_PAYLOAD` is whole directories, so
without `_HI_TRIM_TABLE` a session ships files it has been told not to use;
the client reads `settings.sh` (HI.36) before building the tar, so this costs
no probe. One table feeds both halves — tree files and the overlay files a
toggle takes off — because off has to take _both_ off or a switched-off toggle
still ships a file. `settings/aliases.sh` is never trimmed: it carries the
whole alias set, and every consumer of `common/osc52.sh` and
`common/notify.sh` tests the file exists first, so trimming the emitters is
safe.

**Staged, in a subshell, under a trap.** The strip rewrites files and the tree
is not hi's to touch, so a `tar | tar` pair copies it to a `mktemp -d` stage
(same exclusion list; `-h` resolves symlinks so the stage holds real files).
The subshell lets cleanup be an `EXIT` trap rather than an `rm` on each way
out — a ^C during a slow build would otherwise leave the stage in the client's
tmp. `INT` and `TERM` are trapped explicitly to `exit`, since a signal that
kills the subshell outright never reaches the `EXIT` trap; set in the
function's own shell the trap would replace the one `_hi` installed for its
error log.

**One awk, then `_hi_write_back`.** A single awk invocation strips every file
(each lands in `<file>.strip`), and the result goes back with HI.09's `cat`,
not `mv`: the strip file's mode would otherwise land on the target, and
`hi.sh` has to stay executable — the install probe tests `[ -x .../hi.sh ]`.

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

`vim.rc` and `nano.rc` ride it for the same reason `colors` and `packages` do:
the tree copy is a default, and `common/paths.sh` points `$_HI_VIMRC` /
`$_HI_NANORC` at the overlay's when there is one. Left out of the stream, that
guard could only fire on the client — an editor override working locally and
silently reverting on every target, the asymmetry `paths_test.sh`'s
guard/roster pin catches one layer up.

## HI.42 recent targets

`_hi_record_recent` (`hi.sh`) appends one `<epoch>\t<target>` line to the
recent-targets file after a session that ended cleanly; `common/targets.sh`
ranks completion by it (frecency: most and most recently connected first).
Client-side only: a session's own `hi` (a relay hop) writes nothing, so
nothing about a client's habits lands on a target, and the file is not in
`$_HI_PAYLOAD`. `_HI_RECENT=0` turns off both halves. Every write may fail
quietly — a read-only `$HOME` is no reason to fail a session that already
ended well. Past 500 lines the file is trimmed in place to the newest 300, so
it stays a few KB and the rank cost flat.

## HI.43 container target grammar

A container target may name what to run _in_ as well as where: `pod/container`
for kube, `alloc/task` for nomad — one spelling for both, since a task and a
container are the same idea here, and a suffix rather than a flag so completion
can offer the pairs (`_hi_outer` / `_hi_inner` in `hi.sh`). Only those two
split: a docker or podman name is taken whole, having no inner unit and `/`
being legal in it.

kube adds `[[context:]namespace:]pod[/container]` (`_hi_kube_split`). `:` is
the separator because no ssh host, container name or allocation id may carry
one, so a prefixed name can only mean a pod; no prefix means whatever kubectl
points at, and `common/targets.sh`'s `list_kube` emits the same spelling for
pods outside the current namespace. A multi-container pod resolves on the pod
half; kubectl checks the container half when the session runs and fails loudly
on a missing name — better than declining silently and falling through to ssh.

docker alone also answers to a compose service name (`_hi_compose_container`)
when exactly one running container carries that label. Ambiguous (two
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
([SUPPORT.md](SUPPORT.md#features-that-were-removed) has the reasoning).

## HI.47 what a child inherits

`env | grep ^_HI_` in a process started from an interactive hi shell shows
core.sh's `_HI_CHILD_ENV` roster and nothing else with the prefix. The roster
is eight names:

- `$_HI_HOME` and `$_HI_CONFIG_DIR` — the overlay on a target is wherever
  `hi.sh` put it, and cannot be re-derived;
- `$_HI_REMOTE_SESSION`;
- `$_HI_SESSION_RC` — HI.46's wrappers are re-defined in every nested shell;
- `_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT`, `_HI_RECENT`, `_HI_RECENT_FILE` —
  the knobs `sh targets.sh` reads straight off its environment from a
  completion.

It works by taking the attribute off, not by never setting it. fish parses
`common/paths.sh` alongside sh, zsh and bash, and the one assignment all four
accept is `export NAME=value`, so every name it sets arrives exported —
sixty-odd. Each interactive rc (`bash.sh`, `zsh.zsh`, `config.fish`)
un-exports the lot as the last thing in its required block: `_hi_unexport` in
core.sh (bash `export -n`, zsh `typeset -g +x` — a bare `typeset` inside a
function declares a local), and a `set -gu NAME $NAME` loop in config.fish.
The values stay as shell variables: `now` expands `$_HI_HUMAN_SHORT_DATE` when
typed, the prompt reads the colour memos every render, and a `$( )` is a fork
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
