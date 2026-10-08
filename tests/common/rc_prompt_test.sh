#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The prompt the shell rcs hand over or draw for a prompt program: starship and
# oh-my-posh, the programs with no init, and the separator.
# A part of rc_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is rc_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2016
set -euo pipefail

_HI_RC_PART=prompt
# shellcheck source=./rc_test.sh
source "${BASH_SOURCE[0]%/*}/rc_test.sh"

# One case for all three shells and both tools: the per-shell rc, prompt-print
# incantation, and expected shape live in the case's own table. Extra
# NAME=VALUE arguments ride _hi_rc_shell (env applies the last assignment, so
# the prepended-PATH override wins over the baseline), so there is one `env -i`
# block here rather than one per case.
function test_defers_to_prompt_tool_when_asked() {
  local shell="$1" tool="$2" script want out
  case "$shell" in
  bash)
    script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf "%s|%s" "$PS1" "${HI_PS1:-unset}"'
    want="PROMPT-STUB|unset"
    ;;
  zsh)
    script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "$PS1"'
    want="PROMPT-STUB"
    ;;
  fish)
    script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; fish_prompt'
    want="*PROMPT-STUB*"
    ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" \
    PATH="$(_hi_prompt_stub_dir "$tool"):$PATH" _HI_PROMPT_TOOL="$tool")"
  # shellcheck disable=SC2053 # $want is a pattern (fish's is a glob)
  [[ "$out" == $want ]] || _hi_why out want
}

# on a target, a tool's config in the overlay becomes the tool's own variable
# (starship.toml -> $STARSHIP_CONFIG, theme.yml -> $EZA_CONFIG_DIR - the
# directory, since eza fixes the file name - bat.conf -> $BAT_CONFIG_PATH,
# inputrc -> $INPUTRC, and ripgreprc, fzfrc, lazygit.yml the same); at
# home the variable is left alone, whatever the overlay holds. The lines that
# do it are the ones the client packs beside the file (GLOSSARY: HI.62).
# <shell> <overlay file> <variable> <expected on a target> [NAME=VALUE...]
# shellcheck disable=SC2016 # the child bash expands its own script
function test_remote_session_exports_overlay_config() {
  local shell="$1" file="$2" var="$3" want="$4" script out home
  shift 4
  mkdir -p "$_HI_WORKDIR/cfg"
  case "$file" in */*) mkdir -p "$_HI_WORKDIR/cfg/${file%/*}" ;; esac
  printf '# a config\n' >"$_HI_WORKDIR/cfg/$file"
  _hi_wiring_for "$file" >"$_HI_WORKDIR/cfg/wiring.sh" || _hi_why file || return 1
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${'"$var"':-}"' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; echo -n $'"$var" ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" "$@" _HI_REMOTE_SESSION=1)"
  home="$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")"
  rm -f "$_HI_WORKDIR/cfg/$file" "$_HI_WORKDIR/cfg/wiring.sh"
  [ "$out" = "$want" ] && [ -z "$home" ] || _hi_why out want home
}

# on a target, micro reaches the overlay's copy through its alias, a
# wiring.sh line (GLOSSARY: HI.62): micro -config-dir the micro/ directory.
# tmux, screen, and zellij are common/mux.sh's there, which names the
# overlay's copy itself (hi/keep_test.sh has what it runs). With no overlay
# copy the target's own ~/.tmux.conf is not picked up in its place.
# <shell> <overlay file, or - for none> <alias> <wanted> [unwanted]
function test_remote_session_aliases_overlay_config() {
  local shell="$1" file="$2" name="$3" want="$4" bad="${5:-}" script out
  [ "$file" = - ] || {
    mkdir -p "$_HI_WORKDIR/cfg/micro" "$_HI_WORKDIR/cfg/zellij" "$_HI_WORKDIR/cfg/tmux"
    printf '# a config\n' >"$_HI_WORKDIR/cfg/$file"
    _hi_wiring_for "$file" >"$_HI_WORKDIR/cfg/wiring.sh" || _hi_why file || return 1
  }
  printf 'set -g @mine target\n' >"$_HI_WORKDIR/.tmux.conf"
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; alias '"$name" ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; functions '"$name" ;;
  esac
  # the editor aliases are gated on their tool (common/aliases.sh), and no
  # runner has micro: a stub on PATH stands in for it
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" _HI_REMOTE_SESSION=1 \
    PATH="$(_hi_fake_path rc-tools micro tmux screen zellij):$PATH" 2>/dev/null)"
  rm -rf "$_HI_WORKDIR/cfg/micro" "$_HI_WORKDIR/cfg/zellij" "$_HI_WORKDIR/cfg/tmux" "$_HI_WORKDIR/cfg/screenrc" "$_HI_WORKDIR/.tmux.conf" \
    "$_HI_WORKDIR/cfg/wiring.sh"
  if [[ "$out" != *"$want"* ]] || { [ -n "$bad" ] && [[ "$out" == *"$bad"* ]]; }; then
    _hi_cecho " | $name is: [$out]" "$RED"
    return 1
  fi
}

# At home a tool whose own config is in force gets no alias: naming the file
# it already reads buys nothing, and `vim -u` or `nano --rcfile` is not a
# no-op. With no config anywhere there is nothing to name either, and
# micro's default flags are a target's alone.
# <shell> <own|none>
_HI_HOME_ALIASED="vim nvim hx nano emacs micro tmux screen zellij"

function test_home_session_aliases_only_his_configs() {
  local shell="$1" mode="$2" home="$_HI_WORKDIR/home-$2" script f out
  mkdir -p "$home"
  [ "$mode" = none ] || {
    mkdir -p "$home/.config/nvim" "$home/.config/helix" "$home/.config/micro" "$home/.config/zellij"
    for f in .vimrc .config/nvim/init.lua .config/helix/config.toml .nanorc .emacs .tmux.conf .screenrc; do
      printf '# mine\n' >"$home/$f"
    done
  }
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; for a in '"$_HI_HOME_ALIASED"'; do alias "$a" >/dev/null 2>&1 && printf "%s " "$a"; done' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; for a in '"$_HI_HOME_ALIASED"'; do alias "$a" >/dev/null 2>&1 && printf "%s " "$a"; done' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; for a in '"$_HI_HOME_ALIASED"'; functions -q $a; and printf "%s " $a; end' ;;
  esac
  # shellcheck disable=SC2086 # one fake binary per word of the list
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" HOME="$home" \
    PATH="$(_hi_fake_path rc-home-tools $_HI_HOME_ALIASED):$PATH" 2>/dev/null)"
  [ -z "$out" ] && return 0
  _hi_cecho " | aliased: [$out], wanted none" "$RED"
  return 1
}

# extensions/ (GLOSSARY: HI.59), one fixture for every shell: 10 exports a value
# and a segment, 20 reads 10's value (so name order is load order), 30 uses
# if/then/fi (bash and zsh parse it, fish does not), 40 parses nowhere, and
# 50 is a backup that is never a member. Each shell loads what it can parse,
# in order, says what it skipped, and draws the segment.
function _hi_extension_cfg() {
  local d="$_HI_WORKDIR/extcfg/extensions"
  [ -d "$d" ] || {
    mkdir -p "$d"
    printf '#!/bin/sh\nexport HI_A=a\nexport _HI_SEGMENT="printf kctx"\n' >"$d/10-kube"
    printf '#!/bin/sh\nexport HI_B="$HI_A"b\n' >"$d/20-order"
    printf 'if [ 1 ]; then :; fi\nexport HI_C=c\n' >"$d/30-shonly"
    printf 'foo() {\n' >"$d/40-broken"
    printf 'export HI_D=d\n' >"$d/50-x.bak"
  }
  printf '%s' "${d%/*}"
}

function test_extensions_load_in_order_skip_loudly_and_draw() {
  local shell="$1" script want out
  case "$shell" in
  bash)
    script='source "$_HI_HOME/say-hi/common/bash.sh" 2>&1; __hi_ps1; printf "[%s|%s|%s|%s]" "$HI_A" "$HI_B" "${HI_C:-}" "${HI_D:-}"; printf "%s" "$__hi_env_info"'
    want='[a|ab|c|]kctx '
    ;;
  zsh)
    script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>&1; __hi_env_precmd; __hi_segment_precmd; print -rn -- "[$HI_A|$HI_B|${HI_C:-}|${HI_D:-}]$__hi_env_info"'
    want='[a|ab|c|]kctx '
    ;;
  fish)
    script='source $_HI_HOME/say-hi/common/config.fish 2>&1; echo -n "[$HI_A|$HI_B|$HI_C|$HI_D]"; fish_prompt'
    want='[a|ab||]'
    ;;
  esac
  out="$(_hi_rc_shell dumb "$shell" "$script" _HI_CONFIG_DIR="$(_hi_extension_cfg)")"
  # fish's drawn prompt sits between the values and the segment's lead space
  if [[ "$out" != *"extension 40-broken does not parse in $shell; skipped"* || "$out" == *50-x* ||
    "$out" != *"$want"* || "$out" != *"kctx "* ]] ||
    [[ "$shell" == fish && "$out" != *"extension 30-shonly does not parse in fish"* ]]; then
    _hi_cecho " | $shell said: [$out]" "$RED"
    return 1
  fi
}

# <shell>: the overlay's aliases.sh is parsed before it is sourced. One
# holding a function is bash's and zsh's to load and fish's to skip, with a
# line saying so, and one all three parse loads in each.
function test_overlay_aliases_are_parsed_before_they_load() {
  local shell="$1" cfg="$_HI_WORKDIR/aliases-guard" script out
  mkdir -p "$cfg"
  case "$shell" in
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>&1; functions -q hi_guard_ok; and echo -n LOADED' ;;
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>&1; alias hi_guard_ok >/dev/null 2>&1 && printf LOADED' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>&1; alias hi_guard_ok >/dev/null 2>&1 && printf LOADED' ;;
  esac
  printf '%s\n' 'alias hi_guard_ok="echo ok"' >"$cfg/aliases.sh"
  out="$(_hi_rc_shell dumb "$shell" "$script" _HI_CONFIG_DIR="$cfg")"
  [[ "$out" == *LOADED* && "$out" != *"does not parse"* ]] || _hi_because "$shell, the subset: [$out]" || return 1
  printf '%s\n' 'alias hi_guard_ok="echo ok"' 'hi_guard_fn() { echo fn; }' >"$cfg/aliases.sh"
  out="$(_hi_rc_shell dumb "$shell" "$script" _HI_CONFIG_DIR="$cfg")"
  if [ "$shell" = fish ]; then
    [[ "$out" == *"aliases.sh does not parse in fish; skipped"* && "$out" != *LOADED* ]] || _hi_because "fish, a function: [$out]"
  else
    [[ "$out" == *LOADED* && "$out" != *"does not parse"* ]] || _hi_because "$shell, a function: [$out]"
  fi
}

# fish's sudo wrapper is a function behind _HI_SUDO_ALIAS, the same opt-in
# as the POSIX alias; unset, `sudo` is the command and nothing else
function test_fish_sudo_wrapper_follows_the_toggle() {
  local script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; functions -q sudo; and echo wrapped; or echo bare' on off
  on="$(_hi_rc_shell xterm-256color fish "$script" _HI_SUDO_ALIAS=1)"
  off="$(_hi_rc_shell xterm-256color fish "$script")"
  [ "$on" = wrapped ] && [ "$off" = bare ] || _hi_why on off
}

function test_bash_keeps_hi_prompt_without_the_setting() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_prompt_stub_dir starship):$PATH")"
  [[ "$out" == *'\u'* ]] || _hi_why out
}

# Asked for, not installed: hi's prompt, and nothing on stderr. "Not
# installed" has to be manufactured - this machine may well carry starship
# (an Arch box does), so the case swaps $PATH for a toolbox of the real tools
# bash.sh needs, minus starship, rather than trusting the box to lack it.
function test_bash_falls_back_when_starship_is_absent() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_real_path starshipless bash sh sed awk grep tr cut hostname uname cksum git)" \
    _HI_PROMPT_TOOL=starship 2>&1)"
  [[ "$out" == *'\u'* ]] || _hi_why out
}

# The prompt programs without `init <shell>` (GLOSSARY: HI.32), each faked
# where it installs under a $HOME of its own: powerlevel10k and oh-my-zsh's
# libraries and oh-my-bash each stand in with a marker and an alias of theirs
# (hi's must win), tide as an autoloading fish_prompt, powerline-go as a stub
# echoing its argv. The overlay carries the home half - a p10k config, the two
# themes, tide's variables - which only a target reads.
function _hi_fw_home() {
  local h="$_HI_WORKDIR/fwhome" c="$_HI_WORKDIR/fwhome/cfg"
  [ -d "$h" ] || {
    mkdir -p "$h/powerlevel10k" "$h/.oh-my-zsh/lib" "$h/.oh-my-bash" "$h/.config/fish/functions" "$c"
    printf 'p10k() { :; }\nPROMPT=P10K\n' >"$h/powerlevel10k/powerlevel10k.zsh-theme"
    printf 'git_prompt_info() { print -n G; }\nalias ls=FW-LS\n' >"$h/.oh-my-zsh/lib/git.zsh"
    printf '_omb_module_require() { :; }\nalias ls=FW-LS\n' >"$h/.oh-my-bash/oh-my-bash.sh"
    # bash_it.sh's loader sources $BASH_IT_THEME as a literal path; it gets no
    # alias of its own, since hi sources the whole framework, aliases included
    mkdir -p "$h/.bash_it"
    printf '_bash-it-log-prefix-by-path() { :; }\n[ -n "$BASH_IT_THEME" ] && . "$BASH_IT_THEME"\n' >"$h/.bash_it/bash_it.sh"
    printf 'function tide; end\n' >"$h/.config/fish/functions/tide.fish"
    printf 'function fish_prompt; echo -n "TIDE:$tide_character_icon:"(count $tide_left_prompt_items):(count $tide_empty):(count (env | string match "tide_*")); end\n' \
      >"$h/.config/fish/functions/fish_prompt.fish"
    printf 'PROMPT="$PROMPT+CFG"\n' >"$c/p10k.zsh"
    printf 'PROMPT="OMZ-$(git_prompt_info)"\n' >"$c/oh-my-zsh.zsh-theme"
    printf 'PS1=OMB\n' >"$c/oh-my-bash.theme.sh"
    printf 'PS1=BASHIT\n' >"$c/bash-it.theme.bash"
    printf 'SETUVAR tide_character_icon:\\u276f\nSETUVAR tide_left_prompt_items:pwd\\x1egit\nSETUVAR tide_empty:\\x1d\n' >"$c/tide.vars"
  }
  printf '%s' "$h"
}

# bash-it loaded by the rc already has a theme, and that theme's
# prompt_command precmd entry would redraw over the home theme: it is dropped,
# a hook of anyone else's is kept, and the home theme is sourced on top
function test_bash_it_from_the_rc_hands_over_its_precmd() {
  local h out
  h="$(_hi_fw_home)"
  out="$(_hi_rc_shell dumb bash '_bash-it-log-prefix-by-path() { :; }
    prompt_command() { PS1=RC-BASHIT; }; other_hook() { :; }
    precmd_functions=(prompt_command other_hook); PS1=RC-BASHIT
    source "$_HI_HOME/say-hi/common/bash.sh" 2>&1
    printf "%s|%s" "$PS1" "${precmd_functions[*]}"' \
    HOME="$h" _HI_CONFIG_DIR="$h/cfg" _HI_PROMPT_TOOL=bash-it _HI_REMOTE_SESSION=1)"
  [ "$out" = "BASHIT|other_hook" ] || _hi_because "bash drew: [$out]"
}

# oh-my-bash loaded by hi takes every alias with `unalias -a`, its libraries'
# included, and puts back each one set before it as it was, a quote in the
# value too
function test_oh_my_bash_puts_the_aliases_back() {
  local h out want
  h="$(_hi_fw_home)"
  out="$(_hi_rc_shell dumb bash 'alias q="echo it'"'"'s" ll="ls -l"
    source "$_HI_HOME/say-hi/common/bash.sh" >/dev/null 2>&1
    alias q ll; alias ls 2>&1' \
    HOME="$h" _HI_CONFIG_DIR="$h/cfg" _HI_PROMPT_TOOL=oh-my-bash _HI_REMOTE_SESSION=1)"
  want="alias q='echo it'\\''s'"$'\n'"alias ll='ls -l'"
  [[ "$out" == "$want"* && "$out" != *FW-LS* ]] || _hi_because "aliases: [$out]"
}

# <shell> <before-rc script> - a prompt hi has no hand-over for (a framework's
# marker, or fish_prompt in the user's own functions/) stays the user's, and
# `hi` in $_HI_PROMPT_TOOL takes it anyway. powerlevel10k in the list fits no
# case here, so the list runs out rather than naming hi. The $PS1 under a
# marker is the shell's own default, so only the marker can be what keeps it.
function test_foreign_prompt_stays_unless_hi_named() {
  local shell="$1" pre="$2" script x="$_HI_WORKDIR/ownprompt" theirs mine own=MINE
  mkdir -p "$x/fish/functions"
  printf 'function fish_prompt; echo -n MINE; end\n' >"$x/fish/functions/fish_prompt.fish"
  case "$shell" in
  bash)
    own='\s-\v\$ '
    script="$pre"'; PS1=$RC_PS1; source "$_HI_HOME/say-hi/common/bash.sh" >/dev/null 2>&1; eval "${PROMPT_COMMAND:-}" >/dev/null; printf %s "$PS1"'
    ;;
  zsh)
    own='%m%# '
    script="$pre"'; PS1=$RC_PS1; source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1; print -rn -- "$PS1"'
    ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish >/dev/null 2>&1; fish_prompt' ;;
  esac
  theirs="$(_hi_rc_shell dumb "$shell" "$script" _HI_PROMPT_TOOL=powerlevel10k XDG_CONFIG_HOME="$x" RC_PS1="$own")"
  mine="$(_hi_rc_shell dumb "$shell" "$script" _HI_PROMPT_TOOL=hi XDG_CONFIG_HOME="$x" RC_PS1="$own")"
  [[ "$theirs" == "$own" && "$mine" != "$own" ]] || {
    _hi_cecho " | $shell drew [$theirs] unnamed, [$mine] with hi named" "$RED"
    return 1
  }
}

# <shell> <stays|drawn> <PS1> [NAME=VALUE...] - the $PS1 the rc left before
# hi's: the user's own stays at home, and the shell's or a distro's default,
# or any on a target, is drawn over (GLOSSARY: HI.32)
function test_rc_prompt() {
  local shell="$1" want="$2" ps1="$3" script out
  shift 3
  case "$shell" in
  bash) script='PS1=$RC_PS1; source "$_HI_HOME/say-hi/common/bash.sh" >/dev/null 2>&1; eval "${PROMPT_COMMAND:-}" >/dev/null; printf %s "$PS1"' ;;
  zsh) script='PS1=$RC_PS1; source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1; print -rn -- "$PS1"' ;;
  esac
  out="$(_hi_rc_shell dumb "$shell" "$script" _HI_PROMPT_TOOL=powerlevel10k RC_PS1="$ps1" "$@")"
  case "$want" in
  stays) [ "$out" = "$ps1" ] ;;
  *) [[ "$out" != "$ps1" && "$out" == *__hi_env_info* ]] ;;
  esac || {
    _hi_cecho " | $shell, wanting $want, drew [$out] over [$ps1]" "$RED"
    return 1
  }
}

# hi's own prompt from an earlier load is nobody's hand-written one: the rc
# sourced again draws again, so an upgraded tree's prompt code is the one
# running (GLOSSARY: HI.60)
function test_rc_prompt_redraws_on_a_re_source() {
  local shell="$1" script out
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" >/dev/null 2>&1; eval "$PROMPT_COMMAND" >/dev/null; unset -f __hi_ps1; source "$_HI_HOME/say-hi/common/bash.sh" >/dev/null 2>&1; declare -F __hi_ps1' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1; unfunction __hi_git_precmd; source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1; print -rn -- "${+functions[__hi_git_precmd]}"' ;;
  esac
  out="$(_hi_rc_shell dumb "$shell" "$script" _HI_PROMPT_TOOL=powerlevel10k)"
  [ "$out" = __hi_ps1 ] || [ "$out" = 1 ] || _hi_why out
}

# <shell> <want glob> <before-rc script> [NAME=VALUE...] - the prompt drawn
# once hi's rc and one round of its per-draw hooks ran, then `|` and what `ls`
# is aliased to, with the tool aliases opted into so hi's ls is there to win
function test_prompt_program_draws() {
  local shell="$1" want="$2" pre="$3" script out h
  shift 3
  h="$(_hi_fw_home)"
  case "$shell" in
  bash) script="$pre"'; source "$_HI_HOME/say-hi/common/bash.sh" 2>&1; eval "${PROMPT_COMMAND:-}"; printf "%s|%s" "$PS1" "$(alias ls)"' ;;
  zsh) script="$pre"'; source "$_HI_HOME/say-hi/common/zsh.zsh" 2>&1; for f in $precmd_functions; do $f; done; print -rn -- "$PS1|$aliases[ls]"' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>&1; fish_prompt' ;;
  esac
  out="$(_hi_rc_shell dumb "$shell" "$script" HOME="$h" _HI_CONFIG_DIR="$h/cfg" _HI_TOOL_ALIASES=1 \
    PATH="$(_hi_stub_bin powerline-go 'printf "PLGO %s" "$*"'):$PATH" "$@")"
  # shellcheck disable=SC2053 # $want is a pattern
  [[ "$out" == $want && "$out" != *FW-LS* ]] || {
    _hi_cecho " | $shell drew: [$out]" "$RED"
    return 1
  }
}

# oh-my-bash, loaded by hi, takes every alias down with its own; the ones
# there before it are put back as they were, a quote in a value included
function test_oh_my_bash_keeps_an_alias_with_a_quote() {
  local out h
  h="$(_hi_fw_home)"
  out="$(_hi_rc_shell dumb bash 'alias say="$RC_ALIAS"; source "$_HI_HOME/say-hi/common/bash.sh" 2>&1
    printf "%s|%s" "$(alias say)" "$(alias ls)"' HOME="$h" _HI_CONFIG_DIR="$h/cfg" _HI_TOOL_ALIASES=1 \
    _HI_PROMPT_TOOL=oh-my-bash _HI_REMOTE_SESSION=1 RC_ALIAS="echo it's 'here'")"
  [[ "$out" == "alias say='echo it'\\''s '\\''here'\\'''|"* && "$out" != *FW-LS* ]] || _hi_because "the aliases: [$out]"
}

# a target is sent only the loaders of the frameworks it is handed (pack.sh's
# _hi_payload_excl), so a framework whose loader is missing is passed over
# for the next in the list, hi's prompt at the end of it
function test_prompt_framework_without_its_loader_is_passed_over() {
  local shell="$1" fw="$2" want="$3" base
  base="$(mktemp -d "$_HI_WORKDIR/noloader.XXXXXX")" || return 1
  mkdir -p "$base/say-hi"
  cp -R "$_HI_ROOT/common" "$_HI_ROOT/config" "$base/say-hi/"
  rm -f "$base/say-hi/common/fw_$fw".*
  test_prompt_program_draws "$shell" "$want" : _HI_PROMPT_TOOL="$fw" _HI_REMOTE_SESSION=1 _HI_HOME="$base"
}

function test_fish_registers_hi_completion() {
  # fish echoes the registration back without the -c flag, so match on the
  # target-list wiring instead
  _hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c hi' |
    grep -qF '$_HI_TARGETS' || _hi_why
}

# zsh colors the target list by backend through the hi-targets tag's
# list-colors, matched on each display line's leading kind; none under
# $NO_COLOR, and a zstyle of the user's own is left alone
function test_zsh_target_list_colors_per_backend() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -l -- $lc')"
  [[ "$out" == *"=* ssh - *=0;33"* && "$out" == *"docker|"*") - *=0;34"* &&
    "$out" == *"=* nomad - *=0;32"* && "$out" == *"=* kube - *=1;35"* ]] || {
    _hi_cecho " | list-colors: ${out//$'\n'/ }" "$RED"
    return 1
  }
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -r -- ${#lc}' NO_COLOR=1)"
  [ "$out" = 0 ] || _hi_why out || return 1
  out="$(_hi_rc_shell xterm-256color zsh '
    zstyle ":completion:*:hi-targets" list-colors "=*=31"
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -r -- "$lc"')"
  [ "$out" = "=*=31" ] || _hi_why out
}

# zsh expands hi's own `hi` alias before completing, so the launcher's name
# is registered too, or `hi <TAB>` falls through to file completion. compinit
# is the rc's: <before|after> runs it ahead of hi's block (compdef registers
# _hi) or behind it (compinit reads common/_hi's #compdef line off $fpath).
function test_zsh_completion_covers_the_alias_target() {
  local init='autoload -Uz compinit && compinit -u -D' before="" after="" out
  if [ "$1" = before ]; then before="$init"; else after="$init"; fi
  out="$(_hi_rc_shell xterm-256color zsh "
    $before
    source \$_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    $after
    print -r -- \"\${_comps[hi]}:\${_comps[hi.sh]}\"")"
  [ "$out" = "_hi:_hi" ] || {
    _hi_cecho " | compinit $1: _comps[hi]:_comps[hi.sh] = $out" "$RED"
    return 1
  }
}

# ...and the target branch goes through _description with that tag, which is
# what applies the style: a seeded cache, the completion builtins stubbed
function test_zsh_target_completion_uses_the_colored_tag() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    autoload -Uz _hi
    _description() { print -r -- "desc $*"; expl=(-V -default-); }
    compadd() { print -r -- "compadd $*"; }
    _HI_TARGET_ROWS=(web) _HI_TARGET_DESCS=("docker - web") _HI_TARGET_ROWS_AT=$SECONDS
    words=(hi ""); CURRENT=2
    _hi')"
  [[ "$out" == *"desc -V hi-targets expl target"* &&
    "$out" == *"compadd -V -default- -d _HI_TARGET_DESCS -a _HI_TARGET_ROWS"* ]] || {
    _hi_cecho " | got: ${out//$'\n'/ | }" "$RED"
    return 1
  }
}

# _hi_bash_listing <COMP_TYPE> <word> [NAME=VALUE...] - _hi_complete's
# COMPREPLY for <word>, "|"-joined, over a seeded target cache
function _hi_bash_listing() {
  local type="$1" word="$2"
  shift 2
  _hi_rc_shell dumb bash "
    source \"\$_HI_HOME/say-hi/common/bash.sh\" 2>/dev/null
    _HI_TARGET_ROWS=(web\$'\\t'docker web2\$'\\t'podman jobx\$'\\t'nomad podx\$'\\t'kube sshy\$'\\t'ssh dup\$'\\t'ssh dup\$'\\t'docker)
    _HI_TARGET_ROWS_AT=\$SECONDS
    COMP_WORDS=(hi '$word') COMP_CWORD=1 COMP_TYPE=$type
    _hi_complete
    IFS='|'
    printf '%s' \"\${COMPREPLY[*]}\"" "$@"
}

# bash lists each target's backend symbol only while readline lists (63),
# never when it inserts (9); a name two backends share is listed once with
# both symbols; ASCII stand-ins off a UTF-8 locale; $_HI_SYMBOL_* wins.
# GLOSSARY: HI.56
function test_bash_target_symbols_only_when_listing() {
  local out
  out="$(_hi_bash_listing 63 '' LANG=C.UTF-8)"
  [ "$out" = "web ▣|web2 ▣|jobx ◆|podx ⎈|sshy »|dup »▣" ] || {
    _hi_cecho " | listing: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 9 w LANG=C.UTF-8)"
  [ "$out" = "web|web2" ] || {
    _hi_cecho " | inserting: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 d LANG=C.UTF-8)"
  [ "$out" = dup ] || {
    _hi_cecho " | one shared name: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 '')"
  [ "$out" = "web #|web2 #|jobx *|podx @|sshy >|dup >#" ] || {
    _hi_cecho " | ascii: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 '' LANG=C.UTF-8 _HI_SYMBOL_KUBE=k8s)"
  [[ "$out" == *"|podx k8s|"* ]] || _hi_why out
}

# fish's target rows carry the backend's symbol ahead of the kind, the
# description fish shows beside each name; $_HI_SYMBOL_* wins
function test_fish_target_symbols() {
  local fixture="$_HI_WORKDIR/targets-fixture.sh" out
  printf '%s\n' "printf 'web\\tdocker\\njobx\\tnomad\\npodx\\tkube\\nsshy\\tssh\\n'" >"$fixture"
  out="$(_hi_rc_shell dumb fish "source \$_HI_HOME/say-hi/common/config.fish 2>/dev/null
    set _HI_TARGETS $fixture
    __hi_targets" LANG=C.UTF-8 _HI_SYMBOL_SSH=S)"
  [ "$out" = $'web\t▣ docker\njobx\t◆ nomad\npodx\t⎈ kube\nsshy\tS ssh' ] || {
    _hi_cecho " | __hi_targets: ${out//$'\n'/ | }" "$RED"
    return 1
  }
}

# _hi_greet <shell> <i|c|s> [NAME=VALUE...] - how many times <shell> prints
# the Online header sourcing hi's rc: typed in (i, from stdin), `-i -c` (c),
# or as a script (s); settings.sh trims the header to one cell, no probes
function _hi_greet() {
  local shell="$1" rc=bash.sh cfg="$_HI_WORKDIR/greet"
  local -a args=(--norc)
  [ "$shell" = zsh ] && rc=zsh.zsh args=(-f)
  local src="source \"\$_HI_HOME/say-hi/common/$rc\""
  case "$2" in i) args+=(-i) ;; c) args+=(-i -c "$src") ;; esac
  shift 2
  mkdir -p "$cfg" && printf 'export _HI_HEADER_ORDER=utc\n' >"$cfg/settings.sh"
  printf '%s\n' "$src" | env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$cfg" "$@" "$shell" "${args[@]}" 2>/dev/null |
    grep -c Online || true
}

# a local interactive bash and zsh greet with hi's header, as fish does -
# once; never `-i -c` or a script (fish greets neither), a target session,
# or under the toggle
function test_local_shell_prints_the_header() {
  local shell=$1
  [ "$(_hi_greet "$shell" i)" = 1 ] && [ "$(_hi_greet "$shell" c)" = 0 ] &&
    [ "$(_hi_greet "$shell" s)" = 0 ] &&
    [ "$(_hi_greet "$shell" i _HI_REMOTE_SESSION=1)" = 0 ] &&
    [ "$(_hi_greet "$shell" i _HI_DISABLE_HEADER=1)" = 0 ] || _hi_why shell
}

# fish does its own prefix matching, so `--preview-c` narrows to one flag, and
# prints it with the roster's help clause after a tab - the description fish
# shows beside the flag. A line that does not start with a dash would be a
# target row ("<name>\t<kind>"), which is the sweep the -n guard exists to
# keep out of a dash word.
function test_fish_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color fish '
    source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    complete -C "hi --pl"
  ')"
  printf '%s\n' "$out" | grep -q "^--plain$(printf '\t')a bare shell" || _hi_why out || return 1
  if printf '%s\n' "$out" | grep -qv '^-'; then
    _hi_cecho "   a dash word also swept the targets" "$RED"
    return 1
  fi
  return 0
}

# the word after --preview: fish's own condition picks the words roster, and
# the target sweep (any line not in the roster) stays out
function test_fish_completes_the_word_after_preview() {
  local out
  out="$(_hi_rc_shell xterm-256color fish '
    source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    complete -C "hi --preview "
  ')"
  printf '%s\n' "$out" | grep -q "^header$(printf '\t')the connect header" || _hi_why out || return 1
  printf '%s\n' "$out" | grep -q "^colors$(printf '\t')" || _hi_why out || return 1
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 3 ] || _hi_why out
}

function _hi_rc_reentry() {
  local shell="$1" member="$2" probe="$3" cfg="$_HI_WORKDIR/reentry-$1" rc
  rc="$(_hi_rc_of_member "$member")"
  mkdir -p "$cfg"
  printf 'source "%s"\n' "$_HI_HOME/say-hi/common/$rc" >"$cfg/$member"
  (exec env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" _HI_HOME="$_HI_HOME" _HI_PROMPT_TOOL=hi \
    _HI_CONFIG_DIR="$cfg" "$shell" -c "source \"\$_HI_HOME/say-hi/common/$rc\"; $probe" \
    </dev/null >"$cfg.out" 2>&1) &
  _hi_wait_pid $! 20
  [ "$_HI_WAIT_EXIT" != 124 ] && cat "$cfg.out"
}

# test_sh_rc_reentry_returns <shell> <rc>
function test_sh_rc_reentry_returns() {
  [ "$(_hi_rc_reentry "$1" "$2" 'printf %s "${_hi_rc_loading-done}:${_HI_ROOT:+root}"')" = done:root ] || _hi_why _hi_rc_loading
}

function test_fish_rc_reentry_returns() {
  [ "$(_hi_rc_reentry fish config.fish 'set -q _hi_rc_loading; or printf done; test -n "$_HI_ROOT"; and printf :root')" = done:root ] || _hi_why
}

# test_sh_rc_re_source_after_an_upgrade <shell> <rc>
# GLOSSARY: HI.60. A shell outlives the tree under it: `hi --update` rewrites
# say-hi in place, tmux panes last weeks, and the usual reflex is a
# `tmux send-keys ... 'source ~/.bashrc'` into every one of them at once.
# core.sh's load guard would make that second source a no-op and leave the new
# tree's code running on the old tree's paths, so the rc clears it. The scratch
# tree grows a path between the two sources, which is exactly what an upgrade
# looks like from inside such a shell.
function test_sh_rc_re_source_after_an_upgrade() {
  local shell="$1" rc="$2" base="$_HI_WORKDIR/upgrade-$1"
  rm -rf "$base" "$base.out"
  mkdir -p "$base/say-hi" "$base/cfg"
  cp -R "$_HI_ROOT/common" "$_HI_ROOT/config" "$base/say-hi/"
  (exec env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" _HI_HOME="$base" _HI_PROMPT_TOOL=hi \
    _HI_CONFIG_DIR="$base/cfg" "$shell" -c "
      source \"\$_HI_HOME/say-hi/common/$rc\"
      printf '%s|' \"\${_HI_ADDED_LATER-unset}\"
      printf 'export _HI_ADDED_LATER=\"\$_HI_ROOT/added\"\n' >>\"\$_HI_HOME/say-hi/common/paths.sh\"
      source \"\$_HI_HOME/say-hi/common/$rc\"
      printf '%s' \"\${_HI_ADDED_LATER-unset}\"" \
    </dev/null >"$base.out" 2>/dev/null) &
  _hi_wait_pid $! 20
  [ "$(cat "$base.out")" = "unset|$base/say-hi/added" ] || _hi_why base
}

function test_fish_flag_completion_does_not_also_sweep_targets() {
  local out
  out="$(_hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c hi')"
  # the bare-target line is guarded, and the flags line still is too
  { printf '%s\n' "$out" | grep -qF 'not string match -q -- "-*"' &&
    printf '%s\n' "$out" | grep -qF '$_HI_TARGETS flags'; } || _hi_why out
}

# _hi_prompt_ends <as_root> <shell> <want> [NAME=VALUE ...] - does the prompt
# the shell builds with those pairs set end with <want>? The trailing space
# every separator carries comes off before the tail is compared. The one
# predicate behind every separator case; the scenarios live with their
# registrations.
function _hi_prompt_ends() {
  local as_root="$1" shell="$2" want="$3" out
  shift 3
  out="$(_HI_AS_ROOT="$as_root" _hi_prompt_tail "$shell" "$@")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

#
# fish cannot call a bash helper, so common/config.fish carries its own copy of
# common/core.sh's overlay-directory resolution. Two copies of one decision is
# exactly the shape that drifts, so these cases run fish's and compare with the
# answers tests/common/core_test.sh pins bash's against.
#
# _HI_CONFIG_DIR has to come out of the environment here (the helper above sets
# it for every other case), which is why this runs fish directly.
function _hi_fish_cfg_answer() {
  local base="$_HI_WORKDIR/fishxdg.$1" out
  rm -rf "$base"
  mkdir -p "$base"
  case "$1" in
  new) mkdir -p "$base/say-hi" ;;
  esac
  out="$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
  printf '%s' "${out#"$base/"}"
}

function test_fish_config_dir_matches_bash() {
  [ "$(_hi_fish_cfg_answer neither)" = say-hi ] &&
    [ "$(_hi_fish_cfg_answer new)" = say-hi ] || _hi_why
}

# hi.sh points a target at its shipped overlay; fish must honour that too
function test_fish_config_dir_explicit_value_wins() {
  local base="$_HI_WORKDIR/fishxdg.explicit" out
  rm -rf "$base"
  mkdir -p "$base/say-hi"
  out="$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" _HI_CONFIG_DIR="$base/shipped" \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
  [ "$out" = "$base/shipped" ] || _hi_why out base
}

function run_rc_prompt_tests() {
  _hi_rc_begin

  _hi_h1 "Testing common/bash.sh, zsh.zsh, and config.fish behavior (the prompt)"

  _hi_h2 "Testing: prompt handoff (_HI_PROMPT_TOOL=starship / oh-my-posh)"
  _hi_check "[bash] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked bash starship
  _hi_check "[bash] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked bash oh-my-posh
  _hi_check "[bash] keeps hi's prompt without the setting" test_bash_keeps_hi_prompt_without_the_setting
  _hi_check "[bash] falls back silently when absent" test_bash_falls_back_when_starship_is_absent
  _hi_check "[bash] a target points the tool at the overlay's config" test_remote_session_exports_overlay_config bash starship.toml STARSHIP_CONFIG "$_HI_WORKDIR/cfg/starship.toml" PATH="$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship
  _hi_check "[bash] a target points eza at the overlay's theme" test_remote_session_exports_overlay_config bash eza/theme.yml EZA_CONFIG_DIR "$_HI_WORKDIR/cfg/eza"
  _hi_check "[bash] a target points bat at the overlay's config" test_remote_session_exports_overlay_config bash bat/config BAT_CONFIG_PATH "$_HI_WORKDIR/cfg/bat/config"
  _hi_check "[bash] a target points readline at the overlay's inputrc" test_remote_session_exports_overlay_config bash inputrc INPUTRC "$_HI_WORKDIR/cfg/inputrc"
  _hi_check "[bash] a target points ripgrep at the overlay's ripgreprc" test_remote_session_exports_overlay_config bash ripgreprc RIPGREP_CONFIG_PATH "$_HI_WORKDIR/cfg/ripgreprc"
  _hi_check "[bash] a target points fzf at the overlay's fzfrc" test_remote_session_exports_overlay_config bash fzfrc FZF_DEFAULT_OPTS_FILE "$_HI_WORKDIR/cfg/fzfrc"
  _hi_check "[bash] a target points lazygit at the overlay's config" test_remote_session_exports_overlay_config bash lazygit/config.yml LG_CONFIG_FILE "$_HI_WORKDIR/cfg/lazygit/config.yml"
  _hi_check "[bash] a target points kakoune at the overlay's kakrc" test_remote_session_exports_overlay_config bash kak/kakrc KAKOUNE_CONFIG_DIR "$_HI_WORKDIR/cfg/kak"
  _hi_check "[bash] a target's load.sh is handed the overlay's vimrc" test_remote_session_exports_overlay_config bash vim/vimrc _HI_VIMRC "$_HI_WORKDIR/cfg/vim/vimrc"
  _hi_check "[bash] a target points oh-my-posh at the overlay's config" test_remote_session_exports_overlay_config bash oh-my-posh.yaml POSH_CONFIG "$_HI_WORKDIR/cfg/oh-my-posh.yaml"
  _hi_check "[bash] a target's tmux is common/mux.sh's to start" test_remote_session_aliases_overlay_config bash tmux/tmux.conf tmux "common/mux.sh tmux"
  _hi_check "[bash] ...and never the target's own" test_remote_session_aliases_overlay_config bash - tmux "" .tmux.conf
  _hi_check "[bash] a target's screen is common/mux.sh's to start" test_remote_session_aliases_overlay_config bash screenrc screen "common/mux.sh screen"
  _hi_check "[bash] a target's zellij is common/mux.sh's to start" test_remote_session_aliases_overlay_config bash zellij/config.kdl zellij "common/mux.sh zellij"
  _hi_check "[bash] a target's micro is left alone without a micro/" test_remote_session_aliases_overlay_config bash - micro "" micro
  _hi_check "[bash] a target's micro reads the overlay's micro/" test_remote_session_aliases_overlay_config bash micro/settings.json micro "micro -backup false -savehistory false -config-dir $_HI_WORKDIR/cfg/micro"
  _hi_check_requires zsh "[zsh] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked zsh starship
  _hi_check_requires zsh "[zsh] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked zsh oh-my-posh
  _hi_check_requires fish "[fish] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked fish starship
  _hi_check_requires fish "[fish] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked fish oh-my-posh
  _hi_check_requires fish "[fish] a target points the tool at the overlay's config" test_remote_session_exports_overlay_config fish starship.toml STARSHIP_CONFIG "$_HI_WORKDIR/cfg/starship.toml" PATH="$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship
  _hi_check_requires fish "[fish] a target points eza at the overlay's theme" test_remote_session_exports_overlay_config fish eza/theme.yml EZA_CONFIG_DIR "$_HI_WORKDIR/cfg/eza"
  _hi_check_requires fish "[fish] a target points bat at the overlay's config" test_remote_session_exports_overlay_config fish bat/config BAT_CONFIG_PATH "$_HI_WORKDIR/cfg/bat/config"
  _hi_check_requires fish "[fish] a target points readline at the overlay's inputrc" test_remote_session_exports_overlay_config fish inputrc INPUTRC "$_HI_WORKDIR/cfg/inputrc"
  _hi_check_requires fish "[fish] a target points ripgrep at the overlay's ripgreprc" test_remote_session_exports_overlay_config fish ripgreprc RIPGREP_CONFIG_PATH "$_HI_WORKDIR/cfg/ripgreprc"
  _hi_check_requires fish "[fish] a target points fzf at the overlay's fzfrc" test_remote_session_exports_overlay_config fish fzfrc FZF_DEFAULT_OPTS_FILE "$_HI_WORKDIR/cfg/fzfrc"
  _hi_check_requires fish "[fish] a target points lazygit at the overlay's config" test_remote_session_exports_overlay_config fish lazygit/config.yml LG_CONFIG_FILE "$_HI_WORKDIR/cfg/lazygit/config.yml"
  _hi_check_requires fish "[fish] a target points kakoune at the overlay's kakrc" test_remote_session_exports_overlay_config fish kak/kakrc KAKOUNE_CONFIG_DIR "$_HI_WORKDIR/cfg/kak"
  _hi_check_requires fish "[fish] a target's session is handed the overlay's vimrc" test_remote_session_exports_overlay_config fish vim/vimrc _HI_VIMRC "$_HI_WORKDIR/cfg/vim/vimrc"
  _hi_check_requires fish "[fish] a target points oh-my-posh at the overlay's config" test_remote_session_exports_overlay_config fish oh-my-posh.toml POSH_CONFIG "$_HI_WORKDIR/cfg/oh-my-posh.toml"
  _hi_check_requires fish "[fish] a target's tmux is common/mux.sh's to start" test_remote_session_aliases_overlay_config fish tmux/tmux.conf tmux "common/mux.sh tmux"
  _hi_check_requires fish "[fish] a target's screen is common/mux.sh's to start" test_remote_session_aliases_overlay_config fish screenrc screen "common/mux.sh screen"
  _hi_check_requires fish "[fish] a target's zellij is common/mux.sh's to start" test_remote_session_aliases_overlay_config fish zellij/config.kdl zellij "common/mux.sh zellij"
  _hi_check_requires fish "[fish] a target's micro is left alone without a micro/" test_remote_session_aliases_overlay_config fish - micro "" micro
  _hi_check_requires fish "[fish] a target's micro reads the overlay's micro/" test_remote_session_aliases_overlay_config fish micro/settings.json micro "micro -backup false -savehistory false -config-dir $_HI_WORKDIR/cfg/micro"
  _hi_check_requires fish "[fish] the sudo wrapper follows _HI_SUDO_ALIAS" test_fish_sudo_wrapper_follows_the_toggle
  _hi_check "[bash] at home the tools' own configs leave them unaliased" test_home_session_aliases_only_his_configs bash own
  _hi_check "[bash] ...and with no config, none at all" test_home_session_aliases_only_his_configs bash none
  _hi_check_requires zsh "[zsh] at home the tools' own configs leave them unaliased" test_home_session_aliases_only_his_configs zsh own
  _hi_check_requires zsh "[zsh] ...and with no config, none at all" test_home_session_aliases_only_his_configs zsh none
  _hi_check_requires fish "[fish] at home the tools' own configs leave them unaliased" test_home_session_aliases_only_his_configs fish own
  _hi_check_requires fish "[fish] ...and with no config, none at all" test_home_session_aliases_only_his_configs fish none

  _hi_h2 "Testing: prompt programs without init (powerline-go, the frameworks)"
  _hi_check "[bash] powerline-go draws each prompt with the status and options" \
    test_prompt_program_draws bash 'PLGO -shell bash -error * -jobs 0 -mode flat|*' : _HI_PROMPT_TOOL=powerline-go _HI_POWERLINE_GO_OPTS="-mode flat"
  _hi_check "[bash] oh-my-bash, loaded by hi, draws the home theme on a target" \
    test_prompt_program_draws bash 'OMB|*' : _HI_PROMPT_TOOL=oh-my-bash _HI_REMOTE_SESSION=1
  _hi_check "[bash] ...putting back an alias whose value holds a quote" test_oh_my_bash_keeps_an_alias_with_a_quote
  _hi_check "[bash] ...and puts back the aliases set before it" test_oh_my_bash_puts_the_aliases_back
  _hi_check "[bash] ...at home, with no theme to draw, hi's prompt stays" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' : _HI_PROMPT_TOOL=oh-my-bash
  _hi_check "[bash] ...loaded by the rc, its prompt stays at home" \
    test_prompt_program_draws bash 'RC-OMB|*' '_omb_module_require() { :; }; PS1=RC-OMB' _HI_PROMPT_TOOL=oh-my-bash
  _hi_check "[bash] ...a target sent no loader for it keeps hi's prompt" \
    test_prompt_framework_without_its_loader_is_passed_over bash oh-my-bash '*\\u@\\h:\\w*'
  _hi_check "[bash] bash-it, loaded by hi, draws the home theme on a target" \
    test_prompt_program_draws bash 'BASHIT|*' : _HI_PROMPT_TOOL=bash-it _HI_REMOTE_SESSION=1
  _hi_check "[bash] ...at home, with no theme to draw, hi's prompt stays" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' : _HI_PROMPT_TOOL=bash-it
  _hi_check "[bash] ...loaded by the rc, its precmd hands over to the home theme" test_bash_it_from_the_rc_hands_over_its_precmd
  _hi_check "[bash] a list's first program that fits the shell wins" \
    test_prompt_program_draws bash 'OMB|*' : _HI_PROMPT_TOOL="tide powerlevel10k oh-my-bash" _HI_REMOTE_SESSION=1
  _hi_check "[bash] a name hi does not know keeps hi's prompt" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' : _HI_PROMPT_TOOL=powerline
  _hi_check_requires zsh "[zsh] powerline-go draws each prompt with the status and options" \
    test_prompt_program_draws zsh 'PLGO -shell zsh -error * -jobs 0 -mode flat|*' : _HI_PROMPT_TOOL=powerline-go _HI_POWERLINE_GO_OPTS="-mode flat"
  _hi_check_requires zsh "[zsh] powerlevel10k, loaded by hi, takes the home config on a target" \
    test_prompt_program_draws zsh 'P10K+CFG|*' : _HI_PROMPT_TOOL=powerlevel10k _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] ...loaded by the rc, the home config goes over the target's" \
    test_prompt_program_draws zsh 'RC+CFG|*' 'p10k() { :; }; PROMPT=RC' _HI_PROMPT_TOOL=powerlevel10k _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] oh-my-zsh's libraries, loaded by hi, draw the home theme" \
    test_prompt_program_draws zsh 'OMZ-G|*' : _HI_PROMPT_TOOL=oh-my-zsh _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] ...at home, with no theme to draw, hi's prompt stays" \
    test_prompt_program_draws zsh '*%n@%m*' : _HI_PROMPT_TOOL=oh-my-zsh
  _hi_check_requires zsh "[zsh] ...a target sent no loader for it keeps hi's prompt" \
    test_prompt_framework_without_its_loader_is_passed_over zsh oh-my-zsh '*%n@%m*'
  _hi_check_requires fish "[fish] powerline-go draws each prompt with the status and options" \
    test_prompt_program_draws fish 'PLGO -shell bare -error 0 -jobs 0 -mode flat' : _HI_PROMPT_TOOL=powerline-go _HI_POWERLINE_GO_OPTS="-mode flat"
  _hi_check_requires fish "[fish] tide draws with the home variables, exported, on a target" \
    test_prompt_program_draws fish 'TIDE:❯:2:0:3' : _HI_PROMPT_TOOL=tide _HI_REMOTE_SESSION=1 LANG=C.UTF-8
  _hi_check_requires fish "[fish] ...and with its own at home" \
    test_prompt_program_draws fish 'TIDE::0:0:0' : _HI_PROMPT_TOOL=tide LANG=C.UTF-8
  _hi_check "[bash] unset, a framework found here keeps its prompt" \
    test_prompt_program_draws bash 'RC-OMB|*' '_omb_module_require() { :; }; PS1=RC-OMB' _HI_PROMPT_TOOL=
  _hi_check "[bash] ...but a target looks at nothing of its own" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' '_omb_module_require() { :; }; PS1=RC-OMB' _HI_PROMPT_TOOL= _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] hi named takes the prompt back from a loaded framework, precmd and all" \
    test_prompt_program_draws zsh '*%n@%m*' 'p10k() { :; }; _p9k_precmd() { PROMPT=RC; }; precmd_functions+=(_p9k_precmd); PROMPT=RC' _HI_PROMPT_TOOL=hi
  _hi_check_requires zsh "[zsh] ...unset, the rc's own program keeps its precmd" \
    test_prompt_program_draws zsh '*RC|*' 'starship_precmd() { PROMPT=RC; }; precmd_functions+=(starship_precmd)' _HI_PROMPT_TOOL= _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] hi named takes the prompt back from starship's >=1.3.0 zsh hook name" \
    test_prompt_program_draws zsh '*%n@%m*' 'prompt_starship_precmd() { PROMPT=RC; }; precmd_functions+=(prompt_starship_precmd)' _HI_PROMPT_TOOL=hi
  _hi_check_requires zsh "[zsh] ...unset, starship's current-name precmd keeps drawing" \
    test_prompt_program_draws zsh '*RC|*' 'prompt_starship_precmd() { PROMPT=RC; }; precmd_functions+=(prompt_starship_precmd)' _HI_PROMPT_TOOL= _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] at home, powerlevel10k installed but not loaded stays off" \
    test_prompt_program_draws zsh '*%n@%m*' : _HI_PROMPT_TOOL=powerlevel10k
  _hi_check "[bash] hi named takes the prompt back from the rc's starship hook" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' 'starship_precmd() { PS1=STAR; }; PROMPT_COMMAND=starship_precmd' _HI_PROMPT_TOOL=hi
  _hi_check "[bash] ...unset, the rc's own program keeps its hook" \
    test_prompt_program_draws bash '*STAR|*' 'starship_precmd() { PS1=STAR; }; PROMPT_COMMAND=starship_precmd' _HI_PROMPT_TOOL= _HI_REMOTE_SESSION=1
  _hi_check "[bash] hi named clears bash-it's precmd_functions array, not just PROMPT_COMMAND" \
    test_prompt_program_draws bash '*\\u@\\h:\\w*' 'prompt_command() { PS1=RC; }; precmd_functions=(prompt_command); __hi_test_dispatch() { local f; for f in "${precmd_functions[@]}"; do "$f"; done; }; PROMPT_COMMAND=__hi_test_dispatch' _HI_PROMPT_TOOL=hi
  _hi_check "[bash] ...unset, bash-it's array-held hook keeps drawing" \
    test_prompt_program_draws bash '*RC|*' 'prompt_command() { PS1=RC; }; precmd_functions=(prompt_command); __hi_test_dispatch() { local f; for f in "${precmd_functions[@]}"; do "$f"; done; }; PROMPT_COMMAND=__hi_test_dispatch' _HI_PROMPT_TOOL= _HI_REMOTE_SESSION=1
  _hi_check_requires fish "[fish] unset, tide found here draws" \
    test_prompt_program_draws fish 'TIDE::0:0:0' : _HI_PROMPT_TOOL= LANG=C.UTF-8
  _hi_check_requires fish "[fish] a program that does not fit fish keeps hi's prompt" \
    test_prompt_program_draws fish '*@*' : _HI_PROMPT_TOOL="oh-my-bash powerlevel10k" XDG_CONFIG_HOME="$_HI_WORKDIR/noprompt"
  # one setting, a program per shell: bash:starship is bash's alone
  _hi_check "[bash] bash:starship hi draws starship in bash, at home" \
    test_prompt_program_draws bash 'PROMPT-STUB|*' : _HI_PROMPT_TOOL="bash:starship hi" PATH="$(_hi_prompt_stub_dir starship):$PATH"
  _hi_check "[bash] ...and on a target" \
    test_prompt_program_draws bash 'PROMPT-STUB|*' : _HI_PROMPT_TOOL="bash:starship hi" _HI_REMOTE_SESSION=1 PATH="$(_hi_prompt_stub_dir starship):$PATH"
  _hi_check_requires zsh "[zsh] ...and hi's prompt in zsh" \
    test_prompt_program_draws zsh '*%n@%m*' : _HI_PROMPT_TOOL="bash:starship hi" _HI_REMOTE_SESSION=1 PATH="$(_hi_prompt_stub_dir starship):$PATH"
  _hi_check_requires fish "[fish] ...and in fish" \
    test_prompt_program_draws fish '*@*' : _HI_PROMPT_TOOL="bash:starship hi" _HI_REMOTE_SESSION=1 PATH="$(_hi_prompt_stub_dir starship):$PATH" XDG_CONFIG_HOME="$_HI_WORKDIR/noprompt"
  _hi_check "[bash] liquidprompt's prompt stays, unless hi is named" \
    test_foreign_prompt_stays_unless_hi_named bash '_LP_VERSION=(2 3 0)'
  _hi_check "[bash] ...and bash-git-prompt's" \
    test_foreign_prompt_stays_unless_hi_named bash 'setGitPrompt() { :; }'
  _hi_check_requires zsh "[zsh] a promptinit theme stays, unless hi is named" \
    test_foreign_prompt_stays_unless_hi_named zsh 'prompt_theme=(adam1)'
  _hi_check_requires zsh "[zsh] ...and spaceship's, and pure's" \
    test_foreign_prompt_stays_unless_hi_named zsh 'SPACESHIP_VERSION=4; prompt_pure_setup() { :; }'
  _hi_check_requires fish "[fish] a fish_prompt of the user's own stays, unless hi is named" \
    test_foreign_prompt_stays_unless_hi_named fish :
  _hi_check "[bash] a PS1 of the user's own stays at home" test_rc_prompt bash stays '\[\e[1;32m\]\u\[\e[0m\] \w \$ '
  _hi_check "[bash] ...unless hi is named" test_rc_prompt bash drawn '\[\e[1;32m\]\u\[\e[0m\] \w \$ ' _HI_PROMPT_TOOL=hi
  _hi_check "[bash] ...and a target's rc is not asked" test_rc_prompt bash drawn '\[\e[1;32m\]\u\[\e[0m\] \w \$ ' _HI_REMOTE_SESSION=1
  _hi_check "[bash] bash's own default is drawn over" test_rc_prompt bash drawn '\s-\v\$ '
  _hi_check "[bash] ...and Debian's, behind its xterm title" test_rc_prompt bash drawn \
    '\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
  _hi_check "[bash] ...and its plain one" test_rc_prompt bash drawn '${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
  _hi_check "[bash] ...and Fedora's and Arch's" test_rc_prompt bash drawn '[\u@\h \W]\$ '
  _hi_check "[bash] ...and Git Bash's, by its title" test_rc_prompt bash drawn \
    '\[\033]0;$TITLEPREFIX:$PWD\007\]\n\[\033[32m\]\u@\h \[\033[35m\]$MSYSTEM \[\033[33m\]\w\[\033[0m\]\n$ '
  _hi_check "[bash] ...and MSYS2's and Cygwin's" test_rc_prompt bash drawn \
    '\[\e]0;\w\a\]\n\[\e[32m\]\u@\h \[\e[35m\]$MSYSTEM\[\e[0m\] \[\e[33m\]\w\[\e[0m\]\n\$ '
  _hi_check "[bash] ...and Termux's" test_rc_prompt bash drawn '\[\e[0;32m\]\w\[\e[0m\] \[\e[0;97m\]\$\[\e[0m\] '
  _hi_check "[bash] the rc sourced again draws over hi's own" test_rc_prompt_redraws_on_a_re_source bash
  _hi_check_requires zsh "[zsh] a PROMPT of the user's own stays at home" test_rc_prompt zsh stays '%F{green}%n%f %~ %# '
  _hi_check_requires zsh "[zsh] ...unless hi is named" test_rc_prompt zsh drawn '%F{green}%n%f %~ %# ' _HI_PROMPT_TOOL=hi
  _hi_check_requires zsh "[zsh] ...and a target's rc is not asked" test_rc_prompt zsh drawn '%F{green}%n%f %~ %# ' _HI_REMOTE_SESSION=1
  _hi_check_requires zsh "[zsh] zsh's own default is drawn over" test_rc_prompt zsh drawn '%m%# '
  _hi_check_requires zsh "[zsh] ...and Fedora's" test_rc_prompt zsh drawn '[%n@%m]%~%# '
  _hi_check_requires zsh "[zsh] the rc sourced again draws over hi's own" test_rc_prompt_redraws_on_a_re_source zsh
  _hi_check "[bash] extensions load in order, skip loudly, draw a segment" test_extensions_load_in_order_skip_loudly_and_draw bash
  _hi_check_requires zsh "[zsh] extensions load in order, skip loudly, draw a segment" test_extensions_load_in_order_skip_loudly_and_draw zsh
  _hi_check_requires fish "[fish] extensions load in order, skip loudly, draw a segment" test_extensions_load_in_order_skip_loudly_and_draw fish
  _hi_check "[bash] the overlay's aliases.sh is parsed before it loads" test_overlay_aliases_are_parsed_before_they_load bash
  _hi_check_requires zsh "[zsh] the overlay's aliases.sh is parsed before it loads" test_overlay_aliases_are_parsed_before_they_load zsh
  _hi_check_requires fish "[fish] ...and one fish cannot parse is skipped, in a line" test_overlay_aliases_are_parsed_before_they_load fish
  _hi_check_requires fish "fish registers hi completion" test_fish_registers_hi_completion
  _hi_check_requires fish "fish flag TAB does not sweep the backends" test_fish_flag_completion_does_not_also_sweep_targets
  _hi_check_requires fish "fish flag TAB completes hi's options, described" test_fish_flag_completion_offers_hi_options
  _hi_check_requires fish "fish completes the word after --preview" test_fish_completes_the_word_after_preview
  _hi_check_requires fish "fish resolves \$_HI_CONFIG_DIR as bash does" test_fish_config_dir_matches_bash
  _hi_check_requires fish "fish honours an explicit \$_HI_CONFIG_DIR" test_fish_config_dir_explicit_value_wins
  _hi_check "[bash] an overlay re-entering hi's rc returns" test_sh_rc_reentry_returns bash bashrc
  _hi_check "[bash] a re-source after an upgrade re-derives" test_sh_rc_re_source_after_an_upgrade bash bash.sh
  _hi_check_requires zsh "[zsh] a re-source after an upgrade re-derives" test_sh_rc_re_source_after_an_upgrade zsh zsh.zsh
  _hi_check_requires zsh "[zsh] an overlay re-entering hi's rc returns" test_sh_rc_reentry_returns zsh zshrc
  _hi_check_requires zsh "[zsh] the target list is colored per backend" test_zsh_target_list_colors_per_backend
  _hi_check_requires zsh "[zsh] target completion carries the colored tag" test_zsh_target_completion_uses_the_colored_tag
  _hi_check_requires zsh "[zsh] a compinit before hi's block registers hi and its launcher" test_zsh_completion_covers_the_alias_target before
  _hi_check_requires zsh "[zsh] ...and one after it finds common/_hi on \$fpath" test_zsh_completion_covers_the_alias_target after
  _hi_check "[bash] target symbols only while listing" test_bash_target_symbols_only_when_listing
  _hi_check_requires fish "[fish] target rows carry their symbol" test_fish_target_symbols
  _hi_check "[bash] a local interactive shell prints the header" test_local_shell_prints_the_header bash
  _hi_check_requires zsh "[zsh] a local interactive shell prints the header" test_local_shell_prints_the_header zsh
  _hi_check_requires fish "[fish] an overlay re-entering hi's rc returns" test_fish_rc_reentry_returns

  _hi_h2 "Testing: the prompt separator"
  # The shells install.sh wires up locally, and their shipped defaults, both
  # read off core.sh's rosters rather than spelled again here. Per shell: the
  # shipped default lands, the shell-specific setting wins, and an empty value is
  # "unset", not "no separator" - a prompt ending in a bare space is never
  # what someone meant, and ' ' still expresses it.
  local shell upper var default
  for shell in $(_hi_shell_rows | cut -d'|' -f1); do
    upper="$(printf '%s' "$shell" | tr '[:lower:]' '[:upper:]')"
    var="_HI_PROMPT_END_$upper"
    # bash's default ships as the two characters `\$`, which bash renders as $
    # for a user and # for root; these cases run as a user, so the leading
    # backslash comes off before comparing against a rendered prompt.
    default="$(_hi_prompt_end_default "$upper")"
    default="${default#\\}"
    _hi_check_requires "$shell" "[$shell] default is '$default'" _hi_prompt_ends no "$shell" "$default"
    _hi_check_requires "$shell" "[$shell] $var wins" _hi_prompt_ends no "$shell" @@ "$var=@@"
    _hi_check_requires "$shell" "[$shell] empty falls back to '$default'" _hi_prompt_ends no "$shell" "$default" "$var="
  done
  # Root gets '#' - but as the *default* giving way, never as an override,
  # which is the rule bash's shipped `\$` follows (it renders as # for root,
  # and an explicit _HI_PROMPT_END_BASH still wins). fish is the only shell
  # where that decision is made in hi's own code rather than by the shell, so
  # it is the only one with a case. Run through the shadow, so it covers the
  # branch on a non-root box too.
  _hi_check_requires fish "[fish] root takes '#' over the default" _hi_prompt_ends yes fish '#'
  _hi_check_requires fish "[fish] root keeps an explicit one" _hi_prompt_ends yes fish @@ _HI_PROMPT_END_FISH=@@

  _hi_suite_end "rc (the prompt)"
}

run_rc_prompt_tests
