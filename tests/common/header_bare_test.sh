#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# common/header.sh on a target with no coreutils: every row from builtins and
# /proc alone.
# A part of header_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is header_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_HEADER_PART=bare
# shellcheck source=./header_test.sh
source "${BASH_SOURCE[0]%/*}/header_test.sh"

# A target with a shell and awk and nothing else - core_test.sh's barebones
# box, one layer up. The header is the first thing a session prints, so a
# missing uname greeting the user with "command not found" across the
# banner would be a bad first impression; the cells say "?" instead, the way
# every other sysinfo probe answers a missing binary.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_stripped_header() {
  _hi_bare_bash stripped 'bash awk' \
    'source "$_HI_HOME/say-hi/common/core.sh"; source "$_HI_HEADER"; eval "$_HI_CASE_PROBE"' \
    _HI_CASE_PROBE="$1"
}

function test_system_info_without_uname_says_unknown() {
  local out
  out="$(_hi_stripped_header "$_HI_ROW_FNS; _hi_sysinfo_row")"
  [[ "$out" == *"?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out" && return 0
  # once red on Windows arm64 with nothing to say; the row itself says why
  _hi_cecho " | the row without uname came out as:" "$RED"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

# ...except the clocks, which bash 4.2+ formats itself (printf's %(...)T): a
# missing date(1) costs them nothing there, and 3.2 (macOS's) still says "?"
function test_timestamp_answers_without_date() {
  local out
  out="$(_hi_stripped_header timestamp)"
  ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out" || _hi_why out _HI_SHELL_ERROR_RE || return 1
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    [[ "$out" =~ [0-9]{2}:[0-9]{2}:[0-9]{2}\ UTC ]]
  else
    [[ "$out" == *"?"* ]]
  fi
}

# unlike the other sysinfo cells, _hi_cell_uptime's only external dependency
# on Linux is awk - which "stripped" still carries, since most probes need it -
# so this stays a smoke test for "no raw shell error leaks out", not a claim
# that the cell renders "?": a real /proc/uptime under a real Linux kernel
# answers it regardless of what else is missing.
# shellcheck disable=SC2016 # $u expands in the stripped child bash, not here
function test_uptime_cell_survives_a_stripped_environment() {
  local out
  out="$(_hi_stripped_header '_hi_cell_uptime u; printf "%s" "$u"')"
  { [[ "$out" == *"Up: "* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"; } || _hi_why out _HI_SHELL_ERROR_RE
}

# The exact case the comment above contrasts itself with: every branch of
# _hi_cell_ip's first stage is an external binary ("ip", "hostname",
# "ifconfig", "ipconfig") the stripped ("bash and awk only") target has none
# of, so unlike uptime this doubles as a claim about the value, not only
# about failing quietly - "?" is the only answer this environment can give.
# shellcheck disable=SC2016 # $i expands in the stripped child bash, not here
function test_ip_cell_says_unknown_under_a_stripped_environment() {
  local out
  out="$(_hi_stripped_header '_hi_cell_ip i; printf "%s" "$i"')"
  { [[ "$out" == *"IP: ?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"; } || _hi_why out _HI_SHELL_ERROR_RE
}

# the whole banner, since that is what a session actually prints
function test_banner_renders_without_coreutils() {
  local out
  out="$(_hi_stripped_header 'banner Connected "" ""')"
  { [[ "$out" == *Connected* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"; } || _hi_why out _HI_SHELL_ERROR_RE
}

# --- the non-Linux arms of the sysinfo cells, uptime and ip, on shims ------
#
# The macOS and Windows probes cannot run here, so each platform is a PATH
# dir of fake tools answering exactly the invocations header.sh makes, and
# _HI_LINUX_RELEASE pointed at nothing so the kernel string decides the arm.
# What each case asserts is the parse: the figures below are chosen so a
# wrong field, a wrong page size, or a byte order read the wrong way round
# gives a different number.

# _hi_platform_header <shims> <probe> [env...] - <probe> in a child bash
# whose PATH is <shims> plus the coreutils the probes themselves fork
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_platform_header() {
  local shims="$1" probe="$2"
  shift 2
  # _HI_LINUX_RELEASE is set after the source: paths.sh (via core.sh) writes
  # its /etc/os-release default over whatever the environment carried in
  env "$@" PATH="$shims:$(_hi_real_path platform-tools bash sh awk sed date fold mktemp rm sleep)" \
    NO_COLOR=1 _HI_CASE_PROBE="$probe" \
    bash -c 'source "$_HI_HEADER"; _HI_LINUX_RELEASE=/nonexistent; eval "$_HI_CASE_PROBE"' 2>&1
}

# an Apple Silicon mac: sysctl has no hw.cpufrequency (the cpu cell fails
# closed to "?"), and vm_stat's page size is 16K and read from its own header
function _hi_mac_shims() {
  local dir="$_HI_WORKDIR/mac-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
    printf '#!/bin/sh\necho 15.1\n' >"$dir/sw_vers"
    cat >"$dir/sysctl" <<'EOF'
#!/bin/sh
case "$2" in
hw.ncpu) echo 8 ;;
hw.memsize) echo 17179869184 ;;
vm.loadavg) echo "{ 2.00 1.50 1.00 }" ;;
# 5430, not 5400: header.sh reads its own `date +%s` on the other side
# of the pipe, so the two clock reads can straddle a second tick and
# land a second either way. Half a minute in puts the figure in the
# middle of the minute the case asserts instead of on its edge.
kern.boottime) echo "{ sec = $(($(date +%s) - 5430)), usec = 0 } Thu Jan  1 00:00:00 2026" ;;
*) exit 1 ;;
esac
EOF
    cat >"$dir/vm_stat" <<'EOF'
#!/bin/sh
printf '%s\n' 'Mach Virtual Memory Statistics: (page size of 16384 bytes)' \
  'Pages free:                              100000.' \
  'Pages active:                            200000.' \
  'Pages wired down:                         50000.' \
  'Pages occupied by compressor:             12500.'
EOF
    cat >"$dir/ifconfig" <<'EOF'
#!/bin/sh
printf '%s\n' 'lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384' \
  '	inet 127.0.0.1 netmask 0xff000000' \
  'en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500' \
  '	inet6 fe80::1%en0 prefixlen 64 secured scopeid 0x4' \
  '	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255'
EOF
    chmod +x "$dir"/*
  fi
  printf '%s' "$dir"
}

# git-bash on Windows: the MINGW kernel string, wmic's two-line answers
# (header, then the value) and ipconfig's CRLF lines
function _hi_windows_shims() {
  local dir="$_HI_WORKDIR/windows-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "MINGW64_NT-10.0-22631 x86_64"\n' >"$dir/uname"
    cat >"$dir/wmic" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
"ComputerSystem get TotalPhysicalMemory") printf 'TotalPhysicalMemory\n17179869184\n' ;;
"cpu get MaxClockSpeed") printf 'MaxClockSpeed\n2400\n' ;;
*) exit 1 ;;
esac
EOF
    cat >"$dir/ipconfig" <<'EOF'
#!/bin/sh
printf '%s\r\n' 'Windows IP Configuration' '' 'Ethernet adapter Ethernet:' \
  '   IPv4 Address. . . . . . . . . . . : 10.0.0.5' \
  '   Subnet Mask . . . . . . . . . . . : 255.255.255.0'
EOF
    chmod +x "$dir"/*
  fi
  printf '%s' "$dir"
}

# _hi_platform_header's Linux twin: same shim discipline, but
# $_HI_LINUX_RELEASE points at a real file so the Linux arm is the one taken
# whatever box this runs on - the mac and Windows helpers above get there by
# pointing it at nothing, and there is no third way to reach this branch.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_linux_header() {
  local shims="$1" probe="$2" rel="$_HI_WORKDIR/os-release"
  shift 2
  [ -f "$rel" ] || printf 'PRETTY_NAME="Test Linux 1.0"\n' >"$rel"
  env "$@" PATH="$shims:$(_hi_real_path platform-tools bash sh awk sed date fold mktemp rm sleep)" \
    NO_COLOR=1 _HI_CASE_PROBE="$probe" _HI_TEST_RELEASE="$rel" \
    bash -c 'source "$_HI_HEADER"; _HI_LINUX_RELEASE="$_HI_TEST_RELEASE"; eval "$_HI_CASE_PROBE"' 2>&1
}

# A Linux box whose `ip` can be silenced: the cell's first stage is `ip -4 -o
# addr show scope global`, and `hostname -I` is the fallback for the hosts
# where that prints nothing. Both answer the field layout header.sh's awk
# reads, so a wrong field number changes the answer.
function _hi_linux_ip_shims() {
  local dir="$_HI_WORKDIR/linux-ip-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "Linux x86_64"\n' >"$dir/uname"
    cat >"$dir/ip" <<'EOF'
#!/bin/sh
[ "${_HI_FAKE_IP_SILENT:-0}" = 1 ] && exit 0
printf '%s\n' '2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0' \
  '3: eth1    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth1'
EOF
    cat >"$dir/hostname" <<'EOF'
#!/bin/sh
[ "$1" = -I ] && printf '198.51.100.7 198.51.100.8 \n'
EOF
    chmod +x "$dir/uname" "$dir/ip" "$dir/hostname"
  fi
  printf '%s' "$dir"
}

function test_ip_cell_on_linux_reads_iproute2() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_linux_header "$(_hi_linux_ip_shims)" '_hi_cell_ip i; printf "[%s]" "$i"')"
  [[ "$out" == *"[IP: 10.0.0.5, 192.0.2.10]"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# `ip` exists and answers nothing on a host with no routable address on an
# iproute2-visible link - a container on a host network among them - and
# `hostname -I` is the second opinion. A bare "?" is reserved for "neither
# tool exists nor has anything to say".
function test_ip_cell_on_linux_falls_back_to_hostname() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_linux_header "$(_hi_linux_ip_shims)" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_FAKE_IP_SILENT=1)"
  [[ "$out" == *"[IP: 198.51.100.7, 198.51.100.8]"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# The five sysinfo cells share one memoized probe ($_HI_SI_PROBED), which
# is what makes $_HI_HEADER_ORDER's per-word toggles free: asking for arch
# alone pays for exactly one probe, and asking for all five pays for the same
# one. Counted by standing a uname in front of the mac shims' that appends a
# line per call, and reading the counter either side of the five getters.
function test_system_info_probes_once_for_all_five_cells() {
  local dir="$_HI_WORKDIR/probe-count" count out probe
  count="$_HI_WORKDIR/uname.calls"
  mkdir -p "$dir"
  : >"$count"
  cat >"$dir/uname" <<EOF
#!/bin/sh
printf 'x\n' >>"$count"
echo "Darwin arm64"
EOF
  chmod +x "$dir/uname"
  # awk, not wc: _hi_platform_header's PATH carries only the tools the probes
  # themselves fork, and wc is not one of them
  probe="pre=\$(awk 'END { print NR }' '$count')"
  probe="$probe; v=''; _hi_cell_arch v; _hi_cell_os v; _hi_cell_cores v"
  probe="$probe; _hi_cell_cpu v; _hi_cell_ram v"
  probe="$probe; post=\$(awk 'END { print NR }' '$count')"
  probe="$probe; printf 'delta=%s' \$((post - pre))"
  out="$(_hi_platform_header "$dir:$(_hi_mac_shims)" "$probe")"
  [[ "$out" == *"delta=1"* ]] || {
    _hi_cecho " | five cells cost more than one probe: $out" "$RED"
    return 1
  }
}

function test_system_info_on_a_mac() {
  local out
  out="$(_hi_platform_header "$(_hi_mac_shims)" "$_HI_ROW_FNS; _hi_sysinfo_row")"
  # used = (200000 + 50000 + 12500) pages * 16K = 4.0G of 16G; 2.00 on 8
  # cores is 25%; sysctl answered no clock, so the cpu cell fails closed
  [[ "$out" == *"macOS 15.1"* && "$out" == *"arm64"* && "$out" == *"Cores: 8 (25%)"* &&
    "$out" == *"RAM: 4/16G"* && "$out" == *"CPU: ? GHz"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_uptime_and_ip_cells_on_a_mac() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$(_hi_mac_shims)" '_hi_cell_uptime u; _hi_cell_ip i; printf "%s\n%s\n" "$u" "$i"')"
  # kern.boottime 5430s ago; ifconfig's inet line, not inet6 and not lo0
  [[ "$out" == *"Up: 1h 30m"* && "$out" == *"IP: 192.0.2.10"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_system_info_on_windows() {
  local out
  out="$(_hi_platform_header "$(_hi_windows_shims)" "$_HI_ROW_FNS; _hi_sysinfo_row" NUMBER_OF_PROCESSORS=4)"
  # wmic exposes the rated clock
  [[ "$out" == *"Windows (MINGW64_NT-10.0-22631)"* && "$out" == *"Cores: 4"* &&
    "$out" == *"RAM: 16G"* && "$out" == *"CPU: 2.4 GHz"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# _HI_IP_HIDE: a docker bridge address is noise on any box that runs
# containers, so the default hides 172.*; `none` shows everything; any other
# value is a list of globs. The filter is checked on its own, then through
# the cell on a mac-shaped box whose ifconfig answers two addresses.
function test_ip_filter_hides_the_bridge_by_default() {
  local out
  unset _HI_IP_HIDE
  _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "10.0.0.5" ] || _hi_why out || return 1
  _hi_ip_filter out "10.0.0.5,172.18.0.1,192.0.2.10"
  [ "$out" = "10.0.0.5,192.0.2.10" ] || _hi_why out
}

# `none` hides nothing; an empty value is unset, so it hides the default
# range - what the wizard's preview shows for it too
function test_ip_filter_none_and_empty_keep_everything() {
  local out
  _HI_IP_HIDE=none _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "172.17.0.2,10.0.0.5" ] || _hi_why out || return 1
  _HI_IP_HIDE="" _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "10.0.0.5" ] || _hi_why out
}

function test_ip_filter_takes_a_glob_list() {
  local out
  _HI_IP_HIDE="10.*" _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "172.17.0.2" ] || _hi_why out || return 1
  _HI_IP_HIDE="10.* 172.*" _hi_ip_filter out "172.17.0.2,10.0.0.5,192.0.2.10"
  [ "$out" = "192.0.2.10" ] || _hi_why out || return 1
  _HI_IP_HIDE="192.0.2.1?" _hi_ip_filter out "192.0.2.10,192.0.2.100"
  [ "$out" = "192.0.2.100" ] || _hi_why out
}

# every address hidden: the cell is empty (so the header drops it), never
# "?", which still means no routable address was found at all
function test_ip_cell_is_empty_when_every_address_is_hidden() {
  local dir="$_HI_WORKDIR/ip-hide-shims" out
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
  printf '#!/bin/sh\nprintf "\tinet 127.0.0.1 netmask 0xff000000\n\tinet 172.17.0.2 netmask 0xffff0000\n\tinet 10.0.0.5 netmask 0xffffff00\n"\n' >"$dir/ifconfig"
  chmod +x "$dir/uname" "$dir/ifconfig"
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"')"
  [[ "$out" == *"[IP: 10.0.0.5]"* ]] || {
    _hi_cecho " | default got: $out" "$RED"
    return 1
  }
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_IP_HIDE="10.* 172.*")"
  [[ "$out" == *"[]"* ]] || {
    _hi_cecho " | all hidden got: $out" "$RED"
    return 1
  }
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_IP_HIDE=none)"
  [[ "$out" == *"[IP: 172.17.0.2, 10.0.0.5]"* ]] || {
    _hi_cecho " | none got: $out" "$RED"
    return 1
  }
}

# ...and the header itself then prints no IP cell at all. Shimmed the same
# way the sibling above is: hi_header run against the *real* uname/ifconfig
# only proves this on a box whose live network happens to hand back a
# non-loopback IPv4 the parser recognizes - on one that doesn't, _hi_cell_ip
# takes its "nothing routable found" path and prints "IP: ?" regardless of
# $_HI_IP_HIDE, which still contains "IP:" and fails this for a reason that
# has nothing to do with the hiding this test means to check.
function test_header_omits_the_ip_cell_when_hidden() {
  local dir="$_HI_WORKDIR/ip-hide-header-shims" out
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
  printf '#!/bin/sh\nprintf "\tinet 127.0.0.1 netmask 0xff000000\n\tinet 10.0.0.5 netmask 0xffffff00\n"\n' >"$dir/ifconfig"
  chmod +x "$dir/uname" "$dir/ifconfig"
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" 'hi_header Connected' _HI_HEADER_ORDER='utc ip' _HI_IP_HIDE='*')"
  [[ "$out" == *"Connected"* && "$out" == *" UTC"* && "$out" != *"IP:"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_uptime_and_ip_cells_on_windows() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$(_hi_windows_shims)" '_hi_cell_uptime u; _hi_cell_ip i; printf "%s\n%s\n" "$u" "$i"')"
  # no sysctl on git-bash: uptime is not probed at all; ipconfig's CR is gone
  [[ "$out" == *"Up: ?"* && "$out" == *"IP: 10.0.0.5"* && "$out" != *$'\r'* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# no uname and no /etc/os-release: nothing says what this box is, and the
# cells say "?" rather than guessing at macOS
function test_system_info_with_no_kernel_and_no_release_says_unknown() {
  local out
  out="$(_hi_platform_header "$(_hi_fake_path no-kernel-tools true)" "$_HI_ROW_FNS; _hi_sysinfo_row")"
  { [[ "$out" == *"?"* && "$out" != *"macOS"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"; } || _hi_why out _HI_SHELL_ERROR_RE
}

# --- the row painter's two width-neutral switches -----------------------

# $_HI_DISABLE_LEAD_SPACE drops the leading space and only that: the " | " between
# cells stays, on a header row and on the packages check's own rows
function test_no_lead_space_drops_only_the_leading_space() {
  local out
  out="$(NO_COLOR=1 _HI_DISABLE_LEAD_SPACE=1 bash -c 'source "$_HI_HEADER"; header_row alpha beta')"
  # matched by shape, not in full: the row is padded out to its right edge now,
  # and the width that pad answers to is the terminal's. What this case is
  # about is the two ends - no leading space, and the " | " between the cells
  # kept - so it pins those and the closing pipe.
  # the pad still budgets for the leading space this toggle drops, so the
  # closed row lands one column short of the banner rather than at it - a
  # pre-existing wrinkle of the toggle, not this case's concern
  [[ "$out" == "| alpha | beta"*"|" ]] && [ "${#out}" -eq 79 ] || {
    _hi_cecho " | got: [$out]" "$RED"
    return 1
  }
  out="$(NO_COLOR=1 bash -c 'source "$_HI_HEADER"; header_row alpha beta')"
  [[ "$out" == " | alpha | beta"*"|" ]] && [ "${#out}" -eq 80 ] || _hi_why out
}

function test_no_lead_space_applies_to_the_packages_check() {
  local out
  mkdir -p "$_HI_WORKDIR/pkgcfg"
  printf '%s = []\n' "$_HI_REAL_CMD" >"$_HI_WORKDIR/pkgcfg/packages"
  out="$(NO_COLOR=1 _HI_DISABLE_LEAD_SPACE=1 _HI_CONFIG_DIR="$_HI_WORKDIR/pkgcfg" bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" == "|"* && "$out" == *"$_HI_REAL_CMD"* ]] || _hi_why out _HI_REAL_CMD
}

# a row with nothing to place still ends the line: hi_header's own loop
# relies on the reset-and-newline to close whatever color a prior cell left
function test_header_row_with_no_cells_prints_a_bare_line() {
  local out
  out="$(NO_COLOR=1 bash -c 'source "$_HI_HEADER"; header_row; printf END')"
  [ "$out" = $'\nEND' ] || _hi_why out
}

# a git identity has to exist to be masked; none at all is its own text
function test_identity_without_a_git_email_says_so() {
  local out
  out="$(cd "$_HI_WORKDIR" && NO_COLOR=1 \
    PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 bash -c "source \"\$_HI_HEADER\"; $_HI_ROW_FNS; _hi_identity_row")"
  [[ "$out" == *"No Git ID Found"* ]] || _hi_why out
}

# ...and one that exists shows its local part, the domain a run of mask
# glyphs exactly as long (`*` under _HI_ASCII=1), never the domain itself
function test_identity_masks_the_git_email_domain() {
  local cfg="$_HI_WORKDIR/gitconfig-email" out
  printf '[user]\n\temail = alice@example.com\n' >"$cfg"
  out="$(cd "$_HI_WORKDIR" && NO_COLOR=1 _HI_ASCII=1 GIT_CONFIG_GLOBAL="$cfg" \
    PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 bash -c "source \"\$_HI_HEADER\"; $_HI_ROW_FNS; _hi_identity_row")"
  [[ "$out" == *'alice@***********'[!*]* && "$out" != *example.com* ]] || {
    _hi_cecho "   identity row: $out" "$RED"
    return 1
  }
}

# the alternate-hue table's two ends: a word with an entry, and one without,
# which reads empty so the caller keeps the primary rather than a stray code
function test_header_word_alt_is_empty_for_an_unknown_word() {
  local v=set
  _hi_header_word_alt no-such-word v
  [ -z "$v" ] || _hi_why v || return 1
  _hi_header_word_alt uptime v
  [ "$v" = "$BRGREEN" ] || _hi_why v BRGREEN
}

function run_header_bare_tests() {
  _hi_header_begin

  _hi_h1 "Testing common/header.sh (a bare target)"

  _hi_h2 "Testing: a target with no coreutils"
  _hi_check "System_info says ? without uname" test_system_info_without_uname_says_unknown
  _hi_check "System_info on a mac, from shims" test_system_info_on_a_mac
  _hi_check "Uptime and IP cells on a mac" test_uptime_and_ip_cells_on_a_mac
  _hi_check "The ip cell reads iproute2 on Linux" test_ip_cell_on_linux_reads_iproute2
  _hi_check "The ip cell falls back to hostname -I" test_ip_cell_on_linux_falls_back_to_hostname
  _hi_check "Five cells cost one probe" test_system_info_probes_once_for_all_five_cells
  _hi_check "System_info on Windows (git-bash), from shims" test_system_info_on_windows
  _hi_check "Uptime and IP cells on Windows" test_uptime_and_ip_cells_on_windows
  _hi_check "_HI_IP_HIDE hides the bridge by default" test_ip_filter_hides_the_bridge_by_default
  _hi_check "_HI_IP_HIDE none/empty keep everything" test_ip_filter_none_and_empty_keep_everything
  _hi_check "_HI_IP_HIDE takes a glob list" test_ip_filter_takes_a_glob_list
  _hi_check "The ip cell is empty when every address is hidden" test_ip_cell_is_empty_when_every_address_is_hidden
  _hi_check "The header omits a hidden ip cell" test_header_omits_the_ip_cell_when_hidden
  _hi_check "System_info with no kernel and no os-release says ?" test_system_info_with_no_kernel_and_no_release_says_unknown
  _hi_check "_HI_DISABLE_LEAD_SPACE drops only the leading space" test_no_lead_space_drops_only_the_leading_space
  _hi_check "...on the packages check too" test_no_lead_space_applies_to_the_packages_check
  _hi_check "A row with no cells prints a bare line" test_header_row_with_no_cells_prints_a_bare_line
  _hi_check "Identity without a git email says so" test_identity_without_a_git_email_says_so
  _hi_check "Identity masks a git email's domain" test_identity_masks_the_git_email_domain
  _hi_check "Alternate hue is empty for an unknown word" test_header_word_alt_is_empty_for_an_unknown_word
  _hi_check "Timestamp answers without date" test_timestamp_answers_without_date
  _hi_check "The uptime cell survives a stripped environment" test_uptime_cell_survives_a_stripped_environment
  _hi_check "The ip cell says unknown under a stripped environment" test_ip_cell_says_unknown_under_a_stripped_environment
  _hi_check "The banner still renders" test_banner_renders_without_coreutils

  _hi_suite_end "header.sh (a bare target)"
}

run_header_bare_tests
