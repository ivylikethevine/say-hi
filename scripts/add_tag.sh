#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --add-tag`: write the `# Tags: <tag>` comment common/core.sh's
# _hi_ssh_host_tag_walk reads, directly above a host's `Host` (or
# `Match host`) line in ~/.ssh/config or whichever file it Includes the host
# from. A tag already there is replaced - the walk reads the leftmost only, so
# a second would change nothing. A name only a wildcard block covers is
# refused with that block named: tagging the pattern is the way to say it. A
# host the name of its config.d file already tags that way is left alone.
# `hi --remove-tag` (--remove first) takes the `# Tags:` line back out.
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

mode=add
[ "${1:-}" != --remove ] || {
  mode=remove
  shift
}
me="${_HI_ARGV0:-hi --$mode-tag}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()

# shellcheck disable=SC2329 # _hi_args runs it
function _hi_add_tag_help() {
  if [ "$mode" = remove ]; then
    cat <<EOF
Usage: $me <host> [--dry-run]

Takes the "# Tags:" line above <host>'s Host (or Match host) line out of
$_HI_SSH_CONFIG, or the file it Includes the host from. A host in a file of a
config.d directory still carries that file's name as its tag.

  -n, --dry-run    say what would be written, and write nothing
EOF
    return 0
  fi
  cat <<EOF
Usage: $me <host> <tag> [--dry-run]

Writes "# Tags: <tag>" directly above <host>'s Host (or Match host) line in
$_HI_SSH_CONFIG, or in the file it Includes the host from, so a hosttag or
usertag row in your colors file colors it (docs/COLORS.md). A tag already
there is replaced. <host> is matched as written in the config, so a pattern
tags its whole block: $me '*.prod' prod. A host in a file of a config.d
directory carries that file's name as its tag until a line says otherwise.

  -n, --dry-run    say what would be written, and write nothing

\`hi --preview colors\` shows the host in its new color.
EOF
}

_hi_args _hi_add_tag_help "$me --help" "$@"

if [ "$mode" = remove ]; then
  [ "${#args[@]}" -eq 1 ] || _hi_die "needs a host ($me --help)"
else
  [ "${#args[@]}" -eq 2 ] || _hi_die "needs a host and a tag ($me --help)"
fi
host="${args[0]}" tag="${args[1]:-}"
# one word the walk reads whole: it stops the leftmost tag at a comma or space
[ "$mode" = remove ] || [[ "$tag" =~ ^[A-Za-z0-9_.-]+$ ]] ||
  _hi_die "not a tag: $tag (letters, digits, _ . - only)"
# a backend's word is the tag of every target of its kind (hi.sh's
# _hi_backend_tags), so no host carries one
case " $_HI_CONTAINER_CLIS nomad kube " in
*" $tag "*) _hi_die "not a tag for a host: $tag is a backend's word, the tag of every $tag target (settings.$tag.sh reaches them)" ;;
esac
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

# _hi_wild_block - the first wildcard Host pattern covering $host, if any. A
# function, not inline in the $( ) below: bash 3.2 ends a substitution at a
# case pattern's `)`. GLOSSARY: HI.29
function _hi_wild_block() {
  sh "$_HI_TARGETS" ssh-config "$_HI_SSH_CONFIG" | while IFS= read -r line; do
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in [Hh][Oo][Ss][Tt][[:space:]]*) ;; *) continue ;; esac
    t="${t#[Hh][Oo][Ss][Tt]}"
    t="${t%%#*}"
    for p in ${t//,/ }; do
      case "$p" in *[\*\?]*) _hi_ssh_pattern_hit "$host" "$p" && printf '%s' "$p" && exit 0 ;; esac
    done
  done
}

if [ -z "$file" ]; then
  # no line of its own: say which wildcard block claims it, if one does
  # set -f: the words are ssh's patterns, never this directory's files
  pattern="$(set -f && _hi_wild_block)" || true
  [ -z "$pattern" ] ||
    _hi_die "$host has no Host line of its own - only 'Host $pattern' covers it; tag that instead: $me '$pattern'${tag:+ $tag}"
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

# The tag the walk reads off the file's own name, where no line is written: a
# file directly in a config.d tags the hosts it spells out.
filetag=""
case "$file" in */config.d/*) filetag="${file##*/config.d/}" ;; esac
case "$host" in *[\*\?]*) filetag="" ;; esac
case "$filetag" in *[!A-Za-z0-9_.-]*) filetag="" ;; esac

# _hi_tag_write - $lines over $file, unless --dry-run; ends the script
function _hi_tag_write() {
  dry_run_say "write $file" && exit 0
  tmpfile="$(mktemp -t hi.sshconfig.XXXXXX)"
  printf '%s\n' "${lines[@]}" >"$tmpfile"
  _hi_write_back "$tmpfile" "$file"
  _hi_cecho "$file updated" "$GREEN"
  exit 0
}

hostline="${lines[at - 1]}"
indent="${hostline%%[![:space:]]*}"
if [ "$mode" = remove ]; then
  if [ "$tagline" -lt 0 ]; then
    if [ -n "$filetag" ]; then
      _hi_cecho " $file: $host has no # Tags: line - the file's name tags it $filetag" "$BLUE"
    else
      _hi_cecho " $file: $host has no # Tags: line - nothing to write" "$BLUE"
    fi
    exit 0
  fi
  _hi_cecho " - ${lines[tagline]#"$indent"} (above ${hostline#"$indent"})" "$YELLOW"
  lines=("${lines[@]:0:tagline}" "${lines[@]:tagline+1}")
  _hi_tag_write
fi
new="$indent# Tags: $tag"
if [ "$tagline" -ge 0 ] && [ "${lines[tagline]}" = "$new" ]; then
  _hi_cecho " $file: $host is already tagged $tag" "$BLUE"
  exit 0
fi
if [ "$tagline" -lt 0 ] && [ "$tag" = "$filetag" ]; then
  _hi_cecho " $file: $host is already tagged $tag, by the file's name" "$BLUE"
  exit 0
fi
if [ "$tagline" -ge 0 ]; then
  _hi_cecho " ~ ${lines[tagline]#"$indent"} -> # Tags: $tag (above ${hostline#"$indent"})" "$YELLOW"
  lines[tagline]="$new"
else
  over=""
  [ -z "$filetag" ] || over=", over the file's own tag $filetag"
  _hi_cecho " + # Tags: $tag (above ${hostline#"$indent"}$over)" "$GREEN"
  lines=("${lines[@]:0:at-1}" "$new" "${lines[@]:at-1}")
fi

_hi_tag_write
