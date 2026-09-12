#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# no_hi_session_left.sh [file that must still exist] - ci.yml's macOS loopback,
# bsd_loopback.sh, and windows-e2e.yml's wsl-suites (shard 1) all share this:
# the session directory a client leaves under $_HI_HOME's mktemp -d (GLOSSARY:
# HI.33) must not survive the client's own exit (load.sh's clean_all).
# ${TMPDIR:-/tmp} is macOS's own convention and, unset inside WSL, is
# exactly /tmp. The optional argument is windows-e2e.yml's packaged-tree
# check - nothing installs anything on the macOS loopback, so it passes none.
set -eu
if ls -d "${TMPDIR:-/tmp}"/*.hi.* 2>/dev/null; then
  echo "session directory survived the exit" >&2
  exit 1
fi
[ $# -eq 0 ] || test -x "$1"
