#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Sourced (not run) by pages.yml, release.yml's freeze step, and coverage.yml's
# PR comment - the one answer to "is this coverage figure a real measurement",
# so the three places a figure reaches a reader agree.
#
# An all-zero figure is kcov's checkout-less merge ("files": [], 0.00), not a
# measurement: coverage.yml's gather job refuses to publish one, and every
# reader here refuses to render one an older artifact still carries.
#
# No `set -euo pipefail`: every caller already has its own before sourcing
# this, and a sourced file changing the caller's shell options is a surprise.

# pct_ok <figure> - true if <figure> looks like a real coverage percentage
function pct_ok() {
  case "$1" in '' | *[!0-9.]* | 0 | 0.0 | 0.00 | 0.000) return 1 ;; esac
}
