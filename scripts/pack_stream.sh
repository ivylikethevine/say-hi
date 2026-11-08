#!/usr/bin/env bash
# The packer's streams: the staged tars of the overlay and tree, the comment
# strip, their caches, and the sizes hi reports. Sourced by scripts/pack.sh;
# nothing here rides. GLOSSARY: HI.66
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

# _hi_stage_carry - carries what staged file $f (member $_hi_st_m, dialect
# $_hi_st_d) includes from its tool's directories (_hi_include_carry), neovim's
# required modules (_hi_require_carry), and `hi-carry` lines' files
# (_hi_marked_carry), each staged and queued for the same scan, sources in
# $_hi_st_carry. Works on _hi_stage_tar's locals.
function _hi_stage_carry() {
  local _hi_sc_src="${_hi_st_qs[_hi_st_i]:-}" _hi_sc_at=" " _hi_sc_ct=" " _hi_sc_l _hi_sc_n=0 _hi_sc_out="" _hi_sc_k _hi_sc_j _hi_sc_m _hi_sc_rtp=""
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
    case "$_hi_sc_at" in *" $_hi_sc_n "*)
      _hi_include_carry _hi_sc_l "$_hi_sc_l" "${_hi_st_m%%/*}" || true
      # neovim's require of a module that rides: the line stays, under the
      # marker the scan spares
      case "$_hi_st_m:$_hi_st_d" in nvim/*:'lua | '*)
        ! _hi_require_carry "$_hi_sc_l" nvim || _hi_sc_out+="-- hi-allow"$'\n' _hi_sc_rtp=1
        ;;
      esac
      ;;
    esac
    case "$_hi_sc_ct" in *" $_hi_sc_n "*) _hi_marked_carry _hi_sc_l "$_hi_sc_l" "$_hi_st_m" || true ;; esac
    _hi_sc_out+="$_hi_sc_l"$'\n'
  done <"$f"
  ((${#_hi_carried[@]} + ${#_hi_marked[@]})) || return 0
  # the modules land under the overlay's nvim/, which the init puts on the
  # runtimepath itself: no alias, $EDITOR, or $VIMINIT has to say so
  [ -z "$_hi_sc_rtp" ] || [ "$_hi_st_m" != nvim/init.lua ] ||
    _hi_sc_out="vim.opt.rtp:prepend(\"$_HI_CARRY_TOKEN/nvim\")"$'\n'"$_hi_sc_out"
  printf '%s' "$_hi_sc_out" >"$f" || return 1
  # a marked file rides as written, being no config of the member's dialect;
  # a carried one joins the scan in that dialect. One already staged - a
  # member, or a file carried before - rides once.
  _hi_sc_k=${#_hi_marked[@]}
  _hi_marked+=(${_hi_carried[@]+"${_hi_carried[@]}"})
  for ((_hi_sc_j = 0; _hi_sc_j < ${#_hi_marked[@]}; _hi_sc_j += 2)); do
    _hi_sc_m="${_hi_marked[_hi_sc_j]}" _hi_sc_l="${_hi_marked[_hi_sc_j + 1]}"
    [ ! -e "$_hi_st_root/$_hi_sc_m" ] || continue
    mkdir -p "$_hi_st_root/${_hi_sc_m%/*}" && cp "$_hi_sc_l" "$_hi_st_root/$_hi_sc_m" || return 1
    _hi_st_carry+=("$_hi_sc_l")
    stage_out+=("$_hi_sc_m")
    ((_hi_sc_j >= _hi_sc_k)) || continue
    _hi_st_q+=("$_hi_st_root/$_hi_sc_m")
    _hi_st_qd[${#_hi_st_q[@]} - 1]="$_hi_st_d"
    _hi_st_qs[${#_hi_st_q[@]} - 1]="$_hi_sc_l"
  done
}

# _hi_stage_tar <src-dir> <stage-subdir> - both stagers' body: copy members
# from <src-dir> into a scratch stage, strip comments, gzip. Reads the
# caller's $stage_in (members to pull), $stage_out (to emit), $stage_excl
# (dropped once pulled), $stage_add (<member> <path> pairs from elsewhere),
# and $stage_lint (1 for the overlay: include scan, strip by dialect).
# A subshell, so a ^C leaves nothing (GLOSSARY: HI.39); prefixed locals,
# since it runs inside _say_hi (GLOSSARY: HI.04).
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
    # cp, not a tar pair: busybox's tar could not fill the nix store's 0555
    # directories. -L turns a dotfile manager's symlinks into content.
    # $stage_as names the directory the base is staged under (the payload's
    # say-hi/, whatever the tree is called); the overlay stages at the top
    for f in ${stage_in[@]+"${stage_in[@]}"}; do
      _hi_st_d="$stage${stage_as:+/$stage_as}/$f"
      [ -d "${_hi_st_d%/*}" ] || mkdir -p "${_hi_st_d%/*}" || exit 1
      cp -R -L "$1/$f" "$_hi_st_d" || exit 1
    done
    for ((_hi_st_i = 0; _hi_st_i < ${#_hi_st_add[@]}; _hi_st_i += 2)); do
      case "${_hi_st_add[_hi_st_i]}" in */*) mkdir -p "$_hi_st_root/${_hi_st_add[_hi_st_i]%/*}" || exit 1 ;; esac
      cp "${_hi_st_add[_hi_st_i + 1]}" "$_hi_st_root/${_hi_st_add[_hi_st_i]}" || exit 1
    done
    # a copy keeps its source's mode, and one read-only by it (the nix
    # store's 0444) is cut and stripped here, and removed on the target, by
    # its owner
    chmod -R u+w "$stage" || exit 1
    ((${#stage_excl[@]} == 0)) || rm -rf "${stage_excl[@]/#/$stage/}"
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
    # One awk over every file (GLOSSARY: HI.35), writing each back in place:
    # no `mv` per file (slow, and it broke on Windows over an open file), and
    # modes stay as they were.
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

# _hi_overlay_tar [file...] - the overlay archive of the given members, or of
# _hi_overlay_files; nothing for none. Comment-stripped like the payload
# (GLOSSARY: HI.35), with wiring.sh beside the members (GLOSSARY: HI.62).
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

# The overlay cache's key: what changes the tar without touching a member's
# mtime (the overlay's path, the member list, the wiring), hashed to keep the
# name short. Two overlays share the runtime dir, so the path must be in it.
function _hi_overlay_cache_key() {
  local _hi_ok_w _hi_ok_out="$1"
  shift
  _hi_overlay_wiring _hi_ok_w "$@"
  _hi_hash "${_HI_CONFIG_DIR:-}|$*$_hi_ok_w" "$_hi_ok_out"
}

# _hi_cached <outvar> <tag> <key> <builder> <watch...> - a cache, rebuilt when
# missing, when a <watch> or $cache_also path (symlink targets included) is
# newer, or under _HI_PAYLOAD_CACHE=0; written to a temp name and moved, so
# no reader sees half. 1: no cache, build it yourself. Prefixed locals
# (GLOSSARY: HI.04).
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

# _hi_cached over these overlay members, keyed on the list and each source's
# path, watching the sources and the files the last build carried
# ($_hi_carry_list). Fails with no member.
function _hi_overlay_cached() {
  local _hi_oc_outvar="$1" _hi_oc_f _hi_oc_src _hi_oc_key _hi_oc_dir _hi_carry_list=""
  shift
  (($#)) || return 1
  local -a cache_also=()
  for _hi_oc_f; do
    _hi_overlay_src "$_hi_oc_f" _hi_oc_src && [ "$_hi_oc_src" != "$_HI_CONFIG_DIR/$_hi_oc_f" ] &&
      cache_also+=("$_hi_oc_src")
  done
  _hi_overlay_cache_key _hi_oc_key "$@" ${cache_also[@]+"${cache_also[@]}"}
  _hi_runtime_dir _hi_oc_dir
  if [ -n "$_hi_oc_dir" ]; then
    _hi_carry_list="$_hi_oc_dir/hi.overlay.$_hi_oc_key.carry"
    [ ! -f "$_hi_carry_list" ] || while IFS= read -r _hi_oc_f; do
      [ -z "$_hi_oc_f" ] || cache_also+=("$_hi_oc_f")
    done <"$_hi_carry_list"
  fi
  _hi_cached "$_hi_oc_outvar" overlay "$_hi_oc_key" "$_HI_CONFIG_DIR/" _hi_overlay_tar "$@"
}

# The tree's cache, saving _hi_payload_tar's ~70-130ms a connect. Keyed on
# the tree's path, $_HI_PAYLOAD_CUT, and $payload_excl, since trees and cuts
# share the runtime dir; the file list passed is what _hi_cached watches.
function _hi_payload_cached() {
  local _hi_pc_key
  _hi_hash "$_HI_ROOT|${_HI_PAYLOAD_CUT[*]} ${payload_excl[*]-}" _hi_pc_key
  _hi_pc_key="tree.$_hi_pc_key"
  _hi_cached "$1" payload "$_hi_pc_key" \
    "$_HI_ROOT/" _hi_payload_tar "${_HI_PAYLOAD[@]}"
}

# _hi_overlay_file <outvar> <dir> <member...> - the overlay's archive as
# <dir>/overlay.tgz: a copy of the cache when warm and clean, for
# _hi_payload_file's reason, else a build.
function _hi_overlay_file() {
  local _hi_of_out="$1" _hi_of_dir="$2" _hi_of_c=""
  shift 2
  { _hi_overlay_cached _hi_of_c "$@" && cp "$_hi_of_c" "$_hi_of_dir/overlay.tgz" 2>/dev/null; } ||
    _hi_overlay_tar "$@" >"$_hi_of_dir/overlay.tgz" || return 1
  printf -v "$_hi_of_out" '%s' "$_hi_of_dir/overlay.tgz"
}

# The script's lines that unpack the overlay's archive, landed beside it by
# the boot probe, and fix the paths of what it carried.
function _hi_overlay_unpack() {
  printf 'mkdir -p "$_HI_ROOT/config"\ntar -x -m -z -f "$_hi_b/overlay.tgz" -C "$_HI_ROOT/config" && %s' \
    "$(_hi_overlay_fixup '"$_HI_ROOT/config"')"
}

# The comment stripper: drops comment lines (`#`, or a member's dialect
# leader, c=), blank lines, and indentation, except after a `word\`
# continuation. A nanorc's dropped syntax includes ride as comments for
# load.sh's _hi_nano_fallback. GLOSSARY: HI.35
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

# _hi_payload_excl <member...> - tree files to leave out, into the caller's
# $payload_excl: defaults these members shadow (GLOSSARY: HI.41), header.sh
# and the package list with the header off, keep.sh and mux.sh under
# $_HI_DISABLE_KEEP, and each fw_<name> loader for a framework the target is
# not handed. GLOSSARY: HI.32
function _hi_payload_excl() {
  local f s
  payload_excl=()
  ! _hi_toggle_on _HI_DISABLE_HEADER || payload_excl=(say-hi/common/header.sh say-hi/config/packages)
  # the kept session switched off: neither file of it rides (GLOSSARY: HI.65)
  [ "${_HI_DISABLE_KEEP:-0}" != 1 ] || payload_excl+=(say-hi/common/keep.sh say-hi/common/mux.sh)
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
  local stage_as=say-hi
  stage_in=("${_HI_PAYLOAD[@]}")
  _hi_stage_tar "$_HI_ROOT" say-hi
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it, and the tree's archive after it, through
# the same payload cache - a warm one stages nothing. GLOSSARY: HI.44 - why
# not a sum of streams
# shellcheck disable=SC2034 # the locals are hi.sh's _hi_remote_script's to read
function _hi_wire_bytes() {
  local overlay_line="" bootloader script tree_f="" tree_n=0 dir head
  local size="$_HI_SIZE_TOKEN"
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  dir="$(mktemp -d -t hi.wire.XXXXXX)" || return 1
  _hi_payload_file tree_f "$dir" || tree_f=""
  _hi_byte_count tree_n "$tree_f"
  rm -f "$dir/tree.tgz"
  rmdir "$dir" 2>/dev/null || :
  _hi_remote_script script
  head="$((${#script} + 1)) $tree_n 0"
  _hi_out "${1:-}" "$((${#head} + 1 + ${#script} + 1 + tree_n))"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
}
