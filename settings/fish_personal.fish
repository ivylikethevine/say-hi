#!/bin/fish
# hi's own fish preferences: keybindings, the syntax and pager color palette,
# and the git-prompt styling. Taste, not product - a color scheme especially -
# which is why they live here rather than in common/config.fish beside the
# prompt and the aliases that are.
#
# Sourced by common/config.fish behind $_HI_DISABLE_PERSONAL, and NOT shipped at
# all when that toggle is on (hi.sh's _hi_payload_tar trims it). Your own copy at
# $_HI_CONFIG_DIR/config.fish is sourced after this one and wins, on
# settings/personal.sh's precedent - additive, never a replacement.
bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

# syntax colors, ordered as per
# https://fishshell.com/docs/4.5/interactive.html#syntax-highlighting-variables
# (anything not listed keeps fish's default)
set -gx fish_color_normal normal
set -gx fish_color_command blue
set -gx fish_color_keyword blue
set -gx fish_color_quote yellow
set -gx fish_color_redirection cyan --bold
set -gx fish_color_end green
set -gx fish_color_error brred
set -gx fish_color_param cyan
set -gx fish_color_valid_path --underline=single
set -gx fish_color_option brgreen
set -gx fish_color_comment red
set -gx fish_color_selection white --bold --background=brblack
set -gx fish_color_operator brcyan
set -gx fish_color_escape brcyan
set -gx fish_color_autosuggestion brblack
set -gx fish_color_cwd green
set -gx fish_color_cwd_root red
set -gx fish_color_status red
set -gx fish_color_cancel --reverse
set -gx fish_color_search_match white --background=brblack
set -gx fish_color_history_current --bold

# pager colors, as per
# https://fishshell.com/docs/4.5/interactive.html#pager-color-variables
set -gx fish_pager_color_progress brwhite --background=cyan
set -gx fish_pager_color_prefix normal --bold --underline=single
set -gx fish_pager_color_completion normal
set -gx fish_pager_color_description yellow --italics
set -gx fish_pager_color_selected_background --reverse
