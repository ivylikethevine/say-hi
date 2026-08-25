# Glossary of deliberate oddities

say-hi's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `settings/aliases.sh` and
`settings.sh` natively). Targets also split between **GNU and BSD userlands**.
Each entry below is a construct that looks odd until you know which master it
serves.

Every entry carries a stable `HI.NN` code, and a file references it with a
`# GLOSSARY: HI.NN` tag instead of re-explaining. The tag is _mandatory_ in
`common/`, `settings/`, `load.sh` and `hi.sh` — the files a reader meets first.
Codes are what tags point at, so an entry can be retitled without touching a
tagged file; codes are never reused once retired. A tag is one code, or two
joined with ` + `, with optional prose after it. `tests/lint/shellcheck_test.sh`
fails the build if a tag names a code this file doesn't define, or if an entry
here is referenced by nothing. This file never ships (`docs/` is not in
`$_HI_PAYLOAD`).

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
- [HI.24 graft crash guard](#hi24-graft-crash-guard)
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
an unset variable is fatal under bash's `set -u`. The toggles must therefore
always exist: `common/core.sh` defaults the `_HI_TOGGLES` list (defaulted,
never assigned, so settings.sh and paths.sh's gate still win),
`common/config.fish` mirrors it with `set -q X; or set -gx X 0`, and `hi.sh`'s
`_hi_fallback_rc` emits `export X=0` lines from the same list for bash-less
targets.

## HI.08 sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back — see HI.09 for why with `cat`.

## HI.09 cat-over-mv

Writing a tempfile back over an existing file goes through the existing inode:
`cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in `common/core.sh`;
`rewrite` in `packaging/stamp.sh` is the boundary-forced copy). `mv` would
transplant mktemp's 0600 mode onto the target and sever any hardlink/ACL — a
dotfile manager's hardlinked `~/.bashrc` must see the new content, and `hi.sh`
must stay executable in the payload. Non-atomicity is acceptable for
single-user rc files; `common/targets.sh`'s cache swap keeps `mv` deliberately,
for atomicity over a file it owns.

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

A second, **narrower** chain over the same family is how flags reach only the
tier that parses them: `$_HI_BAT_REAL` is `bat || batcat` where
`$_HI_BATCAT_BIN` is `bat || batcat || ccat || cat`, so bat-syntax options
attach behind `[ -n "$_HI_BAT_REAL" ] && alias ... || true` and leave ccat and
coreutils `cat` the bare binary.

## HI.14 _hi_on_exit

zsh has `TRAPEXIT` rather than bash-style `trap ... EXIT`. `_hi_on_exit`
(`common/core.sh`) picks per shell, and is the only way cleanup traps are
registered in shared code.

## HI.15 strict-mode bracketing

Files that run inside an interactive shell (`common/core.sh`, `hi.sh`,
`common/bash.sh`, `common/git_prompt.sh`, ...) set `set -euo pipefail` at the
top _and disable it at the end of their own code_: left on, any later non-zero
status or unset variable kills the user's session. The bootloader and fallback
rc do the same on targets — forgetting it there once broke
`hi <target> <command>` outright.

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

Every command hi sends meets the target's _login_ shell first, and that shell
may be fish, which parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is the transport's job, not per-site care
(the install probe answered "nothing installed" on every fish-login host until
it was wrapped). Quoting is single-quote-and-escape rather than `printf %q`,
which escapes every space with a backslash — readable in neither the code nor
an `ssh -v` log, and one more thing for fish to differ about.

## HI.19 stdin transport

The bootloader travels over **stdin of the first of two ssh calls multiplexed
on one connection** (still one authentication), never as an argument: Linux
caps a _single_ argv entry at 128KB (`MAX_ARG_STRLEN`) however large `ARG_MAX`
is, and the payload had grown within a few KB of it. It has to be two calls
because the second one's stdin belongs to the interactive session. The script
goes as plain text and is `cat` into place; only the three streams _inside_ it
are armored, because only they are binary — armoring the whole script (which
the argv era needed) spent a third of every session's bytes re-encoding ASCII.
The write doubles as the probe: a target where `sh -c` won't run has no POSIX
shell (stock Windows OpenSSH), and one without `base64` cannot unpack; either
way the session falls through to the PowerShell branch rather than
half-landing.

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

## HI.24 graft crash guard

`clean_all` cannot run after a hard kill, so every rc graft is wrapped in a
tree-exists guard that makes the block vanish on its own when the tree it
points at is gone — otherwise every shell the user opens from then on errors
at its first source line, and in a container sharing `$HOME` (distrobox) that
is the _host's_ rc file. The guard re-resolves at shell start and asks for
`$_HI_HOME`, stopping when there is none rather than falling back to `$HOME`
(HI.33).

## HI.25 session-shell ranking

`$_HI_SHELL_PREFERENCE` is an ordered list of names hi styles, plus the token
`login` for the user's login shell; the first entry installed wins, and bash is
the floor because `load.sh` only runs where bash exists. Its default tail is
not a literal: `_hi_session_shell` walks `common/core.sh`'s `$_HI_SHELL_TREE`
(`fish zsh bash dash ash sh`) and drops the tiers that need bash to be
_missing_, leaving `fish > zsh > bash`; `hi.sh`'s `$_HI_SHELL_LADDER` is the
same tree with bash removed. One list, two consumers.

`login` leads for a reason found by the framework matrix: a ranking that leads
with fish hands it to anyone whose box has it, so a user whose login shell is
zsh-with-oh-my-zsh never sees their own setup.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi` and a space — the most
latency-sensitive path in say-hi and the slowest (four of five backends are a
subprocess each). Two knobs keep it honest.

`_HI_PROBE_TIMEOUT` is the seconds a backend CLI gets (default 2, needs GNU
`timeout`; shared with `common/core.sh`'s `_hi_probe`). It bounds the **whole
sweep**: the backends are started together and read back in roster order, so
four wedged daemons cost one ceiling rather than four. A host with no writable
scratch directory falls back to the in-turn sweep, which is slow, not wrong.

`_HI_TARGETS_TTL` is the seconds a result is reused (default 5, 0 disables) —
a just-started container may not appear until it expires. **Nothing
invalidates it**; only the clock. Two windows stack and are offset: the file
cache in `targets.sh` stamps when it was written, the in-shell memo in
`common/bash.sh`/`common/zsh.zsh` stamps when that shell last read the file,
so worst-case staleness is close to **twice** the TTL. Only
`_HI_TARGETS_TTL=0` turns both off.

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
name. shellcheck reads that as dead code (SC2329), which is why every suite
carries a file-level `# shellcheck disable=SC2329`.

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

`$_HI_HOME` is the directory _containing_ `say-hi`, and every file that needs
the tree derives it from its own path rather than defaulting to `$HOME`. The
default was a guess that was right for a standard install and wrong everywhere
else — and when wrong it did not fail, it silently read _another tree_ (both
platform e2e jobs spent their first real run sourcing a tree under
`/Users/runner` that was never there). Each file asks only when `$_HI_HOME` is
unset, so an outer export still wins and costs no fork.

`common/core.sh` owns the answer, and everything that merely _needs_ the tree
reaches core.sh through its own path. The files that derive are the ones with
nothing above them to ask through:

| where | how |
| --- | --- |
| `common/core.sh` | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`. Answers for every file sourced through it |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh` | the same, behind a `readlink` walk - `$_HI_LINK` is `/usr/bin/hi`, and the unresolved path answers `/usr`. Three copies, because each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh` | `${BASH_SOURCE[0]}` - entry points that _export_ for children |
| `scripts/doctor.sh`, `scripts/color_preview.sh`, `scripts/packages_preview.sh`, `tests/test_lib.sh` | `${BASH_SOURCE[0]}`, then `$_HI_HOME` if set - the standalone-entry form below |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; bash cannot parse `%x`, so core.sh's arm is `eval`'d |
| fish (`common/config.fish`) | `sh -c 'cd -P "$1/../.." && pwd'` - a builtin-only substitution would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical |
| `common/bash.sh` | `$_HI_HOME`, not its own path - the one file that cannot self-locate, because `load.sh` grafts its _text_ into someone else's rc (HI.24), where `$BASH_SOURCE` is that rc |

**The standalone-entry form, and why `$_HI_HOME` wins in it.** A script invoked
on its own derives from `${BASH_SOURCE[0]}` only as the fallback:

```sh
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
```

When `$_HI_HOME` is set, _everything_ has to come from there, core.sh included:
reaching core.sh through the script's own path while `$_HI_ROOT` came from
`$_HI_HOME` runs two trees in one process, silently.

Two places keep a fallback, and both say so out loud. `hi.sh` prints
`set _HI_HOME to the directory that holds it` and exits when the derived path
holds no tree. And on a _target_ — the one machine with no checkout to derive
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
   rc line, so a brew-installed target was invisible to tiers 1 and 2 and got
   the payload copied over a tree already sitting there. Best-effort by
   construction, strictly a fallback, two builtins per candidate and no forks.

Each candidate is tried as `<home>/say-hi`. The probe's `sed` uses separate
`-e` expressions rather than `\(a\|b\)` (BRE alternation is a GNU extension),
and a second `sed` unwraps the value, because `config_shell` writes the path
quoted _and_ pads a `# added by hi during install` marker onto every line it
owns. Its expressions are **ordered**: the comment strip runs first, addressed
to lines that do _not_ begin with a quote (`/^"/!`), and the unquoting second —
the other order would strip from a `#` inside the quotes. `IFS` is a newline
for the candidate loop, so an install directory with a space is one candidate.

`tests/lint/shellcheck_test.sh`'s `lint_home_default` greps the tree for the
retired spellings — over `.md` too, since docs teaching the old rule are what a
packager reads.

## HI.34 test suite preamble

Every suite under `tests/` opens with the same four lines, four separate
mechanisms rather than boilerplate:

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

`test_lib.sh` sources `common/core.sh` itself. A suite sources the harness and
never core.sh: doing both runs core.sh's initialisation twice, the second time
after the harness has moved `$XDG_CONFIG_HOME` into the scratch dir. The
`# shellcheck source=` line is a directive the linter follows, and
`# shellcheck disable=SC2329` is HI.30. Both stay verbatim above their
statement.

## HI.35 payload comment strip

Every `*.sh`, `*.zsh` and `*.fish` file is comment-stripped on its way into the
payload (`_hi_strip_awk` and `_hi_payload_tar` in `hi.sh`) — about 40% of the
shipped shell is comment. `bench_payload_readme_badge` keeps README's badge
honest against the result.

Two rules keep it safe. **Full-line comments only**: an inline `#` cannot be
told from `${x#y}`, `$#` or a `#` in a string without a real parser. **Never
inside a heredoc**: those bodies are data the target reads, and one of them is
`hi --help`. The comment test runs _before_ the heredoc-open test, on purpose: a
comment mentioning `<<WORD` would otherwise open a heredoc that never closes
and silently stop stripping the rest of the file.

`_HI_KEEP_COMMENTS=1` ships the tree verbatim. `tests/hi/payload_test.sh` pins
the rest: no full-line comment survives outside `hi.sh`'s heredocs, every code
line survives byte for byte, the result still parses, and `hi.sh` keeps its
exec bit — which is why the write-back is HI.09's `cat`, the target's probe
testing `[ -x .../hi.sh ]` before it trusts a tree.

## HI.36 overlay toggle source

`_hi_overlay_toggle` (`hi.sh`, over `common/core.sh`'s `_hi_setting_get`)
reads `$_HI_CONFIG_DIR/settings.sh` as a _file_ rather than off the exported
environment, and that distinction is the whole point: settings.sh rides along
and is sourced on the target, so it is the value that will apply there. The
client's exported copy means something else — `_HI_DISABLE_LOCAL=1` is "leave
my machine alone but style the hosts I visit", and trimming the payload on it
would stop shipping files to targets that never disabled them.
`_hi_setting_get` is the one reader of the grammar `install.sh`'s
`config_shell` writes: quoted or bare values, the install marker padded after
a bare one, last assignment wins.

## HI.37 zsh pattern-in-variable

`_hi_ssh_pattern_hit` (`common/core.sh`) matches a name against `Host`/`Match
host` glob patterns read out of `~/.ssh/config` — `*` and `?` mean the same in
ssh's syntax as in a `case` pattern, so only a way to try each pattern that
survives both bash and zsh is needed.

Two zsh divergences stack. First, zsh does not word-split an unquoted
variable, so `for pat in $patterns` never iterates; `setopt localoptions
shwordsplit` fixes that, scoped to the function. Second — same symptom, a
`case` that never matches — zsh does not treat `*` in a _variable's_ value as
an active wildcard unless `GLOB_SUBST` is set. The tempting `setopt globsubst`
breaks the first fix: splitting `$patterns` then also glob-expands each token
against real files, and a pattern matching nothing on disk errors the loop out.
`${~pat}` is the escape: a per-expansion toggle asking zsh to treat that one
substitution as a pattern. Bash does not understand it, so the function
branches on `$ZSH_VERSION`.

A `!`-prefixed token (ssh's per-pattern negation) is not honored as exclusion —
it survives as a literal pattern nothing is ever named, so it is inert rather
than wrong; the cost is a wrongly-colored excluded host, which is cosmetic.
