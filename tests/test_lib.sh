#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared scaffolding for every suite under tests. The scaffolding itself lives
# in tests/lib/; this file is the one path a suite sources (common/paths.sh
# exports it as $_HI_TEST_LIB), so the parts can be re-cut without touching a
# single suite. Order below is dependency order - report.sh's assertions print
# through its own _hi_align, and every part uses core.sh.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# Isolation, and it has to happen before bootstrap.sh: that resolves
# $_HI_SETTINGS/$_HI_COLORS/$_HI_PACKAGES against $_HI_CONFIG_DIR once, so by
# the time a suite runs it is too late to stop the developer's own
# ~/.config/say-hi from deciding what those point at. Deliberately a path that
# does not exist yet, so the baseline every suite starts from is "no overlay,
# in-tree defaults"; a test wanting an overlay mkdir's this and writes into it,
# and _hi_test_cleanup takes it away again. Same rule as never touching the
# real ~/say-hi.
#
# Both isolated directories live under one root this file makes itself with
# mktemp -d - a fresh name every time, so nothing stale is ever inherited and
# nothing needs deleting up front. _hi_test_cleanup removes that root, by the
# path recorded here, and nothing else on its account: never $XDG_CONFIG_HOME
# or $XDG_RUNTIME_DIR themselves, which a test or a sourcing shell could have
# pointed at a real ~/.config or /run/user/<uid> by then.
_HI_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hi.testroot.XXXXXX")"
export XDG_CONFIG_HOME="$_HI_TEST_ROOT/config"
# Each suite its own runtime dir, too: otherwise every suite running at once
# shares ${TMPDIR:-/tmp}/hi-<uid> - the payload, overlay, and ssh-tags caches
# and the ControlMaster sockets - and one suite's scratch tree seeds a cache
# another reads (or a developer's real sessions, through theirs). Made here,
# since hi only takes $XDG_RUNTIME_DIR when it exists. A case about the runtime
# dir itself names its own.
export XDG_RUNTIME_DIR="$_HI_TEST_ROOT/run"
# no -m 700: mktemp -d made the root 0700 already, and Git Bash refuses a
# mode it cannot map onto Windows ACLs ("cannot change permissions")
mkdir "$XDG_RUNTIME_DIR"
# The developer's ~/.gitconfig is the same hazard for every git fixture:
# `commit.gpgsign` signs each fixture commit with a key CI does not have, and
# `rebase.updateRefs` makes git refuse `rebase --apply` outright, so
# git_prompt's REBASE case never reaches rebase state. Fixtures set their own
# identity (_hi_git_fixture), so nothing here needs the global file.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export _HI_CONFIG_DIR="$XDG_CONFIG_HOME/say-hi"
# ...and the five files that carry a path variable of their own, for the same
# reason one line later. Each takes an explicit value over the overlay's
# ("only when unset", common/paths.sh), so a value inherited from the shell
# that launched the suite - an agent session, a developer's own hi session -
# would be read as a deliberate choice and outrank the $_HI_CONFIG_DIR above.
# paths.sh drops a value still equal to the one it recorded resolving, so an
# ordinary child shell needs no help here - but a shell that predates those
# companions carries the value without the record, and its tree is not this one.
unset _HI_COLORS _HI_PACKAGES _HI_VIMRC _HI_NVIMRC _HI_NANORC _HI_EMACSRC
# The tools' own config variables hi.sh's _hi_overlay_src reads: inherited,
# they would pack the developer's real configs into every overlay stream a
# suite builds. The prompt programs are pinned to hi's own for the same
# reason - unset, whatever this box has installed would draw every prompt -
# and a case about them names its list.
unset STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR MICRO_CONFIG_HOME ZELLIJ_CONFIG_DIR KAKOUNE_CONFIG_DIR POSH_CONFIG POSH_THEME \
  POWERLEVEL9K_CONFIG_FILE ZSH ZSH_CUSTOM ZSH_THEME OSH OSH_CUSTOM OSH_THEME _HI_POWERLINE_GO_OPTS
export _HI_PROMPT_TOOL=hi
# The backend probe cap, pinned: the default 2s is a user's budget for a CLI
# that really answers, and against the suites' shell shims on a loaded BSD VM
# or emulated Git Bash it could run out and flip a row to "not answering". A
# case about the cap sets its own.
export _HI_PROBE_TIMEOUT=10

# The one place the test side resolves a tree. GLOSSARY: HI.33
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# GIT_CONFIG_GLOBAL=/dev/null above also takes the global safe.directory with
# it, and that is what lets git read a checkout another uid owns: the FreeBSD
# job's rsync'd tree, tests/profile.sh's bind mount. Without it every git call
# against this tree dies on "dubious ownership". The tree under test is the one
# repository a suite has to trust, so it rides in command scope - protected
# configuration, the only place git reads safe.directory from - and nothing
# else does: `*` would also trust a .git another user planted above a scratch
# dir. Appended, so a GIT_CONFIG_COUNT the caller already set survives.
_hi_n="${GIT_CONFIG_COUNT:-0}"
export GIT_CONFIG_COUNT=$((_hi_n + 1)) "GIT_CONFIG_KEY_$_hi_n=safe.directory" \
  "GIT_CONFIG_VALUE_$_hi_n=$(cd -P "$_hi_d/.." && pwd)"
unset _hi_n
# shellcheck source=../common/core.sh
source "$_hi_d/../common/core.sh"
# ...and the half of that resolution the unset above cannot reach: paths.sh's
# editor tier reads $HOME/.vimrc, $HOME/.nanorc, $HOME/.emacs.d/init.el and
# friends, which the XDG_CONFIG_HOME throwaway does not move, so on a developer
# box with any of them the baseline stops being "no editor config" and every
# overlay stream a suite builds carries their editor. Pinned *after* the source,
# since paths.sh re-exports over whatever it was handed. A suite exercising the
# tier points them somewhere of its own, as tests/common/paths_test.sh does.
export _HI_VIMRC="" _HI_NVIMRC="" _HI_HELIXRC="" _HI_NANORC="" _HI_EMACSRC="" _HI_TMUX_CONF="" _HI_SCREENRC=""
# ...and ~/.ssh/config the same way: its `# Tags:` lines ride the overlay as
# ssh_tags, so a developer's own would be a member of every stream built here
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

# The standalone-run half of the runner's tree check: with an inherited
# $_HI_TEST_LIB this file can come off a different checkout than the
# $_HI_ROOT core.sh resolved above, and a suite run on its own then
# half-succeeds against two trees with nothing saying so. The runner makes
# this check once per run; a suite reaching here any other way gets the same
# one yellow line. A warning, not a failure, for _hi_host_tree_check's reason.
_hi_host_tree_check "$(_hi_host_resolve "$_hi_d/..")" || true
unset _hi_d
