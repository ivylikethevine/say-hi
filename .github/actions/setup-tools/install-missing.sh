#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Installs whatever ./action.yml's cache step missed, one tool at a time via
# ../setup-tool/install.sh - always the tools.txt pin, so the row's sha256 is
# what gets verified.
set -euo pipefail

: "${CI_TOOLS:?set by action.yml}"

# a whole-key miss restores nothing, so this only skips a binary something
# else already put there
for _ci_t in $CI_TOOLS; do
  [ -x "${CI_TOOL_BIN_DIR:-/usr/local/bin}/$_ci_t" ] && continue
  CI_TOOL="$_ci_t" "$(dirname "${BASH_SOURCE[0]}")/../setup-tool/install.sh" install
done
