#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The packer's streams: the staged tars of the overlay and the tree, the
# comment strip they pass through, their caches, and the sizes hi reports.
# Sourced by scripts/pack.sh, never run, and like it nothing here rides in
# the payload. GLOSSARY: HI.66
#
# A `$var` in single quotes is its reader's to expand (SC2016).
# shellcheck disable=SC2016

# What the comment-stripper is pointed at in the tree, as find's tests; an
# overlay member is stripped by its dialect's <strip>. GLOSSARY: HI.35
_HI_STRIP_NAMES=(-name '*.sh' -o -name '*.zsh' -o -name '*.fish' -o -name flags -o -path '*/config/*')
# What of $_HI_PAYLOAD never rides: the plugins rows, which this file alone
# reads (GLOSSARY: HI.63). Part of the payload cache's key, so a cache built
# with them in it is not served.
_HI_PAYLOAD_CUT=(say-hi/config/plugins)

# _hi_stage_carry - the overlay stager's carry, over its staged file $f
# (member $_hi_st_m, dialect row $_hi_st_d): each include the scan finds whose
# path names a file under the member's tool directories (_hi_tool_dirs) is
# rewritten to the copy that rides (_hi_include_carry), and the file staged
# as a member of its own, queued for the same scan; each file a line under
# `hi-carry` names rides too, as written (_hi_marked_carry). The source each
# came from is kept in $_hi_st_carry. Reads and grows _hi_stage_tar's locals.
function _hi_stage_carry() {
  local _hi_sc_src="${_hi_st_qs[_hi_st_i]:-}" _hi_sc_at=" " _hi_sc_ct=" " _hi_sc_l _hi_sc_n=0 _hi_sc_out="" _hi_sc_k _hi_sc_j _hi_sc_m
  local -a _hi_dirs=() _hi_carried=() _hi_marked=() _hi_unmarked=()
  [ -n "$_hi_sc_src" ] || _hi_overlay_src "$_hi_st_m" _hi_sc_src || return 0
  _hi_tool_dirs "$_hi_st_m" "$_hi_sc_src"
  while IFS='|' read -r _ _hi_sc_l _hi_sc_k _; do
    case "$_hi_sc_k" in
    include) ((! ${#_hi_dirs[@]})) || _hi_sc_at="$_hi_sc_at$_hi_sc_l " ;;
    carry) _hi_sc_ct="$_hi_sc_ct$_hi_sc_l " ;;
    esac
  done < <(_hi_dialect="$_hi_st_d" awk -v mode=report -v name="$_hi_st_m" "$_hi_st_prog" "$f")
  [ "$_hi_sc_at$_hi_sc_ct" != "  " ] || return 0
  while IFS= read -r _hi_sc_l || [ -n "$_hi_sc_l" ]; do
    _hi_sc_n=$((_hi_sc_n + 1))
    case "$_hi_sc_at" in *" $_hi_sc_n "*) _hi_include_carry _hi_sc_l "$_hi_sc_l" "${_hi_st_m%%/*}" || true ;; esac
    case "$_hi_sc_ct" in *" $_hi_sc_n "*) _hi_marked_carry _hi_sc_l "$_hi_sc_l" "$_hi_st_m" || true ;; esac
    _hi_sc_out+="$_hi_sc_l"$'\n'
  done <"$f"
  ((${#_hi_carried[@]} + ${#_hi_marked[@]})) || return 0
  printf '%s' "$_hi_sc_out" >"$f" || return 1
  # a marked file rides as written: it is no config of the member's dialect
  for ((_hi_sc_j = 0; _hi_sc_j < ${#_hi_marked[@]}; _hi_sc_j += 2)); do
    _hi_sc_m="${_hi_marked[_hi_sc_j]}"
    [ ! -e "$_hi_st_root/$_hi_sc_m" ] || continue
    mkdir -p "$_hi_st_root/${_hi_sc_m%/*}" && cp "${_hi_marked[_hi_sc_j + 1]}" "$_hi_st_root/$_hi_sc_m" || return 1
    _hi_st_carry+=("${_hi_marked[_hi_sc_j + 1]}")
    stage_out+=("$_hi_sc_m")
  done
  for ((_hi_sc_j = 0; _hi_sc_j < ${#_hi_carried[@]}; _hi_sc_j += 2)); do
    _hi_sc_m="${_hi_carried[_hi_sc_j]}"
    # one already staged - a member, or a file carried before - rides once
    [ ! -e "$_hi_st_root/$_hi_sc_m" ] || continue
    mkdir -p "$_hi_st_root/${_hi_sc_m%/*}" && cp "${_hi_carried[_hi_sc_j + 1]}" "$_hi_st_root/$_hi_sc_m" || return 1
    _hi_st_q+=("$_hi_st_root/$_hi_sc_m")
    _hi_st_qd[${#_hi_st_q[@]} - 1]="$_hi_st_d"
    _hi_st_qs[${#_hi_st_q[@]} - 1]="${_hi_carried[_hi_sc_j + 1]}"
    _hi_st_carry+=("${_hi_carried[_hi_sc_j + 1]}")
    stage_out+=("$_hi_sc_m")
  done
}

# _hi_stage_tar <src-dir> <stage-subdir> - the shared body of the two stagers
# below: pull the members out of <src-dir> into a scratch stage, strip their
# comments, gzip what comes out. Reads $stage_in (members to pull), $stage_out
# (members to emit), $stage_excl (stage paths dropped once pulled - not tar's
# --exclude, which OpenBSD's has none of) and $stage_add
# (<member> <path> pairs copied in from outside <src-dir>) and $stage_lint (1
# for the overlay: the include scan runs over the stage, and each member is
# stripped by its dialect rather than $_HI_STRIP_NAMES) from
# its caller, the convention _hi_container_cleanup and _hi_remote_middle also
# use.
#
# A subshell, so cleanup is a trap and a ^C mid-build leaves nothing behind
# (GLOSSARY: HI.39). Prefixed locals (GLOSSARY: HI.04): `root` is
# _say_hi_container's name for the target's tree, and this runs inside it.
function _hi_stage_tar() {
  local stage f _hi_st_root _hi_st_i _hi_st_prog _hi_st_m _hi_st_d _hi_st_n
  local -a _hi_st_strip=() _hi_st_add=(${stage_add[@]+"${stage_add[@]}"})
  local -a _hi_st_q=() _hi_st_qd=() _hi_st_qs=() _hi_st_carry=()
  local _hi_st_lint="${stage_lint:-0}"
  (
    stage="$(mktemp -d -t hi.stage.XXXXXX)" || exit 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _hi_st_root="$stage${2:+/$2}"
    # a file, not `tar cf - | tar xf -`: the reader stops at the end-of-archive
    # marker while a GNU writer still has record padding to send, which is an
    # EPIPE and a "tar: Write error" on stderr. Skipped when every member is
    # a $stage_add one: GNU tar refuses to write an empty archive.
    if ((${#stage_in[@]})); then
      tar -c -h -f "$stage/in.tar" -C "$1" "${stage_in[@]}" || exit 1
      tar -x -f "$stage/in.tar" -C "$stage" || exit 1
      rm -rf "$stage/in.tar" ${stage_excl[@]+"${stage_excl[@]/#/$stage/}"}
    fi
    for ((_hi_st_i = 0; _hi_st_i < ${#_hi_st_add[@]}; _hi_st_i += 2)); do
      case "${_hi_st_add[_hi_st_i]}" in */*) mkdir -p "$_hi_st_root/${_hi_st_add[_hi_st_i]%/*}" || exit 1 ;; esac
      cp "${_hi_st_add[_hi_st_i + 1]}" "$_hi_st_root/${_hi_st_add[_hi_st_i]}" || exit 1
    done
    # fish's universal variables are everything `set -U` ever kept, secrets
    # included: tide's lines ride and nothing else
    if [ -f "$_hi_st_root/tide.vars" ]; then
      grep '^SETUVAR tide_' "$_hi_st_root/tide.vars" >"$stage/tide.keep" || true
      mv -f "$stage/tide.keep" "$_hi_st_root/tide.vars" || exit 1
    fi
    # ahead of the stripper, over the staged copies rather than the user's
    # own files: an include hi cannot carry goes out commented, or made inert
    # in a shell or JSON file, and the strip below drops a comment
    if [ "$_hi_st_lint" = 1 ]; then
      _hi_st_prog="$(_hi_lint_awk)"
      _hi_read_lines _hi_st_q < <(find "$_hi_st_root" -type f ! -name '*.lint')
      # a queue, not the find's lines: a carried file joins it, in the
      # dialect of the member that named it
      for ((_hi_st_i = 0; _hi_st_i < ${#_hi_st_q[@]}; _hi_st_i++)); do
        f="${_hi_st_q[_hi_st_i]}" _hi_st_m="${_hi_st_q[_hi_st_i]#"$_hi_st_root"/}" _hi_st_d="${_hi_st_qd[_hi_st_i]:-}"
        [ -n "$_hi_st_d" ] || _hi_member_dialect "$_hi_st_m" _hi_st_d || continue
        _hi_stage_carry || exit 1
        _hi_dialect="$_hi_st_d" awk -v mode=fix -v name="$_hi_st_m" "$_hi_st_prog" "$f" >/dev/null || exit 1
        # no .lint at all means an empty member: awk never ran a rule on it
        [ ! -f "$f.lint" ] || mv -f "$f.lint" "$f" || exit 1
        # <name> | <leader> | <strip> | ...: strip.awk's d= and c= per file
        _hi_st_n="${_hi_st_d%% | *}" _hi_st_d="${_hi_st_d#* | }"
        case "${_hi_st_d#* | }" in 1' | '*) _hi_st_strip+=("d=$_hi_st_n" "c=${_hi_st_d%% | *}" "$f") ;; esac
      done
      # what the overlay cache watches besides the members (_hi_overlay_cached)
      [ -z "${_hi_carry_list:-}" ] ||
        printf '%s\n' ${_hi_st_carry[@]+"${_hi_st_carry[@]}"} >"$_hi_carry_list" || exit 1
    fi
    _hi_strip_awk >"$stage/strip.awk"
    # one awk over every file (GLOSSARY: HI.35); strip.awk sits at $stage and
    # matches no name above, so the stripper never eats its own script. It
    # buffers each file and writes it back over itself once the batch has been
    # read, so there is no `<file>.strip` left to rename: that rename was one
    # `mv` a file - 40 of them in a `hi --doctor`, which stages twice, and the
    # largest external cost it had - and renaming over a file still held open
    # is what broke the Windows runners. Writing in place also leaves every
    # mode alone, so hi.sh stays 0755 for the relay with nothing to restore.
    if [ "$_hi_st_lint" = 1 ]; then
      ((${#_hi_st_strip[@]} == 0)) || awk -f "$stage/strip.awk" "${_hi_st_strip[@]}" || exit 1
    else
      find "$_hi_st_root" -type f \( "${_HI_STRIP_NAMES[@]}" \) -exec awk -f "$stage/strip.awk" {} + || exit 1
    fi
    # the overlay's generated member, last: hi wrote it, so there is nothing
    # in it to scan or strip
    [ -z "${stage_wiring:-}" ] || printf '%s' "$stage_wiring" >"$_hi_st_root/wiring.sh" || exit 1
    _hi_tar_gz -C "$stage" "${stage_out[@]}"
  )
}

# _hi_overlay_tar [file...] - the overlay archive over the given members, or
# over _hi_overlay_files when called bare; nothing when there are none.
# Comment-stripped through a staging copy like the payload (GLOSSARY: HI.35):
# the overlay is the user's prose-heavy files and every byte rides each
# connect. The first tar's -h resolves a dotfile manager's symlinks into
# content; the final tar names the members, so strip.awk never ships. A
# member _hi_overlay_src packs from elsewhere is copied in under its own name.
# wiring.sh rides beside the members it has a line for (GLOSSARY: HI.62).
function _hi_overlay_tar() {
  local -a present=("$@")
  [ $# -gt 0 ] || _hi_read_lines present < <(_hi_overlay_files)
  ((${#present[@]})) || return 0
  local -a stage_in=() stage_out=("${present[@]}") stage_excl=() stage_add=()
  local stage_lint=1 stage_wiring=""
  local f src
  _hi_overlay_wiring stage_wiring "${present[@]}"
  [ -z "$stage_wiring" ] || stage_out+=(wiring.sh)
  for f in "${present[@]}"; do
    if _hi_overlay_src "$f" src && [ "$src" != "$_HI_CONFIG_DIR/$f" ]; then
      stage_add+=("$f" "$src")
    else
      stage_in+=("$f")
    fi
  done
  _hi_stage_tar "$_HI_CONFIG_DIR" ""
}

# What changes an overlay tar without touching any member's mtime: the member
# list itself, and the wiring written from it, which a newer hi.sh can change
# under the same list. Hashed, not spelled out, to keep the cache filename
# short.
function _hi_overlay_cache_key() {
  local _hi_ok_w
  _hi_overlay_wiring _hi_ok_w "$@"
  _hi_hash "$*$_hi_ok_w"
}

# _hi_cached <outvar> <tag> <key> <builder> <watch...> - one cache, two
# callers. Rebuilt when missing, when any <watch> or $cache_also path (from its
# caller) is newer than it - a symlink's target counts, so a dotfile manager's
# edit does - or when _HI_PAYLOAD_CACHE=0; written under a temp name and mv'd into place, so a
# concurrent reader sees the old file or the new one and never a half-written
# archive. rc 1 means "no cache, build it yourself".
#
# Prefixed locals throughout (GLOSSARY: HI.04): a plain `cache` would shadow a
# caller's outvar and the printf -v would never leave this function.
function _hi_cached() {
  local _hi_c_outvar="$1" _hi_c_tag="$2" _hi_c_key="$3" _hi_c_pre="$4" _hi_c_build="$5"
  shift 5
  local _hi_c_dir _hi_c_cache _hi_c_tmp
  local -a _hi_c_watch=("${@/#/$_hi_c_pre}" ${cache_also[@]+"${cache_also[@]}"})
  [ "${_HI_PAYLOAD_CACHE:-1}" != 0 ] || return 1
  _hi_runtime_dir _hi_c_dir
  [ -n "$_hi_c_dir" ] || return 1
  _hi_c_cache="$_hi_c_dir/hi.$_hi_c_tag.$_hi_c_key"
  if [ -f "$_hi_c_cache" ] &&
    [ -z "$(find -H "${_hi_c_watch[@]}" -newer "$_hi_c_cache" -print 2>/dev/null)" ]; then
    printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
    return 0
  fi
  # mktemp, not `.$$`: every subshell of one shell shares its $$
  _hi_c_tmp="$(mktemp "$_hi_c_cache.XXXXXX")" || return 1
  "$_hi_c_build" "$@" >"$_hi_c_tmp" || {
    rm -f "$_hi_c_tmp"
    return 1
  }
  mv -f "$_hi_c_tmp" "$_hi_c_cache"
  printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
}

# _hi_cached over exactly these overlay members, keyed on the list. Fails when
# there is no member at all, on top of _hi_cached's own refusals. A member
# _hi_overlay_src packs from elsewhere is watched there and keyed by its path,
# so pointing the tool at another file never serves the old one's cache. The
# files the last build carried (_hi_stage_carry) are watched from the list it
# left beside the cache, $_hi_carry_list.
function _hi_overlay_cached() {
  local _hi_oc_outvar="$1" _hi_oc_f _hi_oc_src _hi_oc_key _hi_oc_dir _hi_carry_list=""
  shift
  (($#)) || return 1
  local -a cache_also=()
  for _hi_oc_f; do
    _hi_overlay_src "$_hi_oc_f" _hi_oc_src && [ "$_hi_oc_src" != "$_HI_CONFIG_DIR/$_hi_oc_f" ] &&
      cache_also+=("$_hi_oc_src")
  done
  _hi_oc_key="$(_hi_overlay_cache_key "$@" ${cache_also[@]+"${cache_also[@]}"})"
  _hi_runtime_dir _hi_oc_dir
  if [ -n "$_hi_oc_dir" ]; then
    _hi_carry_list="$_hi_oc_dir/hi.overlay.$_hi_oc_key.carry"
    [ ! -f "$_hi_carry_list" ] || while IFS= read -r _hi_oc_f; do
      [ -z "$_hi_oc_f" ] || cache_also+=("$_hi_oc_f")
    done <"$_hi_carry_list"
  fi
  _hi_cached "$_hi_oc_outvar" overlay "$_hi_oc_key" "$_HI_CONFIG_DIR/" _hi_overlay_tar "$@"
}

# The tree twin, against the ~70-130ms _hi_payload_tar otherwise costs on
# every connect. _hi_payload_tar takes no arguments - the roster is its own -
# but is handed one anyway: that list is what _hi_cached watches for staleness.
# Keyed on the tree's own path, $_HI_PAYLOAD_CUT, and the caller's
# $payload_excl: two trees on
# one machine share the runtime dir, and staleness is only "no file newer
# than the cache", so a tree keyed by name alone was served the other tree's
# payload; and a tree cut for one overlay is never served beside another.
function _hi_payload_cached() {
  local _hi_pc_key
  _hi_hash "$_HI_HOME|${_HI_PAYLOAD_CUT[*]} ${payload_excl[*]-}" _hi_pc_key
  _hi_pc_key="tree.$_hi_pc_key"
  _hi_cached "$1" payload "$_hi_pc_key" \
    "$_HI_HOME/say-hi/" _hi_payload_tar "${_HI_PAYLOAD[@]}"
}

# The overlay tar on stdout: the cache when warm and clean, a fresh build
# otherwise. An if/else and not `cat && || tar`, which would emit both halves
# if the cat died partway through. Prefixed local: GLOSSARY: HI.04.
function _hi_overlay_bytes() {
  local _hi_ob_cache=""
  if _hi_overlay_cached _hi_ob_cache "$@"; then
    cat "$_hi_ob_cache"
  else
    _hi_overlay_tar "$@"
  fi
}

# _hi_overlay_bytes armored into the line that unpacks it on the target.
function _hi_overlay_stream() {
  _hi_overlay_bytes "$@" | _hi_armored_line '|' "tar -x -m -z -f - -C \"\$_HI_ROOT/config\" && $(_hi_overlay_fixup '"$_HI_ROOT/config"')"
}

# The comment stripper every payload file goes through: their prose headers
# are for the installed copy a user reads, not the wire. A comment line starts
# with `#`, or with c=, an overlay member's dialect <leader>, set on the
# command line ahead of its file with its d=, and blank lines and indentation
# go with them - no dialect with <strip> 1 reads either, and the indentation
# alone is 3% of the payload - except on a line continuing a `word\`, where it
# is the only separator. A nanorc's dropped syntax include and extendsyntax
# ride as comments, for load.sh's _hi_nano_fallback to find.
# GLOSSARY: HI.35 - the rules, and why their order is the argument
function _hi_strip_awk() {
  cat <<'AWK'
FNR == 1 { out = FILENAME; seen[out] = 1; buf[out] = ""; tag = ""; dash = cont = 0; lc = (c != "" && c != "#") ? "^[ \t]*" c : ""; nano = (d == "nano") }
FNR == 1 && /^#!/ { buf[out] = buf[out] $0 "\n"; next }
nano && /^# hi dropped: (include .*\.nanorc|extendsyntax )/ { buf[out] = buf[out] $0 "\n"; next }
lc != "" && $0 ~ lc { next }
tag != "" {
  line = $0
  if (dash) sub(/^\t+/, "", line)
  if (line == tag) tag = ""
  buf[out] = buf[out] $0 "\n"
  next
}
/^[ \t]*#/ { next }
/^[ \t]*$/ { next }
{
  if (!cont) sub(/^[ \t]+/, "")
  cont = /[^ \t\\]\\$/
  s = $0
  while (match(s, /<<-?[ \t]*("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|[A-Za-z_][A-Za-z0-9_]*)/)) {
    m = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    dash = (m ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", m)
    sub(/^["']/, "", m)
    sub(/["']$/, "", m)
    tag = m
  }
  buf[out] = buf[out] $0 "\n"
}
END {
  for (f in seen) {
    printf "%s", buf[f] > (f)
    close(f)
  }
}
AWK
}

# _hi_payload_excl <member...> - the tree files those overlay members shadow
# (GLOSSARY: HI.41), into the caller's $payload_excl: one copy on the wire,
# not the default beside the file that beats it. Only a member that ships
# counts, so a file still under a $_HI_OVERLAY_RENAMES name cuts nothing.
# With the header off the target never draws one, so header.sh and the
# package list it checks stay home too. A framework's prompt loader,
# common/fw_<name>.<ext>, rides only to a target handed that framework
# (_hi_prompt_list): the shell there picks from that list alone. GLOSSARY: HI.32
function _hi_payload_excl() {
  local f s
  payload_excl=()
  ! _hi_toggle_on _HI_DISABLE_HEADER || payload_excl=(say-hi/common/header.sh say-hi/config/packages)
  for f; do
    f="${f%%/*}"
    case "$_HI_OVERLAY_SHADOWS${payload_excl[*]-} " in
    *" say-hi/config/$f "*) ;;
    *" $f "*) payload_excl+=("say-hi/config/$f") ;;
    esac
  done
  _hi_prompt_list >/dev/null
  for f in "${_HI_PROMPT_TABLE[@]}"; do
    case "$f" in *'|fw|'*) ;; *) continue ;; esac
    case " $_HI_PROMPT_LIST_MEMO " in *[\ :]"${f%%|*} "*) continue ;; esac
    s="${f#*|}" s="${s%%|*}"
    payload_excl+=("say-hi/common/fw_${f%%|*}.${s/bash/sh}")
  done
}

# The tree, comment-stripped through a staging copy; both size budgets
# measure this. GLOSSARY: HI.39 + HI.35. Whole unless the caller holds a
# $payload_excl - a connect that ships the overlay too; _hi_wire_bytes has
# none, and measures the stock tree, less $_HI_PAYLOAD_CUT.
function _hi_payload_tar() {
  local -a stage_in stage_out=(say-hi) stage_excl=("${_HI_PAYLOAD_CUT[@]}" ${payload_excl[@]+"${payload_excl[@]}"})
  stage_in=("${_HI_PAYLOAD[@]/#/say-hi/}")
  _hi_stage_tar "$_HI_HOME" say-hi
}

# The tree twin of _hi_overlay_stream: the armored payload tar, through the
# cache when it is warm and clean.
function _hi_payload_stream() {
  local cache=""
  if _hi_payload_cached cache; then
    $_HI_ARMOR <"$cache"
  else
    _hi_payload_tar | $_HI_ARMOR
  fi
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it, through the same payload cache - a warm
# one stages nothing. GLOSSARY: HI.44 - why not a sum of streams
# shellcheck disable=SC2034 # the locals are hi.sh's _hi_remote_script's to read
function _hi_wire_bytes() {
  local overlay_line="" bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_stream)"
  _hi_remote_script script
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
}
