#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each; the
# bash, zsh, and fish completions all read it. Standalone POSIX - fish shells
# out to it, and it runs on whatever /bin/sh a target has.
# Usage: sh targets.sh [ssh|<cli>|nomad|kube|flags [<command>]|words <flag>]
#        (<cli> = one of the docker-compatible CLIs: docker, podman, nerdctl
#        or finch; no argument = every backend; `flags` = hi's own
#        options instead, `flags --install` a local command's own switches,
#        `words --use` the word a flag takes, `ssh-config [file]` the ssh
#        config with its Includes inlined, `ssh-files [file]` the files that
#        reads, `ssh-include <words>` one Include's files)
# GLOSSARY: HI.26 - _HI_PROBE_TIMEOUT and _HI_TARGETS_TTL
# GLOSSARY: HI.51 - the docker-compatible CLI family
#
# Backends are probed in parallel, each capped at $_HI_PROBE_TIMEOUT, output
# in roster order; with no writable scratch directory, in turn.
# shellcheck disable=SC2329 # every function here is reached indirectly, through
# run_lister's dispatch or as a background job.

# ssh_config_flat config|files <path> | ssh_config_flat include <words> - an ssh config
# with each `Include` followed in place as ssh does (`~` is $HOME, relative
# under ~/.ssh, globs sorted, 16 deep); the line stays so a `# Tags:` above it
# still ends there. A word with anything but path and glob characters is
# skipped. `files` prints the paths read instead. Each Included file's lines
# follow a `# hi-file: <path>` line, its parent's after, so a file's name can
# tag its hosts (core.sh's _hi_ssh_walk_line).
ssh_config_flat() {
  awk -v mode="$1" -v arg="$2" -v home="$HOME" '
    function inc(args, depth,   n, w, i, p, cmd, f, m, list, k) {
      n = split(args, w, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        p = w[i]
        gsub(/"/, "", p)
        # `]` first and `[` bare: busybox awk ends the class at a `\]`
        if (p == "" || p !~ /^[][A-Za-z0-9_.\/~*?,@%+:=-]+$/) continue
        if (p ~ /^~\//) p = home substr(p, 2)
        else if (p !~ /^\//) p = home "/.ssh/" p
        cmd = "for f in " p "; do [ -f \"$f\" ] && printf \"%s\\n\" \"$f\"; done"
        m = 0
        while ((cmd | getline f) > 0) list[++m] = f
        close(cmd)
        for (k = 1; k <= m; k++) emit(list[k], depth + 1)
      }
    }
    function emit(file, depth,   line, rest) {
      if (mode == "files") print file
      else if (depth) print "# hi-file: " file
      while ((getline line < file) > 0) {
        rest = line
        sub(/^[ \t]+/, "", rest)
        if (depth < 16 && tolower(rest) ~ /^include[ \t=]/) {
          if (mode != "files") print line
          sub(/^[^ \t=]+[ \t=]+/, "", rest)
          inc(rest, depth)
          if (mode != "files") print "# hi-file: " file
        } else if (mode != "files") print line
      }
      close(file)
    }
    BEGIN { if (mode == "include") inc(arg, 0); else emit(arg, 0); exit }'
}

# ssh_hosts <help> - every literal Host name in the ssh config and its
# Includes, "<name>\t<help>"; a wildcard names no host of its own
ssh_hosts() {
  _hi_ssh_config="${_HI_SSH_CONFIG:-$HOME/.ssh/config}"
  [ -f "$_hi_ssh_config" ] || return 0
  ssh_config_flat config "$_hi_ssh_config" | awk -v help="$1" 'tolower($1) == "host" {
    for (i = 2; i <= NF; i++) {
      if ($i ~ /^#/) break
      if ($i !~ /[*?]/) printf "%s\t%s\n", $i, help
    }
  }'
}

kind="${1:-all}"
# `ssh-config`/`ssh-files [file]` and `ssh-include <words>`: ssh_config_flat
# for the shells, which walk a config for tags and cannot source this file
case "$kind" in
ssh-config | ssh-files)
  ssh_config_flat "${kind#ssh-}" "${2:-${_HI_SSH_CONFIG:-$HOME/.ssh/config}}"
  exit 0
  ;;
ssh-include)
  ssh_config_flat include "${2:-}"
  exit 0
  ;;
esac
# The docker-compatible family, once: the `words` arm below and the probe
# roster further down both walk it, and the two exits are far enough apart
# that they read as unrelated files. hi.sh and common/header.sh read the same
# four words from core.sh's $_HI_CONTAINER_CLIS, which this standalone POSIX
# file cannot source - the drift suite pins the two together. GLOSSARY: HI.51
clis="docker podman nerdctl finch"

# hi's own flags for `hi --<TAB>`, "<flag>\t<help>" lines like a target's,
# answered before the cache and probes so they never wait on a daemon.
# targets_test.sh checks them against --help. The tree comes from $0, since
# a completion may run this without paths.sh (GLOSSARY: HI.33).
case $0 in
*/*) hi_tree="${0%/*}/.." ;;
*) hi_tree=".." ;;
esac

if [ "$kind" = flags ]; then
  # From common/flags. A <needs> of `-` is offered everywhere; the rest are
  # withheld in a session and checked against the tree (a package has no
  # .git). `flags <command>` for a local command offers its own switches from
  # the argument column (`hi --install --<TAB>`); otherwise hi's roster.
  if [ -n "${2:-}" ]; then
    while IFS='|' read -r flag arg needs _var _first _help; do
      [ "$flag" = "$2" ] && [ "$needs" != - ] || continue
      for word in $(printf '%s' "$arg" | tr -d '[]'); do
        case "$word" in
        --*) printf '%s\t%s option\n' "$word" "$flag" ;;
        esac
      done
      exit 0
    done <"$hi_tree/common/flags"
  fi
  while IFS='|' read -r flag _arg needs _var _first help; do
    case "$flag" in '#'* | '' | *=*) continue ;; esac
    [ "$needs" = - ] || [ "${_HI_REMOTE_SESSION:-0}" != 1 ] || continue
    case "$needs" in
    scripts) [ -d "$hi_tree/scripts" ] || continue ;;
    git) [ -d "$hi_tree/.git" ] || continue ;;
    esac
    printf '%s\t%s\n' "$flag" "$help"
  done <"$hi_tree/common/flags"
  exit 0
fi

# The word a flag takes (`hi --preview <TAB>`), as "<word>\t<help>" lines:
# common/flags' <flag>=<word> rows, or computed (a host, a tag, a plugin).
# --use's arms are spelled again here (parse_test.sh pins them to hi.sh's).
# Answered before the probes.

if [ "$kind" = words ]; then
  # a fixed list is common/flags' <flag>=<word> rows
  while IFS='|' read -r flag help; do
    case "$flag" in "${2:-}="?*) printf '%s\t%s\n' "${flag#*=}" "$help" ;; esac
  done <"$hi_tree/common/flags"
  case "${2:-}" in
  --update)
    # the release tags a checkout knows of, newest first; a package has no
    # .git and gets nothing
    [ -d "$hi_tree/.git" ] && git -C "$hi_tree" tag --list 'v*' --sort=-v:refname 2>/dev/null |
      while IFS= read -r tag; do printf '%s\trelease tag\n' "$tag"; done
    ;;
  --add-tag)
    ssh_hosts 'an ssh host to tag'
    ;;
  --remove-tag)
    ssh_hosts 'an ssh host to untag'
    ;;
  --disable-plugin)
    # the plugins files read as text, since this file cannot source the
    # packer: each `[<group>.<name>]` table's plugin. A session has neither
    # file, and no use for the flag.
    for f in "$hi_tree/config/plugins" "${_HI_CONFIG_DIR:-}/plugins"; do
      [ ! -f "$f" ] || sed -n 's/^[[:space:]]*\[[[:space:]]*\([A-Za-z0-9_-]\{1,\}\)[[:space:]]*\.[[:space:]]*\([A-Za-z0-9_-]\{1,\}\)[[:space:]]*\].*/\1|\2/p' "$f"
    done | awk -F'|' '!seen[$2]++ { printf "%s\ta plugin\n", $2 }'
    ;;
  --enable-plugin)
    # what is off: the words of settings.sh's last _HI_PLUGINS_OFF line
    [ -f "${_HI_CONFIG_DIR:-}/settings.sh" ] &&
      sed -n 's/^[ ]*\(export[ ]\{1,\}\)\{0,1\}_HI_PLUGINS_OFF=//p' "$_HI_CONFIG_DIR/settings.sh" |
      tail -n 1 | tr -d "\"'" | tr ',' ' ' | tr -s ' ' '\n' | while IFS= read -r line; do
        [ -z "$line" ] || printf '%s\tswitched off\n' "$line"
      done
    ;;
  --edit)
    # hi's own four, there or not, then every other file of the overlay
    for line in settings.sh colors packages plugins; do printf '%s\thi reads it\n' "$line"; done
    [ -d "${_HI_CONFIG_DIR:-}" ] && find "$_HI_CONFIG_DIR" -type f 2>/dev/null |
      cut -c"$((${#_HI_CONFIG_DIR} + 2))-" | sort | while IFS= read -r line; do
      case "$line" in
      settings.sh | colors | packages | plugins) ;;
      *) printf '%s\ta file of your overlay\n' "$line" ;;
      esac
    done
    ;;
  --use)
    printf 'ssh\tssh, no probing (a container of the same name loses)\n'
    # shellcheck disable=SC2086 # the split is the roster
    for cli in $clis; do
      printf '%s\ta running container, through %s\n' "$cli" "$cli"
    done
    printf 'nomad\ta running nomad allocation\n'
    printf 'kube\ta kubernetes pod\n'
    ;;
  esac
  exit 0
fi

# core.sh's _HI_TARGETS_TTL_DEFAULT and _HI_PROBE_TIMEOUT_DEFAULT, which drift
# pins these to
ttl="${_HI_TARGETS_TTL:-5}" cap="${_HI_PROBE_TIMEOUT:-2}"

# core.sh's _hi_probe, again: optional `timeout`, `-k 0.2` because rootless
# podman defers the TERM while its runtime starts, and BusyBox's older forms.
# run_lanes calls it once before forking.
run_backend() {
  if ! command -v timeout >/dev/null 2>&1; then
    run_backend() { "$@"; }
  elif timeout -k 0.2 1 true 2>/dev/null; then
    run_backend() { timeout -k 0.2 "$cap" "$@"; }
  elif timeout 1 true 2>/dev/null; then
    run_backend() { timeout "$cap" "$@"; }
  elif timeout -t 1 true 2>/dev/null; then
    run_backend() { timeout -t "$cap" "$@"; }
  else
    run_backend() { "$@"; }
  fi
  run_backend "$@"
}

# Everything below the first line of $1, fork-free: faster than a `tail` exec
# at this size, and works on a PATH with no coreutils.
cache_body() {
  {
    IFS= read -r _hi_line # the stamp
    while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do printf '%s\n' "$_hi_line"; done
  } <"$1"
}

# Private per-run scratch for a fan-out's output, made only on a path that fans
# out (a host with no backends never reaches for `mkdir`).
scratch=""

# backend_wanted <label> - does the kind gate pass, is it left on, and is
# its CLI (kube's is kubectl) here? Every half is a builtin, so the roster is sized before
# anything forks.
backend_wanted() {
  { [ "$kind" = "$1" ] || [ "$kind" = all ]; } || return 1
  # $_HI_BACKENDS_OFF, as core.sh's _hi_backend_off reads it
  case " ${_HI_BACKENDS_OFF:-} " in
  *[\ ,]"$1"[\ ,]* | *[\ ,]all[\ ,]*) return 1 ;;
  esac
  case "$1" in kube) set -- kubectl ;; esac
  command -v "$1" >/dev/null 2>&1
}

# run_lister <label> - that backend's rows on stdout, in turn or backgrounded.
run_lister() {
  case "$1" in
  nomad) list_nomad ;;
  kube) list_kube ;;
  *) list_ps "$1" ;;
  esac
}

# Every wanted lane's rows, backgrounded where there is somewhere to put them
# and more than one lane to run. Its own function because emit_targets asks
# for the same thing twice - once through dedupe_family and once not - and
# spelling the fan-out at both call sites is how the two drift apart.
run_lanes() {
  if [ "$n_wanted" -ge 2 ] && [ -n "$scratch" ]; then
    files=""
    run_backend true
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
}

# Two family members fronting one daemon (podman-docker's `docker` is a script
# that execs podman; nerdctl and finch share a containerd) list every container
# once per lane. The earlier lane's row wins, so a shim-docker host lists its
# containers as `docker`; nomad and kube rows pass untouched. No fork: names
# never carry whitespace, so a default-IFS `read` splits the tab for free.
dedupe_family() {
  _hi_seen=" "
  while read -r _hi_name _hi_kind || [ -n "$_hi_name" ]; do
    [ -n "$_hi_name" ] || continue
    case "$_hi_kind:$_hi_seen" in
    nomad:* | kube:*) ;;
    *" $_hi_name "*) continue ;;
    *) _hi_seen="$_hi_seen$_hi_name " ;;
    esac
    printf '%s\t%s\n' "$_hi_name" "$_hi_kind"
  done
}

emit_targets() {
  # ssh first and in line: a local file read and one awk, faster than the
  # bookkeeping of backgrounding it
  if [ "$kind" = ssh ] || [ "$kind" = all ]; then
    ssh_hosts ssh
  fi

  # The roster, in the order the rows are emitted: the docker-compatible
  # family, each CLI its own lane and kind, then nomad and kube. One that is
  # not on $PATH costs a builtin `command -v` and nothing else.
  wanted="" n_wanted=0 n_family=0
  # shellcheck disable=SC2086 # the split is the roster
  for label in $clis nomad kube; do
    backend_wanted "$label" || continue
    wanted="${wanted}${wanted:+ }$label"
    n_wanted=$((n_wanted + 1))
    case "$label" in nomad | kube) ;; *) n_family=$((n_family + 1)) ;; esac
  done
  [ "$n_wanted" -gt 0 ] || return 0

  # worth its two forks only where something fans out: two or more backends,
  # or nomad/kube alone, whose own calls fan out inside the lane
  if [ "$n_wanted" -ge 2 ] || [ "$wanted" = nomad ] || [ "$wanted" = kube ]; then
    # `mkdir -m 700` and no `-p`: -p succeeds on a path somebody else got to
    # first, which would then be adopted and `rm -rf`'d on the way out
    _hi_scratch="${TMPDIR:-/tmp}/hi-probe.$$"
    ! mkdir -m 700 "$_hi_scratch" 2>/dev/null || scratch="$_hi_scratch"
  fi

  # the dedupe pass only where two family lanes could list one daemon twice
  if [ "$n_family" -ge 2 ]; then run_lanes | dedupe_family; else run_lanes; fi

  [ -n "$scratch" ] && rm -rf "$scratch" 2>/dev/null
  return 0
}

# The listers, each reached through run_lister's dispatch.

# One call per family CLI, its kind the CLI's name, tagged by the read loop
# rather than a `sed`. docker and podman also list compose service names
# (_hi_compose_container resolves them); nerdctl and finch are unverified for
# that template.
list_ps() {
  _hi_fmt='{{.Names}}'
  case "$1" in docker | podman) _hi_fmt='{{.Names}} {{.Label "com.docker.compose.service"}}' ;; esac
  run_backend "$1" ps --format "$_hi_fmt" 2>/dev/null |
    while read -r _hi_name _hi_svc || [ -n "$_hi_name" ]; do
      [ -n "$_hi_name" ] || continue
      printf '%s\t%s\n' "$_hi_name" "$1"
      # only when it differs, or a container_name equal to the service name
      # would complete twice
      [ -n "$_hi_svc" ] && [ "$_hi_svc" != "$_hi_name" ] && printf '%s\t%s\n' "$_hi_svc" "$1"
    done
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

# Each pod, plus "pod/container" lines for a pod with several, from one
# jsonpath over every namespace: bare in the current namespace, else
# `namespace:pod`. The namespace lookup runs beside the listing, the longest
# lane.
kube_ns() { run_backend kubectl config view --minify -o jsonpath='{..namespace}'; }

list_kube() {
  if [ -n "$scratch" ]; then
    kube_ns >"$scratch/kube.ns" 2>/dev/null &
    kube_pods >"$scratch/kube.pods" 2>/dev/null
    wait
    IFS= read -r _hi_ns <"$scratch/kube.ns" 2>/dev/null || _hi_ns=""
    kube_rows <"$scratch/kube.pods"
  else
    _hi_ns="$(kube_ns 2>/dev/null)"
    kube_pods 2>/dev/null | kube_rows
  fi
}

# --request-timeout: kubectl's own bound, the one left where `timeout` is not
kube_pods() {
  run_backend kubectl get pods -A --request-timeout="${cap}s" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{range .spec.containers[*]}{" "}{.name}{end}{"\n"}{end}'
}

# stdin is kube_pods' output; $_hi_ns decides which pods are emitted bare
kube_rows() {
  [ -n "${_hi_ns:-}" ] || _hi_ns=default
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

# No cache wanted: just answer, before the two forks below.
if [ "$ttl" -le 0 ]; then
  emit_targets
  exit 0
fi
# the fallback outside the substitution, and `exec` inside it: a `||` in
# there defeats the run-in-place optimisation and costs a second process
now="$(exec date +%s 2>/dev/null)" || now=0

# $XDG_RUNTIME_DIR is per-user and 0700 where it exists; the fallback makes a
# private directory of its own, not a predictable name in a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  # one `id -u`, not two: the name needs it and so does the ownership check
  _hi_uid="$(exec id -u 2>/dev/null)" || _hi_uid=unknown
  cache_dir="${TMPDIR:-/tmp}/hi-$_hi_uid"
  # first TAB only; -m 700 on the create so it is never briefly world-readable,
  # and no -p, which would silently adopt a path somebody else made
  [ -d "$cache_dir" ] || mkdir -m 700 "$cache_dir" 2>/dev/null
  # The name is predictable, so another user could make it first on a shared
  # /tmp; a directory not ours means no cache, a slower sweep. Owner by
  # `ls -ldn` (`test -O` is not POSIX), numeric so no `id -un` fork.
  # shellcheck disable=SC2012,SC2046 # `find -maxdepth` is not POSIX and `find -user`
  # takes a user *name*, which is exactly what a host with no passwd entry for
  # the caller cannot supply. SC2012's hazard is parsing file *names* out of
  # ls; this reads a fixed column off one path this script built itself.
  set -- $(exec ls -ldn "$cache_dir" 2>/dev/null)
  if [ ! -d "$cache_dir" ] || [ -L "$cache_dir" ] || [ "${3:-}" != "$_hi_uid" ]; then
    emit_targets
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
  # shellcheck disable=SC2015,SC2086 # ${1:+"$1"} - vanishes when empty, one word when not
  printf '%s\n' "$now" ${1:+"$1"} 2>/dev/null >"$_hi_tmp" && mv "$_hi_tmp" "$cache" 2>/dev/null || rm -f "$_hi_tmp" 2>/dev/null
}

# The cache's first line is its time (no portable mtime in seconds). Inside
# the TTL the copy answers; up to $stale_for it answers while a refresh runs
# behind; past that the sweep is waited on. TTL 0 skips the cache.
stale_for=600
age=""
if [ -f "$cache" ] && [ -r "$cache" ]; then
  # `read < file`, not $(head -n1): on the cache-hit path that subshell+exec
  # was most of the cost
  IFS= read -r stamp <"$cache" 2>/dev/null || stamp=""
  case "$stamp" in
  '' | *[!0-9]*) ;; # not a timestamp - treat as a miss and rewrite it
  *) [ "$now" -lt "$stamp" ] || age=$((now - stamp)) ;;
  esac
fi

if [ -n "$age" ] && { [ "$age" -lt "$ttl" ] || [ "$age" -lt "$stale_for" ]; }; then
  cache_body "$cache"
  [ "$age" -ge "$ttl" ] || exit 0
  # One refresh at a time: a lock directory holding its time. One older than
  # 30s, or with no time and over a minute old, belongs to a refresher that
  # died and is taken over.
  lock="$cache.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    if IFS= read -r _hi_at <"$lock/at" 2>/dev/null; then
      case "$_hi_at" in '' | *[!0-9]*) _hi_at=0 ;; esac
      [ "$((now - _hi_at))" -gt 30 ] || exit 0
    else
      [ -n "$(find "$lock" -prune -mmin +1 2>/dev/null)" ] || exit 0
    fi
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
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
