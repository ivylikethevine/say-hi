#!/bin/sh
# aliases.sh's binary lookups for the shells without core.sh's
# _hi_path_lookup, sh and the bash-less tier, in a file of their own: each
# holds a `$( )`, which fish before 3.4 refuses to parse anywhere in a file it
# sources, so fish takes config.fish's __hi_alias_bins in their place. bash
# and zsh read this too, and each line's leading test hands them back to the
# helper's lines in aliases.sh. Each `$( )` clears aliases first, in its own
# subshell only - the target's `alias ls='ls --color=auto'`, or ours on a
# re-source, would otherwise become the binary. `||` chains, because `zsh -n`
# fails a file holding a `!`. GLOSSARY: HI.13
# shellcheck disable=SC2155 # nothing reads the status of an export here
# shellcheck disable=SC2015 # `|| true` only keeps a failed unalias from ending the chain
command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_CAT_BIN" ] || export _HI_CAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat || command -v ccat || command -v cat)"
# shellcheck disable=SC2015
command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_BAT_BIN" ] || export _HI_BAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat)"
# shellcheck disable=SC2015
command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_LS_BIN" ] || export _HI_LS_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza || command -v ls)"
# shellcheck disable=SC2015
command -v _hi_path_lookup >/dev/null 2>&1 || [ -n "$_HI_LS_OPTS" ] || [ -z "$_HI_LS_BIN" ] || [ "$_HI_LS_BIN" != "$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza)" ] || export _HI_LS_OPTS="$_HI_EZA_OPTS"
# every shell's last rung: ls's own flags, and colors where it takes the flag
[ -z "$_HI_LS_OPTS" ] && export _HI_LS_OPTS="-F -l$(command ls --color=auto -d / >/dev/null 2>&1 && echo ' --color=auto')" || true
