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

# The same sweep for a $HOME-shaped tree default, over a wider file list. Every
# file that needs the tree can derive it from its own path (GLOSSARY: HI.33);
# guessing $HOME does not fail when it is wrong, it silently reads *another
# tree*, which is how both platform e2e jobs spent their first run sourcing a
# say-hi that was never there.
#
# Wider than the shellcheck list, which is *.sh only: zsh.zsh and config.fish
# are the files that most want this, and .md carries the rule as documentation
# - docs/PACKAGING.md taught the retired default, which is what a packager
# reads. Not .rb: _hi_lint_table drops comments, and the formula's only
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
# space, `=` or a quote, in a `*.sh`/`*.yml` line that is not a comment. Each
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

  [ "$bad" -eq 0 ] || return "$bad"
  return 0
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
  # any more just sits there, and the code it described can move or go without
  # anything noticing. HI.08 and HI.09 had both happened - orphaned, and naming
  # a file _hi_write_back had since left.
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

# The vocabulary a `settings.sh` may use has to be written down where a user
# looks for it, and the tree is where it actually lives - in three places, at
# that: `common/core.sh`'s `_HI_TOGGLES` is the on/off roster, and
# `scripts/install.sh`'s `_HI_FEATURE_PROMPTS` and `_HI_HEADER_PROMPTS` are the
# questions `hi --configure` asks and the lines it writes. A name goes into any
# of the three without a thought for the docs, which is how "what can I set?"
# stopped being answerable from one place; this is what makes SETTINGS.md's
# roster derived rather than hand-kept.
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

  # ...and the direction that rots quietly, on the GLOSSARY check's precedent:
  # a row for a variable nothing reads any more. Names hi assembles at run time
  # never appear whole in the tree - core.sh reads `_HI_PROMPT_END_$1` through
  # an eval - so a miss retries against the literal prefix up to the last `_`
  # before it is called a failure.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local tree stale=0 stem
  tree="$(grep -rhoE '_HI_[A-Z0-9_]+' "$_HI_ROOT/common" "$_HI_ROOT/settings" \
    "$_HI_ROOT/scripts" "$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh" \
    2>/dev/null | sort -u)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$tree" in *"$name"$'\n'* | *"$name") continue ;; esac
    stem="${name%_*}_"
    case "$tree" in *"$stem"*) continue ;; esac
    _hi_align " | $name has a row but nothing in the tree reads it" "FAILED" "$RED"
    _hi_note_failure "settings table: $name unread"
    stale=$((stale + 1))
  done <<<"$(printf '%s' "$documented" | tr '|' '\n')"
  [ "$stale" -eq 0 ] && _hi_align " | every row names a variable the tree reads" "OK" "$GREEN"
  bad=$((bad + stale))
  return "$bad"
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
# groups `hi --configure` asks, `<var>|<off>|<on>|<preview>|<question>|<needs>`
# rows). Any table by that name counts, so a section added to the wizard
# cannot ask about a setting this check never sees. `sort -u` because the
# toggles and the tables overlap almost entirely - without it a toggle that
# is also a question is reported missing twice.
function _hi_settings_roster() {
  {
    sed -n '/^  _HI_TOGGLES=(/,/)$/p' "$_HI_ROOT/common/core.sh" |
      grep -oE '_HI_[A-Z0-9_]+' | grep -v '^_HI_TOGGLES$'
    sed -n '/^_HI_[A-Z_]*_PROMPTS=(/,/^)$/p' \
      "$_HI_ROOT/scripts/configure.sh" | sed -n 's/^ *"\(_HI_[A-Z0-9_]*\)|.*/\1/p'
  } | sort -u
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
# --flag it shows is a common/flags row (--json, --use's word and the like
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

function run_drift() {
  _hi_lint_suite_begin "Checking repo-consistency drift"

  # _hi_lint_mirror blanks the tree under $_HI_WORKDIR/lintmirror
  _hi_workdir drifttest

  _hi_lint_halves lint_bash32 lint_home_default lint_glossary_tags \
    lint_settings_table lint_liquid_docs lint_tldr_page lint_dockerfiles \
    lint_image_tags lint_image_digests
  _hi_lint_suite_end
}

run_drift
