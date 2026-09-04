#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each; the
# bash, zsh and fish completions all read it. Standalone POSIX - fish shells
# out to it, and it runs on whatever /bin/sh a target has.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube|flags]
#        (no argument = every backend; `flags` = hi's own options instead)
# GLOSSARY: HI.26 - _HI_PROBE_TIMEOUT and _HI_TARGETS_TTL
#
# The backends are probed together, each capped at $_HI_PROBE_TIMEOUT, so N
# wedged daemons cost the longest ceiling rather than the sum (the trade
# header.sh's _hi_probe_start makes for the banner). Emission order stays the
# roster's; a host with no writable scratch directory gets the in-turn sweep.
# shellcheck disable=SC2329 # every function here is reached indirectly - by
# the completion hook that sources this file, through run_lister's dispatch, or
# as a background job - so "never invoked" is true of the file, not of five
# lines in it.

kind="${1:-all}"

# hi's own flags, so `hi --<TAB>` completes them like a target. Here rather
# than per shell because this is the one file all three completions read and
# the only one fish can run. Answered before the cache and the probes: a flag
# list must never wait on a docker daemon. targets_test.sh drift-checks it
# against hi.sh's --help.
if [ "$kind" = flags ]; then
  # Out of common/flags, the table hi.sh dispatches from. <needs> is what a
  # flag wants that is not always on disk: `-` is offered everywhere; the rest
  # are withheld in a session and then checked against the tree (a package
  # install ships scripts/ but neither tests/ nor .git). Derived from $0, since
  # a completion can reach this file without paths.sh (GLOSSARY: HI.33).
  case $0 in
  */*) hi_tree="${0%/*}/.." ;;
  *) hi_tree=".." ;;
  esac
  while IFS='|' read -r flag needs _rest; do
    case "$flag" in '#'* | '') continue ;; esac
    [ "$needs" = - ] || [ "${_HI_REMOTE_SESSION:-0}" != 1 ] || continue
    case "$needs" in
    scripts) [ -d "$hi_tree/scripts" ] || continue ;;
    tests) [ -f "$hi_tree/tests/test_runner.sh" ] || continue ;;
    git) [ -d "$hi_tree/.git" ] || continue ;;
    esac
    printf '%s\n' "$flag"
  done <"$hi_tree/common/flags"
  exit 0
fi

ttl="${_HI_TARGETS_TTL:-5}"
now="$(date +%s 2>/dev/null || echo 0)"

# `timeout` is GNU/busybox, absent on stock macOS - optional. `-k 0.2`: the
# cap is a SIGTERM, which rootless podman defers while its runtime initialises
# (longer than the cap on a fresh $HOME); the KILL 200ms later is what makes
# $_HI_PROBE_TIMEOUT a bound. core.sh's _hi_probe carries the same one.
if command -v timeout >/dev/null 2>&1; then
  run_backend() { timeout -k 0.2 "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  run_backend() { "$@"; }
fi

# Everything below the first line of $1, fork-free: faster than a `tail` exec
# at this size, and works on a PATH with no coreutils.
cache_body() {
  {
    IFS= read -r _hi_line # the stamp
    while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do printf '%s\n' "$_hi_line"; done
  } <"$1"
}

# The roster, "<label>:<bin>", in the order the rows are emitted.
backends='docker:docker podman:podman nomad:nomad kube:kubectl'

# Private per-run scratch for a fan-out's output, made at most once and only
# on a path that fans out (a host with no backends never reaches for `mkdir`).
# `mkdir -m 700` and no `-p`: -p succeeds on a path somebody else got to first,
# which would then be adopted and `rm -rf`'d on the way out.
scratch=""
scratch_dir() {
  [ -n "$scratch" ] && return 0
  _hi_scratch="${TMPDIR:-/tmp}/hi-probe.$$"
  mkdir -m 700 "$_hi_scratch" 2>/dev/null || return 1
  scratch="$_hi_scratch"
}

# backend_wanted <label> <bin> - does the kind gate pass, and is the CLI here?
# Both halves are builtins, so the roster is sized before anything forks.
backend_wanted() {
  { [ "$kind" = "$1" ] || [ "$kind" = all ]; } || return 1
  command -v "$2" >/dev/null 2>&1
}

# run_lister <label> - that backend's rows on stdout, in turn or backgrounded.
run_lister() {
  case "$1" in
  docker | podman) list_ps "$1" ;;
  nomad) list_nomad ;;
  kube) list_kube ;;
  esac
}

emit_targets() {
  # ssh first and in line: a local file read and one awk, faster than the
  # bookkeeping of backgrounding it
  if [ "$kind" = ssh ] || [ "$kind" = all ]; then
    _hi_ssh_config="${_HI_SSH_CONFIG:-$HOME/.ssh/config}"
    [ -f "$_hi_ssh_config" ] &&
      awk 'tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?]/) printf "%s\tssh\n", $i
        }
      }' "$_hi_ssh_config"
  fi

  wanted="" n_wanted=0
  for spec in $backends; do
    backend_wanted "${spec%%:*}" "${spec#*:}" || continue
    wanted="${wanted}${wanted:+ }${spec%%:*}"
    n_wanted=$((n_wanted + 1))
  done
  [ "$n_wanted" -gt 0 ] || return 0

  # worth its two forks only where something fans out: two or more backends,
  # or nomad/kube alone, whose own calls fan out inside the lane
  if [ "$n_wanted" -ge 2 ] || [ "$wanted" = nomad ] || [ "$wanted" = kube ]; then
    scratch_dir
  fi

  if [ "$n_wanted" -ge 2 ] && [ -n "$scratch" ]; then
    files=""
    for label in $wanted; do
      run_lister "$label" >"$scratch/$label" 2>/dev/null &
      files="$files $scratch/$label"
    done
    wait
    # shellcheck disable=SC2086 # deliberate split: the roster-ordered file list
    cat $files 2>/dev/null
  else
    for label in $wanted; do run_lister "$label"; done
  fi

  [ -n "$scratch" ] && rm -rf "$scratch" 2>/dev/null
  return 0
}

# The listers, each reached through run_lister's dispatch.

# docker and podman are one call (drop-in CLIs); the tag is appended by the
# read loop, not a `sed`, on this every-TAB path. Docker also carries the
# compose service label on the same call: a target one word shorter than the
# container name, resolved back by hi.sh's _hi_compose_container.
list_ps() {
  if [ "$1" = docker ]; then
    run_backend docker ps --format '{{.Names}} {{.Label "com.docker.compose.service"}}' 2>/dev/null |
      while read -r _hi_name _hi_svc || [ -n "$_hi_name" ]; do
        [ -n "$_hi_name" ] || continue
        printf '%s\tdocker\n' "$_hi_name"
        # only when it differs, or a container_name equal to the service name
        # would complete twice
        [ -n "$_hi_svc" ] && [ "$_hi_svc" != "$_hi_name" ] && printf '%s\tdocker\n' "$_hi_svc"
      done
  else
    run_backend "$1" ps --format '{{.Names}}' 2>/dev/null |
      while IFS= read -r _hi_name || [ -n "$_hi_name" ]; do
        [ -n "$_hi_name" ] || continue
        printf '%s\t%s\n' "$_hi_name" "$1"
      done
  fi
}

# nomad_allocs <job> - the running allocations of one job plus their task
# names, one call per job.
nomad_allocs() {
  # shellcheck disable=SC2016 # $t/$s are nomad's Go template, not the shell's
  run_backend nomad job allocs -t \
    '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{range $t, $s := .TaskStates}}{{" "}}{{$t}}{{end}}{{"\n"}}{{end}}{{end}}' \
    "$1" 2>/dev/null
}

# The allocation, plus "alloc/task" per task when the group has more than one
# (list_kube's shape, and the syntax hi takes). The per-job calls go out
# together where there is a scratch dir: run in turn, N wedged jobs cost N
# ceilings with nothing bounding the total.
list_nomad() {
  _hi_jobs="$(run_backend nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }')"
  [ -n "$_hi_jobs" ] || return 0
  if [ -n "$scratch" ]; then
    _hi_j=0
    for _hi_job in $_hi_jobs; do
      _hi_j=$((_hi_j + 1))
      nomad_allocs "$_hi_job" >"$scratch/nomad.$_hi_j" 2>/dev/null &
    done
    wait
    # the glob cannot catch the "nomad" the backend fan-out writes: no dot
    cat "$scratch"/nomad.* 2>/dev/null
  else
    for _hi_job in $_hi_jobs; do nomad_allocs "$_hi_job"; done
  fi | while read -r alloc t1 t2 rest; do
    [ -n "$alloc" ] || continue
    printf '%s\tnomad\n' "$alloc"
    if [ -n "$t2" ]; then
      for t in $t1 $t2 $rest; do printf '%s/%s\tnomad\n' "$alloc" "$t"; done
    fi
  done
}

# The pod, plus a "pod/container" line per container when it has more than one
# (the syntax hi takes for picking one). One jsonpath over every namespace: a
# pod in the current namespace is emitted bare, any other as `namespace:pod`
# (hi.sh's _hi_kube_split). The namespace comes from the kubeconfig (empty
# means `default`); still a large exec, so with a scratch dir it runs beside
# the pod listing rather than ahead of it - this lane is the longest one.
kube_ns() { run_backend kubectl config view --minify -o jsonpath='{..namespace}'; }

list_kube() {
  if [ -n "$scratch" ]; then
    kube_ns >"$scratch/kube.ns" 2>/dev/null &
    kube_pods >"$scratch/kube.pods" 2>/dev/null
    wait
    IFS= read -r _hi_ns <"$scratch/kube.ns" 2>/dev/null || _hi_ns=""
    [ -n "$_hi_ns" ] || _hi_ns=default
    kube_rows <"$scratch/kube.pods"
  else
    _hi_ns="$(kube_ns 2>/dev/null)"
    [ -n "$_hi_ns" ] || _hi_ns=default
    kube_pods 2>/dev/null | kube_rows
  fi
}

kube_pods() {
  run_backend kubectl get pods -A --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{range .spec.containers[*]}{" "}{.name}{end}{"\n"}{end}'
}

# stdin is kube_pods' output; $_hi_ns decides which pods are emitted bare
kube_rows() {
  while read -r ns pod c1 c2 rest; do
    [ -n "$pod" ] || continue
    [ "$ns" = "$_hi_ns" ] || pod="$ns:$pod"
    printf '%s\tkube\n' "$pod"
    # c2 non-empty means more than one container, so the choice is real
    if [ -n "$c2" ]; then
      for c in $c1 $c2 $rest; do printf '%s/%s\tkube\n' "$pod" "$c"; done
    fi
  done
}

# Recent targets first. hi.sh appends "<epoch>\t<target>" to the recent file
# after every clean session (client-side only); this ranks the rows it names
# ahead of the rest by zoxide's frecency (4 within the hour, 2 within the day,
# 0.5 within the week, 0.25 after). The file ranks, it never adds. Applied on
# the way out, not before the cache, so a session reorders the next TAB
# without waiting out the TTL. _HI_RECENT=0 turns it off; _HI_RECENT_FILE
# points the file elsewhere (the suite does).
rank_recent() {
  _hi_recent="${_HI_RECENT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/say-hi/recent}"
  # pass-through without an exec: no recent file (or no coreutils, which the
  # suite's toolbox is) must cost nothing here
  if [ "${_HI_RECENT:-1}" = 0 ] || [ ! -r "$_hi_recent" ]; then
    while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do printf '%s\n' "$_hi_line"; done
    return 0
  fi
  awk -F '\t' -v now="$now" '
    FNR == NR {
      if ($2 == "") next
      age = now - $1
      if (age < 0) age = 0
      w = age < 3600 ? 4 : age < 86400 ? 2 : age < 604800 ? 0.5 : 0.25
      score[$2] += w
      next
    }
    { n++; row[n] = $0; name[n] = $1 }
    END {
      # scored rows highest first: a selection pass per row, nothing at this size
      for (;;) {
        best = 0
        for (i = 1; i <= n; i++)
          if (!(done[i]) && (name[i] in score) && (best == 0 || score[name[i]] > score[name[best]])) best = i
        if (best == 0) break
        done[best] = 1
        print row[best]
      }
      for (i = 1; i <= n; i++) if (!(done[i])) print row[i]
    }' "$_hi_recent" -
}

# No cache wanted: just answer, before the two forks below.
if [ "$ttl" -le 0 ]; then
  emit_targets | rank_recent
  exit 0
fi

# $XDG_RUNTIME_DIR is per-user and 0700 where it exists; the fallback makes a
# private directory of its own, not a predictable name in a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  # one `id -u`, not two: the name needs it and so does the ownership check
  _hi_uid="$(id -u 2>/dev/null || echo unknown)"
  cache_dir="${TMPDIR:-/tmp}/hi-$_hi_uid"
  # first TAB only; -m 700 on the create so it is never briefly world-readable,
  # and no -p, which would silently adopt a path somebody else made
  [ -d "$cache_dir" ] || mkdir -m 700 "$cache_dir" 2>/dev/null
  # The name is predictable (the next TAB has to find it), so on a shared /tmp
  # another user can get there first - and would then be choosing what
  # `hi <TAB>` offers. A directory that is not ours is not made ours: the cache
  # is skipped and the backends swept instead, slower and correct.
  #
  # Ownership through `ls -ld`, not `test -O`: -O is a bash/ksh/zsh extension
  # (SC3067). The owner column is compared against both the name and the uid,
  # since a host with no passwd entry for the caller prints a number there.
  # Spelled as a flag rather than one `[ ] || [ ] && [ ]` chain, so the
  # grouping is visible.
  _hi_cache_ok=1
  [ -d "$cache_dir" ] || _hi_cache_ok=0
  if [ -L "$cache_dir" ]; then _hi_cache_ok=0; fi
  # shellcheck disable=SC2012 # `find -maxdepth` is not POSIX and `find -user`
  # takes a user *name*, which is exactly what a host with no passwd entry for
  # the caller cannot supply - the case the uid arm below exists for. SC2012's
  # hazard is parsing file *names* out of ls; this reads a fixed column off one
  # path this script built itself.
  _hi_owner="$(ls -ld "$cache_dir" 2>/dev/null | awk 'NR == 1 { print $3 }')"
  if [ -z "$_hi_owner" ]; then
    _hi_cache_ok=0
  elif [ "$_hi_owner" != "$(id -un 2>/dev/null || echo)" ] &&
    [ "$_hi_owner" != "$_hi_uid" ]; then
    _hi_cache_ok=0
  fi
  if [ "$_hi_cache_ok" = 0 ]; then
    emit_targets | rank_recent
    exit 0
  fi
fi
cache="$cache_dir/hi.targets.$kind"

# Written whole (temp-file-and-mv, so a mid-refresh reader sees old or new,
# never half) and stamped with the run's *start* time, so a row is never read
# as younger than it is. A cache that can't be written is not an error.
write_cache() {
  _hi_tmp="$cache.$$"
  # stderr first: a 2>/dev/null after the redirection that fails comes too
  # late to catch the shell's own message
  # shellcheck disable=SC2086 # ${1:+"$1"} - vanishes when empty, one word when not
  if printf '%s\n' "$now" ${1:+"$1"} 2>/dev/null >"$_hi_tmp"; then
    mv "$_hi_tmp" "$cache" 2>/dev/null || rm -f "$_hi_tmp" 2>/dev/null
  else
    rm -f "$_hi_tmp" 2>/dev/null
  fi
}

# The timestamp is the cache's first line, not the mtime (every portable way
# to read an mtime in seconds is a GNU extension).
#
# Three ages. Inside the TTL the copy is the answer. Past it but within
# $stale_for, the copy is still the answer, printed now while a refresh runs
# behind the TAB - a TAB that waits on a daemon is the one cost a user feels.
# Past $stale_for the shell has been idle long enough that the world has
# probably moved, and the sweep is waited on like a first TAB. TTL 0 skips
# the file entirely (above).
stale_for=600
age=""
if [ -f "$cache" ] && [ -r "$cache" ]; then
  # `read < file`, not $(head -n1): on the cache-hit path that subshell+exec
  # was most of the cost
  IFS= read -r stamp <"$cache" 2>/dev/null || stamp=""
  case "$stamp" in
  '' | *[!0-9]*) ;; # not a timestamp - treat as a miss and rewrite it
  *)
    if [ "$now" -ge "$stamp" ]; then
      age=$((now - stamp))
      if [ "$age" -lt "$ttl" ]; then
        cache_body "$cache" | rank_recent
        exit 0
      fi
    fi
    ;;
  esac
fi

if [ -n "$age" ] && [ "$age" -lt "$stale_for" ]; then
  cache_body "$cache" | rank_recent
  # One refresh at a time, or every TAB in the window a sweep takes would
  # start another. The lock is a directory (made or not in one call) holding
  # the time it was taken; one older than any sweep runs (a flat 30s) was left
  # by a refresher that died, and is taken over.
  lock="$cache.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    IFS= read -r _hi_at <"$lock/at" 2>/dev/null || _hi_at=0
    case "$_hi_at" in '' | *[!0-9]*) _hi_at=0 ;; esac
    [ "$((now - _hi_at))" -gt 30 ] || exit 0
    rm -rf "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || exit 0
  fi
  printf '%s\n' "$now" >"$lock/at" 2>/dev/null
  # Every descriptor to /dev/null: the shell reads this script through a
  # command substitution, which returns only when the *last* writer to its
  # pipe is gone - a refresher holding stdout would be the wait this branch
  # exists to avoid.
  (
    trap 'rm -rf "$lock"' EXIT
    trap 'exit 1' HUP INT TERM
    write_cache "$(emit_targets)"
  ) </dev/null >/dev/null 2>&1 &
  exit 0
fi

out="$(emit_targets)"
write_cache "$out"
[ -n "$out" ] && printf '%s\n' "$out" | rank_recent
exit 0
