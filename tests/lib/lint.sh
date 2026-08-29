#!/usr/bin/env bash
# The one piece of lint infra more than one tests/lint/*_test.sh needs: the
# file-listing sweep. run_shellcheck (shellcheck_test.sh) uses it to build the
# *.sh list shellcheck itself reads, and lint_bash32/lint_home_default/
# lint_liquid_docs (drift_test.sh) use it through _hi_lint_mirror and
# _hi_jekyll_md_files. Two different suites, two different processes -
# GLOSSARY: HI.34 says a suite sources test_lib.sh and nothing else, so a
# helper more than one of them needs lives here instead of being copied.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# shellcheck disable=SC2329

# _hi_lint_find <find-name-expr...> - the files a lint sweeps. The exclusions
# live here, not at each caller: packaging/mkpkg.sh stages a *copy* of the tree
# under dist/, so a run after a local package build would lint everything twice
# and report against paths that are not the source. .claude/ is agent scratch.
function _hi_lint_find() {
  find "$_HI_ROOT" \( "$@" \) -not -path '*/.git/*' \
    -not -path "$_HI_ROOT/dist/*" -not -path "$_HI_ROOT/.claude/*" | sort
}
