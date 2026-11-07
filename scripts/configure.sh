#!/usr/bin/env bash
# `hi --configure` and the second half of a plain install: a preset to start
# from, then the one write to $_HI_SETTINGS, a line per scripts/settings row.
# Sourced by scripts/install.sh after common/core.sh, scripts/lib.sh and
# scripts/table.sh; not an entry point of its own. run_configure at the
# bottom is the sequence; install.sh opens the file in the editor after it.
#
# A preset's answers land in _HI_SETTING_PENDING ("<var>=<value>", empty for
# the shipped default), ahead of what the file says; setting_value reads
# both. collect_setting_lines derives the block from them once, at write
# time, and config_shell writes it in one call (it rewrites the whole marker
# block). A setting at its default is written commented, at that default, so
# the block lists every setting and an edit is removing a `#`.

# Answers this run has taken. An indexed array: `declare -A` is bash 4.
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
function _hi_pending_set() {
  local i
  for i in ${_HI_SETTING_PENDING[@]+"${!_HI_SETTING_PENDING[@]}"}; do
    [ "${_HI_SETTING_PENDING[$i]%%=*}" = "$1" ] || continue
    _HI_SETTING_PENDING[i]="$1=$2"
    return 0
  done
  _HI_SETTING_PENDING+=("$1=$2")
}

# setting_value <var> <target> [outvar] - this run's answer, else what <target>
# sets it to, else empty
function setting_value() {
  local _hi_sv_var="$1" _hi_sv_target="$2" _hi_sv_val=""
  pending_answer "$_hi_sv_var" _hi_sv_val ||
    _hi_setting_get "$_hi_sv_target" "$_hi_sv_var" _hi_sv_val || _hi_sv_val=""
  _hi_out "${3:-}" "$_hi_sv_val"
}

# _hi_preset_list - the presets as the pick lists them: the name with its
# hotkey, padded by its visible length (a printf width counts the escapes),
# then the description
function _hi_preset_list() {
  local row name desc shown
  for row in "${_HI_PRESETS[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    _hi_hotkey "$name" "${name:0:1}" shown
    _hi_pad_to shown 13 "$shown"
    printf '   %s %b%s%b\n' "$shown" "$BLUE" "$desc" "$NC"
  done
}

# menu_read <prompt> <outvar> - one answer, trimmed and lower-cased (tr, not
# ${x,,}: that is bash 4); 1 on EOF, after closing the line `read -p` left
function menu_read() {
  local _hi_mr_reply=""
  if ! read -r -p "$1" _hi_mr_reply; then
    printf '\n' >&2
    return 1
  fi
  _hi_mr_reply="$(printf '%s' "$_hi_mr_reply" | tr '[:upper:]' '[:lower:]')"
  _hi_mr_reply="${_hi_mr_reply#"${_hi_mr_reply%%[![:space:]]*}"}"
  _hi_mr_reply="${_hi_mr_reply%"${_hi_mr_reply##*[![:space:]]}"}"
  printf -v "$2" '%s' "$_hi_mr_reply"
}

# Every row of scripts/settings as <name>, <section>, <check>, <default>, a
# \x1f between (a default can be `|`), in the table's order, which is the block's. <default> is the value the shipped
# default stands for: core.sh's $<name>_DEFAULT, else the row's <default>
# cell when it is one code span, else empty (unset, or decided at run time).
_HI_SETTING_ROWS=()
function _hi_settings_load() {
  local line sec name def check dv us=$'\x1f'
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    # <section> | <name> | <default> | <check> | <hint> | <what it does>
    IFS="$us" read -r sec name def check _ <<<"${line// | /$us}"
    dv="${name}_DEFAULT"
    if [ -n "${!dv:-}" ]; then
      def="${!dv}"
    else
      case "$def" in
      \`*\`) def="${def#\`}" def="${def%\`}" def="${def//\\|/|}" ;;
      *) def="" ;;
      esac
    fi
    _HI_SETTING_ROWS+=("$name$us$sec$us$check$us$def")
  done <"$_HI_ROOT/scripts/settings"
}
_hi_settings_load

# <name>|<one-line description>|<var=value ...>: a starting point for the
# rows of the `preset` section. A preset row the preset does not name goes
# back to its default, so a preset is an absolute answer, not a delta on the
# file; a var outside the section (lean's _HI_PROMPT_TOOL) is set, and no
# other preset changes it back. $_HI_PRESET_DEFAULT is what a first install
# starts from when nobody picks.
_HI_PRESET_DEFAULT=balanced
_HI_PRESETS=(
  "everything|every feature on, here and on every target you hi to|_HI_PACKAGES_GROUPS=core,useful,deprecated"
  "balanced|everything on every target, a shorter package check; nothing on this machine|_HI_PACKAGES_GROUPS=core,deprecated _HI_DISABLE_LOCAL=1"
  "minimal|the colored prompt and your configs, no header or editor configs; nothing on this machine|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_PLUGINS_OFF=vim,nvim,nano,emacs,hx,kak,micro _HI_DISABLE_LOCAL=1"
  "lean|minimal, and nothing of yours rides: hi's own prompt, no plugin's config, ssh the only backend|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_PLUGINS_OFF=vim,nvim,nano,emacs,hx,kak,micro,aliases,bash,zsh,fish,extensions,bin,env,starship,powerlevel10k,tide,oh-my-posh,oh-my-zsh,oh-my-bash,bash-it,eza,bat,rg,fzf,lazygit,git,readline,tmux,screen,zellij _HI_DISABLE_LOCAL=1 _HI_PROMPT_TOOL=hi _HI_BACKENDS_OFF=all"
)

# preset_row <name> - its table row, or failure for a name that is not one
function preset_row() {
  local row
  for row in "${_HI_PRESETS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    printf '%s' "$row"
    return 0
  done
  return 1
}

function preset_names() {
  local row out=""
  for row in "${_HI_PRESETS[@]}"; do out="$out${out:+ }${row%%|*}"; done
  printf '%s' "$out"
}

# preset_shorthand <letter> - the one preset whose name starts with <letter>;
# failure for anything else, so preset_row's error lists the names
function preset_shorthand() {
  local row hit="" hits=0
  [ "${#1}" -eq 1 ] || return 1
  for row in "${_HI_PRESETS[@]}"; do
    [ "${row:0:1}" = "$1" ] || continue
    hit="${row%%|*}"
    hits=$((hits + 1))
  done
  [ "$hits" -eq 1 ] || return 1
  printf '%s' "$hit"
}

# apply_preset <name> - this run's answers from the preset: every preset row
# back to its default, then the preset's values
function apply_preset() {
  local row values name sec pair vocab="" extra=""
  row="$(preset_row "$1")" || {
    _hi_cecho " no such preset: $1 (one of: $(preset_names))" "$RED" >&2
    return 1
  }
  values="${row##*|}"
  for row in "${_HI_SETTING_ROWS[@]}"; do
    IFS=$'\x1f' read -r name sec _ <<<"$row"
    [ "$sec" = preset ] || continue
    vocab="$vocab $name"
    _hi_pending_set "$name" ""
  done
  # shellcheck disable=SC2086 # the split is the point: one var=value a word
  for pair in $values; do
    _hi_pending_set "${pair%%=*}" "${pair#*=}"
    _hi_list_has "$vocab" "${pair%%=*}" || extra="$extra${extra:+, }${pair%%=*}"
  done
  _hi_cecho " starting from the '$1' preset" "$GREEN"
  [ -z "$extra" ] || _hi_cecho " it also sets $extra, which no other preset changes back" "$BLUE"
}

# config_pick_preset <default> - the one question: which preset, by its
# letter or name. Enter takes <default>, or keeps the file where it is empty;
# a name that is no preset keeps it too.
function config_pick_preset() {
  local reply="" short enter="Enter keeps your settings" shown=keep
  [ -z "$1" ] || enter="Enter is $1" shown="$1"
  _hi_cecho " How much of hi rides along? One of:" "$BLUE"
  _hi_preset_list
  menu_read " Start from which? (the bracketed letter or the name; $enter) [$shown] " reply || reply=""
  [ -n "$reply" ] || reply="$1"
  [ -n "$reply" ] || return 0
  short="$(preset_shorthand "$reply")" && reply="$short"
  apply_preset "$reply" || {
    [ -n "$1" ] || return 0
    _hi_cecho " ...so $1, the default, applies" "$YELLOW"
    apply_preset "$1"
  }
}

# Every line of the block, in scripts/settings' order: a setting whose value
# is set and not its default as `export NAME=value`, every other as that line
# commented, at the default. Written in one call by run_configure, in a
# stable order, since config_shell compares the block to decide whether the
# file is up to date.
_HI_SETTING_LINES=()

# _hi_setting_line <outvar> <name> <check> <value> - the export line, the
# value single-quoted where it is a list or free text or holds whitespace,
# and a ' in it written '\'' (which sh and fish both read)
function _hi_setting_line() {
  local _hi_sl_v="$4" _hi_sl_q="'\\''"
  if [ -z "$_hi_sl_v" ]; then
    printf -v "$1" 'export %s=' "$2"
    return 0
  fi
  case "$3" in
  toggle | flag | number:* | duration | prompts | editor)
    case "$_hi_sl_v" in
    *[[:space:]]* | *\'*) ;;
    *)
      printf -v "$1" 'export %s=%s' "$2" "$_hi_sl_v"
      return 0
      ;;
    esac
    ;;
  esac
  printf -v "$1" "export %s='%s'" "$2" "${_hi_sl_v//\'/$_hi_sl_q}"
}

function collect_setting_lines() {
  local row name check def value line
  _HI_SETTING_LINES=("# every setting, a line each: a # in front leaves it at its default, and hi --doctor checks the rest")
  for row in "${_HI_SETTING_ROWS[@]}"; do
    IFS=$'\x1f' read -r name _ check def <<<"$row"
    setting_value "$name" "$_HI_SETTINGS" value
    if [ -n "$value" ] && [ "$value" != "$def" ]; then
      _hi_setting_line line "$name" "$check" "$value"
    else
      _hi_setting_line line "$name" "$check" "$def"
      line="# $line"
    fi
    _HI_SETTING_LINES+=("$line")
  done
}

# A line written by hand outside the block - `export _HI_TRUECOLOR=1`, the
# way COLORS.md says to force 24-bit color - is read by setting_value and
# would then be written twice. Adopted instead: for every name the block
# sets, the un-marked line goes and the block's carries its value.
function settings_adopt_hand_lines() {
  local line name
  [ -f "$_HI_SETTINGS" ] || return 0
  for line in "${_HI_SETTING_LINES[@]}"; do
    case "$line" in export\ *) ;; *) continue ;; esac
    name="${line#export }"
    name="${name%%=*}"
    # not `grep -q`: under pipefail its early exit SIGPIPEs the writer (SYNTAX.md)
    grep -v -F "$_HI_MARKER" "$_HI_SETTINGS" |
      grep -E "^[[:space:]]*(export[[:space:]]+)?$name=" >/dev/null || continue
    dry_run_say "adopt the hand-written $name line in $_HI_SETTINGS" && continue
    _hi_rewrite "$_HI_SETTINGS" \
      "/^[[:space:]]*\\(export[[:space:]]\\{1,\\}\\)\\{0,1\\}$name=/{/$_HI_MARKER/!d;}"
    _hi_cecho " adopted your hand-written $name line into the settings block" "$BLUE"
  done
}

# $_HI_SETTINGS holds only `export NAME=value` lines and comments, so it gets
# a real `#!/bin/sh` line 1, which every shell that sources it reads as a
# comment; any other shebang is replaced. config_shell keeps it, outside its
# block.
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

# What this run changed, as +/- lines against the block's export lines
# before it: a diff of line sets, since a moved line is no change. Read
# before config_shell writes, printed after.
function settings_diff_before() {
  local line
  _HI_SETTINGS_BEFORE=()
  [ -f "$_HI_SETTINGS" ] || return 0
  while IFS= read -r line; do
    line="${line%"$_HI_MARKER"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in export\ *) _HI_SETTINGS_BEFORE+=("$line") ;; esac
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
  local line changes=0
  for line in "${_HI_SETTING_LINES[@]}"; do
    case "$line" in export\ *) ;; *) continue ;; esac
    _hi_in_list "$line" ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"} && continue
    _hi_cecho "   + $line" "$GREEN"
    changes=$((changes + 1))
  done
  for line in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
    _hi_in_list "$line" "${_HI_SETTING_LINES[@]}" && continue
    _hi_cecho "   - $line (back to the default)" "$YELLOW"
    changes=$((changes + 1))
  done
  [ "$changes" = 0 ] && _hi_cecho "   no changes" "$GREEN"
  return 0
}

# The sequence, then the one write. $1 is a preset name, or empty: with one,
# nothing is asked. A terminal is asked for a preset - on a first install
# with $_HI_PRESET_DEFAULT on Enter, under --configure with Enter keeping the
# file. With no terminal a first install takes the default preset, and
# --configure, which has only the question and the editor to offer, refuses.
function run_configure() {
  local preset="${1:-}"
  if [ -n "$preset" ]; then
    apply_preset "$preset" || return 1
  elif [ -t 0 ] && [ -n "${_HI_FEATURES_ONLY:-}" ]; then
    config_pick_preset ""
  elif [ -n "${_HI_FEATURES_ONLY:-}" ]; then
    _hi_cecho " ${_HI_ME:-hi --configure}: no terminal to ask or edit at - --preset <name> answers without one (one of: $(preset_names)), and hi --edit settings.sh opens the file" "$RED" >&2
    return 1
  elif [ -f "$_HI_SETTINGS" ]; then
    _hi_cecho " your settings stay as they are - hi --configure changes them" "$GREEN"
  elif [ -t 0 ]; then
    config_pick_preset "$_HI_PRESET_DEFAULT"
    _hi_cecho " hi --configure opens every other setting in your editor" "$BLUE"
  else
    _hi_cecho " no terminal to ask - the $_HI_PRESET_DEFAULT preset applies; hi --configure at a terminal, or --preset <name>, changes it" "$YELLOW"
    apply_preset "$_HI_PRESET_DEFAULT"
  fi
  collect_setting_lines
  settings_adopt_hand_lines
  ensure_settings_shebang
  settings_diff_before
  # The block opens on its shape line, which convert_settings.sh and
  # hi --doctor read in place of guessing the shape from the rows.
  config_shell settings "$_HI_SETTINGS" "# say-hi settings $_HI_SETTINGS_SHAPE" "${_HI_SETTING_LINES[@]}" || return 1
  settings_diff_report
}
