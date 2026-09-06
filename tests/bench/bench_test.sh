#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Benchmarks for the product's hot paths - the code every shell start, prompt,
# TAB completion and connect runs - plus the ssh payload's size budget. The
# test suite itself is deliberately NOT benchmarked. Ceilings are generous on
# purpose: the job is to catch a path getting an order of magnitude slower (a
# fork slipping into a loop, a probe losing its timeout), not to flake on a
# busy CI runner. Its own `bench` group, so `--group fast` stays fast.
#
# GLOSSARY: HI.30 + HI.34. The single-quoted child scripts are expanded by the
# child shell (SC2016). SC2317 rides along because the two payload benches
# source hi.sh inside a function: with test_lib.sh reached first, hi.sh's
# trailing `_hi "$@"` is two sources deep and shellcheck reads everything
# after the source as unreachable.
# shellcheck disable=SC2329,SC2016,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# The cap one backend probe gets, in seconds. A variable rather than a literal
# because bench_targets_cold's ceiling is derived from it: the two numbers are
# one statement about the same run, and setting them apart is how the ceiling
# ended up under the benchmark's own floor.
_HI_BENCH_PROBE=1

# run <cmd...> in the controlled environment rc_test.sh also uses, so local
# settings and a live backend zoo can't skew a number; probes get
# $_HI_BENCH_PROBE seconds
function _hi_bench_env() {
  env -i HOME="$_HI_WORKDIR" TERM=xterm-256color PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" \
    _HI_PROBE_TIMEOUT="$_HI_BENCH_PROBE" _HI_TARGETS_TTL=5 "$@" </dev/null
}

# _hi_bench <label> <ceiling-ms> <n> <cmd...> - average of n runs against a
# generous ceiling, reported either way so the numbers are in every CI log.
# hyperfine is the preferred backend when installed (warmup run, outlier
# detection); the plain timing loop is the fallback - and what CI measures,
# since the runners don't install hyperfine. The output says which one ran.
function _hi_bench() {
  local label="$1" ceiling="$2" n="$3" i t0 t1 avg="" cmd runs backend=""
  shift 3
  if command -v hyperfine >/dev/null 2>&1; then
    # hyperfine takes a command string, not an argv: %q-quote it and run it
    # under bash, where the exported _hi_bench_env is a function again
    printf -v cmd '%q ' "$@"
    runs=$((n < 2 ? 2 : n))
    if hyperfine --shell=bash --ignore-failure --warmup 1 --runs "$runs" \
      --style none --export-json "$_HI_WORKDIR/bench.json" -- "$cmd" \
      >/dev/null 2>&1; then
      # "mean" is seconds in the JSON export; awk's numeric coercion drops
      # the trailing comma, so no jq needed
      avg="$(awk -F: '/"mean"/ { printf "%.1f", $2 * 1000; exit }' "$_HI_WORKDIR/bench.json")"
    fi
    if [ -n "$avg" ]; then
      backend="hyperfine, " n="$runs"
    fi
  fi
  if [ -z "$avg" ]; then
    # one untimed run first, the way the hyperfine arm above passes --warmup 1.
    # CI always lands here (the runners install zsh and fish, never hyperfine),
    # so without it run #1's cold binary paging and first-daemon-contact are
    # divided into the average and every ceiling has to carry them.
    "$@" >/dev/null 2>&1 || true
    t0="$(_hi_now)"
    for ((i = 0; i < n; i++)); do "$@" >/dev/null 2>&1 || true; done
    t1="$(_hi_now)"
    avg="$(awk -v a="$t0" -v b="$t1" -v n="$n" 'BEGIN { printf "%.1f", (b - a) * 1000 / n }')"
  fi
  if awk -v x="$avg" -v c="$ceiling" 'BEGIN { exit !(x <= c) }'; then
    _hi_align " | $label: ${avg}ms avg (${backend}ceiling ${ceiling}ms, n=$n)" "OK" "$GREEN"
  else
    _hi_cecho " | $label: ${avg}ms avg BLEW the ${ceiling}ms ceiling (${backend}n=$n)" "$RED"
    return 1
  fi
}

function bench_bash_startup() {
  _hi_bench "bash rc (common/bash.sh)" 500 10 \
    _hi_bench_env bash -c 'source "$_HI_HOME/say-hi/common/bash.sh"'
}

function bench_zsh_startup() {
  _hi_bench "zsh rc (common/zsh.zsh)" 500 10 \
    _hi_bench_env zsh -c 'source "$_HI_HOME/say-hi/common/zsh.zsh"'
}

function bench_fish_startup() {
  _hi_bench "fish rc (common/config.fish)" 500 10 \
    _hi_bench_env fish -c 'source $_HI_HOME/say-hi/common/config.fish'
}

# the connect banner the user watches before getting a shell; backend probes
# are capped at 1s each by the env above
function bench_header() {
  _hi_bench "header (hi_header Online)" 3000 3 \
    _hi_bench_env bash -c 'source "$_HI_HOME/say-hi/common/header.sh"; hi_header Online'
}

# per-prompt cost: many calls inside ONE shell, so the number is the
# function's, not bash's startup
function bench_git_prompt() {
  _hi_bench "git prompt (50 calls, one shell)" 2500 1 \
    _hi_bench_env bash -c '
      source "$_HI_HOME/say-hi/common/core.sh"
      source "$_HI_HOME/say-hi/common/git_prompt.sh"
      cd "$_HI_HOME/say-hi" || exit 1
      for ((i = 0; i < 50; i++)); do _hi_git_prompt out; done'
}

# what every TAB after `hi ` pays: once cold, then against the warm cache.
#
# The ceiling is arithmetic, not a round number: ONE probe cap plus a fork
# budget. targets.sh sweeps the backends together, so a cold TAB costs the
# longest of them rather than the sum - but a daemon that is installed and not
# answering costs that whole cap, and a hosted runner hands this job two of
# them (docker and podman both wedged), so $_HI_BENCH_PROBE seconds is the
# floor this number cannot go under however parallel the sweep is. The +800ms
# is everything around it: the 200ms KILL grace behind the cap's TERM (a
# rootless podman on a fresh $HOME defers the TERM through its whole runtime
# setup, and a hosted runner has been seen to take a second over that - the
# 2013ms that once failed this case was that lane, not the sweep going in
# turn), then `env -i`, `sh`, the scratch mkdir, and one `timeout`+CLI exec
# per backend, which are large Go binaries. A contended 4-core hosted runner
# spends ~285ms on those; a developer machine with a docker that answers,
# ~90ms for the whole run. The extra 200ms over that sum is slack for a
# noisier runner than any of the above.
#
# In turn on that same host would be two caps and change, so this still tells
# the two apart - but it is a wall clock on somebody else's machine and it is
# not what guards the fan-out. tests/common/targets_test.sh's "Backends are
# swept together, not in turn" does that, deterministically, in the fast group.
function bench_targets_cold() {
  _hi_bench "targets.sh, cold cache" $((_HI_BENCH_PROBE * 1000 + 800)) 3 \
    _hi_bench_env env _HI_TARGETS_TTL=0 sh "$_HI_TARGETS"
}

# TTL 60, not the env's 5: this primes once and then times five more runs, and
# at 5s the cache can turn over mid-loop - one "warm" run silently becomes a
# cold one, and a ~1000ms event lands in an average held to 500ms. The number
# wanted here is the cache-hit path's, which a longer window measures more of.
function bench_targets_warm() {
  _hi_bench_env env _HI_TARGETS_TTL=60 sh "$_HI_TARGETS" >/dev/null 2>&1 || true # prime
  _hi_bench "targets.sh, warm cache" 500 5 \
    _hi_bench_env env _HI_TARGETS_TTL=60 sh "$_HI_TARGETS"
}

# The wire budget: the payload built exactly the way hi.sh builds it, against
# a byte ceiling. Catches the payload quietly growing (a new file sneaking
# into $_HI_PAYLOAD's directories, comments ballooning) long before anyone
# notices a slow connect. This budget and the wire figure the badge tracks move
# independently - the launcher rides *inside* this tar, so it counts here and
# not as a stream of its own. See CLAUDE.md.
# Both figures below are a DEFAULT configuration's, and have to be: hi.sh's
# _hi_payload_tar drops settings/vim.rc, settings/nano.rc and
# common/passthrough.sh when the overlay has
# already switched them off, so a configured client sends less than
# either number says. The ceiling and the badge are the unconfigured case, which
# is the one every budget should be set against.
function bench_payload_size() {
  local bytes budget=65536
  set -- # hi.sh reads "$@"; make sure it sees none (same as hi_test.sh)
  # shellcheck source=../../hi.sh
  source "$_HI_LAUNCHER"
  bytes="$(_hi_payload_tar | wc -c)"
  if ((bytes <= budget)); then
    _hi_align " | payload: $bytes bytes gzipped (budget $budget)" "OK" "$GREEN"
  else
    _hi_cecho " | payload: $bytes bytes gzipped BLEW the $budget budget" "$RED"
    return 1
  fi
}

# The README wears the per-session wire size as a badge; this keeps it honest
# the same way the packaging drift guards keep the formula honest - CI fails
# until the number is true again.
#
# The badge tracks _hi_wire_bytes, i.e. the assembled script hi prints the size
# of on connect (no overlay - which files ride is a question about a target),
# NOT the gzipped tar bench_payload_size budgets. Those are different numbers
# on purpose: the tar is what the tree costs, this is what a session costs.
# 5% of slack, so ordinary drift in a PR that never touched the payload cannot
# fail it, while a real jump still does.
function bench_payload_readme_badge() {
  local bytes kb badge
  set -- # hi.sh reads "$@"; make sure it sees none (same as hi_test.sh)
  # shellcheck source=../../hi.sh
  source "$_HI_LAUNCHER"
  bytes="$(_hi_wire_bytes)"
  kb=$(((bytes + 512) / 1024))
  badge="$(sed -n 's/.*ssh_payload-\([0-9]*\)KB.*/\1/p' "$_HI_ROOT/README.md" | head -1)"
  if [ -z "$badge" ]; then
    _hi_cecho " | README payload badge: MISSING (expected ssh_payload-<n>KB in README.md)" "$RED"
    return 1
  fi
  # 5% of the true figure, rounded up, and never less than 1KB - the same band
  # ssh_wire_test.sh holds the connect line to, through the same helper
  if _hi_within_percent "$badge" "$kb" 5; then
    _hi_align " | README payload badge: says ${badge}KB, a session sends ${kb}KB (±${_HI_WITHIN_SLACK}KB)" "OK" "$GREEN"
  else
    _hi_cecho " | README payload badge says ${badge}KB but a session sends ${kb}KB - update the badge" "$RED"
    return 1
  fi
}

# The probes above run with $HOME pointed at the scratch dir, so a rootless
# podman answering `podman ps` initialises its storage under it - and the
# overlay dirs it leaves behind belong to a subuid, which the generic
# `rm -rf "$_HI_WORKDIR"` cannot remove ("Permission denied" on .../work/work).
# `podman unshare` re-enters the user namespace they were made in, which is
# the only way this user can take them back. Runs before the generic
# teardown, because that is the rm it exists to let succeed.
function _hi_bench_cleanup() {
  [ -n "$_HI_WORKDIR" ] && [ -d "$_HI_WORKDIR/.local/share/containers" ] || return 0
  command -v podman >/dev/null 2>&1 || return 0
  # a podman that will not unshare must not hang a teardown. Where `timeout` is
  # absent (stock macOS) this stands down and the generic rm handles it: the
  # subuid ownership that defeats that rm is the Linux rootless case, and a
  # macOS podman's files under $HOME belong to the user who ran it.
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 podman unshare rm -rf "$_HI_WORKDIR/.local/share/containers" >/dev/null 2>&1 || true
  fi
  return 0
}

function run_bench_tests() {
  _hi_workdir benchtest _hi_bench_cleanup
  mkdir -p "$_HI_WORKDIR/cfg"
  # hyperfine reruns the benched argv in a child bash: hand that child the
  # env wrapper and the three vars its body expands
  export -f _hi_bench_env
  export _HI_WORKDIR _HI_HOME _HI_BENCH_PROBE

  _hi_suite_begin

  _hi_h1 "Benchmarking hi's hot paths"

  _hi_h2 "Benchmark: shell startup"
  _hi_case bench_bash_startup
  if command -v zsh >/dev/null 2>&1; then _hi_case bench_zsh_startup; else _hi_skip "zsh rc" "no zsh"; fi
  if command -v fish >/dev/null 2>&1; then _hi_case bench_fish_startup; else _hi_skip "fish rc" "no fish"; fi

  _hi_h2 "Benchmark: per-session and per-prompt paths"
  _hi_case bench_header
  _hi_case bench_git_prompt

  _hi_h2 "Benchmark: completion"
  _hi_case bench_targets_cold
  _hi_case bench_targets_warm

  _hi_h2 "Benchmark: the wire"
  _hi_case bench_payload_size
  _hi_case bench_payload_readme_badge

  _hi_suite_end "bench" \
    "Every hot path under its ceiling ($_HI_TOTAL benchmarks)" \
    "$_HI_FAILED/$_HI_TOTAL benchmarks over their ceiling"
}

run_bench_tests
