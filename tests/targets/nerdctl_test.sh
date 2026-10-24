#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Drives hi.sh's real nerdctl path - see tests/lib/backend.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with docker_test.sh and podman_test.sh. nerdctl's containerd namespace is its
# own store, so this builds its own copies of the test images (through
# buildkitd, which .github/actions/setup-backends/nerdctl.sh starts).
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_hi_container_backend_test nerdctl
