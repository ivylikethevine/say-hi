#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# `hi --preview <subject>`: what a setting resolves to, rendered the way a
# connect will render it, plus why.
#
#   colors     every ssh host and every known user in the color it lands in
#              (override/hosttag/pattern/default) - for tuning settings/colors
#   packages   the header's packages check: what each priority means, the
#              colors it paints an installed and a missing package, a real
#              example of each from your own packages file, then the check
#   header     the connect header itself
#
# One script for the three subjects: they share the boxed table (table.sh),
# the palette they paint with, and the scheme line above every table.
set -euo pipefail

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
  packages   the header's packages check: legend, marks, modes, then the check
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
    echo "${_HI_ARGV0:-preview.sh}: one of colors, packages or header is required" >&2
    _hi_preview_usage >&2
    exit 1
  fi
  ;;
*)
  echo "${_HI_ARGV0:-preview.sh}: unknown subject '$_hi_subject' - one of colors, packages or header" >&2
  _hi_preview_usage >&2
  exit 1
  ;;
esac

case "${1:-}" in
-h | --help)
  case "$_hi_subject" in
  colors)
    cat <<EOF
Usage: $_hi_argv0

Prints two tables - every known user, and every ssh host that resolves to
something other than the default - rendered in the color they'd actually
appear in, alongside *why* they resolve that way (an exact override, an
ssh-config tag, or the hash of the name).

Takes no arguments. Reads:
  settings/colors        the type,name,color pins (its own comments explain them)
  ~/.ssh/config      hosts, and the "# Tags: ..." comments above them

Hosts with no override and no usable tag are left out: they'd render exactly
as a bare \`hi\` does, so there is nothing to preview.
EOF
    ;;
  packages)
    cat <<EOF
Usage: $_hi_argv0

Prints the legend for the header's packages check - every priority, the colors
it renders installed and missing packages in, and one real example of each
taken from your own packages file - then the marks, then the check itself
exactly as a connect will print it.

Takes no arguments. Reads:
  settings/packages      the [-|+]package:priority lines (the overlay's
                     ~/.config/say-hi/packages wins when present)
  common/header.sh   the priority meanings and their two color tables
  \$_HI_PACKAGES_PALETTE   which of the named color tables is active (cool, the
                     default; warm; mono) - printed above the legend

A line's leading mode character decides which states speak at all: \`-\` only
when the whole line is missing, \`+\` only when something on it is installed,
no flag both ways - the MODE table below the marks spells them out. An
EXAMPLE cell reading "below floor" means \$_HI_PACKAGES_MIN_PRIORITY is above
that rank, so the header prints nothing for it whatever its colors say. That
floor defaults to 2, so priorities 0-1 read "below floor" until you set one
of your own; 4 turns the check off entirely. A priority with no example at
all has no package of its own in your file.
EOF
    ;;
  header)
    cat <<EOF
Usage: $_hi_argv0

Prints the connect header exactly as this machine would draw it, under the
settings.sh in force - the way to judge a header order, width or palette
before saving it.

Takes no arguments.
EOF
    ;;
  esac
  exit 0
  ;;
'') ;;
*)
  echo "$_hi_argv0: takes no arguments (got: $*)" >&2
  echo "Usage: $_hi_argv0" >&2
  exit 1
  ;;
esac

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

# _hi_pattern_for <name> - the subnet-style pin (hostname row whose name field
# is a glob) that would color <name>, printed as the glob itself; core.sh's
# _hi_colors_pattern answers with the color, but the source cell wants the why
function _hi_pattern_for() {
  local cur_type cur_name _
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = hostname ]] || continue
    case "$cur_name" in
    *[\*\?]*) _hi_ssh_pattern_hit "$1" "$cur_name" || continue ;;
    *) continue ;;
    esac
    printf '%s' "$cur_name"
    return 0
  done <"$_HI_COLORS"
  return 1
}

# every subnet-style pin, deduped in file order - each gets an example row in
# the hosts table, since a globbed name never appears in targets.sh's list
function _hi_pattern_pins() {
  local cur_type cur_name _
  [[ -f "$_HI_COLORS" ]] || return 0
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = hostname ]] || continue
    case "$cur_name" in
    *[\*\?]*) printf '%s\n' "$cur_name" ;;
    esac
  done <"$_HI_COLORS" | awk '!seen[$0]++'
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
  printf 'default'
}

# _hi_colors_names <type> [skip-name] - deduped pinned names of that type.
# Not in core.sh: the colors preview is its only caller, and core.sh ships in
# the ssh payload under a size budget nothing a target runs should spend.
function _hi_colors_names() {
  local cur_type cur_name
  [[ -f "$_HI_COLORS" ]] || return 0
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = "$1" && "$cur_name" != "${2:-}" ]] || continue
    printf '%s\n' "$cur_name"
  done <"$_HI_COLORS" | awk '!seen[$0]++'
}

# both read settings/colors through the _hi_colors_names above
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
  local i=0 existing
  for existing in ${group_order[@]+"${group_order[@]}"}; do
    [[ "$existing" = "$1" ]] && {
      printf '%s' "$i"
      return 0
    }
    i=$((i + 1))
  done
  return 1
}

# users table: every known real user with a non-default color, plus LOCALUSER
# and every usertag override as its own "example" row
function _hi_print_users_table() {
  local user tag source color_name name_escape uidx=0
  local users=() usertags=() u_source=()
  local w_item=9 w_color=5 w_source=6
  local localuser_color=""

  _hi_read_lines users < <(_hi_known_users)
  _hi_read_lines usertags < <(_hi_known_usertags)

  _hi_widen w_color "${_HI_COLOR_NAMES[@]}"
  # ${a[@]+"${a[@]}"} throughout this file, not a plain "${a[@]}": on bash 3.2
  # (macOS) expanding an *empty* array under `set -u` is a fatal "unbound
  # variable", and a colors file with no usertag pins - or an ssh config with no
  # interesting hosts - leaves exactly that. The *index* form "${!a[@]}" needs no
  # such guard (it is already empty-safe), and must not be given one: bash 3.2
  # reads ${!a[@]+...} as expanding to nothing whatever the array holds, and
  # bash 5 reads it as an indirect reference and errors outright.
  _hi_widen w_item "${users[@]}" LOCALUSER ${usertags[@]+"${usertags[@]}"}
  # _hi_color_source re-reads settings/colors end to end and walks ~/.ssh/config,
  # so the render loop below reads what this one worked out rather than asking
  # a second time for every user.
  for user in "${users[@]}"; do
    u_source[uidx]="$(_hi_color_source username "$user")"
    _hi_widen w_source "${u_source[uidx]}"
    uidx=$((uidx + 1))
  done
  _hi_widen w_source "local:username"
  for tag in ${usertags[@]+"${usertags[@]}"}; do
    _hi_widen w_source "usertag:$tag"
  done

  _hi_hbar "$w_item" "$w_color" "$w_source"
  printf '| %-*s | %-*s | %-*s |\n' "$w_item" "USER" "$w_color" "COLOR" "$w_source" "SOURCE"
  _hi_hbar "$w_item" "$w_color" "$w_source"

  uidx=0
  for user in "${users[@]}"; do
    source="${u_source[uidx]}"
    uidx=$((uidx + 1))
    [[ "$source" = default ]] && continue
    color_name=$(_hi_resolve_color username "$user")
    name_escape=$(_hi_color_escape "$color_name")
    _hi_cell "$w_item" "$name_escape" "$user"
    _hi_cell "$w_color" "$name_escape" "$color_name"
    _hi_cell "$w_source" "$name_escape" "$source"
    printf '|\n'
  done

  if localuser_color=$(_hi_override_color username LOCALUSER 2>/dev/null); then
    name_escape=$(_hi_color_escape "$localuser_color")
    _hi_cell "$w_item" "$name_escape" "LOCALUSER"
    _hi_cell "$w_color" "$name_escape" "$localuser_color"
    _hi_cell "$w_source" "$name_escape" "local:username"
    printf '|\n'
  fi

  for tag in ${usertags[@]+"${usertags[@]}"}; do
    color_name=$(_hi_override_color usertag "$tag") || continue
    name_escape=$(_hi_color_escape "$color_name")
    _hi_cell "$w_item" "$name_escape" "$tag"
    _hi_cell "$w_color" "$name_escape" "$color_name"
    _hi_cell "$w_source" "$name_escape" "usertag:$tag"
    printf '|\n'
  done

  _hi_hbar "$w_item" "$w_color" "$w_source"
}

# hosts table: a LOCALHOSTNAME row (the current machine) followed by every
# ssh-config host grouped by the color it'd actually render with. PREVIEW
# combines every real known user plus the "example" users from the users
# table (LOCALUSER, each usertag) against that host's name(s)
function _hi_print_hosts_table() {
  local name color_name source user user_color user_escape name_escape key
  local cur_line sep sep_w candidate idx idx2 li total_lines itemtext previewtext
  local tag has_usertag
  local user_width=0 pw pad_preview local_hostname
  local preview_users=() group_order=() group_names=() item_lines=()
  # Five *parallel* indexed arrays sharing one index, rather than associative
  # arrays keyed by $key: `local -A` is bash 4 and macOS ships bash 3.2, where
  # the declaration alone is a fatal "invalid option".
  # group_order holds the keys, so it doubles as the lookup table below.
  local group_hosts=() group_source=() group_color=() group_tag=() group_pw=()
  local gidx localhostname_color=""

  _hi_read_lines preview_users < <(_hi_preview_users)
  _hi_widen user_width ${preview_users[@]+"${preview_users[@]}"}

  # The current machine renders as its own single-host group ahead of the ssh
  # ones, so one measure/render path serves both - its key can't collide with
  # a real group's (no _hi_color_source result reads local:hostname).
  if localhostname_color=$(_hi_override_color hostname LOCALHOSTNAME 2>/dev/null); then
    local_hostname=$(_hi_local_hostname)
    group_order+=("local:hostname"$'\x1f'"$localhostname_color")
    group_source+=("local:hostname")
    group_color+=("$localhostname_color")
    group_tag+=("")
    group_hosts+=("$local_hostname")
  fi

  # Each subnet-style pin as its own example row, seeded with the glob itself
  # as the "host": the glob matches itself through _hi_ssh_pattern_hit, so
  # resolving it yields the pin's color, and a real ssh host the pin covers
  # joins this same group through the key below.
  local pat
  while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    color_name=$(_hi_resolve_color hostname "$pat")
    group_order+=("pattern:$pat"$'\x1f'"$color_name"$'\x1f')
    group_source+=("pattern:$pat")
    group_color+=("$color_name")
    group_tag+=("")
    group_hosts+=("$pat")
  done < <(_hi_pattern_pins)

  # group hosts that share a type+source AND the actual resolved color, so
  # only hosts that would render identically collapse into one row
  if [[ -f "$_HI_SSH_CONFIG" ]]; then
    while IFS=$'\t' read -r name _; do
      source=$(_hi_color_source hostname "$name")
      tag=$(_hi_ssh_host_tag "$name" 2>/dev/null) || tag=""
      has_usertag=false
      [[ -n "$tag" ]] && _hi_override_color usertag "$tag" >/dev/null 2>&1 && has_usertag=true
      # skip hosts that wouldn't render any differently from a bare `hi`
      [[ "$source" = default && "$has_usertag" = false ]] && continue
      color_name=$(_hi_resolve_color hostname "$name")
      # tag is part of the key (not just source/color) since it changes which
      # users get colored via usertag, even when the hostname cell looks identical
      key="$source"$'\x1f'"$color_name"$'\x1f'"$tag"
      if gidx="$(_hi_group_index "$key")"; then
        group_hosts[gidx]="${group_hosts[gidx]} $name"
      else
        group_order+=("$key")
        group_source+=("$source")
        group_color+=("$color_name")
        group_tag+=("$tag")
        group_hosts+=("$name")
      fi
    done < <(sh "$_HI_TARGETS" ssh)
  fi

  local w_item=24 w_color=5 w_source=6 w_preview=7
  _hi_widen w_color "${_HI_COLOR_NAMES[@]}"
  [[ -n "$localhostname_color" ]] && _hi_widen w_item "$local_hostname"

  for gidx in "${!group_order[@]}"; do
    _hi_widen w_source "${group_source[gidx]}"
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

  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  printf '| %-*s | %-*s | %-*s | %-*s |\n' \
    "$w_item" "HOST" "$w_color" "COLOR" "$w_source" "SOURCE" "$w_preview" "PREVIEW"
  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"

  for gidx in "${!group_order[@]}"; do
    source="${group_source[gidx]}"
    color_name="${group_color[gidx]}"
    name_escape=$(_hi_color_escape "$color_name")
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
    pad_preview=$((w_preview - pw))

    total_lines=${#item_lines[@]}
    ((${#preview_users[@]} > total_lines)) && total_lines=${#preview_users[@]}

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

      if ((li < ${#preview_users[@]})); then
        user="${preview_users[li]}"
        user_color=$(_hi_resolve_color username "$user" "${group_tag[gidx]}")
        user_escape=$(_hi_color_escape "$user_color")
        previewtext=""
        for idx2 in "${!group_names[@]}"; do
          ((idx2 > 0)) && previewtext+='  '
          # pad after the hostname so the next column lands at the same spot
          # in every user row beneath it, regardless of that user's name
          # length; mirrors HI_PS1 in common/bash.sh - the "@" is yellow,
          # same as a live ssh session, since that's what connecting to one
          # of these hosts is
          previewtext+="${user_escape}${user}${NC}${YELLOW}@${NC}${name_escape}${group_names[idx2]}$(printf '%*s' $((user_width - ${#user})) '')${NC}"
        done
        printf '| %b%*s |\n' "$previewtext" "$pad_preview" ""
      else
        printf '| %*s |\n' "$w_preview" ""
      fi
    done

    _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  done

  [[ -f "$_HI_SSH_CONFIG" ]] || _hi_cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
}

#
# packages
#

# _hi_priority_meanings - "<priority>\t<meaning>" per priority, read from the
# comment block header.sh keeps directly above _HI_YES rather than copied here:
# that block is the only description of the priorities there is, and a copy
# would be a second thing to keep true. Only the run of lines immediately
# preceding _HI_YES counts, so an unrelated "# 2 ..." elsewhere can't join in.
# The parenthetical examples are dropped - the EXAMPLE column below shows real
# ones, from the file the header will actually read.
function _hi_priority_meanings() {
  awk '
    /^_HI_YES=/ {
      for (i = 1; i <= n; i++) print buf[i]
      exit
    }
    /^# [0-9]+ [^ ]/ {
      line = $0
      p = $2
      sub(/^# [0-9]+ +/, "", line)
      sub(/ *\(.*/, "", line)
      buf[++n] = p "\t" line
      next
    }
    { n = 0 }
  ' "$_HI_HEADER"
}

# _hi_color_name_of <escape> - name the palette entry an escape came from, so
# the table can print "brgreen" beside a cell painted with it. _HI_YES/_HI_NO
# hold escapes, not names, and this is the only way back without a second copy
# of the mapping. Both sides go through printf '%b' because core.sh's palette
# variables hold a literal "\e[..." while _hi_color_escape emits a real ESC,
# and both are cut to their 16-color half (_hi_sgr_base): under a 24-word
# scheme the check's escapes carry the second bank's hex, and the name is
# the half they share. Anything outside the palette - $NC, and every color
# under $NO_COLOR - is "plain", which is exactly how it will render.
# The escapes for _HI_COLOR_NAMES, in the same order, resolved once. Built
# here rather than inside _hi_color_name_of, which the legend calls four
# times a row - resolving all twelve names on every one of those calls would
# fork _hi_color_escape forty-eight times instead of twelve.
_HI_COLOR_ESCAPES=()
for _hi_cn in "${_HI_COLOR_NAMES[@]}"; do
  _HI_COLOR_ESCAPES+=("$(_hi_color_escape "$_hi_cn")")
done
unset _hi_cn

function _hi_color_name_of() {
  local want have i=0
  _hi_sgr_base want "$(printf '%b' "$1")"
  [[ -n "$want" ]] || {
    printf 'plain'
    return
  }
  while ((i < ${#_HI_COLOR_NAMES[@]})); do
    _hi_sgr_base have "${_HI_COLOR_ESCAPES[i]}"
    [[ "$want" = "$have" ]] && {
      printf '%s' "${_HI_COLOR_NAMES[i]}"
      return
    }
    i=$((i + 1))
  done
  printf 'plain'
}

# Filled by _hi_collect_examples, read by the table: per-priority example rows
# and their printed widths, plus the two totals under the table. Indexed by
# priority (a plain indexed array - bash 3.2 has no associative ones), and
# global rather than local because the collector cannot return six things.
_HI_EX_OK=() _HI_EX_OK_W=() _HI_EX_NO=() _HI_EX_NO_W=()
_HI_PKG_LISTED=0 _HI_PKG_SHOWN=0 _HI_PKG_FLOORED=0
# read once, here, rather than at each use: full_check reads the same setting
# and this preview has to answer for the floor the header will actually apply
_HI_PKG_MIN="${_HI_PACKAGES_MIN_PRIORITY:-2}"

# Run the real check over the real packages file and keep the first installed
# and first missing row at each priority. check_line appends what it would print
# to `visible` (bash's dynamic scoping - full_check calls it exactly this way)
# and drops mode-suppressed rows on the floor, which is the point: a `-` line
# that is installed, or a `+` line that is missing, has no example to show
# because it shows nothing.
function _hi_collect_examples() {
  local line entry priority width rendered
  local -a visible=()

  while IFS=$' ' read -r line; do
    # the header's own filter, character for character
    [[ "$line" == *#* || -z "$line" ]] && continue
    _HI_PKG_LISTED=$((_HI_PKG_LISTED + 1))
    check_line "$line"
  done <"$_HI_PACKAGES"
  _HI_PKG_SHOWN=${#visible[@]}

  for entry in ${visible[@]+"${visible[@]}"}; do
    IFS=$'\x1f' read -r priority width rendered <<<"$entry"
    # counted, not skipped: the example is still collected so the table can show
    # what this rank *would* print, with the cell saying the floor is why it
    # does not. full_check applies the same floor for real.
    ((priority >= _HI_PKG_MIN)) || _HI_PKG_FLOORED=$((_HI_PKG_FLOORED + 1))
    # the mark is the last thing check_line renders, and $RED prefixes only
    # that one - a bare "x" (the ASCII glyph) also occurs inside package names
    if [[ "$rendered" == *"$RED$_HI_MARK_NO" ]]; then
      [[ -n "${_HI_EX_NO[priority]:-}" ]] || {
        _HI_EX_NO[priority]="$rendered"
        _HI_EX_NO_W[priority]="$width"
      }
    else
      [[ -n "${_HI_EX_OK[priority]:-}" ]] || {
        _HI_EX_OK[priority]="$rendered"
        _HI_EX_OK_W[priority]="$width"
      }
    fi
  done
}

# _hi_example_cell <priority> - the installed example then the missing one, laid
# out the way full_check lays a row out ("|<rendered> " each), and the printed
# width that comes to. Two values, so it prints them tab-separated rather than
# writing to yet another global.
function _hi_example_cell() {
  local p="$1" text="" width=0
  # the floor's own "hidden": a rank below it renders nothing in the header
  # whatever its colors say, so the cell names the reason rather than showing an
  # example that will never appear
  if ((p < _HI_PKG_MIN)); then
    printf '%s\t%s' "below floor" 11
    return 0
  fi
  if [[ -n "${_HI_EX_OK[p]:-}" ]]; then
    text+="$NC|${_HI_EX_OK[p]} "
    width=$((width + _HI_EX_OK_W[p]))
  fi
  if [[ -n "${_HI_EX_NO[p]:-}" ]]; then
    text+="$NC|${_HI_EX_NO[p]} "
    width=$((width + _HI_EX_NO_W[p]))
  fi
  [[ -n "$text" ]] || {
    text="-" width=1
  }
  printf '%s\t%s' "$text" "$width"
}

# the legend: one row per priority, highest first (the order full_check sorts
# its output into), each painted in the colors that priority actually uses
function _hi_print_priorities_table() {
  local entry p meaning yes_escape no_escape yes_name no_name example ex_width
  local i=0
  local -a rows=() c_yes=() c_no=() c_example=() c_ex_width=()
  local w_prio=8 w_meaning=7 w_yes=9 w_no=7 w_example=7

  _hi_read_lines rows < <(_hi_priority_meanings | LC_ALL=C sort -k1,1nr)

  # The measure pass keeps what it worked out, indexed by row, so the render
  # pass below reads it instead of calling _hi_color_name_of and
  # _hi_example_cell a second time for every row. Same parallel-array shape as
  # _HI_EX_OK/_HI_EX_OK_W above.
  for entry in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r p meaning <<<"$entry"
    _hi_widen w_meaning "$meaning"
    c_yes[i]="$(_hi_color_name_of "${_HI_YES[p]:-}")"
    c_no[i]="$(_hi_color_name_of "${_HI_NO[p]:-}")"
    _hi_widen w_yes "${c_yes[i]}"
    _hi_widen w_no "${c_no[i]}"
    IFS=$'\t' read -r example ex_width <<<"$(_hi_example_cell "$p")"
    c_example[i]="$example"
    c_ex_width[i]="$ex_width"
    _hi_widen_to w_example "$ex_width"
    i=$((i + 1))
  done

  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"
  printf '| %-*s | %-*s | %-*s | %-*s | %-*s |\n' \
    "$w_prio" "PRIORITY" "$w_meaning" "MEANING" "$w_yes" "INSTALLED" \
    "$w_no" "MISSING" "$w_example" "EXAMPLE"
  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"

  i=0
  for entry in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r p meaning <<<"$entry"
    yes_escape="${_HI_YES[p]:-}"
    no_escape="${_HI_NO[p]:-}"
    yes_name="${c_yes[i]}"
    no_name="${c_no[i]}"
    example="${c_example[i]}"
    ex_width="${c_ex_width[i]}"
    i=$((i + 1))

    _hi_cell "$w_prio" "" "$p"
    _hi_cell "$w_meaning" "" "$meaning"
    _hi_cell "$w_yes" "$yes_escape" "$yes_name"
    _hi_cell "$w_no" "$no_escape" "$no_name"
    _hi_cell_raw "$w_example" "$ex_width" "$example"
    printf '|\n'
  done

  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"
  _hi_cecho " | $_HI_PKG_LISTED listed, $((_HI_PKG_SHOWN - _HI_PKG_FLOORED)) shown, $((_HI_PKG_LISTED - _HI_PKG_SHOWN)) hidden by their priority"
  if ((_HI_PKG_MIN > 0)); then
    _hi_cecho " | $_HI_PKG_FLOORED more below \$_HI_PACKAGES_MIN_PRIORITY=$_HI_PKG_MIN, which this legend marks \"below floor\"" "$YELLOW"
  fi
}

# the other half of a rendered row: which of the three marks it ends in, and
# what each one is saying. The glyphs come from core.sh's _hi_choose_glyphs, so
# this table follows a terminal onto the ASCII set the same way the header does.
function _hi_print_marks_table() {
  local w_mark=4 w_means=5
  local -a marks=(
    "$GREEN$_HI_MARK_OK|$_HI_MARK_OK_W|installed, under the first name the line lists"
    "$YELLOW$_HI_MARK_ALT|$_HI_MARK_ALT_W|installed, but via one of the alternatives after it"
    "$RED$_HI_MARK_NO|$_HI_MARK_NO_W|not installed - no name on the line resolved"
  )
  local entry glyph width means

  for entry in "${marks[@]}"; do
    IFS='|' read -r glyph width means <<<"$entry"
    _hi_widen_to w_mark "$width"
    _hi_widen w_means "$means"
  done

  _hi_hbar "$w_mark" "$w_means"
  printf '| %-*s | %-*s |\n' "$w_mark" "MARK" "$w_means" "MEANS"
  _hi_hbar "$w_mark" "$w_means"
  for entry in "${marks[@]}"; do
    IFS='|' read -r glyph width means <<<"$entry"
    _hi_cell_raw "$w_mark" "$width" "$glyph"
    _hi_cell "$w_means" "" "$means"
    printf '|\n'
  done
  _hi_hbar "$w_mark" "$w_means"
}

# the third axis of a line: its leading mode character, which decides whether
# the row speaks at all. No glyph negotiation here - `-` and `+` are the
# literal characters the packages file uses.
function _hi_print_modes_table() {
  local w_mode=4 w_means=5
  local -a modes=(
    "-|speaks only when the whole line is missing"
    "+|speaks only when something on the line is installed"
    "none|speaks both ways - the default"
  )
  local entry flag means

  for entry in "${modes[@]}"; do
    IFS='|' read -r flag means <<<"$entry"
    _hi_widen w_mode "$flag"
    _hi_widen w_means "$means"
  done

  _hi_hbar "$w_mode" "$w_means"
  printf '| %-*s | %-*s |\n' "$w_mode" "MODE" "$w_means" "MEANS"
  _hi_hbar "$w_mode" "$w_means"
  for entry in "${modes[@]}"; do
    IFS='|' read -r flag means <<<"$entry"
    _hi_cell "$w_mode" "" "$flag"
    _hi_cell "$w_means" "" "$means"
    printf '|\n'
  done
  _hi_hbar "$w_mode" "$w_means"
}

# same hatch as scripts/install.sh: sourcing this file defines its functions
# without rendering anything, which is what tests/scripts/preview_test.sh needs
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

case "$_hi_subject" in
colors)
  _hi_print_scheme_line
  printf '\n'
  _hi_print_users_table
  printf '\n'
  _hi_print_hosts_table
  ;;
packages)
  # Everything below reads it, so there is no half-preview worth printing -
  # and the bare redirect this saves fails as "No such file", naming a path
  # without saying which of the two it was looking for.
  if [[ ! -f "$_HI_PACKAGES" ]]; then
    _hi_cecho "No packages file at $_HI_PACKAGES - the header has nothing to check" "$RED"
    exit 1
  fi
  _hi_cecho " | reading $_HI_PACKAGES"
  _hi_cecho " | palette: ${_HI_PACKAGES_PALETTE:-cool}"
  _hi_print_scheme_line
  printf '\n'
  _hi_collect_examples
  _hi_print_priorities_table
  printf '\n'
  _hi_print_marks_table
  printf '\n'
  _hi_print_modes_table
  printf '\n'
  _hi_h2 "as the header will print it"
  full_check
  ;;
header)
  hi_header Preview
  ;;
esac
