#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The apt half of the setup-backends action: the HashiCorp repo (keyring
# fetched here - the one security-relevant download in the action) and the
# package install. A script rather than YAML-embedded shell so the lint
# gate's shellcheck/shfmt sweep covers it. Arguments are extra apt packages
# to install alongside podman and nomad.
set -euo pipefail

# gpg unprivileged, `sudo` only for the write. `sudo gpg` runs with root's
# HOME, creates /root/.gnupg on the way past, and then wants a controlling
# terminal to say so - which an Actions step does not have: "gpg: cannot open
# '/dev/tty'". --batch --yes says there is nobody to ask, and the keyring
# lands through tee, the way the repo list on the next line already does.
curl -sSfL https://apt.releases.hashicorp.com/gpg |
  gpg --batch --yes --dearmor |
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
  sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update && sudo apt-get install -y podman nomad "$@"
nomad version
