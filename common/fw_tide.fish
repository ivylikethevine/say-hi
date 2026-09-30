#!/bin/fish
# SPDX-License-Identifier: MIT
# tide's prompt hand-over on a target, sourced by common/config.fish once it
# picks tide; its own file so a target not handed tide is not sent it
# (GLOSSARY: HI.32). fish already loaded tide and its fish_prompt autoloads;
# the home config rides as fish_variables lines, exported so tide's background
# renderer (a `fish -c`) sees them over the target's own.
if test -f $_HI_CONFIG_DIR/tide.vars
  for _hi_l in (string match 'SETUVAR tide_*' <$_HI_CONFIG_DIR/tide.vars)
    set -l kv (string split -m1 : -- (string sub -s 9 -- $_hi_l))
    # \x1e joins a list, a lone \x1d is the empty one
    set -l v (string unescape -- "$kv[2]" | string collect)
    test "$v" = \x1d; and set -gx $kv[1]; or set -gx $kv[1] (string split -- \x1e "$v")
  end
  set -e _hi_l
end
