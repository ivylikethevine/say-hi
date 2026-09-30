#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rewrites overlay files still in a shape this hi no longer reads, in place,
# keeping each original beside it as <file>.old:
#   packages     "[-|+]name:N,..." rows, or "[-|+]name,..." rows under
#                [group] lines -> TOML tables of name = [...] rows
#   colors       "type,name,color[,rrggbb]" rows, or "name color [rrggbb]"
#                rows under [type] lines -> TOML tables of name = "..." rows
#   carry        "member | tool | wire | home" lines -> plugins, TOML rows
#                of the same columns under [carry]
#   settings.sh  _HI_PACKAGES_MIN_PRIORITY -> _HI_PACKAGES_GROUPS; the
#                _HI_DISABLE_TOOL_ALIASES/_HI_DISABLE_SUDO_ALIAS lines dropped;
#                an editor's or a multiplexer's _HI_DISABLE_* -> its word in
#                _HI_PLUGINS_OFF
# A file already in the current shape is left alone, so a second run is a
# no-op. scripts/install.sh (--install, --configure) and scripts/update.sh
# run it; add_package.sh's shape: HI.33 the standalone entry, HI.09 the
# commit step.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
# shellcheck source=./table.sh
source "$_hi_d/scripts/table.sh"
unset _hi_d

# _hi_convert_packages - stdin's name:N rows as [group] sections on stdout.
# A row goes to the group its highest N named (3 core, 2 useful, 1 extras,
# 0 trivia), alternatives sorted highest N first, file order within one. An
# old `-` row (shown only when missing) becomes a `+` row, those at N 0-1 in
# [base]; an old `+` row (shown only when installed) has no counterpart and
# becomes a plain row in [platform]. Comments travel with the row below them;
# those above the first row stay on top.
function _hi_convert_packages() {
  awk '
    function flush_to(g, row) {
      body[g] = body[g] pend row "\n"
      pend = ""
    }
    /^[ \t]*$/ { next }
    /#/ {
      if (!seen) head = head $0 "\n"; else pend = pend $0 "\n"
      next
    }
    {
      seen = 1
      line = $0
      gsub(/[ \t]/, "", line)
      m = substr(line, 1, 1)
      if (m == "-" || m == "+") line = substr(line, 2); else m = ""
      n = split(line, alt, ",")
      max = 0
      for (i = 1; i <= n; i++) {
        p = alt[i]; sub(/^[^:]*:?/, "", p)
        p = (p ~ /^[0-9]+$/) ? p + 0 : 0
        if (p > 3) p = 3
        nm[i] = alt[i]; sub(/:.*/, "", nm[i]); pr[i] = p
        if (p > max) max = p
      }
      # stable insertion sort, highest N first
      for (i = 2; i <= n; i++) {
        tn = nm[i]; tp = pr[i]
        for (j = i - 1; j >= 1 && pr[j] < tp; j--) { nm[j + 1] = nm[j]; pr[j + 1] = pr[j] }
        nm[j + 1] = tn; pr[j + 1] = tp
      }
      row = nm[1]
      for (i = 2; i <= n; i++) row = row "," nm[i]
      if (m == "+") { flush_to("platform", row); next }
      g = (max == 3) ? "core" : (max == 2) ? "useful" : (max == 1) ? "extras" : "trivia"
      if (m == "-") { row = "+" row; if (max < 2) g = "base" }
      flush_to(g, row)
    }
    END {
      printf "%s", head
      split("core useful extras trivia base platform", order, " ")
      for (k = 1; k <= 6; k++) {
        g = order[k]
        if (body[g] == "") continue
        printf "\n[%s]\n%s", g, body[g]
      }
      if (pend != "") printf "\n%s", pend
    }
  '
}

# _hi_convert_colors - stdin's type,name,color[,rrggbb] rows as [type]
# sections of "name color [rrggbb]" on stdout, types in the order they first
# appear and rows in file order within one, so a pattern keeps its place.
# Comments above the first row stay on top; the rest travel with the row below.
function _hi_convert_colors() {
  awk '
    /^[ \t]*$/ { next }
    /^[ \t]*#/ {
      if (!seen) head = head $0 "\n"; else pend = pend $0 "\n"
      next
    }
    {
      seen = 1
      n = split($0, f, ",")
      t = f[1]; gsub(/[ \t]/, "", t)
      if (!(t in body)) { types[++nt] = t; body[t] = "" }
      row = f[2] "\037" f[3]
      if (n >= 4 && f[4] != "") row = row " " f[4]
      body[t] = body[t] pend row "\n"
      pend = ""
    }
    END {
      printf "%s", head
      for (k = 1; k <= nt; k++) printf "\n[%s]\n%s", types[k], body[types[k]]
      if (pend != "") printf "\n%s", pend
    }
  ' | _hi_pad_cols 15
}

# _hi_toml_packages - stdin's `[group]` sections of "[-|+]name,..." rows as
# TOML on stdout: a group's plain rows under `[group]`, its + rows under
# `[group.required]`, its - rows under `[group.unwanted]`, each
# `name = ["alternative", ...]`. A table is written once, so a group's rows
# gather by kind, in file order within one. A line holding a #, which nothing
# read, is a comment; comments travel with the row or the group below them.
function _hi_toml_packages() {
  awk '
    function key(n) { return (n ~ /^[A-Za-z0-9_-]+$/) ? n : "\"" n "\"" }
    function group(g) {
      if (!(g in known)) { known[g] = 1; order[++ng] = g }
    }
    function table(g, k) {
      if (body[g, k] == "" && (k != "" || body[g, "required"] body[g, "unwanted"] != "")) return
      if (g k != "") {
        printf "%s%s[%s%s%s]\n", (out ? "\n" : ""), above[g], g, (g != "" && k != "" ? "." : ""), k
        above[g] = ""
      }
      printf "%s", body[g, k]
      out = 1
    }
    /^[ \t]*$/ {
      if (!seen) { head = head pend "\n"; pend = "" }
      next
    }
    /#/ {
      sub(/^[ \t]+/, "")
      pend = pend (/^#/ ? "" : "# ") $0 "\n"
      next
    }
    /^[ \t]*\[.*\][ \t]*$/ {
      seen = 1
      g = $0; gsub(/[][ \t]/, "", g)
      group(g)
      above[g] = above[g] pend; pend = ""
      next
    }
    {
      seen = 1
      line = $0
      gsub(/[ \t]/, "", line)
      m = substr(line, 1, 1)
      k = (m == "+") ? "required" : (m == "-") ? "unwanted" : ""
      if (k != "") line = substr(line, 2)
      n = split(line, alt, ",")
      row = ""
      for (i = 2; i <= n; i++) row = row (i > 2 ? ", " : "") "\"" alt[i] "\""
      group(g)
      body[g, k] = body[g, k] pend key(alt[1]) " = [" row "]\n"
      pend = ""
    }
    END {
      sub(/\n+$/, "\n", head)
      if (head == "\n") head = ""
      printf "%s", head
      out = (head != "")
      for (j = 1; j <= ng; j++) {
        table(order[j], "")
        table(order[j], "required")
        table(order[j], "unwanted")
      }
      if (pend != "") printf "%s%s", (out ? "\n" : ""), pend
    }
  '
}

# _hi_toml_colors - stdin's `[type]` sections of "name color [rrggbb]" rows as
# TOML on stdout: `name = "color [rrggbb]"` under `[type]`, a table written
# once and its rows in file order. What followed a row's color and was no
# hex, which nothing read, is a comment behind the row.
function _hi_toml_colors() {
  awk '
    function key(n) { return (n ~ /^[A-Za-z0-9_-]+$/) ? n : "\"" n "\"" }
    /^[ \t]*$/ {
      if (!seen) { head = head pend "\n"; pend = "" }
      next
    }
    /^[ \t]*#/ {
      sub(/^[ \t]+/, "")
      pend = pend $0 "\n"
      next
    }
    /^[ \t]*\[.*\][ \t]*$/ {
      seen = 1
      t = $0; gsub(/[][ \t]/, "", t)
      if (!(t in known)) { known[t] = 1; order[++nt] = t }
      above[t] = above[t] pend; pend = ""
      next
    }
    {
      seen = 1
      v = $2; from = 3
      if ($3 ~ /^#?[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) { v = v " " $3; from = 4 }
      note = ""
      for (i = from; i <= NF; i++) note = note " " $i
      sub(/^[ #]+/, "", note)
      if (!(t in known)) { known[t] = 1; order[++nt] = t }
      body[t] = body[t] pend key($1) "\037= \"" v "\"" (note == "" ? "" : " # " note) "\n"
      pend = ""
    }
    END {
      sub(/\n+$/, "\n", head)
      if (head == "\n") head = ""
      printf "%s", head
      out = (head != "")
      for (j = 1; j <= nt; j++) {
        t = order[j]
        if (t != "") printf "%s%s[%s]\n", (out ? "\n" : ""), above[t], t
        printf "%s", body[t]
        out = 1
      }
      if (pend != "") printf "%s%s", (out ? "\n" : ""), pend
    }
  ' | _hi_pad_cols 15
}

# _hi_convert_carry - stdin's `member | tool | wire | home` lines as TOML on
# stdout: `"member" = "tool | wire | home"` rows under [carry], the group the
# lines had, a name TOML would not read bare in quotes; comments stay where
# they were, and a line of the wrong shape becomes one
function _hi_convert_carry() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*$/ { next }
    /^[ \t]*#/ { print trim($0); next }
    {
      if (!seen++) print "[carry]"
      n = split($0, f, "|")
      if (n != 4 || index($0, "\"") || index($0, "\\")) { print "# " trim($0); next }
      k = trim(f[1])
      if (k !~ /^[A-Za-z0-9_-]+$/) k = "\"" k "\""
      printf "%s = \"%s | %s | %s\"\n", k, trim(f[2]), trim(f[3]), trim(f[4])
    }
  '
}

# _hi_convert_settings - stdin's settings.sh with a _HI_PACKAGES_MIN_PRIORITY
# line replaced by the _HI_PACKAGES_GROUPS that shows the same tiers, its
# trailing comment (install's marker among them) kept, or dropped where that
# is the default (2) or a _HI_PACKAGES_GROUPS line already says what to show;
# and with every editor's and multiplexer's toggle gone, the ones at 1 as
# words of the _HI_PLUGINS_OFF line, which is written where the file's own
# was, or last, under the marker any of them carried
function _hi_convert_settings() {
  awk -v old="$_HI_OLD_TOGGLES" '
    BEGIN {
      word["EDITORS"] = "editors"; word["VIM"] = "vim nvim"; word["NANO"] = "nano"
      word["EMACS"] = "emacs"; word["MICRO"] = "micro"; word["HELIX"] = "hx"
      word["KAKOUNE"] = "kak"; word["TMUX"] = "tmux"; word["SCREEN"] = "screen"
      word["ZELLIJ"] = "zellij"
    }
    function add(words,   k, w, m) {
      m = split(words, w, /[ ,]+/)
      for (k = 1; k <= m; k++)
        if (w[k] != "" && index(" " off " ", " " w[k] " ") == 0) off = off (off == "" ? "" : " ") w[k]
    }
    # the line as the wizard pads it (rc_tagged), so its block takes it as its own
    function listed(   l) {
      l = "export _HI_PLUGINS_OFF=\047" off "\047"
      if (mark == "") print l; else print l "\037" mark
    }
    function marked(l) {
      if (!match(l, /[ \t]+#.*/)) return
      mark = substr(l, RSTART); sub(/^[ \t]+/, "", mark)
    }
    function value(l) {
      sub(/^[^=]*=/, "", l); sub(/[ \t]+#.*/, "", l); gsub(/["\047]/, "", l)
      return l
    }
    { lines[++n] = $0 }
    /^[ \t]*(export[ \t]+)?_HI_PACKAGES_GROUPS=/ { has = 1 }
    /^[ \t]*(export[ \t]+)?_HI_PLUGINS_OFF=/ { at = n }
    $0 ~ "^[ \t]*(export[ \t]+)?_HI_DISABLE_(" old ")=" {
      t = $0; sub(/^[ \t]*(export[ \t]+)?_HI_DISABLE_/, "", t); sub(/=.*/, "", t)
      if (value($0) == 1) { moved = moved " " word[t]; marked($0) }
      lines[n] = ""; gone[n] = 1
    }
    END {
      if (at) { add(value(lines[at])); marked(lines[at]) }
      add(moved)
      for (i = 1; i <= n; i++) {
        if (gone[i]) continue
        if (i == at) { if (off != "") listed(); continue }
        l = lines[i]
        # the tool and sudo aliases went opt-in under new names: the old
        # disables have nothing left to turn off
        if (l ~ /^[ \t]*(export[ \t]+)?_HI_DISABLE_(TOOL|SUDO)_ALIAS(ES)?=/) continue
        if (l !~ /^[ \t]*(export[ \t]+)?_HI_PACKAGES_MIN_PRIORITY=/) { print l; continue }
        if (has) continue
        v = l; sub(/^[^=]*=["\047]?/, "", v); sub(/[^0-9].*/, "", v)
        if (v == "" || v == 2) continue
        if (v == 0) g = "core useful deprecated extras trivia base platform"
        else if (v == 1) g = "core useful deprecated extras base"
        else if (v == 3) g = "core deprecated"
        else g = "none"
        c = ""
        if (match(l, /[ \t]+#.*/)) c = substr(l, RSTART)
        print "export _HI_PACKAGES_GROUPS=\047" g "\047" c
      }
      if (!at && off != "") listed()
    }
  ' | _hi_pad_cols 45
}

# _hi_convert_one <file> <shape> <converter> [dst] - <file> through
# <converter> into [dst] (default <file> itself), and through _hi_toml_<the
# converter's subject> behind it when <shape> is `flat`, the rows two formats
# back; the old file kept as <file>.old. Nothing for the shape this hi reads.
function _hi_convert_one() {
  local f="$1" dst="${4:-$1}" to="" tmp
  case "$2" in '' | toml) return 0 ;; esac
  [ "$dst" = "$f" ] || to="$dst"
  if [ -n "$_HI_DRY_RUN" ]; then
    _hi_cecho " would convert $f${to:+ to $to} (the old one kept at $f.old)" "$BLUE"
    return 0
  fi
  tmp="$(mktemp -t hi.convert.XXXXXX)"
  case "$2" in
  flat) "$3" <"$f" | "_hi_toml_${3#_hi_convert_}" >"$tmp" ;;
  *) "$3" <"$f" >"$tmp" ;;
  esac
  [ -n "$to" ] || cp -p "$f" "$f.old"
  _hi_write_back "$tmp" "$dst"
  [ -z "$to" ] || mv -f "$f" "$f.old"
  _hi_cecho " converted $f to ${to:-the current format} (the old one is at $f.old)" "$GREEN"
}

# _hi_convert_data <file> <packages|colors> <flat rows' pattern> - a data
# file, by the shape scripts/lib.sh's _hi_data_shape reads off its rows
function _hi_convert_data() {
  local shape=""
  _hi_data_shape shape "$1" "$3"
  case "$shape" in
  flat) _hi_convert_one "$1" flat "_hi_convert_$2" ;;
  sections) _hi_convert_one "$1" sections "_hi_toml_$2" ;;
  esac
}

# sourced by a suite for the converters alone
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

_HI_ME="${_HI_ARGV0:-convert_settings.sh}"
_HI_DRY_RUN=""
dir="$_HI_CONFIG_DIR"
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    printf 'Usage: %s [--dry-run] [<dir>]\n\nConverts the packages, colors, carry, and settings.sh in <dir> (default %s)\nfrom a format this hi no longer reads, keeping each original as <file>.old.\n' convert_settings.sh "$_HI_CONFIG_DIR"
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  -*) _hi_die "unknown option $1 (--dry-run, a directory)" ;;
  *) dir="$1" ;;
  esac
  shift
done

_hi_old_settings="^[[:space:]]*(export[[:space:]]+)?_HI_(PACKAGES_MIN_PRIORITY|DISABLE_TOOL_ALIASES|DISABLE_SUDO_ALIAS|DISABLE_($_HI_OLD_TOGGLES))="
_hi_convert_data "$dir/packages" packages "$_HI_FLAT_PACKAGES"
_hi_convert_data "$dir/colors" colors "$_HI_FLAT_COLORS"
# a carry file is the plugins file's old name; nothing where there is one already
[ ! -f "$dir/carry" ] || [ -e "$dir/plugins" ] || _hi_convert_one "$dir/carry" carry _hi_convert_carry "$dir/plugins"
[ ! -f "$dir/settings.sh" ] || ! grep -Eq "$_hi_old_settings" "$dir/settings.sh" ||
  _hi_convert_one "$dir/settings.sh" settings _hi_convert_settings
