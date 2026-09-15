# shellcheck shell=bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# This repo's half of ./check_tool_versions.sh, which sources it before any
# section runs (its header has the contract). Not run on its own.

# Pins that live inline rather than in tools.txt, one row each:
#   bashcov        a rubygem, and no tools.txt kind fetches one
#   vhs            vhs-action's `version:` input - the action's SHA does not
#                  cover the binary it downloads
#   just-the-docs  the Pages theme, fetched by jekyll-build-pages at deploy
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_WORKFLOW_ROSTER='bashcov|.github/workflows/coverage.yml|BASHCOV_VERSION: "\([0-9][0-9.]*\)"|github:infertux/bashcov|
vhs|.github/workflows/demos.yml|version: v\([0-9][0-9.]*\)|github:charmbracelet/vhs|
just-the-docs|_config.yml|remote_theme: just-the-docs/just-the-docs@v\([0-9][0-9.]*\)|github:just-the-docs/just-the-docs|'

# The fixtures are the only Dockerfiles. Images named outside one (shell,
# workflow YAML) are ci_local_checks' below: the FROM/image: extraction
# cannot read them.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_IMAGE_GLOBS='tests/dockerfiles/*.Dockerfile'

# Files that run a digest-pinned image outside a Dockerfile. Dependabot cannot
# see them, so each digest must be one of the tests/dockerfiles pins, which it
# does move - this reports the two parting after a repin PR merges.
_HI_IMAGE_FILES='packaging/mkrepo.sh .github/workflows/ci.yml'

# The floors (and fish's ceiling) the docker `ignore:` rules in
# .github/dependabot.yml hold still: each must still be a fixture pin, and
# each ignore must still protect one of these.
_HI_FLOOR_PINS='bash:3.2 zshusers/zsh:5.8 ubuntu:24.04 ubuntu:26.04'

function ci_local_checks() {
  local pins ignores f refs ref hex floor image pinned

  # image:tag@sha256:<hex> per pinned FROM
  pins="$(sed -n 's/^FROM[[:space:]]\{1,\}\([^[:space:]]*@sha256:[0-9a-f]\{64\}\).*/\1/p' \
    tests/dockerfiles/*.Dockerfile | sort -u)"

  echo "## Images outside Dockerfiles (check_tool_versions.local.sh)"
  echo
  for f in $_HI_IMAGE_FILES; do
    refs="$({ grep -oE '[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}' "$f" || true; } | sort -u)"
    if [ -z "$refs" ]; then
      printf '%-48s %-22s ERROR (no digest-pinned image)\n' "$f" "-"
      _ci_problem "$f" "no digest-pinned image left in $f - pin it to a tests/dockerfiles digest"
      continue
    fi
    while IFS= read -r ref; do
      hex="${ref##*:}"
      if grep -qxF "$ref" <<<"$pins"; then
        printf '%-48s %-22s current (%s, a tests/dockerfiles pin)\n' "${ref%@*}" "${hex:0:12}..." "$f"
      else
        printf '%-48s %-22s OUTDATED (%s: no tests/dockerfiles FROM pins this digest)\n' \
          "${ref%@*}" "${hex:0:12}..." "$f"
        _ci_problem "${ref%@*} in $f" "$f pins $ref, which no tests/dockerfiles FROM does - repin it to the fixture's digest"
      fi
    done <<<"$refs"
  done

  echo
  echo "## Shell floors (dependabot.yml docker ignores)"
  echo
  ignores="$(sed -n 's/^[[:space:]]*- dependency-name: "\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' .github/dependabot.yml | sort -u)"
  for floor in $_HI_FLOOR_PINS; do
    image="${floor%:*}"
    # a literal prefix match, not grep: the tag's dots are not wildcards
    case "$'\n'$pins" in
    *$'\n'"$floor@sha256:"*) pinned=1 ;;
    *) pinned="" ;;
    esac
    if [ -z "$pinned" ]; then
      printf '%-48s ERROR (no tests/dockerfiles FROM pins it)\n' "$floor"
      _ci_problem "$floor" "the $floor floor is no longer a tests/dockerfiles pin - move the floor fixture back, or update _HI_FLOOR_PINS"
    elif ! grep -qxF "$image" <<<"$ignores"; then
      printf '%-48s ERROR (no dependabot ignore holds it)\n' "$floor"
      _ci_problem "$floor" "dependabot.yml has no docker ignore for $image, so a bump PR can move the $floor floor"
    else
      printf '%-48s pinned and ignored\n' "$floor"
    fi
  done
  while IFS= read -r image; do
    [ -n "$image" ] || continue
    case " $_HI_FLOOR_PINS " in *" $image:"*) continue ;; esac
    printf '%-48s ERROR (ignored, but no floor names it)\n' "$image"
    _ci_problem "$image" "dependabot.yml ignores $image, which no floor in check_tool_versions.local.sh names - a stale ignore"
  done <<<"$ignores"
}
