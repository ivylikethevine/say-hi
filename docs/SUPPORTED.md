# What hi supports, and how well

`hi <name>` resolves one name through a ladder - an ssh host first, then four
container backends - and lands you in the same styled session either way. This
file is every level of support that session has: what hi can reach, what it does
once it gets to a given OS, and which shell it hands you when it lands.

The reasoning for what is _not_ here - every runtime, shell, channel and feature
weighed and left off, each with the argument against it - is
[UNSUPPORTED.md](UNSUPPORTED.md). A thing missing from this page is not an
oversight; it has a row over there.

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

A backend is not one function. Adding one touches seven places, and the last
two are the ones that decide most of the verdicts below:

- **a row in `_HI_BACKENDS`** (`hi.sh`) - `<name>|<what a target resolves
as>|<liveness probe>|<predicate>`. One list, walked by the dispatch and by
  `scripts/doctor.sh`, so a row reaches `hi --doctor` at the same moment it
  reaches `hi`.
- **a predicate**, beside `_hi_is_docker_container`: one `command -v` guard,
  one `[ "$(<query>)" = <literal> ]`, all stderr swallowed.
- **an arm in `_hi_container_cmds`**, filling `probe`/`cp`/`attach` - ask a
  question, stream a file in, hand over a session. Everything past that point
  is backend-agnostic.
- **a lister, a `run_lister` case and the usage line** in `common/targets.sh`,
  written in that file's standalone-POSIX dialect: it is the only file all
  three completions read and the only one fish can run.
- **a fifth copy of the roster in `common/header.sh`**, whose `_hi_probe_launch`
  hardcodes the backends on purpose - `hi.sh` is never sourced in a session,
  and sharing the list would cost the ssh payload bytes for something that
  changes about once a year. `tests/hi/parse_test.sh` greps the two against
  each other so the copy cannot drift.
- **an e2e suite** in `tests/targets/`, registered in `test_runner.sh`'s
  `_HI_TESTS` table. A suite that can only ever skip is worth less than no
  suite.
- **a fixture that can stand the target up**, which for every backend so far
  has meant a container image.

Then the part that is paid by everyone else. `_hi_resolve_backend` runs
**every** predicate, in parallel, on every `hi <target>`; `common/targets.sh`
probes **every** backend on every TAB after `hi` and a space
(GLOSSARY: HI.26). Both costs land on machines that have none of the runtime
in question. The `command -v` guard inside each predicate short-circuits
before the CLI is executed, so the
marginal cost of a row is a fork rather than a daemon round-trip - but it is
still a fork, five times per keystroke instead of four.

That is the test a candidate has to pass: **a row earns a yes by being
something people actually sit in, not by being reachable.**

## The five that ship

| target        | what a name resolves as                                      | proven by                                                                                                      |
| ------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| ssh host ✅   | a `Host` entry in `~/.ssh/config`, or any name ssh will take | `tests/targets/ssh_test.sh`, plus `ssh_disconnect_test.sh` (cleanup on an abrupt drop) and `ssh_relay_test.sh` |
| docker ✅     | a running container                                          | `tests/targets/docker_test.sh` - six cases across bash, zsh, fish, dash and busybox `sh`                       |
| podman ✅     | a running container                                          | `tests/targets/podman_test.sh`, the same six against podman's own image store                                  |
| nomad ✅      | a running allocation, or `alloc/task`                        | `tests/targets/nomad_test.sh`, against a real `nomad agent -dev`                                               |
| kubernetes ✅ | a running pod, or `pod/container`                            | `tests/targets/kube_test.sh`, against a real kind cluster                                                      |

ssh is checked first and short-circuits the roster entirely, which is why a
name that is both an ssh host and a container name resolves as the ssh host.

## Already covered, without a row

These come up as requests, and every one of them already works. They need
collecting, not deciding.

| target                                                                              | why no row is needed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **distrobox** and **toolbx**                                                        | they _are_ podman (or docker) containers, so the existing rows reach them by name today. The wrinkle worth knowing is not the transport: these share your real `$HOME`, so hi's rc grafts land in the same files your host shells read. That is what GLOSSARY HI.24's tree-exists guard exists for, and [ALTERNATIVES.md](ALTERNATIVES.md#adjacent-tools-and-how-they-compose) has the full account                                                                                                                                                                  |
| **remote docker contexts**                                                          | the docker row shells out to whatever `docker` is on `$PATH`, so `docker context use` and `DOCKER_HOST` are transparent to hi - the daemon being on another machine changes nothing it looks at                                                                                                                                                                                                                                                                                                                                                                      |
| **AWS SSM `start-session`, `gcloud compute ssh`, `fly ssh console`, Azure Bastion** | anything that terminates in an OpenSSH connection is a `Host` entry away from being an ordinary ssh target, usually a `ProxyCommand` one. The constraint to know is that hi's ssh path multiplexes two calls over a single `ControlMaster` (`_hi_ctl_open`), which is exactly why mosh and Eternal Terminal cannot be ridden - but a `ProxyCommand` is still OpenSSH, so it can                                                                                                                                                                                      |
| **devcontainers / VS Code dev containers**                                          | they are docker containers, on exactly the distrobox precedent, so the docker row finds them by name today. The name is the one docker gives them (`vsc-<project>-<hash>-uid`), not the one in `devcontainer.json` - which is the ergonomic wrinkle the `docker compose` row below answers, and devcontainers do not carry a `com.docker.compose.service` label, so they do not get the same alias                                                                                                                                                                   |
| **`docker compose` services**                                                       | a compose service _is_ a docker container, so `hi myproject-web-1` always worked. `hi web` now does too: `common/targets.sh`'s docker lister piggybacks the `com.docker.compose.service` label on the same `docker ps` call rather than a second one, and `hi.sh`'s docker predicate and exec commands (`_hi_compose_container`) resolve the alias back to its real container - by that label, not by `docker compose ps`, which needs a project directory this never has. Ambiguous (the same service name running in two projects) resolves to neither, on purpose |
| **`multipass`, Vagrant, Codespaces**                                                | all three end in a real OpenSSH connection, so they are the AWS SSM row again: a `Host` entry away. Vagrant and Codespaces will write it for you - `vagrant ssh-config` and `gh codespace ssh --config` both emit a paste-ready block. Multipass is the manual one: take the IP from `multipass info` and point `IdentityFile` at multipassd's own key                                                                                                                                                                                                               |

## The target's OS

Can hi land a session there at all?

| target OS                                     | result                                                                                                         | proven by                                                                                                                                                |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…)     | ✅ full session                                                                                                | `tests/targets/ssh_test.sh`, on Debian bookworm                                                                                                          |
| Linux, musl + busybox (Alpine…)               | ✅ full session with `bash` installed, ⚠️ aliases-only without                                                 | `ssh_test.sh`, on Alpine 3.24                                                                                                                            |
| macOS                                         | ✅ full session — bash 3.2 is what it ships, and the suite runs a real bash 3.2 target, client half included   | `ssh_test.sh` bash-3.2 case, plus `.github/workflows/macos-e2e.yml`, which ci.yml calls on every push                                                    |
| WSL                                           | 🟡 it is Linux, and the `.deb` installs into it unchanged                                                      | —                                                                                                                                                        |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH` | ✅ as a target, 🟡 as a client — same code path as any ssh host either way, but only the target half is proven | `.github/workflows/windows-e2e.yml` (target side), called by ci.yml on every push; `windows-client.yml` (client side) is written and still dispatch-only |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell) | ⚠️ plain PowerShell session, no hi styling — the fallback is deliberate, not a failure                         | `windows-e2e.yml`, the target-side half above                                                                                                            |
| \*BSD, Solaris/illumos                        | 🟡 nothing in hi is Linux-specific past the header's `/proc` probes, which degrade to `?`                      | —                                                                                                                                                        |

## The shell you end up in

What hi hands you once it is on the target.

| session shell                                    | result                                                                | note                                                                                                                                                            |
| ------------------------------------------------ | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash` ≥ 3.2                                     | ✅ full: header, prompt, git status, aliases, editor configs          | 3.2 is the floor because macOS still ships it                                                                                                                   |
| `zsh`                                            | ✅ full                                                               | `shells/zsh.zsh`                                                                                                                                                |
| `fish`                                           | ✅ full                                                               | `shells/config.fish`                                                                                                                                            |
| `sh`/`dash`/`ash` (no bash on the target)        | ⚠️ aliases and a colored `user@host` prompt, with a warning saying so | no header and no git segment - those need bash                                                                                                                  |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | ❌ **decided against**, not pending                                   | see [Shells hi does not style](UNSUPPORTED.md#shells-hi-does-not-style). You still get a session — hi lands you in the best of `$_HI_SHELL_TREE` the target has |
| PowerShell                                       | ❌                                                                    | bash-only by design                                                                                                                                             |

**If you use a shell framework**, hi lands you in your own login shell, so it
loads normally — that is what `_HI_SHELL_PREFERENCE`'s default (`login`, then
the styled head of `$_HI_SHELL_TREE`: `fish zsh bash`) means.
`tests/targets/framework_test.sh` tests nine of them against hi — oh-my-zsh,
powerlevel10k, starship, bash-it, fzf, zoxide, direnv, atuin and mise — each
asserting the session comes up with no shell errors and that hi left the
framework's own hook intact: zsh's array base unchanged under oh-my-zsh and
powerlevel10k, `PROMPT_COMMAND` still chained rather than replaced for the
bash prompt frameworks, and the `bind -x` key bindings and `PROMPT_COMMAND`
hooks the rest install still in place.

**Both tables above assume hi can reach the target in the first place**, which
is what [The five that ship](#the-five-that-ship) and [Already
covered](#already-covered-without-a-row) answer. Everything weighed and left off
that roster - LXC/Incus, `systemd-nspawn`, WSL, `nerdctl`, jails, zones and the
rest - is in [UNSUPPORTED.md](UNSUPPORTED.md).
