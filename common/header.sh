#!/usr/bin/env bash
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
  printf -v "$1" '%d' "${#s}"
}

# <var> gets $2's hue - the final digit of its leading `\e[<bold>;3<n>m`
# escape (1 red, 2 green, 3 yellow, 4 blue, 5 purple, 6 cyan), ignoring the
# bold bit, so CYAN and BRCYAN read as the same hue and BLUE/CYAN don't.
# Empty when there is no leading escape - NO_COLOR blanks the whole palette
# (core.sh), and a cell like $_HI_SI_OS is then bare text. Anchored and
# validated the same way _hi_visible_width's own prefix match is, rather
# than an unanchored `${cell%%m*}`: an unvalidated cut would read a stray
# "m" out of plain text (an OS name, "GHz") as if it were a color.
function _hi_cell_hue() {
  local s="$2" re='^\\e\[[01];3([1-6])m'
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
# header_row/system_info/identity directly) stays unarmed, and unarmed
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
      # $_HI_NO_LEAD_SPACE drops just this one leading space - the "| "
      # between later cells is the structural separator, not "the initial
      # space", and stays either way
      if [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]]; then
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

# The header's version cell is a glance value, not a lookup key - git
# describe's own hash (7 hex digits, either after "-g" or bare when no tag is
# reachable at all) is more precision than a header row has room for, and its
# tag can carry one too (a snapshot tag names its own commit). So: drop
# -dirty (a glance value has no room for it either), keep at most 5 columns of
# tag plus a 4-column hash joined by ".", never bare $_HI_RELEASE or
# `hi --version`'s answer (hi.sh's _hi_version calls _hi_release_or_describe
# directly) - this is a display-only shortening of the header's copy, capped
# at 10 columns either way.
function _hi_shorten_describe() {
  local v="${1%-dirty}" tag="" hash="" out
  local re_g='^(.*)-[0-9]+-g([0-9a-f]{4,})$' re_bare='^([0-9a-f]{4,})$'
  if [[ "$v" =~ $re_g ]]; then
    tag="${BASH_REMATCH[1]}" hash="${BASH_REMATCH[2]}"
  elif [[ "$v" =~ $re_bare ]]; then
    hash="${BASH_REMATCH[1]}"
  else
    tag="$v"
  fi
  if [ -z "$hash" ]; then
    out="${tag:0:10}"
  else
    tag="${tag:0:5}"
    while [ -n "$tag" ]; do
      case "$tag" in *[-._]) tag="${tag%?}" ;; *) break ;; esac
    done
    out="${tag:+$tag.}${hash:0:4}"
  fi
  printf '%s' "$out"
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
# below full_check's neighbor _hi_header_row) needs the *text*, not a line
# printed on the spot: header_row always ends its own call with a newline
# (_hi_row_line's final printf), so a getter that called it directly would
# put every cell on its own line instead of letting several pack onto one -
# exactly the row concept this flattening is supposed to remove, not
# reintroduce one cell at a time. timestamp() below still calls header_row
# itself, once, with the getters' three answers together - unchanged output
# for load.sh's disconnect banner and any other direct caller.
function _hi_cell_utc() {
  # not "utc": timestamp() below passes that exact name as $1, and this
  # getter's own local of the same name would shadow it right back -
  # printf -v resolves the nearest scope, which by then is this function's
  # own frame, not the caller's.
  local _hi_utc_raw
  _hi_utc_raw="$(date -u "$_HI_HUMAN_CENTRIC_DATE" 2>/dev/null || :)"
  printf -v "$1" '%s' "$BRBLUE${_hi_utc_raw:-?}"
}

function _hi_cell_version() {
  _hi_header_version >/dev/null # primes the memo; read the variable, not a $( )
  printf -v "$1" '%s' "$GREEN$_HI_HEADER_VERSION"
}

function _hi_cell_localtime() {
  local local_now
  local_now="$(date "$_HI_HUMAN_CENTRIC_DATE" 2>/dev/null || :)"
  printf -v "$1" '%s' "$BRYELLOW${local_now:-?}"
}

# The group wrapper, kept for load.sh's disconnect banner and any direct
# caller (hi --doctor, a suite) that wants the bundle rather than picking
# individual words.
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

# One or two clocks, folded to one when there is nothing worth a second
# number: no boost probe answered, or it answered the same as base (no real
# turbo range) - a real base/boost pair is the only case worth "<n>/<n> GHz"
# rather than one.
function _hi_cpu_clocks() {
  local base="$1" boost="$2"
  if [ -n "$base" ] && [ -n "$boost" ] && [ "$base" != "$boost" ]; then
    printf '%s/%s' "$base" "$boost"
  elif [ -n "$base" ]; then
    printf '%s' "$base"
  elif [ -n "$boost" ]; then
    printf '%s' "$boost"
  else
    printf '?'
  fi
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
# not a stopwatch. Shared by _hi_uptime_cell and nothing else; system_info no
# longer touches uptime at all.
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

# The detection system_info()'s five cells share, run once per shell and
# memoized into $_HI_SI_* (fully rendered, colored cell text - the same
# memo-once shape $_HI_HEADER_VERSION uses) so splitting the cells into
# independently orderable/toggleable $_HI_HEADER_ORDER words costs nothing
# extra: arch alone still pays for exactly one probe, not five.
function _hi_system_info_probe() {
  [ -z "${_HI_SI_PROBED:-}" ] || return 0
  _HI_SI_PROBED=1
  local kernel arch os cpus ram base_mhz boost_mhz load="" load_pct=""
  # process substitution, not <<<: a here-string is a temp file before bash
  # 5.1. `|| :` so no uname means empty cells (rendered "?"), not an error.
  read -r kernel arch < <(uname -sm 2>/dev/null || :)
  _hi_sanitize_var kernel "$kernel"
  _hi_sanitize_var arch "$arch"
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    local cpufreq=/sys/devices/system/cpu/cpu0/cpufreq
    # also covers WSL - a real Linux kernel with its own /etc/os-release.
    # Every probe ends in `|| true`: a stripped-down target falls through to
    # "?" - and a caller under its own `set -e` (see the top of the file)
    # must not abort on a missing probe.
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE" 2>/dev/null || true)
    cpus=$(nproc 2>/dev/null || true)
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
    load=$(awk '{ printf "%s", $1 }' /proc/loadavg 2>/dev/null || true)
    # base clock from the model name ("... @ 2.80GHz"); AMD chips print none,
    # so fall back to cpufreq's base_frequency, then amd-pstate-epp's
    # lowest_nonlinear_freq (the driver's floor, but it beats "?").
    # `read < file`, not $(cat file): a miss is silent and costs no fork.
    base_mhz=$(awk -F'@ *' '/model name/ && NF>1 { gsub(/GHz.*/, "", $2); printf "%.0f", $2 * 1000; exit }' /proc/cpuinfo 2>/dev/null || true)
    local khz freq_path
    for freq_path in "$cpufreq/base_frequency" "$cpufreq/amd_pstate_lowest_nonlinear_freq"; do
      [ -n "$base_mhz" ] && break
      [ -f "$freq_path" ] || continue
      read -r khz <"$freq_path" 2>/dev/null || khz=0
      base_mhz=$((khz / 1000))
      ((base_mhz)) || base_mhz=""
    done
    # boost/max clock: cpufreq first, else lscpu. khz reset, or a host with
    # base_frequency but no cpuinfo_max_freq reports its base as its boost.
    # cpuinfo_max_freq's *presence* gates the read (its value is never used):
    # scaling_max_freq alone, without the hardware figure beside it, is a
    # policy clamp with nothing to say it means "max".
    khz=0
    if [ -f "$cpufreq/cpuinfo_max_freq" ] && [ -f "$cpufreq/scaling_max_freq" ]; then
      read -r khz <"$cpufreq/scaling_max_freq" 2>/dev/null || khz=0
    fi
    boost_mhz=$((khz / 1000))
    ((boost_mhz)) || boost_mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/ { gsub(/ /, "", $2); printf "%.0f", $2 }' || true)
  elif [[ "$kernel" == MINGW* || "$kernel" == MSYS* || "$kernel" == CYGWIN* ]]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }' || true)
    # wmic only exposes the rated (base) clock
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }' || true)
  elif [ -z "$kernel" ]; then
    # no /etc/os-release and no uname: nothing to guess from
    os=""
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null || true)
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
    # Apple Silicon exposes neither clock via sysctl; only Intel Macs get a value
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }' || true)
  fi
  _hi_sanitize_var os "$os"
  # every probe above yields MHz (hence base_mhz/boost_mhz keep their names)
  [ -n "${base_mhz:-}" ] && _hi_ghz base_mhz "$base_mhz"
  [ -n "${boost_mhz:-}" ] && _hi_ghz boost_mhz "$boost_mhz"
  # a stripped-down awk or a locale that prints a comma decimal both fail
  # closed to "?", not a garbled cell
  case "$load" in '' | *[!0-9.]*) load="" ;; esac
  _hi_load_pct load_pct "$load" "${cpus:-}"
  _HI_SI_ARCH="$PURPLE${arch:-?}"
  _HI_SI_OS="$GREEN${os:-?}"
  _HI_SI_CORES="${YELLOW}Cores: ${cpus:-?}${load_pct:+ ($load_pct%)}"
  _HI_SI_CPU="${BRBLUE}CPU: $(_hi_cpu_clocks "${base_mhz:-}" "${boost_mhz:-}") GHz"
  _HI_SI_RAM="${CYAN}RAM: ${ram:-?}"
}

function _hi_cell_arch() {
  _hi_system_info_probe
  printf -v "$1" '%s' "$_HI_SI_ARCH"
}
function _hi_cell_os() {
  _hi_system_info_probe
  printf -v "$1" '%s' "$_HI_SI_OS"
}
function _hi_cell_cores() {
  _hi_system_info_probe
  printf -v "$1" '%s' "$_HI_SI_CORES"
}
function _hi_cell_cpu() {
  _hi_system_info_probe
  printf -v "$1" '%s' "$_HI_SI_CPU"
}
function _hi_cell_ram() {
  _hi_system_info_probe
  printf -v "$1" '%s' "$_HI_SI_RAM"
}

# The group wrapper: unchanged output for any direct caller (hi --doctor,
# a suite) that wants the whole bundle rather than picking individual words.
function system_info() {
  local arch os cores cpu ram
  _hi_cell_arch arch
  _hi_cell_os os
  _hi_cell_cores cores
  _hi_cell_cpu cpu
  _hi_cell_ram ram
  header_row "$arch" "$os" "$cores" "$cpu" "$ram"
}

# <var> gets the uptime cell, folded into identity() rather than a row of its
# own so it rides the wrap instead of always costing a line. Its own minimal
# probe rather than sharing system_info's: only the kernel branch (which
# command answers "how long has this box been up") is common to both, and
# duplicating that one `uname` call is cheaper than making the two share
# state.
function _hi_uptime_cell() {
  local kernel uptime_s="" up=""
  read -r kernel _ < <(uname -sm 2>/dev/null || :)
  _hi_sanitize_var kernel "$kernel"
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    uptime_s=$(awk '{ printf "%d", $1; exit }' /proc/uptime 2>/dev/null || true)
  elif [[ "$kernel" != MINGW* && "$kernel" != MSYS* && "$kernel" != CYGWIN* && -n "$kernel" ]]; then
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

# identity()'s backend probes are independent and each capped at
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

# Start whichever backends this host can answer, all at once. Split out of
# identity() so hi_header can start them first and the other rows run in
# their shadow.
function _hi_probe_launch() {
  local container_bin nomad=0 kube=0
  # idempotent: hi_header starts these early, and identity() calls it too so a
  # direct `identity` (the suites, hi --doctor) still probes
  [ -z "$_HI_PROBE_DIR" ] || return 0
  if command -v docker &>/dev/null; then
    container_bin=docker
  elif command -v podman &>/dev/null; then
    container_bin=podman
  fi
  command -v nomad &>/dev/null && nomad=1
  command -v kubectl &>/dev/null && kube=1
  [ -n "$container_bin" ] || ((nomad || kube)) || return 0
  _HI_PROBE_DIR="$(mktemp -d -t hi.probes.XXXXXX)"
  [ -n "$container_bin" ] && _hi_probe_start "$_HI_PROBE_DIR/containers" _hi_probe "$container_bin" container ls -q
  ((nomad)) && _hi_probe_start "$_HI_PROBE_DIR/nomad" _hi_probe nomad job status
  # kube counts through targets.sh, whose list_kube owns the "which pods count
  # as reachable" rule; docker/nomad counts answer a different question
  ((kube)) && _hi_probe_start "$_HI_PROBE_DIR/kube" sh "$_HI_TARGETS" kube
  return 0
}

# git identity (domain masked), containers/jobs/pods, ssh key counts - the
# detection identity()'s cells share, memoized into $_HI_ID_* the same way
# _hi_system_info_probe memoizes system_info()'s. $_HI_ID_CONTAINERS/_JOBS/_PODS
# stay empty when that backend's probe never ran - a getter checks for that
# itself, same "cell appears only when the probe actually ran" rule as
# before. Uptime is not part of this probe: _hi_uptime_cell already has its
# own minimal, independent one (see its own comment) and stays that way.
# Reads what _hi_probe_launch started; calls it itself if nobody did.
function _hi_identity_probe() {
  [ -z "${_HI_ID_PROBED:-}" ] || return 0
  _HI_ID_PROBED=1
  local email="" domain user_part bullets containers="" jobs="" pods="" authorized=0 public=0
  local -a lines
  command -v git &>/dev/null && email=$(git config --get user.email 2>/dev/null || true)
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
    if [ -f "$_HI_PROBE_DIR/containers" ]; then
      _hi_read_lines lines <"$_HI_PROBE_DIR/containers"
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

function _hi_cell_gitid() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_GITID"
}
function _hi_cell_containers() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_CONTAINERS"
}
function _hi_cell_jobs() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_JOBS"
}
function _hi_cell_pods() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_PODS"
}
function _hi_cell_auth() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_AUTH"
}
function _hi_cell_pub() {
  _hi_identity_probe
  printf -v "$1" '%s' "$_HI_ID_PUB"
}
function _hi_cell_uptime() {
  _hi_uptime_cell "$1"
}

# The group wrapper: unchanged output for any direct caller (hi --doctor,
# a suite) that wants the whole bundle rather than picking individual words.
function identity() {
  local gitid containers jobs pods auth pub up_cell
  local -a cells
  _hi_cell_gitid gitid
  _hi_cell_containers containers
  _hi_cell_jobs jobs
  _hi_cell_pods pods
  _hi_cell_auth auth
  _hi_cell_pub pub
  _hi_cell_uptime up_cell
  cells=("$gitid")
  [ -n "$containers" ] && cells+=("$containers")
  [ -n "$jobs" ] && cells+=("$jobs")
  [ -n "$pods" ] && cells+=("$pods")
  cells+=("$auth" "$pub" "$up_cell")
  header_row "${cells[@]}"
}

# "~~~ <label> [host] ~~~" prefixed with say-hi's local change count, always
# _hi_draw_width columns wide
function banner() {
  [[ "${_HI_HEADER_BANNER:-1}" == 0 ]] && return 0
  local label="$1" color="${2:-$BRGREEN}" changes="" prefix="${3:-}" changes_w=0
  # ~10ms of `git status`, computed once and kept for both banners
  if [ -d "$_HI_ROOT/.git" ]; then
    if [ -z "${_HI_BANNER_CHANGES+x}" ]; then
      local -a lines
      _hi_read_lines lines < <(git -C "$_HI_ROOT" status --short 2>/dev/null)
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
  [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]] && lead=""
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

# tmux swallows the DCS passthrough osc52.sh and notify.sh wrap their escapes
# in unless `allow-passthrough` is on (off by default since tmux 3.3), and
# nothing fails visibly - that is the "hi_copy does nothing" report, answered
# here before it is filed. Three conditions: a tmux in the way ($TMUX, not
# $TERM), at least one of the two features on, and the option not set.
# `show -Apv`: allow-passthrough is a *pane* option, -A includes the inherited
# global; a tmux too old to have it answers nothing, and nothing is the right
# thing to say back. `all` counts as on. No _HI_HEADER_* toggle: this row only
# appears where something is broken, and fixing it silences it.
function passthrough_check() {
  local value
  [ -n "${TMUX:-}" ] || return 0
  [[ "${_HI_DISABLE_OSC52:-0}" == 1 && "${_HI_DISABLE_NOTIFY:-0}" == 1 ]] && return 0
  command -v tmux &>/dev/null || return 0
  value="$(tmux show -Apv allow-passthrough 2>/dev/null || true)"
  [ -n "$value" ] || value="$(tmux show -gv allow-passthrough 2>/dev/null || true)"
  case "$value" in on | all | '') return 0 ;; esac
  header_row "${YELLOW}tmux passthrough off - hi_copy/hi_notify muted" \
    "${BRYELLOW}set -g allow-passthrough on"
}

# hi_header's default row order, and $_HI_HEADER_ORDER's vocabulary - one word
# per feature, in the shipped default order - no more grouping: any word may
# be reordered or left out on its own, independent of the others. Named here
# rather than only in the case below, so a doc or test can read the default
# without parsing the dispatch.
_HI_HEADER_ORDER_DEFAULT="utc version localtime arch os cores cpu ram gitid containers jobs pods auth pub uptime check"

# <var> gets $1's cell text if $1 names a getter, empty otherwise -
# _hi_collect_header_word's own dispatch, split out so a direct caller (a
# suite) can ask "what would this word render as" without going through the
# accumulate/flush machinery below.
function _hi_header_word_cell() {
  case "$1" in
  utc) _hi_cell_utc "$2" ;;
  version) _hi_cell_version "$2" ;;
  localtime) _hi_cell_localtime "$2" ;;
  arch) _hi_cell_arch "$2" ;;
  os) _hi_cell_os "$2" ;;
  cores) _hi_cell_cores "$2" ;;
  cpu) _hi_cell_cpu "$2" ;;
  ram) _hi_cell_ram "$2" ;;
  gitid) _hi_cell_gitid "$2" ;;
  containers) _hi_cell_containers "$2" ;;
  jobs) _hi_cell_jobs "$2" ;;
  pods) _hi_cell_pods "$2" ;;
  auth) _hi_cell_auth "$2" ;;
  pub) _hi_cell_pub "$2" ;;
  uptime) _hi_cell_uptime "$2" ;;
  *) printf -v "$2" '%s' "" ;;
  esac
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
function _hi_header_word_alt() {
  case "$1" in
  utc) printf -v "$2" '%s' "$BRCYAN" ;;
  version) printf -v "$2" '%s' "$BRCYAN" ;;
  localtime) printf -v "$2" '%s' "$BRRED" ;;
  arch) printf -v "$2" '%s' "$BRCYAN" ;;
  os) printf -v "$2" '%s' "$BRPURPLE" ;;
  cores) printf -v "$2" '%s' "$BRGREEN" ;;
  cpu) printf -v "$2" '%s' "$BRPURPLE" ;;
  ram) printf -v "$2" '%s' "$BRGREEN" ;;
  gitid) printf -v "$2" '%s' "$BRRED" ;;
  containers) printf -v "$2" '%s' "$BRYELLOW" ;;
  jobs) printf -v "$2" '%s' "$BRYELLOW" ;;
  pods) printf -v "$2" '%s' "$BRCYAN" ;;
  auth) printf -v "$2" '%s' "$BRYELLOW" ;;
  pub) printf -v "$2" '%s' "$BRRED" ;;
  uptime) printf -v "$2" '%s' "$BRGREEN" ;;
  *) printf -v "$2" '%s' "" ;;
  esac
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
    _hi_header_word_alt "$1" alt
    local re='^\\e\[[01];3[1-6]m(.*)$'
    [[ "$cell" =~ $re ]] && cell="$alt${BASH_REMATCH[1]}"
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
  if _hi_order_has containers || _hi_order_has jobs || _hi_order_has pods; then
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
  # last, so the one line that says something is wrong sits next to the
  # prompt. Connect only: load.sh's disconnect calls banner directly. No
  # _HI_HEADER_ORDER word of its own - like passthrough_check always was,
  # this is not a word a reorder moves.
  passthrough_check
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
# The numbered lines below are scraped verbatim by scripts/packages_preview.sh
# (the run directly above _HI_YES, parentheticals dropped): keep the
# "# <n> <meaning> (<examples>)" shape and add nothing between them and the
# table.
# 0 platform trivia (sw_vers, kitty)
# 1 optional extras (gping, navi)
# 2 useful tools (make, vim, python3)
# 3 favorites and core (bat, fzf, awk)
_HI_YES=("$CYAN" "$GREEN" "$BRCYAN" "$BRGREEN")
_HI_NO=("$BLUE" "$PURPLE" "$BRYELLOW" "$BRRED")

# $_HI_PACKAGES_PALETTE picks one of the named ramps below over the two
# tables just assigned - packages_preview.sh's scrape (above) stops at the
# first line starting "_HI_YES=", so that assignment has to stay exactly
# there and cannot move into the case. Every value is one of
# _HI_COLOR_NAMES (core.sh), the vocabulary settings/colors and fish's
# set_color both use, so packages_preview.sh's _hi_color_name_of can always
# name it. Each ramp is meant to read monotonic 0->3 in both directions - a
# missing favorite the loudest thing on screen, installed trivia the
# quietest - and legible on light and dark terminals alike; judge a
# candidate with `hi --packages-preview`. "cool" is the shipped default:
# _HI_YES/_HI_NO as assigned just above, unchanged from a fresh source so
# the common case (no override, no palette function call yet) costs nothing
# extra to read.
function _hi_packages_palette() {
  case "${_HI_PACKAGES_PALETTE:-cool}" in
  warm)
    _HI_YES=("$YELLOW" "$BRYELLOW" "$GREEN" "$BRGREEN")
    _HI_NO=("$PURPLE" "$BRPURPLE" "$RED" "$BRRED")
    ;;
  mono)
    _HI_YES=("$BLUE" "$CYAN" "$BRBLUE" "$BRCYAN")
    _HI_NO=("$YELLOW" "$BRYELLOW" "$RED" "$BRRED")
    ;;
  *)
    _HI_YES=("$CYAN" "$GREEN" "$BRCYAN" "$BRGREEN")
    _HI_NO=("$BLUE" "$PURPLE" "$BRYELLOW" "$BRRED")
    ;;
  esac
}
_hi_packages_palette

# For each "[-|+]cmd:priority[,...]": the highest-priority installed package
# (or the first, if none) — a fully-missing line ranks at the max priority
# among its alternatives — colored and marked per above. `-` drops the row
# when something is installed, `+` when nothing is. The marks live in
# core.sh's _hi_choose_glyphs.
function check_line() {
  local pair cmd priority color best best_priority max_priority best_idx=0 idx=0 found=0 symbol rendered
  local mode=both line=$1
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

  local mark_w
  if ((found)); then
    [[ "$mode" == miss ]] && return 0
    color="${_HI_YES[best_priority]:-$NC}"
    if ((best_idx == 0)); then
      symbol="$GREEN$_HI_MARK_OK" mark_w="$_HI_MARK_OK_W"
    else
      symbol="$YELLOW$_HI_MARK_ALT$NC" mark_w="$_HI_MARK_ALT_W"
    fi
  else
    [[ "$mode" == have ]] && return 0
    best_priority=$max_priority
    color="${_HI_NO[best_priority]:-$NC}"
    symbol="$RED$_HI_MARK_NO" mark_w="$_HI_MARK_NO_W"
  fi
  rendered="$color $best $symbol"
  # 4 = the "| " lead plus the spaces around the item; the mark's width comes
  # from the chosen glyph set (ASCII "ok" is two columns, ✓ is one)
  visible+=("$best_priority"$'\x1f'"$((${#best} + 4 + mark_w))"$'\x1f'"$rendered")
}

# print sorted package results limited by _hi_draw_width, from
# $_HI_PACKAGES_MIN_PRIORITY up. The floor lives here, not in check_line:
# scripts/packages_preview.sh calls check_line directly and needs the rows
# the floor hides.
function full_check() {
  local line priority width_item rendered count=0 max cell vislen piece i
  _hi_draw_width max
  local width=$max
  local min="${_HI_PACKAGES_MIN_PRIORITY:-2}"
  local -a visible=() row_widths=() row_pieces=() # visible appended to by check_line
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

  while IFS=$' ' read -r line; do
    [[ "$line" == *#* || -z "$line" ]] || check_line "$line"
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
      if [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]]; then
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
