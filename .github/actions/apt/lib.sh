#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `apt-get update` on a GitHub-hosted runner, made survivable. Sourced by
# ../setup-tool/install.sh (the cmake/make kinds' build deps) and by any other
# step that installs from apt, so the two mitigations below are written once.
#
# CI-only: nothing here runs outside a hosted runner.

# The hosted images preconfigure third-party apt repositories nobody here
# wants (Google Chrome, packages.microsoft.com). `apt-get update` exits 100
# when *any* index fails, so one of those republishing mid-fetch ("Hash Sum
# mismatch") fails every job that installs anything.
#
# Ubuntu's own repositories are not touched: noble keeps them in the deb822
# /etc/apt/sources.list.d/ubuntu.sources and jammy in /etc/apt/sources.list,
# so the *.list files in sources.list.d are exactly the vendor ones. Call this
# BEFORE adding a repository of your own, or it takes that one out too.
function _ci_apt_drop_vendor_lists() {
  sudo rm -f /etc/apt/sources.list.d/*.list
}

# A mirror can still hand back a short or stale index, so the update is
# retried. The list directory is emptied between tries: a Hash Sum mismatch
# leaves the bad index cached, and a plain retry fails on the same bytes.
function _ci_apt_update() {
  local try
  for try in 1 2 3; do
    sudo apt-get update && return 0
    [ "$try" = 3 ] && break
    echo "apt-get update failed (attempt $try/3), clearing the index cache" >&2
    sudo rm -rf /var/lib/apt/lists/*
    sleep $((try * 5))
  done
  echo "apt-get update failed three times" >&2
  return 1
}
