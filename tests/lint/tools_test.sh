#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The external-tool wrappers that ride along with the lint gate when their
# tool is installed, and skip yellow when it isn't: shfmt as a formatting
# gate, checkbashisms over the #!/bin/sh files, mandoc over the man page, vim and
# emacs over the editor rcs that ship, and typos over the whole tree. CI always has them
# (setup-tool actions pin each one), so a local skip here is a local-only gap,
# never a green run that CI would have failed.
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
  if ! command -v shfmt >/dev/null 2>&1; then
    _hi_skip "shfmt" "not installed"
    return 0
  fi
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
  if ! command -v checkbashisms >/dev/null 2>&1; then
    _hi_skip "checkbashisms" "not installed"
    return 0
  fi
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
  if ! command -v mandoc >/dev/null 2>&1; then
    _hi_skip "mandoc" "not installed"
    return 0
  fi
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

# The vim rc hi ships, parsed by the editor that reads it. Everything else in
# the suite treats settings/vim.rc as *bytes* - payload_test.sh checks it ships
# and survives the comment strip, load_test.sh checks $VIMINIT points at it - so
# a syntax error in the file itself failed nothing and rode the wire to every
# target (an orphaned `endif` left by a half-finished deletion did exactly
# that). vim only: settings/aliases.sh points neovim at settings/init.lua now,
# which lint_nvim_rc below parses with the editor that reads it.
#
# `-u <rc> -es` is the production invocation (the alias's own), and the verdict
# is $v:errmsg written to a file, not stderr and not the exit status: vim
# prints the error to stderr in a full environment but goes silent under the
# `env -i` a suite runs in. v:errmsg is the one signal that survives either.
#
# E484 on defaults.vim is the exception, and a deliberate one: the rc sources
# it with `silent!` precisely because a vim old enough not to ship that file
# would error on it (settings/vim.rc says so). `silent!` suppresses the
# message but still sets v:errmsg, so the tolerated case is spelled out here.
#
# No nano half: nano reports a bad rcfile only on its status bar and refuses to
# start without a terminal, so there is nothing to assert on offline.
#
# The emacs half is lint_emacs_rc below: `--batch -q -l` loads the file the
# way the alias does and exits non-zero on an elisp error, so there the exit
# status is the verdict.
function lint_vim_rc() {
  local err out rc="$_HI_ROOT/settings/vim.rc"
  _hi_h2 "Checking the shipped editor rc (vim -u settings/vim.rc)"
  if ! command -v vim >/dev/null 2>&1; then
    _hi_skip vim "not installed"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  err="$_HI_WORKDIR/vim.err"
  vim -u "$rc" -es -c "call writefile([v:errmsg], '$err')" -c 'qa!' \
    </dev/null >/dev/null 2>&1 || true
  out="$(grep -v "E484.*defaults\.vim" "$err" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$out" ]; then
    _hi_align " | settings/vim.rc (vim)" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | settings/vim.rc (vim)" "FAILED" "$RED"
  sed 's/^/      /' "$err"
  _hi_note_failure "settings/vim.rc (vim)"
  return 1
}

# The neovim rc, parsed by the editor that reads it. `--headless -u <rc>` is
# the alias's own invocation and runs the file as lua; unlike the vim half both
# signals are usable here - a lua error goes to stderr and nvim exits non-zero -
# so the verdict is a clean exit with nothing written.
function lint_nvim_rc() {
  local err rc="$_HI_ROOT/settings/init.lua"
  _hi_h2 "Checking the shipped editor rc (nvim -u settings/init.lua)"
  if ! command -v nvim >/dev/null 2>&1; then
    _hi_skip nvim "not installed"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  err="$_HI_WORKDIR/initlua.err"
  if nvim --headless -u "$rc" -c 'qa!' </dev/null >/dev/null 2>"$err" && [ ! -s "$err" ]; then
    _hi_align " | settings/init.lua (nvim)" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | settings/init.lua (nvim)" "FAILED" "$RED"
  sed 's/^/      /' "$err"
  _hi_note_failure "settings/init.lua (nvim)"
  return 1
}

function lint_emacs_rc() {
  local err rc="$_HI_ROOT/settings/emacs.el"
  _hi_h2 "Checking the shipped editor rc (emacs -q -l settings/emacs.el)"
  if ! command -v emacs >/dev/null 2>&1; then
    _hi_skip emacs "not installed"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  err="$_HI_WORKDIR/emacs.err"
  if emacs --batch -q -l "$rc" --eval '(kill-emacs 0)' </dev/null >"$err" 2>&1; then
    _hi_align " | settings/emacs.el (emacs)" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | settings/emacs.el (emacs)" "FAILED" "$RED"
  sed 's/^/      /' "$err"
  _hi_note_failure "settings/emacs.el (emacs)"
  return 1
}

# Spelling, over everything git tracks (typos honours .gitignore, so dist/ and
# the like stay out). The allowlist is .typos.toml at the root - a term it
# reads wrong goes there with a word on what it is, not into a wider ignore.
# Skips yellow when typos is absent; CI pins one via tools.txt.
function lint_typos() {
  local out
  _hi_h2 "Checking spelling (typos, allowlist in .typos.toml)"
  if ! command -v typos >/dev/null 2>&1; then
    _hi_skip "typos" "not installed"
    return 0
  fi
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

function run_tools() {
  _hi_lint_suite_begin "Checking external-tool lints (shfmt, checkbashisms, mandoc, vim, nvim, emacs, typos)"
  _hi_workdir toolstest

  # the same *.sh list shellcheck_test.sh builds, needed here too since shfmt
  # and checkbashisms are separate processes and cannot read its variable
  local -a _HI_SH_FILES=()
  _hi_read_lines _HI_SH_FILES < <(_hi_lint_find -name '*.sh')

  _hi_lint_halves lint_shfmt lint_checkbashisms lint_manpage lint_vim_rc lint_nvim_rc lint_emacs_rc lint_typos
  _hi_lint_suite_end
}

run_tools
