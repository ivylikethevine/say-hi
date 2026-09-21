#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --add-tag`: write the `# Tags: <tag>` comment common/core.sh's
# _hi_ssh_host_tag_walk reads, directly above a host's `Host` (or
# `Match host`) line in ~/.ssh/config or whichever file it Includes the host
# from. A tag already there is replaced - the walk reads the leftmost only, so
# a second would change nothing. A name only a wildcard block covers is
# refused with that block named: tagging the pattern is the way to say it.
# add_package.sh's shape: HI.33 the standalone entry, HI.09 the commit step.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

me="${_HI_ARGV0:-hi --add-tag}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()

function _hi_add_tag_help() {
  cat <<EOF
Usage: $me <host> <tag> [--dry-run]

Writes "# Tags: <tag>" directly above <host>'s Host (or Match host) line in
$_HI_SSH_CONFIG, or in the file it Includes the host from, so a hosttag or
usertag row in your colors file colors it (docs/COLORS.md). A tag already
there is replaced. <host> is matched as written in the config, so a pattern
tags its whole block: $me '*.prod' prod.

  -n, --dry-run    say what would be written, and write nothing

\`hi --preview colors\` shows the host in its new color.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_add_tag_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  -*) _hi_die "unknown option $1 ($me <host> <tag> [--dry-run])" ;;
  *) args+=("$1") ;;
  esac
  shift
done

[ "${#args[@]}" -eq 2 ] || _hi_die "needs a host and a tag ($me --help)"
host="${args[0]}" tag="${args[1]}"
# one word the walk reads whole: it stops the leftmost tag at a comma or space
[[ "$tag" =~ ^[A-Za-z0-9_.-]+$ ]] ||
  _hi_die "not a tag: $tag (letters, digits, _ . - only)"
[ -f "$_HI_SSH_CONFIG" ] || _hi_die "no ssh config at $_HI_SSH_CONFIG"

# _hi_host_line <file> - the line number of the first Host or Match host line
# in <file> naming $host as one of its words, exactly; nothing if none does
function _hi_host_line() {
  awk -v want="$host" '{
    t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]#.*/, "", t); gsub(/[\t,]/, " ", t)
    n = split(t, w, / +/); k = tolower(w[1]); i = 2
    if (k == "match" && tolower(w[2]) == "host") i = 3
    else if (k != "host") next
    for (; i <= n; i++) if (w[i] == want) { print NR; exit }
  }' "$1"
}

file="" at=""
while IFS= read -r f; do
  at="$(_hi_host_line "$f")"
  [ -z "$at" ] || {
    file="$f"
    break
  }
done < <(sh "$_HI_TARGETS" ssh-files "$_HI_SSH_CONFIG")

if [ -z "$file" ]; then
  # no line of its own: say which wildcard block claims it, if one does
  # set -f: the words are ssh's patterns, never this directory's files
  pattern="$(set -f && sh "$_HI_TARGETS" ssh-config "$_HI_SSH_CONFIG" | while IFS= read -r line; do
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in [Hh][Oo][Ss][Tt][[:space:]]*) ;; *) continue ;; esac
    t="${t#[Hh][Oo][Ss][Tt]}"
    t="${t%%#*}"
    for p in ${t//,/ }; do
      case "$p" in *[\*\?]*) _hi_ssh_pattern_hit "$host" "$p" && printf '%s' "$p" && exit 0 ;; esac
    done
  done)" || true
  [ -z "$pattern" ] ||
    _hi_die "$host has no Host line of its own - only 'Host $pattern' covers it; tag that instead: $me '$pattern' $tag"
  _hi_die "no Host $host in $_HI_SSH_CONFIG or the files it Includes"
fi

# The comment run directly above the Host line - blank lines and comments, the
# lines the walk carries a tag across - and a `# Tags:` line within it, if any.
lines=()
_hi_read_lines lines <"$file"
tagline=-1
for ((i = at - 2; i >= 0; i--)); do
  t="${lines[i]#"${lines[i]%%[![:space:]]*}"}"
  case "$t" in
  '') continue ;;
  '#'*)
    t="${t#\#}"
    t="${t#"${t%%[![:space:]]*}"}"
    case "$t" in [Tt]ags[:=]*)
      tagline=$i
      break
      ;;
    esac
    ;;
  *) break ;;
  esac
done

hostline="${lines[at - 1]}"
indent="${hostline%%[![:space:]]*}"
new="$indent# Tags: $tag"
if [ "$tagline" -ge 0 ] && [ "${lines[tagline]}" = "$new" ]; then
  _hi_cecho " $file: $host is already tagged $tag" "$BLUE"
  exit 0
fi
if [ "$tagline" -ge 0 ]; then
  _hi_cecho " ~ ${lines[tagline]#"$indent"} -> # Tags: $tag (above ${hostline#"$indent"})" "$YELLOW"
  lines[tagline]="$new"
else
  _hi_cecho " + # Tags: $tag (above ${hostline#"$indent"})" "$GREEN"
  lines=("${lines[@]:0:at-1}" "$new" "${lines[@]:at-1}")
fi

dry_run_say "write $file" && exit 0
tmpfile="$(mktemp -t hi.sshconfig.XXXXXX)"
printf '%s\n' "${lines[@]}" >"$tmpfile"
_hi_write_back "$tmpfile" "$file"
_hi_cecho "$file updated" "$GREEN"
