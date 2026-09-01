#!/usr/bin/env bash
# Drives hi.sh's real docker path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with podman_test.sh. docker also gets one extra case podman does not:
# compose service aliases, docker-only per hi.sh's _hi_compose_container.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# A container carrying a compose label, driven through the *alias* rather than
# $_HI_CONTAINER - the point is proving _hi_compose_container resolves it, not
# that the real name still works (the plain "bash" case covers that path).
function _hi_docker_compose_alias_case() {
  local label="compose" alias="hi-dockertest-composesvc-$$"
  local _HI_CONTAINER="" ok=0

  if _hi_start_case_container "$label" debian:bookworm-slim \
    --label "com.docker.compose.service=$alias"; then
    _hi_cecho " | Alias: $alias"
    _hi_exec_case "$label" "docker path (compose alias)" "$_HI_TEST_MARKER" 30 \
      "$alias" "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)" && ok=1
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

# A read-only root with $TMPDIR pointing at the one writable mount - the shape
# a pod with readOnlyRootFilesystem and an emptyDir gets - has to land the
# tree under $TMPDIR (the marker asserts $_HI_ROOT's parent), and the same
# container with nowhere writable at all has to say so and name --plain rather
# than fail at the copy with a message about the copy. Docker-only for the
# same reason as the compose case: podman's flags for both differ, and the
# code under test (the target-side mkdir) is one function across backends.
function _hi_docker_case_tmpdir() {
  local label="tmpdir" ok=0
  local _HI_CONTAINER=""

  if _hi_start_case_container "$label" debian:bookworm-slim \
    --read-only --tmpfs /scratch -e TMPDIR=/scratch; then
    _hi_exec_case "$label" "docker path (read-only root, \$TMPDIR)" "$_HI_TEST_MARKER" 30 \
      "$_HI_CONTAINER" "$(_hi_probe_cmd "$_HI_TEST_MARKER" rooted_under /scratch)" && ok=1
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

function _hi_docker_case_notmp() {
  local label="notmp" ok=0
  local _HI_CONTAINER=""

  if _hi_start_case_container "$label" debian:bookworm-slim --read-only; then
    _hi_exec_case "$label" "docker path (nowhere writable)" "no writable temp directory" 30 \
      "$_HI_CONTAINER" "echo $_HI_TEST_MARKER" && ok=1
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

_hi_container_backend_test docker _hi_docker_compose_alias_case _hi_docker_case_tmpdir _hi_docker_case_notmp
