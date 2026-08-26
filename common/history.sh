#!/usr/bin/env bash
# A fresh scratch directory for this shell's command history, removed when
# the shell exits. common/bash.sh and common/zsh.zsh source this and point
# HISTFILE into it; fish can't source it and keeps its own copy in
# common/config.fish. _HI_DISABLE_HISTORY=1 skips this file entirely (and
# hi.sh's _HI_TRIM_TABLE drops it from the payload), so nothing here runs
# unless the caller already checked the toggle.
if [ -z "${_HI_TMPDIR:-}" ]; then
  _HI_TMPDIR="$(mktemp -d -t hi.history.XXXXXX)"
  export _HI_TMPDIR
  # GLOSSARY: HI.14 - bash's `trap ... EXIT` vs zsh's TRAPEXIT
  # shellcheck disable=SC2016 # $_HI_TMPDIR is resolved when the trap fires, not now
  _hi_on_exit 'rm -rf "$_HI_TMPDIR"'
fi
