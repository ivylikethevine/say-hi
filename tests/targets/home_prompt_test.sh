#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# hi's prompt at home over a distro's own rc chain (GLOSSARY: HI.32). At home
# bash and zsh keep a PS1 the rc set unless it is one nobody wrote; rc_test.sh
# proves that against the prompt strings, and this against the files they come
# from. Each distro's stock image boots once with this tree copied in, and
# each case (tests/dockerfiles/home-prompt.sh) installs hi into a fresh $HOME
# built from that image's /etc/skel: a stock .bashrc gets hi's prompt, and a
# PS1 the user wrote into it stays theirs. zsh runs on Debian alone, the one
# image here that installs it from a mirror the e2e job already allows.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# <label>|<image>: Arch rolls, so its tag is the one that is Arch today
_HI_HP_IMAGES=(
  "debian|debian:bookworm-slim"
  "fedora|fedora:44"
  "arch|archlinux:latest"
)
_HI_HP_OWN='MINE \w \$ '
_HI_HP_PS1=""

# _hi_hp_start <label> <image> - the distro's container, this tree at
# /opt/hi/say-hi (no .git, and none of the tooling a build leaves beside it)
function _hi_hp_start() {
  local c="hi-homeprompt-$1-$$"
  _hi_track_container "$c"
  if ! { docker run -d --name "$c" "$2" tail -f /dev/null >/dev/null 2>"$_HI_WORKDIR/$1.run.log" &&
    docker exec "$c" mkdir -p /opt/hi/say-hi 2>>"$_HI_WORKDIR/$1.run.log" &&
    tar -C "$_HI_ROOT" --exclude=./.git --exclude=./.github --exclude=./.claude --exclude=./local \
      --exclude=./dist -cf - . | docker cp - "$c:/opt/hi/say-hi" 2>>"$_HI_WORKDIR/$1.run.log"; }; then
    _hi_dump_log "could not start $2 with this tree in it:" "$_HI_WORKDIR/$1.run.log" "$YELLOW"
    return 1
  fi
}

# _hi_hp_read <label> <bash|zsh> [own] - the PS1 home-prompt.sh read, into
# $_HI_HP_PS1
function _hi_hp_read() {
  local out err="$_HI_WORKDIR/$1.$2.err"
  out="$(timeout 300 docker exec -e TERM=xterm-256color "hi-homeprompt-$1-$$" \
    bash /opt/hi/say-hi/tests/dockerfiles/home-prompt.sh "${@:2}" 2>"$err")" || {
    _hi_dump_log "home-prompt.sh $2 failed:" "$err"
    return 1
  }
  case "$out" in
  *'HIPS1<'*'>HIEND'*) ;;
  *)
    _hi_because "no prompt read: [$out]"
    return 1
    ;;
  esac
  _HI_HP_PS1="${out##*HIPS1<}" _HI_HP_PS1="${_HI_HP_PS1%%>HIEND*}"
}

# <label> <shell> - a stock rc's prompt is drawn over
function test_home_prompt_drawn() {
  _hi_hp_read "$1" "$2" || return 1
  [[ "$_HI_HP_PS1" == *__hi_env_info* ]] || _hi_because "$1 $2 kept [$_HI_HP_PS1]"
}

# <label> <shell> - a PS1 the rc sets ahead of hi's block stays
function test_home_prompt_stays() {
  _hi_hp_read "$1" "$2" "$_HI_HP_OWN" || return 1
  [ "$_HI_HP_PS1" = "$_HI_HP_OWN" ] || _hi_because "$1 $2 drew [$_HI_HP_PS1] over [$_HI_HP_OWN]"
}

function run_home_prompt_tests() {
  local row label image zsh_ok
  _hi_require_backend docker
  _hi_workdir homeprompt
  _hi_suite_begin
  _hi_h1 "Testing hi's prompt at home over each distro's own rc"

  for row in "${_HI_HP_IMAGES[@]}"; do
    label="${row%%|*}" image="${row#*|}"
    _hi_h2 "Testing: $label ($image)"
    if ! _hi_hp_start "$label" "$image"; then
      _hi_skip "[$label] a stock .bashrc gets hi's prompt" "no $image"
      _hi_skip "[$label] a PS1 of the user's own stays" "no $image"
      continue
    fi
    _hi_check "[$label] a stock .bashrc gets hi's prompt" test_home_prompt_drawn "$label" bash
    _hi_check "[$label] a PS1 of the user's own stays" test_home_prompt_stays "$label" bash
    [ "$label" = debian ] || continue
    zsh_ok=0
    docker exec "hi-homeprompt-$label-$$" sh -c \
      'apt-get update -qq && apt-get install -y -qq --no-install-recommends zsh' \
      >"$_HI_WORKDIR/zsh.log" 2>&1 && zsh_ok=1
    if [ "$zsh_ok" = 1 ]; then
      _hi_check "[$label] zsh: hi's prompt without one of the user's" test_home_prompt_drawn "$label" zsh
      _hi_check "[$label] zsh: a PS1 of the user's own stays" test_home_prompt_stays "$label" zsh
    else
      _hi_dump_log "apt-get could not install zsh:" "$_HI_WORKDIR/zsh.log" "$YELLOW"
      _hi_skip "[$label] zsh: hi's prompt without one of the user's" "no zsh"
      _hi_skip "[$label] zsh: a PS1 of the user's own stays" "no zsh"
    fi
  done

  _hi_suite_end "home_prompt"
}

run_home_prompt_tests
