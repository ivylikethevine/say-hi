#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The settings wizard's live previews: what each question draws above itself
# - the header, the prompt, the package check, the editors, the aliases -
# rendered from the answers pending this run. Sourced by scripts/configure.sh;
# not an entry point of its own.

# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
function show_preview() {
  local out content_w=0 len line top fill_top i indent='   ' room restore=0
  local label="$_HI_BOX_H preview "
  local -a lines lens=()
  out="$("$@" 2>/dev/null)" || true
  [ -n "$out" ] || return 0
  _hi_read_lines lines <<<"$out"
  # the box fits the menu: a narrow one indents it by one, and a line wider
  # than the room left is cut there - its colors dropped, the escapes being
  # what a cut cannot count through
  ((_HI_MENU_W < 60)) && indent=' '
  room=$((_HI_MENU_W - ${#indent} - 4))
  # measured once, kept for the render loop: the strip behind _hi_visible_len
  # is the expensive half of every line
  for i in "${!lines[@]}"; do
    _hi_visible_len len "${lines[i]}"
    if ((len > room)); then
      shopt -q extglob || {
        shopt -s extglob
        restore=1
      }
      line="${lines[i]//$'\e'\[*([0-9;])m/}"
      ((restore)) && shopt -u extglob
      lines[i]="${line:0:room}" len=$room
    fi
    lens+=("$len")
    ((len > content_w)) && content_w=$len
  done
  # the top rule carries a label _hi_hbar has no room for, so only it is
  # spelled out here; the bottom rule and every row are table.sh's own
  # primitives, the same ones every other box in this file draws with
  _hi_repeat fill_top $((content_w + 2 - ${#label})) "$_HI_BOX_H"
  top="$_HI_BOX_TL${label}${fill_top}$_HI_BOX_TR"
  _hi_cecho "$indent$top" "$NC"
  for i in "${!lines[@]}"; do
    printf '%s' "$indent"
    _hi_cell_raw "$content_w" "${lens[i]}" "${lines[i]}"
    _hi_row_end
  done
  printf '%s' "$indent"
  _hi_hbar bottom "$content_w"
}

# The header's cells are memoized per shell (_HI_SI_* by
# _hi_system_info_probe, _HI_ID_* by _hi_identity_probe and _hi_backend_probe -
# the latter waits on the docker/nomad/kubectl probes, up to
# $_HI_PROBE_TIMEOUT). Paid once here,
# in the shell that runs the menus, so every `$( )` render below inherits the
# memo instead of probing the backends again per keystroke.
function _hi_probe_once() {
  _hi_load_preview_sources
  _hi_system_info_probe
  _hi_identity_probe
  _hi_backend_probe
  _hi_header_version >/dev/null
}

# The real header, rendered at the answers this run holds so far: hi_header
# itself, in a subshell that exports what it reads. _HI_DISABLE_HEADER is
# read here rather than exported: a header switched off previews as a
# sentence, not as an empty box show_preview would drop on the floor.
# Captured, not a tty, so _hi_draw_width draws to $_HI_MAX_WIDTH
# exactly - which is what the width dial is previewing.
function _hi_header_preview() {
  local order banner width groups palette lead iphide scheme w
  _hi_load_preview_sources
  if setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1; then
    _hi_cecho " header off - nothing prints on connect or disconnect" "$YELLOW"
    return 0
  fi
  setting_value _HI_HEADER_ORDER "$_HI_SETTINGS" order
  setting_value _HI_DISABLE_BANNER "$_HI_SETTINGS" banner
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" width
  setting_value _HI_PACKAGES_GROUPS "$_HI_SETTINGS" groups
  setting_value _HI_PACKAGES_PALETTE "$_HI_SETTINGS" palette
  setting_value _HI_DISABLE_LEAD_SPACE "$_HI_SETTINGS" lead
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  setting_value _HI_COLOR_SCHEME "$_HI_SETTINGS" scheme
  (
    # no wider than the menu's box can hold: a session clamps to its
    # terminal the same way
    w="${width:-80}"
    ((w > _HI_MENU_W - 8)) && w=$((_HI_MENU_W - (_HI_MENU_W < 60 ? 6 : 8)))
    export _HI_HEADER_ORDER="$order" _HI_DISABLE_BANNER="${banner:-0}" _HI_MAX_WIDTH="$w"
    export _HI_PACKAGES_GROUPS="$groups" _HI_PACKAGES_PALETTE="$palette"
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
    # a narrow menu's box has room for the cwd's last part, not its path
    ((_HI_MENU_W >= 60)) || PWD="${PWD##*/}"
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

# The Package check page's picture: the check alone, at the groups this run
# holds - or why there is none to draw
function _hi_check_preview() {
  local order="" groups="" out w=""
  _hi_load_preview_sources
  setting_value _HI_HEADER_ORDER "$_HI_SETTINGS" order
  setting_value _HI_PACKAGES_GROUPS "$_HI_SETTINGS" groups
  case " ${order:-$_HI_HEADER_ORDER_DEFAULT} " in
  *" check "*) ;;
  *)
    _hi_cecho " the check item is off (the Header page) - these run when it is back on" "$YELLOW"
    return 0
    ;;
  esac
  # no wider than the menu's box can hold, as the header's preview is
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" w
  w="${w:-80}"
  ((w > _HI_MENU_W - 8)) && w=$((_HI_MENU_W - (_HI_MENU_W < 60 ? 6 : 8)))
  out="$(_HI_MAX_WIDTH="$w" _HI_PACKAGES_GROUPS="${groups:-$_HI_PACKAGES_GROUPS_DEFAULT}" full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " these groups show nothing here" "$YELLOW"
  fi
}

# The hub's picture: the header as it would print, then the prompt line as
# it would draw under it - the two things every session shows. Each half
# says "off" in words when it is, so the box always has something to show.
function _hi_config_preview() {
  _hi_header_preview
  _hi_prompt_sample_preview
}

# what each editor's alias is on a target: the lines
# pack.sh's _hi_overlay_wiring writes for the editor configs that would ride
# (GLOSSARY: HI.62), read off that writer rather than restated here, each
# naming the file it carries in place of the target's copy. A name two
# lines alias (`vim`, where a target has nvim) is listed for each, in the
# order a target reads them, so the last is the one it keeps, and a line
# several members of one directory share (micro's) once. A subshell: nothing
# this defines should survive past the preview.
function _hi_editors_preview() {
  (
    # shellcheck source=/dev/null # hi.sh, which shellcheck would follow into its own `_hi "$@"`
    source "$_HI_LAUNCHER" >/dev/null 2>&1
    local row member src lines line body dir from seen=$'\n'
    # under the list this run has settled on, not the file's
    setting_value _HI_PLUGINS_OFF "$_HI_SETTINGS" _HI_PLUGINS_OFF
    while IFS= read -r row; do
      case "$row" in *'|editors|'*) ;; *) continue ;; esac
      member="${row##*|}" src="" lines=""
      _hi_overlay_src "$member" src || continue
      _hi_overlay_wiring lines "$member"
      while IFS= read -r line; do
        while [ "${line#* alias }" != "$line" ]; do
          line="${line#* alias }"
          body="${line#*=\"}"
          body="${body%%\"*}"
          # the file it names, else the directory holding it; both cut
          # ahead of the substitution, which bash 3.2 splits at a / inside
          # a nested expansion
          dir="${member%%/*}" from="${src%/*}"
          body="${body//\$_HI_CONFIG_DIR\/$member/$src}"
          body="${body//\$_HI_CONFIG_DIR\/$dir/$from}"
          _hi_pad_to dir 5 "${line%%=*}"
          body="$dir -> $body"
          case "$seen" in *$'\n'"$body"$'\n'*) continue ;; esac
          seen="$seen$body"$'\n'
          printf '%s\n' "$body"
        done
      done <<<"$lines"
    done < <(_hi_plugin_rows)
  )
}

# what `cat` and `eza` resolve to with the rebinds on - read back from
# common/aliases.sh itself (the same trick _hi_editors_preview uses above)
# rather than restated here, so it cannot drift from what a real session
# gets. The
# resolution caches into _HI_*_BIN/_HI_*_OPTS on export, so those are cleared
# first to force a fresh probe of $PATH rather than reusing another preview's.
function _hi_tool_alias_preview() {
  (
    _HI_TOOL_ALIASES=1
    _HI_CAT_BIN="" _HI_BAT_BIN="" _HI_LS_BIN=""
    _HI_BAT_OPTS="" _HI_EXA_OPTS="" _HI_EZA_OPTS="" _HI_LS_OPTS=""
    # shellcheck disable=SC2031 # lives and dies in this subshell
    # shellcheck source=../common/aliases.sh
    source "$_HI_ALIASES" >/dev/null 2>&1
    if [ -n "$_HI_BAT_BIN" ]; then
      printf 'cat -> %s %s\n' "$_HI_CAT_BIN" "$_HI_BAT_OPTS"
    else
      printf 'bat is not installed here - only targets that have it are affected\n'
    fi
    if [ -n "$(command -v eza || command -v exa)" ]; then
      printf 'ls -> %s %s\n' "$_HI_LS_BIN" "$_HI_LS_OPTS"
    else
      printf 'eza is not installed here - only targets that have it are affected\n'
    fi
  )
}

# The Aliases page's picture: what ls and cat become, while that row is on
function _hi_aliases_preview() {
  setting_on _HI_TOOL_ALIASES "$_HI_SETTINGS" "" 1 || return 0
  _hi_tool_alias_preview
}

# _hi_prompt_choice <shell> <value> <outvar> - who draws <shell>'s prompt
# under a $_HI_PROMPT_TOOL value, as the menu names it: the first program or
# `hi` its entries try, auto when there are only other shells' entries or
# none, and hi when every entry misses the shell (core.sh's _hi_prompt_tool)
function _hi_prompt_choice() {
  local _hi_pc_w _hi_pc_r _hi_pc_on="" _hi_pc_p="" _hi_pc_c=""
  # shellcheck disable=SC2086 # the value is a space-separated word list
  for _hi_pc_w in $2; do
    case "$_hi_pc_w" in
    "$1":*) _hi_pc_on="$_hi_pc_on ${_hi_pc_w#*:}" ;;
    *:*) ;;
    *) _hi_pc_p="$_hi_pc_p $_hi_pc_w" ;;
    esac
  done
  for _hi_pc_w in $_hi_pc_on $_hi_pc_p; do
    [ "$_hi_pc_w" != hi ] || _hi_pc_c=hi
    [ -n "$_hi_pc_c" ] || ! _hi_prompt_row "$_hi_pc_w" _hi_pc_r || {
      _hi_pc_r="${_hi_pc_r#*|}"
      case " ${_hi_pc_r%%|*} " in *" $1 "*) _hi_pc_c="$_hi_pc_w" ;; esac
    }
    [ -z "$_hi_pc_c" ] || break
  done
  [ -n "$_hi_pc_c" ] || { [ -n "$_hi_pc_p" ] && _hi_pc_c=hi || _hi_pc_c=auto; }
  printf -v "$3" '%s' "$_hi_pc_c"
}

# _hi_prompt_tool_preview <shell> <choice> - the choices for who draws
# <shell>'s prompt, numbered for config_prompt_tool with <choice> checked;
# what auto means here is hi.sh's own answer, sourced into a subshell
# through its BASH_SOURCE hatch
function _hi_prompt_tool_preview() {
  local found off="" r name item n=1 note
  setting_value _HI_DISABLE_PROMPT "$_HI_SETTINGS" off
  if [ "$off" = 1 ]; then
    printf "moot while the prompt is off (the item above): no program and no hi prompt draws\n"
    return 0
  fi
  # shellcheck source=/dev/null # hi.sh, whose functions alone are wanted
  found="$(unset _HI_PROMPT_TOOL && source "$_HI_LAUNCHER" && _hi_prompt_list)"
  note="no prompt program is installed here, so hi's prompt"
  for name in $found; do
    _hi_prompt_row "$name" r || continue
    r="${r#*|}"
    case " ${r%%|*} " in *" $1 "*) note="the first of these a target has, else hi's: $found" && break ;; esac
  done
  for name in auto hi $_HI_PROMPT_TOOLS; do
    case "$name" in
    auto | hi) ;;
    *)
      _hi_prompt_row "$name" r
      r="${r#*|}"
      case " ${r%%|*} " in *" $1 "*) ;; *) continue ;; esac
      case " $found " in *" $name "*) note="found here" ;; *) note="not found here" ;; esac
      ;;
    esac
    [ "$name" != hi ] || note="hi's own prompt"
    _hi_ask_item item "$n" "$([ "$name" = "$2" ] && echo 1 || echo 0)" "$name" 13
    printf ' %s  %b%s%b\n' "$item" "$BLUE" "$note" "$NC"
    n=$((n + 1))
  done
}
