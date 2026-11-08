#!/usr/bin/env bash
# The packer's include scan: lines of an overlay member that name a path no
# target has, and the files a marked line carries instead. Sourced by
# scripts/pack.sh; nothing here rides. GLOSSARY: HI.57 + HI.66
#
# The scan is an awk script, whose `$var`s are awk's to expand (SC2016).
# shellcheck disable=SC2016

# The include scanner, one $_HI_DIALECTS grammar per file
# (ENVIRON[_hi_dialect]). A line naming a path the target lacks would make the
# tool fail there. What each dialect flags, and what it leaves alone:
#
#   vim     `source`/`so` and the managers (`Plug`, `packadd`, `plug#`...);
#           not `runtime` or `$VIMRUNTIME`, which the target has.
#   lua     `dofile`/`loadfile`, a `vim.cmd` source, `require` of anything
#           but `vim.`, and the managers (lazy, packer, paq, `vim.pack.add`,
#           an `rtp:prepend` bootstrap); micro's `AddRuntimeFile` too, not
#           its `import` of Go packages.
#   nano    `include` of anything but a file directly in /usr/share/nano:
#           its `extra/` is Debian's alone, and one bad glob costs the
#           whole rcfile.
#   tmux    `source-file`, `default-shell`, and TPM; a `\` continuation
#           goes with its line. screen: `source`, `shell`, `defshell`.
#   inputrc `$include` of anything but /etc/inputrc.
#   kak     `source` outside %val{runtime}, and the managers.
#   kdl     zellij's `layout_dir`, `theme_dir`, `default_shell`, and any
#           `"file:..."` plugin; a bar pane that loses one gets compact-bar.
#   omp     `extends` of a local file (emptied in JSON, which has no comment).
#   git     an `[include]` path, and the private keys (INTEGRATIONS.md's
#           _git_), matched as lower-cased `<section>.<key>`.
#   elisp   `load`, `load-path`, and the managers; not a bare `require`.
#   sh/fish `source`/`.` outside $_HI_CONFIG_DIR and $_HI_ROOT (a framework
#           theme may also source its own tree, sourced only once
#           _hi_prompt_fw found it), and the managers (zinit, fisher, ...).
#
# Markers (docs/SETTINGS.md): `hi-allow` rides and reports nothing,
# `hi-quiet` drops silently, `hi-carry` is a `carry` row whose files ride
# (_hi_marked_carry), `hi-drop` drops whatever the line says unless an allow
# or carry spares it. Each word pairs `-start`/`-end` on its own; an unclosed
# start is an `unclosed` row, found by reading the file once at FNR == 1
# (blk: lines in a closed pair, bad: unclosed starts). A private line is a
# `private` row, or `allowed` under hi-allow.
#
# mode=report prints `<member>|<line>|<kind>|<text>` rows; mode=fix also
# writes <file>.lint with each finding disabled, for strip.awk to drop. lua,
# elisp, and kdl comment out the whole bracket-balanced expression (bal(),
# blind to strings; ' delimits only in lua); sh and fish turn just the verb
# and its file word into `:` or `true`, since an empty `then` body does not
# parse. wlen() is one shell word's length. `name` is the member's name.
function _hi_lint_awk() {
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function mark(s) {
  if (!match(s, /^[ \t]*(#|"|--|;|\/\/)+[ \t]*hi-(allow|quiet|carry|drop)(-start|-end)?/)) return ""
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
function subj(s,   k) {
  sub(/^[ \t]+/, "", s)
  if (s ~ /^\[/) {
    k = s; sub(/^\[[ \t]*/, "", k); sub(/[] \t"].*/, "", k); sect = tolower(k)
    sub(/^\[[^]]*\][ \t]*/, "", s)
    if (s == "") return ""
  }
  sub(/[ \t]*=.*/, "", s); sub(/[ \t].*/, "", s)
  return sect "." tolower(s)
}
function kindof(s,   t) {
  if (lead != "-" && s ~ ("^[ \t]*" lead)) return ""
  if (index(s, "@@HI_CONFIG@@")) return ""
  if (stmt == "[]") { if (vcont) return ""; s = subj(s); if (s == "") return "" }
  if (plug != "-" && s ~ plug) { fixed = noop " " s; return (stmt == "[]") ? "private" : "plugin" }
  if (inc == "-") return ""
  if (noop != "") { fixed = shfix(s); return (fixed != s) ? "include" : "" }
  t = s
  if (allow != "-") gsub(allow, "", t)
  if (t !~ inc) return ""
  if (blank && match(s, inc)) { t = substr(s, RSTART); sub(/:[ \t]*"[^"]*"/, ": \"\"", t); fixed = substr(s, 1, RSTART - 1) t }
  return "include"
}
FNR == 1 {
  close(out); out = FILENAME ".lint"; depth = allow_l = quiet = drop_l = n = vcont = 0; sect = ""
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
  depth = (stmt == "\\" || stmt == "[]") ? ($0 ~ /\\$/) : depth + bal($0)
  if (depth < 0) depth = 0
  if (mode == "fix") print lead " hi dropped: " $0 > out
  allow_l = quiet = carry_l = drop_l = 0
  next
}
{
  w = mark($0)
  code = w == "" && $0 ~ /[^ \t]/ && !(lead != "-" && $0 ~ ("^[ \t]*" lead))
  carry = (carry_l || (("carry", FNR) in blk)) && code
  spare = carry || allow_l || (("allow", FNR) in blk)
  kind = (spare && stmt != "[]") ? "" : kindof($0)
  if (spare && kind != "") { if (kind == "private") printf "%s|%d|allowed|%s\n", name, FNR, trim($0); kind = "" }
  hush = quiet || (("quiet", FNR) in blk)
  if ((drop_l || (("drop", FNR) in blk)) && code && !spare && lead != "-") {
    hush = 1
    if (kind == "") { kind = "drop"; match($0, /^[ \t]*/); fixed = substr($0, 1, RLENGTH) noop }
  }
  allow_l = (w == "allow"); quiet = (w == "quiet"); carry_l = (w == "carry"); drop_l = (w == "drop")
  if (carry) printf "%s|%d|carry|%s\n", name, FNR, trim($0)
  if (kind == "") { vcont = ($0 ~ /\\$/); if (mode == "fix") print > out; if ($0 ~ /[^ \t]/ && !(lead != "-" && $0 ~ ("^[ \t]*" lead))) prev = $0; next }
  if (!hush) printf "%s|%d|%s|%s\n", name, FNR, kind, trim($0)
  if (mode == "fix" && kind == "plugin" && under != "" && prev ~ under) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) standin > out }
  if (mode == "fix" && stmt == "[]" && match($0, /^[ \t]*\[[^]]*\]/)) print substr($0, 1, RLENGTH) > out
  if (mode == "fix") print ((noop != "" || blank) ? fixed : lead " hi dropped: " $0) > out
  if (stmt ~ /^\(\)/) { depth = bal($0); if (depth < 0) depth = 0 }
  if (stmt == "\\" || stmt == "[]") depth = ($0 ~ /\\$/)
}
AWK
}

# _hi_include_lint - every finding in the overlay members that would actually
# ship, one row each (see _hi_lint_awk); a member with no dialect has none, and
# an include the packer carries (_hi_include_carry) is no finding. A line
# under `hi-carry` is a row only for what of it cannot ride. With <kind>, the
# rows of that kind alone, from the members with nothing to carry.
function _hi_include_lint() {
  local f src prog row m n k t only="${1:-}"
  local -a _hi_dirs=() _hi_carried=() _hi_marked=() _hi_unmarked=()
  prog="$(_hi_lint_awk)"
  while IFS= read -r f; do
    if ! _hi_member_dialect "$f" row || ! _hi_overlay_src "$f" src; then continue; fi
    [ -z "$only" ] || case "$row" in *' | [] | '*) ;; *) continue ;; esac
    _hi_tool_dirs "$f" "$src"
    while IFS='|' read -r m n k t; do
      if [ -n "$only" ]; then
        [ "$k" != "$only" ] || printf '%s|%s|%s|%s\n' "$m" "$n" "$k" "$t"
        continue
      fi
      [ "$k" = include ] && ((${#_hi_dirs[@]})) && _hi_include_carry row "$t" "${f%%/*}" && continue
      # neovim's require of a module that rides (_hi_require_carry)
      [ "$k:${f%%/*}" = include:nvim ] && _hi_require_carry "$t" nvim && continue
      # what a dialect keeps home as private is its job, and no finding
      case "$k" in private | allowed) continue ;; esac
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

# _hi_allowed_lines - the private lines that ride under a `hi-allow`, a
# `<member>|<line>|allowed|<text>` row each, for `hi --plugins` to name
function _hi_allowed_lines() { _hi_include_lint allowed; }

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

# _hi_marked_carry <outvar> <line> <member> - a `hi-carry` line: each file
# under $HOME it names is rewritten to $_HI_CARRY_TOKEN/<tool>/carried/<name>
# (<member>.carried with no tool directory) and added to the caller's
# $_hi_marked; a missing one goes to $_hi_unmarked. Paths outside $HOME are
# the target's. 1 when nothing is carried. GLOSSARY: HI.57
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

# _hi_require_carry <line> <tool> - adds each module <line> requires from a
# lua/ in $_hi_dirs to the caller's $_hi_carried as <tool>/lua/<path>; the
# line stays, found on the runtimepath. 1 when none is carried. GLOSSARY: HI.57
function _hi_require_carry() {
  local _hi_rq_rest="$1" _hi_rq_m _hi_rq_d _hi_rq_f _hi_rq_n=0
  local _hi_rq_re='require[[:space:]]*[(]?[[:space:]]*["'"'"']([A-Za-z0-9_][A-Za-z0-9_./-]*)["'"'"']'
  while [[ $_hi_rq_rest =~ $_hi_rq_re ]]; do
    _hi_rq_m="${BASH_REMATCH[1]}"
    _hi_rq_rest="${_hi_rq_rest#*"${BASH_REMATCH[0]}"}"
    case "$_hi_rq_m" in vim.* | *..*) continue ;; esac
    _hi_rq_m="${_hi_rq_m//.//}"
    for _hi_rq_d in ${_hi_dirs[@]+"${_hi_dirs[@]}"}; do
      _hi_rq_d="${_hi_rq_d%%/lua/*}"
      _hi_rq_d="${_hi_rq_d%/lua}"
      for _hi_rq_f in "lua/$_hi_rq_m.lua" "lua/$_hi_rq_m/init.lua"; do
        [ -f "$_hi_rq_d/$_hi_rq_f" ] || continue
        _hi_carried+=("$2/$_hi_rq_f" "$_hi_rq_d/$_hi_rq_f")
        _hi_rq_n=1
        break 2
      done
    done
  done
  [ "$_hi_rq_n" = 1 ]
}

# _hi_include_carry <outvar> <line> <tool> - <line> with each file it names
# under $_hi_dirs rewritten to $_HI_CARRY_TOKEN/<tool>/<path>, each added to
# the caller's $_hi_carried. ~, $HOME, and $XDG_CONFIG_HOME expand as here.
# 1 when nothing is carried.
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
