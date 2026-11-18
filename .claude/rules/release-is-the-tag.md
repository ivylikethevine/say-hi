---
paths:
  - ".github/**"
  - "**/CHANGELOG.md"
---

# The tag is the release

Merging the pull request and pushing a signed tag is the whole release.

- Nothing is run, written or remembered by a person for a release, before the
  tag or after it: no changelog entry, fold or stamp, no version bump, no
  release commit. A design that leaves the maintainer a step to remember is
  rejected; the fix removes the state that needs tending.
- A tag gate checks only the tag: its format, its signature, its commit on
  `main`, and green CI on that commit. Nothing that only a further commit could
  satisfy refuses a tag, and no file's contents are checked.
- Release text and versions are computed at publish, from the tag and what is
  already on `main`. A failure computing the text warns, and the release ships.
- A change that would add a release requirement is not made, even when asked
  for in passing: say that it breaks this rule. An existing release flow that
  breaks it is reported first, with the fix.

`.github/scripts/lint_workflows.sh` rule 9 fails a tag workflow that checks a
changelog; this rule covers what no lint sees.
