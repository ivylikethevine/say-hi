#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rewrites overlay files still in a shape this hi no longer reads, in place,
# keeping each original beside it as <file>.old:
#   packages     "[-|+]name:N,..." rows -> [group] sections
#   colors       "type,name,color[,rrggbb]" rows -> [type] sections
#   settings.sh  _HI_PACKAGES_MIN_PRIORITY -> _HI_PACKAGES_GROUPS; the
#                _HI_DISABLE_TOOL_ALIASES/_HI_DISABLE_SUDO_ALIAS lines dropped
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
      row = sprintf("%-15s %s", f[2], f[3])
      if (n >= 4 && f[4] != "") row = row " " f[4]
      body[t] = body[t] pend row "\n"
      pend = ""
    }
    END {
      printf "%s", head
      for (k = 1; k <= nt; k++) printf "\n[%s]\n%s", types[k], body[types[k]]
      if (pend != "") printf "\n%s", pend
    }
  '
}

# _hi_convert_settings - stdin's settings.sh with a _HI_PACKAGES_MIN_PRIORITY
# line replaced by the _HI_PACKAGES_GROUPS that shows the same tiers, its
# trailing comment (install's marker among them) kept, or dropped where that
# is the default (2) or a _HI_PACKAGES_GROUPS line already says what to show
function _hi_convert_settings() {
  awk '
    { lines[++n] = $0 }
    /^[ \t]*(export[ \t]+)?_HI_PACKAGES_GROUPS=/ { has = 1 }
    END {
      for (i = 1; i <= n; i++) {
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
    }
  '
}

# _hi_convert_one <file> <converter> <old-shape grep> - converts <file> when
# a line matches the old shape and none is a [section] (settings.sh has none)
function _hi_convert_one() {
  local f="$1" tmp
  [ -f "$f" ] && grep -Eq "$3" "$f" || return 0
  [ "$2" = _hi_convert_settings ] || ! grep -Eq '^\[[^]]+\]$' "$f" || return 0
  if [ -n "$_HI_DRY_RUN" ]; then
    _hi_cecho " would convert $f (the old one kept at $f.old)" "$BLUE"
    return 0
  fi
  tmp="$(mktemp -t hi.convert.XXXXXX)"
  "$2" <"$f" >"$tmp"
  cp -p "$f" "$f.old"
  _hi_write_back "$tmp" "$f"
  _hi_cecho " converted $f to the current format (the old one is at $f.old)" "$GREEN"
}

# sourced by a suite for the converters alone
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

_HI_DRY_RUN=""
dir="$_HI_CONFIG_DIR"
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    printf 'Usage: %s [--dry-run] [<dir>]\n\nConverts the packages, colors, and settings.sh in <dir> (default %s)\nfrom a format this hi no longer reads, keeping each original as <file>.old.\n' convert_settings.sh "$_HI_CONFIG_DIR"
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  -*) _hi_die "unknown option $1 (--dry-run, a directory)" ;;
  *) dir="$1" ;;
  esac
  shift
done

_hi_convert_one "$dir/packages" _hi_convert_packages '^[^#]*:[0-9]'
_hi_convert_one "$dir/colors" _hi_convert_colors '^[a-z]+,[^,#]+,'
_hi_convert_one "$dir/settings.sh" _hi_convert_settings '^[[:space:]]*(export[[:space:]]+)?_HI_(PACKAGES_MIN_PRIORITY|DISABLE_TOOL_ALIASES|DISABLE_SUDO_ALIAS)='
