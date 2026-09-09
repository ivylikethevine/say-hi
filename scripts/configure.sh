#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The settings wizard behind `hi --configure` (and the second half of a plain
# install): a hub menu over a live preview, one section per menu item, and
# the one write to $_HI_SETTINGS. Sourced by scripts/install.sh after
# common/core.sh and scripts/table.sh; not an entry point of its own.
# run_configure at the bottom is the sequence.
#
# The shape: every answer taken this run lands in _HI_SETTING_PENDING (as
# "<var>=<value>", an empty value meaning "the shipped default"), ahead of
# what the file still says from last time; setting_value is the one reader
# of both. Nothing accumulates lines as it asks - a section can be opened
# twice, so the `export NAME=value` lines are derived once, at save time, by
# collect_setting_lines walking a fixed roster in a stable order, and
# config_shell writes them in one call (it rewrites the *whole* marker block
# in its target, so one call per section would each wipe the others').
# Interactively that save is the hub's [s]; [q] writes nothing at all. With
# no tty, or under --preset, there is no hub: the roster is collected from
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
}

# Answers this run has already taken, as "<var>=<value>" entries. An indexed
# array rather than `declare -A`: associative arrays are bash 4 and macOS
# ships 3.2. A linear scan over a few dozen answers costs nothing.
_HI_SETTING_PENDING=()

function pending_answer() {
  local entry
  for entry in ${_HI_SETTING_PENDING[@]+"${_HI_SETTING_PENDING[@]}"}; do
    [ "${entry%%=*}" = "$1" ] || continue
    printf '%s' "${entry#*=}"
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
  if ! _hi_sv_val="$(pending_answer "$_hi_sv_var")"; then
    # core.sh's reader, which knows config_shell's marker-padded spelling
    _hi_setting_get "$_hi_sv_target" "$_hi_sv_var" _hi_sv_val || _hi_sv_val=""
  fi
  if [ -n "${3:-}" ]; then
    printf -v "$3" '%s' "$_hi_sv_val"
  else
    printf '%s' "$_hi_sv_val"
  fi
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
# ($4) has to be written out, like _HI_PROMPT=starship - is on only when its
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
  local var="$1" off="$2" on="$3"
  if setting_on "$var" "$_HI_SETTINGS" "$off" "$on"; then
    if [ -n "$on" ]; then _hi_pending_set "$var" ""; else _hi_pending_set "$var" "$off"; fi
    printf -v "$4" '%s' off
  else
    if [ -n "$on" ]; then _hi_pending_set "$var" "$on"; else _hi_pending_set "$var" ""; fi
    printf -v "$4" '%s' on
  fi
}

# Ask a yes/no question about one setting, defaulting to its current state.
# $5, if given, is a zero-arg function whose output is boxed as a live preview
# after the question text, so the question reads first and the preview
# illustrates the answer. $6 is the on-value for an opt-in (see setting_on).
# The prompt says what the setting is now in words, not only through which
# letter of the hint is capitalised. Non-interactive runs (no tty) keep
# whatever is already configured rather than hanging on a prompt nobody can
# answer, and skip the preview since the question is auto-answered.
function ask_setting() {
  local var="$1" question="$2" target="$3" off="${4:-1}" preview="${5:-}" on="${6:-}"
  local default hint state reply=""
  setting_on "$var" "$target" "$off" "$on" && default=y || default=n
  if [ ! -t 0 ]; then
    [ "$default" = y ]
    return
  fi
  hint="Y/n" state=on
  [ "$default" = n ] && hint="y/N" state=off
  printf '%s\n' "$question"
  [ -n "$preview" ] && show_preview "$preview"
  read -r -p " (currently $state) [$hint] " reply || reply=""
  [ -z "$reply" ] && reply="$default"
  [[ "$reply" =~ ^[Yy] ]]
}

# ask_value <question> <current> <default> <validator-fn> <invalid-msg> -
# one free-text prompt, printed value on stdout: entering nothing keeps
# <current> (or the default when there is no override yet), a rejected answer
# says why and keeps it too, and an answer equal to <default> comes back
# empty - the caller records nothing rather than restating a shipped default.
# Non-interactive runs keep what is configured, like ask_setting. The
# messages go to stderr: stdout is the captured answer.
# ask_setting_value <var> <default> <validator-fn> <invalid-msg> <question> -
# ask_value against a setting, recorded. The whole shape of every free-text
# question here: this run's answer (or the file's) is the current value, and
# the reply goes back into the pending set. It was written out eight times,
# six of them with a dead `current=""` ahead of it - setting_value assigns its
# outvar on both paths, so that store never survived to be read.
function ask_setting_value() {
  local _hi_asv_cur=""
  setting_value "$1" "$_HI_SETTINGS" _hi_asv_cur
  _hi_pending_set "$1" "$(ask_value "$5" "$_hi_asv_cur" "$2" "$3" "$4")"
}

# _hi_shell_var <outvar> <shell> - the uppercase half of a $_HI_PROMPT_END_<SHELL>
# name. _HI_RC_TABLE carries the shell lowercase and the setting is spelled
# uppercase, so three sites bridged the two with their own `tr` - two forks
# apiece, and one of them runs per wired shell on every redraw of the Prompt
# menu. bash 3.2 has no ${x^^}, so a helper is the fork-free-ish form.
function _hi_shell_var() {
  printf -v "$1" '%s' "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
}

function ask_value() {
  local question="$1" current="$2" default="$3" validate="$4" invalid_msg="$5"
  local value reply=""
  value="${current:-$default}"
  if [ -t 0 ]; then
    read -r -p " $question [$value] " reply || reply=""
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

# _hi_hotkey <name> <letter> <outvar> - <name> with its shortcut letter in
# brackets, [e]verything or p[r]ompt: how every menu here spells an option
# whose letter is typed rather than its number, so the key and the word
# are read together and nothing has to say "or type e".
function _hi_hotkey() {
  local name="$1" key="$2" head
  head="${name%%"$key"*}"
  if [ "$head" = "$name" ]; then
    printf -v "$3" '%s' "$name"
  else
    printf -v "$3" '%s[%s]%s' "$head" "$key" "${name#*"$key"}"
  fi
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

function _hi_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
# a header width: 40 columns is the narrowest the banner and rows draw in
function _hi_is_width() { _hi_is_number "$1" && [ "$1" -ge 40 ]; }

# seconds, as timeout(1) takes them: whole or with a fraction
function _hi_is_seconds() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
# plain identifiers, space-separated: hi.sh names a function after each one
function _hi_is_cli_list() { [[ "$1" =~ ^[A-Za-z0-9_]+(\ [A-Za-z0-9_]+)*$ ]]; }

function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

function _hi_is_glyph_choice() {
  case "$1" in auto | glyphs | ascii) ;; *) return 1 ;; esac
}

function _hi_is_truecolor_choice() {
  case "$1" in auto | on | off) ;; *) return 1 ;; esac
}

# $_HI_PACKAGES_PALETTE's vocabulary: the names header.sh's
# _hi_packages_palette case understands
function _hi_is_packages_palette() {
  case "$1" in cool | warm | mono) ;; *) return 1 ;; esac
}

# $_HI_COLOR_SCHEME's vocabulary: the schemes core.sh's _hi_scheme_hex knows,
# `default` for none (ask_value blanks it, which clears the line), or a list
# of 12/24 hex words - a scheme of the user's own, which config_color_scheme
# keeps rather than asks for. `custom` is what that shows as, never a value.
function _hi_is_color_scheme() {
  [ "$1" = default ] || _hi_scheme_ok "$1"
}

# $_HI_IP_HIDE's vocabulary: the word `none`, or space-separated globs over
# dotted-quad addresses - digits, dots, `*` and `?` and nothing else, so a
# stray quote or a shell metacharacter can't be written into settings.sh
function _hi_is_ip_hide() {
  case "$1" in
  none) return 0 ;;
  '' | *[!0-9.*?\ ]*) return 1 ;;
  esac
}

# _hi_is_header_word <word> - one of $_HI_HEADER_ORDER's vocabulary, read off
# header.sh's own $_HI_HEADER_ORDER_DEFAULT rather than a second copy of the
# word list here (the two used to drift)
function _hi_is_header_word() {
  _hi_load_preview_sources
  case " $_HI_HEADER_ORDER_DEFAULT " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

# $_HI_HEADER_ORDER's vocabulary: those words, any order, space-separated, a
# feature skippable by leaving it out. Empty is refused - at runtime an empty
# value falls back to the default order, so it is not a way to spell "none"
function _hi_is_header_order() {
  local word
  [ -n "$1" ] || return 1
  # shellcheck disable=SC2086 # the split is the point: one word per feature
  for word in $1; do
    _hi_is_header_word "$word" || return 1
  done
}

# A section heading plus one line saying what the menu under it decides,
# so a section reads as a unit before its first prompt does.
function section() {
  _hi_h2 "$1"
  [ -t 0 ] && [ -n "${2:-}" ] && _hi_cecho " $2" "$BLUE"
  return 0
}

# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
function show_preview() {
  local out content_w=0 len line pad top bottom fill_top fill_bottom i
  local label="$_HI_BOX_H preview "
  local -a lines lens=()
  out="$("$@" 2>/dev/null)" || true
  [ -n "$out" ] || return 0
  _hi_read_lines lines <<<"$out"
  # measured once, kept for the render loop: the strip behind _hi_visible_len
  # is the expensive half of every line
  for line in "${lines[@]}"; do
    _hi_visible_len len "$line"
    lens+=("$len")
    ((len > content_w)) && content_w=$len
  done
  _hi_repeat fill_top $((content_w + 2 - ${#label})) "$_HI_BOX_H"
  _hi_repeat fill_bottom $((content_w + 2)) "$_HI_BOX_H"
  top="$_HI_BOX_TL${label}${fill_top}$_HI_BOX_TR"
  bottom="$_HI_BOX_BL${fill_bottom}$_HI_BOX_BR"
  _hi_cecho "   $top" "$NC"
  for i in "${!lines[@]}"; do
    pad=$((content_w - lens[i]))
    printf '   %s %s%*s %s\n' "$_HI_BOX_V" "${lines[i]}" "$pad" "" "$_HI_BOX_V"
  done
  _hi_cecho "   $bottom" "$NC"
}

# The header's cells are memoized per shell (_HI_SI_* by
# _hi_system_info_probe, _HI_ID_* by _hi_identity_probe - the latter waits on
# the docker/nomad/kubectl probes, up to $_HI_PROBE_TIMEOUT). Paid once here,
# in the shell that runs the menus, so every `$( )` render below inherits the
# memo instead of probing the backends again per keystroke.
function _hi_probe_once() {
  _hi_load_preview_sources
  _hi_system_info_probe
  _hi_identity_probe
}

# The real header, rendered at the answers this run holds so far: hi_header
# itself, in a subshell that exports what it reads. _HI_DISABLE_HEADER is
# read here rather than exported: a header switched off previews as a
# sentence, not as an empty box show_preview would drop on the floor.
# Captured, not a tty, so _hi_draw_width draws to $_HI_MAX_WIDTH
# exactly - which is what the width dial is previewing.
function _hi_header_preview() {
  local order banner width floor palette lead iphide scheme
  _hi_load_preview_sources
  if setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1; then
    _hi_cecho " header off - nothing prints on connect or disconnect" "$YELLOW"
    return 0
  fi
  setting_value _HI_HEADER_ORDER "$_HI_SETTINGS" order
  setting_value _HI_DISABLE_BANNER "$_HI_SETTINGS" banner
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" width
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" floor
  setting_value _HI_PACKAGES_PALETTE "$_HI_SETTINGS" palette
  setting_value _HI_NO_LEAD_SPACE "$_HI_SETTINGS" lead
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" scheme
  (
    export _HI_HEADER_ORDER="$order" _HI_DISABLE_BANNER="${banner:-0}" _HI_MAX_WIDTH="${width:-80}"
    export _HI_PACKAGES_MIN_PRIORITY="${floor:-2}" _HI_PACKAGES_PALETTE="${palette:-cool}"
    export _HI_NO_LEAD_SPACE="${lead:-0}" _HI_IP_HIDE="${iphide:-172.*}"
    # the palette and the check ramps were captured at source time;
    # rebuild both under this run's scheme so the preview paints with it
    # shellcheck disable=SC2030 # the scheme lives and dies in this subshell
    export _HI_COLOR_SCHEME="$scheme"
    _hi_assign_palette
    _hi_packages_palette
    unset _HI_DISABLE_HEADER
    hi_header Connected
  )
}

# _hi_prompt_end_shown <SHELL> <outvar> - what that shell's prompt ends with
# at this run's answers, as it will look: the shipped bash default is the PS1
# escape `\$`, so one leading backslash comes off for display
function _hi_prompt_end_shown() {
  local _hi_pe_end=""
  # core.sh's _hi_prompt_end order: the shell's own, then the default
  setting_value "_HI_PROMPT_END_$1" "$_HI_SETTINGS" _hi_pe_end
  [ -n "$_hi_pe_end" ] || _hi_pe_end="$(_hi_prompt_end_default "$1")"
  printf -v "$2" '%s' "${_hi_pe_end#\\}"
}

# sample "user@host cwd" line, colored like common/bash.sh's real HI_PS1, with
# the literal current user/host/cwd instead of \u/\h/\w (@ yellow over ssh)
function _hi_prompt_preview() {
  local cwd="${PWD/#$HOME/\~}" at="$NC"
  [ -n "${SSH_TTY:-}" ] && at="$YELLOW"
  printf '%b\n' " $(_hi_user_escape)$(_hi_whoami)$at@$(_hi_host_escape)$(_hi_hostname)$NC $BRBLUE$cwd$NC"
}

# the real git prompt segment against say-hi's own checkout (always a git repo),
# so the preview shows this machine's actual status. _HI_DISABLE_GIT_STATUS is
# unset for the call, or a toggle the user has switched off makes it return
# empty.
function _hi_git_status_preview() {
  # shellcheck disable=SC2119 # stdout form on purpose - this feeds show_preview
  (cd "$_HI_ROOT" 2>/dev/null && unset _HI_DISABLE_GIT_STATUS && _hi_git_prompt)
}

# the whole prompt line as bash would draw it at this run's answers:
# user@host cwd, the git segment when that is on, and the end character -
# or a sentence, when the colored prompt itself is off
function _hi_prompt_sample_preview() {
  local prompt git="" end scheme
  if setting_off _HI_DISABLE_PROMPT "$_HI_SETTINGS" 1; then
    _hi_cecho " prompt off - your shell's own" "$YELLOW"
    return 0
  fi
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" scheme
  # the escape memos are per shell, so the scheme is applied in a subshell
  # with them cleared, and the palette rebuilt under it
  prompt="$(
    # shellcheck disable=SC2031 # the same subshell-scoped export as the header preview
    export _HI_COLOR_SCHEME="$scheme"
    _hi_assign_palette
    unset _HI_HOST_ESC _HI_USER_ESC
    _hi_prompt_preview
  )"
  setting_off _HI_DISABLE_GIT_STATUS "$_HI_SETTINGS" 1 || git="$(_hi_git_status_preview)"
  _hi_prompt_end_shown BASH end
  printf '%s%s %s\n' "$prompt" "$git" "$end"
}

# The hub's picture: the header as it would print, then the prompt line as
# it would draw - the two things every session shows. Each half says "off"
# in words when it is, so the box always has something to show.
function _hi_config_preview() {
  _hi_header_preview
  printf '\n'
  _hi_prompt_sample_preview
}

# what `nano`/`vim` actually resolve to with the override on. The vim ladder
# is settings/aliases.sh's, spelled again because this file cannot source it -
# see the note there; alias_fallthrough_test.sh fails when the two drift.
function _hi_editors_preview() {
  printf 'nano -> nano --rcfile %s\n' "$_HI_NANORC"
  printf 'vim  -> %s -u %s\n' "$(command -v nvim || command -v vim)" "$_HI_VIMRC"
}

# what `cat` and `eza` resolve to with the rebinds on. settings/aliases.sh's
# ladders are spelled again because this file cannot source it - see the note
# there; alias_fallthrough_test.sh fails when the two drift.
function _hi_tool_alias_preview() {
  local bat_bin eza_bin
  bat_bin="$(command -v bat || command -v batcat)"
  if [ -n "$bat_bin" ]; then
    printf 'cat -> %s -P --tabs 2 --theme Monokai\\ Extended\\ Bright --style changes,grid\n' "$bat_bin"
  else
    printf 'bat is not installed here - only targets that have it are affected\n'
  fi
  eza_bin="$(command -v eza || command -v exa)"
  if [ -n "$eza_bin" ]; then
    printf 'eza -> %s -F -1 -l -m --group-directories-first --smart-group --time-style="+%%b %%d %%Y %%H:%%M"\n' "$eza_bin"
  else
    printf 'eza is not installed here - only targets that have it are affected\n'
  fi
}

function _hi_starship_preview() {
  if command -v starship >/dev/null 2>&1; then
    printf "starship is installed here (%s); a target without it keeps hi's prompt\n" \
      "$(starship --version 2>/dev/null | head -1)"
  else
    printf "starship is not installed on this machine - only targets that have it are affected\n"
  fi
}

# The package floor's preview, rendered at the value being *considered* rather
# than the one configured: full_check reads $_HI_PACKAGES_MIN_PRIORITY on every
# call, so a prefix assignment around it is the whole trick. An empty render is
# a real answer at a high enough floor, and says so rather than showing
# show_preview a blank string, which it would drop on the floor.
# <candidate> - the floor to render at. Taken as an argument rather than read
# out of config_packages_floor's scope: show_preview already runs "$@", so the
# two were coupled through a bare global name for nothing.
function _hi_packages_floor_preview() {
  local out candidate="${1:-2}"
  out="$(_HI_PACKAGES_MIN_PRIORITY="$candidate" full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " nothing - the check is off at this floor" "$YELLOW"
  fi
}

# The palette's preview, shown once before the question rather than re-rendered
# per keystroke the way the floor's loop does: the answer here is a word from a
# closed set (cool/warm/mono), not a dial. Renders under whatever
# $_HI_PACKAGES_PALETTE is configured right now - full_check resolves it itself
# - so cool/warm/mono are compared by eye against the shipped default before
# picking a name, not only by reading which is which.
function _hi_packages_palette_preview() {
  local out
  out="$(full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " nothing - the package check is off (\$_HI_PACKAGES_MIN_PRIORITY)" "$YELLOW"
  fi
}

# One row per scheme, the twelve palette names painted as that scheme
# paints them. _HI_TRUECOLOR=1 is forced for the swatches on purpose: the
# question is what a capable terminal will show, and the note below says so
# when this one is not. Temporary-environment calls on a function, so
# nothing leaks and nothing forks.
function _hi_color_scheme_preview() {
  local scheme name esc current="" n i
  # shellcheck disable=SC2153 # the roster is core.sh's, exported
  for scheme in default $_HI_COLOR_SCHEMES; do
    printf '   %-11s' "$scheme"
    for name in "${_HI_COLOR_NAMES[@]}"; do
      _HI_COLOR_SCHEME="$scheme" _HI_TRUECOLOR=1 _hi_color_escape_var esc "$name"
      printf '%b%s%b ' "$esc" "$name" "$NC"
    done
    printf '\n'
  done
  # a hand-written list as its own row, and a second one for the bank the
  # packages check paints from when it carries twenty-four words (HI.50)
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" current
  _HI_COLOR_SCHEME="$current" _hi_scheme_words n
  if [ "$n" -gt 0 ]; then
    for scheme in custom packages; do
      [ "$scheme" = packages ] && [ "$n" -lt 24 ] && break
      printf '   %-11s' "$scheme"
      i=0
      [ "$scheme" = packages ] && i=12
      for name in "${_HI_COLOR_NAMES[@]}"; do
        _HI_COLOR_SCHEME="$current" _HI_TRUECOLOR=1 _hi_color_escape_at esc "$i"
        printf '%b%s%b ' "$esc" "$name" "$NC"
        i=$((i + 1))
      done
      printf '\n'
    done
  fi
  _hi_has_truecolor ||
    _hi_cecho " this terminal reports no truecolor (COLORTERM), so a scheme renders as the default row here" "$YELLOW"
}

# Every line collect_setting_lines decides on, written to $_HI_SETTINGS in
# one go by run_configure. An ordered array, because config_shell compares
# what it would write against what is there to decide whether the file is up
# to date - so the write order has to be stable across runs.
declare -a _HI_SETTING_LINES=()

# The yes/no settings as tables, one row per setting, in the order they are
# listed and written: <var>|<off-value>|<on-value>|<preview-fn>|<question>|
# <needs>|<label>. <on-value> is empty for a default-on toggle (off writes
# the off-value, on writes nothing) and set for an opt-in (on writes it, off
# writes nothing) - setting_on has the rule. <needs> names a command the
# setting is moot without: the menu says so beside it, and a question walk
# (ask_prompt_group) skips the row. <label> is the menu's short name for it;
# <question> is the long form ask_prompt_group asks. Adding a setting is one
# row, and every `_HI_*_PROMPTS` table is what tests/lint's settings-table
# check reads.
_HI_FEATURE_PROMPTS=(
  "_HI_DISABLE_HEADER|1||_hi_header_preview| Enable the connect/disconnect header (system info, git identity, package check)?||connect/disconnect header - its contents are the Header menu"
  "_HI_DISABLE_PROMPT|1||_hi_prompt_preview| Enable the colored user@host prompt?||colored user@host prompt"
  "_HI_DISABLE_GIT_STATUS|1||_hi_git_status_preview| Enable git status in the prompt?||git status in the prompt"
  "_HI_DISABLE_EDITORS|1||_hi_editors_preview| Enable the vim/nano config overrides?||vim/nano config overrides"
  "_HI_DISABLE_TOOL_ALIASES|1||_hi_tool_alias_preview| Enable the styled tool aliases (cat -> bat with --tabs 2, changes/grid; exa/eza with hi's columns) where the tools are installed?||styled tool aliases - cat -> bat, exa/eza"
  "_HI_DISABLE_MARKS|1||| Enable prompt marks and cwd reporting (OSC 133/7: jump between prompts, select a command's output, open a new tab in the remote directory)?||prompt marks and cwd reporting (OSC 133/7)"
  "_HI_DISABLE_LOCAL|1||| Enable all of the above on this machine (the one say-hi is installed on), not just when you hi elsewhere?||all of the above on this machine too, not just where you hi"
)

# The one row that survives from the old row toggles: banner is not part of
# $_HI_HEADER_ORDER's reorderable feature list (it always leads), so it still
# needs its own hide switch. Every other former row toggle (TIMESTAMP/
# SYSINFO/UPTIME/IDENTITY/CHECK) is retired - that content is addressed at
# the finer feature grain, through the header editor (config_header).
_HI_HEADER_PROMPTS=(
  "_HI_DISABLE_BANNER|1||_hi_header_preview| Show the connect/disconnect banner line?||banner"
)

# whether to hand the prompt to starship where a target has one. An opt-in,
# never auto-detected - core.sh's _hi_wants_prompt_tool, which also takes
# _HI_PROMPT=oh-my-posh written by hand (no menu item: one toggle, one tool)
_HI_PROMPT_PROMPTS=(
  "_HI_PROMPT||starship|_hi_starship_preview| Hand the prompt to starship on targets that have it (hi keeps the header and aliases)?||starship draws the prompt on targets that have it"
)

# The advanced section, behind the hub's Advanced item: settings most
# installs never touch, kept out of the default path so it stays short. Not
# opening it keeps whatever each of these already holds.
_HI_ADVANCED_PROMPTS=(
  "_HI_NO_LEAD_SPACE|0|1|| Drop the leading space hi puts before the prompt's user@host, the git segment, and each header line?||"
  "_HI_MUX|0|1|| Wrap every session in a local tmux (one named session per target, reattached when you reconnect)?|tmux|"
)

function _hi_is_yes_no() {
  case "$1" in y | yes | n | no) ;; *) return 1 ;; esac
}

# _hi_prompt_rows <table-name> <outvar-array> - the table copied out by name
# through eval rather than `local -n rows="$1"`: namerefs are bash 4.3 and
# macOS ships bash 3.2. The ${a[@]+"${a[@]}"} guard one eval deeper: an empty
# table would otherwise be an "unbound variable" on bash 3.2 rather than
# nothing to ask.
function _hi_prompt_rows() {
  eval "$2=(\${$1[@]+\"\${$1[@]}\"})"
}

# Ask every row of the table named by $1 in turn, recording each answer. A
# row whose <needs> command is absent here is not asked - its stored value
# is carried by the collector untouched.
function ask_prompt_group() {
  local row var off on preview question needs label target="$_HI_SETTINGS"
  local -a rows=()
  _hi_prompt_rows "$1" rows
  for row in ${rows[@]+"${rows[@]}"}; do
    IFS='|' read -r var off on preview question needs label <<<"$row"
    if [ -n "$needs" ] && ! command -v "$needs" >/dev/null 2>&1; then
      continue
    fi
    if ask_setting "$var" "$question" "$target" "$off" "$preview" "$on"; then
      if [ -n "$on" ]; then _hi_pending_set "$var" "$on"; else _hi_pending_set "$var" ""; fi
    else
      if [ -n "$on" ]; then _hi_pending_set "$var" ""; else _hi_pending_set "$var" "$off"; fi
    fi
  done
}

# <name>|<one-line description>|<var=value ...>: a starting point for the
# feature, header, package-check and prompt settings - the presets say
# nothing about the header order, the advanced section, the width or the
# separators. A var the preset does not name goes back to its shipped
# default, so a preset is an absolute answer rather than a delta on what the
# file holds. Applied, its answers are what the hub shows and saves;
# `--preset <name>` writes them without a hub at all.
_HI_PRESETS=(
  "everything|every feature and every header item on - the shipped defaults|"
  "balanced|everything but the noise: a shorter package check|_HI_PACKAGES_MIN_PRIORITY=3"
  "minimal|on targets only the colored prompt and the aliases - no header, git status, editors or prompt marks; nothing at all on this machine|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_DISABLE_EDITORS=1 _HI_DISABLE_MARKS=1 _HI_DISABLE_LOCAL=1"
)

# every variable a preset answers for: the feature and header yes/no tables,
# plus the one dial - so "not named by the preset" can mean "back to the
# default". _HI_PROMPT (starship) stays out, like the color scheme: it is
# taste, not a feature level, and no preset has an opinion on it.
function _hi_preset_vocab() {
  local row
  for row in "${_HI_FEATURE_PROMPTS[@]}" "${_HI_HEADER_PROMPTS[@]}"; do
    printf '%s\n' "${row%%|*}"
  done
  printf '%s\n' _HI_PACKAGES_MIN_PRIORITY
}

# preset_row <name> - its table row, or failure for a name that is not one
# The three helpers take an optional table name so the header presets can use
# them too: _HI_HEADER_PRESETS is the same `name|desc|payload` shape, and
# config_header_preset used to re-implement all three - the listing, the row
# lookup, and the first-letter match. That third copy had no ambiguity guard
# and no break, so it silently took the *last* preset whose name started with
# the typed letter, and a prefix match could clobber an exact name match.
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
# vocabulary variable (empty for "the default"), so the hub starts there and
# a --preset run writes exactly the preset.
function apply_preset() {
  local row values var value pair
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
  _hi_cecho " starting from the '$1' preset" "$GREEN"
}

# The hub's preset item: pick one to start from, or Enter to leave things as
# they are. One shot, not a loop - a typo gets the name list back and the
# hub comes round again.
function config_preset() {
  [ -t 0 ] || return 0
  local row name desc reply="" short shown
  section "Starting point" "A preset answers the feature and header settings at once; change any of them after."
  for row in "${_HI_PRESETS[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    _hi_hotkey "$name" "${name:0:1}" shown
    printf '   %-13s %s\n' "$shown" "$desc"
  done
  menu_read " Start from a preset? (the bracketed letter or the full name; Enter keeps your current settings) [keep] " reply || return 0
  [ -n "$reply" ] || return 0
  short="$(preset_shorthand "$reply")" && reply="$short"
  apply_preset "$reply" || return 0
  return 0
}

# What a run is about to do, said once up front: how the hub works, where
# the answers go, and that nothing is written until `s` - so ^C or `q` at
# any point leaves settings.sh exactly as it was. Interactive only; a run
# with no tty has nobody to orient.
function configure_intro() {
  [ -t 0 ] || return 0
  local state="none yet - defaults apply"
  [ -f "$_HI_SETTINGS" ] && state="$(grep -cF "$_HI_MARKER" "$_HI_SETTINGS" 2>/dev/null || echo 0) setting(s) stored"
  _hi_cecho " The preview shows what a session will look like at your current settings." "$BLUE"
  _hi_cecho " Pick a preset, or open a section and change what you like; each menu says" "$BLUE"
  _hi_cecho " how. Nothing is written until you save with [s]; [q] leaves the file untouched." "$BLUE"
  _hi_cecho " settings: $_HI_SETTINGS ($state)" "$BLUE"
}

# The hub: the preview, six sections, save or quit. Every section returns
# here, and the preview re-renders with whatever it changed. EOF saves - the
# same "no answer keeps what you have and the run completes" that every
# question here has always meant. The third junk answer in a row ends the
# run too, but as a quit: three words that are not menu items are not an
# instruction to write the file. Enter alone redraws.
_HI_CONFIGURE_QUIT=""
function config_hub() {
  local reply rejects=0 max_rejects=3
  _hi_probe_once
  while :; do
    _hi_h2 "hi --configure"
    show_preview _hi_config_preview
    printf '   1) %-12s %s\n' "[p]reset" "[e]verything / [b]alanced / [m]inimal - a starting point"
    printf '   2) %-12s %s\n' "[h]eader" "what the header shows and in what order; its width, the package check's depth and palette, the addresses hidden"
    printf '   3) %-12s %s\n' "[f]eatures" "prompt, git status, editors, prompt marks, ..."
    printf '   4) %-12s %s\n' "p[r]ompt" "starship, and the character each shell's prompt ends with"
    printf '   5) %-12s %s\n' "[a]dvanced" "the leading space, tmux, glyphs, 24-bit color, the container CLI roster"
    printf '   6) %-12s %s\n' "[c]olors" "a truecolor scheme for prompt and header - catppuccin, monokai, onedark, vscode, or your own hex list"
    printf '      %-12s %s\n' "[s]ave" "write the settings and exit"
    printf '      %-12s %s\n' "[q]uit" "exit without writing anything"
    menu_read " > " reply || return 0
    case "$reply" in
    '')
      rejects=0
      continue
      ;;
    1 | p | preset) config_preset ;;
    2 | h | header) config_header ;;
    3 | f | features) config_features ;;
    4 | r | prompt) config_prompt ;;
    5 | a | advanced) config_advanced ;;
    6 | c | colors) config_color_scheme ;;
    s | save) return 0 ;;
    q | quit)
      _HI_CONFIGURE_QUIT=1
      return 0
      ;;
    *)
      rejects=$((rejects + 1))
      if [ "$rejects" -ge "$max_rejects" ]; then
        _hi_cecho " not a menu item three times - leaving $_HI_SETTINGS as it was" "$YELLOW"
        _HI_CONFIGURE_QUIT=1
        return 0
      fi
      _hi_cecho " type 1-6 or the bracketed letter ([p] [h] [f] [r] [a] [c]); [s] saves, [q] quits" "$YELLOW"
      continue
      ;;
    esac
    rejects=0
  done
}

# The Features menu: one line per _HI_FEATURE_PROMPTS row with its state, a
# number toggles it and shows the row's preview, Enter goes back. A row whose
# <needs> command is absent here says so but still toggles - the setting
# applies wherever the command exists.
function config_features() {
  local reply rejects=0 max_rejects=3 i n state var off on preview question needs label note
  local -a rows=()
  _hi_prompt_rows _HI_FEATURE_PROMPTS rows
  n=${#rows[@]}
  section "Features" "What hi does on every host you say hi to. Type a number to turn one on or off; Enter goes back."
  while :; do
    for i in "${!rows[@]}"; do
      IFS='|' read -r var off on preview question needs label <<<"${rows[$i]}"
      setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && state="x" || state=" "
      note=""
      if [ -n "$needs" ] && ! command -v "$needs" >/dev/null 2>&1; then
        note=" ($needs is not installed here)"
      fi
      printf '  %2d) [%s] %s%s\n' "$((i + 1))" "$state" "$label" "$note"
    done
    menu_read " Feature to toggle (Enter when done) > " reply || return 0
    [ -n "$reply" ] || return 0
    if _hi_is_number "$reply" && [ "$reply" -ge 1 ] && [ "$reply" -le "$n" ]; then
      rejects=0
      IFS='|' read -r var off on preview question needs label <<<"${rows[$((reply - 1))]}"
      _hi_setting_flip "$var" "$off" "$on" state
      _hi_cecho " ${label%% - *}: now $state" "$GREEN"
      [ -n "$preview" ] && show_preview "$preview"
      continue
    fi
    rejects=$((rejects + 1))
    [ "$rejects" -ge "$max_rejects" ] && return 0
    _hi_cecho " type a number from 1 to $n, or Enter to go back" "$YELLOW"
  done
}

# <name>|<one-line description>|<words>: a starting point for the header
# editor. Empty words mean the shipped order - the same spelling
# $_HI_HEADER_ORDER itself uses for "the default" - rather than a second copy
# of header.sh's word list.
_HI_HEADER_PRESETS=(
  "full|every item, in the shipped order|"
  "compact|the clocks, the version, your git identity, the backend counts and the package check|utc version localtime gitid containers jobs pods check"
  "quiet|just the clocks and your git identity|utc localtime gitid"
)

# _hi_header_word_desc <word> <outvar> - what a header word shows, for the
# editor's list. docs/SETTINGS.md's header table says the same in prose.
function _hi_header_word_desc() {
  case "$1" in
  utc) printf -v "$2" '%s' "the UTC clock" ;;
  version) printf -v "$2" '%s' "hi's own version" ;;
  localtime) printf -v "$2" '%s' "your local clock" ;;
  arch) printf -v "$2" '%s' "the CPU architecture" ;;
  os) printf -v "$2" '%s' "the OS name/version" ;;
  cores) printf -v "$2" '%s' "core count and load" ;;
  cpu) printf -v "$2" '%s' "clock speed" ;;
  ram) printf -v "$2" '%s' "used/total memory" ;;
  ip) printf -v "$2" '%s' "this box's routable IPv4 address(es)" ;;
  gitid) printf -v "$2" '%s' "your git identity, domain masked" ;;
  containers) printf -v "$2" '%s' "docker/podman container count, when either runs" ;;
  jobs) printf -v "$2" '%s' "nomad job count, when nomad answers" ;;
  pods) printf -v "$2" '%s' "reachable kube pod count, when kubectl answers" ;;
  auth) printf -v "$2" '%s' "lines in ~/.ssh/authorized_keys" ;;
  pub) printf -v "$2" '%s' "public keys (~/.ssh/*.pub)" ;;
  uptime) printf -v "$2" '%s' "this box's uptime" ;;
  check) printf -v "$2" '%s' "the installed-packages check (settings/packages)" ;;
  *) printf -v "$2" '%s' "" ;;
  esac
}

# The editor's working copy of $_HI_HEADER_ORDER: every word of the
# vocabulary exactly once, in display order, with a parallel on/off flag.
# _hi_header_edit_load seeds it from this run's value - the words it names
# first, in its order, then every word it leaves out, off, in the shipped
# order - and _hi_header_edit_commit writes the on words back to pending
# (empty when they are the shipped order, so nothing is written for it).
_HI_HDR_WORDS=()
_HI_HDR_ON=()

function _hi_header_edit_load() {
  local current word seen=" "
  _hi_load_preview_sources
  setting_value _HI_HEADER_ORDER "$_HI_SETTINGS" current
  [ -n "$current" ] || current="$_HI_HEADER_ORDER_DEFAULT"
  _HI_HDR_WORDS=()
  _HI_HDR_ON=()
  # shellcheck disable=SC2086 # the split is the point: one word per feature
  for word in $current; do
    _hi_is_header_word "$word" || continue
    case "$seen" in *" $word "*) continue ;; esac
    seen="$seen$word "
    _HI_HDR_WORDS+=("$word")
    _HI_HDR_ON+=(1)
  done
  for word in $_HI_HEADER_ORDER_DEFAULT; do
    case "$seen" in *" $word "*) continue ;; esac
    seen="$seen$word "
    _HI_HDR_WORDS+=("$word")
    _HI_HDR_ON+=(0)
  done
}

function _hi_header_edit_commit() {
  local i on=""
  for i in "${!_HI_HDR_WORDS[@]}"; do
    [ "${_HI_HDR_ON[$i]}" = 1 ] && on="$on${_HI_HDR_WORDS[$i]} "
  done
  on="${on% }"
  [ "$on" = "$_HI_HEADER_ORDER_DEFAULT" ] && on=""
  _hi_pending_set _HI_HEADER_ORDER "$on"
}

# how many words are on - the editor refuses to turn the last one off, since
# an empty $_HI_HEADER_ORDER means the default order at runtime, not none
function _hi_header_edit_count_on() {
  local i n=0
  for i in "${!_HI_HDR_ON[@]}"; do [ "${_HI_HDR_ON[$i]}" = 1 ] && n=$((n + 1)); done
  printf '%d' "$n"
}

function _hi_header_edit_has() {
  local i
  for i in "${!_HI_HDR_WORDS[@]}"; do
    [ "${_HI_HDR_WORDS[$i]}" = "$1" ] && [ "${_HI_HDR_ON[$i]}" = 1 ] && return 0
  done
  return 1
}

# _hi_header_edit_preset <name> - the editor's words from a header preset:
# its words first and on, in its order, everything else off after
function _hi_header_edit_preset() {
  local row words
  for row in "${_HI_HEADER_PRESETS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    words="${row##*|}"
    _hi_pending_set _HI_HEADER_ORDER "$words"
    _hi_header_edit_load
    _hi_header_edit_commit
    _hi_cecho " header: the '$1' preset" "$GREEN"
    return 0
  done
  return 1
}

# _hi_header_edit_move <index> <-1|+1> - swap a word with its neighbor
function _hi_header_edit_move() {
  local i="$1" j=$(($1 + $2)) w o
  if ((j < 0 || j >= ${#_HI_HDR_WORDS[@]})); then
    _hi_cecho " ${_HI_HDR_WORDS[$i]} is already at that end" "$YELLOW"
    return 0
  fi
  w="${_HI_HDR_WORDS[$i]}" o="${_HI_HDR_ON[$i]}"
  _HI_HDR_WORDS[i]="${_HI_HDR_WORDS[j]}" _HI_HDR_ON[i]="${_HI_HDR_ON[j]}"
  _HI_HDR_WORDS[j]="$w" _HI_HDR_ON[j]="$o"
  _hi_header_edit_commit
}

function _hi_header_edit_list() {
  local i state desc banner width floor palette iphide on_state="on"
  setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1 && on_state="off"
  setting_off _HI_DISABLE_BANNER "$_HI_SETTINGS" 1 && state=" " || state="x"
  printf '   0) header: %s\n' "$on_state"
  printf '   1) [%s] %-11s %s\n' "$state" banner "the ~~~ Connected [host] ~~~ line - always first"
  for i in "${!_HI_HDR_WORDS[@]}"; do
    [ "${_HI_HDR_ON[$i]}" = 1 ] && state="x" || state=" "
    _hi_header_word_desc "${_HI_HDR_WORDS[$i]}" desc
    printf '  %2d) [%s] %-11s %s\n' "$((i + 2))" "$state" "${_HI_HDR_WORDS[$i]}" "$desc"
  done
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" width
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" floor
  setting_value _HI_PACKAGES_PALETTE "$_HI_SETTINGS" palette
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  _hi_cecho "   N toggles an item, 0 the whole header; up N / down N moves it; [p] header preset; [w] width (${width:-80})" "$BLUE"
  if _hi_header_edit_has ip; then
    _hi_cecho "   [i] hidden addresses (${iphide:-172.*})" "$BLUE"
  fi
  if _hi_header_edit_has check; then
    _hi_cecho "   [c] check depth (${floor:-2}); [k] check palette (${palette:-cool}); Enter goes back" "$BLUE"
  else
    _hi_cecho "   Enter goes back" "$BLUE"
  fi
}

# The header editor: the real header rendered above a numbered list of
# everything it can show; every command re-renders. Item 1 is the banner
# (_HI_DISABLE_BANNER - it always leads, so it toggles but never moves), the
# rest are $_HI_HEADER_ORDER's words in the order they will print, 0 is the
# header itself. The width, the package check's depth and its palette live
# here too, since the render is what each of them changes.
function config_header() {
  local reply rejects=0 max_rejects=3 cmd arg idx n state
  section "Header" "What the connect/disconnect header shows, in the order it shows it. The preview is the real thing."
  _hi_probe_once
  _hi_header_edit_load
  while :; do
    show_preview _hi_header_preview
    _hi_header_edit_list
    n=$((${#_HI_HDR_WORDS[@]} + 1))
    menu_read " > " reply || return 0
    [ -n "$reply" ] || return 0
    cmd="${reply%% *}" arg=""
    [ "$cmd" != "$reply" ] && arg="${reply#* }"
    case "$cmd" in
    0)
      _hi_setting_flip _HI_DISABLE_HEADER 1 "" state
      _hi_cecho " header: now $state" "$GREEN"
      ;;
    1)
      _hi_setting_flip _HI_DISABLE_BANNER 1 "" state
      _hi_cecho " banner: now $state" "$GREEN"
      ;;
    up | u | down | d)
      if ! _hi_is_number "$arg" || [ "$arg" -lt 1 ] || [ "$arg" -gt "$n" ]; then
        _hi_cecho " up/down take an item number from 2 to $n" "$YELLOW"
      elif [ "$arg" = 1 ]; then
        _hi_cecho " the banner always leads" "$YELLOW"
      else
        case "$cmd" in u*) _hi_header_edit_move "$((arg - 2))" -1 ;; *) _hi_header_edit_move "$((arg - 2))" 1 ;; esac
      fi
      ;;
    p | preset)
      config_header_preset
      ;;
    w | width)
      config_max_width
      ;;
    c | check | depth)
      if _hi_header_edit_has check; then config_packages_floor; else _hi_cecho " the package check is off - turn 'check' on first" "$YELLOW"; fi
      ;;
    k | palette)
      if _hi_header_edit_has check; then config_packages_palette; else _hi_cecho " the package check is off - turn 'check' on first" "$YELLOW"; fi
      ;;
    i | ip | hide)
      if _hi_header_edit_has ip; then config_ip_hide; else _hi_cecho " the ip cell is off - turn 'ip' on first" "$YELLOW"; fi
      ;;
    *)
      if _hi_is_number "$cmd" && [ "$cmd" -ge 2 ] && [ "$cmd" -le "$n" ]; then
        idx=$((cmd - 2))
        if [ "${_HI_HDR_ON[$idx]}" = 1 ] && [ "$(_hi_header_edit_count_on)" -le 1 ]; then
          _hi_cecho " keep at least one item - 0 turns the whole header off" "$YELLOW"
        else
          [ "${_HI_HDR_ON[$idx]}" = 1 ] && _HI_HDR_ON[idx]=0 || _HI_HDR_ON[idx]=1
          _hi_header_edit_commit
        fi
      else
        rejects=$((rejects + 1))
        [ "$rejects" -ge "$max_rejects" ] && {
          _hi_cecho " not an item three times - back to the menu" "$YELLOW"
          return 0
        }
        _hi_cecho " type an item number, up N, down N, [p], [w], [i], [c], [k], 0, or Enter to go back" "$YELLOW"
        continue
      fi
      ;;
    esac
    rejects=0
  done
}

# the header editor's preset pick: one shot, like config_preset
function config_header_preset() {
  local row name desc reply="" short="" shown
  for row in "${_HI_HEADER_PRESETS[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    _hi_hotkey "$name" "${name:0:1}" shown
    printf '   %-10s %s\n' "$shown" "$desc"
  done
  menu_read " Header preset? (the bracketed letter or the name; Enter keeps the list as it is) [] " reply || return 0
  [ -n "$reply" ] || return 0
  # an exact name first, then an unambiguous first letter - config_preset's
  # own rule, through the same two helpers rather than a third copy of it
  if preset_row "$reply" _HI_HEADER_PRESETS >/dev/null; then
    short="$reply"
  else
    short="$(preset_shorthand "$reply" _HI_HEADER_PRESETS)" || short=""
  fi
  [ -n "$short" ] && _hi_header_edit_preset "$short" && return 0
  _hi_cecho " no such header preset: $reply" "$YELLOW"
  return 0
}

# The one prompt that loops. Every other question here previews once and takes
# an answer, because the answer is a yes/no or a character; this one is a dial
# whose whole point is how much it prints, so it re-renders the real check at
# each value until the answer stops changing. Enter accepts what is on screen.
#
# Because it loops, it is also the one prompt that has to prove it can stop.
# Three ways out, and a non-answer is not one of them: an empty line, an answer
# equal to the value already on screen, or EOF. A reply that is not a number is
# re-asked at most $max_rejects times and then keeps the current value - the
# loop is a dial, not a validator, and an unbounded retry here is a hang.
function config_packages_floor() {
  local current reply rejects=0 max_rejects=3 _hi_floor_candidate
  current=""
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" current
  _hi_floor_candidate="${current:-2}"
  if [ -t 0 ]; then
    _hi_load_preview_sources
    while :; do
      show_preview _hi_packages_floor_preview "$_hi_floor_candidate"
      # menu_read carries the EOF contract (read, close the prompt line, rc 1)
      # this used to restate; its lowercase-and-squeeze is a no-op on a number
      menu_read " Lowest package priority to show (0-3, or 4 to turn the check off)? [$_hi_floor_candidate] " reply || break
      [ -z "$reply" ] && break
      if ! _hi_is_number "$reply" || [ "$reply" -gt 4 ]; then
        rejects=$((rejects + 1))
        if [ "$rejects" -ge "$max_rejects" ]; then
          _hi_cecho " not 0-4, leaving it at $_hi_floor_candidate" "$YELLOW"
          break
        fi
        _hi_cecho " not 0-4 - type a priority, 4 to turn the check off, or press Enter to keep $_hi_floor_candidate" "$YELLOW"
        continue
      fi
      rejects=0
      [ "$reply" = "$_hi_floor_candidate" ] && break
      _hi_floor_candidate="$reply"
    done
  fi
  # 2 is common/header.sh's own default, so it clears the override rather than
  # restating it - config_max_width does the same with 80. 0 and 1 get written
  # out: each is a real answer (lower tiers back on), not the default.
  [ "$_hi_floor_candidate" = 2 ] && _hi_floor_candidate=""
  _hi_pending_set _HI_PACKAGES_MIN_PRIORITY "$_hi_floor_candidate"
}

# Which of header.sh's named color ramps the packages check paints with - a
# word from a closed set (cool/warm/mono), so ask_value rather than the
# floor's re-rendering loop; the preview above still shows the check as it
# renders right now, for a by-eye comparison against the name being typed.
function config_packages_palette() {
  local current="" value
  setting_value _HI_PACKAGES_PALETTE "$_HI_SETTINGS" current
  if [ -t 0 ]; then
    _hi_load_preview_sources
    show_preview _hi_packages_palette_preview
  fi
  value="$(ask_value "Package check palette: cool, warm, or mono?" \
    "$current" cool _hi_is_packages_palette "answer cool, warm or mono")"
  _hi_pending_set _HI_PACKAGES_PALETTE "$value"
}

# Which truecolor scheme the twelve palette names render as, everywhere hi
# paints - the prompt, the header, the git segment, the packages check. A
# word from a closed set, so ask_value; `default` clears the line. Not a
# preset answer: a scheme is taste, not a feature level.
function config_color_scheme() {
  local current="" shown value n
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" current
  # a scheme of the user's own - 12 or 24 hex words, written into settings.sh
  # by hand - shows as `custom` and Enter keeps it; the list itself is never
  # typed at a prompt
  shown="$current"
  _HI_COLOR_SCHEME="$current" _hi_scheme_words n
  [ "$n" -gt 0 ] && shown=custom
  if [ -t 0 ]; then
    show_preview _hi_color_scheme_preview
    # what hi --doctor and the previews say about the same value: a word
    # nothing renders is ignored, and Enter would keep it
    if [ -n "$current" ] && [ "$n" -eq 0 ] && ! _hi_scheme_ok "$current"; then
      _hi_cecho " $current is not a scheme, so it is ignored - Enter keeps it, default clears it" "$YELLOW"
    fi
  fi
  value="$(ask_value "Color scheme: default, catppuccin, monokai, onedark, or vscode (or 12/24 hex words, written into settings.sh by hand)?" \
    "$shown" default _hi_is_color_scheme "answer default, catppuccin, monokai, onedark or vscode")"
  [ "$value" = custom ] && value="$current"
  _hi_pending_set _HI_COLOR_SCHEME "$value"
}

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

# The Prompt menu: the sample line rendered, starship as item 1, then what
# each shell's prompt ends with - one item per shell wired up locally
# (_HI_RC_TABLE's roster), since that is the point: the shipped defaults are
# different characters per shell. Those defaults come from core.sh's
# _hi_prompt_end_default rather than being spelled here a second time;
# entering the default clears the override rather than writing it, as
# config_max_width does with 80. Values are single-quoted on the way out (a
# separator is as likely to be `$` as a letter), so `'` itself is refused.
function config_prompt() {
  local reply rejects=0 max_rejects=3 row name shell default var current value state i n
  local -a shells=()
  for row in "${_HI_RC_TABLE[@]}"; do shells+=("${row%%|*}"); done
  n=$((${#shells[@]} + 1))
  section "Prompt" "Who draws the prompt, and the character each shell's prompt ends with. Enter goes back."
  while :; do
    show_preview _hi_prompt_sample_preview
    setting_off _HI_DISABLE_PROMPT "$_HI_SETTINGS" 1 &&
      _hi_cecho "   (the colored prompt is off - Features turns it on; these apply once it is)" "$YELLOW"
    IFS='|' read -r var _ _ _ _ _ _ <<<"${_HI_PROMPT_PROMPTS[0]}"
    setting_on "$var" "$_HI_SETTINGS" "" starship && state=x || state=" "
    printf '   1) [%s] %s\n' "$state" "starship draws the prompt on targets that have it"
    for i in "${!shells[@]}"; do
      name="${shells[$i]}"
      _hi_shell_var shell "$name"
      _hi_prompt_end_shown "$shell" current
      printf '   %d) %-5s prompt ends with  %s\n' "$((i + 2))" "$name" "$current"
    done
    menu_read " > " reply || return 0
    [ -n "$reply" ] || return 0
    if [ "$reply" = 1 ]; then
      rejects=0
      _hi_setting_flip "$var" "" starship state
      _hi_cecho " starship: now $state" "$GREEN"
      show_preview _hi_starship_preview
      continue
    fi
    if _hi_is_number "$reply" && [ "$reply" -ge 2 ] && [ "$reply" -le "$n" ]; then
      rejects=0
      name="${shells[$((reply - 2))]}"
      _hi_shell_var shell "$name"
      default="$(_hi_prompt_end_default "$shell")"
      var="_HI_PROMPT_END_$shell"
      current=""
      setting_value "$var" "$_HI_SETTINGS" current
      value="$(ask_value "Character to end the $name prompt with?" "$current" "$default" \
        _hi_has_no_single_quote "a single quote can't be written to settings.sh")"
      _hi_pending_set "$var" "$value"
      continue
    fi
    rejects=$((rejects + 1))
    [ "$rejects" -ge "$max_rejects" ] && {
      _hi_cecho " not an item three times - back to the menu" "$YELLOW"
      return 0
    }
    _hi_cecho " type a number from 1 to $n, or Enter to go back" "$YELLOW"
  done
}

# The advanced section's free-text half: the glyph policy and the container
# CLI roster. Each keeps its current value on Enter and clears the override
# when the answer is the shipped default, like config_max_width.
function config_advanced_values() {
  local current value choice

  # _HI_ASCII is a 1/0/unset flag; the question uses words and maps both ways,
  # since "1" for ASCII is a fact about the implementation, not an answer
  setting_value _HI_ASCII "$_HI_SETTINGS" current
  case "$current" in 1) choice=ascii ;; 0) choice=glyphs ;; *) choice="" ;; esac
  value="$(ask_value "Banner/prompt/package glyphs: auto (by the locale), glyphs, or ascii?" \
    "$choice" auto _hi_is_glyph_choice "answer auto, glyphs or ascii")"
  case "$value" in ascii) value=1 ;; glyphs) value=0 ;; *) value="" ;; esac
  _hi_pending_set _HI_ASCII "$value"

  # _HI_TRUECOLOR is the same shape as _HI_ASCII - the client's verdict on
  # its terminal, shipped to the session - and asked the same way: on is the
  # answer under tmux, which hides COLORTERM
  setting_value _HI_TRUECOLOR "$_HI_SETTINGS" current
  case "$current" in 1) choice=on ;; 0) choice=off ;; *) choice="" ;; esac
  value="$(ask_value "24-bit color for a scheme's hex: auto (by COLORTERM), on (under tmux, say), or off?" \
    "$choice" auto _hi_is_truecolor_choice "answer auto, on or off")"
  case "$value" in on) value=1 ;; off) value=0 ;; *) value="" ;; esac
  _hi_pending_set _HI_TRUECOLOR "$value"

  ask_setting_value _HI_CONTAINER_CLIS "docker podman nerdctl finch" _hi_is_cli_list \
    "plain names separated by spaces, like: docker podman" \
    "(containers) Docker-compatible CLIs hi lists and reaches containers through, in order (space-separated; podman, nerdctl and finch all speak docker's grammar)?"
}

# The advanced section: a short question walk rather than a menu - these are
# asked once in a blue moon, and Enter through them keeps every value. The
# hub's menu item is the gate; a run that never opens it never changes them.
function config_advanced() {
  section "Advanced settings" "The leading space, tmux, the glyphs, 24-bit color and the container CLI roster. Enter keeps each value."
  ask_prompt_group _HI_ADVANCED_PROMPTS
  config_advanced_values
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
  _hi_collect_group _HI_FEATURE_PROMPTS
  _hi_collect_group _HI_HEADER_PROMPTS
  _hi_collect_value _HI_HEADER_ORDER "$_HI_HEADER_ORDER_DEFAULT" quoted
  _hi_collect_value _HI_PACKAGES_MIN_PRIORITY 2
  _hi_collect_value _HI_PACKAGES_PALETTE cool
  _hi_collect_value _HI_COLOR_SCHEME ""
  _hi_collect_value _HI_IP_HIDE '172.*' quoted
  _hi_collect_value _HI_MAX_WIDTH 80
  _hi_collect_group _HI_PROMPT_PROMPTS
  for row in "${_HI_RC_TABLE[@]}"; do
    name="${row%%|*}"
    _hi_shell_var shell "$name"
    _hi_collect_value "_HI_PROMPT_END_$shell" "$(_hi_prompt_end_default "$shell")" quoted
  done
  _hi_collect_group _HI_ADVANCED_PROMPTS
  _hi_collect_value _HI_ASCII ""
  _hi_collect_value _HI_TRUECOLOR ""
  _hi_collect_value _HI_CONTAINER_CLIS "docker podman nerdctl finch" quoted
}

# _hi_has_setting_lines - is there anything to write? A loop, not
# ${#a[@]}: an empty array under `set -u` is an unbound variable on bash 3.2.
function _hi_has_setting_lines() {
  local _hi_l
  for _hi_l in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
    return 0
  done
  return 1
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
# comment and which lets editors, `file` and shellcheck see a POSIX sh script
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

function settings_diff_report() {
  local line other found changes=0
  for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
    [ -n "$line" ] || continue
    found=0
    for other in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
      [ "$other" = "$line" ] && found=1 && break
    done
    [ "$found" = 1 ] || {
      _hi_cecho "   + $line" "$GREEN"
      changes=$((changes + 1))
    }
  done
  for other in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
    found=0
    for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
      [ "$other" = "$line" ] && found=1 && break
    done
    [ "$found" = 1 ] || {
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
  configure_intro
  if [ -n "$preset" ]; then
    apply_preset "$preset" || return 1
  fi
  if [ -z "$preset" ]; then
    if [ -t 0 ]; then
      config_hub
    elif [ -n "${_HI_FEATURES_ONLY:-}" ]; then
      # the menu is this run's whole job, and there is nobody to answer it
      _hi_cecho " ${_HI_ME:-hi --configure}: no terminal for the menu - --preset <name> answers it without one (one of: $(preset_names))" "$RED" >&2
      return 1
    else
      _hi_cecho " no terminal for the settings menu - the defaults apply; hi --configure at a terminal, or --preset <name>, sets them" "$YELLOW"
    fi
  fi
  if [ -n "$_HI_CONFIGURE_QUIT" ]; then
    _hi_cecho " nothing written - $_HI_SETTINGS is as it was" "$GREEN"
    return 0
  fi
  collect_setting_lines
  # No terminal, no preset, no file and nothing to say: a settings.sh with
  # only a shebang in it would be a decision record with no decision in it.
  if [ ! -t 0 ] && [ -z "$preset" ] && [ ! -f "$_HI_SETTINGS" ] && ! _hi_has_setting_lines; then
    _hi_cecho " nothing to write - the defaults apply until hi --configure is run at a terminal" "$GREEN"
    return 0
  fi
  settings_adopt_hand_lines
  ensure_settings_shebang
  settings_diff_before
  # ${a[@]+"${a[@]}"}, not a plain "${a[@]}": on bash 3.2 (macOS) expanding
  # an *empty* array under `set -u` is a fatal "unbound variable", and
  # every setting at its default leaves exactly that - no lines to write.
  config_shell settings "$_HI_SETTINGS" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}
  settings_diff_report
}
