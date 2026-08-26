#!/usr/bin/env bash
# preview what every ssh host & every known user resolve to, rendered in that
# actual color, plus why (override/hosttag/default) - handy when tuning
# settings/colors. Run via `hi --color-preview`.
set -euo pipefail

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
unset _hi_d
# shellcheck source=./table.sh
source "$_HI_ROOT/scripts/table.sh"

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Usage: color_preview.sh

Prints two tables - every known user, and every ssh host that resolves to
something other than the default - rendered in the color they'd actually
appear in, alongside *why* they resolve that way (an exact override, an
ssh-config tag, or the hash of the name).

Takes no arguments. Reads:
  settings/colors        the type,name,color pins (its own comments explain them)
  ~/.ssh/config      hosts, and the "# Tags: ..." comments above them

Hosts with no override and no usable tag are left out: they'd render exactly
as a bare `hi` does, so there is nothing to preview.
EOF
  exit 0
  ;;
esac

function _hi_color_source() {
  local type="$1" name="$2" tag
  if _hi_override_color "$type" "$name" >/dev/null 2>&1; then
    printf 'override:%s' "$type"
    return
  fi
  if [[ "$type" = hostname ]] && tag=$(_hi_ssh_host_tag "$name") && _hi_override_color hosttag "$tag" >/dev/null 2>&1; then
    printf 'tag:%s' "$tag"
    return
  fi
  printf 'default'
}

# both read settings/colors through common/core.sh's _hi_colors_names
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

# same hatch as scripts/install.sh: sourcing this
# file defines its functions without rendering anything, which is what
# tests/scripts/color_preview_test.sh needs
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_hi_print_users_table
printf '\n'
_hi_print_hosts_table
