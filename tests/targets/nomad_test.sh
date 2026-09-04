#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Boots a throwaway `nomad agent -dev` (single-node, server+client, its own
# temp data dir) and drives hi.sh's real nomad path (_say_hi_container) over
# actual `nomad alloc exec` against jobs running under nomad's docker task
# driver.
# Only two cases are covered here, not the full zsh/fish fallback matrix
# docker_test.sh/podman_test.sh run: _say_hi_container's fallback logic past
# the initial `command -v bash` probe is identical code for every backend and
# is already proven there, so this only needs to prove nomad's own probe/cp/
# attach argument shapes work - once with bash present, once without.
# Everything is ephemeral (its own data dir, agent process, jobs) and bound to
# 127.0.0.1 only. Skips cleanly if nomad or docker isn't installed/reachable
# (the dev agent's docker task driver needs a real docker daemon).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_free_port_base [count] - a base port with $count consecutive free ports
# from it, printed on stdout. A suite that binds a well-known port collides
# with any real service of the same kind already on the host (and with a
# second copy of itself), which is a failure that looks exactly like a bug in
# the code under test. The ssh fixtures avoid this by letting docker map an
# ephemeral port; anything hi runs directly has to pick its own, so it asks
# here. Probing is a connect attempt: refused means nothing is listening.
# Racy in principle, since something could claim the port between the probe
# and the bind, but bounded - and unlike a hardcoded port it is usually right.
function _hi_free_port_base() {
  local count="${1:-1}" base i ok attempt
  for ((attempt = 0; attempt < 20; attempt++)); do
    base=$((20000 + RANDOM % 20000))
    ok=1
    for ((i = 0; i < count; i++)); do
      if (exec 3<>"/dev/tcp/127.0.0.1/$((base + i))") 2>/dev/null; then
        ok=0
        break
      fi
    done
    if [ "$ok" -eq 1 ]; then
      printf '%s' "$base"
      return 0
    fi
  done
  return 1
}
_HI_NOMAD_PID=""

function _hi_nomad_cleanup() {
  local j
  # the harness ledger, not a shell array: it is file-backed, so a job
  # registered inside a background case survives the subshell that ran it
  for j in $(_hi_ledger_rows job); do
    nomad job stop -purge "$j" >/dev/null 2>&1 || true
  done
  if [ -n "$_HI_NOMAD_PID" ] && kill -0 "$_HI_NOMAD_PID" 2>/dev/null; then
    kill "$_HI_NOMAD_PID" 2>/dev/null
    wait "$_HI_NOMAD_PID" 2>/dev/null
  fi
}

_HI_TEST_MARKER="HI_NOMAD_TEST_OK"

# first running allocation ID for a job, once it has one
function _hi_first_running_alloc() {
  nomad job allocs -t \
    '{{range .}}{{if eq .ClientStatus "running"}}{{.ID}}{{"\n"}}{{end}}{{end}}' \
    "$1" 2>/dev/null | head -1
}

function _hi_dump_alloc_status() {
  _hi_cecho " |  nomad alloc status $alloc:" "$YELLOW"
  nomad alloc status "$alloc" 2>&1 | sed 's/^/      /'
}

function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local job jobfile alloc ok=0

  job="hi-nomadtest-$label-$$"
  jobfile="$_HI_WORKDIR/$label.nomad.hcl"
  _hi_h3 "Testing driver shape: [$label]"

  cat >"$jobfile" <<EOF
job "$job" {
  datacenters = ["dc1"]
  type        = "service"

  group "hitest" {
    count = 1
    task "hitest" {
      driver = "docker"
      config {
        image   = "$image"
        command = "sleep"
        args    = ["infinity"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF

  if ! nomad job run -detach "$jobfile" >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_dump_log "failed to submit job:" "$_HI_WORKDIR/$label.run.log"
    return 1
  fi
  _hi_ledger job "$job"
  _hi_cecho " | Job: $job (image: $image)"

  if ! alloc="$(_hi_poll_value 80 0.25 _hi_first_running_alloc "$job")"; then
    _hi_cecho " | Allocation never reported running" "$RED"
    return 1
  fi
  _hi_cecho " | Allocation: $alloc"

  _hi_exec_case "$label" "nomad path" "$_HI_TEST_MARKER" "$timeout_s" "$alloc" "$cmd" _hi_dump_alloc_status && ok=1
  nomad job stop -purge "$job" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

# The alloc/task syntax, against a group that actually has two tasks. Same
# assertion as the kube suite's twin: not "it connected" but "it connected to
# the one named". Without the suffix nomad refuses a multi-task exec outright
# rather than guessing, so the plain form is expected to fail here - which is
# why only the suffixed one is asserted.
function _hi_nomad_multi_task_case() {
  local job="hi-nomadtest-multi-$$" jobfile="$_HI_WORKDIR/multi.nomad.hcl"
  local alloc got ok=0
  _hi_h3 "Testing driver shape: [multi-task]"
  cat >"$jobfile" <<EOF
job "$job" {
  datacenters = ["dc1"]
  type        = "service"

  group "hitest" {
    count = 1
    task "app" {
      driver = "docker"
      config {
        image   = "$_HI_PAIR_IMAGE_SH"
        command = "sh"
        args    = ["-c", "echo app >/tmp/who; sleep infinity"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }
    task "sidecar" {
      driver = "docker"
      config {
        image   = "$_HI_PAIR_IMAGE_SH"
        command = "sh"
        args    = ["-c", "echo sidecar >/tmp/who; sleep infinity"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF
  if ! nomad job run -detach "$jobfile" >"$_HI_WORKDIR/multi.run.log" 2>&1; then
    _hi_dump_log "failed to submit the multi-task job:" "$_HI_WORKDIR/multi.run.log"
    return 1
  fi
  _hi_ledger job "$job"
  if ! alloc="$(_hi_poll_value 120 0.25 _hi_first_running_alloc "$job")"; then
    _hi_cecho " | Multi-task allocation never reported running" "$RED"
    nomad job stop -purge "$job" >/dev/null 2>&1
    return 1
  fi
  _hi_cecho " | Allocation: $alloc"

  # through the suite's pty wrapper, like _hi_exec_case: `nomad alloc exec`
  # refuses outright with "not a terminal" when stdin is a pipe, and hi asks
  # for -t=true because a real session needs one.
  got="$(${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "$_HI_ROOT/hi.sh" "$alloc/sidecar" 'cat /tmp/who' 2>/dev/null |
    tr -d '\r' | tail -1)"
  if [ "$got" = sidecar ]; then
    _hi_align " | alloc/task reached the named task" "OK" "$GREEN"
    ok=1
  else
    _hi_cecho " | hi $alloc/sidecar read '$got', expected 'sidecar'" "$RED"
  fi
  nomad job stop -purge "$job" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

function run_nomad_test() {
  _hi_require nomad
  _hi_require_backend docker "not installed (nomad's dev agent needs it for the docker task driver)"
  _hi_workdir nomadtest _hi_nomad_cleanup

  _hi_h1 "Testing hi's nomad path against a throwaway dev agent"

  # An agent on the well-known 4646 collides with any real nomad on this
  # machine, and its cleanup would then purge that agent's jobs rather than
  # its own. Take three consecutive free ports instead - dev mode needs http,
  # rpc and serf - the same way the ssh fixtures let docker pick an ephemeral
  # one. NOMAD_ADDR is exported so every nomad call in this suite, hi.sh's
  # backend probe included, reaches this agent and not another.
  local port_base
  port_base="$(_hi_free_port_base 3)" ||
    _hi_stand_down "no free ports" "couldn't find three free ports for the dev agent, skipping"
  cat >"$_HI_WORKDIR/agent.hcl" <<EOF
ports {
  http = $port_base
  rpc  = $((port_base + 1))
  serf = $((port_base + 2))
}
EOF

  _hi_h2 "Starting nomad agent -dev on port $port_base"
  nomad agent -dev -data-dir="$_HI_WORKDIR/data" -log-level=WARN \
    -config="$_HI_WORKDIR/agent.hcl" \
    >"$_HI_WORKDIR/agent.log" 2>&1 &
  _HI_NOMAD_PID=$!
  export NOMAD_ADDR="http://127.0.0.1:$port_base"

  function _hi_nomad_alive() { kill -0 "$_HI_NOMAD_PID" 2>/dev/null; }
  if ! _hi_poll_bool -a _hi_nomad_alive 60 0.5 nomad node status; then
    _hi_dump_log "Nomad dev agent never came up:" "$_HI_WORKDIR/agent.log" "$YELLOW"
    _hi_stand_down "nomad dev agent never came up"
  fi
  _hi_cecho " | Dev agent up: $NOMAD_ADDR" "$GREEN"

  _hi_pty_stdin force "no python3 to give the launcher its own pty - nomad alloc exec's attach may not get a real pty, results may be unreliable"

  # Serial on purpose, and said out loud by _hi_par_begin: two cases against a
  # single-node dev agent are worth ~3s of a 348s run, and the ssh, framework
  # and container suites are where the wall clock actually is. Job teardown is
  # not a constraint here: it goes through the ledger, which is subshell-safe.
  export _HI_PAR_WIDTH=1
  _hi_backend_pair_cases nomad "driver shape" _hi_nomad_multi_task_case
}

run_nomad_test
