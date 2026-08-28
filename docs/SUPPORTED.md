# What hi supports, and how well

`hi <name>` resolves one name through a ladder — an ssh host first, then four
container backends — and lands you in the same styled session either way. This
file is every level of support that session has: what hi can reach, what it
does once it gets to a given OS, and which shell it hands you.

The reasoning for what is _not_ here — every runtime, shell, channel and
feature weighed and left off — is [UNSUPPORTED.md](UNSUPPORTED.md). A thing
missing from this page has a row over there.

**Legend:** ✅ exercised by a suite on every run · 🟡 expected to work, nobody
has proven it · ⚠️ works, reduced · ❌ not supported, see
[UNSUPPORTED.md](UNSUPPORTED.md).

## Contents

- [What a "yes" costs](#what-a-yes-costs)
- [The five that ship](#the-five-that-ship)
- [Already covered, without a row](#already-covered-without-a-row)
- [The target's OS](#the-targets-os)
- [The shell you end up in](#the-shell-you-end-up-in)

## What a "yes" costs

A backend is not one function. Adding one touches seven places:

- **a row in `_HI_BACKENDS`** (`hi.sh`) — `<name>|<what a target resolves
  as>|<liveness probe>|<predicate>`, walked by the dispatch and by
  `scripts/doctor.sh`.
- **a predicate**, beside `_hi_is_docker_container`: one `command -v` guard,
  one `[ "$(<query>)" = <literal> ]`, all stderr swallowed.
- **an arm in `_hi_container_cmds`**, filling `probe`/`cp`/`attach` — ask a
  question, stream a file in, hand over a session. Everything past that is
  backend-agnostic.
- **a lister, a `run_lister` case and the usage line** in `common/targets.sh`,
  in that file's standalone-POSIX dialect: the only file all three completions
  read and the only one fish can run.
- **a fifth copy of the roster in `common/header.sh`**, whose
  `_hi_probe_launch` hardcodes the backends on purpose — `hi.sh` is never
  sourced in a session, and sharing the list would cost payload bytes for
  something that changes about once a year. `tests/hi/parse_test.sh` greps the
  two against each other.
- **an e2e suite** in `tests/targets/`, registered in `test_runner.sh`'s
  `_HI_TESTS` table. A suite that can only ever skip is worth less than none.
- **a fixture that can stand the target up**, so far always a container image.

Then the part paid by everyone else: `_hi_resolve_backend` runs **every**
predicate on every `hi <target>`, and `common/targets.sh` probes **every**
backend on every TAB (GLOSSARY: HI.26), on machines that have none of the
runtime in question. The `command -v` guard short-circuits before the CLI
runs, so the marginal cost of a row is a fork rather than a daemon round-trip —
but a fork, five times per keystroke instead of four.

**A row earns a yes by being something people actually sit in, not by being
reachable.**

## The five that ship

| target       | what a name resolves as                                      | proven by                                                                                                                                   |
| ------------ | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| ssh host ✅   | a `Host` entry in `~/.ssh/config`, or any name ssh will take | `tests/targets/ssh_test.sh`, plus `ssh_disconnect_test.sh` (cleanup on an abrupt drop), `ssh_relay_test.sh` and `ssh_wire_test.sh` (bytes on the wire vs the printed size)                              |
| docker ✅     | a running container                                          | `tests/targets/docker_test.sh` - six shell environments (bash, bash interactive, zsh, fish, dash, busybox `sh`) plus the compose-alias case |
| podman ✅     | a running container                                          | `tests/targets/podman_test.sh`, the same six shell environments against podman's own image store                                            |
| nomad ✅      | a running allocation, or `alloc/task`                        | `tests/targets/nomad_test.sh`, against a real `nomad agent -dev`                                                                            |
| kubernetes ✅ | a running pod, `pod/container`, `ns:pod`, `ctx:ns:pod`       | `tests/targets/kube_test.sh`, against a real kind cluster                                                                                   |

ssh is checked first and short-circuits the roster, so a name that is both an
ssh host and a container name resolves as the ssh host.

## Already covered, without a row

These come up as requests, and every one already works.

| target                                                                              | why no row is needed                                                                                                                                                                                                                                                                                                                                                                                              |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **distrobox** and **toolbx**                                                        | they _are_ podman (or docker) containers, so the existing rows reach them by name. The wrinkle: they share your real `$HOME`, so hi's rc grafts land in the files your host shells read — what GLOSSARY HI.24's tree-exists guard exists for; [ALTERNATIVES.md](ALTERNATIVES.md#adjacent-tools-and-how-they-compose) has the full account                                                                         |
| **remote docker contexts**                                                          | the docker row shells out to whatever `docker` is on `$PATH`, so `docker context use` and `DOCKER_HOST` are transparent to hi                                                                                                                                                                                                                                                                                     |
| **AWS SSM `start-session`, `gcloud compute ssh`, `fly ssh console`, Azure Bastion** | anything that terminates in an OpenSSH connection is a `Host` entry away, usually a `ProxyCommand` one. hi's ssh path multiplexes two calls over a single `ControlMaster` (`_hi_ctl_open`), which is why mosh and Eternal Terminal cannot be ridden — but a `ProxyCommand` is still OpenSSH                                                                                                                       |
| **devcontainers / VS Code dev containers**                                          | docker containers, on the distrobox precedent. The name is the one docker gives them (`vsc-<project>-<hash>-uid`), not the one in `devcontainer.json`; they carry no `com.docker.compose.service` label, so they do not get the compose alias below. That is the view from _outside_; a devcontainer whose terminal you are already sitting in has no client to say `hi` from, and the [devcontainer Feature](PACKAGING.md#devcontainer-feature) installs say-hi inside the image for exactly that case                                                              |
| **`docker compose` services**                                                       | a compose service _is_ a docker container, so `hi myproject-web-1` always worked. `hi web` does too: `common/targets.sh`'s docker lister piggybacks the `com.docker.compose.service` label on the same `docker ps` call, and `hi.sh`'s docker predicate and exec commands (`_hi_compose_container`) resolve the alias by that label. Ambiguous (the same service in two projects) resolves to neither, on purpose |
| **`multipass`, Vagrant, Codespaces**                                                | all three end in a real OpenSSH connection — the AWS SSM row again. `vagrant ssh-config` and `gh codespace ssh --config` emit a paste-ready block; for multipass take the IP from `multipass info` and point `IdentityFile` at multipassd's key                                                                                                                                                                   |
| **Lima / Colima**                                                                   | the VM is an ssh target with a key Lima already made: `limactl show-ssh --format config <vm>` emits the `Host` block (Colima's VM is `limactl show-ssh colima`). Paste it into `~/.ssh/config` and `hi <vm>` is an ordinary ssh session                                                                                                                                                                           |
| **OrbStack**                                                                        | writes `~/.ssh/config` itself (`Include ~/.orbstack/ssh/config`), one `Host` per machine, so `hi <machine>` works the day OrbStack is installed; its containers are docker containers and take the docker row                                                                                                                                                                                                     |
| **Tailscale SSH, Teleport (`tsh`)**                                                 | both are OpenSSH underneath: Tailscale SSH is plain `ssh` to the node's tailnet name, and Teleport's `tsh config` emits a `ProxyCommand` block per cluster. The AWS SSM row again - still OpenSSH, so the two-call multiplex works                                                                                                                                                                                |

## The target's OS

Can hi land a session there at all?

| target OS                                     | result                                                                                                             | proven by                                                                                                                                                |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…)     | ✅ full session                                                                                                     | `tests/targets/ssh_test.sh`, on Debian bookworm                                                                                                          |
| Linux, musl + busybox (Alpine…)               | ✅ full session with `bash` installed, ⚠️ aliases-only without                                                      | `ssh_test.sh`, on Alpine 3.24                                                                                                                            |
| macOS                                         | ✅ full session — bash 3.2 is what it ships, and the suite runs a real bash 3.2 target, client half included        | `ssh_test.sh` bash-3.2 case, plus `.github/workflows/macos-e2e.yml`, which ci.yml calls on every push                                                    |
| WSL                                           | 🟡 it is Linux, and the `.deb` installs into it unchanged                                                           | —                                                                                                                                                        |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH` | ✅ as a target, 🟡 as a client — same code path as any ssh host either way, but only the target half is proven       | `.github/workflows/windows-e2e.yml` (target side), called by ci.yml on every push; `windows-client.yml` (client side) is called by ci.yml on every push too, but no run against current `dev` has gone green yet (docs/ROADMAP.md) |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell) | ⚠️ plain PowerShell session, no hi styling — the fallback is deliberate, not a failure                             | `windows-e2e.yml`, the target-side half above                                                                                                            |
| \*BSD, Solaris/illumos                        | ✅ FreeBSD, full session — BSD userland and a pkg bash, client half included; 🟡 the rest, which share that userland | `.github/workflows/freebsd-e2e.yml` (fast suites plus a loopback session in a FreeBSD VM), called by ci.yml on every push                                |

## The shell you end up in

| session shell                                    | result                                                                | note                                                                                                                                                            |
| ------------------------------------------------ | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash` ≥ 3.2                                     | ✅ full: header, prompt, git status, aliases, editor configs           | 3.2 is the floor because macOS still ships it                                                                                                                   |
| `zsh`                                            | ✅ full                                                                | `common/zsh.zsh`                                                                                                                                                |
| `fish`                                           | ✅ full                                                                | `common/config.fish`                                                                                                                                            |
| `sh`/`dash`/`ash` (no bash on the target)        | ⚠️ aliases and a colored `user@host` prompt, with a warning saying so | no header and no git segment - those need bash                                                                                                                  |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | ❌ **decided against**, not pending                                    | see [Shells hi does not style](UNSUPPORTED.md#shells-hi-does-not-style). You still get a session — hi lands you in the best of `$_HI_SHELL_TREE` the target has |
| PowerShell                                       | ❌                                                                     | bash-only by design                                                                                                                                             |

**If you use a shell framework**, hi lands you in your own login shell, so it
loads normally — that is what `_HI_SHELL_PREFERENCE`'s default (`login`, then
`fish zsh bash`) means. `tests/targets/framework_test.sh` tests nine of them —
oh-my-zsh, powerlevel10k, starship, bash-it, fzf, zoxide, direnv, atuin and
mise — each asserting the session comes up with no shell errors and that hi
left the framework's own hook intact: zsh's array base unchanged,
`PROMPT_COMMAND` chained rather than replaced, `bind -x` bindings in place.

**Both tables assume hi can reach the target in the first place**, which is
what [The five that ship](#the-five-that-ship) and [Already
covered](#already-covered-without-a-row) answer. Everything weighed and left
off that roster — LXC/Incus, `systemd-nspawn`, WSL, `nerdctl`, jails, zones
and the rest — is in [UNSUPPORTED.md](UNSUPPORTED.md).
