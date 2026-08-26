#!/usr/bin/env bash
# Shared scaffolding for every suite under tests. The scaffolding itself lives
# in tests/lib/; this file is the one path a suite sources (common/paths.sh
# exports it as $_HI_TEST_LIB), so the parts can be re-cut without touching a
# single suite. Order below is dependency order - report.sh's _hi_align is
# what case.sh's assertions print through, and every part uses core.sh.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# Isolation, and it has to happen before bootstrap.sh: that resolves
# $_HI_SETTINGS/$_HI_COLORS/$_HI_PACKAGES against $_HI_CONFIG_DIR once, so by
# the time a suite runs it is too late to stop the developer's own
# ~/.config/say-hi from deciding what those point at. Deliberately a path that
# does not exist yet, so the baseline every suite starts from is "no overlay,
# in-tree defaults"; a test wanting an overlay mkdir's this and writes into it,
# and _hi_test_cleanup takes it away again. Same rule as never touching the
# real ~/say-hi.
export XDG_CONFIG_HOME="${TMPDIR:-/tmp}/hi.testcfg.$$"
export _HI_CONFIG_DIR="$XDG_CONFIG_HOME/say-hi"

# The one place the test side resolves a tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# shellcheck source=../common/core.sh
source "$_hi_d/../common/core.sh"

# shellcheck source=./lib/workdir.sh
source "$_hi_d/lib/workdir.sh"
# shellcheck source=./lib/case.sh
source "$_hi_d/lib/case.sh"
# shellcheck source=./lib/parallel.sh
source "$_hi_d/lib/parallel.sh"
# shellcheck source=./lib/fixtures.sh
source "$_hi_d/lib/fixtures.sh"
# shellcheck source=./lib/report.sh
source "$_hi_d/lib/report.sh"
# shellcheck source=./lib/process.sh
source "$_hi_d/lib/process.sh"
# shellcheck source=./lib/ssh.sh
source "$_hi_d/lib/ssh.sh"
# shellcheck source=./lib/backend.sh
source "$_hi_d/lib/backend.sh"
unset _hi_d
