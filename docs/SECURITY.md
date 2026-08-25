# Security Policy

The threat model for a tool people run against every host they touch: what hi
does and deliberately doesn't, what runs where, what it leaves behind, where
the trust boundaries sit, and how to report what slipped through.

## Contents

- [What hi does - and deliberately doesn't](#what-hi-does---and-deliberately-doesnt)
- [What runs where](#what-runs-where)
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

## What runs where

`hi.sh` runs on the client: it parses arguments, picks the backend, tars and
armors the payload, and pipes it over the transport. On the target a single
`sh` unpacks it into a temp directory and chainloads `load.sh`, which prints
the header, grafts hi's marker-delimited blocks onto the host's rc files, and
hands off to the best shell available. Everything the target executes was
generated on the client.

## Footprint and cleanup on the target

- The session tree lives in a `mktemp -d` directory (mode 0700, named
  `<user>.hi.XXXXXX`); the ssh bootstrap directory is `mkdir -m 700`.
- Removal has two independent paths: the bootstrap's
  `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s own on-exit hook.
  `tests/targets/ssh_disconnect_test.sh` verifies cleanup fires on an abrupt
  disconnect, not just a clean exit.
- The rc additions sit between `# hi-config-start` and `# hi-config-end`
  markers and are stripped by that same hook.
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
