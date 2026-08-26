#!/usr/bin/env bash
# The container-backend suites, whole: one throwaway container per case, and the
# docker/podman/nomad/kube test bodies that drive hi.sh through it.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# Top-level rather than nested in _hi_container_backend_test, so any suite that
# boots a throwaway container around one case can use them. They read the
# conventions the e2e suites already set: $_HI_BACKEND (the CLI to drive) and
# $_HI_TEST_MARKER (the transcript marker _hi_probe_cmd echoes). The started
# container's name is left in $_HI_CONTAINER.
_HI_CONTAINER=""

function _hi_container_running() {
  [ "$("${_HI_BACKEND:-docker}" container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

# _hi_start_case_container <label> <image> [run-arg...] - boot one throwaway
# container for a case (kept alive by `tail -f`), registered for teardown,
# waited until the backend reports it running. Extra arguments go to `run`
# ahead of the image (a `--label`, say), as _hi_sshd_container's do.
function _hi_start_case_container() {
  local label="$1" image="$2"
  shift 2

  _HI_CONTAINER="hi-${_HI_BACKEND}test-$label-$$"
  _hi_h3 "Testing shell: $label"

  # tracked before the run, for the reason _hi_sshd_container states
  _hi_track_container "$_HI_CONTAINER"
  if ! "$_HI_BACKEND" run -d --name "$_HI_CONTAINER" "$@" "$image" tail -f /dev/null \
    >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
    _hi_dump_log "Failed to start container (image: $image):" "$_HI_WORKDIR/$label.run.log"
    return 1
  fi
  _hi_cecho " | Container: $_HI_CONTAINER (image: $image)"

  if ! _hi_poll_bool 40 0.25 _hi_container_running "$_HI_CONTAINER"; then
    _hi_cecho " | Container never reported running" "$RED"
    return 1
  fi
}

# _hi_backend_case <label> <image> <cmd> [timeout_s] - one command-shaped case:
# boot, run hi against the container, tear down, report.
function _hi_backend_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local ok=0
  # the case's own, not the suite's: _hi_start_case_container assigns into this
  # frame, so two cases running at once cannot read each other's container
  local _HI_CONTAINER=""

  _hi_start_case_container "$label" "$image" || return 1
  _hi_exec_case "$label" "$_HI_BACKEND path" "$_HI_TEST_MARKER" "$timeout_s" "$_HI_CONTAINER" "$cmd" && ok=1
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

# _hi_backend_interactive_case <label> <image> [timeout_s] - the interactive
# shape, plus the cleanup assertion: the disposable tree must be gone from the
# container once the session ends.
function _hi_backend_interactive_case() {
  local label="$1" image="$2" timeout_s="${3:-60}"
  local ok=0
  local _HI_CONTAINER=""

  _hi_start_case_container "$label" "$image" || return 1
  if _hi_interactive_case "$label" "$_HI_BACKEND path (interactive)" "$_HI_TEST_MARKER" \
    "$timeout_s" "$_HI_LAUNCHER" "$_HI_CONTAINER"; then
    ok=1
    if "$_HI_BACKEND" exec "$_HI_CONTAINER" sh -c 'ls -d /tmp/*.hi.log.* >/dev/null 2>&1'; then
      _hi_align " | [$label] -- say-hi's copy was left behind in the container" "FAILED" "$RED"
      ok=0
    fi
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

# Boots throwaway containers - one per shell environment - and drives hi.sh's
# real _say_hi_container against each of them over `<backend> exec`. Podman's
# CLI is a full drop-in for docker's here, so
# docker_test.sh and podman_test.sh are both just `_hi_container_backend_test
# docker|podman` - this one function proves both branches of
# _say_hi_container: the bash-present main path (tar copy + `bash --rcfile`),
# and every arm of the bash-less fallback's ladder ($_HI_SHELL_LADDER).
# Everything is ephemeral and nothing touches host ssh config. Skips cleanly
# if $backend isn't installed/running. Needs network access the first time it
# runs, to pull/build the test images.
#
# Extra case functions (docker_test.sh's compose-alias case, so far - podman
# has none) ride in the same parallel batch, on _hi_backend_pair_cases'
# precedent: each takes no args of its own and reads $_HI_BACKEND/
# $_HI_TEST_MARKER, since _hi_par_case runs it in a fresh subshell per case.
function _hi_container_backend_test() {
  local backend="$1"
  shift
  local -a extra_cases=("$@")

  _hi_require_backend "$backend"
  _HI_BACKEND="$backend"
  _hi_workdir "${backend}test"
  _hi_h1 "Testing hi's $backend path across container shell environments"

  _hi_h2 "Building test images"
  # shellcheck disable=SC2034 # read back through _hi_kv_get, which shellcheck
  # cannot follow (the name is a string there)
  local shell shell_ok=""
  local -a built_images=()
  for shell in zsh fish dash; do
    # an empty context: alpine-shell.Dockerfile has no COPY, and the build
    # still wants a directory to be handed
    mkdir -p "$_HI_WORKDIR/$shell"
    if _hi_build_image "$shell" "hi-${backend}test-$shell-$$" "the $shell fallback" \
      --build-arg "PKGS=$shell" -f "$(_hi_dockerfile alpine-shell)" "$_HI_WORKDIR/$shell"; then
      _hi_kv_set shell_ok "$shell" 1
    else
      _hi_kv_set shell_ok "$shell" 0
    fi
    # recorded whether or not the build succeeded: a half-built tag still
    # wants removing, and `image rm -f` on a name that never existed is a no-op
    built_images+=("hi-${backend}test-$shell-$$")
  done

  _HI_TEST_MARKER="HI_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - $backend exec -it will fail outright, results may be unreliable"

  _hi_suite_begin

  # Every case here boots its own container and reads nothing another case
  # writes, so the whole battery is one parallel batch.
  _hi_par_begin "$backend shell environments"
  _hi_par_case bash _hi_backend_case bash debian:bookworm-slim "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  _hi_par_case bash-interactive _hi_backend_interactive_case bash-interactive debian:bookworm-slim
  local spec
  for spec in zsh:fallback fish:fallback_fish dash:fallback; do
    shell="${spec%%:*}"
    if [ "$(_hi_kv_get shell_ok "$shell")" = 1 ]; then
      _hi_par_case "$shell" _hi_backend_case "$shell" "hi-${backend}test-$shell-$$" "$(_hi_probe_cmd "$_HI_TEST_MARKER" "${spec#*:}")"
    fi
  done
  _hi_par_case sh _hi_backend_case sh alpine:3.24 "$(_hi_probe_cmd "$_HI_TEST_MARKER" fallback)"
  local extra
  for extra in ${extra_cases[@]+"${extra_cases[@]}"}; do
    _hi_par_case "${extra##*_}" "$extra"
  done
  _hi_par_wait

  # $$-suffixed like the container names: without it a second run of this
  # suite on the same host removes the images the first is still running from.
  # The list comes from the build loop rather than being spelled again, so a
  # shell added there cannot be left behind here.
  "$backend" image rm -f "${built_images[@]}" >/dev/null 2>&1 || true

  _hi_suite_end "$backend" \
    "hi's $backend path survived every shell environment tested ($_HI_TOTAL cases)" \
    "hi's $backend path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

# _hi_backend_pair_cases <label> <thing tested> - the bash-present + bash-less
# case pair every ephemeral-cluster suite (kube, nomad) ends with, once its
# own cluster/agent is up, $_HI_TEST_MARKER is set, and a suite-local
# _hi_run_case is in scope. _say_hi_container's fallback logic past the
# initial `command -v bash` probe is identical for every backend and already
# proven by _hi_container_backend_test above, so these suites only need to
# prove their own backend's probe/attach argument shapes - once with bash
# present, once without.
# The pair runs as a batch, which is a real saving on kube (two pods scheduled
# together on a cluster that took 40s to exist) and none at all on nomad - whose
# suite tracks its jobs in a shell array and therefore asks for _HI_PAR_WIDTH=1,
# so this path stays one code path either way.
# The pair's two images, named once: kube side-loads them into its cluster
# before the cases run, and a preload that drifts from what the cases ask for is
# a silent 20-second wait, not an error.
_HI_PAIR_IMAGE_BASH="debian:bookworm-slim"
_HI_PAIR_IMAGE_SH="alpine:3.24"

# _hi_backend_pair_cases <label> <thing> [extra-case-fn...] - the bash/sh pair
# every backend runs, plus any case only one backend has. The extras go inside
# the same parallel block on purpose: _hi_suite_end below reports and exits, so
# a caller cannot add a check after this returns - it does not return.
function _hi_backend_pair_cases() {
  local label="$1" thing="$2" extra
  shift 2

  _hi_suite_begin

  _hi_par_begin "$label cases"
  _hi_par_case bash _hi_run_case bash "$_HI_PAIR_IMAGE_BASH" "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  _hi_par_case sh _hi_run_case sh "$_HI_PAIR_IMAGE_SH" "$(_hi_probe_cmd "$_HI_TEST_MARKER" fallback)"
  for extra in "$@"; do
    _hi_par_case "${extra##*_}" "$extra"
  done
  _hi_par_wait

  _hi_suite_end "" \
    "hi's $label path survived every $thing tested ($_HI_TOTAL cases)" \
    "hi's $label path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}
