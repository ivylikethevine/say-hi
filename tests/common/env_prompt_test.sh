#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for common/env_prompt.sh's _hi_env_prompt - the prompt's leading
# "(myproj) ", naming every active environment manager.
#
# Every case is a subshell with the whole roster of tool variables unset and
# only the ones under test put back, so a suite run from inside a venv, a
# direnv or a mise shell asserts the same thing as one run from a bare login.
#
# GLOSSARY: HI.30 + HI.34 + HI.54
# shellcheck disable=SC2329
# The out-var is optional by design, and every case below deliberately omits it
# (the stdout form is what is under test), which SC2119 cannot tell from a slip.
# shellcheck disable=SC2119
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../common/env_prompt.sh
source "$_HI_ENV_PROMPT"

# the multibyte glyph set, pinned: the truncation cases below match the
# ellipsis literally, and a runner without a UTF-8 locale would otherwise get
# the ASCII stand-in
_HI_ASCII=0
_hi_choose_glyphs

# Every variable _hi_env_prompt reads, plus the two settings and the shell's
# deference verdict. `name` is stdenv's, which is exactly why a case has to be
# able to clear it: a suite run inside a nix shell inherits one.
_HI_ENV_ROSTER="MISE_SHELL ASDF_DIR PYENV_VERSION RBENV_VERSION NODENV_VERSION
  IN_NIX_SHELL name GUIX_ENVIRONMENT DEVBOX_SHELL_ENABLED DEVENV_ROOT
  DIRENV_DIR CONDA_DEFAULT_ENV CONDA_PROMPT_MODIFIER VIRTUAL_ENV
  VIRTUAL_ENV_PROMPT _OLD_VIRTUAL_PS1
  _HI_ENV_DEFER _HI_ENV_ORDER _HI_DISABLE_ENV_STATUS"

# _hi_mise_local walks $PWD up to $HOME looking for a project config, so every
# case that wants "(mise)" to show has to set both: $_hi_mise_home stands in
# for ~ (no config of its own), $_hi_mise_project is a real project override
# one level under it, $_hi_mise_project/sub a subdirectory the walk has to
# climb out of, $_hi_mise_home/other a project-less sibling, and
# $_hi_mise_home/toml-proj an override spelled mise.toml instead.
_hi_mise_home="$(mktemp -d)"
_hi_mise_project="$_hi_mise_home/proj"
mkdir -p "$_hi_mise_project/sub" "$_hi_mise_home/other" "$_hi_mise_home/toml-proj"
: >"$_hi_mise_project/.tool-versions"
: >"$_hi_mise_home/toml-proj/mise.toml"
trap 'rm -rf "$_hi_mise_home"' EXIT

# _hi_env_case <VAR=value>... - the segment a shell with exactly those
# variables set would draw. A subshell, so the suite's own environment (and
# whatever the machine running it has activated) never leaks into a case.
function _hi_env_case() {
  (
    local kv
    # shellcheck disable=SC2086 # the roster is a word list on purpose
    unset $_HI_ENV_ROSTER
    for kv in "$@"; do
      eval "${kv%%=*}=\${kv#*=}; export ${kv%%=*}"
    done
    _hi_env_prompt
  )
}

function test_no_environment_produces_no_output() {
  [ -z "$(_hi_env_case)" ]
}

function test_disabled_flag_produces_no_output() {
  [ -z "$(_hi_env_case VIRTUAL_ENV_PROMPT=myproj _HI_DISABLE_ENV_STATUS=1)" ]
}

# The out-var form is what bash.sh's ps1() and zsh.zsh's precmd call: it must
# fill the variable and print nothing at all.
function test_out_var_form_fills_variable_not_stdout() {
  local captured="" out
  out="$(
    VIRTUAL_ENV_PROMPT=myproj _hi_env_prompt captured
    printf '%s' "$captured"
  )"
  [ "$out" = "(myproj) " ] && [ -z "$captured" ]
}

function test_out_var_and_stdout_form_agree() {
  local captured=""
  export VIRTUAL_ENV_PROMPT=myproj DIRENV_DIR=-/home/x/proj
  _hi_env_prompt captured
  [ "$captured" = "$(_hi_env_prompt)" ] && [ -n "$captured" ]
}

# The early returns have to *clear* a stale out-var, not leave the previous
# draw's answer in it - see the printf -v note at the top of the file under
# test, and git_prompt.sh's identical guard.
function test_out_var_is_precleared_when_disabled() {
  local captured="(stale) "
  _HI_DISABLE_ENV_STATUS=1 _hi_env_prompt captured
  [ -z "$captured" ]
}

function test_out_var_is_precleared_with_nothing_active() {
  local captured="(stale) "
  (
    # shellcheck disable=SC2086 # the roster is a word list on purpose
    unset $_HI_ENV_ROSTER
    _hi_env_prompt captured
    [ -z "$captured" ]
  )
}

# zsh sources this file too, and does *not* word-split an unquoted expansion:
# the order list is walked by expansion for exactly that reason, and this is
# the guard on it. Compares zsh's answer to bash's rather than to a literal,
# so the two can never drift apart silently.
function test_zsh_walks_the_order_list_the_same_way() {
  local want got
  want="$(_hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    MISE_SHELL=bash DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj)"
  got="$(
    env -u _HI_ENV_ORDER -u _HI_DISABLE_ENV_STATUS -u _HI_ENV_DEFER \
      HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
      MISE_SHELL=zsh DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj \
      zsh -c "source '$_HI_ENV_PROMPT'; _hi_env_prompt"
  )"
  [ -n "$want" ] && [ "$want" = "$got" ]
}

function run_env_prompt_tests() {
  _hi_h1 "Testing common/env_prompt.sh"

  _hi_suite_begin

  _hi_h2 "Use-Case: nothing active / disabled"
  _hi_check "No environment -> no output" test_no_environment_produces_no_output
  _hi_check "_HI_DISABLE_ENV_STATUS=1 -> no output" test_disabled_flag_produces_no_output

  _hi_h2 "Use-Case: one environment at a time"
  _hi_check_eq "mise, activated with a project override" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" MISE_SHELL=bash
  _hi_check_eq "asdf, activated" "(asdf) " _hi_env_case ASDF_DIR=/opt/asdf
  _hi_check_eq "pyenv shell override" "(py:3.12.1) " _hi_env_case PYENV_VERSION=3.12.1
  _hi_check_eq "rbenv shell override" "(rb:3.3.0) " _hi_env_case RBENV_VERSION=3.3.0
  _hi_check_eq "nodenv shell override" "(node:22.1.0) " _hi_env_case NODENV_VERSION=22.1.0
  _hi_check_eq "nix-shell, unnamed" "(nix) " _hi_env_case IN_NIX_SHELL=impure
  _hi_check_eq "nix-shell, stdenv \$name" "(nix:hello-1.0) " _hi_env_case IN_NIX_SHELL=pure name=hello-1.0
  _hi_check_eq "guix environment" "(guix) " _hi_env_case GUIX_ENVIRONMENT=/gnu/store/x
  _hi_check_eq "devbox shell" "(devbox) " _hi_env_case DEVBOX_SHELL_ENABLED=1
  _hi_check_eq "devenv shell" "(devenv) " _hi_env_case DEVENV_ROOT=/home/x/proj
  _hi_check_eq "conda environment" "(sci) " _hi_env_case CONDA_DEFAULT_ENV=sci

  _hi_h2 "Use-Case: mise's default vs. a project override"
  _hi_check_eq "mise active, PWD is HOME itself (the ~/.tool-versions default)" "" \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_home" MISE_SHELL=bash
  _hi_check_eq "mise active, a project subdir with no config of its own" "" \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_home/other" MISE_SHELL=bash
  _hi_check_eq "mise active, project override one level down" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" MISE_SHELL=bash
  _hi_check_eq "mise active, override found by walking up from a subdir" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project/sub" MISE_SHELL=bash
  _hi_check_eq "mise active, mise.toml counts as an override too" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_home/toml-proj" MISE_SHELL=bash

  _hi_h2 "Use-Case: the names that need work"
  _hi_check_eq "direnv drops its leading '-' and keeps the basename" "(direnv:proj) " \
    _hi_env_case DIRENV_DIR=-/home/x/proj
  _hi_check_eq "VIRTUAL_ENV_PROMPT wins over the path" "(myproj) " \
    _hi_env_case VIRTUAL_ENV=/x/other/.venv VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "a named venv directory is its own name" "(myenv) " \
    _hi_env_case VIRTUAL_ENV=/x/myenv
  _hi_check_eq "a .venv is named for the directory holding it" "(proj) " \
    _hi_env_case VIRTUAL_ENV=/x/proj/.venv
  _hi_check_eq "so is a bare venv/" "(proj) " _hi_env_case VIRTUAL_ENV=/x/proj/venv
  _hi_check_eq "and a prompt of '.venv' from an older activate" "(proj) " \
    _hi_env_case VIRTUAL_ENV=/x/proj/.venv VIRTUAL_ENV_PROMPT=.venv

  _hi_h2 "Use-Case: several at once"
  _hi_check_eq "direnv outside a venv, outermost first" "(direnv:proj|myproj) " \
    _hi_env_case DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "mise outside both" "(mise|direnv:proj|myproj) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    MISE_SHELL=bash DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "_HI_ENV_ORDER drops a word" "(myproj) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    MISE_SHELL=bash VIRTUAL_ENV_PROMPT=myproj _HI_ENV_ORDER=venv
  _hi_check_eq "_HI_ENV_ORDER reorders what is left" "(myproj|mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    MISE_SHELL=bash VIRTUAL_ENV_PROMPT=myproj _HI_ENV_ORDER="venv mise"
  _hi_check_eq "stray spaces in _HI_ENV_ORDER are not words" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    MISE_SHELL=bash _HI_ENV_ORDER="  mise   "

  _hi_h2 "Use-Case: standing down for a tool drawing its own prefix"
  _hi_check_eq "zsh/fish: activate ran here, so the venv is the venv's" "(direnv:proj) " \
    _hi_env_case _HI_ENV_DEFER=1 _OLD_VIRTUAL_PS1='$ ' \
    DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "bash: nothing survives its PROMPT_COMMAND, so hi draws it" "(direnv:proj|myproj) " \
    _hi_env_case _HI_ENV_DEFER=0 _OLD_VIRTUAL_PS1='$ ' \
    DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "a venv inherited rather than activated is still hi's" "(myproj) " \
    _hi_env_case _HI_ENV_DEFER=1 VIRTUAL_ENV_PROMPT=myproj
  _hi_check_eq "conda with changeps1 on is conda's" "(mise) " \
    _hi_env_case HOME="$_hi_mise_home" PWD="$_hi_mise_project" \
    _HI_ENV_DEFER=1 MISE_SHELL=bash CONDA_DEFAULT_ENV=sci \
    CONDA_PROMPT_MODIFIER='(sci) '
  _hi_check_eq "conda with changeps1 off is hi's" "(sci) " \
    _hi_env_case _HI_ENV_DEFER=1 CONDA_DEFAULT_ENV=sci

  _hi_h2 "Use-Case: truncation"
  _hi_check_eq "A stack over 32 columns is cut at 31 + the ellipsis" \
    "($(printf 'a%.0s' $(seq 31))$_HI_GLYPH_ELLIPSIS) " \
    _hi_env_case "VIRTUAL_ENV_PROMPT=$(printf 'a%.0s' $(seq 40))"
  _hi_check_eq "Exactly 32 columns is left alone" \
    "($(printf 'a%.0s' $(seq 32))) " \
    _hi_env_case "VIRTUAL_ENV_PROMPT=$(printf 'a%.0s' $(seq 32))"

  _hi_h2 "Use-Case: the out-var form bash.sh and zsh.zsh call"
  _hi_check "Fills the var, not stdout" test_out_var_form_fills_variable_not_stdout
  _hi_check "Agrees with the stdout form" test_out_var_and_stdout_form_agree
  _hi_check "Pre-cleared when disabled" test_out_var_is_precleared_when_disabled
  _hi_check "Pre-cleared with nothing active" test_out_var_is_precleared_with_nothing_active

  _hi_h2 "Use-Case: the file is sourced by zsh too"
  _hi_check_requires zsh "zsh walks the order list the same way" \
    test_zsh_walks_the_order_list_the_same_way

  _hi_suite_end "env_prompt.sh"
}

run_env_prompt_tests
