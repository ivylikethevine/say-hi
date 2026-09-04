#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Builds the source tarball a release ships, and nothing else.
#
# Its own entry point rather than a line of YAML in .github/workflows/release.yml
# because packaging/bump.sh needs the same bytes: the manifests checksum this
# tarball, so the release has to attach the very file they were summed from. One
# implementation in packaging/lib.sh (src_tarball), two callers, no `git archive`
# invocation spelled twice with a prefix that has to match by luck.
#
# Usage: srctar.sh <version> <ref> <outfile>

# strict mode comes back on with the source: lib.sh ends with `set -euo
# pipefail` after core.sh turned it off
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

_HI_USAGE="Usage: srctar.sh <version> <ref> <outfile>"

case "${1:-}" in
-h | --help)
  cat <<USAGE
$_HI_USAGE

Writes a say-hi-<version>.tar.gz of <ref> to <outfile>, with the
say-hi-<version>/ prefix the AUR package's prepare() expects. <ref> is a tag
on a release and HEAD on a rehearsal.
USAGE
  exit 0
  ;;
esac

[ $# -eq 3 ] || {
  echo "srctar.sh: expected <version> <ref> <outfile>" >&2
  echo "$_HI_USAGE" >&2
  exit 1
}

src_tarball "$1" "$2" "$3"
_hi_cecho " $3 :)" "$GREEN"
