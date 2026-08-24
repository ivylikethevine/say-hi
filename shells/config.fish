#!/bin/fish

# === start required configuration ===
# The tree from this file's own path, and only when unset. GLOSSARY: HI.33
# Through `sh`, not fish's `cd`/`pwd`: a builtin-only command substitution runs
# in the *current* process (so a bare `cd` moves the caller's cwd), and fish's
# `pwd` is logical where every other dialect here is physical.
if not set -q _HI_HOME
  set -gx _HI_HOME (command sh -c 'cd -P "$1/../.." && pwd' sh (status dirname))
end
# GLOSSARY: HI.07 - defaulted, never assigned, so bare reads are
# safe and settings.sh still overrides. Mirrors core.sh's _HI_TOGGLES.
for _hi_toggle in _HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER \
    _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL _HI_DISABLE_GIT_STATUS \
    _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES _HI_DISABLE_OSC52 \
    _HI_DISABLE_NOTIFY
  set -q $_hi_toggle; or set -gx $_hi_toggle 0
end
set -e _hi_toggle
# the overlay's home (fish can't expand the XDG default); only when unset, so
# hi.sh can point a target at its shipped copy.
if not set -q _HI_CONFIG_DIR
  set -l _hi_cfg_base ~/.config
  set -q XDG_CONFIG_HOME; and set _hi_cfg_base $XDG_CONFIG_HOME
  set -gx _HI_CONFIG_DIR $_hi_cfg_base/say-hi
end
# settings ahead of paths.sh, whose gate reads them - plain `export NAME=value`
# lines, which fish parses natively
if test -f $_HI_CONFIG_DIR/settings.sh
  source $_HI_CONFIG_DIR/settings.sh
end
source $_HI_HOME/say-hi/common/paths.sh
source $_HI_ALIASES

# misc/aliases.sh stays `alias` for bash/zsh/fish compatibility, so fish turns
# each into an opaque function with no preview of what it expands to. `alias`
# with no args lists them as `alias name 'value'`, itself valid fish syntax, so
# swapping the leading word for `abbr -a --` and eval'ing it reuses fish's own
# quoting round-trip rather than re-escaping by hand.
function hi_abbr_aliases --description 'add a fish abbr for every alias hi defined, so it expands in place'
  for hi_abbr_line in (alias)
    set -l hi_abbr_name (string match -rg '^alias (\S+) ' -- $hi_abbr_line)
    test -n "$hi_abbr_name"; or continue
    abbr -q -- $hi_abbr_name; and continue
    eval "abbr -a -- "(string replace -r '^alias \S+ ' "$hi_abbr_name " -- $hi_abbr_line)
  end
end
# Off by default: turning every alias into an abbr changes what your command
# line and history literally look like. Fish-only, so it is not in core.sh's
# _HI_TOGGLES; `hi_abbr_aliases` is still there to call by hand.
#
# Showing the expansion as autosuggestion text instead - so nothing is
# rewritten - was investigated and is not available: fish generates
# autosuggestions from history and completions only. As of 4.8 the surface is
# `$fish_color_autosuggestion` (styling) and `commandline --showing-suggestion`
# (a query); there is no setter, so nothing can put arbitrary text there.
#
# It is also unnecessary, which is the better half of the answer. fish's own
# `alias` builtin records the body as the function's description, so the
# completion pager already prints `hi_copy  alias hi_copy=sh .../osc52.sh` when
# you TAB the name - the expansion, visible, with the command line untouched.
# That is the default behaviour for every alias misc/aliases.sh defines; the
# abbr above is only for people who want the line itself rewritten.
set -q _HI_ENABLE_FISH_ALIAS_ABBR; or set -gx _HI_ENABLE_FISH_ALIAS_ABBR 0
test "$_HI_ENABLE_FISH_ALIAS_ABBR" = 1; and hi_abbr_aliases

# Both halves carry the opposite condition, so exactly one runs per TAB. The
# negation is not symmetry for its own sake: without it `hi --<TAB>` fires the
# target sweep as well, and a flag list must never wait on a docker daemon or
# an ssh config - the promise targets.sh's own flags branch makes by exiting
# before the cache and the probes, and the one bash.sh and zsh.zsh keep by
# answering `-*` words without touching the target cache.
complete -c hi -f -n 'not string match -q -- "-*" (commandline -ct)' \
  -a '(sh $_HI_TARGETS)' # "<target>\ttype" lines
# hi's own options, from the same file rather than a second list here - the two
# would drift, and targets.sh is the only one of the three fish can run.
complete -c hi -f -n 'string match -q -- "-*" (commandline -ct)' \
  -a '(sh $_HI_TARGETS flags)'
complete exa --wraps eza

# fish can't run hi's bash side, so the greeting, the package check and the
# color resolution each come from one bash call
function fish_greeting
  # on a hi session load.sh printed this already and sets $fish_greeting to
  # suppress us; locally nothing sets it, so we print the header ourselves
  set -q fish_greeting; or bash -c "source $_HI_HEADER; hi_header Online"
end

# a whole process for two color names, so memoized in a universal variable
# keyed on user@host+colors-mtime: only the first shell after a change pays
set -l hi_key "$USER@"(prompt_hostname)
test -f $_HI_COLORS; and set hi_key "$hi_key:"(command stat -c %Y $_HI_COLORS 2>/dev/null; or command stat -f %m $_HI_COLORS 2>/dev/null)
if not set -q __hi_colors_key; or test "$__hi_colors_key" != "$hi_key"
  set -l hi_colors (bash -c "source $_HI_CORE; _hi_user_color; _hi_host_color")
  set -U __hi_color_user $hi_colors[1]
  set -U __hi_color_host $hi_colors[2]
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

# the prompt's end character, mirroring core.sh's _hi_prompt_end (fish can't
# call it): fish setting, then all-three, then default. Empty counts as unset,
# and root still gets '#'.
set -g _hi_prompt_end '|'
set -q _HI_PROMPT_END; and test -n "$_HI_PROMPT_END"; and set -g _hi_prompt_end $_HI_PROMPT_END
set -q _HI_PROMPT_END_FISH; and test -n "$_HI_PROMPT_END_FISH"; and set -g _hi_prompt_end $_HI_PROMPT_END_FISH

# prompt: "<chroot> user@host cwd (git) [status] |", @ yellow over ssh; skipped
# entirely when disabled, leaving fish's own default prompt in place
if test "$_HI_DISABLE_PROMPT" != 1

# deference, chosen in settings.sh - core.sh's _hi_wants_starship rule, which
# fish can't call; a missing starship falls back to hi's prompt below
if test "$_HI_PROMPT" = starship; and command -q starship
starship init fish | source
else

# https://no-color.org (fish has no rule of its own): non-empty $NO_COLOR
# shadows set_color with a no-op, so every call below - and fish_vcs_prompt's
# own - renders the same prompt with no escapes in it.
if test -n "$NO_COLOR"
  function set_color
  end
end

function prompt_login --description "display user name for the prompt"
  if not set -q __fish_machine
    set -g __fish_machine ""
    test -r /etc/debian_chroot; and set -g __fish_machine "(chroot:"(cat /etc/debian_chroot)") "
  end
  set -l color_at normal
  set -q SSH_TTY; and set color_at yellow
  echo -ns (set_color yellow) "$__fish_machine" \
    (set_color $fish_color_user) " $USER" \
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
    set suffix '#'
  end

  # bold the status only when it changed since the last prompt
  set -l bold_flag --bold
  set -q __fish_prompt_status_generation; or set -g __fish_prompt_status_generation $status_generation
  test $__fish_prompt_status_generation = $status_generation; and set bold_flag
  set __fish_prompt_status_generation $status_generation

  set -l prompt_status (__fish_print_pipestatus "[" "]" "|" \
    (set_color $fish_color_status) (set_color $bold_flag $fish_color_status) $last_pipestatus)

  echo -n -s (prompt_login)' ' (set_color $color_cwd) (prompt_pwd) $normal \
    (test "$_HI_DISABLE_GIT_STATUS" != 1; and fish_vcs_prompt) $normal " "$prompt_status $suffix " "
end

end
end
# === end required configuration ===

# hi's own preferences, in their own file - see shells/fish_personal.fish. The
# user's copy comes after and is NOT gated: the toggle turns off *hi's* taste,
# not yours.
if test "$_HI_DISABLE_PERSONAL" != 1; and test -f $_HI_ROOT/shells/fish_personal.fish
  source $_HI_ROOT/shells/fish_personal.fish
end

# NOT in fish_personal.fish, though it sits behind the same toggle: this is
# hi's git segment, the fish half of what common/git_prompt.sh does for bash and
# zsh, and tests/hi/prompt_test.sh pins its glyphs and colors against core.sh.
# Product, not taste - so it stays in the shipped rc where that pin can find it.
if test "$_HI_DISABLE_PERSONAL" != 1
# git prompt, matched by common/git_prompt.sh for bash & zsh
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

# the ASCII fallback _hi_choose_glyphs gives bash/zsh, with _HI_ASCII
# overriding the locale probe both ways as everywhere else
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
end
end

if test -f $_HI_CONFIG_DIR/fish_personal.fish
  source $_HI_CONFIG_DIR/fish_personal.fish
end
