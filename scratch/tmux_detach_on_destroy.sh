#!/usr/bin/env bash
# Does a client leave when a kept tmux session closes under a config's
# `detach-on-destroy off`, with another session on the server? Each case starts
# hi-kept as _hi_keep_start does, attaches a client on a pty, then ends the
# owner pane's shell, as `y` at the close question does.
#
# Run from your own shell, since a session's sandbox refuses tmux's socket:
#   mkdir -p local && bash scratch/tmux_detach_on_destroy.sh | tee local/tmux_detach.txt
#
# Every tmux call names its own socket, so no other server is touched. Reads:
#   plain                 client on [none, it left]   the baseline
#   off                   client on [other]           reproduced
#   off-then-session-on   client on [none, it left]   what setting it on the
#                                                     kept session alone does
set -u
D=$(mktemp -d "${TMPDIR:-/tmp}/hk.XXXXXX")
export TERM=xterm-256color

run_case() {
  local name=$1 conf=$2 after=$3 sock="$D/$1" i client rest
  local -a t=(tmux -S "$sock" -f "$conf")
  "${t[@]}" new-session -d -s other 'sleep 60' || exit 1
  # stdin stays open, or script hands the pane an end of file as a keystroke
  sleep 30 | script -qfc "tmux -S '$sock' -f '$conf' new-session -s hi-kept 'read x'" /dev/null >/dev/null &
  client=$!
  for ((i = 0; i < 20; i++)); do
    [ -n "$("${t[@]}" list-clients -t '=hi-kept' 2>/dev/null)" ] && break
    sleep 0.25
  done
  [ -z "$after" ] || "${t[@]}" set-option -t '=hi-kept:' detach-on-destroy "$after" >/dev/null
  echo "--- $name"
  echo "before: client on [$("${t[@]}" list-clients -F '#{session_name}')]"
  "${t[@]}" send-keys -t '=hi-kept:' Enter
  sleep 1
  rest=$("${t[@]}" list-clients -F '#{session_name}')
  echo "after:  sessions [$("${t[@]}" list-sessions -F '#S' | paste -sd, -)], client on [${rest:-none, it left}]"
  "${t[@]}" kill-server
  wait "$client" 2>/dev/null
}

tmux -V
printf 'set -g detach-on-destroy off\n' >"$D/off.conf"
: >"$D/plain.conf"
run_case plain "$D/plain.conf" ""
run_case off "$D/off.conf" ""
run_case off-then-session-on "$D/off.conf" on
case "$D" in */hk.??????) rm -rf "$D" ;; esac
