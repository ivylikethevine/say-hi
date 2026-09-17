# Colors

How every color hi paints is chosen: the per-host hash, the pins in
`~/.config/say-hi/colors`, the 24-bit scheme, and the package check's ramp
and groups. The two settings here, `_HI_COLOR_SCHEME` and
`_HI_PACKAGES_PALETTE`, are rows in
[SETTINGS.md](SETTINGS.md#every-setting); the wizard asks about neither.

## Contents

- [The package check's ramp](#the-package-checks-ramp)
- [Grouping the package check](#grouping-the-package-check)
- [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)

Every username and hostname resolves to a color derived from its own name, so
an unpinned host looks the same from every machine you say `hi` from. Pin the
ones that matter in `~/.config/say-hi/colors`: `username,root,red`,
`hostname,bastion,yellow`, or `hosttag,prod,red` to color every host carrying a
`# Tags: prod` comment above its `Host` or `Match host` line in
`~/.ssh/config` — a wildcard block (`Host prod-*`) colors every name it covers.
A fourth kind, `usertag,prod,red`, colors the _username_ on every host that
carries that tag, so `you@prod-db` reads as prod on both halves. A
`hostname` row whose name holds `*` or `?` is a pattern:
`hostname,10.0.1.*,red` or `hostname,*.prod.example.com,red` colors a whole
subnet or domain at once, no ssh-config entry needed — the first matching
pattern in the file wins. Precedence, highest first: an exact pin, then a
hosttag, then a pattern, then the hash.

`hi --preview colors` shows every host in your ssh config and every user it
knows of, drawn in the colors themselves, each row naming the rule it matched:

![hi --preview colors: every ssh host and user in the colors they resolve to, then a prod host in red and a dev host in green](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

Any of those rows takes an optional fourth column, that pin's own 24-bit
color as six hex digits (a leading `#` is fine):
`hostname,prod-db,brred,ff5f5f` renders `prod-db` in exactly that red on a
truecolor terminal. The third column is still a name from the vocabulary
below and is what a 16-color terminal gets, so name the nearest one. A fourth
column outranks `_HI_COLOR_SCHEME` for that one pin — the scheme says what a
_name_ renders as, the column what this host or user renders as — and
anything that is not six hex digits is ignored.

The vocabulary is twenty-four names: the terminal's twelve (`red`, `green`,
`yellow`, `blue`, `magenta`, `cyan`, and their `br` forms) and twelve more -
`orange`, `pink`, `teal`, `lime`, `violet`, `salmon`, `gold`, `sky`,
`indigo`, `mint`, `peach`, `lavender` - that a pin may name and the hash
lands on as readily as the first twelve. A pin, the hash, and
`hi --preview colors` never see anything else. What each name _renders as_ is
`_HI_COLOR_SCHEME`'s: unset, the terminal's own sixteen colors for the first
twelve and a built-in 24-bit color for each extra; set, that list's hex for
every name. Each is emitted as one escape carrying a 16-color code first and
the 24-bit color after it, so a terminal that ignores the second keeps the
first - an extra name's 16-color half is the nearest of the sixteen (orange
reads as bright yellow there, teal as cyan).

The 24-bit half paints everything hi paints - the prompt, the header's cells
and packages check, the git segment - and only on a terminal that says it
can: `COLORTERM` set to `truecolor` or `24bit`, which hi reads on the client
and ships to the session as `_HI_TRUECOLOR` (ssh drops `COLORTERM` itself).
Inside tmux, or on a terminal that renders 24-bit color without announcing it,
`export _HI_TRUECOLOR=1` in `settings.sh` forces it; `0` refuses it. zsh
takes the hex from 5.7 on and keeps the plain name below that; macOS
Terminal.app never sets `COLORTERM` and so keeps its own sixteen.

hi ships no named schemes: the scheme _is_ the setting — twenty-four
six-digit hex words, one space apart, in the order of the names above (red,
green, yellow, blue, magenta, cyan, the six bright ones, then the twelve
extras), or forty-eight, whose second twenty-four paint only the package
check, so a missing favorite can shout in a different red from the one your
prompt wears. Write it into `settings.sh` by hand — it ships to every target,
so a scheme follows you:

```sh
export _HI_COLOR_SCHEME='f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 f37799 89d88b ebd391 74a8fc f2aede 6bd7ca fab387 f2cdcd 81c8be c3e88d cba6f7 eba0ac e5c890 89dceb 7287fd 8be9b0 f5a97f b4befe'
```

The quotes matter (the value holds spaces, and fish sources the file too).
Anything that is not exactly 24 or 48 hex words renders as the default and
`hi --doctor` says so. `hi --preview colors` and `hi --preview packages` judge
a scheme, labelling it `custom (24)`, `custom (48)`, or
`(ignored - not a scheme)`.

## The package check's ramp

`_HI_PACKAGES_PALETTE` is the same idea one level down: which of the
twenty-four names the header's package check paints each priority in. It is
eight of those names, one space apart — four for installed, rising 0→3, then
four for missing:

```sh
export _HI_PACKAGES_PALETTE='cyan green brcyan brgreen blue magenta bryellow brred'
```

That line is the shipped ramp, so writing it changes nothing. A ramp reads
best when both halves climb in one direction — a missing favorite the loudest
thing on screen, installed trivia the quietest — and stay legible on light and
dark terminals alike. Anything that is not eight names from the vocabulary
falls back to the shipped ramp, `hi --doctor` says so, and
`hi --preview packages` labels the line `default`, `custom`, or
`(ignored - not eight color names)`.

## Grouping the package check

One `packages` file ranks everything on one ramp, so your language toolchain
and the box's own package manager can only be told apart by priority. A
`packages.d/` directory beside it holds more packages files, each a **group**:
checked after `packages`, in file-name order, its rows kept together (sorted
by priority within the group, not merged into one sort), and painted in a
color of its own. The group's name is the file's, less a leading
`<digits>-` ordering prefix:

```sh
mkdir -p ~/.config/say-hi/packages.d
printf 'color=orange\ngo:3\ncargo:3\nuv:2\n' >~/.config/say-hi/packages.d/10-lang
printf 'color=brblue\n+apt:3,dnf:3,apk:3,pacman:3,brew:3\n' >~/.config/say-hi/packages.d/20-box
```

`hi --add-package go:3,cargo:3 --group lang` writes the rows for you (creating
the group if it does not exist); the `color=` line is still yours to add by
hand, the way above.

A member's rows are the `packages` grammar, and one `color=` line sets its
color: a single name from the vocabulary paints every row, installed or
missing (the mark still says which), and eight names are a ramp of the group's
own in `_HI_PACKAGES_PALETTE`'s shape. With no `color=` line, or a value that
is neither, the group wears the ramp in force. `_HI_PACKAGES_MIN_PRIORITY`
still decides how deep every group goes.

Only plain names are members — a letter or digit first, then letters, digits,
`_`, `.`, and `-`, and not ending in `.bak`, `.orig`, `.rej`, or `.tmp` — so an
editor's swap file or a backup never travels. Each member rides the overlay
comment-stripped, a few dozen bytes apiece over the same rows in one file.
`hi --preview packages` adds a GROUP table naming each group, its rows, and
its color painted in itself; `hi --doctor` names the groups in order and warns
about a `color=` it ignores, a file that is no member, and a group nothing
paints — one whose every row sits below the floor.
[HI.58](GLOSSARY.md#hi58-overlay-directory-members) has the mechanics.

## Using the hash in your own prompt

`_HI_DISABLE_PROMPT=1` turns off hi's own `user@host` prompt; the per-host
color hashing is still resolved, into variables for your own `bashrc` or
`zshrc` (sourced at the end of hi's,
[above](SETTINGS.md#shells-you-drop-into-inside-a-session)) to use:

- `$_HI_HOST_ESC`/`$_HI_USER_ESC` — the raw ANSI escape, for a bash `PS1` to
  embed directly (wrap it in `\[ \]` so readline doesn't count its width):
  `PS1="\[$_HI_HOST_ESC\]\h\[$NC\] \w "`.
- `$_HI_HOST_COLOR`/`$_HI_USER_COLOR` — the color by name, for zsh's own
  `%F{}`: `PS1='%F{$_HI_HOST_COLOR}%m%f %~ '`. One of the twelve extras is
  not a name `%F{}` knows: `_hi_color_base b "$_HI_HOST_COLOR"` gives the
  sixteen-color name behind it, and `_hi_color_hex h "$_HI_HOST_COLOR"` the
  hex for `%F{#$h}`.
- fish needs neither: `common/config.fish` sets
  `$fish_color_host`/`$fish_color_user` unconditionally, for
  `set_color $fish_color_host` in your own `fish_prompt`.

Each shell resolves them once at startup, so a change to the color pins shows
from the next shell on.
