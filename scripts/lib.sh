#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The tooling-side helpers scripts/, packaging/, docs/tapes/, and tests/ share:
# flag parsing, the heading rules, the sed-rewrite primitive, the settings and
# scheme readers, and the box glyphs. None of it belongs in common/core.sh -
# common/ ships in the ssh payload and wears a CI-enforced size budget, and
# nothing a target runs draws a heading or rewrites a file in place. Source it
# *after* common/core.sh, whose _hi_repeat, _hi_cecho, and palette it uses;
# sourcing it does nothing else.

# _hi_die <msg> - "$_HI_ME: <msg>" in red on stderr, then exit 1: every
# refusal a script makes before it does anything.
function _hi_die() {
  _hi_cecho "$_HI_ME: $1" "$RED" >&2
  exit 1
}

# _hi_flag_word_or_die <outvar> <errmsg> <flag> [next] - _hi_flag_word, but a
# bare flag with nothing after it _hi_die's with <errmsg> rather than handing
# the caller a status to branch on. Status 2 (it took <next>, the caller must
# shift again) still comes back, the one case every call site still has to
# act on.
function _hi_flag_word_or_die() {
  local outvar="$1" msg="$2"
  shift 2
  _hi_flag_word "$outvar" "$@" && return 0
  case $? in
  2) return 2 ;;
  *) _hi_die "$msg" ;;
  esac
}

# _hi_on_path <dir> - true when <dir> is a colon-delimited member of $PATH
function _hi_on_path() {
  case ":$PATH:" in
  *":$1:"*) return 0 ;;
  *) return 1 ;;
  esac
}

# _hi_missing_tools <name...> - those of <name...> this machine does not have,
# space-separated, in the order given.
function _hi_missing_tools() {
  local tool missing=""
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing$tool "
  done
  printf '%s' "${missing% }"
}

# dry_run_say <what> - under --dry-run ($_HI_DRY_RUN: install.sh's flag, and
# add_package.sh's), say what would happen and succeed, so the caller returns
# before it writes; otherwise fail quietly and the caller carries on. Every
# writer either of them reaches opens with one of these.
function dry_run_say() {
  [ -n "${_HI_DRY_RUN:-}" ] || return 1
  _hi_cecho " dry run: would $1" "$BLUE"
  return 0
}

# tmp -> dest through dest's existing inode: cat, not mv, or mktemp's 0600
# lands on the destination and severs any hardlink/ACL. The mode is captured
# and reapplied too, since truncate-in-place alone did not preserve it on
# Windows Git Bash. GLOSSARY: HI.09
function _hi_write_back() {
  local mode=""
  [ -e "$2" ] && mode="$(stat -c '%a' "$2" 2>/dev/null || stat -f '%Lp' "$2" 2>/dev/null)"
  cat "$1" >"$2"
  [ -n "$mode" ] && chmod "$mode" "$2" 2>/dev/null
  command rm -f "$1"
}

# The TOML files (config/packages, config/colors) as the editing scripts hold
# them: a global `_hi_rows` array of lines, one per file line.

# _hi_toml_table <outvar> <line> - the name a `[table]` line gives, or 1
function _hi_toml_table() {
  local _hi_tt="${2#"${2%%[![:space:]]*}"}"
  case "$_hi_tt" in '['*']'*) ;; *) return 1 ;; esac
  _hi_tt="${_hi_tt#\[}"
  printf -v "$1" '%s' "${_hi_tt%%\]*}"
}

# _hi_toml_key <outvar> <name> - <name> as a key: bare where TOML reads it
# bare, in double quotes otherwise
function _hi_toml_key() {
  case "$2" in
  '' | *[!A-Za-z0-9_-]*) printf -v "$1" '"%s"' "$2" ;;
  *) printf -v "$1" '%s' "$2" ;;
  esac
}

# _hi_section_of <outvar> <index> - the table the line at <index> of `_hi_rows`
# sits in: the nearest `[...]` line above it, empty above the first
function _hi_section_of() {
  local _hi_so_i
  printf -v "$1" '%s' ''
  for ((_hi_so_i = $2; _hi_so_i >= 0; _hi_so_i--)); do
    ! _hi_toml_table "$1" "${_hi_rows[_hi_so_i]}" || return 0
  done
}

# _hi_section_add <table> <row> - <row> into `_hi_rows` after <table>'s last
# row, or under a new `[<table>]` when the file has none: after the last row
# of the tables of its group (`core` for `core.required`), else at the end
function _hi_section_add() {
  local _hi_sa_i _hi_sa_in=0 _hi_sa_at=-1 _hi_sa_by=-1 _hi_sa_t
  for ((_hi_sa_i = 0; _hi_sa_i < ${#_hi_rows[@]}; _hi_sa_i++)); do
    if _hi_toml_table _hi_sa_t "${_hi_rows[_hi_sa_i]}"; then
      _hi_sa_in=0
      case "$_hi_sa_t" in
      "$1") _hi_sa_in=1 _hi_sa_at=$((_hi_sa_i + 1)) ;;
      "${1%.*}" | "${1%.*}".*) _hi_sa_in=2 _hi_sa_by=$((_hi_sa_i + 1)) ;;
      esac
      continue
    fi
    case "${_hi_rows[_hi_sa_i]}" in
    '' | '#'*) ;;
    *)
      case "$_hi_sa_in" in
      1) _hi_sa_at=$((_hi_sa_i + 1)) ;;
      2) _hi_sa_by=$((_hi_sa_i + 1)) ;;
      esac
      ;;
    esac
  done
  if [ "$_hi_sa_at" -ge 0 ]; then
    _hi_rows=("${_hi_rows[@]:0:_hi_sa_at}" "$2" "${_hi_rows[@]:_hi_sa_at}")
  elif [ "$_hi_sa_by" -ge 0 ]; then
    # a blank line either side, where a line follows that is not one
    _hi_sa_t="$2"
    [ -z "${_hi_rows[_hi_sa_by]:-}" ] || _hi_sa_t="$2"$'\n'
    _hi_rows=("${_hi_rows[@]:0:_hi_sa_by}" "" "[$1]" "$_hi_sa_t" "${_hi_rows[@]:_hi_sa_by}")
  else
    [ "${#_hi_rows[@]}" -eq 0 ] || [ -z "${_hi_rows[${#_hi_rows[@]} - 1]}" ] || _hi_rows+=("")
    _hi_rows+=("[$1]" "$2")
  fi
}

# the rows of the first packages and colors files, "name:N,..." and
# "type,name,color", for _hi_data_shape
_HI_FLAT_PACKAGES='^[^#]*:[0-9]'
_HI_FLAT_COLORS='^[a-z]+,[^,#]+,'

# _hi_data_shape <outvar> <file> <flat rows' pattern> - which hi wrote the
# rows of a packages or colors file: `toml`, this one, also of a file with no
# rows; `sections` for bare rows under `[section]` lines; `flat` for the rows
# before those, which <flat rows' pattern> matches. Empty for no file.
function _hi_data_shape() {
  local _hi_ds_l _hi_ds_k _hi_ds_v _hi_ds_heads=0 _hi_ds_old=0
  printf -v "$1" '%s' ''
  [ -f "$2" ] || return 0
  while IFS= read -r _hi_ds_l || [ -n "$_hi_ds_l" ]; do
    _hi_ds_l="${_hi_ds_l#"${_hi_ds_l%%[![:space:]]*}"}"
    case "$_hi_ds_l" in
    '' | '#'*) ;;
    '['*']'*) _hi_ds_heads=1 ;;
    *) _hi_toml_row "$_hi_ds_l" _hi_ds_k _hi_ds_v || _hi_ds_old=1 ;;
    esac
  done <"$2"
  if ! ((_hi_ds_old)); then
    printf -v "$1" toml
  elif ! ((_hi_ds_heads)) && grep -Eq "$3" "$2"; then
    printf -v "$1" flat
  else
    printf -v "$1" sections
  fi
}

# _hi_packages_drift <file> <tree's> - what a packages file of the user's own
# gets wrong unseen, a line each: `group|<name>` for a group the tree's has
# and <file> lacks, since a copy replaces the tree's and never gains one added
# later, and `marker|<row>` for a row with a name led by - or +, which is
# part of a name nothing matches: a table says what its rows are
function _hi_packages_drift() {
  local _hi_pd_l _hi_pd_g _hi_pd_k _hi_pd_v _hi_pd_have=" " _hi_pd_said=" "
  [ -f "$1" ] || return 0
  while IFS= read -r _hi_pd_l || [ -n "$_hi_pd_l" ]; do
    if _hi_package_table "$_hi_pd_l" _hi_pd_g _hi_pd_k; then
      _hi_pd_have="$_hi_pd_have$_hi_pd_g "
    elif _hi_toml_row "$_hi_pd_l" _hi_pd_k _hi_pd_v; then
      case ",$_hi_pd_k,$_hi_pd_v" in *,[-+]*) printf 'marker|%s\n' "$_hi_pd_k${_hi_pd_v:+,$_hi_pd_v}" ;; esac
    fi
  done <"$1"
  [ "$1" != "$2" ] && [ -f "$2" ] || return 0
  while IFS= read -r _hi_pd_l || [ -n "$_hi_pd_l" ]; do
    _hi_package_table "$_hi_pd_l" _hi_pd_g _hi_pd_k || continue
    case "$_hi_pd_have$_hi_pd_said" in *" $_hi_pd_g "*) continue ;; esac
    _hi_pd_said="$_hi_pd_said$_hi_pd_g "
    printf 'group|%s\n' "$_hi_pd_g"
  done <"$2"
}

# _hi_term_cols <outvar> - the terminal's width, or empty: $_HI_TERM_COLS (a
# suite's pin), else - only when stdout is a tty, so captured output keeps
# its fixed width - $COLUMNS, then tput. header.sh's _hi_draw_width rule.
function _hi_term_cols() {
  local _hi_tc="${_HI_TERM_COLS-}"
  if [ -z "${_HI_TERM_COLS+x}" ] && [ -t 1 ]; then
    _hi_tc="${COLUMNS:-}"
    case "$_hi_tc" in '' | *[!0-9]*) _hi_tc="$(tput cols 2>/dev/null || true)" ;; esac
  fi
  case "$_hi_tc" in *[!0-9]* | 0) _hi_tc="" ;; esac
  printf -v "$1" '%s' "$_hi_tc"
}

# _hi_out_width <outvar> - what a rule or a wrapped line draws to:
# $_HI_MAX_WIDTH, narrowed to the terminal when that is narrower
function _hi_out_width() {
  local _hi_ow=${_HI_MAX_WIDTH:-80} _hi_ow_cols
  _hi_term_cols _hi_ow_cols
  [ -n "$_hi_ow_cols" ] && ((_hi_ow_cols < _hi_ow)) && _hi_ow=$_hi_ow_cols
  printf -v "$1" '%d' "$_hi_ow"
}

# _hi_cells_line <color> <cell>... - " | a | b" lines, as many cells to a
# line as fit the output width; a cell wider than that has a line of its own
function _hi_cells_line() {
  local color="$1" w line="" cell
  shift
  _hi_out_width w
  for cell; do
    if [ -n "$line" ] && ((${#line} + ${#cell} + 3 > w)); then
      _hi_cecho "$line" "$color"
      line=""
    fi
    line="$line | $cell"
  done
  [ -z "$line" ] || _hi_cecho "$line" "$color"
}

# _hi_hrule <label> <bar-char> <inset> <color> - a rule across the output
# width with the label centered; the worker behind the heading levels
function _hi_hrule() {
  local pad label width total left right lbar rbar
  _hi_out_width width
  width=$((width - 1))
  _hi_repeat pad "$3" ' '
  label="$pad$1$pad"
  total=$((width - ${#label}))
  # an over-wide label keeps a 4-bar rule each side and overflows
  ((total < 8)) && total=8
  left=$((total / 2))
  right=$((total - left))
  _hi_repeat lbar "$left" "$2"
  _hi_repeat rbar "$right" "$2"
  _hi_cecho " $lbar$label$rbar" "$4"
}

function _hi_h1() {
  _hi_hrule "$1" '=' 1 "${2:-$BRBLUE}"
}

function _hi_h2() {
  _hi_hrule "$1" '-' 2 "${2:-$BRCYAN}"
}

# _hi_is_darwin - macOS, where a login bash reads ~/.bash_profile and never
# ~/.bashrc. $_HI_UNAME lets a suite stage the other platform.
function _hi_is_darwin() {
  [ "${_HI_UNAME:-$(uname -s 2>/dev/null)}" = Darwin ]
}

# _hi_rewrite <file> <sed-expr>... - every expression in one pass, in place.
# A temp file, not `sed -i`: its flag differs BSD/GNU, and -i replaces a
# symlinked rc with a regular file. GLOSSARY: HI.08
function _hi_rewrite() {
  local file="$1" e tmp
  shift
  local -a exprs=()
  for e in "$@"; do exprs+=(-e "$e"); done
  tmp="$(mktemp -t hi.rewrite.XXXXXX)"
  sed "${exprs[@]}" "$file" >"$tmp"
  _hi_write_back "$tmp" "$file"
}

# _hi_shell_rows - core.sh's $_HI_SHELL_TABLE, one row per line for
# `while IFS='|' read` callers.
function _hi_shell_rows() {
  printf '%s\n' "${_HI_SHELL_TABLE[@]}"
}

# _hi_setting_get <file> <name> [outvar] - what <name> holds after sourcing
# <file>, or rc 1 when it never gets set. A subshell sources the file for real
# (only <name> unset) rather than a hand-rolled grammar, so it agrees with
# what a target would see; nothing outside it is touched.
function _hi_setting_get() {
  # prefixed locals: a plain `val` would shadow the caller's (GLOSSARY: HI.04)
  local _hi_sg_file="$1" _hi_sg_name="$2" _hi_sg_outvar="${3:-}" _hi_sg_val
  [ -f "$_hi_sg_file" ] || return 1
  _hi_sg_val="$(
    unset "$_hi_sg_name"
    # shellcheck source=/dev/null # a config file, or one a test wrote - not one shellcheck can trace
    . "$_hi_sg_file" >/dev/null 2>&1
    [ "${!_hi_sg_name+x}" = x ] || exit 1
    printf '%s' "${!_hi_sg_name}"
  )" || return 1
  _hi_out "$_hi_sg_outvar" "$_hi_sg_val"
}

# _hi_color_escape <name> [outvar] - the ANSI escape for a palette name
# (_HI_COLOR_NAMES) as a real ESC byte, where core.sh's _hi_color_escape_var
# leaves the two characters `\e`
function _hi_color_escape() {
  local _hi_ce
  _hi_color_escape_var _hi_ce "$1"
  printf -v _hi_ce '%b' "$_hi_ce"
  _hi_out "${2:-}" "$_hi_ce"
}

# What a settings.sh value may be, one predicate per shape. The wizard takes
# an answer by these (scripts/configure.sh), and doctor_config judges a
# hand-written line by the same ones, so a value the menu would refuse is
# named rather than silently falling back to the default.
function _hi_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
# a header width: 40 columns is the narrowest the banner and rows draw in
function _hi_is_width() { _hi_is_number "$1" && [ "$1" -ge 40 ]; }
# $_HI_PACKAGES_GROUPS: `none`, or group names separated by spaces or commas
function _hi_is_package_groups() {
  case "$1" in
  none) return 0 ;;
  '' | *[!A-Za-z0-9_.,\ -]*) return 1 ;;
  esac
}
# a 0/1 switch (_HI_MUX, _HI_TRUECOLOR, the toggles)
function _hi_is_flag() { [ "$1" = 0 ] || [ "$1" = 1 ]; }
# one of core.sh's $_HI_EDITORS
function _hi_is_editor() {
  case " $_HI_EDITORS " in *" $1 "*) return 0 ;; esac
  return 1
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

# _hi_is_header_order <words> - every word of the value one of $_HI_HEADER_ORDER's
# vocabulary, read off header.sh's own $_HI_HEADER_ORDER_DEFAULT (the caller
# has header.sh loaded) rather than a second copy of the list
function _hi_is_header_order() {
  local _hi_ho_w
  [ -n "$1" ] || return 1
  # shellcheck disable=SC2086 # the value is a space-separated word list
  for _hi_ho_w in $1; do
    case " $_HI_HEADER_ORDER_DEFAULT " in *" $_hi_ho_w "*) ;; *) return 1 ;; esac
  done
  return 0
}

# _hi_is_prompt_list <words> - every word of the value a program of core.sh's
# _HI_PROMPT_TABLE, or `hi`
function _hi_is_prompt_list() {
  local _hi_pl_w
  # shellcheck disable=SC2086 # the value is a space-separated word list
  for _hi_pl_w in $1; do
    [ "$_hi_pl_w" = hi ] || _hi_prompt_row "$_hi_pl_w" >/dev/null || return 1
  done
  return 0
}

# The scheme helpers only the tooling reads (GLOSSARY: HI.50): core.sh
# answers "what does slot n render as", these answer "what is the setting".
# _hi_scheme_ok <value> - 24/48 hex words, the only shape there is
function _hi_scheme_ok() {
  local _hi_so_n
  _HI_COLOR_SCHEME="$1" _hi_scheme_words _hi_so_n
  [ "$_hi_so_n" -gt 0 ]
}

# _hi_scheme_label <outvar> - the scheme as a preview or report names it:
# default, custom (24|48), or the value and why it is ignored
function _hi_scheme_label() {
  local _hi_sl_n
  _hi_scheme_words _hi_sl_n
  if [ -z "${_HI_COLOR_SCHEME:-}" ]; then
    printf -v "$1" '%s' default
  elif [ "$_hi_sl_n" -gt 0 ]; then
    printf -v "$1" 'custom (%s)' "$_hi_sl_n"
  else
    printf -v "$1" '%s (ignored - not a scheme)' "$_HI_COLOR_SCHEME"
  fi
}

# _hi_ramp_label <outvar> - the same three shapes for the packages check's
# ramp: default, custom, or the value and why it is ignored. header.sh's
# _hi_ramp_ok is the judge, so a preview and a report can never disagree
# with what full_check actually paints.
function _hi_ramp_label() {
  if [ -z "${_HI_PACKAGES_PALETTE:-}" ]; then
    printf -v "$1" '%s' default
  elif _hi_ramp_ok "$_HI_PACKAGES_PALETTE"; then
    printf -v "$1" '%s' custom
  else
    printf -v "$1" '%s (ignored - not eight color names)' "$_HI_PACKAGES_PALETTE"
  fi
}

# Every rule and edge scripts/table.sh and scripts/configure.sh draw with.
# Here and not in core.sh's _hi_choose_glyphs beside the mark glyphs, for the
# reason at the top of this file: nothing a target runs draws a box, and
# common/ ships in the ssh payload under a size budget. One set per session,
# decided at source time the way the glyphs are - configure.sh is sourced by
# install.sh after this file and never re-asks.
#
# Eleven names rather than three strings to slice: under `_HI_ASCII=0` on a
# non-UTF-8 locale a ${s:0:1} would cut a byte out of a three-byte glyph
# (GLOSSARY: HI.12). The junctions (T/B/L/R/X) are what let a rule know
# whether it is a table's top, its header separator, or its bottom; ASCII
# spells all nine corners `+`.
if _hi_use_ascii; then
  _HI_BOX_TL="+" _HI_BOX_T="+" _HI_BOX_TR="+"
  _HI_BOX_L="+" _HI_BOX_X="+" _HI_BOX_R="+"
  _HI_BOX_BL="+" _HI_BOX_B="+" _HI_BOX_BR="+"
  _HI_BOX_H="-" _HI_BOX_V="|"
else
  _HI_BOX_TL="┌" _HI_BOX_T="┬" _HI_BOX_TR="┐"
  _HI_BOX_L="├" _HI_BOX_X="┼" _HI_BOX_R="┤"
  _HI_BOX_BL="└" _HI_BOX_B="┴" _HI_BOX_BR="┘"
  _HI_BOX_H="─" _HI_BOX_V="│"
fi

# _hi_plugin_rows - every row of hi.sh's that can be switched, the table's
# and the carry's (so only where hi.sh is sourced), as
# `<plugin>|<group>|<member>` lines in the table's order: what hi --plugins
# lists
function _hi_plugin_rows() {
  local _hi_pw_r _hi_pw_g _hi_pw_n
  _hi_carry_load
  for _hi_pw_r in "${_HI_OVERLAY_TABLE[@]}" ${_HI_CARRY_ROWS[@]+"${_HI_CARRY_ROWS[@]}"}; do
    _hi_row_col "$_hi_pw_r" group _hi_pw_g
    [ "$_hi_pw_g" != - ] || continue
    _hi_plugin_name "${_hi_pw_r%%|*}" _hi_pw_n "$_hi_pw_r"
    printf '%s|%s|%s\n' "$_hi_pw_n" "$_hi_pw_g" "${_hi_pw_r%%|*}"
  done
}

# _hi_unsent_why <member> <outvar> - why a connect sends nothing of a member
# that has a file, in a phrase; 1 when neither a switch, the prompt in force,
# nor a missing tool is the reason
function _hi_unsent_why() {
  local _hi_uw=""
  if _hi_plugin_off "$1" _hi_uw; then
    _hi_uw="switched off ($_hi_uw)"
  elif _hi_prompt_row "$1" >/dev/null && ! _hi_prompt_handed "$1"; then
    _hi_uw="its prompt program is not one a target is handed (_HI_PROMPT_TOOL)"
  elif ! _hi_tool_here "$1"; then
    _hi_uw="its tool is not installed here"
  fi
  printf -v "$2" '%s' "$_hi_uw"
  [ -n "$_hi_uw" ]
}

# _hi_plugin_state <member> <outvar> - what a connect does with <member>,
# in a phrase; 1 when it is off
function _hi_plugin_state() {
  local src="" why="" tilde='~'
  case "$1" in
  */)
    src="$(_hi_overlay_files "$1" | grep -c .)" || true
    if [ "$src" = 0 ]; then src=""; else src="$src file(s)"; fi
    ;;
  *) ! _hi_overlay_src "$1" src || src="${src/#"$HOME"/$tilde}" ;;
  esac
  if [ -n "$src" ]; then
    printf -v "$2" '%s' "rides: $src"
  elif _hi_unsent_why "$1" why; then
    printf -v "$2" '%s' "stays home: $why"
  else
    printf -v "$2" '%s' "nothing to carry"
  fi
  [ "${why#switched off}" = "$why" ]
}

# _hi_plugin_words - every word $_HI_PLUGINS_OFF may hold, one a line
function _hi_plugin_words() {
  _hi_plugin_rows | tr '|' '\n' | sort -u
}
