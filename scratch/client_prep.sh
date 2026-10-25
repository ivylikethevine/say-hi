#!/usr/bin/env bash
# The client's work before a connect's first ssh call, with no network: a
# stand-in `ssh` on PATH records the moment hi starts it (and keeps the boot
# call's stdin, the script), and fails. Prints the median of [runs] for the
# target, then with HI_PREP_PROFILE=1 one run under xtrace, its wall time up
# to that first ssh summed by the innermost three functions. The target is
# one the stand-in config names (`cfg`), or any other word, which goes
# through the backend probes first. Docker's and kubectl's probes need their
# sockets: run outside the sandbox for a figure a real client pays.
#
#   scratch/client_prep.sh [target] [runs]   # default: cfg 8
#   HI_PREP_PROFILE=1 scratch/client_prep.sh user@example.org
#
# The script the boot call would have sent lands in local/client_prep/script.
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
target="${1:-cfg}"
runs="${2:-8}"
out="$root/local/client_prep"
mkdir -p "$out"
w="$(mktemp -d "${TMPDIR:-/tmp}/hiprep.XXXXXX")"
cleanup() { case "$w" in */hiprep.??????) rm -r "$w" ;; esac }
trap cleanup EXIT
mkdir -p "$w/bin" "$w/home/.ssh" "$w/home/.config" "$w/run"
chmod 700 "$w/run"
printf 'Host cfg\n  HostName 127.0.0.1\n' >"$w/home/.ssh/config"
cat >"$w/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$EPOCHREALTIME" >>"$HI_PREP_LOG"
case "$*" in *"cat > "*) cat >"$HI_PREP_LOG.script" ;; esac
exit 255
EOF
chmod +x "$w/bin/ssh"
env_=(env -i HOME="$w/home" PATH="$w/bin:/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color
  XDG_CONFIG_HOME="$w/home/.config" XDG_RUNTIME_DIR="$w/run" HI_PREP_LOG="$w/log" _HI_HOME="${root%/*}")

for _ in $(seq "$runs"); do
  : >"$w/log"
  t0=$EPOCHREALTIME
  "${env_[@]}" bash "$root/hi.sh" "$target" </dev/null >/dev/null 2>&1
  awk -v a="$t0" 'NR == 1 { printf "%.3f\n", $1 - a }' "$w/log"
done | sort -n | awk -v t="$target" '{ a[NR] = $1 } END { printf "%s: %s s to the first ssh, median of %d\n", t, a[int((NR + 1) / 2)], NR }'
[ ! -f "$w/log.script" ] || cp "$w/log.script" "$out/script"

if [ "${HI_PREP_PROFILE:-0}" = 1 ]; then
  : >"$w/log"
  exec 9>"$w/xtrace"
  # shellcheck disable=SC2016 # PS4 expands in the traced shell
  "${env_[@]}" BASH_XTRACEFD=9 SHELLOPTS=xtrace \
    PS4='+${EPOCHREALTIME} ${FUNCNAME[0]:-main}|${FUNCNAME[1]:-}|${FUNCNAME[2]:-} ' \
    bash "$root/hi.sh" "$target" </dev/null >/dev/null 2>&1
  exec 9>&-
  awk -v end="$(head -1 "$w/log")" '$1 ~ /^\++[0-9.]+$/ {
      t = substr($1, match($1, /[0-9]/)); if (t > end) next
      if (last) cost[w] += t - last; last = t; w = $2
    }
    END { for (k in cost) printf "%.4f %s\n", cost[k], k }' "$w/xtrace" | sort -rn | head -20
fi
