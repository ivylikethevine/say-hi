#!/bin/bash
# The repo's lint gate. shellcheck covers every *.sh file; on top of that, every
# file a non-bash shell parses for itself is run through that shell's own syntax
# checker (`zsh -n` / `fish --no-execute`) - see $_HI_NATIVE_LINT below. Without
# that second half, shells/zsh.zsh and shells/config.fish are checked by nothing
# at all, and the files fish and zsh share with sh are only ever checked as sh.
# Two more halves ride along when their tool is installed (and skip yellow when
# not): shfmt as a formatting gate, and checkbashisms over the #!/bin/sh files.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# "<file>:<shell>:<flag...>", one per file/shell pair shellcheck's own reading
# doesn't cover. Skipped with a warning when that shell isn't installed: these
# supplement the gate rather than being it, unlike the shellcheck run below,
# whose absence is a hard failure.
# (A comment line here must never *begin* with the word shellcheck - that reads
# as a directive and fails the very lint this file runs.)
#
# Two kinds of entry. shells/zsh.zsh and shells/config.fish are not shell the
# linter can parse at all, so their own shell's syntax checker (`zsh -n` /
# `fish --no-execute`, the same two scripts/install.sh runs against the user's
# rc files) is the only thing checking them.
#
# The rest are files shellcheck *does* read - as sh or bash - that another shell
# also sources for real, so they have to parse in both. misc/aliases.sh and
# common/paths.sh (and misc/personal.sh, which aliases.sh sources) are what fish reads directly, and the failure mode there
# is silent: a perfectly good `${X:-0}` is a fish parse error that aborts the
# whole file, taking every alias (or every path) with it. zsh reaches
# common/core.sh, common/git_prompt.sh and both of those through shells/zsh.zsh.
_HI_NATIVE_LINT=(
  "shells/zsh.zsh:zsh:-n"
  "shells/zsh_personal.zsh:zsh:-n"
  "shells/config.fish:fish:--no-execute"
  "shells/fish_personal.fish:fish:--no-execute"
  "misc/aliases.sh:fish:--no-execute"
  "misc/personal.sh:fish:--no-execute"
  "common/paths.sh:fish:--no-execute"
  "misc/aliases.sh:zsh:-n"
  "misc/personal.sh:zsh:-n"
  "common/paths.sh:zsh:-n"
  "common/core.sh:zsh:-n"
  "common/git_prompt.sh:zsh:-n"
)

# Syntax-check the files above, returning how many failed. Adds its files to
# $_HI_LINT_TOTAL so the suite's reported tally covers everything it checked,
# not just the shellcheck half.
function lint_native() {
  local entry file shell flag out bad=0
  for entry in "${_HI_NATIVE_LINT[@]}"; do
    IFS=: read -r file shell flag <<<"$entry"
    if ! command -v "$shell" >/dev/null 2>&1; then
      _hi_skip "$file" "no $shell to check it with"
      continue
    fi
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$("$shell" "$flag" "$_HI_ROOT/$file" 2>&1)"; then
      _hi_align " | $file ($shell $flag)" "OK" "$GREEN"
    else
      _hi_align " | $file ($shell $flag)" "FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$file ($shell $flag)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

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

# _hi_lint_find <find-name-expr...> - the files a lint sweeps. The exclusions
# live here, not at each caller: packaging/mkpkg.sh stages a *copy* of the tree
# under dist/, so a run after a local package build would lint everything twice
# and report against paths that are not the source. .claude/ is agent scratch.
function _hi_lint_find() {
  find "$_HI_ROOT" \( "$@" \) -not -path '*/.git/*' \
    -not -path "$_HI_ROOT/dist/*" -not -path "$_HI_ROOT/.claude/*" | sort
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
# wants the *.sh half and lint_home_default the whole thing, and $_HI_SH_FILES
# is _hi_lint_find's *.sh subset - the same find, same exclusions - so one
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

# The formatter as a lint: shfmt -d over the same file list shellcheck reads
# (so dist/ stays excluded). The 2-space style comes from .editorconfig, which
# shfmt picks up when invoked with no style flags. Skips yellow when shfmt is
# absent; CI pins one via .github/actions/setup-shfmt so the gate runs there.
function lint_shfmt() {
  local out
  _hi_h2 "Checking formatting (shfmt -d, style from .editorconfig)"
  if ! command -v shfmt >/dev/null 2>&1; then
    _hi_skip "shfmt" "not installed"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(shfmt -d "${_HI_SH_FILES[@]}" 2>&1)"; then
    _hi_align " | shfmt $(shfmt --version): every file already formatted" "OK" "$GREEN"
  else
    _hi_align " | shfmt: files need reformatting (fix with: shfmt -w on the paths below)" "FAILED" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "shfmt formatting (shfmt -w the paths it names)"
    return 1
  fi
}

# Bashisms in the #!/bin/sh files slip past the main linter (they are valid
# bash, and not every POSIX deviation is flagged when checking as sh), and
# common/paths.sh really is sourced by dash/busybox sh on minimal targets -
# checkbashisms covers exactly that shebang list (first line only: the test
# files embed '#!/bin/sh' inside the shim scripts they generate). Skips yellow
# when absent; CI installs a pinned copy via .github/actions/setup-checkbashisms.
function lint_checkbashisms() {
  local file rel out shebang bad=0
  _hi_h2 "Checking the #!/bin/sh files for bashisms (checkbashisms)"
  if ! command -v checkbashisms >/dev/null 2>&1; then
    _hi_skip "checkbashisms" "not installed"
    return 0
  fi
  for file in "${_HI_SH_FILES[@]}"; do
    # `read` builtin, not `head | grep`: two forks per file over ~110 files,
    # to answer a question about one line
    IFS= read -r shebang <"$file" 2>/dev/null || shebang=""
    case "$shebang" in '#!/bin/sh'*) ;; *) continue ;; esac
    rel="${file#"$_HI_ROOT/"}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$(checkbashisms "$file" 2>&1)"; then
      _hi_align " | $rel" "OK" "$GREEN"
    else
      _hi_align " | $rel" "FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$rel (checkbashisms)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
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
# new enough for timep's prebuilt .so. So the rule is "every tag named in shell
# or YAML is *one of* the pinned tags", not "every tag matches the pin".
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
  local image tag ref pinned images hit bad=0 hits line
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
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # the tag as written, off the end of the matched reference
      ref="$(printf '%s' "$line" | grep -oE "[ =\"']${image}:[A-Za-z0-9][A-Za-z0-9._-]*" | head -1)"
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
# stopped being answerable from one place; this is what makes CONFIGURATION.md's
# roster derived rather than hand-kept.
#
# Only the `## Every setting` section counts, not every backticked `_HI_` name
# in the file. The point of the entry is one table, and matching the whole
# document would go green on a name mentioned in passing three sections away -
# which is the state this check exists to end.
function lint_settings_table() {
  local doc="$_HI_ROOT/docs/CONFIGURATION.md"
  local documented names name bad=0
  _hi_h2 "Checking hi's settings against docs/CONFIGURATION.md"
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
  tree="$(grep -rhoE '_HI_[A-Z0-9_]+' "$_HI_ROOT/common" "$_HI_ROOT/misc" \
    "$_HI_ROOT/shells" "$_HI_ROOT/scripts" "$_HI_ROOT/hi.sh" "$_HI_ROOT/load.sh" \
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
# variable column of install.sh's two `<var>|<off>|<preview>|<question>` tables.
# `sort -u` because the two overlap almost entirely - without it a toggle that
# is also a `hi --configure` question is reported missing twice.
function _hi_settings_roster() {
  {
    sed -n '/^  _HI_TOGGLES=(/,/)$/p' "$_HI_ROOT/common/core.sh" |
      grep -oE '_HI_[A-Z0-9_]+' | grep -v '^_HI_TOGGLES$'
    sed -n '/^_HI_FEATURE_PROMPTS=(/,/^)$/p;/^_HI_HEADER_PROMPTS=(/,/^)$/p' \
      "$_HI_ROOT/scripts/install.sh" | sed -n 's/^ *"\(_HI_[A-Z0-9_]*\)|.*/\1/p'
  } | sort -u
}

# A source of the user's config directory with no `# shellcheck source=`
# directive above it is a machine-killer, not a style nit, and this is what
# keeps one from landing again. It runs as a *precondition* of run_shellcheck
# rather than as one of the halves at the end: the damage happens in the
# fan-out, so a check that runs after it never gets the chance to speak.
#
# .shellcheckrc sets source-path=SCRIPTDIR, so under `shellcheck -x` the
# basename in a config-dir source resolves against the *sourcing file's own*
# directory. Where that basename is the file's own name - which is exactly what
# the per-shell overrides and misc/aliases.sh's own overlay are - the linter
# follows the file into itself and re-parses its source tree until the kernel
# stops it. Measured on this tree: ~33GB resident before a global OOM, twice,
# taking the editor down with the run. Neither the `[ -f ]` test nor the path
# comparison guarding those lines is visible to it; only the directive is.
#
# (No line of this comment may begin with the linter's own name followed by a
# space - that is the directive syntax, and prose there is a parse error.)
#
# Six lines of look-back because the guarded form spans an `&&` chain and the
# directive sits above the whole statement, not above the `source` token.
#
# The needle is split so this file does not match its own detector - the two
# halves are concatenated at run time and never appear adjacent in the source.
function lint_config_dir_sources() {
  local file needle rel stripped i n total ok bad=0
  local -a lines
  # shellcheck disable=SC2016 # a literal to match for, not an expansion
  needle='"$_HI_CONFIG'"_DIR/"
  _hi_h2 "Checking config-dir sources carry a shellcheck directive"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  for file in "${_HI_SH_FILES[@]}"; do
    case "$(cat "$file")" in *"$needle"*) ;; *) continue ;; esac
    _hi_read_lines lines <"$file"
    total="${#lines[@]}"
    for ((i = 0; i < total; i++)); do
      # leading whitespace off, comments skipped, and the dot form only where
      # `.` is a command: `grep -c . "$_HI_CONFIG_DIR/$f"` (scripts/doctor.sh)
      # is a regex dot and an argument, not a source, and matching it was this
      # check's first false positive.
      stripped="${lines[i]#"${lines[i]%%[![:space:]]*}"}"
      case "$stripped" in '#'*) continue ;; esac
      case "$stripped" in
      "source $needle"* | ". $needle"* | \
        *"&& source $needle"* | *"&& . $needle"* | \
        *"; source $needle"* | *"; . $needle"*) ;;
      *) continue ;;
      esac
      ok=""
      for ((n = 1; n <= 6 && i - n >= 0; n++)); do
        case "${lines[i - n]}" in
        *'# shellcheck source='*)
          ok=1
          break
          ;;
        esac
      done
      [ -n "$ok" ] && continue
      rel="${file#"$_HI_ROOT"/}"
      _hi_align " | $rel:$((i + 1)) sources the config dir with no 'shellcheck source=' above it" "FAILED" "$RED"
      _hi_note_failure "config-dir source: $rel:$((i + 1))"
      bad=$((bad + 1))
    done
  done
  [ "$bad" -eq 0 ] && _hi_align " | every config-dir source is directive-guarded" "OK" "$GREEN"
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

# The linter is the whole cost of `--group fast`, and it runs as one serial
# process: under -x it re-parses each file's entire sourced tree from scratch, so
# tests/test_lib.sh and the eight parts under tests/lib/ are analysed once per
# suite that sources them - most of the tree. The work is per-file and
# independent, so it fans out here the way tests/lib/parallel.sh fans out
# container cases: one shellcheck per file, $(_hi_sc_width) at a time, each
# writing its own output file so concurrent findings cannot interleave, replayed
# in the original order once the batch is done. Same tool, same flags, same
# bytes on the terminal - only the wall clock changes.
#
# The width is the whole CPU count rather than _hi_par_width's cap of four: that
# cap is there because a container case is a docker daemon and an sshd, where
# this is pure CPU and a few MB resident. $_HI_SC_WIDTH overrides it, and
# _HI_SC_WIDTH=1 is the serial run down this same code path.
#
# Raising it past the CPU count is not the lever it looks like. Measured on an
# 8-core box: 1 -> 60s, 2 -> 47s, 4 -> 41s, 8 -> 40s, and 12/16/24/32 all sit at
# 38-39s, which is run-to-run noise. What flattens the curve is -x re-parsing,
# not scheduling - see _hi_sc_chunks below, which is where the time actually
# went.
function _hi_sc_width() {
  local cpus
  if [ -n "${_HI_SC_WIDTH:-}" ]; then
    printf '%s' "$_HI_SC_WIDTH"
    return 0
  fi
  cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || true)"
  case "$cpus" in '' | *[!0-9]*) cpus=2 ;; esac
  [ "$cpus" -lt 1 ] && cpus=1
  printf '%s' "$cpus"
}

# _hi_sc_chunks <outdir> <width> <file...> - the file list dealt into <width>
# chunks, printed as "<outdir>/<n>\0<file>\0<file>...\0\n" - one line per chunk,
# which is the argv one shellcheck invocation gets.
#
# Chunks rather than one process per file, and the difference is not small: under
# -x a single invocation parses each sourced file once and reuses it for every
# file in that invocation, so 130 one-file runs re-parse test_lib.sh and its
# parts 130 times and spend triple the CPU to save half the wall clock.
#
# The same argument decides how the files are *dealt*, and it points the
# opposite way to load balancing. Round-robin used to deal file by file, which
# spread tests/ evenly and made all eight invocations parse test_lib.sh and its
# parts - eight times the work that one invocation would do. Dealing whole
# top-level directories instead keeps every file that shares a sourced tree in
# the same invocation, so that tree is parsed once. Measured at width 8: 42-45s
# by file, 32s by directory, repeatably.
#
# Chunks are *deliberately* unbalanced as a result - tests/ is 47 of 75 files
# and lands whole in one of them, which is also the run's critical path. That is
# the trade: an even split costs more total CPU than the idle cores save, and
# splitting tests/ by subdirectory (each of which sources test_lib.sh too) times
# at 36-37s, between the two. It also means width past the number of top-level
# directories buys nothing at all - there is no tenth group to hand a ninth
# core.
function _hi_sc_chunks() {
  local out="$1" width="$2" i=0 f rel top idx seen="" s
  shift 2
  for f in "$@"; do
    # $_HI_ROOT-relative, so the group is the top-level directory - and a
    # root-level file (hi.sh, load.sh) is its own group, which is right: it
    # shares a sourced tree with nothing.
    rel="${f#"$_HI_ROOT"/}"
    top="${rel%%/*}"
    case " $seen " in
    *" $top "*) ;;
    *) seen="$seen $top" ;;
    esac
    # the group's position in $seen is its chunk - first seen, first chunk,
    # which keeps the deal stable for a given (sorted) file list
    idx=0
    # shellcheck disable=SC2086 # deliberate split: $seen is a space-joined list
    for s in $seen; do
      [ "$s" = "$top" ] && break
      idx=$((idx + 1))
    done
    printf '%s\0' "$f" >>"$out/chunk.$((idx % width))"
  done
  i=0
  while [ "$i" -lt "$width" ]; do
    [ -s "$out/chunk.$i" ] && printf '%s\n' "$i"
    i=$((i + 1))
  done
}

# _hi_shellcheck_all <log> <file...> - every file checked, concatenated into
# <log> in the order given. Non-zero when any file had findings, exactly as a
# single shellcheck over the whole list would be.
function _hi_shellcheck_all() {
  local log="$1" out width rc=0 i
  shift
  width="$(_hi_sc_width)"
  out="$_HI_WORKDIR/sc.out"
  rm -rf "$out"
  mkdir -p "$out"

  _hi_read_lines _HI_SC_CHUNKS < <(_hi_sc_chunks "$out" "$width" "$@")

  # one invocation per chunk, each writing its own file so concurrent findings
  # cannot interleave; replayed in chunk order once the batch is done
  # ($1 below expands in the child sh, which is the point - SC2016.)
  # shellcheck disable=SC2016
  printf '%s\0' ${_HI_SC_CHUNKS[@]+"${_HI_SC_CHUNKS[@]}"} |
    (cd "$out" && xargs -0 -n 1 -P "$width" \
      sh -c 'xargs -0 shellcheck -x -Calways -S style <"chunk.$1" >"out.$1" 2>&1' sh) || rc=$?

  : >"$log"
  for i in ${_HI_SC_CHUNKS[@]+"${_HI_SC_CHUNKS[@]}"}; do
    [ -s "$out/out.$i" ] && cat "$out/out.$i" >>"$log"
  done
  return "$rc"
}

function run_shellcheck() {
  # deliberately *not* _hi_require: every other suite skips cleanly when its
  # backend is missing, but this one is the lint gate - a missing shellcheck
  # means the check didn't run, which must not read as a pass.
  if ! command -v shellcheck >/dev/null 2>&1; then
    _hi_cecho "shellcheck is not installed" "$RED"
    exit 1
  fi

  # the .git/dist exclusions and why they are there live on _hi_lint_find,
  # which lint_home_default reads through too
  _hi_read_lines _HI_SH_FILES < <(_hi_lint_find -name '*.sh')
  _HI_LINT_TOTAL="${#_HI_SH_FILES[@]}"
  _HI_SKIPPED=0

  _hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
  _hi_h2 "Version: $(shellcheck --version | awk '/^version:/ {print $2}')"

  _hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$BLUE"

  # Before the fan-out, and fatal - not one of the halves below. A config-dir
  # source with no directive makes the very next step recurse into itself until
  # the kernel OOM-kills it, so a half that reports afterwards reports only when
  # there is nothing to report. Ordering is the whole value of this check.
  if ! lint_config_dir_sources; then
    _hi_cecho " | refusing to run shellcheck: the files above would make it" "$RED"
    _hi_cecho " | re-parse itself until the machine runs out of memory" "$RED"
    exit 1
  fi

  _hi_workdir shellchecktest
  _HI_SC_LOG="$_HI_WORKDIR/shellcheck.log"

  _HI_T0="$(_hi_now)"

  _HI_SC_FAILED=0
  _HI_SC_RC=0
  _hi_shellcheck_all "$_HI_SC_LOG" "${_HI_SH_FILES[@]}" || _HI_SC_RC=$?
  cat "$_HI_SC_LOG"
  if [ "$_HI_SC_RC" -ne 0 ]; then
    # -Calways leaves ANSI codes in $_HI_SC_LOG (needed for the colorized
    # output above), so they have to be stripped before "^In " can match
    _HI_SC_FAILED=$(sed 's/\x1b\[[0-9;]*m//g' "$_HI_SC_LOG" | grep -oE '^In .* line [0-9]+:' | sed -E 's/^In (.*) line [0-9]+:/\1/' | sort -u | wc -l)
    _hi_note_failure "shellcheck: $_HI_SC_FAILED file(s) with findings"
  fi

  _hi_h2 "Syntax-checking the files shellcheck can't parse"
  # One list, so a lint half is registered by adding its name here and nowhere
  # else. The old form paired a per-half counter with a nine-term sum on one
  # line, where forgetting the sum left that half's failures invisible while
  # the suite still went green - silent, which is the wrong way for a gate to
  # break. Each function prints its own _hi_h2 banner, so order is the running
  # order. Seeded with the shellcheck count from above.
  _HI_LINT_FAILED=$_HI_SC_FAILED
  for _hi_lint_half in lint_native lint_bash32 lint_home_default lint_shfmt \
    lint_checkbashisms lint_glossary_tags lint_settings_table \
    lint_dockerfiles lint_image_tags; do
    "$_hi_lint_half" || _HI_LINT_FAILED=$((_HI_LINT_FAILED + $?))
  done
  unset _hi_lint_half
  _hi_report_counts "$_HI_LINT_TOTAL" "$_HI_LINT_FAILED" "$_HI_SKIPPED"

  local skipped=""
  [ "$_HI_SKIPPED" -gt 0 ] && skipped=", $_HI_SKIPPED skipped"
  if [ "$_HI_LINT_FAILED" -eq 0 ]; then
    _hi_h1 "Found no issues ($_HI_LINT_TOTAL files$skipped, $(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$BRGREEN"
  else
    _hi_h1 "Found issues: $_HI_LINT_FAILED/$_HI_LINT_TOTAL files$skipped ($(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$RED"
    exit "$_HI_LINT_FAILED"
  fi
}

run_shellcheck
