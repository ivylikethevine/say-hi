#!/usr/bin/env bash
# kcov_ps4_probe.sh - which kcov bash tracing survives this machine's bash:
# runs tests/coverage.sh's three-line repro (an assignment whose value holds
# a quote and a newline, a sourced function, then a child bash) under kcov's
# own PS4, under tests/lib/kcov_env.sh's PS4, and under kcov's DEBUG method,
# and prints the lines each recorded. coverage.sh needs hi's PS4 to read
# lib.sh and child.sh in full. Rerun it after a kcov or bash upgrade, or when
# kcov's badge sags far under bashcov's.
#
#   scratch/kcov_ps4_probe.sh
#   KCOV=/path/to/kcov scratch/kcov_ps4_probe.sh
set -euo pipefail

kcov="${KCOV:-kcov}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d "${TMPDIR:-/tmp}/kcov_ps4_probe.XXXXXX")"
cleanup() { case "$root" in */kcov_ps4_probe.??????) rm -rf "$root" ;; esac }
trap cleanup EXIT

cat >"$root/lib.sh" <<'EOF'
f() {
  local a=1
  a=$((a + 1))
  printf 'f ran %s\n' "$a"
}
g() {
  printf 'g ran\n'
}
EOF
cat >"$root/child.sh" <<'EOF'
source "$(dirname "$0")/lib.sh"
g
EOF
cat >"$root/repro.sh" <<'EOF'
X="$(printf "a'b\nc'd\n")"
source "$(dirname "$0")/lib.sh"
f
bash "$(dirname "$0")/child.sh"
EOF
# the same, after the swap tests/test_lib.sh makes under kcov's PS4 method
{
  # shellcheck disable=SC2016 # the fixture's text: it expands when kcov runs it
  printf '%s\n' '_HI_TEST_ROOT="$(dirname "$0")"' 'source "$HI_KCOV_ENV"'
  cat "$root/repro.sh"
} >"$root/hi_repro.sh"

# probe <name> <method> <script>
probe() {
  mkdir -p "$root/out/$1"
  HI_KCOV_ENV="$here/tests/lib/kcov_env.sh" "$kcov" --bash-method="$2" \
    --include-pattern="$root/" "$root/out/$1" "$root/$3" >"$root/$1.log" 2>&1 ||
    printf '%s: kcov exited %s, log: %s\n' "$1" "$?" "$root/$1.log" >&2
}
probe kcov-ps4 PS4 repro.sh
probe hi-ps4 PS4 hi_repro.sh
probe debug DEBUG repro.sh

printf '%s\n' "bash $BASH_VERSION, $("$kcov" --version)"
printf '%-9s | %-8s | %s\n' tracing file "lines recorded"
printf '%s\n' '----------+----------+---------------'
for m in kcov-ps4 hi-ps4 debug; do
  json="$(find "$root/out/$m" -path '*.sh.*/coverage.json' | head -n 1)"
  for f in lib.sh child.sh; do
    row="$(grep -o "\"file\": \"[^\"]*/$f\"[^}]*" "$json" 2>/dev/null || true)"
    got=absent
    if [ -n "$row" ]; then
      cov="$(printf '%s\n' "$row" | sed -n 's/.*"covered_lines": "\([0-9]*\)".*/\1/p')"
      tot="$(printf '%s\n' "$row" | sed -n 's/.*"total_lines": "\([0-9]*\)".*/\1/p')"
      got="$cov of $tot"
    fi
    printf '%-9s | %-8s | %s\n' "$m" "$f" "$got"
  done
done
