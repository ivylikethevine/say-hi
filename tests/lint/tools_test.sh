#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The external-tool wrappers that ride along with the lint gate when their
# tool is installed, and skip yellow when it isn't: shfmt as a formatting
# gate, checkbashisms over the #!/bin/sh files, mandoc over the man page, vim and
# emacs over the editor rcs that ship, typos over the whole tree, and
# markdownlint and prettier over the Markdown. CI always has them (setup-tool
# pins each binary; `npm ci --prefix .github` the two node tools), so a local
# skip here is a local-only gap, never a green run that CI would have failed.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# The formatter as a lint: shfmt -d over the same file list shellcheck reads
# (so dist/ stays excluded). The 2-space style comes from .editorconfig, which
# shfmt picks up when invoked with no style flags. Skips yellow when shfmt is
# absent; CI pins one via .github/actions/setup-tool so the gate runs there.
function lint_shfmt() {
  local out
  _hi_h2 "Checking formatting (shfmt -d, style from .editorconfig)"
  _hi_lint_has shfmt || return 0
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(shfmt -d "${_HI_SH_FILES[@]}" 2>&1)"; then
    _hi_align " | shfmt $(shfmt --version): every file already formatted" "OK" "$GREEN"
  else
    _hi_align " | shfmt: files need reformatting (fix with: shfmt -w on the paths below)" "FAILED" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "shfmt formatting (shfmt -w the paths it names)"
    return 1
  fi
}

# Bashisms in the #!/bin/sh files slip past the main linter (they are valid
# bash, and not every POSIX deviation is flagged when checking as sh), and
# common/paths.sh really is sourced by dash/busybox sh on minimal targets -
# checkbashisms covers exactly that shebang list (first line only: the test
# files embed '#!/bin/sh' inside the shim scripts they generate). Skips yellow
# when absent; CI installs a pinned copy via .github/actions/setup-tool.
function lint_checkbashisms() {
  local file rel out shebang bad=0
  _hi_h2 "Checking the #!/bin/sh files for bashisms (checkbashisms)"
  _hi_lint_has checkbashisms || return 0
  for file in "${_HI_SH_FILES[@]}"; do
    # `read` builtin, not `head | grep`: two forks per file over ~110 files,
    # to answer a question about one line
    IFS= read -r shebang <"$file" 2>/dev/null || shebang=""
    case "$shebang" in '#!/bin/sh'*) ;; *) continue ;; esac
    rel="${file#"$_HI_ROOT/"}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$(checkbashisms "$file" 2>&1)"; then
      _hi_align " | $rel" "OK" "$GREEN"
    else
      _hi_align " | $rel" "FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$rel (checkbashisms)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# The man page, parsed. docs/hi.1 ships in every package and parse_test.sh
# drift-checks its flags, but until this nothing ever ran it through a roff
# parser - a macro typo renders as garbage on `man hi` and fails nothing.
# `mandoc -T lint` at warning level: a warning is a page that renders wrong
# somewhere (an unparseable .TH date, say), which is the whole point. Skips
# yellow when mandoc is absent; CI pins one via tools.txt.
function lint_manpage() {
  local man="$_HI_ROOT/docs/hi.1" out
  _hi_h2 "Checking the man page (mandoc -T lint)"
  _hi_lint_has mandoc || return 0
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(mandoc -T lint -W warning "$man" 2>&1)"; then
    _hi_align " | docs/hi.1" "OK" "$GREEN"
  else
    _hi_align " | docs/hi.1" "FAILED" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "docs/hi.1 (mandoc)"
    return 1
  fi
}

# The editors demo's vimrc (docs/tapes/editors/vimrc), parsed by the editor
# that reads it: the demo rides it to a target under `vim -u`, so a syntax
# error in it would show on the recording.
#
# `-u <rc> -es` is the alias's own invocation, and the verdict is $v:errmsg
# written to a file, not stderr and not the exit status: vim prints the error
# to stderr in a full environment but goes silent under the `env -i` a suite
# runs in. v:errmsg is the one signal that survives either.
#
# E484 on defaults.vim is the exception, and a deliberate one: the rc sources
# it with `silent!` because a vim old enough not to ship that file would error
# on it. `silent!` suppresses the message but still sets v:errmsg, so the
# tolerated case is spelled out here.
function lint_vim_rc() {
  local err out rc="$_HI_ROOT/docs/tapes/editors/vimrc"
  _hi_h2 "Checking the editors demo's vimrc (vim -u)"
  _hi_lint_has vim || return 0
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  err="$_HI_WORKDIR/vim.err"
  vim -u "$rc" -es -c "call writefile([v:errmsg], '$err')" -c 'qa!' \
    </dev/null >/dev/null 2>&1 || true
  out="$(grep -v "E484.*defaults\.vim" "$err" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$out" ]; then
    _hi_align " | docs/tapes/editors/vimrc (vim)" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | docs/tapes/editors/vimrc (vim)" "FAILED" "$RED"
  sed 's/^/      /' "$err"
  _hi_note_failure "docs/tapes/editors/vimrc (vim)"
  return 1
}

# Spelling, over everything git tracks (typos honours .gitignore, so dist/ and
# the like stay out). The allowlist is .typos.toml at the root - a term it
# reads wrong goes there with a word on what it is, not into a wider ignore.
# Skips yellow when typos is absent; CI pins one via tools.txt.
function lint_typos() {
  local out
  _hi_h2 "Checking spelling (typos, allowlist in .typos.toml)"
  _hi_lint_has typos || return 0
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(cd "$_HI_ROOT" && typos --format brief --config .typos.toml . 2>&1)"; then
    _hi_align " | typos $(typos --version | awk '{print $2}'): nothing misspelt" "OK" "$GREEN"
  else
    _hi_align " | typos: misspellings below (a term that is right goes in .typos.toml)" "FAILED" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "spelling (typos)"
    return 1
  fi
}

# The Markdown git knows about - tracked, plus new files not yet added, minus
# what .gitignore drops (CLAUDE.local.md) - so a local run and CI's checkout
# read the same list. `-f`: a file deleted but not yet staged is still in the
# index. One path per line; no tracked Markdown name has a newline.
function _hi_md_files() {
  local f
  git -C "$_HI_ROOT" ls-files --cached --others --exclude-standard -- \
    '*.md' ':!:.claude/**' ':!:**/node_modules/**' | while IFS= read -r f; do
    [ -f "$_HI_ROOT/$f" ] && printf '%s\n' "$f"
  done | sort -u
}

# _hi_node_tool <name> - the path of a .github/package.json tool, or nothing
# when `npm ci --prefix .github` has not run or there is no node to run it.
function _hi_node_tool() {
  local bin="$_HI_ROOT/.github/node_modules/.bin/$1"
  [ -x "$bin" ] && command -v node >/dev/null 2>&1 && printf '%s' "$bin"
}

# _hi_lint_md_tool <tool> <heading> <ok> <failed> <note> [arg...] - one
# pinned .github/package.json tool over _HI_MD_FILES, run from the root so it
# reads its config there, with <arg>s before the file list. No version on the
# OK line: .github/package-lock.json already pins it. Skips yellow when the
# pinned copy is not installed or git listed no Markdown; `npm ci --prefix
# .github` installs it.
function _hi_lint_md_tool() {
  local tool="$1" heading="$2" ok="$3" failed="$4" note="$5"
  local bin out
  shift 5
  _hi_h2 "$heading"
  bin="$(_hi_node_tool "$tool")" || {
    _hi_skip "$tool" "not installed (npm ci --prefix .github)"
    return 0
  }
  if [ "${#_HI_MD_FILES[@]}" -eq 0 ]; then
    _hi_skip "$tool" "no Markdown listed (not a git checkout?)"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(cd "$_HI_ROOT" && "$bin" "$@" "${_HI_MD_FILES[@]}" 2>&1)"; then
    _hi_align " | $tool: $ok" "OK" "$GREEN"
  else
    _hi_align " | $tool: $failed" "FAILED" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "$note"
    return 1
  fi
}

# markdownlint over the Markdown, rules from .markdownlint.yaml. Blocking: a
# heading or list slip is cheap to fix on the PR that makes it and a sweep to
# fix later.
function lint_markdownlint() {
  _hi_lint_md_tool markdownlint-cli2 \
    "Checking the Markdown (markdownlint-cli2, rules in .markdownlint.yaml)" \
    "${#_HI_MD_FILES[@]} files clean" "findings below" \
    "Markdown lint (markdownlint-cli2)"
}

# prettier --check over the same list, style from .prettierrc.yaml; files in
# .prettierignore (docs/tldr.md) are skipped even when named.
function lint_prettier() {
  _hi_lint_md_tool prettier \
    "Checking Markdown formatting (prettier --check, style in .prettierrc.yaml)" \
    "every file already formatted" \
    "files need reformatting (fix with: prettier --write on the paths below)" \
    "Markdown formatting (prettier --write the paths it names)" --check
}

function run_tools() {
  _hi_lint_suite_begin "Checking external-tool lints (shfmt, checkbashisms, mandoc, vim, nvim, emacs, typos, markdownlint, prettier)"
  _hi_workdir toolstest

  # the same *.sh list shellcheck_test.sh builds, needed here too since shfmt
  # and checkbashisms are separate processes and cannot read its variable
  local -a _HI_SH_FILES=()
  _hi_read_lines _HI_SH_FILES < <(_hi_lint_find -name '*.sh')

  local -a _HI_MD_FILES=()
  _hi_read_lines _HI_MD_FILES < <(_hi_md_files 2>/dev/null)

  _hi_lint_halves lint_shfmt lint_checkbashisms lint_manpage lint_vim_rc lint_typos \
    lint_markdownlint lint_prettier
  _hi_lint_suite_end
}

run_tools
