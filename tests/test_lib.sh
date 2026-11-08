#!/usr/bin/env bash
# The one file every suite sources ($_HI_TEST_LIB); the parts live in
# tests/lib/, sourced in dependency order.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# Isolation, before paths are resolved: $_HI_CONFIG_DIR is a path that does
# not exist yet, so every suite starts with no overlay, never the developer's.
# The isolated directories sit under one fresh `mktemp -d` root, the only
# thing _hi_test_cleanup removes for them: never $XDG_CONFIG_HOME,
# $XDG_RUNTIME_DIR, or $HOME, which may point at the real ones by then.
_HI_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hi.testroot.XXXXXX")"
export XDG_CONFIG_HOME="$_HI_TEST_ROOT/config"
# Each suite its own runtime dir (made here, since hi only takes one that
# exists), so suites never share caches and sockets with each other or with
# the developer's sessions.
export XDG_RUNTIME_DIR="$_HI_TEST_ROOT/run"
# no -m 700: mktemp -d made the root 0700 already, and Git Bash refuses a
# mode it cannot map onto Windows ACLs ("cannot change permissions")
mkdir "$XDG_RUNTIME_DIR"
# $HOME too, before core.sh, so the developer's ~/.vimrc and the like never
# ride and no shell reads their ~/.zshenv. docker and podman keep their real
# config and storage through their own variables (podman would otherwise
# build storage no cleanup can remove). _HI_TEST_KEEP_HOME=1 skips this.
if [ "${_HI_TEST_KEEP_HOME:-0}" != 1 ]; then
  [ ! -d "$HOME/.docker" ] || export DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  export HOME="$_HI_TEST_ROOT/home"
  mkdir "$HOME"
fi
# The developer's ~/.gitconfig is the same hazard for every git fixture:
# `commit.gpgsign` signs each fixture commit with a key CI does not have, and
# `rebase.updateRefs` makes git refuse `rebase --apply` outright, so
# git_prompt's REBASE case never reaches rebase state. Fixtures set their own
# identity (_hi_git_fixture), so nothing here needs the global file.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export _HI_CONFIG_DIR="$XDG_CONFIG_HOME/say-hi"
# ...and the two files with path variables of their own, since an inherited
# value (from a hi session that launched the suite) would outrank the
# overlay above.
unset _HI_COLORS _HI_PACKAGES
# The tools' config variables _hi_overlay_src reads, so the developer's
# configs never ride (payload_overlay_test.sh pins the list to the plugins'
# home columns); ZDOTDIR also keeps rc.sh's .zshrc in the fixture home. The
# prompt is pinned to hi's own, and the developer's editor unset, since an
# inherited one waits on a terminal.
unset VISUAL EDITOR SUDO_EDITOR STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR MICRO_CONFIG_HOME ZELLIJ_CONFIG_DIR KAKOUNE_CONFIG_DIR POSH_CONFIG POSH_THEME INPUTRC SCREENRC \
  RIPGREP_CONFIG_PATH FZF_DEFAULT_OPTS_FILE LG_CONFIG_FILE ATUIN_CONFIG_DIR \
  POWERLEVEL9K_CONFIG_FILE ZDOTDIR ZSH ZSH_CUSTOM ZSH_THEME OSH OSH_CUSTOM OSH_THEME _HI_POWERLINE_GO_OPTS
export _HI_PROMPT_TOOL=hi
# The backend probe cap, pinned: the default 2s is a user's budget for a CLI
# that really answers, and against the suites' shell shims on a loaded BSD VM
# or emulated Git Bash it could run out and flip a row to "not answering". A
# case about the cap sets its own.
export _HI_PROBE_TIMEOUT=10

# The one place the test side resolves a tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# GIT_CONFIG_GLOBAL=/dev/null drops the global safe.directory, which a tree
# another uid owns needs (the FreeBSD job, tests/profile.sh). So this tree,
# and only it (`*` would trust a planted .git), is trusted in command scope,
# appended to any GIT_CONFIG_COUNT already set.
_hi_n="${GIT_CONFIG_COUNT:-0}" _hi_tl_tree="$(cd -P "$_hi_d/.." && pwd)" || :
export GIT_CONFIG_COUNT=$((_hi_n + 1)) "GIT_CONFIG_KEY_$_hi_n=safe.directory" \
  "GIT_CONFIG_VALUE_$_hi_n=$_hi_tl_tree"
unset _hi_n
# shellcheck source=../common/core.sh
source "$_hi_d/../common/core.sh"
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"
# ~/.ssh/config, pinned after the source, which sets it: its `# Tags:` lines
# ride the overlay as ssh_tags, so under _HI_TEST_KEEP_HOME=1 a developer's
# own would be a member of every stream built here
export _HI_SSH_CONFIG="$XDG_CONFIG_HOME/no-ssh-config"
# the heading rules the harness and the suites print with
# shellcheck source=../scripts/lib.sh
source "$_hi_d/../scripts/lib.sh"

# shellcheck source=./lib/workdir.sh
source "$_hi_d/lib/workdir.sh"
# shellcheck source=./lib/parallel.sh
source "$_hi_d/lib/parallel.sh"
# shellcheck source=./lib/fixtures.sh
source "$_hi_d/lib/fixtures.sh"
# shellcheck source=./lib/report.sh
source "$_hi_d/lib/report.sh"
# shellcheck source=./lib/process.sh
source "$_hi_d/lib/process.sh"
# shellcheck source=./lib/ssh.sh
source "$_hi_d/lib/ssh.sh"
# shellcheck source=./lib/backend.sh
source "$_hi_d/lib/backend.sh"
# shellcheck source=./lib/lint.sh
source "$_hi_d/lib/lint.sh"

# The runner's tree check, for a suite run alone: an inherited $_HI_TEST_LIB
# may come from another checkout than $_HI_ROOT. One yellow line, as in
# _hi_host_tree_check.
_hi_host_tree_check "$_hi_tl_tree" || true
unset _hi_d _hi_tl_tree
