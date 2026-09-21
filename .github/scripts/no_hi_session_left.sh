#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# no_hi_session_left.sh [file that must still exist] - ci.yml's macOS loopback,
# bsd_loopback.sh, and windows-e2e.yml's git-bash-target and wsl-suites
# (shard 1) all share this:
# the session directory a client leaves under $_HI_HOME's mktemp -d (GLOSSARY:
# HI.33) must not survive the client's own exit (load.sh's clean_all).
# ${TMPDIR:-/tmp} is macOS's own convention and, unset inside WSL, is
# exactly /tmp. The optional argument is windows-e2e.yml's packaged-tree
# check - nothing installs anything on the macOS loopback, so it passes none.
#
# The cleanup is the target side's EXIT trap, which can still be running as
# the client returns - sshd tears a session down on its own time, Windows'
# the slowest - so the directory gets ten seconds to go before it counts as
# left behind.
set -eu
tries=0
while ls -d "${TMPDIR:-/tmp}"/*.hi.* >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -gt 20 ]; then
    ls -d "${TMPDIR:-/tmp}"/*.hi.*
    echo "session directory survived the exit (10s after it)" >&2
    exit 1
  fi
  sleep 0.5
done
[ $# -eq 0 ] || test -x "$1"
