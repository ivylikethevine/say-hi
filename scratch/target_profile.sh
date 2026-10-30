#!/usr/bin/env bash
# What the target side of a connect runs and what it costs: hi connects to a
# fake ssh on this machine that runs each call's command locally instead of
# on a host, under strace or perf. The connect is hi's own cold one: a
# ControlPath with no persist, so the boot and the session calls overlap
# (_hi_connect_overlap), each its own fake ssh; the session is interactive,
# in a pty from script(1), and sent `exit` after [wait] seconds. The target
# has this machine's userland; by default its session takes bash, hi's own
# prompt, no backend, and dash as sh, as the suites' debian image would (it
# has no container CLI or prompt program), though a multiplexer or git
# installed here is still found. PROFILE_TARGET=here leaves all of that to this
# machine. Logs land in local/target_profile/.
#
#   exec  every exec on the target side with its time, under `strace -f`:
#         per call, the span, the exec count, the commands by count, and
#         the timeline (ms from the call's start). strace slows each exec,
#         so read the counts and the order, not the times.
#   cpu   [runs] cold connects under `perf stat`, no strace: the median CPU
#         time (task-clock, user and kernel, every process each call forks)
#         of the boot call, the session call, and the two together; then
#         [runs] more under `perf record`, the commands ranked by their
#         user time a connect. The samples are user time only
#         (perf_event_paranoid 2), so an exec's kernel half is in the
#         totals but not the ranking.
#         Under a CFS quota of a fraction of a core, the target side's wall
#         time is at least its CPU time over that fraction.
#   trace one connect whose session call runs under bash's xtrace (riding
#         SHELLOPTS into every bash it starts), each line stamped with
#         $EPOCHREALTIME, its process, file, and function; the time to a
#         process's next line is charged to the line before, up to 2 ms (a
#         longer gap is a wait on a child or the prompt). Prints the
#         files and functions by that time and by line count. xtrace's own
#         cost a line dominates a fast line, so the shares are weighted
#         toward loops of cheap lines: they say where the lines run, not
#         where the CPU goes. Time a function alone before cutting it.
#
# Needs strace or perf, and script(1); runs from a session.
#
#   scratch/target_profile.sh [exec] [wait]       # default wait 3
#   scratch/target_profile.sh cpu [runs] [wait]   # default 9 runs, wait 2
#   scratch/target_profile.sh trace [wait]        # default wait 2
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mode="exec"
case "${1:-}" in exec | cpu | trace) mode="$1" && shift ;; esac
if [ "$mode" = cpu ]; then
  runs="${1:-9}" wait_s="${2:-2}"
elif [ "$mode" = trace ]; then
  runs=1 wait_s="${1:-2}"
else
  runs=1 wait_s="${1:-3}"
fi
out="$root/local/target_profile"
mkdir -p "$out"
rm -f "$out"/call.* "$out"/cpu.* "$out"/perf.* "$out"/trace.*
w="$(mktemp -d "${TMPDIR:-/tmp}/hiprof.XXXXXX")"
cleanup() { case "$w" in */hiprof.??????) rm -r "$w" ;; esac }
trap cleanup EXIT
mkdir -p "$w/bin" "$w/home" "$w/run" "$w/home/.config"
chmod 700 "$w/run"

# ssh hands its command to the login shell as one string; -G answers as an
# ssh with no config would, and -O as a master that is there (hi asks only
# to check or close it). The boot and session calls run at once, so a
# call's log is named by its pid, or in cpu mode by the run number from
# the environment and its role: the session's stdin is the pty.
# shellcheck disable=SC2016 # the fake ssh expands these
if [ "$mode" = cpu ]; then
  run_='role=boot; [ ! -t 0 ] || role=sess
case "$_HI_PROF_RUN" in
s*) exec perf stat -x, -e task-clock -o "'"$out"'/cpu.$_HI_PROF_RUN.$role" /bin/bash -c "$last" ;;
*) exec perf record -q -F 20000 -e cpu-clock -o "'"$out"'/perf.$_HI_PROF_RUN.$role" /bin/bash -c "$last" ;;
esac'
elif [ "$mode" = trace ]; then
  run_='[ -t 0 ] || exec /bin/bash -c "$last"
exec 9>>"'"$out"'/trace.$$"
exec env SHELLOPTS=xtrace BASH_XTRACEFD=9 PS4='"'"'+${EPOCHREALTIME} ${BASHPID} ${BASH_SOURCE[0]##*/}:${FUNCNAME[0]:-main}: '"'"' /bin/bash -c "$last"'
else
  run_='exec strace -f -ttt -e trace=execve -e signal=none -o "'"$out"'/call.$$" /bin/bash -c "$last"'
fi
# the target's sh is dash, as on debian, unless PROFILE_TARGET=here: a bash
# sh exports SHELLOPTS with posix in it, and a bash under it skips --rcfile
sh_=""
if [ "${PROFILE_TARGET:-bare}" != here ] && command -v dash >/dev/null; then
  mkdir -p "$w/tbin" && ln -s "$(command -v dash)" "$w/tbin/sh"
  sh_="PATH=$w/tbin:\$PATH; export PATH"
fi
cat >"$w/bin/ssh" <<EOF
#!/bin/sh
for a; do last=\$a; done
case " \$* " in *" -G "*) exit 255 ;; *" -O "*) exit 0 ;; esac
$sh_
$run_
EOF
chmod +x "$w/bin/ssh"

# one cold connect, numbered $1
connect() {
  local env_=(env -i HOME="$w/home" PATH="$w/bin:/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color
    XDG_CONFIG_HOME="$w/home/.config" XDG_RUNTIME_DIR="$w/run" _HI_CTL_PERSIST=0
    _HI_PROF_RUN="$1" _HI_HOME="${root%/*}")
  # the client's environment reaches this fake target, so these stand in
  # for the suites' bare debian image: bash, hi's prompt, no container CLI
  [ "${PROFILE_TARGET:-bare}" = here ] ||
    env_+=(_HI_SHELL_PREFERENCE=bash _HI_PROMPT_TOOL=hi _HI_BACKENDS_OFF=all)
  {
    printf '#!/usr/bin/env bash\nexec'
    printf ' %q' "${env_[@]}" bash "$root/hi.sh" hitest@fake
    printf '\n'
  } >"$w/run.sh"
  chmod +x "$w/run.sh"
  {
    sleep "$wait_s"
    printf 'exit\n'
  } | script -qefc "$w/run.sh" /dev/null >"$out/transcript.$1" 2>&1
}

if [ "$mode" = exec ]; then
  connect 1
  for log in "$out"/call.*; do
    [ -f "$log" ] || continue
    awk -v name="${log##*/}" '
      / execve\(/ && !/ = -1 / {
        t = $2 + 0
        if (t0 == "") t0 = t
        cmd = $0
        sub(/.*execve\("/, "", cmd)
        sub(/".*/, "", cmd)
        sub(/.*\//, "", cmd)
        n++
        count[cmd]++
        line[n] = sprintf("%8.1f  %s", (t - t0) * 1000, cmd)
        last = t
      }
      END {
        printf "== %s: %d execs over %.1f ms\n", name, n, (last - t0) * 1000
        for (c in count) printf "%5d  %s\n", count[c], c | "sort -rn"
        close("sort -rn")
        print "-- timeline (ms)"
        for (i = 1; i <= n; i++) print line[i]
      }' "$log"
  done | tee "$out/summary.txt"
  exit 0
fi

# the stat runs first, then the record runs: perf record's own CPU would
# land in task-clock
if [ "$mode" = trace ]; then
  connect 1
  cat "$out"/trace.* | awk '
    /^\+[0-9]+\.[0-9]+ [0-9]+ / {
      t = substr($1, 2) + 0; pid = $2; key = $3
      # a gap past 2 ms is a wait (a child, a probe, the idle prompt), not work
      if (pid in last) { g = t - last[pid]; if (g > 0.002) { wait += g - 0.002; g = 0.002 } by[lastkey[pid]] += g }
      last[pid] = t; lastkey[pid] = key; n[key]++; total++
    }
    END {
      for (k in by) { all += by[k]; f = k; sub(/:.*/, "", f); file[f] += by[k]; fn[f] += n[k] }
      printf "%d trace lines, %.0f ms charged, %.0f ms of waits left out (xtrace-slowed)\n-- by file: share of time, lines\n", total, all * 1000, wait * 1000
      for (f in file) printf "%5.1f%%  %6d  %s\n", file[f] * 100 / all, fn[f], f | "sort -rn"
      close("sort -rn")
      print "-- by function: share of time, lines"
      for (k in by) printf "%5.1f%%  %6d  %s\n", by[k] * 100 / all, n[k], k | "sort -rn | head -40"
      close("sort -rn | head -40")
    }' | tee "$out/summary.txt"
  exit 0
fi

for ((r = 1; r <= runs; r++)); do connect "s$r"; done
for ((r = 1; r <= runs; r++)); do connect "r$r"; done
for ((r = 1; r <= runs; r++)); do
  b="$out/cpu.s$r.boot" s="$out/cpu.s$r.sess"
  [ -f "$b" ] && [ -f "$s" ] || continue
  awk -F, '/task-clock/ { printf "%s ", $1 }' "$b" "$s"
  echo
done >"$w/ms"
{
  printf 'target-side CPU, median of %s cold connects (task-clock, ms)\n' "$(wc -l <"$w/ms")"
  awk '{ b[NR] = $1; s[NR] = $2; t[NR] = $1 + $2 }
    function med(a, n,   i, j, x) {
      for (i = 2; i <= n; i++) { x = a[i]; for (j = i - 1; j > 0 && a[j] > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
      return a[int((n + 1) / 2)]
    }
    END { printf "%-9s %7.1f\n%-9s %7.1f\n%-9s %7.1f\n", "boot", med(b, NR), "session", med(s, NR), "both", med(t, NR) }' "$w/ms"
  printf -- '-- user ms a connect, by command and call (perf record, %s runs)\n' "$runs"
  for f in "$out"/perf.*; do
    perf report -i "$f" --stdio -n --sort comm 2>/dev/null |
      awk -v call="${f##*.}" '!/^#/ && NF >= 3 { print call, $3, $2 }'
  done | awk -v runs="$runs" '{ s[$1 " " $2] += $3 } END { for (k in s) { split(k, a, " "); printf "%7.2f  %-5s %s\n", s[k] * 0.05 / runs, a[1], a[2] } }' |
    sort -rn | head -30
  printf '%s; host %sCPU/%sGB\n' "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet -- hi.sh load.sh common || echo ' plus the working tree')" \
    "$(nproc)" "$(free -g | awk '/^Mem:/ { print $2 }')"
} | tee "$out/summary.txt"
