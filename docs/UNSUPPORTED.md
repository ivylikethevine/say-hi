# Decided against, and why

Every answer say-hi has given that was **no**, with the argument attached: the
runtimes it will not reach, the shells it will not style, the packaging
channels it does not publish, and the features it added and then removed. It
exists so nobody re-litigates a suggestion from scratch, and so anyone
outside the repo can tell whether their runtime was rejected or never
considered. What say-hi _does_ support is [SUPPORTED.md](SUPPORTED.md),
including [what a "yes" costs](SUPPORTED.md#what-a-yes-costs), the bar every row
here was read against.

**Legend:** ❌ decided against, not pending. Nothing on this page is open — see
[What would change an answer](#what-would-change-an-answer) for the one thing
that reopens a row.

## Contents

- [Targets weighed and not shipped](#targets-weighed-and-not-shipped)
- [Shells hi does not style](#shells-hi-does-not-style)
- [Packaging channels weighed and not shipped](#packaging-channels-weighed-and-not-shipped)
- [Features that were removed](#features-that-were-removed)
- [Changes proposed and not made](#changes-proposed-and-not-made)
- [What would change an answer](#what-would-change-an-answer)

## Targets weighed and not shipped

Each would need everything in [What a "yes" costs](SUPPORTED.md#what-a-yes-costs),
and each is a "no" for a reason of its own.

| target                                                                                                    | status                                       | why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `systemd-nspawn` / `machinectl`                                                                           | ❌ decided against                            | `machinectl shell` goes through systemd-machined, so it wants root or a polkit prompt on the host — and the people sitting in an nspawn container long enough to want their aliases there are few next to a fifth probe on every TAB for everyone else. The containers themselves would be ideal targets; the audience is what fails the test                                                                                                                                                                                                                                                                                                                                       |
| WSL (`wsl -d <distro>`)                                                                                   | ❌ decided against                            | reachable only from a Windows client, hi's least-proven tier — and a WSL distribution is a machine you install say-hi _into_: the `.deb` installs into one unchanged, `/etc/profile.d/say-hi.sh` and all                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `nerdctl` / containerd                                                                                    | ❌ decided against                            | the CLI is deliberately docker-compatible, so anyone who wants it can have it with `alias docker=nerdctl` before hi sees the name. The population with nerdctl and neither docker nor kubectl is not large enough to charge everyone a probe for                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `crictl` / CRI-O                                                                                          | ❌ decided against                            | a node-level debugging tool, not a place people sit; the thing you want a session in is the pod, which the kubernetes row resolves. `tests/targets/kube_test.sh` uses `crictl` internally to preload images, which is about the right relationship to it                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Apptainer / Singularity                                                                                   | ❌ decided against                            | HPC containers are run-to-completion jobs far more often than long-lived instances, so most of the time there is nothing to exec into; where there is, the surrounding culture is batch schedulers and `srun`                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Proxmox `pct enter`                                                                                       | ❌ decided against                            | LXC underneath, reachable only from the PVE node as root — the lxc row below with a narrower door                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| FreeBSD jails (`jexec`), illumos zones (`zlogin`)                                                         | ❌ decided against                            | host-local and root-only: you reach the host over ssh first, at which point `hi` is already running there. The transports are also unlike the container four — no unprivileged listing, no unprivileged liveness probe                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `chroot`                                                                                                  | ❌ decided against                            | no isolation worth the name, no way to enumerate what exists, root-only to enter, and hi's disposable tree lands inside the chroot anyway                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `adb shell` (Android)                                                                                     | ❌ decided against, and the closest call here | mechanically the best fit on this page: `adb shell`/`adb push`/`adb devices` map onto probe/cp/attach almost exactly, and the CLI is one static binary. What fails is the other end: Toybox with no bash and no package manager to get one, so every session lands in the aliases-only tier by construction, and `$HOME` is `/data/local/tmp` at best. hi would reach it and have almost nothing to do there                                                                                                                                                                                                                                                                        |
| AWS ECS Exec (`aws ecs execute-command`)                                                                  | ❌ decided against                            | a real exec shape with a real audience, and a name hi cannot take: a task is a cluster/task/container triple, not one word. It also needs the Session Manager plugin beside the CLI, so a `command -v aws` guard would not be honest about whether the backend works                                                                                                                                                                                                                                                                                                                                                                                                                |
| Slurm (`srun --pty bash`)                                                                                 | ❌ decided against                            | `srun` **allocates** rather than attaches: `hi <job>` would be queueing a job on a scheduler, which no other name on this page does. The machine people want styled is the login node they submit from, already an ordinary ssh host                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Docker Swarm services, Azure Container Instances (`az container exec`), `systemd-run` / portable services | ❌ decided against                            | listed so nobody has to re-ask. None has shown an audience that _sits_ in it: Swarm is largely superseded by the kubernetes row, ACI is run-a-container-and-go, `systemd-run` launches a unit rather than being a place to find one                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Talos Linux and other shell-less immutable distributions                                                  | ❌ decided against                            | there is no shell to style, by design — the node exposes an API, not a login, and `talosctl` has no exec-a-shell verb because there is no `/bin/sh`. Where such a node runs pods, the kubernetes row answers                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Serial consoles (`picocom`, `virsh console`), `telnet`                                                    | ❌ decided against                            | **no file transfer channel at all**, disqualifying in a way no other row is: hi's first move is landing `$_HI_PAYLOAD` on the far end, and a serial console gives it nothing to land through short of typing base64 at a getty                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| WinRM / PowerShell Remoting                                                                               | ❌ decided against                            | the same bash-only answer [the OS table](SUPPORTED.md#the-targets-os) gives for stock Windows OpenSSH. hi's payload is POSIX shell; PowerShell can neither source it nor run the fallback ladder. Windows with Git Bash on `PATH` is the supported shape                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `lxc` / `incus` (and LXD)                                                                                 | ❌ decided against                            | the closest shape to a fit: a full system container running a real distro, and `lxc exec <name> -- <cmd>` is an ordinary probe/cp/attach triple. Two things decide it. **The suite could only ever skip:** every other backend suite stands its target up from a container image, while LXD and Incus want a real daemon and a storage pool on the runner. **And the door is already open:** a system container people sit in is a container running sshd, which the ssh row answers, or a machine you install say-hi _into_. That leaves a fifth fork on every `hi <target>` and every TAB, charged to everyone without it, to save an `~/.ssh/config` entry for those who have it |

Every one of these still works from the other side: ssh into the host and run
`hi` there if say-hi is installed, or accept the host's own shell. A "no" here
is about hi's roster, not the machine.

## Shells hi does not style

Each would need its own rc in `common/` (prompt, aliases, completion) plus a
tier in the fallback ladder in `hi.sh`'s `_hi_remote_suffix` and `load.sh`'s
`load()`.

| shell        | status              | why                                                                                                                                                                                                                       |
| ------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `elvish`     | **decided against** | its own language, so the prompt and aliases would be a second implementation to keep in sync forever, for an audience hi has no evidence of. A `common/rc.elv` is what it would take, and nobody has asked                |
| `xonsh`      | **decided against** | Python — a third implementation, on the same terms as elvish                                                                                                                                                              |
| `tcsh`/`csh` | **decided against** | different rc syntax _and_ no `$ENV` equivalent, so there is no hook to land on: it would need its own rc and its own delivery mechanism                                                                                   |
| `nushell`    | **decided against** | Nu is not POSIX, so it can source none of `common/`                                                                                                                                                                       |
| `ksh`/`mksh` | **decided against** | they land in the `sh` tier like any other bash-less shell — aliases and the colored prompt, no header. A ksh-specific tier once existed for a live git segment and was removed as not worth a second POSIX implementation |
| PowerShell   | not a POSIX shell   | the greeting hi prints there is the whole extent of it                                                                                                                                                                    |

Using one of these as a _login_ shell still works — hi lands you in the best
of `$_HI_SHELL_TREE` the target has. Only the _session_ shell is limited.

## Packaging channels weighed and not shipped

**nix.** Looked at, and the answer for now is no — recorded because the build
shape was never the hard part.

The derivation is the Homebrew formula: `$out/share/say-hi` plus a wrapped
`$out/bin/hi` whose only job is `export _HI_HOME=$out/share`. It is the formula
and not `scripts/install.sh --prefix` for the reason [PACKAGING.md's
_Layout_](PACKAGING.md#layout) gives — `install_tree` hardcodes `/usr/bin` and
`/etc/profile.d`, and neither exists in a store path.

Two routes, not the same commitment. A `flake.nix` in this repo is publishable
with no external review (`nix run github:ivylikethevine/say-hi`), needs no
source hash, and teaches `bump.sh` nothing new. A nixpkgs submission is
discoverable from `environment.systemPackages`, where nix users actually look,
but is upstream review plus a standing maintainer entry and a fourth manifest
to checksum. **If it ships, it ships as a flake first.**

**The precondition, before either.** A nix derivation is a _third_ copy of
`_HI_PACKAGE_CONTENTS`, where `tests/packaging/packaging_test.sh` currently
guards one (the formula). The drift guard grows a case before anything is
published — a channel installing a stale file list is the failure this repo has
already designed against twice.

**The `/etc/profile.d` half has no store-path equivalent.** That snippet is how
a _new_ process reads `$_HI_HOME` with no tree to derive it from. On NixOS that
wants a module (`environment.etc`, or a `programs.say-hi` option), which is not
committed to; under home-manager the rc line `install.sh` writes covers it, and
the plain answer stays `install.sh --no-link`, which is what the formula's
`caveats` says today.

Two things would come free if revisited: nix builds are hermetic, so the
reproducibility [mkpkg.sh works for](PACKAGING.md#reproducibility) becomes a
property rather than a CI check, and a `checkPhase` running `--group fast`
would make the build itself a test.

## Features that were removed

Shipped, then taken back out — once a yes, which is why they are worth writing
down rather than leaving to `git log`.

**The tmux integration** (`hi --tmux`, `--no-tmux`, `_HI_TMUX_ATTACH`,
`_HI_TMUX_SESSION`, `_HI_DISABLE_TMUX` and `misc/tmux.conf`) was removed on
2026-08-21. It ran the session inside a named tmux on the target so a dropped
connection detached instead of losing the session — but only where say-hi was
**permanently installed**: on a disposable target the tree is deleted when the
session ends, so a detached tmux would have outlived what it was attached to,
and `_hi_tmux_wanted` refused rather than leave one pointing at nothing. That
restriction was never escapable from inside the feature, and the file cost
payload bytes on every session that never used it. Nothing stands in its
place: a dropped connection loses the session. The question is open again from
the other end, as
[FUTURE.md](FUTURE.md#persistent-sessions-on-a-disposable-target)'s _persistent
sessions on a disposable target_ entry.

**The rc graft** (`_HI_GRAFT_RC`, `load.sh`'s `configure_files`, the
`# hi-config-start`/`-end` block and the tree-exists guard around it) was
removed on 2026-08-29. Opt-in by then, it appended hi's rc to the **target's**
`~/.bashrc`, `~/.zshrc` and fish config for the session's duration, so that a
shell nothing typed — a tmux pane, an editor's terminal — came up styled.
Everything typed was already covered without it: the session rc directory
([GLOSSARY HI.46](GLOSSARY.md#hi46-session-rc-directory)) reaches zsh through
`$ZDOTDIR`, POSIX shells through `$ENV`, and bash and fish through a wrapper
alias. What remained was a write to a login file on a machine that is not
yours, twice per session, and a hazard class of its own — a block left behind
by a hard kill, two overlapping sessions stripping each other's, a distrobox
landing it in the host's own rc — for the one case of an untyped bash or fish
shell. hi now writes nothing to a target's login files under any setting; a
bash or fish shell spawned by tmux or an editor inside a session comes up as
the host's own.

**Scratch history** (`_HI_SCRATCH_HISTORY`, `common/history.sh`, fish's
`fish_postexec` log and `$_HI_TMPDIR`) was removed on 2026-08-29, the day the
rc graft went, for the same reason: the other opt-in that shipped off and
that `SECURITY.md` had to explain. Set, it pointed each shell's history at a
`mktemp -d` wiped on exit instead of the target's own history file - a
throwaway-box convenience whose default-off state was the only safe one, since
a session that erases the record of what it did is afterwards the same shape
as one that meant to. With it gone hi has no setting that ships off, no
`_HI_OPT_INS` roster, no inverted rows in the payload trim table, and touches
no shell's history under any configuration. Want it back for one box: `export
HISTFILE=$(mktemp -d)/h` in the overlay's `bash.sh` does the bash half in one
line.

**Three shell tiers existed briefly and were dropped**, each for the reason its
row above gives: `shells/tcsh.sh` (2026-08-09), `shells/config.nu`
(2026-08-18) and `shells/ksh.sh` (2026-08-21). The ksh one is the instructive
case — written for a live git segment, and removed on the decision that a
second POSIX implementation to keep in sync is not worth one segment.

## Changes proposed and not made

A change to something that already works, weighed and declined.

**Renaming the config directory** to `~/.say-hi-conf`, or anything outside the
XDG base, was decided against on 2026-08-24. The config lives at
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi` (`common/core.sh`) and stays there.

- **The override already does it.** `$_HI_CONFIG_DIR` is read before anything
  else and wins over the derivation, so `_HI_CONFIG_DIR=~/.say-hi-conf` gets
  exactly the asked-for path today, with no migration. A rename would take
  that choice away from everyone else to hand it to one person.
- **Discoverability is already answered.** `hi --help` names the path, and
  `hi --doctor` prints the _resolved_ one as a section heading.
- **A bare `~/.say-hi-conf` is strictly worse for the people it would affect
  most.** It drops spec compliance silently for anyone who has moved
  `$XDG_CONFIG_HOME`, and puts another dotdir in `$HOME`, which is what XDG
  exists to stop.
- **The cost is not the one-line derivation.** 33 files carry the literal path
  or the XDG base across 81 occurrences — the docs, `docs/hi.1`, the formula,
  the demo tapes and fixtures — plus a migration for every existing install,
  plus the suite's isolation trick (`tests/test_lib.sh` points
  `$XDG_CONFIG_HOME` at a scratch directory, and six suites depend on that).
- **No motivation was ever recorded.** The proposal entered the tree on
  2026-08-22 phrased as "something like `~/.say-hi-conf`", naming no problem
  the current path causes.

**What would reopen it:** a concrete failure of the XDG path — a platform where
it is wrong, or a collision with another tool — rather than a preference about
how it reads.

## What would change an answer

A "no" above is closed, not permanent — but the thing that reopens one is the
same in every section: **evidence of people sitting in it**, enough to be worth
charging everyone who has never heard of it. For a target that price is a fork
on every TAB; for a shell, a second implementation of the prompt to keep in
sync forever; for a channel, another copy of the file list to drift. A new
exec CLI, a cleaner API or an easier integration does not move any of these,
because none of them are "no" for being hard.

The useful shape of the argument: who is in these, how often, and what they do
today instead.

**Nothing is pending.** Every candidate anyone has raised is on a table above
with a verdict and a reason. A runtime that appears here for the first time
gets read against [What a "yes" costs](SUPPORTED.md#what-a-yes-costs), and lands
as a row either way.
