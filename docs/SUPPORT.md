# What hi supports, and what it doesn't

`hi <name>` resolves one name through a ladder — an ssh host first, then four
container backends — and lands you in the same styled session either way. The
first half of this file is what hi can reach, what it does on a given OS, and
which shell it hands you. The second half, from
[Targets weighed and not shipped](#targets-weighed-and-not-shipped) down, is
every answer that was **no**, with the reason: the runtimes it will not reach,
the shells it will not style, and the features it added and then removed. A
thing missing from the first half has a row in the second.

**Legend:** ✅ exercised by a suite on every run · 🟡 expected to work, nobody
has proven it · ⚠️ works, reduced · ❌ decided against, not pending. Nothing
marked ❌ is open — see
[What would change an answer](#what-would-change-an-answer) for the one thing
that reopens a row.

## Contents

- [What a "yes" costs](#what-a-yes-costs)
- [The five that ship](#the-five-that-ship)
- [Already covered, without a row](#already-covered-without-a-row)
- [The target's OS](#the-targets-os)
- [The shell you end up in](#the-shell-you-end-up-in)
- [Targets weighed and not shipped](#targets-weighed-and-not-shipped)
- [Shells hi does not style](#shells-hi-does-not-style)
- [What would change an answer](#what-would-change-an-answer)

## What a "yes" costs

A backend is not one function. A docker-compatible CLI is the exception:
podman, nerdctl and finch share docker's `ps`/`exec`/`inspect` grammar, so
they are one arm and a name in `_HI_CONTAINER_CLIS`
([SETTINGS.md](SETTINGS.md#every-setting), GLOSSARY: HI.51) — a new
drop-in costs a word in a setting, not a row here. Anything else touches
seven places:

- **a row in `_HI_BACKENDS`** (`hi.sh`): `<name>|<what a target resolves
as>|<liveness probe>|<predicate>`, walked by the dispatch and by
  `scripts/doctor.sh`.
- **a predicate** beside `_hi_is_family_container`: one `command -v` guard,
  one `[ "$(<query>)" = <literal> ]`, stderr swallowed.
- **an arm in `_hi_container_cmds`** filling `probe`/`cp`/`attach`; past
  that, everything is backend-agnostic.
- **a lister, a `run_lister` case and the usage line** in `common/targets.sh`,
  in its standalone-POSIX dialect — the only file all three completions read
  and the only one fish can run.
- **a fifth copy of the roster in `common/header.sh`**: `_hi_probe_launch`
  hardcodes the backends because `hi.sh` is never sourced in a session and
  sharing the list would cost payload bytes. `tests/hi/parse_test.sh` greps
  the two against each other.
- **an e2e suite** in `tests/targets/`, registered in `test_runner.sh`'s
  `_HI_TESTS` table. A suite that can only ever skip is worth less than none.
- **a fixture that stands the target up** — so far always a container image.

Then the part everyone else pays: `_hi_resolve_backend` runs **every**
predicate on every `hi <target>`, and `common/targets.sh` probes **every**
backend on every TAB (GLOSSARY: HI.26), on machines with none of the runtime.
One background subshell per row, installed or not, is the resolve-time part;
on TAB the `command -v` guard is a shell builtin, so an absent CLI costs
nothing there and a present one is one parallel lane. The subshell per
`hi <target>` is what every row charges every host.

**A row earns a yes by being something people actually sit in, not by being
reachable.**

## The five that ship

| target         | what a name resolves as                                      | proven by                                                                                                                                                                                                     |
| -------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ssh host ✅    | a `Host` entry in `~/.ssh/config`, or any name ssh will take | `tests/targets/ssh_test.sh`, plus `ssh_disconnect_test.sh` (cleanup on an abrupt drop), `ssh_relay_test.sh` and `ssh_wire_test.sh` (bytes on the wire vs the printed size)                                    |
| docker ✅      | a running container                                          | `tests/targets/docker_test.sh` - six shell environments (bash, bash interactive, zsh, fish, dash, busybox `sh`) plus the compose-alias case                                                                   |
| podman ✅      | a running container                                          | `tests/targets/podman_test.sh`, the same six against podman's own image store                                                                                                                                 |
| nerdctl, finch | a running container, through the docker arm                  | nothing in CI - no hosted runner has either. Members of the default `_HI_CONTAINER_CLIS` because the grammar is docker's; unproven, and the docker and podman suites are what prove the arm (GLOSSARY: HI.51) |
| nomad ✅       | a running allocation, or `alloc/task`                        | `tests/targets/nomad_test.sh`, against a real `nomad agent -dev`                                                                                                                                              |
| kubernetes ✅  | a running pod, `pod/container`, `ns:pod`, `ctx:ns:pod`       | `tests/targets/kube_test.sh`, against a real kind cluster                                                                                                                                                     |

ssh is checked first and short-circuits the roster, so a name that is both an
ssh host and a container name resolves as the ssh host.

## Already covered, without a row

Requested, and already working.

| target                                                                                                                                                        | why no row is needed                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **distrobox** and **toolbx**                                                                                                                                  | they _are_ podman (or docker) containers, so the existing rows reach them by name. Sharing your real `$HOME` costs nothing: hi writes to no login file on a target                                                                                                                                                                                                                                                                                                 |
| **remote docker contexts**                                                                                                                                    | the docker row shells out to whatever `docker` is on `$PATH`, so `docker context use` and `DOCKER_HOST` are transparent to hi                                                                                                                                                                                                                                                                                                                                      |
| **devcontainers / VS Code dev containers**                                                                                                                    | docker containers, on the distrobox precedent, under docker's name (`vsc-<project>-<hash>-uid`) rather than `devcontainer.json`'s; no `com.docker.compose.service` label, so no compose alias. That is the view from _outside_; a devcontainer whose terminal you already sit in has no client to say `hi` from — nothing ships for that side today, and a devcontainer Feature that installed say-hi permanently into the container is the shape a fix would take |
| **`docker compose` services**                                                                                                                                 | a compose service _is_ a docker container, so `hi myproject-web-1` always worked. `hi web` does too: `common/targets.sh`'s docker lister reads the `com.docker.compose.service` label on the same `docker ps` call, and `hi.sh`'s docker predicate and exec commands (`_hi_compose_container`) resolve the alias by it. Ambiguous (the same service in two projects) resolves to neither, on purpose                                                               |
| **AWS SSM, `gcloud compute ssh`, `fly ssh console`, Azure Bastion, `multipass`, Vagrant, Codespaces, Lima/Colima, OrbStack, Tailscale SSH, Teleport (`tsh`)** | all ten end in a real OpenSSH connection, usually a `ProxyCommand` one — hi's ssh path multiplexes two calls over one `ControlMaster` (`_hi_ctl_open`), why mosh and Eternal Terminal cannot be ridden, and a `ProxyCommand` is still OpenSSH. Most emit or write the `Host` block themselves: `vagrant ssh-config`, `gh codespace ssh --config`, `limactl show-ssh --format config <vm>`, `tsh config`; OrbStack writes `~/.ssh/config` on its own                |

## The target's OS

Can hi land a session there at all?

| target OS                                                        | result                                                                                                                                                                                                                                                            | proven by                                                                                                                                                                                                                                                                               |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…)                        | ✅ full session                                                                                                                                                                                                                                                   | `tests/targets/ssh_test.sh`, on Debian bookworm                                                                                                                                                                                                                                         |
| Linux, musl + busybox (Alpine…)                                  | ✅ full session with `bash` installed, ⚠️ aliases-only without                                                                                                                                                                                                    | `ssh_test.sh`, on Alpine 3.24                                                                                                                                                                                                                                                           |
| macOS                                                            | ✅ full session — it ships bash 3.2, and the suite runs a real bash 3.2 target, client half included                                                                                                                                                              | `ssh_test.sh`'s bash-3.2 case; `ci.yml`'s fast suites on `macos-latest` on every PR; and `.github/workflows/macos-e2e.yml` on every push - Apple's `/bin/bash` 3.2 as the client into the runner's own sshd, a one-shot command, a full session whose header says macOS, and `--doctor` |
| WSL                                                              | ✅ full session — it is Linux, and the package layout installs into it unchanged                                                                                                                                                                                  | `.github/workflows/windows-e2e.yml`'s `wsl-suites` (the fast suites inside an Ubuntu WSL distribution, sharded) and `wsl` (the `--prefix` package layout, then `hi` into it from Git Bash) jobs, both green and called by ci.yml on every push                                          |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH`                    | ✅ as a target, ✅ as a client — the same code path as any ssh host                                                                                                                                                                                               | `.github/workflows/windows-e2e.yml` (target side) and `windows-client.yml` (client side), both called by ci.yml on every push                                                                                                                                                           |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell)                    | ⚠️ plain PowerShell session, no hi styling — a deliberate fallback, not a failure                                                                                                                                                                                 | `windows-e2e.yml`, the target-side half above                                                                                                                                                                                                                                           |
| \*BSD, Solaris/illumos                                           | ✅ FreeBSD, full session — BSD userland and a pkg bash, client half included; 🟡 the rest, which share that userland                                                                                                                                              | `.github/workflows/freebsd-e2e.yml` (fast suites plus a loopback session in a FreeBSD VM), called by ci.yml on every push                                                                                                                                                               |
| NAS appliances: Synology DSM, QNAP QTS                           | 🟡 full session expected — both ship `bash` beside a busybox `sh`, and busybox's `base64` and `mktemp` are the two the bootstrap needs; the login shell is `sh`, so hi picks `bash` itself. DSM wants the user-home service on, or there is no `$HOME` to land in | — the busybox-with-bash shape is Alpine's, which `ssh_test.sh` proves; nobody has run it on the appliance                                                                                                                                                                               |
| NAS distributions: TrueNAS SCALE, Unraid, TrueNAS CORE           | 🟡 full session expected — SCALE is Debian (the glibc row's own fixture), Unraid is Slackware with bash as its shell, CORE is FreeBSD with a bash in base                                                                                                         | the glibc and FreeBSD rows above; no appliance-specific run                                                                                                                                                                                                                             |
| OpenWrt (and other busybox routers)                              | ⚠️ aliases-only — busybox `ash`, no bash, `base64` and `mktemp` present; `opkg install bash` makes it a full session. `/tmp` is RAM, and 48KB a connect is fine there                                                                                             | 🟡 the same shape as Alpine's bash-less case in `ssh_test.sh`; not run on a router                                                                                                                                                                                                      |
| Termux (Android)                                                 | 🟡 as a **client**, bash and coreutils `base64` are there; install with `--no-link` (no `/usr/bin`) and put `hi.sh` on `$PATH` yourself. 🟡 as a target, over Termux's own `sshd` (port 8022): full session, bash is Termux's shell                               | — the [adb row](#targets-weighed-and-not-shipped) is the other direction and stays a no                                                                                                                                                                                                 |
| any of the above behind sshd `ForceCommand`, or a `command=` key | ⚠️ the host's own session — the forced program — after a line saying hi's bootstrap never ran; a forced program that exits non-zero and prints nothing gets the PowerShell notice instead                                                                         | `ssh_test.sh`'s two forced-command cases                                                                                                                                                                                                                                                |
| any of the above with an `rbash` login shell                     | ✅ full session — `sh` has no `/` in its name, so rbash runs the bootstrap unrestricted; not a boundary hi respects ([SECURITY.md](SECURITY.md#what-runs-where))                                                                                                  | `ssh_test.sh`'s rbash case                                                                                                                                                                                                                                                              |
| any of the above with `MaxSessions 1`                            | ✅ full session — the probe's channel closes before the session's opens                                                                                                                                                                                           | `ssh_test.sh`'s maxsessions1 case                                                                                                                                                                                                                                                       |

## The shell you end up in

| session shell                                    | result                                                                | note                                                                                                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash` ≥ 3.2                                     | ✅ full: header, prompt, git status, aliases, editor configs          | 3.2 is the floor because macOS still ships it                                                                                                     |
| `zsh`                                            | ✅ full                                                               | `common/zsh.zsh`                                                                                                                                  |
| `fish`                                           | ✅ full                                                               | `common/config.fish`                                                                                                                              |
| `sh`/`dash`/`ash` (no bash on the target)        | ⚠️ aliases and a colored `user@host` prompt, with a warning saying so | no header and no git segment - those need bash                                                                                                    |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | ❌ **decided against**, not pending                                   | see [Shells hi does not style](#shells-hi-does-not-style). You still get a session — hi lands you in the best of `$_HI_SHELL_TREE` the target has |
| PowerShell                                       | ❌                                                                    | bash-only by design                                                                                                                               |

**A shell framework loads normally on a target**: hi lands you in your own
login shell, which is what `_HI_SHELL_PREFERENCE`'s default (`login`, then
`fish zsh bash`) means. `tests/targets/framework_test.sh` covers nine — oh-my-zsh,
powerlevel10k, starship, bash-it, fzf, zoxide, direnv, atuin and mise — each
asserting no shell errors and the framework's own hook left intact: zsh's
array base unchanged, `PROMPT_COMMAND` chained rather than replaced, `bind -x`
bindings in place.

**On your own machine the prompt is the one thing that gives way** to a
detected framework - your prompt locally, hi's on every target. See
[SETTINGS.md](SETTINGS.md#others) for the detection rule.

## Targets weighed and not shipped

Everything weighed and left off the roster above. Each would need everything
in [What a "yes" costs](#what-a-yes-costs), and every row here is **❌
decided against** - none of it is pending.

| target                                                                                                    | why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `systemd-nspawn` / `machinectl`                                                                           | `machinectl shell` goes through systemd-machined, so it wants root or a polkit prompt on the host, and the few people who sit in an nspawn container long enough to want their aliases do not outweigh a fifth probe on every TAB for everyone else. The containers would be ideal targets; the audience fails the test                                                                                                                                                                                                                                                                                                                                       |
| WSL (`wsl -d <distro>`)                                                                                   | reachable only from a Windows client — and a WSL distribution is a machine you install say-hi _into_: the `.deb` installs into one unchanged, `/etc/profile.d/say-hi.sh` and all                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `crictl` / CRI-O                                                                                          | a node-level debugging tool, not a place people sit; the session you want is the pod, which the kubernetes row resolves. `tests/targets/kube_test.sh` uses `crictl` to preload images — about the right relationship to it                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Apptainer / Singularity                                                                                   | HPC containers are mostly run-to-completion jobs, so there is usually nothing to exec into; where there is, the culture is batch schedulers and `srun`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Proxmox `pct enter`                                                                                       | LXC underneath, reachable only from the PVE node as root — the lxc row below with a narrower door                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| FreeBSD jails (`jexec`), illumos zones (`zlogin`)                                                         | host-local and root-only: you ssh to the host first, where `hi` is already running. The transports are also unlike the container four — no unprivileged listing, no unprivileged liveness probe                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `chroot`                                                                                                  | no isolation worth the name, nothing to enumerate, root-only to enter, and hi's disposable tree lands inside the chroot anyway                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `adb shell` (Android), the closest call here                                                              | mechanically the best fit on this page: `adb shell`/`adb push`/`adb devices` map onto probe/cp/attach almost exactly, and the CLI is one static binary. The other end fails: Toybox with no bash and no package manager to get one, so every session lands in the aliases-only tier by construction, and `$HOME` is `/data/local/tmp` at best. hi would reach it and have almost nothing to do there                                                                                                                                                                                                                                                          |
| AWS ECS Exec (`aws ecs execute-command`)                                                                  | a real exec shape with a real audience, and a name hi cannot take: a task is a cluster/task/container triple, not one word. It also needs the Session Manager plugin beside the CLI, so `command -v aws` would not be honest about whether the backend works                                                                                                                                                                                                                                                                                                                                                                                                  |
| Slurm (`srun --pty bash`)                                                                                 | `srun` **allocates** rather than attaches: `hi <job>` would queue a job on a scheduler, which nothing else on this page does. The machine people want styled is the login node they submit from, already an ssh host                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Docker Swarm services, Azure Container Instances (`az container exec`), `systemd-run` / portable services | none has shown an audience that _sits_ in it: Swarm is largely superseded by the kubernetes row, ACI is run-a-container-and-go, `systemd-run` launches a unit rather than being a place to find one                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Talos Linux and other shell-less immutable distributions                                                  | no shell to style, by design: the node exposes an API, not a login, and `talosctl` has no exec-a-shell verb because there is no `/bin/sh`. Where such a node runs pods, the kubernetes row answers                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Serial consoles (`picocom`, `virsh console`), `telnet`                                                    | **no file transfer channel at all**, disqualifying as no other row is: hi's first move is landing `$_HI_PAYLOAD` on the far end, and a serial console offers nothing to land through short of typing base64 at a getty                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| WinRM / PowerShell Remoting                                                                               | the bash-only answer [the OS table](#the-targets-os) gives stock Windows OpenSSH: hi's payload is POSIX shell, which PowerShell can neither source nor run the fallback ladder for. Windows with Git Bash on `PATH` is the supported shape                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `lxc` / `incus` (and LXD)                                                                                 | the closest shape to a fit: a full system container running a real distro, and `lxc exec <name> -- <cmd>` is an ordinary probe/cp/attach triple. Two things decide it. **The suite could only ever skip:** every other backend suite stands its target up from a container image; LXD and Incus want a real daemon and a storage pool on the runner. **And the door is already open:** a system container people sit in is either running sshd, which the ssh row answers, or a machine you install say-hi _into_. That leaves a fifth fork on every `hi <target>` and every TAB, charged to everyone, to save an `~/.ssh/config` entry for those who have it |

Every one of these still works from the other side: ssh into the host and run
`hi` there if say-hi is installed, or accept the host's own shell.

## Shells hi does not style

Each would need its own rc in `common/` (prompt, aliases, completion) plus a
tier in the fallback ladder in `hi.sh`'s `_hi_remote_suffix` and `load.sh`'s
`load()`. Using one of these as a _login_ shell still works - only the
_session_ shell is limited, and every row below is **❌ decided against**.

| shell        | why                                                                                                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `elvish`     | its own language, so the prompt and aliases would be a second implementation to keep in sync forever, for an audience hi has no evidence of. A `common/rc.elv` is what it would take, and nobody has asked |
| `xonsh`      | Python — a third implementation, on elvish's terms                                                                                                                                                         |
| `tcsh`/`csh` | different rc syntax _and_ no `$ENV` equivalent, so there is no hook to land on: it would need its own rc and its own delivery mechanism                                                                    |
| `nushell`    | not POSIX, so it can source none of `common/`                                                                                                                                                              |
| `ksh`/`mksh` | they land in the `sh` tier like any bash-less shell — aliases and the colored prompt, no header. A ksh tier for a live git segment is not worth a second POSIX implementation                              |
| PowerShell   | not a POSIX shell; the greeting hi prints there is the whole extent of it                                                                                                                                  |

                                                                                        |

## What would change an answer

A "no" above is closed, not permanent, and the one thing that reopens it is
the same in every section: **evidence of people sitting in it**, enough to be
worth charging everyone who has never heard of it — a subshell on every
`hi <target>` for a target, a second prompt implementation to keep in sync
forever for a shell. A new exec CLI, a cleaner API or an easier integration
moves neither, because neither is a "no" for being hard — unless the CLI
speaks docker's grammar, in which case it is a word in `_HI_CONTAINER_CLIS`
and needs no answer here at all.

The useful shape of the argument: who is in these, how often, and what they do
today instead.

**Nothing is pending.** Every candidate anyone has raised is on a table above
with a verdict and a reason. Two proposals about hi itself were weighed and
declined without shipping: **persistent sessions on a target**
(`hi --session <name>`, a tree that outlives a dropped connection) — `tmux`
or `screen` on the client already survives a drop, and a tree that outlives
its session breaks [SECURITY.md](SECURITY.md#what-hi-writes-on-a-target)'s
footprint promise; and **a bash 4 floor for the client** — the 3.2 plumbing
is tested on both ends, and a split floor is two dialects in one tree. A runtime that appears here for the first time
is read against [What a "yes" costs](#what-a-yes-costs), and lands as a row
either way.
