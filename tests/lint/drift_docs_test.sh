#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The repo-consistency sweeps over the docs: GLOSSARY's tags, SETTINGS.md's
# table, the Liquid rule, the site's links, and the tldr page. A part of
# drift_test.sh, a suite of its own. The preamble's source line is
# drift_test.sh's - it sources the harness, and holds the tables and helpers
# both share (GLOSSARY: HI.34).
set -euo pipefail

_HI_DRIFT_PART=docs
# shellcheck source=./drift_test.sh
source "${BASH_SOURCE[0]%/*}/drift_test.sh"

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
    --exclude-dir=.git --exclude-dir=dist "${_HI_LINT_NOT_OUTPUT[@]}" --exclude='*.md' 2>/dev/null || true)
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

# scripts/settings is every setting, a row each: docs/SETTINGS.md's table is
# written from it and `hi --configure` reads its items from it, so there is
# no second roster to hold it to. What is left to check is the rows against
# what the doc says elsewhere and what the shipped tree reads.
function lint_settings_table() {
  local doc="$_HI_ROOT/docs/SETTINGS.md"
  local documented name bad=0
  _hi_h2 "Checking scripts/settings against docs/SETTINGS.md and the tree"
  documented="$(_hi_settings_documented)"

  # A name the doc files under `### Not settings` is by its own account not a
  # setting, so a row for it contradicts the doc three sections down.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local levers lever=0
  levers="$(_hi_settings_not_settings "$doc")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$documented" in *"|$name|"*) ;; *) continue ;; esac
    _hi_align " | $name has a row in scripts/settings, and a '### Not settings' entry saying it is none" "FAILED" "$RED"
    _hi_note_failure "settings table: $name is both a row and not a setting"
    lever=$((lever + 1))
  done <<<"$levers"
  [ "$lever" -eq 0 ] && _hi_align " | no row is also listed under '### Not settings'" "OK" "$GREEN"
  bad=$((bad + lever))

  # ...and the direction that rots quietly, on the GLOSSARY check's precedent:
  # a row for a variable nothing reads. A *read* - `$NAME`, `${NAME`,
  # fish's `$$NAME`, or `set -q NAME` - not any mention: an assignment or a
  # comment would keep a dead name green. Only the shipped tree counts (common/, config/, load.sh, hi.sh),
  # plus scripts/update.sh: a setting is what a *session* or a connect
  # honours, and scripts/ never rides in the payload, so a name only the
  # wizard or doctor reads is a row that promises nothing on a target.
  # `hi --update` is the one local command with a setting of its own. Names hi assembles at run time never appear whole
  # in the tree - core.sh reads `_HI_PROMPT_END_$1` through an eval - and
  # those, and only those, are excused by name in _hi_settings_dynamic. No
  # retry of a miss against the stem up to the last `_`: that would let
  # every `_HI_DISABLE_*` and `_HI_*_BIN` row ride on a sibling's read, so
  # each row has to be found by its literal name.
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  local tree stale=0 dynamic
  tree="$(grep -rhoE '(\$\{?|\$\$|set -q )_HI_[A-Z0-9_]+' "$_HI_ROOT/common" \
    "$_HI_ROOT/config" "$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh" "$_HI_ROOT/scripts/update.sh" \
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

# The `_HI_` names of scripts/settings' rows, `|`-delimited with a leading
# and trailing one so a `*"|$name|"*` match cannot succeed on a prefix.
function _hi_settings_documented() {
  printf '|%s|' "$(awk -F' [|] ' '!/^#/ && $2 ~ /^_HI_/ { print $2 }' "$_HI_ROOT/scripts/settings" |
    sort -u | tr '\n' '|' | sed 's/|$//')"
}

# `_config.yml`'s `exclude:` block, split into _HI_JEKYLL_DIR_EXCL (entries
# with a trailing `/`) and _HI_JEKYLL_FILE_EXCL, one entry per line each.
# Parsed on first use; later calls in the same shell reuse it.
function _hi_jekyll_excludes() {
  local block entry
  [ -n "${_HI_JEKYLL_PARSED:-}" ] && return 0
  _HI_JEKYLL_DIR_EXCL="" _HI_JEKYLL_FILE_EXCL="" _HI_JEKYLL_PARSED=1
  block="$(awk '/^exclude:/{inside=1; next} /^[A-Za-z]/{inside=0} inside' "$_HI_ROOT/_config.yml" |
    sed -n 's/^ *- *//p')"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
    */) _HI_JEKYLL_DIR_EXCL="$_HI_JEKYLL_DIR_EXCL$entry"$'\n' ;;
    *) _HI_JEKYLL_FILE_EXCL="$_HI_JEKYLL_FILE_EXCL$entry"$'\n' ;;
    esac
  done <<<"$block"
}

# The markdown Jekyll actually turns into a page: every `*.md` in the tree,
# minus anything under a dotfile directory (`.github`, `.git`, `.claude`, ...)
# and minus every path `_config.yml`'s `exclude:` block names - directory
# entries (trailing `/`) as a prefix, file entries as a whole line. Derived
# rather than hand-kept, so excluding a file from the site (docs/tldr.md,
# below, is exactly this) drops it from the sweep with no second edit.
function _hi_jekyll_md_files() {
  local entry file rel skip
  _hi_jekyll_excludes
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$_HI_ROOT/"}"
    case "${rel%%/*}" in .*) continue ;; esac
    case $'\n'"$_HI_JEKYLL_FILE_EXCL" in *$'\n'"$rel"$'\n'*) continue ;; esac
    skip=""
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      case "$rel" in "$entry"*) skip=1 ;; esac
    done <<<"$_HI_JEKYLL_DIR_EXCL"
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

# _hi_md_link_targets <file> - "<line>\t<target>" for every inline link, image,
# reference definition, and href/src attribute, outside fenced code and inline
# code spans. Only the target is printed; titles and fragments are the
# caller's to strip.
function _hi_md_link_targets() {
  awk '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      if (line ~ /^ *\[[^]]+\]:[ \t]/) {
        t = line
        sub(/^ *\[[^]]+\]:[ \t]*/, "", t)
        print NR "\t" t
      }
      rest = line
      while (match(rest, /\]\([^)]*\)/)) {
        print NR "\t" substr(rest, RSTART + 2, RLENGTH - 3)
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = line
      while (match(rest, /(href|src)="[^"]*"/)) {
        t = substr(rest, RSTART, RLENGTH)
        sub(/^(href|src)="/, "", t)
        print NR "\t" substr(t, 1, length(t) - 1)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# A relative link on a page the site builds has to land on a page the site
# builds too. Jekyll drops every dot-path (.github/, .markdownlint.yaml) and
# everything `_config.yml`'s `exclude:` names, so a link from docs/ into
# ../.github/workflows/ or tapes/generate.sh renders fine on GitHub and 404s
# on Pages. The rule (docs/CONTRIBUTING.md): links into those paths are
# absolute github.com URLs. Existence is lychee's check in ci.yml; this one
# only knows what the site leaves out, read through _hi_jekyll_excludes like
# _hi_jekyll_md_files. A link that climbs out of the repository is flagged
# too - nothing above the root is on the site. The one way back onto it is
# pages.yml's overlay: it copies the GIFs into _site/docs/tapes/ after Jekyll
# runs, so docs/tapes/*.gif is allowed for as long as pages.yml still does.
function lint_site_links() {
  local entry file rel dir n target norm seg why
  local filebad bad=0 overlay=""
  local -a parts stack
  _hi_h2 "Checking site pages' relative links against Jekyll's exclusions"
  grep -qF '.gif _site/docs/tapes/' "$_HI_ROOT/.github/workflows/pages.yml" 2>/dev/null && overlay=1
  _hi_jekyll_excludes
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$_HI_ROOT/"}"
    dir="${rel%/*}"
    [ "$dir" = "$rel" ] && dir=""
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    filebad=0
    while IFS=$'\t' read -r n target; do
      # <target> and "title" forms, then the fragment/query
      target="${target#<}"
      target="${target%%>*}"
      target="${target%% *}"
      target="${target%%#*}"
      target="${target%%\?*}"
      case "$target" in
      '' | /* | *:* | *'{{'*) continue ;;
      esac
      stack=()
      why=""
      IFS='/' read -r -a parts <<<"${dir:+$dir/}$target"
      for seg in "${parts[@]}"; do
        case "$seg" in
        '' | .) ;;
        ..)
          if [ "${#stack[@]}" -eq 0 ]; then
            why="climbs out of the repository"
            break
          fi
          unset "stack[$((${#stack[@]} - 1))]"
          ;;
        .*)
          why="points into a dot-path Jekyll never publishes"
          stack+=("$seg")
          ;;
        *) stack+=("$seg") ;;
        esac
      done
      if [ -z "$why" ]; then
        norm="$(
          IFS=/
          printf '%s' "${stack[*]+"${stack[*]}"}"
        )"
        case $'\n'"$_HI_JEKYLL_FILE_EXCL" in *$'\n'"$norm"$'\n'*) why="points at $norm, excluded in _config.yml" ;; esac
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          case "$norm/" in "$entry"*) why="points under $entry, excluded in _config.yml" ;; esac
        done <<<"$_HI_JEKYLL_DIR_EXCL"
        case "$overlay:$norm" in 1:docs/tapes/*.gif) why="" ;; esac
      fi
      [ -n "$why" ] || continue
      _hi_align " | $rel:$n: $target $why - use a github.com URL" "FAILED" "$RED"
      _hi_note_failure "site links: $rel:$n"
      filebad=1
    done < <(_hi_md_link_targets "$file")
    bad=$((bad + filebad))
  done < <(_hi_jekyll_md_files)
  [ "$bad" -eq 0 ] && _hi_align " | every site page's relative links stay on the site" "OK" "$GREEN"
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

function run_drift_docs() {
  _hi_lint_suite_begin "Checking repo-consistency drift (docs)"

  _hi_workdir driftdocstest

  _hi_lint_halves lint_glossary_tags lint_settings_table lint_liquid_docs lint_site_links lint_tldr_page
  _hi_lint_suite_end
}

run_drift_docs
