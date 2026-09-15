#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# tide through fisher, the way its README installs it: fish autoloads its
# fish_prompt, which common/config.fish must leave defined, and tide's
# background renderer is a `fish -c` that has to see the home variables.
#
# fisher pinned to 4.4.5 by the sha256 of the function file, tide to v6.2.0.
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
_hi_fisher="$(mktemp)"
trap 'rm -f "$_hi_fisher"' EXIT
curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/4.4.5/functions/fisher.fish -o "$_hi_fisher"
echo "59640d07bda182f2ad0fdfe9dc8a799fb79f46e6e5fc460354ffe2e21f759688  $_hi_fisher" | sha256sum -c - >/dev/null
fish -c "source $_hi_fisher && fisher install jorgebucaran/fisher@4.4.5 ilancosman/tide@v6.2.0" >/dev/null
