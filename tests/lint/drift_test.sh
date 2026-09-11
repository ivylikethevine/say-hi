#!/usr/bin/env bash
# Copyright the say-hi contributors.
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
# The last entry isn't a version issue at all - ${!a[@]+...} is a trap in both
# directions: bash 3.2 quietly expands it to nothing whatever the array holds,
# and bash 5 reads it as an indirect reference and dies. Plain "${!a[@]}" is
# already empty-safe and is what to write instead.
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
)

# The retired ~/say-hi default, as "<pattern>|<what it is>" - both dialects that
# ever spelled it. See lint_home_default below for why this is a gate and not
# a preference.
# shellcheck disable=SC2016 # these are regexes and prose, not expansions
_HI_HOME_LINT=(
  '\$\{_HI_HOME:[-=]\$\{?HOME\}?\}|${_HI_HOME:-$HOME} tree default - derive it from the file'"'"'s own path'
  'set -g?x? *_HI_HOME +(~|\$HOME)([^A-Za-z_]|$)|fish `set -gx _HI_HOME ~` tree default'
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

function lint_bash32() {
  _hi_h2 "Checking for bash-4-only constructs (macOS ships bash 3.2)"
  _hi_lint_mirror
  _hi_lint_table "$_HI_LINT_MIRROR" '*.sh' "bash-4 construct" "${_HI_BASH32_LINT[@]}"
}

# A shipped file that .gitignore swallows never reaches a commit, and nothing
# local notices: the suites read the working tree. A settings/*.toml sat
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
  done < <(cd "$_HI_ROOT" && find common settings scripts hi.sh load.sh -type f 2>/dev/null |
    git check-ignore --stdin 2>/dev/null)
  [ "$bad" -eq 0 ] && _hi_align " | every file under common/, settings/, scripts/ is tracked" "OK" "$GREEN"
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
# reason, 24.04 the fish floor and 26.04 the fish ceiling
# (tests/dockerfiles/{fish37,fish4}.Dockerfile). So the rule is "every tag
# named in shell or YAML is *one of* the pinned tags", not "every tag matches
# the pin".
#
# A tag counts as an image reference only where it reads like one: preceded by a
# space, `=`, or a quote, in a `*.sh`/`*.yml` line that is not a comment. Each
# of those filters earns its place - `nobash:alpine:ssh_fallback` is a case
# spec, `/bin/bash:bash` a framework row and `bash:5` a packages fixture, all
# the same characters meaning something else; prose in `.md` and `#` comments
# names old versions on purpose (dependabot.yml explains bash:5 by naming it).
# So does docs/PACKAGING.md, whose runbook installs the .deb on `debian:stable`
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
      hits="$hits$line
"
    done < <(grep -rnE "[ =\"']${image}:[A-Za-z0-9][A-Za-z0-9._-]*" "$_HI_ROOT" \
      --include='*.sh' --include='*.yml' \
      --exclude-dir=.git --exclude-dir=dist --exclude-dir=dockerfiles 2>/dev/null |
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

# Every GLOSSARY tag in the tree has to name a real `## HI.NN` heading in
# docs/GLOSSARY.md: the tags are how shipped files point at an explanation
# without carrying it, and a deleted entry would otherwise strand its tags
# silently. A tag is one code with optional prose after it, or two codes
# joined with ` + `; the code is matched, not the title, so retitling an entry
# touches no shipped file. Markdown files are excluded from the sweep - the
# docs *talk about* the convention.
#
# Matched anywhere on the line, not only at the start of a comment. Half the
# references in the tree are mid-sentence - `(GLOSSARY: HI.33)` inside a
# paragraph of prose - and an anchored pattern silently skipped every one of
# them, which is exactly the stranding this check exists to prevent. The cost
# of the wider net: a reference that wraps onto a second comment line is still
# invisible, so keep the code on the same line as the marker.
function lint_glossary_tags() {
  local pat='GLOSSARY' glossary="$_HI_ROOT/docs/GLOSSARY.md"
  local headings tags line tag part h ok bad=0
  _hi_h2 "Checking GLOSSARY tags against docs/GLOSSARY.md"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  _hi_read_lines headings < <(sed -n 's/^## \(HI\.[0-9][0-9]\).*/\1/p' "$glossary")
  _hi_read_lines tags < <(grep -rn "${pat}: " "$_HI_ROOT" \
    --exclude-dir=.git --exclude-dir=dist --exclude='*.md' 2>/dev/null || true)
  for line in "${tags[@]}"; do
    [ -n "$line" ] || continue
    tag="${line#*"${pat}": }"
    while IFS= read -r part; do
      ok=""
      for h in "${headings[@]}"; do
        case "$part" in "$h"*) ok=1 ;; esac
      done
      if [ -z "$ok" ]; then
        _hi_align " | unknown code in ${line%%:*}: $part" "FAILED" "$RED"
        _hi_note_failure "GLOSSARY tag: $part"
        bad=$((bad + 1))
      fi
    done <<<"${tag//" + "/$'\n'}"
  done
  [ "$bad" -eq 0 ] && _hi_align " | every tag names a real entry" "OK" "$GREEN"

  # ...and the other direction, which is the one that rots quietly. A tag
  # naming a dead entry fails above and gets fixed; an entry nothing points at
  # just sits there, and the code it described can move or go without
  # anything noticing.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local used orphan=0
  used="$(printf '%s\n' "${tags[@]}")"
  for h in "${headings[@]}"; do
    case "$used" in *"$h"*) continue ;; esac
    _hi_align " | $h is defined but nothing references it" "FAILED" "$RED"
    _hi_note_failure "GLOSSARY entry: $h unreferenced"
    orphan=$((orphan + 1))
  done
  [ "$orphan" -eq 0 ] && _hi_align " | every entry is referenced" "OK" "$GREEN"
  bad=$((bad + orphan))
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

# The vocabulary a `settings.sh` may use has to be written down where a user
# looks for it, and the tree is where it actually lives - in three places, at
# that: `common/core.sh`'s `_HI_TOGGLES` is the on/off roster, and
# `scripts/configure.sh`'s `_HI_*_PROMPTS` tables and its `_hi_collect_value`
# calls are the questions `hi --configure` asks and the lines it writes. A
# name goes into any of the three without a thought for the docs; this is
# what makes SETTINGS.md's roster derived rather than hand-kept.
#
# Only the `## Every setting` section counts, not every backticked `_HI_` name
# in the file. The point of the entry is one table, and matching the whole
# document would go green on a name mentioned in passing three sections away -
# which is the state this check exists to end.
function lint_settings_table() {
  local doc="$_HI_ROOT/docs/SETTINGS.md"
  local documented names name bad=0
  _hi_h2 "Checking hi's settings against docs/SETTINGS.md"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  documented="$(_hi_settings_documented "$doc")"
  _hi_read_lines names < <(_hi_settings_roster)
  for name in "${names[@]}"; do
    [ -n "$name" ] || continue
    case "$documented" in *"|$name|"*) continue ;; esac
    _hi_align " | $name is a setting with no row in '## Every setting'" "FAILED" "$RED"
    _hi_note_failure "settings table: $name undocumented"
    bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ] && _hi_align " | every setting the tree defines has a row" "OK" "$GREEN"

  # A name the doc files under `### Not settings` is by its own account not a
  # setting, so a row for it contradicts the doc three sections down - and
  # that is the list the roster above is filtered against, so the two halves
  # cannot both be right about one name.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local levers lever=0
  levers="$(_hi_settings_not_settings "$doc")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$documented" in *"|$name|"*) ;; *) continue ;; esac
    _hi_align " | $name has a row, and a '### Not settings' entry saying it is none" "FAILED" "$RED"
    _hi_note_failure "settings table: $name is both a row and not a setting"
    lever=$((lever + 1))
  done <<<"$levers"
  [ "$lever" -eq 0 ] && _hi_align " | no row is also listed under '### Not settings'" "OK" "$GREEN"
  bad=$((bad + lever))

  # ...and the direction that rots quietly, on the GLOSSARY check's precedent:
  # a row for a variable nothing reads. A *read* - `$NAME`, `${NAME`,
  # fish's `$$NAME`, or `set -q NAME` - not any mention: an assignment or a
  # comment would keep a dead name green. Only the shipped tree counts (common/, settings/, load.sh, hi.sh):
  # a setting is what a *session* honours, and scripts/ never rides in the
  # payload, so a name only the wizard or doctor reads is a row that promises
  # nothing on a target. Names hi assembles at run time never appear whole
  # in the tree - core.sh reads `_HI_PROMPT_END_$1` through an eval - and
  # those, and only those, are excused by name in _hi_settings_dynamic. No
  # retry of a miss against the stem up to the last `_`: that would let
  # every `_HI_DISABLE_*` and `_HI_*_BIN` row ride on a sibling's read, so
  # each row has to be found by its literal name.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local tree stale=0 dynamic
  tree="$(grep -rhoE '(\$\{?|\$\$|set -q )_HI_[A-Z0-9_]+' "$_HI_ROOT/common" \
    "$_HI_ROOT/settings" "$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh" \
    2>/dev/null | grep -oE '_HI_[A-Z0-9_]+' | sort -u)"
  dynamic="$(_hi_settings_dynamic)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case $'\n'"$tree"$'\n' in *$'\n'"$name"$'\n'*) continue ;; esac
    case $'\n'"$dynamic"$'\n' in *$'\n'"$name"$'\n'*) continue ;; esac
    _hi_align " | $name has a row but nothing in the shipped tree reads it" "FAILED" "$RED"
    _hi_note_failure "settings table: $name unread"
    stale=$((stale + 1))
  done <<<"$(printf '%s' "$documented" | tr '|' '\n')"
  [ "$stale" -eq 0 ] && _hi_align " | every row names a variable the shipped tree reads" "OK" "$GREEN"
  bad=$((bad + stale))

  # The `## Presets` table is the other roster the doc keeps by hand: its
  # first column has to be `_HI_PRESETS`' first column in configure.sh, both
  # ways - a preset the wizard offers with no row is unfindable, a row for a
  # preset the wizard no longer knows is `hi --configure --preset <name>`
  # failing on a documented word.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local doc_presets tree_presets preset drift=0
  # shellcheck disable=SC2016 # \1 is sed's backref, not shell
  doc_presets="$(awk '/^## /{inside = ($0 == "## Presets")} inside' "$doc" |
    sed -n 's/^| *`\([a-z][a-z0-9-]*\)`.*/\1/p' | sort -u)"
  tree_presets="$(sed -n '/^_HI_PRESETS=(/,/^)$/p' "$_HI_ROOT/scripts/configure.sh" |
    sed -n 's/^ *"\([a-z][a-z0-9-]*\)|.*/\1/p' | sort -u)"
  if [ -z "$doc_presets" ] || [ -z "$tree_presets" ]; then
    _hi_align " | the presets scrape came back empty" "FAILED" "$RED"
    _hi_note_failure "settings table: presets scrape empty"
    drift=1
  fi
  while IFS= read -r preset; do
    [ -n "$preset" ] || continue
    case $'\n'"$doc_presets"$'\n' in *$'\n'"$preset"$'\n'*) continue ;; esac
    _hi_align " | preset '$preset' is in _HI_PRESETS with no row in '## Presets'" "FAILED" "$RED"
    _hi_note_failure "settings table: preset $preset undocumented"
    drift=$((drift + 1))
  done <<<"$tree_presets"
  while IFS= read -r preset; do
    [ -n "$preset" ] || continue
    case $'\n'"$tree_presets"$'\n' in *$'\n'"$preset"$'\n'*) continue ;; esac
    _hi_align " | preset '$preset' has a row in '## Presets' but no _HI_PRESETS entry" "FAILED" "$RED"
    _hi_note_failure "settings table: preset $preset unknown to configure.sh"
    drift=$((drift + 1))
  done <<<"$doc_presets"
  [ "$drift" -eq 0 ] && _hi_align " | '## Presets' names exactly _HI_PRESETS' presets" "OK" "$GREEN"
  bad=$((bad + drift))
  return "$bad"
}

# The rows the unread check excuses: names core.sh only ever reads through
# `eval "\${_HI_PROMPT_END_$1:-}"` in _hi_prompt_end, one per shell of the
# tree, so no grep for the literal can find them. Spelled out rather than
# pattern-matched, and only while the eval is still there to justify it - if
# _hi_prompt_end is rewritten to read the names whole, the list prints
# nothing and the rows are held to the same grep as every other.
function _hi_settings_dynamic() {
  # shellcheck disable=SC2016 # the literal `$1` of core.sh's eval is the text sought
  grep -q '_HI_PROMPT_END_\$1' "$_HI_ROOT/common/core.sh" || return 0
  printf '%s\n' _HI_PROMPT_END_BASH _HI_PROMPT_END_ZSH _HI_PROMPT_END_FISH
}

# The `_HI_` names docs/SETTINGS.md's `### Not settings` subsection lists as
# settings-shaped names - derived paths, the client's `_HI_ASCII` verdict, the
# test levers (`_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT`, ...). One per line.
function _hi_settings_not_settings() {
  # shellcheck disable=SC2016 # a backticked `$_HI_X` in the doc, not an expansion
  awk '/^##/{inside = ($0 == "### Not settings")} inside' "$1" |
    grep -oE '`\$?_HI_[A-Z0-9_]+`' | tr -d '`$' | sort -u
}

# The `_HI_` names of the `## Every setting` table, `|`-delimited with a leading
# and trailing one so a `*"|$name|"*` match cannot succeed on a prefix.
function _hi_settings_documented() {
  # shellcheck disable=SC2016 # \1 is sed's backref and `|$` its anchor, not shell
  printf '|%s|' "$(awk '/^## /{inside = ($0 == "## Every setting")} inside' "$1" |
    sed -n 's/^| *`\(_HI_[A-Z0-9_]*\)`.*/\1/p' | sort -u | tr '\n' '|' | sed 's/|$//')"
}

# Every name the tree treats as a setting: core.sh's toggle roster, plus the
# variable column of every `_HI_*_PROMPTS` table in configure.sh (the yes/no
# groups `hi --configure` asks, `<var>|<off>|<on>|<preview>|<needs>|<label>`
# rows), plus every name a `_hi_collect_value` call writes (the free-text
# settings the wizard asks outside a table; a name assembled at run time,
# `_HI_PROMPT_END_$shell`, is skipped here and caught by its literal rows).
# Any table by that name counts, so a section added to the wizard cannot ask
# about a setting this check never sees. Plus the knobs the wizard never asks
# about: every `_HI_<TOOL>_OPTS` and `_HI_<TOOL>_BIN` that settings/aliases.sh
# reads (`${_HI_BAT_OPTS:-...}`, `"$_HI_LS_BIN"`) is a user-facing dial with
# no question behind it, and the suffix is what tells those from the file's
# own state (`_HI_SESSION_RC`, `_HI_CLEANUP`, `_HI_CONFIG_DIR`). Minus
# whatever the doc itself files under `### Not settings` - the test levers
# and the derived paths take effect the same way a row does and must not be
# asked for as one. `sort -u` because the toggles and the tables overlap
# almost entirely - without it a toggle that is also a question is reported
# missing twice.
function _hi_settings_roster() {
  {
    sed -n '/^  _HI_TOGGLES=(/,/)$/p' "$_HI_ROOT/common/core.sh" |
      grep -oE '_HI_[A-Z0-9_]+' | grep -v '^_HI_TOGGLES$'
    sed -n '/^_HI_[A-Z_]*_PROMPTS=(/,/^)$/p' \
      "$_HI_ROOT/scripts/configure.sh" | sed -n 's/^ *"\(_HI_[A-Z0-9_]*\)|.*/\1/p'
    sed -n 's/^ *_hi_collect_value "\{0,1\}\(_HI_[A-Z0-9_]*\)"\{0,1\} .*/\1/p' \
      "$_HI_ROOT/scripts/configure.sh" | grep -v '_$'
    grep -oE '\$\{?_HI_[A-Z0-9]+_(OPTS|BIN)[^A-Z0-9_]' "$_HI_ROOT/settings/aliases.sh" |
      grep -oE '_HI_[A-Z0-9_]+'
  } | sort -u | grep -vxF -f <(_hi_settings_not_settings "$_HI_ROOT/docs/SETTINGS.md")
}

# The markdown Jekyll actually turns into a page: every `*.md` in the tree,
# minus anything under a dotfile directory (`.github`, `.git`, `.claude`, ...)
# and minus every path `_config.yml`'s `exclude:` block names - directory
# entries (trailing `/`) as a prefix, file entries as a whole line. Derived
# rather than hand-kept, so excluding a file from the site (docs/tldr.md,
# below, is exactly this) drops it from the sweep with no second edit.
function _hi_jekyll_md_files() {
  local block file_excl="" dir_excl="" entry file rel skip
  block="$(awk '/^exclude:/{inside=1; next} /^[A-Za-z]/{inside=0} inside' "$_HI_ROOT/_config.yml" |
    sed -n 's/^ *- *//p')"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
    */) dir_excl="$dir_excl$entry"$'\n' ;;
    *) file_excl="$file_excl$entry"$'\n' ;;
    esac
  done <<<"$block"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$_HI_ROOT/"}"
    case "${rel%%/*}" in .*) continue ;; esac
    case $'\n'"$file_excl" in *$'\n'"$rel"$'\n'*) continue ;; esac
    skip=""
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      case "$rel" in "$entry"*) skip=1 ;; esac
    done <<<"$dir_excl"
    [ -n "$skip" ] && continue
    printf '%s\n' "$file"
  done < <(_hi_lint_find -name '*.md')
}

# Jekyll's Liquid runs over every page's raw text *before* Markdown, so a
# GitHub Actions `${{ }}` inside a fenced code block gets no shelter from the
# fence - Liquid opens on the first `{{` or `{%` and raises if the matching
# close isn't found before EOF. The construct that does it is a fenced
# `${{ needs.runner.outputs.ubuntu == ... &&
# format('{0}-{1}', ...) }}`: the inner `{0}` gives Liquid's tokenizer a
# single `}` to close on, so it raises mid-expression - in CI, with nothing
# local to catch it first. A doc that means to show `{{ }}`/`{% %}` verbatim
# has to wrap the span in `{% raw %}` … `{% endraw %}`, each inside an HTML
# comment so the guard itself never renders, or stay off the site
# (docs/tldr.md's use of `{{placeholder}}` is
# tldr-pages' own syntax and has to stay byte-for-byte, so it is excluded in
# `_config.yml` instead of guarded).
function lint_liquid_docs() {
  local file rel line raw n filebad bad=0
  _hi_h2 "Checking docs for Liquid syntax outside {% raw %}"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$_HI_ROOT/"}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    raw=0
    n=0
    filebad=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      case "$line" in
      *'{% raw %}'*) raw=1 ;;
      *'{% endraw %}'*) raw=0 ;;
      *)
        if [ "$raw" -eq 0 ]; then
          case "$line" in
          *'{{'* | *'{%'*)
            _hi_align " | $rel:$n has {{ or {% outside {% raw %}" "FAILED" "$RED"
            _hi_note_failure "liquid docs: $rel:$n"
            filebad=$((filebad + 1))
            ;;
          esac
        fi
        ;;
      esac
    done <"$file"
    if [ "$raw" -eq 1 ]; then
      _hi_align " | $rel ends inside an unclosed {% raw %}" "FAILED" "$RED"
      _hi_note_failure "liquid docs: $rel unclosed {% raw %}"
      filebad=$((filebad + 1))
    fi
    bad=$((bad + filebad))
  done < <(_hi_jekyll_md_files)
  [ "$bad" -eq 0 ] && _hi_align " | every page's Liquid is balanced" "OK" "$GREEN"
  return "$bad"
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
      --exclude-dir=.git --exclude-dir=dist --include='*.sh' 2>/dev/null |
      sed "s/.*$call \"\{0,1\}//;s/\"\$//"
    grep -rhoE 'dockerfiles/[a-z0-9-]+\.Dockerfile' "$_HI_ROOT" \
      --exclude-dir=.git --exclude-dir=dist --exclude-dir=dockerfiles 2>/dev/null |
      sed 's|.*/||;s|\.Dockerfile$||'
  } | sort -u)

  # the interpolated form, _hi_dockerfile "<prefix>$..." - the literal half is
  # all a grep can know, so every file it could name counts as referenced
  _hi_read_lines prefixes < <(grep -rhoE "$call \"[a-z0-9-]*\\\$" "$_HI_ROOT" \
    --exclude-dir=.git --exclude-dir=dist --include='*.sh' 2>/dev/null |
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

# docs/tldr.md is the tldr-pages draft, paired with docs/hi.1 in
# CONTRIBUTING's table but, unlike the page, checked by nothing - a flag
# rename failed parse_test.sh on the page and passed here. Two facts: every
# --flag it shows is a common/flags row (--json, --use's word, and the like
# are arguments, so only the first word of a command counts), and it stays
# inside upstream's cap of eight examples.
function lint_tldr_page() {
  local page="$_HI_ROOT/docs/tldr.md" flag n bad=0
  _hi_h2 "Checking docs/tldr.md against common/flags"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    if grep -q "^$flag|" "$_HI_ROOT/common/flags"; then
      _hi_align " | $flag" "OK" "$GREEN"
    else
      _hi_align " | $flag is not a common/flags row" "FAILED" "$RED"
      _hi_note_failure "docs/tldr.md: $flag"
      bad=$((bad + 1))
    fi
  done < <(sed -n 's/^`hi \(--[a-z-]*\).*/\1/p' "$page" | sort -u)
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  n="$(grep -c '^- ' "$page")"
  if [ "$n" -le 8 ]; then
    _hi_align " | $n examples (tldr-pages allows 8)" "OK" "$GREEN"
  else
    _hi_align " | $n examples, over tldr-pages' cap of 8" "FAILED" "$RED"
    _hi_note_failure "docs/tldr.md: $n examples"
    bad=$((bad + 1))
  fi
  return "$bad"
}

# GitHub derives a heading's anchor by lowercasing it, dropping everything
# that is not a letter, digit, space, `-`, or `_`, then turning spaces into
# `-` - so ` - ` between words collapses to a double hyphen, which is why
# several entries carry one. bash 3.2 has no ${x,,}, hence tr.
function _hi_doc_anchor() {
  printf '%s\n' "$1" |
    sed -e 's/\[\([^]]*\)\]([^)]*)/\1/g' -e 's/[*`]//g' |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9 _-]//g' -e 's/^ *//' -e 's/ *$//' -e 's/ /-/g'
}

# _config.yml runs just-the-docs with no front matter on any page, so the
# theme generates no in-page navigation: a doc's "## Contents" block is the
# only intra-page nav the published site has, and nothing regenerates it. A
# heading added without its entry reads as no heading at all on the site.
# Both directions,
# plus the nesting, since a ### filed at a ##'s indent reads as a peer.
# Headings inside a fenced block are the page's content, not its structure,
# and an h3's entry only has to be indented under an h2's, not at one depth -
# TESTING.md groups two h3s under a third on purpose.
function lint_doc_contents() {
  local file rel line fence intoc depth text anchor want
  local heads entries filebad bad=0
  _hi_h2 "Checking each doc's Contents block against its headings"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    grep -q '^## Contents$' "$file" || continue
    rel="${file#"$_HI_ROOT/"}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    heads=""
    entries=""
    fence=0
    intoc=0
    while IFS= read -r line; do
      case "$line" in
      '```'*) fence=$((1 - fence)) ;;
      esac
      [ "$fence" -eq 0 ] || continue
      case "$line" in
      '### '*)
        intoc=0
        text="${line#\#\#\# }"
        heads="${heads}3 $(_hi_doc_anchor "$text")"$'\n'
        continue
        ;;
      '## '*)
        text="${line#\#\# }"
        if [ "$text" = Contents ]; then
          intoc=1
          continue
        fi
        intoc=0
        heads="${heads}2 $(_hi_doc_anchor "$text")"$'\n'
        continue
        ;;
      esac
      [ "$intoc" -eq 1 ] || continue
      case "$line" in
      '- ['*'](#'*')') entries="${entries}0 ${line##*\(#}"$'\n' ;;
      ' '*'- ['*'](#'*')') entries="${entries}1 ${line##*\(#}"$'\n' ;;
      esac
    done <"$file"
    entries="$(printf '%s' "$entries" | sed 's/)$//')"
    filebad=0
    while IFS=' ' read -r depth anchor; do
      [ -n "$anchor" ] || continue
      want=0
      [ "$depth" = 3 ] && want=1
      case $'\n'"$entries"$'\n' in
      *$'\n'"$want $anchor"$'\n'*) ;;
      *$'\n'*" $anchor"$'\n'*)
        _hi_align " | $rel: #$anchor is an h$depth but sits at the wrong list level" "FAILED" "$RED"
        filebad=$((filebad + 1))
        ;;
      *)
        _hi_align " | $rel: no Contents entry for #$anchor" "FAILED" "$RED"
        filebad=$((filebad + 1))
        ;;
      esac
    done <<<"$heads"
    while IFS=' ' read -r depth anchor; do
      [ -n "$anchor" ] || continue
      case $'\n'"$heads"$'\n' in
      *" $anchor"$'\n'*) ;;
      *)
        _hi_align " | $rel: Contents links #$anchor, which is no heading" "FAILED" "$RED"
        filebad=$((filebad + 1))
        ;;
      esac
    done <<<"$entries"
    if [ "$filebad" -eq 0 ]; then
      _hi_align " | $rel" "OK" "$GREEN"
    else
      _hi_note_failure "$rel: Contents drift"
      bad=$((bad + filebad))
    fi
  done < <(_hi_jekyll_md_files)
  return "$bad"
}

function run_drift() {
  _hi_lint_suite_begin "Checking repo-consistency drift"

  # _hi_lint_mirror blanks the tree under $_HI_WORKDIR/lintmirror
  _hi_workdir drifttest

  _hi_lint_halves lint_bash32 lint_home_default lint_ignored_payload lint_glossary_tags \
    lint_settings_table lint_container_family lint_runtime_dir lint_liquid_docs \
    lint_doc_contents lint_tldr_page lint_dockerfiles lint_image_tags \
    lint_image_digests
  _hi_lint_suite_end
}

run_drift
