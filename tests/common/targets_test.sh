#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for common/targets.sh - the "<name>\t<kind>" list behind `hi`'s
# bash/zsh/fish completions and hi.sh's own _hi_is_ssh_host check.
#
# The ssh half runs against fixture ~/.ssh/config files in the scratch dir; the
# docker/podman/nomad/kube halves run against fake CLIs on $PATH, so the
# expected output is fixed instead of "whatever this machine happens to be
# running". A third PATH - a toolbox holding only the commands targets.sh
# itself needs - covers the "no backend installed at all" shape.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_SHIM_PATH=""
_HI_TOOLBOX_PATH=""
_HI_CONFIG=""
_HI_NO_CONFIG=""

# Fake backend CLIs, each answering only the exact invocation targets.sh makes
# and failing anything else, so a changed command shape shows up as a missing
# row rather than a silently passing test.
function _hi_write_shims() {
  local dir="$_HI_WORKDIR/shims" tool
  mkdir -p "$dir"

  # "beta compose-svc" is the compose-labeled shape: {{.Names}} {{.Label ...}}
  # separated by a space, an empty second field for a plain container
  cat >"$dir/docker" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'alpha\nbeta compose-svc\n'
EOF

  # podman renders the same {{.Label ...}} template docker does (verified
  # against a real podman), so its lane carries the compose column too
  cat >"$dir/podman" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'pod-one\npod-two compose-pod\n'
EOF

  # a third family member (GLOSSARY: HI.51); finch is deliberately not
  # shimmed, so the default roster always carries one absent member
  cat >"$dir/nerdctl" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'nerd-one\n'
EOF

  # two members fronting one daemon, podman-docker style: both answer `twin`
  mkdir -p "$dir/twins"
  cat >"$dir/twins/docker" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'twin\nonly-docker\n'
EOF
  cat >"$dir/twins/podman" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'twin\nonly-podman\n'
EOF
  chmod +x "$dir/twins/docker" "$dir/twins/podman"
  _HI_TWIN_PATH="$dir/twins:$PATH"

  # `nomad job status` (header row + one job), then `nomad job allocs` per job
  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
case "$1 $2" in
"job status") printf 'ID    Type     Status\nweb   service  running\n' ;;
"job allocs") printf 'abc12345\n' ;;
*) exit 1 ;;
esac
EOF

  # `get pods -A` rows are "<namespace> <pod> [containers...]"; `config view`
  # answers the current namespace, so pod-c should come back prefixed
  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
case "$1" in
config) printf 'default' ;;
get) printf 'default pod-a\ndefault pod-b\nother pod-c\n' ;;
*) exit 1 ;;
esac
EOF

  for tool in docker podman nerdctl nomad kubectl; do
    chmod +x "$dir/$tool"
  done
  _HI_SHIM_PATH="$dir:$PATH"
}

# The same idea, slowed down and made to keep a diary: each backend records
# "<name> start", waits, then records "<name> end". Run in turn that log reads
# start/end/start/end; run together the three starts bunch at the top before
# any end - which is the whole claim emit_targets's fan-out makes, asserted on
# the *order* of events rather than on a stopwatch, so a loaded runner and the
# macOS job read it the same way.
#
# Gated on fork_concurrency, not just slowed down: a 2026-08-28 windows-latest
# dispatch measured this fan-out taking exactly as long as the deliberately
# in-turn fallback below, at both a 0.3s and a 2s wait - MSYS
# backgrounding doesn't overlap here at all, so no wait would ever pass this,
# and a longer one only slows every other platform for nothing.
#
# nomad answers a header row and no jobs: it belongs to the roster (four
# backends is what makes emit_targets fan out at all) but has nothing to wait
# for, and its per-job fan-out is a second mechanism this case is not about.
_HI_SLOW_PATH=""

_HI_PROBE_LOG=""

# Each lane logs its start, then waits for the other two to start - up to 2s -
# before it logs its end. A meeting, not a fixed `sleep`: a sleep proves
# overlap only if all three lanes start inside it, which a loaded BSD VM does
# not promise. Lanes run together pass at once; lanes run in turn each wait
# out the 2s (under the 10s probe cap _hi_targets_slow gives them) and log
# their end first, which is what the in-turn case asserts.
# shellcheck disable=SC2016 # the shims' own code, expanded when they run
_HI_SLOW_MEET='i=0
while [ "$(awk "/ start\$/ { n++ } END { print n + 0 }" "$_HI_PROBE_LOG")" -lt 3 ] && [ "$i" -lt 20 ]; do
  sleep 0.1
  i=$((i + 1))
done'

function _hi_write_slow_shims() {
  local dir="$_HI_WORKDIR/slowshims" tool
  mkdir -p "$dir"
  _HI_PROBE_LOG="$_HI_WORKDIR/probe.log"

  for tool in docker podman; do
    cat >"$dir/$tool" <<EOF
#!/bin/sh
[ "\$1" = ps ] || exit 1
printf '$tool start\\n' >>"\$_HI_PROBE_LOG"
$_HI_SLOW_MEET
printf '$tool end\\n' >>"\$_HI_PROBE_LOG"
printf 'slow-$tool\\n'
EOF
  done

  cat >"$dir/kubectl" <<EOF
#!/bin/sh
[ "\$1" = get ] || exit 1
printf 'kube start\\n' >>"\$_HI_PROBE_LOG"
$_HI_SLOW_MEET
printf 'kube end\\n' >>"\$_HI_PROBE_LOG"
printf 'default slow-pod\n'
EOF

  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
[ "$1 $2" = "job status" ] || exit 1
printf 'ID    Type     Status\n'
EOF

  for tool in docker podman kubectl nomad; do
    chmod +x "$dir/$tool"
  done
  # Its own toolbox rather than $_HI_TOOLBOX_PATH: `sleep` is one of the
  # commands these shims run, and the fan-out arm needs the four the in-turn
  # arm never touches - mkdir and chmod to make the scratch dir, cat and rm to
  # spend it. A PATH missing those is the *no-scratch* case, which is the other
  # test here. No real backend is on it either: a real nomad found behind the
  # fakes would put this machine's daemons back into a fixed case.
  _HI_SLOW_PATH="$dir:$(_hi_real_path slowtools sh awk sed sleep mkdir chmod cat rm)"
}

# targets.sh under the slow shims, from an empty diary. $1, if given, is a
# TMPDIR for the run - the no-scratch case points it somewhere unmakeable.
function _hi_targets_slow() {
  : >"$_HI_PROBE_LOG"
  PATH="$_HI_SLOW_PATH" _HI_SSH_CONFIG="$_HI_NO_CONFIG" _HI_PROBE_LOG="$_HI_PROBE_LOG" \
    TMPDIR="${1:-${TMPDIR:-/tmp}}" _HI_TARGETS_TTL=0 _HI_PROBE_TIMEOUT=10 sh "$_HI_TARGETS"
}

# A PATH with the commands targets.sh runs and nothing else - no docker,
# podman, nomad, or kubectl to find.
function _hi_write_toolbox() {
  _HI_TOOLBOX_PATH="$(_hi_real_path toolbox sh awk sed)"
}

function _hi_write_configs() {
  _HI_CONFIG="$_HI_WORKDIR/ssh_config"
  _HI_NO_CONFIG="$_HI_WORKDIR/no_such_ssh_config"
  cat >"$_HI_CONFIG" <<'EOF'
Host alpha beta
  HostName 10.0.0.1

# a wildcard entry, plus one with a single-character glob
Host *
  User nobody
Host web-?
  User nobody

host lowercase-keyword
  User nobody

Host commented # trailing comment, not a host
  User nobody
EOF
}

# targets.sh under the shimmed PATH: `_hi_targets <config> [kind]`
function _hi_targets() {
  local config="$1"
  shift
  # _HI_TARGETS_TTL=0 disables the result cache. Every case below changes what
  # the fake CLIs answer between runs, so a cached "all" would be handed
  # straight back to the next case and the shims it is meant to be exercising
  # would never run. The cache gets its own cases instead, further down.
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$config" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" "$@"
}

function _hi_has_row() {
  printf '%s\n' "$1" | grep -qxF "$2"$'\t'"$3"
}

function test_multi_alias_host_yields_one_row_each() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  _hi_has_row "$out" alpha ssh && _hi_has_row "$out" beta ssh
}

function test_wildcard_patterns_are_skipped() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  ! printf '%s\n' "$out" | grep -qE '^(\*|web-\?)'
}

function test_lowercase_host_keyword_is_matched() {
  _hi_has_row "$(_hi_targets "$_HI_CONFIG" ssh)" lowercase-keyword ssh
}

function test_trailing_comment_is_not_a_host() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  _hi_has_row "$out" commented ssh || return 1
  ! printf '%s\n' "$out" | grep -Eq 'trailing|comment,'
}

function test_missing_config_is_empty_and_succeeds() {
  local out
  out="$(_hi_targets "$_HI_NO_CONFIG" ssh)" || return 1
  [ -z "$out" ]
}

# a host that lives only in an Included file completes like one in the config
# itself: ~/.ssh-relative paths, globs, and nested Includes; a word that is not
# a path is skipped, never run
function test_ssh_hosts_follow_include() {
  local h="$_HI_WORKDIR/inc-home" out
  mkdir -p "$h/.ssh/config.d" "$h/.ssh/deep"
  # shellcheck disable=SC2016 # the $( ) is the config's text, and must not run
  printf 'Include config.d/* $(touch %s/ran)\nHost top\n' "$h" >"$h/.ssh/config"
  printf 'Host alpha\n  Include deep/*\n' >"$h/.ssh/config.d/01-a"
  printf 'Host gamma\n' >"$h/.ssh/deep/x"
  out="$(HOME="$h" _hi_targets "$h/.ssh/config" ssh)" || return 1
  _hi_has_row "$out" alpha ssh && _hi_has_row "$out" gamma ssh &&
    _hi_has_row "$out" top ssh && [ ! -e "$h/ran" ]
}

# `ssh-files` names every file an Include walk reads, the config first and
# each Included file where ssh reads it - the list hi --add-tag edits
function test_ssh_files_lists_the_config_and_its_includes_in_order() {
  local h="$_HI_WORKDIR/files-home" out
  mkdir -p "$h/.ssh/config.d"
  printf 'Include config.d/*\nHost top\n' >"$h/.ssh/config"
  printf 'Host bravo\n' >"$h/.ssh/config.d/02-b"
  printf 'Host alpha\n' >"$h/.ssh/config.d/01-a"
  out="$(HOME="$h" sh "$_HI_TARGETS" ssh-files "$h/.ssh/config" | tr '\n' ' ')"
  [ "$out" = "$h/.ssh/config $h/.ssh/config.d/01-a $h/.ssh/config.d/02-b " ] || _hi_because "ssh-files: [$out]"
}

# the word after --add-tag is a literal Host from the config or an Include;
# a pattern names no host to tag
function test_add_tag_words_are_the_literal_ssh_hosts() {
  local h="$_HI_WORKDIR/addtag-home" out
  mkdir -p "$h/.ssh/config.d"
  printf 'Include config.d/*\nHost top *.example web?\n' >"$h/.ssh/config"
  printf 'Host alpha # a note\n' >"$h/.ssh/config.d/01-a"
  out="$(HOME="$h" _HI_SSH_CONFIG="$h/.ssh/config" sh "$_HI_TARGETS" words --add-tag | cut -f1 | sort | tr '\n' ' ')"
  [ "$out" = "alpha top " ] || _hi_because "--add-tag words: [$out]" || return 1
  [ -z "$(HOME="$h" _HI_SSH_CONFIG="$h/none" sh "$_HI_TARGETS" words --add-tag)" ]
}

function test_ssh_kind_excludes_container_backends() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  [ -n "$out" ] || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

function test_docker_kind_lists_running_containers() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  _hi_has_row "$out" alpha docker && _hi_has_row "$out" beta docker
}

# ...unless $_HI_BACKENDS_OFF names it, which leaves the others listing
function test_a_backend_switched_off_is_not_listed() {
  local out
  [ -z "$(_HI_BACKENDS_OFF=docker _hi_targets "$_HI_CONFIG" docker)" ] || return 1
  out="$(_HI_BACKENDS_OFF="nomad,docker" _hi_targets "$_HI_CONFIG" all)"
  ! printf '%s\n' "$out" | grep -q $'\tdocker$' && printf '%s\n' "$out" | grep -q $'\tssh$' || return 1
  out="$(_HI_BACKENDS_OFF=all _hi_targets "$_HI_CONFIG" all)"
  [ -n "$out" ] && ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

# beta's compose label rides in as a third row - the friendlier name a real
# session resolves back to "beta" through hi.sh's _hi_compose_container
function test_docker_kind_lists_compose_service_alias() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  _hi_has_row "$out" compose-svc docker
}

# podman resolves a compose service name exactly as docker does - the same
# `{{.Label ...}}` template on the way out and the same `label=` filter on the
# way back through hi.sh's _hi_compose_container. pod-one carries no label, so
# it stays one row while pod-two gains its service alias.
function test_podman_kind_lists_compose_service_alias() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" podman)"
  _hi_has_row "$out" pod-one podman &&
    _hi_has_row "$out" pod-two podman &&
    _hi_has_row "$out" compose-pod podman
}

# alpha has no label, so its second field is empty - must not turn into a
# blank completable row
function test_docker_kind_omits_alias_row_when_label_is_empty() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  ! printf '%s\n' "$out" | grep -qxF $'\t''docker'
}

# every member of the docker-compatible family is a kind of its own, and the
# family is not configurable: all four are always tried (GLOSSARY: HI.51)
function test_nerdctl_kind_lists_running_containers() {
  _hi_has_row "$(_hi_targets "$_HI_CONFIG" nerdctl)" nerd-one nerdctl
}

# a member off $PATH emits nothing and fails nothing: finch has no shim
function test_absent_family_member_is_silent() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" finch)" || return 1
  [ -z "$out" ]
}

# the family's own order is the emission order, ahead of nomad and kube, and
# nothing in the environment reorders or narrows it - a stale
# _HI_CONTAINER_CLIS from an older install is just another unread name
function test_family_order_is_emission_order() {
  local out
  out="$(_HI_CONTAINER_CLIS=podman _hi_targets "$_HI_CONFIG" | grep -v $'\tssh$')"
  [ "$(printf '%s\n' "$out" | sed -n '1p')" = "alpha"$'\t'"docker" ] || return 1
  printf '%s\n' "$out" | grep -qxF "pod-one"$'\t'"podman" || return 1
  printf '%s\n' "$out" | grep -qxF "nerd-one"$'\t'"nerdctl"
}

# podman-docker's `docker` is podman: both lanes list the same container, and
# the row is emitted once, as the earlier lane's kind
function test_duplicate_daemon_rows_are_emitted_once() {
  local out
  out="$(PATH="$_HI_TWIN_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS")"
  [ "$(printf '%s\n' "$out" | grep -c $'^twin\t')" -eq 1 ] || return 1
  _hi_has_row "$out" twin docker || return 1
  _hi_has_row "$out" only-docker docker || return 1
  _hi_has_row "$out" only-podman podman
}

# the dedupe is the family's alone: a pod named like a container keeps its row
function test_dedupe_leaves_nomad_and_kube_alone() {
  local dir="$_HI_WORKDIR/shims/pod-twin" out
  mkdir -p "$dir"
  cp "$_HI_WORKDIR/shims/twins/docker" "$_HI_WORKDIR/shims/twins/podman" "$dir/"
  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
case "$1" in
config) printf 'default' ;;
get) printf 'default twin\n' ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/kubectl"
  out="$(PATH="$dir:$PATH" _HI_SSH_CONFIG="$_HI_CONFIG" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS")"
  _hi_has_row "$out" twin docker || return 1
  _hi_has_row "$out" twin kube
}

function test_nomad_kind_lists_running_allocs() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" nomad)"
  _hi_has_row "$out" abc12345 nomad || return 1
  # the `nomad job status` header row must not become a target of its own
  ! printf '%s\n' "$out" | grep -q '^ID'
}

function test_kube_kind_lists_running_pods() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" kube)"
  _hi_has_row "$out" pod-a kube && _hi_has_row "$out" pod-b kube &&
    _hi_has_row "$out" other:pod-c kube
}

# an alloc running more than one task also offers each as "alloc/task", the
# syntax hi takes for picking one; a lone task is the alloc itself, no row
function test_nomad_multi_task_alloc_lists_each_task() {
  local dir="$_HI_WORKDIR/shims/nomad-tasks" out
  mkdir -p "$dir"
  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
case "$1 $2" in
"job status") printf 'ID    Type     Status\nweb   service  running\n' ;;
"job allocs") printf 'abc12345 web sidecar\ndef67890 solo\n' ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/nomad"
  out="$(PATH="$dir:$PATH" _HI_SSH_CONFIG="$_HI_NO_CONFIG" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" nomad)"
  _hi_has_row "$out" abc12345 nomad || return 1
  _hi_has_row "$out" abc12345/web nomad || return 1
  _hi_has_row "$out" abc12345/sidecar nomad || return 1
  _hi_has_row "$out" def67890 nomad || return 1
  ! printf '%s\n' "$out" | grep -q '^def67890/'
}

# the same for a pod: more than one container is a real choice and gets
# "pod/container" rows, a one-container pod gets none
function test_kube_multi_container_pod_lists_each_container() {
  local dir="$_HI_WORKDIR/shims/kube-containers" out
  mkdir -p "$dir"
  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
case "$1" in
config) printf 'default' ;;
get) printf 'default pod-a app sidecar\ndefault pod-b app\n' ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/kubectl"
  out="$(PATH="$dir:$PATH" _HI_SSH_CONFIG="$_HI_NO_CONFIG" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" kube)"
  _hi_has_row "$out" pod-a kube || return 1
  _hi_has_row "$out" pod-a/app kube || return 1
  _hi_has_row "$out" pod-a/sidecar kube || return 1
  _hi_has_row "$out" pod-b kube || return 1
  ! printf '%s\n' "$out" | grep -q '^pod-b/'
}

# The fan-out itself. Three backends that take 0.3s each: started together the
# log opens with three starts, started in turn it never gets two in a row.
function test_backends_are_swept_together() {
  local out first
  out="$(_hi_targets_slow)" || return 1
  _hi_has_row "$out" slow-docker docker || return 1
  _hi_has_row "$out" slow-podman podman || return 1
  _hi_has_row "$out" slow-pod kube || return 1
  first="$(head -n 3 "$_HI_PROBE_LOG" | grep -c ' start$')"
  [ "$first" = 3 ] && return 0
  _hi_cecho "   the backends ran in turn - the log opens: $(head -n 3 "$_HI_PROBE_LOG" | tr '\n' '/')" "$RED"
  return 1
}

# ...and the documented degradation: no writable scratch dir means no fan-out,
# which is slow and must still be right. TMPDIR under /dev/null can never be
# mkdir'd, so scratch_dir fails the way an unwritable host would.
function test_no_scratch_dir_falls_back_in_turn() {
  local out
  out="$(_hi_targets_slow /dev/null/nope)" || return 1
  _hi_has_row "$out" slow-docker docker || return 1
  _hi_has_row "$out" slow-podman podman || return 1
  _hi_has_row "$out" slow-pod kube || return 1
  # one backend finished before the next started, i.e. really the in-turn arm
  [ "$(sed -n '2p' "$_HI_PROBE_LOG")" = "docker end" ]
}

# ...and nomad's per-job calls fall back the same way: nomad alone would fan
# them out, so with no scratch dir they run in turn and the alloc still lists
function test_nomad_without_scratch_dir_lists_allocs_in_turn() {
  local out
  out="$(TMPDIR=/dev/null/nope _hi_targets "$_HI_NO_CONFIG" nomad)" || return 1
  _hi_has_row "$out" abc12345 nomad
}

function test_no_argument_lists_every_kind() {
  local out kind
  out="$(_hi_targets "$_HI_CONFIG")"
  _hi_has_row "$out" alpha ssh || return 1
  for kind in docker podman nerdctl nomad kube; do
    printf '%s\n' "$out" | grep -q $'\t'"$kind\$" || return 1
  done
}

function test_unknown_kind_is_empty_and_succeeds() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" not-a-backend)" || return 1
  [ -z "$out" ]
}

# 110ms of backend CLIs on every TAB is what this exists to avoid, so what
# matters is that a hit really does skip the backends. Each case gets its own
# XDG_RUNTIME_DIR so it starts from a cold cache and can't see another's.

function _hi_targets_cached() {
  local dir="$1" ttl="$2"
  shift 2
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    XDG_RUNTIME_DIR="$dir" _HI_TARGETS_TTL="$ttl" sh "$_HI_TARGETS" "$@"
}

function test_cache_reuses_the_first_answer() {
  local dir="$_HI_WORKDIR/cache-hit" shim="$_HI_WORKDIR/shims/docker" first second ok=0
  mkdir -p "$dir"
  first="$(_hi_targets_cached "$dir" 60 docker)"
  # take the shim away: a miss now produces nothing, a hit still has the rows,
  # which is the only way to prove the backend really wasn't run again
  mv "$shim" "$shim.aside"
  second="$(_hi_targets_cached "$dir" 60 docker)"
  mv "$shim.aside" "$shim"
  [ -n "$first" ] && [ "$first" = "$second" ] && ok=1
  [ "$ok" -eq 1 ]
}

function test_cache_is_bypassed_at_ttl_zero() {
  local dir="$_HI_WORKDIR/cache-off" out
  mkdir -p "$dir"
  printf '%s\nstale\tdocker\n' "$(date +%s)" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 0 docker)"
  ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

function test_cache_expires_with_its_ttl() {
  local dir="$_HI_WORKDIR/cache-stale" out
  mkdir -p "$dir"
  # stamped an hour ago, so any sane ttl has to treat it as a miss
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 3600))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

# ...whereas one only just past the TTL is the answer *now*, and the sweep
# that replaces it runs behind the TAB: the rows come back stale, the lock the
# refresher holds goes away when its mv lands, and the file then says what
# the shim answers. (An hour-old one, above, is past $stale_for and waits.)
function test_stale_cache_answers_now_and_refreshes_behind() {
  local dir="$_HI_WORKDIR/cache-swr" out
  mkdir -p "$dir"
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 20))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  _hi_has_row "$out" stale docker || return 1
  ! _hi_has_row "$out" alpha docker || return 1
  _hi_poll_bool 300 0.1 [ ! -d "$dir/hi.targets.docker.lock" ] || true
  grep -qxF "alpha"$'\t'"docker" "$dir/hi.targets.docker"
}

# a refresh already running is left to finish: a second stale TAB inside its
# window answers from the copy and starts nothing
function test_stale_cache_refresh_is_not_doubled() {
  local dir="$_HI_WORKDIR/cache-swr-lock" out
  mkdir -p "$dir/hi.targets.docker.lock"
  date +%s >"$dir/hi.targets.docker.lock/at"
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 20))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  _hi_has_row "$out" stale docker || return 1
  sleep 0.3
  [ -d "$dir/hi.targets.docker.lock" ] &&
    grep -qxF "stale"$'\t'"docker" "$dir/hi.targets.docker"
}

# ...but a lock nobody could still be holding - taken longer ago than any
# sweep runs - is a dead refresher's, and is taken over rather than obeyed
function test_stale_cache_dead_lock_is_taken_over() {
  local dir="$_HI_WORKDIR/cache-swr-dead" out
  mkdir -p "$dir/hi.targets.docker.lock"
  printf '%s\n' "$(($(date +%s) - 120))" >"$dir/hi.targets.docker.lock/at"
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 20))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  _hi_has_row "$out" stale docker || return 1
  _hi_poll_bool 300 0.1 [ ! -d "$dir/hi.targets.docker.lock" ] || true
  grep -qxF "alpha"$'\t'"docker" "$dir/hi.targets.docker"
}

# a hand-edited or truncated cache file must be re-derived, not printed
function test_cache_ignores_a_file_with_no_timestamp() {
  local dir="$_HI_WORKDIR/cache-junk" out
  mkdir -p "$dir"
  printf 'not-a-timestamp\nstale\tdocker\n' >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 60 docker)"
  _hi_has_row "$out" alpha docker && ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

# the timestamp is bookkeeping, not a target - it must never reach completion
function test_cache_does_not_leak_its_timestamp() {
  local dir="$_HI_WORKDIR/cache-stamp" out
  mkdir -p "$dir"
  _hi_targets_cached "$dir" 60 docker >/dev/null
  out="$(_hi_targets_cached "$dir" 60 docker)"
  ! printf '%s\n' "$out" | grep -qE '^[0-9]+$'
}

# The hijack defense only runs on the $TMPDIR/hi-<uid> fallback (every case
# above sets XDG_RUNTIME_DIR to a case-owned dir, which skips this whole
# block) - so these clear it and use TMPDIR instead. A directory somebody else
# got to first is never trusted: the sweep runs and nothing is read from or
# written to the hijacked path.
function test_cache_dir_symlink_is_not_trusted() {
  local tmp="$_HI_WORKDIR/symlink-hijack" elsewhere out uid
  mkdir -p "$tmp"
  elsewhere="$_HI_WORKDIR/symlink-hijack-target"
  mkdir -p "$elsewhere"
  uid="$(id -u)"
  ln -s "$elsewhere" "$tmp/hi-$uid"
  out="$(PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    XDG_RUNTIME_DIR='' TMPDIR="$tmp" _HI_TARGETS_TTL=60 sh "$_HI_TARGETS" docker)"
  _hi_has_row "$out" alpha docker || return 1
  [ -z "$(ls -A "$elsewhere" 2>/dev/null)" ]
}

# No root here to actually own a directory as somebody else, so `ls -ld` is
# shimmed to answer the one call this defense makes as though it did - every
# other invocation (there is exactly one real `ls` in targets.sh) falls
# through to the real binary.
function test_cache_dir_wrong_owner_is_not_trusted() {
  local tmp="$_HI_WORKDIR/owner-hijack" bin="$_HI_WORKDIR/owner-hijack-bin" uid out
  mkdir -p "$bin"
  uid="$(id -u)"
  mkdir -m 700 "$tmp"
  mkdir -m 700 "$tmp/hi-$uid"
  cat >"$bin/ls" <<SHIM
#!/bin/sh
if [ "\$*" = "-ldn $tmp/hi-$uid" ]; then
  printf 'drwx------ 2 65534 65534 4096 Jan  1 00:00 %s\n' "$tmp/hi-$uid"
else
  exec $(command -v ls) "\$@"
fi
SHIM
  chmod +x "$bin/ls"
  out="$(PATH="$bin:$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    XDG_RUNTIME_DIR='' TMPDIR="$tmp" _HI_TARGETS_TTL=60 sh "$_HI_TARGETS" docker)"
  _hi_has_row "$out" alpha docker || return 1
  [ ! -e "$tmp/hi-$uid/hi.targets.docker" ]
}

# A cache dir that is ours but refuses the write is not an error either: the
# sweep's rows print, nothing is left behind, and the shell's own "Permission
# denied" stays off stderr - write_cache's 2>/dev/null sits before the `>` it
# has to silence, or every TAB would print it over the prompt.
function test_unwritable_cache_dir_still_answers() {
  local tmp="$_HI_WORKDIR/cache-readonly" err="$_HI_WORKDIR/cache-readonly.err" uid out rc=0
  uid="$(id -u)"
  mkdir -m 700 "$tmp"
  mkdir -m 700 "$tmp/hi-$uid"
  chmod 500 "$tmp/hi-$uid"
  out="$(PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    XDG_RUNTIME_DIR='' TMPDIR="$tmp" _HI_TARGETS_TTL=60 sh "$_HI_TARGETS" docker 2>"$err")" || rc=1
  chmod 700 "$tmp/hi-$uid"
  [ "$rc" = 0 ] || return 1
  _hi_has_row "$out" alpha docker || return 1
  [ -z "$(ls -A "$tmp/hi-$uid")" ] || return 1
  [ ! -s "$err" ] || {
    _hi_cecho "   stderr: $(cat "$err")" "$RED"
    return 1
  }
}

function test_absent_backends_leave_only_ssh_rows() {
  local out
  out="$(PATH="$_HI_TOOLBOX_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" sh "$_HI_TARGETS")" || return 1
  _hi_has_row "$out" alpha ssh || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

# _hi_targets_begin - what every part of this suite starts from, and the tally
function _hi_targets_begin() {
  _hi_workdir targetstest

  _hi_write_configs
  _hi_write_shims
  _hi_write_slow_shims
  _hi_write_toolbox
  _hi_suite_begin
}

function run_targets_tests() {
  _hi_targets_begin

  _hi_h1 "Testing common/targets.sh"

  _hi_h2 "Testing: ssh hosts"
  _hi_check "Multi-alias Host line -> one row per alias" test_multi_alias_host_yields_one_row_each
  _hi_check "Wildcard patterns skipped" test_wildcard_patterns_are_skipped
  _hi_check "Lowercase 'host' keyword matched" test_lowercase_host_keyword_is_matched
  _hi_check "Trailing comment isn't a host" test_trailing_comment_is_not_a_host
  _hi_check "Missing config -> empty, exit 0" test_missing_config_is_empty_and_succeeds
  _hi_check "'ssh' argument excludes other kinds" test_ssh_kind_excludes_container_backends
  _hi_check "A backend switched off is not listed" test_a_backend_switched_off_is_not_listed
  _hi_check "ssh hosts follow Include" test_ssh_hosts_follow_include
  _hi_check "ssh-files lists the config and its Includes, in order" test_ssh_files_lists_the_config_and_its_includes_in_order
  _hi_check "--add-tag completes the literal ssh hosts" test_add_tag_words_are_the_literal_ssh_hosts

  _hi_h2 "Testing: container/orchestrator backends"
  _hi_check "docker -> running containers" test_docker_kind_lists_running_containers
  _hi_check "docker -> compose service alias" test_docker_kind_lists_compose_service_alias
  _hi_check "docker -> no alias row for an empty label" test_docker_kind_omits_alias_row_when_label_is_empty
  _hi_check "podman -> compose service alias" test_podman_kind_lists_compose_service_alias
  _hi_check "nerdctl -> running containers, its own kind" test_nerdctl_kind_lists_running_containers
  _hi_check "an absent family member emits nothing" test_absent_family_member_is_silent
  _hi_check "the family's order is the emission order" test_family_order_is_emission_order
  _hi_check "two CLIs on one daemon -> one row" test_duplicate_daemon_rows_are_emitted_once
  _hi_check "dedupe leaves nomad and kube rows alone" test_dedupe_leaves_nomad_and_kube_alone
  _hi_check "nomad -> running allocs, no header row" test_nomad_kind_lists_running_allocs
  _hi_check "kube -> running pods" test_kube_kind_lists_running_pods
  _hi_check "nomad -> alloc/task rows for a multi-task alloc" test_nomad_multi_task_alloc_lists_each_task
  _hi_check "kube -> pod/container rows for a multi-container pod" test_kube_multi_container_pod_lists_each_container
  _hi_check_capable fork_concurrency "Backends are swept together, not in turn" test_backends_are_swept_together
  _hi_check "No scratch dir -> in turn, same rows" test_no_scratch_dir_falls_back_in_turn
  _hi_check "...nomad's per-job calls too" test_nomad_without_scratch_dir_lists_allocs_in_turn

  _hi_h2 "Testing: argument handling"
  _hi_check "No argument -> every kind" test_no_argument_lists_every_kind
  _hi_check "Unknown argument -> empty, exit 0" test_unknown_kind_is_empty_and_succeeds
  _hi_check "No backends installed -> ssh rows only" test_absent_backends_leave_only_ssh_rows

  _hi_h2 "Testing: the result cache"
  _hi_check "A hit skips the backend entirely" test_cache_reuses_the_first_answer
  _hi_check "TTL 0 bypasses it" test_cache_is_bypassed_at_ttl_zero
  _hi_check "An expired entry is re-derived" test_cache_expires_with_its_ttl
  _hi_check "A stale entry answers now, refreshes behind" test_stale_cache_answers_now_and_refreshes_behind
  _hi_check "A running refresh is not doubled" test_stale_cache_refresh_is_not_doubled
  _hi_check "A dead refresher's lock is taken over" test_stale_cache_dead_lock_is_taken_over
  _hi_check "A file with no timestamp is re-derived" test_cache_ignores_a_file_with_no_timestamp
  _hi_check "The timestamp never reaches completion" test_cache_does_not_leak_its_timestamp
  _hi_check "A symlinked cache dir is swept, not trusted" test_cache_dir_symlink_is_not_trusted
  _hi_check "A wrong-owner cache dir is swept, not trusted" test_cache_dir_wrong_owner_is_not_trusted
  _hi_check_capable lockout "An unwritable cache dir still answers, silently" test_unwritable_cache_dir_still_answers

  _hi_suite_end "targets.sh"
}

# a part (targets_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_TARGETS_PART:-}" ] || run_targets_tests
