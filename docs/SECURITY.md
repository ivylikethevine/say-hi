# Security Policy

A tool people run against every host they touch earns the obvious
questions up front. This is the threat model: what hi does and
deliberately doesn't, what runs where, what it leaves behind, where the
trust boundaries sit, and how to report what slipped through.

## Contents

- [What hi does - and deliberately doesn't](#what-hi-does---and-deliberately-doesnt)
- [What runs where](#what-runs-where)
- [Footprint and cleanup on the target](#footprint-and-cleanup-on-the-target)
- [Trust boundaries](#trust-boundaries)
- [When a push is refused](#when-a-push-is-refused)
- [Supported versions](#supported-versions)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## What hi does - and deliberately doesn't

- **No network calls of its own.** `hi` only execs the transports you
  already use (`ssh`, `docker exec`, `podman exec`, `nomad alloc exec`,
  `kubectl exec`) against a target you named. No telemetry, no update
  checks, no `curl`/`wget` anywhere in the shipped tree.
- **No `curl | bash`.** Installing is `git clone` plus
  `scripts/install.sh`, or a distro package (deb/rpm/apk, AUR, Homebrew)
  built from that same script. `hi --update` is `git pull` in a checkout
  you can read.
- **The payload is an allow list.** What goes over the wire is exactly
  `$_HI_PAYLOAD` at the top of `hi.sh` (`common settings load.sh hi.sh`) -
  docs, tests, CI and editor config never leave the client.
  `hi.sh` is in that list so a session can say `hi` onward from the
  target. Your overlay is a second, smaller allow list -
  `$_HI_OVERLAY_FILES`, also in `hi.sh` (`settings.sh`, `colors`,
  `packages`, `personal.sh`, `aliases.sh`, `bash.sh`, `zsh.zsh`,
  `config.fish` from `~/.config/say-hi/`) - so anything else sharing that
  directory stays on the client.
- **base64 is armor, not crypto.** The payload is base64-encoded so it
  survives the target's login shell unmangled; it provides no
  confidentiality or integrity. Both come entirely from the transport
  (ssh, or the container runtime's exec channel).

## What runs where

`hi.sh` runs on the client: it parses arguments, picks the backend, tars
and armors the payload, and pipes it over the transport. On the target, a
single `sh` unpacks it into a temp directory and chainloads `load.sh`,
which prints the header, grafts hi's marker-delimited blocks onto the
host's rc files, and hands off to the best shell available. Everything
the target executes was generated on the client.

## Footprint and cleanup on the target

- The session tree lives in a `mktemp -d` directory (mode 0700, named
  `<user>.hi.XXXXXX`); the ssh bootstrap directory is created with
  `mkdir -m 700`.
- Removal has two independent paths: the bootstrap's
  `trap 'rm -rf $_HI_CLEANUP' exit`, and `load.sh`'s own on-exit hook.
  `tests/targets/ssh_disconnect_test.sh` verifies cleanup fires on an
  abrupt disconnect, not just a clean exit.
- The rc additions sit between `# hi-config-start` and `# hi-config-end`
  markers and are stripped back out by that same on-exit hook.
- A target with a permanent say-hi is used in place and nothing is
  deleted; the rc grafts are still cleaned on exit. However it got there -
  `scripts/install.sh`, a `.deb`/`.rpm`/`.apk`, a Homebrew keg - hi finds
  it by reading that target's own login rc files and then the standard
  install prefixes, so nothing has to be at a fixed path. That permanent
  tree never needs to be writable by you: root-owned, package-manager
  copies work, because your config lives in `~/.config/say-hi/`.
  `tests/targets/install_methods_test.sh` drives one target per method.
- On the client, `install.sh` validates your existing rc files with each
  shell's own syntax checker before touching them, and `--uninstall`
  removes exactly what install wrote.

## Trust boundaries

- hi's security model is the transport's security model. It adds no
  authentication, listens on nothing, and anyone positioned to intercept
  or control your ssh/container session could do so without hi in it.
- A malicious target gets what any interactive session gives it: your
  payload and a terminal. Treat every file in your overlay - the eight
  `$_HI_OVERLAY_FILES` names above - as public to every host you visit.
  Nothing a target sends back is ever executed on the client - the one
  string hi reads back (the probe for an existing say-hi tree) is only
  interpolated into the script sent back to that same target. Escape sequences in session
  output remain possible, exactly as with plain `ssh`.
- Backend dispatch trusts your local `~/.ssh/config` and your
  `docker`/`podman`/`nomad`/`kubectl` CLIs - the same ones you already
  run by hand.

## When a push is refused

Secret scanning and push protection are both on for this repository. Push
protection is the half that acts: it refuses the push outright rather than
reporting the leak afterwards, so the first thing you see is GitHub's own
error, not anything from this project.

**That refusal is the guard working.** The fix is to take the credential out of
the commit — amend it, or rewrite the branch — and push again. It is not to
force the push, and it is not to bypass the block and clean up later: a secret
that reaches the remote for even one push is a secret to rotate, whatever
happens to the commit afterwards. If the blocked string is a false positive,
GitHub's own error links the bypass flow, which asks you to say why and records
the answer; take that route rather than reshaping the string until the scanner
stops noticing.

It is reachable at all because four credentials are handled by hand: the two
signing keys, plus `AUR_SSH_KEY` and `HOMEBREW_TAP_TOKEN`. Every one is
generated on a laptop, pasted into a settings page, and deleted locally — a
sequence whose failure mode is one paste into the wrong buffer and a commit.
[PACKAGING.md](PACKAGING.md) walks each of them.

Still GitHub's scanner rather than gitleaks or trufflehog, deliberately: it
runs on the push path, where a third-party action cannot. Revisit only if a key
format it does not recognise shows up.

## Supported versions

There is no tagged release yet: the supported version is the tip of
`main`. Once v1.0 is tagged, this section becomes a version table, with
the latest release supported.

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Instead,
either:

- report privately via
  [GitHub private vulnerability reporting](https://github.com/ivylikethevine/say-hi/security/advisories/new),
