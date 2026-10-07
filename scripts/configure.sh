#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The settings wizard behind `hi --configure` (and the second half of a plain
# install): one flat menu of every setting under a live preview, and the one
# write to $_HI_SETTINGS. Sourced by scripts/install.sh after
# common/core.sh and scripts/table.sh; not an entry point of its own.
# run_configure at the bottom is the sequence. The live previews are
# configure_preview.sh and the menu configure_menu.sh, each sourced from here
# where it sat.
#
# The shape: every answer taken this run lands in _HI_SETTING_PENDING (as
# "<var>=<value>", an empty value meaning "the shipped default"), ahead of
# what the file still says from last time; setting_value is the one reader
# of both. Nothing accumulates lines as it asks - a setting can be changed
# twice, so the `export NAME=value` lines are derived once, at save time, by
# collect_setting_lines walking a fixed roster in a stable order, and
# config_shell writes them in one call (it rewrites the *whole* marker block
# in its target, so one call per setting would each wipe the others').
# Interactively that save is the menu's [s]; [q] writes nothing at all. With
# no tty, or under --preset, there is no menu: the roster is collected from
# the file (plus the preset) and written as it stands.

# The live previews borrow header.sh's hi_header/banner/full_check and
# git_prompt.sh's segment. Sourced on first use rather than up top:
# --uninstall and packaging mode never
# render one, and never need $_HI_HEADER_ORDER_DEFAULT either.
function _hi_load_preview_sources() {
  [ -n "${_hi_previews_loaded:-}" ] && return 0
  _hi_previews_loaded=1
  # shellcheck source=../common/header.sh
  source "$_HI_HEADER"
  # shellcheck source=../common/git_prompt.sh
  source "$_HI_GIT_PROMPT"
  # shellcheck source=../common/env_prompt.sh
  source "$_HI_ENV_PROMPT"
}

# Answers this run has already taken, as "<var>=<value>" entries. An indexed
# array rather than `declare -A`: associative arrays are bash 4 and macOS
# ships 3.2. A linear scan over a few dozen answers costs nothing.
_HI_SETTING_PENDING=()

# pending_answer <var> [outvar] - this run's answer for <var>, or rc 1
function pending_answer() {
  local _hi_pa_entry
  for _hi_pa_entry in ${_HI_SETTING_PENDING[@]+"${_HI_SETTING_PENDING[@]}"}; do
    [ "${_hi_pa_entry%%=*}" = "$1" ] || continue
    _hi_out "${2:-}" "${_hi_pa_entry#*=}"
    return 0
  done
  return 1
}

# _hi_pending_set <var> <value> - record an answer, replacing an earlier one
# for the same var in place: a section opened twice must not leave two
# entries for pending_answer's first-match scan to disagree over.
function _hi_pending_set() {
  local i
  for i in ${_HI_SETTING_PENDING[@]+"${!_HI_SETTING_PENDING[@]}"}; do
    [ "${_HI_SETTING_PENDING[$i]%%=*}" = "$1" ] || continue
    _HI_SETTING_PENDING[i]="$1=$2"
    return 0
  done
  _HI_SETTING_PENDING+=("$1=$2")
}

# setting_value <var> <target> [outvar] - what $var is set to right now: this
# run's answer if it has one, otherwise the line in $2 (a tiny file, re-read
# per question behind an interactive prompt - not worth a cache that every
# write path would have to remember to clear). Empty when neither has it.
function setting_value() {
  local _hi_sv_var="$1" _hi_sv_target="$2" _hi_sv_val=""
  # scripts/lib.sh's reader, which knows config_shell's marker-padded spelling
  pending_answer "$_hi_sv_var" _hi_sv_val ||
    _hi_setting_get "$_hi_sv_target" "$_hi_sv_var" _hi_sv_val || _hi_sv_val=""
  _hi_out "${3:-}" "$_hi_sv_val"
}

# true if $1 is turned off: its value is $3. hi's own _HI_DISABLE_* vars use 1
# for "off"; common/header.sh's per-line toggles use 0, hence the argument.
function setting_off() {
  local var="$1" target="$2" off="${3:-1}" answer
  setting_value "$var" "$target" answer
  [ "$answer" = "$off" ]
}

# true if $1 is on. Two shapes of setting share this: a default-on toggle is
# on unless its value is <off> ($3), and an opt-in - one whose on-value <on>
# ($4) has to be written out, like _HI_DISABLE_LEAD_SPACE=1 - is on only when its
# value *is* that.
function setting_on() {
  local var="$1" target="$2" off="${3:-1}" on="${4:-}" answer
  setting_value "$var" "$target" answer
  if [ -n "$on" ]; then
    [ "$answer" = "$on" ]
  else
    [ "$answer" != "$off" ]
  fi
}

# _hi_setting_flip <var> <off> <on> <outvar> - turn a setting the other way
# and record it: a default-on toggle turned off gets its off-value, turned on
# gets "" (the default, nothing written); an opt-in turned on gets its
# on-value, turned off gets "". <outvar> gets the new state, on or off - an
# outvar rather than stdout, since a `$( )` around this would record the
# answer in a subshell and lose it.
function _hi_setting_flip() {
  local var="$1" off="$2" on="$3" want=on
  setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && want=off
  if [ "$want" = on ]; then
    _hi_pending_set "$var" "$on"
  elif [ -n "$on" ]; then
    _hi_pending_set "$var" ""
  else
    _hi_pending_set "$var" "$off"
  fi
  printf -v "$4" '%s' "$want"
}

# ask_setting_value <var> <default> <validator-fn> <invalid-msg> <question> -
# ask_value against a setting, recorded. The whole shape of every free-text
# question here: this run's answer (or the file's) is the current value, and
# the reply goes back into the pending set.
function ask_setting_value() {
  local _hi_asv_cur=""
  setting_value "$1" "$_HI_SETTINGS" _hi_asv_cur
  _hi_pending_set "$1" "$(ask_value "$5" "$_hi_asv_cur" "$2" "$3" "$4")"
}

# _hi_shell_var <outvar> <shell> - the uppercase half of a $_HI_PROMPT_END_<SHELL>
# name. _HI_RC_TABLE carries the shell lowercase and the setting is spelled
# uppercase; bash 3.2 has no ${x^^}, so one `tr` for all three callers.
function _hi_shell_var() {
  printf -v "$1" '%s' "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
}

# ask_value <question> <current> <default> <validator-fn> <invalid-msg> -
# one free-text prompt, printed value on stdout: entering nothing keeps
# <current> (or the default when there is no override yet), a rejected answer
# says why and keeps it too, and an answer equal to <default> comes back
# empty - the caller records nothing rather than restating a shipped default.
# Non-interactive runs keep what is configured rather than hanging on a
# prompt nobody can answer. The messages go to stderr: stdout is the
# captured answer.
function ask_value() {
  local question="$1" current="$2" default="$3" validate="$4" invalid_msg="$5"
  local value reply="" shown
  value="${current:-$default}"
  if [ -t 0 ]; then
    _hi_paint shown "$BRPURPLE" "[$value]"
    read -r -p " $question $shown " reply || reply=""
    if [ -n "$reply" ]; then
      if "$validate" "$reply"; then
        value="$reply"
      else
        _hi_cecho " $invalid_msg, leaving it at $value" "$YELLOW" >&2
      fi
    fi
  fi
  [ "$value" = "$default" ] && value=""
  printf '%s' "$value"
}

# _hi_preset_list <table> <width> - a presets table as its pick lists it:
# the name with its hotkey, padded to <width> by its visible length (a
# printf width would count the key's escapes), then the description
function _hi_preset_list() {
  local row name desc shown
  local -a rows
  _hi_prompt_rows "$1" rows
  for row in "${rows[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    _hi_hotkey "$name" "${name:0:1}" shown
    _hi_pad_to shown $(($2 - 2)) "$shown"
    printf '   %s %b%s%b\n' "$shown" "$BLUE" "$desc" "$NC"
  done
}

# menu_read <prompt> <outvar> - one menu answer: trimmed, lower-cased (tr,
# not ${x,,}: that is bash 4), inner runs of spaces squeezed so "up  3" and
# "up 3" are the same command. Returns 1 on EOF - a closed pipe, ^D, or a
# driver that ran out of input - after closing the line `read -p` left the
# cursor on. EOF is never an answer; each loop decides what it means.
function menu_read() {
  local _hi_mr_reply=""
  if ! read -r -p "$1" _hi_mr_reply; then
    printf '\n' >&2
    return 1
  fi
  _hi_mr_reply="$(printf '%s' "$_hi_mr_reply" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"
  _hi_mr_reply="${_hi_mr_reply# }"
  _hi_mr_reply="${_hi_mr_reply% }"
  printf -v "$2" '%s' "$_hi_mr_reply"
}

# _hi_menu_reject <counter-var> <max> <hint> - increments <counter-var> by
# name; true, with <hint> printed, while still under <max> - every call site
# follows it with `continue`. False, nothing printed, at the limit, for the
# caller's own exceeded-message and exit (`return 0` or `break` differ by
# site, so that much stays local). This is the one guarantee that no menu can
# hang on a driver out of sensible input, kept once for every call site.
function _hi_menu_reject() {
  printf -v "$1" '%s' "$((${!1} + 1))"
  [ "${!1}" -lt "$2" ] || return 1
  _hi_menu_say "$3" "$YELLOW"
}

# The value validators are scripts/lib.sh's (_hi_is_width and the rest):
# doctor judges a hand-written settings.sh by the same rules the menu takes
# an answer by. Only the two that need the menu's own state live here.

# a settings.sh value has to survive being written into a single-quoted export
function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

function _hi_is_truecolor_choice() {
  case "$1" in auto | on | off) ;; *) return 1 ;; esac
}

# _hi_is_header_word <word> - one of $_HI_HEADER_ORDER's vocabulary, off
# header.sh's own list, which the menu loads on first use
function _hi_is_header_word() {
  _hi_load_preview_sources
  _hi_is_header_order "$1"
}

# the live previews the questions draw
# shellcheck source=./configure_preview.sh
source "$_HI_ROOT/scripts/configure_preview.sh"

# Who draws one shell's prompt: auto, hi, or a program that fits it, asked by
# number or name and written back into $_HI_PROMPT_TOOL as <shell>:<choice>
# entries - `hi` alone for the shells that share it, nothing for auto
function config_prompt_tool() {
  local cur="" r sh choice fits="" reply w rejects=0 out="" hi_too=0 auto=0
  local -a all=() picks=()
  setting_value _HI_PROMPT_TOOL "$_HI_SETTINGS" cur
  _hi_prompt_choice "$1" "$cur" choice
  for w in $_HI_PROMPT_TOOLS; do
    _hi_prompt_row "$w" r
    r="${r#*|}"
    case " ${r%%|*} " in *" $1 "*) fits="$fits $w" ;; esac
  done
  # shellcheck disable=SC2206 # space-separated words, no globs
  all=(auto hi $fits)
  while [ -t 0 ]; do
    show_preview _hi_prompt_tool_preview "$1" "$choice"
    _hi_paint w "$BRPURPLE" "[$choice]"
    menu_read " Who draws the $1 prompt, by number or name? $w " reply || break
    [ -n "$reply" ] || break
    case "$reply" in *[!0-9]* | 0*) ;; *) ((reply > ${#all[@]})) || reply="${all[reply - 1]}" ;; esac
    case " ${all[*]} " in
    *" $reply "*)
      choice="$reply"
      break
      ;;
    esac
    _hi_menu_reject rejects 3 "no choice $reply - type a number or a name from the list" && continue
    break
  done
  for r in "${_HI_SHELL_TABLE[@]}"; do
    sh="${r%%|*}" w="$choice"
    [ "$sh" = "$1" ] || _hi_prompt_choice "$sh" "$cur" w
    case "$w" in auto) auto=1 ;; hi) hi_too=1 ;; esac
    picks+=("$sh:$w")
  done
  # plain `hi` stands for every shell that says hi, where no shell is auto
  for w in "${picks[@]}"; do
    case "$w" in
    *:auto) ;;
    *:hi) if ((auto)); then out="$out $w"; fi ;;
    *) out="$out $w" ;;
    esac
  done
  ((auto || ! hi_too)) || out="$out hi"
  out="${out# }"
  _hi_pending_set _HI_PROMPT_TOOL "$out"
  _hi_menu_note " $1 prompt: $choice" "$GREEN"
}

# _hi_package_group_notes - "<group>|<note>" for each group of $_HI_PACKAGES:
# the first sentence of the comment right above its first table, else the
# first packages it lists
function _hi_package_group_notes() {
  [ -f "${_HI_PACKAGES:-}" ] || return 0
  awk '
    function flush() { if (g != "") print g "|" (note != "" ? note : eg); g = "" }
    /^[ \t]*#/ { c = $0; sub(/^[ \t]*#[ \t]*/, "", c); com = com == "" ? c : com " " c; next }
    /^[ \t]*\[/ {
      t = $0; sub(/^[ \t]*\[/, "", t); sub(/\].*/, "", t); sub(/\.(required|unwanted)$/, "", t)
      flush()
      if (!(t in seen)) { seen[t] = 1; g = t; eg = ""; note = com; sub(/\. .*/, "", note); sub(/\.$/, "", note) }
      com = ""; next
    }
    { com = "" }
    g != "" && /=/ && length(eg) < 60 { p = $0; sub(/[ \t]*=.*/, "", p); gsub(/^[ \t]+|"/, "", p); eg = eg == "" ? p : eg ", " p }
    END { flush() }
  ' "$_HI_PACKAGES"
}

# _hi_ask_item <outvar> <n> <1|0> <name> <width> - one numbered checkbox,
# "NN) [x] name" with the name padded to <width>
function _hi_ask_item() {
  local _hi_ai_n _hi_ai_x _hi_ai_w
  _hi_pad_to _hi_ai_n 2 "$2" right
  if [ "$3" = 1 ]; then _hi_paint _hi_ai_x "$BRGREEN" "[x]"; else _hi_paint _hi_ai_x "$RED" "[ ]"; fi
  _hi_pad_to _hi_ai_w "$5" "$4"
  printf -v "$1" '%b%s)%b %s %s' "$BRYELLOW" "$_hi_ai_n" "$NC" "$_hi_ai_x" "$_hi_ai_w"
}

# Every line collect_setting_lines decides on, written to $_HI_SETTINGS in
# one go by run_configure. An ordered array, because config_shell compares
# what it would write against what is there to decide whether the file is up
# to date - so the write order has to be stable across runs.
declare -a _HI_SETTING_LINES=()

# The yes/no settings as tables, one row per setting, in the order they are
# listed and written: <var>|<off-value>|<on-value>|<preview-fn>|<needs>|
# <label>. <on-value> is empty for a default-on toggle (off writes the
# off-value, on writes nothing) and set for an opt-in (on writes it, off
# writes nothing) - setting_on has the rule. <preview-fn> is boxed under the
# menu after the row flips, for what the menu's own preview does not show.
# <needs> names a command the setting is moot without (`a/b` for either of
# two): the menu says so beside it. <label> is the menu's name for it, and its
# part before " - " is what the flip reports. banner is the header's one row
# with a hide switch of its own: it is not part of $_HI_HEADER_ORDER's
# reorderable list (it always leads). The prompt's switch, off altogether, is
# a feature toggle, and so in every preset's vocabulary. The advanced items
# are the ones most installs never touch, listed last.
#
# _hi_settings_load fills them from scripts/settings, whose rows with a
# <label> in the feature, header, prompt, and advanced sections are these
# items, so adding a setting is one row there.
_HI_FEATURE_PROMPTS=() _HI_HEADER_PROMPTS=() _HI_PROMPT_PROMPTS=() _HI_ADVANCED_PROMPTS=()
function _hi_settings_load() {
  local line sec name item col i
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    # <section> | <name> | <default> | <off> | <on> | <preview> | <needs> | <label> | ...
    sec="${line%% | *}" line="${line#* | }"
    name="${line%% | *}" line="${line#* | }"
    line="${line#* | }"
    item="$name"
    for i in 1 2 3 4 5; do
      col="${line%% | *}" line="${line#* | }"
      [ "$col" != - ] || col=""
      item="$item|$col"
    done
    [ -n "$col" ] || continue
    case "$sec" in
    feature) _HI_FEATURE_PROMPTS+=("$item") ;;
    header) _HI_HEADER_PROMPTS+=("$item") ;;
    prompt) _HI_PROMPT_PROMPTS+=("$item") ;;
    advanced) _HI_ADVANCED_PROMPTS+=("$item") ;;
    esac
  done <"$_HI_ROOT/scripts/settings"
}
_hi_settings_load

# _hi_prompt_rows <table-name> <outvar-array> - the table copied out by name
# through eval rather than `local -n rows="$1"`: namerefs are bash 4.3 and
# macOS ships bash 3.2. The ${a[@]+"${a[@]}"} guard one eval deeper: an empty
# table would otherwise be an "unbound variable" on bash 3.2 rather than
# nothing to ask.
function _hi_prompt_rows() {
  eval "$2=(\${$1[@]+\"\${$1[@]}\"})"
}

# <name>|<one-line description>|<var=value ...>: a starting point for the
# feature, header, package-check, and prompt settings - the presets say
# nothing about the header order, the advanced section, the width, or the
# separators. A var the preset does not name goes back to its shipped
# default, so a preset is an absolute answer rather than a delta on what the
# file holds. Applied, its answers are what the menu shows and saves;
# `--preset <name>` writes them without a hub at all.
_HI_PRESETS=(
  "everything|the shipped defaults - every feature and header item on, the alias opt-ins off|"
  "balanced|everything but the noise: a shorter package check|_HI_PACKAGES_GROUPS=core,deprecated"
  "minimal|on targets only the colored prompt - no header, git status, or editors; nothing at all on this machine|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_PLUGINS_OFF=editors _HI_DISABLE_LOCAL=1"
  "lean|minimal, and nothing of yours rides: hi's own prompt, no plugin's config, ssh the only backend|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_PLUGINS_OFF=editors,cli,mux,shell,prompt _HI_DISABLE_LOCAL=1 _HI_PROMPT_TOOL=hi _HI_BACKENDS_OFF=all"
)

# every variable a preset answers for: the feature and header yes/no tables,
# plus the two lists - so "not named by the preset" can mean "back to the
# default". _HI_PROMPT_TOOL (hi's prompt) stays out, like the color scheme and the
# packages ramp: those are taste, not a feature level, and no preset resets
# them. Neither is asked here at all - both are written into settings.sh by
# hand (GLOSSARY: HI.50). A preset may still name a variable outside this
# vocabulary, as `lean` does _HI_PROMPT_TOOL and _HI_BACKENDS_OFF: that one
# is set, and no other preset changes it back.
function _hi_preset_vocab() {
  local row
  for row in "${_HI_FEATURE_PROMPTS[@]}" "${_HI_HEADER_PROMPTS[@]}"; do
    printf '%s\n' "${row%%|*}"
  done
  # the one feature toggle listed under Prompt rather than Features
  printf '%s\n' _HI_DISABLE_PROMPT _HI_PACKAGES_GROUPS _HI_PLUGINS_OFF
}

# preset_row <name> - its table row, or failure for a name that is not one
# The three helpers take an optional table name so the header presets can use
# them too: _HI_HEADER_PRESETS is the same `name|desc|payload` shape, so
# config_header_preset shares the listing, the row lookup, and the
# first-letter match - with its ambiguity guard and exact-name-first order -
# rather than carrying a third copy.
function preset_row() {
  local row
  local -a _hi_pr_rows
  _hi_prompt_rows "${2:-_HI_PRESETS}" _hi_pr_rows
  for row in "${_hi_pr_rows[@]}"; do
    [ "${row%%|*}" = "$1" ] && {
      printf '%s' "$row"
      return 0
    }
  done
  return 1
}

function preset_names() {
  local row out=""
  local -a _hi_names_rows
  _hi_prompt_rows "${1:-_HI_PRESETS}" _hi_names_rows
  for row in "${_hi_names_rows[@]}"; do out="$out${out:+ }${row%%|*}"; done
  printf '%s' "$out"
}

# preset_shorthand <letter> - the one preset whose name starts with <letter>,
# or failure for anything but a single character or a letter two names share.
# Ambiguous or unknown falls through to preset_row's own "no such preset"
# error rather than guessing, so a typo still gets the full name list back.
function preset_shorthand() {
  local row name hit="" hits=0
  local -a _hi_ps_rows
  [ "${#1}" -eq 1 ] || return 1
  _hi_prompt_rows "${2:-_HI_PRESETS}" _hi_ps_rows
  for row in "${_hi_ps_rows[@]}"; do
    name="${row%%|*}"
    if [ "${name:0:1}" = "$1" ]; then
      hit="$name"
      hits=$((hits + 1))
    fi
  done
  [ "$hits" -eq 1 ] || return 1
  printf '%s' "$hit"
}

# apply_preset <name> - seed this run's answers with the preset's, one per
# vocabulary variable (empty for "the default"), so the menu starts there and
# a --preset run writes exactly the preset.
function apply_preset() {
  local row values var value pair vocab extra=""
  row="$(preset_row "$1")" || {
    _hi_cecho " no such preset: $1 (one of: $(preset_names))" "$RED" >&2
    return 1
  }
  values="${row##*|}"
  while IFS= read -r var; do
    value=""
    # shellcheck disable=SC2086 # the split is the point: one var=value a word
    for pair in $values; do
      [ "${pair%%=*}" = "$var" ] && value="${pair#*=}"
    done
    _hi_pending_set "$var" "$value"
  done < <(_hi_preset_vocab)
  vocab=" $(_hi_preset_vocab | tr '\n' ' ')"
  # shellcheck disable=SC2086
  for pair in $values; do
    case "$vocab" in *" ${pair%%=*} "*) continue ;; esac
    _hi_pending_set "${pair%%=*}" "${pair#*=}"
    extra="$extra${extra:+, }${pair%%=*}"
  done
  _hi_cecho " starting from the '$1' preset" "$GREEN"
  [ -z "$extra" ] || _hi_cecho " it also sets $extra, which no other preset changes back" "$BLUE"
}

# config_first_install - all an install asks a terminal, and only while
# there is no settings.sh: whether hi styles this machine as well as the
# hosts it connects to. The menu is hi --configure's.
function config_first_install() {
  local reply=""
  if [ -f "$_HI_SETTINGS" ]; then
    _hi_cecho " your settings stay as they are - hi --configure changes them" "$GREEN"
    return 0
  fi
  menu_read " Style this machine's own shells too, not only the hosts you hi to? [Y/n] " reply || reply=""
  case "$reply" in
  n | no) _hi_pending_set _HI_DISABLE_LOCAL 1 ;;
  esac
  _hi_cecho " hi --configure has every other setting" "$BLUE"
}

# The menu's [p]: pick a preset to start from, or Enter to leave things as
# they are. One shot, not a loop - a typo gets the name list back and the
# menu comes round again.
function config_preset() {
  [ -t 0 ] || return 0
  local reply="" short
  _hi_h2 "Starting point"
  _hi_cecho " A preset answers the feature and header settings at once; change any of them after." "$BLUE"
  _hi_preset_list _HI_PRESETS 13
  menu_read " Start from a preset? (the bracketed letter or the full name; Enter keeps your current settings) [keep] " reply || return 0
  [ -n "$reply" ] || return 0
  short="$(preset_shorthand "$reply")" && reply="$short"
  apply_preset "$reply" || return 0
  return 0
}

# What a run is about to do, said once up front: how the menu works, where
# the answers go, and that nothing is written until `s` - so ^C or `q` at
# any point leaves settings.sh exactly as it was. Interactive only; a run
# with no tty has nobody to orient.
function configure_intro() {
  [ -t 0 ] || return 0
  local state="none yet - defaults apply" file="$_HI_SETTINGS"
  # no `|| echo 0`: grep -c already prints 0 on no match, then exits 1
  [ -f "$_HI_SETTINGS" ] && state="$(grep -cF "$_HI_MARKER" "$_HI_SETTINGS" 2>/dev/null) setting(s) stored"
  case "$file" in "$HOME"/*) file="~${file#"$HOME"}" ;; esac
  _hi_menu_cols _HI_MENU_W
  _hi_menu_say "The preview shows a session at your current settings. A section's letter opens its page, [b] comes back; a number flips a setting or asks for its value, from any page." "$BLUE"
  _hi_menu_say "Nothing is written until you save with [s]; [q] leaves the file untouched." "$BLUE"
  _hi_menu_say "settings: $file ($state)" "$BLUE"
}

# the menu: its pages, the hub, the header editor, and the group and plugin flips
# shellcheck source=./configure_menu.sh
source "$_HI_ROOT/scripts/configure_menu.sh"

# Which addresses the header's ip cell leaves out - header.sh's
# _hi_ip_filter reads it. `172.*` is the shipped default (the docker/podman
# bridge range), so typing it clears the override the way config_max_width's
# 80 does; `none` shows every address.
function config_ip_hide() {
  ask_setting_value _HI_IP_HIDE '172.*' _hi_is_ip_hide "answer none, or globs like 172.* 10.0.*" \
    "Hide which addresses from the ip cell (globs, space-separated, or none)?"
}

# Ask for the header/banner's terminal width. Entering 80 (common/core.sh's
# own built-in default, via ${_HI_MAX_WIDTH:-80}) clears the override instead
# of writing it out.
function config_max_width() {
  ask_setting_value _HI_MAX_WIDTH 80 _hi_is_width "a number, 40 or more" \
    "Terminal width for the header/banner (40 or more)?"
}

# config_prompt_end <shell> - the character <shell>'s prompt ends with. The
# shipped default comes from core.sh's _hi_prompt_end_default rather than
# being spelled here a second time; entering it clears the override, as
# config_max_width does with 80. Values are single-quoted on the way out (a
# separator is as likely to be `$` as a letter), so `'` itself is refused.
function config_prompt_end() {
  local shell
  _hi_shell_var shell "$1"
  ask_setting_value "_HI_PROMPT_END_$shell" "$(_hi_prompt_end_default "$shell")" \
    _hi_has_no_single_quote "a single quote can't be written to settings.sh" \
    "Character to end the $1 prompt with?"
}

# The 24-bit color verdict. It keeps its current value on Enter and clears
# the override when the answer is the shipped default, like config_max_width.
#
# $_HI_TRUECOLOR is an unset/1/0 flag asked in words: "1" is a fact about the
# implementation rather than an answer, so the words map in on the way to the
# question and back out on the way to the file. `on` is the answer under tmux,
# which hides COLORTERM. Glyphs are not asked at all - the locale
# decides, and the client ships its verdict to the session (docs/SETTINGS.md's
# _Not settings_).
function config_truecolor() {
  local current value choice
  setting_value _HI_TRUECOLOR "$_HI_SETTINGS" current
  case "$current" in 1) choice=on ;; 0) choice=off ;; *) choice="" ;; esac
  value="$(ask_value "24-bit color for a scheme's hex: auto (by COLORTERM), on (under tmux, say), or off?" \
    "$choice" auto _hi_is_truecolor_choice "answer auto, on, or off")"
  case "$value" in on) value=1 ;; off) value=0 ;; *) value="" ;; esac
  _hi_pending_set _HI_TRUECOLOR "$value"
}

# The roster, walked once at save time: every setting the wizard writes, in
# the order its line lands in settings.sh. A yes/no row writes its off-value
# when off (a default-on toggle) or its on-value when on (an opt-in) and
# nothing otherwise; a value writes when it is set and is not the shipped
# default - ask_value already blanks a typed default, and this applies the
# same rule to what the file held. Nothing is dropped for being moot: a
# header order stored while the header is off is there again when it comes
# back on.
function _hi_collect_group() {
  local row var off on rest
  local -a rows=()
  _hi_prompt_rows "$1" rows
  for row in ${rows[@]+"${rows[@]}"}; do
    IFS='|' read -r var off on rest <<<"$row"
    if [ -n "$on" ]; then
      setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && _HI_SETTING_LINES+=("export $var=$on")
    else
      setting_on "$var" "$_HI_SETTINGS" "$off" || _HI_SETTING_LINES+=("export $var=$off")
    fi
  done
}

# _hi_collect_value <var> <default> [quoted] - one value line, or none. A
# value holding whitespace is quoted whether or not the caller asked: the
# line has to parse as sh and fish both, and a bare word is the only form
# that does so unquoted.
function _hi_collect_value() {
  local var="$1" default="$2" quoted="${3:-}" value=""
  setting_value "$var" "$_HI_SETTINGS" value
  [ -n "$value" ] && [ "$value" != "$default" ] || return 0
  case "$value" in *[[:space:]]*) quoted=1 ;; esac
  if [ -n "$quoted" ]; then
    _HI_SETTING_LINES+=("export $var='$value'")
  else
    _HI_SETTING_LINES+=("export $var=$value")
  fi
}

function collect_setting_lines() {
  local row name shell
  _hi_load_preview_sources
  _HI_SETTING_LINES=()
  _hi_collect_group _HI_HEADER_PROMPTS
  _hi_collect_value _HI_HEADER_ORDER "$_HI_HEADER_ORDER_DEFAULT" quoted
  _hi_collect_value _HI_PACKAGES_GROUPS "$_HI_PACKAGES_GROUPS_DEFAULT" quoted
  _hi_collect_value _HI_PACKAGES_PALETTE ""
  _hi_collect_value _HI_COLOR_SCHEME ""
  _hi_collect_value _HI_IP_HIDE '172.*' quoted
  _hi_collect_value _HI_MAX_WIDTH 80
  _hi_collect_group _HI_FEATURE_PROMPTS
  _hi_collect_value _HI_PLUGINS_OFF "" quoted
  _hi_collect_value _HI_PLUGINS_ON "" quoted
  _hi_collect_group _HI_PROMPT_PROMPTS
  _hi_collect_value _HI_PROMPT_TOOL ""
  _hi_collect_value _HI_BACKENDS_OFF "" quoted
  for row in "${_HI_SHELL_TABLE[@]}"; do
    name="${row%%|*}"
    _hi_shell_var shell "$name"
    _hi_collect_value "_HI_PROMPT_END_$shell" "$(_hi_prompt_end_default "$shell")" quoted
  done
  _hi_collect_group _HI_ADVANCED_PROMPTS
  _hi_collect_value _HI_TRUECOLOR ""
}

# A line written by hand - `export _HI_COLOR_SCHEME=...` with no marker, the
# way SETTINGS.md says to set a scheme of your own - is read by
# setting_value (it sources the file) and then written again as a marker
# line, and the two then survive every later run. Adopted instead: for every
# name this run writes, the un-marked line goes and the marker line carries
# its value. A hand line for a name this run does not write stays as it is.
function settings_adopt_hand_lines() {
  local line name
  [ -f "$_HI_SETTINGS" ] || return 0
  for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
    name="${line#export }"
    name="${name%%=*}"
    grep -v -F "$_HI_MARKER" "$_HI_SETTINGS" |
      grep -qE "^[[:space:]]*(export[[:space:]]+)?$name=" || continue
    dry_run_say "adopt the hand-written $name line in $_HI_SETTINGS" && continue
    _hi_rewrite "$_HI_SETTINGS" \
      "/^[[:space:]]*\\(export[[:space:]]\\{1,\\}\\)\\{0,1\\}$name=/{/$_HI_MARKER/!d;}"
    _hi_cecho " adopted your hand-written $name line into the settings block" "$BLUE"
  done
}

# $_HI_SETTINGS is hi's own file, not one of the user's rc files, and it
# holds nothing but `export NAME=value` lines - so it gets a real `#!/bin/sh`
# line 1, which every shell that sources it (sh, bash, zsh, fish) reads as a
# comment and which lets editors, `file`, and shellcheck see a POSIX sh script
# rather than an anonymous fragment. Any other shebang is replaced rather than
# left alongside: dash and fish both source this, so sh is the only correct one.
# config_shell rewrites only its own marker-tagged block, so this line stays.
function ensure_settings_shebang() {
  local shebang='#!/bin/sh' first="" tmpfile
  if [ -f "$_HI_SETTINGS" ]; then
    IFS= read -r first <"$_HI_SETTINGS" || first=""
  fi
  [ "$first" = "$shebang" ] && return 0
  dry_run_say "put $shebang on line 1 of $_HI_SETTINGS" && return 0

  mkdir -p "$(dirname "$_HI_SETTINGS")"
  tmpfile="$(mktemp -t hi.settings.XXXXXX)"
  printf '%s\n' "$shebang" >"$tmpfile"
  if [ -f "$_HI_SETTINGS" ]; then
    case "$first" in
    '#!'*) tail -n +2 "$_HI_SETTINGS" >>"$tmpfile" ;;
    *) cat "$_HI_SETTINGS" >>"$tmpfile" ;;
    esac
  fi
  _hi_write_back "$tmpfile" "$_HI_SETTINGS"
}

# What this run changed, as +/- lines against the block settings.sh held
# before it: a diff of the two line sets rather than of the file, since
# config_shell rewrites the block in a stable order and a moved line is not a
# change. Read before config_shell writes; printed after, so the report sits
# beside the "updated" line it explains.
function settings_diff_before() {
  local line
  _HI_SETTINGS_BEFORE=()
  [ -f "$_HI_SETTINGS" ] || return 0
  while IFS= read -r line; do
    line="${line%"$_HI_MARKER"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] && _HI_SETTINGS_BEFORE+=("$line")
  done < <(grep -F "$_HI_MARKER" "$_HI_SETTINGS" || true)
}

# _hi_in_list <needle> <haystack...> - is <needle> one of the rest?
function _hi_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

function settings_diff_report() {
  local line other changes=0
  for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
    [ -n "$line" ] || continue
    _hi_in_list "$line" ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"} || {
      _hi_cecho "   + $line" "$GREEN"
      changes=$((changes + 1))
    }
  done
  for other in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
    _hi_in_list "$other" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"} || {
      _hi_cecho "   - $other (back to the default)" "$YELLOW"
      changes=$((changes + 1))
    }
  done
  [ "$changes" = 0 ] && _hi_cecho "   no changes" "$GREEN"
  return 0
}

# The sequence, then the one write. $1 is a preset name, or empty: with one,
# its answers are taken as final and the hub never opens - what a run with no
# tty gets as well, minus the preset. `q` at the hub returns without writing
# and leaves _HI_CONFIGURE_QUIT set for install.sh's closing line to read.
function run_configure() {
  local preset="${1:-}"
  _HI_CONFIGURE_QUIT=""
  _hi_load_preview_sources
  # the menu's own instructions, for the runs that can open it
  [ -z "$preset" ] && [ -z "${_HI_FEATURES_ONLY:-}" ] || configure_intro
  if [ -n "$preset" ]; then
    apply_preset "$preset" || return 1
  elif [ -t 0 ] && [ -z "${_HI_FEATURES_ONLY:-}" ]; then
    config_first_install
  elif [ -t 0 ]; then
    config_hub
  elif [ -n "${_HI_FEATURES_ONLY:-}" ]; then
    # the menu is this run's whole job, and there is nobody to answer it
    _hi_cecho " ${_HI_ME:-hi --configure}: no terminal for the menu - --preset <name> answers it without one (one of: $(preset_names))" "$RED" >&2
    return 1
  else
    _hi_cecho " no terminal for the settings menu - the defaults apply; hi --configure at a terminal, or --preset <name>, sets them" "$YELLOW"
  fi
  if [ -n "$_HI_CONFIGURE_QUIT" ]; then
    _hi_cecho " nothing written - $_HI_SETTINGS is as it was" "$GREEN"
    return 0
  fi
  collect_setting_lines
  # No terminal, no preset, no file, and nothing to say: a settings.sh with
  # only a shebang in it would be a decision record with no decision in it.
  if [ ! -t 0 ] && [ -z "$preset" ] && [ ! -f "$_HI_SETTINGS" ] && ((${#_HI_SETTING_LINES[@]} == 0)); then
    _hi_cecho " nothing to write - the defaults apply until hi --configure is run at a terminal" "$GREEN"
    return 0
  fi
  settings_adopt_hand_lines
  ensure_settings_shebang
  settings_diff_before
  # ${a[@]+"${a[@]}"}, not a plain "${a[@]}": on bash 3.2 (macOS) expanding
  # an *empty* array under `set -u` is a fatal "unbound variable", and
  # every setting at its default leaves exactly that - no lines to write.
  config_shell settings "$_HI_SETTINGS" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"} || return 1
  settings_diff_report
}
