#!/usr/bin/env bash
# Installs whatever ./action.yml's cache step missed, one tool at a time via
# ../setup-tool/install.sh - always the tools.txt pin, so the row's sha256 is
# what gets verified.
set -euo pipefail

: "${CI_TOOLS:?set by action.yml}"

# every tool, even one already on the path: the cache saves what sits at each
# path under the pinned key, so a binary something else put there would be
# saved unverified
for _ci_t in $CI_TOOLS; do
  CI_TOOL="$_ci_t" "$(dirname "${BASH_SOURCE[0]}")/../setup-tool/install.sh" install
done
