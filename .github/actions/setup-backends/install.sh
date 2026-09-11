#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The apt half of the setup-backends action: the HashiCorp repo (keyring
# fetched here - the one security-relevant download in the action) and the
# package install. A script rather than YAML-embedded shell so the lint
# gate's shellcheck/shfmt sweep covers it. $HI_BACKENDS names which of
# podman/nomad to install (action.yml only runs this step when at least one
# is in it); $HI_EXTRA_PACKAGES rides along unconditionally.
set -euo pipefail

# $HI_APT_CACHE (action.yml points it at a runner-owned $RUNNER_TEMP dir, so
# actions/cache can restore it without root) replaces apt's own
# /var/cache/apt/archives so the downloaded .debs survive between runs;
# apt needs the archive dir's partial/ subdirectory to exist up front.
: "${HI_APT_CACHE:=/var/cache/apt/archives}"
mkdir -p "$HI_APT_CACHE/partial"

: "${HI_BACKENDS:=podman nomad}"
_hi_pkgs=""
case " $HI_BACKENDS " in *' podman '*) _hi_pkgs="$_hi_pkgs podman" ;; esac
case " $HI_BACKENDS " in *' nomad '*) _hi_pkgs="$_hi_pkgs nomad" ;; esac

# shellcheck source=../apt/lib.sh
source "$GITHUB_ACTION_PATH/../apt/lib.sh"
_hi_apt_drop_vendor_lists

# nomad only: podman is in ubuntu's own repo. gpg unprivileged, `sudo` only
# for the write. `sudo gpg` runs with root's HOME, creates /root/.gnupg on
# the way past, and then wants a controlling terminal to say so - which an
# Actions step does not have: "gpg: cannot open '/dev/tty'". --batch --yes
# says there is nobody to ask, and the keyring lands through tee, the way
# the repo list on the next line already does. Before the vendor-list prune
# above runs, never after: it takes out every *.list in sources.list.d, this
# one included.
case " $HI_BACKENDS " in
*' nomad '*)
  curl -sSfL https://apt.releases.hashicorp.com/gpg |
    gpg --batch --yes --dearmor |
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  ;;
esac
_hi_apt_update
# unquoted on purpose: word lists, one apt name each
# shellcheck disable=SC2086
sudo apt-get -o "Dir::Cache::Archives=$HI_APT_CACHE" install -y $_hi_pkgs $HI_EXTRA_PACKAGES

# apt (root) leaves its lock file and a root-only partial/ behind, and the
# .debs root-owned; actions/cache's post-job save tars the directory as the
# runner user and fails on the first unreadable entry ("partial: Cannot
# open: Permission denied", exit 2 - the save is skipped, so every run
# re-downloads). Drop apt's scratch and hand the .debs back to the runner;
# the mkdir above recreates partial/ on the next run.
sudo rm -rf "$HI_APT_CACHE/partial" "$HI_APT_CACHE/lock"
sudo chown -R "$(id -u):$(id -g)" "$HI_APT_CACHE"
case " $HI_BACKENDS " in *' nomad '*) nomad version ;; esac
