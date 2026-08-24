# Decided against, and why

Every answer say-hi has given that was **no**, with the argument attached: the
runtimes it will not reach, the shells it will not style, the packaging channels
it does not publish, and the features it used to have and took back out.

It exists because that reasoning lived nowhere. Every suggestion got
re-litigated from scratch, and nobody outside the repo could tell whether their
runtime had been rejected or simply never considered. What say-hi _does_ support,
and how well, is [SUPPORTED.md](SUPPORTED.md) - including
[what a "yes" costs](SUPPORTED.md#what-a-yes-costs), which is the bar every row
here was read against.

**Legend:** ❌ decided against, not pending. Nothing on this page is open, and
nothing is queued behind it - see [What would change an
answer](#what-would-change-an-answer) for the one thing that reopens a row.

## Contents

- [Targets weighed and not shipped](#targets-weighed-and-not-shipped)
- [Shells hi does not style](#shells-hi-does-not-style)
- [Packaging channels weighed and not shipped](#packaging-channels-weighed-and-not-shipped)
- [Features that were removed](#features-that-were-removed)
- [Changes proposed and not made](#changes-proposed-and-not-made)
- [What would change an answer](#what-would-change-an-answer)

## Targets weighed and not shipped

Each of these would need everything in [What a "yes" costs](SUPPORTED.md#what-a-yes-costs),
and each is a "no" for a reason of its own rather than by category.

| target | status | why |
| ------ | ------ | --- |
| `systemd-nspawn` / `machinectl` | ❌ decided against | `machinectl shell` goes through systemd-machined, so it wants root or a polkit prompt on the host - and the people sitting in an nspawn container long enough to want their aliases there are few next to a fifth probe on every TAB for everyone else. The containers themselves would be ideal targets (a full distro, systemd and bash already in them); the audience is what fails the test, not the shape |
| WSL (`wsl -d <distro>`) | ❌ decided against | reachable only from a Windows client, which is already hi's least-proven tier - and a WSL distribution is a machine you can install say-hi _into_ rather than reach for a session at a time: the `.deb` installs into one unchanged, `/etc/profile.d/say-hi.sh` and all. The permanent install is the better answer to the same want |
| `nerdctl` / containerd | ❌ decided against | the CLI is deliberately docker-compatible, which cuts both ways: it means the integration would be trivial, and it means anyone who wants it can have it with `alias docker=nerdctl` before hi ever sees the name. The population with nerdctl and neither docker nor kubectl is not large enough to charge everyone a probe for |
| `crictl` / CRI-O | ❌ decided against | a node-level debugging tool, not a place people sit - it talks to the CRI socket on one node, and the thing you actually want a session in is the pod, which the kubernetes row already resolves. `tests/targets/kube_test.sh` uses `crictl` internally to preload images, which is about the right relationship to it |
| Apptainer / Singularity | ❌ decided against | HPC containers are run-to-completion jobs far more often than long-lived instances, so most of the time there is nothing to exec into. Where there is an instance, the surrounding culture is batch schedulers and `srun`, not an interactive shell you would want styled |
| Proxmox `pct enter` | ❌ decided against | LXC underneath, and only reachable from the PVE node itself as root - so it is the lxc row below with a narrower door, and closed for the same reasons |
| FreeBSD jails (`jexec`), illumos zones (`zlogin`) | ❌ decided against | both are host-local and root-only: you reach the host over ssh first, at which point the jail or zone is a local concern and `hi` is already running there. The transports are also genuinely unlike the container four - no listing that does not need privileges, nothing that answers a liveness probe unprivileged |
| `chroot` | ❌ decided against | no isolation worth the name, no way to enumerate what exists, root-only to enter, and hi's disposable tree lands inside the chroot anyway. There is no question here that a session answers |
| `adb shell` (Android) | ❌ decided against, and the closest call here | mechanically it is the best fit on this page: `adb shell`/`adb push`/`adb devices` map onto the probe/cp/attach triple almost exactly, and the CLI is one static binary on every platform hi runs on. What fails is the other end. Android's shell is Toybox with no bash and no package manager to get one, so every session lands in the aliases-only tier by construction; `$HOME` is `/data/local/tmp` at best, which is not a home directory in the sense every rc graft in `common/` assumes. hi would reach it and then have almost nothing to do there |
| AWS ECS Exec (`aws ecs execute-command`) | ❌ decided against | a real exec shape with a real audience, and a name hi cannot take: a task is a cluster/task/container triple, not one word, so `hi <name>` has nothing to resolve. Worse than nomad's `alloc/task` split, which at least starts from a unique ID. It also needs the Session Manager plugin installed beside the CLI, so the `command -v aws` guard would not even be honest about whether the backend works |
| Slurm (`srun --pty bash`) | ❌ decided against | `srun` **allocates** rather than attaches: `hi <job>` would be queueing a job on a scheduler, which is not what any other name on this page does and not what anyone types `hi` expecting. The machine people actually want styled is the login node they submit from, and that is already an ordinary ssh host |
| Docker Swarm services, Azure Container Instances (`az container exec`), `systemd-run` / portable services | ❌ decided against | listed so nobody has to re-ask. None of the three has shown an audience that _sits_ in it: Swarm is largely superseded by the kubernetes row, ACI is a run-a-container-and-go product, and `systemd-run` is a way to launch a unit rather than a place to find one. Each would still cost every machine without it a fork on every TAB |
| Talos Linux and other shell-less immutable distributions | ❌ decided against | there is no shell to style, by design - the node exposes an API, not a login. `talosctl` has no exec-a-shell verb because there is no `/bin/sh` for one to reach. Where such a node runs pods, the kubernetes row already answers; the node itself is not a target any tool can make into one |
| Serial consoles (`picocom`, `virsh console`), `telnet` | ❌ decided against | **there is no file transfer channel at all**, which is disqualifying in a way none of the other rows are. Every other "no" here is about audience; this one is about mechanism - hi's whole first move is landing `$_HI_PAYLOAD` on the far end, and a serial console gives it nothing to land through short of typing base64 at a getty. A session hi cannot deliver its tree to is not a session hi can style |
| WinRM / PowerShell Remoting | ❌ decided against | the same bash-only answer [the OS table](SUPPORTED.md#the-targets-os) already gives for stock Windows OpenSSH. hi's payload is POSIX shell; PowerShell can neither source it nor run the fallback ladder. Windows with Git Bash on `PATH` is the supported shape, and it is an ordinary ssh target |
| `lxc` / `incus` (and LXD) | ❌ decided against | the closest thing here to a shape that fits: an LXC container is normally a full system container running a real distro, so it would land in the top tier of the fallback ladder rather than the aliases-only one, and `lxc exec <name> -- <cmd>` (Incus ships the same arguments) is an ordinary probe/cp/attach triple. Two things decide it anyway. **The suite could only ever skip:** every other backend suite stands its target up from a container image, while LXD and Incus want a real daemon and a storage pool on the runner - a change to the self-hosted box rather than a Dockerfile - and a backend proven by a suite that never runs is not proven. **And the door is already open:** a system container that people sit in is a container running sshd, which the ssh row answers today, or a machine you install say-hi _into_, the same answer the WSL row gives. That leaves a fifth fork on every `hi <target>` and every TAB, charged to everyone without it, to save an `~/.ssh/config` entry for those who have it |

Every one of these still works the way it always did, from the other side: ssh
into the host and run `hi` there if say-hi is installed, or accept the host's
own shell. A "no" here is about hi's roster, not about the machine.

## Shells hi does not style

These are settled the same way the targets above are. Each would need its own rc
in `shells/` (prompt, aliases, completion) plus a tier in the fallback ladder in
`hi.sh`'s `_hi_remote_suffix` and `load.sh`'s `load()`.

| shell        | status                          | why                                                                                                                                                                                                                                                                                                                                                                  |
| ------------ | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `elvish`     | **decided against**             | its own language, so the prompt and aliases would be a second implementation to keep in sync forever, for an audience hi has no evidence of. A `shells/rc.elv` is what it would take, and nobody has asked                                                                                                                                                           |
| `xonsh`      | **decided against**             | Python — a third implementation, on the same terms as elvish and with the same answer                                                                                                                                                                                                                                                                                |
| `tcsh`/`csh` | **decided against**             | different rc syntax _and_ no `$ENV` equivalent, so there is no hook to land on at all: it would need its own rc and its own delivery mechanism                                                                                                                                                                                                                       |
| `nushell`    | **decided against**             | Nu is not POSIX, so it can source none of `common/`                                                                                                                                                                                                                                                                                                                  |
| `ksh`/`mksh` | **decided against**             | they land in the `sh` tier like any other bash-less shell - aliases and the colored prompt, no header. A ksh-specific tier once existed for the sake of a live git segment; it was removed as not worth a second POSIX implementation to keep in sync                                                                                                                |
| PowerShell   | not a POSIX shell               | the greeting hi prints there is the whole extent of it                                                                                                                                                                                                                                                                                                               |

Using one of these as a _login_ shell still works, and always did — hi lands
you in the best of `$_HI_SHELL_TREE` the target actually has. Only the
_session_ shell is limited, and only for the shells in that table.

## Packaging channels weighed and not shipped

**nix.** Looked at, and the answer for now is no — recorded here rather than
left as an open question, because the build shape was never the hard part.

The derivation is the Homebrew formula: `$out/share/say-hi` plus a wrapped
`$out/bin/hi` whose only job is `export _HI_HOME=$out/share`. It is the formula
and not `scripts/install.sh --prefix` for the reason [PACKAGING.md's _Layout_](PACKAGING.md#layout) already
gives — `install_tree` hardcodes `/usr/bin` and `/etc/profile.d`, and neither
exists in a store path.

Two routes, and they are not the same commitment. A `flake.nix` in this repo is
publishable with no external review: `nix run github:ivylikethevine/say-hi`
works the moment it lands, and a flake on the repo itself needs no source hash,
so `bump.sh` learns nothing new. A nixpkgs submission is discoverable from
`environment.systemPackages`, which is where nix users actually look, but it is
upstream review plus a standing maintainer entry, and `bump.sh` grows a fourth
manifest to checksum. **If it ships, it ships as a flake first.**

**The precondition, before either.** A nix derivation is a _third_ copy of
`_HI_PACKAGE_CONTENTS`, where `tests/packaging/packaging_test.sh` currently
guards exactly one (the formula). The drift guard grows a case before anything
is published, not after — a channel installing a stale file list is the failure
this repo has already designed against twice.

**The `/etc/profile.d` half has no store-path equivalent.** That snippet is how
a _new_ process — a login shell, tmux's `update-environment`, another machine's
`hi` probing this one — reads `$_HI_HOME` with no tree to derive it from. On
NixOS that wants a module (`environment.etc`, or a `programs.say-hi` option),
which is not committed to; under home-manager the rc line `install.sh` writes
already covers it, and the plain answer stays `install.sh --no-link`, which is
what the formula's `caveats` says today.

Two things would come free and are worth remembering if this is revisited: nix
builds are hermetic, so the reproducibility [mkpkg.sh works
for](PACKAGING.md#reproducibility) becomes a property rather than a CI check, and a
`checkPhase` running `--group fast` would make the build itself a test.

## Features that were removed

Shipped, then taken back out. Unlike every other section here, these were once a
yes - which is why they are worth writing down rather than leaving to
`git log`.

**The tmux integration** (`hi --tmux`, `--no-tmux`, `_HI_TMUX_ATTACH`,
`_HI_TMUX_SESSION`, `_HI_DISABLE_TMUX` and `misc/tmux.conf`) was removed on
2026-08-21. It ran the session inside a named tmux on the target so a dropped
connection detached instead of losing the session - but only where say-hi was
**permanently installed**: on a disposable target the tree is deleted when the
session ends, so a detached tmux would have outlived the thing it was attached
to, and `_hi_tmux_wanted` refused rather than leave one pointing at nothing.
That restriction was never escapable from inside the feature, and the file it
shipped cost payload bytes on every session that never used it.

Nothing stands in its place today: a dropped connection loses the session. The
question is open again from the other end, as [ROADMAP.md](ROADMAP.md#large)'s
_persistent sessions on a disposable target_ entry - which has to answer the
multiplexer question itself rather than inherit an answer.

**Three shell tiers existed briefly and were dropped**, each for the reason its
row above gives: `shells/tcsh.sh` (2026-08-09), `shells/config.nu` (2026-08-18)
and `shells/ksh.sh` (2026-08-21). The ksh one is the instructive case - it was
written for the sake of a live git segment, and removing it was the decision
that a second POSIX implementation to keep in sync is not worth one segment.

## Changes proposed and not made

Not a runtime, a shell or a channel - a change to something that already works,
weighed and declined. Same rule as every section above: the reasoning is here so
it is not re-derived from scratch next time.

**Renaming the config directory** to `~/.say-hi-conf`, or anything else outside
the XDG base, was decided against on 2026-08-24. The config lives at
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi` (`common/core.sh`) and stays there.

- **The override already does it.** `$_HI_CONFIG_DIR` is read before anything
  else and wins over the derivation, so `_HI_CONFIG_DIR=~/.say-hi-conf` gets
  exactly the asked-for path today, with no code change and no migration. A
  rename would take that choice away from everyone else to hand it to one
  person - the opposite of what an override is for.
- **Discoverability, the likeliest motive, is already answered.** `hi --help`
  names the path, and `hi --doctor` prints the _resolved_ one as a section
  heading, so a user who has moved `$XDG_CONFIG_HOME` still gets told where
  their own config is rather than where the default would be.
- **A bare `~/.say-hi-conf` is strictly worse for the people it would affect
  most.** It drops spec compliance silently for anyone who has moved
  `$XDG_CONFIG_HOME` - their config would stop being read with no error - and
  it puts another dotdir in `$HOME`, which is the thing XDG exists to stop.
- **The cost is not the one-line derivation.** 29 files carry the literal path
  or the XDG base, across 57 occurrences - the docs, `docs/hi.1`,
  `packaging/homebrew/say-hi.rb`, the demo tapes and fixtures - plus a
  migration for every existing install, plus the suite's isolation trick, where
  `tests/test_lib.sh` points `$XDG_CONFIG_HOME` at a scratch directory and
  derives `$_HI_CONFIG_DIR` from it and six suites depend on that shape.
- **No motivation was ever recorded.** The proposal entered the tree on
  2026-08-22 phrased as "something like `~/.say-hi-conf`", and nothing before or
  after it names a problem the current path causes.

**What would reopen it:** a concrete failure of the XDG path - a platform where
it is wrong, or a collision with another tool - rather than a preference about
how it reads. The general clause below applies otherwise.

## What would change an answer

A "no" above is closed, not permanent - but the thing that would reopen one is
specific, and it is the same thing in every section: **evidence of people
sitting in it**, enough to be worth charging everyone who has never heard of it.
For a target that price is a fork on every TAB; for a shell it is a second
implementation of the prompt to keep in sync forever; for a channel it is
another copy of the file list to drift. A new exec CLI, a cleaner API or an
easier integration does not move any of these, because none of them are "no"
for being hard.

If you want one reconsidered, the useful shape of the argument is: who is in
these, how often, and what they do today instead.

**Nothing is pending.** Every candidate anyone has raised is on a table above
with a verdict and a reason - there is no open row and no queue behind this
file. A runtime that appears here for the first time gets read against the bar
in [What a "yes" costs](SUPPORTED.md#what-a-yes-costs), and lands as a row either way.
