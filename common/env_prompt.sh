#!/usr/bin/env bash
# Shared bash/zsh environment prompt segment: the "(myproj) " prefix naming
# every active environment manager. common/config.fish carries fish's own copy
# and tests/hi/prompt_test.sh pins the two together. Plain text, no color - the
# one color is applied by each shell's own PS1 template, where that shell's
# width accounting can see it.

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
  # %s '': HI.05; clears a stale out-var before the early returns
  [[ -n "${1:-}" ]] && printf -v "$1" '%s' ''
  [[ "${_HI_DISABLE_ENV_STATUS:-0}" == 1 ]] && return

  # Every branch below is parameter expansion over a variable the tool
  # exported: no probe, no `command -v`, nothing that forks on a prompt draw.
  # mise is the one exception - see _hi_mise_local above.
  # Outermost environment first, so a venv inside a direnv inside mise reads
  # "(mise|direnv:proj|myproj)".
  local _hi_out="" _hi_name
  local _hi_defer="${_HI_ENV_DEFER:-0}"
  [[ -n "${MISE_SHELL:-}" ]] && _hi_mise_local && _hi_out+="|mise"   # env: mise
  [[ -n "${ASDF_DIR:-}" ]] && _hi_out+="|asdf"                       # env: asdf
  [[ -n "${PYENV_VERSION:-}" ]] && _hi_out+="|py:$PYENV_VERSION"     # env: pyenv
  [[ -n "${RBENV_VERSION:-}" ]] && _hi_out+="|rb:$RBENV_VERSION"     # env: rbenv
  [[ -n "${NODENV_VERSION:-}" ]] && _hi_out+="|node:$NODENV_VERSION" # env: nodenv
  # $name is stdenv's, set by nix-shell and by most `nix develop` shells
  [[ -n "${IN_NIX_SHELL:-}" ]] && _hi_out+="|nix${name:+:$name}" # env: nix
  [[ -n "${GUIX_ENVIRONMENT:-}" ]] && _hi_out+="|guix"           # env: guix
  [[ -n "${DEVBOX_SHELL_ENABLED:-}" ]] && _hi_out+="|devbox"     # env: devbox
  [[ -n "${DEVENV_ROOT:-}" ]] && _hi_out+="|devenv"              # env: devenv
  # direnv writes the loaded directory with a leading '-'
  if [[ -n "${DIRENV_DIR:-}" ]]; then # env: direnv
    _hi_name="${DIRENV_DIR#-}"
    _hi_out+="|direnv:${_hi_name##*/}"
  fi
  # conda draws its own prefix from $CONDA_PROMPT_MODIFIER unless changeps1 is
  # off, so a non-empty one means it is already on screen
  if [[ -n "${CONDA_DEFAULT_ENV:-}" ]] && # env: conda
    ! { [[ "$_hi_defer" == 1 ]] && [[ -n "${CONDA_PROMPT_MODIFIER:-}" ]]; }; then
    _hi_out+="|$CONDA_DEFAULT_ENV"
  fi
  # VIRTUAL_ENV_PROMPT is PEP 405's name (venv, virtualenv, poetry, pipenv all
  # set it); the basename is the fallback for an older activate
  _hi_name="${VIRTUAL_ENV_PROMPT:-}" # env: venv
  [[ -z "$_hi_name" && -n "${VIRTUAL_ENV:-}" ]] && _hi_name="${VIRTUAL_ENV##*/}"
  # ".venv" names every project the same; the directory holding it does not
  case "$_hi_name" in
  .venv | venv | .env | env)
    _hi_name="${VIRTUAL_ENV:-}"
    _hi_name="${_hi_name%/*}"
    _hi_name="${_hi_name##*/}"
    ;;
  esac
  # $_OLD_VIRTUAL_PS1 is set by activate itself: it ran in *this* shell, so its
  # own prefix is on screen wherever the shell keeps a PS1 hi does not rebuild.
  # GLOSSARY: HI.54
  [[ "$_hi_defer" == 1 && -n "${_OLD_VIRTUAL_PS1+x}" ]] && _hi_name=""
  [[ -n "$_hi_name" ]] && _hi_out+="|$_hi_name"
  _hi_out="${_hi_out#"|"}"
  [[ -n "$_hi_out" ]] || return

  # the cap and the glyph git_prompt.sh puts on a branch name, so a deep stack
  # cannot walk the prompt off the line
  ((${#_hi_out} > 32)) && _hi_out="${_hi_out:0:31}$_HI_GLYPH_ELLIPSIS"

  _hi_out "${1:-}" "($_hi_out) "
}
