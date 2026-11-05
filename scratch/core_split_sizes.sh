#!/usr/bin/env bash
# The payload's gzipped size, file by file, and the script a candidate core
# would make: what a connect's stdin stream holds (the script's text, the
# tree's archive), what each shipped file costs in it (stripped bytes, its
# archive alone, and at the margin of the whole), and each candidate set of
# members against the TCP windows a cold connect pays a round trip per
# (initcwnd 10 segments of 1448: 14.5 KB, 43.4 KB, 101 KB cumulative).
# Stages the tree as pack.sh does (copy, cut, comment strip, tar | gzip -9 -n),
# so the whole agrees with _hi_wire_bytes and the README badge.
#
#   _HI_HOME=<dir holding say-hi> scratch/core_split_sizes.sh
#
# Prints one report, writes nothing, and unsets every other inherited _HI_*.
set -euo pipefail

for v in $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p'); do
  [ "$v" = _HI_HOME ] || unset "$v"
done
: "${_HI_HOME:?set _HI_HOME to the directory holding say-hi}"
export _HI_PAYLOAD_CACHE=0
set --
# shellcheck source=../hi.sh
source "$_HI_HOME/say-hi/hi.sh"
set -euo pipefail

stage="$(mktemp -d -t hi.sizes.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/say-hi"
for f in "${_HI_PAYLOAD[@]}"; do
  cp -R -L "$_HI_ROOT/$f" "$stage/say-hi/$f"
done
chmod -R u+w "$stage"
rm -rf "${_HI_PAYLOAD_CUT[@]/#/$stage/}"
_hi_strip_awk >"$stage/strip.awk"
find "$stage/say-hi" -type f \( "${_HI_STRIP_NAMES[@]}" \) -exec awk -f "$stage/strip.awk" {} +
# keep.sh's target half, the part load() calls before the shell starts, as a
# member of its own for the candidate that carries it in the core
awk '/^# The target.s half, which load.sh calls/ { on = 1 } on' "$_HI_ROOT/common/keep.sh" >"$stage/keep_target.raw"
awk -f "$stage/strip.awk" "$stage/keep_target.raw"

gz() { _hi_tar_gz -C "$stage" "$@" | wc -c | tr -d ' '; }
kb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1024 }'; }
# extra round trips a cold connect pays for <bytes> on one TCP connection
rtts() {
  if [ "$1" -le 14480 ]; then echo 0; elif [ "$1" -le 43440 ]; then echo 1; elif [ "$1" -le 101360 ]; then echo 2; else echo 3; fi
}

_hi_read_lines files < <(cd "$stage" && find say-hi -type f | sort)
whole="$(gz "${files[@]}")"
built="$(_hi_payload_tar | wc -c | tr -d ' ')"
wire="$(_hi_wire_bytes)"
head_n=$((${#wire} + ${#built} + 4))
text=$((wire - built - head_n))
probe="$(_hi_boot_probe '${TMPDIR:-/tmp}/hi.boot.0123456789abcdef' | wc -c | tr -d ' ')"
ct=0
stub="$(_hi_overlap_stub '${TMPDIR:-/tmp}/hi.boot.0123456789abcdef' | wc -c | tr -d ' ')"
fixed=$((text + head_n + probe + stub))

printf 'whole tree: %s B gzipped (sorted members), %s B as pack.sh builds it; wire (badge): %s B = %s KB\n' \
  "$whole" "$built" "$wire" "$(kb "$wire")"
printf 'script text around the archive: %s B; boot probe command: %s B; session stub command: %s B\n' "$text" "$probe" "$stub"
printf 'fixed bytes a connect sends before the tree: %s B; windows: 14480 / 43440 / 101360 B cumulative\n\n' "$fixed"

# the script's parts, assembled as _hi_wire_bytes assembles them
# shellcheck disable=SC2034 # the locals are hi.sh's builders' to read
{
  local_size="$_HI_SIZE_TOKEN"
  size="$local_size" DOMAIN=target overlay_line="" terminfo_line="" ct=0
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  printf 'script parts (bytes): preamble %s, middle %s, suffix %s; of the suffix, fallback rc armored %s, fallback prompt armored %s; env lines %s\n\n' \
    "$(_hi_remote_preamble | wc -c | tr -d ' ')" "$(_hi_remote_middle | wc -c | tr -d ' ')" "$(_hi_remote_suffix | wc -c | tr -d ' ')" \
    "$(_hi_fallback_rc | _hi_armored_line '>' x | wc -c | tr -d ' ')" "$(_hi_fallback_prompt | _hi_armored_line '>>' x | wc -c | tr -d ' ')" \
    "$(_hi_env_each | wc -c | tr -d ' ')"
} 2>/dev/null || printf 'script parts: not measured (a builder failed)\n\n'

printf '%-28s %9s %9s %9s\n' member 'stripped' 'alone gz' 'margin gz'
for f in "${files[@]}"; do
  rest=()
  for g in "${files[@]}"; do [ "$g" = "$f" ] || rest+=("$g"); done
  printf '%-28s %9s %9s %9s\n' "${f#say-hi/}" "$(wc -c <"$stage/$f" | tr -d ' ')" "$(gz "$f")" "$((whole - $(gz "${rest[@]}")))"
done
printf '%-28s %9s %9s %9s\n' 'keep.sh target half' "$(wc -c <"$stage/keep_target.raw" | tr -d ' ')" "$(gz keep_target.raw)" -

# candidate cores: the set the roadmap measured, then each further cut
without() {
  local f g
  set_out=()
  for f in "${set_in[@]}"; do
    for g; do [ "$f" != "say-hi/$g" ] || continue 2; done
    case "$f" in say-hi/common/fw_*) [ "${1:-}" != 'fw_*' ] || continue ;; esac
    set_out+=("$f")
  done
}
printf '\n%-52s %9s %9s %9s %5s\n' 'candidate core' 'tree gz' 'script' 'on wire' 'RTTs'
report() {
  local g s
  g="$(gz "${set_out[@]}")"
  s=$((g + text + head_n))
  printf '%-52s %9s %9s %9s %5s\n' "$1" "$g" "$s" "$((s + probe + stub))" "$(rtts $((s + probe + stub)))"
}
set_in=("${files[@]}")
without
report 'whole'
without hi.sh common/_hi common/zsh.zsh common/config.fish
report 'A: no hi.sh, _hi, zsh.zsh, config.fish'
set_in=("${set_out[@]}")
without common/keep.sh
report 'B: A less keep.sh'
set_in=("${set_out[@]}")
without common/targets.sh common/flags common/mux.sh
report 'C: B less targets.sh, flags, mux.sh'
set_in=("${set_out[@]}")
without 'fw_*'
report 'D: C less fw_*'
set_in=("${set_out[@]}" keep_target.raw)
without
report 'D plus keep.sh target half'
set_in=("${set_out[@]}")
without common/header.sh config/packages
report 'E: that, header off (no header.sh, packages)'
