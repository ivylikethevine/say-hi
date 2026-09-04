#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Uninstalling is a mode of install.sh - the two halves own the same rc lines,
# the same settings file and the same symlink, so they live in one script. This
# shim is what keeps `hi --uninstall`, $_HI_UNINSTALL and the documented
# `scripts/uninstall.sh` path working. Arguments pass straight through, so
# `scripts/uninstall.sh --help` is install.sh's help.
exec "$(dirname "$0")/install.sh" --uninstall "$@"
