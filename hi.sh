#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies say-hi to the target and chainloads load.sh there.
#
# Most of this file is a script assembled for *another* machine, so a `$var`
# in single quotes is the target's to expand (SC2016) and a command string
# sent to ssh is expanded here on purpose (SC2029).
# shellcheck disable=SC2016,SC2029
set -euo pipefail # off again below: sourced by the interactive shell, where an error would close the session

# The connect banner's client leg, stamped before core.sh exists - so this is
# core.sh's _hi_now inlined, replaced by the real one the moment it loads.
_hi_now() {
  d=$(date +%s.%N 2>/dev/null)
  case "$d" in *N* | '') date +%s ;; *) printf '%s' "$d" ;; esac
}
# the `||` matters under `set -e`: a client with no `date` degrades to an
# empty connect time rather than aborting before this file defines anything.
_HI_CONNECT_T0="${EPOCHREALTIME:-$(_hi_now)}" || _HI_CONNECT_T0=""

# The directory *containing* say-hi, off this script's own path behind a
# symlink walk. Same walk as scripts/install.sh's and packaging/lib.sh's:
# fix one, fix all. GLOSSARY: HI.33
if [ -z "${_HI_HOME:-}" ]; then
  _hi_self="${BASH_SOURCE[0]}"
  while [ -L "$_hi_self" ]; do
    _hi_link="$(readlink "$_hi_self")"
    case "$_hi_link" in
    /*) _hi_self="$_hi_link" ;;
    *) case "$_hi_self" in
      */*) _hi_self="${_hi_self%/*}/$_hi_link" ;;
      *) _hi_self="$_hi_link" ;;
      esac ;;
    esac
  done
  _HI_HOME="$(cd -P "$(dirname "$_hi_self")/.." && pwd)"
  unset _hi_self _hi_link
fi
export _HI_HOME
# checked before the source: bash's own "No such file" would name a path
# nobody typed, and _hi_cecho is in the file that's missing
[ -r "$_HI_HOME/say-hi/common/core.sh" ] || {
  echo "hi: no say-hi at $_HI_HOME/say-hi - set _HI_HOME to the directory that holds it (the checkout has to be a directory named say-hi)" >&2
  exit 1
}
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"

_HI_RELEASE="${_HI_RELEASE:-}"

# Kept identical to docs/hi.1's SYNOPSIS (parse_test.sh compares the two);
# folded so --help fits 80 columns
_HI_USAGE="Usage: hi [ssh-options] [--use <backend>] [--plain] [--mux|--no-mux]
          <target> [command ...]"

# What ships to a target - an allow list. hi.sh is in it so a disposable
# session has a launcher to relay onward with.
_HI_PAYLOAD=(common config load.sh hi.sh)

# The user's config overlay: a second, smaller stream into its own overlay/ on
# the target (GLOSSARY: HI.41), and every member's one resolution order
# (HI.61): the overlay's copy, else the user's own file at home, else the
# tree's default, which the payload already carries. One row per member:
# <member>|<paths.sh variable>|<tree, when config/ has a default>|<tool>|<group>|<wire>|<off>|<dialect>|<home>.
# This table is hi's own members' - its files, and the prompt configs whose
# home is a lookup (@fn) no path list can say. The tools' rows are
# config/plugins' and the overlay's plugins (_hi_plugins_load): the same
# columns, of which a file holds <member>, <tool>, <wire>, <home> and
# <dialect>, and the table it sits under is its <group>.
# <paths.sh variable> is hi's own files' alone: a tool's member has none, and
# what hi's code reads of one on a target is an env: wire of its row.
# <tool> is the binaries that read it, its name in a report first: home's
# copy rides with any of them on $PATH. In parentheses it is a name alone,
# for what nothing looks for - a shell, readline, a prompt program
# (_hi_prompt_list asks about those).
# <group> is the word that switches it with its kind in $_HI_PLUGINS_OFF
# (_hi_plugin_off), or - for a member of hi's own, which nothing switches.
# <wire> is what points the tool at the member on a target, written there by
# _hi_overlay_wiring (HI.62), whose comment is the grammar: env: and envdir:
# export variables, flag: and flagdir: alias a command, and - leaves the
# member to hi's own code.
# <off> is the toggles that keep one of hi's own files home, spelled as a
# wiring line reads them, or - for none: with any of them at 1 the member
# stays home (_hi_plugin_off). A tool's member has none: $_HI_PLUGINS_OFF
# switches it.
# <dialect> is the $_HI_DIALECTS row the include scan and the comment strip
# read it by, or - for a file that rides as written.
# <home> is the candidates, best first, in _hi_path_list's grammar - or @fn
# for a lookup no path list can say, or - for none: a shell's own rc
# (bashrc, zshrc, config.fish) rides only from the overlay, since the rc a
# target runs should be asked for, not found. A member is <tool>/<file>
# where its tool keeps a directory under ~/.config, the file named as the
# tool names it, and its own name where the tool keeps none. A candidate
# ending in / is a directory, the member's file looked for inside it. A
# member with a trailing / is a directory whose files ride one by one
# (HI.58), from the overlay alone where the row has no home.
_HI_OVERLAY_TABLE=(
  'settings.sh|_HI_SETTINGS|-|-|-|-|-|sh|-'
  'colors|_HI_COLORS|tree|-|-|-|-|conf|-'
  'packages|_HI_PACKAGES|tree|-|-|-|$_HI_DISABLE_HEADER|conf|-'
  'extensions/|_HI_EXTENSIONS|-|-|shell|-|-|sh|-'
  'header/|_HI_HEADER_CELLS|-|-|-|-|$_HI_DISABLE_HEADER|sh|-'
  'plugins|-|-|-|-|-|-|conf|-'
  'oh-my-posh.json|-|-|(oh-my-posh)|prompt|env:POSH_CONFIG POSH_THEME|-|omp-json|@_hi_posh_home'
  'oh-my-posh.yaml|-|-|(oh-my-posh)|prompt|env:POSH_CONFIG POSH_THEME|-|omp|@_hi_posh_home'
  'oh-my-posh.toml|-|-|(oh-my-posh)|prompt|env:POSH_CONFIG POSH_THEME|-|omp|@_hi_posh_home'
  'oh-my-zsh.zsh-theme|-|-|(oh-my-zsh)|prompt|-|-|omz|@_hi_theme_home'
  'oh-my-bash.theme.sh|-|-|(oh-my-bash)|prompt|-|-|omb|@_hi_theme_home'
  'bash-it.theme.bash|-|-|(bash-it)|prompt|-|-|bash-it|@_hi_theme_home'
  'ssh_tags|-|-|(ssh)|-|-|-|-|@_hi_ssh_tags_file'
)

# _hi_row_col <row> <column> <outvar> - one column of a row, by the name the
# table's comment gives it
function _hi_row_col() {
  local _hi_rc_r="$1" _hi_rc_n
  for _hi_rc_n in member variable tree tool group wire off dialect home; do
    [ "$_hi_rc_n" != "$2" ] || break
    _hi_rc_r="${_hi_rc_r#*|}"
  done
  printf -v "$3" '%s' "${_hi_rc_r%%|*}"
}

# The dialects a row's <dialect> names, for _hi_lint_awk and _hi_strip_awk:
# <name> | <leader> | <strip> | <end> | <disable> | <plugin> | <include> | <allow>,
# no column holding a ` | `, - for none. <leader> starts a comment line; with
# <strip> 1 the strip drops those, blank lines, and indentation. <end> is
# where a statement ends: line, \ (a line ending in one continues it), ()
# (the brackets balance, strings "-quoted), or ()' ('-quoted too).
# <disable> is how a finding goes out: comment (a <leader> line, the whole
# statement), : or true (the verb and its file word become that no-op, a
# plugin line is prefixed with it), or "" (the value is emptied). <plugin>,
# <include>, and <allow> are EREs, \t a tab: a line matching <plugin> is a
# plugin manager, and one matching <include> is an include, once the text
# <allow> matches is taken out - for a : or true disable, <include> is the
# verb in command position and <allow> the file words it leaves alone.
_HI_DIALECTS=()

# _hi_dialect_row <name> <outvar> - its $_HI_DIALECTS row; 1 for none
function _hi_dialect_row() {
  local _hi_dr
  ((${#_HI_DIALECTS[@]})) || _hi_read_lines _HI_DIALECTS <<'ROWS'
sh | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT)[}/"]
omz | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|ZSH)[}/"]
omb | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|OSH)[}/"]
bash-it | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|BASH_IT)[}/"]
fish | # | 1 | line | true | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT)[}/"]
vim | " | 1 | line | comment | ^[ \t]*(Plug|Plugin|NeoBundle|packadd)[ \t!]|(plug|vundle|dein|minpac)# | ^[ \t]*(source|so)!?[ \t] | .*[$]VIMRUNTIME.*
lua | -- | 1 | ()' | comment | lazypath|rtp:prepend|vim[.]pack[.]add|require[ \t]*[(]?[ \t]*["'](lazy|packer|paq)|AddRuntimeFile.*RTPlugin | AddRuntimeFile|(dofile|loadfile)[ \t]*[(]|vim[.]cmd.*source[ \t]|require[ \t]*[(]?[ \t]*["'] | require[ \t]*[(]?[ \t]*["']vim[.]
elisp | ; | 1 | () | comment | [(](package-initialize|package-install|use-package|straight-|elpaca) | [(]load(-file)?[ \t]+"|add-to-list[ \t]+'load-path | -
nano | # | 1 | line | comment | - | ^[ \t]*include[ \t] | ^[ \t]*include[ \t]+["']?/usr/share/nano/?[^/"' \t]*(["' \t].*)?$
tmux | # | 1 | \ | comment | @plugin|(^|[ \t;{"'])run(-shell)?[ \t].*tpm | (^|[ \t;{"'])source(-file)?[ \t] | -
screen | # | 1 | line | comment | - | ^[ \t]*source[ \t] | -
readline | # | 1 | line | comment | - | ^[ \t]*[$]include[ \t] | ^[ \t]*[$]include[ \t]+/etc/inputrc([ \t].*)?$
kak | # | 0 | line | comment | ^[ \t]*(plug|bundle)[ \t]|(plug|bundle)[.]kak | (^|[ \t;{])source[ \t] | .*%val[{]runtime[}].*
kdl | // | 0 | () | comment | location[ \t]*=[ \t]*"file: | ^[ \t]*(layout_dir|theme_dir)[ \t] | -
omp | # | 0 | line | comment | - | (^|[ \t{,"'])extends["']?[ \t]*[:=][ \t]*["']?[^"' \t,}]*([/~\\][^"' \t,}]*|[.](json|jsonc|ya?ml|toml))(["' \t,}]|$) | extends["']?[ \t]*[:=][ \t]*["']?https?://
omp-json | - | 0 | line | "" | - | (^|[ \t{,"'])extends["']?[ \t]*[:=][ \t]*["']?[^"' \t,}]*([/~\\][^"' \t,}]*|[.](json|jsonc|ya?ml|toml))(["' \t,}]|$) | extends["']?[ \t]*[:=][ \t]*["']?https?://
conf | # | 1 | line | comment | - | - | -
ROWS
  for _hi_dr in "${_HI_DIALECTS[@]}"; do
    [ "${_hi_dr%% | *}" != "$1" ] || {
      printf -v "$2" '%s' "$_hi_dr"
      return 0
    }
  done
  return 1
}

# _hi_member_dialect <member> <outvar> - the dialect row its overlay row
# names; 1 for a member that rides as written
function _hi_member_dialect() {
  local _hi_md
  _hi_overlay_row "$1" _hi_md || return 1
  _hi_row_col "$_hi_md" dialect _hi_md
  _hi_dialect_row "$_hi_md" "$2"
}

# the members alone, and those with a tree default the overlay's copy
# replaces wholesale on a target (aliases.sh is not one - the overlay's is
# sourced on top of the tree's); _hi_payload_excl reads the second
_HI_OVERLAY_FILES=() _HI_OVERLAY_SHADOWS=" "
# ...and every toggle an <off> column names, once each, for _hi_plugin_off
_HI_OFF_TOGGLES=" "
for _hi_r in "${_HI_OVERLAY_TABLE[@]}"; do
  _HI_OVERLAY_FILES+=("${_hi_r%%|*}")
  case "$_hi_r" in *'|tree|'*) _HI_OVERLAY_SHADOWS="$_HI_OVERLAY_SHADOWS${_hi_r%%|*} " ;; esac
  _hi_row_col "$_hi_r" off _hi_r
  for _hi_w in $_hi_r; do
    case "$_hi_w$_HI_OFF_TOGGLES" in -* | *" ${_hi_w#?} "*) ;; *) _HI_OFF_TOGGLES="$_HI_OFF_TOGGLES${_hi_w#?} " ;; esac
  done
done
unset _hi_r _hi_w

# The tools' rows, read from config/plugins and the overlay's plugins by
# _hi_plugins_load: the table's shape. $_HI_PLUGIN_BAD is the lines it
# turned down, `<file>:<line>|<why>` each, for scripts/doctor.sh.
# GLOSSARY: HI.63
_HI_PLUGIN_ROWS=() _HI_PLUGIN_FILES=() _HI_PLUGIN_BAD=() _HI_PLUGIN_KEY="" _HI_PLUGIN_TREE_ROWS=0

# The overlay members renamed before 1.0, old:new. hi reads only the new
# name; scripts/doctor.sh names a file still under the old one, since it
# would otherwise be silently ignored.
_HI_OVERLAY_RENAMES="carry:plugins plugins.d:extensions vim.rc:vim/vimrc vimrc:vim/vimrc init.lua:nvim/init.lua nano.rc:nano/nanorc nanorc:nano/nanorc
  emacs.el:emacs/init.el init.el:emacs/init.el config.toml:helix/config.toml kakrc:kak/kakrc tmux.conf:tmux/tmux.conf theme.yml:eza/theme.yml
  bat.conf:bat/config lazygit.yml:lazygit/config.yml bash.sh:bashrc zsh.zsh:zshrc omz-theme.zsh:oh-my-zsh.zsh-theme omb-theme.sh:oh-my-bash.theme.sh"

# What a bash-less target falls back to, best first - derived from
# $_HI_SHELL_TREE so the two orderings cannot drift.
export _HI_SHELL_LADDER="${_HI_SHELL_TREE//bash /}"

# stands in for the size until the script is measured. GLOSSARY: HI.44
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: HI.17 - base64 over openssl (and openssl where base64 is
# missing), the -d/-D ladder, and the `tr` fold
_HI_ARMOR="base64"
command -v base64 >/dev/null 2>&1 || _HI_ARMOR="openssl base64"
_HI_UNARMOR="if command -v base64 >/dev/null 2>&1; then tr -s ' ' '\n' | { base64 -d 2>/dev/null || base64 -D; }; else tr -d ' \n' | openssl base64 -d -A 2>/dev/null; fi"

function _hi_armored_line() {
  printf 'echo "%s" | %s %s %s' "$($_HI_ARMOR)" "$_HI_UNARMOR" "$1" "$2"
}

# _hi_shquote <var> <value> - <value> as one single-quoted sh word, into <var>;
# every value baked into a target's script goes through here.
# GLOSSARY: HI.40 - why a hand loop and not ${2//...}
function _hi_shquote() {
  local _s="$2" _o=""
  while [ "${_s#*\'}" != "$_s" ]; do
    _o="$_o${_s%%\'*}'\\''"
    _s="${_s#*\'}"
  done
  printf -v "$1" "'%s'" "$_o$_s"
}

# The client-derived env both transports export into the session, one
# NAME<TAB>value pair per line; _hi_env_each renders it per transport.
function _hi_session_env() {
  # the memos primed here and read, not $( ) - see _hi's own priming
  _hi_target_color >/dev/null
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  printf '_HI_TARGET_COLOR\t%s\n' "$_HI_TARGET_COLOR_MEMO"
  # user@host: the tag is the host's, as _hi_target_color reads it
  _hi_ssh_host_tag "${DOMAIN##*@}" >/dev/null 2>&1 || true
  printf '_HI_TARGET_TAG\t%s\n' "$_HI_TAG_VALUE"
  printf '_HI_LOCAL_USER\t%s\n' "$_HI_WHOAMI_CACHE"
  printf '_HI_LOCAL_HOSTNAME\t%s\n' "$_HI_HOSTNAME_CACHE"
  printf '_HI_RELEASE\t%s\n' "$(_hi_version)"
  _hi_prompt_list >/dev/null
  printf '_HI_PROMPT_TOOL\t%s\n' "$_HI_PROMPT_LIST_MEMO"
  # the client's own editors, for load.sh's _hi_session_editor to try first
  local _hi_se_v
  ! _hi_cmd_name "${EDITOR:-}" _hi_se_v || printf '_HI_CLIENT_EDITOR\t%s\n' "$_hi_se_v"
  ! _hi_cmd_name "${VISUAL:-}" _hi_se_v || printf '_HI_CLIENT_VISUAL\t%s\n' "$_hi_se_v"
  _hi_client_verdicts '%s\t%s\n'
}

# _hi_cmd_name <command line> <outvar> - its command's bare name, false when
# that is not a plain word: $EDITOR and $VISUAL ride by name alone, since a
# path or a flag names something of this machine's
function _hi_cmd_name() {
  local _hi_cn_v="${1%% *}"
  _hi_cn_v="${_hi_cn_v##*/}"
  case "$_hi_cn_v" in '' | *[!A-Za-z0-9._+-]*) return 1 ;; esac
  printf -v "$2" '%s' "$_hi_cn_v"
}

# _hi_client_verdicts <format> - the *client's* glyph and 24-bit verdicts
# (ssh never forwards COLORTERM, GLOSSARY: HI.50), and NO_COLOR only when set,
# as <format> lines of name then value; both transports print these.
function _hi_client_verdicts() {
  local _hi_cv_a="${_HI_ASCII:-}" _hi_cv_t="${_HI_TRUECOLOR:-}"
  [ -n "$_hi_cv_a" ] || _hi_ascii_flag _hi_cv_a
  [ -n "$_hi_cv_t" ] || _hi_truecolor_flag _hi_cv_t
  # shellcheck disable=SC2059 # the format is ours, not user data
  {
    printf "$1" _HI_ASCII "$_hi_cv_a"
    printf "$1" _HI_TRUECOLOR "$_hi_cv_t"
    [ -z "${NO_COLOR:-}" ] || printf "$1" NO_COLOR 1
  }
}

# memoized: three callers, $DOMAIN is fixed for the run
function _hi_target_color() {
  [ "${_HI_TARGET_COLOR_MEMO+x}" = x ] ||
    _hi_resolve_color hostname "${DOMAIN##*@}" '' _HI_TARGET_COLOR_MEMO
  printf '%s\n' "$_HI_TARGET_COLOR_MEMO"
}

# _hi_prompt_handed <member> - is that prompt config's program one a target
# is handed (_hi_prompt_list)? Nothing else starts it, so no copy of it rides
# otherwise. GLOSSARY: HI.32
function _hi_prompt_handed() {
  local _hi_ph_t
  _hi_prompt_row "$1" _hi_ph_t || return 1
  _hi_prompt_list >/dev/null
  case " $_HI_PROMPT_LIST_MEMO " in *" ${_hi_ph_t%%|*} "*) ;; *) return 1 ;; esac
}

# _hi_posh_home <member> [outvar] - oh-my-posh's config at home, under the
# member its extension names: oh-my-posh parses by extension and paths.sh
# cannot rename, hence three members for one program - and one config a
# target, so an overlay copy in any format outranks home's. oh-my-posh has no
# default file: $POSH_CONFIG ($POSH_THEME in older releases), else the rc's
# `init --config`.
function _hi_posh_home() {
  local _hi_ph_f
  for _hi_ph_f in "$_HI_CONFIG_DIR"/oh-my-posh.{json,yaml,toml}; do
    [ ! -f "$_hi_ph_f" ] || return 1
  done
  _hi_ph_f="${POSH_CONFIG:-${POSH_THEME:-}}"
  [ -n "$_hi_ph_f" ] || _hi_posh_rc_config _hi_ph_f || return 1
  case "$1:$_hi_ph_f" in
  oh-my-posh.json:*.json | oh-my-posh.yaml:*.yaml | oh-my-posh.yaml:*.yml | oh-my-posh.toml:*.toml) ;;
  *) return 1 ;;
  esac
  [ -f "$_hi_ph_f" ] && _hi_out "${2:-}" "$_hi_ph_f"
}

# _hi_theme_home <member> [outvar] - the theme file the rc's ZSH_THEME /
# OSH_THEME / BASH_IT_THEME names, looked up the way oh-my-zsh, oh-my-bash,
# and bash-it look
function _hi_theme_home() {
  local _hi_th_t _hi_th_d _hi_th_f=""
  case "$1" in
  oh-my-zsh.zsh-theme)
    # powerlevel10k/powerlevel10k is p10k's own entry point, not a theme file
    _hi_rc_theme ZSH_THEME "${ZDOTDIR:-$HOME}/.zshrc" _hi_th_t || return 1
    case "$_hi_th_t" in */* | random) return 1 ;; esac
    _hi_th_d="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
    for _hi_th_f in {"$_hi_th_d","$_hi_th_d/themes","${ZSH:-$HOME/.oh-my-zsh}/themes"}/"$_hi_th_t".zsh-theme; do
      [ -f "$_hi_th_f" ] && break
    done
    ;;
  oh-my-bash.theme.sh)
    _hi_rc_theme OSH_THEME "$HOME/.bashrc" _hi_th_t || return 1
    _hi_th_d="${OSH_CUSTOM:-${OSH:-$HOME/.oh-my-bash}/custom}"
    for _hi_th_f in {"$_hi_th_d","$_hi_th_d/themes","${OSH:-$HOME/.oh-my-bash}/themes"}/"$_hi_th_t/$_hi_th_t".theme.{sh,bash}; do
      [ -f "$_hi_th_f" ] && break
    done
    ;;
  bash-it.theme.bash)
    # bash_it.sh's own loader checks exactly these two, in this order, for a
    # bare theme name - the custom themes dir, then the built-in one
    _hi_rc_theme BASH_IT_THEME "$HOME/.bashrc" _hi_th_t || return 1
    for _hi_th_f in {"${BASH_IT_CUSTOM:-${BASH_IT:-$HOME/.bash_it}/custom}/themes","${BASH_IT:-$HOME/.bash_it}/themes"}/"$_hi_th_t/$_hi_th_t".theme.bash; do
      [ -f "$_hi_th_f" ] && break
    done
    ;;
  esac
  [ -f "$_hi_th_f" ] && _hi_out "${2:-}" "$_hi_th_f"
}

# _hi_prompt_list [outvar] - the prompt programs a target is handed:
# $_HI_PROMPT_TOOL when set, else every one this machine has - the programs
# on $PATH, tide where fisher put it, and a framework with a theme or config
# to ship. Memoized: the members and the session env each ask. GLOSSARY: HI.32
function _hi_prompt_list() {
  local _hi_pl_r _hi_pl_t _hi_pl_f _hi_pl_out=""
  if [ "${_HI_PROMPT_LIST_KEY-}" != "${_HI_PROMPT_TOOL:-}|$HOME" ]; then
    _HI_PROMPT_LIST_KEY="${_HI_PROMPT_TOOL:-}|$HOME" _HI_PROMPT_LIST_MEMO="${_HI_PROMPT_TOOL:-}"
    if [ -z "$_HI_PROMPT_LIST_MEMO" ] && [ "$_HI_REMOTE_SESSION" != 1 ]; then
      # _hi_overlay_src asks this list too: all of it while it is being built
      _HI_PROMPT_LIST_MEMO="$_HI_PROMPT_TOOLS"
      for _hi_pl_r in "${_HI_PROMPT_TABLE[@]}"; do
        _hi_pl_t="${_hi_pl_r%%|*}"
        case "$_hi_pl_r" in
        *'|bin|'*) command -v "$_hi_pl_t" >/dev/null 2>&1 ;;
        tide'|'*) [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions/tide.fish" ] ;;
        powerlevel10k'|'*) _hi_p10k_in_use && _hi_overlay_src "${_hi_pl_r##*|}" _hi_pl_f ;;
        *) _hi_overlay_src "${_hi_pl_r##*|}" _hi_pl_f ;;
        esac && _hi_pl_out="$_hi_pl_out${_hi_pl_out:+ }$_hi_pl_t"
      done
      _HI_PROMPT_LIST_MEMO="$_hi_pl_out"
    fi
  fi
  _hi_out "${1:-}" "$_HI_PROMPT_LIST_MEMO"
}

# _hi_rc_last_match <regex> <outvar> <file...> - the second group of the last
# line of <file...> the regex matches, into <outvar>; 1 when none does. What
# an rc *sets* - a theme name, a flag on an init line - lives in a shell
# variable or a command line no child of the rc sees, so the file is read,
# never sourced. An absent file is skipped.
function _hi_rc_last_match() {
  local _hi_rl_re="$1" _hi_rl_out="$2" _hi_rl_f _hi_rl_l _hi_rl_v=""
  shift 2
  for _hi_rl_f; do
    [ -f "$_hi_rl_f" ] || continue
    while IFS= read -r _hi_rl_l || [ -n "$_hi_rl_l" ]; do
      [[ "$_hi_rl_l" =~ $_hi_rl_re ]] && _hi_rl_v="${BASH_REMATCH[2]}"
    done <"$_hi_rl_f"
  done
  [ -n "$_hi_rl_v" ] && printf -v "$_hi_rl_out" '%s' "$_hi_rl_v"
}

# _hi_rc_value <NAME> <outvar> <file...> - what the last NAME= line of
# <file...> sets, its quotes dropped; 1 when none does, or it sets nothing
function _hi_rc_value() {
  local _hi_rv=""
  _hi_rc_last_match "^[[:space:]]*(export[[:space:]]+)?$1=(\"[^\"]*\"|'[^']*'|[^[:space:]#]*)" _hi_rv "${@:3}" || return 1
  _hi_rv="${_hi_rv#[\"\']}"
  _hi_rv="${_hi_rv%[\"\']}"
  [ -n "$_hi_rv" ] && printf -v "$2" '%s' "$_hi_rv"
}

# _hi_rc_theme <NAME> <rc> [outvar] - $NAME when exported, else what <rc>
# sets it to: a framework's theme.
function _hi_rc_theme() {
  local _hi_rt_v="${!1:-}"
  [ -n "$_hi_rt_v" ] || _hi_rc_value "$1" _hi_rt_v "$2" || return 1
  _hi_out "${3:-}" "$_hi_rt_v"
}

# _hi_posh_rc_config [outvar] - the local file an rc's `oh-my-posh init ...
# --config <file>` names: oh-my-posh has no default file. The last such line
# of the bash, zsh, and fish rcs, `~` and $HOME expanded.
function _hi_posh_rc_config() {
  local _hi_pc_v=""
  _hi_rc_last_match "^[^#]*oh-my-posh[^#]*[[:space:]]init[[:space:]][^#]*(--config[=[:space:]]|-c[[:space:]])[[:space:]]*[\"']?([^\"'[:space:])]+)" \
    _hi_pc_v "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc" "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
  _hi_pc_v="${_hi_pc_v/#\~/$HOME}"
  _hi_pc_v="${_hi_pc_v/#\$HOME/$HOME}"
  _hi_pc_v="${_hi_pc_v/#\$\{HOME\}/$HOME}"
  [ -n "$_hi_pc_v" ] && _hi_out "${1:-}" "$_hi_pc_v"
}

# _hi_p10k_in_use - does the zsh rc load powerlevel10k *as the theme*? Its
# config file is not that signal. p10k's wizard appends
# `[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh`, guarded so it goes inert
# when the file is gone - so a `~/.p10k.zsh` left behind by a theme switch
# outlives the theme it configured, and the file alone read as "in use"
# shipped p10k over the `ZSH_THEME` actually in force. What loads the theme is
# one of three shapes, and all of them name it twice or name its repo:
# `ZSH_THEME=powerlevel10k/powerlevel10k` (oh-my-zsh's entry point for it, the
# one _hi_theme_home turns down as "not a theme file"), a
# source of `powerlevel10k.zsh-theme` wherever it is installed, or a plugin
# manager naming `romkatv/powerlevel10k`. Missed: an rc that loads it from a
# file it sources - the cheaper failure of the two, since it costs the p10k
# prompt on a target rather than drawing a prompt the user does not use, and
# `_HI_PROMPT_TOOL=powerlevel10k` names it past any detection. Every other
# framework here is found the same way, by what the rc sets
# (docs/INTEGRATIONS.md's _counts as installed here_).
function _hi_p10k_in_use() {
  local _hi_pk=""
  _hi_rc_last_match '^[^#]*(powerlevel10k|romkatv)(/powerlevel10k|\.zsh-theme)' \
    _hi_pk "${ZDOTDIR:-$HOME}/.zshrc"
  [ -n "$_hi_pk" ]
}

# _hi_trim <var> - the variable's value without the spaces around it
function _hi_trim() {
  local _hi_tr="${!1}"
  _hi_tr="${_hi_tr#"${_hi_tr%%[! ]*}"}"
  printf -v "$1" '%s' "${_hi_tr%"${_hi_tr##*[! ]}"}"
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
# empty). A candidate is one path or several a , apart, of which the first
# not dropped is the one: where a tool looks once its variable is unset.
# Nothing else expands and nothing runs. GLOSSARY: HI.63
function _hi_path_list() {
  local _hi_pa_s="$1:" _hi_pa_a _hi_pa_c _hi_pa_n
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
        [ -n "${!_hi_pa_n:-}" ] || continue
        _hi_pa_c="${!_hi_pa_n}${_hi_pa_c#"\$$_hi_pa_n"}"
        ;;
      *) continue ;;
      esac
      _hi_paths+=("$_hi_pa_c")
      break
    done
  done
}

# _hi_plugins_load - the tools' rows into $_HI_PLUGIN_ROWS, once per tree
# and overlay: the tree's config/plugins, then the overlay's plugins, whose
# row of a member the tree's has replaces it. Each is TOML in the subset
# core.sh's _hi_toml_row reads: `[group]` tables of
# `"<member>" = "<tool> | <wire> | <home> | <dialect>"` rows, the last column
# - when left out. A row the table could not hold is left out and noted in
# $_HI_PLUGIN_BAD: one above the first table, a member that is no <name>,
# <dir>/<name> or <dir>/, or that is hi's own or a row's already, a tool, a
# wire, or a dialect that is not the table's, a fifth column. On a target the overlay's file is the one that rode, so a next hop
# carries the same members. GLOSSARY: HI.63
function _hi_plugins_load() {
  local _hi_cy_k="$_HI_ROOT|${_HI_CONFIG_DIR:-}" _hi_cy_s _hi_cy_f _hi_cy_l _hi_cy_g _hi_cy_m _hi_cy_t _hi_cy_w _hi_cy_h _hi_cy_d _hi_cy_x _hi_cy_why _hi_cy_n _hi_cy_i
  [ "$_HI_PLUGIN_KEY" != "$_hi_cy_k" ] || return 0
  _HI_PLUGIN_KEY="$_hi_cy_k" _HI_PLUGIN_ROWS=() _HI_PLUGIN_FILES=() _HI_PLUGIN_BAD=() _HI_PLUGIN_TREE_ROWS=0
  for _hi_cy_s in config/plugins plugins; do
    case "$_hi_cy_s" in config/*) _hi_cy_f="$_HI_ROOT/$_hi_cy_s" ;; *) _hi_cy_f="${_HI_CONFIG_DIR:-}/$_hi_cy_s" ;; esac
    [ -f "$_hi_cy_f" ] || continue
    _hi_cy_n=0 _hi_cy_g=""
    while IFS= read -r _hi_cy_l || [ -n "$_hi_cy_l" ]; do
      _hi_cy_n=$((_hi_cy_n + 1))
      _hi_trim _hi_cy_l
      _hi_cy_why=""
      case "$_hi_cy_l" in
      '' | '#'*) continue ;;
      '['*']'*)
        _hi_cy_g="${_hi_cy_l#\[}"
        _hi_cy_g="${_hi_cy_g%%\]*}"
        _hi_trim _hi_cy_g
        _hi_words_ok "$_hi_cy_g" 'A-Za-z0-9_' 'A-Za-z0-9_-' && [ "${_hi_cy_g% *}" = "$_hi_cy_g" ] || {
          _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'[$_hi_cy_g]' is no group name")
          _hi_cy_g=""
        }
        continue
        ;;
      esac
      _hi_cy_x="" _hi_cy_t="" _hi_cy_w="" _hi_cy_h="" _hi_cy_d=""
      if ! _hi_toml_row "$_hi_cy_l" _hi_cy_m _hi_cy_t; then
        _hi_cy_why="not a row: \"<member>\" = \"<tool> | <wire> | <home> | <dialect>\""
      else
        IFS='|' read -r _hi_cy_t _hi_cy_w _hi_cy_h _hi_cy_d _hi_cy_x <<<"$_hi_cy_t"
        _hi_trim _hi_cy_t
        _hi_trim _hi_cy_w
        _hi_trim _hi_cy_h
        _hi_trim _hi_cy_d
        _hi_cy_d="${_hi_cy_d:--}"
      fi
      if [ -n "$_hi_cy_why" ]; then
        :
      elif [ -z "$_hi_cy_g" ]; then
        _hi_cy_why="no [group] above it"
      elif [ -n "$_hi_cy_x" ] || [ -z "$_hi_cy_h" ]; then
        _hi_cy_why="not three or four columns: <tool> | <wire> | <home> | <dialect>"
      elif ! _hi_plugin_member_ok "$_hi_cy_m"; then
        _hi_cy_why="'$_hi_cy_m' is no <name>, <dir>/<name>, or <dir>/"
      elif _hi_plugin_taken "$_hi_cy_m" _hi_cy_i "$_hi_cy_s"; then
        _hi_cy_why="'$_hi_cy_m' is a member already"
      elif [ "${_hi_cy_h#@}" != "$_hi_cy_h" ]; then
        # the table's @fn is a function's name, which no line of a file is
        _hi_cy_why="'$_hi_cy_h' is no list of paths"
      elif ! _hi_plugin_tools_ok "$_hi_cy_t"; then
        _hi_cy_why="'$_hi_cy_t' is no list of commands, a (name), or -"
      elif [ "$_hi_cy_d" != - ] && ! _hi_dialect_row "$_hi_cy_d" _hi_cy_x; then
        _hi_cy_why="'$_hi_cy_d' is no dialect hi reads, or -"
      else
        _hi_plugin_wire_ok "$_hi_cy_w" _hi_cy_why || :
      fi
      if [ -n "$_hi_cy_why" ]; then
        _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|$_hi_cy_why")
        continue
      fi
      _hi_cy_l="$_hi_cy_m|-|-|$_hi_cy_t|$_hi_cy_g|$_hi_cy_w|-|$_hi_cy_d|$_hi_cy_h"
      if [ "$_hi_cy_i" -ge 0 ]; then
        _HI_PLUGIN_ROWS[_hi_cy_i]="$_hi_cy_l"
      else
        _HI_PLUGIN_ROWS+=("$_hi_cy_l")
        _HI_PLUGIN_FILES+=("$_hi_cy_m")
      fi
    done <"$_hi_cy_f"
    [ "$_hi_cy_s" != config/plugins ] || _HI_PLUGIN_TREE_ROWS="${#_HI_PLUGIN_ROWS[@]}"
  done
}

# _hi_plugin_tools_ok <tool> - the table's <tool> column: -, commands a
# space apart, or one (name) nothing looks for
function _hi_plugin_tools_ok() {
  case "$1" in
  -) return 0 ;;
  '('*')') _hi_words_ok "${1#\(}" 'A-Za-z0-9_' 'A-Za-z0-9._+)-' && [ "${1% *}" = "$1" ] ;;
  *) _hi_words_ok "$1" 'A-Za-z0-9_' 'A-Za-z0-9._+-' ;;
  esac
}

# _hi_plugin_wire_ok <wire> <outvar> - the table's <wire> column, wires a ;
# apart, as _hi_overlay_wiring reads them; why not into <outvar>, and 1
function _hi_plugin_wire_ok() {
  local _hi_wk_s="$1;" _hi_wk_w _hi_wk_x _hi_wk_c
  [ "$1" != - ] || return 0
  while [ -n "$_hi_wk_s" ]; do
    _hi_wk_w="${_hi_wk_s%%;*}" _hi_wk_s="${_hi_wk_s#*;}"
    _hi_wk_x="${_hi_wk_w#*:}"
    case "$_hi_wk_w" in
    env:?* | envdir:?*)
      _hi_words_ok "$_hi_wk_x" 'A-Za-z_' 'A-Za-z0-9_' || {
        printf -v "$2" '%s' "'$_hi_wk_x' is no list of variable names"
        return 1
      }
      ;;
    flag:?*' '?* | flagdir:?*' '?*)
      # <names>=, the environment, then the command and its words
      _hi_wk_c="${_hi_wk_x%% *}"
      case "$_hi_wk_c" in *=*) _hi_wk_c="${_hi_wk_c#*=}" _hi_wk_x="${_hi_wk_x#*=}" ;; esac
      while :; do
        case "$_hi_wk_x" in [!-]*=*' '*) _hi_wk_x="${_hi_wk_x#* }" _hi_wk_c="${_hi_wk_x%% *}" ;; *) break ;; esac
      done
      if ! _hi_words_ok "$_hi_wk_c" 'A-Za-z0-9_' 'A-Za-z0-9._+-' || ! _hi_words_ok "$_hi_wk_x" 'A-Za-z0-9=,._+/$-' 'A-Za-z0-9=,._+/$-'; then
        printf -v "$2" '%s' "'$_hi_wk_x' is not a command and its words"
        return 1
      fi
      ;;
    xdg:?*)
      # one word: the command, or <names>=<command>
      if [ "${_hi_wk_x% *}" != "$_hi_wk_x" ] || ! _hi_words_ok "${_hi_wk_x#*=}" 'A-Za-z0-9_' 'A-Za-z0-9._+-' ||
        ! _hi_words_ok "${_hi_wk_x%%=*}" 'A-Za-z0-9_' 'A-Za-z0-9,._+-'; then
        printf -v "$2" '%s' "'$_hi_wk_x' is not a command, or <names>=<command>"
        return 1
      fi
      ;;
    *)
      printf -v "$2" '%s' "'$_hi_wk_w' is not env:, envdir:, flag:, flagdir:, xdg:, or -"
      return 1
      ;;
    esac
  done
}

# _hi_plugin_member_ok <member> - a plain name, <dir>/<name>, or a directory
# <dir>/ or <dir>/<dir>/, each part _hi_dir_member_ok's, and never a name of
# a file hi writes itself
function _hi_plugin_member_ok() {
  local _hi_pm="$1"
  case "$_hi_pm" in */*/*/* | wiring.sh) return 1 ;; esac
  _hi_pm="${_hi_pm%/}"
  _hi_dir_member_ok "${_hi_pm%%/*}" && _hi_dir_member_ok "${_hi_pm##*/}"
}

# _hi_plugin_taken <member> <outvar> [file] - is <member> the table's or a
# name a member had before ($_HI_OVERLAY_RENAMES), a plugins row's already,
# or the directory entry one sits under or that sits under it? A row of the
# tree's file that the overlay's <file> names again is not taken: its index
# in $_HI_PLUGIN_ROWS goes to <outvar>, -1 otherwise, for the overlay's row
# to replace it.
function _hi_plugin_taken() {
  local _hi_ct _hi_ct_i=0
  printf -v "$2" '%s' -1
  for _hi_ct in "${_HI_OVERLAY_FILES[@]}" $_HI_OVERLAY_RENAMES; do
    _hi_ct="${_hi_ct%%:*}"
    case "$1" in "$_hi_ct" | "${_hi_ct%/}"/*) return 0 ;; esac
    case "$_hi_ct" in "${1%/}"/*) return 0 ;; esac
  done
  for _hi_ct in ${_HI_PLUGIN_FILES[@]+"${_HI_PLUGIN_FILES[@]}"}; do
    if [ "$_hi_ct" = "$1" ]; then
      [ "${3:-}" = plugins ] && [ "$_hi_ct_i" -lt "${_HI_PLUGIN_TREE_ROWS:-0}" ] || return 0
      printf -v "$2" '%s' "$_hi_ct_i"
      return 1
    fi
    case "$1" in "${_hi_ct%/}"/*) return 0 ;; esac
    case "$_hi_ct" in "${1%/}"/*) return 0 ;; esac
    _hi_ct_i=$((_hi_ct_i + 1))
  done
  return 1
}

# _hi_overlay_row <member> [outvar] - its row, $_HI_OVERLAY_TABLE's then the
# plugins files' ($_HI_PLUGIN_ROWS): its own or the directory entry (a
# trailing /) it sits under
function _hi_overlay_row() {
  local _hi_or
  _hi_plugins_load
  for _hi_or in "${_HI_OVERLAY_TABLE[@]}" ${_HI_PLUGIN_ROWS[@]+"${_HI_PLUGIN_ROWS[@]}"}; do
    case "$1" in "${_hi_or%%|*}" | "${_hi_or%%/|*}"/?*)
      _hi_out "${2:-}" "$_hi_or"
      return 0
      ;;
    esac
  done
  return 1
}

# _hi_overlay_src <member> [outvar] - where an overlay member is packed from,
# in the table's order: the overlay's copy, else home's (_hi_overlay_home) -
# a target gets the config in force here with no copy to keep in step - else
# nothing, since a tree default rides in the payload already. A prompt
# config rides only for a program a target is handed, and nothing of a
# plugin that is switched off. Fails, printing nothing, when there is no
# file either way.
function _hi_overlay_src() {
  local _hi_os_f="$_HI_CONFIG_DIR/$1"
  ! _hi_plugin_off "$1" || return 1
  ! _hi_prompt_row "$1" >/dev/null || _hi_prompt_handed "$1" || return 1
  [ -f "$_hi_os_f" ] || _hi_overlay_home "$1" _hi_os_f || return 1
  _hi_out "${2:-}" "$_hi_os_f"
}

# _hi_overlay_home <member> [outvar] - the home tier alone, on this machine
# only (a relay must not pack the middle box's) and with the member's tool
# here to read it: the first of its row's candidates that exists. A directory
# entry answers with the directory.
function _hi_overlay_home() {
  local _hi_oh_r _hi_oh_c
  local -a _hi_paths=()
  [ "$_HI_REMOTE_SESSION" != 1 ] && _hi_overlay_row "$1" _hi_oh_r && _hi_tool_here "$1" "$_hi_oh_r" || return 1
  _hi_overlay_places "$1" "$_hi_oh_r"
  for _hi_oh_c in ${_hi_paths[@]+"${_hi_paths[@]}"}; do
    if [ -f "$_hi_oh_c" ] || { [ -z "${1##*/}" ] && [ -d "$_hi_oh_c" ]; }; then
      _hi_out "${2:-}" "$_hi_oh_c"
      return 0
    fi
  done
  return 1
}

# _hi_overlay_places <member> <row> - the row's home candidates into the
# caller's $_hi_paths, best first, a candidate ending in / as the member's
# file inside it
function _hi_overlay_places() {
  local _hi_op_h="${2##*|}" _hi_op_c="" _hi_op_i
  _hi_paths=()
  case "$_hi_op_h" in
  -) ;;
  @*) ! "${_hi_op_h#@}" "$1" _hi_op_c || _hi_paths=("$_hi_op_c") ;;
  *) _hi_path_list "$_hi_op_h" ;;
  esac
  for _hi_op_i in ${_hi_paths[@]+"${!_hi_paths[@]}"}; do
    case "${_hi_paths[_hi_op_i]}" in */) _hi_paths[_hi_op_i]="${_hi_paths[_hi_op_i]}${1#*/}" ;; esac
  done
}

# _hi_ssh_tags_file <member> [outvar] - the tag map a relayed hop colors by
# (ssh_tags' home, so the table's calling shape): every
# `# Tags:` line of ~/.ssh/config and the files it Includes, with the Host or
# Match line under it and nothing else of the block, so the middle box's
# _hi_ssh_host_tag can walk it as the config it is cut from. Kept in the
# runtime dir, recut when the config is newer or has an Include; fails with no
# config, no runtime dir, or no tag.
function _hi_ssh_tags_file() {
  local _hi_tf_d="" _hi_tf _hi_tf_tmp
  [ -f "$_HI_SSH_CONFIG" ] || return 1
  _hi_runtime_dir _hi_tf_d
  [ -n "$_hi_tf_d" ] || return 1
  _hi_tf="$_hi_tf_d/hi.ssh_tags"
  # an Include's files have mtimes of their own, so a config with one is recut
  if [ ! "$_hi_tf" -nt "$_HI_SSH_CONFIG" ] || grep -qi '^[[:space:]]*include[[:space:]=]' "$_HI_SSH_CONFIG"; then
    # mktemp, not `.$$`: every subshell of one shell shares its $$
    _hi_tf_tmp="$(mktemp "$_hi_tf.XXXXXX")" || return 1
    sh "$_HI_TARGETS" ssh-config "$_HI_SSH_CONFIG" | awk '{ t = $0; sub(/^[ \t]+/, "", t); l = tolower(t) }
      l ~ /^#[ \t]*tags[:=]/ { tag = t; next }
      l ~ /^#/ || l == "" { next }
      tag != "" && l ~ /^(host|match[ \t]+host)[ \t]/ { print tag; print t }
      { tag = "" }' >"$_hi_tf_tmp" && mv -f "$_hi_tf_tmp" "$_hi_tf" && _hi_tf_tmp=""
    [ -z "$_hi_tf_tmp" ] || {
      rm -f "$_hi_tf_tmp"
      return 1
    }
  fi
  [ -s "$_hi_tf" ] && _hi_out "${2:-}" "$_hi_tf"
}

# _hi_overlay_tools <member> [outvar] [row] - its row's tool column (the row
# looked up unless handed in); 1 for a member of no tool's, or of no row
function _hi_overlay_tools() {
  local _hi_tc="${3:-}"
  [ -n "$_hi_tc" ] || _hi_overlay_row "$1" _hi_tc || return 1
  _hi_row_col "$_hi_tc" tool _hi_tc
  [ "$_hi_tc" != - ] && _hi_out "${2:-}" "$_hi_tc"
}

# _hi_tool_label <member> <outvar> [row] - the name a report gives its tool,
# the column's first without its parentheses; 1 and empty with no tool
function _hi_tool_label() {
  local _hi_tb=""
  _hi_overlay_tools "$1" _hi_tb "${3:-}" || true
  _hi_tb="${_hi_tb#\(}"
  printf -v "$2" '%s' "${_hi_tb%%[ \)]*}"
  [ -n "$_hi_tb" ]
}

# _hi_plugin_name <member> <outvar> [row] - the plugin a member is of: its
# tool's label, else the member's own name
function _hi_plugin_name() {
  _hi_tool_label "$@" || printf -v "$2" '%s' "${1%%/*}"
}

# _hi_toggle_on <NAME> - is that toggle 1 for a target? The environment's
# value - except at home under _HI_DISABLE_LOCAL=1, where common/paths.sh has
# set every toggle for this machine alone: there, only a toggle settings.sh
# sets itself, read off its last `export NAME=value` line (_hi_rc_value)
# without running it.
function _hi_toggle_on() {
  local _hi_tg_n _hi_tg_v
  if [ "${_HI_DISABLE_LOCAL:-0}" != 1 ] || [ "$_HI_REMOTE_SESSION" = 1 ]; then
    [ "${!1:-0}" = 1 ]
    return
  fi
  if [ "${_HI_SET_ON_KEY-}" != "$_HI_SETTINGS" ]; then
    _HI_SET_ON_KEY="$_HI_SETTINGS" _HI_SET_ON=" "
    for _hi_tg_n in $_HI_OFF_TOGGLES; do
      ! _hi_rc_value "$_hi_tg_n" _hi_tg_v "$_HI_SETTINGS" || [ "$_hi_tg_v" != 1 ] || _HI_SET_ON="$_HI_SET_ON$_hi_tg_n "
    done
  fi
  case "$_HI_SET_ON" in *" $1 "*) return 0 ;; esac
  return 1
}

# _hi_plugin_off <member> [outvar] - is it switched off, and by what, into
# <outvar>? By $_HI_PLUGINS_OFF naming its plugin, its group, or the member
# (words a space or a comma apart), or by a toggle of its row's <off> column;
# a row of hi's own (group -) is never off. Read where the overlay is
# packed, so what is off neither rides nor is wired, and the target is handed
# the result. GLOSSARY: HI.64
function _hi_plugin_off() {
  local _hi_po_r _hi_po_g _hi_po_n _hi_po_t
  # nothing is off, most connects: said once for the values in force, since
  # every member asks, several times a connect
  _hi_po_t="${_HI_PLUGINS_OFF:-}|${_HI_DISABLE_LOCAL:-0}|${_HI_REMOTE_SESSION:-0}|${_HI_SETTINGS:-}|"
  for _hi_po_n in $_HI_OFF_TOGGLES; do _hi_po_t="$_hi_po_t${!_hi_po_n:-0}"; done
  if [ "${_HI_OFF_KEY-}" != "$_hi_po_t" ]; then
    _HI_OFF_KEY="$_hi_po_t" _HI_OFF_ANY="${_HI_PLUGINS_OFF:-}"
    for _hi_po_n in $_HI_OFF_TOGGLES; do ! _hi_toggle_on "$_hi_po_n" || _HI_OFF_ANY=1; done
  fi
  [ -n "$_HI_OFF_ANY" ] && _hi_overlay_row "$1" _hi_po_r || return 1
  _hi_row_col "$_hi_po_r" group _hi_po_g
  _hi_row_col "$_hi_po_r" off _hi_po_t
  # shellcheck disable=SC2086 # the split is the column
  [ "$_hi_po_t" = - ] || for _hi_po_n in $_hi_po_t; do
    ! _hi_toggle_on "${_hi_po_n#?}" || {
      [ -z "${2:-}" ] || printf -v "$2" '%s' "${_hi_po_n#?}=1"
      return 0
    }
  done
  # hi's own file: its toggles above, never the list
  [ "$_hi_po_g" != - ] || return 1
  [ -n "${_HI_PLUGINS_OFF:-}" ] || return 1
  _hi_plugin_name "$1" _hi_po_n "$_hi_po_r"
  case " ${_HI_PLUGINS_OFF//,/ } " in
  *" $_hi_po_n "* | *" $_hi_po_g "* | *" ${_hi_po_r%%|*} "*)
    [ -z "${2:-}" ] || printf -v "$2" '%s' "_HI_PLUGINS_OFF"
    return 0
    ;;
  esac
  return 1
}

# _hi_overlay_wiring <outvar> <member...> - the lines that point each tool at
# its member on a target, in common/paths.sh's four-shell dialect, which
# sources them there. A row's wire column holds one wire or several, a ;
# between them: env:<variables> exports each as the member's path and
# envdir: as its directory; flag:<command> <words> aliases the command to
# itself, the words, and the path, where the target has the command, and
# flagdir: the same with the directory. <command> is `<names>=<command>` to
# answer to other names (a , between them), and words before it that hold a =
# are its environment. A flag ending in = takes the path in the same word.
# xdg:<command> aliases the command to itself with $XDG_CONFIG_HOME set to
# the overlay, whose <tool>/<file> members are laid out as ~/.config is: the
# fallback for a file no variable or flag reaches, since everything the
# command starts inherits the variable too.
# The directory of a member under a / is the one its first name names.
# Wires run in order and a later alias replaces an earlier one, so helix's
# languages.toml row follows its config.toml row: with both riding, the xdg
# alias is the one a target keeps.
#
# The paths stay under $_HI_CONFIG_DIR for the target to expand, so a next
# hop writes the same lines, and a row's <off> toggles are tested there,
# where the shell starts. A line is written once, however many members ask
# for it. Builtins only: every connect runs it. GLOSSARY: HI.62
function _hi_overlay_wiring() {
  local _hi_ow_out="$1" _hi_ow_m _hi_ow_r _hi_ow_ws _hi_ow_w _hi_ow_g _hi_ow_p _hi_ow_v _hi_ow_l
  local _hi_ow_n _hi_ow_c _hi_ow_e _hi_ow_all=$'\n'
  shift
  for _hi_ow_m; do
    _hi_overlay_row "$_hi_ow_m" _hi_ow_r || continue
    _hi_row_col "$_hi_ow_r" wire _hi_ow_ws
    _hi_row_col "$_hi_ow_r" off _hi_ow_r
    [ "$_hi_ow_ws" != - ] || continue
    _hi_ow_ws="$_hi_ow_ws;" _hi_ow_g=""
    # shellcheck disable=SC2086 # the split is the column
    [ "$_hi_ow_r" = - ] || for _hi_ow_v in $_hi_ow_r; do
      _hi_ow_g="${_hi_ow_g}[ \"$_hi_ow_v\" != 1 ] && "
    done
    while [ -n "$_hi_ow_ws" ]; do
      _hi_ow_w="${_hi_ow_ws%%;*}" _hi_ow_ws="${_hi_ow_ws#*;}"
      case "$_hi_ow_w" in
      env:* | flag:*) _hi_ow_p="\$_HI_CONFIG_DIR/$_hi_ow_m" ;;
      envdir:* | flagdir:*)
        _hi_ow_p="\$_HI_CONFIG_DIR"
        case "$_hi_ow_m" in */*) _hi_ow_p="$_hi_ow_p/${_hi_ow_m%%/*}" ;; esac
        ;;
      xdg:*)
        # flag:'s alias with the variable for its environment, and no path
        _hi_ow_n="${_hi_ow_w#xdg:}" _hi_ow_p=""
        case "$_hi_ow_n" in *=*) ;; *) _hi_ow_n="$_hi_ow_n=$_hi_ow_n" ;; esac
        _hi_ow_w="flag:${_hi_ow_n%%=*}=XDG_CONFIG_HOME=\$_HI_CONFIG_DIR ${_hi_ow_n#*=}"
        ;;
      *) continue ;;
      esac
      _hi_ow_l="$_hi_ow_g"
      case "$_hi_ow_w" in
      flag*)
        # <names>=, then the environment, the command, and its words
        _hi_ow_w="${_hi_ow_w#*:} "
        _hi_ow_n="" _hi_ow_e="" _hi_ow_c=""
        case "${_hi_ow_w%% *}" in *=*) _hi_ow_n="${_hi_ow_w%%=*}" _hi_ow_w="${_hi_ow_w#*=}" ;; esac
        while [ -z "$_hi_ow_c" ]; do
          case "${_hi_ow_w%% *}" in
          [!-]*=*) _hi_ow_e="$_hi_ow_e${_hi_ow_w%% *} " ;;
          *) _hi_ow_c="${_hi_ow_w%% *}" ;;
          esac
          _hi_ow_w="${_hi_ow_w#* }"
        done
        case "$_hi_ow_w" in *'= ') _hi_ow_w="${_hi_ow_w% }" ;; esac
        # the path bare, as an alias of hi's always had it: load.sh reads a
        # body back for $EDITOR, and a quote inside one does not survive that
        _hi_ow_v="${_hi_ow_e:+env $_hi_ow_e}$_hi_ow_c $_hi_ow_w$_hi_ow_p"
        # no trailing blank, which would have the shell expand the next word
        # as an alias too
        _hi_ow_v="${_hi_ow_v% }"
        _hi_ow_l="${_hi_ow_l}command -v $_hi_ow_c >/dev/null 2>&1"
        _hi_ow_n="${_hi_ow_n:-$_hi_ow_c},"
        while [ -n "$_hi_ow_n" ]; do
          _hi_ow_l="$_hi_ow_l && alias ${_hi_ow_n%%,*}=\"$_hi_ow_v\""
          _hi_ow_n="${_hi_ow_n#*,}"
        done
        _hi_ow_l="$_hi_ow_l || true"
        ;;
      *)
        _hi_ow_l="${_hi_ow_l}export"
        # shellcheck disable=SC2086 # the split is the column
        for _hi_ow_v in ${_hi_ow_w#*:}; do
          _hi_ow_l="$_hi_ow_l $_hi_ow_v=\"$_hi_ow_p\""
        done
        # a line behind a toggle ends true, or a sourcer under set -e would
        # stop at the file whose last line a toggle turned down
        [ -z "$_hi_ow_g" ] || _hi_ow_l="$_hi_ow_l || true"
        ;;
      esac
      case "$_hi_ow_all" in *$'\n'"$_hi_ow_l"$'\n'*) ;; *) _hi_ow_all="$_hi_ow_all$_hi_ow_l"$'\n' ;; esac
    done
  done
  printf -v "$_hi_ow_out" '%s' "${_hi_ow_all#$'\n'}"
}

# _hi_tool_here <member> [row] - is the tool that reads <member> on this
# machine? The table's binaries, which are the names common/aliases.sh gates
# each alias on; a member of no tool's, or of one nothing looks for, is a yes.
# The client is asked because only it can be, before a connect
# (docs/INTEGRATIONS.md's _Which side is asked_).
function _hi_tool_here() {
  local _hi_tl_t _hi_tl_b
  _hi_overlay_tools "$1" _hi_tl_t "${2:-}" || return 0
  case "$_hi_tl_t" in '('*) return 0 ;; esac
  # shellcheck disable=SC2086 # the split is the column
  for _hi_tl_b in $_hi_tl_t; do
    ! command -v "$_hi_tl_b" >/dev/null 2>&1 || return 0
  done
  return 1
}

# The include scanner, in the dialect of each file it reads. Every member
# ships into the target's `config/`, so a line naming a *path* - a second rc
# beside it, a plugin directory, a manager's bootstrap - names something no
# target has, and the editor or shell fails on it rather than hi. The
# grammars are $_HI_DIALECTS rows, the file's read from ENVIRON[_hi_dialect];
# what each finds, and what it deliberately leaves alone:
#
#   vim     `source`/`so` (a path), the managers' verbs (`Plug`, `packadd`,
#           `plug#`/`vundle#`/`dein#`). `runtime` is *not* flagged: it
#           searches the target vim's own &runtimepath, which is there.
#           `source $VIMRUNTIME/...` is the same argument.
#   lua     `dofile`/`loadfile`, a `vim.cmd` carrying `source`, `require` of
#           anything but a `vim.` module, and the managers (lazy, packer,
#           paq, neovim's own `vim.pack.add`, an `rtp:prepend` bootstrap).
#           micro's init.lua reads the same, plus `AddRuntimeFile` (a plugin
#           with `RTPlugin`); its `import` names micro's own Go packages and
#           is left alone.
#   nano    `include` of anything but a path *directly* under
#           /usr/share/nano, which the nano package itself ships. A
#           subdirectory of it is not: /usr/share/nano/extra is a Debian
#           split that Fedora, Alpine, and macOS do not have, and a glob
#           matching nothing costs the whole rcfile - nano says "Mistakes in
#           '<rcfile>'" on the status bar and rings the bell. The path is
#           read as one word, so a trailing comment cannot fool the rule.
#   tmux    `source-file`/`source` of a path, and TPM (`@plugin`, a `run`
#           of tpm). Line-oriented, but a finding ending in `\` takes its
#           continuation lines with it.
#   screen  `source` of a file.
#   inputrc `$include` of anything but /etc/inputrc, the system file an
#           $INPUTRC stops readline reading on its own.
#   kak     `source` of anything but %val{runtime}'s (the target's own), and
#           the managers (plug.kak's `plug`, kak-bundle's `bundle`).
#   kdl     zellij's `layout_dir`/`theme_dir` (its own layouts/ and themes/
#           ride beside config.kdl) and a plugin `location="file:..."`.
#   omp     oh-my-posh's `extends` naming a local file; a URL or a theme name
#           resolves on the target. JSON has no comment, so there the value is
#           emptied, which oh-my-posh reads as no base; yaml and toml comment it.
#   elisp   `load`/`load-file`, `add-to-list 'load-path`, and the managers
#           (`package-initialize`, `use-package`, straight, elpaca). A bare
#           `require` is left alone: nearly every one names a built-in.
#   sh/fish `source`/`.` of anything but a path under $_HI_CONFIG_DIR or
#           $_HI_ROOT (which ride along), a process substitution, or - in a
#           framework's theme only (omz, omb, bash-it) - under that
#           framework's own tree ($ZSH, $OSH, $BASH_IT): hi sources a theme only once
#           _hi_prompt_fw has found the tree on the target, where every other
#           member runs with it unset. Also the zsh/fish managers' verbs
#           (zinit, zplug, antigen, fisher, ...). An extension is sh.
#
# A line directly under a `hi-allow` comment, in the file's own comment
# syntax, is neither reported nor touched; one under `hi-quiet` is still
# disabled, just not reported - a line you know no target has. A pair,
# `hi-allow-start` and `hi-allow-end` or `hi-quiet-start` and `hi-quiet-end`,
# decides every line inside it the same way. Each word pairs on its own, a
# start with the next end of its word, so an allow pair inside a quiet one
# keeps its lines. A start with no end below it, or with a second start of
# its word before one, decides nothing and is an `unclosed` row; an end with
# no start is ignored. Whether a start is closed is known only at the end of
# the file, so FNR == 1 reads the file through once with getline before the
# scan: blk holds the lines inside a closed pair, bad the starts with no end.
# mark() is the marker a comment line opens with, whole, so `hi-allow` and
# `hi-allow-start` are never read as each other.
#
# mode=report prints one `<member>|<line>|<kind>|<text>` row per finding and
# leaves the file alone; mode=fix also writes <file>.lint with each finding
# disabled - which strip.awk then drops, so a dropped line costs no wire bytes.
# vim and nano are line-oriented, so one line is the whole statement; lua,
# elisp, and kdl are not, so the comment runs to the end of the bracket-balanced
# expression the finding opened, or a `require("x").setup {` would leave its
# closing brace behind as a syntax error. sh and fish get neither: commenting
# a line can empty a `then`/`do` body, which does not parse, so only the verb
# and its file word become `:` (fish: `true`), and the rest of the line stays.
# `name` is the member, not FILENAME: doctor reads ~/.vimrc under its own name.
#
# bal() counts that depth blind to anything inside a quoted string, and takes
# ' as a string delimiter only where <end> says so (lua): in elisp it is the
# quote operator, and reading `'load-path` as an opening quote swallows the
# rest of the file.
# wlen() is the length of one shell word, quotes and $(...) nesting included.
# Nothing in the AWK body carries a `#` comment - strip.awk spares a heredoc
# body, so every one of them would ride the wire on every connect.
function _hi_lint_awk() {
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function mark(s) {
  if (!match(s, /^[ \t]*(#|"|--|;|\/\/)+[ \t]*hi-(allow|quiet)(-start|-end)?/)) return ""
  s = substr(s, RSTART, RLENGTH); sub(/.*hi-/, "", s)
  return s
}
function bal(s,   i, c, q, d) {
  d = 0; q = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") i++; else if (c == q) q = ""; continue }
    if (c == "\"" || (stmt == "()'" && c == "'")) { q = c; continue }
    if (c == "(" || c == "{" || c == "[") d++
    else if (c == ")" || c == "}" || c == "]") d--
  }
  return d
}
function wlen(s,   i, c, q, d) {
  q = ""; d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == q) q = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "\"") { q = (q == "" ? c : ""); continue }
    if (c == "'" && q == "") { q = c; continue }
    if (c == "(" || c == "{") d++
    else if (c == ")" || c == "}") { if (--d < 0) return i - 1 }
    else if (q == "" && d == 0 && c ~ /[ \t;&|]/) return i - 1
  }
  return length(s)
}
function shfix(s,   o, p, r, n, w) {
  o = ""; s = ";" s
  while (match(s, inc)) {
    p = substr(s, 1, RSTART + RLENGTH - 1); r = substr(s, RSTART + RLENGTH)
    n = wlen(r); w = substr(r, 1, n)
    if (w == "" || w ~ /^\\/ || (allow != "-" && w ~ allow) || w ~ /^[<=]?\(/) { o = o p; s = r; continue }
    sub(/[^;&|{() \t]+[ \t]+$/, "", p)
    o = o p noop; s = substr(r, n + 1)
  }
  return substr(o s, 2)
}
function kindof(s,   t) {
  if (lead != "-" && s ~ ("^[ \t]*" lead)) return ""
  if (plug != "-" && s ~ plug) { fixed = noop " " s; return "plugin" }
  if (inc == "-") return ""
  if (noop != "") { fixed = shfix(s); return (fixed != s) ? "include" : "" }
  t = s
  if (allow != "-") gsub(allow, "", t)
  if (t !~ inc) return ""
  if (blank && match(s, inc)) { t = substr(s, RSTART); sub(/:[ \t]*"[^"]*"/, ": \"\"", t); fixed = substr(s, 1, RSTART - 1) t }
  return "include"
}
FNR == 1 {
  close(out); out = FILENAME ".lint"; depth = allow_l = quiet = n = 0
  split("", blk); split("", bad); split("", from)
  while ((getline l < FILENAME) > 0) {
    n++; w = k = mark(l); sub(/-.*/, "", k)
    if (w ~ /-start/) { if (k in from) bad[from[k]] = 1; from[k] = n }
    else if (w ~ /-end/ && (k in from)) { for (i = from[k] + 1; i < n; i++) blk[k, i] = 1; delete from[k] }
  }
  close(FILENAME)
  for (k in from) bad[from[k]] = 1
  split(ENVIRON["_hi_dialect"], f, / [|] /)
  for (i = 6; i <= 8; i++) gsub(/\\t/, "\t", f[i])
  lead = f[2]; stmt = f[4]; noop = f[5]; plug = f[6]; inc = f[7]; allow = f[8]
  blank = (noop == "\"\""); if (noop == "comment" || blank) noop = ""
}
FNR in bad { printf "%s|%d|unclosed|%s\n", name, FNR, trim($0) }
depth > 0 {
  depth = (stmt == "\\") ? ($0 ~ /\\$/) : depth + bal($0)
  if (depth < 0) depth = 0
  if (mode == "fix") print lead " hi dropped: " $0 > out
  allow_l = quiet = 0
  next
}
{
  kind = (allow_l || (("allow", FNR) in blk)) ? "" : kindof($0)
  hush = quiet || (("quiet", FNR) in blk)
  w = mark($0); allow_l = (w == "allow"); quiet = (w == "quiet")
  if (kind == "") { if (mode == "fix") print > out; next }
  if (!hush) printf "%s|%d|%s|%s\n", name, FNR, kind, trim($0)
  if (mode == "fix") print ((noop != "" || blank) ? fixed : lead " hi dropped: " $0) > out
  if (stmt ~ /^\(\)/) { depth = bal($0); if (depth < 0) depth = 0 }
  if (stmt == "\\") depth = ($0 ~ /\\$/)
}
AWK
}

# _hi_include_lint - every finding in the overlay members that would actually
# ship, one row each (see _hi_lint_awk); a member with no dialect has none.
function _hi_include_lint() {
  local f src prog row
  prog="$(_hi_lint_awk)"
  while IFS= read -r f; do
    _hi_member_dialect "$f" row && _hi_overlay_src "$f" src &&
      _hi_dialect="$row" awk -v mode=report -v name="$f" "$prog" "$src"
  done < <(_hi_overlay_files)
  return 0
}

# _hi_overlay_files [member...] - the members (default $_HI_OVERLAY_FILES and
# the plugins files', $_HI_PLUGIN_FILES) that have a source, one per line;
# callers read it once and hand the list to _hi_overlay_tar. A trailing-/ entry lists its members as <dir>/<name>, in
# name order, only those _hi_dir_member_ok admits, over the overlay's
# directory and home's, each name once.
function _hi_overlay_files() {
  local f src home seen
  _hi_plugins_load
  [ $# -gt 0 ] || set -- "${_HI_OVERLAY_FILES[@]}" ${_HI_PLUGIN_FILES[@]+"${_HI_PLUGIN_FILES[@]}"}
  for f; do
    ! _hi_plugin_off "$f" || continue
    case "$f" in
    */)
      _hi_overlay_home "$f" home || home=""
      seen=" "
      for src in "$_HI_CONFIG_DIR/$f"* ${home:+"$home"*}; do
        case "$seen" in *" ${src##*/} "*) continue ;; esac
        [ -f "$src" ] && _hi_dir_member_ok "${src##*/}" && _hi_overlay_src "$f${src##*/}" >/dev/null &&
          seen="$seen${src##*/} " && printf '%s\n' "$f${src##*/}"
      done
      ;;
    *) _hi_overlay_src "$f" src && printf '%s\n' "$f" ;;
    esac
  done
  return 0
}

# Whether this client can gzip at all: gzip itself, or a tar that compresses
# in-process. Only libarchive's does - GNU's and OpenBSD's implement -z by
# exec'ing gzip off $PATH, so without it _hi_tar_gz's fallback fails too, and
# "no gzip" is a refusal rather than a bigger payload. Free where gzip is
# there (a builtin test); the probe is one fork on the boxes that need asking.
# It is _hi_tar_gz's own fallback invocation against a member certain to be
# there, so it cannot be right about a command line other than the real one -
# dash-style options and a real file, never /dev/null, which Git Bash's tar
# does not reliably stat. GLOSSARY: HI.38
function _hi_can_gzip() {
  command -v gzip >/dev/null 2>&1 && return 0
  tar -c -z -f - -C "$_HI_ROOT" hi.sh >/dev/null 2>&1
}

# Dash-style options everywhere tar runs: OpenBSD's tar reads every word
# after an old-style `cf <file>` as a member name, -C and -h included.
# tar's own arguments, gzip in a second process rather than `z`: bsdtar pads
# the compressed stream to 10240. GLOSSARY: HI.38 - that, PIPESTATUS, no-gzip.
# The -z arm is for a tar that compresses on its own; _hi_can_gzip is what
# keeps a client whose tar cannot from reaching it.
function _hi_tar_gz() {
  if ! command -v gzip >/dev/null 2>&1; then
    tar -c -z -f - "$@"
    return $?
  fi
  tar -c -f - "$@" | gzip -n
  local -a st=("${PIPESTATUS[@]}")
  [ "${st[0]}" = 0 ] || return "${st[0]}"
  return "${st[1]}"
}

# _hi_require_packer - tar, and gzip unless this tar compresses on its own:
# _hi_can_gzip first, so such a tar is not asked for a gzip it never runs
function _hi_require_packer() {
  _hi_require tar "to pack the payload" &&
    { _hi_can_gzip || _hi_require gzip "to pack the payload - this tar runs it for -z"; }
}

# What the comment-stripper is pointed at in the tree; an overlay member is
# stripped by its dialect's <strip>. GLOSSARY: HI.35
_HI_STRIP_NAMES=('*.sh' '*.zsh' '*.fish' flags '*/config/*')

# _hi_stage_tar <src-dir> <stage-subdir> - the shared body of the two stagers
# below: pull the members out of <src-dir> into a scratch stage, strip their
# comments, gzip what comes out. Reads $stage_in (members to pull), $stage_out
# (members to emit), $stage_excl (stage paths dropped once pulled - not tar's
# --exclude, which OpenBSD's has none of) and $stage_add
# (<member> <path> pairs copied in from outside <src-dir>) and $stage_lint (1
# for the overlay: the include scan runs over the stage, and each member is
# stripped by its dialect rather than $_HI_STRIP_NAMES) from
# its caller, the convention _hi_container_cleanup and _hi_remote_middle also
# use.
#
# A subshell, so cleanup is a trap and a ^C mid-build leaves nothing behind
# (GLOSSARY: HI.39). Prefixed locals (GLOSSARY: HI.04): `root` is
# _say_hi_container's name for the target's tree, and this runs inside it.
function _hi_stage_tar() {
  local stage f _hi_st_root _hi_st_i _hi_st_prog _hi_st_m _hi_st_d _hi_st_n
  local -a _hi_st_names=() _hi_st_strip=() _hi_st_add=(${stage_add[@]+"${stage_add[@]}"})
  local _hi_st_lint="${stage_lint:-0}"
  for f in "${_HI_STRIP_NAMES[@]}"; do
    ((${#_hi_st_names[@]})) && _hi_st_names+=(-o)
    case "$f" in */*) _hi_st_names+=(-path "$f") ;; *) _hi_st_names+=(-name "$f") ;; esac
  done
  (
    stage="$(mktemp -d -t hi.stage.XXXXXX)" || exit 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _hi_st_root="$stage${2:+/$2}"
    # a file, not `tar cf - | tar xf -`: the reader stops at the end-of-archive
    # marker while a GNU writer still has record padding to send, which is an
    # EPIPE and a "tar: Write error" on stderr. Skipped when every member is
    # a $stage_add one: GNU tar refuses to write an empty archive.
    if ((${#stage_in[@]})); then
      tar -c -h -f "$stage/in.tar" -C "$1" "${stage_in[@]}" || exit 1
      tar -x -f "$stage/in.tar" -C "$stage" || exit 1
      rm -rf "$stage/in.tar" ${stage_excl[@]+"${stage_excl[@]/#/$stage/}"}
    fi
    for ((_hi_st_i = 0; _hi_st_i < ${#_hi_st_add[@]}; _hi_st_i += 2)); do
      case "${_hi_st_add[_hi_st_i]}" in */*) mkdir -p "$_hi_st_root/${_hi_st_add[_hi_st_i]%/*}" || exit 1 ;; esac
      cp "${_hi_st_add[_hi_st_i + 1]}" "$_hi_st_root/${_hi_st_add[_hi_st_i]}" || exit 1
    done
    # fish's universal variables are everything `set -U` ever kept, secrets
    # included: tide's lines ride and nothing else
    if [ -f "$_hi_st_root/tide.vars" ]; then
      grep '^SETUVAR tide_' "$_hi_st_root/tide.vars" >"$stage/tide.keep" || true
      mv -f "$stage/tide.keep" "$_hi_st_root/tide.vars" || exit 1
    fi
    # ahead of the stripper, over the staged copies rather than the user's
    # own files: an include hi cannot carry goes out commented, or made inert
    # in a shell or JSON file, and the strip below drops a comment
    if [ "$_hi_st_lint" = 1 ]; then
      _hi_st_prog="$(_hi_lint_awk)"
      while IFS= read -r f; do
        _hi_st_m="${f#"$_hi_st_root"/}"
        _hi_member_dialect "$_hi_st_m" _hi_st_d || continue
        _hi_dialect="$_hi_st_d" awk -v mode=fix -v name="$_hi_st_m" "$_hi_st_prog" "$f" >/dev/null || exit 1
        # no .lint at all means an empty member: awk never ran a rule on it
        [ ! -f "$f.lint" ] || mv -f "$f.lint" "$f" || exit 1
        # <name> | <leader> | <strip> | ...: strip.awk's d= and c= per file
        _hi_st_n="${_hi_st_d%% | *}" _hi_st_d="${_hi_st_d#* | }"
        case "${_hi_st_d#* | }" in 1' | '*) _hi_st_strip+=("d=$_hi_st_n" "c=${_hi_st_d%% | *}" "$f") ;; esac
      done < <(find "$_hi_st_root" -type f ! -name '*.lint')
    fi
    _hi_strip_awk >"$stage/strip.awk"
    # one awk over every file (GLOSSARY: HI.35); strip.awk sits at $stage and
    # matches no name above, so the stripper never eats its own script. It
    # buffers each file and writes it back over itself once the batch has been
    # read, so there is no `<file>.strip` left to rename: that rename was one
    # `mv` a file - 40 of them in a `hi --doctor`, which stages twice, and the
    # largest external cost it had - and renaming over a file still held open
    # is what broke the Windows runners. Writing in place also leaves every
    # mode alone, so hi.sh stays 0755 for the relay with nothing to restore.
    if [ "$_hi_st_lint" = 1 ]; then
      ((${#_hi_st_strip[@]} == 0)) || awk -f "$stage/strip.awk" "${_hi_st_strip[@]}" || exit 1
    else
      find "$_hi_st_root" -type f \( "${_hi_st_names[@]}" \) -exec awk -f "$stage/strip.awk" {} + || exit 1
    fi
    # the overlay's generated member, last: hi wrote it, so there is nothing
    # in it to scan or strip
    [ -z "${stage_wiring:-}" ] || printf '%s' "$stage_wiring" >"$_hi_st_root/wiring.sh" || exit 1
    _hi_tar_gz -C "$stage" "${stage_out[@]}"
  )
}

# _hi_overlay_tar [file...] - the overlay archive over the given members, or
# over _hi_overlay_files when called bare; nothing when there are none.
# Comment-stripped through a staging copy like the payload (GLOSSARY: HI.35):
# the overlay is the user's prose-heavy files and every byte rides each
# connect. The first tar's -h resolves a dotfile manager's symlinks into
# content; the final tar names the members, so strip.awk never ships. A
# member _hi_overlay_src packs from elsewhere is copied in under its own name.
# wiring.sh rides beside the members it has a line for (GLOSSARY: HI.62).
function _hi_overlay_tar() {
  local -a present=("$@")
  [ $# -gt 0 ] || _hi_read_lines present < <(_hi_overlay_files)
  ((${#present[@]})) || return 0
  local -a stage_in=() stage_out=("${present[@]}") stage_excl=() stage_add=()
  local stage_lint=1 stage_wiring=""
  local f src
  _hi_overlay_wiring stage_wiring "${present[@]}"
  [ -z "$stage_wiring" ] || stage_out+=(wiring.sh)
  for f in "${present[@]}"; do
    if _hi_overlay_src "$f" src && [ "$src" != "$_HI_CONFIG_DIR/$f" ]; then
      stage_add+=("$f" "$src")
    else
      stage_in+=("$f")
    fi
  done
  _hi_stage_tar "$_HI_CONFIG_DIR" ""
}

# _hi_cksum <value> [outvar] - cksum's checksum field alone; `${k%% *}`
# rather than a `cut`, which would be a second process per key, three keys a
# connect.
function _hi_cksum() {
  local _hi_ck
  _hi_ck="$(printf '%s' "$1" | cksum)"
  _hi_out "${2:-}" "${_hi_ck%% *}"
}

# What changes an overlay tar without touching any member's mtime: the member
# list itself, and the wiring written from it, which a newer hi.sh can change
# under the same list. Cksummed, not spelled out, to keep the cache filename
# short.
function _hi_overlay_cache_key() {
  local _hi_ok_w
  _hi_overlay_wiring _hi_ok_w "$@"
  _hi_cksum "$*$_hi_ok_w"
}

# _hi_cached <outvar> <tag> <key> <builder> <watch...> - one cache, two
# callers. Rebuilt when missing, when any <watch> or $cache_also path (from its
# caller) is newer than it - a symlink's target counts, so a dotfile manager's
# edit does - or when _HI_PAYLOAD_CACHE=0; written under a temp name and mv'd into place, so a
# concurrent reader sees the old file or the new one and never a half-written
# archive. rc 1 means "no cache, build it yourself".
#
# Prefixed locals throughout (GLOSSARY: HI.04): a plain `cache` would shadow a
# caller's outvar and the printf -v would never leave this function.
function _hi_cached() {
  local _hi_c_outvar="$1" _hi_c_tag="$2" _hi_c_key="$3" _hi_c_pre="$4" _hi_c_build="$5"
  shift 5
  local _hi_c_dir _hi_c_cache _hi_c_tmp
  local -a _hi_c_watch=("${@/#/$_hi_c_pre}" ${cache_also[@]+"${cache_also[@]}"})
  [ "${_HI_PAYLOAD_CACHE:-1}" != 0 ] || return 1
  _hi_runtime_dir _hi_c_dir
  [ -n "$_hi_c_dir" ] || return 1
  _hi_c_cache="$_hi_c_dir/hi.$_hi_c_tag.$_hi_c_key"
  if [ -f "$_hi_c_cache" ] &&
    [ -z "$(find -H "${_hi_c_watch[@]}" -newer "$_hi_c_cache" -print 2>/dev/null)" ]; then
    printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
    return 0
  fi
  # mktemp, not `.$$`: every subshell of one shell shares its $$
  _hi_c_tmp="$(mktemp "$_hi_c_cache.XXXXXX")" || return 1
  "$_hi_c_build" "$@" >"$_hi_c_tmp" || {
    rm -f "$_hi_c_tmp"
    return 1
  }
  mv -f "$_hi_c_tmp" "$_hi_c_cache"
  printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
}

# _hi_cached over exactly these overlay members, keyed on the list. Fails when
# there is no member at all, on top of _hi_cached's own refusals. A member
# _hi_overlay_src packs from elsewhere is watched there and keyed by its path,
# so pointing the tool at another file never serves the old one's cache.
function _hi_overlay_cached() {
  local _hi_oc_outvar="$1" _hi_oc_f _hi_oc_src
  shift
  (($#)) || return 1
  local -a cache_also=()
  for _hi_oc_f; do
    _hi_overlay_src "$_hi_oc_f" _hi_oc_src && [ "$_hi_oc_src" != "$_HI_CONFIG_DIR/$_hi_oc_f" ] &&
      cache_also+=("$_hi_oc_src")
  done
  _hi_cached "$_hi_oc_outvar" overlay "$(_hi_overlay_cache_key "$@" ${cache_also[@]+"${cache_also[@]}"})" \
    "$_HI_CONFIG_DIR/" _hi_overlay_tar "$@"
}

# The tree twin, against the ~70-130ms _hi_payload_tar otherwise costs on
# every connect. _hi_payload_tar takes no arguments - the roster is its own -
# but is handed one anyway: that list is what _hi_cached watches for staleness.
# Keyed on the tree's own path and the caller's $payload_excl: two trees on
# one machine share the runtime dir, and staleness is only "no file newer
# than the cache", so a tree keyed by name alone was served the other tree's
# payload; and a tree cut for one overlay is never served beside another.
function _hi_payload_cached() {
  local _hi_pc_key
  _hi_pc_key="tree.$(_hi_cksum "$_HI_HOME|${payload_excl[*]-}")"
  _hi_cached "$1" payload "$_hi_pc_key" \
    "$_HI_HOME/say-hi/" _hi_payload_tar "${_HI_PAYLOAD[@]}"
}

# The overlay tar on stdout: the cache when warm and clean, a fresh build
# otherwise. An if/else and not `cat && || tar`, which would emit both halves
# if the cat died partway through. Prefixed local: GLOSSARY: HI.04.
function _hi_overlay_bytes() {
  local _hi_ob_cache=""
  if _hi_overlay_cached _hi_ob_cache "$@"; then
    cat "$_hi_ob_cache"
  else
    _hi_overlay_tar "$@"
  fi
}

# _hi_overlay_bytes armored into the line that unpacks it on the target.
function _hi_overlay_stream() {
  _hi_overlay_bytes "$@" | _hi_armored_line '|' 'tar -x -m -z -f - -C "$_HI_ROOT/config"'
}

# The comment stripper every payload file goes through: their prose headers
# are for the installed copy a user reads, not the wire. A comment line starts
# with `#`, or with c=, an overlay member's dialect <leader>, set on the
# command line ahead of its file with its d=, and blank lines and indentation
# go with them - no dialect with <strip> 1 reads either, and the indentation
# alone is 3% of the payload - except on a line continuing a `word\`, where it
# is the only separator. A nanorc's dropped syntax include and extendsyntax
# ride as comments, for load.sh's _hi_nano_fallback to find.
# GLOSSARY: HI.35 - the rules, and why their order is the argument
function _hi_strip_awk() {
  cat <<'AWK'
FNR == 1 { out = FILENAME; seen[out] = 1; buf[out] = ""; tag = ""; dash = cont = 0; lc = (c != "" && c != "#") ? "^[ \t]*" c : ""; nano = (d == "nano") }
FNR == 1 && /^#!/ { buf[out] = buf[out] $0 "\n"; next }
nano && /^# hi dropped: (include .*\.nanorc|extendsyntax )/ { buf[out] = buf[out] $0 "\n"; next }
lc != "" && $0 ~ lc { next }
tag != "" {
  line = $0
  if (dash) sub(/^\t+/, "", line)
  if (line == tag) tag = ""
  buf[out] = buf[out] $0 "\n"
  next
}
/^[ \t]*#/ { next }
/^[ \t]*$/ { next }
{
  if (!cont) sub(/^[ \t]+/, "")
  cont = /[^ \t\\]\\$/
  s = $0
  while (match(s, /<<-?[ \t]*("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|[A-Za-z_][A-Za-z0-9_]*)/)) {
    m = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    dash = (m ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", m)
    sub(/^["']/, "", m)
    sub(/["']$/, "", m)
    tag = m
  }
  buf[out] = buf[out] $0 "\n"
}
END {
  for (f in seen) {
    printf "%s", buf[f] > (f)
    close(f)
  }
}
AWK
}

# _hi_require <tool> <why> - the tool, or a refusal that names it: the
# difference between a session that says what is missing and one that prints
# line numbers from a stripped-down client.
function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_fail "hi: requires $1 on [$(_hi_hostname)] $2, but it is not installed. Aborting..."
  return 1
}

# <msg> in red on stderr, and a mark that hi already said its piece: _hi's
# end-of-connect report reads $_HI_SAID so a failure is never announced twice.
function _hi_fail() {
  _hi_cecho "$1" "$BRRED" >&2
  _HI_SAID=1
}

# _hi_die <msg> - "hi: <msg>" in red on stderr, then exit 1: a refusal made
# before anything ran.
function _hi_die() {
  _hi_cecho "hi: $1" "$RED" >&2
  exit 1
}

# _hi_payload_excl <member...> - the tree files those overlay members shadow
# (GLOSSARY: HI.41), into the caller's $payload_excl: one copy on the wire,
# not the default beside the file that beats it. Only a member that ships
# counts, so a file still under a $_HI_OVERLAY_RENAMES name cuts nothing.
# With the header off the target never draws one, so header.sh and the
# package list it checks stay home too. A framework's prompt loader,
# common/fw_<name>.<ext>, rides only to a target handed that framework
# (_hi_prompt_list): the shell there picks from that list alone. GLOSSARY: HI.32
function _hi_payload_excl() {
  local f s
  payload_excl=()
  ! _hi_toggle_on _HI_DISABLE_HEADER || payload_excl=(say-hi/common/header.sh say-hi/config/packages)
  for f; do
    f="${f%%/*}"
    case "$_HI_OVERLAY_SHADOWS${payload_excl[*]-} " in
    *" say-hi/config/$f "*) ;;
    *" $f "*) payload_excl+=("say-hi/config/$f") ;;
    esac
  done
  _hi_prompt_list >/dev/null
  for f in "${_HI_PROMPT_TABLE[@]}"; do
    case "$f" in *'|fw|'*) ;; *) continue ;; esac
    case " $_HI_PROMPT_LIST_MEMO " in *" ${f%%|*} "*) continue ;; esac
    s="${f#*|}" s="${s%%|*}"
    payload_excl+=("say-hi/common/fw_${f%%|*}.${s/bash/sh}")
  done
}

# The tree, comment-stripped through a staging copy; both size budgets
# measure this. GLOSSARY: HI.39 + HI.35. Whole unless the caller holds a
# $payload_excl - a connect that ships the overlay too; _hi_wire_bytes has
# none, and measures the stock tree.
function _hi_payload_tar() {
  local -a stage_in stage_out=(say-hi) stage_excl=(${payload_excl[@]+"${payload_excl[@]}"})
  stage_in=("${_HI_PAYLOAD[@]/#/say-hi/}")
  _hi_stage_tar "$_HI_HOME" say-hi
}

# The tree twin of _hi_overlay_stream: the armored payload tar, through the
# cache when it is warm and clean.
function _hi_payload_stream() {
  local cache=""
  if _hi_payload_cached cache; then
    $_HI_ARMOR <"$cache"
  else
    _hi_payload_tar | $_HI_ARMOR
  fi
}

# The walker's rc 2 means "known host, no tag"; only 1 means not in the config.
# Literal entries only, or a `Host *` block would claim every container,
# allocation, and pod name for ssh. Unmemoized: the memo holds the
# wildcard-aware answer the tag colors want.
function _hi_is_ssh_host() {
  local rc=0
  _HI_SSH_LITERAL_ONLY=1 _hi_ssh_host_tag_walk "$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 1 ]
}

# _hi_probe_is <want> <cli> <args...> - the shape every liveness predicate
# below shares, so the roster cannot grow a member that forgets the
# `command -v` guard or the muted stderr. core.sh's _hi_probe bounds the
# daemon round trip: _hi_resolve_backend waits on every row, so one downed
# daemon would otherwise stall every connect with no cap.
function _hi_probe_is() {
  local want="$1"
  shift
  command -v "$1" >/dev/null 2>&1 &&
    [ "$(_hi_probe "$@" 2>/dev/null)" = "$want" ]
}

function _hi_is_container_running() {
  _hi_probe_is true "$1" container inspect -f '{{.State.Running}}' "$2"
}

# The predicate every member of the docker-compatible family shares
# (GLOSSARY: HI.51). The roster wraps it once per member, since a predicate
# column is one word run with the target as its only argument.
function _hi_is_family_container() {
  local _hi_fc
  _hi_container_target "$1" "$2" _hi_fc
}

# _hi_container_target <cli> <name> <outvar> - the container to exec into:
# <name> itself when it is running, else whatever the CLI's alias mechanism
# resolves it to; rc 1 when neither answers. The one place for "docker and
# podman, uniquely, resolve a compose service name" - the other two of the
# family are left out on purpose, see _hi_compose_container.
# GLOSSARY: HI.43, HI.51.
function _hi_container_target() {
  if _hi_is_container_running "$1" "$2"; then
    printf -v "$3" '%s' "$2"
    return 0
  fi
  local _hi_ct_resolved
  case "$1" in docker | podman) ;; *) return 1 ;; esac
  _hi_ct_resolved="$(_hi_compose_container "$1" "$2")" || return 1
  printf -v "$3" '%s' "$_hi_ct_resolved"
}

# _hi_compose_container <cli> <service> - the one running container behind a
# compose service name, or failure; never a guess. GLOSSARY: HI.43
#
# docker and podman only, and that is the whole family that qualifies: both
# take the `label=` filter and render `{{.Label "..."}}`, which is what
# common/targets.sh needs to offer the service name on TAB in the first place.
# nerdctl and finch are left out because nobody has checked them, and a
# template one of them rejects would fail the lookup rather than decline it.
function _hi_compose_container() {
  command -v "$1" >/dev/null 2>&1 || return 1
  local matches
  matches="$(_hi_probe "$1" ps --filter "label=com.docker.compose.service=$2" --format '{{.Names}}' 2>/dev/null)"
  [ -n "$matches" ] || return 1
  # one line and not none - a `wc -l` here was two processes for a glob test
  case "$matches" in *$'\n'*) return 1 ;; esac
  printf '%s\n' "$matches"
}

# _hi_outer / _hi_inner <target> [outvar] - the where and the what of
# `pod/container` and `alloc/task`; docker and podman names are taken whole.
# GLOSSARY: HI.43. [outvar] because the bodies are pure parameter expansion,
# so a $( ) would fork for a value the shell already has (GLOSSARY: HI.05).
function _hi_outer() { _hi_out "${2:-}" "${1%%/*}"; }
function _hi_inner() {
  case "$1" in
  */*) _hi_out "${2:-}" "${1#*/}" ;;
  *) _hi_out "${2:-}" "" ;;
  esac
}

function _hi_is_nomad_alloc() {
  _hi_probe_is running nomad alloc status -t '{{.ClientStatus}}' "${1%%/*}"
}

# _hi_kube_split <target> - `[[context:]namespace:]pod[/container]` into
# _HI_K_POD and the kubectl arguments the prefixes add. GLOSSARY: HI.43
function _hi_kube_split() {
  local outer="${1%%/*}"
  _HI_K_ARGS=()
  case "$outer" in *:*:*)
    _HI_K_ARGS+=(--context "${outer%%:*}")
    outer="${outer#*:}"
    ;;
  esac
  case "$outer" in *:*)
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    outer="${outer#*:}"
    ;;
  esac
  _HI_K_POD="$outer"
}

# resolves on the pod half; kubectl checks the container half at session time
function _hi_is_k8s_pod() {
  _hi_kube_split "$1"
  _hi_probe_is Running kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} \
    get pod "$_HI_K_POD" -o jsonpath='{.status.phase}' --request-timeout="${_HI_PROBE_TIMEOUT:-2}s"
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>". One list
# for _hi's dispatch and scripts/doctor.sh's report. The family rows are the
# docker-compatible CLIs, every one of them, each with a generated one-word
# predicate: $_HI_CONTAINER_CLIS (core.sh), which common/targets.sh cannot
# read and spells again on its own - the drift suite pins the two together.
# GLOSSARY: HI.51
_HI_BACKENDS=()
for _hi_cli in $_HI_CONTAINER_CLIS; do
  eval "function _hi_is_${_hi_cli}_container() { _hi_is_family_container $_hi_cli \"\$1\"; }"
  _HI_BACKENDS+=("$_hi_cli|$_hi_cli container|$_hi_cli ps -q|_hi_is_${_hi_cli}_container")
done
unset _hi_cli
_HI_BACKENDS+=(
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# _hi_use_backend <backend> [chosen] - the arm name for `--use <backend>`, or
# a message and failure: "ssh" or a roster name, never a bare word, since a
# typo would force an arm nothing can run. Read off the roster, so a backend
# added there is reachable with no second spelling anywhere. [chosen] is the
# arm an earlier --use picked: a second naming another is refused, not
# resolved last-wins - the one spelling of that refusal, for _hi_parse and
# doctor both.
function _hi_use_backend() {
  local row names="ssh" arm=""
  [ "$1" = ssh ] && arm=ssh
  for row in "${_HI_BACKENDS[@]}"; do
    [ "$1" = "${row%%|*}" ] && arm="$1"
    names="$names ${row%%|*}"
  done
  if [ -z "$arm" ]; then
    _hi_cecho "${_HI_ARGV0:-hi}: --use wants one of: $names" "$RED" >&2
    return 1
  elif [ -n "${2:-}" ] && [ "$2" != "$arm" ]; then
    _hi_cecho "${_HI_ARGV0:-hi}: --use $1 and --use $2 both name a backend; pick one" "$RED" >&2
    return 1
  fi
  printf '%s' "$arm"
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: HI.18 - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1" q
  shift
  _hi_shquote q "$script"
  ssh "$@" ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN" "sh -c $q"
}

# _hi_ctl_open <run-persist-secs> <run|shared> [ssh-opts...] - a ControlMaster
# socket into the caller's ctl_dir/ctl_path/ctl_opts/ctl_shared, so the
# boot probe and the session multiplex one authentication. _hi_ctl_close
# tears it down, except a shared one, which outlives the call on purpose.
#
# `run` is always a fresh socket, *inside* a `mktemp -d` (0700) rather than at
# a `mktemp -u` name: that only promises the name was free when printed, and
# `ControlMaster=auto` joins an existing socket rather than refusing it.
# doctor.sh asks for `run` - a diagnostic should leave no socket behind.
#
# `shared` tries a stable per-(target, ssh-args) socket under _hi_runtime_dir,
# so a second `hi <target>` within $_HI_CTL_PERSIST seconds skips a fresh key
# exchange - the biggest cost `hi` pays over plain ssh. _HI_CTL_PERSIST=0 or a
# runtime directory hi cannot vouch for both fall back to `run`.
#
# "/s" and "hi.ctl.<key>", never a second random component or a 40-hex `%C`:
# ControlPath goes into a sockaddr_un capped near 104 bytes, and macOS's
# per-user $TMPDIR already spends ~50. <key> is a cksum of $DOMAIN and
# $SSHARGS, so a `-p`/`-l`/`-o` naming a different connection to the same
# target gets its own socket rather than joining the wrong one.
function _hi_ctl_open() {
  local persist="$1" scope="$2" dir key words
  shift 2
  ctl_dir=""
  ctl_path=""
  ctl_opts=()
  ctl_shared=0
  # No multiplexing from an MSYS/Cygwin client: ssh passes the session's file
  # descriptors to the master over SCM_RIGHTS, which that runtime does not
  # carry, so the master is reached and *then* the transfer fails and the
  # connection dies rather than degrading. Answered from $OSTYPE (bash sets it
  # at build time, "msys" for both MSYS2 and Git Bash) rather than a `uname`
  # fork. Lands in the same state as a host with nowhere to put a socket.
  case "${OSTYPE:-}" in
  msys* | cygwin*)
    ctl_opts+=("$@")
    return 0
    ;;
  esac
  if [ "$scope" = shared ] && [ "${_HI_CTL_PERSIST:-60}" != 0 ]; then
    _hi_runtime_dir dir
    if [ -n "$dir" ]; then
      # printf -v and outvars, not $( ): the joined words are a builtin away,
      # and cksum itself is the only fork this key needs to cost
      printf -v words '%s\x1f' "$DOMAIN" ${SSHARGS[@]+"${SSHARGS[@]}"}
      _hi_cksum "$words" key
      ctl_path="$dir/hi.ctl.$key"
      ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=${_HI_CTL_PERSIST:-60}")
      ctl_shared=1
    fi
  fi
  if [ "$ctl_shared" != 1 ]; then
    ctl_dir="$(mktemp -d -t hi.cm.XXXXXX 2>/dev/null)" || ctl_dir=""
    if [ -n "$ctl_dir" ]; then
      ctl_path="$ctl_dir/s"
      ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=$persist")
    fi
  fi
  ctl_opts+=("$@")
}

function _hi_ctl_close() {
  [ "${ctl_shared:-0}" = 1 ] && return 0
  [ -n "$ctl_path" ] && ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1
  [ -n "$ctl_dir" ] && rm -rf "$ctl_dir" 2>/dev/null
  return 0
}

# The sh script the first ssh call runs: check for base64 (or openssl), make a scratch
# directory, take the bootloader off stdin, say where it went. Its own
# function so a suite can assert on it with no ssh hop.
#
# Every path in it is the *target's*, and nothing interpolates a client-side
# value: a client `mktemp -u -t` would name a path in the *client's* $TMPDIR
# and ask the target to mkdir it - fine while both are /tmp, and a silent fall
# through to the PowerShell branch the moment the client has $TMPDIR set.
#
# The two failures say which in the exit status (64 no armor, 65 no scratch
# directory) so _say_hi can name the reason. They are `if`s rather than
# `|| exit N` because Windows OpenSSH hands the command to cmd.exe, which
# cannot run `sh` but does honour `||` - so `|| exit 64` would have cmd itself
# exit 64 and hi would call a Windows box "a host with no base64".
# GLOSSARY: HI.19
function _hi_boot_probe() {
  cat <<'PROBE'
if ! command -v base64 >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then exit 64; fi
if ! d=$(mktemp -d -t hi.boot.XXXXXX); then exit 65; fi
cat > "$d/bootloader" || exit 1
printf "\nHIBOOT:%s\n" "$d"
PROBE
}

# _hi_boot_why <status> <output> - why the boot probe left no scratch dir, as
# a line naming $DOMAIN, or nothing. Four causes, told apart by the write's
# status and what came back (GLOSSARY: HI.19): the probe's own two codes; a
# path hi refused; and a *forced command* (sshd's `ForceCommand`, or a
# `command=` on the key), which runs its own program whatever the client
# asked. A forced command that exits 0 or prints anything cannot be a host
# with no shell, since cmd.exe and PowerShell both fail `sh` non-zero and say
# so on stderr. One that exits non-zero printing nothing is indistinguishable
# from a missing `sh`: nothing here, and the caller's PowerShell notice.
function _hi_boot_why() {
  case "$2" in *HIBOOT:*)
    printf '%s\n' "[$DOMAIN] named a scratch directory hi will not use"
    return 0
    ;;
  esac
  case "$1:${2:+out}" in
  64:*) printf '%s\n' "no base64 or openssl on [$DOMAIN]" ;;
  65:*) printf '%s\n' "no writable temp directory on [$DOMAIN]" ;;
  0:* | *:out) printf '%s\n' "a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
  esac
}

# _hi_safe_path <path> <bracket-class> - <path> when it is absolute and built
# only from the class's characters, nothing otherwise: the gate on every
# scratch directory a target names. Those reach
# commands run back on that target, `rm -rf` among them, so anything that is
# not a path mktemp just made is refused. The class varies per caller, the
# rule does not. An empty answer is the verdict, so this always returns 0.
function _hi_safe_path() {
  case "$1" in '' | [!/]* | *[!$2]*) return 0 ;; esac
  printf '%s' "$1"
}

# GLOSSARY: HI.15
function _hi_bootloader() {
  local clear=""
  # The connect marker every arm prints on the way in has no newline and is
  # normally overwritten by the header's banner. A command replaces the
  # header, so it clears the marker itself - a line-clear on a tty, a newline
  # on a pipe - or its first line of output lands glued to it.
  [ -n "${CMDARG:-}" ] &&
    clear=$'[ -t 2 ] && printf \'\\r\\033[K\' >&2 || printf \'\\n\' >&2\n'
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${clear}${CMDARG:-load}
EOF
}

# The no-bash target's rc: every line valid in sh, zsh *and* fish at once.
# --aliases-only <dir> is the container fallback's shape (aliases.sh alone).
# GLOSSARY: HI.20 - the three-shell subset, and why each line is there
function _hi_fallback_rc() {
  local t aliases_dir=""
  [ "${1:-}" = --aliases-only ] && aliases_dir="$2"
  printf 'export _HI_REMOTE_SESSION=1\n'
  # an unset toggle under `set -u` breaks a bash-less target
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  # the alias opt-ins as this client has them: no settings.sh reaches this tier
  for t in _HI_TOOL_ALIASES _HI_SUDO_ALIAS; do
    if [ "${!t:-0}" = 1 ]; then printf 'export %s=1\n' "$t"; else printf 'export %s=0\n' "$t"; fi
  done
  if [ -n "$aliases_dir" ]; then
    # the client verdicts the ssh preamble would have exported ride the rc here
    _hi_client_verdicts 'export %s=%s\n'
    printf '. %s/aliases.sh 2>/dev/null\n' "$aliases_dir"
  else
    printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
    printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
    printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/common/aliases.sh 2>/dev/null\n'
  fi
  # no $CMDARG here: the two helpers below hand it to each shell the way that
  # shell honours it (GLOSSARY: HI.23)
  return 0
}

# The `hi <target> <cmd>` line, armored like the rc and appended to <file-word>
# on the target. For sh and zsh, which read their rc to the end; fish takes the
# flag below.
function _hi_command_append() {
  [ -n "${CMDARG:-}" ] || return 0
  printf '%s\n' "$CMDARG" | _hi_armored_line '>>' "$1"
}

# ` -c '<cmd>'` for the fish arm: fish runs -c after -C and exits from it
# (GLOSSARY: HI.23). Quoted for the target's sh.
function _hi_command_fish_flag() {
  local q
  [ -n "${CMDARG:-}" ] || return 0
  _hi_shquote q "$CMDARG"
  printf ' -c %s' "$q"
}

# The fallback-shell probe both transports interpolate: one sh loop over
# $_HI_SHELL_LADDER running $1 at the first shell found ($_hi_s names the hit).
function _hi_ladder_probe() {
  printf 'for _hi_s in %s; do command -v "$_hi_s" >/dev/null 2>&1 && { %s; break; }; done' \
    "$_HI_SHELL_LADDER" "$1"
}

# A prompt for the bash-less tiers (sh, ash, dash), baked on the client.
# GLOSSARY: HI.21 - why baked
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # the host lands *inside* PS1's double quotes: escape what would end them
  host="${host//\\/\\\\}"
  host="${host//\$/\\\$}"
  host="${host//\`/\\\`}"
  host="${host//\"/\\\"}"
  # the outvar forms (GLOSSARY: HI.05): through $( ) each memo would be filled
  # in a subshell and die there, and _hi_remote_suffix builds this on every
  # connect, not just a bash-less one
  local user_esc ce pe
  _hi_user_escape user_esc
  _hi_prompt_end BASH pe
  _hi_target_color >/dev/null
  _hi_color_escape_var ce "$_HI_TARGET_COLOR_MEMO"
  printf -v ce '%b' "$ce" # the _var form leaves `\e` literal
  printf -v nc '%b' "$NC"
  local cwd_esc
  printf -v cwd_esc '%b' "$BRBLUE"
  # A line editor counts every byte it is not told to skip, so each escape
  # sits between $_hi_a and $_hi_z: bash's \[ \] for BusyBox ash, a delimiter
  # PS1's first two bytes declare for mksh ($_hi_p), nothing for dash, which
  # has no line editing to mislead. The first line picks - one assignment per
  # statement where one reads another, since FreeBSD's sh expands every word of
  # a command before assigning any - and the second is PS1, its cwd left as
  # ${PWD} for the shell to expand at each draw.
  # shellcheck disable=SC2016 # every $ here is the target shell's
  printf '%s\n' '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}"); _hi_a= _hi_z= _hi_p=; [ -z "${BB_ASH_VERSION-}" ] || { _hi_a='"'"'\['"'"' _hi_z='"'"'\]'"'"'; }; case "${KSH_VERSION-}" in *MIRBSD*) _hi_a=$(printf '"'"'\001'"'"'); _hi_z=$_hi_a; _hi_p=$_hi_a$(printf '"'"'\r'"'"') ;; esac'
  printf 'PS1="${_hi_p} ${_hi_a}%s${_hi_z}${_hi_u}${_hi_a}%s${_hi_z}@${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} ${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} %s "\n' \
    "$user_esc" "$nc" "$ce" "$host" "$nc" "$cwd_esc" '\${PWD}' "$nc" "$pe"
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it, through the same payload cache - a warm
# one stages nothing. GLOSSARY: HI.44 - why not a sum of streams
function _hi_wire_bytes() {
  local overlay_line="" bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_stream)"
  _hi_remote_script script
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
}

function _hi_file_bytes() {
  # ${n// /} rather than a `tr` fork to strip BSD wc's padding
  local n
  n="$(wc -c <"$1")"
  printf '%s' "${n// /}"
}

function _hi_human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B K M G", unit, " ")
    i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    if (i == 1) printf "%dB", b
    else if (b < 10) printf "%.1f%s", b, unit[i]
    else printf "%.0f%s", b, unit[i]
  }'
}

# core.sh's ladder, plus the diagnostic the header's cell has no room for
function _hi_version() {
  local v
  v="$(_hi_release_or_describe)"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
  elif [ -d "$_HI_ROOT/.git" ]; then
    printf 'unknown (git would not answer)\n'
  else
    printf 'unknown (no stamp, no git)\n'
  fi
}

# What `hi --version` prints: the version, then which kind of tree answered
# and where - the next thing a bug report asks. _hi_version alone rides the
# wire as _HI_RELEASE.
function _hi_version_line() {
  local kind
  if [ -d "$_HI_ROOT/.git" ]; then
    kind=checkout
  elif [ -n "${_HI_RELEASE:-}" ]; then
    kind=package
  else
    kind=tree
  fi
  printf '%s (%s at %s)\n' "$(_hi_version)" "$kind" "$_HI_ROOT"
}

# _hi_session_env's pairs through <printf-format>, name then value already
# quoted (`%s=%s`, never `%s="%s"`); one loop for both transports.
# GLOSSARY: HI.40
function _hi_env_each() {
  local n v q
  while IFS=$'\t' read -r n v; do
    _hi_shquote q "$v"
    # shellcheck disable=SC2059 # the format is ours, not user data
    printf "$1" "$n" "$q"
  done < <(_hi_session_env)
}

# _hi_remote_script <outvar> - the script _say_hi sends and _hi_wire_bytes
# measures: preamble, middle, suffix. One assembly, so the two agree (HI.44).
function _hi_remote_script() {
  printf -v "$1" '%s\n%s\n%s' "$(_hi_remote_preamble)" "$(_hi_remote_middle)" "$(_hi_remote_suffix)"
}

# The bit both _say_hi branches need first. Everything expands on the client:
# no backtick or unescaped $( ) below, not even in a comment. The TERM case
# swaps an unknown TERM for xterm-256color when the target's terminfo has no
# entry for it (GLOSSARY: HI.22) - said here and not in the heredoc, whose
# every byte rides the wire on every connect.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
$(_hi_env_each '      export %s=%s\n')
      case "\$TERM" in
      xterm | xterm-256color | xterm-color | screen | screen-256color | tmux | tmux-256color | linux | vt100 | vt220 | dumb | '') ;;
      *)
        _hi_ti_ok=""
        _hi_ti_c=\${TERM%"\${TERM#?}"}
        _hi_ti_x=\$(printf '%x' "'\$_hi_ti_c" 2>/dev/null)
        for _hi_ti_d in "\${TERMINFO:-}" "\$HOME/.terminfo" /etc/terminfo /lib/terminfo /usr/share/terminfo; do
          [ -n "\$_hi_ti_d" ] || continue
          if [ -e "\$_hi_ti_d/\$_hi_ti_c/\$TERM" ] || [ -e "\$_hi_ti_d/\$_hi_ti_x/\$TERM" ]; then
            _hi_ti_ok=1
            break
          fi
        done
        [ -n "\$_hi_ti_ok" ] || export TERM=xterm-256color
        ;;
      esac
REMOTE
}

# hi's yellow and the reset as real escape bytes, derived from the palette
# with no caller input rather than read out of _say_hi's scope, which
# _hi_wire_bytes never fills - the README's wire figure would miss them.
function _hi_esc_pair() {
  printf -v "$1" '%b' "$YELLOW"
  printf -v "$2" '%b' "$NC"
}

# What _say_hi needs once its setup is done: report copy time,
# then hand off to bash or to the best fallback shell. Expects \$_hi_rc_dir to
# point at wherever hi.bashrc/.hi_fallback_rc lives. GLOSSARY: HI.23 - the flag
# order and fish's -C arm. The `*)` arm (sh/dash/ash) appends the prompt there
# rather than in the shared rc, which also feeds fish (no PS1) and zsh.
function _hi_remote_suffix() {
  # single-quoted here so the fallback line can name the target without the
  # session carrying a variable for it
  local target_q _hi_esc _hi_nc
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
      else
        _hi_fallback=sh
        $(_hi_ladder_probe '_hi_fallback="$_hi_s"')
        printf '%s no bash on [%s], dropping into plain %s w/ aliases only %s\n' "$_hi_esc" $target_q "\$_hi_fallback" "$_hi_nc" >&2
        $(_hi_fallback_rc | _hi_armored_line '>' '"$_hi_rc_dir/.hi_fallback_rc"')
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          $(_hi_command_append '"$_hi_rc_dir/.zshrc"')
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")"$(_hi_command_fish_flag) ;;
        *)
          $(_hi_fallback_prompt | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          $(_hi_command_append '"$_hi_rc_dir/.hi_fallback_rc"')
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
REMOTE
}

# The disposable-tree half of the script: unpack the armored streams into a
# fresh /tmp root. Reads $size and the streams from its caller, so _say_hi and
# _hi_wire_bytes assemble one shape rather than two kept in step.
#
# The `trap ... exit` is a backstop, not a second owner: load.sh's clean_all
# knows how to undo everything hi did on the target and runs on a normal exit
# and an abrupt disconnect alike. This trap covers the one thing it cannot
# survive - bash killed by a signal nothing can trap - and only has to remove
# the tree, since $_HI_SESSION_RC_DIR nests inside it.
function _hi_remote_middle() {
  local tmpl _hi_esc _hi_nc
  _hi_esc_pair _hi_esc _hi_nc
  _hi_whoami >/dev/null
  _hi_shquote tmpl "$_HI_WHOAMI_CACHE.hi.XXXXXX"
  cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $tmpl) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/say-hi
      export _HI_CONFIG_DIR=\$_HI_ROOT/config
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
      trap 'rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$_hi_esc" "$_hi_nc" "$size" >&2
      { printf 'export _HI_HOME="%s"\nexport _HI_ROOT="%s"\n' "\$_HI_HOME" "\$_HI_ROOT"
        echo "$bootloader" | $_HI_UNARMOR
      } > "\$_hi_rc_dir/hi.bashrc"
      # ^ the rc names this session's tree itself rather than trusting the
      # environment to still hold it: a target that carries a say-hi of its own
      # exports _HI_HOME for it from the startup files bash reads before an
      # --rcfile (load.sh's _hi_restore_profile guards the same thing on the
      # chain it sources itself). The fallback rc below needs no such line - no
      # profile chain runs on that tier.
REMOTE
  # Both lines below are printf'd rather than left in the heredoc above, and
  # that is load-bearing on Git Bash: splicing a value of 800-odd lines into
  # the middle of a heredoc line wedges it outright - no output, no error, and
  # `timeout` is what ends the session. Measured on windows-2025: the same
  # heredoc returns at once with the payload's newlines stripped, and a heredoc
  # whose whole body *is* the value returns too, so it is the mid-line splice
  # of a multi-line value that does it, not the 64KB. `printf` on the same
  # bytes is instant, which is how _hi_armored_line has always written the
  # overlay's own payload line. $overlay_line carries one of those armored
  # values itself, so it comes out the same way.
  printf '      echo "%s" | %s | tar -x -m -z -f - -C "$_HI_HOME"\n' \
    "$tree" "$_HI_UNARMOR"
  printf '      %s\n' "$overlay_line"
  cat <<REMOTE
      export _HI_CONNECT_PREFIX=" $size"
REMOTE
}

# Connect, copy say-hi over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: HI.18)
function _say_hi() {
  local size script boot_tmp ctl_path ctl_dir ctl_shared ct ec=0
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts overlay=()

  # Asked here rather than at the pipeline that needs them: a
  # `tree="$(_hi_payload_tar | base64)"` takes the armor's status, so a
  # refusal further in is swallowed and the target gets an empty archive.
  _hi_require "${_HI_ARMOR%% *}" "(or base64) to reach an ssh target" || return 1
  _hi_require_packer || return 1

  # local-only, so resolved once here and reused by the warm below and the
  # real stream
  _hi_read_lines overlay < <(_hi_overlay_files)
  local -a payload_excl=()
  _hi_payload_excl ${overlay[@]+"${overlay[@]}"}

  # warm the caches while _hi_ctl_open below settles, so a miss's ~70-130ms
  # build is not paid in series with the connect
  (
    _hi_payload_cached _hi_warm
    ((${#overlay[@]})) && _hi_overlay_cached _hi_warm "${overlay[@]}"
    true
  ) >/dev/null 2>&1 &
  local warm_bg=$!

  # multiplex the bootloader write and the real session over one ssh
  # connection; `shared` tries to reuse one already authenticated for this
  # target
  _hi_ctl_open 30 shared

  # the tars the script carries. The orphaned warm finishes its own atomic mv
  # after hi has moved on.
  wait "$warm_bg" 2>/dev/null || true
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_stream)"
  # the overlay's own stream, omitted when empty (GLOSSARY: HI.41)
  if ((${#overlay[@]})); then
    overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_stream "${overlay[@]}")"
  fi
  size="$_HI_SIZE_TOKEN"
  _hi_remote_script script

  # the true byte count, substituted for the token (GLOSSARY: HI.44)
  size="$(_hi_human_bytes "${#script}")"
  script="${script//$_HI_SIZE_TOKEN/$size}"

  # The bootloader rides stdin of the first of two calls on one connection,
  # and the write doubles as the POSIX-shell-and-base64 probe that selects the
  # PowerShell fallback. GLOSSARY: HI.19 - the argv cap, and why two calls.
  #
  # Its stderr is deliberately *not* redirected: this is the call that opens
  # the ControlMaster and authenticates, so it carries the server's `Banner`,
  # the "Permanently added" line and, on an unknown host, the key fingerprint.
  # ssh reads the yes/no from /dev/tty but prints the fingerprint to stderr,
  # so silencing it would leave the prompt on screen with the thing it is a
  # prompt *about* thrown away.
  #
  # The *target* names the directory and prints it back. A client-side
  # `mktemp -u` would name a path in the **client's** $TMPDIR - on every macOS
  # login shell, /var/folders/../T - which does not exist on a Linux target,
  # so the whole session would fall through to the PowerShell branch on a host
  # that has bash, invisibly to a CI job that only connects to 127.0.0.1.
  local boot_out boot_ec=0
  boot_out="$(printf '%s\n' "$script" | _hi_ssh_sh "$(_hi_boot_probe)" "${ctl_opts[@]}")" || boot_ec=$?

  # Tagged rather than taken whole: a target whose sh writes anything of its
  # own to stdout would otherwise prepend it to the path.
  boot_tmp=""
  case "$boot_out" in *HIBOOT:*)
    boot_tmp="${boot_out##*HIBOOT:}"
    boot_tmp="${boot_tmp%%$'\n'*}"
    ;;
  esac
  # a target string reaching a command run back on that target: _hi_safe_path's
  # rule, over the characters a temp path is built from ("+" for macOS)
  boot_tmp="$(_hi_safe_path "$boot_tmp" 'A-Za-z0-9._/+-')"

  # `-t` only when there is a terminal to ask for. ssh already declines a pty
  # when stdin is not one, so this only stops "Pseudo-terminal will not be
  # allocated" landing in the stderr of every piped `hi <host> <cmd>`. The
  # container arms make the same decision for a harder reason.
  local -a tflag=()
  [ -t 0 ] && tflag=(-t)
  # an empty $boot_tmp: _hi_boot_why names the cause it can, and the host
  # with no `sh` the PowerShell notice exists for is the one it cannot
  local why=""
  [ -n "$boot_tmp" ] || why="$(_hi_boot_why "$boot_ec" "$boot_out")"
  if [ -n "$boot_tmp" ]; then
    # $ct is our own _hi_elapsed digits-and-a-dot, never text a target sent
    # back, so it interpolates straight into the command line
    ct="$(_hi_elapsed "$_HI_CONNECT_T0" "$(_hi_now)")"
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      "_HI_CONNECT_TIME=$ct sh \"$boot_tmp/bootloader\"; rm -rf \"$boot_tmp\"" || ec=$?
  elif [ -n "$why" ]; then
    _hi_cecho " $why - handing over the host's own session" "$YELLOW" >&2
    _say_hi_plain "${ctl_opts[@]}" || ec=$?
  else
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, say-hi colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  fi

  _hi_ctl_close
  return "$ec"
}

# _hi_container_cmds <label> - the three ways to run something in a container
# target, into the caller's probe/cp/attach arrays: probe asks a question (no
# stdin, no tty), cp streams a file in, attach hands over a session. Its own
# function because scripts/doctor.sh has to ask exactly as a session would.
function _hi_container_cmds() {
  # the where/what halves (GLOSSARY: HI.43); $inner is empty for a plain target
  local outer inner
  _hi_outer "$DOMAIN" outer
  _hi_inner "$DOMAIN" inner
  local -a pick=()
  # A tty only when there is one to hand over. Unlike ssh -t, `docker exec -it`
  # on a pipe refuses outright rather than degrading, so `hi <ctr> <cmd> | ...`
  # failed at the transport before the command ran. The `-i`/`-it` split is the
  # same decision in each backend's spelling; nomad wants it explicit either
  # way, since its own guess hangs the exec on a wrapped pty.
  local it=-i nt=-t=false
  if [ -t 0 ]; then
    it=-it
    nt=-t=true
  fi
  case "$1" in
  nomad)
    [ -n "$inner" ] && pick=(-task "$inner")
    probe=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=false -t=false "$outer")
    cp=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true -t=false "$outer")
    attach=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true "$nt" "$outer")
    ;;
  kube)
    # the context/namespace prefixes, if any, ride every kubectl call
    _hi_kube_split "$DOMAIN"
    [ -n "$inner" ] && pick=(-c "$inner")
    probe=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    cp=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec -i "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    attach=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$it" "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    ;;
  *)
    # the docker-compatible family (GLOSSARY: HI.51): the CLI is the arm's own
    # name and the grammar is docker's
    local target="$DOMAIN"
    _hi_container_target "$1" "$DOMAIN" target || : # errexit guard: doctor runs under set -e
    probe=("$1" exec "$target")
    cp=("$1" exec -i "$target")
    attach=("$1" exec "$it" "$target")
    ;;
  esac
}

# The sweep of the scratch tree on every early exit and after the session.
# Reads $root and $probe from _say_hi_container, as _hi_remote_middle reads
# _say_hi's locals.
function _hi_container_cleanup() {
  "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
  return 0
}

# Every fatal arm of the ladder below, once: say why, sweep the scratch tree,
# fail. Spelled out per site before, and two of the five had quietly lost the
# sweep. The two arms that must *not* sweep - nothing created yet, or a $root
# hi refused and must never rm -rf - stay written out.
function _hi_container_abort() {
  _hi_fail "$1"
  _hi_container_cleanup
  return 1
}

# The no-bash fallback, probed and validated. The answer is a word read back
# from the container that reaches an attach command, and the probe only ever
# echoes one of $_HI_SHELL_LADDER's own names - so it is checked against that
# fixed list rather than sanitized, and anything else prints nothing.
# Reads $probe from its caller.
function _hi_container_fallback_shell() {
  local fallback
  fallback="$("${probe[@]}" sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')" 2>"${1:-/dev/null}")"
  case " $_HI_SHELL_LADDER " in
  *" $fallback "*) printf '%s' "$fallback" ;;
  esac
  return 0
}

# _hi_container_put <local-file> <target-path> - one local file onto the
# target, proven to have landed rather than assumed from a zero exit: an
# `exec -i` whose stdin closes before the target's cat drains it succeeds at
# the transport and delivers nothing. The race is transient, hence the retry,
# and only ever seen on a piped writer's stdin - so the retry replays a
# regular file: <local-file> `-` stages stdin to one first, and removes it
# after. Reads cp/probe/tmp from the caller.
function _hi_container_put() {
  local src="$1" dest="$2" try rc=1
  if [ "$src" = - ]; then
    src="$tmp.put"
    cat >"$src"
  fi
  # shellcheck disable=SC2034 # try only bounds the retry count, never read
  for try in 1 2 3; do
    if "${cp[@]}" sh -c "cat > '$dest'" <"$src" 2>"$tmp" &&
      "${probe[@]}" sh -c "[ -s '$dest' ]" 2>"$tmp"; then
      rc=0
      break
    fi
  done
  [ "$1" != - ] || rm -f "$src"
  return "$rc"
}

# _say_hi_container <label> <errlog> - the container arm, across the
# docker-compatible family, nomad, and kube.
function _say_hi_container() {
  local label="$1" tmp="$2"
  local shell_end root fallback exit_code size prefix tarball env_kv
  local -a probe cp attach overlay=()
  _hi_require_packer || return 1
  _hi_container_cmds "$label"

  # The parent is the *target's* `${TMPDIR:-/tmp}`, expanded there, so a pod
  # with a read-only root and an emptyDir still has somewhere to land. Mode
  # 700 and no -p, like the ssh path's boot_tmp: an existing directory is not
  # adopted, and the path that comes back is checked the same way. A target
  # with nowhere writable says so here, naming what it tried, rather than at
  # the copy with a message about the copy.
  root="$("${probe[@]}" sh -c 'd="${TMPDIR:-/tmp}"; d="${d%/}/'"$(_hi_whoami).hi.log.$$"'"
if mkdir -m 700 "$d" 2>/dev/null; then printf "%s" "$d"; else printf "%s" "${TMPDIR:-/tmp}" >&2; exit 1; fi' 2>"$tmp")" || {
    _hi_fail " no writable temp directory ($(cat "$tmp")) in [$DOMAIN] - --plain needs none"
    return 1
  }
  # the class adds "@" to boot_tmp's: the directory name embeds _hi_whoami
  root="$(_hi_safe_path "$root" 'A-Za-z0-9._/+@-')"
  if [ -z "$root" ]; then
    _hi_fail " [$DOMAIN] named a scratch directory hi will not use"
    return 1
  fi
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    fallback="$(_hi_container_fallback_shell "$tmp")"
    [ -n "$fallback" ] || _hi_container_abort " [$DOMAIN] named no shell hi asked about - not falling back" || return 1
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW" >&2

    if ! _hi_container_put "$_HI_ALIASES" "$root/aliases.sh"; then
      _hi_fail " failed to copy aliases.sh into [$DOMAIN]"
      _hi_container_cleanup
      "${attach[@]}" "$fallback"
      return $?
    fi

    # the shared fallback rc in its aliases-only shape, plus the POSIX prompt
    # for the shells that parse it - the ssh path's `*)` rule
    local -a fish_cmd=()
    if ! {
      _hi_fallback_rc --aliases-only "$root"
      case "$fallback" in
      zsh | fish) ;;
      *) _hi_fallback_prompt ;;
      esac
      # last, for the shells that read the file to its end; fish takes it as
      # -c below instead (GLOSSARY: HI.23)
      [ "$fallback" = fish ] || [ -z "${CMDARG:-}" ] || printf '%s\n' "$CMDARG"
    } | _hi_container_put - "$root/.hi_fallback_rc"; then
      _hi_container_abort " failed to write the fallback rc into [$DOMAIN]"
      return 1
    fi
    [ "$fallback" != fish ] || [ -z "${CMDARG:-}" ] || fish_cmd=(-c "$CMDARG")

    case "$fallback" in
    zsh)
      "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp" || _hi_container_abort " failed to write .zshrc into [$DOMAIN]" || return 1
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh -i"
      ;;
    # the rc through -C and the command through -c, as in _hi_remote_suffix
    fish) "${attach[@]}" fish -C "$("${probe[@]}" cat "$root/.hi_fallback_rc")" ${fish_cmd[@]+"${fish_cmd[@]}"} ;;
    *) "${attach[@]}" sh -c "export ENV='$root/.hi_fallback_rc'; exec $fallback -i" ;;
    esac
    exit_code=$?
    _hi_container_cleanup
    return $exit_code
  fi

  # Staged to a file so the announced size is the one actually sent, and asked
  # of the cache first, which already holds that shape. $cached says whether
  # the file is the cache's (leave it) or ours (delete it).
  local cached=1
  local -a payload_excl=()
  _hi_read_lines overlay < <(_hi_overlay_files)
  _hi_payload_excl ${overlay[@]+"${overlay[@]}"}
  if ! _hi_payload_cached tarball; then
    cached=""
    tarball="$tmp.tar.gz"
    _hi_payload_tar >"$tarball" || _hi_container_abort " failed to archive say-hi for [$DOMAIN]" || return 1
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  prefix=" $size" # the shape the ssh path's prefix reads
  printf '%s' "$prefix" >&2

  if ! "${cp[@]}" sh -c "tar -x -m -z -f - -C '$root'" <"$tarball"; then
    [ -n "$cached" ] || rm -f "$tarball"
    _hi_container_abort " failed to copy say-hi into [$DOMAIN]"
    return 1
  fi
  [ -n "$cached" ] || rm -f "$tarball"

  if ((${#overlay[@]})) &&
    ! _hi_overlay_bytes "${overlay[@]}" |
    "${cp[@]}" sh -c "mkdir -p '$root/say-hi/config' && tar -x -m -z -f - -C '$root/say-hi/config'" 2>"$tmp"; then
    _hi_cecho " failed to copy your say-hi config overlay into [$DOMAIN], using defaults" "$YELLOW" >&2
    # the defaults that overlay shadowed were cut from the tree above; a
    # prompt loader's cut is not the overlay's, and a hop's tree lacks it
    local f
    local -a config_defaults=()
    for f in ${payload_excl[@]+"${payload_excl[@]}"}; do
      case "$f" in say-hi/config/*) config_defaults+=("$f") ;; esac
    done
    ! ((${#config_defaults[@]})) || tar -c -f - -C "$_HI_HOME" "${config_defaults[@]}" |
      "${cp[@]}" sh -c "tar -x -m -f - -C '$root'" 2>>"$tmp" || true
  fi

  # hi.sh rides the payload tar unpacked above, mode and all - no separate
  # copy. Put like the fallback rc. An empty hi.bashrc is the worst failure
  # this arm has - `bash --rcfile` would start, source nothing, and hand over a
  # bare shell with no error at all - so it is fatal rather than unchecked.
  _hi_bootloader | _hi_container_put - "$root/say-hi/hi.bashrc" || _hi_container_abort " failed to write hi's bootloader into [$DOMAIN]" || return 1

  # `-i` explicitly: `--rcfile` is read by an *interactive* bash and nothing
  # else, and with a conditional tty that interactivity is not inferred
  # from `exec -it`. Without it a piped `hi <container> <cmd>` reads the empty
  # pipe as a script, ignores the rcfile, never sources load.sh, and never runs
  # the command - a clean exit and no output.
  #
  # _HI_CLEANUP marks the tree disposable for load.sh's clean_all, which owns
  # the teardown; $_HI_SESSION_RC_DIR nests under it, so the one `rm -rf`
  # covers both.
  env_kv="$(_hi_env_each ' %s=%s')"
  # one clock read for both legs: they are microseconds apart, and each
  # _hi_now is a subshell and a `date` fork on the line before the attach
  local now
  now="$(_hi_now)"
  "${attach[@]}" sh -c "export$env_kv _HI_HOME='$root' _HI_ROOT='$root/say-hi' _HI_CONFIG_DIR='$root/say-hi/config' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_elapsed "$shell_end" "$now")' _HI_CONNECT_TIME='$(_hi_elapsed "$_HI_CONNECT_T0" "$now")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/say-hi/hi.bashrc' -i"
  exit_code=$?

  _hi_container_cleanup
  return $exit_code
}

# --plain over ssh: no bootstrap, no boot probe, no payload - just ssh
# handing over the target's own login shell. Needs nothing beyond sshd and a
# shell. Also where _say_hi lands when the target refused its bootstrap, which
# is when the ControlMaster options arrive in "$@".
function _say_hi_plain() {
  local -a tflag=()
  [ -t 0 ] && tflag=(-t)
  ssh ${tflag[@]+"${tflag[@]}"} "$@" "${SSHARGS[@]}" "$DOMAIN" ${RAWCMD:+"$RAWCMD"}
}

# --plain over a container backend: no mkdir, no copy, straight into the best
# shell the target has. Built on the same _hi_container_cmds probe/attach as
# the full path, so the two cannot disagree on how to reach the target.
function _say_hi_container_plain() {
  local label="$1" shell
  local -a probe cp attach
  _hi_container_cmds "$label"
  if "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>&1; then
    shell=bash
  else
    # a bare `sh` when the probe answers nothing usable; the full path refuses
    # instead, having a payload at stake
    shell="$(_hi_container_fallback_shell)"
    [ -n "$shell" ] || shell="sh"
  fi
  if [ -n "${RAWCMD:-}" ]; then
    "${attach[@]}" "$shell" -c "$RAWCMD"
  else
    "${attach[@]}" "$shell"
  fi
}

# The <argument> column of hi's flag <word> (-h/-V stand for their long
# forms): empty for a bare flag, status 1 when <word> is not hi's. With the
# output dropped, it is also the membership test.
function _hi_flag_takes() {
  local row
  case "$1" in -h) set -- --help ;; -V) set -- --version ;; esac
  for row in "${_HI_FLAGS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    row="${row#*|}"
    printf '%s' "${row%%|*}"
    return 0
  done
  return 1
}

# Everything after the target is the remote command: RAWCMD as typed, for
# --plain's direct ssh/exec, and CMDARG with a "; exit" suffix to close the
# bootloader's sourced script out. One of hi's own flags here belongs before
# the target and would otherwise run on the far end as a command nobody has.
function _hi_parse_command() {
  if _hi_flag_takes "${1%%=*}" >/dev/null; then
    _hi_die "$1 goes before the target (hi [options] <target> [command ...])"
  fi
  local sep=""
  [[ "$*" = *[![:space:]]* ]] && sep='; '
  RAWCMD="$*"
  CMDARG="$*$sep exit"
}

# --help and --version take nothing after them: `hi --help extra` is a mistake
# worth naming, the way a stray word after --preview <subject> is
function _hi_only_word() {
  [ $# -le 1 ] || _hi_die "$1 takes no arguments (got: ${*:2})"
}

# _hi_help_or_version "$@" - -h/--help/-V/--version, wherever they are read
# from: _hi_parse answers them ahead of the target, and the top-level dispatch
# answers them again when they are hi's only argument. One arm for the pair.
function _hi_help_or_version() {
  _hi_only_word "$@"
  case $1 in -h | --help) _hi_help ;; *) _hi_version_line ;; esac
  exit 0
}

# _hi_is_ssh_value_opt <word> - an ssh option that takes a separate value;
# doctor.sh sorts its argv with it too
function _hi_is_ssh_value_opt() {
  case "$1" in
  -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -P | -p | -Q | -R | -S | -W | -w) return 0 ;;
  *) return 1 ;;
  esac
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  local use_word takes own=""
  # plain globals, so an inherited MUX=1 or PLAIN=1 must not stand in for a
  # flag that was never typed
  DOMAIN="" BACKEND="" PLAIN="" MUX="" RAWCMD="" CMDARG=""
  SSHARGS=()
  while [ $# -gt 0 ]; do
    # the target ends the options: every word after it, dashed or not, is
    # the remote command's, the way ssh itself reads `ssh host ls -la`
    if [ -n "${DOMAIN:-}" ]; then
      _hi_parse_command "$@"
      return
    fi
    case $1 in
    # hi's own -h/-V, anywhere ahead of the target: `hi -o X=Y -h` is a
    # question for hi, not ssh's usage message
    -h | --help | -V | --version)
      _hi_help_or_version "$@"
      ;;
    # ssh takes no `--word` option, so each is hi's or an error in hi's
    # voice; a single-dash one is ssh's
    -*)
      if [ "${1%%=*}" = --use ]; then
        # the arm by name, as the next word or after an =
        _hi_flag_word use_word "$@" || case $? in
        2) shift ;;
        *)
          _hi_die "--use needs a backend name (ssh counts as one)"
          ;;
        esac
        BACKEND="$(_hi_use_backend "$use_word" "${BACKEND:-}")" || exit 1
        own=1
      elif [ "$1" = --plain ]; then
        PLAIN=1 own=1
      elif [ "$1" = --mux ]; then
        MUX=1 own=1
      elif [ "$1" = --no-mux ]; then
        # the last of --mux/--no-mux wins, and either beats _HI_MUX=1 - which
        # is what makes --no-mux useful behind that setting
        MUX=0 own=1
      elif [ "$1" = -- ]; then
        # ssh's own option terminator, passed along as-is
        SSHARGS+=("$1")
      elif _hi_is_ssh_value_opt "$1"; then
        # its value is never read as the target
        [ "$#" -ge 2 ] || _hi_die "$1 needs a value"
        SSHARGS+=("$1" "$2")
        shift
      elif takes="$(_hi_flag_takes "${1%%=*}")"; then
        # `--plain=1` is one mistake, a local command behind an ssh option is
        # another - those dispatch on the first word alone. Bare flags matched
        # above, so an empty column here is the joined case. One call, not two
        # walks of the table.
        if [ -z "$takes" ]; then
          _hi_cecho "hi: ${1%%=*} takes no value" "$RED" >&2
        else
          _hi_cecho "hi: $1 goes first on the line (hi ${1%%=*} ...)" "$RED" >&2
        fi
        exit 1
      elif [ "${1#--}" != "$1" ]; then
        _hi_die "unknown option $1 (hi --help lists hi's options; ssh takes none that start with --)"
      else
        SSHARGS+=("$1")
      fi
      ;;
    *)
      DOMAIN="$1"
      ;;
    esac
    shift
  done
  [ -n "${DOMAIN:-}" ] || {
    # Bare `hi` prints the help. With any ssh option present, ssh's behaviour
    # stands: an option without a host is ssh's error to report, not a target
    # to guess at.
    # hi's own flags with nothing to connect to are hi's to name: ssh saw
    # none of them and has nothing to say
    if [ "${#SSHARGS[@]}" -eq 0 ]; then
      [ -z "$own" ] && _hi_help && exit 0
      _hi_die "no target to connect to (hi [options] <target> [command ...])"
    fi
    # not an exec, so the exit hook still runs
    ssh "${SSHARGS[@]}"
    exit $?
  }
}

# `${!array[@]}` pairs a row with its pid; bash 3.0, not a bash-4 form.
function _hi_resolve_backend() {
  local target="$1" i
  local -a pids=()
  _hi_probe true # settled once here, not once per predicate
  for i in "${!_HI_BACKENDS[@]}"; do
    # >/dev/null is what makes the early return below mean anything: the
    # caller is `arm="$(_hi_select_arm)"`, and a backgrounded probe holding
    # that substitution's stdout open would keep the parent from seeing EOF
    # until the *slowest* probe finished. The predicates answer with their
    # exit status alone, so nothing is lost by muting them.
    "${_HI_BACKENDS[i]##*|}" "$target" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for i in "${!_HI_BACKENDS[@]}"; do
    if wait "${pids[i]}"; then
      printf '%s' "${_HI_BACKENDS[i]%%|*}"
      return 0
    fi
  done
  return 0
}

# The arm $DOMAIN connects through: empty for ssh, else a roster name.
# $BACKEND wins outright and skips every probe. Its own function so a suite
# can assert the choice with no real connect.
function _hi_select_arm() {
  if [ -n "${BACKEND:-}" ]; then
    [ "$BACKEND" = ssh ] || printf '%s' "$BACKEND"
    return 0
  fi
  _hi_is_ssh_host "$DOMAIN" && return 0
  _hi_resolve_backend "$DOMAIN"
}

# What a dropped link leaves behind. ssh restores the tty's termios, but not
# the *terminal* modes a remote program switched on and never switched off -
# application cursor keys, the keypad, bracketed paste, kitty keyboard mode,
# the alternate screen, a hidden cursor - nor the OSC 133 "command running"
# state hi's prompt marks leave a Konsole in, since a drop never reaches
# load.sh's close. Every byte is a no-op on a terminal already normal (the
# alternate-screen exit only once wrapped, below), so the caller need not know
# which applied; `stty sane` is for the container arms, whose exec does not
# always restore termios. GLOSSARY: HI.53
function _hi_reset_terminal() {
  # DECSC/DECRC (`ESC 7`/`ESC 8`) around the alternate-screen exit: it is the
  # one byte here that is not a no-op on a terminal still on its normal
  # screen. Konsole answers `CSI ?1049 l` with an unconditional cursor
  # restore, and with nothing ever saved that slot is home, so a failed
  # connect went on to overwrite the visible screen from the top. Saving
  # first makes the restore land where we already are; on a terminal really
  # in the alternate screen the save goes to *that* screen's own slot, 1049l
  # still restores the pre-alt cursor, and the DECRC repeats it. GLOSSARY: HI.53
  printf '\033[?1l\033>\033[?2004l\033[<u\0337\033[?1049l\0338\033[?25h'
  printf '\033]133;D;%s\a' "$1"
  stty sane 2>/dev/null || true
}

# What a failed connect says, at most once. Three ways it says nothing, each
# because the failure was already spoken for: $_HI_SAID means _hi_fail printed
# the reason; ssh reserves 255 for its own failures, so any other code from
# the ssh arm is the session's own status and `hi host false` stays as quiet
# as `ssh host false`; and an empty container errlog means nothing hi ran on
# the way in complained.
function _hi_report_failure() {
  local code="$1" arm="$2" errlog="$3" errors
  [ "${_HI_SAID:-0}" != 1 ] || return 0
  if [ -n "$arm" ]; then
    [ -s "$errlog" ] || return 0
  else
    [ "$code" -eq 255 ] || return 0
  fi
  errors="$(<"$errlog")"
  # clearing the container arm's in-progress " <size>", which has no newline
  # yet; on a pipe there is no cursor to move, so a newline is the whole job
  if [ -t 2 ]; then
    printf '\r\033[K' >&2
  else
    printf '\n' >&2
  fi
  _hi_cecho "hi: could not reach [$DOMAIN]" "$BRRED" >&2
  [ -n "$errors" ] && _hi_cecho "$errors" "$BRRED" >&2
}

# The session name for a target: every character tmux's rules reject, or that
# reads badly in a status line, becomes `-`. `ctx:ns:pod/ctr` -> `hi-ctx-ns-pod-ctr`.
function _hi_mux_name() {
  printf 'hi-%s' "${1//[^[:alnum:]_-]/-}"
}

# _hi_mux_tool <outvar> - which multiplexer wraps the session: the first of
# tmux, zellij, and screen on PATH. Empty, with the reason on stderr, when
# there is none to use.
function _hi_mux_tool() {
  local _hi_mt_tool
  for _hi_mt_tool in tmux zellij screen; do
    if command -v "$_hi_mt_tool" >/dev/null 2>&1; then
      printf -v "$1" '%s' "$_hi_mt_tool"
      return 0
    fi
  done
  _hi_cecho "hi: --mux needs tmux, zellij, or screen on this machine; connecting without it" "$YELLOW" >&2
  return 1
}

# One KDL string, for a zellij layout: inside double quotes KDL reads only the
# backslash and the quote itself.
function _hi_kdl_quote() {
  local _hi_kq="$2"
  _hi_kq="${_hi_kq//\\/\\\\}"
  _hi_kq="${_hi_kq//\"/\\\"}"
  printf -v "$1" '"%s"' "$_hi_kq"
}

# With --mux (or _HI_MUX=1 and no --no-mux), re-run this connect inside a
# local multiplexer session named for the target and never return; a second
# `hi --mux <target>` joins the one already running. All client-side - the
# target sees the same session it always does. GLOSSARY: HI.52
function _hi_mux_wrap() {
  local name tool cmd="" word q layout
  local -a inner=()
  [ "${MUX:-${_HI_MUX:-0}}" = 1 ] || return 0
  [ "${_HI_MUX_INNER:-0}" != 1 ] || return 0 # already inside: connect as usual
  _hi_mux_tool tool || return 0
  name="$(_hi_mux_name "$DOMAIN")"
  # Rebuilt from what _hi_parse settled on, not replayed from "$@", so the
  # resolved target rides along. tmux and screen take it as one single-quoted
  # string: tmux hands it to its default-shell, which may be fish, and screen
  # to `sh -c`, and single quotes are the one form every shell reads alike
  # (%q's $'...' is bash's alone). zellij takes the words, in a layout.
  inner=(env _HI_MUX_INNER=1 "$_HI_LAUNCHER"
    ${BACKEND:+--use "$BACKEND"} ${PLAIN:+--plain}
    ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN" ${RAWCMD:+"$RAWCMD"})
  for word in "${inner[@]}"; do
    _hi_shquote q "$word"
    cmd="$cmd${cmd:+ }$q"
  done
  case "$tool" in
  tmux)
    if [ -n "${TMUX:-}" ]; then
      # tmux refuses to nest: create detached if needed, then switch this client
      tmux has-session -t "=$name" 2>/dev/null ||
        tmux new-session -d -s "$name" "$cmd" || exit 1
      exec tmux switch-client -t "=$name"
    fi
    exec tmux new-session -A -s "$name" "$cmd"
    ;;
  screen)
    if [ -n "${STY:-}" ]; then
      # screen has no client switch: a new window in this session is the
      # nearest thing, and the wrap is done once it exists
      screen -t "$name" sh -c "$cmd" || exit 1
      exit 0
    fi
    # -D -R: reattach that session, detaching it elsewhere first, else create it
    exec screen -D -R -S "$name" sh -c "$cmd"
    ;;
  zellij)
    # zellij starts a session's command from a layout file, never from argv;
    # one file per target, under hi's runtime directory, rewritten each time
    _hi_runtime_dir layout
    layout="${layout:-${TMPDIR:-/tmp}}/hi.mux.$name.kdl"
    {
      printf 'layout {\n    pane command=%s close_on_exit=true {\n        args' '"env"'
      for word in "${inner[@]}"; do
        [ "$word" = env ] && continue
        _hi_kdl_quote q "$word"
        printf ' %s' "$q"
      done
      printf '\n    }\n}\n'
    } >"$layout" || exit 1
    if [ -n "${ZELLIJ:-}" ]; then
      # inside a zellij: a new tab in this session, named for the target
      zellij action new-tab --name "$name" --layout "$layout" || exit 1
      exit 0
    fi
    if zellij list-sessions --short 2>/dev/null | grep -qx -- "$name"; then
      exec zellij attach "$name"
    fi
    exec zellij --session "$name" --new-session-with-layout "$layout"
    ;;
  esac
}

function _hi() {
  local tmp exit_code arm

  [ -d "$_HI_ROOT" ] || _hi_die "no such directory: $_HI_ROOT"

  tmp="$(mktemp -t hi.log.XXXXXX)"
  # $tmp is resolved when the trap fires, not now
  _hi_on_exit 'rm -f "$tmp"'

  _hi_parse "$@"
  # Primed in the shell that keeps them: a caller that reads one through $( )
  # would fill the memo in a subshell and lose it there, and the script
  # builders ask six times between them. GLOSSARY: HI.05
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  [ -z "${DOMAIN:-}" ] || { _hi_target_color >/dev/null && _hi_prompt_list >/dev/null; }
  # only with a terminal to attach: a piped `hi host cmd` keeps working
  if [ -t 0 ]; then _hi_mux_wrap; fi
  # No `2>"$tmp"` around this block: catching a failure to reprint in red
  # would also catch every word ssh says on a *successful* session - the
  # server's `Banner`, the "Permanently added" line, the host-key fingerprint.
  # The probes already silence their own daemon chatter, so that catch-all
  # would be almost entirely the transport's noise, and the transport has the
  # better claim on the terminal. $tmp still reaches _say_hi_container, which
  # redirects the commands whose noise is genuinely hi's.
  arm="$(_hi_select_arm)"
  if [ "${PLAIN:-0}" = 1 ]; then
    if [ -n "$arm" ]; then
      _say_hi_container_plain "$arm"
    else
      _say_hi_plain
    fi
  elif [ -n "$arm" ]; then
    _say_hi_container "$arm" "$tmp"
  else
    _say_hi
  fi
  exit_code="$?"

  if [ "$exit_code" -ne 0 ]; then
    # a session that did not end on its own terms may have left the terminal
    # mid-state; only with a terminal on both ends to put right
    [ -t 0 ] && [ -t 1 ] && _hi_reset_terminal "$exit_code"
    _hi_report_failure "$exit_code" "$arm" "$tmp"
  fi
  exit "$exit_code"
}

# The scripts/ entry points, reached as `hi --flag`. The payload ships no
# scripts/, so on a target the file is absent and the flag says which command
# wanted it - $_HI_NO_CHECKOUT is that sentence.
function _hi_run_script() {
  local flag="$1" script="$2"
  shift 2
  # so the script's usage line names `hi --doctor`, not doctor.sh
  [ -f "$script" ] && _HI_ARGV0="hi $flag" exec "$script" "$@"
  _hi_cecho "hi $flag $_HI_NO_CHECKOUT" "$RED" >&2
  exit 1
}

# hi's flags, out of common/flags (its header has the row format): one table
# for the dispatch here, --help's option lines, and completion's roster.
_HI_FLAGS=()
while IFS= read -r _hi_row || [ -n "$_hi_row" ]; do
  case "$_hi_row" in '#'* | '') continue ;; esac
  _HI_FLAGS+=("$_hi_row")
done <"$_HI_ROOT/common/flags"
unset _hi_row

# _hi_dispatch_subcommand "$@" - hands $1 to its script and never returns when
# the table names one; returns 1 otherwise. ${!var} is bash 2, not a bash-4 form.
function _hi_dispatch_subcommand() {
  local row flag var arg
  # Every row is a `--word`, so a target name can never match one. Answered
  # before the walk because this runs on every invocation and each row costs a
  # here-string, which is a temp file on the bash 3.2 floor.
  case "${1:-}" in --*) ;; *) return 1 ;; esac
  # `--update=v1.0.0` is `--update v1.0.0`, for every row alike
  local word="${1%%=*}" joined="" shape w positional
  [ "$word" = "$1" ] || joined="${1#*=}"
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag shape _ var arg _ <<<"$row"
    [ "$flag" = "$word" ] || continue
    [ -n "$var" ] || return 1
    # The joined word stands for the row's *first* argument, and only when
    # that is a positional (--preview=colors, --update=v1.0.0). A row whose
    # first argument is a switch has nothing for it to be: --install=yes is
    # refused here rather than reaching the script as a stray first argument,
    # and --doctor=json is an error rather than a host named json to probe.
    if [ -n "$joined" ]; then
      positional=""
      for w in ${shape//[][]/}; do
        case "$w" in --*) ;; *) positional=1 ;; esac
        break
      done
      [ -n "$positional" ] || _hi_die "$word takes no joined value (hi $word${shape:+ $shape})"
    fi
    shift
    _hi_run_script "$flag" "${!var}" ${arg:+"$arg"} ${joined:+"$joined"} "$@"
  done
  return 1
}

# The option lines of --help: `-` is what works anywhere, `local` what needs a
# part of the tree the payload does not carry. A label wider than the gutter
# gets its own line, the way GNU --help does, so the block fits 80 columns.
function _hi_flag_help() {
  local row flag arg needs help label
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag arg needs _ _ help <<<"$row"
    case "$1:$needs" in
    -:-)
      case "$flag" in
      --help) flag="-h, --help" ;;
      --version) flag="-V, --version" ;;
      esac
      ;;
    local:- | -:*) continue ;;
    esac
    label="$flag${arg:+ $arg}"
    if [ "${#label}" -le 22 ]; then
      printf '  %-22s %s\n' "$label" "$help"
    else
      printf '  %s\n  %-22s %s\n' "$label" "" "$help"
    fi
  done
}

# _hi_help - the --help text, one block: reached as `hi --help`, and by
# _hi_parse for a -h behind an ssh option
function _hi_help() {
  cat <<EOF
$_HI_USAGE

Copies your say-hi to <target> and hands you an identical shell session there -
header, colors, git prompt, aliases, vim/nano configs - then strips it all
back out when the session ends.

With [command ...], runs that inside hi's session instead: hi's aliases and
environment, a pty when your own stdin is one, only the command's output on
stdout. For a plain, pty-free remote command, use ssh itself.

<target> is resolved in this order, first match wins:
  1. a literal Host entry in ~/.ssh/config (a wildcard one does not count)
  2. a running container, by name or ID, through docker, podman, nerdctl, or
     finch - whichever of them answers, in that order
  3. a running nomad allocation, by ID or prefix
  4. a kubernetes pod, in whatever context/namespace kubectl points at -
     or namespace:pod / context:namespace:pod for another one
A name none of them claims still goes to ssh, so unlisted hosts work too.

With no target at all, hi prints this help.

hi's own options, which work anywhere - a session included:
$(_hi_flag_help -)

hi's local commands, which act on this machine instead of connecting. Each
needs a part of the tree the payload does not carry, so inside a session it
says so and stops (--update wants .git as well, which a package has not):
$(_hi_flag_help local)

Every option that takes a word takes it joined too (--use=docker,
--update=v1.0.0); one that takes none refuses it.
Every other option is passed to ssh unchanged - -p, -i, -J, -o, and the rest;
ssh takes none that start with two dashes, so an unknown one is hi's error to
report. Only the first non-option word is the target; everything after it is
the remote command.

Configuration lives in \${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/, so it
survives an upgrade. See \`man hi\` and the README for all of it.
EOF
}

set +euo pipefail # the connection paths below run against unknown hosts, where a probe that fails is normal, not fatal

# sourcing this file defines its functions without connecting, for testing
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone, since _hi_parse hands every other
# -flag to ssh.
_hi_dispatch_subcommand "$@"

case "${1:-}" in
# -V is hi's, like -h: the one ssh short option claimed on purpose, since
# "which version of hi is this" is what a bug report asks first and `ssh -V`
# is a keystroke away. One arm, the way _hi_parse answers the pair.
-h | --help | -V | --version)
  _hi_help_or_version "$@"
  ;;
esac

_hi "$@"
