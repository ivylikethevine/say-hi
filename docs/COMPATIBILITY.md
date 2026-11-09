# What hi supports, and what it doesn't

`hi <name>` tries an ssh host first, then the container backends, and lands
you in the same styled session either way. Everything hi reaches comes first;
every **no**, with its reason, starts at
[Targets weighed and not shipped](#targets-weighed-and-not-shipped).

**Legend:** ✅ run by a suite on every push · 🟡 expected to work, unproven ·
⚠️ works, reduced · ❌ decided against, not pending.

## Contents

- [What hi needs](#what-hi-needs)
- [What ships](#what-ships)
- [The target's OS](#the-targets-os)
- [A local install on a NAS](#a-local-install-on-a-nas)
- [The shell you end up in](#the-shell-you-end-up-in)
- [Targets weighed and not shipped](#targets-weighed-and-not-shipped)
- [Shells hi does not style](#shells-hi-does-not-style)
- [What would change an answer](#what-would-change-an-answer)
- [What a "yes" costs](#what-a-yes-costs)

## What hi needs

- **Your machine**: bash 3.2+, `tar`, `gzip`, and `base64`, plus `ssh` or the
  backend's CLI. A libarchive `tar` compresses on its own and needs no `gzip`;
  `openssl base64` stands in where there is no `base64`.
- **The target**: `base64` (or `openssl`), `mktemp`, and a `tar` that reads
  gzip, over ssh and an exec alike. `bash` gives the full session; without it
  you get [a smaller one](#the-shell-you-end-up-in).
- **The link**: a connect is meant to send at most 128 KB (8 s at 128 kbps), and
  the bench holds the gzipped payload under 64 KB. The README's payload badge
  is today's size.

bash 3.2 is the floor on both ends because macOS still ships it.

## What ships

Four backends; the docker one answers to four CLIs.

| target                                  | what a name resolves as                                      | proven by                                                                                                                              |
| --------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| ssh host ✅                             | a `Host` entry in `~/.ssh/config`, or any name ssh will take | `tests/targets/ssh_test.sh`, plus the disconnect, relay, wire, and keep suites                                                         |
| docker ✅, podman ✅, nerdctl ✅, finch | a running container (GLOSSARY: HI.51)                        | `docker_test.sh`, `podman_test.sh`, `nerdctl_test.sh`, six shells each; finch has no hosted runner and shares the arm the others prove |
| nomad ✅                                | a running allocation, or `alloc/task`                        | `nomad_test.sh`, against `nomad agent -dev`                                                                                            |
| kubernetes ✅                           | a running pod, `pod/container`, `ns:pod`, `ctx:ns:pod`       | `kube_test.sh`, against a kind cluster                                                                                                 |

A name that is both an ssh host and a container resolves as the ssh host.

**Covered by those rows**, so no row of their own:

- **Anything that is a docker or podman container underneath**: distrobox,
  toolbx, devcontainers (from outside), compose services (`hi web` resolves
  the service label; a service name two projects share resolves to neither),
  and remote docker contexts.
- **Anything that ends in a real OpenSSH connection**: AWS SSM,
  `gcloud compute ssh`, `fly ssh console`, Azure Bastion, `multipass`,
  Vagrant, Codespaces, Lima/Colima, OrbStack, Tailscale SSH, Teleport. Most
  can write the `Host` block for you (`vagrant ssh-config`,
  `gh codespace ssh --config`, `limactl show-ssh --format config <vm>`,
  `tsh config`). mosh and Eternal Terminal are not OpenSSH, so hi cannot ride
  them.

## The target's OS

Every workflow named here runs on each push to main and each same-repository
pull request.

| target OS                                                        | result                                                                              | proven by                                                                                     |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…)                        | ✅ full session                                                                     | `ssh_test.sh` on Debian; `install_methods_test.sh` on Fedora too                              |
| Linux, musl + busybox (Alpine…)                                  | ✅ full with `bash` installed, ⚠️ aliases-only without                              | `ssh_test.sh` on Alpine; `ci.yml`'s Alpine client job                                         |
| macOS                                                            | ✅ full session, client included                                                    | `ssh_test.sh`'s bash-3.2 target; `ci.yml`'s macOS job, with Apple's `/bin/bash` as the client |
| WSL                                                              | ✅ full session: it is Linux                                                        | `windows-e2e.yml`'s `wsl-suites` job                                                          |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH`                    | ✅ as a client under Git Bash; 🟡 as a target                                       | `windows-client.yml` (x64 and arm64); `windows-e2e.yml`'s `openssh-target`                    |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell)                    | ⚠️ a plain PowerShell session, on purpose                                           | `windows-e2e.yml`'s `openssh-target` job                                                      |
| \*BSD, Solaris/illumos                                           | ✅ FreeBSD and OpenBSD (with the `bash` package), client included; 🟡 the rest      | `freebsd-e2e.yml` and `openbsd-e2e.yml`, in a VM                                              |
| NAS: Synology DSM, QNAP QTS, TrueNAS SCALE/CORE, Unraid          | 🟡 full session expected: each ships bash and the tools the bootstrap needs         | the Alpine, glibc, and FreeBSD rows cover each shape; untested on an appliance                |
| OpenWrt (and other busybox routers)                              | ⚠️ aliases-only; `opkg install bash` makes it full                                  | 🟡 the same shape as Alpine without bash                                                      |
| Termux (Android)                                                 | 🟡 as a client, installed as usual; 🟡 as a target over Termux's `sshd` (port 8022) | none; [adb](#targets-weighed-and-not-shipped) is the other direction and stays a no           |
| any of the above behind sshd `ForceCommand`, or a `command=` key | ⚠️ the host's forced program, after a line saying hi's bootstrap never ran          | `ssh_test.sh`'s forced-command cases                                                          |
| any of the above with an `rbash` login shell, or `MaxSessions 1` | ✅ full session ([SECURITY.md](SECURITY.md#what-runs-where) on rbash)               | `ssh_test.sh`'s rbash and maxsessions1 cases                                                  |

## A local install on a NAS

**Untested**: drafted from the install path; what it gets wrong is a bug
report.

An install on the NAS is for its own shells (`ssh nas` without `hi`). A `hi`
from your laptop sends the payload as it does to every ssh target.

- **Don't use `scripts/install.sh --prefix`.** It writes `/usr/bin/hi` and
  `/etc/profile.d/say-hi.sh`, which a DSM or QTS firmware upgrade wipes.
- **Install into your home on the data volume**, which survives upgrades:
  `/volume1/homes/<user>` on DSM (turn on the _user home service_ first),
  `/share/homes/<user>` on QTS. SCALE, Unraid, and CORE have ordinary homes.

So: the README's [clone and install](../README.md#in-sixty-seconds), run on
the NAS as the user you ssh in as (a release tarball where there is no
`git`). On DSM a non-admin login lands in `/bin/sh` and never reads
`~/.bashrc`, so check which rc that account reads.

## The shell you end up in

Your login shell on the target, when hi styles it; else the first of fish,
zsh, and bash the target has. `_HI_SHELL_PREFERENCE` reorders that
([SETTINGS.md](SETTINGS.md#every-setting)).

| session shell                                           | result                                                       | note                                                                                       |
| ------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `bash` ≥ 3.2                                            | ✅ full: header, prompt, git status, aliases, editor configs | 3.2 because macOS still ships it                                                           |
| `zsh` ≥ 5.5                                             | ✅ full                                                      | completion through your rc's own `compinit`; 5.5 is RHEL 8's                               |
| `fish` ≥ 3.3                                            | ✅ full                                                      | 3.3 is Ubuntu 22.04's; an older fish gets a notice and the next shell down                 |
| `sh`/`dash`/`ash` (no bash on the target)               | ⚠️ aliases and a colored prompt, with a warning              | no header and no git segment: those need bash                                              |
| `nushell`, `ion`, `elvish`, `xonsh`, `tcsh`, PowerShell | ❌ [decided against](#shells-hi-does-not-style)              | you still get a session in the best shell the target has, or plain PowerShell with no `sh` |

**Shell frameworks load normally on a target** ✅: oh-my-zsh, powerlevel10k,
starship, bash-it, oh-my-bash, tide, powerline-go, fzf, zoxide, direnv,
atuin, and mise, each in `tests/targets/framework_test.sh`. What hi does
alongside each is [INTEGRATIONS.md](INTEGRATIONS.md).

## Targets weighed and not shipped

Each of these still works from the other side: ssh into the host and run `hi`
there, or use the host's own shell.

| target                                                                                                    | why not                                                                                                                                                                                                                           |
| --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `systemd-nspawn` / `machinectl`                                                                           | needs root or a polkit prompt, and few people sit in one; not worth another probe on everyone's TAB                                                                                                                               |
| WSL (`wsl -d <distro>`)                                                                                   | reachable only from a Windows client; install say-hi _into_ the distribution instead                                                                                                                                              |
| `crictl` / CRI-O                                                                                          | a node debugging tool; the pod you want is the kubernetes row's                                                                                                                                                                   |
| Apptainer / Singularity                                                                                   | HPC jobs run to completion, so there is rarely anything to exec into                                                                                                                                                              |
| Proxmox `pct enter`                                                                                       | LXC, reachable only as root on the PVE node; see `lxc` below                                                                                                                                                                      |
| FreeBSD jails (`jexec`), illumos zones (`zlogin`)                                                         | root-only on the host, where you can already run `hi`; no unprivileged listing or probe                                                                                                                                           |
| `chroot`                                                                                                  | nothing to list, root-only, and no isolation worth the name                                                                                                                                                                       |
| `adb shell` (Android)                                                                                     | the commands fit, but the device has no bash, so every session would be aliases-only                                                                                                                                              |
| AWS ECS Exec (`aws ecs execute-command`)                                                                  | a task is a cluster/task/container triple, not one name, and it needs a plugin `command -v aws` cannot see                                                                                                                        |
| Slurm (`srun --pty bash`)                                                                                 | `srun` queues a job rather than attaching; the login node you submit from is already an ssh host                                                                                                                                  |
| Docker Swarm services, Azure Container Instances (`az container exec`), `systemd-run` / portable services | nobody sits in these: Swarm is largely replaced by kubernetes, ACI is run-and-go, `systemd-run` starts a unit                                                                                                                     |
| Talos Linux and other shell-less immutable distributions                                                  | no shell by design; pods on such a node are the kubernetes row's                                                                                                                                                                  |
| Serial consoles (`picocom`, `virsh console`), `telnet`                                                    | no way to transfer the payload                                                                                                                                                                                                    |
| WinRM / PowerShell Remoting                                                                               | PowerShell cannot run hi's POSIX payload; Git Bash on `PATH` is the supported shape                                                                                                                                               |
| Apple `container` (macOS 26)                                                                              | not docker's grammar (`list` for `ps`, no Go templates), so it would need its own arm, and GitHub's macOS runners have no nested virtualization for its Linux VMs, so no suite could run it; checked 2026-10 against the brew CLI |
| `lxc` / `incus` (and LXD)                                                                                 | a suite could only skip (it needs a daemon and storage pool), and a system container people sit in runs sshd or can have say-hi installed                                                                                         |

## Shells hi does not style

Each would need its own rc in `common/` and a tier in the fallback ladder. You
can still use one as your _login_ shell; only the _session_ shell is limited.

| shell            | why not                                                                      |
| ---------------- | ---------------------------------------------------------------------------- |
| `elvish`         | its own language: a second prompt and alias implementation, and nobody asked |
| `xonsh`          | Python: a third implementation                                               |
| `tcsh`/`csh`     | different rc syntax and no `$ENV` hook to land on                            |
| `nushell`, `ion` | not POSIX, so neither can source `common/`                                   |
| `ksh`/`mksh`     | they get the `sh` tier: aliases and the colored prompt                       |
| PowerShell       | not POSIX; hi prints a greeting there and nothing more                       |

## What would change an answer

A "no" above is closed, not permanent. What reopens one is **evidence of
people sitting in it**: who, how often, and what they use today, enough to be
worth [what a yes costs](#what-a-yes-costs) everyone else. A new CLI or an
easier integration does not, because nothing here is a "no" for being hard.

One proposal about hi itself was declined: **a bash 4 floor for the client**.
The 3.2 code is tested on both ends, and a split floor means two dialects in
one tree.

## What a "yes" costs

A new docker-compatible CLI is one word in `_HI_CONTAINER_CLIS` (GLOSSARY:
HI.51). Any other backend touches seven places:

- a row in `_HI_BACKENDS` (`hi.sh`), walked by the dispatch and
  `scripts/doctor.sh`;
- a predicate beside `_hi_is_nomad_alloc`, one `_hi_probe_is` line;
- an arm in `_hi_transport_cmds` (`probe`, `cp`, `attach`);
- a lister, a `run_lister` case, and the usage line in `common/targets.sh`;
- a probe in `common/header.sh`'s `_hi_probe_launch`
  (`tests/hi/parse_test.sh` checks it against the roster);
- an e2e suite in `tests/targets/`, registered in `_HI_TESTS`;
- a fixture that stands the target up, so far always a container image.

Everyone pays for it too: every `hi <target>` that is not an ssh host runs
every backend's predicate, and every uncached TAB checks every backend
(GLOSSARY: HI.26). An absent CLI costs nothing; a present one costs a
parallel probe. So a backend earns a yes by being somewhere people actually
sit, not by being reachable.
