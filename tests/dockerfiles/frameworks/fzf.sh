#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# fzf's Ctrl-R, one of the two bash surfaces hi touches. Debian's fzf predates
# `fzf --bash`, so its packaged key-bindings file is what gets sourced - it
# lives under /usr/share/doc, which framework.Dockerfile un-excludes before
# installing.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
printf 'source /usr/share/doc/fzf/examples/key-bindings.bash\n' >>~/.bashrc
