#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The repo-consistency sweeps: checks that something written down elsewhere
# (a bash-4 floor, a retired default, docs/GLOSSARY.md, docs/SETTINGS.md,
# _config.yml's Liquid rule, tests/dockerfiles/'s own pins) still agrees with
# what the tree actually does. None of these wrap an external tool - every one
# is a grep, a build-list comparison, or a small parser over files already in
# the tree, which is what separates this suite from tools_test.sh.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# The bash-4-only constructs, as "<pattern>|<what it is>". macOS still ships
# bash 3.2 and hi has to run there, but shellcheck can't help: every one of
# these is valid bash, just not valid *old* bash, and most of them fail loudly
# at runtime rather than at parse time (see tests/targets/ssh_test.sh's bash32
# cases for the same rule enforced end-to-end against a real 3.2).
#
# The last two are no version issue. ${!a[@]+...} is a trap in both
# directions: bash 3.2 quietly expands it to nothing whatever the array holds,
# and bash 5 reads it as an indirect reference and dies. Plain "${!a[@]}" is
# already empty-safe and is what to write instead. And bash 3.2 reads the
# pattern of a ${x//pat/rep} up to the first /, one inside a nested expansion
# included, and dies with "bad substitution" where bash 4 pairs the braces.
#
# One trap no pattern here can catch: bash 3.2's $( ... ) scanner does not
# skip # comments, so an apostrophe (or an unbalanced paren) in a comment
# inside a command substitution opens a quote that swallows the rest of the
# file and dies at some far-off `)`. Keep comments inside $( ... ) free of
# both; `bash -n` under the bash:3.2 image is the check that sees it.
# shellcheck disable=SC2016 # these are regexes and prose, not expansions
_HI_BASH32_LINT=(
  '\bmapfile\b|\breadarray\b|mapfile/readarray (bash 4) - use _hi_read_lines'
  '\b(declare|local|typeset)[[:space:]]+-[a-zA-Z]*A\b|associative arrays (bash 4)'
  '\b(declare|local|typeset)[[:space:]]+-[a-zA-Z]*n\b|namerefs (bash 4.3)'
  '\$\{[A-Za-z_][A-Za-z_0-9]*(\[[^]]*\])?(,,?|\^\^?)\}|case conversion (bash 4)'
  '\bwait[[:space:]]+-n\b|wait -n (bash 4.3)'
  '\$\{![A-Za-z_][A-Za-z_0-9]*\[[@*]\][+:-]|${!a[@]+...} - use a plain "${!a[@]}"'
  '\$\{[A-Za-z_][A-Za-z_0-9]*//?[^}]*\$\{[A-Za-z_][A-Za-z_0-9]*(%%?|##?)[^}]*/|a / in an expansion nested in ${x//...} - bash 3.2 ends the pattern there; cut it into a variable first'
)

# Spellings one userland has and another does not, as "<pattern>|<what it
# is>": the enforced rows of docs/SYNTAX.md, which says what to write instead
# and which target each one broke. A spelling that needs a judgement call (a
# `grep -q` under pipefail, sed's `\|`) is a SYNTAX row without a pattern.
# shellcheck disable=SC2016 # these are regexes and prose, not expansions
_HI_PORTABLE_LINT=(
  '\becho[[:space:]]+-e\b|echo -e - dash and a POSIX-mode sh print the -e; use printf'
  '\bdate\b[^#]*%-[a-zA-Z]|date %-X (GNU) - BSD prints it literally; use %e (HI.10)'
  '\bsed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*r\b|sed -r (GNU) - use sed -E'
  '\bsed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*i\b|sed -i - its flag differs BSD/GNU (HI.08)'
  '\bgrep[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*P|grep -P - BSD and busybox grep have no PCRE; use -E'
  '\breadlink[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*f\b|readlink -f - absent from older macOS; cd -P then pwd -P'
  '\bxargs[[:space:]]+(-[a-zA-Z0-9]+[[:space:]]+)*-[a-zA-Z0-9]*r\b|xargs -r (GNU) - guard the empty input instead'
  '\bhead[[:space:]]+-n[[:space:]]*-[0-9]|head -n -N (GNU) - use sed to drop the tail'
  "\\bsed[[:space:]]+(-[a-zA-DF-Z]+[[:space:]]+)*(-e[[:space:]]+)?'[^']*\\\\\\||sed backslash-bar alternation (GNU) - use sed -E"
  "\\bgrep[[:space:]]+(-[a-zA-DF-Z]+[[:space:]]+)*(-e[[:space:]]+)?'[^']*\\\\\\||grep backslash-bar alternation (GNU) - use grep -E, or an -e each"
  "\\bprintf[[:space:]]+-v[[:space:]]+[^[:space:]]+[[:space:]]+(''|\"\")([[:space:];)]|\$)|printf -v x '' - bash 3.2 skips it; printf -v x '%s' '' (HI.05)"
  '\b(gensub|strftime|systime|asorti?|patsplit)[[:space:]]*\(|a gawk-only awk function - mawk, busybox, and BSD awk have none'
  "\\bmktemp\\b[^;|]*-t[[:space:]]+[A-Za-z0-9._/-]*[A-WYZa-z0-9._/-]([[:space:])\"']|\$)|mktemp -t with no X template - GNU refuses it"
)

# Both edit files only inside a Linux container, where sed is GNU's: the p10k
# fixture's ~/.zshrc and repo_test.sh's Fedora mirror pin.
_HI_PORTABLE_EXEMPT=(p10k.sh repo_test.sh)

# The retired ~/say-hi default, as "<pattern>|<what it is>" - both dialects that
# ever spelled it. See lint_home_default below for why this is a gate and not
# a preference.
# shellcheck disable=SC2016 # these are regexes and prose, not expansions
_HI_HOME_LINT=(
  '\$\{_HI_HOME:[-=]\$\{?HOME\}?\}|${_HI_HOME:-$HOME} tree default - derive it from the file'"'"'s own path'
  'set -g?x? *_HI_HOME +(~|\$HOME)([^A-Za-z_]|$)|fish `set -gx _HI_HOME ~` tree default'
)

# What runs text as code beside eval, as "<kind>|<pattern>": a `source` or .
# of a path held in a variable, a shell handed a script in a word, a recursive
# rm. tests/lint/eval_roster counts each, a file.
# shellcheck disable=SC2016 # these are regexes, not expansions
_HI_EVAL_KIN_LINT=(
  'source|(\bsource|(^|&&|\|\||[;({])[[:space:]]*\.)[[:space:]]+"?\$'
  'sh -c|(^|[^A-Za-z_.])(bash|dash|zsh|fish|sh)[[:space:]]+(-[a-z]+[[:space:]]+)*-c([[:space:]]|$)'
  'rm -r|(^|[^A-Za-z_.])rm[[:space:]]+-[a-zA-Z]*[rR]'
)

# One file's text with the pattern tables above blanked out - their patterns
# and descriptions name the very constructs they look for, so this file would
# otherwise report itself. Blanked rather than deleted so the line numbers in a
# real hit still point at the right line. Any _HI_*_LINT table, not just one by
# name: a table added below has to be blanked too, and finding out that it
# wasn't means reading a report of this file against itself.
function _hi_lint_source_lines() {
  awk '/^_HI_[A-Z0-9_]*_LINT=\(/ { inside = 1 }
       inside { print ""; if (/^\)/) inside = 0; next }
       { print }' "$1"
}

# _hi_lint_blanks <dir> <file...> - the blanked mirror of <file...> under
# <dir>, laid out like the source tree so one recursive `grep -H` per pattern
# reports the real path. Blanking each file once and grepping the tree is what
# keeps a table cheap: a grep per (pattern x file) was ~1000 processes a run,
# and this is the CI gate.
function _hi_lint_blanks() {
  local dir="$1" file rel
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  for file in "$@"; do
    rel="${file#"$_HI_ROOT/"}"
    case "$rel" in */*) mkdir -p "$dir/${rel%/*}" ;; esac
    _hi_lint_source_lines "$file" >"$dir/$rel"
  done
}

# _hi_lint_table <dir> <include> <what-plural> <entry...> - every
# "<pattern>|<what>" hit. <include> is grep's --include glob, or empty for the
# whole mirror: the two sweeps share one blanked tree and differ only in which
# extensions they look at.
# outside a comment, reported one line per pattern. Comments are excluded on
# purpose: half of these constructs are *named* in the notes explaining why
# they aren't used. Returns how many patterns matched.
function _hi_lint_table() {
  local dir="$1" include="$2" label="$3" entry pattern what hits bad=0
  local -a inc=()
  shift 3
  [ -n "$include" ] && inc=(--include="$include")
  # $_HI_LINT_EXCLUDE: space-separated basenames this table skips
  for entry in ${_HI_LINT_EXCLUDE:-}; do inc+=(--exclude="$entry"); done
  for entry in "$@"; do
    pattern="${entry%|*}"
    what="${entry##*|}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    # anchored and non-global, so a '%' or a path-like string inside a matched
    # line survives into the report untouched
    hits="$(grep -rnHE ${inc[@]+"${inc[@]}"} "$pattern" "$dir" 2>/dev/null | grep -v ':[[:space:]]*#' |
      sed "s|^$dir/||" || true)"
    if [ -z "$hits" ]; then
      _hi_align " | no $what" "OK" "$GREEN"
      continue
    fi
    _hi_align " | $what" "FOUND" "$RED"
    printf '%s\n' "$hits" | sed 's/^/      /'
    _hi_note_failure "$label: $what"
    bad=$((bad + 1))
  done
  return "$bad"
}

# The blanked mirror both table sweeps read, built on first use. lint_bash32
# wants the *.sh half and lint_home_default the whole thing, and _hi_lint_find
# (tests/lib/lint.sh) -name '*.sh' is the same find, same exclusions - so one
# mirror of the wider list serves both and the narrower sweep filters with
# grep's --include. Blanking twice meant an awk fork per file twice over and
# two copies of the tree on disk.
_HI_LINT_MIRROR=""

function _hi_lint_mirror() {
  local files
  [ -z "$_HI_LINT_MIRROR" ] || return 0
  _HI_LINT_MIRROR="$_HI_WORKDIR/lintmirror"
  _hi_read_lines files < <(_hi_lint_find -name '*.sh' -o -name '*.zsh' \
    -o -name '*.fish' -o -name '*.md')
  _hi_lint_blanks "$_HI_LINT_MIRROR" "${files[@]}"
}

# scan_pinned_images.sh is exempt: it runs only in image-scan.yml on an ubuntu
# runner, never on a target or a Mac, and its worker pool needs bash 4.3's
# `wait -n` (its header says so). grep's --exclude matches the basename.
_HI_BASH32_EXEMPT=(scan_pinned_images.sh)

function lint_bash32() {
  _hi_h2 "Checking for bash-4-only constructs (macOS ships bash 3.2)"
  _hi_lint_mirror
  _HI_LINT_EXCLUDE="${_HI_BASH32_EXEMPT[*]}" \
    _hi_lint_table "$_HI_LINT_MIRROR" '*.sh' "bash-4 construct" "${_HI_BASH32_LINT[@]}"
}

function lint_portable() {
  _hi_h2 "Checking for one-userland spellings (docs/SYNTAX.md)"
  _hi_lint_mirror
  _HI_LINT_EXCLUDE="${_HI_PORTABLE_EXEMPT[*]}" \
    _hi_lint_table "$_HI_LINT_MIRROR" '*.sh' "one-userland spelling" "${_HI_PORTABLE_LINT[@]}"
}

# docs/SYNTAX.md's two rows a single pattern cannot see. `stat -c` (GNU) is
# fine beside its BSD twin `stat -f` on the same line, and nowhere else. A
# file an interactive shell sources that turns strict mode on must turn it off
# again further down (`set +euo pipefail` or `_hi_opts_restore`), or the user's
# shell dies on its next non-zero status (GLOSSARY: HI.15).
function lint_portable_pairs() {
  local f hits bad=0
  _hi_h2 "Checking the paired spellings (docs/SYNTAX.md)"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 2))
  hits="$(cd "$_HI_ROOT" && grep -rnE --include='*.sh' '\bstat[[:space:]]+-c\b' . "${_HI_LINT_NOT_OUTPUT[@]}" --exclude-dir=.git 2>/dev/null |
    grep -v ':[[:space:]]*#' | grep -vE '\bstat[[:space:]]+-f\b' || true)"
  if [ -z "$hits" ]; then
    _hi_align " | no stat -c without its stat -f twin" "OK" "$GREEN"
  else
    _hi_align " | stat -c without its stat -f twin (BSD and macOS stat)" "FOUND" "$RED"
    printf '%s\n' "$hits" | sed 's/^/      /'
    _hi_note_failure "one-userland spelling: stat -c without stat -f"
    bad=$((bad + 1))
  fi
  hits=""
  for f in "$_HI_ROOT"/common/*.sh "$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh"; do
    [ -f "$f" ] || continue
    awk '/^set -euo pipefail/ { on = 1 } on && /^[[:space:]]*(set \+euo pipefail|_hi_opts_restore )/ { on = 0 } END { exit on }' "$f" ||
      hits="$hits${hits:+ }${f#"$_HI_ROOT"/}"
  done
  if [ -z "$hits" ]; then
    _hi_align " | every sourced file turns strict mode off again" "OK" "$GREEN"
  else
    _hi_align " | strict mode left on in a sourced file: $hits" "FOUND" "$RED"
    _hi_note_failure "strict mode left on (HI.15): $hits"
    bad=$((bad + 1))
  fi
  return "$bad"
}

# A shipped file that .gitignore swallows never reaches a commit, and nothing
# local notices: the suites read the working tree. A config/*.toml sat
# under a blanket `*.toml` for a whole feature. Asked of git itself, over
# every file the payload and the package ship.
function lint_ignored_payload() {
  local f bad=0
  _hi_h2 "Checking no shipped file is gitignored"
  if [ ! -d "$_HI_ROOT/.git" ] || ! command -v git >/dev/null 2>&1; then
    _hi_skip "shipped files vs .gitignore" "no git checkout"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  while IFS= read -r f; do
    _hi_align " | $f" "IGNORED" "$RED"
    _hi_note_failure "gitignored shipped file: $f"
    bad=1
  done < <(cd "$_HI_ROOT" && find common config scripts hi.sh load.sh -type f 2>/dev/null |
    git check-ignore --stdin 2>/dev/null)
  [ "$bad" -eq 0 ] && _hi_align " | every file under common/, config/, scripts/ is tracked" "OK" "$GREEN"
  return "$bad"
}

# The same sweep for a $HOME-shaped tree default, over a wider file list. Every
# file that needs the tree can derive it from its own path (GLOSSARY: HI.33);
# guessing $HOME does not fail when it is wrong, it silently reads *another
# tree*, which is how both platform e2e jobs spent their first run sourcing a
# say-hi that was never there.
#
# Wider than the shellcheck list, which is *.sh only: zsh.zsh and config.fish
# are the files that most want this, and .md carries the rule as documentation
# - a doc teaching the retired default is what a packager reads. Not .rb: _hi_lint_table drops comments, and the formula's only
# occurrence is one, so it would buy a file list and no coverage.
function lint_home_default() {
  _hi_h2 "Checking for a \$HOME default for the say-hi tree"
  _hi_lint_mirror
  _hi_lint_table "$_HI_LINT_MIRROR" '' "tree default" "${_HI_HOME_LINT[@]}"
}

# The base images are digest-pinned in tests/dockerfiles/ (docs/TESTING.md says
# why), but the same images are also named as plain tags in shell and YAML -
# tests/lib/backend.sh, docs/tapes/fixtures.sh, ci.yml's packaging smoke. Those
# are the class dependabot cannot see: it reads Dockerfiles, so a digest bump
# lands there and leaves every plain tag behind, and the suite quietly tests two
# different distro versions at once. This makes the tags follow the pins.
#
# "the pins", plural, and the set is what a reference is checked against rather
# than one tag per image: `debian` is legitimately pinned twice, bookworm-slim
# for every fixture and trixie-slim for timep.Dockerfile, which needs a glibc
# new enough for timep's prebuilt .so; `ubuntu` is pinned twice for the same
# reason, 24.04 the apt client CI's runners match and 26.04 the fish ceiling
# (tests/dockerfiles/{apt-client,fish4}.Dockerfile). So the rule is "every tag
# named in shell or YAML is *one of* the pinned tags", not "every tag matches
# the pin".
#
# A tag counts as an image reference only where it reads like one: preceded by a
# space, `=`, or a quote, in a `*.sh`/`*.yml` line that is not a comment. Each
# of those filters earns its place - `nobash:alpine:ssh_fallback` is a case
# spec, `/bin/bash:bash` a framework row, `bash:5` a packages fixture and
# `bash:starship` an _HI_PROMPT_TOOL entry, all the same characters meaning
# something else; prose in `.md` and `#` comments
# names old versions on purpose (dependabot.yml explains bash:5 by naming it).
# So does docs/RELEASING.md, whose runbook installs the .deb on `debian:stable`
# deliberately - a hand-run check wants current stable, not the fixture pin.
# The Dockerfiles are excluded too: they carry the digest, and they are what
# everything else is compared against.
function lint_image_tags() {
  local image tag ref re pinned images hit bad=0 hits line
  _hi_h2 "Checking image tags against the tests/dockerfiles pins"

  # "<image>:<tag>" per pinned FROM, and the distinct image names among them
  _hi_read_lines _HI_PINS < <(
    sed -n 's/^FROM \([^:@ ]*\):\([^@ ]*\)@sha256:.*/\1:\2/p' \
      "$_HI_ROOT/tests/dockerfiles"/*.Dockerfile | sort -u
  )
  pinned=" ${_HI_PINS[*]} "
  _hi_read_lines images < <(printf '%s\n' ${_HI_PINS[@]+"${_HI_PINS[@]}"} |
    sed 's/:.*//' | sort -u)

  for image in ${images[@]+"${images[@]}"}; do
    [ -n "$image" ] || continue
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    hits=""
    re="[ =\"']${image}:[A-Za-z0-9][A-Za-z0-9._-]*"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # the tag as written, off the end of the matched reference - bash's own
      # =~ rather than a printf|grep|head pipeline, which was three forks per
      # matched line in a loop that grows with every new tag reference
      ref=""
      [[ "$line" =~ $re ]] && ref="${BASH_REMATCH[0]}"
      tag="${ref#*:}"
      case "$pinned" in *" $image:$tag "*) continue ;; esac
      # shellcheck disable=SC2153 # core.sh's derived roster, not a typo of the setting
      case " hi $_HI_PROMPT_TOOLS " in *" $tag "*) continue ;; esac
      hits="$hits$line
"
    done < <(grep -rnE "[ =\"']${image}:[A-Za-z0-9][A-Za-z0-9._-]*" "$_HI_ROOT" \
      --include='*.sh' --include='*.yml' \
      --exclude-dir=.git --exclude-dir=dist "${_HI_LINT_NOT_OUTPUT[@]}" --exclude-dir=dockerfiles 2>/dev/null |
      grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)

    hit="$(printf '%s' "$pinned" | tr ' ' '\n' | grep "^$image:" | tr '\n' ' ')"
    if [ -z "$hits" ]; then
      _hi_align " | $image: every tag is one of the pins ($hit)" "OK" "$GREEN"
    else
      _hi_align " | $image: a tag matches no pin ($hit)" "FAILED" "$RED"
      printf '%s' "$hits" | sed "s#^$_HI_ROOT/#      #"
      _hi_note_failure "image tag drift: $image (pinned $hit)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# Two Dockerfiles legitimately pin the same image:tag - see lint_image_tags
# above for why the alpine and debian:bookworm-slim pins each appear twice.
# What they must not do is disagree about *which* digest that tag resolves to:
# demo-debian.Dockerfile's header claims "the same digest pin as the sshd
# base, so there is one debian pin to bump" - true only if the two files are
# kept in sync by hand, which nothing here checks. lint_image_tags strips the
# digest before comparing, on purpose (the doc pins two different debians on
# purpose), so it cannot see two files naming the same image:tag with
# different digests - the exact way that claim could go quietly false. This
# check reads the digest back in and catches that.
function lint_image_digests() {
  local pins pin image_tag digests dup bad=0
  _hi_h2 "Checking that every pinned image:tag agrees on one digest"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))

  # "<image>:<tag> <digest>" per pinned FROM, deduped - two files pinning the
  # same tag to the same digest collapse to one row and never reach the dup
  # check below.
  _hi_read_lines pins < <(
    sed -n 's/^FROM \([^:@ ]*\):\([^@ ]*\)@\(sha256:[0-9a-f]*\).*/\1:\2 \3/p' \
      "$_HI_ROOT/tests/dockerfiles"/*.Dockerfile | sort -u
  )

  # a tag with more than one surviving digest is the drift this exists to
  # catch
  _hi_read_lines dup < <(
    printf '%s\n' ${pins[@]+"${pins[@]}"} | awk '{print $1}' | sort | uniq -d
  )

  for image_tag in ${dup[@]+"${dup[@]}"}; do
    [ -n "$image_tag" ] || continue
    _hi_align " | $image_tag: more than one digest pinned" "FAILED" "$RED"
    digests=""
    for pin in ${pins[@]+"${pins[@]}"}; do
      case "$pin" in "$image_tag "*) digests="$digests${pin#* }
" ;; esac
    done
    while IFS= read -r pin; do
      [ -n "$pin" ] || continue
      grep -l "@$pin" "$_HI_ROOT/tests/dockerfiles"/*.Dockerfile |
        sed "s#^$_HI_ROOT/#      $pin: #"
    done <<<"$digests"
    _hi_note_failure "image digest drift: $image_tag"
    bad=$((bad + 1))
  done

  [ "$bad" -eq 0 ] && _hi_align " | every pinned image:tag agrees on one digest" "OK" "$GREEN"
  return "$bad"
}

# The docker-compatible family (GLOSSARY: HI.51) is four words that two files
# spell for themselves, because neither can read the other's: core.sh's
# $_HI_CONTAINER_CLIS is read by hi.sh and common/header.sh, and
# common/targets.sh is standalone POSIX and cannot source it. A member added
# to one and forgotten in the other would list on TAB and refuse to connect,
# or connect and never probe. This is what keeps them one list.
function lint_container_family() {
  local line bad=0 core="" targets=""
  _hi_h2 "Checking the docker-compatible family across its two files"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  line="$(sed -n 's/^export _HI_CONTAINER_CLIS="\([a-z][a-z ]*\)"$/\1/p' "$_HI_ROOT/common/core.sh")"
  if [ -z "$line" ]; then
    _hi_align " | common/core.sh: no \$_HI_CONTAINER_CLIS where one is expected" "FAILED" "$RED"
    _hi_note_failure "container family: common/core.sh has no list"
    bad=$((bad + 1))
  else
    core="$line"
    _hi_align " | common/core.sh: $core" "OK" "$GREEN"
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  line="$(sed -n 's/^clis="\([a-z][a-z ]*\)"$/\1/p' "$_HI_ROOT/common/targets.sh")"
  if [ -z "$line" ]; then
    _hi_align " | common/targets.sh: no family list where one is expected" "FAILED" "$RED"
    _hi_note_failure "container family: common/targets.sh has no list"
    bad=$((bad + 1))
  else
    targets="$line"
    if [ -n "$core" ] && [ "$targets" != "$core" ]; then
      _hi_align " | common/targets.sh: $targets" "FAILED" "$RED"
      _hi_note_failure "container family: common/targets.sh drifted"
      bad=$((bad + 1))
    else
      _hi_align " | common/targets.sh: $targets" "OK" "$GREEN"
    fi
  fi
  return "$bad"
}

# common/core.sh's _hi_runtime_dir and common/targets.sh's cache_dir
# independently build the SAME directory - $XDG_RUNTIME_DIR, else a private
# ${TMPDIR:-/tmp}/hi-<uid> - and hand it to different callers (the
# payload/overlay cache and the ControlMaster socket on one side, the TAB
# completion cache on the other). They cannot share code: targets.sh is
# standalone POSIX and sources nothing (its own header says so), and
# core.sh:_hi_runtime_dir says the two "only stay in step by comment" (hi.sh
# reads core.sh's). A divergence would not fail
# anything - it would just put two caches in two places, or drop one file's
# ownership guard on a shared /tmp.
#
# The name is normalised before comparing (the two spell the uid into
# differently-named locals), and each guard is asserted in both files rather
# than diffed, since the dialects genuinely differ - bash's $EUID against
# POSIX `id -u`, `printf -v` against a plain assignment.
function lint_runtime_dir() {
  local file name first="" guard bad=0 lost
  _hi_h2 "Checking the runtime-directory copy (common/core.sh, common/targets.sh)"
  for file in common/core.sh common/targets.sh; do
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    # the fallback path, with whatever local holds the uid folded to $UID
    # shellcheck disable=SC2016 # the $ are sed's, matching the literal
    # "${TMPDIR:-/tmp}/hi-$<local>" text in the file - expanding them here
    # would search for this shell's TMPDIR instead of the source's spelling
    name="$(sed -n 's/.*="\${TMPDIR:-\/tmp}\/hi-\$[A-Za-z_][A-Za-z0-9_]*"$/${TMPDIR:-\/tmp}\/hi-$UID/p' "$_HI_ROOT/$file" | head -1)"
    if [ -z "$name" ]; then
      _hi_align " | $file: no \${TMPDIR:-/tmp}/hi-<uid> fallback" "FAILED" "$RED"
      _hi_note_failure "runtime dir: $file has no fallback path"
      bad=$((bad + 1))
      continue
    fi
    if [ -n "$first" ] && [ "$name" != "$first" ]; then
      _hi_align " | $file: $name" "FAILED" "$RED"
      _hi_note_failure "runtime dir: $file names a different directory"
      bad=$((bad + 1))
      continue
    fi
    [ -n "$first" ] || first="$name"
    # the three guards that make the shared name safe on a shared /tmp
    local lost=0
    for guard in 'XDG_RUNTIME_DIR' 'mkdir -m 700' 'ls -ldn'; do
      if ! grep -qF -- "$guard" "$_HI_ROOT/$file"; then
        _hi_align " | $file: lost the '$guard' guard" "FAILED" "$RED"
        _hi_note_failure "runtime dir: $file lost '$guard'"
        lost=$((lost + 1))
      fi
    done
    if [ "$lost" -gt 0 ]; then
      bad=$((bad + lost))
      continue
    fi
    _hi_align " | $file: $name" "OK" "$GREEN"
  done
  return "$bad"
}

# _hi_eval_found - every eval the payload and scripts/ hold, a line each in
# the roster's shape less its <what>, and each kin counted a file
function _hi_eval_found() {
  local entry
  local -a where=("$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh" "$_HI_ROOT/common" "$_HI_ROOT/scripts")
  { grep -rHnE '(^|[^A-Za-z0-9_-])eval[[:space:]]' "${where[@]}" || true; } |
    { grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true; } |
    awk -v skip="${#_HI_ROOT}" '{
      file = $0; sub(/:.*/, "", file)
      text = $0; sub(/^[^:]*:[0-9]+:/, "", text)
      text = substr(text, match(text, /(^|[^A-Za-z0-9_-])eval[ \t]/)); sub(/^[^e]/, "", text)
      print "eval|" substr(file, skip + 2) "|" substr(text, 1, 72)
    }'
  for entry in "${_HI_EVAL_KIN_LINT[@]}"; do
    { grep -rHnE "${entry#*|}" "${where[@]}" || true; } |
      { grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true; } |
      awk -F: -v skip="${#_HI_ROOT}" -v kind="${entry%%|*}" '{ n[substr($1, skip + 2)]++ }
        END { for (file in n) print kind "|" file "|" n[file] }'
  done
}

# Text that runs as code is how a user's or a target's words would come to
# run on the other side, so every way in is written down: tests/lint/eval_roster
# holds each eval with what it evaluates, and each file's count of its kin.
# One the roster lacks fails until it has a row, and a row nothing matches has
# to go, so the roster only ever says what the tree does.
function lint_eval_roster() {
  local roster="$_HI_ROOT/tests/lint/eval_roster" found want line bad=0
  _hi_h2 "Checking every eval and its kin against tests/lint/eval_roster"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  found="$(_hi_eval_found)"
  want="$(awk -F'|' '/^#/ || /^$/ { next }
    $1 != "eval" { print $1 "|" $2 "|" $3; next }
    $3 !~ /^(const|name|own|tool)$/ { print "unknown|" $0; next }
    { text = $0; sub(/^[^|]*\|[^|]*\|[^|]*\|/, "", text); print "eval|" $2 "|" text }' "$roster")"
  while IFS= read -r line; do
    if [ -z "$line" ] || grep -qxF -- "$line" <<<"$want"; then continue; fi
    _hi_align " | not in the roster: $line" "FOUND" "$RED"
    bad=$((bad + 1))
  done <<<"$found"
  while IFS= read -r line; do
    if [ -z "$line" ] || grep -qxF -- "$line" <<<"$found"; then continue; fi
    _hi_align " | in the roster alone: $line" "FOUND" "$RED"
    bad=$((bad + 1))
  done <<<"$want"
  if [ "$bad" = 0 ]; then
    _hi_align " | every eval, source, sh -c, and rm -r has its row" "OK" "$GREEN"
    return 0
  fi
  _hi_note_failure "eval roster: $bad rows apart - tests/lint/eval_roster says what each one evaluates"
  return 1
}

# The image definitions moved out of the suites into tests/dockerfiles/, which
# bought readable files and cost the one thing a heredoc could not get wrong: a
# Dockerfile written inline is referenced by construction. A checked-in one can
# be orphaned when its caller goes, or named by a caller that misspells it -
# both of which surface as "the image just didn't build" three suites later, on
# a machine with a container backend. Both directions are checked here instead,
# in the fast group, where the answer is a grep rather than a build.
#
# Callers name an image two ways: _hi_dockerfile <stem> from anything that
# sources test_lib.sh, and the full tests/dockerfiles/<stem>.Dockerfile path
# from docs/tapes/fixtures.sh, which is standalone and does not. The framework
# suite's call interpolates its label, so that one contributes a *prefix*
# every file under it answers to.
#
# A mention in a comment counts as a reference, deliberately: a file named by
# prose is one whose deletion would strand that prose, which is the same thing
# this is here to stop. The cost is that a comment alone keeps a file looking
# used after its last real caller goes.
function lint_dockerfiles() {
  local dir="$_HI_ROOT/tests/dockerfiles" call='_hi_dockerfile'
  local files file stem first refs prefixes ref pre seen bad=0
  _hi_h2 "Checking tests/dockerfiles/ against its callers"

  # Both greps below still say `dockerfiles` on purpose, and neither wants
  # "fixing": the path one is unanchored, so it matches inside the longer
  # tests/dockerfiles/ just as well, and --exclude-dir matches on basename, so
  # it still names the moved directory. Excluded throughout because one
  # Dockerfile naming another in a comment is not a caller, and would keep an
  # orphan looking used
  _hi_read_lines refs < <({
    grep -rhoE "$call (\"[a-z0-9-]+\"|[a-z0-9-]+)" "$_HI_ROOT" \
      --exclude-dir=.git --exclude-dir=dist "${_HI_LINT_NOT_OUTPUT[@]}" --include='*.sh' 2>/dev/null |
      sed "s/.*$call \"\{0,1\}//;s/\"\$//"
    grep -rhoE 'dockerfiles/[a-z0-9-]+\.Dockerfile' "$_HI_ROOT" \
      --exclude-dir=.git --exclude-dir=dist "${_HI_LINT_NOT_OUTPUT[@]}" --exclude-dir=dockerfiles 2>/dev/null |
      sed 's|.*/||;s|\.Dockerfile$||'
  } | sort -u)

  # the interpolated form, _hi_dockerfile "<prefix>$..." - the literal half is
  # all a grep can know, so every file it could name counts as referenced
  _hi_read_lines prefixes < <(grep -rhoE "$call \"[a-z0-9-]*\\\$" "$_HI_ROOT" \
    --exclude-dir=.git --exclude-dir=dist "${_HI_LINT_NOT_OUTPUT[@]}" --include='*.sh' 2>/dev/null |
    sed "s/.*$call \"//;s/\\\$\$//" | sort -u)

  # every file has a caller
  _hi_read_lines files < <(find "$dir" -name '*.Dockerfile' | sort)
  for file in "${files[@]}"; do
    [ -n "$file" ] || continue
    stem="${file##*/}"
    stem="${stem%.Dockerfile}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))

    # a real Dockerfile, not a FROM-less fragment for a suite to assemble at
    # build time - the shape this guard exists to keep out
    first="$(grep -vE '^[[:space:]]*(#|$)' "$file" | head -1 | awk '{print $1}')"
    if [ "$first" != FROM ] && [ "$first" != ARG ]; then
      _hi_align " | $stem: starts with ${first:-nothing}, not FROM or ARG" "FAILED" "$RED"
      _hi_note_failure "tests/dockerfiles/$stem (no FROM)"
      bad=$((bad + 1))
      continue
    fi

    seen=""
    for ref in ${refs[@]+"${refs[@]}"}; do
      [ "$ref" = "$stem" ] && seen=1
    done
    for pre in ${prefixes[@]+"${prefixes[@]}"}; do
      [ -n "$pre" ] || continue
      case "$stem" in "$pre"*) seen=1 ;; esac
    done
    if [ -n "$seen" ]; then
      _hi_align " | $stem" "OK" "$GREEN"
    else
      _hi_align " | $stem: no caller references it" "FAILED" "$RED"
      _hi_note_failure "tests/dockerfiles/$stem (orphaned)"
      bad=$((bad + 1))
    fi
  done

  # and every caller has a file - the half that catches a typo
  for ref in ${refs[@]+"${refs[@]}"}; do
    [ -n "$ref" ] || continue
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if [ -f "$dir/$ref.Dockerfile" ]; then
      _hi_align " | referenced $ref" "OK" "$GREEN"
    else
      _hi_align " | referenced $ref: no such file in tests/dockerfiles/" "FAILED" "$RED"
      _hi_note_failure "tests/dockerfiles/$ref (referenced, missing)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# A case that fails has to say why on that first failure (docs/TESTING.md):
# a red label alone is no evidence, and a flake's rerun may pass. So every
# failing arm of a case - a function named test_* in a suite - is read for
# one that says nothing:
#
#   return  a statement holding `return 1` with no reporter in it and none in
#           the three statements above it (a block that prints, then cleans
#           up, then returns), or one with its reporter after the return
#   last    a last statement that is a bare assertion: its status is the
#           case's, and nothing follows to explain it
#   subst   an assertion that compares a command substitution and reports:
#           _hi_why prints the statement and its variables, so the value
#           that was wrong is in neither. Captured into a variable on the
#           line above, the reason has it.
#
# A reporter is _hi_because, _hi_why, _hi_cecho, _hi_show_*, _hi_dump_*, or a
# printf or echo that is neither captured nor sent to a file. Statements are
# joined across `||`, `&&`, `|`, and `\` line ends and across an open quote or
# $( ), a heredoc's body and a nested function are skipped, and a quoted
# `return 1` (a stub's `{ return 1; }`, a fixture's text) is not one. What it
# cannot see: an arm inside a loop or an `if` that the function ends on, and
# a helper the case calls. One row a finding:
# <file>:<line>|<case>|<return|last|subst>|<statement>. No awk comments inside: the
# portable-spelling sweep above reads this file too.
function _hi_reasons_awk() {
  cat <<'AWK'
function says(s) {
  if (s ~ /_hi_because|_hi_why|_hi_cecho|_hi_show_[a-z_]+|_hi_dump_[a-z_]+/) return 1
  if (s ~ /(^|[^A-Za-z0-9_])(printf|echo)[ \t]/ && s !~ /^[A-Za-z_][A-Za-z0-9_]*=/ && s !~ />>?[ \t]*["$\/A-Za-z]/) return 1
  return 0
}
function scan(s,   i, c, x) {
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1); x = (d ? sk[d] : "")
    if (x == "'") { if (c == "'") d--; continue }
    if (c == "\\") { i++; continue }
    if (x == "a") { if (c == "'") d--; continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") { sk[++d] = "("; i++; continue }
    if (x != "\"" && c == "$" && substr(s, i + 1, 1) == "'") { sk[++d] = "a"; i++; continue }
    if (d == 0 && substr(s, i, 2) == "<<" && substr(s, i, 3) != "<<<" && match(substr(s, i), /^<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
      tag = substr(s, i, RLENGTH); gsub(/<<-?[ \t]*|['"]/, "", tag); i += RLENGTH - 1; continue
    }
    if (x == "\"") { if (c == "\"") d--; continue }
    if (c == "'" || c == "\"") { sk[++d] = c; continue }
    if (d && c == "(") { sk[++d] = "p"; continue }
    if (d && c == ")") { d--; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;]/)) return substr(s, 1, i - 1)
  }
  return s
}
function bare(s) { gsub(/'[^']*'/, "", s); gsub(/[A-Za-z_][A-Za-z0-9_]*\(\) \{ return 1; \}/, "", s); return s }
function hit(kind, i) { printf "%s:%d|%s|%s|%s\n", FILENAME, ln[i], fn, kind, substr(st[i], 1, 160) }
function flush(   last) {
  if (fn != "" && n > 0) {
    last = st[n]
    if (last !~ /^(return( 0)?|fi|done.*|esac|\}|\)|:|true)$/ && last !~ /\|\| (true|:)$/ && last !~ /^test_[A-Za-z0-9_]+( |$)/ &&
      bare(last) !~ /(^|[^A-Za-z0-9_])return 1([^0-9]|$)/ && !says(last)) hit("last", n)
  }
  fn = ""; n = 0; cur = ""; d = 0; nest = 0; tag = ""
}
FNR == 1 { flush() }
/^function test_[A-Za-z0-9_]*\(\) \{/ { flush(); fn = $2; sub(/\(\).*/, "", fn); next }
fn == "" { next }
tag != "" { t = $0; sub(/^\t+/, "", t); if (t == tag) tag = ""; next }
d == 0 && /^\}/ { flush(); next }
{
  l = $0
  if (d == 0) { sub(/^[ \t]+/, "", l); if (l ~ /^#/ || l == "") next }
  if (cur == "") start = FNR
  l = scan(l); sub(/[ \t]+$/, "", l)
  cur = (cur == "" ? l : cur " " l)
  if (d > 0) next
  if (l ~ /(\|\||&&|\\|\|)$/) next
  s = cur; cur = ""
  if (nest) { if (s == "}") nest = 0; next }
  if (s ~ /^(function )?[A-Za-z_][A-Za-z0-9_]*\(\) *\{/) { if (s !~ /\}$/) nest = 1; next }
  n++; st[n] = s; ln[n] = start
  if (bare(s) ~ /(^|[^A-Za-z0-9_])return 1([^0-9]|$)/ && !says(s) && !(n > 1 && says(st[n - 1])) && !(n > 2 && says(st[n - 2])) && !(n > 3 && says(st[n - 3])))
    hit("return", n)
  else if (bare(s) ~ /(^|[^A-Za-z0-9_])return 1 *\|\|/) hit("return", n)
  t = s; sub(/ *\|\| *_hi_(why|because)([^A-Za-z0-9_]|$).*/, "", t)
  if (t != s) { gsub(/'[^']*'/, "", t); gsub(/\\\$/, "", t) }
  if (t != s && t ~ /(^|[ !({])\[\[? [^]]*\$\([^(]/) hit("subst", n)
}
END { flush() }
AWK
}

# ...and an end-to-end suite's failure line needs its session beside it: in
# any function of tests/targets/ that prints one in red, a _hi_show_transcript,
# _hi_show_target, or _hi_dump_log. One row a finding, the same shape.
function _hi_transcripts_awk() {
  cat <<'AWK'
function flush() { if (fn != "" && red && !shown) printf "%s:%d|%s|transcript|%s\n", FILENAME, red, fn, text; fn = ""; red = 0; shown = 0 }
FNR == 1 { flush() }
/^function [A-Za-z0-9_]+\(\) \{/ { flush(); fn = $2; sub(/\(\).*/, "", fn); next }
/^\}/ { flush(); next }
fn == "" { next }
/^[ \t]*#/ { next }
/_hi_show_transcript|_hi_show_target|_hi_dump_log/ { shown = 1 }
/_hi_cecho .*"\$(BR)?RED"/ && !red { red = FNR; text = $0; sub(/^[ \t]+/, "", text); text = substr(text, 1, 110) }
END { flush() }
AWK
}

# _hi_reasons_rows <awk program> <file...> - its rows, paths under the tree
function _hi_reasons_rows() {
  awk "$1" "${@:2}" | sed "s|^$_HI_ROOT/||"
}

# The scan is first run on a case written to fail it, so a scan that stopped
# seeing anything is itself a finding: a bare assertion as a last line, a
# silent `|| return 1`, and a compared substitution are each named, and their
# repaired twins are not.
function lint_case_reasons() {
  local dir="$_HI_WORKDIR/reasons" rows row bad=0
  local -a suites=()
  _hi_h2 "Checking that every failing arm of a case says why"
  mkdir -p "$dir"
  # shellcheck disable=SC2016 # the fixture's own text, and the rows naming it
  printf '%s\n' 'function test_fixture_ends_bare() {' '  local a=1 b=2' '  [ "$a" = "$b" ]' '}' \
    'function test_fixture_returns_silently() {' '  true || return 1' '  [ -n "$a" ] || _hi_why a' '}' \
    'function test_fixture_says_why() {' '  true || _hi_because "it was false" || return 1' '  [ -n "$a" ] || _hi_why a' '}' \
    'function test_fixture_compares_a_substitution() {' '  [ "$(cat "$a")" = x ] || _hi_why a' '}' \
    >"$dir/fixture_test.sh"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  rows="$(awk "$(_hi_reasons_awk)" "$dir/fixture_test.sh" | sed "s|^$dir/||")"
  # shellcheck disable=SC2016
  if [ "$rows" = 'fixture_test.sh:3|test_fixture_ends_bare|last|[ "$a" = "$b" ]
fixture_test.sh:6|test_fixture_returns_silently|return|true || return 1
fixture_test.sh:14|test_fixture_compares_a_substitution|subst|[ "$(cat "$a")" = x ] || _hi_why a' ]; then
    _hi_align " | the scan names a bare last line, a silent return 1, and a compared substitution" "OK" "$GREEN"
  else
    _hi_align " | the scan read its own fixture as: $rows" "FAILED" "$RED"
    _hi_note_failure "case reasons: the scan no longer sees its fixture"
    bad=1
  fi
  _hi_read_lines suites < <(find "$_HI_ROOT/tests" -name '*_test.sh' | sort)
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  rows="$(_hi_reasons_rows "$(_hi_reasons_awk)" "${suites[@]}")"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    _hi_align " | ${row%%|*}: says nothing, or not the value, when it fails - ${row#*|}" "FOUND" "$RED"
    bad=$((bad + 1))
  done <<<"$rows"
  if [ -z "$rows" ]; then
    _hi_align " | every failing arm of ${#suites[@]} suites' cases says why" "OK" "$GREEN"
  else
    _hi_note_failure "case reasons: an arm that says nothing, or compares a \$( ) it cannot show - end it in _hi_because \"<why>\" or _hi_why <variable>..., the substitution captured first"
  fi
  suites=("$_HI_ROOT"/tests/targets/*_test.sh)
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  rows="$(_hi_reasons_rows "$(_hi_transcripts_awk)" "${suites[@]}")"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    _hi_align " | ${row%%|*}: a failure line with no transcript beside it - ${row#*|}" "FOUND" "$RED"
    bad=$((bad + 1))
  done <<<"$rows"
  if [ -z "$rows" ]; then
    _hi_align " | every end-to-end failure line has its session beside it" "OK" "$GREEN"
  else
    _hi_note_failure "case reasons: an end-to-end failure line alone - add _hi_show_transcript or _hi_show_target"
  fi
  return "$bad"
}

function run_drift() {
  _hi_lint_suite_begin "Checking repo-consistency drift"

  # _hi_lint_mirror blanks the tree under $_HI_WORKDIR/lintmirror
  _hi_workdir drifttest

  _hi_lint_halves lint_bash32 lint_portable lint_portable_pairs lint_home_default lint_ignored_payload \
    lint_container_family lint_runtime_dir lint_eval_roster lint_dockerfiles lint_image_tags \
    lint_image_digests lint_case_reasons
  _hi_lint_suite_end
}

# drift_docs_test.sh sources this file for what is above and runs its own list
[ -n "${_HI_DRIFT_PART:-}" ] || run_drift
