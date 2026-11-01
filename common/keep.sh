#!/usr/bin/env bash
# The kept session (GLOSSARY: HI.65), both halves, in a file the switch
# ($_HI_DISABLE_KEEP) leaves home: hi.sh and load.sh each source it, with
# stand-ins for a tree that came without.
#
# The client's half is first: which connects look for one and which start
# one, the sh those put on a target - the reattach, the owner pane's start,
# the sweep, a held tree's take - `hi --end`, `hi --keep` typed in a session,
# the client's record, and the retry of a dropped link. Its functions read
# hi.sh's parsed state ($DOMAIN, $KEEP, $CMDARG, $SSHARGS) and call its
# helpers, and _hi_keep_connect runs its _say_hi; like hi.sh, most of it is a
# script assembled for another machine (SC2016, SC2029). The target's half
# follows, for load.sh: a session's claim on its tree, and the owner pane's
# watch, panes, and exit.
#
# What a session leaves in its tree, each file's words, and who reads it:
#   hi.pid       <pid>: a disposable session's claim - the sweep, the watcher
#   hi.kept      <pane pid> <outer shell pid, or -> <name>: an owner pane's
#                claim - the sweep, clean_all, the bootstrap's trap
#   hi.hold      <name>: this session holds its tree through a drop - clean_all,
#                the prompt hooks, the bootstrap's trap
#   hi.held      <watcher pid> <shell pid> <name>: a dropped session's tree, on
#                its timer - the sweep, the connect that takes it, hi --end
#   hi.end       empty: hi --end's word to that timer
#   hi.cwd       <directory>: where a holding session is - the taking connect
#   hi.keep      NAME=value lines: what `hi --keep` typed in the session starts
#                its pane with - _hi_keep_here, common/mux.sh
#   hi.pane      the launcher a kept session's other panes open on
#   hi.keep.kdl  zellij's layout for the owner pane
# shellcheck disable=SC2016,SC2029

# What an owner pane is handed beside the client's verdicts, by a connect
# (_hi_keep_start) or from a session's hi.keep (_hi_keep_file)
_HI_KEEP_PANE_VARS=(_HI_ROOT _HI_CLEANUP _HI_CONNECT_PREFIX _HI_CONNECT_TIME _HI_COPY_TIME)

# _hi_keep_seconds <duration> <outvar> - <n>, or <n> with s, m, h, or d, as
# seconds; false for anything else
function _hi_keep_seconds() {
  local _hi_kd_n="${1%[smhd]}" _hi_kd_u="${1#"${1%?}"}"
  case "$_hi_kd_n" in '' | *[!0-9]*) return 1 ;; esac
  _hi_kd_n=$((10#$_hi_kd_n))
  case "$_hi_kd_u" in
  m) _hi_kd_n=$((_hi_kd_n * 60)) ;;
  h) _hi_kd_n=$((_hi_kd_n * 3600)) ;;
  d) _hi_kd_n=$((_hi_kd_n * 86400)) ;;
  esac
  printf -v "$2" '%s' "$_hi_kd_n"
}

# Is one of $_HI_MUXES installed here
function _hi_mux_here() {
  local m
  for m in $_HI_MUXES; do ! command -v "$m" >/dev/null 2>&1 || return 0; done
  return 1
}

# The session name for a target and the user connecting to it: every
# character tmux's rules reject, or that reads badly in a status line,
# becomes `-`, and the client's username ends it as a hash, since a session
# name sits in the target's process table, which never learns the operator's
# (GLOSSARY: HI.47). `ctx:ns:pod/ctr` -> `hi-ctx-ns-pod-ctr-<hash>`. So two
# people on one account of a target keep sessions of their own, and one
# person comes back to theirs from any machine.
# _hi_mux_name <target> [outvar]
function _hi_mux_name() {
  local _hi_mn_u _hi_mn_h
  _hi_local_username _hi_mn_u
  _hi_hash "$_hi_mn_u" _hi_mn_h
  printf -v _hi_mn_h '%x' "$_hi_mn_h"
  _hi_out "${2:-}" "hi-${1//[^[:alnum:]_-]/-}-$_hi_mn_h"
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
  local target_q _hi_esc _hi_nc gone="" any="" m
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  for m in $_HI_MUXES; do any="$any${any:+ || }command -v $m"; done
  [ "${_HI_KEEP_EXPECTED:-}" != 1 ] ||
    gone="      _hi_kept || ! { $any; } >/dev/null 2>&1 || printf '%s hi: the kept session on [%s] is gone %s\\n' \"$_hi_esc\" $target_q \"$_hi_nc\" >&2"$'\n'
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
# open new panes on the launcher _hi_keep_panes writes, and turn
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
    vars+=("${_HI_KEEP_PANE_VARS[@]}")
  fi
  for n in "${vars[@]}"; do
    argv="$argv $n=\"\$$n\""
    [ "$n" = NO_COLOR ] || drop="$drop $n"
  done
  drop="$drop _HI_KEEP_AS _HI_KEEP_WITH"
  cat <<REMOTE
        _hi_k=
        for _hi_s in $_HI_MUXES; do [ "\$_hi_s" = "\${_HI_KEEP_WITH:-\$_hi_s}" ] && command -v "\$_hi_s" >/dev/null 2>&1 && { _hi_k=\$_hi_s; break; }; done
        if [ -n "\$_hi_k" ] && [ -t 0 ]; then
          set -- env _HI_KEEP_MUX="\$_hi_k" _HI_KEEP_NAME="\$_hi_kn" _HI_HOME="\$_HI_HOME" _HI_CONFIG_DIR="\$_HI_CONFIG_DIR"$argv bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
          (
            unset$drop
            case \$_hi_k in
            tmux) set -- new-session -s "\$_hi_kn" "\$@" ;;
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
              ;;
            screen) set -- -S "\$_hi_kn" "\$@" ;;
            esac
            exec sh "\$_hi_rc_dir/common/mux.sh" "\$_hi_k" "\$@"
          )
          _hi_kept_note '$note'
        else
          [ -n "\$_hi_k" ] || { export _HI_KEEP_HOLD="\$_hi_kn" && trap : HUP; }
          bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
        fi
REMOTE
}

# _hi_keep_middle - the kept session's parts of _hi_remote_middle, into its
# locals: the sweep and a held tree's take after the root is made ($sweep),
# the trap's test for a tree the session leaves to its owner pane or its
# timer ($kept), and the unpack skipped for a held tree ($fresh ... $fi)
# shellcheck disable=SC2034 # the caller's locals
function _hi_keep_middle() {
  _hi_keep_probes || return 0
  sweep="$(_hi_keep_sweep)"$'\n'"$(_hi_keep_held)"
  # shellcheck disable=SC2016 # the target's to expand
  fresh='      if [ -z "$_hi_held" ]; then' fi='      fi'
  # shellcheck disable=SC2016 # the target's to expand, when the trap runs
  kept='[ -e "$_HI_ROOT/hi.kept" ] || [ -e "$_HI_ROOT/hi.hold" ] || '
  # shellcheck disable=SC2016
  ! _hi_keep_starts || kept='_hi_kept || [ -e "$_HI_ROOT/hi.hold" ] || '
}

# What a connect that looks for a kept session runs once it has a tree of its
# own. A session killed with no exit hook - the target went down under it -
# left its tree, and its claim in it (_hi_keep_claim): hi.kept, an
# owner pane's pid and that of the shell it was kept from, or hi.pid, any
# other session's, or hi.held, the watcher's of a tree a drop left to its
# timer and the shell's that left it (load.sh's clean_all). A tree no process
# of its claim still runs on is removed, and one a kept session or a timer
# claims is that claim's alone - but for the session $_hi_endname names, which
# hi --end has just ended: its tree goes whatever its panes are still doing,
# since a multiplexer may end them late or without a hangup. GLOSSARY: HI.65
function _hi_keep_sweep() {
  # shellcheck disable=SC2016 # the target's to expand
  printf '%s\n' \
    '      for _hi_s in "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.kept "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.held "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.pid; do' \
    '        case "$_hi_s" in */hi.pid) [ ! -e "${_hi_s%pid}kept" ] && [ ! -e "${_hi_s%pid}held" ] || continue ;; esac' \
    '        read -r _hi_ko _hi_kp _hi_kh 2>/dev/null <"$_hi_s" && [ -n "$_hi_ko" ] || continue' \
    '        [ "$_hi_kh" = "${_hi_endname:-/}" ] || ! { kill -0 "$_hi_ko" 2>/dev/null || kill -0 "${_hi_kp:-$_hi_ko}" 2>/dev/null; } || continue' \
    '        rm -rf "${_hi_s%/say-hi/hi.*}"' \
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
    '        rmdir "$_HI_ROOT" "$_HI_HOME/hi.probes" "$_HI_HOME"' \
    '        export _HI_HOME="$_hi_d" _HI_ROOT="$_hi_d/say-hi" _HI_CONFIG_DIR="$_hi_d/say-hi/config" _HI_CLEANUP="$_hi_d" _HI_KEEP_HOLD="$_hi_kn"' \
    '        _hi_held=1' \
    '        trap : HUP' \
    '        ! IFS= read -r _hi_s <"$_HI_ROOT/hi.cwd" || cd "$_hi_s" 2>/dev/null || :' \
    '        break' \
    '      done'
}

# What `hi --end` runs on the target: 3 when there is no kept session to
# close. The owner pane's bash takes the hangup and its exit hook removes the
# tree, as on a dropped connection. That hook may never run: zellij sends a
# layout's command SIGTERM and then SIGKILL as its server goes, and an
# interactive bash ignores the first. So the script waits, two seconds at
# most, for one of the panes that were running to go, then sweeps as a
# connect does (_hi_keep_sweep), and its status stays the kill's. A tree a
# drop left to its timer is ended through that timer's watcher, which hi.end
# tells to stop waiting.
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
      _hi_live() { read -r _hi_ko _hi_kp 2>/dev/null <"\$1" && kill -0 "\$_hi_ko" 2>/dev/null; }
      _hi_d=\$(mktemp -d -t $tmpl) && rmdir "\$_hi_d" || _hi_d=
      set --
      [ -z "\$_hi_d" ] || for _hi_s in "\${_hi_d%.hi.*}".hi.*/say-hi/hi.kept; do
        ! _hi_live "\$_hi_s" || set -- "\$@" "\$_hi_s"
      done
$(declare -f _hi_mux_kill)
      _hi_mux_kill "\$_hi_k" "\$_hi_kn" "\$_hi_ks"
      _hi_e=\$?
      _hi_n=0
      while [ \$# -gt 0 ] && [ \$_hi_n -lt 10 ]; do
        for _hi_s; do _hi_live "\$_hi_s" || break 2; done
        _hi_n=\$((_hi_n + 1))
        sleep 0.2 2>/dev/null || sleep 1
      done
      [ -z "\$_hi_d" ] || {
        _HI_HOME=\$_hi_d _hi_endname=\$_hi_kn
$(_hi_keep_sweep)
      }
      (exit "\$_hi_e")
REMOTE
}

# hi --end <target>: close the kept session there, without attaching, through
# _hi_keep_end [arm]'s probe (ssh when empty)
function _hi_keep_end() {
  local ec=0 rec
  # shellcheck disable=SC2034 # _hi_transport_cmds reads and fills these
  local -a probe cp attach ctl_opts=()
  _hi_transport_cmds "${1:-ssh}"
  _hi_on_target probe "$(_hi_keep_end_script)" </dev/null || ec=$?
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
# a keeping connect runs from where it starts the pane. load() left what the
# pane needs in hi.keep, a NAME=value a line, the target's name among them.
# The hi.kept marker is the pane's claim on the tree: this session's exit
# leaves the tree to it (load.sh's clean_all). A multiplexer typed bare in a
# session comes here too (common/mux.sh), naming itself in $_HI_KEEP_WITH,
# and is the one started where the name is one of the three. GLOSSARY: HI.65
function _hi_keep_here() {
  local file="$_HI_ROOT/hi.keep" line with=""
  ! _hi_list_has "$_HI_MUXES" "${_HI_KEEP_WITH:--}" || with="$_HI_KEEP_WITH"
  local -a vars=()
  [ -r "$file" ] || _hi_die "--keep: nothing to keep here - it takes a session hi connected, into bash, started without --no-keep"
  [ -t 0 ] || _hi_die "--keep needs a terminal"
  [ -z "${TMUX:-}${ZELLIJ:-}${STY:-}" ] || _hi_die "--keep: already inside a multiplexer here, and hi does not nest one"
  if ! _hi_mux_here; then
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
# hook, its prompt hooks, and its bootstrap's trap read
# (_hi_keep_holds), and the directory it is in now is noted for it. Refused
# where the session could not hold: a window of 0.
function _hi_keep_hold_here() {
  local line as="" name limit=0 _HI_LOCAL_USER="${_HI_LOCAL_USER:-}"
  # the client's username, which names the session, rode the file too
  while IFS= read -r line; do
    case "${line%%=*}" in
    _HI_KEEP_AS) as="${line#*=}" ;;
    _HI_LOCAL_USER) _HI_LOCAL_USER="${line#*=}" ;;
    esac
  done <"$1"
  _hi_keep_seconds "${_HI_HOLD_TIMEOUT:-$_HI_HOLD_TIMEOUT_DEFAULT}" limit || _hi_keep_seconds "$_HI_HOLD_TIMEOUT_DEFAULT" limit
  if [ -z "$as" ] || ((limit <= 0)); then
    _hi_die "--keep needs tmux, zellij, or screen on this machine, or a _HI_HOLD_TIMEOUT over 0 to hold its files by"
  fi
  _hi_mux_name "$as" name
  if ! { printf '%s\n' "$PWD" >"$_HI_ROOT/hi.cwd" && printf '%s\n' "$name" >"$_HI_ROOT/hi.hold"; }; then
    _hi_die "--keep: could not write to $_HI_ROOT"
  fi
  _hi_cecho "hi: no tmux, zellij, or screen here: a dropped link leaves this session's files for ${_HI_HOLD_TIMEOUT:-$_HI_HOLD_TIMEOUT_DEFAULT}, and hi $as comes back to them" "$YELLOW"
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

# A terminal for the wait to draw its dots on
function _hi_keep_live() {
  [ -t 2 ]
}

# _hi_keep_until <outvar> - ", where the session is kept for <how long> until
# <when that is>", for the line a drop leaves. How long is what the target
# reads: $_HI_KEEP_TIMEOUT (24h) for a session in a multiplexer, and
# $_HI_HOLD_TIMEOUT (15m) for a directory held where there is none
# ($_HI_TARGET_MUX, the boot probe's word); 0, a multiplexer's session with
# no end and no held directory at all. No time where date gives none.
function _hi_keep_until() {
  local span secs at fmt='%H:%M' mux="${_HI_TARGET_MUX:-1}" def
  if [ "$mux" = 1 ]; then
    def="$_HI_KEEP_TIMEOUT_DEFAULT" span="${_HI_KEEP_TIMEOUT:-$_HI_KEEP_TIMEOUT_DEFAULT}"
  else
    def="$_HI_HOLD_TIMEOUT_DEFAULT" span="${_HI_HOLD_TIMEOUT:-$_HI_HOLD_TIMEOUT_DEFAULT}"
  fi
  _hi_keep_seconds "$span" secs || { span="$def" && _hi_keep_seconds "$span" secs; }
  printf -v "$1" '%s' ""
  ((secs > 0)) || [ "$mux" = 1 ] || return 0
  printf -v "$1" '%s' ", where the session is kept"
  ((secs > 0)) || return 0
  ((secs < 86400)) || fmt='%a %H:%M'
  at=$(($(date +%s) + secs))
  # GNU and busybox read @<seconds>, BSD -r <seconds>
  at="$(date -d "@$at" "+$fmt" 2>/dev/null || date -r "$at" "+$fmt" 2>/dev/null)" || at=""
  printf -v "$1" ', where the session is kept for %s%s' "$span" "${at:+ until $at}"
}

# The five seconds between tries: at a terminal a dot a second, the fifth as
# the try starts, on a line each wait starts over
function _hi_keep_wait() {
  local n
  _hi_keep_live || {
    sleep 5
    return 0
  }
  printf '\r\033[K ' >&2
  for n in 1 2 3 4 5; do
    sleep 1
    _hi_cecho . "$YELLOW" - >&2
  done
}

# _hi_keep_connect <log> [arm] - _say_hi, for a session that may be kept. The
# target's script ends 86 when it leaves a kept session behind and 0 when it
# does not, and the record follows; a connect that keeps writes it up front,
# since a dropped link says nothing. The record is what the next connect's
# script warns by when the session is gone (_hi_keep_attach), and what a
# dropped session is retried by: at a terminal, for $_HI_KEEP_RETRY from the
# drop, each try quiet (its words in <log>) until the target answers. A try
# that gets in and drops within ten seconds does not restart the window. Only
# ssh's drop is retried: a container's exec that ends is not a link that
# went. GLOSSARY: HI.65
function _hi_keep_connect() {
  local log="$1" arm="${2:-ssh}" ec rec="" window="${_HI_KEEP_RETRY:-$_HI_KEEP_RETRY_DEFAULT}" limit t0="" t1 expected="" until
  ! _hi_keep_probes || _hi_keep_record rec || rec=""
  [ -z "$rec" ] || [ ! -e "$rec" ] || expected=1
  [ -z "$rec" ] || ! _hi_keep_starts || : >"$rec"
  _hi_keep_seconds "$window" limit || { window="$_HI_KEEP_RETRY_DEFAULT" && _hi_keep_seconds "$window" limit; }
  while :; do
    ec=0 t1=$SECONDS _HI_LINK_UP=0 _HI_KEEP_EXPECTED="$expected"
    _say_hi "$arm" "$log" || ec=$?
    if _hi_keep_probes; then
      case "$ec" in
      86)
        ec=0
        [ -z "$rec" ] || : >"$rec"
        ;;
      0) [ -z "$rec" ] || rm -f "$rec" ;;
      esac
    fi
    { [ "$ec" = 255 ] && [ "$arm" = ssh ] && [ -n "$rec" ] && [ -e "$rec" ] && ((limit > 0)) && _hi_keep_at_tty; } || break
    if [ "$_HI_LINK_UP" = 1 ] && { [ -z "$t0" ] || ((SECONDS - t1 >= 10)); }; then
      t0=$SECONDS
      [ ! -t 1 ] || _hi_reset_terminal "$ec"
      _hi_keep_until until
      _hi_cecho " hi: lost [$DOMAIN]$until - retrying for $window, Ctrl+C stops" "$YELLOW" >&2
    elif [ -z "$t0" ]; then
      break
    elif ((SECONDS - t0 >= limit)); then
      ! _hi_keep_live || printf '\r\033[K' >&2
      _hi_cecho "hi: [$DOMAIN] did not come back in $window; a later hi to it reattaches the session it kept" "$YELLOW" >&2
      _HI_SAID=1
      break
    fi
    _hi_keep_wait
    expected=1 _HI_CONNECT_T0="$(_hi_now)" _HI_KEEP_QUIET="$log"
  done
  _HI_KEEP_QUIET=""
  return "$ec"
}

# What `hi --keep` typed in this session starts its owner pane with, a
# NAME=value a line for _hi_keep_here: the target's name as the client typed
# it, the client's verdicts, the tree, and this shell, whose
# exit that pane waits out before it removes the tree. GLOSSARY: HI.65
function _hi_keep_file() {
  local v
  for v in _HI_KEEP_AS "${_HI_SESSION_VARS[@]}" NO_COLOR "${_HI_KEEP_PANE_VARS[@]}"; do
    [ -z "${!v-}" ] || printf '%s=%s\n' "$v" "${!v}"
  done
  printf '_HI_KEEP_OUTER=%s\n' "$$"
}

# A session's claim on its tree. An owner pane's is hi.kept: its pid, then
# that of the shell it was kept from. Any other session of a disposable tree
# leaves its pid in hi.pid. A later connect reads both
# (_hi_keep_sweep) and removes the tree of a session that died with no exit
# hook. GLOSSARY: HI.65
function _hi_keep_claim() {
  if [ -n "${_HI_KEEP_MUX:-}" ]; then
    printf '%s %s %s\n' "$$" "${_HI_KEEP_OUTER:--}" "${_HI_KEEP_NAME:-}" >"$_HI_ROOT/hi.kept"
  elif [[ -n "${_HI_CLEANUP:-}" && "$_HI_ROOT" == "$_HI_CLEANUP"/* ]]; then
    # only into a tree this session may remove: never an install's
    printf '%s\n' "$$" >"$_HI_ROOT/hi.pid"
  fi
}

# Whether this session may hold its tree through a drop: not an owner pane,
# the tree a disposable one, a terminal to lose, and a window to hold it for,
# into $_hi_keep_limit - $_HI_HOLD_TIMEOUT in seconds (15m), and 0 holds
# nothing. It does hold once hi.hold names it:
# load() writes that for a connect that asked ($_HI_KEEP_HOLD, where a
# keeping connect found no multiplexer or took a held tree), and `hi --keep`
# typed in the session writes it later. GLOSSARY: HI.65
function _hi_keep_holds() {
  _hi_keep_limit=0
  [[ -z "${_HI_KEEP_MUX:-}" && -n "${_HI_CLEANUP:-}" && "$_HI_ROOT" == "$_HI_CLEANUP"/* ]] && [ -t 0 ] || return 1
  _hi_keep_seconds "${_HI_HOLD_TIMEOUT:-$_HI_HOLD_TIMEOUT_DEFAULT}" _hi_keep_limit || _hi_keep_seconds "$_HI_HOLD_TIMEOUT_DEFAULT" _hi_keep_limit
  ((_hi_keep_limit > 0))
}

# _hi_keep_claimed <file> <pid> <field> - is <pid> the <field>th word of the
# claim <file> in this tree?
function _hi_keep_claimed() {
  local a="" b=""
  read -r a b _ 2>/dev/null <"$_HI_ROOT/$1" || return 1
  case "$3" in 1) [ "$a" = "$2" ] ;; *) [ "$b" = "$2" ] ;; esac
}

# The target's half, which load.sh calls. A kept session runs load() in the owner pane of a tmux,
# zellij, or screen session _hi_keep_start put it in: $_HI_KEEP_MUX names the multiplexer
# and $_HI_KEEP_NAME the session. The three functions below are that pane's.

# Is a client attached to the session this pane owns? zellij lists its
# clients a line each under a header. With no header to read - a zellij too
# old to list them, or one still starting, which answers with nothing - it
# counts as attached, so nothing closes a session somebody may be in.
function _hi_keep_attached() {
  local n
  case "${_HI_KEEP_MUX:-}" in
  tmux)
    n="$(tmux display-message -p -t "=$_HI_KEEP_NAME:" '#{session_attached}' 2>/dev/null)"
    [ "${n:-0}" != 0 ]
    ;;
  zellij)
    n="$(zellij --session "$_HI_KEEP_NAME" action list-clients 2>/dev/null)" || return 0
    [[ "$n" != CLIENT_ID* || "$n" == *$'\n'* ]]
    ;;
  screen) screen -ls 2>/dev/null | grep -F "${STY:-.$_HI_KEEP_NAME}" | grep -F '(Attached)' >/dev/null ;;
  *) return 1 ;;
  esac
}

# The timeout: a background job of the owner pane that ends the session once
# no client has been attached for $_HI_KEEP_TIMEOUT (24h; 0 is never). The
# pane takes the hangup and its exit hook removes the tree, so nothing of
# hi's outlives the session. <step> is the poll, a test's to shorten.
function _hi_keep_watch() {
  local limit step="${1:-60}" idle=0
  [ -n "${_HI_KEEP_NAME:-}" ] || return 0
  _hi_keep_seconds "${_HI_KEEP_TIMEOUT:-$_HI_KEEP_TIMEOUT_DEFAULT}" limit || _hi_keep_seconds "$_HI_KEEP_TIMEOUT_DEFAULT" limit
  ((limit > 0)) || return 0
  ((step <= limit)) || step="$limit"
  (
    while sleep "$step"; do
      if _hi_keep_attached; then
        idle=0
      else
        idle=$((idle + step))
        ((idle < limit)) || break
      fi
    done
    ! declare -F _hi_clean_tree >/dev/null || _hi_clean_tree
    _hi_keep_kill
  ) </dev/null >/dev/null 2>&1 &
  _hi_keep_watch_pid=$!
}

# _hi_mux_kill <tool> <name> <screen id> - end a session, every pane of it.
# POSIX sh: _hi_keep_end_script sends it as written (declare -f).
function _hi_mux_kill() {
  case "$1" in
  tmux) tmux kill-session -t "=$2" ;;
  zellij) zellij kill-session "$2" ;;
  screen) screen -S "$3" -X quit ;;
  esac
}

# End the session this pane owns.
function _hi_keep_kill() {
  _hi_mux_kill "$_HI_KEEP_MUX" "$_HI_KEEP_NAME" "${STY:-$_HI_KEEP_NAME}"
}

# _hi_keep_panes <session shell command...> - the session's other panes. A
# multiplexer opens each on its default shell, the host's own, which reads
# none of hi's rc (GLOSSARY: HI.46). So the owner pane leaves a launcher
# beside the rc - what load() exported for the session shell, then that shell
# - and names it the session's: tmux's default-command and screen's shell,
# set here for this session alone; zellij takes a default shell at its start
# only, where _hi_keep_start named this path. $SHELL is written back since screen
# hands a window its `shell` as $SHELL. GLOSSARY: HI.65
function _hi_keep_panes() {
  local v q file="$_HI_ROOT/hi.pane"
  [ -n "${_HI_KEEP_MUX:-}" ] || return 0
  {
    printf '#!%s\n' "$BASH"
    for v in "${_HI_CHILD_ENV[@]}" ZDOTDIR ENV VIMINIT EDITOR SUDO_EDITOR VISUAL NO_COLOR SHELL; do
      [ -n "${!v+x}" ] || continue
      printf -v q '%q' "${!v}"
      printf 'export %s=%s\n' "$v" "$q"
    done
    # the overlay's bin/, which the multiplexer's server never had on $PATH
    if [ -n "${_HI_CONFIG_DIR:-}" ] && [ -d "$_HI_CONFIG_DIR/bin" ]; then
      printf -v q '%q' "$_HI_CONFIG_DIR/bin"
      # shellcheck disable=SC2016 # the launcher's to expand
      printf 'export PATH="$PATH":%s\n' "$q"
    fi
    printf 'exec'
    printf ' %q' "$@"
    printf '\n'
  } >"$file" && chmod +x "$file" || return 0
  case "$_HI_KEEP_MUX" in
  tmux)
    # run by tmux's default-shell, whichever that is: %q's backslashes are
    # the one quoting sh, zsh, and fish all read. The colon: set-option's
    # target is a pane, and takes the session's exact name only before one.
    printf -v q '%q' "$file"
    tmux set-option -t "=$_HI_KEEP_NAME:" default-command "$q" >/dev/null 2>&1
    # closing the session ends the connect, whatever the config rode with
    tmux set-option -t "=$_HI_KEEP_NAME:" detach-on-destroy on >/dev/null 2>&1
    ;;
  screen) screen -S "${STY:-$_HI_KEEP_NAME}" -X shell "$file" >/dev/null 2>&1 ;;
  esac
  return 0
}

# Asked when the owner pane's shell exits with a client attached, since an
# `exit` typed from habit would otherwise end every pane. True to stay: the
# client is detached and load() starts a fresh shell. zellij has no command
# that detaches a client, so there the fresh shell comes with the key that
# does. With nobody attached there is nobody to ask, and the session closes.
function _hi_keep_stays() {
  local reply=""
  [ -n "${_HI_KEEP_NAME:-}" ] && [ -t 0 ] && _hi_keep_attached || return 1
  _hi_cecho " hi: close the kept session? [y/N] " "$YELLOW" 1
  read -r reply || return 1
  case "$reply" in [yY]*) return 1 ;; esac
  case "$_HI_KEEP_MUX" in
  tmux) tmux detach-client -s "=$_HI_KEEP_NAME" ;;
  zellij) _hi_cecho " hi: kept - zellij's own key detaches, Ctrl+o d unless rebound" "$YELLOW" ;;
  screen) screen -S "${STY:-$_HI_KEEP_NAME}" -X detach ;;
  esac
  return 0
}
