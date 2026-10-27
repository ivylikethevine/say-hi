# Changelog

What changed for someone using hi, release by release, newest first: each
entry is its pull requests' release notes, written before the tag by
`.github/scripts/changelog.sh`
([RELEASING.md](docs/RELEASING.md#cutting-a-release)), and the
[roadmap](README.md#roadmap) entries finished since the last one, a sentence
each; they, and the sentences of work not yet merged, wait under
`## Unreleased` until then. Releases before the first
entry list theirs on
[the releases page](https://github.com/ivylikethevine/say-hi/releases).

## Unreleased

From the roadmap:

- Every release's source tarball carries a `CHANGELOG.md` that opens on that release's own entry.
- A connect from a git checkout no longer runs `git describe` each time: the version it sends is kept in `.git/hi-version` until a commit, a checkout, a tag, or the index changes it.

## 0.8.0 - 2026-10-26

- Connecting is faster. hi opens the session while its files are still on the way, starts ssh's handshake as soon as it knows the target, and sends 65 KB instead of 82 KB; a cold connect takes about half as long on a fast link, and about 0.4 s less over a 150 ms one.
- `hi user@host` goes straight to ssh, without first asking docker, podman, or kubectl whether the name is theirs.
- A first install defaults to the `balanced` preset: a shorter package check, and your own machine's shell left as it is. `hi --configure --preset everything` brings back the old defaults.
- `hi --update` moves only to a release tag signed by a key the checkout trusts. `_HI_UPDATE_UNSIGNED=1` allows an unsigned one, and replaces `_HI_UPDATE_SIGNED`.
- kitty, ghostty, and other terminals with a `TERM` of their own keep it on any target that has `tic`, so styled underlines and the kitty keyboard protocol work there; other targets still get `xterm-256color`.
- On a target whose locale cannot count multibyte characters, the session gets a UTF-8 locale the target has, or hi's ASCII glyphs where it has none, so the header and prompt no longer wrap.
- A target whose `tar` cannot read gzip is named as the reason, and you get the host's own session.
- A fish session needs fish 3.3 or newer; an older fish gets a one-line notice and the next shell down.
