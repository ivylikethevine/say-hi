#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The nerdctl half of the setup-backends action: the pinned nerdctl-full
# tarball (nerdctl, buildkitd, the CNI plugins), checked against its sha256
# before anything is installed, on top of the containerd the runner's docker
# already runs. Rootful, since that containerd's socket is root's: the
# `nerdctl` on PATH is a sudo shim over the real binary, so the suite and
# hi.sh call it as any user would. buildkitd is what `nerdctl build` needs,
# and its containerd worker writes straight into nerdctl's namespace. Pin and
# sha256 move together; $HI_NERDCTL_CACHE is the tarball's home between runs
# (action.yml points it at a cached $RUNNER_TEMP directory).
set -euo pipefail

HI_NERDCTL_VERSION=2.4.1
HI_NERDCTL_SHA256=ff018f11ac2f1354bf7b3aaaca6e0b52d81139c746a89134744d0b7be3a0e62f

: "${HI_NERDCTL_CACHE:=${RUNNER_TEMP:-/tmp}/nerdctl}"
_hi_tar="nerdctl-full-$HI_NERDCTL_VERSION-linux-amd64.tar.gz"
mkdir -p "$HI_NERDCTL_CACHE"
[ -f "$HI_NERDCTL_CACHE/$_hi_tar" ] ||
  curl -sSfL -o "$HI_NERDCTL_CACHE/$_hi_tar" \
    "https://github.com/containerd/nerdctl/releases/download/v$HI_NERDCTL_VERSION/$_hi_tar"

# refused before the first sudo: a tarball that is not the pinned one installs
# nothing, and does not stay in the cache to be tried again
if ! printf '%s  %s\n' "$HI_NERDCTL_SHA256" "$HI_NERDCTL_CACHE/$_hi_tar" | sha256sum -c - >/dev/null 2>&1; then
  rm -f "$HI_NERDCTL_CACHE/$_hi_tar"
  echo "nerdctl.sh: $_hi_tar does not match its pinned sha256 - removed, nothing installed" >&2
  exit 1
fi

_hi_tree="$(mktemp -d "${RUNNER_TEMP:-/tmp}/nerdctl-tree.XXXXXX")"
tar -xzf "$HI_NERDCTL_CACHE/$_hi_tar" -C "$_hi_tree" bin/nerdctl bin/buildkitd bin/buildctl libexec/cni
sudo install -m 0755 "$_hi_tree/bin/buildkitd" "$_hi_tree/bin/buildctl" /usr/local/bin/
sudo install -d /usr/local/libexec/say-hi /opt/cni/bin
sudo install -m 0755 "$_hi_tree/bin/nerdctl" /usr/local/libexec/say-hi/nerdctl
sudo install -m 0755 "$_hi_tree"/libexec/cni/* /opt/cni/bin/
# shellcheck disable=SC2016 # the shim's own "$@", expanded when it runs
printf '#!/bin/sh\nexec sudo -n /usr/local/libexec/say-hi/nerdctl "$@"\n' |
  sudo tee /usr/local/bin/nerdctl >/dev/null
sudo chmod 0755 /usr/local/bin/nerdctl

# the OCI worker would keep a store of its own; the containerd worker in
# nerdctl's namespace is what lets `nerdctl build` land an image where
# `nerdctl run` finds it, with no load step between
sudo systemd-run --unit hi-buildkitd --quiet /usr/local/bin/buildkitd \
  --oci-worker=false --containerd-worker=true --containerd-worker-namespace=default
_hi_n=0
while [ ! -S /run/buildkit/buildkitd.sock ]; do
  _hi_n=$((_hi_n + 1))
  if [ "$_hi_n" -gt 100 ]; then
    echo "nerdctl.sh: buildkitd did not open its socket in 20s" >&2
    sudo journalctl -u hi-buildkitd --no-pager >&2 || true
    exit 1
  fi
  sleep 0.2
done
nerdctl version
