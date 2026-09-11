#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The settings wizard behind `hi --configure` (and the second half of a plain
# install): one flat menu of every setting under a live preview, and the one
# write to $_HI_SETTINGS. Sourced by scripts/install.sh after
# common/core.sh and scripts/table.sh; not an entry point of its own.
# run_configure at the bottom is the sequence.
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
# ($4) has to be written out, like _HI_PROMPT_TOOL=starship - is on only when its
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

# _hi_pending_state <var> <off> <on> <on|off> - which of two value shapes a
# setting takes, in one place: an opt-in (a nonempty <on>) writes its
# on-value when switched on and clears the pending line when switched off; a
# default-on toggle (empty <on>) does the reverse - clears when on, writes
# its off-value when off. Getting this backwards writes a silently inverted
# setting, which is why every site that flips one calls this.
function _hi_pending_state() {
  local var="$1" off="$2" on="$3" want="$4"
  if [ "$want" = on ]; then
    _hi_pending_set "$var" "$on"
  elif [ -n "$on" ]; then
    _hi_pending_set "$var" ""
  else
    _hi_pending_set "$var" "$off"
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
    _hi_pending_state "$var" "$off" "$on" off
    printf -v "$4" '%s' off
  else
    _hi_pending_state "$var" "$off" "$on" on
    printf -v "$4" '%s' on
  fi
}

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

# _hi_hotkey <name> <letter> <outvar> - <name> with its shortcut letter in
# brackets, [e]verything or p[r]ompt: how every menu here spells an option
# whose letter is typed rather than its number, so the key and the word
# are read together and nothing has to say "or type e". The key is painted
# $BRYELLOW, the color of everything the wizard has you type.
function _hi_hotkey() {
  local name="$1" key="$2" head
  head="${name%%"$key"*}"
  if [ "$head" = "$name" ]; then
    printf -v "$3" '%s' "$name"
  else
    printf -v "$3" '%s%b[%s]%b%s' "$head" "$BRYELLOW" "$key" "$NC" "${name#*"$key"}"
  fi
}

# _hi_paint <outvar> <color> <text> - <text> in <color>, the palette's
# escapes expanded so the result can be joined into a row or a `read -p`
# prompt. Under $NO_COLOR both halves are empty (core.sh) and it is plain.
function _hi_paint() {
  printf -v "$1" '%b%s%b' "$2" "$3" "$NC"
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
    printf '   %s%*s %b%s%b\n' "$shown" $(($2 - ${#name} - 2)) '' "$BLUE" "$desc" "$NC"
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
  _hi_cecho " $3" "$YELLOW"
}

function _hi_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
# a header width: 40 columns is the narrowest the banner and rows draw in
function _hi_is_width() { _hi_is_number "$1" && [ "$1" -ge 40 ]; }

# a settings.sh value has to survive being written into a single-quoted export
function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

function _hi_is_truecolor_choice() {
  case "$1" in auto | on | off) ;; *) return 1 ;; esac
}

# $_HI_IP_HIDE's vocabulary: the word `none`, or space-separated globs over
# dotted-quad addresses - digits, dots, `*`, and `?` - nothing else, so a
# stray quote or a shell metacharacter can't be written into settings.sh
function _hi_is_ip_hide() {
  case "$1" in
  none) return 0 ;;
  '' | *[!0-9.*?\ ]*) return 1 ;;
  esac
}

# _hi_is_header_word <word> - one of $_HI_HEADER_ORDER's vocabulary, read off
# header.sh's own $_HI_HEADER_ORDER_DEFAULT rather than a second copy of the
# word list here (a second copy would drift)
function _hi_is_header_word() {
  _hi_load_preview_sources
  case " $_HI_HEADER_ORDER_DEFAULT " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
function show_preview() {
  local out content_w=0 len line top fill_top i
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
  # the top rule carries a label _hi_hbar has no room for, so only it is
  # spelled out here; the bottom rule and every row are table.sh's own
  # primitives, the same ones every other box in this file draws with
  _hi_repeat fill_top $((content_w + 2 - ${#label})) "$_HI_BOX_H"
  top="$_HI_BOX_TL${label}${fill_top}$_HI_BOX_TR"
  _hi_cecho "   $top" "$NC"
  for i in "${!lines[@]}"; do
    printf '   '
    _hi_cell_raw "$content_w" "${lens[i]}" "${lines[i]}"
    _hi_row_end
  done
  printf '   '
  _hi_hbar bottom "$content_w"
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
  setting_value _HI_DISABLE_LEAD_SPACE "$_HI_SETTINGS" lead
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" scheme
  (
    export _HI_HEADER_ORDER="$order" _HI_DISABLE_BANNER="${banner:-0}" _HI_MAX_WIDTH="${width:-80}"
    export _HI_PACKAGES_MIN_PRIORITY="${floor:-2}" _HI_PACKAGES_PALETTE="$palette"
    export _HI_DISABLE_LEAD_SPACE="${lead:-0}" _HI_IP_HIDE="${iphide:-172.*}"
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

# the environment segment for whatever is active in this shell, with
# _HI_DISABLE_ENV_STATUS unset for the call the way the git preview does it.
# Most runs have nothing active, so the shape stands in for a blank line.
function _hi_env_status_preview() {
  local out
  # shellcheck disable=SC2119 # stdout form on purpose - this feeds show_preview
  out="$(unset _HI_DISABLE_ENV_STATUS && _hi_env_prompt)"
  [ -n "$out" ] || out="(mise|direnv:proj|myproj) "
  printf '%b\n' "$BRCYAN$out$NC"
}

# the whole prompt line as bash would draw it at this run's answers:
# user@host cwd, the git segment when that is on, and the end character -
# or a sentence, when the colored prompt itself is off
function _hi_prompt_sample_preview() {
  local prompt git="" env="" end scheme
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
  # only what is really active here: the shape _hi_env_status_preview falls
  # back to would be a fiction in a line claiming to be this session's prompt
  # shellcheck disable=SC2119 # stdout form on purpose
  setting_off _HI_DISABLE_ENV_STATUS "$_HI_SETTINGS" 1 || env="$(_hi_env_prompt)"
  [ -n "$env" ] && env="$BRCYAN$env$NC"
  _hi_prompt_end_shown BASH end
  printf '%b%s%s %s\n' "$env" "$prompt" "$git" "$end"
}

# The hub's picture: the header as it would print, then the prompt line as
# it would draw - the two things every session shows. Each half says "off"
# in words when it is, so the box always has something to show.
function _hi_config_preview() {
  _hi_header_preview
  printf '\n'
  _hi_prompt_sample_preview
}

# what each editor alias actually resolves to with the override on - read
# back from settings/aliases.sh itself (the overlay's copy on a target)
# rather than restated here, so a box with neither nvim nor vim, say, shows
# nothing for that line instead of a resolved command that was never real. A
# subshell: nothing this defines should survive past the preview.
# load.sh's _hi_session_editor reads an alias body back the same way; the
# eval re-parses bash's own quoting of it (kak's alias nests a quote).
function _hi_editors_preview() {
  (
    # shellcheck disable=SC2030 # lives and dies in this subshell, same as
    # _hi_tool_alias_preview's own export below sourcing the same file
    _HI_DISABLE_EDITORS=0
    # shellcheck disable=SC2031 # lives and dies in this subshell
    # shellcheck source=../settings/aliases.sh
    source "$_HI_ALIASES" >/dev/null 2>&1
    local e body
    for e in nano vim emacs hx kak micro; do
      body="$(alias "$e" 2>/dev/null)" || continue
      eval "body=${body#*=}"
      printf '%-5s -> %s\n' "$e" "$body"
    done
  )
}

# what `cat` and `eza` resolve to with the rebinds on - read back from
# settings/aliases.sh itself (the same trick _hi_editors_preview uses above)
# rather than restated here, so a BAT_CONFIG_PATH that drops --theme, say,
# shows up here too instead of drifting from what a real session gets. The
# resolution caches into _HI_*_BIN/_HI_*_OPTS on export, so those are cleared
# first to force a fresh probe of $PATH rather than reusing another preview's.
function _hi_tool_alias_preview() {
  (
    _HI_DISABLE_TOOL_ALIASES=0
    _HI_CAT_BIN="" _HI_BAT_BIN="" _HI_EXA_BIN="" _HI_EZA_BIN=""
    _HI_BAT_OPTS="" _HI_EXA_OPTS="" _HI_EZA_OPTS=""
    # shellcheck disable=SC2031 # lives and dies in this subshell
    # shellcheck source=../settings/aliases.sh
    source "$_HI_ALIASES" >/dev/null 2>&1
    if [ -n "$_HI_BAT_BIN" ]; then
      printf 'cat -> %s %s\n' "$_HI_CAT_BIN" "$_HI_BAT_OPTS"
    else
      printf 'bat is not installed here - only targets that have it are affected\n'
    fi
    if [ -n "$(command -v eza || command -v exa)" ]; then
      printf 'eza -> %s %s\n' "$_HI_EZA_BIN" "$_HI_EZA_OPTS"
    else
      printf 'eza is not installed here - only targets that have it are affected\n'
    fi
  )
}

# what the tool integration would wire in here: only the tools installed
function _hi_tool_init_preview() {
  local t found=""
  for t in zoxide atuin; do
    command -v "$t" >/dev/null 2>&1 && found="$found $t"
  done
  if [ -n "$found" ]; then
    printf 'installed here:%s - wired into every session on a target that has it\n' "$found"
  else
    printf 'neither zoxide nor atuin is installed here - only targets that have one are affected\n'
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
# out of config_packages_floor's scope: show_preview already runs "$@", so a
# bare global would couple the two for nothing.
function _hi_packages_floor_preview() {
  local out candidate="${1:-2}"
  out="$(_HI_PACKAGES_MIN_PRIORITY="$candidate" full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " nothing - the check is off at this floor" "$YELLOW"
  fi
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
# <needs> names a command the setting is moot without: the menu says so
# beside it. <label> is the menu's name for it, and its part before " - " is
# what the flip reports. Adding a setting is one row, and every
# `_HI_*_PROMPTS` table is what tests/lint's settings-table check reads.
_HI_FEATURE_PROMPTS=(
  "_HI_DISABLE_HEADER|1||||connect/disconnect header - its items are under Header"
  "_HI_DISABLE_PROMPT|1||_hi_prompt_preview||colored user@host prompt"
  "_HI_DISABLE_GIT_STATUS|1||_hi_git_status_preview||git status in the prompt"
  "_HI_DISABLE_ENV_STATUS|1||_hi_env_status_preview||environment segment in the prompt - (myproj) for a venv, ..."
  "_HI_DISABLE_EDITORS|1||_hi_editors_preview||editor config overrides - vim, nano, emacs, helix, kakoune, micro"
  "_HI_DISABLE_TOOL_ALIASES|1||_hi_tool_alias_preview||styled tool aliases - cat -> bat, exa/eza"
  "_HI_DISABLE_TOOL_INIT|1||_hi_tool_init_preview||zoxide/atuin shell integration"
  "_HI_DISABLE_SUDO_ALIAS|1||||sudo alias - aliases survive under sudo"
  "_HI_DISABLE_MARKS|1||||prompt marks and cwd reporting (OSC 133/7)"
  "_HI_DISABLE_LOCAL|1||||all of the above on this machine too, not just where you hi"
)

# The one header row with a hide switch of its own: banner is not part of
# $_HI_HEADER_ORDER's reorderable feature list (it always leads). Every other
# row is addressed at the finer feature grain, as the menu's header items.
_HI_HEADER_PROMPTS=(
  "_HI_DISABLE_BANNER|1||||banner - the ~~~ Connected [host] ~~~ line, always first"
)

# whether to hand the prompt to starship where a target has one. An opt-in,
# never auto-detected - core.sh's _hi_wants_prompt_tool, which also takes
# _HI_PROMPT_TOOL=oh-my-posh written by hand (no menu item: one toggle, one tool)
_HI_PROMPT_PROMPTS=(
  "_HI_PROMPT_TOOL||starship|_hi_starship_preview||starship - draws the prompt on targets that have it"
)

# settings most installs never touch, listed last
_HI_ADVANCED_PROMPTS=(
  "_HI_DISABLE_LEAD_SPACE|0|1|||drop the leading space - before the prompt and header lines"
  "_HI_MUX|0|1|||default every connect to --mux - a local tmux, zellij, or screen session"
)

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
  "everything|every feature and every header item on - the shipped defaults|"
  "balanced|everything but the noise: a shorter package check|_HI_PACKAGES_MIN_PRIORITY=3"
  "minimal|on targets only the colored prompt and the aliases - no header, git status, editors, tool integration, or prompt marks; nothing at all on this machine|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_DISABLE_EDITORS=1 _HI_DISABLE_TOOL_INIT=1 _HI_DISABLE_MARKS=1 _HI_DISABLE_LOCAL=1"
)

# every variable a preset answers for: the feature and header yes/no tables,
# plus the one dial - so "not named by the preset" can mean "back to the
# default". _HI_PROMPT_TOOL (starship) stays out, like the color scheme and the
# packages ramp: those are taste, not a feature level, and no preset has an
# opinion on them. Neither is asked here at all - both are written into
# settings.sh by hand (GLOSSARY: HI.50).
function _hi_preset_vocab() {
  local row
  for row in "${_HI_FEATURE_PROMPTS[@]}" "${_HI_HEADER_PROMPTS[@]}"; do
    printf '%s\n' "${row%%|*}"
  done
  printf '%s\n' _HI_PACKAGES_MIN_PRIORITY
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
  local state="none yet - defaults apply"
  # no `|| echo 0`: grep -c already prints 0 on no match, then exits 1
  [ -f "$_HI_SETTINGS" ] && state="$(grep -cF "$_HI_MARKER" "$_HI_SETTINGS" 2>/dev/null) setting(s) stored"
  _hi_cecho " The preview shows what a session will look like at your current settings." "$BLUE"
  _hi_cecho " Type a number to flip a setting or change its value, or [p] for a preset." "$BLUE"
  _hi_cecho " Nothing is written until you save with [s]; [q] leaves the file untouched." "$BLUE"
  _hi_cecho " settings: $_HI_SETTINGS ($state)" "$BLUE"
}

# The menu is one numbered list of every setting the wizard asks, no
# submenus. _HI_MENU_ITEMS says what each number is, rebuilt as the list
# draws: row|<table>|<index> a yes/no row, word|<index> a header item,
# end|<shell> a prompt separator, or width, floor, iphide, truecolor.
# _HI_MENU_WORD0 is the first header item's number, for up/down.
_HI_MENU_ITEMS=()
_HI_MENU_WORD0=0

# What the last command said, printed under the next list rather than as it
# happened, so the redraw does not scroll it away: the colored line, and a
# preview function to box beneath it.
_HI_MENU_NOTE=""
_HI_MENU_NOTE_PREVIEW=""

# _hi_menu_note <message> <color> [preview-fn]
function _hi_menu_note() {
  _HI_MENU_NOTE="$(_hi_cecho "$1" "$2")"
  _HI_MENU_NOTE_PREVIEW="${3:-}"
}

# The list's colors, so a row scans without reading it: the number you type
# $BRYELLOW, a green [x] on and a red [ ] off, a current value $BRPURPLE, the
# help after a label's " - " $BLUE like the intro's, a missing command's note
# $YELLOW.
# _hi_menu_add <kind> <text> [no_newline] - number the next item and draw it
function _hi_menu_add() {
  _HI_MENU_ITEMS+=("$1")
  printf '  %b%2d)%b %s' "$BRYELLOW" "${#_HI_MENU_ITEMS[@]}" "$NC" "$2"
  [ $# -ge 3 ] || printf '\n'
}

# _hi_menu_check <outvar> <1|0> - a row's checkbox
function _hi_menu_check() {
  if [ "$2" = 1 ]; then _hi_paint "$1" "$BRGREEN" "[x]"; else _hi_paint "$1" "$RED" "[ ]"; fi
}

# _hi_menu_value <kind> <label> <value> - an item that asks for a value,
# indented past the [x] the yes/no rows carry
function _hi_menu_value() {
  local _hi_mv_text
  printf -v _hi_mv_text '    %-22s %b%s%b' "$2" "$BRPURPLE" "$3" "$NC"
  _hi_menu_add "$1" "$_hi_mv_text"
}

# _hi_menu_rows <table> - a yes/no table's rows, checked when on. A row whose
# <needs> command is absent here says so but still toggles - the setting
# applies wherever the command exists.
function _hi_menu_rows() {
  local i var off on needs label state help="" note=""
  local -a rows=()
  _hi_prompt_rows "$1" rows
  for i in ${rows[@]+"${!rows[@]}"}; do
    IFS='|' read -r var off on _ needs label <<<"${rows[$i]}"
    setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && state=1 || state=0
    _hi_menu_check state "$state"
    help="" note=""
    case "$label" in *' - '*) _hi_paint help "$BLUE" " - ${label#* - }" ;; esac
    if [ -n "$needs" ] && ! command -v "$needs" >/dev/null 2>&1; then
      _hi_paint note "$YELLOW" " ($needs is not installed here)"
    fi
    _hi_menu_add "row|$1|$i" "$state ${label%% - *}$help$note"
  done
}

# The list, under a heading per group. Header holds the banner, the header's
# items in the order they print - three to a line, so seventeen of them fit
# a screen - then its width, the package check's depth, and the hidden
# addresses, since the rendered header is what each of those changes.
function _hi_menu_list() {
  local i state word width floor iphide tc row name shell end cols=3
  _HI_MENU_ITEMS=()
  _hi_cecho " Features" "$BRCYAN"
  _hi_menu_rows _HI_FEATURE_PROMPTS
  _hi_cecho " Header" "$BRCYAN" 1
  _hi_cecho " - in the order it prints; up N / down N moves an item" "$BLUE"
  _hi_menu_rows _HI_HEADER_PROMPTS
  _HI_MENU_WORD0=$((${#_HI_MENU_ITEMS[@]} + 1))
  for i in "${!_HI_HDR_WORDS[@]}"; do
    _hi_menu_check state "${_HI_HDR_ON[$i]}"
    printf -v word '%-11s' "${_HI_HDR_WORDS[$i]}"
    _hi_menu_add "word|$i" "$state $word" 1
    [ $(((i + 1) % cols)) != 0 ] || printf '\n'
  done
  [ $((${#_HI_HDR_WORDS[@]} % cols)) = 0 ] || printf '\n'
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" width
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" floor
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  _hi_menu_value width "width" "${width:-80}"
  _hi_menu_value floor "package check depth" "${floor:-2}"
  _hi_menu_value iphide "hidden addresses" "${iphide:-172.*}"
  _hi_cecho " Prompt" "$BRCYAN"
  _hi_menu_rows _HI_PROMPT_PROMPTS
  # one separator per shell wired up locally (_HI_RC_TABLE's roster): the
  # shipped defaults are a different character per shell
  for row in "${_HI_RC_TABLE[@]}"; do
    name="${row%%|*}"
    _hi_shell_var shell "$name"
    _hi_prompt_end_shown "$shell" end
    _hi_menu_value "end|$name" "$name prompt ends with" "$end"
  done
  _hi_cecho " Advanced" "$BRCYAN"
  _hi_menu_rows _HI_ADVANCED_PROMPTS
  setting_value _HI_TRUECOLOR "$_HI_SETTINGS" tc
  case "$tc" in 1) tc=on ;; 0) tc=off ;; *) tc=auto ;; esac
  _hi_menu_value truecolor "24-bit color" "$tc"
}

# _hi_menu_pick <n> - act on item <n>: flip a yes/no row or a header item,
# or ask for a value
function _hi_menu_pick() {
  local kind a b var off on preview label state
  local -a rows=()
  IFS='|' read -r kind a b <<<"${_HI_MENU_ITEMS[$(($1 - 1))]}"
  case "$kind" in
  row)
    _hi_prompt_rows "$a" rows
    IFS='|' read -r var off on preview _ label <<<"${rows[$b]}"
    _hi_setting_flip "$var" "$off" "$on" state
    _hi_menu_note " ${label%% - *}: now $state" "$GREEN" "$preview"
    ;;
  word)
    # an empty $_HI_HEADER_ORDER means the default order at runtime, not
    # none, so the last item stays on
    if [ "${_HI_HDR_ON[$a]}" = 1 ] && [ "$(_hi_header_edit_count_on)" -le 1 ]; then
      _hi_menu_note " keep at least one header item - item 1 turns the whole header off" "$YELLOW"
    else
      [ "${_HI_HDR_ON[$a]}" = 1 ] && _HI_HDR_ON[a]=0 || _HI_HDR_ON[a]=1
      _hi_header_edit_commit
    fi
    ;;
  width) config_max_width ;;
  floor) config_packages_floor ;;
  iphide) config_ip_hide ;;
  end) config_prompt_end "$a" ;;
  truecolor) config_truecolor ;;
  esac
}

# The menu: the preview, the list, save, or quit. A command redraws both with
# whatever it changed; a reply that is not one only says so, under the list
# it was typed against. EOF saves - the same "no answer keeps what you have
# and the run completes" that every question here has always meant. The
# third junk answer in a row ends the run too, but as a quit: three words
# that are not menu items are not an instruction to write the file. Enter
# alone redraws.
_HI_CONFIGURE_QUIT=""
function config_hub() {
  local reply cmd arg idx last rejects=0 max_rejects=3 draw=1 p h s q
  _hi_probe_once
  _hi_header_edit_load
  while :; do
    if [ -n "$draw" ]; then
      _hi_h2 "hi --configure"
      show_preview _hi_config_preview
      _hi_menu_list
      _hi_hotkey preset p p
      _hi_hotkey "header preset" h h
      _hi_hotkey "save and exit" s s
      _hi_hotkey "quit without writing" q q
      printf '   %s  %s  %s  %s\n' "$p" "$h" "$s" "$q"
      if [ -n "$_HI_MENU_NOTE" ]; then
        printf '%s\n' "$_HI_MENU_NOTE"
        [ -z "$_HI_MENU_NOTE_PREVIEW" ] || show_preview "$_HI_MENU_NOTE_PREVIEW"
      fi
      _HI_MENU_NOTE="" _HI_MENU_NOTE_PREVIEW=""
    fi
    draw=1
    menu_read " > " reply || return 0
    cmd="${reply%% *}" arg=""
    [ "$cmd" != "$reply" ] && arg="${reply#* }"
    last=$((_HI_MENU_WORD0 + ${#_HI_HDR_WORDS[@]} - 1))
    case "$cmd" in
    '') ;;
    p | preset) config_preset ;;
    h | header) config_header_preset ;;
    up | u | down | d)
      if _hi_is_number "$arg" && [ "$arg" -ge "$_HI_MENU_WORD0" ] && [ "$arg" -le "$last" ]; then
        idx=$((arg - _HI_MENU_WORD0))
        case "$cmd" in u*) _hi_header_edit_move "$idx" -1 ;; *) _hi_header_edit_move "$idx" 1 ;; esac
      else
        _hi_menu_note " up/down take a header item, $_HI_MENU_WORD0 to $last - the banner always leads" "$YELLOW"
      fi
      ;;
    s | save) return 0 ;;
    q | quit)
      _HI_CONFIGURE_QUIT=1
      return 0
      ;;
    *)
      if _hi_is_number "$cmd" && [ "$cmd" -ge 1 ] && [ "$cmd" -le "${#_HI_MENU_ITEMS[@]}" ]; then
        _hi_menu_pick "$cmd"
      else
        draw=""
        _hi_menu_reject rejects "$max_rejects" \
          "type an item number (1-${#_HI_MENU_ITEMS[@]}), up N / down N, or [p] [h] [s] [q]" && continue
        _hi_cecho " not a menu item three times - leaving $_HI_SETTINGS as it was" "$YELLOW"
        _HI_CONFIGURE_QUIT=1
        return 0
      fi
      ;;
    esac
    rejects=0
  done
}

# <name>|<one-line description>|<words>: a starting point for the header
# items. Empty words mean the shipped order - the same spelling
# $_HI_HEADER_ORDER itself uses for "the default" - rather than a second copy
# of header.sh's word list.
_HI_HEADER_PRESETS=(
  "full|every item, in the shipped order|"
  "compact|the clocks, the version, your git identity, the backend counts, and the package check|utc version localtime gitid containers jobs pods check"
  "quiet|just the clocks and your git identity|utc localtime gitid"
)

# The menu's working copy of $_HI_HEADER_ORDER: every word of the
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

# how many words are on - the menu refuses to turn the last one off, since
# an empty $_HI_HEADER_ORDER means the default order at runtime, not none
function _hi_header_edit_count_on() {
  local i n=0
  for i in "${!_HI_HDR_ON[@]}"; do [ "${_HI_HDR_ON[$i]}" = 1 ] && n=$((n + 1)); done
  printf '%d' "$n"
}

# _hi_header_edit_preset <name> - the header items from a header preset:
# its words first and on, in its order, everything else off after
function _hi_header_edit_preset() {
  local row words
  for row in "${_HI_HEADER_PRESETS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    words="${row##*|}"
    _hi_pending_set _HI_HEADER_ORDER "$words"
    _hi_header_edit_load
    _hi_header_edit_commit
    _hi_menu_note " header: the '$1' preset" "$GREEN"
    return 0
  done
  return 1
}

# _hi_header_edit_move <index> <-1|+1> - swap a word with its neighbor
function _hi_header_edit_move() {
  local i="$1" j=$(($1 + $2)) w o
  if ((j < 0 || j >= ${#_HI_HDR_WORDS[@]})); then
    _hi_menu_note " ${_HI_HDR_WORDS[$i]} is already at that end" "$YELLOW"
    return 0
  fi
  w="${_HI_HDR_WORDS[$i]}" o="${_HI_HDR_ON[$i]}"
  _HI_HDR_WORDS[i]="${_HI_HDR_WORDS[j]}" _HI_HDR_ON[i]="${_HI_HDR_ON[j]}"
  _HI_HDR_WORDS[j]="$w" _HI_HDR_ON[j]="$o"
  _hi_header_edit_commit
}

# the menu's [h]eader preset pick: one shot, like config_preset
function config_header_preset() {
  local reply="" short=""
  _hi_preset_list _HI_HEADER_PRESETS 10
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
  _hi_menu_note " no such header preset: $reply" "$YELLOW"
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
  local current reply rejects=0 max_rejects=3 _hi_floor_candidate shown
  current=""
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" current
  _hi_floor_candidate="${current:-2}"
  if [ -t 0 ]; then
    _hi_load_preview_sources
    while :; do
      show_preview _hi_packages_floor_preview "$_hi_floor_candidate"
      # menu_read carries the EOF contract (read, close the prompt line, rc 1);
      # its lowercase-and-squeeze is a no-op on a number
      _hi_paint shown "$BRPURPLE" "[$_hi_floor_candidate]"
      menu_read " Lowest package priority to show (0-3, or 4 to turn the check off)? $shown " reply || break
      [ -z "$reply" ] && break
      if ! _hi_is_number "$reply" || [ "$reply" -gt 4 ]; then
        _hi_menu_reject rejects "$max_rejects" \
          "not 0-4 - type a priority, 4 to turn the check off, or press Enter to keep $_hi_floor_candidate" && continue
        _hi_cecho " not 0-4, leaving it at $_hi_floor_candidate" "$YELLOW"
        break
      fi
      # shellcheck disable=SC2034 # read by _hi_menu_reject's ${!1}, not by name
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
  _hi_collect_group _HI_FEATURE_PROMPTS
  _hi_collect_group _HI_HEADER_PROMPTS
  _hi_collect_value _HI_HEADER_ORDER "$_HI_HEADER_ORDER_DEFAULT" quoted
  _hi_collect_value _HI_ENV_ORDER "$_HI_ENV_ORDER_DEFAULT" quoted
  _hi_collect_value _HI_PACKAGES_MIN_PRIORITY 2
  _hi_collect_value _HI_PACKAGES_PALETTE ""
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
  config_shell settings "$_HI_SETTINGS" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}
  settings_diff_report
}
