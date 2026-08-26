#!/usr/bin/env bash
# The connect/disconnect banner, one implementation for every shell (fish
# shells out here); the packages check (full_check) lives at the bottom too.
set -euo pipefail

# core.sh through this file's own path; it derives the tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# shellcheck source=./core.sh
source "$_hi_d/core.sh"
unset _hi_d

function header_row() {
  local cell out=""
  for cell in "$@"; do out+="$NC | $cell"; done
  printf '%b\n' "$out$NC"
}

# hi's version for the header, resolved once per shell (the row prints twice a
# session). core.sh's ladder answers; only a stampless, gitless install falls
# through to the bare "unknown" that `hi --version` spells out in full.
function _hi_header_version() {
  if [ -z "${_HI_HEADER_VERSION+x}" ]; then
    _hi_sanitize_var _HI_HEADER_VERSION "$(_hi_release_or_describe)"
    [ -n "$_HI_HEADER_VERSION" ] || _HI_HEADER_VERSION="unknown"
  fi
  printf '%s\n' "$_HI_HEADER_VERSION"
}

# UTC | version | local: no "say-hi" label - the banner above already says whose
function timestamp() {
  _hi_header_version >/dev/null # primes the memo; read the variable, not a $( )
  header_row "$BRBLUE$(date -u "$_HI_HUMAN_CENTRIC_DATE") " \
    "$GREEN$_HI_HEADER_VERSION" \
    " $BRYELLOW$(date "$_HI_HUMAN_CENTRIC_DATE")"
}

function system_info() {
  local kernel arch os cpus ram base_mhz boost_mhz
  # process substitution, not <<<: a here-string is a temp file before bash 5.1
  read -r kernel arch < <(uname -sm)
  _hi_sanitize_var kernel "$kernel"
  _hi_sanitize_var arch "$arch"
  local base_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/base_frequency"
  local max_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
  local scaling_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
  local amd_floor_path="/sys/devices/system/cpu/cpu0/cpufreq/amd_pstate_lowest_nonlinear_freq"
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    # also covers WSL - it's a real Linux kernel with its own /etc/os-release
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE")
    # every probe ends in `|| true`: a stripped-down target falls through to
    # "?" instead of aborting under set -e
    cpus=$(nproc 2>/dev/null || true)
    # straight at the file free(1) itself reads, rather than free | awk
    ram=$(awk '/^MemTotal:/ { printf "%.0fG", $2 / 1048576 }' /proc/meminfo 2>/dev/null || true)
    # base clock from the model name (eg "... @ 2.80GHz"); AMD chips print none,
    # so fall back to cpufreq's base_frequency (Intel P-State / amd-pstate only)
    base_mhz=$(awk -F'@ *' '/model name/ && NF>1 { gsub(/GHz.*/, "", $2); printf "%.0f", $2 * 1000; exit }' /proc/cpuinfo 2>/dev/null || true)
    # `read < file`, not $(cat file): a miss fails silently and costs no fork.
    # The second path is amd-pstate-epp, which publishes neither of the others;
    # lowest_nonlinear_freq is the driver's floor rather than the rated base
    # clock, but it beats "?".
    local khz=0 freq_path
    for freq_path in "$base_freq_path" "$amd_floor_path"; do
      [ -n "$base_mhz" ] && break
      [ -f "$freq_path" ] || continue
      read -r khz <"$freq_path" 2>/dev/null || khz=0
      base_mhz=$((khz / 1000))
      ((base_mhz)) || base_mhz=""
    done
    # boost/max clock: cpufreq first, else lscpu. khz is reset because the base
    # probes above leave their reading in it - a host with base_frequency but no
    # cpuinfo_max_freq would report its base clock as its own boost.
    khz=0
    if [ -f "$max_freq_path" ] && [ -f "$scaling_freq_path" ]; then
      read -r khz <"$scaling_freq_path" 2>/dev/null || khz=0
    fi
    boost_mhz=$((khz / 1000))
    ((boost_mhz)) || boost_mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/ { gsub(/ /, "", $2); printf "%.0f", $2 }' || true)
  elif [[ "$kernel" == MINGW* || "$kernel" == MSYS* || "$kernel" == CYGWIN* ]]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }' || true)
    # wmic only exposes the rated (base) clock; turbo/boost isn't queryable this way
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }' || true)
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null || true)
    ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0fG", $1 / 1073741824 }' || true)
    # Apple Silicon doesn't expose either clock via sysctl; only Intel Macs get a value here
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }' || true)
  fi
  _hi_sanitize_var os "$os"
  # _HI_HEADER_GHZ=1 (settings.sh) swaps the CPU cell to x.xxx GHz; unset/0
  # keeps the MHz integers every test and script still pins
  local freq_unit="MHz"
  if [ "${_HI_HEADER_GHZ:-0}" = 1 ]; then
    freq_unit="GHz"
    # MHz -> x.x GHz with printf, not an awk fork apiece; rounded to tenths
    # *before* splitting so a carry lands properly (2950 -> 3.0, not "2.10")
    local ghz_tenths ghz_var ghz_val
    for ghz_var in base_mhz boost_mhz; do
      eval "ghz_val=\$$ghz_var"
      [ -n "$ghz_val" ] && {
        ghz_tenths=$(((ghz_val + 50) / 100))
        printf -v "$ghz_var" '%d.%d' "$((ghz_tenths / 10))" "$((ghz_tenths % 10))"
      }
    done
  fi
  header_row "$PURPLE$arch" "$GREEN$os" "${YELLOW}Cores: ${cpus:-?}" \
    "${CYAN}RAM: ${ram:-?}" "${BRBLUE}CPU: ${base_mhz:-?}/${boost_mhz:-?} $freq_unit"
}

# identity()'s backend probes are independent and each capped at
# $_HI_PROBE_TIMEOUT: run in turn, three wedged daemons cost the *sum* of the
# ceilings; started together, the longest. Files rather than process
# substitutions, which would be back to waiting on each in turn.
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

# Start whichever of the three backends this host can answer, all at once.
# Split out of identity() so hi_header can start them first: they are the only
# part of the header bounded by $_HI_PROBE_TIMEOUT, and the other rows then
# run in their shadow rather than ahead of them.
function _hi_probe_launch() {
  local container_bin nomad=0 kube=0
  # idempotent: hi_header starts these early, and identity() calls it too so a
  # direct `identity` (the suites, hi --doctor) still probes
  [ -z "$_HI_PROBE_DIR" ] || return 0
  container_bin="$(command -v docker || command -v podman || true)"
  command -v nomad &>/dev/null && nomad=1
  command -v kubectl &>/dev/null && kube=1
  [ -n "$container_bin" ] || ((nomad || kube)) || return 0
  _HI_PROBE_DIR="$(mktemp -d -t hi.probes.XXXXXX)"
  [ -n "$container_bin" ] && _hi_probe_start "$_HI_PROBE_DIR/containers" _hi_probe "$container_bin" container ls -q
  ((nomad)) && _hi_probe_start "$_HI_PROBE_DIR/nomad" _hi_probe nomad job status
  # kube counts through targets.sh, whose list_kube owns the "which pods count
  # as reachable" rule (and brings its own probe timeout). docker/nomad stay
  # direct: their counts answer a different question than the listers do.
  ((kube)) && _hi_probe_start "$_HI_PROBE_DIR/kube" sh "$_HI_TARGETS" kube
  return 0
}

# git identity (domain masked), containers/jobs/pods, ssh key counts. Reads
# what _hi_probe_launch started; calls it itself if nobody did.
function identity() {
  local email="" domain user_part bullets containers="No docker/podman :(" jobs="" pods="" authorized=0 public=0
  local -a lines cells
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

  # No temp dir means nothing to read or remove. Below it the probe file's
  # existence *is* the answer - _hi_probe_start creates it before backgrounding
  # and the wait is done - so no flags are tracked beside the files.
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
    rm -rf "$_HI_PROBE_DIR"
    _HI_PROBE_DIR=""
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && _hi_read_lines lines <"$_HI_SSH_AUTHORIZED_KEYS" && authorized=${#lines[@]}
  [ -d "$_HI_SSH_DIR" ] && _hi_read_lines lines < <(find "$_HI_SSH_DIR" -type f -name "*.pub") && public=${#lines[@]}
  cells=("$user_part" "$BLUE$containers")
  [ -n "$jobs" ] && cells+=("$CYAN$jobs")
  [ -n "$pods" ] && cells+=("$CYAN$pods")
  cells+=("${RED}Auth: $authorized" "${PURPLE}Pub: $public")
  header_row "${cells[@]}"
}

# "~~~ <label> [host] ~~~" prefixed with say-hi's local change count, always
# _HI_MAX_WIDTH columns wide
function banner() {
  [[ "${_HI_HEADER_BANNER:-1}" == 0 ]] && return 0
  local label="$1" color="${2:-$BRGREEN}" changes="" prefix="${3:-}" changes_w=0
  # twice a session for a count that cannot change between: ~10ms of
  # `git status`, computed once and kept
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
    # the Online (local) banner only: a remote session's Connected banner
    # describes the target, and the disconnect banner stays as-is
    if [ "$label" = Online ] && [ -n "${_HI_BANNER_BRANCH:-}" ]; then
      changes+="($_HI_BANNER_BRANCH) "
      changes_w=$((changes_w + ${#_HI_BANNER_BRANCH} + 3))
    fi
  fi
  local host tildes start_len end_len start_tildes end_tildes width left core
  # memoized for the same reason: two forks a banner for a fixed name
  [ -n "${_HI_BANNER_HOST+x}" ] || _hi_sanitize_var _HI_BANNER_HOST "$(_hi_hostname)"
  host="$_HI_BANNER_HOST"
  width=${_HI_MAX_WIDTH:-80}
  tildes=$((width - 6 - changes_w - ${#label} - ${#host} - ${#prefix}))
  ((tildes < 4)) && tildes=4
  # split so "label [host]" lands at the center with at least 1 tilde on the left
  left=$((${#prefix} + 1 + changes_w))
  core=$((${#label} + ${#host} + 4))
  start_len=$((width / 2 - left - core / 2))
  ((start_len < 1)) && start_len=1
  ((start_len > tildes - 1)) && start_len=$((tildes - 1))
  end_len=$((tildes - start_len))
  _hi_repeat start_tildes "$start_len" '~'
  _hi_repeat end_tildes "$end_len" '~'
  local host_esc=""
  _hi_host_escape_var host_esc
  printf '%b\n' " $changes$color$start_tildes $label ${NC}[$host_esc$host$NC]$color $end_tildes$NC"
}

function hi_header() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && return 0
  banner "$@"
  # ahead of the fork-only rows, so their ~30ms runs inside the probes' wall
  # clock; same toggle, so a hidden identity row still starts nothing
  [[ "${_HI_HEADER_IDENTITY:-1}" == 0 ]] || _hi_probe_launch
  [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  [[ "${_HI_HEADER_SYSINFO:-1}" == 0 ]] || system_info
  [[ "${_HI_HEADER_IDENTITY:-1}" == 0 ]] || identity
  [[ "${_HI_HEADER_CHECK:-1}" == 0 ]] || full_check
}

# package priorities, lowest to highest (more can be added).
#
# A priority says how much you want to hear about a tool, and
# `$_HI_PACKAGES_MIN_PRIORITY` is the dial: it gates display, so raising it
# trims the decorative tiers before the ones that can tell you something is
# wrong. Every tier speaks when the tool is missing, which is the point - a
# target you visit often is exactly where a nudge to install your own
# preferred tools belongs, and one that stays quiet about them never nudges.
#
# The dial ships at 1, not 0: tier 0 is trivia by its own description, and a
# stock connect is a better length without it. Nothing is lost - a floor of 0
# is a setting like any other, and asks for the tier back.
#
# Tier 4 is the single exception, and the only `hide` left in the table: it is
# the core-tool tier, where being present is not news and being absent means
# this box is bare. Printing 57 `ok` rows on every healthy target to catch that
# is the wrong trade, so it stays silent until it has something to say.
#
# The numbered lines below are scraped verbatim by scripts/packages_preview.sh
# (the run immediately above _HI_YES, parentheticals dropped), so keep the
# "# <n> <meaning> (<examples>)" shape and add nothing between them and the
# table.
# 0 platform and trivia (sw_vers, netstat)
# 1 optional extras (zoxide, navi)
# 2 system and package tools (flatpak, yay)
# 3 favorites (eza, bat)
# 4 expected on any box (awk, curl, tar)
# 5 workflow-defining (asdf, direnv)
_HI_YES=("$BLUE" "$BRCYAN" "$GREEN" "$BRGREEN" hide "$BRGREEN")
_HI_NO=("$BRBLUE" "$BRPURPLE" "$YELLOW" "$BRYELLOW" "$YELLOW" "$BRRED")

# For each "cmd:priority[,...]": the highest-priority installed package (or the
# first, if none), colored and marked per above. The marks themselves live in
# core.sh's _hi_choose_glyphs, beside the rest of the glyph set.
function check_line() {
  local pair cmd priority color best best_priority best_idx=0 idx=0 found=0 symbol rendered
  # word-split on the local IFS, not `read -ra <<<`: that here-string is a pipe
  # (temp file before bash 5.1) per package line, ~30 a header
  local IFS=','
  # shellcheck disable=SC2206 # deliberate split on IFS; the file has no globs
  local -a pairs=($1)
  unset IFS
  best="${pairs[0]%:*}"
  best_priority="${pairs[0]#*:}"

  for pair in "${pairs[@]}"; do
    cmd="${pair%:*}"
    priority="${pair#*:}"
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
    color="${_HI_YES[best_priority]:-$NC}"
    if ((best_idx == 0)); then
      symbol="$GREEN$_HI_MARK_OK" mark_w="$_HI_MARK_OK_W"
    else
      symbol="$YELLOW$_HI_MARK_ALT$NC" mark_w="$_HI_MARK_ALT_W"
    fi
  else
    color="${_HI_NO[best_priority]:-$NC}"
    symbol="$RED$_HI_MARK_NO" mark_w="$_HI_MARK_NO_W"
  fi
  rendered="$color $best $symbol"
  # 4 = the "| " lead plus the spaces around the item; the mark's width comes
  # from the chosen set (ASCII "ok" is two columns, ✓ is one)
  [[ "$color" == hide ]] || visible+=("$best_priority"$'\x1f'"$((${#best} + 4 + mark_w))"$'\x1f'"$rendered")
}

# print sorted package results limited by _HI_MAX_WIDTH, from
# $_HI_PACKAGES_MIN_PRIORITY up
#
# The floor lives here rather than in check_line on purpose: check_line renders,
# full_check decides what to print. scripts/packages_preview.sh calls check_line
# directly and needs the rows the floor hides, so it can say which ranks went
# quiet instead of dropping them without a word.
function full_check() {
  local line priority width_item rendered count=0 width=0
  local min="${_HI_PACKAGES_MIN_PRIORITY:-1}"
  local -a visible=() # appended to by check_line
  while IFS=$' ' read -r line; do
    [[ "$line" == *#* || -z "$line" ]] || check_line "$line"
  done <"$_HI_PACKAGES"
  ((${#visible[@]})) || return 0

  # GLOSSARY: HI.11 - numeric key over opaque bytes; unpinned, BSD
  # sort under UTF-8 printed nothing and the check rendered empty.
  while IFS=$'\x1f' read -r priority width_item rendered; do
    ((priority >= min)) || continue
    if ((count == 0)) || ((width + width_item > ${_HI_MAX_WIDTH:-80})); then # start of a row
      ((count == 0)) || printf '\n'
      printf ' '
      width=1
    fi
    printf '%b' "$NC|${rendered} $NC"
    width=$((width + width_item))
    ((++count))
  done < <(printf '%s\n' "${visible[@]}" | LC_ALL=C sort -t $'\x1f' -k1,1nr -s)
  # guarded: a floor high enough to hide everything printed a bare newline
  # otherwise, which is a blank line in the header rather than no check at all
  if ((count)); then printf '\n'; fi
}
