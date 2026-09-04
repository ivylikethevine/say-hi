#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# hi against the shell frameworks people actually have installed.
#
# Almost nobody's ~/.zshrc is empty, and load.sh appends hi's block to the *end*
# of it - so hi runs after the framework and is the one positioned to break it.
# The canonical collision: a `setopt KSH_ARRAYS` set for hi's convenience,
# against an oh-my-zsh that indexes arrays from 1.
#
# Each case boots a container with the framework installed per its own README,
# connects for real, and asserts the marker landed, the probe below says the
# specific collision is absent, and the transcript carries no shell error noise.
# A collision is rarely fatal - it just prints at you every prompt, which is
# what no other suite would notice.
#
# Each image keeps every shell the base has: load() follows the *login* shell
# now (see _hi_session_shell), so the framework's own shell is the one hi lands
# in - which is also what makes these cases a test of that. Builds need the
# network; a failed one skips its case rather than failing the suite.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# "<label>=<0|1>", the same kv shape the other target suites use
_HI_FRAMEWORK_OK=""

# <label>:<login shell>:<apt packages>:<probe family>. Every image is
# tests/dockerfiles/framework.Dockerfile with the packages installed and
# tests/dockerfiles/frameworks/<label>.sh run as hitest: each script installs
# its framework unattended and leaves a *real* rc file behind - an empty
# ~/.zshrc would prove nothing, since the whole question is what happens when
# hi's block is appended after someone else's. The family is the last field so
# its own colon (bind:fzf) survives the split.
_HI_FRAMEWORKS=(
  "omz:/usr/bin/zsh:zsh curl git:zsh"
  "p10k:/usr/bin/zsh:zsh curl git:zsh"
  "starship:/bin/bash:curl:bash"
  "bashit:/bin/bash:git:bash"
  # The env tools, which hook the same two surfaces hi's bash half touches -
  # each probed by the family:<needle> in its third field: bind:* is a
  # `bind -x` key binding (fzf's and atuin's Ctrl-R), hook:* a PROMPT_COMMAND
  # hook, the needle being the tool's handler name. zoxide's hook is
  # _zoxide_hook in debian's 0.8 and __zoxide_hook upstream; the
  # underscore-less needle matches both.
  "fzf:/bin/bash:fzf:bind:fzf"
  "zoxide:/bin/bash:zoxide:hook:zoxide_hook"
  "direnv:/bin/bash:direnv:hook:_direnv_hook"
  "atuin:/bin/bash:curl:bind:atuin"
  "mise:/bin/bash:curl:hook:mise"
)

# The line each case types into the live session, once hi and the framework are
# both loaded. Built from two arguments because a pty echoes the input, so the
# token must be assembled by the shell. zsh checks the array base (hi must not
# leave KSH_ARRAYS on under omz/p10k); bash checks that hi's `ps1` is still
# chained onto the framework's PROMPT_COMMAND rather than replacing it.
function _hi_framework_probe() {
  case "$1" in
  zsh) printf '%s\n' "setopt | grep -q ksharrays && printf 'HI_FW-%s\\n' LEAKED || printf 'HI_FW-%s\\n' CLEAN" ;;
  bash) printf '%s\n' "[[ \$PROMPT_COMMAND == *ps1* ]] && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  # the tool's Ctrl-R must still be its own after hi loads - `bind -X` lists
  # the bind -x bindings, and the handlers carry their tool's name
  bind:*) printf '%s\n' "bind -X 2>/dev/null | grep -q ${1#bind:} && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  # both hooks in one PROMPT_COMMAND: the tool's (by its hook's name) still
  # there, and hi's ps1 *chained* on rather than having replaced it. The [*]
  # expansion reads the whole thing whether the tool appended to it as a
  # string or as bash 5.1's array form - bare $PROMPT_COMMAND would show
  # element 0 alone and cry LOST over a coexistence that is fine.
  hook:*) printf '%s\n' "[[ \${PROMPT_COMMAND[*]} == *${1#hook:}* && \${PROMPT_COMMAND[*]} == *ps1* ]] && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  esac
}

# One image per framework, each tests/dockerfiles/framework.Dockerfile with
# that row's packages and setup script, on top of the shared sshd base. A
# failed build - these all reach the network - marks its label 0 and the case
# skips rather than failing the suite.
function _hi_build_frameworks() {
  local spec label shell pkgs family
  for spec in "${_HI_FRAMEWORKS[@]}"; do
    IFS=: read -r label shell pkgs family <<<"$spec"
    # the context is tests/dockerfiles itself: the one COPY is the script
    # under frameworks/, and nothing else in that directory is large
    if _hi_build_image "$label" "hi-fwtest-$label-$$" "the $label case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      --build-arg "FRAMEWORK=$label" --build-arg "PKGS=$pkgs" \
      -f "$(_hi_dockerfile framework)" "$_HI_ROOT/tests/dockerfiles"; then
      _hi_kv_set _HI_FRAMEWORK_OK "$label" 1
    else
      _hi_kv_set _HI_FRAMEWORK_OK "$label" 0
    fi
  done
}

# the shared driver's feeder hook: types the probe for the framework family
# under test into the live session (see _hi_interactive_case's -f)
function _hi_type_framework_probe() {
  _hi_framework_probe "$_HI_FW_FAMILY"
}

# One interactive session per framework - a command-shaped run replaces load()
# outright and never reaches the session rc, which is where collisions live. The
# probe (a second typed line) rides _hi_interactive_case's feeder hook.
function _hi_run_framework_case() {
  local label="$1" login_shell="$2" name ok=0
  # both case-scoped, and both for the same reason: cases run concurrently, and
  # bash's dynamic scoping is what carries the family down to the feeder hook
  # _hi_interactive_case calls on this case's behalf
  local _HI_SSH_PORT=""
  local _HI_FW_FAMILY="$3"

  # checked before the container boots, not after: with no pty to drive there
  # is nothing a booted container could add to the skip
  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[$label]" "no python3 to drive an interactive pty"
    return 0
  fi

  name="hi-fwtest-$label-c-$$"
  _hi_h3 "Testing framework: $label ($login_shell)"
  _hi_sshd_container "$name" "hi-fwtest-$label-$$" -e "LOGIN_SHELL=$login_shell" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"

  if _hi_interactive_case -f _hi_type_framework_probe -m "HI_FW-CLEAN" \
    "$label" framework "$_HI_TEST_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    # the assertion this suite exists for: hi and the framework coexisting
    # without either one printing at the user
    _hi_transcript_is_clean "$label" "$_HI_WORKDIR/$label.interactive.out" && ok=1
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

function run_framework_tests() {
  _hi_require_backend docker

  _hi_workdir fwtest
  _hi_h1 "Testing hi alongside the common shell frameworks"
  _hi_ssh_keypair

  _hi_h2 "Building test images"
  _hi_sshd_image "the framework cases" || _hi_stand_down "no base image"
  _hi_build_frameworks

  _HI_TEST_MARKER="HI_FRAMEWORK_TEST_OK"
  _hi_pty_stdin auto "no tty and no python3 to fake one - results may be unreliable"

  _hi_suite_begin

  # Nine frameworks, nine containers, nothing shared between them - the widest
  # fan-out in the tree and the one this suite is almost entirely made of.
  local spec label shell pkgs family
  _hi_par_begin "framework cases"
  for spec in "${_HI_FRAMEWORKS[@]}"; do
    IFS=: read -r label shell pkgs family <<<"$spec"
    if [ "$(_hi_kv_get _HI_FRAMEWORK_OK "$label")" = 1 ]; then
      _hi_par_case "$label" _hi_run_framework_case "$label" "$shell" "$family"
    else
      _hi_skip "[$label]" "image did not build"
    fi
  done
  _hi_par_wait

  for spec in "${_HI_FRAMEWORKS[@]}"; do
    docker image rm -f "hi-fwtest-${spec%%:*}-$$" >/dev/null 2>&1 || true
  done

  _hi_suite_end "" \
    "hi coexists with every framework tested ($_HI_TOTAL cases)" \
    "hi collides with $_HI_FAILED/$_HI_TOTAL frameworks"
}

run_framework_tests
