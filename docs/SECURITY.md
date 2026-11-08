# Security Policy

The threat model for a tool you run against every host you touch, and how to
report what slipped through it.

## Contents

- [What hi does - and deliberately doesn't](#what-hi-does---and-deliberately-doesnt)
- [What runs where](#what-runs-where)
- [What hi writes on a target](#what-hi-writes-on-a-target)
- [Footprint and cleanup on the target](#footprint-and-cleanup-on-the-target)
- [Trust boundaries](#trust-boundaries)
  - [What a process started from a session inherits](#what-a-process-started-from-a-session-inherits)
- [Assurance case](#assurance-case)
- [Scanning policy](#scanning-policy)
- [Supported versions](#supported-versions)
- [Reporting a vulnerability](#reporting-a-vulnerability)
  - [What happens to a report](#what-happens-to-a-report)

## What hi does - and deliberately doesn't

- **No network calls of its own.** `hi` only runs the transports you already
  use (`ssh`, `docker exec`, `podman exec`, `nerdctl exec`, `finch exec`,
  `nomad alloc exec`, `kubectl exec`) against a target you named. No
  telemetry, no update checks, no `curl` or `wget` in the shipped tree.
- **No `curl | bash`.** Installing is `git clone` plus `scripts/install.sh`,
  or a package built from that script
  ([PACKAGING.md](PACKAGING.md#install-channels)). `hi --update` checks out a
  release tag in a checkout you can read (or fast-forwards `dev`, if you
  chose to follow it).
- **The payload is an allow list.** Only `$_HI_PAYLOAD` (`common config
load.sh hi.sh`) goes over the wire; docs, tests, and CI never leave your
  machine. Your overlay is a second allow list, `$_HI_OVERLAY_FILES`, plus the
  files your `plugins` rows name; `hi --doctor` lists each. Your git config
  rides only with its plugin on, and never its credentials or keys
  ([INTEGRATIONS.md](INTEGRATIONS.md#git)). A `plugins` row is read as data,
  never evaluated ([HI.63](GLOSSARY.md#hi63-plugins-rows)).
- **base64 is armor, not crypto.** It gets the payload through the target's
  login shell intact; confidentiality and integrity come from the transport.
- **hi writes nothing on the target outside its own temp directories**: no
  login file, no history file, nothing under `$HOME`
  ([the full list](#what-hi-writes-on-a-target)).
- **The transport keeps its own voice.** hi does not capture `ssh`'s stderr,
  so the server's banner and a first connection's host-key fingerprint reach
  you exactly as without hi.
- **`hi --update` verifies the tag's signature before checking it out**,
  against the checkout's own `.github/allowed_signers` (ssh) or your gpg
  keyring. A failing signature always refuses. An unsigned tag, an unknown
  key, or no `gpg` refuses too, unless
  [`_HI_UPDATE_UNSIGNED=1`](SETTINGS.md#every-setting).

## What runs where

`hi.sh` runs on your machine: it parses arguments, picks the backend, packs
the payload, and sends it over the transport. On the target one `sh` unpacks
it into a temp directory and starts `load.sh`, which prints the header,
writes the session's rc files into its own directory, and starts your shell.
Everything the target runs was generated on your machine
([HOW-IT-WORKS.md](HOW-IT-WORKS.md)).

Three sshd setups change this, and hi says so for each:

- **`ForceCommand`, or `command=` on the key**: the host runs its own program
  whatever the client asks. hi's bootstrap never runs; hi says so and hands
  over the host's own session.
- **`rbash` as the login shell** forbids a `/` in a command name, and `sh`
  has none, so hi's bootstrap runs unrestricted. rbash is not a boundary; a
  host that needs one wants `ForceCommand`.
- **`MaxSessions 1`** works: hi's two calls share one connection
  ([HI.19](GLOSSARY.md#hi19-stdin-transport)).

`tests/targets/ssh_test.sh` covers all three.

## What hi writes on a target

Two directories in the target's temp directory, mode 0700, for the life of
the session (longer only for a [kept session](INTEGRATIONS.md#terminal-multiplexers)):

| what             | where              | when                                              |
| ---------------- | ------------------ | ------------------------------------------------- |
| the session tree | `<user>.hi.XXXXXX` | every session but `--plain`                       |
| the bootstrap    | `hi.boot.XXXXXX`   | every session but `--plain`, removed when it ends |

Besides those, a fish session caches its two prompt colors in fish's
universal variables, as it does locally, and a `hi` run from inside a
session to reach a further target keeps its caches in the runtime directory.
That is everything hi's own code writes.

Tools you turn on write what they always do, under the target's `$HOME`, and
keep it after the session:

| tool                        | what it keeps, by default                                                                             | when                                                                             |
| --------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| starship, oh-my-posh        | log and cache files under `~/.cache/`                                                                 | when it draws the prompt                                                         |
| powerlevel10k               | gitstatusd and its instant-prompt cache under `~/.cache/`                                             | when it draws the prompt                                                         |
| tide                        | a `_tide_*` universal variable or two in `fish_variables`                                             | when it draws the prompt                                                         |
| zoxide, atuin, direnv, mise | zoxide's database, atuin's history (and sync, if logged in there), direnv's allow list, mise's caches | only once `hi --enable-plugin` names it ([SETTINGS.md](SETTINGS.md#shell-hooks)) |

`_HI_PROMPT_TOOL=hi` keeps the prompt programs out. Your commands land in the
target's own history file, and programs you run write what they always do,
as over plain `ssh`; hi's emacs config turns off emacs's backups, autosaves,
and lock files. `hi --doctor` prints every setting not at its default.

## Footprint and cleanup on the target

- **On exit or a dropped link**, the session's exit hook removes the session
  tree. Over ssh the bootstrap's exit trap is a backstop, and a watcher
  process does the same if both are killed; the account's next
  `hi <target>` removes any tree whose session is gone
  ([HI.65](GLOSSARY.md#hi65-kept-session)).
  `tests/targets/ssh_disconnect_test.sh` checks the abrupt case.
- **A kept session** keeps its tree until it closes or times out
  ([INTEGRATIONS.md](INTEGRATIONS.md#terminal-multiplexers)). A reconnect
  takes over a held tree only from a directory its own account owns, never
  through a symlink.
- **`$PATH` is not changed**, since a `/tmp` path there is a finding on a
  scanned host; `hi` inside a session is an alias. The one exception is
  yours: an overlay `bin/` puts that directory last on `$PATH`
  ([SETTINGS.md](SETTINGS.md#scripts-of-your-own)).
- **A say-hi installed on the target is neither read nor written.**
  `tests/targets/install_methods_test.sh` checks it is whole after a session.

## Trust boundaries

- **hi's security is the transport's.** It adds no authentication and listens
  on nothing. Backend dispatch trusts your `~/.ssh/config` and your backend
  CLIs. A name with no `Host` entry is tried with each backend CLI before ssh,
  and `hi <TAB>` lists through them (`kubectl get pods -A` included);
  [`_HI_BACKENDS_OFF`](SETTINGS.md#every-setting) names the ones hi never
  starts.
- **A malicious target gets your payload and a terminal**, as any session
  would. Treat every overlay file as public to every host you visit,
  `ssh_tags` included (it names your tagged hosts, not how to reach them);
  `hi --doctor` flags a line that looks like a secret.
- **Nothing a target sends back runs on your machine.** The one string hi
  reads back, the scratch directory's path, is used only if absolute and made
  of allowed characters (`_hi_safe_path`). Escape sequences in session output
  are possible, as with plain `ssh`.
- **Tools you start on a target use that target's config**: an atuin logged
  in to a sync server there syncs the session's history.
- **What hi writes on your machine**: the rc lines and `settings.sh` the
  install asked about (each rc syntax-checked first, and `--uninstall`
  removes exactly what it wrote), and caches, the ssh control socket, and kept
  session markers in a private runtime directory (`$XDG_RUNTIME_DIR`, or one
  hi makes with mode 700). If that directory is not yours or is a symlink, hi
  skips the caches and works slower but correct
  ([FILES.md](FILES.md#caches-and-sockets)).
- **The ssh control socket** lives at a hashed name in that runtime
  directory, never in a shared temp directory, and closes after
  `_HI_CTL_PERSIST` idle seconds (60).
  [`_HI_DISABLE_CONTROLMASTER=1`](SETTINGS.md#every-setting) turns it off, at
  the cost of a second authentication per connect.

### What a process started from a session inherits

Only the names in `core.sh`'s `_HI_CHILD_ENV`: the tree and overlay paths,
the session flag, the session rc directory, and the completion settings.
Everything else hi sets stays a shell variable, so a service started by hand,
a `sudo -E`, or a pasted cron line sees an ordinary environment. The names of
your own user and machine never reach a child. The exception is a POSIX `sh`
started inside a session, which re-reads `paths.sh`
([HI.47](GLOSSARY.md#hi47-what-a-child-inherits);
`tests/common/exports_test.sh`).

## Assurance case

How secure design principles were applied against the threat model and
[trust boundaries](#trust-boundaries) above. It is not a claim that hi is
free of bugs.

| principle                                                    | how it holds                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Least privilege, minimal surface                             | no authentication of its own, no listener, no network call of its own                                                                                                                                                                                                 |
| Fail loud, fail closed                                       | every entry point (`hi.sh`, `load.sh`, `common/core.sh`, `scripts/install.sh`) runs under `set -euo pipefail`, turned off only where an error must not close an interactive shell                                                                                     |
| Untrusted input checked against an allow list                | `_hi_safe_path` checks the directory a target hands back; `_hi_ssh_pattern_hit` skips an ssh-config token that is not a hostname; `_hi_sanitize_var` strips control characters from text a target supplies                                                            |
| No secret ever needs to be in the payload                    | the payload is an allow list; credentials are handled outside CI ([CONTRIBUTING.md](CONTRIBUTING.md#when-a-push-is-refused)), with push protection and a full-history secret scan on every PR and push to `main`                                                      |
| The build and release path is defended, not just the product | every CI and release job runs `step-security/harden-runner`; actions are pinned by SHA; `dependency review` blocks high or critical advisories; `release.yml` builds only a signed tag on `main` with green CI ([RELEASING.md](RELEASING.md#the-release-environment)) |

**Not yet countered.** `_HI_UPDATE_UNSIGNED=1` accepts an unsigned tag or one
signed by an unlisted key, naming it in yellow. On `dev`, `hi --update`
fast-forwards commits with no signature check. The allowed-signers file is
trusted on first use. A package updates through its package manager instead
([PACKAGING.md](PACKAGING.md)).

## Scanning policy

What a finding must clear, and by when. The checks themselves are
[CONTRIBUTING.md's _What CI runs_](CONTRIBUTING.md#what-ci-runs).

- **Dependencies.** `dependency review`, required on every pull request,
  refuses a new dependency with a high or critical advisory. A later
  advisory reaches Dependabot and the weekly `tool-versions.yml` issue: high
  or critical is fixed before the next release, moderate or low by the next
  routine bump. An advisory with no patched release is accepted in
  `.github/osv-scanner.toml` with its reason and an expiry date.
- **Licenses.** Nothing is vendored or redistributed; a dependency whose
  license is incompatible with MIT is refused at review.
- **Code.** shellcheck is a required check with nothing disabled globally;
  each suppression is inline. CodeQL blocks a merge on a high or critical
  alert; a lower one is fixed or dismissed with its reason before the next
  release. zizmor runs in `quick lint`, each ignore in `.github/zizmor.yml`
  with its reason.
- **Before a release.** `release.yml` builds only a tag whose commit is green
  on `main`, and no tag is pushed while a high or critical finding is open.

## Supported versions

Before **1.0**, the supported version is the latest release and the tip of
`main`. Fixes ship in the next release, never as a backport, so a release
stops receiving security updates when its successor is tagged. After 1.0
this becomes a version table; what 1.x keeps stable is
[CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break).

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Report it
privately via
[GitHub private vulnerability reporting](https://github.com/ivylikethevine/say-hi/security/advisories/new).

### What happens to a report

- **Acknowledgement within 14 days**, usually sooner; the report reaches the
  one maintainer directly.
- **Coordinated disclosure.** A confirmed vulnerability is fixed before it is
  discussed publicly, unless the reporter and maintainer agree otherwise,
  aiming for a fix within 60 days. Reporters are kept in the loop throughout.
- **Advisories are public.** Every fixed vulnerability gets a
  [GitHub Security Advisory](https://github.com/ivylikethevine/say-hi/security/advisories)
  naming the affected versions and the fix, referenced in the release notes.
  None have been reported to date.
- **Credit.** Reporters are credited in the advisory and the release notes
  unless they ask not to be.

Last reviewed 2026-09.
