#!/bin/fish
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT

# === start required configuration ===
# The tree from this file's own path, only when unset. Through `sh`, not
# fish's `cd`/`pwd`: a builtin-only command substitution runs in the current
# process, and fish's `pwd` is logical. GLOSSARY: HI.33
if not set -q _HI_HOME
  set -gx _HI_HOME (command sh -c 'cd -P "$1/../.." && pwd' sh (status dirname))
end
# GLOSSARY: HI.07 - defaulted, never assigned, so settings.sh still overrides.
# Mirrors core.sh's _HI_TOGGLES.
for _hi_toggle in _HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER \
    _HI_DISABLE_PROMPT _HI_DISABLE_GIT_STATUS _HI_DISABLE_ENV_STATUS \
    _HI_DISABLE_EDITORS \
    _HI_DISABLE_MARKS \
    _HI_DISABLE_TOOL_ALIASES _HI_DISABLE_BANNER
  set -q $_hi_toggle; or set -gx $_hi_toggle 0
end
set -e _hi_toggle
# the overlay's home (fish can't expand the XDG default); only when unset, so
# hi.sh can point a target at its shipped copy
if not set -q _HI_CONFIG_DIR
  set -l _hi_cfg_base ~/.config
  set -q XDG_CONFIG_HOME; and set _hi_cfg_base $XDG_CONFIG_HOME
  set -gx _HI_CONFIG_DIR $_hi_cfg_base/say-hi
end
# settings ahead of paths.sh, whose gate reads them (plain `export NAME=value`
# lines, which fish parses natively)
if test -f $_HI_CONFIG_DIR/settings.sh
  source $_HI_CONFIG_DIR/settings.sh
end
source $_HI_HOME/say-hi/common/paths.sh
source $_HI_ALIASES

# core.sh's _HI_CHILD_ENV and _HI_SESSION_VARS, mirrored (fish cannot read a
# bash array); exports_test.sh pins both. The first is what a child inherits
# after the un-export loop at the end of the required block. The second is
# what load.sh wrote into the session rc as plain globals, so the bash this
# file shells out to has to be handed them - __hi_bash's job. `-f` (function
# scope) rather than `-l`: a `-l` inside the `for` is gone by the time the
# command runs. GLOSSARY: HI.47
set -g _HI_CHILD_ENV _HI_HOME _HI_CONFIG_DIR _HI_REMOTE_SESSION _HI_SESSION_RC \
    _HI_TARGETS_TTL _HI_PROBE_TIMEOUT
set -g _HI_SESSION_VARS _HI_TARGET_COLOR _HI_TARGET_TAG _HI_LOCAL_USER \
    _HI_LOCAL_HOSTNAME _HI_RELEASE _HI_ASCII _HI_TRUECOLOR
function __hi_bash --description 'bash -c <script>, with the session values hi keeps out of the environment passed along'
  for __hi_n in $_HI_SESSION_VARS
    set -q $__hi_n; and set -fx $__hi_n $$__hi_n
  end
  command bash -c $argv
end

# Opposite conditions, so exactly one runs per TAB: without the negation
# `hi --<TAB>` would fire the target sweep too, and a flag list must never
# wait on a docker daemon (the promise targets.sh, bash.sh and zsh.zsh keep).
# -k keeps targets.sh's order instead of sorting.
# the word after a flag that takes one - `hi --preview <TAB>`, `hi --use
# <TAB>` - is neither a flag nor a target: targets.sh's words roster
function __hi_prev_takes_word --description 'is the previous token one of $_HI_WORD_FLAGS'
  set -l toks (commandline -opc)
  # `--` before the separator: the flags start with dashes, and string
  # would read them as its own options
  test (count $toks) -gt 0; and contains -- $toks[-1] (string split -- ' ' $_HI_WORD_FLAGS)
end
complete -c hi -f -k -n 'not string match -q -- "-*" (commandline -ct); and not __hi_prev_takes_word' \
  -a '(sh $_HI_TARGETS)' # "<target>\ttype" lines
complete -c hi -f -k -n __hi_prev_takes_word \
  -a '(sh $_HI_TARGETS words (commandline -opc)[-1])'
# hi's own options from the same file, so the two lists cannot drift; behind
# a local command (`hi --install --<TAB>`) that command's own switches
complete -c hi -f -n 'string match -q -- "-*" (commandline -ct)' \
  -a '(sh $_HI_TARGETS flags (commandline -opc)[2])'
complete exa --wraps eza

# fish can't run hi's bash side, so the greeting, the package check and the
# color resolution each come from one bash call
function fish_greeting
  # on a hi session load.sh printed this already and sets $fish_greeting to
  # suppress us; locally nothing sets it, so we print the header ourselves.
  # $COLUMNS is fish's own global and never exported, so header.sh's
  # _hi_draw_width wouldn't see it through __hi_bash's plain `bash -c` -
  # handed over with an explicit prefix instead of joining _HI_SESSION_VARS
  # for the one caller that needs it
  set -q fish_greeting; or COLUMNS=$COLUMNS __hi_bash "source $_HI_HEADER; hi_header Online"
end

# a whole process for two colors, so memoized in a universal variable keyed
# on user@host+colors-mtime, plus the scheme and the terminal's 24-bit verdict
# (a universal variable outlives this terminal): only the first shell after a
# change pays. Each value is a list - "rrggbb name" under a scheme, the bare
# name otherwise - and set_color takes the first entry this terminal renders.
set -l hi_key "$USER@"(prompt_hostname)
test -f $_HI_COLORS; and set hi_key "$hi_key:"(path mtime $_HI_COLORS 2>/dev/null; or command stat -c %Y $_HI_COLORS 2>/dev/null; or command stat -f %m $_HI_COLORS 2>/dev/null)
set hi_key "$hi_key:$_HI_COLOR_SCHEME:$_HI_TRUECOLOR:$COLORTERM"
if not set -q __hi_colors_key; or test "$__hi_colors_key" != "$hi_key"
  set -l hi_colors (__hi_bash "source $_HI_CORE; _hi_prompt_colors")
  set -U __hi_color_user (string split ' ' $hi_colors[1])
  set -U __hi_color_host (string split ' ' $hi_colors[2])
  set -U __hi_colors_key "$hi_key"
end
set -gx fish_color_user $__hi_color_user
set -gx fish_color_host $__hi_color_host
set -gx fish_color_host_remote $fish_color_host

# wrapper so aliases (functions, in fish) work under sudo; args ride fish's own
# argv after --, never a re-parsed string - that invites injection
function sudo
  if functions -q -- "$argv[1]"
    set -lx hi_sudo_fn $argv[1]
    set -lx function_src (string join "\n" (string escape --style=var (functions -- $hi_sudo_fn)))
    command sudo -E fish -c 'string unescape --style=var (string split "\n" $function_src) | source; $hi_sudo_fn $argv' -- $argv[2..]
  else
    command sudo $argv
  end
end

# the prompt's end character, mirroring core.sh's _hi_prompt_end: fish
# setting, then default; empty counts as unset. Whether a
# setting spoke is remembered, because root's '#' replaces the *default* only.
set -g _hi_prompt_end '|'
set -g _hi_prompt_end_explicit 0
set -q _HI_PROMPT_END_FISH; and test -n "$_HI_PROMPT_END_FISH"; and set -g _hi_prompt_end $_HI_PROMPT_END_FISH; and set -g _hi_prompt_end_explicit 1

# prompt: "<chroot> user@host cwd (git) [status] |", @ yellow over ssh; skipped
# entirely when disabled, leaving fish's own default prompt in place
if test "$_HI_DISABLE_PROMPT" != 1
  # core.sh's _hi_wants_prompt_tool rule (fish can't call it); a missing tool
  # falls back to hi's prompt below. The tool's config variable is paths.sh's
  # job, which fish sourced above
  if contains -- "$_HI_PROMPT" starship oh-my-posh; and command -q $_HI_PROMPT
    $_HI_PROMPT init fish | source
  else
    # https://no-color.org (fish has no rule of its own): non-empty $NO_COLOR
    # shadows set_color with a no-op, so every call below - and fish_vcs_prompt's
    # own - renders with no escapes
    if test -n "$NO_COLOR"
      function set_color
      end
    end

    # The fish half of common/env_prompt.sh: the "(myproj) " prefix naming
    # every active environment manager. Fish cannot call the bash copy, and a
    # `bash -c` here would be a fork on every prompt draw, so the source list
    # is a third copy on purpose - tests/hi/prompt_test.sh pins the two
    # together. Fish always stands down for a tool drawing its own prefix,
    # which is _HI_ENV_DEFER=1 on the bash side. GLOSSARY: HI.54
    function __hi_env_prompt --description 'name every active environment manager'
      test "$_HI_DISABLE_ENV_STATUS" = 1; and return
      set -l order mise asdf pyenv rbenv nodenv nix guix devbox devenv direnv conda venv
      test -n "$_HI_ENV_ORDER"; and set order (string split -n ' ' -- $_HI_ENV_ORDER)
      set -l names
      for src in $order
        switch $src
          case mise
            test -n "$MISE_SHELL"; and set -a names mise
          case asdf
            test -n "$ASDF_DIR"; and set -a names asdf
          case pyenv
            test -n "$PYENV_VERSION"; and set -a names "py:$PYENV_VERSION"
          case rbenv
            test -n "$RBENV_VERSION"; and set -a names "rb:$RBENV_VERSION"
          case nodenv
            test -n "$NODENV_VERSION"; and set -a names "node:$NODENV_VERSION"
          case nix
            if test -n "$IN_NIX_SHELL"
              test -n "$name"; and set -a names "nix:$name"; or set -a names nix
            end
          case guix
            test -n "$GUIX_ENVIRONMENT"; and set -a names guix
          case devbox
            test -n "$DEVBOX_SHELL_ENABLED"; and set -a names devbox
          case devenv
            test -n "$DEVENV_ROOT"; and set -a names devenv
          case direnv
            test -n "$DIRENV_DIR"; and set -a names "direnv:"(string replace -r '^-?.*/' '' -- $DIRENV_DIR)
          case conda
            test -n "$CONDA_DEFAULT_ENV"; and test -z "$CONDA_PROMPT_MODIFIER"
            and set -a names $CONDA_DEFAULT_ENV
          case venv
            set -l venv_name "$VIRTUAL_ENV_PROMPT"
            test -z "$venv_name"; and set venv_name (string replace -r '.*/' '' -- $VIRTUAL_ENV)
            contains -- "$venv_name" .venv venv .env env
            and set venv_name (string replace -r '.*/([^/]*)/[^/]*$' '$1' -- $VIRTUAL_ENV)
            test -n "$venv_name"; and not functions -q _old_fish_prompt
            and set -a names $venv_name
        end
      end
      test -n "$names"; or return
      set -l out (string join '|' $names)
      test (string length -- "$out") -gt 32
      and set out (string sub -l 31 -- "$out")$_hi_env_ellipsis
      echo -n "($out) "
    end

    function prompt_login --description "display user name for the prompt"
      if not set -q __fish_machine
        set -g __fish_machine ""
        test -r /etc/debian_chroot; and set -g __fish_machine "(chroot:"(cat /etc/debian_chroot)") "
      end
      set -l color_at normal
      set -q SSH_TTY; and set color_at yellow
      set -l lead " "
      test "$_HI_NO_LEAD_SPACE" = 1; and set lead ""
      # $lead is its own argument, never "$lead"(__hi_env_prompt): fish drops
      # the *whole* concatenated word when a command substitution inside it
      # produces nothing, so glued to an empty environment segment - which is
      # every prompt outside a venv/conda/direnv - the leading space
      # disappeared with it. `echo -ns` joins its arguments with no separator,
      # so two words render exactly as the one did when the segment was there.
      echo -ns (set_color yellow) "$__fish_machine" \
        (set_color brcyan) "$lead" (__hi_env_prompt) \
        (set_color $fish_color_user) "$USER" \
        (set_color $color_at) @ \
        (set_color $fish_color_host) (prompt_hostname) (set_color normal)
    end

    # copied + modified from Lilly Ballard, fish default
    function fish_prompt --description 'Write out the prompt'
      set -l last_pipestatus $pipestatus
      set -lx __fish_last_status $status
      set -l normal (set_color normal)

      set -l color_cwd $fish_color_cwd
      set -l suffix " $_hi_prompt_end"
      if functions -q fish_is_root_user; and fish_is_root_user
        set -q fish_color_cwd_root; and set color_cwd $fish_color_cwd_root
        # root's '#' is the *default* giving way (bash's shipped `\$` does the
        # same); an explicit setting is honoured for root too
        test "$_hi_prompt_end_explicit" = 1; or set suffix ' #'
      end

      # bold the status only when it changed since the last prompt
      set -l bold_flag --bold
      set -q __fish_prompt_status_generation; or set -g __fish_prompt_status_generation $status_generation
      test $__fish_prompt_status_generation = $status_generation; and set bold_flag
      set __fish_prompt_status_generation $status_generation

      # quoted so an empty set_color (no colour on this TERM) still counts as an
      # argument - fish 3 otherwise reports "missing argument" on every prompt
      set -l prompt_status (__fish_print_pipestatus "[" "]" "|" \
        "$(set_color $fish_color_status)" "$(set_color $bold_flag $fish_color_status)" $last_pipestatus)

      echo -n -s $_hi_marks_a (prompt_login)' ' (set_color $color_cwd) (prompt_pwd) $normal \
        (test "$_HI_DISABLE_GIT_STATUS" != 1; and fish_vcs_prompt) $normal " "$prompt_status $suffix " " $_hi_marks_b
    end

    # OSC 133 prompt marks and OSC 7 cwd reporting, the fish half of what
    # common/bash.sh's ps1() emits. fish 4 emits both itself, so only fish 3 gets
    # hi's copy - two sets of marks would confuse the terminal.
    set -g _hi_marks_a ''
    set -g _hi_marks_b ''
    if test "$_HI_DISABLE_MARKS" != 1; and not string match -qr '^[4-9]\.' -- $version
      set -g _hi_marks_a \e']133;A'\a
      set -g _hi_marks_b \e']133;B'\a
      function __hi_marks_preexec --on-event fish_preexec
        printf '\e]133;C\a'
      end
      function __hi_marks_postexec --on-event fish_postexec
        printf '\e]133;D;%s\a' $status
      end
      # only an interactive fish owns a terminal to report to: `fish -c` and the
      # suites' captured runs would otherwise get the escape ahead of their output
      function __hi_marks_cwd --on-variable PWD
        status is-interactive; and printf '\e]7;file://%s%s\a' (prompt_hostname) $PWD
      end
      __hi_marks_cwd
    end
  end
end

# The fish half of core.sh's _hi_unexport: every _HI_* name not in
# _HI_CHILD_ENV loses its export flag, value kept (`set -gu NAME $NAME` - fish
# cannot flip the flag alone). Last in the required block, after every alias
# has expanded its paths. `string match` with a glob, not -r: a regex match
# prints only the matched text. GLOSSARY: HI.47
for __hi_n in (set -n | string match '_HI_*')
  contains -- $__hi_n $_HI_CHILD_ENV; or set -gu $__hi_n $$__hi_n
end
set -e __hi_n
# === end required configuration ===

# hi's git segment: the fish half of common/git_prompt.sh; prompt_test.sh pins
# its glyphs and colors against core.sh. Product, not taste, so unconditional
# (docs/SETTINGS.md on what hi stopped shipping).
set -g __fish_git_prompt_show_informative_status 1
set -g __fish_git_prompt_showupstream informative
set -g __fish_git_prompt_showdirtystate yes
set -g __fish_git_prompt_showuntrackedfiles yes
set -g __fish_git_prompt_showstashstate yes
set -g __fish_git_prompt_showcolorhints yes
set -g __fish_git_prompt_describe_style contains
set -g __fish_git_prompt_shorten_branch_len 32
set -g __fish_git_prompt_color_branch brmagenta
set -g __fish_git_prompt_color_stagedstate yellow
set -g __fish_git_prompt_color_invalidstate red
set -g __fish_git_prompt_color_cleanstate brgreen

set -g _hi_env_ellipsis …

# the ASCII fallback _hi_choose_glyphs gives bash/zsh, with _HI_ASCII
# overriding the locale probe both ways
if test "$_HI_ASCII" = 1
    or begin
        test "$_HI_ASCII" != 0
        and not string match -qri 'utf-?8' -- "$LC_ALL$LC_CTYPE$LANG"
    end
    set -g __fish_git_prompt_char_upstream_ahead '^'
    set -g __fish_git_prompt_char_upstream_behind 'v'
    set -g __fish_git_prompt_char_stagedstate '*'
    set -g __fish_git_prompt_char_dirtystate '+'
    set -g __fish_git_prompt_char_invalidstate 'x'
    set -g __fish_git_prompt_char_untrackedfiles '?'
    set -g __fish_git_prompt_char_stashstate '$'
    set -g __fish_git_prompt_char_cleanstate 'ok'
    set -g _hi_env_ellipsis '..'
end

# see common/bash.sh for why the paths are compared before sourcing
if test "$_HI_CONFIG_DIR/config.fish" != "$_HI_ROOT/common/config.fish"
    and test -f $_HI_CONFIG_DIR/config.fish
  source $_HI_CONFIG_DIR/config.fish
end
