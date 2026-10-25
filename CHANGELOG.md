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
