#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --preview <subject>`: what a setting resolves to, rendered the way a
# connect will render it, plus why.
#
#   colors     every ssh host and every known user in the color it lands in
#              (override/hosttag/pattern/hash) - for tuning config/colors
#   packages   the header's packages check: each group, whether it runs, the
#              colors it paints an installed and a missing package, a real
#              example of each from your own packages file, then the check
#   header     the connect header itself
#
# One script for the three subjects: they share the boxed table (table.sh),
# the palette they paint with, and the scheme line above every table.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d
# The renderer packages and header preview, reused rather than reimplemented -
# check_line is what paints every packages row below, so the preview cannot
# drift from the header. Sourcing header.sh only defines functions.
# shellcheck source=../common/header.sh
source "$_HI_HEADER"
# shellcheck source=./table.sh
source "$_HI_ROOT/scripts/table.sh"

_hi_subject="${1:-}"
_hi_argv0="${_HI_ARGV0:-preview.sh${_hi_subject:+ $_hi_subject}}"

function _hi_preview_usage() {
  cat <<EOF
Usage: ${_HI_ARGV0:-preview.sh} <colors|packages|header>

  colors     every ssh host and every known user, in the color it resolves to
  packages   the header's packages check: groups, marks, markers, then the check
  header     the connect header as it will print here

Each subject takes --help and no other argument.
EOF
}

case "$_hi_subject" in
colors | packages | header) shift ;;
-h | --help)
  _hi_preview_usage
  exit 0
  ;;
'')
  # sourced with no subject (the test suite's hatch below): every function,
  # no render, nothing to refuse
  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _hi_cecho "${_HI_ARGV0:-preview.sh}: one of colors, packages, or header is required (${_HI_ARGV0:-preview.sh} --help)" "$RED" >&2
    exit 1
  fi
  ;;
*)
  _hi_cecho "${_HI_ARGV0:-preview.sh}: unknown subject '$_hi_subject' - one of colors, packages, or header (${_HI_ARGV0:-preview.sh} --help)" "$RED" >&2
  exit 1
  ;;
esac

case "${1:-}" in
-h | --help)
  case "$_hi_subject" in
  colors)
    cat <<EOF
Usage: $_hi_argv0

Prints two tables - every known user, and every ssh host - rendered in the
color they'd actually appear in, alongside *why* they resolve that way (an
exact override, an ssh-config tag, a pattern, or the hash of the name).

Takes no arguments. Reads:
  config/colors        the type,name,color[,rrggbb] pins (its own comments explain them)
  ~/.ssh/config      hosts, and the "# Tags: ..." comments above them
EOF
    ;;
  packages)
    cat <<EOF
Usage: $_hi_argv0

Prints the legend for the header's packages check - every group in your
packages file, whether \$_HI_PACKAGES_GROUPS runs it, the colors it renders
installed and missing packages in, and one real example of each - then the
marks, then the check itself exactly as a connect will print it.

Takes no arguments. Reads:
  config/packages    the [group] sections of [-|+]package[,...] rows (a
                     ~/.config/say-hi/packages of your own replaces it)
  \$_HI_PACKAGES_GROUPS   the groups that run (unset: $_HI_PACKAGES_GROUPS_DEFAULT)
  \$_HI_PACKAGES_PALETTE   the ramp in force - unset for the shipped one, or
                     eight color names of your own - printed above the legend

A row's leading marker decides which states speak at all: none both ways,
\`-\` (unwanted) only as a warning when installed, \`+\` (required) only as an
alarm when missing - the line under the marks says the same. A group whose
STATE reads "off" prints nothing in the header whatever its colors say; its
example shows what it would print.
EOF
    ;;
  header)
    cat <<EOF
Usage: $_hi_argv0

Prints the connect header exactly as this machine would draw it, under the
settings.sh in force - the way to judge a header order, width, or palette
before saving it.

Takes no arguments.
EOF
    ;;
  esac
  exit 0
  ;;
'') ;;
*)
  _hi_cecho "$_hi_argv0: takes no arguments (got: $*) - $_hi_argv0 --help" "$RED" >&2
  exit 1
  ;;
esac

# which ramp the legend below is painted in - default, custom, or a value
# nothing paints, exactly as hi --doctor names it
function _hi_print_ramp_line() {
  local label
  _hi_ramp_label label
  _hi_cecho " | palette: $label"
}

# what the swatches are painted under, so an eyeball pass of a
# $_HI_COLOR_SCHEME says which one it is looking at (GLOSSARY: HI.50)
function _hi_print_scheme_line() {
  local label
  _hi_scheme_label label
  if _hi_has_truecolor; then
    _hi_cecho " | scheme: $label"
  else
    _hi_cecho " | scheme: $label (no truecolor here - the 16-color escapes render)"
  fi
}

#
# colors
#

# _hi_colors_rows <type> - every pinned name of that type, one per line, file
# order, not deduped - the one walk of $_HI_COLORS behind _hi_pattern_for,
# _hi_pattern_pins, and _hi_colors_names below. Not in core.sh: the colors
# preview is its only caller, and core.sh ships in the ssh payload under a
# size budget nothing a target runs should spend.
function _hi_colors_rows() {
  local cur_type="" cur_name
  [[ -f "$_HI_COLORS" ]] || return 0
  while read -r cur_name _; do
    case "$cur_name" in
    '' | '#'*) continue ;;
    '['*']')
      cur_type="${cur_name#[}"
      cur_type="${cur_type%]}"
      continue
      ;;
    esac
    [[ "$cur_type" = "$1" ]] || continue
    printf '%s\n' "$cur_name"
  done <"$_HI_COLORS"
}

# _hi_pattern_for <name> - the subnet-style pin (hostname row whose name field
# is a glob) that would color <name>, printed as the glob itself; core.sh's
# _hi_colors_pattern answers with the color, but the source cell wants the why
function _hi_pattern_for() {
  local cur_name
  while IFS= read -r cur_name; do
    case "$cur_name" in
    *[\*\?]*) _hi_ssh_pattern_hit "$1" "$cur_name" || continue ;;
    *) continue ;;
    esac
    printf '%s' "$cur_name"
    return 0
  done < <(_hi_colors_rows hostname)
  return 1
}

# every subnet-style pin, deduped in file order - each gets an example row in
# the hosts table, since a globbed name never appears in targets.sh's list
function _hi_pattern_pins() {
  local cur_name
  while IFS= read -r cur_name; do
    case "$cur_name" in
    *[\*\?]*) printf '%s\n' "$cur_name" ;;
    esac
  done < <(_hi_colors_rows hostname) | awk '!seen[$0]++'
}

function _hi_color_source() {
  local type="$1" name="$2" tag pat
  if _hi_override_color "$type" "$name" >/dev/null 2>&1; then
    printf 'override:%s' "$type"
    return
  fi
  if [[ "$type" = hostname ]] && tag=$(_hi_ssh_host_tag "$name") && _hi_override_color hosttag "$tag" >/dev/null 2>&1; then
    printf 'tag:%s' "$tag"
    return
  fi
  # after the tag, before the hash - _hi_resolve_color's order
  if [[ "$type" = hostname ]] && pat=$(_hi_pattern_for "$name"); then
    printf 'pattern:%s' "$pat"
    return
  fi
  printf 'hash'
}

# _hi_colors_names <type> [skip-name] - deduped pinned names of that type.
function _hi_colors_names() {
  local cur_name
  while IFS= read -r cur_name; do
    [ "$cur_name" != "${2:-}" ] || continue
    printf '%s\n' "$cur_name"
  done < <(_hi_colors_rows "$1") | awk '!seen[$0]++'
}

# both read config/colors through the _hi_colors_names above
function _hi_known_users() {
  {
    _hi_whoami
    _hi_colors_names username LOCALUSER
  } | awk '!seen[$0]++'
}

function _hi_known_usertags() {
  _hi_colors_names usertag
}

function _hi_preview_users() {
  local tag
  {
    _hi_known_users # already leads with _hi_whoami, LOCALUSER-pinned or not
    while IFS= read -r tag; do
      _hi_override_color usertag "$tag" >/dev/null 2>&1 && printf '%s\n' "$tag"
    done < <(_hi_known_usertags)
  } | awk '!seen[$0]++'
}

function _hi_group_preview_width() {
  local h n=$# pw=0
  for h in "$@"; do pw=$((pw + user_width + 1 + ${#h})); done
  printf '%s' $((pw + 2 * (n - 1)))
}

# _hi_group_index <key> - where $key sits in $group_order, or 1 if it isn't
# there yet. The bash 3.2 stand-in for `${group_hosts[$key]+x}`: it reads
# _hi_print_hosts_table's own local through bash's dynamic scoping, which is why
# it lives beside it rather than taking the array as an argument (bash 3.2 has
# no namerefs to pass one with).
function _hi_group_index() {
  local i
  for i in "${!group_order[@]}"; do
    [[ "${group_order[i]}" = "$1" ]] && {
      printf '%s' "$i"
      return 0
    }
  done
  return 1
}

# _hi_user_color_memo <user> <tag> <color-outvar> <escape-outvar> - most
# groups share the same (user, tag) pair (usually the empty tag), and
# _hi_resolve_color walks config/colors and ~/.ssh/config to answer one.
# Reads/writes _hi_print_hosts_table's own parallel arrays through bash's
# dynamic scoping, the same as _hi_group_index above; _hi_color_escape_var
# is core.sh's no-fork escape form, which a memo answering through an outvar
# can use directly.
# _hi_user_row <item> <color> <source> - one users-table row in <color>'s
# escape, at the caller's w_* widths (dynamic scoping)
function _hi_user_row() {
  local _hi_ur_esc
  _hi_color_escape "$2" _hi_ur_esc
  _hi_cell "$w_item" "$_hi_ur_esc" "$1"
  _hi_cell "$w_color" "$_hi_ur_esc" "$2"
  _hi_cell "$w_source" "$_hi_ur_esc" "$3"
  _hi_row_end
}

function _hi_user_color_memo() {
  local i color escape
  for i in "${!_hi_upc_keys[@]}"; do
    if [ "${_hi_upc_keys[i]}" = "$1"$'\x1f'"$2" ]; then
      printf -v "$3" '%s' "${_hi_upc_colors[i]}"
      printf -v "$4" '%s' "${_hi_upc_escapes[i]}"
      return 0
    fi
  done
  color="$(_hi_resolve_color username "$1" "$2")"
  _hi_color_escape_var escape "$color"
  printf -v escape '%b' "$escape"
  _hi_upc_keys+=("$1"$'\x1f'"$2")
  _hi_upc_colors+=("$color")
  _hi_upc_escapes+=("$escape")
  printf -v "$3" '%s' "$color"
  printf -v "$4" '%s' "$escape"
}

# users table: every known real user with a non-default color, plus LOCALUSER
# and every usertag override as its own "example" row
function _hi_print_users_table() {
  local color_name uidx tidx
  local users=() usertags=() u_source=() u_color=() t_color=()
  local w_item=9 w_color=5 w_source=6
  local localuser_color=""

  _hi_read_lines users < <(_hi_known_users)
  _hi_read_lines usertags < <(_hi_known_usertags)

  # every palette name fits, and a pin carrying a fourth-column hex resolves
  # to "<name>#<rrggbb>", which does not - so the widths below are taken from
  # the colors these rows actually resolve to as well as from the names
  _hi_widen w_color "${_HI_COLOR_NAMES[@]}"
  # ${a[@]+"${a[@]}"} throughout this file, not a plain "${a[@]}": on bash 3.2
  # (macOS) expanding an *empty* array under `set -u` is a fatal "unbound
  # variable", and a colors file with no usertag pins - or an ssh config with no
  # interesting hosts - leaves exactly that. The *index* form "${!a[@]}" needs no
  # such guard (it is already empty-safe), and must not be given one: bash 3.2
  # reads ${!a[@]+...} as expanding to nothing whatever the array holds, and
  # bash 5 reads it as an indirect reference and errors outright.
  _hi_widen w_item "${users[@]}" LOCALUSER ${usertags[@]+"${usertags[@]}"}
  # _hi_color_source re-reads config/colors end to end and walks ~/.ssh/config,
  # so the render loop below reads what this one worked out rather than asking
  # a second time for every user.
  for uidx in "${!users[@]}"; do
    u_source[uidx]="$(_hi_color_source username "${users[uidx]}")"
    _hi_resolve_color username "${users[uidx]}" '' color_name # outvar form: no fork per user
    u_color[uidx]="$color_name"
    _hi_widen w_source "${u_source[uidx]}"
    _hi_widen w_color "${u_color[uidx]}"
  done
  _hi_widen w_source "local:username"
  localuser_color=$(_hi_override_color username LOCALUSER 2>/dev/null) || localuser_color=""
  [[ -n "$localuser_color" ]] && _hi_widen w_color "$localuser_color"
  for tidx in "${!usertags[@]}"; do
    _hi_widen w_source "usertag:${usertags[tidx]}"
    t_color[tidx]="$(_hi_override_color usertag "${usertags[tidx]}")" || t_color[tidx]=""
    [[ -n "${t_color[tidx]}" ]] && _hi_widen w_color "${t_color[tidx]}"
  done

  _hi_hbar top "$w_item" "$w_color" "$w_source"
  _hi_head_row "$w_item" USER "$w_color" COLOR "$w_source" SOURCE
  _hi_hbar mid "$w_item" "$w_color" "$w_source"

  for uidx in "${!users[@]}"; do
    _hi_user_row "${users[uidx]}" "${u_color[uidx]}" "${u_source[uidx]}"
  done

  [[ -z "$localuser_color" ]] || _hi_user_row LOCALUSER "$localuser_color" local:username

  for tidx in "${!usertags[@]}"; do
    [[ -n "${t_color[tidx]}" ]] || continue
    _hi_user_row "${usertags[tidx]}" "${t_color[tidx]}" "usertag:${usertags[tidx]}"
  done

  _hi_hbar bottom "$w_item" "$w_color" "$w_source"
}

# hosts table: a LOCALHOSTNAME row (the current machine) followed by every
# ssh-config host grouped by the color it'd actually render with. PREVIEW
# combines every real known user plus the "example" users from the users
# table (LOCALUSER, each usertag) against that host's name(s)
function _hi_print_hosts_table() {
  # shellcheck disable=SC2034 # user_color: a required outvar of
  # _hi_user_color_memo below (its color half), never read on its own - only
  # user_escape, the memo's second outvar, feeds the render loop
  local name color_name source user user_color user_escape name_escape key
  local cur_line sep sep_w candidate idx idx2 li total_lines itemtext previewtext
  local tag
  local user_width=0 pw pad local_hostname
  local preview_users=() group_users=() group_order=() group_names=() item_lines=()
  # Five *parallel* indexed arrays sharing one index, rather than associative
  # arrays keyed by $key: `local -A` is bash 4 and macOS ships bash 3.2, where
  # the declaration alone is a fatal "invalid option".
  # group_order holds the keys, so it doubles as the lookup table below.
  local group_hosts=() group_source=() group_color=() group_tag=() group_pw=()
  local gidx localhostname_color="" localhostname_source
  # (user, tag) -> (color, escape), so the render loop below asks
  # _hi_resolve_color once per pair instead of once per (pair, group)
  local _hi_upc_keys=() _hi_upc_colors=() _hi_upc_escapes=()

  _hi_read_lines preview_users < <(_hi_preview_users)
  _hi_widen user_width ${preview_users[@]+"${preview_users[@]}"}
  # the usertag example rows that are no real user's name, " a b ": each is
  # drawn only under a host carrying its tag
  local known=" " tag_rows=" "
  while IFS= read -r user; do known+="$user "; done < <(_hi_known_users)
  while IFS= read -r tag; do
    case "$known" in *" $tag "*) ;; *) tag_rows+="$tag " ;; esac
  done < <(_hi_known_usertags)

  # The current machine renders as its own single-host group ahead of the ssh
  # ones, so one measure/render path serves both - its key has no tag field, so
  # it can't collide with a real group's.
  _hi_local_hostname local_hostname
  if localhostname_color=$(_hi_override_color hostname LOCALHOSTNAME 2>/dev/null); then
    localhostname_source=local:hostname
  else
    _hi_resolve_color hostname "$local_hostname" '' localhostname_color
    localhostname_source=$(_hi_color_source hostname "$local_hostname")
  fi
  group_order+=("$localhostname_source"$'\x1f'"$localhostname_color") group_source+=("$localhostname_source") group_color+=("$localhostname_color") group_tag+=("") group_hosts+=("$local_hostname")

  # Each subnet-style pin as its own example row, seeded with the glob itself
  # as the "host": the glob matches itself through _hi_ssh_pattern_hit, so
  # resolving it yields the pin's color, and a real ssh host the pin covers
  # joins this same group through the key below.
  local pat
  while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    _hi_resolve_color hostname "$pat" '' color_name
    group_order+=("pattern:$pat"$'\x1f'"$color_name"$'\x1f') group_source+=("pattern:$pat") group_color+=("$color_name") group_tag+=("") group_hosts+=("$pat")
  done < <(_hi_pattern_pins)

  # group hosts that share a type+source AND the actual resolved color, so
  # only hosts that would render identically collapse into one row
  if [[ -f "$_HI_SSH_CONFIG" ]]; then
    while IFS=$'\t' read -r name _; do
      # the tag first, in this shell, so its memo spares the next two a walk
      _hi_ssh_host_tag "$name" >/dev/null 2>&1 || :
      tag="$_HI_TAG_VALUE"
      source=$(_hi_color_source hostname "$name")
      _hi_resolve_color hostname "$name" '' color_name
      # tag is part of the key (not just source/color) since it changes which
      # users get colored via usertag, even when the hostname cell looks identical
      key="$source"$'\x1f'"$color_name"$'\x1f'"$tag"
      if gidx="$(_hi_group_index "$key")"; then
        group_hosts[gidx]="${group_hosts[gidx]} $name"
      else
        group_order+=("$key") group_source+=("$source") group_color+=("$color_name") group_tag+=("$tag") group_hosts+=("$name")
      fi
    done < <(sh "$_HI_TARGETS" ssh)
  fi

  local w_item=24 w_color=5 w_source=6 w_preview=7
  _hi_widen w_color "${_HI_COLOR_NAMES[@]}"
  _hi_widen w_item "$local_hostname"

  for gidx in "${!group_order[@]}"; do
    _hi_widen w_source "${group_source[gidx]}"
    _hi_widen w_color "${group_color[gidx]}"
    read -ra group_names <<<"${group_hosts[gidx]}"
    group_pw[gidx]="$(_hi_group_preview_width "${group_names[@]}")"
    _hi_widen_to w_preview "${group_pw[gidx]}"
    # the wrap below can only break *between* names, so a name wider than the
    # column has nowhere to go - widen to it instead of overflowing the border.
    # A wrapped line keeps its trailing ", ", which counts toward the width.
    sep_w=0
    ((${#group_names[@]} > 1)) && sep_w=2
    for name in "${group_names[@]}"; do
      _hi_widen_to w_item $((${#name} + sep_w))
    done
  done

  _hi_hbar top "$w_item" "$w_color" "$w_source" "$w_preview"
  _hi_head_row "$w_item" HOST "$w_color" COLOR "$w_source" SOURCE "$w_preview" PREVIEW
  _hi_hbar mid "$w_item" "$w_color" "$w_source" "$w_preview"

  for gidx in "${!group_order[@]}"; do
    source="${group_source[gidx]}"
    color_name="${group_color[gidx]}"
    _hi_color_escape "$color_name" name_escape
    read -ra group_names <<<"${group_hosts[gidx]}"

    # wrap the name list within the ITEM column instead of overflowing it
    item_lines=()
    cur_line=""
    for idx in "${!group_names[@]}"; do
      name="${group_names[idx]}"
      sep=""
      ((idx < ${#group_names[@]} - 1)) && sep=", "
      candidate="${cur_line}${name}${sep}"
      if ((${#cur_line} > 0 && ${#candidate} > w_item)); then
        item_lines+=("$cur_line")
        cur_line="${name}${sep}"
      else
        cur_line="$candidate"
      fi
    done
    [[ -n "$cur_line" ]] && item_lines+=("$cur_line")

    # every preview line in this group has identical plain-text width (users
    # are right-padded to user_width) so one pad amount covers the whole group
    pw="${group_pw[gidx]}"

    # a usertag's example row only under a host carrying its tag: elsewhere it
    # would be the hash of the tag's own name, which reads as the tag not
    # applying
    group_users=()
    for user in ${preview_users[@]+"${preview_users[@]}"}; do
      case "$tag_rows" in *" $user "*) [ "$user" = "${group_tag[gidx]}" ] || continue ;; esac
      group_users+=("$user")
    done
    total_lines=${#item_lines[@]}
    ((${#group_users[@]} > total_lines)) && total_lines=${#group_users[@]}

    for ((li = 0; li < total_lines; li++)); do
      if ((li < ${#item_lines[@]})); then
        itemtext="${item_lines[li]}"
        _hi_cell "$w_item" "$name_escape" "$itemtext"
      else
        _hi_cell "$w_item" "" ""
      fi

      if ((li == 0)); then
        _hi_cell "$w_color" "$name_escape" "$color_name"
        _hi_cell "$w_source" "$name_escape" "$source"
      else
        _hi_cell "$w_color" "" ""
        _hi_cell "$w_source" "" ""
      fi

      if ((li < ${#group_users[@]})); then
        user="${group_users[li]}"
        _hi_user_color_memo "$user" "${group_tag[gidx]}" user_color user_escape
        # pad after the hostname so the next column lands at the same spot in
        # every user row beneath it, regardless of that user's name length;
        # depends only on $user, so once per row rather than once per column
        printf -v pad '%*s' $((user_width - ${#user})) ''
        previewtext=""
        for idx2 in "${!group_names[@]}"; do
          ((idx2 > 0)) && previewtext+='  '
          # mirrors HI_PS1 in common/bash.sh - the "@" is yellow, same as a
          # live ssh session, since that's what connecting to one of these
          # hosts is
          previewtext+="${user_escape}${user}${NC}${YELLOW}@${NC}${name_escape}${group_names[idx2]}${pad}${NC}"
        done
        _hi_cell_raw "$w_preview" "$pw" "$previewtext"
      else
        _hi_cell "$w_preview" "" ""
      fi
      _hi_row_end
    done

    _hi_hbar bottom "$w_item" "$w_color" "$w_source" "$w_preview"
  done

  [[ -f "$_HI_SSH_CONFIG" ]] || _hi_cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
}

#
# packages
#

# Filled by _hi_collect_examples, read by the table: per-group names, state,
# tier, example rows and their printed widths, plus the totals under the
# table. Indexed by group, in file order, index 0 being the rows above the
# first `[group]` line (a plain indexed array - bash 3.2 has no associative
# ones), and global rather than local because the collector cannot return
# them all.
_HI_PG_NAME=() _HI_PG_ON=() _HI_PG_TIER=() _HI_PG_ROWS=()
_HI_EX_OK=() _HI_EX_OK_W=() _HI_EX_NO=() _HI_EX_NO_W=()
_HI_PKG_LISTED=0 _HI_PKG_SHOWN=0 _HI_PKG_SILENT=0 _HI_PKG_OFF=0

# Run the real check over every row of the real packages file, groups that
# are off included, and keep the first installed and the first missing (or
# warned) row per group. check_line appends what it would print to `visible`
# (bash's dynamic scoping - full_check calls it exactly this way) and appends
# nothing for a `-` row that is absent or a `+` row that is installed, which
# is the point: those rows show nothing.
function _hi_collect_examples() {
  local line entry rank width rendered gi=0 on=1 tier=1
  local -a visible
  _HI_PG_NAME[0]="(no group)" _HI_PG_ON[0]=1 _HI_PG_TIER[0]=1 _HI_PG_ROWS[0]=0

  while IFS=$' ' read -r line; do
    # the header's own filter, character for character
    case "$line" in
    '' | *'#'*) continue ;;
    '['*']')
      line="${line#[}"
      line="${line%]}"
      gi=$((gi + 1))
      on=0
      _hi_group_on "$line" && on=1
      _hi_group_tier tier "$line"
      _HI_PG_NAME[gi]="$line" _HI_PG_ON[gi]=$on _HI_PG_TIER[gi]=$tier _HI_PG_ROWS[gi]=0
      continue
      ;;
    esac
    _HI_PKG_LISTED=$((_HI_PKG_LISTED + 1))
    _HI_PG_ROWS[gi]=$((_HI_PG_ROWS[gi] + 1))
    visible=()
    check_line visible "$line" "$tier"
    if ((${#visible[@]} == 0)); then
      _HI_PKG_SILENT=$((_HI_PKG_SILENT + 1))
      continue
    fi
    if ((on)); then
      _HI_PKG_SHOWN=$((_HI_PKG_SHOWN + 1))
    else
      _HI_PKG_OFF=$((_HI_PKG_OFF + 1))
    fi
    IFS=$'\x1f' read -r rank width rendered <<<"${visible[0]}"
    # the mark is the last thing check_line renders, and $RED or $YELLOW
    # prefixes only that one - a bare "x" (the ASCII glyph) also occurs
    # inside package names
    if [[ "$rendered" == *"$RED$_HI_MARK_NO" || "$rendered" == *"$YELLOW$_HI_MARK_WARN$NC" ]]; then
      [[ -n "${_HI_EX_NO[gi]:-}" ]] || {
        _HI_EX_NO[gi]="$rendered"
        _HI_EX_NO_W[gi]="$width"
      }
    else
      [[ -n "${_HI_EX_OK[gi]:-}" ]] || {
        _HI_EX_OK[gi]="$rendered"
        _HI_EX_OK_W[gi]="$width"
      }
    fi
  done <"$_HI_PACKAGES"
}

# _hi_example_cell <group index> - the installed example then the missing
# one, laid out the way full_check lays a row out ("|<rendered> " each), and
# the printed width that comes to. Two values, so it prints them
# tab-separated rather than writing to yet another global.
function _hi_example_cell() {
  local g="$1" text="" width=0
  if [[ -n "${_HI_EX_OK[g]:-}" ]]; then
    text+="$NC|${_HI_EX_OK[g]} "
    width=$((width + _HI_EX_OK_W[g]))
  fi
  if [[ -n "${_HI_EX_NO[g]:-}" ]]; then
    text+="$NC|${_HI_EX_NO[g]} "
    width=$((width + _HI_EX_NO_W[g]))
  fi
  [[ -n "$text" ]] || {
    text="-" width=1
  }
  printf '%s\t%s' "$text" "$width"
}

# the legend: one row per group, in file order, each painted in the colors
# its tier actually uses
function _hi_print_groups_table() {
  local g t state example ex_width
  local -a c_example=() c_ex_width=()
  local w_group=5 w_state=5 w_yes=9 w_no=7 w_example=7

  # The measure pass keeps what it worked out, indexed by group, so the render
  # pass below reads it instead of calling _hi_example_cell a second time.
  for g in "${!_HI_PG_NAME[@]}"; do
    ((g > 0 || _HI_PG_ROWS[0] > 0)) || continue
    t="${_HI_PG_TIER[g]}"
    _hi_widen w_group "${_HI_PG_NAME[g]}"
    _hi_widen w_yes "${_HI_YES_NAMES[t]:-plain}"
    _hi_widen w_no "${_HI_NO_NAMES[t]:-plain}"
    IFS=$'\t' read -r example ex_width <<<"$(_hi_example_cell "$g")"
    c_example[g]="$example"
    c_ex_width[g]="$ex_width"
    _hi_widen_to w_example "$ex_width"
  done

  _hi_hbar top "$w_group" "$w_state" "$w_yes" "$w_no" "$w_example"
  _hi_head_row "$w_group" GROUP "$w_state" STATE "$w_yes" INSTALLED \
    "$w_no" MISSING "$w_example" EXAMPLE
  _hi_hbar mid "$w_group" "$w_state" "$w_yes" "$w_no" "$w_example"

  for g in "${!_HI_PG_NAME[@]}"; do
    ((g > 0 || _HI_PG_ROWS[0] > 0)) || continue
    t="${_HI_PG_TIER[g]}"
    state=off
    ((_HI_PG_ON[g])) && state=on
    _hi_cell "$w_group" "" "${_HI_PG_NAME[g]}"
    _hi_cell "$w_state" "" "$state"
    _hi_cell "$w_yes" "${_HI_YES[t]:-}" "${_HI_YES_NAMES[t]:-plain}"
    _hi_cell "$w_no" "${_HI_NO[t]:-}" "${_HI_NO_NAMES[t]:-plain}"
    _hi_cell_raw "$w_example" "${c_ex_width[g]}" "${c_example[g]}"
    _hi_row_end
  done

  _hi_hbar bottom "$w_group" "$w_state" "$w_yes" "$w_no" "$w_example"
  _hi_cecho " | $_HI_PKG_LISTED listed, $_HI_PKG_SHOWN shown, $_HI_PKG_SILENT silent by their marker"
  if ((_HI_PKG_OFF > 0)); then
    _hi_cecho " | $_HI_PKG_OFF more in groups \$_HI_PACKAGES_GROUPS leaves off (${_HI_PACKAGES_GROUPS:-$_HI_PACKAGES_GROUPS_DEFAULT} run)" "$YELLOW"
  fi
}

# the other half of a rendered row: which mark it ends in, and what each one
# is saying. The glyphs come from core.sh's _hi_choose_glyphs, so this table
# follows a terminal onto the ASCII set the same way the header does.
# Column 1 is never measured: a mark is one visible column by construction,
# and measuring it against an escape sequence would be wrong.
function _hi_print_marks_table() {
  local w2=5 entry c1 c2
  local -a rows=("$GREEN$_HI_MARK_OK|installed, under the first name the row lists"
    "$YELLOW$_HI_MARK_ALT|installed, but via one of the alternatives after it"
    "$RED$_HI_MARK_NO|not installed - no name on the row resolved"
    "$YELLOW$_HI_MARK_WARN|installed, on a - row: a package you don't want")
  for entry in "${rows[@]}"; do _hi_widen w2 "${entry#*|}"; done
  _hi_hbar top 4 "$w2"
  _hi_head_row 4 MARK "$w2" MEANS
  _hi_hbar mid 4 "$w2"
  for entry in "${rows[@]}"; do
    IFS='|' read -r c1 c2 <<<"$entry"
    _hi_cell_raw 4 1 "$c1"
    _hi_cell "$w2" "" "$c2"
    _hi_row_end
  done
  _hi_hbar bottom 4 "$w2"
  # the third axis, a row's leading marker: whether the row speaks at all
  _hi_cecho " | a leading - (unwanted) speaks only when installed, + (required) only"
  _hi_cecho " | when missing; no marker speaks both ways"
}

# same hatch as scripts/install.sh: sourcing this file defines its functions
# without rendering anything, which is what tests/scripts/preview_test.sh needs
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# Strict mode for the real run only, from here down: core.sh (sourced above)
# ends with `set +euo pipefail`, so a `set` line placed before it is silently
# undone, and a script-wide `set -euo pipefail` above the return guard would
# leak into every test that sources this file for its functions instead of
# running it. GLOSSARY: HI.15
set -euo pipefail

case "$_hi_subject" in
colors)
  _hi_print_scheme_line
  printf '\n'
  _hi_print_users_table
  printf '\n'
  _hi_print_hosts_table
  ;;
packages)
  # Everything below reads it, so there is no half-preview worth printing
  if [ ! -f "$_HI_PACKAGES" ]; then
    _hi_cecho "No packages file at $_HI_PACKAGES - the header has nothing to check" "$RED"
    exit 1
  fi
  _hi_cecho " | reading $_HI_PACKAGES"
  _hi_print_ramp_line
  _hi_print_scheme_line
  printf '\n'
  _hi_collect_examples
  _hi_print_groups_table
  printf '\n'
  _hi_print_marks_table
  printf '\n'
  _hi_h2 "as the header will print it"
  full_check
  ;;
header)
  # the wizard's preview says the same in its box: a silent exit here read
  # as "the header is empty", not "the header is off"
  if [ "${_HI_DISABLE_HEADER:-0}" = 1 ]; then
    _hi_cecho " header off (_HI_DISABLE_HEADER=1${_HI_DISABLE_LOCAL:+, through _HI_DISABLE_LOCAL=$_HI_DISABLE_LOCAL on this machine}) - nothing to draw" "$YELLOW"
  else
    hi_header Preview
  fi
  ;;
esac
