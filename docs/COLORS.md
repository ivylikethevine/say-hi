# Colors

How hi picks every color it paints: the per-host hash, your pins, tags, the
24-bit scheme, and the package check's colors. All of them live in one file,
`~/.config/say-hi/colors` (`hi --edit colors` opens it), which rides to every
target.

## Contents

- [Pins](#pins)
- [Tags](#tags)
- [Color names](#color-names)
- [The 24-bit scheme](#the-24-bit-scheme)
- [The package check's ramp](#the-package-checks-ramp)
- [The package check's rows](#the-package-checks-rows)
- [Using the hash in your own prompt](#using-the-hash-in-your-own-prompt)

## Pins

Every user and host gets a color derived from its name, so an unpinned host
looks the same from every machine. Pin the ones that matter. The file is TOML
([the subset hi reads](SETTINGS.md#the-toml-hi-reads)): a `[type]` line opens
a table, and each row is `name = "color"`, with the name in double quotes if
it holds anything but letters, digits, `_`, and `-`.

```toml
[username]
root = "red b00020"

[hostname]
bastion = "yellow"
"10.0.1.*" = "red"

[hosttag]
prod = "red"

[usertag]
prod = "red"
```

- `[hostname]` and `[username]` pin one name. A hostname with `*` or `?` is a
  pattern (`10.0.1.*`, `*.prod.example.com`); the first match wins.
- `[hosttag]` colors every host with that [tag](#tags); `[usertag]` colors
  the _username_ on those hosts, so `you@prod-db` reads as prod on both
  halves.
- Precedence, highest first: an exact pin, a hosttag, a pattern, the hash.
- A second word is that pin's exact 24-bit color in hex (`"brred ff5f5f"`).
  The first word is still a [name](#color-names), used on a 16-color
  terminal, so pick the nearest.

`hi --preview colors` shows every host in your ssh config and every known
user in their colors, each naming the rule it matched:

![hi --preview colors: every ssh host and user in the colors they resolve to, then a prod host in red and a dev host in green](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

## Tags

A host's tag comes from `~/.ssh/config`, read the way ssh reads it, `Include`
files included:

- a `# Tags: prod` comment above its `Host` or `Match host` line, which
  `hi --add-tag <host> prod` writes for you;
- a `Tag prod` line inside the block (ssh's own keyword, OpenSSH 9.4+);
- the name of its file, for a file directly in a `config.d` directory:
  hosts in `~/.ssh/config.d/acme` carry `acme`.

The comment wins over a `Tag` line, which wins over the file name. A wildcard
block (`Host prod-*`) tags every name it covers, but takes a tag only from a
line of its own. A tag holding anything but letters, digits, `_`, `.`, and
`-` tags nothing; one with a `.` colors but names no
[settings file](SETTINGS.md#settings-by-host-tag). `hi --doctor <host>` says
where a host's tag came from.

**Tags follow you past the first hop.** Your tagged `Host` lines (those lines
and their tags only, no `HostName` or `User`) ride the overlay as
`ssh_tags`, so a `hi` typed inside a session colors the next host too. Like
`colors`, it names hosts to every target; an empty `ssh_tags` of your own in
the overlay keeps them home.

## Color names

There are twenty-four: the terminal's twelve (`red`, `green`, `yellow`,
`blue`, `magenta`, `cyan`, and their `br` forms) and twelve more (`orange`,
`pink`, `teal`, `lime`, `violet`, `salmon`, `gold`, `sky`, `indigo`, `mint`,
`peach`, `lavender`). Pins and the hash use only these.

Each name is sent as a 16-color code followed by a 24-bit color, so a
terminal that ignores the second still gets the first; the extras fall back
to the nearest of the sixteen (orange to bright yellow). Without a
[scheme](#the-24-bit-scheme), the first twelve are the terminal's own colors
and the extras built-in hex values.

24-bit color is used only where the terminal says it can: `COLORTERM` of
`truecolor` or `24bit` on the client. `_HI_TRUECOLOR=1` in `settings.sh`
forces it (inside tmux, say), and `0` refuses it. zsh before 5.7 and macOS
Terminal.app get the sixteen colors.

## The 24-bit scheme

A scheme is the colors file's `[scheme]` table: a `colors` row of
twenty-four hex values, in the order of the names above (the six, the six
bright ones, then the twelve extras). An optional `packages` row of
twenty-four more paints only the package check.

```toml
[scheme]
colors = "f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 f37799 89d88b ebd391 74a8fc f2aede 6bd7ca fab387 f2cdcd 81c8be c3e88d cba6f7 eba0ac e5c890 89dceb 7287fd 8be9b0 f5a97f b4befe"
```

A pin's own hex outranks the scheme. A scheme that is not exactly 24 hex
values (plus 24 or none in `packages`) is ignored, and `hi --doctor` and
`hi --preview colors` say so.

## The package check's ramp

The `[palette]` table picks which names the package check paints each tier
in, rising 0 to 3, for installed and missing tools:

```toml
[palette]
installed = ["cyan", "green", "brcyan", "brgreen"]
missing   = ["blue", "magenta", "bryellow", "brred"]
```

Those are the shipped values. A good ramp makes a missing core tool the
loudest thing on screen and installed trivia the quietest, on light and dark
terminals alike. Anything but four names per row falls back to the shipped
ramp, and `hi --doctor` says so.

## The package check's rows

The check reads `packages`, also TOML: a table per group, and a row per tool
listing its alternatives in order of preference. The shipped file is short;
[packages.example](packages.example) is a longer one to copy
(`hi --edit packages`).

```toml
[useful]
curl = ["httpie", "xh"]
rsync = []
"+sudo" = ["doas"]

[deprecated]
"-neofetch" = []
```

The first name installed is shown, marked `~` when it is an alternative. A
mark before the name (then in double quotes) says what the row is for:

- **no mark**, wanted: installed (`✓`) and missing (`✗`) both show;
- **`-`**, unwanted: silent while absent, a warning (`!`) when installed;
- **`+`**, required: silent while installed, an alarm (`✗`) when missing.

Warnings and alarms sort first, in the loudest missing color. Every other row
takes its group's tier of the ramp:

| tier | groups                                     |
| ---- | ------------------------------------------ |
| 3    | `core`, `base`, `deprecated`               |
| 2    | `useful`                                   |
| 1    | `extras`, and any group of your own naming |
| 0    | `trivia`, `platform`                       |

`_HI_PACKAGES_GROUPS` picks the groups that run (default `core deprecated`,
or `none`); rows above the first table always run. To turn the check off,
drop `check` from `_HI_HEADER_ORDER`. `hi --preview packages` shows each
group and its colors.

Your copy replaces the shipped file whole and never gains a group the tree
adds later; `hi --preview packages` and `hi --doctor` name the groups yours
lacks.

## Using the hash in your own prompt

With `_HI_DISABLE_PROMPT=1`, hi still resolves the colors into variables for
your own [`bashrc` or `zshrc`](SETTINGS.md#shells-you-drop-into-inside-a-session):

- `$_HI_HOST_ESC` and `$_HI_USER_ESC`: the raw escape, for a bash `PS1`
  (wrapped in `\[ \]`): `PS1="\[$_HI_HOST_ESC\]\h\[$NC\] \w "`.
- `$_HI_HOST_COLOR` and `$_HI_USER_COLOR`: the name, for zsh's `%F{}`:
  `PS1='%F{$_HI_HOST_COLOR}%m%f %~ '`. For an extra name `%F{}` does not
  know, `_hi_color_base b "$_HI_HOST_COLOR"` gives the nearest of the sixteen
  and `_hi_color_hex h "$_HI_HOST_COLOR"` the hex for `%F{#$h}`.
- fish: `common/config.fish` sets `$fish_color_host` and `$fish_color_user`
  for `set_color` in your own `fish_prompt`.

Each shell resolves them at startup, so a changed pin shows from the next
shell on.
