# Security Policy

The threat model for a tool people run against every host they touch: what hi
does and deliberately doesn't, what runs where, what it leaves behind, where
the trust boundaries sit, and how to report what slipped through.

## Contents

- [What hi does - and deliberately doesn't](#what-hi-does---and-deliberately-doesnt)
- [What runs where](#what-runs-where)
- [What hi writes on a target](#what-hi-writes-on-a-target)
- [Footprint and cleanup on the target](#footprint-and-cleanup-on-the-target)
- [Trust boundaries](#trust-boundaries)
- [When a push is refused](#when-a-push-is-refused)
- [Supported versions](#supported-versions)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## What hi does - and deliberately doesn't

- **No network calls of its own.** `hi` only execs the transports you already
  use (`ssh`, `docker exec`, `podman exec`, `nomad alloc exec`, `kubectl exec`)
  against a target you named. No telemetry, no update checks, no
  `curl`/`wget` in the shipped tree.
- **No `curl | bash`.** Installing is `git clone` plus `scripts/install.sh`, or
  a distro package (deb/rpm/apk, AUR, Homebrew) built from that same script.
  `hi --update` is `git pull` in a checkout you can read.
- **The payload is an allow list.** What goes over the wire is exactly
  `$_HI_PAYLOAD` at the top of `hi.sh` (`common settings load.sh hi.sh`) —
  docs, tests, CI and editor config never leave the client; `hi.sh` is there so
  a session can say `hi` onward. Your overlay is a second, smaller allow list,
  `$_HI_OVERLAY_FILES` (`settings.sh`, `colors`, `packages`, `vim.rc`,
  `nano.rc`, `aliases.sh`, `bash.sh`, `zsh.zsh`, `config.fish` from
  `~/.config/say-hi/`), so anything else in that directory stays on the client.
- **base64 is armor, not crypto.** It gets the payload through the target's
  login shell unmangled; confidentiality and integrity come entirely from the
  transport.
- **Nothing on the target is written outside the session directory, by
  default.** No login file, no history file, nothing under `$HOME`. The two
  settings that would change that are opt-in and named in
  [What hi writes on a target](#what-hi-writes-on-a-target) below.
- **The transport keeps its own voice.** hi does not redirect `ssh`'s stderr,
  so the server's `Banner`, the `Permanently added ... to the list of known
  hosts` line and the host-key fingerprint on a first connection reach your
  terminal exactly as they would without hi in the way. hi captured all of it
  until it was pointed out that this quietly turned trust-on-first-use into
  accepting a fingerprint nobody was shown.
- **`hi --update` is an unsigned `git pull`.** There are no signed tags yet
  (there is no tagged release yet at all - see
  [Supported versions](#supported-versions)), so what it verifies is what
  `git` verifies: the transport to the remote, and nothing about the commits.
  A packaged install updates through its package manager instead, which has
  its own signing story.

## What runs where

`hi.sh` runs on the client: it parses arguments, picks the backend, tars and
armors the payload, and pipes it over the transport. On the target a single
`sh` unpacks it into a temp directory and chainloads `load.sh`, which prints
the header, grafts hi's marker-delimited blocks onto the host's rc files, and
hands off to the best shell available. Everything the target executes was
generated on the client.

## What hi writes on a target

Default answer: one directory, and only for the life of the session.

| what                     | where                                              | when                                    |
| ------------------------ | -------------------------------------------------- | --------------------------------------- |
| the session tree         | `mktemp -d`, mode 0700, `<user>.hi.XXXXXX`         | always (unless the target has its own permanent say-hi, which is used in place and never written to) |
| the ssh bootstrap        | `mkdir -m 700` under the target's temp directory   | ssh targets only, removed by the session it starts |
| the target's rc files    | `~/.bashrc`, `~/.zshrc`, fish's `config.fish`      | **only with `_HI_GRAFT_RC=1`** - off by default |
| command history          | a `mktemp -d` wiped on exit, instead of the host's | **only with `_HI_SCRATCH_HISTORY=1`** - off by default |

Both of those last two ship **off**, and both are off for a reason a fleet
operator will recognise:

- The **rc graft** is a write to a login file on a machine that is not yours,
  twice per session, for every host you visit. Whatever watches those paths -
  AIDE, Wazuh, osquery, a package manager's own integrity check - sees a
  modification it will ask you about, and another login on a shared account
  can read the file mid-write. `_HI_GRAFT_RC=1` turns it on for the hosts
  where a shell started *inside* the session should match the session.
- **Scratch history** redirects the session's command history into a directory
  that is deleted when the shell exits. It is a reasonable thing to want on a
  throwaway box and an unreasonable default everywhere: a session that erases
  the record of what it did is, afterwards, the same shape as one that was
  meant to. Off, your commands land in the target's own history file exactly
  as they would over plain `ssh`.

`hi --doctor` prints any setting that is not at its default, both of these
included, so "what is this install allowed to do to a target" is one command.

## Footprint and cleanup on the target

- The session tree lives in a `mktemp -d` directory (mode 0700, named
  `<user>.hi.XXXXXX`); the ssh bootstrap directory is `mkdir -m 700`.
- Removal has two independent paths: the bootstrap's
  `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s own on-exit hook.
  `tests/targets/ssh_disconnect_test.sh` verifies cleanup fires on an abrupt
  disconnect, not just a clean exit.
- The rc additions - **when `_HI_GRAFT_RC=1` asked for them** - sit between
  `# hi-config-start` and `# hi-config-end` markers and are stripped by that
  same hook. Each is also wrapped in a tree-exists guard, so one left behind
  by a session that was killed between the write and the cleanup is inert
  rather than an error in every later login.
- The session tree is **not** added to `$PATH`. `hi` inside a session is an
  alias (`common/paths.sh`), which is how it was always reached; the `$PATH`
  entry that used to sit beside it put a `/tmp` path on `$PATH`, which is a
  finding on any host that is scanned for one.
- A target with a permanent say-hi is used in place and nothing is deleted; the
  rc grafts are still cleaned on exit. hi finds that tree by reading the
  target's login rc files, then the standard install prefixes, so nothing has to
  be at a fixed path, and the tree never needs to be writable by you — your
  config lives in `~/.config/say-hi/`.
  `tests/targets/install_methods_test.sh` drives one target per install method.
- On the client, `install.sh` validates your rc files with each shell's own
  syntax checker before touching them, and `--uninstall` removes exactly what
  install wrote.

## Trust boundaries

- hi's security model is the transport's. It adds no authentication, listens on
  nothing, and anyone positioned to intercept or control your ssh/container
  session could do so without hi in it.
- A malicious target gets what any interactive session gives it: your payload
  and a terminal. Treat every overlay file as public to every host you visit.
  Nothing a target sends back is executed on the client — the one string hi
  reads back (the probe for an existing say-hi tree) is only interpolated into
  the script sent back to that same target. Escape sequences in session output
  remain possible, exactly as with plain `ssh`.
- Backend dispatch trusts your local `~/.ssh/config` and your
  `docker`/`podman`/`nomad`/`kubectl` CLIs — the same ones you already run.
- The ssh `ControlMaster` socket lives inside a `mktemp -d` of its own rather
  than at a `mktemp -u` name in a shared temp directory: `ControlMaster=auto`
  *joins* a socket it finds at the path it was given, and a name that was
  merely unused when it was printed is not a guarantee about the moment it is
  used.
- `hi <TAB>`'s target cache is written to `$XDG_RUNTIME_DIR`, or to a
  per-uid directory hi creates with `mkdir -m 700`. The name is predictable —
  the next TAB has to find it — so if that path already exists and is not
  owned by you, or is a symlink, the cache is skipped rather than adopted.
  Completion falls back to sweeping the backends, which is slower and correct.

### What a process started from a session inherits

Eight `_HI_*` names, and nothing else with the prefix: the tree and overlay
pointers, the remote-session flag, the session rc directory, and the four
completion knobs `targets.sh` reads from its environment. Everything else hi
sets — sixty-odd paths and toggles — stays a shell variable in the session
shell and stops there, so a service started by hand, a `sudo -E`, or a cron
line pasted at the prompt sees an ordinary environment. In particular the
two values that name your workstation (`_HI_LOCAL_USER`,
`_HI_LOCAL_HOSTNAME`) are never in a child's environment; a shell started
inside the session reads them from hi's own rc directory instead. The
mechanism and the roster are [HI.47](GLOSSARY.md#hi47-what-a-child-inherits);
`tests/common/exports_test.sh` pins both. The one tier this does not reach is
a POSIX `sh` started inside a session (and the bash-less fallback), where
`$ENV` sources `paths.sh` again and dash has no un-export.

## When a push is refused

Secret scanning and push protection are on for this repository. Push
protection refuses the push outright, so the first thing you see is GitHub's
own error.

**That refusal is the guard working.** Take the credential out of the commit —
amend, or rewrite the branch — and push again. Do not force it and do not
bypass and clean up later: a secret that reaches the remote for even one push
is a secret to rotate. For a false positive, GitHub's error links the bypass
flow, which records why; take that route rather than reshaping the string.

It is reachable at all because four credentials are handled by hand — the two
signing keys, `AUR_SSH_KEY` and `HOMEBREW_TAP_TOKEN`, each generated locally,
pasted into a settings page and deleted. [PACKAGING.md](PACKAGING.md) walks
each. GitHub's scanner is used rather than gitleaks or trufflehog because it
runs on the push path, where a third-party action cannot.

## Supported versions

No tagged release yet: the supported version is the tip of `main`. Once v1.0 is
tagged, this becomes a version table with the latest release supported.

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Instead:

- report privately via
  [GitHub private vulnerability reporting](https://github.com/ivylikethevine/say-hi/security/advisories/new)
