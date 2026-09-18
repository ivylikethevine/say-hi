#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Sourced (not run) by release.yml's publish job and its package-repository
# step, and by demos.yml's attach job - the one way this repo puts a file on a
# release. CI-only: nothing here runs outside a hosted runner.
#
# Two things went wrong on v0.4.3, and both are answered here.
#
# `gh release upload` takes the whole list in one call, uploads five at a
# time, and ends the command on the first refusal - so the minisign
# signature, the SBOM and the attestation bundle queued behind the rpm never
# went up at all, and the release shipped four assets short of the ones its
# own body tells people to verify against. One call per asset instead, the
# list finished whatever any one of them does, and a closing annotation that
# names every file that did not land.
#
# And the rpm was refused twice, identically, so not a flake to wait out. The
# one property that separates it from the ten assets that did land is the
# Content-Type gh sends: gh picks it off a hardcoded table where `.rpm` is
# `application/x-rpm`, and there is no flag to say otherwise. So the retry
# stops asking gh and posts the upload endpoint itself as octet-stream.
#
# No `set -euo pipefail`: every caller sets its own before sourcing this, and
# a sourced file changing the caller's shell options is a surprise.

# _ci_release_ids <tag> <asset-name> - "<release id><TAB><asset id>", the
# asset id empty when the release carries no asset of that name. One call for
# both: the raw endpoint is addressed by release id, the delete by asset id.
# The name goes through the environment rather than into the jq program,
# where it would need quoting twice.
function _ci_release_ids() {
  CI_ASSET_NAME="$2" gh api "repos/$GITHUB_REPOSITORY/releases/tags/$1" \
    --jq '[.id] + [.assets[] | select(.name == env.CI_ASSET_NAME) | .id] | @tsv'
}

# _ci_upload_asset <tag> <file> - attach one file, whatever it takes. Three
# tries, the name cleared by asset id before each: an attempt GitHub refused
# part way can still be holding it, and `--clobber` deletes only what the
# release's own asset list admits to. Asset names here are all
# [A-Za-z0-9._-], so `?name=` needs no escaping - one that ever does wants
# encoding added here first.
function _ci_upload_asset() {
  local tag="$1" file="$2" name try ids rid aid out
  name="${file##*/}"
  out=""
  for try in 1 2 3; do
    ids=""
    ids="$(_ci_release_ids "$tag" "$name")" || true
    rid="" aid=""
    IFS=$'\t' read -r rid aid <<<"$ids" || :
    [ -z "$aid" ] ||
      gh api --silent --method DELETE \
        "repos/$GITHUB_REPOSITORY/releases/assets/$aid" >/dev/null 2>&1 || true
    if [ "$try" = 1 ]; then
      if out="$(gh release upload "$tag" --repo "$GITHUB_REPOSITORY" \
        --clobber "$file" 2>&1)"; then
        return 0
      fi
    elif [ -n "$rid" ]; then
      if out="$(gh api --method POST \
        "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$rid/assets?name=$name" \
        -H 'Content-Type: application/octet-stream' --input "$file" 2>&1)"; then
        return 0
      fi
    else
      out="no release $tag to attach $name to"
    fi
    [ "$try" = 3 ] && break
    echo "$name did not attach (attempt $try/3), retrying" >&2
    sleep $((try * 5))
  done
  echo "$name did not attach after three tries" >&2
  [ -z "$out" ] || {
    echo "the last answer was:" >&2
    printf '%s\n' "$out" >&2
  }
  return 1
}

# _ci_upload_assets <tag> <file...> - every file, one at a time, and the whole
# list attempted however many of them fail. The failures are collected rather
# than raised where they happen: a release four assets short should say so
# once and by name, not stop at the first and leave whoever reads the log to
# work out what else never went up. A space-joined string, not an array: the
# bash 3.2 sweep reads this file, and an empty array is an unbound variable
# under `set -u` on that bash.
function _ci_upload_assets() {
  local tag="$1" file missing=""
  shift
  [ "$#" -gt 0 ] || {
    echo "_ci_upload_assets: no files to attach to $tag" >&2
    return 1
  }
  for file; do
    _ci_upload_asset "$tag" "$file" || missing="$missing ${file##*/}"
  done
  [ -n "$missing" ] || return 0
  echo "::error title=Release assets::$tag is missing:$missing - re-run this job, or attach them by hand with gh release upload"
  return 1
}
