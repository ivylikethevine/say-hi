#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The shipped suite table against the workflows that run it - runner_test.sh's ci part, a suite of its own in the ci group, which runs
# once on ubuntu: repo text and ubuntu-only tooling give the same answer on
# every platform. The preamble's source line is runner_test.sh's - it sources the
# harness, and a second source here would initialise core.sh twice
# (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_RUNNER_PART=ci
# shellcheck source=./runner_test.sh
source "${BASH_SOURCE[0]%/*}/runner_test.sh"
