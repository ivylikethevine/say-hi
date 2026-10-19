#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# A FreeBSD VM on this machine for the cases that fail only on the BSD CI jobs:
# boots the release's cloud-init image under qemu (KVM where /dev/kvm is
# readable, software emulation otherwise), installs the packages the CI job's
# prepare step installs, copies this checkout in over ssh, and runs one suite's
# cases or a command there. Everything it makes lives in local/bsdvm.
#
# Usage: scratch/bsd_vm.sh <command> [args]
#   up                      download, provision and boot the VM; waits for ssh
#   cases <suite> <word>... scratch/run_cases.sh in the VM, against the synced tree
#   suite <suite>           tests/test_runner.sh <suite> in the VM
#   sh [cmd...]             a shell, or one command, in the VM's checkout
#   sync                    copy the checkout in again (cases/suite/sh do this first)
#   down                    power the VM off
#   console                 the serial console log so far
#
#   scratch/bsd_vm.sh up
#   scratch/bsd_vm.sh cases load/load_test.sh test_hooks_run_once
#   scratch/bsd_vm.sh sh 'ps -A -o pid,ppid,pgid,tty,stat,wchan,etime,args'
#
# The guest runs everything as the user `hi`, or as root with BSD_VM_USER=root,
# which is what the CI jobs run as; bash, zsh, git and python3 come from pkg at
# first boot, so `up` needs the VM online. _HI_HOME in the guest is the user's
# home directory, the tree <home>/say-hi. FreeBSD only: OpenBSD ships no cloud
# image, and FreeBSD reproduces the hang the BSD jobs share.
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
vm="$root/local/bsdvm"
release="${BSD_VM_RELEASE:-15.1}"
image="FreeBSD-$release-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2"
mirror="https://download.freebsd.org/releases/VM-IMAGES/$release-RELEASE/amd64/Latest"
port="${BSD_VM_PORT:-2222}"
# BSD_VM_USER=root is what the CI jobs run as; `hi` is the provisioned user
user="${BSD_VM_USER:-hi}"
ssh_opts=(-p "$port" -i "$vm/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR -o ConnectTimeout=5)
mkdir -p "$vm"

function say() { printf '%s\n' "$*" >&2; }

function fetch_image() {
  [ -f "$vm/$image" ] && return 0
  if [ ! -f "$vm/$image.xz" ]; then
    say "fetching $image.xz"
    curl -fL --retry 3 -o "$vm/$image.xz.part" "$mirror/$image.xz"
    mv "$vm/$image.xz.part" "$vm/$image.xz"
  fi
  curl -fsSL -o "$vm/CHECKSUM.SHA256" "$mirror/CHECKSUM.SHA256"
  want="$(sed -n "s/^SHA256 ($image.xz) = //p" "$vm/CHECKSUM.SHA256")"
  got="$(sha256sum "$vm/$image.xz" | cut -d' ' -f1)"
  [ "$want" = "$got" ] || {
    say "checksum mismatch for $image.xz: want $want, got $got"
    exit 1
  }
  say "unpacking $image.xz"
  xz -dk "$vm/$image.xz"
}

# the NoCloud seed: a user with our key, and the CI prepare step's packages
function make_seed() {
  [ -f "$vm/id_ed25519" ] || ssh-keygen -t ed25519 -N '' -q -f "$vm/id_ed25519" -C bsd_vm
  local key
  key="$(cat "$vm/id_ed25519.pub")"
  mkdir -p "$vm/seed"
  printf 'instance-id: bsd-vm-1\nlocal-hostname: freebsd\n' >"$vm/seed/meta-data"
  cat >"$vm/seed/user-data" <<EOF
#cloud-config
users:
  - name: $user
    shell: /bin/sh
    ssh_authorized_keys:
      - $key
runcmd:
  - env ASSUME_ALWAYS_YES=yes pkg install -y bash zsh git python3 gtar
  - mkdir -p -m 700 /root/.ssh
  - cp /home/$user/.ssh/authorized_keys /root/.ssh/authorized_keys
  - printf 'PermitRootLogin prohibit-password\n' >>/etc/ssh/sshd_config
  - service sshd restart
  - touch /home/$user/.provisioned /root/.provisioned
  - chown $user /home/$user/.provisioned
EOF
  if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -output "$vm/seed.iso" -volid cidata -joliet -rock "$vm/seed/user-data" "$vm/seed/meta-data"
  else
    xorriso -as mkisofs -quiet -output "$vm/seed.iso" -volid cidata -joliet -rock "$vm/seed/user-data" "$vm/seed/meta-data" 2>/dev/null
  fi
}

function vm_pid() {
  local p
  [ -f "$vm/qemu.pid" ] && read -r p <"$vm/qemu.pid" && kill -0 "$p" 2>/dev/null && printf '%s' "$p"
}

# shellcheck disable=SC2029 # the command is built here on purpose
function vm_ssh() { ssh "${ssh_opts[@]}" "$user@127.0.0.1" "$@"; }

function boot() {
  if [ -n "$(vm_pid)" ]; then
    say "VM already running, pid $(vm_pid)"
    return 0
  fi
  fetch_image
  make_seed
  # a fresh disk off the pristine image each boot: the seed provisions it again
  cp "$vm/$image" "$vm/disk.qcow2"
  local -a accel=(-accel tcg -cpu max)
  [ -r /dev/kvm ] && [ -w /dev/kvm ] && accel=(-accel kvm -cpu host)
  say "booting with ${accel[1]}, ssh on 127.0.0.1:$port, console in local/bsdvm/console.log"
  : >"$vm/console.log"
  # its own session, so it outlives the shell that started it
  setsid -f qemu-system-x86_64 -machine q35 "${accel[@]}" -m 2048 -smp 4 \
    -drive "file=$vm/disk.qcow2,if=virtio,format=qcow2" \
    -drive "file=$vm/seed.iso,media=cdrom,format=raw" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22" \
    -display none -serial "file:$vm/console.log" -pidfile "$vm/qemu.pid" \
    -monitor none </dev/null >"$vm/qemu.log" 2>&1
  local t=0
  until vm_ssh test -f .provisioned 2>/dev/null; do
    [ -n "$(vm_pid)" ] || [ "$t" -lt 5 ] || {
      say "qemu exited; its log:"
      cat "$vm/qemu.log" >&2
      exit 1
    }
    [ "$t" -lt 900 ] || {
      say "no provisioned guest after ${t}s; the console log's tail:"
      tail -n 30 "$vm/console.log" >&2
      exit 1
    }
    sleep 5
    t=$((t + 5))
  done
  say "up after ${t}s: $(vm_ssh 'uname -sr; bash --version | head -n 1')"
}

# the checkout over a tar pipe: the guest has no rsync, and .git and local/
# stay behind
function sync_tree() {
  [ -n "$(vm_pid)" ] || {
    say "VM not running: scratch/bsd_vm.sh up"
    exit 1
  }
  tar -C "$root/.." --exclude=say-hi/.git --exclude=say-hi/local --exclude=say-hi/node_modules \
    --exclude=say-hi/.github/node_modules -cf - say-hi |
    vm_ssh 'rm -rf say-hi && tar -xf -'
}

# every ssh command runs in the checkout with the guest's bash, _HI_HOME at
# the directory holding it, nothing else inherited
function in_tree() {
  vm_ssh "cd say-hi && env -i HOME=\$HOME PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin TERM=dumb _HI_HOME=\$HOME bash -c $(printf '%q' "$*")"
}

case "${1:-}" in
up) boot ;;
sync) sync_tree ;;
cases)
  shift
  sync_tree
  in_tree "scratch/run_cases.sh $*"
  ;;
suite)
  sync_tree
  in_tree "tests/test_runner.sh ${2:?suite}"
  ;;
sh)
  shift
  sync_tree
  if [ $# -eq 0 ]; then vm_ssh -t 'cd say-hi && exec bash -l'; else in_tree "$*"; fi
  ;;
console) cat "$vm/console.log" ;;
down)
  p="$(vm_pid)"
  [ -n "$p" ] || {
    say "not running"
    exit 0
  }
  vm_ssh 'doas poweroff 2>/dev/null || su root -c poweroff' 2>/dev/null || true
  sleep 3
  kill -0 "$p" 2>/dev/null && kill "$p"
  rm -f "$vm/qemu.pid"
  say "stopped"
  ;;
*)
  sed -n '3,20p' "$0" >&2
  exit 2
  ;;
esac
