#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The packer's plugins files: the tree's config/plugins and the overlay's
# plugins read into rows, each table checked as it closes, and the shell
# hooks among them. Sourced by scripts/pack.sh, never run, and like it
# nothing here rides in the payload. GLOSSARY: HI.63 + HI.66
#
# A row's `$var` is its reader's to expand (SC2016).
# shellcheck disable=SC2016

# _hi_trim <var...> - each variable's value without the spaces around it
function _hi_trim() {
  local _hi_tr_v _hi_tr
  for _hi_tr_v; do
    _hi_tr="${!_hi_tr_v}"
    _hi_tr="${_hi_tr#"${_hi_tr%%[! ]*}"}"
    printf -v "$_hi_tr_v" '%s' "${_hi_tr%"${_hi_tr##*[! ]}"}"
  done
}

# _hi_words_ok <words> <first> <rest> - is <words> one or more words, a space
# between them, each a character of the bracket class <first> and then of
# <rest> alone? The shape of a tool or a variable list in a plugins row.
function _hi_words_ok() {
  local _hi_wo_s="$1 " _hi_wo_w
  [ -n "$1" ] || return 1
  while [ -n "$_hi_wo_s" ]; do
    _hi_wo_w="${_hi_wo_s%% *}" _hi_wo_s="${_hi_wo_s#* }"
    # shellcheck disable=SC2254 # the classes are patterns, and ours
    case "$_hi_wo_w" in '' | [!$2]* | *[!$3]*) return 1 ;; esac
  done
}

# _hi_path_list <list> - a row's home column into the caller's $_hi_paths:
# candidates a : apart, best first, each a path that starts at /, at ~/ (this
# $HOME), or at $NAME (that variable, the path dropped while it is unset or
# empty; $ZDOTDIR is also the one ~/.zshenv sets). A candidate is one path or several a , apart, of which the first
# not dropped is the one: where a tool looks once its variable is unset.
# Nothing else expands and nothing runs. GLOSSARY: HI.63
function _hi_path_list() {
  local _hi_pa_s="$1:" _hi_pa_a _hi_pa_c _hi_pa_n _hi_pa_v
  _hi_paths=()
  while [ -n "$_hi_pa_s" ]; do
    _hi_pa_a="${_hi_pa_s%%:*}," _hi_pa_s="${_hi_pa_s#*:}"
    while [ -n "$_hi_pa_a" ]; do
      _hi_pa_c="${_hi_pa_a%%,*}" _hi_pa_a="${_hi_pa_a#*,}"
      _hi_trim _hi_pa_c
      case "$_hi_pa_c" in
      /*) ;;
      \~/*) _hi_pa_c="$HOME/${_hi_pa_c#??}" ;;
      '$'*)
        _hi_pa_n="${_hi_pa_c#?}"
        _hi_pa_n="${_hi_pa_n%%/*}"
        _hi_words_ok "$_hi_pa_n" 'A-Za-z_' 'A-Za-z0-9_' && [ "${_hi_pa_n% *}" = "$_hi_pa_n" ] || continue
        _hi_pa_v="${!_hi_pa_n:-}"
        # a ~/.zshenv's ZDOTDIR is in no environment but a zsh's
        if [ -z "$_hi_pa_v" ] && [ "$_hi_pa_n" = ZDOTDIR ]; then
          _hi_zshrc_here _hi_pa_v
          _hi_pa_v="${_hi_pa_v%/.zshrc}"
          [ "$_hi_pa_v" != "$HOME" ] || _hi_pa_v=""
        fi
        [ -n "$_hi_pa_v" ] || continue
        _hi_pa_c="$_hi_pa_v${_hi_pa_c#"\$$_hi_pa_n"}"
        ;;
      *) continue ;;
      esac
      _hi_paths+=("$_hi_pa_c")
      break
    done
  done
}

# _hi_plugins_load - the plugins files into $_HI_PLUGIN_ROWS, a row a member,
# once per tree and overlay: the tree's config/plugins, then the overlay's
# plugins, whose plugin of a name the tree's has replaces it whole. Each is
# TOML in the subset core.sh's _hi_toml_row reads. A `[<group>.<name>]` table
# is a plugin, its keys `files` (the members, a space apart), `tool` (left
# out, the name), and `wire`, `home`, and `dialect` (left out, -); a
# `[<group>.<name>."<member>"]` table under it is the wire, home, or dialect
# one of its files has of its own. What the table could not hold is left out
# and noted in $_HI_PLUGIN_BAD: a line that is no table and no key =
# "value", a key above the first plugin or of no name hi reads, a table of
# the rows before these, a second plugin of a name, a plugin of no files, a
# member that is no <name>, <dir>/<name> or <dir>/, or that is hi's own or
# another plugin's, a tool, a wire, or a dialect that is not the table's, a
# home naming a function. GLOSSARY: HI.63
function _hi_plugins_load() {
  local _hi_cy_k="$_HI_ROOT|${_HI_CONFIG_DIR:-}" _hi_cy_s _hi_cy_f _hi_cy_l _hi_cy_n _hi_cy_h _hi_cy_g _hi_cy_p _hi_cy_m _hi_cy_v _hi_cy_i _hi_cy_seen _hi_cy_old
  # the plugin being read: where it opened, its group, name, and keys, its
  # files with the keys each has of its own, and where a key lands - the
  # plugin (-1), one of its files (an index), a table that was turned down
  # (-2), or above the first table (-3)
  local _hi_rc_at _hi_rc_g _hi_rc_n _hi_rc_t _hi_rc_w _hi_rc_h _hi_rc_d _hi_rc_to _hi_rc_i _hi_rc_p _hi_rc_df
  local -a _hi_rc_m=() _hi_rc_mw=() _hi_rc_mh=() _hi_rc_md=()
  [ "$_HI_PLUGIN_KEY" != "$_hi_cy_k" ] || return 0
  _HI_PLUGIN_KEY="$_hi_cy_k" _HI_PLUGIN_ROWS=() _HI_PLUGIN_FILES=() _HI_PLUGIN_NAMES=() _HI_PLUGIN_BAD=()
  _HI_PLUGIN_HOOKS=() _HI_PLUGIN_DEFAULT_OFF=" "
  for _hi_cy_s in config/plugins plugins; do
    case "$_hi_cy_s" in config/*) _hi_cy_f="$_HI_ROOT/$_hi_cy_s" ;; *) _hi_cy_f="${_HI_CONFIG_DIR:-}/$_hi_cy_s" ;; esac
    [ -f "$_hi_cy_f" ] || continue
    _hi_cy_n=0 _hi_cy_seen=" " _hi_cy_old="" _hi_rc_n="" _hi_rc_to=-3
    while IFS= read -r _hi_cy_l || [ -n "$_hi_cy_l" ]; do
      _hi_cy_n=$((_hi_cy_n + 1))
      _hi_trim _hi_cy_l
      case "$_hi_cy_l" in
      '' | '#'*) continue ;;
      '['*']'*)
        _hi_cy_h="${_hi_cy_l#\[}"
        _hi_cy_h="${_hi_cy_h%%\]*}"
        _hi_cy_g="${_hi_cy_h%%.*}" _hi_cy_p="" _hi_cy_m=""
        case "$_hi_cy_h" in *.*) _hi_cy_p="${_hi_cy_h#*.}" ;; esac
        case "$_hi_cy_p" in *.*) _hi_cy_m="${_hi_cy_p#*.}" _hi_cy_p="${_hi_cy_p%%.*}" ;; esac
        _hi_trim _hi_cy_g _hi_cy_p _hi_cy_m
        _hi_cy_m="${_hi_cy_m#\"}"
        _hi_cy_m="${_hi_cy_m%\"}"
        # a file of the plugin being read
        if [ -n "$_hi_cy_m" ] && [ -n "$_hi_rc_n" ] && [ "$_hi_cy_g.$_hi_cy_p" = "$_hi_rc_g.$_hi_rc_n" ]; then
          _hi_rc_to=-2
          for _hi_cy_i in ${_hi_rc_m[@]+"${!_hi_rc_m[@]}"}; do
            [ "${_hi_rc_m[_hi_cy_i]}" != "$_hi_cy_m" ] || _hi_rc_to="$_hi_cy_i"
          done
          [ "$_hi_rc_to" != -2 ] || _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'$_hi_cy_m' is no file of $_hi_rc_n")
          continue
        fi
        _hi_plugins_close
        _hi_rc_to=-2
        if [ -z "$_hi_cy_p" ]; then
          # the rows before the tables, said once a file
          [ -n "$_hi_cy_old" ] || _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'[$_hi_cy_h]' is no [<group>.<name>]: rows of the shape before it, which hi --configure converts")
          _hi_cy_old=1
        elif [ -n "$_hi_cy_m" ]; then
          _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'[$_hi_cy_h]' follows no [$_hi_cy_g.$_hi_cy_p]")
        elif [ "${_hi_cy_g% *}${_hi_cy_p% *}" != "$_hi_cy_g$_hi_cy_p" ] || ! _hi_words_ok "$_hi_cy_g" 'A-Za-z0-9_' 'A-Za-z0-9_-' || ! _hi_words_ok "$_hi_cy_p" 'A-Za-z0-9_' 'A-Za-z0-9_-'; then
          _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'[$_hi_cy_h]' is no [<group>.<name>]")
        elif [ "${_hi_cy_seen#* "$_hi_cy_p" }" != "$_hi_cy_seen" ]; then
          _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'$_hi_cy_p' is a plugin of this file already")
        else
          _hi_cy_seen="$_hi_cy_seen$_hi_cy_p "
          _hi_rc_at="$_hi_cy_s:$_hi_cy_n" _hi_rc_g="$_hi_cy_g" _hi_rc_n="$_hi_cy_p" _hi_rc_to=-1
          _hi_rc_t="" _hi_rc_w="" _hi_rc_h="" _hi_rc_d="" _hi_rc_i="" _hi_rc_p="" _hi_rc_df=""
          _hi_rc_m=() _hi_rc_mw=() _hi_rc_mh=() _hi_rc_md=()
        fi
        continue
        ;;
      esac
      if ! _hi_toml_row "$_hi_cy_l" _hi_cy_h _hi_cy_v; then
        # under a table that was turned down, its lines say nothing more
        [ "$_hi_rc_to" = -2 ] || _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|not a line of a plugin: <key> = \"<value>\"")
        continue
      fi
      case "$_hi_rc_to:$_hi_cy_h" in
      -3:*) _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|no [<group>.<name>] above it") ;;
      -2:*) ;;
      -1:files)
        _hi_rc_m=() _hi_cy_v="$_hi_cy_v "
        while [ -n "$_hi_cy_v" ]; do
          _hi_cy_m="${_hi_cy_v%% *}" _hi_cy_v="${_hi_cy_v#* }"
          [ -z "$_hi_cy_m" ] || _hi_rc_m+=("$_hi_cy_m")
        done
        ;;
      -1:tool) _hi_rc_t="$_hi_cy_v" ;;
      -1:wire) _hi_rc_w="$_hi_cy_v" ;;
      -1:home) _hi_rc_h="$_hi_cy_v" ;;
      -1:dialect) _hi_rc_d="$_hi_cy_v" ;;
      -1:init) _hi_rc_i="$_hi_cy_v" ;;
      -1:prompt) _hi_rc_p="$_hi_cy_v" ;;
      -1:default) _hi_rc_df="$_hi_cy_v" ;;
      -1:*) _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'$_hi_cy_h' is no key of a plugin: files, tool, wire, home, dialect, init, prompt, default") ;;
      *:wire) _hi_rc_mw[_hi_rc_to]="$_hi_cy_v" ;;
      *:home) _hi_rc_mh[_hi_rc_to]="$_hi_cy_v" ;;
      *:dialect) _hi_rc_md[_hi_rc_to]="$_hi_cy_v" ;;
      *) _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'$_hi_cy_h' is no key of a plugin's file: wire, home, dialect") ;;
      esac
    done <"$_hi_cy_f"
    _hi_plugins_close
  done
}

# _hi_plugins_close - the plugin _hi_plugins_load has read, into the rows: a
# row a file, with the plugin's keys or the file's own. Reads that
# function's locals, and ends its plugin. An overlay's plugin takes the place
# of the tree's of its name once it has a row to stand there.
function _hi_plugins_close() {
  local _hi_cl_i _hi_cl_m _hi_cl_t _hi_cl_w _hi_cl_h _hi_cl_d _hi_cl_why _hi_cl_x _hi_cl_put=""
  local -a _hi_cl_rows=() _hi_cl_files=() _hi_cl_names=() _hi_cl_r=() _hi_cl_f=() _hi_cl_n=()
  [ -n "$_hi_rc_n" ] || return 0
  # the tool, left out, is the plugin's name - or its init's command
  _hi_cl_t="${_hi_rc_t:-${_hi_rc_i:+${_hi_rc_i%% *}}}"
  _hi_cl_t="${_hi_cl_t:-$_hi_rc_n}"
  # the shell hook (HI.67): a command printing the shell's code, {shell} in
  # it the shell's name; `prompt = "yes"` says it draws the prompt; `default
  # = "off"` keeps the plugin home until $_HI_PLUGINS_ON names it
  if [ -n "$_hi_rc_p" ] && [ "$_hi_rc_p" != yes ] && [ "$_hi_rc_p" != no ]; then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: prompt is yes or no, not '$_hi_rc_p'")
    _hi_rc_p=""
  fi
  if [ -n "$_hi_rc_df" ] && [ "$_hi_rc_df" != off ] && [ "$_hi_rc_df" != on ]; then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: default is on or off, not '$_hi_rc_df'")
    _hi_rc_df=""
  fi
  if [ -n "$_hi_rc_i" ]; then
    if ! _hi_plugin_init_ok "$_hi_rc_i"; then
      _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: init is a command and its words, no quote, ; | & or \$ among them: '$_hi_rc_i'")
    else
      _hi_plugin_hook_put "$_hi_rc_g|$_hi_rc_n|$_hi_cl_t|$_hi_rc_i|${_hi_rc_p:-no}"
    fi
  elif [ "$_hi_rc_p" = yes ]; then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: prompt = yes needs an init")
  fi
  if [ "$_hi_rc_df" = off ]; then
    case "$_HI_PLUGIN_DEFAULT_OFF" in *" $_hi_rc_n "*) ;; *) _HI_PLUGIN_DEFAULT_OFF="$_HI_PLUGIN_DEFAULT_OFF$_hi_rc_n " ;; esac
  else
    _HI_PLUGIN_DEFAULT_OFF="${_HI_PLUGIN_DEFAULT_OFF// $_hi_rc_n / }"
  fi
  if ! _hi_plugin_tools_ok "$_hi_cl_t"; then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: '$_hi_cl_t' is no list of commands, or -")
  elif ((${#_hi_rc_m[@]} == 0)); then
    [ -n "$_hi_rc_i" ] || _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n names no files")
  else
    for _hi_cl_i in "${!_hi_rc_m[@]}"; do
      _hi_cl_m="${_hi_rc_m[_hi_cl_i]}" _hi_cl_why=""
      _hi_cl_w="${_hi_rc_mw[_hi_cl_i]:-${_hi_rc_w:--}}"
      _hi_cl_h="${_hi_rc_mh[_hi_cl_i]:-${_hi_rc_h:--}}"
      _hi_cl_d="${_hi_rc_md[_hi_cl_i]:-${_hi_rc_d:--}}"
      if ! _hi_plugin_member_ok "$_hi_cl_m"; then
        _hi_cl_why="is no <name>, <dir>/<name>, or <dir>/"
      elif _hi_plugin_taken "$_hi_cl_m" "$_hi_rc_n" ${_hi_cl_files[@]+"${_hi_cl_files[@]}"}; then
        _hi_cl_why="is a member already"
      elif [ "${_hi_cl_h#@}" != "$_hi_cl_h" ] && { [ "${_hi_rc_at%%:*}" != config/plugins ] || ! declare -F "${_hi_cl_h#@}" >/dev/null; }; then
        # an @fn is a function of this file, which only the tree's plugins name
        _hi_cl_why="has a home, '$_hi_cl_h', that is no list of paths"
      elif [ "$_hi_cl_d" != - ] && ! _hi_dialect_row "$_hi_cl_d" _hi_cl_x; then
        _hi_cl_why="has a dialect, '$_hi_cl_d', that hi does not read"
      elif ! _hi_plugin_wire_ok "$_hi_cl_w" _hi_cl_x; then
        _hi_cl_why="has a wire hi does not read: $_hi_cl_x"
      fi
      if [ -n "$_hi_cl_why" ]; then
        _HI_PLUGIN_BAD+=("$_hi_rc_at|'$_hi_cl_m' $_hi_cl_why")
        continue
      fi
      _hi_cl_rows+=("$_hi_cl_m|-|-|$_hi_cl_t|$_hi_rc_g|$_hi_rc_n|$_hi_cl_w|-|$_hi_cl_d|$_hi_cl_h")
      _hi_cl_files+=("$_hi_cl_m") _hi_cl_names+=("$_hi_rc_n")
    done
  fi
  if ((${#_hi_cl_rows[@]})); then
    # where the tree's plugin of this name stood, else last
    for _hi_cl_i in ${_HI_PLUGIN_NAMES[@]+"${!_HI_PLUGIN_NAMES[@]}"}; do
      if [ "${_HI_PLUGIN_NAMES[_hi_cl_i]}" != "$_hi_rc_n" ]; then
        _hi_cl_r+=("${_HI_PLUGIN_ROWS[_hi_cl_i]}") _hi_cl_f+=("${_HI_PLUGIN_FILES[_hi_cl_i]}") _hi_cl_n+=("${_HI_PLUGIN_NAMES[_hi_cl_i]}")
      elif [ -z "$_hi_cl_put" ]; then
        _hi_cl_put=1
        _hi_cl_r+=("${_hi_cl_rows[@]}") _hi_cl_f+=("${_hi_cl_files[@]}") _hi_cl_n+=("${_hi_cl_names[@]}")
      fi
    done
    [ -n "$_hi_cl_put" ] || _hi_cl_r+=("${_hi_cl_rows[@]}") _hi_cl_f+=("${_hi_cl_files[@]}") _hi_cl_n+=("${_hi_cl_names[@]}")
    _HI_PLUGIN_ROWS=("${_hi_cl_r[@]}") _HI_PLUGIN_FILES=("${_hi_cl_f[@]}") _HI_PLUGIN_NAMES=("${_hi_cl_n[@]}")
  fi
  _hi_rc_n=""
}

# _hi_plugin_tools_ok <tool> - a plugin's tool: -, or commands a space apart
function _hi_plugin_tools_ok() {
  [ "$1" = - ] || _hi_words_ok "$1" 'A-Za-z0-9_' 'A-Za-z0-9._+-'
}

# _hi_plugin_init_ok <init> - a command and its words: nothing the shell
# would read as more than words, since a target runs what the command prints
function _hi_plugin_init_ok() {
  local _hi_io_bad=';|&$`"()<>'"'" _hi_io_i
  [ -n "$1" ] || return 1
  # a character at a time, not a bracket expression: one holding every quote
  # is a bash 3.2 trap
  for ((_hi_io_i = 0; _hi_io_i < ${#_hi_io_bad}; _hi_io_i++)); do
    case "$1" in *"${_hi_io_bad:_hi_io_i:1}"*) return 1 ;; esac
  done
  _hi_words_ok "${1%% *}" 'A-Za-z0-9_' 'A-Za-z0-9._+-'
}

# _hi_plugin_hook_put <row> - a hook row, in place of the tree's of its name
function _hi_plugin_hook_put() {
  local _hi_hp_i _hi_hp_n _hi_hp_o
  _hi_hook_col "$1" name _hi_hp_n
  for _hi_hp_i in ${_HI_PLUGIN_HOOKS[@]+"${!_HI_PLUGIN_HOOKS[@]}"}; do
    _hi_hook_col "${_HI_PLUGIN_HOOKS[_hi_hp_i]}" name _hi_hp_o
    [ "$_hi_hp_o" != "$_hi_hp_n" ] || {
      _HI_PLUGIN_HOOKS[_hi_hp_i]="$1"
      return 0
    }
  done
  _HI_PLUGIN_HOOKS+=("$1")
}

# _hi_hook_col <row> <group|name|tool|init|prompt> [outvar] - one column of a
# hook row
function _hi_hook_col() {
  local _hi_hc_r="$1" _hi_hc_n
  for _hi_hc_n in group name tool init prompt; do
    [ "$_hi_hc_n" != "$2" ] || break
    _hi_hc_r="${_hi_hc_r#*|}"
  done
  _hi_out "${3:-}" "${_hi_hc_r%%|*}"
}

# _hi_hook_here <row> - is the hook's tool on this machine; with a tool of
# -, the init's own command
function _hi_hook_here() {
  local _hi_hh_t _hi_hh_l
  _hi_hook_col "$1" tool _hi_hh_l
  [ "$_hi_hh_l" != - ] || { _hi_hook_col "$1" init _hi_hh_l && _hi_hh_l="${_hi_hh_l%% *}"; }
  for _hi_hh_t in $_hi_hh_l; do
    ! command -v "$_hi_hh_t" >/dev/null 2>&1 || return 0
  done
  return 1
}

# _hi_hook_off <row> - is the hook's plugin switched off: named in
# $_HI_PLUGINS_OFF, or off by default and not in $_HI_PLUGINS_ON. core.sh's
# _hi_hook_on is the target's reading.
function _hi_hook_off() {
  local _hi_ho_n
  _hi_hook_col "$1" name _hi_ho_n
  _hi_plugin_switched_off "$_hi_ho_n"
}

# _hi_plugin_switched_off <name> - the two lists' verdict on a plugin
function _hi_plugin_switched_off() {
  local _hi_so_off="${_HI_PLUGINS_OFF:-}" _hi_so_on="${_HI_PLUGINS_ON:-}"
  case " ${_hi_so_off//,/ } " in *" $1 "*) return 0 ;; esac
  case "$_HI_PLUGIN_DEFAULT_OFF" in *" $1 "*) ;; *) return 1 ;; esac
  case " ${_hi_so_on//,/ } " in *" $1 "*) return 1 ;; esac
  return 0
}

# _hi_wire_read <wire> - one wire of a <wire> column, taken apart into the
# caller's locals: $_hi_wr_kind (env, envdir, flag, flagdir, xdg) and, for an
# env or envdir, $_hi_wr_vars; for the rest $_hi_wr_names (what the alias
# answers to, a , apart: `<names>=` ahead of the command, else the command),
# $_hi_wr_env (the words ahead of the command that hold a =, a space after
# each), $_hi_wr_cmd, and $_hi_wr_words (what follows it). An xdg is one
# word, the command or <names>=<command>, with $XDG_CONFIG_HOME for its
# environment. 1 for a wire of no kind, or of no command. The one reading of
# the grammar: _hi_plugin_wire_ok admits what this takes apart, and
# _hi_overlay_wiring writes it. Builtins only. GLOSSARY: HI.62
function _hi_wire_read() {
  local _hi_wr_b="${1#*:} " _hi_wr_x
  _hi_wr_kind="${1%%:*}" _hi_wr_vars="" _hi_wr_names="" _hi_wr_env="" _hi_wr_cmd="" _hi_wr_words=""
  case "$1" in
  env:?* | envdir:?*)
    _hi_wr_vars="${1#*:}"
    return 0
    ;;
  xdg:?*)
    _hi_wr_cmd="${_hi_wr_b% }"
    case "$_hi_wr_cmd" in *' '*) return 1 ;; *=*) _hi_wr_names="${_hi_wr_cmd%%=*}" _hi_wr_cmd="${_hi_wr_cmd#*=}" ;; esac
    _hi_wr_env='XDG_CONFIG_HOME=$_HI_CONFIG_DIR '
    ;;
  flag:?* | flagdir:?*)
    case "${_hi_wr_b%% *}" in *=*) _hi_wr_names="${_hi_wr_b%%=*}" _hi_wr_b="${_hi_wr_b#*=}" ;; esac
    while [ -n "$_hi_wr_b" ] && [ -z "$_hi_wr_cmd" ]; do
      _hi_wr_x="${_hi_wr_b%% *}" _hi_wr_b="${_hi_wr_b#* }"
      case "$_hi_wr_x" in
      [!-]*=*) _hi_wr_env="$_hi_wr_env$_hi_wr_x " ;;
      *) _hi_wr_cmd="$_hi_wr_x" ;;
      esac
    done
    _hi_wr_words="${_hi_wr_b% }"
    ;;
  *) return 1 ;;
  esac
  [ -n "$_hi_wr_cmd" ] || return 1
  _hi_wr_names="${_hi_wr_names:-$_hi_wr_cmd}"
}

# _hi_plugin_wire_ok <wire> <outvar> - the table's <wire> column, wires a ;
# apart, each as _hi_wire_read takes it apart; why not into <outvar>, and 1.
# Every part is checked, since each becomes a word of a line a target
# sources: nothing that could run or expand there beyond a $NAME.
function _hi_plugin_wire_ok() {
  local _hi_wk_s="$1;" _hi_wk_w _hi_wk_why
  local _hi_wr_kind _hi_wr_vars _hi_wr_names _hi_wr_env _hi_wr_cmd _hi_wr_words
  [ "$1" != - ] || return 0
  while [ -n "$_hi_wk_s" ]; do
    _hi_wk_w="${_hi_wk_s%%;*}" _hi_wk_s="${_hi_wk_s#*;}" _hi_wk_why=""
    _hi_wire_read "$_hi_wk_w" || _hi_wr_cmd=""
    case "$_hi_wk_w" in
    env:?* | envdir:?*)
      _hi_words_ok "$_hi_wr_vars" 'A-Za-z_' 'A-Za-z0-9_' || _hi_wk_why="is no list of variable names"
      ;;
    flag:?* | flagdir:?*)
      # a command, at least one word after it, and nothing else in a part
      _hi_words_ok "$_hi_wr_cmd" 'A-Za-z0-9_' 'A-Za-z0-9._+-' &&
        _hi_words_ok "$_hi_wr_words" 'A-Za-z0-9=,._+/$-' 'A-Za-z0-9=,._+/$-' &&
        _hi_words_ok "${_hi_wr_names//,/ }" 'A-Za-z0-9_' 'A-Za-z0-9._+-' &&
        { [ -z "$_hi_wr_env" ] || _hi_words_ok "${_hi_wr_env% }" 'A-Za-z_' 'A-Za-z0-9=,._+/$-'; } ||
        _hi_wk_why="is not a command and its words"
      ;;
    xdg:?*)
      _hi_words_ok "$_hi_wr_cmd" 'A-Za-z0-9_' 'A-Za-z0-9._+-' &&
        _hi_words_ok "${_hi_wr_names//,/ }" 'A-Za-z0-9_' 'A-Za-z0-9._+-' ||
        _hi_wk_why="is not a command, or <names>=<command>"
      ;;
    *)
      printf -v "$2" '%s' "'$_hi_wk_w' is not env:, envdir:, flag:, flagdir:, xdg:, or -"
      return 1
      ;;
    esac
    [ -z "$_hi_wk_why" ] || {
      printf -v "$2" '%s' "'${_hi_wk_w#*:}' $_hi_wk_why"
      return 1
    }
  done
}

# _hi_plugin_member_ok <member> - a plain name, <dir>/<name>, or a directory
# <dir>/ or <dir>/<dir>/, each part _hi_dir_member_ok's, and never the name
# of a file hi writes itself or of the overlay's rows, which stay home
function _hi_plugin_member_ok() {
  local _hi_pm="$1"
  case "$_hi_pm" in */*/*/* | wiring.sh | plugins | plugins/*) return 1 ;; esac
  _hi_pm="${_hi_pm%/}"
  _hi_dir_member_ok "${_hi_pm%%/*}" && _hi_dir_member_ok "${_hi_pm##*/}"
}

# _hi_plugin_taken <member> <plugin> [member...] - is <member> the table's or
# a name a member had before ($_HI_OVERLAY_RENAMES), one of the <member...>
# its own plugin has already, another plugin's, or the directory entry any of
# those sits under or that sits under it? A row of <plugin>'s own does not
# count: an overlay's plugin replaces the tree's of its name.
function _hi_plugin_taken() {
  local _hi_ct _hi_ct_m="$1" _hi_ct_n="$2" _hi_ct_i
  shift 2
  for _hi_ct in "${_HI_OVERLAY_FILES[@]}" $_HI_OVERLAY_RENAMES "$@"; do
    _hi_ct="${_hi_ct%%:*}"
    case "$_hi_ct_m" in "$_hi_ct" | "${_hi_ct%/}"/*) return 0 ;; esac
    case "$_hi_ct" in "${_hi_ct_m%/}"/*) return 0 ;; esac
  done
  for _hi_ct_i in ${_HI_PLUGIN_FILES[@]+"${!_HI_PLUGIN_FILES[@]}"}; do
    [ "${_HI_PLUGIN_NAMES[_hi_ct_i]}" != "$_hi_ct_n" ] || continue
    _hi_ct="${_HI_PLUGIN_FILES[_hi_ct_i]}"
    case "$_hi_ct_m" in "$_hi_ct" | "${_hi_ct%/}"/*) return 0 ;; esac
    case "$_hi_ct" in "${_hi_ct_m%/}"/*) return 0 ;; esac
  done
  return 1
}
