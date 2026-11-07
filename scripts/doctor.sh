#!/usr/bin/env bash
# `hi --doctor [target]`: why hi is slow or failing. Reports the local tree,
# the overlay, and every backend through the same bounded probes the header
# and completion make; given a target, walks a real connect's resolution and
# ssh probe. Read-only, locally and remotely. The target section is
# doctor_target.sh.
#
# SC2317/SC2329: shellcheck follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"` and marks the rest unreachable; hi.sh's BASH_SOURCE
# guard says otherwise.
# shellcheck disable=SC2317,SC2329

# --text ahead of core.sh, which sets its palette as it is sourced
_HI_TEXT=0
case " $* " in *" --text "*) _HI_TEXT=1 && export NO_COLOR=1 ;; esac

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
[ -z "${_HI_ROOT:-}" ] || [ "${_HI_ROOT%/*}" != "${_HI_HOME:-${_HI_ROOT%/*}}" ] || _hi_d="$_HI_ROOT"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
# shellcheck source=./table.sh
source "$_hi_d/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_hi_d/scripts/rc.sh"
unset _hi_d

function _hi_doctor_help() {
  cat <<EOF
Usage: ${_HI_ARGV0:-doctor.sh} [--json] [--problems] [--text] [--use <backend>] [ssh-options] [target]

A read-only report, a table a section - the local tree, the config overlay,
the files, the shell configs, the install, the backends, and a target when
one is named - its rows marked $_HI_MARK_OK ok, ! warn, $_HI_MARK_NO bad, or blank for
information. Exits 1 on any bad row, 0 otherwise.

  --problems       only the warn and bad rows, in one box
  --text           no box and no color: "section / label: text" a line
  --json           the report as one JSON document: version, target,
                   findings (the count of bad rows), and rows of section,
                   label, text, and severity (info, ok, warn, bad)
  --use <backend>  the target's backend, as a connect's --use names it
  ssh-options      -p, -i, -J, -o and the rest reach the target's BatchMode
                   probe, as a connect's would
--plain, --keep, --no-keep, and --end are accepted and ignored. man hi has
what each section checks.
EOF
}

# hi.sh sourced for its backend predicates, $_HI_PAYLOAD and _hi_use_backend;
# the args are saved first, since hi.sh must see none, and sorted after it.
_HI_DOC_TARGET=""
_HI_DOC_JSON=0
_HI_DOC_PROBLEMS=0
_HI_DOC_BACKEND=""
_HI_DOC_SSHARGS=()
_hi_doc_args=("$@")
set --
# shellcheck source=../hi.sh
source "$_HI_LAUNCHER"
# $_HI_HEADER_ORDER_DEFAULT, for the settings rows; only defines functions
# shellcheck source=../common/header.sh
source "$_HI_HEADER"

# The flags, the target and ssh options in any order. hi.sh's _hi_ssh_opt
# sorts an ssh option from its value; an unknown `--word` and a second target
# are errors, and --use twice is refused as a connect refuses it.
_HI_ME="${_HI_ARGV0:-doctor.sh}"
_hi_arm=""
# the guard: no arguments is an empty array (GLOSSARY: HI.01)
set -- ${_hi_doc_args[@]+"${_hi_doc_args[@]}"}
while [ $# -gt 0 ]; do
  _hi_arg="$1"
  case "$_hi_arg" in
  --json) _HI_DOC_JSON=1 ;;
  --problems) _HI_DOC_PROBLEMS=1 ;;
  # read ahead of core.sh, above
  --text) ;;
  --use | --use=*)
    _hi_flag_word_or_die _hi_arm "--use needs a backend name (ssh counts as one)" "$@"
    [ $? -eq 2 ] && shift
    _HI_DOC_BACKEND="$(_hi_use_backend "$_hi_arm" "$_HI_DOC_BACKEND")" || exit 1
    ;;
  # connect-time flags: accepted, never read as a target
  --plain | --keep | --no-keep | --end) ;;
  -h | --help)
    _hi_doctor_help
    exit 0
    ;;
  # ssh's own terminator, forwarded as hi.sh does
  --)
    _HI_DOC_SSHARGS+=("$_hi_arg")
    ;;
  --*)
    _hi_die "unknown option $_hi_arg (--json, --problems, --text, --use <backend>, ssh options, a target)"
    ;;
  -*)
    _hi_ssh_opt "$@" || shift
    _HI_DOC_SSHARGS+=("${_HI_SSH_OPT[@]}")
    ;;
  *)
    [ -z "$_HI_DOC_TARGET" ] || _hi_die "one target at a time ($_HI_DOC_TARGET and $_hi_arg)"
    _HI_DOC_TARGET="$_hi_arg"
    ;;
  esac
  shift
done
unset _hi_arg _hi_arm _hi_doc_args
[ "$_HI_DOC_JSON" != 1 ] || [ "$_HI_TEXT" != 1 ] || _hi_die "--json and --text are two forms of the report: one at a time"

_HI_DOC_BAD=0
# the open section, and the JSON rows so far: the document prints whole at
# the end, since its header carries the bad rows' count
_HI_DOC_SECTION=""
_HI_DOC_ROWS=""
# every warn and bad row so far, for doctor_findings, a findings label
# prefixed with its section key
_HI_DOC_WARN=0
_HI_DOC_F_LABEL=() _HI_DOC_F_TEXT=() _HI_DOC_F_SEV=()
# 1 while the last row was a finding: an unlabeled row after it (ssh's words
# under a failed connect) follows it into the findings box
_HI_DOC_IN_FINDING=0

# doctor_section <key> <title> - open a section: the key is the stable name
# --json and --text carry, the title the banner. Each ends in doctor_flush.
function doctor_section() {
  _HI_DOC_SECTION="$1"
  if [ "$_HI_TEXT" = 1 ]; then
    _HI_TEXT_SECTION="$1"
    return 0
  fi
  [ "$_HI_DOC_JSON" = 1 ] || [ "$_HI_DOC_PROBLEMS" = 1 ] || _hi_section "$2"
}

# doctor_flush - draw the open section's table, none under --problems
function doctor_flush() {
  [ "$_HI_DOC_PROBLEMS" = 1 ] || _hi_rows_flush
  _HI_ROWS_LABEL=() _HI_ROWS_TEXT=() _HI_ROWS_SEV=() _HI_ROWS_COLOR=()
  _HI_DOC_IN_FINDING=0
}

# doctor_findings - --problems' one box of every warn and bad row
function doctor_findings() {
  [ "${#_HI_DOC_F_SEV[@]}" -gt 0 ] || return 0
  _hi_h2 "Findings: $_HI_DOC_BAD bad, $_HI_DOC_WARN warn"
  _HI_TEXT_SECTION=findings
  _HI_ROWS_LABEL=("${_HI_DOC_F_LABEL[@]}")
  _HI_ROWS_TEXT=("${_HI_DOC_F_TEXT[@]}")
  _HI_ROWS_SEV=("${_HI_DOC_F_SEV[@]}")
  _hi_rows_flush
}

# _hi_json_str <outvar> <text> - <text> as a JSON string, quotes included:
# backslash and quote escaped, newline, tab and CR as spaces
function _hi_json_str() {
  local _hi_js="$2" _hi_js_nl=$'\n' _hi_js_tab=$'\t' _hi_js_cr=$'\r'
  _hi_js="${_hi_js//"$_hi_js_nl"/ }"
  _hi_js="${_hi_js//"$_hi_js_tab"/ }"
  _hi_js="${_hi_js//"$_hi_js_cr"/ }"
  _hi_js="${_hi_js//\\/\\\\}"
  _hi_js="${_hi_js//\"/\\\"}"
  printf -v "$1" '"%s"' "$_hi_js"
}

# doctor_row <label> <text> [info|ok|warn|bad] - one row of the open section;
# a bad one is counted. Under --json it joins the document, else the table,
# and a warn or bad one the findings.
function doctor_row() {
  local sev="${3:-info}" section label text
  [ "$sev" != bad ] || _HI_DOC_BAD=$((_HI_DOC_BAD + 1))
  if [ "$_HI_DOC_JSON" = 1 ]; then
    _hi_json_str section "$_HI_DOC_SECTION"
    _hi_json_str label "$1"
    _hi_json_str text "$2"
    _HI_DOC_ROWS="$_HI_DOC_ROWS${_HI_DOC_ROWS:+,
}    {\"section\": $section, \"label\": $label, \"text\": $text, \"severity\": \"$sev\"}"
    return 0
  fi
  _hi_row "$1" "$2" "$sev"
  case "$sev" in
  warn | bad)
    [ "$sev" = bad ] || _HI_DOC_WARN=$((_HI_DOC_WARN + 1))
    _HI_DOC_IN_FINDING=1
    _HI_DOC_F_LABEL+=("${_HI_DOC_SECTION:+$_HI_DOC_SECTION/}$1")
    ;;
  *)
    [ "$_HI_DOC_IN_FINDING" = 1 ] && [ -z "$1" ] || {
      _HI_DOC_IN_FINDING=0
      return 0
    }
    _HI_DOC_F_LABEL+=("")
    ;;
  esac
  _HI_DOC_F_TEXT+=("$2") _HI_DOC_F_SEV+=("$sev")
  return 0
}

# The local tree, and the tools a payload needs here: base64 (or openssl's)
# for ssh, tar for every transport, and gzip, which only libarchive's tar can
# do without (hi.sh's _hi_can_gzip).
function doctor_local() {
  local branch="" changes=0 wire missing nice_missing line
  doctor_section local "The local tree"
  doctor_row tree "$_HI_ROOT"
  _hi_version line
  doctor_row version "$line"
  if [ -d "$_HI_ROOT/.git" ]; then
    # the branch read off HEAD itself, a git fewer
    line=""
    [ ! -r "$_HI_ROOT/.git/HEAD" ] || IFS= read -r line <"$_HI_ROOT/.git/HEAD" || true
    case "$line" in 'ref: refs/heads/'*) branch="${line#ref: refs/heads/}" ;; esac
    _hi_count_lines changes < <(git -C "$_HI_ROOT" status --short 2>/dev/null)
    doctor_row checkout "git, ${branch:-detached HEAD (a release tag?)}, $changes local change(s)"
  else
    doctor_row checkout "no .git - a package or tarball install (hi --update names the way forward for each)"
  fi
  # A missing tool is named once and the size skipped, which would fail with
  # it. The armor is probed on this $PATH, not read off hi.sh's $_HI_ARMOR.
  local armor=base64
  command -v base64 >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 || armor=openssl
  local -a floor=("$armor" tar)
  _hi_missing_into missing "${floor[@]}"
  _hi_missing_into nice_missing gzip
  if [ -n "$missing" ]; then
    doctor_row tools "MISSING locally: $missing - hi cannot ship a payload without them" bad
  elif ! _hi_can_gzip; then
    missing=gzip
    doctor_row tools "MISSING locally: gzip - this tar runs it for -z, so hi cannot pack a payload without it" bad
  else
    doctor_row tools "${floor[*]} present${nice_missing:+, no gzip (your tar compresses on its own - a padded payload, not a broken one)}" \
      "${nice_missing:+warn}"
  fi
  # what leaves this machine, and what it unpacks to
  if [ -z "$missing" ]; then
    _hi_wire_bytes wire
    _hi_human_bytes "$wire" wire
    doctor_row payload "$wire over the wire per ssh session, $(_hi_size) unpacked (${_HI_PAYLOAD[*]})"
  else
    doctor_row payload "unknown - needs $missing to measure (${_HI_PAYLOAD[*]})" bad
  fi
  # rc_shell_present, as doctor_install reads it, so the two agree
  local row have=""
  for row in "${_HI_RC_TABLE[@]}"; do
    rc_shell_present "${row%%|*}" && have="$have${row%%|*} "
  done
  doctor_row shells "local: ${have:-none?!}"
  doctor_flush
}

# doctor_code_dir <member/> <dir> <shell...> - extensions/ (GLOSSARY: HI.59)
# or header/ (HI.58): a row for each entry that never loads, each member a
# <shell> here cannot parse, and the load order
function doctor_code_dir() {
  local label="$1" dir="$2" f n sh bad order=""
  local -a _hi_members=() _hi_strays=()
  shift 2
  _hi_dir_members "$dir"
  for f in ${_hi_strays[@]+"${_hi_strays[@]}"}; do
    doctor_row "$label${f##*/}" "ignored - a backup, a temp file, or not a plain name, so it never loads" warn
  done
  for f in ${_hi_members[@]+"${_hi_members[@]}"}; do
    n="${f##*/}"
    order="$order, $n"
    bad=""
    for sh; do
      command -v "$sh" >/dev/null 2>&1 || continue
      case "$sh" in fish) fish --no-config -n "$f" ;; *) "$sh" -n "$f" ;; esac >/dev/null 2>&1 ||
        bad="${bad:+$bad, }$sh"
    done
    [ -z "$bad" ] || doctor_row "$label$n" "does not parse in $bad - skipped there" warn
  done
  [ -z "$order" ] || doctor_row "$label" "loads in order: ${order#, }"
}

# doctor_bin_dir - the overlay's bin/ (GLOSSARY: HI.58): a row for each entry
# that stays home, with why (pack.sh's _hi_bin_ok)
function doctor_bin_dir() {
  local f why
  for f in "$_HI_CONFIG_DIR"/bin/*; do
    [ -e "$f" ] || continue
    why="not a plain file of a plain name"
    if [ -f "$f" ] && _hi_dir_member_ok "${f##*/}"; then
      ! _hi_bin_ok "$f" why || continue
    fi
    doctor_row "bin/${f##*/}" "left home - $why" warn
  done
}

# The numbers of a file's lines that set something secret-shaped: a TOKEN,
# SECRET, PASSWORD, API, ACCESS or PRIVATE key name given a literal value
# where an assignment starts (not a $variable, a _FILE or _DIR path, or
# inside another value as LS_COLORS's `*passwd=0;38`), fish's `set` of one, a
# known issuer's token prefix, or a private key header. Comments and lines
# under hi-allow are skipped; toupper(), since mawk and busybox lack
# IGNORECASE.
# shellcheck disable=SC2016 # awk's own $0
_HI_SECRET_AWK='
/hi-allow-start/ { blk = 1 }
/hi-allow-end/ { blk = 0; prev = $0; next }
{
  up = toupper($0)
  hit = 0
  if (!blk && prev !~ /hi-allow/ && $0 !~ /^[ \t]*(#|--|;|\/\/)/) {
    if (up ~ /(^|[ \t"\047;&|({,])[A-Z0-9_.-]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Z0-9_]*[ \t]*[=:][ \t]*["\047]?\\?[^ \t"\047$\\]/ &&
      up !~ /(TOKEN|SECRET|PASSWORD|PASSWD|KEY)[A-Z0-9_]*_(DIR|FILE|PATH|CMD|COMMAND|HELPER|STORE)[A-Z0-9_]*[ \t]*[=:]/) hit = 1
    if (up ~ /^[ \t]*SET[ \t]+(-[A-Z]+[ \t]+)*[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Z0-9_]*[ \t]+[^ \t$(]/) hit = 1
    if ($0 ~ /(ghp_|gho_|github_pat_|xox[baprs]-|AKIA[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z])[A-Za-z0-9_]/) hit = 1
    if ($0 ~ /-----BEGIN [A-Z ]*PRIVATE KEY/) hit = 1
  }
  if (hit) print FNR
  prev = $0
}'

# _hi_doc_now <outvar> - core.sh's _hi_now, with no fork on bash 5
function _hi_doc_now() {
  printf -v "$1" '%s' "${EPOCHREALTIME:-$(_hi_now)}"
}

# doctor_riding <member...> - a secret-shaped line in a file that rides, by
# file and line, its value unprinted
function doctor_riding() {
  local member src n
  for member; do
    _hi_overlay_src "$member" src || continue
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      doctor_row "$member:$n" "sets something secret-shaped, and $src rides to every host you hi to - keep it in an rc that stays home (a hi-allow comment above the line says it is meant)" warn
    done < <(awk "$_HI_SECRET_AWK" "$src" 2>/dev/null)
  done
}

function doctor_config() {
  local f t v label late
  doctor_section config "The config overlay ($_HI_CONFIG_DIR) - what targets get"
  # a present settings.sh is doctor_configs' row, a parser each
  [ -f "$_HI_SETTINGS" ] ||
    doctor_row settings.sh "none - defaults apply (hi --configure writes one)"
  # ...and a shape a newer hi wrote, which nothing here converts back
  _hi_settings_shape v "$_HI_SETTINGS"
  [ -z "$v" ] || [ "$v" -le "$_HI_SETTINGS_SHAPE" ] ||
    doctor_row settings.sh "is shape $v, which this hi does not read (it reads $_HI_SETTINGS_SHAPE): a newer hi wrote it - move this one up, or hi --configure rewrites the block in this one's shape" bad
  # the site tier (HI.61)
  if [ -d "${_HI_SITE_DIR:-}" ]; then
    t=""
    for f in settings.sh colors packages plugins; do
      [ ! -f "$_HI_SITE_DIR/$f" ] || t="$t${t:+ }$f"
    done
    doctor_row site "$_HI_SITE_DIR holds ${t:-none of settings.sh, colors, packages, plugins} - read after the tree's defaults and before yours, and sent where you have no copy"
  fi
  # settings.<tag>.sh: read for a target carrying that tag, never sent as itself
  local tags=""
  for f in "$_HI_CONFIG_DIR"/settings.*.sh; do
    [ -f "$f" ] || continue
    t="${f##*/settings.}"
    t="${t%.sh}"
    case "$t" in
    *[!A-Za-z0-9_-]*) doctor_row "settings.$t.sh" "never read - a tag's file is named by a tag of letters, digits, _ and -" warn ;;
    *) tags="$tags${tags:+ }$t" ;;
    esac
  done
  [ -z "$tags" ] ||
    doctor_row "tag settings" "$tags - each settings.<tag>.sh is read for a host whose # Tags: or Tag line names it, a container, allocation, or pod for its backend's word, and a pod for its context and namespace, and joined to the settings.sh that target gets"
  doctor_settings_values
  # a file under a name hi stopped reading before 1.0
  for t in $_HI_OVERLAY_RENAMES; do
    [ -e "$_HI_CONFIG_DIR/${t%%:*}" ] || continue
    f=""
    case "$t" in
    carry:*) f="hi --configure converts it" ;;
    *)
      case "${t#*:}" in */*) f="mkdir -p $_HI_CONFIG_DIR/${t#*:}" f="${f%/*} && " ;; esac
      f="${f}mv $_HI_CONFIG_DIR/${t%%:*} $_HI_CONFIG_DIR/${t#*:}"
      ;;
    esac
    doctor_row "${t%%:*}" "an old name hi no longer reads - it is ${t#*:} now: $f" bad
  done
  # a plugins row _hi_plugins_load turned down, whose member rides nowhere
  # (GLOSSARY: HI.63)
  _hi_plugins_load
  for t in ${_HI_PLUGIN_BAD[@]+"${_HI_PLUGIN_BAD[@]}"}; do
    doctor_row "${t%%|*}" "ignored - ${t#*|}" warn
  done
  # what the files table cannot say of a member; where it comes from is that
  # table's
  for f in "${_HI_OVERLAY_FILES[@]}" ${_HI_PLUGIN_FILES[@]+"${_HI_PLUGIN_FILES[@]}"}; do
    case "$f" in
    extensions/) doctor_code_dir "$f" "$_HI_EXTENSIONS" bash zsh fish ;;
    # cells are bash's, and none loads with the header off
    header/) _hi_plugin_off "$f" || doctor_code_dir "$f" "$_HI_HEADER_CELLS" bash ;;
    ssh_tags)
      ! _hi_overlay_src "$f" t ||
        doctor_row "$f" "the # Tags: and Tag lines of $_HI_SSH_CONFIG ride along - a hop taken from inside a session keeps its tag colors"
      ;;
    bin/) _hi_plugin_off "$f" || doctor_bin_dir ;;
    esac
    case "$f" in settings.sh | ssh_tags | */) continue ;; esac
    [ -f "$_HI_CONFIG_DIR/$f" ] || continue
    _hi_member_label "$f" label
    t=""
    if ! _hi_overlay_src "$f" t; then
      # a copy that rides nowhere and was not switched off
      _hi_plugin_off "$f" || ! _hi_unsent_why "$f" late ||
        doctor_row "$label" "not sent - $late, so targets keep their own" warn
    elif [ "$t" = "$_HI_CONFIG_DIR/$f" ] && [ -f "$_HI_ROOT/config/$f" ] && cmp -s "$t" "$_HI_ROOT/config/$f"; then
      doctor_row "$label" "a copy of the tree's, unchanged - edit it to override"
    fi
  done
  # a line naming a file no target has, as the packer drops it: hi.sh's
  # _hi_include_lint, the packer's own rows (GLOSSARY: HI.57)
  local member lineno kind text fate said
  fate="dropped on the way out (a # hi-allow line above it keeps it, # hi-quiet drops it without this row; a -start and -end pair of either decides a block)"
  while IFS='|' read -r member lineno kind text; do
    [ -n "$member" ] || continue
    case "$kind" in
    unclosed)
      doctor_row "$member:$lineno" "$text has no ${text%%-start*}-end below it, so it decides nothing" warn
      continue
      ;;
    carry)
      doctor_row "$member:$lineno" "under hi-carry, $text - nothing rides for it" warn
      continue
      ;;
    plugin) said="names a plugin manager" ;;
    *) said="reads a file hi does not carry" ;;
    esac
    doctor_row "$member:$lineno" "$said - $text - $fate" warn
  done < <(_hi_include_lint)
  local -a members=()
  _hi_read_lines members < <(_hi_overlay_files)
  doctor_riding ${members[@]+"${members[@]}"}
  # aliases.sh loads after hi's aliases are built, so a value they read, set
  # there, does nothing; the toggles are read off common/aliases.sh
  local toggles asrc="" atext=""
  _hi_overlay_src aliases.sh asrc || true
  [ -z "$asrc" ] || atext="$(grep -v '^[[:space:]]*#' "$asrc")" || true
  late=""
  if [ -n "$atext" ]; then
    toggles="$(grep -oE '_HI_(DISABLE_[A-Z_]+|TOOL_ALIASES|SUDO_ALIAS)' "$_HI_ALIASES" 2>/dev/null | sort -u | tr '\n' '|')"
    late="$(printf '%s\n' "$atext" |
      grep -oE "(_HI_[A-Z0-9]+_(OPTS|BIN)|${toggles%|})=" |
      tr -d = | sort -u | tr '\n' ' ')" || true
  fi
  [ -z "$late" ] ||
    doctor_row alias-vars "aliases.sh sets ${late% } - hi's aliases are built before it loads, so it does nothing; move it to settings.sh" bad
  # ...an alias of it replaces a wiring line's of that name (GLOSSARY: HI.62)
  local wired="" shadowed="" re
  _hi_overlay_wiring wired ${members[@]+"${members[@]}"}
  while [ "${wired#* alias }" != "$wired" ]; do
    wired="${wired#* alias }"
    t="${wired%%=*}"
    ! _hi_list_has "$shadowed" "$t" || continue
    re="(^|[[:space:];&|])alias[[:space:]]+$t="
    [[ ! "$atext" =~ $re ]] || shadowed="$shadowed $t"
  done
  [ -z "$shadowed" ] ||
    doctor_row alias-wired "aliases.sh aliases${shadowed} - on a target that replaces hi's alias, so the config hi carries for it goes unused there; drop the alias, or keep that config home with its _HI_DISABLE_ toggle" warn
  # ...and its $EDITOR or $VISUAL replaces the session's (load.sh's
  # _hi_session_editor)
  re='(^|[[:space:];&|])(export[[:space:]]+)?(EDITOR|VISUAL)='
  [[ ! "$atext" =~ $re ]] ||
    doctor_row alias-editor "aliases.sh sets \$EDITOR or \$VISUAL - on a target, naming another editor than hi's replaces the one hi exports, so git and sudo -e start it without the config hi carries; _HI_EDITOR in settings.sh names an editor instead" warn
  # a switched-off plugin's one row: the files table lists none of it
  [ -z "${_HI_PLUGINS_OFF:-}" ] || doctor_row "plugins off" "$_HI_PLUGINS_OFF (hi --plugins lists each)"
  doctor_flush
}

# doctor_settings_values - each value set (settings.sh is sourced) against
# its scripts/settings row's <check>, and the colors file's tables (HI.50)
function doctor_settings_values() {
  local name check why v
  while IFS='|' read -r name check why; do
    v="${!name:-}"
    [ -n "$v" ] || continue
    _hi_setting_check "$check" "$v" || doctor_row "$name" "'$v' is ignored - $why" bad
  done < <(_hi_setting_rules)
  [ -z "${_HI_PACKAGES_MIN_PRIORITY:-}" ] ||
    doctor_row _HI_PACKAGES_MIN_PRIORITY "is ignored - name the groups to show in _HI_PACKAGES_GROUPS" bad
  for name in ${_HI_OLD_TOGGLES//|/ }; do
    name="_HI_DISABLE_$name"
    [ -z "${!name:-}" ] ||
      doctor_row "$name" "is ignored - hi --disable-plugin keeps a config home, and hi --configure converts this line" bad
  done
  _hi_data_shape v "${_HI_PACKAGES:-}" "$_HI_FLAT_PACKAGES"
  case "$v" in
  flat) doctor_row packages "$_HI_PACKAGES has name:priority rows, which this hi reads none of - hi --configure converts it" bad ;;
  sections) doctor_row packages "$_HI_PACKAGES has rows that are not TOML's name = [...], which this hi does not read - hi --configure converts it" bad ;;
  tables) doctor_row packages "$_HI_PACKAGES has [group.required] or [group.unwanted] tables, which this hi reads as groups of those names - a \"+name\" or \"-name\" row says it now, and hi --configure converts it" bad ;;
  *)
    while IFS='|' read -r v why; do
      doctor_row packages "$why" "$v"
    done < <(_hi_packages_drift "${_HI_PACKAGES:-}" "$_HI_ROOT/config/packages")
    ;;
  esac
  _hi_data_shape v "${_HI_COLORS:-}" "$_HI_FLAT_COLORS"
  case "$v" in
  flat) doctor_row colors "$_HI_COLORS has type,name,color rows, which pin nothing - hi --configure converts it" bad ;;
  sections) doctor_row colors "$_HI_COLORS has rows that are not TOML's name = \"color\", which pin nothing - hi --configure converts it" bad ;;
  *)
    while IFS='|' read -r v why; do
      doctor_row colors "line $v is no row, and pins nothing: '$why' - a row is name = \"color\" on one line" warn
    done < <(_hi_toml_strays "${_HI_COLORS:-}")
    ;;
  esac
  [ -z "${_HI_COLOR_SCHEME:-}" ] || _hi_scheme_ok "$_HI_COLOR_SCHEME" ||
    doctor_row colors "[scheme] '$_HI_COLOR_SCHEME' is ignored - colors is 24 six-digit hex words, and packages 24 more" bad
  [ -z "${_HI_PACKAGES_PALETTE:-}" ] || _hi_ramp_ok "$_HI_PACKAGES_PALETTE" ||
    doctor_row colors "[palette] '$_HI_PACKAGES_PALETTE' is ignored - installed and missing are four color names each" bad
  for name in _HI_COLOR_SCHEME:scheme _HI_PACKAGES_PALETTE:palette; do
    if [ -f "${_HI_SETTINGS:-}" ] && grep -E "^[[:space:]]*(export[[:space:]]+)?${name%%:*}=" "$_HI_SETTINGS" >/dev/null; then
      doctor_row "${name%%:*}" "is ignored - it is the [${name#*:}] table of $_HI_CONFIG_DIR/colors now" bad
    fi
  done
}

# doctor_files - every member's row, as `hi --plugins` lists it
function doctor_files() {
  doctor_section files "The files hi looks for"
  local row _HI_ROW_FN=doctor_row
  local -a members=()
  _hi_plugins_load
  # settings.sh, extensions/ and what is off are the overlay section's
  for row in "${_HI_OVERLAY_TABLE[@]}" ${_HI_PLUGIN_ROWS[@]+"${_HI_PLUGIN_ROWS[@]}"}; do
    case "${row%%|*}" in settings.sh | extensions/) continue ;; esac
    _hi_plugin_off "${row%%|*}" || members+=("${row%%|*}")
  done
  _hi_member_rows "${members[@]}"
  doctor_flush
}

# doctor_config_row <label> <file> <check...> - a file through its parser,
# rc.sh's _hi_config_check as install.sh runs it; no row without either
function doctor_config_row() {
  local label="$1" target="$2" rc=0
  shift 2
  _hi_config_check "$target" "$@" || rc=$?
  [ "$rc" -ne 2 ] || return 0
  if [ "$rc" -eq 0 ]; then
    doctor_row "$label" "$target parses ($1)" ok
  else
    doctor_row "$label" "$target has issues ($1): ${_HI_CONFIG_CHECK_OUT%%$'\n'*}" bad
  fi
  return 0
}

# install.sh's syntax checks as rows: the rc files, then the overlay's shell
# files under every parser a target may source them with
function doctor_configs() {
  local row shell target check file label
  doctor_section configs "Shell configs (the rc files and the overlay's shell files, parsed)"
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell _ _ target check _ <<<"$row"
    # shellcheck disable=SC2086 # the check column is a command plus its flag
    doctor_config_row "$shell" "$target" $check
  done
  # the file as the label: rc.sh's labels overflow the column
  for row in "${_HI_OVERLAY_CHECKS[@]}"; do
    IFS='|' read -r file check <<<"$row"
    # shellcheck disable=SC2086
    doctor_config_row "$file" "$_HI_CONFIG_DIR/$file" $check
  done
  # a tag's and the site's settings.sh, under settings.sh's two parsers
  for target in "$_HI_CONFIG_DIR"/settings.*.sh "${_HI_SITE_DIR:-/nonexistent}/settings.sh"; do
    [ -f "$target" ] || continue
    label="${target##*/}"
    [ "$target" != "${_HI_SITE_DIR:-}/settings.sh" ] || label="site settings.sh"
    doctor_config_row "$label" "$target" sh -n
    doctor_config_row "$label" "$target" fish --no-execute
  done
  doctor_flush
}

# _hi_rc_names_tree <rc-file> - the path a marker line in <rc-file> names,
# on stdout: its _HI_ROOT line's, else its _HI_HOME line's (the directory
# holding a say-hi); empty when none does
function _hi_rc_names_tree() {
  local _hi_rn
  _hi_rn="$(grep -F "$_HI_MARKER" "$1" 2>/dev/null | sed -n 's/.*_HI_ROOT[= ]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
  [ -n "$_hi_rn" ] ||
    _hi_rn="$(grep -F "$_HI_MARKER" "$1" 2>/dev/null | sed -n 's/.*_HI_HOME[= ]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
  printf '%s' "$_hi_rn"
}

# _hi_rc_names_this_tree <rc-file> - does the path that line names lead to
# this tree: as its root, or as the directory above a tree called say-hi
function _hi_rc_names_this_tree() {
  local _hi_rt
  _hi_rt="$(_hi_rc_names_tree "$1")"
  [ -n "$_hi_rt" ] || return 1
  [ "$_hi_rt" -ef "$_HI_ROOT" ] || { [ "${_HI_ROOT##*/}" = say-hi ] && [ "$_hi_rt" -ef "$_HI_HOME" ]; }
}

# The install: each shell's rc wired, and to this tree; the hi link and what
# `hi` on PATH runs; and the two ways a wired rc is never read (a macOS login
# bash, a moved .zshrc)
function doctor_install() {
  local row shell label target tree_rc dialect other found owner bindir profile form home
  doctor_section install "The install (what hi --install wired up)"
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label tree_rc target _ dialect <<<"$row"
    if ! rc_shell_present "$shell"; then
      doctor_row "$shell" "not installed here, nothing to wire"
    elif ! _hi_has_marker "$target" && ! rc_shell_wanted "$shell" "$target"; then
      doctor_row "$shell" "not wired - not your login shell, and no $target (hi --install --shell $shell wires it)"
    elif ! _hi_has_marker "$target"; then
      doctor_row "$shell" "$target has no hi lines (hi --install writes them)" warn
    elif rc_block_form form "$shell" "$tree_rc" "$dialect" "$target" && [ -n "$form" ]; then
      doctor_row "$shell" "$target is wired to this tree" ok
    elif grep -qF "$(tmpdir_line "$dialect")" "$target" || _hi_rc_names_this_tree "$target"; then
      # an older hi's block for this tree, whose lines this hi has replaced
      doctor_row "$shell" "$target is wired to this tree, but not with the lines this hi writes (hi --install refreshes them)" warn
    else
      other="$(_hi_rc_names_tree "$target")"
      rc_home home
      doctor_row "$shell" "$target names ${other:-another tree}, this is $home (hi --install repairs it)" bad
    fi
  done
  # zsh reads one .zshrc, under $ZDOTDIR or in ~ (_hi_zshrc_here)
  _hi_zshrc_here target
  for other in "$HOME/.zshrc" "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/.zshrc"; do
    if [ "$other" != "$target" ] && _hi_has_marker "$other" && ! _hi_has_marker "$target"; then
      doctor_row zdotdir "$other has hi's lines, but zsh reads $target (hi --install writes there now)" warn
    fi
  done
  # macOS: a login bash reads the first of ~/.bash_profile, ~/.bash_login and
  # ~/.profile, never ~/.bashrc
  if _hi_is_darwin && rc_shell_present bash; then
    _hi_login_bash_profile profile
    if [ -f "$profile" ] && grep -qF '.bashrc' "$profile"; then
      doctor_row login-bash "$profile reads ~/.bashrc" ok
    elif [ "$profile" = "$HOME/.bash_login" ]; then
      doctor_row login-bash "a login bash reads $profile, which never reaches ~/.bashrc - add to it: $_HI_BASH_PROFILE_LINE" warn
    else
      doctor_row login-bash "a login bash reads $profile, which never reaches ~/.bashrc (hi --install adds the line to ~/.bash_profile)" warn
    fi
  fi
  local runs=""
  _hi_path_lookup found hi || true
  [ -z "$found" ] || ! _hi_link_runs_this_tree "$found" || runs=1
  # shellcheck disable=SC2153 # $_HI_LINK is paths.sh's, exported
  if _hi_link_is_ours "$_HI_LINK"; then
    doctor_row link "$_HI_LINK -> $_HI_LAUNCHER" ok
    bindir="${_HI_LINK%/*}"
    _hi_on_path "$bindir" || doctor_row PATH "$bindir is not on PATH - the wired shells alias hi; scripts and other programs need it there" warn
  elif [ -e "$_HI_LINK" ] || [ -L "$_HI_LINK" ]; then
    owner="$(link_owner "$_HI_LINK" 2>/dev/null || true)"
    doctor_row link "$_HI_LINK is not this tree's: $(readlink "$_HI_LINK" 2>/dev/null || echo 'a regular file')${owner:+, the $owner package}" bad
  elif [ -n "$runs" ]; then
    doctor_row link "no $_HI_LINK, none needed: $found runs this tree" ok
  else
    doctor_row link "no $_HI_LINK - the wired shells alias hi; scripts and other programs need one (hi --install makes one; --link none chose none)" warn
  fi
  if [ -z "$found" ]; then
    doctor_row command "no hi on PATH (the wired shells alias it)"
  elif [ -n "$runs" ]; then
    doctor_row command "hi on PATH is $found, and runs this tree" ok
  else
    doctor_row command "hi on PATH is $found, which runs $(readlink "$found" 2>/dev/null || echo 'something else') - not this tree" warn
  fi
  doctor_flush
}

# doctor_backend <name> <cli> <probe...> - installed, answering, and how long
# the answer took; the same _hi_probe ceiling the header and completion use
function doctor_backend() {
  local name="$1" t0 t1 rc=0
  shift
  if ! command -v "$1" >/dev/null 2>&1; then
    doctor_row "$name" "not installed"
    return 0
  fi
  _hi_doc_now t0
  _hi_probe "$@" >/dev/null 2>&1 || rc=$?
  _hi_doc_now t1
  if [ "$rc" -eq 0 ]; then
    doctor_row "$name" "answering ($(_hi_elapsed "$t0" "$t1")s)" ok
  else
    doctor_row "$name" "installed but not answering after $(_hi_elapsed "$t0" "$t1")s (exit $rc) - completion and the header wait on this every time" warn
  fi
}

function doctor_backends() {
  local hosts t0 t1
  doctor_section backends "Backends (probes capped at ${_HI_PROBE_TIMEOUT:-$_HI_PROBE_TIMEOUT_DEFAULT}s each, like the header)"
  if [ -f "$_HI_SSH_CONFIG" ]; then
    # counted by targets.sh's own literal-Host rule
    _hi_count_lines hosts < <(_HI_TARGETS_TTL=0 sh "$_HI_TARGETS" ssh 2>/dev/null)
    doctor_row ssh "$hosts literal host(s) in $_HI_SSH_CONFIG"
  else
    doctor_row ssh "no $_HI_SSH_CONFIG - names still reach ssh, just without completion or tags"
  fi
  local row name probe off=""
  for row in "${_HI_BACKENDS[@]}"; do
    IFS='|' read -r name _ probe _ <<<"$row"
    if _hi_backend_off "$name"; then
      off="$off${off:+ }$name"
      continue
    fi
    # shellcheck disable=SC2086 # the probe column is a command line
    doctor_backend "$name" $probe
  done
  [ -z "$off" ] || doctor_row "switched off" "$off (_HI_BACKENDS_OFF) - never asked; --use still reaches one by name"
  _hi_doc_now t0
  _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" >/dev/null 2>&1 || true
  _hi_doc_now t1
  doctor_row completion "full target list built in $(_hi_elapsed "$t0" "$t1")s cold (TAB reuses it for ${_HI_TARGETS_TTL:-$_HI_TARGETS_TTL_DEFAULT}s)"
  doctor_flush
}

# shellcheck source=./doctor_target.sh
source "$_HI_ROOT/scripts/doctor_target.sh"

# GLOSSARY: HI.06 - executed, it runs the report
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# strict mode for the run alone, after core.sh's `set +euo pipefail`
# (GLOSSARY: HI.15)
set -euo pipefail

[ "$_HI_DOC_JSON" = 1 ] || [ "$_HI_DOC_PROBLEMS" = 1 ] || _hi_h1 "hi doctor"
doctor_local
doctor_config
doctor_files
doctor_configs
doctor_install
doctor_backends
[ -n "${_HI_DOC_TARGET:-}" ] && doctor_target "$_HI_DOC_TARGET"
if [ "$_HI_DOC_JSON" = 1 ]; then
  _hi_target_json=null _hi_version_json=""
  [ -z "$_HI_DOC_TARGET" ] || _hi_json_str _hi_target_json "$_HI_DOC_TARGET"
  _hi_version _hi_version_json
  _hi_json_str _hi_version_json "$_hi_version_json"
  printf '{\n  "version": %s,\n  "target": %s,\n  "findings": %s,\n  "rows": [\n%s\n  ]\n}\n' \
    "$_hi_version_json" "$_hi_target_json" "$_HI_DOC_BAD" "$_HI_DOC_ROWS"
else
  # --problems' box is its whole answer; the closing line stands in for none
  if [ "$_HI_DOC_PROBLEMS" = 1 ] && [ "${#_HI_DOC_F_SEV[@]}" -gt 0 ]; then
    doctor_findings
  elif [ "$_HI_DOC_BAD" -eq 0 ]; then
    _hi_h1 "Nothing looks broken" "$BRGREEN"
  else
    _hi_h1 "$_HI_DOC_BAD finding(s) above in red" "$RED"
  fi
fi
# 1 on any finding, never the count, which would wrap past 255
[ "$_HI_DOC_BAD" -eq 0 ] || exit 1
exit 0
