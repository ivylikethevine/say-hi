#!/usr/bin/env bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies say-hi to the target and chainloads load.sh there.
#
# File-scope: almost everything here is a script assembled for *another*
# machine, so a `$var` in single quotes is the target's to expand (SC2016) and
# a command string sent to ssh is expanded here on purpose (SC2029).
# shellcheck disable=SC2016,SC2029
set -euo pipefail # off again below: this file is sourced by the interactive shell, where an error would close the session

# $_HI_HOME is the directory *containing* say-hi, derived from this script's
# own path behind a symlink walk (/usr/bin/hi -> <prefix>/say-hi/hi.sh). The
# same walk as scripts/install.sh's and packaging/lib.sh's: fix one, fix all.
# GLOSSARY: HI.33
if [ -z "${_HI_HOME:-}" ]; then
  _hi_self="${BASH_SOURCE[0]}"
  while [ -L "$_hi_self" ]; do
    _hi_link="$(readlink "$_hi_self")"
    case "$_hi_link" in
    /*) _hi_self="$_hi_link" ;;
    *) case "$_hi_self" in
      */*) _hi_self="${_hi_self%/*}/$_hi_link" ;;
      *) _hi_self="$_hi_link" ;;
      esac ;;
    esac
  done
  _HI_HOME="$(cd -P "$(dirname "$_hi_self")/.." && pwd)"
  unset _hi_self _hi_link
fi
export _HI_HOME
# checked before the source: bash's own "No such file" would name a path
# nobody typed. No _hi_cecho - core.sh is the file that's gone.
[ -r "$_HI_HOME/say-hi/common/core.sh" ] || {
  echo "hi: no say-hi at $_HI_HOME/say-hi - set _HI_HOME to the directory that holds it" >&2
  exit 1
}
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"

_HI_RELEASE="${_HI_RELEASE:-}"

# The synopsis, kept identical to docs/hi.1's .SH SYNOPSIS
_HI_USAGE="Usage: hi [ssh-options] <target> [command ...]"

# What ships to a target - an allow list. hi.sh is in it so a disposable
# session has a launcher to relay onward with (~14KB of wire inside the tar).
_HI_PAYLOAD=(common settings load.sh hi.sh)

# The user's config overlay: a second, smaller stream into its own config/ on
# the target. GLOSSARY: HI.41 - why its own directory, why the editor rcs ride
_HI_OVERLAY_FILES=(settings.sh colors packages vim.rc nano.rc aliases.sh
  bash.sh zsh.zsh config.fish)

# What a bash-less target falls back to, best first: core.sh's $_HI_SHELL_TREE
# minus bash, derived so the two orderings cannot drift.
export _HI_SHELL_LADDER="${_HI_SHELL_TREE//bash /}"

# stands in for the connect line's size until the script is measured; wider
# than any figure. GLOSSARY: HI.44
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: HI.17 - why base64 over openssl, the -d/-D ladder, and the
# `tr` fold $_HI_UNARMOR puts in front of the decode (armor that arrived as an
# argv word could be space-folded; the stdin transport needs no fold)
_HI_ARMOR="base64"
_HI_UNARMOR="tr -s ' ' '\n' | { base64 -d 2>/dev/null || base64 -D; }"

function _hi_armored_line() {
  printf 'echo "%s" | %s %s %s' "$($_HI_ARMOR)" "$_HI_UNARMOR" "$1" "$2"
}

# _hi_shquote <var> <value> - <value> as one single-quoted sh word, into <var>.
# Every value baked into a target's script goes through here.
# GLOSSARY: HI.40 - why a hand loop and not ${2//...}, and what it prevents
function _hi_shquote() {
  local _s="$2" _o=""
  while [ "${_s#*\'}" != "$_s" ]; do
    _o="$_o${_s%%\'*}'\\''"
    _s="${_s#*\'}"
  done
  printf -v "$1" "'%s'" "$_o$_s"
}

# The client-derived env both transports export into the session, one
# NAME<TAB>value pair per line (_hi_env_each renders it per transport)
function _hi_session_env() {
  printf '_HI_TARGET\t%s\n' "$DOMAIN"
  printf '_HI_TARGET_COLOR\t%s\n' "$(_hi_target_color)"
  printf '_HI_TARGET_TAG\t%s\n' "$(_hi_ssh_host_tag "$DOMAIN" 2>/dev/null || true)"
  printf '_HI_LOCAL_USER\t%s\n' "$(_hi_whoami)"
  printf '_HI_LOCAL_HOSTNAME\t%s\n' "$(_hi_hostname)"
  printf '_HI_RELEASE\t%s\n' "$(_hi_version)"
  # the client's glyph verdict, not the target's: see _hi_ascii_flag
  printf '_HI_ASCII\t%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
  # the client's no-color choice travels the same way (nothing when unset,
  # which is the value https://no-color.org gives no meaning to)
  [ -n "${NO_COLOR:-}" ] && printf 'NO_COLOR\t1\n'
  return 0
}

# memoized: three callers, $DOMAIN is fixed for the run
function _hi_target_color() {
  [ "${_HI_TARGET_COLOR_MEMO+x}" = x ] ||
    _HI_TARGET_COLOR_MEMO="$(_hi_resolve_color hostname "${DOMAIN##*@}")"
  printf '%s\n' "$_HI_TARGET_COLOR_MEMO"
}

# <toggle>|<tree files, under $_HI_HOME>|<overlay files>: what each settings.sh
# toggle takes off the wire; one table for both halves. GLOSSARY: HI.39
_HI_TRIM_TABLE=(
  "_HI_DISABLE_EDITORS|say-hi/settings/vim.rc say-hi/settings/nano.rc|vim.rc nano.rc"
  "_HI_DISABLE_OSC52|say-hi/common/osc52.sh|"
  "_HI_DISABLE_NOTIFY|say-hi/common/notify.sh|"
)

# _hi_trimmed <tree|overlay> <outvar> - that column of every _HI_TRIM_TABLE row
# whose setting the overlay answers the way the row asks, space-separated, into
# <outvar>.
function _hi_trimmed() {
  local row val out=""
  for row in "${_HI_TRIM_TABLE[@]}"; do
    val=""
    _hi_overlay_toggle "${row%%|*}" val
    # anything that is not a literal 1 is "off"; an absent setting reads empty
    [ "$val" = 1 ] || continue
    row="${row#*|}"
    case "$1" in
    tree) out="$out ${row%%|*}" ;;
    overlay) out="$out ${row#*|}" ;;
    esac
  done
  printf -v "$2" '%s' "$out"
}

# _hi_overlay_files - the overlay members that exist and are not trimmed, one
# per line. Callers read it once and hand the list to _hi_overlay_tar.
function _hi_overlay_files() {
  local f skip=""
  _hi_trimmed overlay skip
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    case " $skip " in *" $f "*) continue ;; esac
    [ -f "$_HI_CONFIG_DIR/$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# tar's own arguments, gzip in a second process rather than `z`: bsdtar pads
# the compressed stream to 10240. GLOSSARY: HI.38 - that, PIPESTATUS, no-gzip
function _hi_tar_gz() {
  local -a st
  if ! command -v gzip >/dev/null 2>&1; then
    tar czf - "$@"
    return $?
  fi
  tar cf - "$@" | gzip -n
  st=("${PIPESTATUS[@]}")
  [ "${st[0]}" = 0 ] || return "${st[0]}"
  [ "${st[1]}" = 0 ] || return "${st[1]}"
  return 0
}

# _hi_overlay_tar [file...] - the overlay archive over the given members, or
# over _hi_overlay_files when called bare; nothing at all when there are none.
function _hi_overlay_tar() {
  local -a present=("$@")
  [ $# -gt 0 ] || _hi_read_lines present < <(_hi_overlay_files)
  ((${#present[@]})) || return 0
  _hi_tar_gz -h -C "$_HI_CONFIG_DIR" "${present[@]}"
}

# _hi_overlay_toggle <name> [outvar] - what the overlay's settings.sh sets it
# to, read from the file rather than off the environment.
# GLOSSARY: HI.36 - why the file and not the environment
function _hi_overlay_toggle() {
  _hi_setting_get "$_HI_CONFIG_DIR/settings.sh" "$@"
}

# The comment stripper every shell file - and the settings/flags data files,
# whose prose headers are for the *installed* copy a user reads, not the wire
# - takes on its way into the payload. vim.rc's comment character is `"`; the
# `#` rule already covers the rest of the data files.
# GLOSSARY: HI.35 - the three rules, and why their order is the whole argument
function _hi_strip_awk() {
  cat <<'AWK'
FNR == 1 { close(out); out = FILENAME ".strip"; tag = ""; dash = 0; vim = (FILENAME ~ /vim\.rc$/) }
FNR == 1 && /^#!/ { print > out; next }
vim && /^[ \t]*"/ { next }
tag != "" {
  line = $0
  if (dash) sub(/^\t+/, "", line)
  if (line == tag) tag = ""
  print > out
  next
}
/^[ \t]*#/ { next }
{
  s = $0
  while (match(s, /<<-?[ \t]*("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|[A-Za-z_][A-Za-z0-9_]*)/)) {
    m = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    dash = (m ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", m)
    sub(/^["']/, "", m)
    sub(/["']$/, "", m)
    tag = m
  }
  print > out
}
AWK
}

# _hi_require <tool> <why> - the tool, or a refusal that names it. Every
# transport needs a handful of binaries that a stripped-down client may not
# have, and "hi: requires tar on [box] ..." is the difference between a
# session that says what is missing and one that prints line numbers.
function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_fail "hi: requires $1 on [$(_hi_hostname)] $2, but it is not installed. Aborting..."
  return 1
}

# _hi_fail <msg> - <msg> in red on stderr, and a mark that hi already said its
# piece: _hi's end-of-connect report reads $_HI_SAID to tell "the transport
# failed silently" from "hi already printed the reason", so a failure is never
# announced twice.
function _hi_fail() {
  _hi_cecho "$1" "$BRRED" >&2
  _HI_SAID=1
}

# The tree minus what the overlay switched off, comment-stripped through a
# staging copy; both size budgets measure a *default* configuration.
# GLOSSARY: HI.39 + HI.35
function _hi_payload_tar() {
  local -a excl=()
  local _hi_trim="" _hi_f
  _hi_trimmed tree _hi_trim
  for _hi_f in $_hi_trim; do excl+=("--exclude=$_hi_f"); done
  # _HI_KEEP_COMMENTS=1 ships the tree verbatim, for reading real source on a
  # target
  if [ "${_HI_KEEP_COMMENTS:-0}" = 1 ]; then
    _hi_tar_gz -h ${excl[@]+"${excl[@]}"} -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/say-hi/}"
    return 0
  fi

  # a subshell, so the stage's cleanup is a trap and a ^C mid-build leaves
  # nothing behind (GLOSSARY: HI.39)
  local stage f
  (
    stage="$(mktemp -d -t hi.stage.XXXXXX)" || exit 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    tar cf - -h ${excl[@]+"${excl[@]}"} -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/say-hi/}" |
      tar xf - -C "$stage" || exit 1
    _hi_strip_awk >"$stage/strip.awk"
    # one awk over every file; _hi_write_back keeps hi.sh's mode. GLOSSARY: HI.09
    find "$stage/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \
      -o -name flags -o -name colors -o -name packages -o -name vim.rc -o -name nano.rc \) \
      -exec awk -f "$stage/strip.awk" {} + || exit 1
    while IFS= read -r f; do
      _hi_write_back "$f" "${f%.strip}"
    done < <(find "$stage/say-hi" -type f -name '*.strip')
    _hi_tar_gz -C "$stage" say-hi
  )
}

# The walker's rc 2 means "known host, no tag"; only 1 means not in the config.
function _hi_is_ssh_host() {
  local rc=0
  _hi_ssh_host_tag "$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 1 ]
}

function _hi_is_container_running() {
  command -v "$1" >/dev/null 2>&1 &&
    [ "$("$1" container inspect -f '{{.State.Running}}' "$2" 2>/dev/null)" = true ]
}

# docker and podman are identical for this
function _hi_is_docker_container() {
  _hi_is_container_running docker "$1" || _hi_compose_container "$1" >/dev/null
}
function _hi_is_podman_container() { _hi_is_container_running podman "$1"; }

# _hi_compose_container <service> - the one running container behind a docker
# compose service name, or failure; never a guess. GLOSSARY: HI.43
function _hi_compose_container() {
  command -v docker >/dev/null 2>&1 || return 1
  local matches
  matches="$(docker ps --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' 2>/dev/null)"
  [ -n "$matches" ] || return 1
  [ "$(printf '%s\n' "$matches" | wc -l)" -eq 1 ] || return 1
  printf '%s\n' "$matches"
}

# _hi_outer / _hi_inner <target> - the where and the what of `pod/container`
# and `alloc/task`; docker and podman names are taken whole. GLOSSARY: HI.43
function _hi_outer() { printf '%s' "${1%%/*}"; }
function _hi_inner() {
  case "$1" in
  */*) printf '%s' "${1#*/}" ;;
  esac
}

function _hi_is_nomad_alloc() {
  command -v nomad >/dev/null 2>&1 &&
    [ "$(nomad alloc status -t '{{.ClientStatus}}' "$(_hi_outer "$1")" 2>/dev/null)" = running ]
}

# _hi_kube_split <target> - `[[context:]namespace:]pod[/container]` into
# _HI_K_POD and the kubectl arguments the prefixes add. GLOSSARY: HI.43
function _hi_kube_split() {
  local outer="${1%%/*}"
  _HI_K_POD="$outer"
  _HI_K_ARGS=()
  case "$outer" in
  *:*:*)
    _HI_K_ARGS+=(--context "${outer%%:*}")
    outer="${outer#*:}"
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    _HI_K_POD="${outer#*:}"
    ;;
  *:*)
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    _HI_K_POD="${outer#*:}"
    ;;
  esac
  return 0
}

# resolves on the pod half; kubectl checks the container half at session time
function _hi_is_k8s_pod() {
  command -v kubectl >/dev/null 2>&1 || return 1
  _hi_kube_split "$1"
  [ "$(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} get pod "$_HI_K_POD" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>". One list
# for _hi's dispatch and scripts/doctor.sh's report.
_HI_BACKENDS=(
  "docker|docker container|docker ps -q|_hi_is_docker_container"
  "podman|podman container|podman ps -q|_hi_is_podman_container"
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# _hi_backend_flag <word> - "docker" for "--docker", "ssh" for "--ssh", or
# nothing: whether <word> names a backend to force rather than probe for.
# Reads $_HI_BACKENDS rather than a second spelling of the roster, so a
# backend added there gets its flag for free; common/flags still carries the
# row each name needs for --help and completion, and
# tests/hi/parse_test.sh checks the two rosters agree.
function _hi_backend_flag() {
  local row
  case "$1" in
  --ssh) printf 'ssh' && return 0 ;;
  esac
  for row in "${_HI_BACKENDS[@]}"; do
    [ "$1" = "--${row%%|*}" ] && printf '%s' "${row%%|*}" && return 0
  done
  return 1
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: HI.18 - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1" q
  shift
  _hi_shquote q "$script"
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c $q"
}

# _hi_ctl_open <persist-secs> [ssh-opts...] - a fresh ControlMaster socket into
# the caller's ctl_dir/ctl_path/ctl_opts, so the install probe and the session
# that follows multiplex one authentication; _hi_ctl_close tears it down.
#
# The socket lives *inside* a `mktemp -d` (0700) rather than at a `mktemp -u`
# name in a shared $TMPDIR. `mktemp -u` only promises the name was free when it
# was printed, and `ControlMaster=auto` *joins* an existing socket at that path
# rather than refusing it - so on a multi-user box the predictable-name form is
# the shape every hardening guide names. The directory is made atomically and
# only this user can traverse it, which makes the socket's own name moot.
#
# "/s", not a second random component: ControlPath goes into a sockaddr_un,
# capped near 104 bytes, and macOS's per-user $TMPDIR already spends ~50 of them.
#
# A host with no writable temp directory gets no multiplexing rather than no
# session: ctl_opts stays empty, ssh authenticates twice, everything still works.
function _hi_ctl_open() {
  ctl_dir=""
  ctl_path=""
  ctl_opts=()
  ctl_dir="$(mktemp -d -t hi.cm.XXXXXX 2>/dev/null)" || ctl_dir=""
  if [ -n "$ctl_dir" ]; then
    ctl_path="$ctl_dir/s"
    ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=$1")
  fi
  shift
  ctl_opts+=("$@")
}

function _hi_ctl_close() {
  [ -n "$ctl_path" ] && ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1
  [ -n "$ctl_dir" ] && rm -rf "$ctl_dir" 2>/dev/null
  return 0
}

# The sh script _hi_remote_root runs on the target: the path of a permanent
# say-hi there, or nothing. Its own function so a suite can run it without an
# ssh hop. GLOSSARY: HI.33 - the candidate order and the two ordered seds
function _hi_remote_root_probe() {
  # core.sh's _HI_SHELL_TABLE home-rc column with the target's $HOME, plus the
  # packaged snippet
  local rcs="" home_rc
  # shellcheck disable=SC2119 # no flag: every row of the roster, unfiltered
  while IFS='|' read -r _ _ _ home_rc _; do
    rcs="$rcs \"\$HOME${home_rc#"$HOME"}\""
  done < <(_hi_shell_rows)
  printf '_c=$(for _f in%s /etc/profile.d/say-hi.sh; do\n' "$rcs"
  cat <<'PROBE'
  [ -f "$_f" ] && sed -n -e 's/^[[:space:]]*export  *_HI_HOME=//p' -e 's/^[[:space:]]*set -gx  *_HI_HOME  *//p' "$_f"
done | sed -e '/^"/!s/[[:space:]]*#.*$//' -e 's/^"\([^"]*\)".*$/\1/' -e 's/[[:space:]]*$//')
IFS='
'
for _h in $_c "$HOME" "$HOME/.local/share" /usr/local/share /opt /usr/share \
  "$HOME/.linuxbrew/opt/say-hi/libexec" /home/linuxbrew/.linuxbrew/opt/say-hi/libexec \
  /opt/homebrew/opt/say-hi/libexec /usr/local/opt/say-hi/libexec; do
  [ -n "$_h" ] || continue
  [ -x "$_h/say-hi/hi.sh" ] && [ -f "$_h/say-hi/common/paths.sh" ] && {
    printf "%s" "$_h/say-hi"
    exit 0
  }
done
PROBE
}

# The sh script the first ssh call runs: check for base64, make a scratch
# directory, take the bootloader off stdin, and say where it went. Its own
# function so a suite can assert on it without an ssh hop, the same reason
# _hi_remote_root_probe is one.
#
# Every path in it is the *target's*. Nothing here interpolates a client-side
# value, and that is the whole point: a client `mktemp -u -t` names a path in
# the client's $TMPDIR and then asks the target to mkdir it - fine while both
# are /tmp, and a session that silently falls through to the PowerShell branch
# the moment the client has $TMPDIR set, which is every macOS login shell.
#
# The two ways it can fail once `sh` is running each say which in the exit
# status - 64 for no base64, 65 for no scratch directory - so _say_hi can name
# the reason and hand over the host's own session. The PowerShell notice is
# for the other shape, where `sh` never ran at all - and telling the two apart
# is why those two lines are `if`s rather than `|| exit N`: stock Windows
# OpenSSH hands the command to cmd.exe, which cannot run `sh` but *does*
# honour `||`, so a `|| exit 64` would have cmd itself exit 64 and hi call a
# Windows box "a host with no base64". As an argument to `sh`, the `if` is
# nothing cmd acts on, and what comes back is cmd's own "not recognized" -
# non-zero with nothing on stdout. GLOSSARY: HI.19
function _hi_boot_probe() {
  cat <<'PROBE'
if ! command -v base64 >/dev/null 2>&1; then exit 64; fi
if ! d=$(mktemp -d -t hi.boot.XXXXXX); then exit 65; fi
cat > "$d/bootloader" || exit 1
printf "\nHIBOOT:%s\n" "$d"
PROBE
}

# A path the target reported, or nothing. What comes back from a target is
# interpolated into a script run back on that same target, so it is refused
# rather than escaped, on the bootstrap directory's rule: absolute, and free of
# anything a double-quoted heredoc expands or closes on. A refusal takes the
# disposable path, which trusts the target for nothing. A space is not hostile
# - an install directory may carry one. Always returns 0: an empty answer is
# the verdict, not an error.
function _hi_trusted_path() {
  case "$1" in
  /*) ;;
  *) return 0 ;;
  esac
  case "$1" in
  *[\"\$\`\\]* | *$'\n'*) return 0 ;;
  esac
  printf '%s' "$1"
}

# _hi_safe_path <path> <bracket-class> - <path> when it is absolute and built
# only from the class's characters, nothing otherwise. The whitelist twin of
# _hi_trusted_path's blacklist, for the scratch directories a target names:
# the value is interpolated into commands run back on that target (`rm -rf`
# among them), so it can only be a path mktemp just made, and anything that is
# not one is refused rather than escaped. The class varies per caller; the
# rule does not. Always returns 0: an empty answer is the verdict.
function _hi_safe_path() {
  case "$1" in
  /*) ;;
  *) return 0 ;;
  esac
  case "$1" in
  *[!$2]*) return 0 ;;
  esac
  printf '%s' "$1"
}

# The one tty decision, as a 1/0 flag. $_HI_TTY answers for `[ -t 0 ]` when it
# is set: hi's own suites have no tty and need a deterministic answer to
# assert either arm against, and it is the escape hatch for a wrapper that
# knows better than the probe does.
function _hi_tty() {
  printf '%s' "${_HI_TTY:-$([ -t 0 ] && echo 1 || echo 0)}"
}

# Prints the path of a permanent say-hi on $DOMAIN, if any.
#
# stderr is deliberately *not* redirected. This is the first of the two calls,
# so it is the one that opens the ControlMaster - which makes it the call that
# carries the server's `Banner`, the "Permanently added ... to the list of known
# hosts" line, and, on a host nobody has met before, the key fingerprint the
# user is being asked to compare. ssh reads the yes/no answer from /dev/tty but
# prints the fingerprint to stderr, so silencing it left the prompt on screen
# with the thing it is a prompt *about* thrown away - trust-on-first-use with
# nothing to base the trust on. The probe's own noise on an odd target is the
# price, and it is the cheaper of the two.
function _hi_remote_root() {
  local out
  out="$(_hi_ssh_sh "$(_hi_remote_root_probe)" \
    "$@" -o ConnectTimeout=5)" || out=""
  printf '%s' "$out"
}

# GLOSSARY: HI.15
function _hi_bootloader() {
  local clear=""
  # The connect marker every arm prints on the way in (" <size>", or
  # "-> local say-hi install", with no newline) is overwritten by the header's
  # banner. A command replaces the header, so it clears the marker itself -
  # a line-clear on a tty, a newline on a pipe, the same two shapes
  # _hi_report_failure uses - or the command's first line of output lands
  # glued to it.
  [ -n "${CMDARG:-}" ] &&
    clear=$'[ -t 2 ] && printf \'\\r\\033[K\' >&2 || printf \'\\n\' >&2\n'
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${clear}${CMDARG:-load}
EOF
}

# The no-bash target's rc: every line valid in sh, zsh *and* fish at once.
# --aliases-only <dir> is the container fallback's shape (aliases.sh alone).
# GLOSSARY: HI.20 - the three-shell subset, and why each line is there
function _hi_fallback_rc() {
  local t aliases_dir=""
  [ "${1:-}" = --aliases-only ] && aliases_dir="$2"
  printf 'export _HI_REMOTE_SESSION=1\n'
  # core.sh's _HI_TOGGLES: an unset one under `set -u` breaks a bash-less target
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  if [ -n "$aliases_dir" ]; then
    # the client verdicts the ssh preamble would have exported ride the rc here
    printf 'export _HI_ASCII=%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
    [ -n "${NO_COLOR:-}" ] && printf 'export NO_COLOR=1\n'
    printf '. %s/aliases.sh 2>/dev/null\n' "$aliases_dir"
  else
    printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
    printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
    printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/settings/aliases.sh 2>/dev/null\n'
  fi
  # no $CMDARG here: the two helpers below hand it to each shell the way that
  # shell honours it (GLOSSARY: HI.23 - fish ignores an `exit` in -C)
  return 0
}

# _hi_command_append <file-word> - the `hi <target> <cmd>` line, armored like
# the rc, appended to <file-word> on the target; nothing without a command.
# For sh and zsh, which read their rc to the end; fish takes the flag below.
function _hi_command_append() {
  [ -n "${CMDARG:-}" ] || return 0
  printf '%s\n' "$CMDARG" | _hi_armored_line '>>' "$1"
}

# _hi_command_fish_flag - ` -c '<cmd>'` for the fish arm, or nothing: fish runs
# -c after -C and exits from it (GLOSSARY: HI.23). Quoted for the target's sh.
function _hi_command_fish_flag() {
  local q
  [ -n "${CMDARG:-}" ] || return 0
  _hi_shquote q "$CMDARG"
  printf ' -c %s' "$q"
}

# The fallback-shell probe both transports interpolate: one sh loop over
# $_HI_SHELL_LADDER running $1 ($_hi_s names the hit) at the first shell found.
function _hi_ladder_probe() {
  printf 'for _hi_s in %s; do command -v "$_hi_s" >/dev/null 2>&1 && { %s; break; }; done' \
    "$_HI_SHELL_LADDER" "$1"
}

# A prompt for the bash-less tiers (sh, ash, dash), baked on the client.
# GLOSSARY: HI.21 - why baked
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # the host lands *inside* PS1's double quotes: escape what would end them
  host="${host//\\/\\\\}"
  host="${host//\$/\\\$}"
  host="${host//\`/\\\`}"
  host="${host//\"/\\\"}"
  # _hi_color_escape already emits real escapes; only $NC is a literal to expand
  printf -v nc '%b' "$NC"
  printf '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}")\n'
  printf 'PS1=" %s${_hi_u}%s@%s%s%s %s "\n' \
    "$(_hi_user_escape)" "$nc" "$(_hi_color_escape "$(_hi_target_color)")" \
    "$host" "$nc" "$(_hi_prompt_end SH)"
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it. GLOSSARY: HI.44 - why not a sum of streams
function _hi_wire_bytes() {
  local hi_esc="" nc_esc="" overlay_line="" bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_tar | $_HI_ARMOR)"
  script="$(_hi_remote_preamble)
$(_hi_remote_middle)
$(_hi_remote_suffix)"
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
}

function _hi_file_bytes() {
  wc -c <"$1" | tr -d ' '
}

function _hi_human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B K M G", unit, " ")
    i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    if (i == 1) printf "%dB", b
    else if (b < 10) printf "%.1f%s", b, unit[i]
    else printf "%.0f%s", b, unit[i]
  }'
}

# core.sh's ladder, plus the diagnostic the header's cell has no room for
function _hi_version() {
  local v
  v="$(_hi_release_or_describe)"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
  elif [ -d "$_HI_ROOT/.git" ]; then
    printf 'unknown (git would not answer)\n'
  else
    printf 'unknown (no stamp, no git)\n'
  fi
}

# _hi_env_each <printf-format> - _hi_session_env's NAME<TAB>value pairs through
# <format>, name then value already quoted (`%s=%s`, never `%s="%s"`); one
# loop for both transports. GLOSSARY: HI.40
function _hi_env_each() {
  local n v q
  while IFS=$'\t' read -r n v; do
    _hi_shquote q "$v"
    # shellcheck disable=SC2059 # the format is ours, not user data
    printf "$1" "$n" "$q"
  done < <(_hi_session_env)
}

# The bit both _say_hi branches need first. Everything expands on the client:
# no backtick or unescaped $( ) below, not even inside a comment. The TERM
# case swaps an unknown TERM for xterm-256color when the target's terminfo
# has no entry for it (GLOSSARY: HI.22) - noted here rather than in the
# heredoc, whose every byte rides the wire on every connect.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
$(_hi_env_each '      export %s=%s\n')
      case "\${_HI_TERM_FALLBACK:-1}:\$TERM" in
      0:* | 1:xterm | 1:xterm-256color | 1:xterm-color | 1:screen | 1:screen-256color | 1:tmux | 1:tmux-256color | 1:linux | 1:vt100 | 1:vt220 | 1:dumb | 1:) ;;
      *)
        _hi_ti_ok=""
        _hi_ti_c=\${TERM%"\${TERM#?}"}
        _hi_ti_x=\$(printf '%x' "'\$_hi_ti_c" 2>/dev/null)
        for _hi_ti_d in "\${TERMINFO:-}" "\$HOME/.terminfo" /etc/terminfo /lib/terminfo /usr/share/terminfo; do
          [ -n "\$_hi_ti_d" ] || continue
          if [ -e "\$_hi_ti_d/\$_hi_ti_c/\$TERM" ] || [ -e "\$_hi_ti_d/\$_hi_ti_x/\$TERM" ]; then
            _hi_ti_ok=1
            break
          fi
        done
        [ -n "\$_hi_ti_ok" ] || export TERM=xterm-256color
        ;;
      esac
REMOTE
}

# What both _say_hi branches need once their setup is done: report copy time,
# then hand off to bash or to the best fallback shell. Expects \$_hi_rc_dir to
# point at wherever hi.bashrc/.hi_fallback_rc lives.
# GLOSSARY: HI.23 - the flag order, and fish's -C arm (its rc goes through -C
# and the command through -c). The `*)` arm (sh/dash/ash) appends the prompt
# there rather than in the shared rc, which also feeds fish (no PS1) and zsh
# (a different \$ escape).
function _hi_remote_suffix() {
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
      else
        _hi_fallback=sh
        $(_hi_ladder_probe '_hi_fallback="$_hi_s"')
        printf '%s no bash on [%s], dropping into plain %s w/ aliases only %s\n' "$hi_esc" "\$_HI_TARGET" "\$_hi_fallback" "$nc_esc" >&2
        $(_hi_fallback_rc | _hi_armored_line '>' '"$_hi_rc_dir/.hi_fallback_rc"')
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          $(_hi_command_append '"$_hi_rc_dir/.zshrc"')
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")"$(_hi_command_fish_flag) ;;
        *)
          $(_hi_fallback_prompt | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          $(_hi_command_append '"$_hi_rc_dir/.hi_fallback_rc"')
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
REMOTE
}

# The disposable-tree half of the script: unpack the armored streams into a
# fresh /tmp root. Reads $hi_esc/$nc_esc/$size and the streams from its caller,
# so _say_hi and _hi_wire_bytes assemble one shape rather than two kept in step.
#
# The `trap ... exit` below is a backstop, not a second owner: load.sh's
# clean_all is what actually knows how to undo everything hi did on the
# target - this tree and $_HI_SESSION_RC_DIR (nested under $_HI_CLEANUP for
# exactly this reason) - and it runs
# on every normal exit and on an abrupt disconnect alike (SIGHUP, tested by
# tests/targets/ssh_disconnect_test.sh). This trap exists for the one thing
# clean_all cannot survive: bash killed by a signal nothing can trap. It only
# ever needs to remove the tree, since $_HI_SESSION_RC_DIR lives inside
# it - kept out of the heredoc itself, since every byte here rides the wire
# on every connect.
function _hi_remote_middle() {
  local tmpl
  _hi_shquote tmpl "$(_hi_whoami).hi.XXXXXX"
  cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $tmpl) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/say-hi
      export _HI_CONFIG_DIR=\$_HI_ROOT/config
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
      trap 'rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "$size" >&2
      echo "$bootloader" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      echo "$tree" | $_HI_UNARMOR | tar mxzf - -C "\$_HI_HOME"
      $overlay_line
      export _HI_CONNECT_PREFIX=" $size"
REMOTE
}

# Connect, copy say-hi over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: HI.18)
function _say_hi() {
  local size hi_esc nc_esc script middle boot_tmp remote_root tmp_root ctl_path ctl_dir ec=0
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts overlay=()

  # only this path armors (containers stream via their CLI); tar is every
  # transport's floor, and both are asked here rather than at the pipeline
  # that needs them - `tree="$(_hi_payload_tar | base64)"` takes the armor's
  # status, so a refusal further in is swallowed and the session carries on to
  # the next missing binary, printing a raw "command not found" per pipe
  # stage and handing the target an empty archive.
  _hi_require base64 "to reach an ssh target" || return 1
  _hi_require tar "to pack the payload" || return 1

  printf -v hi_esc '%b' "$YELLOW"
  printf -v nc_esc '%b' "$NC"

  # multiplex the install-probe and the real session over one ssh connection
  _hi_ctl_open 30
  remote_root="$(_hi_remote_root "${ctl_opts[@]}")"
  remote_root="$(_hi_trusted_path "$remote_root")"

  if [ -n "$remote_root" ]; then
    # $remote_root is always <home>/<tree>
    tmp_root="${remote_root%/*}"
    middle="$(
      cat <<REMOTE
      export _HI_HOME="$tmp_root"
      export _HI_ROOT="$remote_root"
      _hi_rc_dir="\$(dirname "\$0")"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "-> local say-hi install" >&2
      $(_hi_bootloader | _hi_armored_line '>' '"$_hi_rc_dir/hi.bashrc"')
      export _HI_CONNECT_PREFIX="-> local say-hi install"
REMOTE
    )"
  else
    bootloader="$(_hi_bootloader | $_HI_ARMOR)"
    tree="$(_hi_payload_tar | $_HI_ARMOR)"
    # the overlay's own stream, omitted when empty (GLOSSARY: HI.41)
    _hi_read_lines overlay < <(_hi_overlay_files)
    if ((${#overlay[@]})); then
      overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_tar "${overlay[@]}" | _hi_armored_line '|' 'tar mxzf - -C "$_HI_ROOT/config"')"
    fi
    size="$_HI_SIZE_TOKEN"
    middle="$(_hi_remote_middle)"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # the true byte count, substituted for the token (GLOSSARY: HI.44)
  if [ -z "$remote_root" ]; then
    size="$(_hi_human_bytes "${#script}")"
    script="${script//$_HI_SIZE_TOKEN/$size}"
  fi

  # The bootloader rides stdin of the first of two calls on one connection; the
  # write doubles as the POSIX-shell-and-base64 probe that selects the
  # PowerShell fallback. GLOSSARY: HI.19 - the argv cap, and why two calls
  # ...and this one keeps its stderr too: where the ControlMaster could not be
  # opened above, this is the call that authenticates, so it inherits the same
  # duty. A target with no POSIX shell says so in one line before the PowerShell
  # branch announces itself, which reads better than a silent swap anyway.
  #
  # The *target* names the directory and prints it back, rather than a
  # client-side `mktemp -u` naming a path in the **client's** $TMPDIR for the
  # target to `mkdir`: on any client with $TMPDIR set - every macOS login
  # shell, where it is /var/folders/../T - that path would not exist on a
  # Linux target, the mkdir would fail, and the whole session would fall
  # through to the PowerShell branch on a host that has bash, invisibly to CI
  # (whose macOS job only ever connects to 127.0.0.1, where the path does
  # exist). The container arm already gets this right ("a literal /tmp",
  # below).
  #
  # `mktemp -d` also creates at 0700 itself, so no separate mkdir flag is
  # needed for the mode. Six X exactly: busybox mktemp accepts no other count.
  local boot_out boot_ec=0
  boot_out="$(printf '%s\n' "$script" | _hi_ssh_sh "$(_hi_boot_probe)" "${ctl_opts[@]}")" || boot_ec=$?

  # Tagged rather than taken whole: a target whose sh writes anything of its own
  # to stdout would otherwise prepend it to the path. Everything after the last
  # marker, up to the newline.
  boot_tmp=""
  case "$boot_out" in *HIBOOT:*)
    boot_tmp="${boot_out##*HIBOOT:}"
    boot_tmp="${boot_tmp%%$'\n'*}"
    ;;
  esac
  # ...and it is a string from the target being interpolated into a command run
  # back on that target - _hi_safe_path's rule, drawn from the characters a
  # temp path is built out of ("+" included: macOS's /var/folders names use it)
  boot_tmp="$(_hi_safe_path "$boot_tmp" 'A-Za-z0-9._/+-')"

  # `-t` only when there is a terminal to ask for. ssh already declines to
  # allocate a pty when stdin is not one, so this changes no behaviour - it
  # just stops "Pseudo-terminal will not be allocated because stdin is not a
  # terminal" landing in the stderr of every piped `hi <host> <cmd>`. The
  # container arms have to make the same decision for a harder reason
  # (_hi_container_cmds).
  local -a tflag=()
  [ "$(_hi_tty)" = 1 ] && tflag=(-t)
  # An empty $boot_tmp has four causes, and only one of them is the host with
  # no `sh` the PowerShell notice exists for. Told apart by the write's
  # status and what came back (GLOSSARY: HI.19): the probe's own two codes;
  # a path hi refused above; and a *forced command* - sshd's `ForceCommand`,
  # or a `command=` on the key - which runs its own program whatever the
  # client asked, so `sh -c` never ran and the status and output are that
  # program's. A forced command that exits 0, or prints anything, cannot be
  # a host with no shell (cmd.exe and PowerShell both fail `sh` non-zero and
  # say so on stderr). Each of the three gets a line naming it and the host's
  # own session, which is what `ssh` would have given - and for a forced
  # command, the only session the host offers. One that exits non-zero and
  # prints nothing to stdout is indistinguishable from a missing `sh` and
  # gets the PowerShell notice, which it ignores like every other command.
  local why=""
  if [ -z "$boot_tmp" ]; then
    case "$boot_out" in
    *HIBOOT:*) why="[$DOMAIN] named a scratch directory hi will not use" ;;
    *)
      case "$boot_ec" in
      64) why="no base64 on [$DOMAIN]" ;;
      65) why="no writable temp directory on [$DOMAIN]" ;;
      0) why="a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
      *) [ -z "$boot_out" ] || why="a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
      esac
      ;;
    esac
  fi
  if [ -n "$boot_tmp" ]; then
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      "sh \"$boot_tmp/bootloader\"; rm -rf \"$boot_tmp\"" || ec=$?
  elif [ -n "$why" ]; then
    _hi_cecho " $why - handing over the host's own session" "$YELLOW" >&2
    _say_hi_plain "${ctl_opts[@]}" || ec=$?
  else
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, say-hi colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  fi

  _hi_ctl_close
  return "$ec"
}

# _hi_container_cmds <label> - the three ways to run something in a container
# target, into the caller's probe/cp/attach arrays: probe asks a question (no
# stdin, no tty), cp streams a file in, attach hands over a session. Its own
# function because scripts/doctor.sh has to ask exactly as a session would.
function _hi_container_cmds() {
  # the where/what halves (GLOSSARY: HI.43); $inner is empty for a plain target
  local outer inner
  outer="$(_hi_outer "$DOMAIN")"
  inner="$(_hi_inner "$DOMAIN")"
  local -a pick=()
  # A tty only when there is one to hand over. `docker exec -it` with stdin on
  # a pipe does not degrade - it refuses outright ("cannot attach stdin to a
  # TTY-enabled container because stdin is not a terminal"), so
  # `hi <container> <cmd> | ...` failed at the transport before the command
  # ever ran. ssh -t merely warns and carries on, which is why only the
  # container arms had this. The `-i`/`-it` split below is the same decision
  # in each backend's spelling (nomad wants it explicit either way: its
  # stdin-is-a-tty guess lands wrong on a wrapped pty and hangs the exec).
  local tty it=-i nt=-t=false
  tty="$(_hi_tty)"
  if [ "$tty" = 1 ]; then
    it=-it
    nt=-t=true
  fi
  case "$1" in
  docker | podman)
    local target="$DOMAIN"
    # the compose alias, only when the literal name doesn't already resolve
    if [ "$1" = docker ] && ! _hi_is_container_running docker "$DOMAIN"; then
      local resolved
      resolved="$(_hi_compose_container "$DOMAIN")" && target="$resolved"
    fi
    probe=("$1" exec "$target")
    cp=("$1" exec -i "$target")
    attach=("$1" exec "$it" "$target")
    ;;
  nomad)
    [ -n "$inner" ] && pick=(-task "$inner")
    probe=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=false -t=false "$outer")
    cp=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true -t=false "$outer")
    attach=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true "$nt" "$outer")
    ;;
  kube)
    # the context/namespace prefixes, if any, ride every kubectl call
    _hi_kube_split "$DOMAIN"
    [ -n "$inner" ] && pick=(-c "$inner")
    probe=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    cp=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec -i "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    attach=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$it" "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    ;;
  esac
}

# The client-side sweep of the scratch tree on every early exit and after the
# session. Reads $root and the probe array from its caller's scope
# (_say_hi_container's locals), the way _hi_remote_middle reads _say_hi's.
function _hi_container_cleanup() {
  "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
  return 0
}

# _hi_container_fallback_shell [errlog] - the no-bash fallback, probed and
# validated. The answer is a *word read back from the container* that gets
# interpolated into an attach command, and the probe only ever echoes one of
# $_HI_SHELL_LADDER's own names - so anything else means the answer did not
# come from the probe (a busybox `echo` with a mind of its own, or a shell
# that wrote something extra on the way past), and nothing is printed:
# checked against the fixed list of right answers rather than sanitized.
# Reads the probe array from its caller's scope.
function _hi_container_fallback_shell() {
  local fallback
  fallback="$("${probe[@]}" sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')" 2>"${1:-/dev/null}")"
  case " $_HI_SHELL_LADDER " in
  *" $fallback "*) printf '%s' "$fallback" ;;
  esac
  return 0
}

# _say_hi_container <label> <errlog> - the container arm, across docker,
# podman, nomad and kube.
function _say_hi_container() {
  local label="$1" tmp="$2"
  local shell_end root fallback exit_code size prefix tarball env_kv
  local -a probe cp attach overlay=()
  _hi_require tar "to pack the payload" || return 1
  _hi_container_cmds "$label"

  # The tree's parent is the *target's* `${TMPDIR:-/tmp}`, expanded on the
  # target - the client's $TMPDIR has nothing to say about it - so a pod with
  # a read-only root and an emptyDir wherever its $TMPDIR points still has
  # somewhere to land. Mode 700 at creation and no -p, like the ssh path's
  # boot_tmp: a directory that already exists is not adopted. The path comes
  # back from the target and is interpolated into every command run there, so
  # it is checked the way boot_tmp is - absolute, and drawn from the characters
  # a temp path is built from - and refused rather than escaped. A target
  # with nowhere writable says so here, naming the directory it tried, rather
  # than at the copy with a message about the copy; --plain needs no tree.
  root="$("${probe[@]}" sh -c 'd="${TMPDIR:-/tmp}"; d="${d%/}/'"$(_hi_whoami).hi.log.$$"'"
if mkdir -m 700 "$d" 2>/dev/null; then printf "%s" "$d"; else printf "%s" "${TMPDIR:-/tmp}" >&2; exit 1; fi' 2>"$tmp")" || {
    _hi_fail " no writable temp directory ($(cat "$tmp")) in [$DOMAIN] - --plain needs none"
    return 1
  }
  # the class adds "@" to boot_tmp's: the directory name embeds _hi_whoami
  root="$(_hi_safe_path "$root" 'A-Za-z0-9._/+@-')"
  if [ -z "$root" ]; then
    _hi_fail " [$DOMAIN] named a scratch directory hi will not use"
    return 1
  fi
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    fallback="$(_hi_container_fallback_shell "$tmp")"
    if [ -z "$fallback" ]; then
      _hi_fail " [$DOMAIN] named no shell hi asked about - not falling back"
      return 1
    fi
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW" >&2

    if ! "${cp[@]}" sh -c "cat > '$root/aliases.sh'" <"$_HI_ALIASES" 2>"$tmp"; then
      _hi_fail " failed to copy aliases.sh into [$DOMAIN]"
      _hi_container_cleanup
      "${attach[@]}" "$fallback"
      return $?
    fi

    # the shared fallback rc in its aliases-only shape, plus the POSIX prompt
    # for the shells that can parse it - the ssh path's `*)` rule
    local -a fish_cmd=() st
    {
      _hi_fallback_rc --aliases-only "$root"
      case "$fallback" in
      zsh | fish) ;;
      *) _hi_fallback_prompt ;;
      esac
      # the command last, for the shells that read the file to its end; fish
      # takes it as -c below instead (GLOSSARY: HI.23)
      [ "$fallback" = fish ] || [ -z "${CMDARG:-}" ] || printf '%s\n' "$CMDARG"
    } |
      "${cp[@]}" sh -c "cat > '$root/.hi_fallback_rc'" 2>"$tmp"
    st=("${PIPESTATUS[@]}")
    # checked like aliases.sh's copy above, and for the same reason: a miss
    # here is silent otherwise. The write can succeed at the transport and
    # still deliver nothing - an exec -i whose stdin closes before the
    # target's cat drains it - which is why the file is also proven non-empty
    # on the target, not just assumed from a zero exit; either failure drops
    # $CMDARG along with the rest of the rc and leaves a bare, uncommanded
    # shell with no way to tell the two apart from the outside
    if [ "${st[1]}" != 0 ] || ! "${probe[@]}" sh -c "[ -s '$root/.hi_fallback_rc' ]" 2>"$tmp"; then
      _hi_fail " failed to write the fallback rc into [$DOMAIN]"
      _hi_container_cleanup
      return 1
    fi
    [ "$fallback" != fish ] || [ -z "${CMDARG:-}" ] || fish_cmd=(-c "$CMDARG")

    case "$fallback" in
    zsh)
      if ! "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp"; then
        _hi_fail " failed to write .zshrc into [$DOMAIN]"
        _hi_container_cleanup
        return 1
      fi
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh -i"
      ;;
    # the rc through -C and the command through -c, as in _hi_remote_suffix
    fish) "${attach[@]}" fish -C "$("${probe[@]}" cat "$root/.hi_fallback_rc")" ${fish_cmd[@]+"${fish_cmd[@]}"} ;;
    *) "${attach[@]}" sh -c "export ENV='$root/.hi_fallback_rc'; exec $fallback -i" ;;
    esac
    exit_code=$?
    _hi_container_cleanup
    return $exit_code
  fi

  # staged to a file so the announced size is the one actually sent
  tarball="$tmp.tar.gz"
  if ! _hi_payload_tar >"$tarball"; then
    _hi_fail " failed to archive say-hi for [$DOMAIN]"
    return 1
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  # just the size, the way the ssh path's prefix reads
  prefix=" $size"
  printf '%s' " $size" >&2

  if ! "${cp[@]}" sh -c "tar mxzf - -C '$root'" <"$tarball"; then
    rm -f "$tarball"
    _hi_fail " failed to copy say-hi into [$DOMAIN]"
    _hi_container_cleanup
    return 1
  fi
  rm -f "$tarball"

  _hi_read_lines overlay < <(_hi_overlay_files)
  if ((${#overlay[@]})) &&
    ! _hi_overlay_tar "${overlay[@]}" |
    "${cp[@]}" sh -c "mkdir -p '$root/say-hi/config' && tar mxzf - -C '$root/say-hi/config'" 2>"$tmp"; then
    _hi_cecho " failed to copy your say-hi config overlay into [$DOMAIN], using defaults" "$YELLOW" >&2
  fi

  # hi.sh rides the payload tar unpacked above, mode and all - no separate copy
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/say-hi/hi.bashrc'"

  # `-i` explicitly, the way the ssh arm's _hi_remote_suffix has always spelled
  # it. `--rcfile` is read by an *interactive* bash and nothing else, and until
  # the tty became conditional above this line got its interactivity by
  # accident: `docker exec -it` handed bash a terminal on stdin and stderr with
  # no script argument, which is the other way bash decides it is interactive.
  # Drop the tty for a piped `hi <container> <cmd>` and that inference goes with
  # it - bash reads the (empty) pipe as a script, ignores the rcfile, never
  # sources load.sh and never runs the command, and the caller gets a clean
  # exit and no output.
  #
  # _HI_CLEANUP marks the tree disposable for load.sh's clean_all, which owns
  # undoing everything hi did here. The rm -rf below is a client-side
  # backstop for the one thing clean_all cannot survive - bash killed by a
  # signal nothing can trap - not a second place that has to know what to
  # remove: $_HI_SESSION_RC_DIR nests under $_HI_CLEANUP, so this one `rm -rf`
  # already covers it too.
  env_kv="$(_hi_env_each ' %s=%s')"
  "${attach[@]}" sh -c "export$env_kv _HI_HOME='$root' _HI_ROOT='$root/say-hi' _HI_CONFIG_DIR='$root/say-hi/config' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_elapsed "$shell_end" "$(_hi_now)")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/say-hi/hi.bashrc' -i"
  exit_code=$?

  _hi_container_cleanup
  return $exit_code
}

# _say_hi_plain [ssh-opts...] - --plain over ssh: no bootstrap, no
# local-install probe, no payload - just ssh handing over the target's own
# login shell, the way it always would with no target-side config to try.
# Needs nothing beyond sshd and a shell: no tar, no base64, no writable /tmp,
# no $HOME. Also where _say_hi lands when the target refused its bootstrap,
# which is when the ControlMaster options arrive in "$@".
function _say_hi_plain() {
  local -a tflag=()
  [ "$(_hi_tty)" = 1 ] && tflag=(-t)
  ssh ${tflag[@]+"${tflag[@]}"} "$@" "${SSHARGS[@]}" "$DOMAIN" ${RAWCMD:+"$RAWCMD"}
}

# _say_hi_container_plain <label> - --plain over a container backend: no
# mkdir, no copy, straight into the best shell the target has - bash if a
# read-only probe finds it, else the best of $_HI_SHELL_LADDER, else a bare
# `sh`. _hi_container_cmds builds the same probe/attach the full path uses,
# so the two can never disagree on how to reach the target.
function _say_hi_container_plain() {
  local label="$1" shell
  local -a probe cp attach
  _hi_container_cmds "$label"
  if "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>&1; then
    shell=bash
  else
    # a probe that answers nothing usable still gets a bare `sh` here - the
    # full path refuses instead, since it has a payload at stake
    shell="$(_hi_container_fallback_shell)"
    [ -n "$shell" ] || shell="sh"
  fi
  if [ -n "${RAWCMD:-}" ]; then
    "${attach[@]}" "$shell" -c "$RAWCMD"
  else
    "${attach[@]}" "$shell"
  fi
}

# split ssh's arguments from the target and any trailing remote command
# A target chosen from the list, on stdout. What bare `hi` reaches instead of
# falling through to ssh's usage message. Two failures, told apart because they
# deserve different answers: 2 is "there was nothing to offer", which is still
# ssh's usage message to print, and 1 is "you dismissed the menu", which is not.
#
# The rows are common/targets.sh's, the same "<name>\t<kind>" list the three
# shell completions read - so the offer is backend-tagged, recency-ranked, and
# served out of the $_HI_TARGETS_TTL cache a TAB may already have warmed. This
# runs entirely on the client and connects to the result like any other target,
# so nothing here reaches a payload or a target's disk.
#
# fzf or sk when the client has one, a numbered `select` when it does not:
# nothing has to be installed for bare `hi` to work. Both write their menu to
# the terminal rather than to stdout, which is this function's return value -
# fzf and sk open /dev/tty themselves, and bash's `select` prompts on stderr.
function _hi_pick_target() {
  local picker rows reply name kind
  rows="$(sh "$_HI_TARGETS" 2>/dev/null || true)"
  [ -n "$rows" ] || return 2
  picker="$(command -v fzf || command -v sk || true)"
  if [ -n "$picker" ]; then
    # --with-nth over a tab delimiter shows the tag beside the name while
    # keeping the whole row as the value, so the cut below is the same for
    # both pickers
    # stderr is deliberately not swallowed: the picker draws its pane on
    # /dev/tty, so the only thing that reaches stderr is a complaint - a flag
    # this build does not take, most likely - and silence there would read as
    # "hi did nothing". A dismissal is an empty answer, not an error.
    reply="$(printf '%s\n' "$rows" | "$picker" --prompt='hi ' \
      --delimiter=$'\t' --with-nth=1,2 --height=40% --reverse --no-multi || true)"
    reply="${reply%%$'\t'*}"
  else
    local -a menu=()
    while IFS=$'\t' read -r name kind; do
      [ -n "$name" ] || continue
      # bash prints a `select` item verbatim, so "<name> (<kind>)" is all the
      # formatting there is - and the cut below takes the name back off it
      menu+=("$name (${kind:-ssh})")
    done <<<"$rows"
    ((${#menu[@]})) || return 2
    # stdin, not an explicit /dev/tty: bare `hi` already established that stdin
    # is a terminal, and reopening one here would ignore a redirect
    local PS3="hi which? "
    select reply in "${menu[@]}"; do
      [ -n "$reply" ] && break
    done
    reply="${reply%% *}"
  fi
  [ -n "$reply" ] || return 1
  printf '%s' "$reply"
}

function _hi_parse() {
  local backend_word
  SSHARGS=()
  while [ $# -gt 0 ]; do
    case $1 in
    # every ssh option taking a separate value, so it is never read as the target
    -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      [ "$#" -ge 2 ] || {
        _hi_cecho "hi: $1 needs a value" "$RED" >&2
        exit 1
      }
      SSHARGS+=("$1" "$2")
      shift
      ;;
    # a backend flag names the arm outright, ahead of the target - like any
    # other ssh option. ssh itself takes no `--` option, so claiming every one
    # here costs nothing: today they are all just ssh's own "unknown option"
    # to report. Only ahead of the target - one already chosen means this is
    # the remote command's own word, not hi's.
    -*)
      if [ -n "${DOMAIN:-}" ]; then
        SSHARGS+=("$1")
      elif backend_word="$(_hi_backend_flag "$1")"; then
        if [ -n "${BACKEND:-}" ] && [ "$BACKEND" != "$backend_word" ]; then
          _hi_cecho "hi: $1 and --$BACKEND both name a backend; pick one" "$RED" >&2
          exit 1
        fi
        BACKEND="$backend_word"
      elif [ "$1" = --plain ]; then
        PLAIN=1
      else
        SSHARGS+=("$1")
      fi
      ;;
    *)
      if [ -z "${DOMAIN:-}" ]; then
        DOMAIN="$1"
      else
        # the words as-is, for --plain's direct ssh/exec (no bootloader to
        # embed them in, so no "; exit" to close a sourced script out with)
        RAWCMD="$*"
        CMDARG="$*$([[ "$*" = *[![:space:]]* ]] && echo '; ') exit"
        return
      fi
      ;;
    esac
    shift
  done
  [ -n "${DOMAIN:-}" ] || {
    # Bare `hi` - no target and no ssh option either - has a list to offer
    # rather than a usage message to print. Any ssh option present and the old
    # behaviour stands: `hi -V` has to go on being `ssh -V`, and an option
    # without a host is ssh's error to report, not a target to guess at.
    #
    # Both ends of a terminal are required. Without them there is nobody to
    # answer the picker, and a `hi` in a script or a CI job would hang on a
    # menu instead of failing the way it does today.
    if [ "${#SSHARGS[@]}" -eq 0 ] && [ -t 0 ] && [ -t 2 ]; then
      local pick_rc=0
      DOMAIN="$(_hi_pick_target)" || pick_rc=$?
      [ -n "${DOMAIN:-}" ] && return 0
      # dismissed rather than empty: that is an answer, and printing ssh's
      # usage over the top of the menu just closed is not a reply to it. A
      # machine with nothing to offer (rc 2) falls through and says so the way
      # it always has.
      [ "$pick_rc" -eq 1 ] && exit 0
    fi
    ssh "${SSHARGS[@]}"
    exit 1
  }
}

# `${!array[@]}`, not a counter kept in lockstep: the index is what pairs a row
# with its pid. (bash 3.0+, not one of the bash-4 forms the lint suite greps.)
function _hi_resolve_backend() {
  local target="$1" i
  local -a pids=()
  for i in "${!_HI_BACKENDS[@]}"; do
    "${_HI_BACKENDS[i]##*|}" "$target" &
    pids+=("$!")
  done
  for i in "${!_HI_BACKENDS[@]}"; do
    if wait "${pids[i]}"; then
      printf '%s' "${_HI_BACKENDS[i]%%|*}"
      return 0
    fi
  done
  return 0
}

# _hi_select_arm - the arm $DOMAIN connects through: empty for ssh, one of
# $_HI_BACKENDS' names otherwise. $BACKEND (a backend flag, set by _hi_parse)
# wins outright and skips every probe below it - "ssh" means the empty arm,
# same as an unforced ssh host. Its own function, apart from _hi, so a suite
# can assert the choice without a real connect.
function _hi_select_arm() {
  if [ -n "${BACKEND:-}" ]; then
    [ "$BACKEND" = ssh ] || printf '%s' "$BACKEND"
    return 0
  fi
  _hi_is_ssh_host "$DOMAIN" && return 0
  _hi_resolve_backend "$DOMAIN"
}

# _hi_record_recent <target> - one "<epoch>\t<target>" line appended to the
# recent-targets file common/targets.sh ranks completion by; client-side only,
# quiet on failure, trimmed past 500 lines. GLOSSARY: HI.42
function _hi_record_recent() {
  local f n tmp
  [ "${_HI_RECENT:-1}" != 0 ] || return 0
  [ "${_HI_REMOTE_SESSION:-0}" != 1 ] || return 0
  f="${_HI_RECENT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/say-hi/recent}"
  [ -d "${f%/*}" ] || mkdir -p "${f%/*}" 2>/dev/null || return 0
  printf '%s\t%s\n' "$(date +%s 2>/dev/null || echo 0)" "$1" >>"$f" 2>/dev/null || return 0
  n="$(grep -c . "$f" 2>/dev/null || echo 0)"
  if [ "$n" -gt 500 ]; then
    tmp="$f.$$"
    if tail -n 300 "$f" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
      rm -f "$tmp" 2>/dev/null
    fi
  fi
  return 0
}

# _hi_report_failure <code> <arm> <errlog> - what a failed connect says, at
# most once. Three ways it says nothing at all, each because the failure was
# already spoken for: $_HI_SAID means _hi_fail already printed the reason;
# ssh reserves exit 255 for its own failures and prints them itself (the
# comment above this function's caller explains why hi stopped wrapping the
# whole connect to catch them again), so any other code from the ssh arm is
# the session's or the remote command's own status - `hi host false` has to
# stay as quiet as `ssh host false`; and an empty container errlog means
# nothing hi ran on the way in complained, so the code is the session's too.
function _hi_report_failure() {
  local code="$1" arm="$2" errlog="$3" errors
  [ "${_HI_SAID:-0}" != 1 ] || return 0
  if [ -n "$arm" ]; then
    [ -s "$errlog" ] || return 0
  else
    [ "$code" -eq 255 ] || return 0
  fi
  errors="$(<"$errlog")"
  # a real line-clear, not four bytes of \r: what this is clearing is the
  # container arm's in-progress " <size>" (no trailing newline yet) - on a
  # pipe there is no cursor to move, so a newline is the whole job instead
  if [ -t 2 ]; then
    printf '\r\033[K' >&2
  else
    printf '\n' >&2
  fi
  _hi_cecho "hi: could not reach [$DOMAIN]" "$BRRED" >&2
  [ -n "$errors" ] && _hi_cecho "$errors" "$BRRED" >&2
}

function _hi() {
  local tmp exit_code arm

  [ -d "$_HI_ROOT" ] || {
    _hi_cecho "hi: no such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  }

  tmp="$(mktemp -t hi.log.XXXXXX)"
  # $tmp is resolved when the trap fires, not now
  _hi_on_exit 'rm -f "$tmp"'

  _hi_parse "$@"
  # No `2>"$tmp"` around this block: wrapping the whole connect to reprint a
  # failure in red at the end would also catch every word ssh says on a
  # *successful* session - the server's `Banner` (the notice a regulated
  # fleet is required to display), the "Permanently added" line, and the
  # host-key fingerprint. Every backend probe already silences its own daemon
  # chatter (_hi_is_container_running and friends), so that catch-all would be
  # almost entirely the transport's noise, and the transport has the better
  # claim on the terminal. $tmp is still handed to _say_hi_container, which
  # redirects the individual commands whose noise is genuinely hi's.
  arm="$(_hi_select_arm)"
  if [ "${PLAIN:-0}" = 1 ]; then
    if [ -n "$arm" ]; then
      _say_hi_container_plain "$arm"
    else
      _say_hi_plain
    fi
  elif [ -n "$arm" ]; then
    _say_hi_container "$arm" "$tmp"
  else
    _say_hi
  fi
  exit_code="$?"

  # a session that ended cleanly is one worth offering first next time; one
  # that never connected (a typo, an unreachable host) is not
  [ "$exit_code" -eq 0 ] && _hi_record_recent "$DOMAIN"

  [ "$exit_code" -eq 0 ] || _hi_report_failure "$exit_code" "$arm" "$tmp"
  exit "$exit_code"
}

# The scripts/ entry points, reached as `hi --flag`. The payload ships neither
# scripts/ nor tests/, so on a target the file is absent and the flag has to
# say which command wanted it; $_HI_NO_CHECKOUT (paths.sh) is that sentence.
function _hi_run_script() {
  local flag="$1" script="$2"
  shift 2
  [ -f "$script" ] && exec "$script" "$@"
  _hi_cecho "hi $flag $_HI_NO_CHECKOUT" "$RED" >&2
  exit 1
}

# hi's flags, out of common/flags (its header has the row format): one table
# for the dispatch here, --help's option lines and completion's roster. Rows
# with a script var hand off; the rest have case arms below.
_HI_FLAGS=()
while IFS= read -r _hi_row || [ -n "$_hi_row" ]; do
  case "$_hi_row" in '#'* | '') continue ;; esac
  _HI_FLAGS+=("$_hi_row")
done <"$_HI_ROOT/common/flags"
unset _hi_row

# _hi_dispatch_subcommand "$@" - hands $1 to its script and never returns when
# the table names one; returns 1 otherwise. ${!var} is bash 2, not a bash-4 form.
function _hi_dispatch_subcommand() {
  local row flag var arg
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag _ var arg _ <<<"$row"
    [ "$flag" = "${1:-}" ] || continue
    [ -n "$var" ] || return 1
    shift
    _hi_run_script "$flag" "${!var}" ${arg:+"$arg"} "$@"
  done
  return 1
}

# _hi_flag_help <-|local> - the option lines of --help: `-` is what works
# anywhere, `local` what needs a part of the tree the payload does not carry.
function _hi_flag_help() {
  local row flag needs help
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag needs _ _ help <<<"$row"
    case "$1:$needs" in
    -:-) [ "$flag" = --help ] && flag="-h, --help" ;;
    local:-) continue ;;
    -:*) continue ;;
    esac
    printf '  %-21s %s\n' "$flag" "$help"
  done
}

set +euo pipefail # the connection paths below run against unknown hosts, where a probe that fails is normal, not fatal

# sourcing this file defines its functions without connecting, for testing
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone: _hi_parse hands every other -flag to
# ssh, so anything hi answers itself is caught first. A bare `hi` still execs
# ssh, so `hi -V` and friends behave as they do there.
_hi_dispatch_subcommand "$@"

case "${1:-}" in
-h | --help)
  cat <<EOF
$_HI_USAGE

Copies your say-hi to <target> and hands you an identical shell session there -
header, colors, git prompt, aliases, vim/nano configs - then strips it all
back out when the session ends.

With [command ...], runs that instead - but not quite the way ssh does, and the
difference matters if you are scripting: the command runs inside hi's session,
so it has hi's aliases, \$PATH and environment, and it runs on a pty when your
own stdin is one. Only the command's own output goes to stdout; hi's progress
and errors go to stderr. For a plain, unstyled, pty-free remote command - a
tarball you are piping into a file, say - use ssh itself.

<target> is resolved in this order, first match wins:
  1. a Host in ~/.ssh/config (or any name ssh can reach)
  2. a running docker container, by name or ID
  3. a running podman container
  4. a running nomad allocation, by ID or prefix
  5. a kubernetes pod, in whatever context/namespace kubectl points at -
     or namespace:pod / context:namespace:pod for another one

--ssh, --docker, --podman, --nomad or --kube before the target names the arm
outright and skips every probe above it - the fix for a container that
shadows an unrelated ssh host of the same name. --plain skips the payload
too and hands over a bare shell on whichever arm resolves - no tar, no
base64, no writable /tmp, no \$HOME needed on the target at all.

With no target at all, hi offers that same list - the one your shell completes
from, backend-tagged and recently-used first - and connects to what you pick:
through fzf or sk when you have one, a numbered menu when you do not.

hi's own options, which work anywhere - a session included:
$(_hi_flag_help -)

hi's local sub-commands, which act on this machine instead of connecting. They
need a part of the tree the payload does not carry, so inside a hi session
each says so and stops:
$(_hi_flag_help local)

Everything else is passed to ssh unchanged - -p, -i, -J, -o and the rest behave
exactly as they do there, and ssh keeps its own stderr, so a host's login
banner and an unknown key's fingerprint reach you as they always would. Only
the first non-option word is the target; everything after it is the remote
command.

Configuration lives outside this tree, in \${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/
so it survives an upgrade. See \`man hi\` and the README for all of it.
EOF
  exit 0
  ;;
# .git as the test: absent from payloads and packaged installs alike
--update)
  shift
  [ -d "$_HI_ROOT/.git" ] || {
    _hi_cecho "hi --update: $_HI_NO_GIT" "$RED" >&2
    exit 1
  }
  exec git -C "$_HI_ROOT" pull "$@"
  ;;
# the full preview lives in scripts/; a target falls back to the check itself
--packages-preview)
  shift
  [ -f "$_HI_PACKAGES_PREVIEW" ] && exec "$_HI_PACKAGES_PREVIEW" "$@"
  exec bash -c 'source "$1" && full_check' hi "$_HI_HEADER"
  ;;
--version)
  _hi_version
  exit 0
  ;;
esac

_hi "$@"
