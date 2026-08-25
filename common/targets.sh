#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this for
# connection, autocomplete, and autosuggest.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube|flags]
#        (no argument = every backend; `flags` = hi's own options instead)
# GLOSSARY: HI.26 - _HI_PROBE_TIMEOUT and _HI_TARGETS_TTL
#
# The backends are probed *together*, not in turn. Each is capped at
# $_HI_PROBE_TIMEOUT on its own, so one after another two wedged daemons cost
# the sum of the ceilings and four cost 8s of a single TAB; started together
# they cost the longest. That is the trade common/header.sh's _hi_probe_start
# already makes for the banner, in the one dialect this file is allowed.
# Emission order stays the roster's - the rows are read back per backend, never
# in the order the daemons answered - and a host with no writable scratch
# directory simply gets the old in-turn sweep, which is slow, not wrong.
# shellcheck disable=SC2329 # every function here is reached indirectly - by
# the completion hook that sources this file, through run_lister's dispatch, or
# as a background job - so "never invoked" is true of the file, not of five
# lines in it.

kind="${1:-all}"

# hi's own flags, so `hi --<TAB>` completes them the way a target does. They
# live here rather than in each shell because this file is already the one thing
# all three completions read, and the only one fish can run - a roster in
# core.sh would be unreachable from `complete -c hi`.
#
# Answered before anything else below: a flag list must never wait on a docker
# daemon or an ssh config, and this exits before the cache and the probes.
#
# tests/common/targets_test.sh drift-checks both halves against hi.sh's --help,
# so a flag added there and forgotten here fails the fast suite.
if [ "$kind" = flags ]; then
  # Out of common/flags, the same table hi.sh dispatches and prints --help
  # from. A row's <needs> column says what it wants that is not always on
  # disk: `-` is offered everywhere (--help and --version are hi.sh's own,
  # --packages-preview falls back to the shipped common/header.sh), and the
  # rest are withheld in a session - completing one there lands on hi.sh's
  # $_HI_NO_CHECKOUT refusal - and then checked against the tree, since a
  # package-manager install ships scripts/ but neither tests/ nor .git.
  # Derived from $0 rather than $_HI_ROOT, since a completion can reach this
  # file from a shell that never sourced paths.sh (GLOSSARY: HI.33).
  case $0 in
  */*) hi_tree="${0%/*}/.." ;;
  *) hi_tree=".." ;;
  esac
  while IFS='|' read -r flag needs _rest; do
    case "$flag" in '#'* | '') continue ;; esac
    case "$needs" in
    -) ;;
    *)
      [ "${_HI_REMOTE_SESSION:-0}" != 1 ] || continue
      case "$needs" in
      scripts) [ -d "$hi_tree/scripts" ] || continue ;;
      tests) [ -f "$hi_tree/tests/test_runner.sh" ] || continue ;;
      git) [ -d "$hi_tree/.git" ] || continue ;;
      esac
      ;;
    esac
    printf '%s\n' "$flag"
  done <"$hi_tree/common/flags"
  exit 0
fi

ttl="${_HI_TARGETS_TTL:-5}"

# `timeout` is GNU (busybox has it too), absent on stock macOS - optional.
# Called via list_*. `-k 0.2`: the cap is a SIGTERM, and a CLI is free to
# finish what it was doing before honouring one - rootless podman defers it
# for as long as its runtime is still initialising, which on a fresh $HOME is
# a storage setup that can outlast the cap itself. The KILL 200ms later is
# what makes $_HI_PROBE_TIMEOUT a bound rather than a request; core.sh's
# _hi_probe carries the same one.
if command -v timeout >/dev/null 2>&1; then
  run_backend() { timeout -k 0.2 "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  run_backend() { "$@"; }
fi

# Everything below the first line of $1, fork-free: faster than a `tail` exec
# at this size, and the cache keeps working on a PATH with no coreutils.
cache_body() {
  _hi_first=1
  while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do
    if [ "$_hi_first" = 1 ]; then
      _hi_first=0
      continue
    fi
    printf '%s\n' "$_hi_line"
  done <"$1"
}

# The roster, "<label>:<bin>", in the order the rows are emitted.
backends='docker:docker podman:podman nomad:nomad kube:kubectl'

# Somewhere private to collect a fan-out's output, made at most once per run
# and only on a path that has a fan-out to collect - so a host with no backends
# at all (and the suite's toolbox PATH, which carries sh, awk and sed and
# nothing else) never reaches for `mkdir`. Not $XDG_RUNTIME_DIR: this is
# per-run scratch rather than a cache, and it is removed on the way out.
#
# `mkdir -m 700`, and deliberately no `-p`: with -p the call *succeeds* on a
# path that already exists, so a name somebody else got to first would be
# adopted here and then removed by emit_targets' `rm -rf` on the way out. The
# mode rides the same call rather than a chmod after it, which left a window
# where the directory existed on the default umask.
scratch=""
scratch_dir() {
  [ -n "$scratch" ] && return 0
  _hi_scratch="${TMPDIR:-/tmp}/hi-probe.$$"
  mkdir -m 700 "$_hi_scratch" 2>/dev/null || return 1
  scratch="$_hi_scratch"
}

# backend_wanted <label> <bin> - does the kind gate pass, and is the CLI here?
# Both halves are builtins, so the whole roster is sized before anything forks.
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
  # ssh first and in line: a local file read and one awk, already faster than
  # the bookkeeping backgrounding it would cost.
  if [ "$kind" = ssh ] || [ "$kind" = all ]; then
    [ -f "${_HI_SSH_CONFIG:-$HOME/.ssh/config}" ] &&
      awk 'tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?]/) printf "%s\tssh\n", $i
        }
      }' "${_HI_SSH_CONFIG:-$HOME/.ssh/config}"
  fi

  wanted="" n_wanted=0
  for spec in $backends; do
    backend_wanted "${spec%%:*}" "${spec#*:}" || continue
    wanted="${wanted}${wanted:+ }${spec%%:*}"
    n_wanted=$((n_wanted + 1))
  done
  [ "$n_wanted" -gt 0 ] || return 0

  # worth its two forks only where something actually fans out: two or more
  # backends, or nomad and kube alone, whose own calls fan out inside the lane
  if [ "$n_wanted" -ge 2 ] || [ "$wanted" = nomad ] || [ "$wanted" = kube ]; then
    scratch_dir || :
  fi

  if [ "$n_wanted" -ge 2 ] && [ -n "$scratch" ]; then
    for label in $wanted; do
      run_lister "$label" >"$scratch/$label" 2>/dev/null &
    done
    wait
    files=""
    for label in $wanted; do files="$files $scratch/$label"; done
    # shellcheck disable=SC2086 # deliberate split: the roster-ordered file list
    cat $files 2>/dev/null
  else
    for label in $wanted; do run_lister "$label"; done
  fi

  [ -n "$scratch" ] && rm -rf "$scratch" 2>/dev/null
  scratch=""
  return 0
}

# The listers, each reached indirectly through run_lister's dispatch.

# docker and podman are one call (drop-in CLIs); the tag is appended by the
# read loop rather than by a `sed` over the result - one fewer exec per backend
# on the path that runs on every TAB, for the reason cache_body gives. Docker
# also carries the compose service label piggybacked on the same call rather
# than a second `docker ps`: a target one word shorter than the generated
# container name, resolved back to it by hi.sh's own predicate and exec
# commands (_hi_compose_container) rather than by anything here.
list_ps() {
  if [ "$1" = docker ]; then
    run_backend docker ps --format '{{.Names}} {{.Label "com.docker.compose.service"}}' 2>/dev/null |
      while read -r _hi_name _hi_svc || [ -n "$_hi_name" ]; do
        [ -n "$_hi_name" ] || continue
        printf '%s\tdocker\n' "$_hi_name"
        # only when it differs - a custom container_name equal to the
        # service name would otherwise complete twice for one container
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

# nomad_allocs <job> - the running allocations of one job, and the task names
# riding the same template as the ID, so this stays one call per job.
nomad_allocs() {
  # shellcheck disable=SC2016 # $t/$s are nomad's Go template, not the shell's
  run_backend nomad job allocs -t \
    '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{range $t, $s := .TaskStates}}{{" "}}{{$t}}{{end}}{{"\n"}}{{end}}{{end}}' \
    "$1" 2>/dev/null
}

# The allocation, plus "alloc/task" per task when the group has more than one -
# the same shape list_kube emits, and the same syntax hi takes.
#
# The per-job calls go out together where there is a scratch dir to collect
# them: each carries its own $_HI_PROBE_TIMEOUT, so run in turn N wedged jobs
# cost N ceilings and nothing bounds the total. This is the file's one fan-out
# sized by the host rather than by the roster.
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

# The pod, and - when it has more than one container - a "pod/container" line
# per container as well, which is the syntax hi takes for picking one. A
# single-container pod emits only its own name: the suffix would be noise on a
# target where there is nothing to choose.
#
# One jsonpath, not one call per pod: this runs on every TAB.
#
# Every namespace, one call: a pod in the current namespace is emitted bare,
# any other as `namespace:pod` - the spelling hi.sh's _hi_kube_split takes.
# The current namespace is read out of the kubeconfig (a local file, no
# round trip); empty means `default`, as kubectl itself reads it. Still an
# exec of a large binary, so where there is a scratch dir it runs *beside*
# the pod listing rather than ahead of it: this lane is the longest one on a
# host whose daemons all answer, and two kubectl round trips in a row was
# most of it.
list_kube() {
  if [ -n "$scratch" ]; then
    run_backend kubectl config view --minify -o jsonpath='{..namespace}' >"$scratch/kube.ns" 2>/dev/null &
    kube_pods >"$scratch/kube.pods" 2>/dev/null
    wait
    IFS= read -r _hi_ns <"$scratch/kube.ns" 2>/dev/null || _hi_ns=""
    [ -n "$_hi_ns" ] || _hi_ns=default
    kube_rows <"$scratch/kube.pods"
  else
    _hi_ns="$(run_backend kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)"
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
# after every session that ended cleanly (client-side only - a target never
# sees it); this reads it back and puts the rows it names ahead of the rest,
# best first, where a row's score is zoxide's frecency: each visit weighs 4
# within the hour, 2 within the day, 0.5 within the week, 0.25 after. Rows
# the file does not name keep the roster's order behind them, and a name in
# the file that is not a row is not invented - the file ranks, it never adds.
#
# Applied on the way out rather than before the cache, so a session changes
# the order at the next TAB without waiting out the cache's TTL. One awk,
# only when the file exists: a machine that has never connected pays nothing.
# _HI_RECENT=0 turns it off; the file itself can be pointed elsewhere with
# _HI_RECENT_FILE (the suite does).
rank_recent() {
  _hi_recent="${_HI_RECENT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/say-hi/recent}"
  # pass-through without an exec: a host with no recent file (or a PATH with
  # no coreutils, which the suite's toolbox is) must cost nothing here
  if [ "${_HI_RECENT:-1}" = 0 ] || [ ! -r "$_hi_recent" ]; then
    while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do printf '%s\n' "$_hi_line"; done
    return 0
  fi
  awk -F '\t' -v now="$(date +%s 2>/dev/null || echo 0)" '
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
      # the scored rows, highest first: a selection pass per emitted row,
      # which is nothing at the size a target list is
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

# No cache wanted (or no writable place to put one): just answer. Reached
# before the two forks below, so a TTL of 0 pays for neither.
if [ "$ttl" -le 0 ]; then
  emit_targets | rank_recent
  exit 0
fi

# $XDG_RUNTIME_DIR is per-user and 0700 where it exists; the fallback makes a
# private directory of its own, not a predictable name in a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  cache_dir="${TMPDIR:-/tmp}/hi-$(id -u 2>/dev/null || echo unknown)"
  # first TAB only: otherwise two execs per completion on any host without
  # $XDG_RUNTIME_DIR (macOS, most containers)
  # -m 700 on the create, so a fresh cache is never even briefly world-readable
  # - and no -p, which would silently adopt a path somebody else made. The
  # chmod is the other arm rather than a follow-on: it runs only when the mkdir
  # declined, which past the `-d` test above means losing a race with another
  # shell, and this directory is *meant* to outlive the run.
  [ -d "$cache_dir" ] || {
    mkdir -m 700 "$cache_dir" 2>/dev/null || chmod 700 "$cache_dir" 2>/dev/null
  }
fi
cache="$cache_dir/hi.targets.$kind"
now="$(date +%s 2>/dev/null || echo 0)"

# The cache is written whole - temp-file-and-mv, so a mid-refresh reader sees
# old or new, never half - and stamped with the run's *start* time, so a row
# is never read as younger than it is. A cache that can't be written is not
# an error - answer anyway.
write_cache() {
  _hi_tmp="$cache.$$"
  if {
    printf '%s\n' "$now"
    [ -n "$1" ] && printf '%s\n' "$1"
    true
  } >"$_hi_tmp" 2>/dev/null; then
    mv "$_hi_tmp" "$cache" 2>/dev/null || rm -f "$_hi_tmp" 2>/dev/null
  else
    rm -f "$_hi_tmp" 2>/dev/null
  fi
}

# The timestamp is the cache's first line, not the mtime: every portable way to
# read an mtime in seconds is a GNU `find`/`stat` extension.
#
# Three ages, not two. Inside the TTL the copy is the answer. Past it but
# within $stale_for, the copy is *still* the answer - printed now, while the
# sweep that replaces it runs behind the TAB - because a TAB that waits on a
# daemon is the one cost here a user feels, and a list a few minutes old is
# what completion offered a moment ago anyway. Past $stale_for the shell has
# been idle long enough that the world has probably moved, and the sweep is
# waited on the way a first TAB is: better one pause than a page of names
# that no longer exist and none of the ones that do. TTL 0 skips the file
# entirely (above), so it turns this off too.
stale_for=600
age=""
if [ -f "$cache" ] && [ -r "$cache" ]; then
  # `read < file`, not $(head -n1): on the cache-*hit* path the subshell+exec
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
  # One refresh at a time: every TAB in the window a sweep takes would
  # otherwise start another. The lock is a directory - made or not in one
  # call - holding the time it was taken, and one older than any sweep runs
  # (a flat 30s, not arithmetic on $_HI_PROBE_TIMEOUT, which may be a
  # fraction) was left by a refresher that died; it is cleared and taken over
  # rather than honoured forever.
  lock="$cache.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    IFS= read -r _hi_at <"$lock/at" 2>/dev/null || _hi_at=0
    case "$_hi_at" in '' | *[!0-9]*) _hi_at=0 ;; esac
    [ "$((now - _hi_at))" -gt 30 ] || exit 0
    rm -rf "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || exit 0
  fi
  printf '%s\n' "$now" >"$lock/at" 2>/dev/null
  # Every descriptor goes to /dev/null: the shell reads this script through
  # a command substitution, which returns only when the *last* writer to its
  # pipe is gone - a refresher still holding stdout would be the wait this
  # branch exists to avoid.
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
