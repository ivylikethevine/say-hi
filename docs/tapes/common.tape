# The geometry every demo shares, sourced rather than copied into each tape:
# `Source docs/tapes/common.tape`, which resolves from the repo root the tapes
# are rendered from (docs/tapes/generate.sh, or `vhs docs/tapes/<name>.tape`).
#
# Sourced after a tape's own `Set Shell`, and before anything a tape overrides.
# Nothing else belongs here - `Output`, `Require` and the Hide/Show script stay
# per tape.
#
# Every demo renders at this one geometry, and no tape overrides it. The height
# is the tightest that still fits the tallest thing any demo draws, which is
# colors.tape's preview table - check that one first if you change it.
#
# Two things vary between the demos, and both mean something. hi's own
# configuration - the settings.sh each gets from docs/tapes/fixtures.sh - is
# the one a reader is meant to compare, so a difference in the frame is never
# incidental. The theme is the other, and it is not decoration: it tracks the
# **client shell**, so the set has three looks rather than seven and the look
# tells you which shell you are watching.
#
#   bash (no `Set Shell`, the default here)      GruvboxDark
#   zsh  (editors.tape, run.tape)                 Dracula
#   fish (overlay.tape, complete.tape)            nord
#
# bash is the warm one on purpose: it is the shell four of the demos use -
# demo, packages, colors and pick - so the odd one out in tone is the one you
# see most, and the two cool themes then read as "not bash" at a glance.
#
# The bash one lives here because it is the default; the other two override it
# immediately after their `Source` line. Adding a demo on a fourth shell means
# a fourth theme - and adding one on an existing shell means reusing its theme,
# not picking a new one.

Set FontSize 16
Set Width 1120
Set Height 800
Set Padding 10
# Set Margin 10
Set TypingSpeed 40ms
Set BorderRadius 10
# Set WindowBar Colorful

# The bash default - overridden by the non-bash tapes. Names come from
# `vhs themes`; see https://github.com/charmbracelet/vhs/blob/main/THEMES.md
# Set Theme "GruvboxDark"
Set Theme "Monokai Pro"
