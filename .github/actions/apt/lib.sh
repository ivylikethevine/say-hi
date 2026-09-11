#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# `apt-get update` on a GitHub-hosted runner, made survivable. Sourced by
# ../setup-shells, ../setup-backends, ../setup-tool/install.sh and
# coverage.yml's gather-kcov job directly, so the two mitigations below are
# written once rather than per caller.
#
# Nothing here runs on a target: this directory is CI-only and never ships.

# The hosted images preconfigure third-party apt repositories nobody here
# wants: Google Chrome and packages.microsoft.com. `apt-get update` exits 100
# when *any* index fails, so one of those republishing a Packages.gz mid-fetch
# ("Hash Sum mismatch") fails every job that installs anything - which has no
# bearing on whether zsh, fish, podman or kcov's headers can be fetched.
#
# Ubuntu's own repositories are not touched: noble keeps them in the deb822
# /etc/apt/sources.list.d/ubuntu.sources, and jammy in /etc/apt/sources.list,
# so the *.list files in sources.list.d are exactly the vendor ones. Call this
# BEFORE adding a repository of your own (../setup-backends adds hashicorp's),
# or it takes that one out too.
function _hi_apt_drop_vendor_lists() {
  sudo rm -f /etc/apt/sources.list.d/*.list
}

# A mirror can still hand back a short or stale index, so the update is
# retried rather than trusted once. The list directory is emptied between
# tries: a Hash Sum mismatch leaves the bad index cached, and a plain retry
# fails on the same bytes.
function _hi_apt_update() {
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
