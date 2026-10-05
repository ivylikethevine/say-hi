#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The packer: what hi.sh sends a target, built on the machine that owns the
# config - the overlay's table and the plugins files' rows, home's lookups,
# the include scan, the comment strip, and the staged tars with their caches.
# hi.sh sources this where it is. scripts/ never rides in the payload, so a
# session's hi.sh finds none and relays its own tree as it stands (hi.sh's
# own _hi_payload_tar): nothing here costs a byte on the wire.
# GLOSSARY: HI.66
#
# Sourced, never run. Strict mode, common/core.sh, and the helpers called
# from here (_hi_tar_gz, _hi_hash, _hi_armored_line, ...) are hi.sh's.
#
# Much of this file is a table or a script read somewhere else, so a `$var`
# in single quotes is that reader's to expand (SC2016).
# shellcheck disable=SC2016

# _hi_zshrc_here: the .zshrc a framework's theme or init line is read from
# shellcheck source=./zshrc.sh
source "$_HI_ROOT/scripts/zshrc.sh"

# The user's config overlay: a second, smaller stream into its own overlay/ on
# the target (GLOSSARY: HI.41), and every member's one resolution order
# (HI.61): the overlay's copy, else the user's own file at home, else the
# tree's default, which the payload already carries. One row per member:
# <member>|<paths.sh variable>|<tree, when config/ has a default>|<tool>|<group>|<plugin>|<wire>|<off>|<dialect>|<home>.
# This table is hi's own files', which $_HI_PLUGINS_OFF never switches. The
# rows it does switch are the plugins files' (_hi_plugins_load), config/plugins
# and the overlay's plugins: a `[<group>.<plugin>]` table there is a row here
# for each of its files, of its `tool`, `wire`, `home`, and `dialect`.
# <paths.sh variable> is hi's own files' alone: a tool's member has none, and
# what hi's code reads of one on a target is an env: wire of its row.
# <tool> is the binaries that read it: home's copy rides with any of them on
# $PATH, and - asks about nothing (a shell, readline, a prompt program:
# _hi_prompt_list asks about those).
# <group> is the word that switches it with its kind in $_HI_PLUGINS_OFF
# (_hi_plugin_off), or - for a member of hi's own, which nothing switches.
# <plugin> is its own word there and the name a report gives what reads it,
# or - for none.
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
# for a lookup no path list can say, a function of this file that only this
# table and the tree's config/plugins may name, or - for none: a shell's own rc
# (bashrc, zshrc, config.fish) rides only from the overlay, since the rc a
# target runs should be asked for, not found. A member is <tool>/<file>
# where its tool keeps a directory under ~/.config, the file named as the
# tool names it, and its own name where the tool keeps none. A candidate
# ending in / is a directory, the member's file looked for inside it. A
# member with a trailing / is a directory whose files ride one by one
# (HI.58), from the overlay alone where the row has no home.
_HI_OVERLAY_TABLE=(
  'settings.sh|_HI_SETTINGS|-|-|-|-|-|-|sh|-'
  'colors|_HI_COLORS|tree|-|-|-|-|-|conf|-'
  'packages|_HI_PACKAGES|tree|-|-|-|-|$_HI_DISABLE_HEADER|conf|-'
  'header/|_HI_HEADER_CELLS|-|-|-|-|-|$_HI_DISABLE_HEADER|sh|-'
  'ssh_tags|-|-|-|-|ssh|-|-|-|@_hi_ssh_tags_file'
)

# _hi_row_col <row> <column> <outvar> - one column of a row, by the name the
# table's comment gives it
function _hi_row_col() {
  local _hi_rc_r="$1" _hi_rc_n
  for _hi_rc_n in member variable tree tool group plugin wire off dialect home; do
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

# The plugins files' rows, in the table's shape, read from config/plugins and
# the overlay's plugins by _hi_plugins_load, with each row's member in
# $_HI_PLUGIN_FILES and its plugin in $_HI_PLUGIN_NAMES. $_HI_PLUGIN_BAD is
# what it turned down, `<file>:<line>|<why>` each, for scripts/doctor.sh.
# GLOSSARY: HI.63
_HI_PLUGIN_ROWS=() _HI_PLUGIN_FILES=() _HI_PLUGIN_NAMES=() _HI_PLUGIN_BAD=() _HI_PLUGIN_KEY=""

# The overlay members renamed before 1.0, old:new. hi reads only the new
# name; scripts/doctor.sh names a file still under the old one, since it
# would otherwise be silently ignored.
_HI_OVERLAY_RENAMES="carry:plugins plugins.d:extensions vim.rc:vim/vimrc vimrc:vim/vimrc init.lua:nvim/init.lua nano.rc:nano/nanorc nanorc:nano/nanorc
  emacs.el:emacs/init.el init.el:emacs/init.el config.toml:helix/config.toml kakrc:kak/kakrc tmux.conf:tmux/tmux.conf theme.yml:eza/theme.yml
  bat.conf:bat/config lazygit.yml:lazygit/config.yml bash.sh:bashrc zsh.zsh:zshrc omz-theme.zsh:oh-my-zsh.zsh-theme omb-theme.sh:oh-my-bash.theme.sh"

# stands in for the target's overlay directory in a carried include's path
# until the overlay lands there (_hi_overlay_fixup)
_HI_CARRY_TOKEN="@@HI_CONFIG@@"
# a path an include may name: from ~/, $HOME, $XDG_CONFIG_HOME, or /, to the
# first character no config file puts in a bare path
_HI_CARRY_RE='(~/|[$][{]?(HOME|XDG_CONFIG_HOME)[}]?/|/)[^]{}[:space:]"'"'"';,()<>|&\[]+'

# _hi_prompt_handed <member> - is that prompt config's program one a target
# is handed (_hi_prompt_list)? Nothing else starts it, so no copy of it rides
# otherwise. GLOSSARY: HI.32
function _hi_prompt_handed() {
  local _hi_ph_t
  _hi_prompt_row "$1" _hi_ph_t || return 1
  _hi_prompt_list >/dev/null
  case " $_HI_PROMPT_LIST_MEMO " in *[\ :]"${_hi_ph_t%%|*} "*) ;; *) return 1 ;; esac
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
    _hi_zshrc_here _hi_th_f
    _hi_rc_theme ZSH_THEME "$_hi_th_f" _hi_th_t || return 1
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

# _hi_prompt_here <list> - hi.sh's _hi_prompt_list, where $_HI_PROMPT_TOOL
# names no program for every shell: <list>, then every prompt program this
# machine has - the ones on $PATH, tide where fisher put it, and a framework
# with a theme or config to ship - into $_HI_PROMPT_LIST_MEMO. GLOSSARY: HI.32
function _hi_prompt_here() {
  local _hi_pl_r _hi_pl_t _hi_pl_f _hi_pl_out="$1"
  # _hi_overlay_src asks this list too: all of it while it is being built
  _HI_PROMPT_LIST_MEMO="$_hi_pl_out${_hi_pl_out:+ }$_HI_PROMPT_TOOLS"
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
  local _hi_pc_v="" _hi_pc_z
  _hi_zshrc_here _hi_pc_z
  _hi_rc_last_match "^[^#]*oh-my-posh[^#]*[[:space:]]init[[:space:]][^#]*(--config[=[:space:]]|-c[[:space:]])[[:space:]]*[\"']?([^\"'[:space:])]+)" \
    _hi_pc_v "$HOME/.bashrc" "$_hi_pc_z" "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
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
  local _hi_pk="" _hi_pk_z
  _hi_zshrc_here _hi_pk_z
  _hi_rc_last_match '^[^#]*(powerlevel10k|romkatv)(/powerlevel10k|\.zsh-theme)' _hi_pk "$_hi_pk_z"
  [ -n "$_hi_pk" ]
}

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
  local _hi_rc_at _hi_rc_g _hi_rc_n _hi_rc_t _hi_rc_w _hi_rc_h _hi_rc_d _hi_rc_to
  local -a _hi_rc_m=() _hi_rc_mw=() _hi_rc_mh=() _hi_rc_md=()
  [ "$_HI_PLUGIN_KEY" != "$_hi_cy_k" ] || return 0
  _HI_PLUGIN_KEY="$_hi_cy_k" _HI_PLUGIN_ROWS=() _HI_PLUGIN_FILES=() _HI_PLUGIN_NAMES=() _HI_PLUGIN_BAD=()
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
          _hi_rc_t="" _hi_rc_w="" _hi_rc_h="" _hi_rc_d=""
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
      -1:*) _HI_PLUGIN_BAD+=("$_hi_cy_s:$_hi_cy_n|'$_hi_cy_h' is no key of a plugin: files, tool, wire, home, dialect") ;;
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
  _hi_cl_t="${_hi_rc_t:-$_hi_rc_n}"
  if ! _hi_plugin_tools_ok "$_hi_cl_t"; then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n: '$_hi_cl_t' is no list of commands, or -")
  elif ((${#_hi_rc_m[@]} == 0)); then
    _HI_PLUGIN_BAD+=("$_hi_rc_at|$_hi_rc_n names no files")
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

# _hi_overlay_home <member> [outvar] - the home tier alone, with the member's
# tool here to read it: the first of its row's candidates that exists. A
# directory entry answers with the directory.
function _hi_overlay_home() {
  local _hi_oh_r _hi_oh_c
  local -a _hi_paths=()
  _hi_overlay_row "$1" _hi_oh_r && _hi_tool_here "$1" "$_hi_oh_r" || return 1
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

# _hi_plugin_name <member> <outvar> [row] - the plugin a member is of, which
# is the name a report gives what reads it (the row looked up unless handed
# in); 1 and empty for a member of none
function _hi_plugin_name() {
  local _hi_tb="${3:-}"
  printf -v "$2" '%s' ''
  [ -n "$_hi_tb" ] || _hi_overlay_row "$1" _hi_tb || return 1
  _hi_row_col "$_hi_tb" plugin _hi_tb
  [ "$_hi_tb" != - ] && printf -v "$2" '%s' "$_hi_tb"
}

# _hi_toggle_on <NAME> - is that toggle 1 for a target? The environment's
# value - except at home under _HI_DISABLE_LOCAL=1, where common/paths.sh has
# set every toggle for this machine alone: there, only a toggle settings.sh
# sets itself, read off its last `export NAME=value` line (_hi_rc_value)
# without running it.
function _hi_toggle_on() {
  local _hi_tg_n _hi_tg_v
  if [ "${_HI_DISABLE_LOCAL:-0}" != 1 ]; then
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
# <outvar>? By $_HI_PLUGINS_OFF naming its plugin, its group, or the member -
# its row's, or its own where it is one file of a directory row - (words a
# space or a comma apart), or by a toggle of its row's <off> column;
# a row of hi's own (group -) is never off. Read where the overlay is
# packed, so what is off neither rides nor is wired, and the target is handed
# the result. GLOSSARY: HI.64
function _hi_plugin_off() {
  local _hi_po_r _hi_po_g _hi_po_n _hi_po_t
  # nothing is off, most connects: said once for the values in force, since
  # every member asks, several times a connect
  _hi_po_t="${_HI_PLUGINS_OFF:-}|${_HI_DISABLE_LOCAL:-0}|${_HI_SETTINGS:-}|"
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
  *" $_hi_po_n "* | *" $_hi_po_g "* | *" ${_hi_po_r%%|*} "* | *" $1 "*)
    [ -z "${2:-}" ] || printf -v "$2" '%s' "_HI_PLUGINS_OFF"
    return 0
    ;;
  esac
  return 1
}

# _hi_overlay_wiring <outvar> <member...> - the lines that point each tool at
# its member on a target, in common/paths.sh's four-shell dialect, which
# sources them there. A row's wire column holds one wire or several, a ;
# between them, each read by _hi_wire_read: env:<variables> exports each as
# the member's path and envdir: as its directory; flag:<command> <words>
# aliases the command to itself, the words, and the path, where the target
# has the command, and flagdir: the same with the directory. A flag ending
# in = takes the path in the same word.
# xdg:<command> aliases the command to itself with $XDG_CONFIG_HOME set to
# the overlay, whose <tool>/<file> members are laid out as ~/.config is: the
# fallback for a file no variable or flag reaches, since everything the
# command starts inherits the variable too.
# The directory of a member under a / is the one its first name names.
# Wires run in order and a later alias replaces an earlier one, so helix's
# languages.toml row follows its config.toml row: with both riding, the xdg
# alias is the one a target keeps.
#
# The paths stay under $_HI_CONFIG_DIR for the target to expand, so the file
# holds on a next hop, and a row's <off> toggles are tested there, where the
# shell starts. A line is written once, however many members ask
# for it. Builtins only: every connect runs it. GLOSSARY: HI.62
function _hi_overlay_wiring() {
  local _hi_ow_out="$1" _hi_ow_m _hi_ow_r _hi_ow_ws _hi_ow_g _hi_ow_p _hi_ow_v _hi_ow_l _hi_ow_n _hi_ow_all=$'\n'
  local _hi_wr_kind _hi_wr_vars _hi_wr_names _hi_wr_env _hi_wr_cmd _hi_wr_words
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
      _hi_wire_read "${_hi_ow_ws%%;*}" || _hi_wr_kind=""
      _hi_ow_ws="${_hi_ow_ws#*;}"
      case "$_hi_wr_kind" in
      env | flag) _hi_ow_p="\$_HI_CONFIG_DIR/$_hi_ow_m" ;;
      envdir | flagdir)
        _hi_ow_p="\$_HI_CONFIG_DIR"
        case "$_hi_ow_m" in */*) _hi_ow_p="$_hi_ow_p/${_hi_ow_m%%/*}" ;; esac
        ;;
      xdg) _hi_ow_p="" ;;
      *) continue ;;
      esac
      _hi_ow_l="$_hi_ow_g"
      case "$_hi_wr_kind" in
      env | envdir)
        _hi_ow_l="${_hi_ow_l}export"
        # shellcheck disable=SC2086 # the split is the column
        for _hi_ow_v in $_hi_wr_vars; do
          _hi_ow_l="$_hi_ow_l $_hi_ow_v=\"$_hi_ow_p\""
        done
        # a line behind a toggle ends true, or a sourcer under set -e would
        # stop at the file whose last line a toggle turned down
        [ -z "$_hi_ow_g" ] || _hi_ow_l="$_hi_ow_l || true"
        ;;
      *)
        # the path bare, as an alias of hi's always had it: load.sh reads a
        # body back for $EDITOR, and a quote inside one does not survive
        # that. No trailing blank either, which would have the shell expand
        # the next word as an alias too.
        _hi_ow_v="${_hi_wr_env:+env $_hi_wr_env}$_hi_wr_cmd${_hi_wr_words:+ $_hi_wr_words}"
        case "$_hi_wr_words" in *=) _hi_ow_v="$_hi_ow_v$_hi_ow_p" ;; *) _hi_ow_v="$_hi_ow_v${_hi_ow_p:+ $_hi_ow_p}" ;; esac
        _hi_ow_l="${_hi_ow_l}command -v $_hi_wr_cmd >/dev/null 2>&1"
        _hi_ow_n="$_hi_wr_names,"
        while [ -n "$_hi_ow_n" ]; do
          _hi_ow_l="$_hi_ow_l && alias ${_hi_ow_n%%,*}=\"$_hi_ow_v\""
          _hi_ow_n="${_hi_ow_n#*,}"
        done
        _hi_ow_l="$_hi_ow_l || true"
        ;;
      esac
      case "$_hi_ow_all" in *$'\n'"$_hi_ow_l"$'\n'*) ;; *) _hi_ow_all="$_hi_ow_all$_hi_ow_l"$'\n' ;; esac
    done
  done
  printf -v "$_hi_ow_out" '%s' "${_hi_ow_all#$'\n'}"
}

# _hi_tool_here <member> [row] - is the tool that reads <member> on this
# machine? The table's binaries, which are the names common/aliases.sh gates
# each alias on; a member of no tool's is a yes.
# The client is asked because only it can be, before a connect
# (docs/INTEGRATIONS.md's _Which side is asked_).
function _hi_tool_here() {
  local _hi_tl_t="${2:-}" _hi_tl_b
  [ -n "$_hi_tl_t" ] || _hi_overlay_row "$1" _hi_tl_t || return 0
  _hi_row_col "$_hi_tl_t" tool _hi_tl_t
  [ "$_hi_tl_t" != - ] || return 0
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
  if (index(s, "@@HI_CONFIG@@")) return ""
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
# ship, one row each (see _hi_lint_awk); a member with no dialect has none, and
# an include the packer carries (_hi_include_carry) is no finding.
function _hi_include_lint() {
  local f src prog row m n k t
  local -a _hi_dirs=() _hi_carried=()
  prog="$(_hi_lint_awk)"
  while IFS= read -r f; do
    if ! _hi_member_dialect "$f" row || ! _hi_overlay_src "$f" src; then continue; fi
    _hi_tool_dirs "$f" "$src"
    while IFS='|' read -r m n k t; do
      [ "$k" = include ] && ((${#_hi_dirs[@]})) && _hi_include_carry row "$t" "${f%%/*}" && continue
      printf '%s|%s|%s|%s\n' "$m" "$n" "$k" "$t"
    done < <(_hi_dialect="$row" awk -v mode=report -v name="$f" "$prog" "$src")
  done < <(_hi_overlay_files)
  return 0
}

# _hi_tool_dirs <member> <source> - the directories an include in <member> is
# carried from, into the caller's $_hi_dirs: the source's own directory (not
# $HOME's), and $XDG_CONFIG_HOME/<tool>, ~/.<tool>, and ~/.<tool>.d for the
# member's directory <tool>. None for a member with no directory.
function _hi_tool_dirs() {
  local _hi_td_t="${1%%/*}" _hi_td_s="${2%/*}"
  _hi_dirs=()
  [ "$_hi_td_t" != "$1" ] || return 0
  [ "$_hi_td_s" = "$HOME" ] || [ "$_hi_td_s" = "$2" ] || _hi_dirs+=("$_hi_td_s")
  _hi_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/$_hi_td_t" "$HOME/.$_hi_td_t" "$HOME/.$_hi_td_t.d")
}

# _hi_include_carry <outvar> <line> <tool> - <line> with each path in it that
# names a file under one of the caller's $_hi_dirs rewritten to
# $_HI_CARRY_TOKEN/<tool>/<its path under that directory>, into <outvar>,
# and each such file appended to the caller's $_hi_carried as a <member>
# <source> pair; 1 when no path is carried. ~, $HOME, and $XDG_CONFIG_HOME
# are read as they are here.
function _hi_include_carry() {
  local _hi_ic_rest="$2" _hi_ic_out="" _hi_ic_t _hi_ic_p _hi_ic_d _hi_ic_r _hi_ic_n=0
  while [[ $_hi_ic_rest =~ $_HI_CARRY_RE ]]; do
    _hi_ic_t="${BASH_REMATCH[0]}"
    _hi_ic_out+="${_hi_ic_rest%%"$_hi_ic_t"*}"
    _hi_ic_rest="${_hi_ic_rest#*"$_hi_ic_t"}"
    # shellcheck disable=SC2088 # a ~ the include wrote, matched as text
    case "$_hi_ic_t" in
    '~/'*) _hi_ic_p="$HOME/${_hi_ic_t#'~/'}" ;;
    '$HOME/'* | '${HOME}/'*) _hi_ic_p="$HOME/${_hi_ic_t#*/}" ;;
    '$XDG_CONFIG_HOME/'* | '${XDG_CONFIG_HOME}/'*) _hi_ic_p="${XDG_CONFIG_HOME:-$HOME/.config}/${_hi_ic_t#*/}" ;;
    *) _hi_ic_p="$_hi_ic_t" ;;
    esac
    for _hi_ic_d in ${_hi_dirs[@]+"${_hi_dirs[@]}"}; do
      _hi_ic_r="${_hi_ic_p#"$_hi_ic_d"/}"
      [ "$_hi_ic_r" != "$_hi_ic_p" ] && [ -f "$_hi_ic_p" ] || continue
      case "/$_hi_ic_r/" in */../* | */./*) continue ;; esac
      _hi_carried+=("$3/$_hi_ic_r" "$_hi_ic_p")
      _hi_ic_t="$_HI_CARRY_TOKEN/$3/$_hi_ic_r" _hi_ic_n=1
      break
    done
    _hi_ic_out+="$_hi_ic_t"
  done
  printf -v "$1" '%s' "$_hi_ic_out$_hi_ic_rest"
  [ "$_hi_ic_n" = 1 ]
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

# What the comment-stripper is pointed at in the tree, as find's tests; an
# overlay member is stripped by its dialect's <strip>. GLOSSARY: HI.35
_HI_STRIP_NAMES=(-name '*.sh' -o -name '*.zsh' -o -name '*.fish' -o -name flags -o -path '*/config/*')
# What of $_HI_PAYLOAD never rides: the plugins rows, which this file alone
# reads (GLOSSARY: HI.63). Part of the payload cache's key, so a cache built
# with them in it is not served.
_HI_PAYLOAD_CUT=(say-hi/config/plugins)

# _hi_stage_carry - the overlay stager's carry, over its staged file $f
# (member $_hi_st_m, dialect row $_hi_st_d): each include the scan finds whose
# path names a file under the member's tool directories (_hi_tool_dirs) is
# rewritten to the copy that rides (_hi_include_carry), and the file staged
# as a member of its own, queued for the same scan. The source it came from
# is kept in $_hi_st_carry. Reads and grows _hi_stage_tar's locals.
function _hi_stage_carry() {
  local _hi_sc_src="${_hi_st_qs[_hi_st_i]:-}" _hi_sc_at=" " _hi_sc_l _hi_sc_n=0 _hi_sc_out="" _hi_sc_k _hi_sc_j _hi_sc_m
  local -a _hi_dirs=() _hi_carried=()
  [ -n "$_hi_sc_src" ] || _hi_overlay_src "$_hi_st_m" _hi_sc_src || return 0
  _hi_tool_dirs "$_hi_st_m" "$_hi_sc_src"
  ((${#_hi_dirs[@]})) || return 0
  while IFS='|' read -r _ _hi_sc_l _hi_sc_k _; do
    [ "$_hi_sc_k" != include ] || _hi_sc_at="$_hi_sc_at$_hi_sc_l "
  done < <(_hi_dialect="$_hi_st_d" awk -v mode=report -v name="$_hi_st_m" "$_hi_st_prog" "$f")
  [ "$_hi_sc_at" != " " ] || return 0
  while IFS= read -r _hi_sc_l || [ -n "$_hi_sc_l" ]; do
    _hi_sc_n=$((_hi_sc_n + 1))
    case "$_hi_sc_at" in *" $_hi_sc_n "*) _hi_include_carry _hi_sc_l "$_hi_sc_l" "${_hi_st_m%%/*}" || true ;; esac
    _hi_sc_out+="$_hi_sc_l"$'\n'
  done <"$f"
  ((${#_hi_carried[@]})) || return 0
  printf '%s' "$_hi_sc_out" >"$f" || return 1
  for ((_hi_sc_j = 0; _hi_sc_j < ${#_hi_carried[@]}; _hi_sc_j += 2)); do
    _hi_sc_m="${_hi_carried[_hi_sc_j]}"
    # one already staged - a member, or a file carried before - rides once
    [ ! -e "$_hi_st_root/$_hi_sc_m" ] || continue
    mkdir -p "$_hi_st_root/${_hi_sc_m%/*}" && cp "${_hi_carried[_hi_sc_j + 1]}" "$_hi_st_root/$_hi_sc_m" || return 1
    _hi_st_q+=("$_hi_st_root/$_hi_sc_m")
    _hi_st_qd[${#_hi_st_q[@]} - 1]="$_hi_st_d"
    _hi_st_qs[${#_hi_st_q[@]} - 1]="${_hi_carried[_hi_sc_j + 1]}"
    _hi_st_carry+=("${_hi_carried[_hi_sc_j + 1]}")
    stage_out+=("$_hi_sc_m")
  done
}

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
  local -a _hi_st_strip=() _hi_st_add=(${stage_add[@]+"${stage_add[@]}"})
  local -a _hi_st_q=() _hi_st_qd=() _hi_st_qs=() _hi_st_carry=()
  local _hi_st_lint="${stage_lint:-0}"
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
      _hi_read_lines _hi_st_q < <(find "$_hi_st_root" -type f ! -name '*.lint')
      # a queue, not the find's lines: a carried file joins it, in the
      # dialect of the member that named it
      for ((_hi_st_i = 0; _hi_st_i < ${#_hi_st_q[@]}; _hi_st_i++)); do
        f="${_hi_st_q[_hi_st_i]}" _hi_st_m="${_hi_st_q[_hi_st_i]#"$_hi_st_root"/}" _hi_st_d="${_hi_st_qd[_hi_st_i]:-}"
        [ -n "$_hi_st_d" ] || _hi_member_dialect "$_hi_st_m" _hi_st_d || continue
        _hi_stage_carry || exit 1
        _hi_dialect="$_hi_st_d" awk -v mode=fix -v name="$_hi_st_m" "$_hi_st_prog" "$f" >/dev/null || exit 1
        # no .lint at all means an empty member: awk never ran a rule on it
        [ ! -f "$f.lint" ] || mv -f "$f.lint" "$f" || exit 1
        # <name> | <leader> | <strip> | ...: strip.awk's d= and c= per file
        _hi_st_n="${_hi_st_d%% | *}" _hi_st_d="${_hi_st_d#* | }"
        case "${_hi_st_d#* | }" in 1' | '*) _hi_st_strip+=("d=$_hi_st_n" "c=${_hi_st_d%% | *}" "$f") ;; esac
      done
      # what the overlay cache watches besides the members (_hi_overlay_cached)
      [ -z "${_hi_carry_list:-}" ] ||
        printf '%s\n' ${_hi_st_carry[@]+"${_hi_st_carry[@]}"} >"$_hi_carry_list" || exit 1
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
      find "$_hi_st_root" -type f \( "${_HI_STRIP_NAMES[@]}" \) -exec awk -f "$stage/strip.awk" {} + || exit 1
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

# What changes an overlay tar without touching any member's mtime: the member
# list itself, and the wiring written from it, which a newer hi.sh can change
# under the same list. Hashed, not spelled out, to keep the cache filename
# short.
function _hi_overlay_cache_key() {
  local _hi_ok_w
  _hi_overlay_wiring _hi_ok_w "$@"
  _hi_hash "$*$_hi_ok_w"
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
# so pointing the tool at another file never serves the old one's cache. The
# files the last build carried (_hi_stage_carry) are watched from the list it
# left beside the cache, $_hi_carry_list.
function _hi_overlay_cached() {
  local _hi_oc_outvar="$1" _hi_oc_f _hi_oc_src _hi_oc_key _hi_oc_dir _hi_carry_list=""
  shift
  (($#)) || return 1
  local -a cache_also=()
  for _hi_oc_f; do
    _hi_overlay_src "$_hi_oc_f" _hi_oc_src && [ "$_hi_oc_src" != "$_HI_CONFIG_DIR/$_hi_oc_f" ] &&
      cache_also+=("$_hi_oc_src")
  done
  _hi_oc_key="$(_hi_overlay_cache_key "$@" ${cache_also[@]+"${cache_also[@]}"})"
  _hi_runtime_dir _hi_oc_dir
  if [ -n "$_hi_oc_dir" ]; then
    _hi_carry_list="$_hi_oc_dir/hi.overlay.$_hi_oc_key.carry"
    [ ! -f "$_hi_carry_list" ] || while IFS= read -r _hi_oc_f; do
      [ -z "$_hi_oc_f" ] || cache_also+=("$_hi_oc_f")
    done <"$_hi_carry_list"
  fi
  _hi_cached "$_hi_oc_outvar" overlay "$_hi_oc_key" "$_HI_CONFIG_DIR/" _hi_overlay_tar "$@"
}

# The tree twin, against the ~70-130ms _hi_payload_tar otherwise costs on
# every connect. _hi_payload_tar takes no arguments - the roster is its own -
# but is handed one anyway: that list is what _hi_cached watches for staleness.
# Keyed on the tree's own path, $_HI_PAYLOAD_CUT, and the caller's
# $payload_excl: two trees on
# one machine share the runtime dir, and staleness is only "no file newer
# than the cache", so a tree keyed by name alone was served the other tree's
# payload; and a tree cut for one overlay is never served beside another.
function _hi_payload_cached() {
  local _hi_pc_key
  _hi_hash "$_HI_HOME|${_HI_PAYLOAD_CUT[*]} ${payload_excl[*]-}" _hi_pc_key
  _hi_pc_key="tree.$_hi_pc_key"
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
  _hi_overlay_bytes "$@" | _hi_armored_line '|' "tar -x -m -z -f - -C \"\$_HI_ROOT/config\" && $(_hi_overlay_fixup '"$_HI_ROOT/config"')"
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
    case " $_HI_PROMPT_LIST_MEMO " in *[\ :]"${f%%|*} "*) continue ;; esac
    s="${f#*|}" s="${s%%|*}"
    payload_excl+=("say-hi/common/fw_${f%%|*}.${s/bash/sh}")
  done
}

# The tree, comment-stripped through a staging copy; both size budgets
# measure this. GLOSSARY: HI.39 + HI.35. Whole unless the caller holds a
# $payload_excl - a connect that ships the overlay too; _hi_wire_bytes has
# none, and measures the stock tree, less $_HI_PAYLOAD_CUT.
function _hi_payload_tar() {
  local -a stage_in stage_out=(say-hi) stage_excl=("${_HI_PAYLOAD_CUT[@]}" ${payload_excl[@]+"${payload_excl[@]}"})
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

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it, through the same payload cache - a warm
# one stages nothing. GLOSSARY: HI.44 - why not a sum of streams
# shellcheck disable=SC2034 # the locals are hi.sh's _hi_remote_script's to read
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
