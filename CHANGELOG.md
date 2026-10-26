# Changelog

What changed for someone using hi, release by release, newest first: each
entry is its pull requests' release notes, written before the tag by
`.github/scripts/changelog.sh`
([RELEASING.md](docs/RELEASING.md#cutting-a-release)), and the
[roadmap](README.md#roadmap) entries finished since the last one, a sentence
each, which wait under `## Unreleased` until then. Releases before the first
entry list theirs on
[the releases page](https://github.com/ivylikethevine/say-hi/releases).

## Unreleased

From the roadmap:

- A cold connect over ssh opens the session while the script is still landing, about two round trips sooner.
- The tree and the overlay ride to the target unarmored, which cuts what a session sends from 82 KB to 63 KB.
- A `user@host` target goes straight to ssh, without asking any container backend first.
- The connect starts its handshake as soon as the target is known, about 70 ms sooner on every cold connect.
- A first install defaults to the `balanced` preset, which leaves this machine's own shell alone.
- `hi --update` moves only to a tag signed by a key the checkout trusts, unless `_HI_UPDATE_UNSIGNED=1` says otherwise.
- A target whose `tar` cannot read gzip is named as such, and hands over its own session.
- fish 3.3 is the oldest fish that lands a fish session.
- Apple's `container` CLI is checked against its own grammar on a hosted macOS 26 runner, which cannot start a container itself.
- A connect's waits for its script sleep on a FIFO until it is built or has landed, rather than looking every 10 ms, and it looks for its master's socket without a fork.
- The boot call starts before hi reads the target's color and prompt list, 11 ms into a connect.
- A connect hashes each of its cache keys once, and builds the overlay's without a subshell.
