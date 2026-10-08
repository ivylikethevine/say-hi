#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The kept session, client half (GLOSSARY: HI.65): which connects look for
# one and which start one, the sh those put on a target - the reattach, the
# owner pane's start, the sweep, a held tree's take - `hi --end`, `hi --keep`
# typed in a session, the client's record, and the retry of a dropped link.
# The target's half is load.sh's.
#
# hi.sh sources this and is the one caller: its functions read hi.sh's parsed
# state ($DOMAIN, $KEEP, $CMDARG, $SSHARGS) and call its helpers, and
# _hi_keep_connect runs its _say_hi. Like hi.sh, most of it is a script
# assembled for another machine (SC2016, SC2029).
# shellcheck disable=SC2016,SC2029

# The session name for a target: every character tmux's rules reject, or that
# reads badly in a status line, becomes `-`. `ctx:ns:pod/ctr` -> `hi-ctx-ns-pod-ctr`.
# _hi_mux_name <target> [outvar]
function _hi_mux_name() {
  _hi_out "${2:-}" "hi-${1//[^[:alnum:]_-]/-}"
}

# Whether this connect looks on the target for a kept session to reattach:
# every session, not a command, unless --no-keep asked for one beside it, and
# none with the kept session switched off (hi.sh's _hi_keep_off).
function _hi_keep_probes() {
  [ -z "${CMDARG:-}" ] && [ "${KEEP:-}" != 0 ] && ! _hi_keep_off
}

# ...and whether it starts one where the target has none: --keep, or
# _HI_KEEP=1 with neither flag typed.
function _hi_keep_starts() {
  _hi_keep_probes && [ "${KEEP:-${_HI_KEEP:-0}}" = 1 ]
}

# How the target finds its kept session: $_hi_kn is the name, and _hi_kept
# answers with the multiplexer holding it in $_hi_k (screen's own id for it
# in $_hi_ks). GLOSSARY: HI.65
function _hi_keep_find() {
  local name_q
  _hi_mux_name "$DOMAIN" name_q
  _hi_shquote name_q "$name_q"
  cat <<REMOTE
      _hi_kn=$name_q
      _hi_kept() {
        _hi_k=tmux
        tmux has-session -t "=\$_hi_kn" 2>/dev/null && return
        _hi_k=zellij
        zellij ls -n 2>/dev/null | grep -v '(EXITED' | grep -q "^\$_hi_kn " && return
        _hi_k=screen
        _hi_ks=\$(screen -ls 2>/dev/null | sed -n "/Dead/d; s/^[[:space:]]*\\([0-9][0-9]*[.]\$_hi_kn\\)[[:space:]].*/\\1/p")
        [ -n "\$_hi_ks" ] && return
        _hi_k=
        return 1
      }
REMOTE
}

# Ahead of the unpack: a kept session is attached and the script ends there,
# so nothing new lands on the target. _hi_kept_note is the line a detach
# leaves, for this path and the start below, and the script's status says
# whether a kept session is left behind (86, _hi_keep_connect). A client that
# expected one says so where there is none - on a target with a multiplexer
# to have held it, since a keeping connect expects one before it knows. A
# session that does start is told the target's name, for a `hi --keep` typed
# in it (_hi_keep_here).
function _hi_keep_attach() {
  local target_q _hi_esc _hi_nc gone=""
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  [ "${_HI_KEEP_EXPECTED:-}" != 1 ] ||
    gone="      _hi_kept || ! { command -v tmux || command -v zellij || command -v screen; } >/dev/null 2>&1 || printf '%s hi: the kept session on [%s] is gone %s\\n' \"$_hi_esc\" $target_q \"$_hi_nc\" >&2"$'\n'
  _hi_keep_find
  cat <<REMOTE
      _hi_kept_note() { _hi_kept && printf '%s%s detached, the session on [%s] is kept %s\n' "$_hi_esc" "\$1" $target_q "$_hi_nc" >&2; }
      if [ -t 0 ] && _hi_kept; then
        case \$_hi_k in
        tmux) tmux attach-session -t "=\$_hi_kn" ;;
        zellij) zellij attach "\$_hi_kn" ;;
        screen) screen -x "\$_hi_ks" ;;
        esac
        _hi_kept_note ' hi:' && exit 86
        exit 0
      fi
$gone      export _HI_KEEP_AS=$target_q
REMOTE
}

# The bash handoff of a connect that keeps its session: the same
# `bash --rcfile` as the owner pane of a tmux, zellij, or screen session, the
# first of the three on the target. The session's variables reach the pane as
# an `env` argv, since a multiplexer server already running hands a pane its
# own environment, and the subshell drops them before the exec so a server
# started here carries none of them to its other panes (GLOSSARY: HI.47).
# The multiplexer reads the config hi carried, as the session's alias does.
# zellij takes a first pane's command from a layout alone, so that argv is
# written into one beside the rc, as KDL strings, under zellij's own two bars;
# its options keep the session off the disk and a dropped client a detach,
# open new panes on the launcher load.sh writes (_hi_keep_panes), and turn
# off the popups that would take the first prompt's keys, each asked for only
# where this zellij lists it.
# _hi_keep_start [note prefix [name...]] - the names are the pane's variables
# where a session starts it, which has them in a file and not in a connect.
# $_HI_KEEP_WITH, there, is the one of the three that was typed. A target with
# none of the three holds the session's tree instead (_hi_keep_held): its
# bootstrap outlasts the hangup, so the session's own exit decides the tree.
function _hi_keep_start() {
  local n argv="" drop="" note="${1:- |}"
  local -a vars=("${@:2}")
  if [ "${#vars[@]}" -eq 0 ]; then
    while IFS=$'\t' read -r n _; do vars+=("$n"); done < <(_hi_session_env)
    vars+=(_HI_ROOT _HI_CLEANUP _HI_CONNECT_PREFIX _HI_CONNECT_TIME _HI_COPY_TIME)
  fi
  for n in "${vars[@]}"; do
    argv="$argv $n=\"\$$n\""
    [ "$n" = NO_COLOR ] || drop="$drop $n"
  done
  drop="$drop _HI_KEEP_AS _HI_KEEP_WITH"
  cat <<REMOTE
        _hi_k=
        for _hi_s in tmux zellij screen; do [ "\$_hi_s" = "\${_HI_KEEP_WITH:-\$_hi_s}" ] && command -v "\$_hi_s" >/dev/null 2>&1 && { _hi_k=\$_hi_s; break; }; done
        if [ -n "\$_hi_k" ] && [ -t 0 ]; then
          set -- env _HI_KEEP_MUX="\$_hi_k" _HI_KEEP_NAME="\$_hi_kn" _HI_HOME="\$_HI_HOME" _HI_CONFIG_DIR="\$_HI_CONFIG_DIR"$argv bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
          (
            unset$drop
            case \$_hi_k in
            tmux)
              _hi_kc="\$_HI_CONFIG_DIR/tmux/tmux.conf"
              [ ! -f "\$_hi_kc" ] || exec tmux -f "\$_hi_kc" new-session -s "\$_hi_kn" "\$@"
              exec tmux new-session -s "\$_hi_kn" "\$@"
              ;;
            zellij)
              _hi_kc="\$_hi_rc_dir/hi.keep.kdl"
              {
                printf '%s\n' 'layout {' 'default_tab_template {' 'pane size=1 borderless=true {' 'plugin location="zellij:tab-bar"' '}' children 'pane size=2 borderless=true {' 'plugin location="zellij:status-bar"' '}' '}' 'tab {' 'pane command="env" close_on_exit=true {'
                shift
                printf args
                for _hi_s; do printf ' "%s"' "\$(printf '%s' "\$_hi_s" | sed 's/[\\\\"]/\\\\&/g')"; done
                printf '\n}\n}\n}\n'
              } >"\$_hi_kc"
              set -- -s "\$_hi_kn" -n "\$_hi_kc" options --session-serialization false --on-force-close detach --default-shell "\$_hi_rc_dir/hi.pane"
              for _hi_s in startup-tips release-notes; do
                ! zellij options --help 2>/dev/null | grep -q -- "--show-\$_hi_s" || set -- "\$@" "--show-\$_hi_s" false
              done
              [ ! -d "\$_HI_CONFIG_DIR/zellij" ] || set -- --config-dir "\$_HI_CONFIG_DIR/zellij" "\$@"
              exec zellij "\$@"
              ;;
            screen)
              _hi_kc="\$_HI_CONFIG_DIR/screenrc"
              [ ! -f "\$_hi_kc" ] || exec screen -c "\$_hi_kc" -S "\$_hi_kn" "\$@"
              exec screen -S "\$_hi_kn" "\$@"
              ;;
            esac
          )
          _hi_kept_note '$note'
        else
          [ -n "\$_hi_k" ] || { export _HI_KEEP_HOLD="\$_hi_kn" && trap : HUP; }
          bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
        fi
REMOTE
}

# What a connect that looks for a kept session runs once it has a tree of its
# own. A session killed with no exit hook - the target went down under it -
# left its tree, and its claim in it (load.sh's _hi_keep_claim): hi.kept, an
# owner pane's pid and that of the shell it was kept from, or hi.pid, any
# other session's, or hi.held, the watcher's of a tree a drop left to its
# timer and the shell's that left it (load.sh's clean_all). A tree no process
# of its claim still runs on is removed, and one a kept session or a timer
# claims is that claim's alone. GLOSSARY: HI.65
function _hi_keep_sweep() {
  # shellcheck disable=SC2016 # the target's to expand
  printf '%s\n' \
    '      for _hi_s in "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.kept "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.held "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.pid; do' \
    '        case "$_hi_s" in */hi.pid) [ ! -e "${_hi_s%pid}kept" ] && [ ! -e "${_hi_s%pid}held" ] || continue ;; esac' \
    '        read -r _hi_ko _hi_kp _hi_kh 2>/dev/null <"$_hi_s" && [ -n "$_hi_ko" ] || continue' \
    '        kill -0 "$_hi_ko" 2>/dev/null || kill -0 "${_hi_kp:-$_hi_ko}" 2>/dev/null || rm -rf "${_hi_s%/say-hi/hi.*}"' \
    '      done'
}

# What a connect that looks for a kept session runs after the sweep, at a
# terminal: a tree a dropped session of this name left to its timer
# (hi.held: the watcher, the shell, the name) becomes this connect's, in place
# of the empty one it just made, and $_hi_held says the unpack is not needed.
# Only a directory of this account's own, never a link to one, since its rc
# is about to be run. The claim is this script's pid in hi.pid, then the
# removal of hi.held, which one of two connects wins; the session starts in
# the directory the dropped one was in, and holds its tree as that one did.
# GLOSSARY: HI.65
function _hi_keep_held() {
  # shellcheck disable=SC2016 # the target's to expand
  printf '%s\n' \
    '      _hi_held=' \
    '      [ ! -t 0 ] || for _hi_s in "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.held; do' \
    '        _hi_d=${_hi_s%/say-hi/hi.held}' \
    '        [ -O "$_hi_d" ] && [ ! -L "$_hi_d" ] && read -r _hi_ko _hi_kp _hi_kh 2>/dev/null <"$_hi_s" && [ "$_hi_kh" = "$_hi_kn" ] || continue' \
    '        echo "$$" >"$_hi_d/say-hi/hi.pid" && rm "$_hi_s" 2>/dev/null || continue' \
    '        rmdir "$_HI_ROOT" "$_HI_HOME"' \
    '        export _HI_HOME="$_hi_d" _HI_ROOT="$_hi_d/say-hi" _HI_CONFIG_DIR="$_hi_d/say-hi/config" _HI_CLEANUP="$_hi_d" _HI_KEEP_HOLD="$_hi_kn"' \
    '        _hi_held=1' \
    '        trap : HUP' \
    '        ! IFS= read -r _hi_s <"$_HI_ROOT/hi.cwd" || cd "$_hi_s" 2>/dev/null || :' \
    '        break' \
    '      done'
}

# What `hi --end` runs on the target: 3 when there is no kept session to
# close. The owner pane's bash takes the hangup and its exit hook removes the
# tree, as on a dropped connection. A tree a drop left to its timer is ended
# through that timer's watcher, which hi.end tells to stop waiting.
function _hi_keep_end_script() {
  local tmpl
  _hi_whoami >/dev/null
  _hi_shquote tmpl "$_HI_WHOAMI_CACHE.hi.XXXXXX"
  _hi_keep_find
  cat <<REMOTE
      _hi_kept || {
        _hi_e=3
        _hi_d=\$(mktemp -d -t $tmpl) && rmdir "\$_hi_d" || exit 3
        for _hi_s in "\${_hi_d%.hi.*}".hi.*/say-hi/hi.held; do
          [ -O "\$_hi_s" ] && read -r _hi_ko _hi_kp _hi_kh 2>/dev/null <"\$_hi_s" && [ "\$_hi_kh" = "\$_hi_kn" ] || continue
          : >"\${_hi_s%held}end" && _hi_e=0
        done
        exit \$_hi_e
      }
      case \$_hi_k in
      tmux) tmux kill-session -t "=\$_hi_kn" ;;
      zellij) zellij kill-session "\$_hi_kn" ;;
      screen) screen -S "\$_hi_ks" -X quit ;;
      esac
REMOTE
}

# hi --end <target>: close the kept session there, without attaching
function _hi_keep_end() {
  local ec=0 rec
  _hi_ssh_sh "$(_hi_keep_end_script)" </dev/null || ec=$?
  # closed, or not there: either way this client no longer expects it
  case "$ec" in 0 | 3) ! _hi_keep_record rec || rm -f "$rec" ;; esac
  case "$ec" in
  0) _hi_cecho "hi: closed the kept session on [$DOMAIN]" "$GREEN" ;;
  3)
    _hi_cecho "hi: no kept session on [$DOMAIN]" "$YELLOW" >&2
    ec=1
    ;;
  esac
  return "$ec"
}

# hi --keep typed in a session: the session's tree gets an owner pane in the
# first multiplexer here, under the name its client looks for, by the script
# a keeping connect runs from where it starts the pane. load.sh left what the
# pane needs in hi.keep, a NAME=value a line, the target's name among them.
# The hi.kept marker is the pane's claim on the tree: this session's exit
# leaves the tree to it (load.sh's clean_all). A multiplexer typed bare in a
# session comes here too (common/mux.sh), naming itself in $_HI_KEEP_WITH,
# and is the one started where the name is one of the three. GLOSSARY: HI.65
function _hi_keep_here() {
  local file="$_HI_ROOT/hi.keep" line with=""
  case "${_HI_KEEP_WITH:-}" in tmux | zellij | screen) with="$_HI_KEEP_WITH" ;; esac
  local -a vars=()
  [ -r "$file" ] || _hi_die "--keep: nothing to keep here - it takes a session over ssh, into bash, started without --no-keep"
  [ -t 0 ] || _hi_die "--keep needs a terminal"
  [ -z "${TMUX:-}${ZELLIJ:-}${STY:-}" ] || _hi_die "--keep: already inside a multiplexer here, and hi does not nest one"
  if ! { command -v tmux || command -v zellij || command -v screen; } >/dev/null 2>&1; then
    _hi_keep_hold_here "$file"
    return
  fi
  # The script's environment, in the shell _hi is about to leave: a child's
  # (GLOSSARY: HI.47) and the file's, so the multiplexer started here
  # inherits what one a connect starts does, and none of this launcher's own.
  _hi_unexport
  while IFS= read -r line; do
    export "${line?}"
    [ "${line%%=*}" = _HI_KEEP_AS ] || vars+=("${line%%=*}")
  done <"$file"
  DOMAIN="$_HI_KEEP_AS" KEEP=1 CMDARG=""
  # 86 is the attach block's word to a client that a session is kept
  # shellcheck disable=SC2016 # the script's sh expands these
  _HI_KEEP_WITH="$with" sh -c "$(_hi_keep_attach)"'
      _hi_rc_dir=$_HI_ROOT
      : >"$_HI_ROOT/hi.kept"
'"$(_hi_keep_start ' hi:' "${vars[@]}")"'
      _hi_kept || rm -f "$_HI_ROOT/hi.kept"' || [ "$?" = 86 ]
}

# `hi --keep` typed in a session on a machine with none of the three: the
# session holds its tree from here on, as one a keeping connect started
# there does. hi.hold, the name a later connect looks for, is what its exit
# hook, its prompt hooks, and its bootstrap's trap read (load.sh's
# _hi_keep_holds), and the directory it is in now is noted for it. Refused
# where the session could not hold: a window of 0.
function _hi_keep_hold_here() {
  local line as="" name limit=0
  while IFS= read -r line; do
    [ "${line%%=*}" != _HI_KEEP_AS ] || as="${line#*=}"
  done <"$1"
  _hi_keep_seconds "${_HI_KEEP_TIMEOUT:-15m}" limit || limit=900
  if [ -z "$as" ] || ((limit <= 0)); then
    _hi_die "--keep needs tmux, zellij, or screen on this machine, or a _HI_KEEP_TIMEOUT over 0 to hold its files by"
  fi
  _hi_mux_name "$as" name
  if ! { printf '%s\n' "$PWD" >"$_HI_ROOT/hi.cwd" && printf '%s\n' "$name" >"$_HI_ROOT/hi.hold"; }; then
    _hi_die "--keep: could not write to $_HI_ROOT"
  fi
  _hi_cecho "hi: no tmux, zellij, or screen here: a dropped link leaves this session's files for ${_HI_KEEP_TIMEOUT:-15m}, and hi $as comes back to them" "$YELLOW"
}

# _hi_keep_record <outvar> - where this client notes that the target holds a
# kept session: an empty file in hi's runtime directory, named for the
# connection, so a logout forgets it. False with no such directory.
function _hi_keep_record() {
  local _hi_kr_dir _hi_kr_key
  _hi_runtime_dir _hi_kr_dir
  [ -n "$_hi_kr_dir" ] || return 1
  _hi_conn_key _hi_kr_key
  printf -v "$1" '%s/hi.kept.%s' "$_hi_kr_dir" "$_hi_kr_key"
}

# _hi_keep_alive - a keepalive, into the caller's retry array, for a connect
# that keeps its session or comes back to one: a link that freezes is a drop,
# and so retried, only once ssh says so, and ssh says nothing unasked. Fifteen
# seconds three times over, and only where the ssh config sets no interval of
# its own (`ssh -G`, one fork, on these connects alone); an ssh too old to
# answer that gets none.
function _hi_keep_alive() {
  local _hi_ka
  _hi_keep_starts || [ "${_HI_KEEP_EXPECTED:-}" = 1 ] || return 0
  while read -r _hi_ka; do
    case "$_hi_ka" in
    'serveraliveinterval 0')
      retry+=(-o ServerAliveInterval=15 -o ServerAliveCountMax=3)
      return 0
      ;;
    serveraliveinterval\ *) return 0 ;;
    esac
  done < <(ssh -G ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN" 2>/dev/null)
  return 0
}

# A terminal for a retry to come back to: a connect with none ends at the drop
function _hi_keep_at_tty() {
  [ -t 0 ]
}

# _hi_keep_connect <log> - _say_hi, for a session that may be kept. The
# target's script ends 86 when it leaves a kept session behind and 0 when it
# does not, and the record follows; a connect that keeps writes it up front,
# since a dropped link says nothing. The record is what the next connect's
# script warns by when the session is gone (_hi_keep_attach), and what a
# dropped session is retried by: at a terminal, for $_HI_KEEP_RETRY from the
# drop, each try quiet (its words in <log>) until the target answers. A try that gets in and drops within ten seconds does
# not restart the window. GLOSSARY: HI.65
function _hi_keep_connect() {
  local log="$1" ec rec="" probes=0 window="${_HI_KEEP_RETRY:-5m}" limit t0="" t1 expected=""
  ! _hi_keep_probes || probes=1
  [ "$probes" = 0 ] || _hi_keep_record rec || rec=""
  [ -z "$rec" ] || [ ! -e "$rec" ] || expected=1
  [ -z "$rec" ] || ! _hi_keep_starts || : >"$rec"
  _hi_keep_seconds "$window" limit || window=5m limit=300
  while :; do
    ec=0 t1=$SECONDS _HI_LINK_UP=0 _HI_KEEP_EXPECTED="$expected"
    _say_hi || ec=$?
    if [ "$probes" = 1 ]; then
      case "$ec" in
      86)
        ec=0
        [ -z "$rec" ] || : >"$rec"
        ;;
      0) [ -z "$rec" ] || rm -f "$rec" ;;
      esac
    fi
    { [ "$ec" = 255 ] && [ -n "$rec" ] && [ -e "$rec" ] && ((limit > 0)) && _hi_keep_at_tty; } || break
    if [ "$_HI_LINK_UP" = 1 ] && { [ -z "$t0" ] || ((SECONDS - t1 >= 10)); }; then
      t0=$SECONDS
      [ ! -t 1 ] || _hi_reset_terminal "$ec"
      _hi_cecho " hi: lost [$DOMAIN], where the session is kept - retrying for $window, Ctrl+C stops" "$YELLOW" >&2
    elif [ -z "$t0" ]; then
      break
    elif ((SECONDS - t0 >= limit)); then
      _hi_cecho "hi: [$DOMAIN] did not come back in $window; a later hi to it reattaches the session it kept" "$YELLOW" >&2
      _HI_SAID=1
      break
    fi
    sleep 5
    expected=1 _HI_CONNECT_T0="$(_hi_now)" _HI_KEEP_QUIET="$log"
  done
  _HI_KEEP_QUIET=""
  return "$ec"
}
