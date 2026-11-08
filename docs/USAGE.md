# Usage

Every `hi --flag`, with what it prints. Each line is `hi --help`'s, from
`common/flags`; the images are rendered by CI from `docs/tapes/usage`. The
full detail is the [man page](https://github.com/ivylikethevine/say-hi/blob/main/docs/hi.1),
and a connect itself is in [the tour](GETTING-STARTED.md#a-tour).

## Contents

- [Every command](#every-command)
  - [`hi --help`](#hi---help)
  - [`hi --version`](#hi---version)
  - [`hi --use`](#hi---use)
  - [`hi --plain`](#hi---plain)
  - [`hi --no-plain`](#hi---no-plain)
  - [`hi --keep`](#hi---keep)
  - [`hi --no-keep`](#hi---no-keep)
  - [`hi --end`](#hi---end)
  - [`hi --preview`](#hi---preview)
  - [`hi --doctor`](#hi---doctor)
  - [`hi --install`](#hi---install)
  - [`hi --uninstall`](#hi---uninstall)
  - [`hi --configure`](#hi---configure)
  - [`hi --update`](#hi---update)
  - [`hi --add-tag`](#hi---add-tag)
  - [`hi --remove-tag`](#hi---remove-tag)
  - [`hi --plugins`](#hi---plugins)
  - [`hi --disable-plugin`](#hi---disable-plugin)
  - [`hi --enable-plugin`](#hi---enable-plugin)
  - [`hi --edit`](#hi---edit)

## Every command

These work inside a session too: `--help`, `--version`, `--use`, `--plain`, `--no-plain`, `--keep`, `--no-keep`, `--end`. The rest need the checkout's `scripts/`.

### `hi --help`

`hi --help`: this text.

![hi --help](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-help.svg)

### `hi --version`

`hi --version`: hi's version: the packaging stamp, or git describe.

![hi --version](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-version.svg)

### `hi --use`

`hi --use <backend>`: skip probing and force that backend (ssh counts as one).

### `hi --plain`

`hi --plain`: a bare shell, nothing copied: no tar or /tmp needed.

### `hi --no-plain`

`hi --no-plain`: hi's own session this once, past \_HI\_PLAIN=1.

### `hi --keep`

`hi --keep`: keep the session on the target through a dropped link.

It changes how a connect runs, which [the tour's story](GETTING-STARTED.md#survive-a-dropped-link) shows.

### `hi --no-keep`

`hi --no-keep`: an ordinary session, past \_HI\_KEEP=1 or a kept one.

### `hi --end`

`hi --end`: close the session \<target\> is keeping.

### `hi --preview`

`hi --preview <subject> [--text]`: colors, packages, or header, as printed here.

![hi --preview colors](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview.svg)

![hi --preview packages](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview-2.svg)

![hi --preview header](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview-3.svg)

### `hi --doctor`

`hi --doctor [--json] [--problems] [--text] [--use <backend>] [ssh-options] [target]`: a read-only pre-flight report, or just its problems.

![hi --doctor --problems](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-doctor.svg)

### `hi --install`

`hi --install [--yes] [--link {none,user,system}] [--shell <list>] [--print-rc] [--preset <name>] [--dry-run]`: install or repair say-hi's lines in your shell rc files.

![hi --install --yes --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-install.svg)

### `hi --uninstall`

`hi --uninstall [--purge] [--dry-run]`: take those lines out; --purge removes the overlay too.

![hi --uninstall --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-uninstall.svg)

### `hi --configure`

`hi --configure [--preset <name>] [--dry-run]`: revisit the settings, leaving the rc wiring be.

![hi --configure --preset minimal --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-configure.svg)

### `hi --update`

`hi --update [<tag>] [--dry-run]`: move the checkout to the newest release tag, or \<tag\>. Needs a git checkout, which a package is not.

### `hi --add-tag`

`hi --add-tag <host> <tag> [--dry-run]`: tag an ssh host, for the colors.

![hi --add-tag web-dev dev --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-add-tag.svg)

### `hi --remove-tag`

`hi --remove-tag <host> [--dry-run]`: take a host's # Tags: line back out.

![hi --remove-tag web-dev --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-remove-tag.svg)

### `hi --plugins`

`hi --plugins [--text]`: list the plugins: what rides, and what is off.

![hi --plugins](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-plugins.svg)

![hi --plugins --text](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-plugins-2.svg)

### `hi --disable-plugin`

`hi --disable-plugin <name>... [--dry-run]`: switch plugins off: nothing of theirs rides.

![hi --disable-plugin bat --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-disable-plugin.svg)

### `hi --enable-plugin`

`hi --enable-plugin <name>... [--dry-run]`: switch them back on.

![hi --enable-plugin tmux --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-enable-plugin.svg)

### `hi --edit`

`hi --edit [<file>]`: open your overlay, or one file of it, in your editor.
