---
paths:
  - "**/tests/**"
  - "**/test/**"
  - "**/test_*"
  - "**/*_test.*"
---

# Git fixtures and a developer's git config

A developer's git config may sign every commit and tag (`commit.gpgsign`,
`tag.gpgsign`), check every object it receives (`transfer.fsckObjects`) or show
signatures in `git log` (`log.showSignature`). CI sets none of them, so a
fixture that passes there can fail on a developer's machine and look like a
regression.

- Fixture commits pass
  `-c commit.gpgsign=false -c user.name=... -c user.email=...`.
- Fixture tags pass `-c tag.gpgsign=false`. Under `tag.gpgsign`, a bare
  `git tag <name>` fails with "no tag message?", and a suite that silences it
  fails later with "no tag or branch named ...".
- A fixture built from deliberately malformed objects passes
  `-c transfer.fsckObjects=false`.
- Scripts that parse `git log` pass `--no-show-signature`.

Read a setting with `git config --get <key>` before blaming it. To confirm a
failure comes from signing, rerun the suite with
`GIT_CONFIG_PARAMETERS="'tag.gpgsign=false' 'commit.gpgsign=false'"`.
