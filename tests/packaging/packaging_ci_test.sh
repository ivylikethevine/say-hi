#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The workflows, the manifests, and the release tooling (bump.sh, mkpkg.sh,
# mkrepo.sh, srctar.sh, .github/scripts) - packaging_test.sh's ci part, a suite of its own in the ci group, which runs
# once on ubuntu: repo text and ubuntu-only tooling give the same answer on
# every platform. The preamble's source line is packaging_test.sh's - it sources the
# harness, and a second source here would initialise core.sh twice
# (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_PACKAGING_PART=ci
# shellcheck source=./packaging_test.sh
source "${BASH_SOURCE[0]%/*}/packaging_test.sh"
