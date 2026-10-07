#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The packer's include scan: every line of an overlay member that names a
# path no target has, in each dialect hi ships, and the files a marked line
# carries along instead. Sourced by scripts/pack.sh, never run, and like it
# nothing here rides in the payload. GLOSSARY: HI.57 + HI.66
#
# The scan is an awk script, whose `$var`s are awk's to expand (SC2016).
# shellcheck disable=SC2016

# The include scanner, in the dialect of each file it reads. Every member
# ships into the target's `config/`, so a line naming a *path* - a second rc
# beside it, a plugin directory, a manager's bootstrap - names something no
# target has, and the editor or shell fails on it rather than hi. The
# grammars are $_HI_DIALECTS rows, the file's read from ENVIRON[_hi_dialect];
# what each finds, and what it deliberately leaves alone:
#
#   vim     `source`/`so` (a path), the managers' verbs (`Plug`, `packadd`,
#           `plug#`/`vundle#`/`dein#`). `runtime` is *not* flagged: it
#           searches the target vim's own &runtimepath, which is there.
#           `source $VIMRUNTIME/...` is the same argument.
#   lua     `dofile`/`loadfile`, a `vim.cmd` carrying `source`, `require` of
#           anything but a `vim.` module, and the managers (lazy, packer,
#           paq, neovim's own `vim.pack.add`, an `rtp:prepend` bootstrap).
#           micro's init.lua reads the same, plus `AddRuntimeFile` (a plugin
#           with `RTPlugin`); its `import` names micro's own Go packages and
#           is left alone.
#   nano    `include` of anything but a path *directly* under
#           /usr/share/nano, which the nano package itself ships. A
#           subdirectory of it is not: /usr/share/nano/extra is a Debian
#           split that Fedora, Alpine, and macOS do not have, and a glob
#           matching nothing costs the whole rcfile - nano says "Mistakes in
#           '<rcfile>'" on the status bar and rings the bell. The path is
#           read as one word, so a trailing comment cannot fool the rule.
#   tmux    `source-file`/`source` of a path, a `default-shell` (a path on
#           the client: without it a pane opens on the session's $SHELL), and
#           TPM (`@plugin`, a `run` of tpm). Line-oriented, but a finding
#           ending in `\` takes its continuation lines with it.
#   screen  `source` of a file, and `shell`/`defshell`, as tmux's.
#   inputrc `$include` of anything but /etc/inputrc, the system file an
#           $INPUTRC stops readline reading on its own.
#   kak     `source` of anything but %val{runtime}'s (the target's own), and
#           the managers (plug.kak's `plug`, kak-bundle's `bundle`).
#   kdl     zellij's `layout_dir`/`theme_dir` (its own layouts/ and themes/
#           ride beside config.kdl), its `default_shell`, as tmux's, and a
#           plugin at a `"file:..."` wherever one is named: a layout's
#           `location=`, a `LaunchOrFocusPlugin`, `load_plugins`. A layout's
#           borderless pane that loses its plugin is a bar, and gets
#           zellij's own compact-bar: left empty, it opens as a shell.
#   omp     oh-my-posh's `extends` naming a local file; a URL or a theme name
#           resolves on the target. JSON has no comment, so there the value is
#           emptied, which oh-my-posh reads as no base; yaml and toml comment it.
#   elisp   `load`/`load-file`, `add-to-list 'load-path`, and the managers
#           (`package-initialize`, `use-package`, straight, elpaca). A bare
#           `require` is left alone: nearly every one names a built-in.
#   sh/fish `source`/`.` of anything but a path under $_HI_CONFIG_DIR or
#           $_HI_ROOT (which ride along), a process substitution, or - in a
#           framework's theme only (omz, omb, bash-it) - under that
#           framework's own tree ($ZSH, $OSH, $BASH_IT): hi sources a theme only once
#           _hi_prompt_fw has found the tree on the target, where every other
#           member runs with it unset. Also the zsh/fish managers' verbs
#           (zinit, zplug, antigen, fisher, ...). An extension is sh.
#
# A line directly under a `hi-allow` comment, in the file's own comment
# syntax, is neither reported nor touched; one under `hi-quiet` is still
# disabled, just not reported - a line you know no target has. A pair,
# `hi-allow-start` and `hi-allow-end` or `hi-quiet-start` and `hi-quiet-end`,
# decides every line inside it the same way. Each word pairs on its own, a
# start with the next end of its word, so an allow pair inside a quiet one
# keeps its lines. A line under `hi-carry`, or inside its pair, is neither: it
# is a `carry` row in either mode, never dropped, and the stager rides the
# files it names (_hi_marked_carry). A start with no end below it, or with a second start of
# its word before one, decides nothing and is an `unclosed` row; an end with
# no start is ignored. Whether a start is closed is known only at the end of
# the file, so FNR == 1 reads the file through once with getline before the
# scan: blk holds the lines inside a closed pair, bad the starts with no end.
# mark() is the marker a comment line opens with, whole, so `hi-allow` and
# `hi-allow-start` are never read as each other.
#
# mode=report prints one `<member>|<line>|<kind>|<text>` row per finding and
# leaves the file alone; mode=fix also writes <file>.lint with each finding
# disabled - which strip.awk then drops, so a dropped line costs no wire bytes.
# vim and nano are line-oriented, so one line is the whole statement; lua,
# elisp, and kdl are not, so the comment runs to the end of the bracket-balanced
# expression the finding opened, or a `require("x").setup {` would leave its
# closing brace behind as a syntax error. sh and fish get neither: commenting
# a line can empty a `then`/`do` body, which does not parse, so only the verb
# and its file word become `:` (fish: `true`), and the rest of the line stays.
# `name` is the member, not FILENAME: doctor reads ~/.vimrc under its own name.
#
# bal() counts that depth blind to anything inside a quoted string, and takes
# ' as a string delimiter only where <end> says so (lua): in elisp it is the
# quote operator, and reading `'load-path` as an opening quote swallows the
# rest of the file.
# wlen() is the length of one shell word, quotes and $(...) nesting included.
# Nothing in the AWK body carries a `#` comment - strip.awk spares a heredoc
# body, so every one of them would ride the wire on every connect.
function _hi_lint_awk() {
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function mark(s) {
  if (!match(s, /^[ \t]*(#|"|--|;|\/\/)+[ \t]*hi-(allow|quiet|carry)(-start|-end)?/)) return ""
  s = substr(s, RSTART, RLENGTH); sub(/.*hi-/, "", s)
  return s
}
function bal(s,   i, c, q, d) {
  d = 0; q = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") i++; else if (c == q) q = ""; continue }
    if (c == "\"" || (stmt == "()'" && c == "'")) { q = c; continue }
    if (c == "(" || c == "{" || c == "[") d++
    else if (c == ")" || c == "}" || c == "]") d--
  }
  return d
}
function wlen(s,   i, c, q, d) {
  q = ""; d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == q) q = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "\"") { q = (q == "" ? c : ""); continue }
    if (c == "'" && q == "") { q = c; continue }
    if (c == "(" || c == "{") d++
    else if (c == ")" || c == "}") { if (--d < 0) return i - 1 }
    else if (q == "" && d == 0 && c ~ /[ \t;&|]/) return i - 1
  }
  return length(s)
}
function shfix(s,   o, p, r, n, w) {
  o = ""; s = ";" s
  while (match(s, inc)) {
    p = substr(s, 1, RSTART + RLENGTH - 1); r = substr(s, RSTART + RLENGTH)
    n = wlen(r); w = substr(r, 1, n)
    if (w == "" || w ~ /^\\/ || (allow != "-" && w ~ allow) || w ~ /^[<=]?\(/) { o = o p; s = r; continue }
    sub(/[^;&|{() \t]+[ \t]+$/, "", p)
    o = o p noop; s = substr(r, n + 1)
  }
  return substr(o s, 2)
}
function kindof(s,   t) {
  if (lead != "-" && s ~ ("^[ \t]*" lead)) return ""
  if (index(s, "@@HI_CONFIG@@")) return ""
  if (plug != "-" && s ~ plug) { fixed = noop " " s; return "plugin" }
  if (inc == "-") return ""
  if (noop != "") { fixed = shfix(s); return (fixed != s) ? "include" : "" }
  t = s
  if (allow != "-") gsub(allow, "", t)
  if (t !~ inc) return ""
  if (blank && match(s, inc)) { t = substr(s, RSTART); sub(/:[ \t]*"[^"]*"/, ": \"\"", t); fixed = substr(s, 1, RSTART - 1) t }
  return "include"
}
FNR == 1 {
  close(out); out = FILENAME ".lint"; depth = allow_l = quiet = n = 0
  split("", blk); split("", bad); split("", from)
  while ((getline l < FILENAME) > 0) {
    n++; w = k = mark(l); sub(/-.*/, "", k)
    if (w ~ /-start/) { if (k in from) bad[from[k]] = 1; from[k] = n }
    else if (w ~ /-end/ && (k in from)) { for (i = from[k] + 1; i < n; i++) blk[k, i] = 1; delete from[k] }
  }
  close(FILENAME)
  for (k in from) bad[from[k]] = 1
  split(ENVIRON["_hi_dialect"], f, / [|] /)
  for (i = 6; i <= 8; i++) gsub(/\\t/, "\t", f[i])
  lead = f[2]; stmt = f[4]; noop = f[5]; plug = f[6]; inc = f[7]; allow = f[8]
  blank = (noop == "\"\""); if (noop == "comment" || blank) noop = ""
  under = standin = prev = ""; i = index(f[9], " => ")
  if (i) { under = substr(f[9], 1, i - 1); standin = substr(f[9], i + 4); gsub(/\\t/, "\t", under) }
}
FNR in bad { printf "%s|%d|unclosed|%s\n", name, FNR, trim($0) }
depth > 0 {
  depth = (stmt == "\\") ? ($0 ~ /\\$/) : depth + bal($0)
  if (depth < 0) depth = 0
  if (mode == "fix") print lead " hi dropped: " $0 > out
  allow_l = quiet = carry_l = 0
  next
}
{
  w = mark($0)
  carry = (carry_l || (("carry", FNR) in blk)) && w == "" && $0 ~ /[^ \t]/ && !(lead != "-" && $0 ~ ("^[ \t]*" lead))
  kind = (carry || allow_l || (("allow", FNR) in blk)) ? "" : kindof($0)
  hush = quiet || (("quiet", FNR) in blk)
  allow_l = (w == "allow"); quiet = (w == "quiet"); carry_l = (w == "carry")
  if (carry) printf "%s|%d|carry|%s\n", name, FNR, trim($0)
  if (kind == "") { if (mode == "fix") print > out; if ($0 ~ /[^ \t]/ && !(lead != "-" && $0 ~ ("^[ \t]*" lead))) prev = $0; next }
  if (!hush) printf "%s|%d|%s|%s\n", name, FNR, kind, trim($0)
  if (mode == "fix" && kind == "plugin" && under != "" && prev ~ under) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) standin > out }
  if (mode == "fix") print ((noop != "" || blank) ? fixed : lead " hi dropped: " $0) > out
  if (stmt ~ /^\(\)/) { depth = bal($0); if (depth < 0) depth = 0 }
  if (stmt == "\\") depth = ($0 ~ /\\$/)
}
AWK
}

# _hi_include_lint - every finding in the overlay members that would actually
# ship, one row each (see _hi_lint_awk); a member with no dialect has none, and
# an include the packer carries (_hi_include_carry) is no finding. A line
# under `hi-carry` is a row only for what of it cannot ride.
function _hi_include_lint() {
  local f src prog row m n k t
  local -a _hi_dirs=() _hi_carried=() _hi_marked=() _hi_unmarked=()
  prog="$(_hi_lint_awk)"
  while IFS= read -r f; do
    if ! _hi_member_dialect "$f" row || ! _hi_overlay_src "$f" src; then continue; fi
    _hi_tool_dirs "$f" "$src"
    while IFS='|' read -r m n k t; do
      [ "$k" = include ] && ((${#_hi_dirs[@]})) && _hi_include_carry row "$t" "${f%%/*}" && continue
      if [ "$k" = carry ]; then
        _hi_unmarked=()
        _hi_marked_carry t "$t" "$f" || true
        for t in ${_hi_unmarked[@]+"${_hi_unmarked[@]}"}; do printf '%s|%s|%s|%s\n' "$m" "$n" "$k" "$t"; done
        continue
      fi
      printf '%s|%s|%s|%s\n' "$m" "$n" "$k" "$t"
    done < <(_hi_dialect="$row" awk -v mode=report -v name="$f" "$prog" "$src")
  done < <(_hi_overlay_files)
  return 0
}

# _hi_tool_dirs <member> <source> - the directories an include in <member> is
# carried from, into the caller's $_hi_dirs: the source's own directory (not
# $HOME's), and $XDG_CONFIG_HOME/<tool>, ~/.<tool>, and ~/.<tool>.d for the
# member's directory <tool>. None for a member with no directory.
function _hi_tool_dirs() {
  local _hi_td_t="${1%%/*}" _hi_td_s="${2%/*}"
  _hi_dirs=()
  [ "$_hi_td_t" != "$1" ] || return 0
  [ "$_hi_td_s" = "$HOME" ] || [ "$_hi_td_s" = "$2" ] || _hi_dirs+=("$_hi_td_s")
  _hi_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/$_hi_td_t" "$HOME/.$_hi_td_t" "$HOME/.$_hi_td_t.d")
}

# _hi_carry_path <text> <outvar> - a path $_HI_CARRY_RE matched, as it is
# here: ~, $HOME, and $XDG_CONFIG_HOME read as this machine's
function _hi_carry_path() {
  # shellcheck disable=SC2088 # a ~ the line wrote, matched as text
  case "$1" in
  '~/'*) printf -v "$2" '%s' "$HOME/${1#'~/'}" ;;
  '$HOME/'* | '${HOME}/'*) printf -v "$2" '%s' "$HOME/${1#*/}" ;;
  '$XDG_CONFIG_HOME/'* | '${XDG_CONFIG_HOME}/'*) printf -v "$2" '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/${1#*/}" ;;
  *) printf -v "$2" '%s' "$1" ;;
  esac
}

# _hi_marked_carry <outvar> <line> <member> - a line under `hi-carry`: each
# path in it that names a file under $HOME is rewritten to
# $_HI_CARRY_TOKEN/<dir>/<name> - <dir> the member's directory's carried/,
# or <member>.carried for a member with no directory - and appended to the
# caller's $_hi_marked as a <member> <source> pair; a second file of a name
# rides under its directory's name too. A path under $HOME that is no file,
# or a line naming none, is said in the caller's $_hi_unmarked. A path
# outside $HOME is the target's own, and left as written. 1 when no path is
# carried. GLOSSARY: HI.57
function _hi_marked_carry() {
  local _hi_mc_rest="$2" _hi_mc_out="" _hi_mc_t _hi_mc_p _hi_mc_d _hi_mc_f _hi_mc_i _hi_mc_n=0 _hi_mc_h=0
  case "$3" in */*) _hi_mc_d="${3%%/*}/carried" ;; *) _hi_mc_d="$3.carried" ;; esac
  while [[ $_hi_mc_rest =~ $_HI_CARRY_RE ]]; do
    _hi_mc_t="${BASH_REMATCH[0]}"
    _hi_mc_out+="${_hi_mc_rest%%"$_hi_mc_t"*}"
    _hi_mc_rest="${_hi_mc_rest#*"$_hi_mc_t"}"
    _hi_carry_path "$_hi_mc_t" _hi_mc_p
    if [ "${_hi_mc_p#"$HOME"/}" != "$_hi_mc_p" ]; then
      _hi_mc_h=1
      if [ -f "$_hi_mc_p" ]; then
        _hi_mc_f="${_hi_mc_p##*/}"
        for ((_hi_mc_i = 0; _hi_mc_i < ${#_hi_marked[@]}; _hi_mc_i += 2)); do
          [ "${_hi_marked[_hi_mc_i]}" = "$_hi_mc_d/$_hi_mc_f" ] && [ "${_hi_marked[_hi_mc_i + 1]}" != "$_hi_mc_p" ] || continue
          _hi_mc_f="${_hi_mc_p%/*}"
          _hi_mc_f="${_hi_mc_f##*/}-${_hi_mc_p##*/}"
        done
        _hi_marked+=("$_hi_mc_d/$_hi_mc_f" "$_hi_mc_p")
        _hi_mc_t="$_HI_CARRY_TOKEN/$_hi_mc_d/$_hi_mc_f" _hi_mc_n=1
      else
        _hi_unmarked+=("$_hi_mc_t is no file here")
      fi
    fi
    _hi_mc_out+="$_hi_mc_t"
  done
  [ "$_hi_mc_h" = 1 ] || _hi_unmarked+=("names no path under your home directory")
  printf -v "$1" '%s' "$_hi_mc_out$_hi_mc_rest"
  [ "$_hi_mc_n" = 1 ]
}

# _hi_include_carry <outvar> <line> <tool> - <line> with each path in it that
# names a file under one of the caller's $_hi_dirs rewritten to
# $_HI_CARRY_TOKEN/<tool>/<its path under that directory>, into <outvar>,
# and each such file appended to the caller's $_hi_carried as a <member>
# <source> pair; 1 when no path is carried. ~, $HOME, and $XDG_CONFIG_HOME
# are read as they are here.
function _hi_include_carry() {
  local _hi_ic_rest="$2" _hi_ic_out="" _hi_ic_t _hi_ic_p _hi_ic_d _hi_ic_r _hi_ic_n=0
  while [[ $_hi_ic_rest =~ $_HI_CARRY_RE ]]; do
    _hi_ic_t="${BASH_REMATCH[0]}"
    _hi_ic_out+="${_hi_ic_rest%%"$_hi_ic_t"*}"
    _hi_ic_rest="${_hi_ic_rest#*"$_hi_ic_t"}"
    _hi_carry_path "$_hi_ic_t" _hi_ic_p
    for _hi_ic_d in ${_hi_dirs[@]+"${_hi_dirs[@]}"}; do
      _hi_ic_r="${_hi_ic_p#"$_hi_ic_d"/}"
      [ "$_hi_ic_r" != "$_hi_ic_p" ] && [ -f "$_hi_ic_p" ] || continue
      case "/$_hi_ic_r/" in */../* | */./*) continue ;; esac
      _hi_carried+=("$3/$_hi_ic_r" "$_hi_ic_p")
      _hi_ic_t="$_HI_CARRY_TOKEN/$3/$_hi_ic_r" _hi_ic_n=1
      break
    done
    _hi_ic_out+="$_hi_ic_t"
  done
  printf -v "$1" '%s' "$_hi_ic_out$_hi_ic_rest"
  [ "$_hi_ic_n" = 1 ]
}
