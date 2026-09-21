# Colors

How every color hi paints is chosen: the per-host hash, the pins in
`~/.config/say-hi/colors`, the 24-bit scheme, and the package check's ramp
and rows. The two settings here, `_HI_COLOR_SCHEME` and
`_HI_PACKAGES_PALETTE`, are rows in
[SETTINGS.md](SETTINGS.md#every-setting); the wizard asks about neither.

## Contents

- [The package check's ramp](#the-package-checks-ramp)
- [The package check's rows](#the-package-checks-rows)
- [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)

Every username and hostname resolves to a color derived from its own name, so
an unpinned host looks the same from every machine you say `hi` from. Pin the
ones that matter in `~/.config/say-hi/colors`: `username,root,red`,
`hostname,bastion,yellow`, or `hosttag,prod,red` to color every host carrying a
`# Tags: prod` comment above its `Host` or `Match host` line in
`~/.ssh/config` — a wildcard block (`Host prod-*`) colors every name it covers.
`hi --add-tag <host> <tag>` writes that comment for you, replacing a tag
already there; given a name only a wildcard block covers, it names the block
to tag instead.
A fourth kind, `usertag,prod,red`, colors the _username_ on every host that
carries that tag, so `you@prod-db` reads as prod on both halves. A
`hostname` row whose name holds `*` or `?` is a pattern:
`hostname,10.0.1.*,red` or `hostname,*.prod.example.com,red` colors a whole
subnet or domain at once, no ssh-config entry needed — the first matching
pattern in the file wins. Precedence, highest first: an exact pin, then a
hosttag, then a pattern, then the hash.

A config split into files (`Include config.d/*` in `~/.ssh/config`) is read
the way ssh reads it: each `Include` is followed in place - `~` is your home,
a relative path is under `~/.ssh`, globs expand in sorted order, nested
Includes too - so a host and its `# Tags:` line that live in
`~/.ssh/config.d/01-work` complete, color, and ride like any other.

Tags follow you past the first hop. A `hi` typed inside a session runs on a
box whose `~/.ssh/config` has none of your `# Tags:` lines, so the tagged
`Host` and `Match host` lines of yours - those two lines of each block and
nothing else, no `HostName`, no `User`, no untagged host - ride the overlay as
`ssh_tags`, and the middle box reads them wherever its own config has no tag
for the name. The host is matched as you type it there, against the patterns
you wrote here. `hi --doctor` says when the member rides; like `colors`, it
names hosts to every target you visit, so an empty `ssh_tags` of your own in
`~/.config/say-hi/` is how to keep them home.

`hi --preview colors` shows every host in your ssh config and every user it
knows of, drawn in the colors themselves, each row naming the rule it matched
(`hash` for one nothing pins):

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

## The package check's rows

The check reads one file, `config/packages`. A row is one tool and its
fallbacks, `[-|+]package:priority[,package:priority...]`, and two dials
decide what it prints:

- **its priority**, 0-3, against `_HI_PACKAGES_MIN_PRIORITY` (0-3, default
  `2`): a row that cannot reach the floor is not even looked for. The ramp
  above paints each priority; there is no per-row color.
- **an optional leading character**: `-` speaks only when the whole row is
  missing (core tools, where present is not news), `+` only when something
  on it is installed (platform facts, where absent is noise).

`hi --add-package go:3 cargo:3,rustc:3` adds rows to
`~/.config/say-hi/packages`, copying the tree's file there first: a copy of
your own replaces the tree's wholesale, the same rule `colors` follows. By
hand, `cp "$_HI_ROOT/config/packages" ~/.config/say-hi/packages` and edit.
`hi --preview packages` shows each priority's colors with a real example
from your rows; to turn the check off, drop `check` from `_HI_HEADER_ORDER`.

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
