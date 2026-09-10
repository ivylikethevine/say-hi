#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The connect/disconnect banner, one implementation for every shell (fish
# shells out here); the packages check (full_check) lives at the bottom too.
#
# No strict-mode bracket of its own: core.sh's tail releases `set -euo
# pipefail` on every source (an error must not close an interactive shell),
# so a bracket opened here was dead the moment core.sh below loaded. The
# `|| true` guards through this file protect a *caller* running under its own
# strict mode (scripts/configure.sh's previews do).

# core.sh through this file's own path; it derives the tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# shellcheck source=./core.sh
source "$_hi_d/core.sh"
unset _hi_d

# <var> gets $2's visible column width - one leading color-var prefix
# stripped first, since a header_row cell never carries more than the one its
# caller opens it with (the reset between cells is header_row's own, added
# below, never the caller's). The color vars hold the literal two characters
# `\e`, not a real escape byte (core.sh assigns them single-quoted; only
# header_row's own final `printf '%b'` interprets it), so the pattern matches
# that literal prefix rather than $'\e'.
function _hi_visible_width() {
  local s="$2" re='^\\e\[[0-9;]*m(.*)$'
  [[ "$s" =~ $re ]] && s="${BASH_REMATCH[1]}"
  # where ${#} counts bytes (core.sh's $_HI_BYTE_COUNTS), the UTF-8
  # continuation bytes come off first: 0x80-0xBF never start a character, so
  # what is left is one byte per column. GLOSSARY: HI.12
  ((_HI_BYTE_COUNTS)) && s="${s//[$'\200'-$'\277']/}"
  printf -v "$1" '%d' "${#s}"
}

# <var> gets $2's hue - the final digit of its leading `\e[<bold>;3<n>m`
# escape (1 red, 2 green, 3 yellow, 4 blue, 5 purple, 6 cyan), ignoring the
# bold bit, so CYAN and BRCYAN read as the same hue and BLUE/CYAN don't.
# Under a color scheme the same escape carries on `;38;2;r;g;b` after the
# slot digit (GLOSSARY: HI.50), so the digit is followed by `;` or `m` and
# is the hue either way. Empty when there is no leading escape - NO_COLOR
# blanks the whole palette (core.sh), and a cell like $_HI_SI_OS is then
# bare text. Anchored and validated the same way _hi_visible_width's own
# prefix match is, rather than an unanchored `${cell%%m*}`: an unvalidated
# cut would read a stray "m" out of plain text (an OS name, "GHz") as if it
# were a color.
function _hi_cell_hue() {
  local s="$2" re='^\\e\[[01];3([1-6])[;m]'
  printf -v "$1" '%s' ""
  [[ "$s" =~ $re ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
}

# <var> gets the width the header actually draws to: $_HI_MAX_WIDTH, never
# wider than the window. A row left to overrun the real terminal gets broken
# by the terminal mid-cell, which is the one break header_row/full_check/
# banner exist to prevent.
#
# $_HI_TERM_COLS set (by a caller, or a previous call's own tput fallback)
# always wins, tty or not - the one deliberate override, and what lets a
# suite pin a narrow width the same way it already pins $_HI_MAX_WIDTH.
# Otherwise, only when stdout is a tty: a captured header (the suites that
# never touch $_HI_TERM_COLS, configure.sh's previews, `hi --doctor`) keeps
# drawing to $_HI_MAX_WIDTH exactly. $COLUMNS first, read fresh every call -
# bash's checkwinsize keeps it current across a resize, and reading it is
# free. `tput` is the fallback and the fork, so its answer is memoized into
# $_HI_TERM_COLS for every call after the first.
#
# Locals prefixed _hi_dw_, not the generic "max"/"cols" every caller uses for
# its own budget - `printf -v "$1"` resolves the name in the nearest scope,
# so a same-named local declared here would shadow the caller's variable
# instead of writing into it.
function _hi_draw_width() {
  local _hi_dw_max=${_HI_MAX_WIDTH:-80} _hi_dw_cols=""
  if [ -n "${_HI_TERM_COLS+x}" ]; then
    _hi_dw_cols="$_HI_TERM_COLS"
  elif [ -t 1 ]; then
    _hi_dw_cols="${COLUMNS:-}"
    case "$_hi_dw_cols" in '' | *[!0-9]*) _hi_dw_cols="" ;; esac
    if [ -z "$_hi_dw_cols" ]; then
      _hi_dw_cols="$(command -v tput >/dev/null 2>&1 && tput cols 2>/dev/null || true)"
      case "$_hi_dw_cols" in '' | *[!0-9]*) _hi_dw_cols="" ;; esac
      _HI_TERM_COLS="$_hi_dw_cols"
    fi
  fi
  [ -n "$_hi_dw_cols" ] && ((_hi_dw_cols > 0 && _hi_dw_cols < _hi_dw_max)) && _hi_dw_max=$_hi_dw_cols
  printf -v "$1" '%d' "$_hi_dw_max"
}

# A row's overflow cells, handed to the next row instead of costing a line of
# their own - the point of this whole cascade. Armed only for the span of
# hi_header's row loop, the one caller with a "next row" to hand cells to;
# every other caller (configure.sh's previews, `hi --doctor`, a suite calling
# header_row directly) stays unarmed, and unarmed
# header_row drains its own carry before returning - so standalone output is
# unchanged from before this cascade existed.
_HI_ROW_CARRY_ARMED=0
declare -a _HI_ROW_CARRY=()

# The previous $_HI_HEADER_ORDER cell's hue, tracked across
# _hi_collect_header_word calls so a colliding neighbor can be recolored.
# File scope, like $_HI_ROW_CARRY_ARMED above: configure.sh's previews run
# under their own strict mode, and an unset global there is a `set -u` trip,
# not a silently-empty read.
_HI_PREV_HUE=""

# Fills exactly one line at _hi_draw_width from <cells...>, prints it, and
# leaves whatever didn't fit in $_HI_ROW_CARRY (reset on entry) for a caller
# to hand to the next row. `width` starts at `max` so the first cell always
# looks like an overflow and takes the same branch a real wrap does, minus
# the `count == 0` guard that places it anyway - the first cell is always
# placed even when it alone exceeds the width. Stops at the first cell that
# doesn't fit and carries the rest wholesale, rather than scanning for a
# smaller cell further along that would still fit - that would reorder the
# header. Every cell keeps its own trailing reset before a line break, since
# a color left open would otherwise bleed onto the next physical line.
# Returns 1 and prints nothing for zero cells.
function _hi_row_line() {
  local cell out="" max vislen count=0 width i n
  _hi_draw_width max
  width=$max
  _HI_ROW_CARRY=()
  local -a args=("$@")
  n=${#args[@]}
  for ((i = 0; i < n; i++)); do
    cell="${args[$i]}"
    _hi_visible_width vislen "$cell"
    vislen=$((vislen + 3)) # " | " - the join this has always used
    if ((count > 0 && width + vislen > max)); then
      _HI_ROW_CARRY=("${args[@]:$i}")
      break
    fi
    if ((count == 0)); then
      width=0
      # $_HI_DISABLE_LEAD_SPACE drops just this one leading space - the "| "
      # between later cells is the structural separator, not "the initial
      # space", and stays either way
      if [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]]; then
        out+="$NC| $cell"
      else
        out+="$NC | $cell"
      fi
    else
      out+="$NC | $cell"
    fi
    width=$((width + vislen))
    ((++count))
  done
  ((count)) || return 1
  printf '%b\n' "$out$NC"
}

# Drains $_HI_ROW_CARRY a line at a time until empty - terminates because
# _hi_row_line always places at least one cell per call.
function _hi_header_flush() {
  while ((${#_HI_ROW_CARRY[@]})); do
    _hi_row_line "${_HI_ROW_CARRY[@]}"
  done
}

# One row's cells, prepended with whatever an earlier row's line couldn't
# fit. Unarmed (every caller but hi_header's own loop), a row still wraps
# fully within itself via _hi_header_flush, so standalone output matches
# what this function always printed. Armed, the leftover rides in
# $_HI_ROW_CARRY for the next header_row call instead.
function header_row() {
  local -a cells=(${_HI_ROW_CARRY[@]+"${_HI_ROW_CARRY[@]}"} "$@")
  _HI_ROW_CARRY=()
  if ((${#cells[@]})); then
    _hi_row_line "${cells[@]}"
  else
    printf '%b\n' "$NC"
  fi
  ((_HI_ROW_CARRY_ARMED)) || _hi_header_flush
}

# The header's version cell is a glance value, not a lookup key. A tag exactly
# on HEAD (a release, or a plain $_HI_RELEASE/snapshot stamp) is shown as-is,
# capped at 10 columns. Anything else - commits ahead of the last tag, or no
# reachable tag at all - is not a release, so the tag is dropped rather than
# implied: just a 6-column commit hash, `-dirty` included in neither case.
# Never `hi --version`'s own answer (hi.sh's _hi_version calls
# _hi_release_or_describe directly) - this is a display-only shortening of the
# header's copy.
function _hi_shorten_describe() {
  local v="${1%-dirty}" hash=""
  local re_g='^.*-[0-9]+-g([0-9a-f]{4,})$' re_bare='^([0-9a-f]{4,})$'
  if [[ "$v" =~ $re_g ]] || [[ "$v" =~ $re_bare ]]; then
    hash="${BASH_REMATCH[1]}"
    printf '%s' "${hash:0:6}"
  else
    printf '%s' "${v:0:10}"
  fi
}

# hi's version for the header, resolved once per shell (the row prints twice
# a session); a stampless, gitless install gets "unknown".
function _hi_header_version() {
  if [ -z "${_HI_HEADER_VERSION+x}" ]; then
    _hi_sanitize_var _HI_HEADER_VERSION "$(_hi_release_or_describe)"
    [ -n "$_HI_HEADER_VERSION" ] || _HI_HEADER_VERSION="unknown"
    _HI_HEADER_VERSION="$(_hi_shorten_describe "$_HI_HEADER_VERSION")"
  fi
  printf '%s\n' "$_HI_HEADER_VERSION"
}

# UTC | version | local. `|| :` on both clocks: a target with no date(1)
# gets an empty cell, not two "command not found" lines across the header.
# <var> gets one of timestamp()'s three cells - a pure getter, no header_row
# call of its own. $_HI_HEADER_ORDER's flattened dispatch (_hi_collect_header_word,
# below full_check's neighbor header_row) needs the *text*, not a line
# printed on the spot: header_row always ends its own call with a newline
# (_hi_row_line's final printf), so a getter that called it directly would
# put every cell on its own line instead of letting several pack onto one -
# exactly the row concept this flattening is supposed to remove, not
# reintroduce one cell at a time. timestamp() below still calls header_row
# itself, once, with the getters' three answers together - unchanged output
# for load.sh's disconnect banner and any other direct caller.
# <outvar> <color> [utc] - the two clock cells differ by `date -u` and a hue.
# Prefixed local: timestamp() below passes "utc" and "localtime" as $1, and a
# getter's own local of that name would shadow the caller's right back -
# printf -v resolves the nearest scope, which by then is this frame.
function _hi_cell_clock() {
  local _hi_ck_raw
  # shellcheck disable=SC2086 # ${3:+-u} is a flag or nothing, never a word
  _hi_ck_raw="$(exec date ${3:+-u} "$_HI_HUMAN_CENTRIC_DATE" 2>/dev/null)" || _hi_ck_raw=""
  printf -v "$1" '%s' "$2${_hi_ck_raw:-?}"
}
function _hi_cell_utc() { _hi_cell_clock "$1" "$BRBLUE" utc; }

function _hi_cell_version() {
  _hi_header_version >/dev/null # primes the memo; read the variable, not a $( )
  printf -v "$1" '%s' "$GREEN$_HI_HEADER_VERSION"
}

function _hi_cell_localtime() { _hi_cell_clock "$1" "$BRYELLOW"; }

# The group wrapper, kept for load.sh's disconnect banner and for
# tests/common/header_test.sh, which drives the clock cells through it. Not a
# compatibility surface for anything else: scripts/doctor.sh does not call it,
# and neither does hi.sh - naming a caller that does not exist is what stops
# the next reader from removing generality nothing wants.
function timestamp() {
  local utc version localtime
  _hi_cell_utc utc
  _hi_cell_version version
  _hi_cell_localtime localtime
  header_row "$utc" "$version" "$localtime"
}

# _hi_ghz <var> <mhz> - <var> as "<n>.<tenth>" GHz; printf, not an awk fork
# apiece, rounded to tenths *before* splitting so a carry lands properly
# (2950 -> 3.0, not "2.10")
function _hi_ghz() {
  local t=$((($2 + 50) / 100))
  printf -v "$1" '%d.%d' "$((t / 10))" "$((t % 10))"
}

# _hi_load_pct <var> <load> <cpus> - the 1-minute load average as a percentage
# of this box's own core count ("2.34" on 8 cores -> "29"): the number that
# actually answers "is this box busy", where the bare load figure needed the
# core count to mean anything and never carried it along. Empty <var> when
# either input is missing, or <cpus> isn't a plain positive integer - the
# Windows fallback's own unresolved "?" among them.
function _hi_load_pct() {
  local load="$2" cpus="$3"
  case "$cpus" in '' | *[!0-9]*) return 0 ;; esac
  [ -n "$load" ] && ((cpus > 0)) || return 0
  printf -v "$1" '%s' "$(awk -v l="$load" -v c="$cpus" 'BEGIN { printf "%.0f", (l / c) * 100 }')"
}

# <seconds> humanized to at most two units, largest first - a header cell,
# not a stopwatch. Shared by _hi_cell_uptime and nothing else.
function _hi_humanize_uptime() {
  local s="$1"
  if ((s >= 86400)); then
    printf '%dd %dh' "$((s / 86400))" "$((s % 86400 / 3600))"
  elif ((s >= 3600)); then
    printf '%dh %dm' "$((s / 3600))" "$((s % 3600 / 60))"
  else
    printf '%dm' "$((s / 60))"
  fi
}

# The detection the five sysinfo cells (os arch cores cpu ram) share, run once per shell and
# memoized into $_HI_SI_* (fully rendered, colored cell text - the same
# memo-once shape $_HI_HEADER_VERSION uses) so splitting the cells into
# independently orderable/toggleable $_HI_HEADER_ORDER words costs nothing
# extra: arch alone still pays for exactly one probe, not five.
# _hi_platform <outvar> - linux, windows, bsd or unknown: the one question
# the three probes below all asked, in three spellings that had already
# drifted apart (only the first had an "unknown" arm). Every platform test in
# the shipped tree is in this file, so it lives here and not in core.sh.
#
# The `uname` fork is memoized; the verdict is not. $_HI_LINUX_RELEASE stays
# first in the chain and is re-tested on every call, because header_test.sh
# points it at a fixture after sourcing to choose an arm - a remembered
# verdict would ignore that.
function _hi_platform() {
  if [ -z "${_HI_KERNEL+x}" ]; then
    # process substitution, not <<<: a here-string is a temp file before bash
    # 5.1. `|| :` so no uname means empty cells (rendered "?"), not an error.
    read -r _HI_KERNEL _HI_ARCH < <(uname -sm 2>/dev/null || :)
    _hi_sanitize_var _HI_KERNEL "$_HI_KERNEL"
    _hi_sanitize_var _HI_ARCH "$_HI_ARCH"
  fi
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    printf -v "$1" '%s' linux
  else
    case "$_HI_KERNEL" in
    MINGW* | MSYS* | CYGWIN*) printf -v "$1" '%s' windows ;;
    '') printf -v "$1" '%s' unknown ;;
    *) printf -v "$1" '%s' bsd ;;
    esac
  fi
}

function _hi_system_info_probe() {
  [ -z "${_HI_SI_PROBED:-}" ] || return 0
  _HI_SI_PROBED=1
  local kernel arch os cpus ram base_mhz load="" load_pct="" plat
  _hi_platform plat
  kernel="$_HI_KERNEL" arch="$_HI_ARCH"
  if [ "$plat" = linux ]; then
    local cpufreq=/sys/devices/system/cpu/cpu0/cpufreq
    # also covers WSL - a real Linux kernel with its own /etc/os-release.
    # Every probe ends in `|| true`: a stripped-down target falls through to
    # "?" - and a caller under its own `set -e` (see the top of the file)
    # must not abort on a missing probe.
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE" 2>/dev/null || true)
    cpus=$(exec nproc 2>/dev/null) || true
    # straight at the files free(1) and uptime(1) themselves read. Used is
    # MemTotal - MemAvailable (the "how much could a new process actually get"
    # figure free -h reports, not the naive MemTotal - MemFree); MemAvailable
    # predates nothing this project targets but a pre-3.14 kernel, where the
    # END block still has a total to print.
    ram=$(awk '
      /^MemTotal:/     { total = $2 }
      /^MemAvailable:/ { avail = $2 }
      END {
        if (avail != "") printf "%.0f/%.0fG", (total - avail) / 1048576, total / 1048576
        else if (total != "") printf "%.0fG", total / 1048576
      }' /proc/meminfo 2>/dev/null || true)
    load=$(exec awk '{ printf "%s", $1 }' /proc/loadavg 2>/dev/null) || true
    # base clock from the model name ("... @ 2.80GHz"); AMD chips print none,
    # so fall back to cpufreq's base_frequency, then amd-pstate-epp's
    # lowest_nonlinear_freq (the driver's floor, but it beats "?").
    # `read < file`, not $(cat file): a miss is silent and costs no fork.
    base_mhz=$(exec awk -F'@ *' '/model name/ && NF>1 { gsub(/GHz.*/, "", $2); printf "%.0f", $2 * 1000; exit }' /proc/cpuinfo 2>/dev/null) || true
    local khz freq_path
    for freq_path in "$cpufreq/base_frequency" "$cpufreq/amd_pstate_lowest_nonlinear_freq"; do
      [ -n "$base_mhz" ] && break
      [ -f "$freq_path" ] || continue
      read -r khz <"$freq_path" 2>/dev/null || khz=0
      base_mhz=$((khz / 1000))
      ((base_mhz)) || base_mhz=""
    done
  elif [ "$plat" = windows ]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }' || true)
    # wmic only exposes the rated (base) clock
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }' || true)
  elif [ "$plat" = unknown ]; then
    # no /etc/os-release and no uname: nothing to guess from
    os=""
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
    cpus=$(exec sysctl -n hw.ncpu 2>/dev/null) || true
    # total from sysctl, used from vm_stat: active + wired + compressed pages,
    # at vm_stat's own page size (its "(page size of N bytes)" header, not the
    # hardcoded 4096 that stopped being universal on Apple Silicon) - matched
    # by line prefix rather than a fixed field index, since a line's label
    # width varies by macOS version.
    ram=$(
      total_b=$(sysctl -n hw.memsize 2>/dev/null)
      vm_stat 2>/dev/null | awk -v total="$total_b" '
        /page size of/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) page = $i }
        /^Pages active/          { gsub(/\.$/, "", $NF); active = $NF }
        /^Pages wired down/      { gsub(/\.$/, "", $NF); wired = $NF }
        /^Pages occupied by compressor/ { gsub(/\.$/, "", $NF); compressed = $NF }
        END {
          if (page != "" && total != "")
            printf "%.0f/%.0fG", (active + wired + compressed) * page / 1073741824, total / 1073741824
          else if (total != "")
            printf "%.0fG", total / 1073741824
        }' || true
    )
    load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{ printf "%s", $2 }' || true)
    # Apple Silicon exposes no clock via sysctl at all (only Intel Macs get a
    # value here), so the cell reads "?" there, like every failed probe; drop
    # `cpu` from $_HI_HEADER_ORDER on such a box. A boost figure once came
    # from a hand-bounded, reverse-engineered ioreg read - more code and more
    # churn than one header cell was worth.
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }' || true)
  fi
  _hi_sanitize_var os "$os"
  # every probe above yields MHz (hence base_mhz keeps its name)
  [ -n "${base_mhz:-}" ] && _hi_ghz base_mhz "$base_mhz"
  # a stripped-down awk or a locale that prints a comma decimal both fail
  # closed to "?", not a garbled cell
  case "$load" in '' | *[!0-9.]*) load="" ;; esac
  _hi_load_pct load_pct "$load" "${cpus:-}"
  _HI_SI_ARCH="$PURPLE${arch:-?}"
  _HI_SI_OS="$GREEN${os:-?}"
  _HI_SI_CORES="${YELLOW}Cores: ${cpus:-?}${load_pct:+ ($load_pct%)}"
  _HI_SI_CPU="${BRBLUE}CPU: ${base_mhz:-?} GHz"
  _HI_SI_RAM="${CYAN}RAM: ${ram:-?}"
}

# _hi_probed_cell <outvar> <probe-fn> <memo-var> - every _hi_cell_* getter
# below is "run the (memoized) probe, copy one of its globals out by name".
# GLOSSARY: HI.04 - ${!3} is indirect expansion, not a nameref (bash 3.2 has
# none of those), and has worked since early bash with no declare needed.
function _hi_probed_cell() {
  "$2"
  printf -v "$1" '%s' "${!3}"
}

function _hi_cell_arch() { _hi_probed_cell "$1" _hi_system_info_probe _HI_SI_ARCH; }
function _hi_cell_os() { _hi_probed_cell "$1" _hi_system_info_probe _HI_SI_OS; }
function _hi_cell_cores() { _hi_probed_cell "$1" _hi_system_info_probe _HI_SI_CORES; }
function _hi_cell_cpu() { _hi_probed_cell "$1" _hi_system_info_probe _HI_SI_CPU; }
function _hi_cell_ram() { _hi_probed_cell "$1" _hi_system_info_probe _HI_SI_RAM; }

# <var> gets the uptime cell, one of the identity-group words rather than a
# row of its own so it rides the wrap instead of always costing a line. Its
# own probe rather than sharing the sysinfo cells' state - only "which command
# answers how long this box has been up" is common to the two - but the platform question
# itself is _hi_platform's, so the `uname` behind it is paid once per session
# rather than once per probe.
function _hi_cell_uptime() {
  local uptime_s="" up="" plat
  _hi_platform plat
  if [ "$plat" = linux ]; then
    uptime_s=$(exec awk '{ printf "%d", $1; exit }' /proc/uptime 2>/dev/null) || true
  elif [ "$plat" = bsd ]; then
    # kern.boottime prints "{ sec = <epoch>, usec = ... } <date>"; the split on
    # "sec = " makes $2 lead with the epoch, which awk's coercion reads whole.
    # Not probed on Windows: git-bash/MSYS2/Cygwin have no sysctl.
    uptime_s=$(sysctl -n kern.boottime 2>/dev/null |
      awk -v now="$(date +%s)" -F'sec = ' '{ printf "%d", now - $2; exit }' || true)
  fi
  # the guard drops anything non-numeric - a skewed clock can make the macOS
  # probe negative, and a stripped-down awk fails closed the same way
  case "$uptime_s" in '' | *[!0-9]*) uptime_s="" ;; esac
  [ -n "$uptime_s" ] && up="$(_hi_humanize_uptime "$uptime_s")"
  printf -v "$1" '%s' "${BRBLUE}Up: ${up:-?}"
}

# <var> gets the ip cell: every routable IPv4 address this box has, comma-
# joined. Its own minimal probe for the same reason _hi_cell_uptime gives for
# its own uname call - duplicating it here is cheaper than sharing state with
# system_info's. `ip` is tried first (present on every target this project
# already assumes iproute2 for, and on Alpine's busybox too - both answer the
# same `-o` field layout); `hostname -I` is the fallback where it prints
# nothing. Scope global excludes loopback and link-local, so a bare "?" means
# neither this box has a routable address nor either tool exists to say so.
function _hi_cell_ip() {
  local ips="" plat
  _hi_platform plat
  # One possibly-absent tool per branch, piped straight into awk for every
  # further step (splitting, filtering, joining) - awk is the one thing
  # besides bash a stripped target is guaranteed to have (GLOSSARY: HI.30
  # territory), so `cut`/`paste`/`tr`/`grep` chained after it would be one
  # more absent-tool roll of the dice apiece, each needing its own
  # `2>/dev/null` to stay quiet under _hi_stripped_header.
  if [ "$plat" = linux ]; then
    ips=$(ip -4 -o addr show scope global 2>/dev/null | awk '{
      split($4, a, "/"); printf "%s%s", sep, a[1]; sep = ","
    }')
    [ -n "$ips" ] || ips=$(hostname -I 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) { printf "%s%s", sep, $i; sep = "," }
    }')
  elif [ "$plat" = windows ]; then
    # git-bash/MSYS2/Cygwin: no `ip`, no `ifconfig` - ipconfig is the one tool
    # every one of them shells out to Windows for
    ips=$(ipconfig 2>/dev/null | awk -F': ' '/IPv4 Address/ {
      gsub(/\r/, "", $2); printf "%s%s", sep, $2; sep = ","
    }')
  elif [ "$plat" = bsd ]; then
    # macOS and the BSDs: no `ip`, but `ifconfig`'s "inet " line (never
    # "inet6") is there on all of them
    ips=$(ifconfig 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {
      printf "%s%s", sep, $2; sep = ","
    }')
  fi
  _hi_sanitize_var ips "$ips"
  # Addresses found but every one of them hidden is an empty cell, which
  # _hi_collect_header_word drops - not "?", which keeps meaning that
  # nothing routable was found or no tool could say.
  if [ -n "$ips" ]; then
    _hi_ip_filter ips "$ips"
    [ -n "$ips" ] || {
      printf -v "$1" '%s' ''
      return 0
    }
  fi
  printf -v "$1" '%s' "${BLUE}IP: ${ips:-?}"
}

# _hi_ip_filter <outvar> <comma-joined addresses> - the same list minus every
# address a $_HI_IP_HIDE glob matches. The setting is space-separated globs,
# unset or empty meaning `172.*` (the docker/podman bridge range, noise on
# any box that runs containers - empty is unset, as every other setting
# reads it); the word `none` hides nothing. The words are peeled off the
# string one at a time rather than word-split in a `for`, which would also
# pathname-expand `172.*` against the cwd.
function _hi_ip_filter() {
  local _hi_if_hide="${_HI_IP_HIDE:-172.*}" _hi_if_rest="$2" _hi_if_kept="" _hi_if_ip
  case "$_hi_if_hide" in none)
    printf -v "$1" '%s' "$2"
    return 0
    ;;
  esac
  while [ -n "$_hi_if_rest" ]; do
    _hi_if_ip="${_hi_if_rest%%,*}"
    if [ "$_hi_if_ip" = "$_hi_if_rest" ]; then _hi_if_rest=""; else _hi_if_rest="${_hi_if_rest#*,}"; fi
    # core.sh's matcher, which is this loop's former self: same peel, same
    # glob rule, and one place to fix when either is wrong
    _hi_ssh_pattern_hit "$_hi_if_ip" "$_hi_if_hide" ||
      _hi_if_kept="$_hi_if_kept${_hi_if_kept:+,}$_hi_if_ip"
  done
  printf -v "$1" '%s' "$_hi_if_kept"
}

# The identity cells' backend probes are independent and each capped at
# $_HI_PROBE_TIMEOUT: started together they cost the longest, not the sum.
# Files rather than process substitutions, which would wait on each in turn.
# `wait <pid>` and never `wait -n`: macOS ships bash 3.2.
declare -a _HI_PROBE_PIDS=()

# one probe into <file>, backgrounded; 2>/dev/null so a downed daemon
# reports to itself, not into the header
function _hi_probe_start() {
  local out="$1"
  shift
  "$@" >"$out" 2>/dev/null &
  _HI_PROBE_PIDS+=("$!")
}

# a probe failing is a normal outcome - that is what the counts are for
function _hi_probe_wait() {
  local pid
  for pid in ${_HI_PROBE_PIDS[@]+"${_HI_PROBE_PIDS[@]}"}; do wait "$pid" || true; done
  _HI_PROBE_PIDS=()
}

# Where _hi_probe_launch drops its output; empty until something is launched,
# so a host answering none of the three pays no mktemp and no rm.
_HI_PROBE_DIR=""

# Start whichever backends this host can answer, all at once. Its own
# function so hi_header can start them first and the other rows run in their
# shadow.
function _hi_probe_launch() {
  local cli clis="" nomad=0 kube=0
  # idempotent: hi_header starts these early, and _hi_identity_probe calls it
  # too so a direct cell read (the suites, hi --doctor) still probes
  [ -z "$_HI_PROBE_DIR" ] || return 0
  # one lane per docker-compatible CLI on $PATH (GLOSSARY: HI.51); the cell
  # below unions the lanes, so two CLIs fronting one daemon count once. The
  # same four words are in hi.sh and common/targets.sh, pinned together by
  # the drift suite
  for cli in docker podman nerdctl finch; do
    command -v "$cli" &>/dev/null && clis="$clis${clis:+ }$cli"
  done
  command -v nomad &>/dev/null && nomad=1
  command -v kubectl &>/dev/null && kube=1
  [ -n "$clis" ] || ((nomad || kube)) || return 0
  _HI_PROBE_DIR="$(mktemp -d -t hi.probes.XXXXXX)"
  for cli in $clis; do
    _hi_probe_start "$_HI_PROBE_DIR/containers.$cli" _hi_probe "$cli" container ls -q
  done
  ((nomad)) && _hi_probe_start "$_HI_PROBE_DIR/nomad" _hi_probe nomad job status
  # kube counts through targets.sh, whose list_kube owns the "which pods count
  # as reachable" rule; docker/nomad counts answer a different question
  ((kube)) && _hi_probe_start "$_HI_PROBE_DIR/kube" sh "$_HI_TARGETS" kube
  return 0
}

# git identity (domain masked), containers/jobs/pods, ssh key counts - the
# detection the identity cells share, memoized into $_HI_ID_* the same way
# _hi_system_info_probe memoizes the sysinfo cells'. $_HI_ID_CONTAINERS/_JOBS/_PODS
# stay empty when that backend's probe never ran - a getter checks for that
# itself, same "cell appears only when the probe actually ran" rule as
# before. Uptime is not part of this probe: _hi_cell_uptime already has its
# own minimal, independent one (see its own comment) and stays that way.
# Reads what _hi_probe_launch started; calls it itself if nobody did.
function _hi_identity_probe() {
  [ -z "${_HI_ID_PROBED:-}" ] || return 0
  _HI_ID_PROBED=1
  local email="" domain user_part bullets containers="" jobs="" pods="" authorized=0 public=0
  local -a lines
  command -v git &>/dev/null && { email=$(exec git config --get user.email 2>/dev/null) || email=""; }
  _hi_sanitize_var email "$email"
  if [ -n "$email" ]; then
    domain=${email#*@}
    _hi_repeat bullets "${#domain}" "$_HI_GLYPH_MASK"
    user_part="$YELLOW${email%%@*}@$bullets"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi

  _hi_probe_launch
  _hi_probe_wait

  # One rule for all three backends: a cell appears only when its binary was
  # found and its probe actually ran - the file's existence is that signal,
  # never its content - and once it has, the count prints as-is, zero
  # included. A reachable-but-idle nomad or kube used to render exactly like
  # an absent one; a probed-and-empty docker/podman already didn't, and this
  # brings the other two in line with it rather than the other way round.
  if [ -n "$_HI_PROBE_DIR" ]; then
    local -a lanes=("$_HI_PROBE_DIR"/containers.*)
    if [ -f "${lanes[0]}" ]; then
      if [ "${#lanes[@]}" -eq 1 ]; then
        _hi_read_lines lines <"${lanes[0]}"
      else
        # IDs are the daemon's, so a shim's lane repeats another's and the
        # union is the count - one fork, only on a host with two CLIs
        _hi_read_lines lines < <(sort -u "${lanes[@]}")
      fi
      containers="Containers: ${#lines[@]}"
    fi
    if [ -f "$_HI_PROBE_DIR/nomad" ]; then
      _hi_read_lines lines <"$_HI_PROBE_DIR/nomad"
      lines=("${lines[@]:1}") # drop the header row
      jobs="Jobs: ${#lines[@]}"
    fi
    if [ -f "$_HI_PROBE_DIR/kube" ]; then
      _hi_read_lines lines <"$_HI_PROBE_DIR/kube"
      pods="Pods: ${#lines[@]}"
    fi
    command rm -rf "$_HI_PROBE_DIR"
    _HI_PROBE_DIR=""
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && _hi_read_lines lines <"$_HI_SSH_AUTHORIZED_KEYS" && authorized=${#lines[@]}
  [ -d "$_HI_SSH_DIR" ] && _hi_read_lines lines < <(find "$_HI_SSH_DIR" -type f -name "*.pub") && public=${#lines[@]}
  _HI_ID_GITID="$user_part"
  _HI_ID_CONTAINERS="${containers:+$BLUE$containers}"
  _HI_ID_JOBS="${jobs:+$BRGREEN$jobs}"
  _HI_ID_PODS="${pods:+$BRPURPLE$pods}"
  _HI_ID_AUTH="${RED}Auth: $authorized"
  _HI_ID_PUB="${PURPLE}Pub: $public"
}

function _hi_cell_gitid() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_GITID; }
function _hi_cell_containers() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_CONTAINERS; }
function _hi_cell_jobs() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_JOBS; }
function _hi_cell_pods() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_PODS; }
function _hi_cell_auth() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_AUTH; }
function _hi_cell_pub() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_PUB; }

# "~~~ <label> [host] ~~~" prefixed with say-hi's local change count, always
# _hi_draw_width columns wide
function banner() {
  [[ "${_HI_DISABLE_BANNER:-0}" == 1 ]] && return 0
  local label="$1" color="${2:-$BRGREEN}" changes="" prefix="${3:-}" changes_w=0
  # ~10ms of `git status`, computed once and kept for both banners.
  # --no-optional-locks as git_prompt.sh: a plain `git status` also rewrites
  # .git/index - cheap on ext4, a 9p round trip per file on a /mnt checkout.
  if [ -d "$_HI_ROOT/.git" ]; then
    if [ -z "${_HI_BANNER_CHANGES+x}" ]; then
      local -a lines
      _hi_read_lines lines < <(git -C "$_HI_ROOT" --no-optional-locks status --short 2>/dev/null)
      _HI_BANNER_CHANGES="${#lines[@]}"
      # symbolic-ref is empty on detached HEAD and main is blanked, so only
      # an unusual branch earns a callout
      _hi_sanitize_var _HI_BANNER_BRANCH \
        "$(git -C "$_HI_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)"
      [ "$_HI_BANNER_BRANCH" = main ] && _HI_BANNER_BRANCH=""
    fi
    changes="$BRYELLOW$_HI_BANNER_CHANGES $_HI_GLYPH_AHEAD "
    # columns, not ${#} bytes (GLOSSARY: HI.12): the digits, then "␣↑␣"
    changes_w=$((${#_HI_BANNER_CHANGES} + 3))
    # the Online (local) banner only: a remote Connected banner describes the
    # target, and the disconnect banner stays as-is
    if [ "$label" = Online ] && [ -n "${_HI_BANNER_BRANCH:-}" ]; then
      changes+="($_HI_BANNER_BRANCH) "
      changes_w=$((changes_w + ${#_HI_BANNER_BRANCH} + 3))
    fi
  fi
  local host tildes start_len end_len start_tildes end_tildes width left core lead=" "
  [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]] && lead=""
  # memoized for the same reason: two forks a banner for a fixed name
  [ -n "${_HI_BANNER_HOST+x}" ] || _hi_sanitize_var _HI_BANNER_HOST "$(_hi_hostname)"
  host="$_HI_BANNER_HOST"
  _hi_draw_width width
  # split so "label [host]" lands at the center with at least 1 tilde on the left
  left=$((${#prefix} + ${#lead} + changes_w))
  core=$((${#label} + ${#host} + 4))
  tildes=$((width - left - core - 1))
  ((tildes < 4)) && tildes=4
  start_len=$((width / 2 - left - core / 2))
  ((start_len < 1)) && start_len=1
  ((start_len > tildes - 1)) && start_len=$((tildes - 1))
  end_len=$((tildes - start_len))
  _hi_repeat start_tildes "$start_len" '~'
  _hi_repeat end_tildes "$end_len" '~'
  local host_esc=""
  _hi_host_escape host_esc
  printf '%b\n' "$lead$changes$color$start_tildes $label ${NC}[$host_esc$host$NC]$color $end_tildes$NC"
}

# hi_header's default row order, and $_HI_HEADER_ORDER's vocabulary - one word
# per feature, in the shipped default order - no more grouping: any word may
# be reordered or left out on its own, independent of the others. Named here
# rather than only in the case below, so a doc or test can read the default
# without parsing the dispatch.
_HI_HEADER_ORDER_DEFAULT="utc version localtime os arch cores cpu ram ip gitid containers jobs pods auth pub uptime check"

# <var> gets $1's cell text if $1 names a getter, empty otherwise -
# _hi_collect_header_word's own dispatch, split out so a direct caller (a
# suite) can ask "what would this word render as" without going through the
# accumulate/flush machinery below.
function _hi_header_word_cell() {
  printf -v "$2" '%s' ""
  # Fifteen of the sixteen getters were already named _hi_cell_<word> and the
  # case restated the mapping; now the convention *is* the mapping. The roster
  # gate is what keeps it safe: $_HI_HEADER_ORDER is the user's own string, so
  # only a word the shipped default names may reach a function here. `check`
  # is in that roster and has no getter - it is full_check's own row - hence
  # the declare -F.
  case " $_HI_HEADER_ORDER_DEFAULT " in
  *" $1 "*) declare -F "_hi_cell_$1" >/dev/null && "_hi_cell_$1" "$2" ;;
  esac
  return 0
}

# <var> gets $1's alternate color - a bright variant of a hue other than the
# word's own primary, used only when that primary would collide with the
# previous cell's hue (_hi_collect_header_word below). GLOSSARY: HI.48 - no
# ring walk or iteration is needed to pick it: a substitution only fires when
# prev_hue == primary_hue, and every alternate below has a hue that differs
# from its own word's primary, so alt_hue != primary_hue == prev_hue always
# holds - the substitution can never itself collide. That property is
# load-bearing and not enforced by the shell; a new header word's entry here
# must keep it (tests/common/header_test.sh checks it mechanically).
# "<word>:<bright palette variable>", one row per header word - sixteen case
# arms whose bodies differed only in a colour name were data written as
# control flow. GLOSSARY: HI.48 - every alternate's hue must differ from its
# own word's primary, which is what makes a substitution unable to collide,
# and header_test.sh checks it. The variable *name* is stored, not its value.
_HI_HEADER_ALTS="utc:BRCYAN version:BRCYAN localtime:BRRED os:BRPURPLE\
 arch:BRCYAN cores:BRGREEN cpu:BRPURPLE ram:BRGREEN ip:BRCYAN gitid:BRRED\
 containers:BRYELLOW jobs:BRYELLOW pods:BRCYAN auth:BRYELLOW pub:BRRED\
 uptime:BRGREEN"

function _hi_header_word_alt() {
  local _hi_wa
  printf -v "$2" '%s' ""
  # shellcheck disable=SC2086 # the split is the table
  for _hi_wa in $_HI_HEADER_ALTS; do
    [ "${_hi_wa%%:*}" = "$1" ] || continue
    _hi_wa="${_hi_wa#*:}"
    # read at call time, not baked in: configure.sh's previews flip
    # $_HI_COLOR_SCHEME and re-run _hi_assign_palette between renders
    printf -v "$2" '%s' "${!_hi_wa}"
    return 0
  done
  return 0
}

# One $_HI_HEADER_ORDER word: "check" flushes whatever cells are pending as
# one header_row call (so full_check's own carry-absorption at its top sees
# the right leftover), then runs it; every other word gets its cell text and
# appends it to $_HI_PENDING_CELLS (bash's dynamic scoping reaches into the
# caller's local array, the same trick $_HI_ROW_CARRY's callers use) rather
# than calling header_row itself - header_row always ends its own call with a
# newline, so a call per feature would put one cell per line instead of
# letting consecutive features pack onto one, the very thing this flattening
# is supposed to stop being a fixed row rather than reintroduce one at a
# time. An unknown word is silently skipped: a reorder, not a second way to
# spell a typo into an error.
function _hi_collect_header_word() {
  if [ "$1" = check ]; then
    if ((${#_HI_PENDING_CELLS[@]})); then
      header_row "${_HI_PENDING_CELLS[@]}"
      _HI_PENDING_CELLS=()
    fi
    full_check
    # the packages check has its own palette (_HI_YES/_HI_NO below); nothing
    # after "check" should be recolored against it
    _HI_PREV_HUE=""
    return 0
  fi
  local cell="" hue="" alt=""
  _hi_header_word_cell "$1" cell
  # an empty cell (containers/jobs/pods whose backend never answered) leaves
  # $_HI_PREV_HUE untouched - writing "" here would disable the *next*
  # word's comparison too, since a collision needs both hues non-empty
  [ -n "$cell" ] || return 0
  _hi_cell_hue hue "$cell"
  if [ -n "$hue" ] && [ "$hue" = "${_HI_PREV_HUE:-}" ]; then
    # $hue only got set above by matching this exact escape prefix, so it's
    # already known to be there and to end in the first "m" in the string -
    # no need to re-derive it with a second regex.
    _hi_header_word_alt "$1" alt
    cell="$alt${cell#*m}"
    _hi_cell_hue hue "$cell"
  fi
  _HI_PREV_HUE="$hue"
  _HI_PENDING_CELLS+=("$cell")
}

# Is <word> anywhere in $_HI_HEADER_ORDER (or its default)? Used to decide
# whether hi_header's eager probe-launch is worth starting at all, and by
# load.sh's disconnect banner to match the connect side without a
# disconnect-specific toggle of its own.
function _hi_order_has() {
  case " ${_HI_HEADER_ORDER:-$_HI_HEADER_ORDER_DEFAULT} " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

function hi_header() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && return 0
  banner "$@"
  # ahead of the fork-only cells, so their ~30ms runs inside the probes' wall
  # clock. Only the three that actually consume a backend probe gate this -
  # gitid/auth/pub never did, so they cost nothing here whether or not they
  # end up in the order.
  # Skipped once identity is memoized (configure.sh renders the header
  # repeatedly in subshells): a relaunch there would start backends nobody
  # waits on and leave their mktemp dir behind.
  if [ -z "${_HI_ID_PROBED:-}" ] && { _hi_order_has containers || _hi_order_has jobs || _hi_order_has pods; }; then
    _hi_probe_launch
  fi
  local row
  local -a _HI_PENDING_CELLS=()
  # armed for the span of this loop only - a cell's overflow cascades into
  # the next header_row call's line instead of costing one of its own. Reset
  # per call: hi_header runs twice a session (connect, disconnect). Same
  # reason for $_HI_PREV_HUE below - the adjacency resolver's own memory of
  # "what hue did the last cell end up as".
  _HI_ROW_CARRY=() _HI_ROW_CARRY_ARMED=1
  _HI_PREV_HUE=""
  # shellcheck disable=SC2086 # the split is the point: one word per feature
  for row in ${_HI_HEADER_ORDER:-$_HI_HEADER_ORDER_DEFAULT}; do
    _hi_collect_header_word "$row"
  done
  ((${#_HI_PENDING_CELLS[@]})) && header_row "${_HI_PENDING_CELLS[@]}"
  _HI_ROW_CARRY_ARMED=0
  # whatever the last line couldn't fit, printed as its own line rather than
  # dropped - a no-op when the order ends on "check", since full_check
  # absorbs the carry itself and leaves none behind.
  _hi_header_flush
}

# Package priorities, lowest to highest, 0-3. A priority says how loudly you
# want to hear about a tool; $_HI_PACKAGES_MIN_PRIORITY gates display and
# ships at 2, so tiers 0-1 (trivia and optional extras) are hidden until asked
# for, and anything above 3 mutes the check entirely. Direction is a separate axis, one leading
# character per line: `-` speaks only when the tool is missing (core tools,
# where present is not news and absent means the box is bare), `+` only when
# it is installed (platform facts, where absent is noise); no flag speaks
# both ways. Priorities above 3 clamp to 3, so an old-format file still
# renders.
#
# Each ramp is ordered intensity-major, not hue-major: both normal
# intensities first, then both bright, so the loudness step from one
# priority to the next never reverses direction. A ramp that alternates
# normal/bright/normal/bright reads a lower priority as louder than the one
# above it - what "monotonic in both directions" below is guarding against.
# The numbered lines below are scraped verbatim by scripts/preview.sh
# (the run directly above _HI_YES_NAMES, parentheticals dropped): keep the
# "# <n> <meaning> (<examples>)" shape and add nothing between them and the
# table.
# 0 platform trivia (sw_vers, kitty)
# 1 optional extras (gping, navi)
# 2 useful tools (make, vim, python3)
# 3 favorites and core (bat, fzf, awk)
_HI_YES_NAMES=(cyan green brcyan brgreen)
_HI_NO_NAMES=(blue magenta bryellow brred)
# The shipped ramp as one string, in the eight-name shape
# $_HI_PACKAGES_PALETTE takes - the fallback restores from here rather than
# repeating the two literals above, which have to stay where they are for
# preview.sh's scrape.
_HI_PACKAGES_RAMP="${_HI_YES_NAMES[*]} ${_HI_NO_NAMES[*]}"

# Palette *names*, not escapes: these are configuration - which of
# _HI_COLOR_NAMES each priority paints in - and storing them rendered meant
# every consumer that wanted the name back had to invert the mapping.
# header.sh recovered the slot by reading digits out of the escape's bytes,
# preview.sh forked twelve escapes to build a reverse lookup, and a case in
# header_test.sh existed only to keep that round trip honest. The escapes
# _hi_packages_palette derives below are what check_line actually reads.

# $_HI_PACKAGES_PALETTE is the ramp itself: eight _HI_COLOR_NAMES words
# (core.sh's vocabulary, the one settings/colors and fish's set_color both
# use), four for installed then four for missing, written into settings.sh
# by hand. Anything else - unset, a typo, the wrong count - is the shipped
# ramp. preview.sh's scrape (above) stops at the first line starting
# "_HI_YES_NAMES=", so that assignment has to stay exactly there.
# A ramp is meant to read monotonic 0->3 in both directions - a missing
# favorite the loudest thing on screen, installed trivia the quietest - and
# legible on light and dark terminals alike; judge one with
# `hi --preview packages`.
function _hi_packages_palette() {
  local _hi_pp_n _hi_pp_i _hi_pp_e _hi_pp_r="$_HI_PACKAGES_RAMP"
  _hi_ramp_ok "${_HI_PACKAGES_PALETTE:-}" && _hi_pp_r="$_HI_PACKAGES_PALETTE"
  # shellcheck disable=SC2086 # eight names, checked by _hi_ramp_ok
  set -- $_hi_pp_r
  _HI_YES_NAMES=("$1" "$2" "$3" "$4")
  _HI_NO_NAMES=("$5" "$6" "$7" "$8")
  # Names to escapes, here rather than at source time: configure.sh's
  # previews flip $_HI_COLOR_SCHEME and $_HI_PACKAGES_PALETTE between
  # renders, and full_check re-runs this before every check_line.
  _hi_scheme_words _hi_pp_n
  _HI_YES=() _HI_NO=()
  for _hi_pp_i in 0 1 2 3; do
    _hi_ramp_escape _hi_pp_e "${_HI_YES_NAMES[_hi_pp_i]}" "$_hi_pp_n"
    _HI_YES+=("$_hi_pp_e")
    _hi_ramp_escape _hi_pp_e "${_HI_NO_NAMES[_hi_pp_i]}" "$_hi_pp_n"
    _HI_NO+=("$_hi_pp_e")
  done
}

# _hi_ramp_escape <outvar> <palette name> <scheme word count> - the escape a
# ramp slot paints in. Normally the palette entry for <name>; with a 48-word
# $_HI_COLOR_SCHEME, the same slot twenty-four further on, which is the second
# bank that scheme carries for the check alone (HI.50). This used to read the slot
# back out of an escape's own bytes, because the ramps stored escapes.
function _hi_ramp_escape() {
  local _hi_re_i=0 _hi_re_n
  printf -v "$1" '%s' ''
  [ -n "${NO_COLOR:-}" ] && return 0
  [ "${3:-0}" = 48 ] || {
    _hi_color_escape_var "$1" "$2"
    return 0
  }
  for _hi_re_n in "${_HI_COLOR_NAMES[@]}"; do
    [ "$_hi_re_n" = "$2" ] && {
      _hi_color_escape_at "$1" $((_hi_re_i + 24))
      return 0
    }
    _hi_re_i=$((_hi_re_i + 1))
  done
}

# Assigned at source time, as the two escape arrays were before. `|| true`
# because this is now a call rather than a literal: header.sh is sourced into
# a stripped `env -i` in the suites and into callers running under their own
# strict mode, and neither could be aborted by a plain array assignment.
_hi_packages_palette || true

# For each "[-|+]cmd:priority[,...]": the highest-priority installed package
# (or the first, if none) — a fully-missing line ranks at the max priority
# among its alternatives — colored and marked per above. `-` drops the row
# when something is installed, `+` when nothing is. The marks live in
# core.sh's _hi_choose_glyphs.
# _hi_row_max <outvar> <line> - the highest rank a roster row could reach:
# its largest `:N`, clamped the way the loop below clamps. Lets full_check
# apply $_HI_PACKAGES_MIN_PRIORITY *before* the probe rather than after -
# check_line runs a `command -v` per alternative, and at the default floor
# more than half the shipped roster is probed only to be dropped.
function _hi_row_max() {
  local _hi_rm_rest="$2" _hi_rm_n _hi_rm_max=0
  while [ "$_hi_rm_rest" != "${_hi_rm_rest#*:}" ]; do
    _hi_rm_rest="${_hi_rm_rest#*:}"
    _hi_rm_n="${_hi_rm_rest%%,*}"
    _hi_rm_n="${_hi_rm_n%%[!0-9]*}"
    [ -n "$_hi_rm_n" ] || continue
    ((_hi_rm_n > 3)) && _hi_rm_n=3
    ((_hi_rm_n > _hi_rm_max)) && _hi_rm_max=$_hi_rm_n
  done
  printf -v "$1" '%s' "$_hi_rm_max"
}

# check_line <out-array-name> <line>. The array is the caller's to name: it
# used to append into a bare `visible`, so both callers had to know that name
# *and* the \x1f record shape, and one of them is in another file.
function check_line() {
  local pair cmd priority color best best_priority max_priority best_idx=0 idx=0 found=0 symbol rendered
  local mode=both line=$2
  case "$line" in
  -*) mode=miss line="${line#-}" ;;
  +*) mode=have line="${line#+}" ;;
  esac
  # word-split on the local IFS, not `read -ra <<<`: that here-string is a
  # temp file before bash 5.1, per package line
  local IFS=','
  # shellcheck disable=SC2206 # deliberate split on IFS; the file has no globs
  local -a pairs=($line)
  unset IFS
  best="${pairs[0]%:*}"
  max_priority=0

  for pair in "${pairs[@]}"; do
    cmd="${pair%:*}"
    priority="${pair#*:}"
    if ((priority > 3)); then priority=3; fi
    if ((priority > max_priority)); then max_priority=$priority; fi
    if command -v "$cmd" &>/dev/null && ((found == 0 || priority > best_priority)); then
      best="$cmd"
      best_priority="$priority"
      best_idx=$idx
      found=1
    fi
    ((++idx))
  done

  if ((found)); then
    [[ "$mode" == miss ]] && return 0
    color="${_HI_YES[best_priority]:-$NC}"
    if ((best_idx == 0)); then
      symbol="$GREEN$_HI_MARK_OK"
    else
      symbol="$YELLOW$_HI_MARK_ALT$NC"
    fi
  else
    [[ "$mode" == have ]] && return 0
    best_priority=$max_priority
    color="${_HI_NO[best_priority]:-$NC}"
    symbol="$RED$_HI_MARK_NO"
  fi
  rendered="$color $best $symbol"
  # 5 = the "| " lead, the spaces around the item, and the mark - one visible
  # column in either glyph set (core.sh's _hi_choose_glyphs)
  # shellcheck disable=SC2034 # read by the eval below, which the linter
  # cannot see into - the point of building the record out here is that
  # everything *it* reads stays visible
  local record="$best_priority"$'\x1f'"$((${#best} + 5))"$'\x1f'"$rendered"
  # appended by name, the idiom core.sh's _hi_read_lines uses. The record is
  # built first rather than inside the eval, which keeps the eval'd string
  # trivial and leaves every variable it reads visible to the linter.
  eval "$1+=(\"\$record\")"
}

# print sorted package results limited by _hi_draw_width, from
# $_HI_PACKAGES_MIN_PRIORITY up. The floor lives here, not in check_line:
# scripts/preview.sh calls check_line directly and needs the rows
# the floor hides.
function full_check() {
  local line priority width_item rendered count=0 max cell vislen piece i
  _hi_draw_width max
  local width=$max
  local min="${_HI_PACKAGES_MIN_PRIORITY:-2}"
  local -a visible=() row_widths=() row_pieces=()
  # re-resolved here, not just at source time: a caller that changes
  # $_HI_PACKAGES_PALETTE after header.sh loaded (configure.sh's preview does)
  # needs the next full_check to see it. A bare case, no fork either way.
  _hi_packages_palette

  # a carry from an earlier row (hi_header's cascade) opens this row's first
  # line, in the same "| <cell> " shape header_row's own cells use - both
  # sources measure "|", a space, the text and a trailing space, so the wrap
  # loop below treats them alike. Absorbed here rather than left for the
  # caller: full_check is the variable-length block, the one row that can
  # always make room for one more cell.
  for cell in ${_HI_ROW_CARRY[@]+"${_HI_ROW_CARRY[@]}"}; do
    _hi_visible_width vislen "$cell"
    row_widths+=("$((vislen + 3))")
    row_pieces+=("| $cell ")
  done
  _HI_ROW_CARRY=()

  local row_max
  while IFS=$' ' read -r line; do
    [[ "$line" == *#* || -z "$line" ]] && continue
    # the floor first: a row that cannot reach it has nothing to contribute,
    # and probing it is a failed PATH walk per alternative. Rows that clear it
    # are still filtered below on the rank they actually scored.
    _hi_row_max row_max "$line"
    ((row_max >= min)) || continue
    check_line visible "$line"
  done <"$_HI_PACKAGES"

  if ((${#visible[@]})); then
    # GLOSSARY: HI.11 - numeric key over opaque bytes; unpinned, BSD sort
    # under UTF-8 printed nothing.
    while IFS=$'\x1f' read -r priority width_item rendered; do
      ((priority >= min)) || continue
      row_widths+=("$width_item")
      row_pieces+=("|${rendered} ")
    done < <(printf '%s\n' "${visible[@]}" | LC_ALL=C sort -t $'\x1f' -k1,1nr -s)
  fi
  ((${#row_widths[@]})) || return 0

  for ((i = 0; i < ${#row_widths[@]}; i++)); do
    width_item="${row_widths[$i]}"
    piece="${row_pieces[$i]}"
    if ((width + width_item > max)); then # start of a row
      ((count == 0)) || printf '\n'
      if [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]]; then
        width=0
      else
        printf ' '
        width=1
      fi
    fi
    printf '%b' "$NC$piece$NC"
    width=$((width + width_item))
    ((++count))
  done
  # guarded: a floor that hides everything printed a bare newline otherwise
  if ((count)); then printf '\n'; fi
}
