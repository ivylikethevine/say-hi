# Glossary of deliberate oddities

say-hi's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `settings/aliases.sh` and
`settings.sh` natively). On top of that, targets split between **GNU and BSD
userlands**. Each entry below is a construct that looks odd until you know
which master it serves.

Every entry carries a stable `HI.NN` code, and a file references it with a short
`# GLOSSARY: HI.NN` tag instead of re-explaining. Any file in the tree may carry
a tag, and `tests/` carries plenty; the tag is _mandatory_ in `common/`,
`settings/`, `load.sh` and `hi.sh` - not for wire bytes any more (HI.35 strips
comments out of the payload), but because those are the files a reader meets
first and the tag is shorter than the explanation. The code is what the tags
point at, so an entry can be retitled without touching a single tagged file;
codes are never reused once retired. A tag is one code, or two joined with
` + `, with optional prose after it. `tests/lint/shellcheck_test.sh` fails the
build if a tag names a code this file doesn't define. This file never ships
(the payload is `$_HI_PAYLOAD` in `hi.sh`; `docs/` isn't in it).

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
treats expanding an _empty_ array as a fatal "unbound variable". Plain
`"${a[@]}"` is only safe when at least one element is guaranteed.

**Exception - the index form.** `"${!a[@]}"` is already empty-safe and must
NOT get the guard: bash 3.2 reads `${!a[@]+...}` as expanding to nothing
whatever the array holds, and bash 5 reads it as an indirect reference and
errors outright. The lint table in `tests/lint/shellcheck_test.sh` rejects
the guarded index form.

## HI.02 _hi_read_lines

`mapfile`/`readarray` are bash 4; on 3.2 the builtin simply doesn't exist.
`_hi_read_lines <array-name>` (`common/core.sh`) is the stand-in: a `while
read` loop assigning through `eval`, keeping a last line without a trailing
newline the way `mapfile -t` does. Use it exactly like
`_hi_read_lines lines < <(cmd)`.

## HI.03 parallel arrays

Associative arrays (`declare -A`/`local -A`) are bash 4 - on 3.2 the
_declaration alone_ is a fatal "invalid option". Where a map is needed,
either parallel indexed arrays sharing one index with a keys array as the
lookup table (`_hi_group_index` in `scripts/color_preview.sh`), or
`"<key>=<value>"` strings via `_hi_kv_get`/`_hi_kv_set` (`tests/test_lib.sh`).

## HI.04 dynamic-name assignment

bash 3.2 has no namerefs (`declare -n`, bash 4.3), so writing into a
caller-named variable goes through `eval` (see `_hi_read_lines`,
`_hi_widen`) or `printf -v` where the value is a single formatted string.
Reading a caller's `local` works through bash's dynamic scoping, which is why
some helpers deliberately live beside their one caller instead of taking the
array as an argument.

## HI.05 printf -v out-var

`out="$(fn)"` forks a subshell per call; `fn outvar` with `printf -v "$outvar"`
doesn't. Used on hot paths (`_hi_git_prompt`'s optional out-var, `_hi_repeat`)

- but only in bash: zsh's `printf` has no `-v`, so zsh callers keep the
  stdout form.

## HI.06 source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`scripts/install.sh`, `packaging/bump.sh`, `packaging/mkpkg.sh`,
`scripts/color_preview.sh` and `scripts/packages_preview.sh` all carry it.

## HI.07 toggle defaulting

fish has no `${X:-0}`, and it sources `aliases.sh`/`paths.sh`/`settings.sh`
natively - so every `_HI_DISABLE_*` toggle is read _bare_, and a bare read of
an unset variable is fatal under bash's `set -u`. Therefore the toggles must
always exist: `common/core.sh` defaults the `_HI_TOGGLES` list (defaulted,
never assigned, so settings.sh and paths.sh's gate still win),
`common/config.fish` mirrors it with `set -q X; or set -gx X 0` (fish can't
read a bash array), and `hi.sh`'s `_hi_fallback_rc` emits `export X=0` lines
from the same list for bash-less targets.

## HI.08 sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back. See also cat-over-mv below for
why the write-back is `cat`, not `mv`.

## HI.09 cat-over-mv

Writing a tempfile back over an existing file goes through the existing
inode: `cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in
`common/core.sh`, which `_hi_rewrite` ends in and `scripts/install.sh` calls;
`rewrite` in `packaging/stamp.sh` is the boundary-forced copy). `mv` would transplant
mktemp's 0600 mode onto the target and sever any hardlink/ACL on it - a
dotfile manager's hardlinked `~/.bashrc` must see the new content.
Non-atomicity is acceptable for single-user rc files; `common/targets.sh`'s
cache swap keeps `mv` deliberately, for atomicity over a file it owns.

## HI.10 strftime %e over %-e

`date +%-e` (no-padding) is a GNU extension; BSD strftime prints the literal
characters. `%e` is the portable day-of-month.

## HI.11 LC_ALL=C sort

Under a UTF-8 locale, BSD `sort` exits "Illegal byte sequence" on non-UTF-8
input - and does so having printed nothing while the pipeline carries on.
Any sort whose input isn't guaranteed clean UTF-8 is pinned to `LC_ALL=C`.

## HI.12 bytes vs columns

`${#var}` counts bytes, not display columns, and in the C locale multibyte
characters inflate it - a banner padded by `${#...}` comes out narrow. Width
math around user-visible strings computes column counts explicitly (see
`changes_w` in `common/header.sh`, `_hi_visible_len` in `scripts/install.sh`).

## HI.13 command -v fallthrough

`alias x="$(command -v tool-a || command -v tool-b || command -v fallback)"`
in `settings/aliases.sh`: resolved at source time, valid in sh, bash, zsh _and_
fish (modern fish parses `$(...)`), and never leaves the alias pointing at a
missing binary. The `|| command -v echo` tail keeps `set -u`/`set -e` shells
alive when nothing matches.

A second, **narrower** chain over the same family is how flags reach only the
tier that parses them: `$_HI_BAT_REAL` is `bat || batcat` where `$_HI_BATCAT_BIN`
is `bat || batcat || ccat || cat`, so `settings/personal.sh` can attach
bat-syntax options behind `[ -n "$_HI_BAT_REAL" ] && alias ... || true` and
leave ccat and coreutils `cat` - neither of which parses them - the bare
binary.

## HI.14 _hi_on_exit

zsh doesn't run bash-style `trap ... EXIT` the same way; it has `TRAPEXIT`.
`_hi_on_exit` (`common/core.sh`) picks per shell, and is the only way cleanup
traps are registered in shared code.

## HI.15 strict-mode bracketing

Files that run inside an interactive shell (`common/core.sh`, `hi.sh`,
`common/bash.sh`, `common/git_prompt.sh`, ...) set `set -euo pipefail` at the
top _and disable it at the end of their own code_: left on, any later
non-zero status or unset variable kills the user's session. The bootloader
and fallback rc do the same on targets - forgetting it there is what once
broke `hi <target> <command>` outright.

## HI.16 no-fork reads

On per-prompt/per-startup paths, builtins over binaries: `read -r x < file`
instead of `$(cat file)` (a miss costs no fork and no error),
`${target%/*}` instead of `$(dirname ...)`, `${row%%$'\t'*}` instead of
`| cut -f1`. A few forks per prompt is the whole latency budget.

## HI.17 base64 armor

The payload is armored with `base64`, not `openssl`: it is pure ASCII
transport encoding (no crypto), and base64 ships on strictly more targets -
coreutils, busybox, macOS/BSD, Git Bash. Decode tries GNU/busybox `-d` first,
then old BSD/macOS `-D`; the failed flag parse consumes no stdin, so the
fallback still sees the whole stream. `tr` runs first because GNU `base64 -d`
tolerates the armor's newlines but not spaces, and a transport that folds
newlines into spaces would otherwise break it. `$_HI_UNARMOR` only ever runs
inside the sh bootloader - the login shell never parses its braces (fish
couldn't).

## HI.18 sh -c wrapping

Every command hi sends meets the target's _login_ shell first, and that shell
may be fish, which parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is therefore the transport's job, not
per-site care - the alternative is finding out one function at a time (the
install probe answered "nothing installed" on every fish-login host until it
was wrapped). The quoting is single-quote-and-escape rather than `printf %q`:
`%q` escapes every space with a backslash, which the login shell then has to
unescape - readable in neither the code nor an `ssh -v` log, and one more
thing for fish to differ about. Callers write plain sh and never count quotes.

## HI.19 stdin transport

The bootloader travels over **stdin of the first of two ssh calls multiplexed
on one connection** (so still one authentication), never as a command-line
argument: Linux caps a _single_ argv entry at 128KB (`MAX_ARG_STRLEN`)
however large `ARG_MAX` is, and the payload had grown within a few KB of it.
stdin has no ceiling. It has to be two calls because the second one's stdin
belongs to the interactive session - feed it a pipe and the remote shell
reads EOF. It goes over that pipe as the plain script and is `cat` into
place: only the three streams _inside_ it are armored, because only they are
binary. Armoring the assembled script on top of them - which the argv era
needed, one shell-safe token - spent a third of every session's bytes to
re-encode text that was already ASCII. The write doubles as the probe: a
target where `sh -c` won't run has no POSIX shell at all (stock Windows
OpenSSH), and one without `base64` cannot unpack what the script carries;
either way the session falls through to the PowerShell branch rather than
half-landing.

## HI.20 fallback rc

The no-bash target's rc is consumed by sh, zsh _and_ fish (`_say_hi`'s
`fish -C` branch), so every line in it must be valid in all three - `export
NAME=value` and `[ -f x ] && . x` are. Anything shell-specific is appended by
that shell's own arm. Toggle defaults come first so the files after them
still win. `_HI_REMOTE_SESSION=1` is exported because this path never reaches
`load.sh`, which normally exports it - unset, `paths.sh`'s gate reads the
target as local and strips hi for anyone with `_HI_DISABLE_LOCAL=1`.
`settings.sh` keeps its `[ -f ]` guard because nothing writes it until
install.sh runs, and a bare `.` on a missing file abandons the rest of the
file in ash/dash. `_HI_CONFIG_DIR` points at the target's own `config/`, where
the shipped overlay was unpacked - not a `~/.config/say-hi` belonging to
whoever we logged in as, and not `settings/`, which holds the _shipped_ copies
of the same names.

## HI.21 baked prompt

The bash-less tiers' PS1 is baked on the client - colors resolved once, the
username read once at source time - because busybox ash does not run command
substitution inside PS1 at all. Handed a live `$( )`, it would print the
substitution's _text_ instead of running it, so there is nothing to defer:
everything the prompt shows is resolved before the line is ever written.

## HI.22 TERM fallback probe

ssh forwards the client `TERM` verbatim, and a TERM the target has no
terminfo entry for (ghostty's `xterm-ghostty` is the canonical case, kitty's
`xterm-kitty` the common one) breaks clear/backspace before hi even matters.
The bootloader skips the probe for ubiquitous names; anything else must be
found in a terminfo tree - plain dirs and the BSD/macOS single-hex-char
layout both checked - or is swapped for `xterm-256color`, which every tree
that exists at all carries. `_HI_TERM_FALLBACK=0` keeps the original TERM no
matter what.

## HI.23 bash --rcfile -i

`bash --rcfile X -i` needs both flags, in that order: without `-i` bash
decides it isn't interactive (from stdin, not the flag) and ignores the
rcfile entirely - that was `hi <target> <cmd>` doing nothing from a script or
cron - and `-i` must come _after_ `--rcfile`, because bash's long-option pass
ends at the first short option. fish is different again: `exit` inside a
sourced file only unwinds the source, so the fish arm feeds the rc's content
to `-C` instead.

## HI.24 graft crash guard

`clean_all` cannot run after a hard kill, so every rc graft is wrapped in a
tree-exists guard that makes the block vanish on its own when the tree it
points at is gone - otherwise every shell the user opens from then on errors
at its first source line, and in a container sharing `$HOME` (distrobox) that
is the _host's_ rc file. The guard re-resolves at shell start, exactly as the
graft's own paths do, so it also silences a bystander shell opened
mid-session with none of the session's env - it asks for `$_HI_HOME` and
stops when there is none, rather than falling back to `$HOME` (HI.33).

## HI.25 session-shell ranking

`$_HI_SHELL_PREFERENCE` is an ordered list of names hi styles, plus the token
`login` for "whatever the user's login shell is"; the first entry that is
installed wins, and bash is the floor because `load.sh` only runs where bash
exists. Its default tail is not a literal: `_hi_session_shell` walks
`common/core.sh`'s `$_HI_SHELL_TREE` (`fish zsh bash dash ash sh`) and
its allow-list `case` drops the tiers that need bash to be _missing_ to be
reachable, leaving `fish > zsh > bash`. `hi.sh`'s `$_HI_SHELL_LADDER` is that
same tree with bash removed. One list, two consumers - two literals would be
free to disagree about fish-vs-zsh and dash-vs-ash.

The default puts `login` first for a reason found by the framework matrix: a
ranking that leads with fish hands it to anyone whose box has it, so a user
whose login shell is zsh-with-oh-my-zsh never sees their own setup - hi's
configs are grafted onto every rc file either way; the user's are not.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi` and a space - the most latency-sensitive path
in say-hi and the slowest (four of five backends are a subprocess each). Two
knobs keep it honest.

`_HI_PROBE_TIMEOUT` is the seconds a backend CLI gets (default 2, needs GNU
`timeout`; shared with `common/core.sh`'s `_hi_probe`) or an unreachable daemon
hangs completion unbounded. It bounds the **whole sweep**, not each leg of it:
the backends are started together and read back in roster order, so four wedged
daemons cost one ceiling rather than four. Started in turn they cost the sum,
which is how a cold TAB on a host with docker and kubectl installed used to
reach two seconds. A host with no writable scratch directory falls back to the
in-turn sweep, which is slow, not wrong.

`_HI_TARGETS_TTL` is the seconds a result is reused (default 5, 0 disables) -
a just-started container may not appear until it expires, the trade for not
paying ~110ms per TAB. **Nothing invalidates it**; there is no watch on
container events, only the clock. Two windows stack, and they are offset: the
file cache in `targets.sh` stamps when it was written, while the in-shell memo
in `common/bash.sh` and `common/zsh.zsh` stamps when that shell last read the
file. A memo filled from an already-4-second-old file holds it for its own full
TTL, so worst-case staleness is close to **twice** the TTL, not once. Only
`_HI_TARGETS_TTL=0` turns both off.

## HI.29 apostrophes in substitution comments

bash 3.2 scans a `$( ... )` command substitution with a simple quote
matcher, not the real parser: a comment line _inside_ one containing a lone
`'` (an apostrophe in prose) reads as an unterminated string, and the whole
file dies at parse time with "unexpected EOF while looking for matching
`'`". bash 4+ parses substitutions recursively and is fine, which is why
this only ever surfaces on macOS. Keep comments inside `$( )`
apostrophe-free, or hoist them above the assignment. The lint greps cannot
see this one; `tests/targets/ssh_test.sh` runs `bash -n` over every file in
a real 3.2 container to catch the class.

## HI.30 indirect invocation

Test suites hand their case functions to `_hi_check`/`_hi_case`/`_hi_par_case`
as `"$@"`, or register them as trap hooks, so nothing in the file ever calls
them by name. shellcheck reads that as dead code and raises SC2329 on each one,
which is why every suite carries a file-level `# shellcheck disable=SC2329`.
The disable is the fix; this entry is the reason it is there.

## HI.31 porcelain branch.oid

`git status --porcelain=v2 --branch` already carries HEAD's sha on its
`# branch.oid` line, so the detached-HEAD label reads it out of the stream the
prompt is already parsing instead of forking `git rev-parse`. The `rev-parse`
beneath it is a fallback for a porcelain stream too old to carry that header,
not a third fork in the common path.

## HI.32 starship deference

`_HI_PROMPT=starship` hands the prompt to [starship](https://starship.rs) when
the target has it, keeping hi's header and aliases. `common/core.sh`'s
`_hi_wants_starship` is the single predicate (the setting _and_ the binary);
`common/bash.sh` and `common/zsh.zsh` each `eval` their own `starship init`
behind it and skip building hi's PS1. Absent starship, the setting is ignored
silently.

## HI.33 derived tree location

`$_HI_HOME` is the directory _containing_ `say-hi`, and every file that needs the
tree derives it from its own path rather than defaulting to `$HOME`. The
default was a guess that is right for a standard install and wrong everywhere
else - and when it was wrong it did not fail, it silently read _another tree_.
Both platform e2e jobs spent their first real run sourcing a tree under
`/Users/runner` that was never there.

Each dialect asks the question its own way, and each asks it only when
`$_HI_HOME` is unset, so an outer layer's export (`hi.sh`'s ssh preamble,
`load.sh`, the rc line `scripts/install.sh` writes) still wins and costs no
fork:

Only a handful of files ask. `common/core.sh` owns the answer, and everything
that merely _needs_ the tree reaches core.sh through its own path rather than
hand-counting a depth from `$_HI_HOME` - `common/header.sh` carries no
derivation at all. The files that do ask are the ones with nothing above them
to ask through: an entry point, or a dialect that cannot use the previous row's
answer.

| where | how |
| --- | --- |
| `common/core.sh` | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`. The one that answers for every file sourced through it |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh` | the same, behind a `readlink` walk - `$_HI_LINK` is `/usr/bin/hi`, and the unresolved path answers `/usr`. Three copies, because each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh` | `${BASH_SOURCE[0]}` - entry points that _export_ for children |
| `scripts/doctor.sh`, `scripts/color_preview.sh`, `scripts/packages_preview.sh`, `tests/test_lib.sh` | `${BASH_SOURCE[0]}`, then `$_HI_HOME` if it is set - the standalone-entry form below |
| zsh (`common/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; zsh has no `$BASH_SOURCE`, and bash cannot parse `%x`, so core.sh's arm is `eval`'d |
| fish (`common/config.fish`) | `sh -c 'cd -P "$1/../.." && pwd'`. Not fish's own `cd`/`pwd`: a builtin-only command substitution runs in the _current_ process, so it would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical |
| `common/bash.sh` | `$_HI_HOME`, not its own path - the one file that cannot self-locate, because `load.sh` grafts its _text_ into someone else's rc (HI.24), where `$BASH_SOURCE` is that rc |

`common/core.sh`'s zsh arm is `eval`'d for one reason: bash reads `${(%):-%x}`
as a bad substitution, and the file has to _parse_ in both shells whichever
one is running it.

**The standalone-entry form, and why `$_HI_HOME` wins in it.** A script invoked
on its own has to find core.sh before it can be told anything, so it derives
from `${BASH_SOURCE[0]}` - but only as the fallback:

```sh
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
```

When `$_HI_HOME` is set, _everything_ has to come from there, core.sh included.
Reaching core.sh through the script's own path while `$_HI_ROOT` - and so
`table.sh`, `header.sh` and the launcher - came from `$_HI_HOME` runs two trees
in one process, and does it silently: the loud "no such file" you would want is
exactly what having a second, working tree takes away.

Two places keep a fallback, and both say so out loud rather than guessing.
`hi.sh` prints `set _HI_HOME to the directory that holds it` and exits when the
derived path holds no tree. And on a _target_ - the one machine with no
checkout to derive from - `_hi_remote_root`'s probe asks in this order:

1. `export _HI_HOME=` / `set -gx _HI_HOME` in `~/.bashrc`, `~/.zshrc`,
   `~/.config/fish/config.fish`, and `/etc/profile.d/say-hi.sh` for a packaged
   install. Read as _files_: the probe runs under `sh -c` over ssh, which is
   neither a login nor an interactive shell and sources none of them.
2. `$HOME`.
3. Where an install lands when nothing declared it: `~/.local/share`,
   `/usr/local/share`, `/opt`, `/usr/share`, and Homebrew's four default
   keg prefixes (`~/.linuxbrew`, `/home/linuxbrew/.linuxbrew`,
   `/opt/homebrew` and `/usr/local`, each under `opt/say-hi/libexec`).

Each candidate is then tried as `<home>/say-hi`.

Tier 3 is why the list is not just "the rc line, then `$HOME`". Homebrew's
formula writes no rc line — its caveats ask you to run `install.sh --no-link`,
and nobody has to — so a brew-installed target was invisible to tiers 1 and 2
and got the payload copied over a tree already sitting there. It is best-effort
by construction (`brew --prefix` is user-settable, and only its defaults are
listed), and strictly a fallback: a `$HOME` tree still wins, so adding it moved
no existing target's answer. The whole tier costs two shell builtins per
candidate and no forks.

The first is the point. A curated tree is exactly the one most likely to live
somewhere else, and a probe that only knew `$HOME/say-hi` made those targets
invisible - hi copied its payload over a checkout already sitting there, the
slow path, silently.

Two details in that probe. Its `sed` uses separate `-e` expressions rather than
one with `\(a\|b\)`, because BRE alternation is a GNU extension and BSD sed is
a target hi has to answer on; and a second `sed` unwraps the value, because
`config_shell` writes the path quoted _and_ pads a `# added by hi during
install` marker onto every line it owns. A quoted value is taken as-is (a `#`
inside it survives) and only an unquoted one has a trailing comment stripped.
That second `sed`'s expressions are **ordered**, and the order is the whole
trick: `-e` expressions run in sequence over a single pattern space, so
stripping the comment after unquoting would strip from a `#` that was inside
the quotes. The comment strip therefore runs first, addressed to lines that do
_not_ begin with a quote (`/^"/!`), and the unquoting runs second.
`IFS` is a newline for the candidate loop, so an install directory with a
space in it is still one candidate.

The rc grafts (HI.24) are the one shape that cannot derive: `load.sh` inlines
hi's rc _into someone else's rc_, where `$BASH_SOURCE` is that rc. They are
wrapped in a guard that requires `$_HI_HOME` to be set - in a session it always
is, and outside one there is no tree to source.

`tests/lint/shellcheck_test.sh`'s `lint_home_default` greps the tree for the
retired spellings, the way it already greps for bash-4 constructs - over
`.md` too, since docs teaching the old rule are what a packager reads.

## HI.34 test suite preamble

Every suite under `tests/` opens with the same four lines, and they are four
separate mechanisms rather than boilerplate:

```sh
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
```

`$_HI_TEST_LIB` is exported by `common/paths.sh`, so under `test_runner.sh` -
or under any shell that has sourced the product - the harness is found through
the tree the runner resolved, not through the suite's own location. The `${...:-}`
tail is the fallback for running a suite directly (`tests/common/core_test.sh`),
where nothing has exported it yet; its `../` depth is the suite's distance from
`tests/`, so a suite that moves has to have it re-counted.

`test_lib.sh` sources `common/core.sh` itself. A suite therefore sources the
harness and never core.sh: doing both would run core.sh's initialisation twice,
and the second run happens after the harness has already moved
`$XDG_CONFIG_HOME` into the scratch dir.

The `# shellcheck source=` line is a directive, not prose - the linter follows
it to type-check the source - and `# shellcheck disable=SC2329` is HI.30's
indirect invocation. Both must stay verbatim above their statement.

## HI.35 payload comment strip

Every `*.sh`, `*.zsh` and `*.fish` file is comment-stripped on its way into the
payload (`_hi_strip_awk` and `_hi_payload_tar` in `hi.sh`). The checkout keeps
every word; the wire does not, which is about 40% of it - roughly two fifths of
the shipped shell is comment. The ratio is the durable figure here; the byte
counts move every release, and `bench_payload_readme_badge` is what keeps the
one number this project quotes (README's badge) honest.

Two rules keep it safe. **Full-line comments only**: an inline `#` cannot be
told from `${x#y}`, `$#` or a `#` inside a string without a real parser, and
none of those are worth the bytes. **Never inside a heredoc**: those bodies are
data the target reads, and one of them is `hi --help`.

The order of the two tests is the correctness argument, not an implementation
detail. The comment test runs _before_ the heredoc-open test, because a comment
mentioning `<<WORD` would otherwise open a heredoc that never closes and
silently stop stripping the rest of the file - failing quiet, in the direction
that costs bytes rather than breaks a session, but failing all the same.

`_HI_KEEP_COMMENTS=1` ships the tree verbatim, for reading the real source on a
target when it behaves differently there. `tests/hi/payload_test.sh` pins the
rest: no full-line comment survives outside `hi.sh`'s heredocs, every code line
survives byte for byte, the result still parses, and `hi.sh` keeps its exec
bit - which is why the write-back is HI.09's `cat` and not `mv`, the target's
own probe testing `[ -x .../hi.sh ]` before it trusts a tree.

## HI.36 overlay toggle source

`_hi_overlay_toggle` (`hi.sh`) reads `$_HI_CONFIG_DIR/settings.sh` as a _file_
rather than off the exported environment, and that distinction is the whole
point: settings.sh rides along and is sourced on the target, so it is the value
that will apply there. The client's exported copy means something else -
`_HI_DISABLE_LOCAL=1` is precisely "leave my machine alone but style the hosts I
visit", and trimming the payload on it would stop shipping files to targets that
never disabled them. Matches `scripts/install.sh`'s `export NAME='value'`
contract for `$_HI_SETTINGS`.

## HI.37 zsh pattern-in-variable

`_hi_ssh_pattern_hit` (`common/core.sh`) matches a name against `Host`/`Match
host` glob patterns read out of `~/.ssh/config` - `*` and `?` mean the same
thing in ssh's syntax as in a `case` pattern, so no translation is needed,
only a way to try each pattern that survives being sourced by both bash and
zsh (this file is HI.34's "every bash/zsh script sources this" entry point).

Two zsh divergences stack here, not one. The first is the one HI.26's
neighbor already worked around before this entry existed: zsh does not
word-split an unquoted variable, so a bare `for pat in $patterns` loop never
iterates - it hands the whole string to `pat` once. `setopt localoptions
shwordsplit` fixes that, scoped to the function by `localoptions` so it
never leaks into a caller.

The second is easy to miss because the symptom looks identical - a `case`
that never matches - but the cause is not splitting, it's globbing. Even
once `pat` correctly holds one token per iteration, `case "$name" in $pat)`
does not treat `*` in a _variable's_ value as an active wildcard unless
`GLOB_SUBST` is set; bash needs no such flag; zsh's default is startlingly
literal here; unquoted or quoted makes no difference. The tempting fix -
`setopt globsubst` alongside `shwordsplit` - breaks the first workaround
instead of completing it: with both set, splitting `$patterns` _also_
glob-expands each token against real files in the working directory, and a
pattern matching nothing on disk errors the whole loop out (`no matches
found`) rather than surviving to the `case`. `${~pat}` is the escape: a
per-expansion toggle that asks zsh to treat that one substitution as a
pattern, at the point it's used, without turning `GLOB_SUBST` on globally or
touching how `$patterns` was split. Bash does not understand `${~pat}` at
all, so the function branches on `$ZSH_VERSION` rather than writing one line
both shells read differently.

A `!`-prefixed token (ssh's own per-pattern negation) is not honored as
exclusion - it survives as a literal pattern nothing is ever named, so it is
inert rather than wrong. Wiring up real negation would need per-token
filtering ahead of the match, which is exactly the loop this works around;
the cost of skipping it is a wrongly-colored excluded host, which is
cosmetic, never a connection.
