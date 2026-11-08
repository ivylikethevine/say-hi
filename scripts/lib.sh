#!/usr/bin/env bash
# Helpers the tooling shares (scripts/, packaging/, docs/tapes/, tests/):
# flag parsing, headings, in-place rewrites, settings and scheme readers, box
# glyphs. Kept out of core.sh, which rides under a size budget. Source after
# core.sh; sourcing does nothing else.

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
  local _hi_mi
  _hi_missing_into _hi_mi "$@"
  printf '%s' "$_hi_mi"
}

# _hi_missing_into <outvar> <name...> - the same, with no fork
function _hi_missing_into() {
  local _hi_mt _hi_mt_out=""
  for _hi_mt in "${@:2}"; do
    command -v "$_hi_mt" >/dev/null 2>&1 || _hi_mt_out="$_hi_mt_out$_hi_mt "
  done
  printf -v "$1" '%s' "${_hi_mt_out% }"
}

# dry_run_say <what> - under --dry-run ($_HI_DRY_RUN: install.sh's flag, and
# the editing scripts'), say what would happen and succeed, so the caller
# returns before it writes; otherwise fail quietly and the caller carries on.
# Every writer they reach opens with one of these.
function dry_run_say() {
  [ -n "${_HI_DRY_RUN:-}" ] || return 1
  _hi_cecho " dry run: would $1" "$BLUE"
  return 0
}

# _hi_args <help-fn> <usage> <word>... - a script's own words: -h/--help runs
# <help-fn> and exits, -n/--dry-run sets $_HI_DRY_RUN, any other --word is
# refused naming <usage>, and the rest land in the caller's args array, in
# order
function _hi_args() {
  local _hi_ag_help="$1" _hi_ag_usage="$2"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
    -h | --help)
      "$_hi_ag_help"
      exit 0
      ;;
    -n | --dry-run) _HI_DRY_RUN=1 ;;
    --text) [ "${_HI_TEXT:-0}" = 1 ] || _hi_die "unknown option $1 ($_hi_ag_usage)" ;;
    --*) _hi_die "unknown option $1 ($_hi_ag_usage)" ;;
    *) args+=("$1") ;;
    esac
    shift
  done
}

# tmp -> dest through dest's existing inode: cat, not mv, or mktemp's 0600
# lands on the destination and severs any hardlink/ACL. The mode is captured
# and reapplied too, since truncate-in-place alone did not preserve it on
# Windows Git Bash. Fails when dest could not be written, the tmp file gone
# either way. GLOSSARY: HI.09
function _hi_write_back() {
  local mode="" rc=0
  [ -e "$2" ] && mode="$(stat -c '%a' "$2" 2>/dev/null || stat -f '%Lp' "$2" 2>/dev/null)"
  cat "$1" >"$2" || rc=1
  [ "$rc" -ne 0 ] || [ -z "$mode" ] || chmod "$mode" "$2" 2>/dev/null || true
  command rm -f "$1"
  return "$rc"
}

# A file as the editing scripts hold it: a global `_hi_rows` array of lines,
# one per file line.

# _hi_rows_read <file> - <file>'s lines as `_hi_rows`, none when it is absent
function _hi_rows_read() {
  _hi_rows=()
  [ ! -f "$1" ] || _hi_read_lines _hi_rows <"$1"
}

# _hi_rows_write <dst> [read-from] - `_hi_rows` as <dst>, or under --dry-run
# what that would do, <read-from> being the file the rows were read from
function _hi_rows_write() {
  local what="write $1" tmpfile
  [ "${2:-$1}" = "$1" ] || what="copy $2 to $1, then change it there"
  ! dry_run_say "$what" || return 0
  mkdir -p "${1%/*}"
  tmpfile="$(mktemp -t "hi.${1##*/}.XXXXXX")"
  [ "${#_hi_rows[@]}" -eq 0 ] || printf '%s\n' "${_hi_rows[@]}" >"$tmpfile"
  _hi_write_back "$tmpfile" "$1"
  _hi_cecho "$1 updated" "$GREEN"
}

# the rows of the first packages and colors files, "name:N,..." and
# "type,name,color", for _hi_data_shape
_HI_FLAT_PACKAGES='^[^#]*:[0-9]'
_HI_FLAT_COLORS='^[a-z]+,[^,#]+,'
# the editors' and multiplexers' _HI_DISABLE_<name> toggles, now words of
# _HI_PLUGINS_OFF
_HI_OLD_TOGGLES='EDITORS|VIM|NANO|EMACS|MICRO|HELIX|KAKOUNE|TMUX|SCREEN|ZELLIJ'

# _hi_data_shape <outvar> <file> <flat rows' pattern> - a packages or colors
# file's shape: `toml` (current, or no rows), `tables` ([group.required] and
# [group.unwanted]), `sections` (bare rows under [section]), or `flat` (rows
# matching the pattern); empty for no file. Any TOML row makes it `toml`.
function _hi_data_shape() {
  local _hi_ds_l _hi_ds_k _hi_ds_v _hi_ds_heads=0 _hi_ds_old=0 _hi_ds_new=0 _hi_ds_sub=0
  printf -v "$1" '%s' ''
  [ -f "$2" ] || return 0
  while IFS= read -r _hi_ds_l || [ -n "$_hi_ds_l" ]; do
    _hi_ds_l="${_hi_ds_l#"${_hi_ds_l%%[![:space:]]*}"}"
    case "$_hi_ds_l" in
    '' | '#'*) ;;
    '['*']'*)
      _hi_ds_heads=1
      case "${_hi_ds_l%%\]*}" in '[required' | '[unwanted' | *.required | *.unwanted) _hi_ds_sub=1 ;; esac
      ;;
    *) if _hi_toml_row "$_hi_ds_l" _hi_ds_k _hi_ds_v; then _hi_ds_new=1; else _hi_ds_old=1; fi ;;
    esac
  done <"$2"
  if ((_hi_ds_new && _hi_ds_sub)); then
    printf -v "$1" tables
  elif ((_hi_ds_new)) || ! ((_hi_ds_old)); then
    printf -v "$1" toml
  elif ! ((_hi_ds_heads)) && grep -Eq "$3" "$2"; then
    printf -v "$1" flat
  else
    printf -v "$1" sections
  fi
}

# _hi_plugins_shape <outvar> <file> - `rows` for a plugins file of the shape
# before the tables, `"member" = "tool | wire | home"` rows under a `[group]`
# line; empty for no file, and for the shape this hi reads
function _hi_plugins_shape() {
  printf -v "$1" '%s' ''
  [ ! -f "$2" ] || ! grep -Eq '^[[:space:]]*\[[^].]+\][[:space:]]*(#.*)?$' "$2" || printf -v "$1" rows
}

# The shape of settings.sh this hi writes and reads: the N of the
# `# say-hi settings N` line hi --configure opens its block with. A file
# with none is shape 0, told by its rows (convert_settings.sh's heuristics).
_HI_SETTINGS_SHAPE=2

# _hi_settings_shape <outvar> <file> - the N of <file>'s first
# `# say-hi settings N` line, 0 for a file with none, empty for no file
function _hi_settings_shape() {
  printf -v "$1" '%s' ''
  [ -f "$2" ] || return 0
  printf -v "$1" '%s' "$(awk '
    !n && /^#[ \t]*say-hi settings[ \t]+[0-9]+/ { sub(/^#[ \t]*say-hi settings[ \t]+/, ""); sub(/[^0-9].*/, ""); n = $0 }
    END { printf "%d\n", n }
  ' "$2")"
}

# _hi_toml_strays <file> - each line of a colors or packages file that is
# no row of the subset (SETTINGS.md, The TOML hi reads) and so is read as
# nothing: `<line number>|<text>`, none for no file
function _hi_toml_strays() {
  local _hi_ts_l _hi_ts_k _hi_ts_v _hi_ts_n=0
  [ -f "$1" ] || return 0
  while IFS= read -r _hi_ts_l || [ -n "$_hi_ts_l" ]; do
    _hi_ts_n=$((_hi_ts_n + 1))
    _hi_ts_l="${_hi_ts_l#"${_hi_ts_l%%[![:space:]]*}"}"
    case "$_hi_ts_l" in '' | '#'* | '['*']'*) continue ;; esac
    _hi_toml_row "$_hi_ts_l" _hi_ts_k _hi_ts_v || printf '%s|%s\n' "$_hi_ts_n" "$_hi_ts_l"
  done <"$1"
}

# _hi_package_groups <outvar> - the groups $_HI_PACKAGES holds, in file
# order, space-separated, each once
function _hi_package_groups() {
  local _hi_pg_l _hi_pg_g _hi_pg_all=""
  [ -f "${_HI_PACKAGES:-}" ] && while IFS=$' ' read -r _hi_pg_l; do
    _hi_package_table "$_hi_pg_l" _hi_pg_g && [ -n "$_hi_pg_g" ] || continue
    case " $_hi_pg_all " in *" $_hi_pg_g "*) ;; *) _hi_pg_all="$_hi_pg_all${_hi_pg_all:+ }$_hi_pg_g" ;; esac
  done <"$_HI_PACKAGES"
  printf -v "$1" '%s' "$_hi_pg_all"
}

# _hi_packages_drift <file> <tree's> - a user's packages file's silent faults,
# `<severity>|<sentence>` lines: an alternative marked - or + (only the name
# takes a mark), a line that is no row, and groups the tree's has and it lacks
function _hi_packages_drift() {
  local _hi_pd_l _hi_pd_g _hi_pd_k _hi_pd_v _hi_pd_have=" " _hi_pd_lack=""
  [ -f "$1" ] || return 0
  while IFS= read -r _hi_pd_l || [ -n "$_hi_pd_l" ]; do
    _hi_pd_l="${_hi_pd_l#"${_hi_pd_l%%[![:space:]]*}"}"
    if _hi_package_table "$_hi_pd_l" _hi_pd_g; then
      _hi_pd_have="$_hi_pd_have$_hi_pd_g "
    elif _hi_toml_row "$_hi_pd_l" _hi_pd_k _hi_pd_v; then
      case ",$_hi_pd_v" in *,[-+]*)
        printf 'warn|the row %s never matches: a - or + leading an alternative is read as part of its name\n' "$_hi_pd_k${_hi_pd_v:+,$_hi_pd_v}"
        ;;
      esac
    else
      case "$_hi_pd_l" in '' | '#'*) ;; *)
        printf 'warn|the line %s is never checked: a row is name = ["alternative", ...] on one line, a name holding more than letters, digits, - and _ in double quotes\n' "$_hi_pd_l"
        ;;
      esac
    fi
  done <"$1"
  [ "$1" != "$2" ] && [ -f "$2" ] || return 0
  while IFS= read -r _hi_pd_l || [ -n "$_hi_pd_l" ]; do
    _hi_package_table "$_hi_pd_l" _hi_pd_g || continue
    ! _hi_list_has "$_hi_pd_have" "$_hi_pd_g" || continue
    _hi_pd_have="$_hi_pd_have$_hi_pd_g " _hi_pd_lack="$_hi_pd_lack${_hi_pd_lack:+, }$_hi_pd_g"
  done <"$2"
  [ -z "$_hi_pd_lack" ] ||
    printf "info|lacks the tree's groups, which are never checked: %s (%s has them to copy)\n" "$_hi_pd_lack" "$2"
}

# _hi_out_width <outvar> - what a rule or a wrapped line draws to:
# $_HI_MAX_WIDTH, narrowed to the terminal when that is narrower
function _hi_out_width() {
  local _hi_ow=${_HI_MAX_WIDTH:-$_HI_MAX_WIDTH_DEFAULT} _hi_ow_cols
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

# under --text (table.sh) a heading is its words alone, no rule
function _hi_h1() { if [ "${_HI_TEXT:-0}" = 1 ]; then printf '%s\n' "$1"; else _hi_hrule "$1" '=' 1 "${2:-$BRBLUE}"; fi; }
function _hi_h2() { if [ "${_HI_TEXT:-0}" = 1 ]; then printf '%s\n' "$1"; else _hi_hrule "$1" '-' 2 "${2:-$BRCYAN}"; fi; }

# _hi_is_darwin - macOS, where a login bash reads ~/.bash_profile and never
# ~/.bashrc. $_HI_UNAME lets a suite stage the other platform.
function _hi_is_darwin() {
  # bash's own word for the platform where no suite names one: no fork
  case "${_HI_UNAME:-$OSTYPE}" in Darwin | darwin*) return 0 ;; esac
  return 1
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

# _hi_editor_cmd <outvar> - the editor hi --edit and hi --configure open:
# the first of $VISUAL, $EDITOR, $_HI_EDITOR that names a command here (a
# value may carry flags, so its first word is looked up), else the first of
# $_HI_EDITORS on PATH; 1 for none
function _hi_editor_cmd() {
  local _hi_ec
  # shellcheck disable=SC2086 # $_HI_EDITORS is a word list
  for _hi_ec in "${VISUAL:-}" "${EDITOR:-}" "${_HI_EDITOR:-}" $_HI_EDITORS; do
    [ -n "$_hi_ec" ] || continue
    command -v "${_hi_ec%% *}" >/dev/null 2>&1 || continue
    printf -v "$1" '%s' "$_hi_ec"
    return 0
  done
  return 1
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

# What a settings.sh value may be, one predicate per shape: doctor_config
# judges each line by them, so a value the code would fall back from is
# named rather than silently ignored.
function _hi_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
# $_HI_PACKAGES_GROUPS: `none`, or group names separated by spaces or commas
function _hi_is_package_groups() {
  case "$1" in
  none) return 0 ;;
  '' | *[!A-Za-z0-9_.,\ -]*) return 1 ;;
  esac
}
# a 0/1 switch (_HI_KEEP, _HI_TRUECOLOR, the toggles)
function _hi_is_flag() { [ "$1" = 0 ] || [ "$1" = 1 ]; }
# $_HI_KEEP_TIMEOUT, $_HI_HOLD_TIMEOUT, $_HI_KEEP_RETRY: seconds, or a number with s, m, h, or d
function _hi_is_duration() { [[ "$1" =~ ^[0-9]+[smhd]?$ ]]; }
# one of core.sh's $_HI_EDITORS
function _hi_is_editor() { _hi_list_has "$_HI_EDITORS" "$1"; }
# $_HI_SHELL_PREFERENCE's vocabulary: `login` and the shells hi styles, in any
# order, space-separated
function _hi_is_shell_list() {
  local _hi_sl_w
  [ -n "$1" ] || return 1
  # shellcheck disable=SC2086 # the split is the point: one word per shell
  for _hi_sl_w in $1; do
    [ "$_hi_sl_w" = login ] || _hi_shell_wired "$_hi_sl_w" || return 1
  done
  return 0
}
# a value written into settings.sh's single-quoted export
function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

# $_HI_IP_HIDE's vocabulary: the word `none`, or space-separated globs over
# addresses and interface names - what core.sh's _hi_ssh_pattern_hit reads,
# nothing else, so a stray quote or a shell metacharacter can't be written
# into settings.sh
function _hi_is_ip_hide() {
  case "$1" in
  none) return 0 ;;
  '' | *[!A-Za-z0-9_.:*?!\ -]*) return 1 ;;
  esac
}

# _hi_is_header_order <words> - every word of the value one of $_HI_HEADER_ORDER's
# vocabulary, read off header.sh's own _hi_header_vocab (the caller has
# header.sh loaded) rather than a second copy of the list
function _hi_is_header_order() {
  local _hi_ho_w _hi_ho_v
  [ -n "$1" ] || return 1
  _hi_header_vocab _hi_ho_v
  # shellcheck disable=SC2086 # the value is a space-separated word list
  for _hi_ho_w in $1; do
    _hi_list_has "$_hi_ho_v" "$_hi_ho_w" || return 1
  done
  return 0
}

# _hi_is_prompt_list <words> - every word of the value a program of core.sh's
# _HI_PROMPT_TABLE, or `hi`, either one optionally <shell>: for a shell it fits
function _hi_is_prompt_list() {
  local _hi_pl_w _hi_pl_r
  # shellcheck disable=SC2086 # the value is a space-separated word list
  for _hi_pl_w in $1; do
    case "$_hi_pl_w" in
    bash:hi | zsh:hi | fish:hi | hi) ;;
    *:*) _hi_prompt_fits "${_hi_pl_w#*:}" "${_hi_pl_w%%:*}" || return 1 ;;
    *) _hi_prompt_row "$_hi_pl_w" _hi_pl_r || return 1 ;;
    esac
  done
  return 0
}

# _hi_prompt_fits <program> <shell> - does that prompt program draw that shell
function _hi_prompt_fits() {
  local _hi_pf_r
  _hi_prompt_row "$1" _hi_pf_r || return 1
  _hi_pf_r="${_hi_pf_r#*|}"
  _hi_list_has "${_hi_pf_r%%|*}" "$2"
}

# _hi_is_plugin_list <value> - is every word of it a plugin or a member
# that can be switched (_hi_plugin_word_ok)?
function _hi_is_plugin_list() {
  local w known
  known=" $(_hi_plugin_words | tr '\n' ' ')"
  for w in ${1//,/ }; do
    _hi_plugin_word_ok "$w" "$known" || return 1
  done
}

# _hi_setting_check <check> <value> - is <value> what a scripts/settings row
# of that <check> takes; 2 for a <check> this does not know. The kinds are
# $_HI_SETTING_CHECKS, which drift holds every row's to.
_HI_SETTING_CHECKS="toggle flag number: duration globs groups header prompts plugins editor shells noquote -"
function _hi_setting_check() {
  case "$1" in
  toggle | flag) _hi_is_flag "$2" ;;
  number:*) _hi_is_number "$2" && [ "$2" -ge "${1#number:}" ] ;;
  duration) _hi_is_duration "$2" ;;
  globs) _hi_is_ip_hide "$2" ;;
  groups) _hi_is_package_groups "$2" ;;
  header) _hi_is_header_order "$2" ;;
  prompts) _hi_is_prompt_list "$2" ;;
  plugins) _hi_is_plugin_list "$2" ;;
  editor) _hi_is_editor "$2" ;;
  shells) _hi_is_shell_list "$2" ;;
  noquote) _hi_has_no_single_quote "$2" ;;
  -) ;;
  *) return 2 ;;
  esac
}

# _hi_setting_rules - every scripts/settings row with a <check>, a line each:
# <name>|<check>|<hint>, the hint ending in the vocabulary its check reads
# where it reads one
function _hi_setting_rules() {
  local _hi_sr_l _hi_sr_n _hi_sr_c _hi_sr_us=$'\x1f'
  while IFS= read -r _hi_sr_l || [ -n "$_hi_sr_l" ]; do
    case "$_hi_sr_l" in '' | '#'*) continue ;; esac
    # <section>, <name>, <default>, <check>, <hint>
    IFS="$_hi_sr_us" read -r _ _hi_sr_n _ _hi_sr_c _hi_sr_l _ <<<"${_hi_sr_l// | /$_hi_sr_us}"
    [ "$_hi_sr_c" != - ] || continue
    case "$_hi_sr_c" in
    header) _hi_sr_l="$_hi_sr_l $_HI_HEADER_ORDER_DEFAULT" ;;
    prompts) _hi_sr_l="$_hi_sr_l $_HI_PROMPT_TOOLS" ;;
    editor) _hi_sr_l="$_hi_sr_l $_HI_EDITORS" ;;
    esac
    printf '%s|%s|%s\n' "$_hi_sr_n" "$_hi_sr_c" "$_hi_sr_l"
  done <"$_HI_ROOT/scripts/settings"
}

# The scheme helpers only the tooling reads (GLOSSARY: HI.50): core.sh
# answers "what does slot n render as", these answer "what does the table hold".
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

# The box-drawing rules and edges table.sh and configure.sh draw with,
# chosen once at source time. Separate names rather than a sliced string,
# since ${s:0:1} cuts a byte off a glyph outside a UTF-8 locale (GLOSSARY:
# HI.12). The junctions (T/B/L/R/X) mark a table's top, separator, and
# bottom; ASCII spells every corner `+`.
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

# _hi_plugin_color <outvar> <rides|off|absent> - the color a listed plugin's
# name takes by its state, set here alone: one that rides to a target, one
# switched off, one with nothing on this machine to send
function _hi_plugin_color() {
  case "$2" in
  rides) printf -v "$1" '%s' "$BRGREEN" ;;
  off) printf -v "$1" '%s' "$YELLOW" ;;
  *) printf -v "$1" '%s' "$BLUE" ;;
  esac
}

# _hi_state_row <rides|off|absent> <label> <text> [severity] - _hi_row, the label in that state's color
function _hi_state_row() {
  local _hi_sr_c
  _hi_plugin_color _hi_sr_c "$1"
  _hi_row "$2" "$3" "${4:-info}" "$_hi_sr_c"
}

# _hi_plugin_rows - every row that can be switched, the plugins files' (so
# only where hi.sh is sourced), as `<plugin>|<group>|<member>` lines: what
# hi --plugins lists
function _hi_plugin_rows() {
  local _hi_pw_r _hi_pw_g _hi_pw_n
  _hi_plugins_load
  for _hi_pw_r in ${_HI_PLUGIN_ROWS[@]+"${_HI_PLUGIN_ROWS[@]}"}; do
    _hi_row_col "$_hi_pw_r" group _hi_pw_g
    _hi_plugin_name "${_hi_pw_r%%|*}" _hi_pw_n "$_hi_pw_r"
    printf '%s|%s|%s\n' "$_hi_pw_n" "$_hi_pw_g" "${_hi_pw_r%%|*}"
  done
  # a plugin with a hook and no file is a word too, under its own name
  for _hi_pw_r in ${_HI_PLUGIN_HOOKS[@]+"${_HI_PLUGIN_HOOKS[@]}"}; do
    _hi_hook_col "$_hi_pw_r" name _hi_pw_n
    _hi_hook_col "$_hi_pw_r" group _hi_pw_g
    printf '%s|%s|%s\n' "$_hi_pw_n" "$_hi_pw_g" "$_hi_pw_n"
  done
  # ...and so is one that sends variables
  for _hi_pw_r in ${_HI_PLUGIN_ENVS[@]+"${_HI_PLUGIN_ENVS[@]}"}; do
    _hi_pw_n="${_hi_pw_r#*|}"
    printf '%s|%s|%s\n' "${_hi_pw_n%%|*}" "${_hi_pw_r%%|*}" "${_hi_pw_n%%|*}"
  done
}

# _hi_hook_rows - every shell hook as a report row (HI.67): the plugin, its
# name in its state's color, its init, and whether a target gets it - the
# tool here, the plugin on
function _hi_hook_rows() {
  local _hi_hr_r _hi_hr_n _hi_hr_i _hi_hr_p _hi_hr_why
  _hi_plugins_load
  for _hi_hr_r in ${_HI_PLUGIN_HOOKS[@]+"${_HI_PLUGIN_HOOKS[@]}"}; do
    _hi_hook_col "$_hi_hr_r" name _hi_hr_n
    _hi_hook_col "$_hi_hr_r" init _hi_hr_i
    if ! _hi_hook_here "$_hi_hr_r"; then
      _hi_state_row absent "$_hi_hr_n" "$_hi_hr_i - not installed here, so not sent"
    elif _hi_plugin_switched_off "$_hi_hr_n"; then
      _hi_hr_why="switched off (_HI_PLUGINS_OFF)"
      ! _hi_list_has "$_HI_PLUGIN_DEFAULT_OFF" "$_hi_hr_n" || _hi_hr_why="off by default (hi --enable-plugin $_hi_hr_n)"
      _hi_state_row off "$_hi_hr_n" "$_hi_hr_i - $_hi_hr_why"
    else
      _hi_hook_col "$_hi_hr_r" prompt _hi_hr_p
      [ "$_hi_hr_p" != yes ] && _hi_hr_p="" || _hi_hr_p=", and draws the prompt"
      _hi_state_row rides "$_hi_hr_n" "$_hi_hr_i - runs on a target that has it$_hi_hr_p" ok
    fi
  done
}

# _hi_env_rows - every variable a plugin's `env` names as a report row
# (HI.62): the variable under its plugin, in its state's color, and whether
# a target gets its value - set here, a value a line can hold, the plugin on
function _hi_env_rows() {
  local _hi_er_r _hi_er_n _hi_er_v _hi_er_off
  _hi_plugins_load
  for _hi_er_r in ${_HI_PLUGIN_ENVS[@]+"${_HI_PLUGIN_ENVS[@]}"}; do
    _hi_er_n="${_hi_er_r#*|}"
    _hi_er_n="${_hi_er_n%%|*}" _hi_er_off=""
    if _hi_plugin_switched_off "$_hi_er_n"; then
      _hi_er_off="switched off (_HI_PLUGINS_OFF)"
      ! _hi_list_has "$_HI_PLUGIN_DEFAULT_OFF" "$_hi_er_n" || _hi_er_off="off by default (hi --enable-plugin $_hi_er_n)"
    fi
    for _hi_er_v in ${_hi_er_r##*|}; do
      if [ -z "${!_hi_er_v:-}" ]; then
        _hi_state_row absent "$_hi_er_v ($_hi_er_n)" "not set here, so not sent"
      elif [ -n "$_hi_er_off" ]; then
        _hi_state_row off "$_hi_er_v ($_hi_er_n)" "$_hi_er_off"
      elif ! _hi_env_rides "$_hi_er_v"; then
        _hi_state_row absent "$_hi_er_v ($_hi_er_n)" "its value holds a quote, a backslash, or a line break - not sent" warn
      else
        _hi_state_row rides "$_hi_er_v ($_hi_er_n)" "its value here is exported on a target" ok
      fi
    done
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

# _hi_member_label <member> <outvar> - <member> with the plugin it is of,
# `vim/vimrc (vim)`, as a row names it; hi's own files go bare.
function _hi_member_label() {
  local _hi_ml_t
  _hi_plugin_name "$1" _hi_ml_t || true
  printf -v "$2" '%s' "$1${_hi_ml_t:+ ($_hi_ml_t)}"
}

# _hi_member_rows <member...> - rows through ${_HI_ROW_FN:-_hi_row}: each
# place a member was found, in resolution order (GLOSSARY: HI.61), marked used
# or passed over, and why nothing is sent. Members found nowhere share one
# `none anywhere` row; one switched off gets its own.
function _hi_member_rows() {
  local row m eff site tree p state text label none="" found draw="${_HI_ROW_FN:-_hi_row}"
  local -a locs _hi_paths=()
  _hi_plugins_load
  for m; do
    _hi_overlay_row "$m" row || continue
    eff="" text="" found="" site="" tree=""
    _hi_overlay_src "$m" eff || eff=""
    _hi_overlay_places "$m" "$row"
    case "$row" in *'|tree|'*) site="${_HI_SITE_DIR:+$_HI_SITE_DIR/$m}" tree="$_HI_ROOT/config/$m" ;; esac
    # the tiers in order: the overlay's copy, the site's (for a member
    # config/ holds a default of), home, the tree's default
    locs=("$_HI_CONFIG_DIR/$m" "$site" ${_hi_paths[@]+"${_hi_paths[@]}"} "$tree")
    [ -n "$eff" ] || [ -z "$tree" ] || ! _hi_tool_here "$m" || eff="$tree"
    for p in "${locs[@]}"; do
      [ -n "$p" ] || continue
      if [ -z "${m##*/}" ]; then
        state=absent
        [ ! -d "$p" ] || state=present
      elif [ "$p" = "$eff" ]; then
        state=used
      elif [ -e "$p" ]; then
        state="passed over"
      else
        state=absent
      fi
      # only what is there: the places looked in and found empty are the
      # table's to know, not a line each here - nor the tree's default
      # behind a copy that replaces it
      [ "$state" != absent ] || continue
      [ "$state" != "passed over" ] || [ "$p" != "$_HI_ROOT/config/$m" ] || continue
      found=1
      [ "$p" != "$_HI_ROOT/config/$m" ] || p="the tree's config/$m"
      [ -z "${_HI_SITE_DIR:-}" ] || [ "$p" != "$_HI_SITE_DIR/$m" ] || p="the site's $p"
      text="$text${text:+; }$state $p"
    done
    _hi_member_label "$m" label
    [ -n "$found" ] || {
      if _hi_plugin_off "$m" p; then
        "$draw" "$label" "switched off ($p)"
        continue
      fi
      none="$none $m"
      continue
    }
    # a directory entry is its files, the overlay's copy of each name first
    case "$m" in */)
      _hi_count_lines p < <(_hi_overlay_files "$m")
      if [ "$p" = 0 ]; then "$draw" "$label" "$text - no file rides"; else "$draw" "$label" "$text - $p file(s) ride" ok; fi
      continue
      ;;
    esac
    if [ -n "$eff" ]; then
      "$draw" "$label" "$text" ok
    else
      _hi_unsent_why "$m" p || p="not the file in force here"
      "$draw" "$label" "$text - not sent: $p"
    fi
  done
  [ -n "$none" ] || return 0
  # one name for a tool's family found nowhere at all: micro/ for its three
  # files, oh-my-posh.* for its three formats
  local family said=" " all
  text=""
  for m in $none; do
    family="$m"
    case "$m" in */*) family="${m%%/*}/" ;; oh-my-posh.*) family="oh-my-posh.*" ;; esac
    all=1
    for p; do
      case "$p" in "$family"* | "${family%\*}"*) _hi_list_has "$none" "$p" || all=0 ;; esac
    done
    [ "$all" = 1 ] || family="$m"
    ! _hi_list_has "$said" "$family" || continue
    said="$said$family " text="$text${text:+ }$family"
  done
  "$draw" "none anywhere" "$text"
}

# _hi_plugin_words - every word $_HI_PLUGINS_OFF may hold that a row names,
# its plugin and its member, one a line
function _hi_plugin_words() {
  _hi_plugin_rows | cut -d'|' -f1,3 | tr '|' '\n' | sort -u
}

# _hi_plugin_word_ok <word> <words> - may $_HI_PLUGINS_OFF hold it: a word of
# _hi_plugin_words (space-bounded), or one file of a directory row the list
# switches (extensions/10-kube), there or not
function _hi_plugin_word_ok() {
  local _hi_pk_r _hi_pk_g
  case "$2" in *" $1 "*) return 0 ;; esac
  _hi_overlay_row "$1" _hi_pk_r || return 1
  case "${_hi_pk_r%%|*}" in */) ;; *) return 1 ;; esac
  [ "${_hi_pk_r%%|*}${1##*/}" = "$1" ] || return 1
  _hi_row_col "$_hi_pk_r" group _hi_pk_g
  [ "$_hi_pk_g" != - ] && _hi_dir_member_ok "${1##*/}"
}

# _hi_file_bytes <file> - its size in bytes
function _hi_file_bytes() {
  # ${n// /} rather than a `tr` fork to strip BSD wc's padding
  local n
  n="$(wc -c <"$1")"
  printf '%s' "${n// /}"
}
