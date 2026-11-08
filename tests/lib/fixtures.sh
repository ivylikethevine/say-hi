#!/usr/bin/env bash
# World-building for a case: fake and real PATHs, git and settings fixtures, a
# scratch tree, and the string helpers that read what came back out.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# _hi_strip_ansi <text> - <text> without color escapes or OSC sequences (some
# fish builds send OSC 7 unasked), the inverse of _hi_rendered. One sed pass,
# since bash's `${s//pattern/}` is quadratic; ESC and BEL go in as raw bytes,
# since BSD sed has no \x1b.
function _hi_strip_ansi() {
  local esc=$'\e' bel=$'\a'
  printf '%s' "$1" | sed \
    -e "s/${esc}\[[0-9;?<=>]*[ -/]*[@-~]//g" \
    -e "s/${esc}\][^${bel}${esc}]*${bel}//g" \
    -e "s/${esc}\][^${bel}${esc}]*${esc}\\\\//g" \
    -e "s/${esc}[()][0-9A-Za-z]//g" \
    -e "s/${esc}[=>78cM]//g"
}

# _hi_within_percent <got> <want> <pct> - is <got> within <pct>% of <want>?
# The band ssh_wire_test.sh holds the wire figures to: rounded up, at least
# one unit, so jitter never fails it. 0 (no figure) is never within.
function _hi_within_percent() {
  local got="$1" want="$2" delta slack=$((($2 * $3 + 99) / 100))
  [ "$slack" -gt 0 ] || slack=1
  [ "$got" -gt 0 ] || return 1
  delta=$((got - want))
  [ "$delta" -lt 0 ] && delta=$((-delta))
  [ "$delta" -le "$slack" ]
}

# A scheme of the user's own: 24 or 48 six-digit hex words in the setting
# itself - the only shape there is, since hi ships no named schemes. Shared
# by common/core_test.sh and common/header_test.sh, which both build custom
# color schemes off it - one copy so the two lists can't drift apart.
_HI_TEST_SCHEME12='f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 f37799 89d88b ebd391 74a8fc f2aede 6bd7ca'
_HI_TEST_SCHEME24="$_HI_TEST_SCHEME12 ff8c00 ff69b4 20b2aa 9acd32 8a2be2 fa8072 ffd700 87ceeb 6a5acd 98ff98 ffb07c b57edc"
_HI_TEST_SCHEME48="$_HI_TEST_SCHEME24 cd3131 0dbc79 e5e510 2472c8 bc3fbc 11a8cd f14c4c 23d18b f5f543 3b8eea d670d6 29b8db e07b39 e75480 2a9d8f 7bc043 7b2cbf f08080 e6b800 5bc0eb 4b0082 3eb489 ffcba4 967bb6"

# A packages ramp of the user's own, in the eight-name shape a [palette]
# loads as: four for installed rising 0->3, then four for missing. Deliberately
# shares no name with the shipped ramp, so a case can tell "taken verbatim"
# from "fell back". Shared by common/header_test.sh and scripts/preview_test.sh.
_HI_TEST_RAMP='yellow bryellow green brgreen magenta brmagenta red brred'

# _hi_color_overlay <dir> <base> [scheme] [ramp] - <dir>/colors: <base>'s rows
# (empty for none), then a [scheme] of [scheme]'s words, the first 24 as
# `colors` and the rest as `packages`, and a [palette] of [ramp]'s names, the
# first four `installed` and the rest `missing` - how a scheme or a ramp
# reaches a child, since core.sh loads both from the colors file it resolves
function _hi_color_overlay() {
  local dir="$1" base="$2" s="${3:-}" r="${4:-}" f="$1/colors" a
  local -a w=()
  mkdir -p "$dir"
  if [ -n "$base" ]; then cat "$base"; fi >"$f"
  if [ -n "$s" ]; then
    read -r -a w <<<"$s"
    printf '\n[scheme]\ncolors = "%s"\n' "${w[*]:0:24}" >>"$f"
    [ "${#w[@]}" -le 24 ] || printf 'packages = "%s"\n' "${w[*]:24}" >>"$f"
  fi
  [ -n "$r" ] || return 0
  read -r -a w <<<"$r"
  printf -v a '"%s", ' "${w[@]:0:4}"
  printf '\n[palette]\ninstalled = [%s]\n' "${a%, }" >>"$f"
  [ "${#w[@]}" -gt 4 ] || return 0
  printf -v a '"%s", ' "${w[@]:4}"
  printf 'missing = [%s]\n' "${a%, }" >>"$f"
}

# _hi_table_is_rectangular <text> - every line of every boxed table in <text>
# is the same printed width. A table is a run of lines starting with a left
# edge ($_HI_BOX_*, either glyph set). Outside a UTF-8 locale ${#} counts
# bytes (GLOSSARY: HI.12), so continuation bytes (0x80-0xBF) are dropped
# before counting.
_HI_RECT_MB='─' # the box glyphs' own fill, so it is never a stranger here
function _hi_table_is_rectangular() {
  local stripped plain width=0 len seen=0
  # _hi_strip_ansi once over the whole text, not once per line: sed is
  # already line-oriented (none of its patterns span a newline), so this
  # reads identically for 2 forks total instead of 2 per line.
  while IFS= read -r stripped; do
    case "$stripped" in
    [+\|┌├└│]*)
      if [ "${#_HI_RECT_MB}" = 1 ]; then
        len=${#stripped}
      else
        plain="${stripped//[$'\200'-$'\277']/}"
        len=${#plain}
      fi
      if [ "$width" -eq 0 ]; then
        width=$len
        seen=1
      elif [ "$len" -ne "$width" ]; then
        return 1
      fi
      ;;
    # anything else ends the current table; the next run measures itself afresh,
    # since two tables in one output need not share a width
    *) width=0 ;;
    esac
  done <<<"$(_hi_strip_ansi "$1")"
  [ "$seen" -eq 1 ]
}

# _hi_check_requires <bin> <label> <predicate...> - _hi_check, unless <bin> is
# missing, in which case the case counts as SKIPPED. The guard lives here, not
# inside the case body, where a `return 0` would report a green OK for a case
# that never ran.
function _hi_check_requires() { _hi_par_requires_body "$1" _hi_check "${@:2}"; }

# _hi_check_requires_eq <bin> <label> <want> <cmd...> - the _hi_expect_eq arm
# of the same guard, the serial twin of _hi_par_check_requires_eq.
function _hi_check_requires_eq() { _hi_par_requires_body "$1" _hi_check_eq "${@:2}"; }

# _hi_cap_memo <var> <probe> - <probe>'s answer, asked once and kept in <var>
# as yes or no. Lazy: the probes write under $_HI_WORKDIR, which does not
# exist until a suite calls _hi_workdir, long after this file is sourced.
function _hi_cap_memo() {
  if [ -z "${!1:-}" ]; then
    if "$2"; then printf -v "$1" '%s' yes; else printf -v "$1" '%s' no; fi
  fi
  [ "${!1}" = yes ]
}

# _hi_can_symlink - whether this filesystem makes real symbolic links. Git
# Bash is the case that matters: `ln -s` on Windows wants Developer Mode or
# administrator, so it fails outright and every case whose *subject* is a
# symlink has nothing to say there.
function _hi_can_symlink() {
  local probe rc=0
  # a private directory rather than a fixed name: the memo dies with a
  # parallel case's subshell, so several cases can be probing at once
  probe="$(mktemp -d "$_HI_WORKDIR/cap.symlink.XXXXXX")"
  : >"$probe/target"
  ln -s "$probe/target" "$probe/link" 2>/dev/null || :
  [ -L "$probe/link" ] || rc=1
  rm -rf "$probe"
  return "$rc"
}

# _hi_can_lock_out - whether a mode can refuse us a write; not as root (the
# FreeBSD VM, most containers), which ignores the bits.
function _hi_can_lock_out() {
  local probe rc=1
  probe="$(mktemp -d "$_HI_WORKDIR/cap.lockout.XXXXXX")"
  mkdir -p "$probe/dir"
  chmod 555 "$probe/dir"
  # stderr first: the message a refused `>` prints is the shell's own, and a
  # 2>/dev/null after the redirection that fails comes too late to catch it
  : 2>/dev/null >"$probe/dir/probe" || rc=0
  chmod 755 "$probe/dir"
  rm -rf "$probe"
  return "$rc"
}

# _hi_is_msys - MSYS or Cygwin, by $OSTYPE, answering two capabilities: no
# fork_concurrency (backgrounded jobs serialize there), and no mode_bits (the
# runtime adds an executable guess from a `#!` line to what `ls -l` shows).
function _hi_is_msys() {
  case "${OSTYPE:-}" in msys* | cygwin*) return 0 ;; esac
  return 1
}

# _hi_mode_string <file> - <file>'s permission string, for a "did the mode
# survive a rewrite" before/after compare. Read via `ls -l`'s first field,
# not `stat`, whose flags differ GNU/BSD - `stat -c` is Linux-only, `stat -f`
# BSD/macOS-only, and there is no portable third spelling.
function _hi_mode_string() {
  # shellcheck disable=SC2012 # every caller's path is a fixture it just wrote
  ls -l "$1" | awk '{ print $1 }'
}

# _hi_can_mkdir_mode - whether `mkdir -m <mode>` creates the directory and
# exits 0; under a Windows-owned temp tree the chmod half fails after the
# directory exists. Probed, since the filesystem decides, not the runtime.
function _hi_can_mkdir_mode() {
  local probe="$_HI_WORKDIR/cap.mkdirmode" rc=0
  mkdir -m 700 "$probe" 2>/dev/null || rc=1
  rm -rf "$probe"
  return "$rc"
}

# _hi_gpg_test_key <homedir> <identity> <err-file> <quick-generate-key args...>
# - a throwaway passphrase-free GPG key in <homedir> (the caller's, mode
# 700). The agent is started first, since Git for Windows' gpg cannot
# auto-start one, and --pinentry-mode loopback keeps some builds off a
# pinentry. <err-file> is dumped on failure.
function _hi_gpg_test_key() {
  local home="$1" identity="$2" err="$3"
  shift 3
  gpgconf --homedir "$home" --launch gpg-agent >/dev/null 2>&1 || true
  if ! GNUPGHOME="$home" gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$identity" "$@" 2>"$err"; then
    _hi_dump_log "gpg --quick-generate-key ($identity) failed" "$err" >&2
    return 1
  fi
}

# Whether gpg can reach an agent from a fresh homedir: Git for Windows' gpg
# cannot start one, and macOS's long $TMPDIR can overflow the socket path, so
# the homedir sits under /tmp as the suites' do. The agent is killed after.
function _hi_can_reach_gpg_agent() {
  local home rc=1
  command -v gpg >/dev/null 2>&1 && command -v gpgconf >/dev/null 2>&1 &&
    home="$(mktemp -d /tmp/hi.gpgcap.XXXXXX 2>/dev/null)" || return 1
  chmod 700 "$home"
  gpgconf --homedir "$home" --launch gpg-agent >/dev/null 2>&1 &&
    gpg-connect-agent --homedir "$home" /bye >/dev/null 2>&1 && rc=0
  gpgconf --homedir "$home" --kill all >/dev/null 2>&1 || true
  rm -rf "$home"
  return "$rc"
}

# _hi_can_shape_netem - whether the netem qdisc is loadable here, what the
# ssh suite's `starved` case needs to shape a container's own eth0. A
# container cannot load a kernel module itself - `modprobe` inside one only
# ever sees the host's module state - so this is a host question, answered
# once from /proc/modules or /sys/module rather than paid for per case.
function _hi_can_shape_netem() {
  grep -q '^sch_netem ' /proc/modules 2>/dev/null || [ -d /sys/module/sch_netem ]
}

# _hi_can_shim_applets - whether `sh` runs a PATH entry named like one of its
# own applets. A busybox built to prefer applets runs its `tar` whatever PATH
# holds, so a case that hides a tool from `sh` cannot hide that one.
function _hi_can_shim_applets() {
  local dir="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/cap.applets" sh_bin out
  sh_bin="$(command -v sh)"
  _hi_script "$dir/tar" '#!/bin/sh' 'echo shim'
  out="$(PATH="$dir" "$sh_bin" -c tar 2>/dev/null)"
  [ "$out" = shim ]
}

# _hi_capable <capability> - whether this machine can do <capability> at all.
# The roster, and the one place either guard below asks:
#
#   symlink           `ln -s` makes a real link (tested by `[ -L ]`: Git Bash
#                     without Developer Mode may silently copy)
#   pty               python3 can allocate one ($_HI_PTY_FORCED; not Windows)
#   lockout           a mode can refuse us a write (not as root)
#   fork_concurrency  background jobs overlap (not MSYS, _hi_is_msys)
#   mode_bits         a permission string is chmod's alone (not MSYS)
#   mkdir_mode        `mkdir -m` succeeds whole (_hi_can_mkdir_mode)
#   gpg_agent         a gpg-agent answers (_hi_can_reach_gpg_agent)
#   netem             the netem qdisc loads (the host ran `modprobe sch_netem`)
#   applet_shims      `sh` runs a PATH entry over a busybox applet
#
# Exit 2 for an unknown capability, so a typo fails rather than skips.
function _hi_capable() {
  case "$1" in
  symlink) _hi_cap_memo _HI_CAP_SYMLINK _hi_can_symlink ;;
  pty) [ "${#_HI_PTY_FORCED[@]}" -gt 0 ] ;;
  lockout) _hi_cap_memo _HI_CAP_LOCKOUT _hi_can_lock_out ;;
  fork_concurrency | mode_bits) ! _hi_is_msys ;;
  mkdir_mode) _hi_cap_memo _HI_CAP_MKDIR_MODE _hi_can_mkdir_mode ;;
  gpg_agent) _hi_cap_memo _HI_CAP_GPG_AGENT _hi_can_reach_gpg_agent ;;
  netem) _hi_cap_memo _HI_CAP_NETEM _hi_can_shape_netem ;;
  applet_shims) _hi_cap_memo _HI_CAP_APPLET_SHIMS _hi_can_shim_applets ;;
  *)
    _hi_cecho "_hi_capable: unknown capability '$1'" "$RED" >&2
    return 2
    ;;
  esac
}

# _hi_check_capable <capability> <label> <predicate...> - _hi_check, unless this
# machine cannot do <capability>, when the case is SKIPPED (a `return 0` in
# the case would report OK). _hi_check_requires' twin for a facility.
function _hi_check_capable() { _hi_par_capable_body "$1" _hi_check "${@:2}"; }

# _hi_script <file> [line...] - <file> written as those lines, or stdin with
# none, executable, its directory made first when missing
function _hi_script() {
  [ -d "${1%/*}" ] || mkdir -p "${1%/*}"
  if [ $# -gt 1 ]; then printf '%s\n' "${@:2}" >"$1"; else cat >"$1"; fi && chmod +x "$1"
}

# _hi_fake_path <name> <bin...> - a $_HI_SUITE_WORKDIR/<name> directory of
# no-op executables, printed - for suites that prove a resolution ladder
# ("candidate X is missing, does it fall through to Y") against a PATH they
# control rather than against whatever this machine has. Built once per name
# and suite, not per case: the callers ask for the same set many times over.
function _hi_fake_path() {
  local dir="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/$1" bin
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for bin in "$@"; do
      _hi_script "$dir/$bin" '#!/bin/sh' 'exit 0'
    done
  fi
  printf '%s' "$dir"
}

# _hi_real_path <name> <tool...> - the real-binary half of _hi_fake_path, same
# build-once contract: a $_HI_SUITE_WORKDIR/<name> directory of the named
# real tools, printed, for suites that replace $PATH. A missing tool is
# skipped. Symlinks where _hi_can_symlink says they work (checked with
# `[ -L ]`), else `#!/bin/sh` exec wrappers, since MSYS can fake a link.
function _hi_real_path() {
  local dir="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/$1" tool real
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    # printf always: OpenBSD's sh has no printf builtin, so a shim on this PATH
    # would find none; everywhere else the builtin wins and the link is inert
    for tool in "$@" printf; do
      # `type -P`, since `command -v printf` names the builtin, which would
      # link onto itself. A builtin-only tool is skipped.
      real="$(type -P "$tool" 2>/dev/null)" || continue
      [ -n "$real" ] || continue
      rm -f "$dir/$tool"
      if _hi_capable symlink; then
        ln -sf "$real" "$dir/$tool" 2>/dev/null || :
        [ -L "$dir/$tool" ] && continue
      fi
      _hi_script "$dir/$tool" '#!/bin/sh' "exec \"$real\" \"\$@\""
    done
  fi
  printf '%s' "$dir"
}

# _hi_path_dirs_of <tool...> - the directories of $PATH holding the named tools,
# in $PATH's order, colon-joined: a short $PATH for code that probes for
# tools no runner has (each miss stats every directory, ~45 on Windows). Real
# directories, so no wrapper costs a fork.
function _hi_path_dirs_of() {
  local real d found=":" out="" IFS
  type -P "$@" >"$_HI_WORKDIR/tool-dirs" 2>/dev/null || :
  while IFS= read -r real; do
    found="$found${real%/*}:"
  done <"$_HI_WORKDIR/tool-dirs"
  IFS=:
  for d in $PATH; do
    case "$found" in *":$d:"*) ;; *) continue ;; esac
    case ":$out:" in *":$d:"*) continue ;; esac
    out="$out${out:+:}$d"
  done
  printf '%s' "${out:-$PATH}"
}

# _hi_git_fixture - a fresh one-commit repo on a branch literally named "main"
# (forced, whatever git's initial-branch config says), printed: a private
# `cp -r` of a template built once per suite, saving six git calls. It holds
# one clean tracked file.txt.
function _hi_git_fixture() {
  local dir template="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/git-template"
  if [ ! -d "$template" ]; then
    mkdir -p "$template"
    git -C "$template" init -q
    git -C "$template" symbolic-ref HEAD refs/heads/main
    git -C "$template" config user.email test@example.com
    git -C "$template" config user.name "Test"
    printf 'one\n' >"$template/file.txt"
    git -C "$template" add file.txt
    git -C "$template" commit -q -m initial
  fi
  dir="$(mktemp -d "$_HI_WORKDIR/repo.XXXXXX")"
  cp -r "$template/." "$dir/"
  printf '%s' "$dir"
}

# _hi_probe_shims <dir> [running-name] - fake docker/podman/nomad/kubectl in
# <dir>, answering only the exact calls hi.sh's predicates and doctor.sh's
# `ps` make and failing anything else, so a changed call fails a test.
# <running-name> (default "yes") is the one running target.
function _hi_probe_shims() {
  local dir="$1" running="${2:-yes}"
  mkdir -p "$dir"

  cat >"$dir/docker" <<EOF
#!/bin/sh
[ "\$1" = ps ] && exit 0
[ "\$1 \$2 \$3" = "container inspect -f" ] || exit 1
case "\$5" in $running) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  # podman is a drop-in for docker in hi.sh, so the shim is the same file
  cp "$dir/docker" "$dir/podman"

  cat >"$dir/nomad" <<EOF
#!/bin/sh
[ "\$1 \$2 \$3" = "alloc status -t" ] || exit 1
case "\$5" in $running) printf 'running\n' ;; *) printf 'pending\n' ;; esac
EOF

  cat >"$dir/kubectl" <<EOF
#!/bin/sh
[ "\$1 \$2 \$4" = "get pod -o" ] || exit 1
case "\$3" in $running) printf 'Running\n' ;; *) printf 'Pending\n' ;; esac
EOF

  chmod +x "$dir/docker" "$dir/podman" "$dir/nomad" "$dir/kubectl"
}

# _hi_scratch_tree <name> <dir...> - a throwaway say-hi under $_HI_WORKDIR/<name>
# holding copies of the named top-level directories; prints its _HI_HOME.
# `link:<dir>` symlinks a read-only directory instead, so bashcov credits the
# repo file; never for one a case writes into.
#
function _hi_scratch_tree() {
  local name="$1" root="$_HI_WORKDIR/$1/say-hi" dir
  shift
  mkdir -p "$root"
  for dir in "$@"; do
    case "$dir" in
    link:*) ln -sfn "$_HI_ROOT/${dir#link:}" "$root/${dir#link:}" ;;
    *) cp -r "$_HI_ROOT/$dir" "$root/" ;;
    esac
  done
  printf '%s' "$_HI_WORKDIR/$name"
}

# _hi_subcmd_run <home> <args...> - runs a _hi_scratch_tree's hi.sh as a
# process, $_HI_HOME at <home>, for hi's local sub-commands, which sourcing
# cannot reach past hi.sh's BASH_SOURCE guard.
function _hi_subcmd_run() {
  local home="$1"
  shift
  (_HI_HOME="$home" "$home/say-hi/hi.sh" "$@" 2>&1)
}

# _hi_wiring_for <member...> - the wiring.sh a client packs for those members
# (pack.sh's _hi_overlay_wiring), on stdout: from a child bash with no
# arguments left, since sourcing hi.sh runs it on them
function _hi_wiring_for() {
  # shellcheck disable=SC2016 # the child bash expands its own script
  bash -c 'm=("$@") && set -- && source "$_HI_LAUNCHER" && _hi_overlay_wiring w "${m[@]}" && printf %s "$w"' _ "$@"
}

# _hi_settings_fixture <name> <fn...> - run <fn...> with $_HI_ROOT,
# $_HI_CONFIG_DIR, and $_HI_SETTINGS at throwaway paths under
# $_HI_WORKDIR/<name>, so install.sh's and configure.sh's writers never touch
# the checkout or the developer's overlay. The overlay is apart from the
# tree's config/, so a write outside the tree is visible. GLOSSARY: HI.34
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir" _HI_CONFIG_DIR="$dir/overlay"
  local _HI_SETTINGS="$dir/overlay/settings.sh"
  mkdir -p "$dir/common" "$dir/config" "$dir/overlay"
  shift
  "$@" >/dev/null
}

# where _hi_settings_fixture's run writes, as the assertions see it
function _hi_fixture_settings() { printf '%s' "$_HI_WORKDIR/$1/overlay/settings.sh"; }

# The suites' small <key> -> <value> maps (which shell image built, where a
# binary is), as a newline-separated "<key>=<value>" string in a plain variable:
# associative arrays are bash 4 and macOS still ships bash 3.2, where `local -A`
# is a fatal "invalid option". _hi_kv_set appends and _hi_kv_get returns the
# *last* value set for a key, so re-setting one wins with no rewriting.
_HI_KV_NL=$'\n'

# _hi_kv_set <var> <key> <value> - eval, because bash 3.2 has no namerefs; the
# caller's `local` is reachable through bash's dynamic scoping either way.
function _hi_kv_set() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_value="$3"
  eval "$_hi_kv_var=\"\${$_hi_kv_var:-}\$_hi_kv_key=\$_hi_kv_value\$_HI_KV_NL\""
}

# _hi_kv_get <var> <key> - print the value, non-zero if the key was never set
function _hi_kv_get() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_store _hi_kv_entry found="" rc=1
  eval "_hi_kv_store=\${$_hi_kv_var:-}"
  while IFS= read -r _hi_kv_entry; do
    [ "${_hi_kv_entry%%=*}" = "$_hi_kv_key" ] || continue
    found="${_hi_kv_entry#*=}"
    rc=0
  done <<<"$_hi_kv_store"
  printf '%s' "$found"
  return "$rc"
}

# _hi_transcript_is_clean <label> <transcript-file> - fail if the session
# printed shell errors. On bash 3.2 a bash-4 builtin is rarely fatal: the
# session comes up and every marker lands, but each connect prints
# "mapfile: command not found", which only this catches.
_HI_SHELL_ERROR_RE='command not found|invalid option|unbound variable|bad substitution|syntax error|not a valid identifier'

function _hi_transcript_is_clean() {
  local label="$1" file="$2" hits
  hits="$(grep -nE "$_HI_SHELL_ERROR_RE" "$file" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    _hi_align " | [$label] -- transcript is free of shell errors" "OK" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED: the session printed shell errors" "$RED"
  printf '%s\n' "$hits" | sed 's/^/      /'
  _hi_note_failure "[$label] transcript has shell errors"
  return 1
}

function _hi_rendered() {
  printf '%b' "$1"
}

function _hi_has_rendered() {
  local needle
  printf -v needle '%b' "$2"
  [[ "$1" == *"$needle"* ]]
}

# _hi_file_is <file> <body> - <file> holds exactly <body> (%b, so \n is a
# line break); what it holds instead is printed when it does not
function _hi_file_is() {
  local want
  want="$(printf '%b' "$2")"
  [ "$(cat "$1" 2>&1)" = "$want" ] && return 0
  _hi_cecho " | got: [$(cat "$1" 2>&1)]" "$RED"
  return 1
}

# _hi_stub_tools <tool...> - a directory of do-nothing executables by exactly
# those names, printed, for a caller's $PATH: _hi_overlay_src ships home's
# config only with its tool on this machine, and a runner has no micro or
# helix. One directory per set, so no case sees another's stubs.
function _hi_stub_tools() {
  local IFS=-
  _hi_fake_path "stub-$*" "$@"
}

# _hi_trace_env - fills the caller's `local -a _hi_trace` with what bashcov
# follows a bash child through, for an `env -i` to hand on: the xtrace trio.
# Stripped, every line the child runs reads as untested. Empty outside a
# sweep, and no fork either way.
function _hi_trace_env() {
  _hi_trace=()
  if [ -n "${BASH_XTRACEFD:-}" ] && [[ $- == *x* ]]; then
    _hi_trace=(SHELLOPTS=xtrace "PS4=$PS4" "BASH_XTRACEFD=$BASH_XTRACEFD")
  fi
}

# _hi_login_env <home> <cmd...> - `env -i` plus only what a login shell has:
# no _HI_HOME (it would answer what install.sh derives) and no _HI_CONFIG_DIR;
# $SHELL because install.sh reports ${SHELL##*/} under `set -u`.
#
# Bounded by $_HI_LOGIN_TIMEOUT (180s, generous for emulated Git Bash arm64),
# so a wedged shell fails its case with 124 instead of freezing the job.
# Without `timeout` (stock macOS) it runs bare.
function _hi_login_env() {
  local home="$1"
  local -a bound=() _hi_trace
  shift
  command -v timeout >/dev/null 2>&1 &&
    bound=(timeout -k 5 "${_HI_LOGIN_TIMEOUT:-180}")
  _hi_trace_env
  ${bound[@]+"${bound[@]}"} env -i HOME="$home" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
    SHELL=/bin/bash XDG_CONFIG_HOME="$home/.config" _HI_PROMPT_TOOL="${_HI_PROMPT_TOOL-}" \
    ${_hi_trace[@]+"${_hi_trace[@]}"} "$@"
}

# _hi_bare_bash <toolbox> <tools> <script> [NAME=VALUE...] - <script> in an
# `env -i` bash with only <tools> on PATH, 2>&1. The overlay is aimed at a
# directory never created: left unset, core.sh would source the real
# ~/.config/say-hi of whoever runs the suite into the probe.
function _hi_bare_bash() {
  local box="$1" tools="$2" script="$3" nocfg="$_HI_WORKDIR/$1-nocfg"
  local -a _hi_trace
  shift 3
  _hi_trace_env
  # shellcheck disable=SC2086 # the tool list splits on purpose
  env -i PATH="$(_hi_real_path "$box" $tools)" HOME="$HOME" NO_COLOR=1 \
    XDG_CONFIG_HOME="$nocfg" _HI_CONFIG_DIR="$nocfg/say-hi" \
    _HI_HOME="$_HI_HOME" ${_hi_trace[@]+"${_hi_trace[@]}"} "$@" bash -c "$script" 2>&1
}
