#!/usr/bin/env bash
# The connect/disconnect banner and header for every shell (fish shells out
# here), and the package check (full_check) at the bottom. No strict mode of
# its own, since core.sh releases it; the `|| true` guards protect a caller
# under strict mode (configure.sh's previews).

# core.sh through this file's own path; it derives the tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# shellcheck source=./core.sh
source "$_hi_d/core.sh"
unset _hi_d

# <var> gets $2's visible column width, color vars stripped. They hold a
# literal `\e` (only header_row's final `printf '%b'` interprets it), so the
# pattern matches that, not $'\e'.
function _hi_visible_width() {
  local s="$2" re='^(.*)\\e\[[0-9;]*m(.*)$'
  while [[ "$s" =~ $re ]]; do s="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  # where ${#} counts bytes (core.sh's $_HI_BYTE_COUNTS), the UTF-8
  # continuation bytes come off first: 0x80-0xBF never start a character, so
  # what is left is one byte per column. GLOSSARY: HI.12
  ((_HI_BYTE_COUNTS)) && s="${s//[$'\200'-$'\277']/}"
  printf -v "$1" '%d' "${#s}"
}

# <var> gets $2's hue: the digit of its leading `\e[<bold>;3<n>m` escape,
# ignoring bold, so CYAN and BRCYAN match. A scheme's escape continues with
# `;38;2;...` after the digit (GLOSSARY: HI.50). Empty with no leading escape
# (NO_COLOR). Anchored, so an "m" in plain text ("GHz") is never read as one.
function _hi_cell_hue() {
  local s="$2" re='^\\e\[[01];3([1-6])[;m]'
  printf -v "$1" '%s' ""
  [[ "$s" =~ $re ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
}

# <var> gets the width the header draws to: $_HI_MAX_WIDTH, narrowed to the
# window so the terminal never breaks a cell. A set $_HI_TERM_COLS always
# wins (the suites pin it). Otherwise only a tty narrows: $COLUMNS, read fresh
# each call, else `tput`, memoized into $_HI_TERM_COLS. Captured output (the
# previews, `hi --doctor`) keeps $_HI_MAX_WIDTH. Locals are prefixed so
# `printf -v "$1"` cannot hit a same-named local.
function _hi_draw_width() {
  local _hi_dw_max=${_HI_MAX_WIDTH:-$_HI_MAX_WIDTH_DEFAULT} _hi_dw_cols=""
  _hi_term_cols _hi_dw_cols
  # a tput answer is remembered for the header's many draws
  [ -n "${_HI_TERM_COLS+x}" ] || [ ! -t 1 ] || case "${COLUMNS:-}" in '' | *[!0-9]*) _HI_TERM_COLS="$_hi_dw_cols" ;; esac
  [ -n "$_hi_dw_cols" ] && ((_hi_dw_cols < _hi_dw_max)) && _hi_dw_max=$_hi_dw_cols
  printf -v "$1" '%d' "$_hi_dw_max"
}

# A row's overflow cells, handed to the next row instead of costing a line.
# Armed only inside hi_header's row loop; elsewhere header_row drains its own
# carry before returning.
_HI_ROW_CARRY_ARMED=0
declare -a _HI_ROW_CARRY=()

# The previous $_HI_HEADER_ORDER cell's hue, tracked across
# _hi_collect_header_word calls so a colliding neighbor can be recolored.
# File scope, like $_HI_ROW_CARRY_ARMED above: configure.sh's previews run
# under their own strict mode, and an unset global there is a `set -u` trip,
# not a silently-empty read.
_HI_PREV_HUE=""

# Prints one line at _hi_draw_width from <cells...> and leaves the rest in
# $_HI_ROW_CARRY. The first cell is always placed; it stops at the first cell
# that does not fit rather than reorder the header. Each cell ends with a
# reset so no color bleeds past a line break. Returns 1 for zero cells.
function _hi_row_line() {
  local cell out="" max vislen width=0 i close=1 pad=""
  _hi_draw_width max
  # The closing " |" owns the last two columns, so every cell is budgeted
  # against a width that short and the row still ends where the banner does.
  # $_HI_DISABLE_RIGHT_EDGE gives back the open-ended row this drew before.
  [[ "${_HI_DISABLE_RIGHT_EDGE:-0}" == 1 ]] && close=0
  ((close)) && ((max -= 2))
  _HI_ROW_CARRY=()
  for ((i = 1; i <= $#; i++)); do
    cell="${!i}"
    _hi_visible_width vislen "$cell"
    vislen=$((vislen + 3)) # " | " - the join this has always used
    if ((i > 1 && width + vislen > max)); then
      _HI_ROW_CARRY=("${@:$i}")
      break
    fi
    # $_HI_DISABLE_LEAD_SPACE drops just the first cell's leading space - the
    # "| " between later cells is the structural separator, not "the initial
    # space", and stays either way
    if ((i == 1)) && [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]]; then
      out+="$NC| $cell"
    else
      out+="$NC | $cell"
    fi
    width=$((width + vislen))
  done
  (($#)) || return 1
  # An oversized lone cell is placed anyway (above), so the pad can be asked
  # for a negative width - _hi_repeat treats that as none, and the pipe lands
  # right after the cell rather than being dropped.
  if ((close)); then
    _hi_repeat pad $((max - width)) ' '
    out+="$NC$pad |"
  fi
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

# The header's version cell, display only (`hi --version` has the full one):
# at most 10 columns, `-dirty` dropped, a tag as is, <tag>+N past a tag (a
# bare `+` when N does not fit), a bare hash cut to 6. GLOSSARY: HI.05
function _hi_shorten_describe() {
  local _hi_sd_v="${1%-dirty}"
  if ((${#_hi_sd_v} > 6)) && [[ "$_hi_sd_v" != *[!0-9a-f]* ]]; then
    _hi_sd_v="${_hi_sd_v:0:6}"
  elif ((${#_hi_sd_v} > 10)) && [[ "$_hi_sd_v" == *+* ]]; then
    _hi_sd_v="${_hi_sd_v%+*}"
    _hi_sd_v="${_hi_sd_v:0:9}+"
  fi
  _hi_out "${2:-}" "${_hi_sd_v:0:10}"
}

# hi's version for the header, resolved once per shell (the row prints twice
# a session); a stampless, gitless install gets "unknown".
function _hi_header_version() {
  if [ -z "${_HI_HEADER_VERSION+x}" ]; then
    local v="${_HI_RELEASE:-}"
    [ -n "$v" ] || _hi_slow_out v describe
    _hi_sanitize_var _HI_HEADER_VERSION "$v"
    [ -n "$_HI_HEADER_VERSION" ] || _HI_HEADER_VERSION="unknown"
    _hi_shorten_describe "$_HI_HEADER_VERSION" _HI_HEADER_VERSION
  fi
}

# _hi_cell_clock <outvar> <color> [utc] - a clock cell, a pure getter (the
# header's dispatch packs cells onto shared lines). bash 4.2+ formats it with
# printf's %(...)T and no fork (four a session, dear on Git Bash); 3.2 forks
# date(1), and no date(1) there reads "?". Prefixed local: timestamp() passes
# "utc"/"localtime" as $1, and printf -v would otherwise land in this frame.
function _hi_cell_clock() {
  local _hi_ck_raw=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    if [ -n "${3:-}" ]; then
      TZ=UTC0 printf -v _hi_ck_raw "%(${_HI_HUMAN_CENTRIC_DATE#+})T" -1
    else
      printf -v _hi_ck_raw "%(${_HI_HUMAN_CENTRIC_DATE#+})T" -1
    fi
  else
    # hi-nocov-begin: bash before 4.2 - macOS's 3.2, which no sweep runs
    # shellcheck disable=SC2086 # ${3:+-u} is a flag or nothing, never a word
    _hi_ck_raw="$(exec date ${3:+-u} "$_HI_HUMAN_CENTRIC_DATE" 2>/dev/null)" || _hi_ck_raw=""
    # hi-nocov-end
  fi
  printf -v "$1" '%s' "$2${_hi_ck_raw:-?}"
}
function _hi_cell_utc() { _hi_cell_clock "$1" "$BRBLUE" utc; }

function _hi_cell_version() {
  _hi_header_version
  printf -v "$1" '%s' "$GREEN$_HI_HEADER_VERSION"
}

function _hi_cell_localtime() { _hi_cell_clock "$1" "$BRYELLOW"; }

# The utc/version/localtime row in one call, for hi_footer's disconnect row
# and tests/common/header_test.sh.
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

# _hi_linux_ram <var> <meminfo> - "<used>/<total>G", used being MemTotal -
# MemAvailable as free(1) reports it (a pre-3.14 kernel gets its total only).
# GiB rounded half up; a `read` loop, not an awk fork.
function _hi_linux_ram() {
  local k v total="" avail=""
  printf -v "$1" '%s' ''
  [ -r "$2" ] || return 0
  while read -r k v _; do
    case "$k" in
    MemTotal:) total="$v" ;;
    MemAvailable:)
      avail="$v"
      break
      ;;
    esac
  done <"$2"
  if [ -n "$avail" ]; then
    printf -v "$1" '%s/%sG' "$(((total - avail + 524288) / 1048576))" "$(((total + 524288) / 1048576))"
  elif [ -n "$total" ]; then
    printf -v "$1" '%sG' "$(((total + 524288) / 1048576))"
  fi
}

# _hi_linux_base_mhz <var> <cpuinfo> <cpufreq dir> - the base clock in MHz,
# from the first model name ("... @ 2.80GHz"); AMD chips print none, so
# cpufreq's base_frequency, then amd-pstate-epp's lowest_nonlinear_freq (the
# driver's floor, but it beats "?"); empty when nothing answers. `read <
# file`, not $(cat file): a miss is silent and costs no fork.
function _hi_linux_base_mhz() {
  local line v k khz freq_path mhz=""
  if [ -r "$2" ]; then
    while IFS= read -r line; do
      case "$line" in "model name"*) ;; *) continue ;; esac
      case "$line" in *@*GHz*)
        v="${line#*@}" v="${v%%GHz*}" v="${v// /}"
        k="${v#*.}000"
        case "$v" in *.*) ;; *) k=000 ;; esac
        case "${v%%.*}${k:0:3}" in '' | *[!0-9]*) ;; *) mhz=$((10#${v%%.*} * 1000 + 10#${k:0:3})) ;; esac
        ;;
      esac
      break
    done <"$2"
  fi
  for freq_path in "$3/base_frequency" "$3/amd_pstate_lowest_nonlinear_freq"; do
    [ -n "$mhz" ] && break
    [ -f "$freq_path" ] || continue
    read -r khz <"$freq_path" 2>/dev/null || khz=0
    mhz=$((khz / 1000))
    ((mhz)) || mhz=""
  done
  printf -v "$1" '%s' "$mhz"
}

# _hi_load_pct <var> <load> <cpus> - the 1-minute load as a percentage of the
# core count ("2.34" on 8 cores -> "29"). Empty when an input is missing or
# <cpus> is not a positive integer (Windows' "?").
function _hi_load_pct() {
  local load="$2" cpus="$3" whole frac
  case "$cpus" in '' | *[!0-9]*) return 0 ;; esac
  case "$load" in '' | *[!0-9.]* | *.*.*) return 0 ;; esac
  ((cpus > 0)) || return 0
  # hundredths of load over the cores, rounded half up, in shell arithmetic
  whole="${load%%.*}" frac="${load#"${load%%.*}"}00"
  frac="${frac#.}"
  printf -v "$1" '%d' $(((2 * (10#${whole:-0} * 100 + 10#${frac:0:2}) + cpus) / (2 * cpus)))
}

# _hi_platform <outvar> - linux, windows, bsd, or unknown, for the probes
# below. Not memoized: header_test.sh points $_HI_LINUX_RELEASE at a fixture
# after sourcing. Linux needs no `uname`.
function _hi_platform() {
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    printf -v "$1" '%s' linux
  else
    _hi_uname
    case "$_HI_KERNEL" in
    MINGW* | MSYS* | CYGWIN*) printf -v "$1" '%s' windows ;;
    '') printf -v "$1" '%s' unknown ;;
    *) printf -v "$1" '%s' bsd ;;
    esac
  fi
}

# $_HI_KERNEL and $_HI_ARCH off the files a Linux from 6.1 has, with no fork
function _hi_uname_linux() {
  [ -f "$_HI_LINUX_RELEASE" ] && [ -r /proc/sys/kernel/arch ] &&
    read -r _HI_KERNEL </proc/sys/kernel/ostype && read -r _HI_ARCH </proc/sys/kernel/arch
}

# $_HI_CPUS_ALLOWED: the CPUs this process may run on, which is what nproc
# counts, off /proc/self/status's list of them; empty where it has none
function _hi_cpus_allowed() {
  local k v r n=0 IFS=$':\t '
  _HI_CPUS_ALLOWED=""
  [ -r /proc/self/status ] || return 0
  while read -r k v; do
    [ "$k" = Cpus_allowed_list ] || continue
    IFS=,
    for r in $v; do
      case "$r" in
      *-*) n=$((n + ${r#*-} - ${r%-*} + 1)) ;;
      ?*) n=$((n + 1)) ;;
      esac
    done
    break
  done </proc/self/status
  [ "$n" = 0 ] || _HI_CPUS_ALLOWED="$n"
}

# $_HI_KERNEL and $_HI_ARCH, from one memoized `uname -sm` where Linux's files
# do not say; no uname leaves both empty, rendered "?"
function _hi_uname() {
  [ -z "${_HI_KERNEL+x}" ] || return 0
  ! _hi_uname_linux || return 0
  local v
  _hi_slow_out v uname
  _hi_sanitize_var _HI_KERNEL "${v%% *}"
  case "$v" in *' '*) v="${v#* }" ;; *) v="" ;; esac
  _hi_sanitize_var _HI_ARCH "$v"
}

# The detection the five sysinfo cells (os arch cores cpu ram) share, run once
# per shell and memoized into $_HI_SI_* (fully rendered, colored cell text -
# the same memo-once shape $_HI_HEADER_VERSION uses) so splitting the cells
# into independently orderable/toggleable $_HI_HEADER_ORDER words costs
# nothing extra: arch alone still pays for exactly one probe, not five.
function _hi_system_info_probe() {
  [ -z "${_HI_SI_PROBED:-}" ] || return 0
  _HI_SI_PROBED=1
  local os="" cpus="" ram="" base_mhz="" load="" load_pct="" plat
  _hi_platform plat
  _hi_uname
  if [ "$plat" = linux ]; then
    # WSL too. Every probe ends `|| true`, so a stripped target shows "?"; a
    # `read` loop each, not an awk fork.
    local k v
    while IFS='=' read -r k v; do
      [ "$k" != PRETTY_NAME ] || os="${v//\"/}"
    done <"$_HI_LINUX_RELEASE"
    _hi_cpus_allowed
    cpus="$_HI_CPUS_ALLOWED"
    [ -n "$cpus" ] || _hi_slow_out cpus nproc
    # straight at the files free(1) and uptime(1) themselves read
    _hi_linux_ram ram /proc/meminfo
    read -r load _ 2>/dev/null </proc/loadavg || load=""
    _hi_linux_base_mhz base_mhz /proc/cpuinfo /sys/devices/system/cpu/cpu0/cpufreq
  elif [ "$plat" = windows ]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($_HI_KERNEL)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }' || true)
    # wmic only exposes the rated (base) clock
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }' || true)
  elif [ "$plat" = bsd ]; then
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
    cpus=$(exec sysctl -n hw.ncpu 2>/dev/null) || true
    # total from sysctl, used from vm_stat: active + wired + compressed pages,
    # at vm_stat's own page size (its "(page size of N bytes)" header, not the
    # hardcoded 4096, which Apple Silicon's 16K pages break) - matched
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
    # `cpu` from $_HI_HEADER_ORDER on such a box.
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }' || true)
  fi
  _hi_sanitize_var os "$os"
  # every probe above yields MHz (hence base_mhz keeps its name)
  [ -n "${base_mhz:-}" ] && _hi_ghz base_mhz "$base_mhz"
  _hi_load_pct load_pct "$load" "${cpus:-}"
  _HI_SI_ARCH="$PURPLE${_HI_ARCH:-?}"
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

# <var> gets the uptime cell, its platform from _hi_platform so `uname` runs
# once per session.
function _hi_cell_uptime() {
  local uptime_s="" up="" plat
  _hi_platform plat
  if [ "$plat" = linux ]; then
    read -r uptime_s _ 2>/dev/null </proc/uptime || uptime_s=""
    uptime_s="${uptime_s%%.*}"
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
  [ -n "$uptime_s" ] && _hi_human_duration "$uptime_s" up
  printf -v "$1" '%s' "${BRBLUE}Up: ${up:-?}"
}

# <var> gets the ip cell: _hi_ip_list's addresses less $_HI_IP_HIDE's,
# comma-joined, "?" where nothing routable was found.
function _hi_cell_ip() {
  local ips
  _hi_slow_out ips ips
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
  # Display only, and the last thing that happens to the list: the comma
  # stays this cell's internal separator, which is what _hi_ip_list builds
  # and what _hi_ip_filter's peel reads, so nothing that splits on it
  # has to learn about the space.
  ips="${ips//,/, }"
  printf -v "$1" '%s' "${BLUE}IP: ${ips:-?}"
}

# the routable addresses, comma-joined, for _hi_cell_ip, each followed by
# %<interface> where the tool says which: _hi_ip_filter reads that and drops it
function _hi_ip_list() {
  local ips="" plat
  _hi_platform plat
  # One possibly-absent tool per branch, piped into awk for the rest: awk is
  # on every target, `cut`/`tr`/`grep` may not be. GLOSSARY: HI.30
  if [ "$plat" = linux ]; then
    # SGR stripped first: an `ip` that colors (an alias or wrapper the shell
    # brought along, or `ip -c`) wraps each address, which shifts nothing in
    # the field layout but defeats the filter's globs and leaks the escapes.
    # A `read` loop, since this runs every connect and awk is an exec.
    local out n a sgr=$'\033\\[[0-9;]*m'
    out="$(exec ip -4 -o addr show scope global 2>/dev/null)" || out=""
    while [[ "$out" =~ $sgr ]]; do out="${out//"${BASH_REMATCH[0]}"/}"; done
    while read -r _ n _ a _; do
      [ -n "$a" ] || continue
      ips="$ips${ips:+,}${a%%/*}%${n%%@*}"
    done <<<"$out"
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
    ips=$(ifconfig 2>/dev/null | awk '/^[^ \t]/ { n = $1; sub(/:$/, "", n) }
      /inet / && $2 !~ /^127\./ {
      printf "%s%s", sep, $2; if (n != "") printf "%%%s", n; sep = ","
    }')
  fi
  printf '%s' "$ips"
}

# _hi_ip_filter <outvar> <comma-joined addresses> - the list without each
# %<interface>, minus every address a $_HI_IP_HIDE glob matches by address or
# interface (unset or empty: the bridge defaults; `none`: nothing). Words are
# peeled one at a time, since a `for` would expand a glob against the cwd.
function _hi_ip_filter() {
  local _hi_if_hide="${_HI_IP_HIDE:-$_HI_IP_HIDE_DEFAULT}" _hi_if_rest="${2:+$2,}" _hi_if_kept="" _hi_if_ip _hi_if_dev
  while [ -n "$_hi_if_rest" ]; do
    _hi_if_ip="${_hi_if_rest%%,*}" _hi_if_rest="${_hi_if_rest#*,}"
    _hi_if_dev=""
    case "$_hi_if_ip" in *%*) _hi_if_dev="${_hi_if_ip#*%}" _hi_if_ip="${_hi_if_ip%%%*}" ;; esac
    if [ "$_hi_if_hide" != none ]; then
      # core.sh's matcher: the same peel and glob rule
      ! _hi_ssh_pattern_hit "$_hi_if_ip" "$_hi_if_hide" || continue
      [ -z "$_hi_if_dev" ] || ! _hi_ssh_pattern_hit "$_hi_if_dev" "$_hi_if_hide" || continue
    fi
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

# Where the probes and prefetches drop their output; empty until one starts,
# so a header needing neither pays no mktemp and no rm. $_HI_PROBE_HOLD keeps
# it past _hi_identity_probe for hi_header's later cells. A session's tree
# comes with an empty hi.probes (hi.sh's _hi_remote_middle), taken while it
# is still empty and left to the tree's removal: no mktemp and no rm.
_HI_PROBE_DIR="" _HI_PROBE_LAUNCHED="" _HI_PROBE_HOLD="" _HI_PF_KEYS=""

function _hi_probe_dir() {
  [ -z "$_HI_PROBE_DIR" ] || return 0
  if [ -n "${_HI_CLEANUP:-}" ] && [ -d "$_HI_CLEANUP/hi.probes" ]; then
    local -a _hi_pd_f=("$_HI_CLEANUP/hi.probes"/*)
    [ -e "${_hi_pd_f[0]}" ] || _HI_PROBE_DIR="$_HI_CLEANUP/hi.probes"
  fi
  [ -n "$_HI_PROBE_DIR" ] || _HI_PROBE_DIR="$(mktemp -d -t hi.probes.XXXXXX)"
  [ -n "$_HI_PROBE_DIR" ]
}

# waits out whatever is still running, then removes the directory
function _hi_probe_done() {
  [ -z "$_HI_PROBE_HOLD" ] && [ -n "$_HI_PROBE_DIR" ] || return 0
  local k pid
  for k in $_HI_PF_KEYS; do
    k="_HI_PF_$k"
    pid="${!k:-}"
    printf -v "$k" '%s' ''
    [ -z "$pid" ] || wait "$pid" 2>/dev/null || true
  done
  _hi_probe_wait
  [ "$_HI_PROBE_DIR" = "${_HI_CLEANUP:-}/hi.probes" ] || command rm -rf "$_HI_PROBE_DIR"
  _HI_PROBE_DIR="" _HI_PROBE_LAUNCHED="" _HI_PF_KEYS=""
}

# The header's fork-bound lookups, one spelling each. A cell reads one through
# _hi_slow_out; hi_header starts the ones its order needs up front, so they
# run side by side in the shadow of the rows before them.
function _hi_slow() {
  # always in a subshell (below), so a lone command can replace it
  case "$1" in
  status) exec git -C "$_HI_ROOT" --no-optional-locks status --porcelain=v2 --branch ;;
  describe) _hi_release_or_describe ;;
  email) exec git config --get user.email ;;
  uname) exec uname -sm ;;
  nproc) exec nproc ;;
  ips) _hi_ip_list ;;
  pubs) exec find "$_HI_SSH_DIR" -type f -name "*.pub" ;;
  esac
}

function _hi_slow_start() { # <key>
  _hi_probe_dir || return 0
  _hi_slow "$1" >"$_HI_PROBE_DIR/pf.$1" 2>/dev/null &
  printf -v "_HI_PF_$1" '%s' "$!"
  _HI_PF_KEYS="$_HI_PF_KEYS $1" _HI_PF_SUB="$BASH_SUBSHELL"
}

# _hi_slow_out <outvar> <key> - $(_hi_slow <key>): the prefetched answer when
# this shell started one, else run here. A $( ) below the starter cannot
# `wait` on its job, so it runs its own.
function _hi_slow_out() {
  local _hi_so_pid="_HI_PF_$2" _hi_so_v="" _hi_so_nl=$'\n'
  _hi_so_pid="${!_hi_so_pid:-}"
  if [ -n "$_hi_so_pid" ] && [ "$BASH_SUBSHELL" = "${_HI_PF_SUB:-}" ]; then
    printf -v "_HI_PF_$2" '%s' ''
    wait "$_hi_so_pid" 2>/dev/null || true
    IFS= read -r -d '' _hi_so_v <"$_HI_PROBE_DIR/pf.$2" || true
    _hi_so_v="${_hi_so_v%"${_hi_so_v##*[!"$_hi_so_nl"]}"}"
  else
    _hi_so_v="$(_hi_slow "$2" 2>/dev/null)" || true
  fi
  printf -v "$1" '%s' "$_hi_so_v"
}

# Start the lookups this order's cells will read. Each is skipped once its
# memo is set, as configure.sh's repeated renders inherit them.
function _hi_header_prefetch() {
  if [ -d "$_HI_ROOT/.git" ]; then
    ! _hi_order_has banner || [ -n "${_HI_BANNER_CHANGES+x}" ] || _hi_slow_start status
    _hi_order_has version && [ -z "${_HI_HEADER_VERSION+x}${_HI_RELEASE:-}" ] && _hi_slow_start describe
  fi
  if [ -z "${_HI_ID_PROBED:-}" ]; then
    _hi_order_has gitid && _hi_slow_start email
    _hi_order_has pub && [ -d "$_HI_SSH_DIR" ] && _hi_slow_start pubs
  fi
  if [ -z "${_HI_SI_PROBED:-}" ]; then
    [ -z "${_HI_KERNEL+x}" ] && _hi_order_has arch && ! _hi_uname_linux && _hi_slow_start uname
    _hi_order_has cores && [ -f "$_HI_LINUX_RELEASE" ] && [ ! -r /proc/self/status ] && _hi_slow_start nproc
  fi
  _hi_order_has ip && _hi_slow_start ips
  return 0
}

# Start whichever backends this host can answer, all at once. Its own
# function so hi_header can start them first and the other rows run in their
# shadow.
function _hi_probe_launch() {
  local cli clis="" nomad=0 kube=0
  # idempotent: hi_header starts these early, and _hi_identity_probe calls it
  # too so a direct cell read (the suites, hi --doctor) still probes
  [ -z "$_HI_PROBE_DIR" ] || [ -z "$_HI_PROBE_LAUNCHED" ] || return 0
  # one lane per docker-compatible CLI on $PATH (GLOSSARY: HI.51); the cell
  # below unions the lanes, so two CLIs fronting one daemon count once.
  # $_HI_CONTAINER_CLIS (core.sh); common/targets.sh spells the same four
  # words again and the drift suite pins the two together.
  for cli in $_HI_CONTAINER_CLIS; do
    command -v "$cli" &>/dev/null && ! _hi_backend_off "$cli" && clis="$clis${clis:+ }$cli"
  done
  command -v nomad &>/dev/null && ! _hi_backend_off nomad && nomad=1
  command -v kubectl &>/dev/null && ! _hi_backend_off kube && kube=1
  [ -n "$clis" ] || ((nomad || kube)) || return 0
  _hi_probe_dir || return 0
  _HI_PROBE_LAUNCHED=1
  _hi_probe true # settled once here, not once per lane
  for cli in $clis; do
    _hi_probe_start "$_HI_PROBE_DIR/containers.$cli" _hi_probe "$cli" container ls -q
  done
  ((nomad)) && _hi_probe_start "$_HI_PROBE_DIR/nomad" _hi_probe nomad job status
  # kube counts through targets.sh, whose list_kube owns the "which pods count
  # as reachable" rule; docker/nomad counts answer a different question
  ((kube)) && _hi_probe_start "$_HI_PROBE_DIR/kube" sh "$_HI_TARGETS" kube
  return 0
}

# git identity (domain masked) and ssh key counts - the detection the
# gitid/auth/pub cells share, memoized into $_HI_ID_* the same way
# _hi_system_info_probe memoizes the sysinfo cells'.
function _hi_identity_probe() {
  [ -z "${_HI_ID_PROBED:-}" ] || return 0
  _HI_ID_PROBED=1
  local email="" domain user_part bullets authorized=0 public=0 n
  command -v git &>/dev/null && _hi_slow_out email email
  _hi_sanitize_var email "$email"
  if [ -n "$email" ]; then
    domain=${email#*@}
    _hi_repeat bullets "${#domain}" "$_HI_GLYPH_MASK"
    user_part="$YELLOW${email%%@*}@$bullets"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && _hi_count_lines authorized <"$_HI_SSH_AUTHORIZED_KEYS"
  if [ -d "$_HI_SSH_DIR" ]; then
    _hi_slow_out n pubs
    # a line per key: the newlines between them, plus the last
    [ -z "$n" ] || { n="${n//[!$'\n']/}" public=$((${#n} + 1)); }
  fi
  _HI_ID_GITID="$user_part"
  _HI_ID_AUTH="${RED}Auth: $authorized"
  _HI_ID_PUB="${PURPLE}Pub: $public"
}

# The containers/jobs/pods counts, memoized into $_HI_ID_CONTAINERS/_JOBS/_PODS.
# Apart from _hi_identity_probe so the other identity cells never wait on a
# daemon. Each stays empty when that backend's probe never ran - a getter
# checks for that itself. Reads what _hi_probe_launch started; calls it
# itself if nobody did.
function _hi_backend_probe() {
  [ -z "${_HI_BK_PROBED:-}" ] || return 0
  _HI_BK_PROBED=1
  local containers="" jobs="" pods="" n
  _hi_probe_launch
  _hi_probe_wait

  # One rule for all three backends: a cell appears only when its binary was
  # found and its probe actually ran - the file's existence is that signal,
  # never its content - and once it has, the count prints as-is, zero
  # included: a reachable-but-idle backend renders its zero, not like an
  # absent one.
  if [ -n "$_HI_PROBE_DIR" ]; then
    local -a lanes=("$_HI_PROBE_DIR"/containers.*)
    if [ -f "${lanes[0]}" ]; then
      if [ "${#lanes[@]}" -eq 1 ]; then
        _hi_count_lines n <"${lanes[0]}"
      else
        # IDs are the daemon's, so a shim's lane repeats another's and the
        # union is the count - one fork, only on a host with two CLIs
        _hi_count_lines n < <(sort -u "${lanes[@]}")
      fi
      containers="Containers: $n"
    fi
    if [ -f "$_HI_PROBE_DIR/nomad" ]; then
      _hi_count_lines n <"$_HI_PROBE_DIR/nomad"
      ((n > 0)) && n=$((n - 1)) # drop the header row
      jobs="Jobs: $n"
    fi
    if [ -f "$_HI_PROBE_DIR/kube" ]; then
      _hi_count_lines n <"$_HI_PROBE_DIR/kube"
      pods="Pods: $n"
    fi
    _hi_probe_done
  fi
  _HI_ID_CONTAINERS="${containers:+$BLUE$containers}"
  _HI_ID_JOBS="${jobs:+$BRGREEN$jobs}"
  _HI_ID_PODS="${pods:+$BRPURPLE$pods}"
}

function _hi_cell_gitid() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_GITID; }
function _hi_cell_containers() { _hi_probed_cell "$1" _hi_backend_probe _HI_ID_CONTAINERS; }
function _hi_cell_jobs() { _hi_probed_cell "$1" _hi_backend_probe _HI_ID_JOBS; }
function _hi_cell_pods() { _hi_probed_cell "$1" _hi_backend_probe _HI_ID_PODS; }
function _hi_cell_auth() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_AUTH; }
function _hi_cell_pub() { _hi_probed_cell "$1" _hi_identity_probe _HI_ID_PUB; }

# "=== <label> [host] ===" prefixed with say-hi's local change count, always
# _hi_draw_width columns wide; first wherever `banner` sits in the order
function banner() {
  _hi_order_has banner || return 0
  local label="$1" color="${2:-$BRGREEN}" changes="" prefix="${3:-}" changes_w=0
  # ~10ms of `git status`, computed once and kept for both banners.
  # --no-optional-locks as git_prompt.sh: a plain `git status` also rewrites
  # .git/index - cheap on ext4, a 9p round trip per file on a /mnt checkout.
  if [ -d "$_HI_ROOT/.git" ]; then
    if [ -z "${_HI_BANNER_CHANGES+x}" ]; then
      # one porcelain pass for both, parsed as git_prompt.sh parses it
      local line out nl=$'\n'
      _HI_BANNER_CHANGES=0 _HI_BANNER_BRANCH=""
      _hi_slow_out out status
      [ -z "$out" ] || out="$out$nl"
      while [ -n "$out" ]; do
        line="${out%%"$nl"*}" out="${out#*"$nl"}"
        case "$line" in
        "# branch.head "*) _HI_BANNER_BRANCH="${line#"# branch.head "}" ;;
        "#"*) ;;
        *) _HI_BANNER_CHANGES=$((_HI_BANNER_CHANGES + 1)) ;;
        esac
      done
      # detached and main are blanked: only an unusual branch earns a callout
      _hi_sanitize_var _HI_BANNER_BRANCH "$_HI_BANNER_BRANCH"
      case "$_HI_BANNER_BRANCH" in main | "(detached)") _HI_BANNER_BRANCH="" ;; esac
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
  local host fill start_len end_len start_fill end_fill width left core lead=" "
  [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]] && lead=""
  # memoized for the same reason; the hostname memo primed in this shell
  if [ -z "${_HI_BANNER_HOST+x}" ]; then
    _hi_hostname >/dev/null
    _hi_sanitize_var _HI_BANNER_HOST "$_HI_HOSTNAME_CACHE"
  fi
  host="$_HI_BANNER_HOST"
  _hi_draw_width width
  # split so "label [host]" lands at the center with at least 1 "=" on the left
  left=$((${#prefix} + ${#lead} + changes_w))
  core=$((${#label} + ${#host} + 4))
  fill=$((width - left - core - 1))
  ((fill < 4)) && fill=4
  start_len=$((width / 2 - left - core / 2))
  ((start_len < 1)) && start_len=1
  ((start_len > fill - 1)) && start_len=$((fill - 1))
  end_len=$((fill - start_len))
  _hi_repeat start_fill "$start_len" "="
  _hi_repeat end_fill "$end_len" "="
  # the fill at normal weight (SGR 22) in the label's color; $color again
  # restores the label's own weight
  local host_esc="" thin="${NC:+\e[22m}"
  _hi_host_escape host_esc
  printf '%b\n' "$lead$changes$color$thin$start_fill $color$label ${NC}[$host_esc$host$NC]$color$thin $end_fill$NC"
}

# The overlay's header/ cells, a file each defining _hi_cell_<word>, sourced
# in name order when the header first draws. One bash cannot parse is skipped
# with a warning; one that defines no function adds no word; a built-in's
# word replaces it. $_HI_HEADER_WORDS is the words that loaded, space-bounded.
# GLOSSARY: HI.58
function _hi_header_cells_load() {
  local _hi_hc_f _hi_hc_w
  local -a _hi_members=() _hi_strays=()
  _HI_HEADER_WORDS=" "
  _hi_dir_members "${_HI_HEADER_CELLS:-}"
  for _hi_hc_f in ${_hi_members[@]+"${_hi_members[@]}"}; do
    _hi_hc_w="${_hi_hc_f##*/}"
    _hi_parses "$_hi_hc_f" "header cell $_hi_hc_w" || continue
    _hi_hc_w="${_hi_hc_w%%.*}"
    # shellcheck source=/dev/null
    source "$_hi_hc_f" || true
    declare -F "_hi_cell_$_hi_hc_w" >/dev/null || continue
    case " $_HI_HEADER_ORDER_DEFAULT$_HI_HEADER_WORDS" in *" $_hi_hc_w "*) ;; *) _HI_HEADER_WORDS="$_HI_HEADER_WORDS$_hi_hc_w " ;; esac
  done
}

# _hi_header_vocab <outvar> - every word $_HI_HEADER_ORDER may name: the
# default's, then header/'s
function _hi_header_vocab() {
  [ -n "${_HI_HEADER_WORDS:-}" ] || _hi_header_cells_load
  printf -v "$1" '%s' "$_HI_HEADER_ORDER_DEFAULT${_HI_HEADER_WORDS% }"
}

# <var> gets $1's cell text if $1 names a getter, empty otherwise -
# _hi_collect_header_word's own dispatch, split out so a direct caller (a
# suite) can ask "what would this word render as" without going through the
# accumulate/flush machinery below.
function _hi_header_word_cell() {
  local _hi_hw_v
  printf -v "$2" '%s' ""
  # A word's getter is _hi_cell_<word>, reached only for a word on the roster,
  # since $_HI_HEADER_ORDER is user text. `check` has no getter (it is
  # full_check's row), hence the declare -F.
  _hi_header_vocab _hi_hw_v
  ! _hi_list_has "$_hi_hw_v" "$1" || ! declare -F "_hi_cell_$1" >/dev/null || "_hi_cell_$1" "$2"
  return 0
}

# <var> gets $1's alternate color, used when its primary would repeat the
# previous cell's hue. Every alternate's hue differs from its word's primary,
# so a swap can never collide; a new word's row must keep that
# (header_test.sh checks). Rows are "<word>:<palette variable name>".
# GLOSSARY: HI.48
_HI_HEADER_ALTS="utc:BRCYAN version:BRCYAN localtime:BRRED os:BRPURPLE\
 arch:BRCYAN cores:BRGREEN cpu:BRPURPLE ram:BRGREEN ip:BRCYAN gitid:BRRED\
 containers:BRYELLOW jobs:BRYELLOW pods:BRCYAN auth:BRYELLOW pub:BRRED\
 uptime:BRGREEN"

# _hi_header_word_alt <word> <outvar> [hue] - a word with no row (one of
# header/'s) takes the next hue round the ring from its own <hue>, bright, so
# the property above holds for it too
function _hi_header_word_alt() {
  local _hi_wa
  printf -v "$2" '%s' ""
  # shellcheck disable=SC2086 # the split is the table
  for _hi_wa in $_HI_HEADER_ALTS; do
    [ "${_hi_wa%%:*}" = "$1" ] || continue
    _hi_wa="${_hi_wa#*:}"
    # read at call time, not baked in: the suites flip $_HI_COLOR_SCHEME
    # and re-run _hi_assign_palette between renders
    printf -v "$2" '%s' "${!_hi_wa}"
    return 0
  done
  case "${3:-}" in
  1) _hi_wa=BRGREEN ;; 2) _hi_wa=BRYELLOW ;; 3) _hi_wa=BRBLUE ;;
  4) _hi_wa=BRPURPLE ;; 5) _hi_wa=BRCYAN ;; 6) _hi_wa=BRRED ;;
  *) return 0 ;;
  esac
  printf -v "$2" '%s' "${!_hi_wa}"
}

# One $_HI_HEADER_ORDER word. "check" flushes the pending cells as one
# header_row, then runs full_check; any other word appends its cell to the
# caller's $_HI_PENDING_CELLS, so consecutive cells pack onto one line. An
# unknown word is skipped. banner and greeting are lines, never cells.
function _hi_collect_header_word() {
  case "$1" in banner | greeting) return 0 ;; esac
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
    _hi_header_word_alt "$1" alt "$hue"
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
  [[ " ${_HI_HEADER_ORDER:-$_HI_HEADER_ORDER_DEFAULT} " == *" $1 "* ]]
}

function hi_header() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && return 0
  _HI_PROBE_HOLD=1
  _hi_header_prefetch
  # ahead of the rows, so their work runs inside the probes' wall clock. Only
  # the three that consume a backend probe gate this.
  # Skipped once the backends are memoized (configure.sh renders the header
  # repeatedly in subshells): a relaunch there would start backends nobody
  # waits on and leave their mktemp dir behind.
  if [ -z "${_HI_BK_PROBED:-}" ] && { _hi_order_has containers || _hi_order_has jobs || _hi_order_has pods; }; then
    _hi_probe_launch
  fi
  banner "$@"
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
  _HI_PROBE_HOLD=""
  _hi_probe_done
}

# The disconnect side: the banner, then timestamp()'s row when one of its
# three words survives in $_HI_HEADER_ORDER - the connect header's toggle
# and order, rather than a disconnect setting of its own.
function hi_footer() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && return 0
  banner "$@"
  if _hi_order_has utc || _hi_order_has version || _hi_order_has localtime; then
    timestamp
  fi
}

# The package check: config/packages' rows, marks, groups, and tiers are
# docs/COLORS.md's _The package check's rows_. The shipped ramp: four
# installed colors, then four missing, tier 0 first, both normal intensities
# before both bright so loudness never steps backwards.
# _hi_packages_palette splits it into _HI_YES_NAMES and _HI_NO_NAMES.
_HI_PACKAGES_RAMP="cyan green brcyan brgreen blue magenta bryellow brred"

# Names, not escapes, so a consumer never inverts one; check_line reads the
# escapes _hi_packages_palette derives. $_HI_PACKAGES_PALETTE is the colors
# file's [palette], eight _HI_COLOR_NAMES words; anything else is the shipped
# ramp.
function _hi_packages_palette() {
  local _hi_pp_n _hi_pp_i _hi_pp_e _hi_pp_r="$_HI_PACKAGES_RAMP"
  _hi_ramp_ok "${_HI_PACKAGES_PALETTE:-}" && _hi_pp_r="$_HI_PACKAGES_PALETTE"
  # shellcheck disable=SC2086 # eight names, checked by _hi_ramp_ok
  set -- $_hi_pp_r
  _HI_YES_NAMES=("$1" "$2" "$3" "$4")
  _HI_NO_NAMES=("$5" "$6" "$7" "$8")
  # Names to escapes, here rather than at source time: the suites flip
  # $_HI_COLOR_SCHEME and $_HI_PACKAGES_PALETTE between renders, and
  # full_check re-runs this before every check_line.
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
# bank that scheme carries for the check alone (HI.50).
function _hi_ramp_escape() {
  local _hi_re_i
  printf -v "$1" '%s' ''
  [ "${3:-0}" = 48 ] || {
    _hi_color_escape_var "$1" "$2"
    return 0
  }
  _hi_color_index _hi_re_i "$2" || return 0
  _hi_color_escape_at "$1" $((_hi_re_i + 24))
}

# _hi_group_tier <outvar> <group> - the ramp tier a group's rows paint in
function _hi_group_tier() {
  case "$2" in
  core | base | deprecated) printf -v "$1" 3 ;;
  useful) printf -v "$1" 2 ;;
  trivia | platform) printf -v "$1" 0 ;;
  *) printf -v "$1" 1 ;;
  esac
}

# check_line <out-array-name> <row> [tier] - one "[-|+]cmd[,cmd2...]" row,
# rendered per the marker rules above in <tier>'s colors (default 1), and
# appended to the named array as a "<rank>\x1f<width>\x1f<text>" record. Rank
# is the tier, or 4 for a warning or an alarm. A row with nothing to say
# appends nothing. The marks live in core.sh's _hi_choose_glyphs.
function check_line() {
  local cmd best="" idx=0 color symbol rendered rank="${3:-1}" mode=want line=$2
  case "$line" in
  -*) mode=unwanted line="${line#-}" ;;
  +*) mode=required line="${line#+}" ;;
  esac
  # word-split on the local IFS, not `read -ra <<<`: that here-string is a
  # temp file before bash 5.1, per package line
  local IFS=','
  # shellcheck disable=SC2206 # deliberate split on IFS; the file has no globs
  local -a names=($line)
  unset IFS

  for cmd in "${names[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      best="$cmd"
      break
    fi
    ((++idx))
  done

  if [ -n "$best" ]; then
    case "$mode" in
    required) return 0 ;;
    unwanted)
      rank=4
      color="${_HI_NO[3]:-$NC}"
      symbol="$YELLOW$_HI_MARK_WARN$NC"
      ;;
    *)
      color="${_HI_YES[rank]:-$NC}"
      if ((idx == 0)); then
        symbol="$GREEN$_HI_MARK_OK"
      else
        symbol="$YELLOW$_HI_MARK_ALT$NC"
      fi
      ;;
    esac
  else
    [[ "$mode" == unwanted ]] && return 0
    best="${names[0]}"
    if [[ "$mode" == required ]]; then
      rank=4 color="${_HI_NO[3]:-$NC}"
    else
      color="${_HI_NO[rank]:-$NC}"
    fi
    symbol="$RED$_HI_MARK_NO"
  fi
  rendered="$color $best $symbol"
  # 5 = the "| " lead, the spaces around the item, and the mark - one visible
  # column in either glyph set (core.sh's _hi_choose_glyphs)
  # shellcheck disable=SC2034 # read by the eval below
  local record="$rank"$'\x1f'"$((${#best} + 5))"$'\x1f'"$rendered"
  # appended by name, as core.sh's _hi_read_lines does
  eval "$1+=(\"\$record\")"
}

# _hi_group_on <group> - whether $_HI_PACKAGES_GROUPS runs <group>
function _hi_group_on() {
  # `none` is the setting's word for no groups, never a group of its own
  [ "$1" != none ] && _hi_list_has "${_HI_PACKAGES_GROUPS:-$_HI_PACKAGES_GROUPS_DEFAULT}" "$1"
}

# full_check's right edge: pads $2's row out to $1 and closes it with a
# pipe. One home for the arithmetic, called from both places a row ends -
# mid-loop on wrap, and once at the final flush.
function _hi_check_close() {
  local _hi_ccl_pad=""
  _hi_repeat _hi_ccl_pad $(($1 - $2)) ' '
  printf '%b' "$NC$_hi_ccl_pad|"
}

# print sorted package results limited by _hi_draw_width, from the groups
# $_HI_PACKAGES_GROUPS runs. The group filter lives here, not in check_line:
# scripts/preview.sh calls check_line directly and needs the rows of groups
# that are off.
function full_check() {
  local width_item max cell vislen piece i pkg_start close=1 line rank rec us=$'\x1f'
  local on=1 tier=1 group name alts
  _hi_draw_width max
  # $_HI_DISABLE_RIGHT_EDGE reaches this loop too, now - one column reserved,
  # not _hi_row_line's two, since every piece below already carries its own
  # trailing space ("| $cell ").
  [[ "${_HI_DISABLE_RIGHT_EDGE:-0}" == 1 ]] && close=0
  ((close)) && ((max -= 1))
  local width=$max
  local -a row_widths=() row_pieces=() visible=()

  # An earlier row's carry opens this row's first line, in header_row's
  # "| <cell> " shape; full_check, the variable-length block, absorbs it.
  for cell in ${_HI_ROW_CARRY[@]+"${_HI_ROW_CARRY[@]}"}; do
    _hi_visible_width vislen "$cell"
    row_widths+=("$((vislen + 3))")
    row_pieces+=("| $cell ")
  done
  # Where the check's own cells start, past any carried-in ones: the render
  # loop doubles this one piece's leading "|" so the check reads as its own
  # section rather than one more item on a row a carried git/env cell opened.
  pkg_start=${#row_pieces[@]}
  _HI_ROW_CARRY=()

  # the ramp resolved per render: a suite changes $_HI_PACKAGES_PALETTE
  # after header.sh loaded
  _hi_packages_palette
  [ -f "${_HI_PACKAGES:-}" ] && while IFS=$' ' read -r line; do
    # a blank line or a comment is no row, and only a [ line a table: a
    # function call each spared on the file's commonest lines
    case "$line" in
    '' | '#'*) continue ;;
    '['*)
      if _hi_package_table "$line" group; then
        on=0
        [ -n "$group" ] && ! _hi_group_on "$group" || on=1
        _hi_group_tier tier "$group"
        continue
      fi
      ;;
    esac
    # a group that is off is skipped before its rows are read: each is a
    # PATH walk per alternative
    ((on)) && _hi_toml_row "$line" name alts && check_line visible "$name${alts:+,$alts}" "$tier"
  done <"$_HI_PACKAGES"
  # highest rank first, file order within one: a pass per rank, not a fork
  for ((rank = 4; rank >= 0; rank--)); do
    for rec in ${visible[@]+"${visible[@]}"}; do
      [ "${rec%%"$us"*}" = "$rank" ] || continue
      rec="${rec#*"$us"}"
      row_widths+=("${rec%%"$us"*}")
      row_pieces+=("|${rec#*"$us"} ")
    done
  done
  ((${#row_widths[@]})) || return 0

  for ((i = 0; i < ${#row_widths[@]}; i++)); do
    width_item="${row_widths[$i]}"
    piece="${row_pieces[$i]}"
    ((i == pkg_start)) && {
      # bold bright white, outside the palette; $NC is empty under NO_COLOR
      piece="${NC:+\e[1;97m}||$NC${piece#|}"
      width_item=$((width_item + 1))
    }
    if ((width + width_item > max)); then # start of a row
      if ((i)); then
        ((close)) && _hi_check_close "$max" "$width"
        printf '\n'
      fi
      if [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]]; then
        width=0
      else
        printf ' '
        width=1
      fi
    fi
    printf '%b' "$NC$piece$NC"
    width=$((width + width_item))
  done
  ((close)) && _hi_check_close "$max" "$width"
  printf '\n'
}
