#!/usr/bin/env bash
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

  cat >"$dir/podman" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'pod-one\n'
EOF

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

  for tool in docker podman nomad kubectl; do
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
# The wait is 2s, not the 0.3s a real stopwatch-free assertion could get away
# with elsewhere: MSYS's fork+exec is expensive enough on a real Windows
# runner (a 2026-08-28 dispatch measured a fully sequential "docker start,
# docker end, podman start" with the shorter wait) that launching the next
# backend can outlast a short sleep on its own, making even genuine `&`
# fan-out read as in-turn. 2s gives real concurrency room to prove itself
# there without slowing the other platforms enough to notice.
#
# nomad answers a header row and no jobs: it belongs to the roster (four
# backends is what makes emit_targets fan out at all) but has nothing to wait
# for, and its per-job fan-out is a second mechanism this case is not about.
_HI_SLOW_PATH=""
_HI_PROBE_LOG=""
function _hi_write_slow_shims() {
  local dir="$_HI_WORKDIR/slowshims" tool
  mkdir -p "$dir"
  _HI_PROBE_LOG="$_HI_WORKDIR/probe.log"

  for tool in docker podman; do
    cat >"$dir/$tool" <<EOF
#!/bin/sh
[ "\$1" = ps ] || exit 1
printf '$tool start\\n' >>"\$_HI_PROBE_LOG"
sleep 2
printf '$tool end\\n' >>"\$_HI_PROBE_LOG"
printf 'slow-$tool\\n'
EOF
  done

  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
[ "$1" = get ] || exit 1
printf 'kube start\n' >>"$_HI_PROBE_LOG"
sleep 2
printf 'kube end\n' >>"$_HI_PROBE_LOG"
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
    TMPDIR="${1:-${TMPDIR:-/tmp}}" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS"
}

# A PATH with the commands targets.sh runs and nothing else - no docker,
# podman, nomad or kubectl to find.
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
  ! printf '%s\n' "$out" | grep -q 'trailing\|comment,'
}

function test_missing_config_is_empty_and_succeeds() {
  local out
  out="$(_hi_targets "$_HI_NO_CONFIG" ssh)" || return 1
  [ -z "$out" ]
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

# beta's compose label rides in as a third row - the friendlier name a real
# session resolves back to "beta" through hi.sh's _hi_compose_container
function test_docker_kind_lists_compose_service_alias() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  _hi_has_row "$out" compose-svc docker
}

# alpha has no label, so its second field is empty - must not turn into a
# blank completable row
function test_docker_kind_omits_alias_row_when_label_is_empty() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  ! printf '%s\n' "$out" | grep -qxF $'\t''docker'
}

function test_podman_kind_lists_running_containers() {
  _hi_has_row "$(_hi_targets "$_HI_CONFIG" podman)" pod-one podman
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

function test_no_argument_lists_every_kind() {
  local out kind
  out="$(_hi_targets "$_HI_CONFIG")"
  _hi_has_row "$out" alpha ssh || return 1
  for kind in docker podman nomad kube; do
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
  local dir="$_HI_WORKDIR/cache-swr" out i
  mkdir -p "$dir"
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 20))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  _hi_has_row "$out" stale docker || return 1
  ! _hi_has_row "$out" alpha docker || return 1
  for ((i = 0; i < 50; i++)); do
    [ -d "$dir/hi.targets.docker.lock" ] || break
    sleep 0.1
  done
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
  local dir="$_HI_WORKDIR/cache-swr-dead" out i
  mkdir -p "$dir/hi.targets.docker.lock"
  printf '%s\n' "$(($(date +%s) - 120))" >"$dir/hi.targets.docker.lock/at"
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 20))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  _hi_has_row "$out" stale docker || return 1
  for ((i = 0; i < 50; i++)); do
    [ -d "$dir/hi.targets.docker.lock" ] || break
    sleep 0.1
  done
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

function test_absent_backends_leave_only_ssh_rows() {
  local out
  out="$(PATH="$_HI_TOOLBOX_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" sh "$_HI_TARGETS")" || return 1
  _hi_has_row "$out" alpha ssh || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

# common/bash.sh's completion function, the other half of this file's subject:
# the cases above prove targets.sh produces the right rows, these prove
# _hi_complete turns them into the right COMPREPLY. It reads $_HI_TARGETS,
# $COMP_WORDS and $COMP_CWORD, so all three are set here and the shimmed PATH
# gives it the same fixed backend list every other case sees.
# A child bash rather than a source into this one: common/bash.sh is an
# interactive rc, and sourcing it here would drop its aliases (rm -iv, cp -rv)
# and readline binds on every case that runs after. The three toggles switch
# off everything except the completion itself, which sits outside all of them.
# Recent targets first. _HI_RECENT_FILE points targets.sh at a file the case
# wrote - "<epoch>\t<name>" lines - and the stamps are relative to now, so
# the frecency weights are the ones a real file would get.
function _hi_recent_file() {
  local f="$_HI_WORKDIR/recent.$1" now
  shift
  now="$(date +%s)"
  : >"$f"
  # <name>:<seconds ago>, one visit each
  local spec
  for spec in "$@"; do
    printf '%s\t%s\n' "$((now - ${spec#*:}))" "${spec%%:*}" >>"$f"
  done
  printf '%s' "$f"
}
function _hi_targets_ranked() {
  local f="$1"
  shift
  _HI_RECENT_FILE="$f" _hi_targets "$_HI_CONFIG" "$@"
}
# the roster order is alpha, beta, lowercase-keyword... - so beta first is
# only ever the file's doing
function test_recent_target_comes_first() {
  local out
  out="$(_hi_targets_ranked "$(_hi_recent_file one beta:10)" ssh)"
  [ "$(printf '%s\n' "$out" | head -1)" = "beta"$'\t'"ssh" ] &&
    _hi_has_row "$out" alpha ssh
}
# frecency, not recency alone: three visits within the day (2 each) outrank
# one visit a minute ago (4)
function test_recent_ranks_by_frecency() {
  local out
  out="$(_hi_targets_ranked "$(_hi_recent_file freq lowercase-keyword:60 beta:80000 beta:80001 beta:80002)" ssh)"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = "beta"$'\t'"ssh" ] &&
    [ "$(printf '%s\n' "$out" | sed -n 2p)" = "lowercase-keyword"$'\t'"ssh" ] &&
    [ "$(printf '%s\n' "$out" | sed -n 3p)" = "alpha"$'\t'"ssh" ]
}
# the file ranks rows, it never adds one: a name with no row stays absent
function test_recent_never_invents_a_target() {
  local out
  out="$(_hi_targets_ranked "$(_hi_recent_file ghost no-such-host:10)" ssh)"
  ! printf '%s\n' "$out" | grep -q no-such-host &&
    [ "$(printf '%s\n' "$out" | head -1)" = "alpha"$'\t'"ssh" ]
}
function test_recent_is_off_with_the_setting() {
  local out
  out="$(_HI_RECENT=0 _hi_targets_ranked "$(_hi_recent_file off beta:10)" ssh)"
  [ "$(printf '%s\n' "$out" | head -1)" = "alpha"$'\t'"ssh" ]
}
# the order survives the cache: a hit is ranked on the way out, so a session
# between two TABs changes the next one without waiting out the TTL
function test_recent_ranks_a_cache_hit() {
  local dir="$_HI_WORKDIR/cache-recent" f out
  mkdir -p "$dir"
  _hi_targets_cached "$dir" 60 ssh >/dev/null
  f="$(_hi_recent_file hit beta:10)"
  out="$(_HI_RECENT_FILE="$f" _hi_targets_cached "$dir" 60 ssh)"
  [ "$(printf '%s\n' "$out" | head -1)" = "beta"$'\t'"ssh" ]
}
# ...and through the bash completion, which is where "first offered" is seen
function test_complete_offers_the_most_recent_first() {
  local f out
  f="$(_hi_recent_file complete beta:10)"
  out="$(_HI_RECENT_FILE="$f" _hi_completions_for "")"
  [ "$(printf '%s\n' "$out" | head -1)" = beta ]
}

function _hi_completions_for() {
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../common/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "$1")
      COMP_CWORD=1
      COMPREPLY=()
      _hi_complete
      printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}
    ' _ "$1"
}

function test_complete_offers_every_target() {
  local out
  out="$(_hi_completions_for "")"
  printf '%s\n' "$out" | grep -qx alpha &&
    printf '%s\n' "$out" | grep -qx pod-one &&
    printf '%s\n' "$out" | grep -qx abc12345
}

function test_complete_filters_by_the_typed_prefix() {
  local out
  out="$(_hi_completions_for pod-)"
  printf '%s\n' "$out" | grep -qx pod-one || return 1
  ! printf '%s\n' "$out" | grep -qx alpha
}

# targets.sh emits "<name>\t<kind>"; only the name is a completion, or every
# suggestion would arrive with a literal tab and its backend glued on
function test_complete_drops_the_kind_column() {
  ! _hi_completions_for "" | grep -q $'\t'
}

function test_complete_is_empty_for_an_unmatched_prefix() {
  [ -z "$(_hi_completions_for zzz-no-such-target)" ]
}

# The in-shell TTL cache: targets.sh's own file cache already makes a repeat
# TAB cheap, and this makes it free. What is counted is the *fork* - `sh
# $_HI_TARGETS` - because that is the thing being avoided, and counting it
# from outside is the only honest way to see it. paths.sh re-exports
# $_HI_TARGETS over anything the environment says, so the counter is a shim
# `sh` on $PATH rather than a fake script path; it only counts the runs that
# are the target list, and execs the real sh either way.
#
# _hi_complete_forks <ttl> - how many times two back-to-back completions in
# one shell actually run the target list.
function _hi_complete_forks() {
  local dir="$_HI_WORKDIR/shcount" counter="$_HI_WORKDIR/sh.calls"
  mkdir -p "$dir"
  : >"$counter"
  cat >"$dir/sh" <<EOF
#!/bin/sh
case "\$1" in
*targets.sh) echo ran >>"$counter" ;;
esac
exec $(command -v sh) "\$@"
EOF
  chmod +x "$dir/sh"
  PATH="$dir:$_HI_SHIM_PATH" _HI_TARGETS_TTL="$1" \
    _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../common/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "")
      COMP_CWORD=1
      COMPREPLY=()
      _hi_complete
      COMPREPLY=()
      _hi_complete
    ' >/dev/null 2>&1
  grep -c . "$counter" || true
}

# the cached path must still produce completions, not just skip the fork
function test_complete_still_answers_from_the_cache() {
  local out
  out="$(
    PATH="$_HI_SHIM_PATH" _HI_DISABLE_PROMPT=1 \
      bash -c '
        source "$_HI_BASHRC"
        COMP_WORDS=(hi "")
        COMP_CWORD=1
        COMPREPLY=()
        _hi_complete
        COMPREPLY=()
        _hi_complete
        printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}
      '
  )"
  printf '%s\n' "$out" | grep -qx alpha
}

# The drift check the roster exists for. hi.sh's --help heredoc and docs/hi.1
# both spell these out; targets.sh is now a third copy, and the only one a
# completion reads - so a flag that stops agreeing with --help is a flag the
# user is offered and hi then rejects.
function test_flags_all_appear_in_help() {
  local flag help bad=0
  help="$(_HI_HOME="$_HI_HOME" bash "$_HI_ROOT/hi.sh" --help 2>&1)" || true
  while read -r flag; do
    case "$help" in
    *"$flag"*) ;;
    *)
      _hi_cecho "   targets.sh offers $flag, which hi --help does not list" "$RED"
      bad=1
      ;;
    esac
  done < <(sh "$_HI_ROOT/common/targets.sh" flags)
  [ "$bad" = 0 ]
}

# ...and the other direction, which is the one that rots quietly: a flag added
# to hi.sh that nobody can TAB to.
function test_help_flags_all_appear_in_roster() {
  local flag roster bad=0
  roster="$(sh "$_HI_ROOT/common/targets.sh" flags)"
  # the long options out of the two --help blocks, which is every flag hi parses
  # except -h (its --help twin is listed, and a single letter is not worth
  # completing)
  while read -r flag; do
    case $'\n'"$roster"$'\n' in
    *$'\n'"$flag"$'\n'*) ;;
    *)
      _hi_cecho "   hi --help lists $flag, which targets.sh does not offer" "$RED"
      bad=1
      ;;
    esac
  done < <(_HI_HOME="$_HI_HOME" bash "$_HI_ROOT/hi.sh" --help 2>&1 |
    sed -n 's/^ *\(--[a-z-]\{2,\}\).*/\1/p' | sort -u)
  [ "$bad" = 0 ]
}

# Inside a session the local sub-commands need a checkout the payload does not
# carry, so completing one lands on hi.sh's refusal. The roster has to know.
# --doctor is one of them, despite looking portable as a read-only probe:
# scripts/doctor.sh is not in $_HI_PAYLOAD, so `hi --doctor` on a target
# answers $_HI_NO_CHECKOUT like the rest.
function test_flags_drop_local_subcommands_in_a_session() {
  local out flag
  out="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags)"
  for flag in --install --doctor --test --update; do
    case $'\n'"$out"$'\n' in
    *$'\n'"$flag"$'\n'*)
      _hi_cecho "   a session was offered $flag" "$RED"
      return 1
      ;;
    esac
  done
  # ...while the one that does work there is still offered: --packages-preview
  # falls back to the shipped common/header.sh rather than refusing.
  case $'\n'"$out"$'\n' in
  *$'\n--packages-preview\n'*) return 0 ;;
  esac
  _hi_cecho "   a session lost --packages-preview, which works there" "$RED"
  return 1
}

# The case _HI_REMOTE_SESSION cannot see. A package-manager install ships
# scripts/ - so every sub-command above works - but neither tests/ nor .git, so
# --test and --update are exactly the two that must not be offered there. The
# roster is answered out of a staged tree rather than this checkout, because
# this checkout has all three and would pass either way.
function test_flags_drop_what_a_package_lacks() {
  local tree="$_HI_WORKDIR/pkgtree" out flag
  rm -rf "$tree"
  mkdir -p "$tree/common" "$tree/scripts"
  cp "$_HI_ROOT/common/targets.sh" "$_HI_ROOT/common/flags" "$tree/common/"
  out="$(sh "$tree/common/targets.sh" flags)"
  for flag in --test --update; do
    case $'\n'"$out"$'\n' in
    *$'\n'"$flag"$'\n'*)
      _hi_cecho "   a packaged install was offered $flag" "$RED"
      return 1
      ;;
    esac
  done
  case $'\n'"$out"$'\n' in
  *$'\n--doctor\n'*) return 0 ;;
  esac
  _hi_cecho "   a packaged install lost --doctor, which works there" "$RED"
  return 1
}

# The roster's four cases above pin targets.sh; these two pin the half that
# reaches it. _hi_complete branches on the typed word, and a branch nothing
# drives is a branch that can be deleted by accident - the completion would
# still "work" for targets and quietly offer none of hi's own options.
function test_complete_offers_hi_flags_for_a_dash_word() {
  local out
  out="$(_hi_completions_for --)"
  printf '%s\n' "$out" | grep -qx -- --doctor &&
    printf '%s\n' "$out" | grep -qx -- --color-preview
}

# ...and the prefix filter is the completion's own, not targets.sh's: the
# roster is emitted whole and matched here. The target assertion is the one
# that matters - $_HI_SHIM_PATH has a docker answering `alpha`, so a dash word
# that fell through to the target branch would show it.
function test_complete_flags_filter_by_prefix_and_never_reach_targets() {
  local out
  out="$(_hi_completions_for --col)"
  printf '%s\n' "$out" | grep -qx -- --color-preview || return 1
  if printf '%s\n' "$out" | grep -qx -- --configure; then
    _hi_cecho "   --col also offered --configure" "$RED"
    return 1
  fi
  if printf '%s\n' "$out" | grep -qx alpha; then
    _hi_cecho "   a dash word reached the target list" "$RED"
    return 1
  fi
  return 0
}

# `hi --<TAB>` must not wait on a docker daemon or an ssh config. Pinned by
# pointing every backend at a command that would hang if it were ever run.
function test_flags_do_not_probe() {
  local out
  out="$(
    PATH="/nonexistent-hi-test-path:$PATH" \
      _HI_PROBE_TIMEOUT=0 sh "$_HI_ROOT/common/targets.sh" flags
  )"
  case $'\n'"$out"$'\n' in
  *$'\n--doctor\n'*) return 0 ;;
  esac
  _hi_cecho "   flags did not answer with an empty PATH - something probed" "$RED"
  return 1
}

function run_targets_tests() {
  _hi_workdir targetstest

  _hi_h1 "Testing common/targets.sh"

  _hi_write_configs
  _hi_write_shims
  _hi_write_slow_shims
  _hi_write_toolbox

  _hi_suite_begin

  _hi_h2 "Testing: ssh hosts"
  _hi_check "Multi-alias Host line -> one row per alias" test_multi_alias_host_yields_one_row_each
  _hi_check "Wildcard patterns skipped" test_wildcard_patterns_are_skipped
  _hi_check "Lowercase 'host' keyword matched" test_lowercase_host_keyword_is_matched
  _hi_check "Trailing comment isn't a host" test_trailing_comment_is_not_a_host
  _hi_check "Missing config -> empty, exit 0" test_missing_config_is_empty_and_succeeds
  _hi_check "'ssh' argument excludes other kinds" test_ssh_kind_excludes_container_backends

  _hi_h2 "Testing: container/orchestrator backends"
  _hi_check "docker -> running containers" test_docker_kind_lists_running_containers
  _hi_check "docker -> compose service alias" test_docker_kind_lists_compose_service_alias
  _hi_check "docker -> no alias row for an empty label" test_docker_kind_omits_alias_row_when_label_is_empty
  _hi_check "podman -> running containers" test_podman_kind_lists_running_containers
  _hi_check "nomad -> running allocs, no header row" test_nomad_kind_lists_running_allocs
  _hi_check "kube -> running pods" test_kube_kind_lists_running_pods
  _hi_check "Backends are swept together, not in turn" test_backends_are_swept_together
  _hi_check "No scratch dir -> in turn, same rows" test_no_scratch_dir_falls_back_in_turn

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

  _hi_h2 "Testing: common/bash.sh's _hi_complete"
  _hi_check "Offers every target" test_complete_offers_every_target
  _hi_check "Filters by the typed prefix" test_complete_filters_by_the_typed_prefix
  _hi_check "Drops the kind column" test_complete_drops_the_kind_column
  _hi_check "Empty for an unmatched prefix" test_complete_is_empty_for_an_unmatched_prefix
  _hi_check_eq "A repeat TAB inside the TTL forks nothing" 1 _hi_complete_forks 5
  # ...and TTL 0 means no cache at all - the same thing it means to targets.sh
  _hi_check_eq "TTL 0 refetches every time" 2 _hi_complete_forks 0
  _hi_check "The cached answer is still an answer" test_complete_still_answers_from_the_cache

  _hi_h2 "Testing: recent targets first"
  _hi_check "A recent target leads" test_recent_target_comes_first
  _hi_check "Ranked by frecency, not recency alone" test_recent_ranks_by_frecency
  _hi_check "Never invents a target" test_recent_never_invents_a_target
  _hi_check "_HI_RECENT=0 keeps the roster order" test_recent_is_off_with_the_setting
  _hi_check "A cache hit is ranked too" test_recent_ranks_a_cache_hit
  _hi_check "The completion offers it first" test_complete_offers_the_most_recent_first
  _hi_check "flags: every one is in hi --help" test_flags_all_appear_in_help
  _hi_check "flags: every --help flag is in the roster" test_help_flags_all_appear_in_roster
  _hi_check "flags: a session is offered only what works there" test_flags_drop_local_subcommands_in_a_session
  _hi_check "flags: a package is offered only what works there" test_flags_drop_what_a_package_lacks
  _hi_check "flags: answered without probing a backend" test_flags_do_not_probe
  _hi_check "flags: a dash word completes hi's options" test_complete_offers_hi_flags_for_a_dash_word
  _hi_check "flags: filtered by prefix, never a target" test_complete_flags_filter_by_prefix_and_never_reach_targets

  _hi_suite_end "targets.sh"
}

run_targets_tests
