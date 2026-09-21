# Portable Spellings

The way to write a command so every target runs it: bash 3.2 on macOS, GNU
and BSD userlands, busybox, dash as `/bin/sh`, Git Bash on Windows, and fish
and zsh where a file is shared with them. Each row is a spelling that has
been gotten wrong here at least once. **Write** is what to use, **Not** what
it replaces, **Breaks on** the target that fails and how, and **Caught by**
what stops it coming back: a lint row (`drift`'s tables, `dialects`,
shellcheck, shfmt), a suite, or - where no pattern can tell the right use from
the wrong one - review, with the failure it was learned from.

Why a construct looks the way it does is [GLOSSARY.md](GLOSSARY.md)'s job; a
row here links the entry rather than restating it. A new row belongs here the
first time a spelling costs a CI round trip.

## Contents

- [Text: sed, grep, awk](#text-sed-grep-awk)
- [Pipes under strict mode](#pipes-under-strict-mode)
- [Output](#output)
- [Files and dates](#files-and-dates)
- [bash 3.2](#bash-32)
- [Files shared with other shells](#files-shared-with-other-shells)
- [Aliases and command lookup](#aliases-and-command-lookup)
- [Git Bash](#git-bash)
- [Terminal width](#terminal-width)
- [Tests](#tests)

## Text: sed, grep, awk

| Write                                 | Not                                                       | Breaks on                                                                                                                              | Caught by                                                                               |
| ------------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `sed -E 's/(a\|b)/x/'`                | `sed -r`, or a backslash-bar alternation in a basic `sed` | BSD sed (macOS, FreeBSD, OpenBSD): `-r` is unknown and backslash-bar is a literal bar, so the match silently fails                     | `drift`                                                                                 |
| `sed … >"$tmp"` then `_hi_write_back` | `sed -i`                                                  | BSD takes an argument after `-i`, GNU does not ([HI.08](GLOSSARY.md#hi08-sed-tempfile-rewrite), [HI.09](GLOSSARY.md#hi09-cat-over-mv)) | `drift`                                                                                 |
| `grep -E`                             | `grep -P`                                                 | BSD and busybox grep have no PCRE                                                                                                      | `drift`                                                                                 |
| `sed '$d'` to drop the last line      | `head -n -1`                                              | BSD and busybox `head` take no negative count                                                                                          | `drift`                                                                                 |
| awk as POSIX writes it                | gawk's `gensub`, `strftime`, `\y`, arrays of arrays       | mawk, busybox awk, and onetrue (BSD) awk; hi.sh's include scan is checked against all four                                             | `drift` (the gawk-only functions); hi.sh's include scan is run under all four in review |

## Pipes under strict mode

| Write                                                       | Not                                                                   | Breaks on                                                                                                                                                                                         | Caught by                                                              |
| ----------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `printf '%s\n' "$x" \| grep -E pat >/dev/null`              | `printf '%s\n' "$x" \| grep -q pat` under `pipefail`                  | OpenBSD, intermittently: `grep -q` leaves at its first match, the writer gets SIGPIPE (141), and `pipefail` fails the pipeline - OpenBSD's 1 KB stdio buffer turns a 1.4 KB input into two writes | review; learned from the OpenBSD job's `release_notes.sh --check` case |
| an awk that sets a flag and reads to the end                | an awk that `exit`s part-way through a piped input                    | the same SIGPIPE, and `set -e` then ends the script                                                                                                                                               | review; the same failure                                               |
| `grep -q pat "$file"`                                       | —                                                                     | nothing: a file argument has no writer to kill                                                                                                                                                    | —                                                                      |
| strict mode on at the top of a sourced file, off at its end | leaving `set -euo pipefail` on in a file an interactive shell sources | the user's shell dies on the next non-zero status ([HI.15](GLOSSARY.md#hi15-strict-mode-bracketing))                                                                                              | `drift`                                                                |

## Output

| Write                                     | Not                                 | Breaks on                                                                        | Caught by                                      |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------- |
| `printf '%s\n' "$x"`                      | `echo -e`, or `echo` of a backslash | dash and macOS's POSIX-mode `sh` expand escapes that bash-as-`sh` prints as text | `drift` (`echo -e`); a dash sweep for the rest |
| `printf -v x '%s' ''` to clear an out-var | `printf -v x ''`                    | bash 3.2 skips the assignment ([HI.05](GLOSSARY.md#hi05-printf--v-out-var))      | `drift`                                        |

## Files and dates

| Write                                             | Not                          | Breaks on                                                                                                      | Caught by |
| ------------------------------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------- | --------- |
| `date +%e`                                        | `date +%-e`                  | BSD strftime prints `%-e` literally ([HI.10](GLOSSARY.md#hi10-strftime-e-over--e))                             | `drift`   |
| `stat -c '%a' f 2>/dev/null \|\| stat -f '%Lp' f` | `stat -c` alone              | BSD and macOS `stat` spell formats with `-f`                                                                   | `drift`   |
| `cd -P "$d" && pwd -P`                            | `readlink -f`                | absent from older macOS                                                                                        | `drift`   |
| `mktemp -t hi.name.XXXXXX`, or a path template    | `mktemp -t name` with no X's | GNU refuses a template without X's; BSD takes `-t` as a prefix, so an X template is the one spelling both read | `drift`   |
| test for empty input, then `xargs`                | `xargs -r`                   | BSD `xargs` has no `-r`                                                                                        | `drift`   |
| `tar -c -f - … \| gzip -n`                        | `tar -c -z -f -`             | bsdtar pads the compressed stream ([HI.38](GLOSSARY.md#hi38-split-tar-and-gzip))                               | a suite   |

## bash 3.2

macOS's `/bin/bash`, and the floor: `drift`'s bash-4 table fails the build on
the first four rows.

| Write                                                       | Not                                                 | Breaks on                                                                                      | Caught by                                                   |
| ----------------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `_hi_read_lines arr < <(cmd)`                               | `mapfile` / `readarray`                             | bash 4 ([HI.02](GLOSSARY.md#hi02-_hi_read_lines))                                              | `drift`                                                     |
| parallel arrays                                             | `declare -A`                                        | bash 4 ([HI.03](GLOSSARY.md#hi03-parallel-arrays))                                             | `drift`                                                     |
| `printf -v "$1"`, or `eval`                                 | `local -n`                                          | bash 4.3 ([HI.04](GLOSSARY.md#hi04-dynamic-name-assignment))                                   | `drift`                                                     |
| `tr '[:upper:]' '[:lower:]'`                                | `${x,,}`                                            | bash 4                                                                                         | `drift`                                                     |
| `${a[@]+"${a[@]}"}`, and a plain `"${!a[@]}"`               | `"${a[@]}"` of a maybe-empty array, or `${!a[@]+…}` | "unbound variable" under `set -u` ([HI.01](GLOSSARY.md#hi01-empty-array-guard))                | `drift` (the index form)                                    |
| comments above a `$( … )`, apostrophe-free inside one       | a `'` in a comment inside `$( … )`                  | the whole file fails to parse ([HI.29](GLOSSARY.md#hi29-apostrophes-in-substitution-comments)) | `bash -n` under the bash:3.2 image                          |
| `_hi_shquote`                                               | `${2//\'/…}`                                        | 3.2 keeps the replacement's quoting ([HI.40](GLOSSARY.md#hi40-hand-rolled-sh-quoting))         | `hi_helpers` and `hi_dispatch`, on the macOS job's bash 3.2 |
| `if ((BASH_VERSINFO[0] > 4 \|\| …))` around a newer builtin | `printf '%(…)T'` unguarded                          | bash before 4.2 has no `%(…)T`                                                                 | the header suite on macOS                                   |

## Files shared with other shells

| File                | Dialect                                                                             | Caught by                                       |
| ------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------- |
| `config/aliases.sh` | what bash, zsh, and fish all parse: `alias`, `export`, `&&` chains, `$( )`; no `if` | `dialects` (fish and zsh parse it)              |
| `common/paths.sh`   | plain `export` lines four shells read                                               | `dialects` (fish and zsh parse it)              |
| `common/targets.sh` | standalone POSIX sh                                                                 | checkbashisms, over every `#!/bin/sh` file      |
| `settings.sh`       | `export NAME=value` lines sh and fish both parse                                    | `hi --doctor`'s config rows, on the user's copy |

## Aliases and command lookup

| Write                                                                     | Not                                        | Breaks on                                                                                                                                          | Caught by                                                               |
| ------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `$(type unalias >/dev/null 2>&1 && unalias -a \|\| true && command -v x)` | `$(command -v x)` where an alias may exist | bash, zsh, and dash hand back the alias's text, so the "binary" is `alias ls='ls --color=auto'` ([HI.13](GLOSSARY.md#hi13-command--v-fallthrough)) | `alias_fallthrough`; learned from the first `ls` of a session on Ubuntu |
| `command sudo`, `command bash` in an alias body                           | `sudo` as its own alias's first word       | fish's alias function calls itself forever                                                                                                         | `aliases`                                                               |

## Git Bash

| Write                                                | Not                                                            | Breaks on                                                                          | Caught by                                 |
| ---------------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ----------------------------------------- |
| `printf '… "%s" …\n' "$long"`                        | a heredoc splicing a many-line value into the middle of a line | Git Bash never returns - no output, no error, only a timeout                       | review; learned from the Windows e2e jobs |
| builtins and parameter expansion on hot paths        | a `$(…)` fork per call                                         | every fork costs milliseconds under MSYS ([HI.16](GLOSSARY.md#hi16-no-fork-reads)) | the bench group                           |
| `_hi_check_capable symlink` before a case that links | assuming `ln -s` makes a link                                  | MSYS copies instead                                                                | the suites' capability checks             |

## Terminal width

| Write                                                          | Not                                     | Breaks on                                                                            | Caught by             |
| -------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------ | --------------------- |
| `_hi_term_cols` / `_hi_draw_width`, pinned by `$_HI_TERM_COLS` | `$COLUMNS` or `tput cols` read directly | captured output and CI's pty have no width; a pin keeps a test's layout fixed        | `configure`, `header` |
| `_hi_visible_len`                                              | `${#x}` for display width               | multibyte glyphs count as several bytes ([HI.12](GLOSSARY.md#hi12-bytes-vs-columns)) | `table`               |

## Tests

| Write                                                                    | Not                                             | Breaks on                                            | Caught by                    |
| ------------------------------------------------------------------------ | ----------------------------------------------- | ---------------------------------------------------- | ---------------------------- |
| `printf` in fixtures                                                     | `echo` with escapes                             | CI's `/bin/sh` is dash                               | a dash sweep before pushing  |
| `sed -E` when a test extracts with alternation                           | a basic `sed` with backslash-bar alternation    | the macOS job's BSD sed                              | `drift`                      |
| one suite per file, sections split by an env var when a suite grows slow | one serial suite past a few minutes on Git Bash | the Windows shard it lands on becomes the run's tail | `test_runner`'s shard checks |
