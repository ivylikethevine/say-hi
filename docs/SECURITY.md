# Security Policy

The threat model for a tool people run against every host they touch, and how
to report what slipped through it.

## Contents

- [What hi does - and deliberately doesn't](#what-hi-does---and-deliberately-doesnt)
- [What runs where](#what-runs-where)
- [What hi writes on a target](#what-hi-writes-on-a-target)
- [Footprint and cleanup on the target](#footprint-and-cleanup-on-the-target)
- [Trust boundaries](#trust-boundaries)
  - [What a process started from a session inherits](#what-a-process-started-from-a-session-inherits)
- [Assurance case](#assurance-case)
- [Supported versions](#supported-versions)
- [Reporting a vulnerability](#reporting-a-vulnerability)
  - [What happens to a report](#what-happens-to-a-report)

## What hi does - and deliberately doesn't

- **No network calls of its own.** `hi` only execs the transports you already
  use (`ssh`, `docker exec`, `podman exec`, `nomad alloc exec`, `kubectl exec`)
  against a target you named. No telemetry, no update checks, no
  `curl`/`wget` in the shipped tree.
- **No `curl | bash`.** Installing is `git clone` plus `scripts/install.sh`, or
  a package built from that same script; the channels that are live are
  [PACKAGING.md](PACKAGING.md)'s first paragraph. `hi --update` is a
  release-tag checkout in a checkout you can read.
- **The payload is an allow list.** What goes over the wire is exactly
  `$_HI_PAYLOAD` at the top of `hi.sh` (`common settings load.sh hi.sh`) —
  docs, tests, CI, and editor config never leave the client; `hi.sh` is there so
  a session can say `hi` onward. Your overlay is a second, smaller allow list,
  `$_HI_OVERLAY_FILES` (the roster is in
  [CONTRIBUTING.md's contract](CONTRIBUTING.md#what-1x-will-not-break), read
  from `~/.config/say-hi/`); anything else in that directory stays on the
  client.
- **base64 is armor, not crypto.** It gets the payload through the target's
  login shell unmangled; confidentiality and integrity come entirely from the
  transport.
- **hi writes nothing on the target outside the session directory.** No login
  file, no history file, nothing under `$HOME`, under any setting -
  [What hi writes on a target](#what-hi-writes-on-a-target) is the whole list.
  The tools a session starts are their own writers: where a target has zoxide
  or atuin, their `init` runs by default, and each keeps its state under
  `$HOME` from then on ([the same section](#what-hi-writes-on-a-target) lists
  them, and the setting that keeps them unstarted).
- **The transport keeps its own voice.** hi does not redirect `ssh`'s stderr,
  so the server's `Banner`, the `Permanently added ... to the list of known
hosts` line and the host-key fingerprint on a first connection reach your
  terminal exactly as they would without hi. Capturing them would turn
  trust-on-first-use into accepting a fingerprint nobody was shown.
- **`hi --update` reads the tag's signature, and refuses only a bad one.**
  Tagged releases exist (`v0.1.0`, `v0.1.1`, … - see
  [Supported versions](#supported-versions)) and their tags are signed.
  `--update` runs `git verify-tag` on the tag it is about to check out and
  reads gpg's status lines rather than the exit code: a signature that does
  not verify (`BADSIG`, a revoked key) refuses the checkout; a good one is
  named with its signer; a key you have not imported, an unsigned tag (a
  fork, a mirror) or no `gpg` at all is said out loud and allowed, since
  refusing there would strand every first install that has not imported the
  key. The check therefore proves integrity only once the maintainer's key
  is in your keyring - [the package repository's key](PACKAGING.md#package-repository)
  is the same one. `--dry-run` reports the same verdict. A packaged install
  updates through its package manager, which has its own signing story.

## What runs where

`hi.sh` runs on the client: it parses arguments, picks the backend, tars and
armors the payload, and pipes it over the transport. On the target a single
`sh` unpacks it into a temp directory and chainloads `load.sh`, which prints
the header, writes the session's rc files into a scratch directory of its own,
and hands off to the best shell available. The target's login files are never
written; everything the target executes was generated on the client.

Three sshd shapes change that picture, and hi names each. A `ForceCommand` in
`sshd_config`, or a `command=` on the key in `authorized_keys`, runs its own
program whatever the client asked: hi's bootstrap never runs, and hi says so
and hands over the host's own session — the forced program, the only session
such a host offers — rather than reporting a success it never had. (A forced
program that exits non-zero and prints nothing is indistinguishable from a
host with no `sh`, and gets the PowerShell notice instead.) A restricted
login shell (`rbash`) forbids a `/` in a command name and little else; `sh`
has no slash, so hi's bootstrap runs unrestricted and the session is a full
one — rbash is not a boundary hi respects, and a host whose restriction
matters wants `ForceCommand`. And `MaxSessions 1` fits: hi's two calls share
one connection, but the probe's channel has closed before the session's
opens. All three are `tests/targets/ssh_test.sh` cases.

## What hi writes on a target

Default answer: one directory, and only for the life of the session.

| what              | where                                            | when                                                                                                 |
| ----------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| the session tree  | `mktemp -d`, mode 0700, `<user>.hi.XXXXXX`       | always                                                                                               |
| the ssh bootstrap | `mkdir -m 700` under the target's temp directory | ssh targets only, removed by the session it starts                                                   |

That is everything hi's own code writes. A session also starts a few
programs of its own accord where the target has them
([INTEGRATIONS.md](INTEGRATIONS.md)), and those write what they always do,
under the target's `$HOME`, and keep it after the session ends:

| tool                  | what it keeps, by default                                             | when                                                                              |
| --------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| zoxide                | its directory database, under `~/.local/share/zoxide/`                | every session on a target that has it, unless `_HI_DISABLE_TOOL_INIT=1`           |
| atuin                 | its history database, under `~/.local/share/atuin/`                   | the same                                                                          |
| starship, oh-my-posh  | starship's log files under `~/.cache/starship/`, oh-my-posh's cache under `~/.cache/oh-my-posh/` | only with `_HI_PROMPT_TOOL` set - off unless you set it |

Each tool's own settings on that target can move those paths.
`_HI_DISABLE_TOOL_INIT=1` and an unset `_HI_PROMPT_TOOL` together bring a
session back to the first table alone.

Your commands land in the target's own history file exactly as they would
over plain `ssh`, and the programs you run yourself - editors included -
write what they would there too; nothing hi ships touches the history file,
and hi's emacs config turns off emacs's backups, autosaves, and lock files.
`hi --doctor` prints any setting that is not at its default, so "what is this
install allowed to do to a target" is one command.

## Footprint and cleanup on the target

- `load.sh`'s own on-exit hook removes the whole disposable tree and the
  session-rc directory, on a clean exit and on an abrupt disconnect alike
  (`tests/targets/ssh_disconnect_test.sh` verifies the latter). The
  bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` is a narrower backstop for the
  one thing the hook cannot survive - bash killed by a signal nothing can
  trap - and only needs to remove the tree, since the session-rc directory
  lives inside it.
- The session tree is **not** added to `$PATH`; `hi` inside a session is an
  alias (`common/paths.sh`) instead. A `/tmp` path on `$PATH` is a finding on
  any host that is scanned for one.
- A say-hi installed on the target is neither read nor written by a session:
  every session runs out of the tree hi just unpacked, and removes that on the
  way out. Nothing hi does needs the installed tree to be writable by you, or
  to be at any fixed path.
  `tests/targets/install_methods_test.sh` drives one target per install method
  and asserts the install is still whole once the session is gone.
- On the client, `install.sh` validates your rc files with each shell's own
  syntax checker before touching them, and `--uninstall` removes exactly what
  install wrote.

## Trust boundaries

- hi's security model is the transport's. It adds no authentication, listens on
  nothing, and anyone positioned to intercept or control your ssh/container
  session could do so without hi in it.
- A malicious target gets what any interactive session gives it: your payload
  and a terminal. Treat every overlay file as public to every host you visit.
  Nothing a target sends back is executed on the client: the two strings hi
  reads back (the probe for an existing say-hi tree, and the bootstrap
  directory the target made) are only interpolated into the script sent back
  to that same target, and only if absolute and free of anything a
  double-quoted heredoc expands or closes on; else the session takes the
  disposable path. Escape sequences in session output remain possible, exactly
  as with plain `ssh`; hi's own connect-failure report prints a target's
  stderr as text, never expanding it, so a backslash sequence a target wrote
  stays one.
- **What hi writes on the client.** The rc lines and `settings.sh` the
  install asked about, a payload cache, and the ssh `ControlMaster` socket
  under a private runtime directory.
- A tool a session starts on a target runs under that target's own config for
  it, not yours: an atuin logged in to a sync server there syncs the
  session's history like any other shell's on that box.
- Backend dispatch trusts your local `~/.ssh/config` and your
  `docker`/`podman`/`nomad`/`kubectl` CLIs — the same ones you already run.
- The ssh `ControlMaster` socket lives at a name only this user's process can
  have made, never at a `mktemp -u` name in a shared temp directory:
  `ControlMaster=auto` _joins_ a socket it finds at the path it was given,
  and a name that was merely unused when printed is no guarantee about the
  moment it is used. Passed as `-o` on the command line, it also outranks a
  `ControlMaster no` in your `~/.ssh/config`. `scripts/doctor.sh`'s probe uses
  a fresh socket in a `mktemp -d` of its own, closed when the probe ends; a
  real connect instead reuses one, at a stable path under the same
  private runtime directory `hi <TAB>`'s own cache uses (below), named by a
  checksum of the target and your ssh options rather than either in the
  clear, and torn down only when idle for sixty seconds. Either way only this
  user's directory permissions and ssh's own authentication reach the socket.
- `hi <TAB>`'s target cache, and the reused-connection socket and
  payload/overlay cache above, are all written to `$XDG_RUNTIME_DIR`, or to a
  per-uid directory hi creates with `mkdir -m 700`. The name is predictable —
  the next `hi` has to find it — so if that path already exists and is not
  owned by you, or is a symlink, every one of them is skipped: completion
  falls back to sweeping the backends and a connect falls back to a fresh
  socket and a fresh build, all slower, and all correct.

### What a process started from a session inherits

`core.sh`'s `_HI_CHILD_ENV` roster, and nothing else with the prefix: the tree
and overlay pointers, the remote-session flag, the session rc directory, and the
completion knobs `targets.sh` reads from its environment. Everything else hi
sets — sixty-odd paths and toggles — stays a shell variable in the session
shell, so a service started by hand, a `sudo -E`, or a cron line pasted at the
prompt sees an ordinary environment. In particular the two values that name
your workstation (`_HI_LOCAL_USER`, `_HI_LOCAL_HOSTNAME`) are never in a
child's environment; a shell started inside the session reads them from hi's
own rc directory instead. The mechanism and the roster are
[HI.47](GLOSSARY.md#hi47-what-a-child-inherits); `tests/common/exports_test.sh`
pins both. The one tier this does not reach is a POSIX `sh` started inside a
session (and the bash-less fallback), where `$ENV` sources `paths.sh` again
and dash has no un-export.

## Assurance case

The argument that secure design principles were applied against the threat
model ([What hi does](#what-hi-does---and-deliberately-doesnt), [What runs
where](#what-runs-where)) and the [trust boundaries](#trust-boundaries) above
— not a claim that the tool is free of bugs.

| principle                                                 | how it holds                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Least privilege, minimal surface                          | hi adds no authentication of its own and listens on nothing - every check above is "no network calls of its own" or "trusts the transport you already run"                                                                                                                                                                                                                                         |
| Fail loud, fail closed                                    | every entry point runs under `set -euo pipefail` (`hi.sh:9`, `load.sh:29`, `common/core.sh:4`, `scripts/install.sh:12`), each with a documented re-disable where an error must not close an interactive shell                                                                                                                                                                                      |
| Untrusted input allowlisted, not sanitized after the fact | `_hi_safe_path` (`hi.sh:520`) checks the two strings a target hands back against an explicit `[bracket-class]` before either reaches a command run back on it; `_hi_ssh_host_tag`/`_hi_ssh_pattern_hit` skip an ssh-config token that isn't a hostname shape rather than evaluate it; `_hi_sanitize_var` (`common/core.sh:283`) strips control characters and backslashes from target-derived text |
| No secret ever needs to be in the payload                 | the payload is the allow list in [What hi does](#what-hi-does---and-deliberately-doesnt); credentials are handled by hand, outside CI ([CONTRIBUTING.md](CONTRIBUTING.md#when-a-push-is-refused)), with GitHub's push protection as backstop                                                                                                                                                       |

**What is not (yet) countered.** `hi --update` verifies the release tag's
signature only as far as your keyring allows
([What hi does](#what-hi-does---and-deliberately-doesnt)); importing the
maintainer's key is the manual step that turns its notice into a check. A
packaged install updates through its package manager instead, with its own
signing story ([PACKAGING.md](PACKAGING.md)).

Last reviewed 2026-09.

## Supported versions

No **1.0** release yet: the supported version is the tip of `main`, and
packages exist for the pre-1.0 versions a hand-pushed `v*` tag has built
([PACKAGING.md](PACKAGING.md)) - `v0.1.0` through the current tag today. Once
v1.0 is tagged, this becomes a version table with the latest release
supported; what a 1.x release keeps stable is
[CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break).

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Instead:

- report privately via
  [GitHub private vulnerability reporting](https://github.com/ivylikethevine/say-hi/security/advisories/new)

### What happens to a report

- **Acknowledgement within 14 days**, usually much sooner — this is a
  one-maintainer project, and the private report reaches that maintainer
  directly.
- **Coordinated disclosure.** A confirmed vulnerability is fixed before it is
  discussed publicly, unless the reporter and maintainer agree otherwise; the
  aim is a fix within 60 days of the report. Reporters are kept in the loop
  from acknowledgement to advisory.
- **Advisories are public.** Every fixed vulnerability gets a
  [GitHub Security Advisory](https://github.com/ivylikethevine/say-hi/security/advisories)
  naming the affected versions and the fix, and the fixing release's notes
  reference it. None have been reported to date.
- **Credit.** Reporters are credited in the advisory and the release notes
  unless they ask not to be.
