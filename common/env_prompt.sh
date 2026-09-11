#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Shared bash/zsh environment prompt segment: the "(myproj) " prefix naming
# every active environment manager. common/config.fish carries fish's own copy
# and tests/hi/prompt_test.sh pins the two together. Plain text, no color - the
# one color is applied by each shell's own PS1 template, where that shell's
# width accounting can see it.
set -euo pipefail # off again at the end: an error must not close an interactive shell

# The sources, in the order they render: outermost environment first, so a venv
# inside a direnv inside mise reads "(mise|direnv:proj|myproj)".
_HI_ENV_ORDER_DEFAULT="mise asdf pyenv rbenv nodenv nix guix devbox devenv direnv conda venv"

# _hi_mise_local's memo: the walk's answer only changes when $PWD does (or a
# config file appears/disappears mid-directory - the same raw edge this file's
# git_prompt.sh sibling accepts for its OID memo), so a `cd`-less run of
# prompts - the common case - pays the stat loop once instead of every draw.
# GLOSSARY: HI.16
_HI_MISE_LOCAL_PWD=""
_HI_MISE_LOCAL_VERDICT=1

# _hi_mise_local - true if a mise config file sits in $PWD or an ancestor below
# $HOME (a config at $HOME is the global one; outside $HOME the walk runs to
# /). mise exports no variable saying which file it resolved, and
# $HOME/.tool-versions applies to every directory beneath it, so MISE_SHELL
# alone is on for effectively every prompt on a box with one - this is the
# only way to tell that apart from a real project override. Builtins only
# (`[[ -f ]]`/parameter expansion), so it stays a no-fork read. GLOSSARY: HI.16
_hi_mise_local() {
  [[ "$PWD" == "$_HI_MISE_LOCAL_PWD" ]] && return "$_HI_MISE_LOCAL_VERDICT"
  local _hi_dir="$PWD" _hi_verdict=1
  while [[ "$_hi_dir" != "${HOME:-}" ]]; do
    if [[ -f "$_hi_dir/.tool-versions" || -f "$_hi_dir/.mise.toml" ||
      -f "$_hi_dir/mise.toml" || -f "$_hi_dir/.mise/config.toml" ]]; then
      _hi_verdict=0
      break
    fi
    [[ "$_hi_dir" == "/" ]] && break
    _hi_dir="${_hi_dir%/*}"
    _hi_dir="${_hi_dir:-/}"
  done
  _HI_MISE_LOCAL_PWD="$PWD" _HI_MISE_LOCAL_VERDICT="$_hi_verdict"
  return "$_hi_verdict"
}

# _hi_env_prompt [outvar] - with outvar the segment lands there instead of
# stdout, saving bash.sh's per-prompt fork. GLOSSARY: HI.05 + HI.54
# shellcheck disable=SC2120 # the argument is optional by design
_hi_env_prompt() {
  # %s '', not a bare '' format: bash 3.2's printf -v skips a zero-conversion,
  # zero-argument format outright, so a stale out-var from the previous draw
  # would survive the early returns below (git_prompt.sh says the same)
  [[ -n "${1:-}" ]] && printf -v "$1" '%s' ''
  [[ "${_HI_DISABLE_ENV_STATUS:-0}" == 1 ]] && return

  # Every branch below is parameter expansion over a variable the tool
  # exported: no probe, no `command -v`, nothing that forks on a prompt draw.
  # mise is the one exception - see _hi_mise_local above.
  local _hi_out="" _hi_src _hi_name _hi_outvar="${1:-}"
  local _hi_defer="${_HI_ENV_DEFER:-0}"
  # The order is a word list, walked a word at a time by expansion rather than
  # by `for x in $list`: zsh does not word-split an unquoted expansion, and
  # zsh.zsh sources this file too.
  local _hi_rest="$_HI_ENV_ORDER_DEFAULT"
  while :; do
    while [[ "$_hi_rest" == " "* ]]; do _hi_rest="${_hi_rest# }"; done
    [[ -n "$_hi_rest" ]] || break
    _hi_src="${_hi_rest%% *}"
    _hi_rest="${_hi_rest#"$_hi_src"}"
    _hi_name=""
    case "$_hi_src" in
    mise) [[ -n "${MISE_SHELL:-}" ]] && _hi_mise_local && _hi_name="mise" ;;
    asdf) [[ -n "${ASDF_DIR:-}" ]] && _hi_name="asdf" ;;
    pyenv) [[ -n "${PYENV_VERSION:-}" ]] && _hi_name="py:$PYENV_VERSION" ;;
    rbenv) [[ -n "${RBENV_VERSION:-}" ]] && _hi_name="rb:$RBENV_VERSION" ;;
    nodenv) [[ -n "${NODENV_VERSION:-}" ]] && _hi_name="node:$NODENV_VERSION" ;;
    nix)
      # $name is stdenv's, set by nix-shell and by most `nix develop` shells
      if [[ -n "${IN_NIX_SHELL:-}" ]]; then
        _hi_name="nix"
        [[ -n "${name:-}" ]] && _hi_name="nix:$name"
      fi
      ;;
    guix) [[ -n "${GUIX_ENVIRONMENT:-}" ]] && _hi_name="guix" ;;
    devbox) [[ -n "${DEVBOX_SHELL_ENABLED:-}" ]] && _hi_name="devbox" ;;
    devenv) [[ -n "${DEVENV_ROOT:-}" ]] && _hi_name="devenv" ;;
    direnv)
      # direnv writes the loaded directory with a leading '-'
      if [[ -n "${DIRENV_DIR:-}" ]]; then
        _hi_name="${DIRENV_DIR#-}"
        _hi_name="direnv:${_hi_name##*/}"
      fi
      ;;
    conda)
      # conda draws its own prefix from $CONDA_PROMPT_MODIFIER unless
      # changeps1 is off, so a non-empty one means it is already on screen
      if [[ -n "${CONDA_DEFAULT_ENV:-}" ]] &&
        ! { [[ "$_hi_defer" == 1 ]] && [[ -n "${CONDA_PROMPT_MODIFIER:-}" ]]; }; then
        _hi_name="$CONDA_DEFAULT_ENV"
      fi
      ;;
    venv)
      # VIRTUAL_ENV_PROMPT is PEP 405's name (venv, virtualenv, poetry, pipenv
      # all set it); the basename is the fallback for an older activate
      _hi_name="${VIRTUAL_ENV_PROMPT:-}"
      [[ -z "$_hi_name" && -n "${VIRTUAL_ENV:-}" ]] && _hi_name="${VIRTUAL_ENV##*/}"
      # ".venv" names every project the same; the directory holding it does not
      case "$_hi_name" in
      .venv | venv | .env | env)
        _hi_name="${VIRTUAL_ENV:-}"
        _hi_name="${_hi_name%/*}"
        _hi_name="${_hi_name##*/}"
        ;;
      esac
      # $_OLD_VIRTUAL_PS1 is set by activate itself: it ran in *this* shell, so
      # its own prefix is on screen wherever the shell keeps a PS1 hi does not
      # rebuild. GLOSSARY: HI.54
      [[ "$_hi_defer" == 1 && -n "${_OLD_VIRTUAL_PS1+x}" ]] && _hi_name=""
      ;;
    esac
    [[ -n "$_hi_name" ]] && _hi_out="${_hi_out:+$_hi_out|}$_hi_name"
  done
  [[ -n "$_hi_out" ]] || return

  # the cap and the glyph git_prompt.sh puts on a branch name, so a deep stack
  # cannot walk the prompt off the line
  ((${#_hi_out} > 32)) && _hi_out="${_hi_out:0:31}$_HI_GLYPH_ELLIPSIS"

  if [[ -n "$_hi_outvar" ]]; then
    printf -v "$_hi_outvar" '(%s) ' "$_hi_out"
  else
    printf '(%s) ' "$_hi_out"
  fi
}

set +euo pipefail # see the top of the file
