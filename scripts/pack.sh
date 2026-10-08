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
# Three files hold its larger halves and are sourced from here, where each
# sat: pack_plugins.sh (the plugins files' rows), pack_scan.sh (the include
# scan), and pack_stream.sh (the staged tars, the strip, the caches).
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
# <group> is the section a list draws it under, or - for a member of hi's
# own, which nothing switches.
# <plugin> is its word in $_HI_PLUGINS_OFF (_hi_plugin_off) and the name a
# report gives what reads it, or - for none.
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
# <name> | <leader> | <strip> | <end> | <disable> | <plugin> | <include> | <allow> | <stand-in>,
# no column holding a ` | `, - for none. <leader> starts a comment line; with
# <strip> 1 the strip drops those, blank lines, and indentation. <end> is
# where a statement ends: line, \ (a line ending in one continues it), ()
# (the brackets balance, strings "-quoted), ()' ('-quoted too), or [] (a key
# under a [section], a \ continuing it: <plugin> and <include> then match
# `<section>.<key>`, lower-cased, and a <plugin> match is private, not a
# manager).
# <disable> is how a finding goes out: comment (a <leader> line, the whole
# statement), : or true (the verb and its file word become that no-op, a
# plugin line is prefixed with it), or "" (the value is emptied). <plugin>,
# <include>, and <allow> are EREs, \t a tab: a line matching <plugin> is a
# plugin manager, and one matching <include> is an include, once the text
# <allow> matches is taken out - for a : or true disable, <include> is the
# verb in command position and <allow> the file words it leaves alone.
# <stand-in> is `<ERE> => <line>`: a dropped plugin directly under a line the
# ERE matches leaves <line> in its place.
_HI_DIALECTS=()

# _hi_dialect_row <name> <outvar> - its $_HI_DIALECTS row; 1 for none
function _hi_dialect_row() {
  local _hi_dr
  ((${#_HI_DIALECTS[@]})) || _hi_read_lines _HI_DIALECTS <<'ROWS'
sh | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT)[}/"] | -
omz | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|ZSH)[}/"] | -
omb | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|OSH)[}/"] | -
bash-it | # | 1 | line | : | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT|BASH_IT)[}/"] | -
fish | # | 1 | line | true | ^[ \t]*(zinit|zplug|antigen|zgen|zgenom|zcomet|fisher)[ \t] | ([;&|{()]|[ \t;](then|do|else|and|or|begin|not))[ \t]*(source|[.])[ \t]+ | ^"?[$][{]?(_HI_CONFIG_DIR|_HI_ROOT)[}/"] | -
vim | " | 1 | line | comment | ^[ \t]*(Plug|Plugin|NeoBundle|packadd)[ \t!]|(plug|vundle|dein|minpac)# | ^[ \t]*(source|so)!?[ \t] | .*[$]VIMRUNTIME.* | -
lua | -- | 1 | ()' | comment | lazypath|rtp:prepend|vim[.]pack[.]add|require[ \t]*[(]?[ \t]*["'](lazy|packer|paq)|AddRuntimeFile.*RTPlugin | AddRuntimeFile|(dofile|loadfile)[ \t]*[(]|vim[.]cmd.*source[ \t]|require[ \t]*[(]?[ \t]*["'] | require[ \t]*[(]?[ \t]*["']vim[.] | -
elisp | ; | 1 | () | comment | [(](package-initialize|package-install|use-package|straight-|elpaca) | [(]load(-file)?[ \t]+"|add-to-list[ \t]+'load-path | - | -
nano | # | 1 | line | comment | - | ^[ \t]*include[ \t] | ^[ \t]*include[ \t]+["']?/usr/share/nano/?[^/"' \t]*(["' \t].*)?$ | -
tmux | # | 1 | \ | comment | @plugin|(^|[ \t;{"'])run(-shell)?[ \t].*tpm | (^|[ \t;{"'])(source(-file)?|set(-option)?[ \t]+(-[A-Za-z]+[ \t]+)*default-shell)[ \t] | - | -
screen | # | 1 | line | comment | - | ^[ \t]*(source|shell|defshell)[ \t] | - | -
git | # | 1 | [] | comment | ^(credential|gpg|includeif|sendemail)[.]|^url[.](push)?insteadof$|[.](signingkey|gpgsign|forcesignannotated|sshcommand|sslkey|sslcert|cookiefile|extraheader|askpass|proxy|password)$ | ^include[.]path$ | - | -
readline | # | 1 | line | comment | - | ^[ \t]*[$]include[ \t] | ^[ \t]*[$]include[ \t]+/etc/inputrc([ \t].*)?$ | -
kak | # | 0 | line | comment | ^[ \t]*(plug|bundle)[ \t]|(plug|bundle)[.]kak | (^|[ \t;{])source[ \t] | .*%val[{]runtime[}].* | -
kdl | // | 0 | () | comment | "file: | ^[ \t]*(layout_dir|theme_dir|default_shell)[ \t] | - | ^[ \t]*pane[ \t].*borderless[ \t]*=[ \t]*true => plugin location="zellij:compact-bar"
omp | # | 0 | line | comment | - | (^|[ \t{,"'])extends["']?[ \t]*[:=][ \t]*["']?[^"' \t,}]*([/~\\][^"' \t,}]*|[.](json|jsonc|ya?ml|toml))(["' \t,}]|$) | extends["']?[ \t]*[:=][ \t]*["']?https?:// | -
omp-json | - | 0 | line | "" | - | (^|[ \t{,"'])extends["']?[ \t]*[:=][ \t]*["']?[^"' \t,}]*([/~\\][^"' \t,}]*|[.](json|jsonc|ya?ml|toml))(["' \t,}]|$) | extends["']?[ \t]*[:=][ \t]*["']?https?:// | -
conf | # | 1 | line | comment | - | - | - | -
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
# The plugins with a shell hook, `<group>|<name>|<tool>|<init>|<prompt>|<shells>`
# each (HI.67), those with variables to send, `<group>|<name>|<variables>`
# (HI.62), and the names whose `default` is off, a space around each: on only
# once $_HI_PLUGINS_ON names them
_HI_PLUGIN_HOOKS=() _HI_PLUGIN_ENVS=() _HI_PLUGIN_DEFAULT_OFF=" "

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
# with a theme or config to ship - into $_HI_PROMPT_LIST_MEMO. One whose
# plugin is switched off is left out: off sets nothing on a target, and
# naming it in $_HI_PROMPT_TOOL is how it is handed over all the same.
# GLOSSARY: HI.32
function _hi_prompt_here() {
  local _hi_pl_r _hi_pl_t _hi_pl_f _hi_pl_p _hi_pl_out="$1"
  # _hi_overlay_src asks this list too: all of it while it is being built
  _HI_PROMPT_LIST_MEMO="$_hi_pl_out${_hi_pl_out:+ }$_HI_PROMPT_TOOLS"
  _hi_plugins_load
  for _hi_pl_r in "${_HI_PROMPT_TABLE[@]}"; do
    _hi_pl_t="${_hi_pl_r%%|*}"
    ! _hi_plugin_switched_off "$_hi_pl_t" || continue
    case "$_hi_pl_r" in
    *'|bin|'*) command -v "$_hi_pl_t" >/dev/null 2>&1 ;;
    tide'|'*) [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions/tide.fish" ] ;;
    powerlevel10k'|'*) _hi_p10k_in_use && _hi_overlay_src "${_hi_pl_r##*|}" _hi_pl_f ;;
    *) _hi_overlay_src "${_hi_pl_r##*|}" _hi_pl_f ;;
    esac && _hi_pl_out="$_hi_pl_out${_hi_pl_out:+ }$_hi_pl_t"
  done
  # a prompt plugin of the plugins files (HI.67), with its tool here and on
  for _hi_pl_r in ${_HI_PLUGIN_HOOKS[@]+"${_HI_PLUGIN_HOOKS[@]}"}; do
    _hi_hook_col "$_hi_pl_r" prompt _hi_pl_p
    [ "$_hi_pl_p" = yes ] || continue
    _hi_hook_col "$_hi_pl_r" name _hi_pl_t
    case " $_hi_pl_out " in *" $_hi_pl_t "*) continue ;; esac
    _hi_hook_here "$_hi_pl_r" && ! _hi_hook_off "$_hi_pl_r" && _hi_pl_out="$_hi_pl_out${_hi_pl_out:+ }$_hi_pl_t"
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

# the plugins files, read into rows
# shellcheck source=./pack_plugins.sh
source "$_HI_ROOT/scripts/pack_plugins.sh"

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
  # a tagged target's settings.sh is settings.sh and its tags' files joined
  # (hi.sh's _hi_tag_settings), with or without a settings.sh of its own
  if [ "$1" = settings.sh ] && [ -n "${_HI_TAG_SETTINGS:-}" ]; then
    _hi_out "${2:-}" "$_HI_TAG_SETTINGS"
    return 0
  fi
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
# <outvar>? By $_HI_PLUGINS_OFF naming its plugin or the member - its row's,
# or its own where it is one file of a directory row - (words a space or a
# comma apart), or by a toggle of its row's <off> column;
# a row of hi's own (group -) is never off. Read where the overlay is
# packed, so what is off neither rides nor is wired, and the target is handed
# the result. GLOSSARY: HI.64
function _hi_plugin_off() {
  local _hi_po_r _hi_po_g _hi_po_n _hi_po_t
  # nothing is off, most connects: said once for the values in force, since
  # every member asks, several times a connect
  _hi_plugins_load
  _hi_po_t="${_HI_PLUGINS_OFF:-}|${_HI_PLUGINS_ON:-}|${_HI_DISABLE_LOCAL:-0}|${_HI_SETTINGS:-}|$_HI_PLUGIN_DEFAULT_OFF|"
  for _hi_po_n in $_HI_OFF_TOGGLES; do _hi_po_t="$_hi_po_t${!_hi_po_n:-0}"; done
  if [ "${_HI_OFF_KEY-}" != "$_hi_po_t" ]; then
    _HI_OFF_KEY="$_hi_po_t" _HI_OFF_ANY="${_HI_PLUGINS_OFF:-}${_HI_PLUGIN_DEFAULT_OFF# }"
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
  _hi_plugin_name "$1" _hi_po_n "$_hi_po_r"
  if [ -n "${_HI_PLUGINS_OFF:-}" ]; then
    case " ${_HI_PLUGINS_OFF//,/ } " in
    *" $_hi_po_n "* | *" ${_hi_po_r%%|*} "* | *" $1 "*)
      [ -z "${2:-}" ] || printf -v "$2" '%s' "_HI_PLUGINS_OFF"
      return 0
      ;;
    esac
  fi
  # off by default, until $_HI_PLUGINS_ON names the plugin
  _hi_plugin_switched_off "$_hi_po_n" || return 1
  [ -z "${2:-}" ] || printf -v "$2" '%s' "_HI_PLUGINS_ON, off by default"
  return 0
}

# _hi_overlay_wiring <outvar> <member...> - the lines that point each tool at
# its member on a target, in common/paths.sh's four-shell dialect, which
# sources them there. A row's wire column holds one wire or several, a ;
# between them, each read by _hi_wire_read: env:<variables> exports each as
# the member's path and envdir: as its directory, a <variable>=<word> among
# them as that word; flag:<command> <words>
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
          case "$_hi_ow_v" in
          *=*) _hi_ow_l="$_hi_ow_l ${_hi_ow_v%%=*}=\"${_hi_ow_v#*=}\"" ;;
          *) _hi_ow_l="$_hi_ow_l $_hi_ow_v=\"$_hi_ow_p\"" ;;
          esac
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
  # the shell hooks (GLOSSARY: HI.67): every init plugin whose tool is here and whose
  # plugin is on, the target running each whose tool it has (and whose
  # settings, the ones that rode, still leave it on); and the prompt programs
  # a target is handed (_hi_prompt_list), as rows core.sh's _hi_prompt_row
  # reads beside its own table
  local _hi_ow_h="" _hi_ow_pp="" _hi_ow_pi="" _hi_ow_i _hi_ow_s
  _hi_plugins_load
  _hi_prompt_list >/dev/null
  for _hi_ow_r in ${_HI_PLUGIN_HOOKS[@]+"${_HI_PLUGIN_HOOKS[@]}"}; do
    _hi_hook_here "$_hi_ow_r" || continue
    _hi_hook_col "$_hi_ow_r" name _hi_ow_n
    _hi_hook_col "$_hi_ow_r" init _hi_ow_i
    _hi_hook_col "$_hi_ow_r" prompt _hi_ow_p
    _hi_hook_col "$_hi_ow_r" shells _hi_ow_s
    if [ "$_hi_ow_p" = yes ]; then
      # a prompt program: its init runs through the prompt hand-over alone
      case " $_HI_PROMPT_LIST_MEMO " in *[\ :]"$_hi_ow_n "*) ;; *) continue ;; esac
      [ "$_hi_ow_s" != - ] || _hi_ow_s="bash zsh fish"
      _hi_ow_pi="$_hi_ow_pi${_hi_ow_pi:+;}$_hi_ow_n=$_hi_ow_i"
      _hi_ow_pp="$_hi_ow_pp${_hi_ow_pp:+;}$_hi_ow_n|$_hi_ow_s|bin|-"
      continue
    fi
    _hi_hook_off "$_hi_ow_r" && continue
    # a leading - on the name says off by default, for the target's _hi_hook_on
    case "$_HI_PLUGIN_DEFAULT_OFF" in *" $_hi_ow_n "*) _hi_ow_n="-$_hi_ow_n" ;; esac
    # ...and a :<shells> after it, a , apart, the shells the hook is kept to
    [ "$_hi_ow_s" = - ] || _hi_ow_n="$_hi_ow_n:${_hi_ow_s// /,}"
    _hi_hook_col "$_hi_ow_r" group _hi_ow_p
    _hi_ow_h="$_hi_ow_h${_hi_ow_h:+;}$_hi_ow_p.$_hi_ow_n=$_hi_ow_i"
  done
  # the variables a plugin's `env` names, each that is set here as its value
  # in single quotes: one holding a quote, a backslash, or a line break
  # stays home (_hi_env_rides), and so does a plugin that is off
  for _hi_ow_r in ${_HI_PLUGIN_ENVS[@]+"${_HI_PLUGIN_ENVS[@]}"}; do
    _hi_ow_n="${_hi_ow_r#*|}"
    ! _hi_plugin_switched_off "${_hi_ow_n%%|*}" || continue
    for _hi_ow_v in ${_hi_ow_r##*|}; do
      ! _hi_env_rides "$_hi_ow_v" || _hi_ow_all="${_hi_ow_all}export $_hi_ow_v='${!_hi_ow_v}'"$'\n'
    done
  done
  [ -z "$_hi_ow_h" ] || _hi_ow_all="${_hi_ow_all}export _HI_HOOKS=\"$_hi_ow_h\""$'\n'
  [ -z "$_hi_ow_pi" ] || _hi_ow_all="${_hi_ow_all}export _HI_PROMPT_INITS=\"$_hi_ow_pi\""$'\n'
  [ -z "$_hi_ow_pp" ] || _hi_ow_all="${_hi_ow_all}export _HI_PROMPT_PLUGINS=\"$_hi_ow_pp\""$'\n'
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

# the include scan, and the files a marked line carries
# shellcheck source=./pack_scan.sh
source "$_HI_ROOT/scripts/pack_scan.sh"

# The most a script of the overlay's bin/ may hold, in characters: it rides
# on every connect
_HI_BIN_MAX=16384

# _hi_bin_ok <file> [outvar] - may a file of the overlay's bin/ ride: one
# that is executable, opens with #!, and holds no NUL and no more than
# $_HI_BIN_MAX characters; why not, into <outvar>. Read with builtins, since
# every connect asks. GLOSSARY: HI.58
function _hi_bin_ok() {
  local _hi_bk="" _hi_bk_nul=0 _hi_bk_why=""
  # true at a NUL or at the cap, false at the end of the file
  ! IFS= read -r -d '' -n $((_HI_BIN_MAX + 1)) _hi_bk <"$1" 2>/dev/null || _hi_bk_nul=1
  if [ ! -x "$1" ]; then
    _hi_bk_why="not executable (chmod +x)"
  elif [ "${_hi_bk:0:2}" != '#!' ] || { [ "$_hi_bk_nul" = 1 ] && [ "${#_hi_bk}" -le "$_HI_BIN_MAX" ]; }; then
    _hi_bk_why="a binary, or no #! line: only scripts ride"
  elif [ "${#_hi_bk}" -gt "$_HI_BIN_MAX" ]; then
    _hi_bk_why="over $_HI_BIN_MAX characters"
  fi
  [ -n "$_hi_bk_why" ] || return 0
  [ -z "${2:-}" ] || printf -v "$2" '%s' "$_hi_bk_why"
  return 1
}

# _hi_overlay_files [member...] - the members (default $_HI_OVERLAY_FILES and
# the plugins files', $_HI_PLUGIN_FILES) that have a source, one per line;
# callers read it once and hand the list to _hi_overlay_tar. A trailing-/ entry lists its members as <dir>/<name>, in
# name order, only those _hi_dir_member_ok admits (and, of bin/, _hi_bin_ok),
# over the overlay's directory and home's, each name once.
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
        [ -f "$src" ] && _hi_dir_member_ok "${src##*/}" && { [ "$f" != bin/ ] || _hi_bin_ok "$src"; } &&
          _hi_overlay_src "$f${src##*/}" >/dev/null &&
          seen="$seen${src##*/} " && printf '%s\n' "$f${src##*/}"
      done
      ;;
    *) _hi_overlay_src "$f" src && printf '%s\n' "$f" ;;
    esac
  done
  return 0
}

# the staged tars, the comment strip, their caches, and the sizes reported
# shellcheck source=./pack_stream.sh
source "$_HI_ROOT/scripts/pack_stream.sh"
