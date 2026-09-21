#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/doctor.sh's --json document: a quarter of doctor_test.sh's
# cases, run as a suite of its own so the Windows shards split them. The
# preamble's source line is doctor_test.sh's - it sources the harness, and a
# second source here would initialise core.sh twice (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_DOCTOR_PART=json
# shellcheck source=./doctor_test.sh
source "${BASH_SOURCE[0]%/*}/doctor_test.sh"
