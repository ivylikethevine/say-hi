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
  a package built from that same script
  ([PACKAGING.md's _Install channels_](PACKAGING.md#install-channels)).
  `hi --update` is a release-tag checkout in a checkout you can read.
- **The payload is an allow list.** What goes over the wire is exactly
  `$_HI_PAYLOAD` at the top of `hi.sh` (`common config load.sh hi.sh`, the
  last so a session can say `hi` onward) — docs, tests, CI, and editor config
  never leave the client. Your overlay is a second, smaller allow list,
  `$_HI_OVERLAY_FILES` (the roster is
  [CONTRIBUTING.md's contract](CONTRIBUTING.md#what-1x-will-not-break)); nothing
  else in `~/.config/say-hi/` leaves the client.
- **base64 is armor, not crypto.** It gets the payload through the target's
  login shell unmangled; confidentiality and integrity come entirely from the
  transport.
- **hi writes nothing on the target outside its own temp directories.** No
  login file, no history file, nothing under `$HOME`, under any setting -
  [What hi writes on a target](#what-hi-writes-on-a-target) is the whole list,
  and names what a prompt program or your own per-shell files write on their
  own account.
- **The transport keeps its own voice.** hi does not redirect `ssh`'s stderr,
  so the server's `Banner`, the `Permanently added ... to the list of known
hosts` line and the host-key fingerprint on a first connection reach your
  terminal exactly as they would without hi. Capturing them would turn
  trust-on-first-use into accepting a fingerprint nobody was shown.
- **`hi --update` reads the tag's signature before checking it out**, from
  `git verify-tag`'s output rather than its exit code, SSH signatures checked
  against the checkout's own `.github/allowed_signers`: a failing signature
  (gpg or ssh, or a revoked gpg key) refuses the checkout, a good one is named
  with its signer, and a key nobody lists, an unsigned tag (a fork, a mirror),
  or no `gpg` is said out loud and allowed, since refusing there would strand
  every first install. `--dry-run` reports the same verdict.

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
and hands over the host's own session - the only one such a host offers -
rather than report a success it never had. (A forced program that exits
non-zero and prints nothing is indistinguishable from a host with no `sh`, and
gets the PowerShell notice instead.) A restricted login shell (`rbash`)
forbids a `/` in a command name and little else; `sh` has no slash, so hi's
bootstrap runs unrestricted - rbash is not a boundary hi respects, and a host
whose restriction matters wants `ForceCommand`. `MaxSessions 1` fits: hi's two
calls share one connection, but the probe's channel closes before the
session's opens. All three are `tests/targets/ssh_test.sh` cases.

## What hi writes on a target

Default answer: one directory (two over ssh), and only for the life of the session.

| what              | where, in the target's temp directory, mode 0700                                             | when                                                               |
| ----------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| the session tree  | `mktemp -d` `<user>.hi.XXXXXX` over ssh; `mkdir -m 700` `<user>.hi.log.<pid>` in a container | every session but `--plain`                                        |
| the ssh bootstrap | `mktemp -d` `hi.boot.XXXXXX`                                                                 | ssh only, removed by the same remote command once the session ends |

That is everything hi's own code writes. A prompt program drawing the prompt
([INTEGRATIONS.md](INTEGRATIONS.md#prompt-programs)) - by default, one you
have installed at home and the target has too - writes what it always does,
under the target's `$HOME`, and keeps it after the session ends:

| tool                 | what it keeps, by default                                                                        | when                     |
| -------------------- | ------------------------------------------------------------------------------------------------ | ------------------------ |
| starship, oh-my-posh | starship's log files under `~/.cache/starship/`, oh-my-posh's cache under `~/.cache/oh-my-posh/` | when it draws the prompt |
| powerlevel10k        | gitstatusd under `~/.cache/gitstatus/` and its instant-prompt cache under `~/.cache/`            | when it draws the prompt |
| tide                 | a `_tide_*` universal variable or two in the target's `fish_variables`, rewritten each start     | when it draws the prompt |

Each tool's own settings on that target can move those paths;
`_HI_PROMPT_TOOL=hi` brings a session back to the first table alone. What your
own per-shell files start (a zoxide or atuin `init`, say) writes on its own
account.

Your commands land in the target's own history file, and the programs you run
yourself - editors included - write there, exactly as over plain `ssh`;
nothing hi ships touches the history file, and hi's emacs config turns off
emacs's backups, autosaves, and lock files. `hi --doctor` prints any setting
not at its default, so "what is this install allowed to do to a target" is one
command.

## Footprint and cleanup on the target

- `load.sh`'s on-exit hook removes the whole session tree, session-rc
  directory included, on a clean exit and on an abrupt disconnect alike
  (`tests/targets/ssh_disconnect_test.sh` verifies the latter). Over ssh the
  bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` is a backstop for the one
  thing the hook cannot survive: bash killed by a signal nothing can trap.
- The session tree is **not** added to `$PATH`; `hi` inside a session is an
  alias (`common/paths.sh`) instead. A `/tmp` path on `$PATH` is a finding on
  any host that is scanned for one.
- A say-hi installed on the target is neither read nor written by a session:
  every session runs out of the tree hi just unpacked, so the installed tree
  need not be writable by you or at any fixed path.
  `tests/targets/install_methods_test.sh` drives one target per install method
  and asserts the install is still whole once the session is gone.

## Trust boundaries

- hi's security model is the transport's. It adds no authentication, listens on
  nothing, and anyone positioned to intercept or control your ssh/container
  session could do so without hi in it. Backend dispatch trusts your local
  `~/.ssh/config` and your `docker`/`podman`/`nomad`/`kubectl` CLIs — the same
  ones you already run.
- A malicious target gets what any interactive session gives it: your payload
  and a terminal. Treat every overlay file as public to every host you
  visit, `ssh_tags` included: it names the hosts your `~/.ssh/config` tags,
  and only those, with nothing of how to reach them.
  Nothing a target sends back is executed on the client. The one string hi
  reads back and uses - the scratch directory the target made (the ssh
  bootstrap's, or a container's session tree) - reaches a command run back on
  that target only if absolute and built from an allow list of path
  characters (`_hi_safe_path`); otherwise ssh hands over the host's own
  session and a container connect fails. Escape sequences in session output
  remain possible, exactly as with plain `ssh`; hi's own connect-failure
  report prints a target's stderr as text, so a backslash sequence a target
  wrote stays one.
- A tool your per-shell files start on a target runs under that target's own
  config for it, not yours: an atuin logged in to a sync server there syncs
  the session's history like any other shell's on that box.
- **What hi writes on the client.** The rc lines and `settings.sh` the install
  asked about - `install.sh` checks your rc files with each shell's own syntax
  checker before touching them, and `--uninstall` removes exactly what it
  wrote - plus `hi <TAB>`'s target cache, the payload/overlay cache, and the
  ssh `ControlMaster` socket, in a private runtime directory:
  `$XDG_RUNTIME_DIR`, or a per-uid directory hi creates with `mkdir -m 700`.
  Its name is predictable - the next `hi` has to find it - so if it already
  exists and is not owned by you, or is a symlink, all three are skipped:
  completion sweeps the backends and a connect builds afresh over a fresh
  socket, slower and correct.
- The `ControlMaster` socket is never at a `mktemp -u` name in a shared temp
  directory: `ControlMaster=auto` _joins_ a socket it finds at its path, and a
  name that was unused when printed promises nothing about the moment it is
  used. A connect reuses one at a stable path in the runtime directory, named
  by a checksum of the target and your ssh options rather than either in the
  clear, and torn down after `_HI_CTL_PERSIST` idle seconds (sixty by
  default); `scripts/doctor.sh`'s probe, `_HI_CTL_PERSIST=0`, and a runtime
  directory hi cannot vouch for take a fresh socket in a `mktemp -d` of their
  own, closed when done. Passed as `-o`, either outranks a `ControlMaster no`
  in your `~/.ssh/config`.

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

| principle                                                    | how it holds                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Least privilege, minimal surface                             | hi adds no authentication of its own, listens on nothing, and makes no network call of its own - it trusts the transport you already run                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Fail loud, fail closed                                       | every entry point (`hi.sh`, `load.sh`, `common/core.sh`, `scripts/install.sh`) runs under `set -euo pipefail`, each with a documented re-disable where an error must not close an interactive shell                                                                                                                                                                                                                                                                                                                                                                                      |
| Untrusted input allowlisted, not sanitized after the fact    | `_hi_safe_path` in `hi.sh` checks the scratch directory a target hands back against an explicit `[bracket-class]` before it reaches a command run back on it; `_hi_ssh_pattern_hit` in `common/core.sh` skips an ssh-config token that isn't a hostname shape rather than evaluate it; `_hi_sanitize_var` in `common/core.sh` strips control characters and backslashes from target-derived text                                                                                                                                                                                         |
| No secret ever needs to be in the payload                    | the payload is the allow list in [What hi does](#what-hi-does---and-deliberately-doesnt); credentials are handled by hand, outside CI ([CONTRIBUTING.md](CONTRIBUTING.md#when-a-push-is-refused)), with GitHub's push protection as backstop and `ci.yml`'s `secret scan (gitleaks)` sweeping the full history on every PR and push to `main`, findings redacted from the log                                                                                                                                                                                                            |
| The build and release path is defended, not just the product | every CI and release job starts with `step-security/harden-runner` (egress audited everywhere, blocked to an allowlist on the jobs holding a publishing credential: `publish`, `tap`, and the AUR push); third-party actions are pinned by SHA; `dependency review` fails a PR that adds a dependency with a high or critical advisory; `release.yml`'s `gate` builds only a tag signed by a key in `.github/allowed_signers`, on `main`, with green CI; the signing keys are `release` environment secrets no other job can read ([RELEASING.md](RELEASING.md#the-release-environment)) |

**What is not (yet) countered.** `hi --update` refuses a tampered signature,
not a missing or foreign one: a tag re-signed with a key
`.github/allowed_signers` does not list, or stripped of its signature, is
named in yellow and checked out. The allowed-signers file is trusted on first
use - the copy already checked out, which a later release can change.
A packaged install updates through its package manager instead
([PACKAGING.md](PACKAGING.md)).

## Supported versions

No **1.0** release yet: the supported version is the tip of `main`, and
packages exist for the pre-1.0 versions a hand-pushed `v*` tag has built
([RELEASING.md](RELEASING.md#cutting-a-release)). Once v1.0 is tagged, this
becomes a version table with the latest release supported; what a 1.x release
keeps stable is
[CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break).

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Instead, report
privately via
[GitHub private vulnerability reporting](https://github.com/ivylikethevine/say-hi/security/advisories/new).

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

Last reviewed 2026-09.
