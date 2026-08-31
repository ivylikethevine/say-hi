#!/usr/bin/env bash
# Warn when docs/tapes/demo.gif is older than the things that decide what it
# shows. Warn, never block: demo.gif is a manual artifact reviewed by eye
# (docs/tapes/generate.sh says so at the top), and a check that refused a
# commit would be making that call for you. Exit status is always 0.
#
# Run by hand, as the pre-commit hook beside it, or by ci.yml's advisory-lint
# job on every pull request - see docs/PACKAGING.md's "Regenerating the demo
# GIFs". It lives in .githooks/ rather than scripts/
# because scripts/ is in $_HI_PACKAGE_CONTENTS: a contributor's git hook has no
# business in /usr/share/say-hi, and a subdirectory under scripts/ also falls
# straight through nfpm.yaml's one-level apk globs (packaging_test.sh fails on
# it).
#
# Only the topmost README demo, on purpose - and it is now the only demo this
# could apply to. It is the one GIF that claims to be the stock defaults with
# nothing turned off, so it is the one that goes quietly wrong when the header,
# the prompt or the tape changes, and the one a person still renders by hand.
# The other seven each advertise a knob and are rendered by CI on a cadence
# (.github/workflows/demos.yml), so nothing here has to watch them.
set -euo pipefail

# Deliberately NOT the standalone-entry form of GLOSSARY: HI.33. That form lets
# $_HI_HOME win, which is correct for a hi entry point and wrong for a git hook:
# a hook has exactly one honest subject, the repository it was invoked in. An
# inherited _HI_ROOT - a long-lived shell still carrying a whole _HI_* set from
# some other checkout - would otherwise silently point every `git log` below at
# that tree and report on it instead, which is a check that always passes.
_HI_REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$_HI_REPO" ] || exit 0
# ...and if that repository is not say-hi, there is nothing here to check.
[ -f "$_HI_REPO/common/core.sh" ] || exit 0
# shellcheck source=../common/core.sh
source "$_HI_REPO/common/core.sh"

_HI_DEMO_GIF="docs/tapes/demo.gif"

# What the frame is made of: the tape and its fixtures (the target's image
# among them - its tools and its checkout are half of what is on screen), plus
# the tree the session in it actually runs - which is $_HI_PAYLOAD, the same
# allow list hi.sh ships over the wire. The rest of docs/ and tests/ is
# deliberately not here: it cannot change a pixel.
_HI_DEMO_INPUTS="
docs/tapes/demo.tape
docs/tapes/common.tape
docs/tapes/fixtures.sh
tests/dockerfiles/demo-debian.Dockerfile
common
settings
load.sh
hi.sh
"

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Usage: demo_staleness.sh

Says whether docs/tapes/demo.gif is older than the tape, the fixtures, or the
shipped tree the demo renders - by commit date, not mtime, since a fresh clone
gives every file the same mtime. Also flags a staged commit that changes one of
those inputs without re-rendering.

Always exits 0. Re-render with:

  docs/tapes/generate.sh demo
EOF
  exit 0
  ;;
esac

# Last commit to touch a path, as a unix timestamp; empty when git has never
# seen it (a new file, or no repository at all).
function _hi_last_commit() {
  git -C "$_HI_REPO" log -1 --no-show-signature --format=%ct -- "$1" 2>/dev/null || :
}

function _hi_demo_staleness() {
  local gif_at input at newer="" staged=""

  # The GIF is in the commit being made, so this *is* the re-render and neither
  # check below has anything to say. It also covers `git commit --amend` adding
  # a fresh render to the commit that changed the tape, where the history check
  # would otherwise still be reading the pre-amend HEAD and warn about work
  # that is right there in the index.
  git -C "$_HI_REPO" diff --cached --quiet -- "$_HI_DEMO_GIF" 2>/dev/null || return 0

  gif_at="$(_hi_last_commit "$_HI_DEMO_GIF")"
  # never committed - there is nothing to be stale against yet
  [ -n "$gif_at" ] || return 0

  for input in $_HI_DEMO_INPUTS; do
    at="$(_hi_last_commit "$input")"
    [ -n "$at" ] || continue
    [ "$at" -gt "$gif_at" ] && newer="$newer $input"
  done

  # the commit being made right now, which no `git log` can see yet
  for input in $_HI_DEMO_INPUTS; do
    git -C "$_HI_REPO" diff --cached --quiet -- "$input" 2>/dev/null ||
      staged="$staged $input"
  done

  [ -n "$newer$staged" ] || return 0

  _hi_cecho "demo.gif may be out of date - it is the stock-defaults GIF at the top of README" "$YELLOW"
  [ -n "$newer" ] && _hi_cecho "  committed since it was last rendered:$newer" "$YELLOW"
  [ -n "$staged" ] && _hi_cecho "  changed by this commit, with no new render:$staged" "$YELLOW"
  _hi_cecho "  re-render with: docs/tapes/generate.sh demo   (needs docker; look at it before committing)" "$BLUE"
  return 0
}

_hi_demo_staleness
exit 0
