# Usage

Every `hi --flag`, with an example of each and what it prints. The flags,
their shapes, and the one-line help come from `common/flags`, the table
`hi --help` prints from; the examples come from `docs/tapes/usage`, and CI
renders each in a throwaway home with a tagged ssh host and a vimrc. What a
flag does in full is the [man page](https://github.com/ivylikethevine/say-hi/blob/main/docs/hi.1);
a connect itself is the [README's demos](../README.md). A command needs the
checkout's `scripts/`, which a session does not carry, unless it says it works
in a session.

## Contents

- [Every command](#every-command)
  - [`hi --help`](#hi---help)
  - [`hi --version`](#hi---version)
  - [`hi --use`](#hi---use)
  - [`hi --plain`](#hi---plain)
  - [`hi --no-plain`](#hi---no-plain)
  - [`hi --mux`](#hi---mux)
  - [`hi --no-mux`](#hi---no-mux)
  - [`hi --keep`](#hi---keep)
  - [`hi --no-keep`](#hi---no-keep)
  - [`hi --end`](#hi---end)
  - [`hi --preview`](#hi---preview)
  - [`hi --doctor`](#hi---doctor)
  - [`hi --install`](#hi---install)
  - [`hi --uninstall`](#hi---uninstall)
  - [`hi --configure`](#hi---configure)
  - [`hi --update`](#hi---update)
  - [`hi --add-package`](#hi---add-package)
  - [`hi --remove-package`](#hi---remove-package)
  - [`hi --add-tag`](#hi---add-tag)
  - [`hi --set-color`](#hi---set-color)
  - [`hi --unset-color`](#hi---unset-color)
  - [`hi --plugins`](#hi---plugins)
  - [`hi --plugin-off`](#hi---plugin-off)
  - [`hi --plugin-on`](#hi---plugin-on)
  - [`hi --add-plugin`](#hi---add-plugin)
  - [`hi --remove-plugin`](#hi---remove-plugin)

## Every command

### `hi --help`

`hi --help`: this text. Works in a session too.

![hi --help](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-help.svg)

### `hi --version`

`hi --version`: hi's version: the packaging stamp, or git describe. Works in a session too.

![hi --version](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-version.svg)

### `hi --use`

`hi --use <backend>`: skip probing and force that backend (ssh counts as one). Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --plain`

`hi --plain`: a bare shell, nothing copied: no tar or /tmp needed. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --no-plain`

`hi --no-plain`: hi's own session this once, past \_HI\_PLAIN=1. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --mux`

`hi --mux`: a local tmux/zellij/screen session; a repeat reattaches. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --no-mux`

`hi --no-mux`: skip the multiplexer this once, past --mux or \_HI\_MUX=1. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --keep`

`hi --keep`: keep the session on the target, in tmux/zellij/screen. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --no-keep`

`hi --no-keep`: an ordinary session, past \_HI\_KEEP=1 or a kept one. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --end`

`hi --end`: close the session \<target\> is keeping. Works in a session too.

It changes how a connect runs, which the [README's demos](../README.md) show.

### `hi --preview`

`hi --preview <subject>`: colors, packages, or header, as printed here.

![hi --preview colors](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview.svg)

![hi --preview packages](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview-2.svg)

![hi --preview header](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-preview-3.svg)

### `hi --doctor`

`hi --doctor [--json] [--problems] [--use <backend>] [ssh-options] [target]`: a read-only pre-flight report, or just its problems.

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

No image: its output depends on the network and the release tags.

### `hi --add-package`

`hi --add-package <group> <pkg>[,...] [--dry-run]`: add rows to a group in your packages file.

![hi --add-package useful lazygit,tig --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-add-package.svg)

### `hi --remove-package`

`hi --remove-package <pkg>... [--dry-run]`: remove rows from your packages file.

![hi --remove-package kubectl --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-remove-package.svg)

### `hi --add-tag`

`hi --add-tag <host> <tag> [--dry-run]`: tag an ssh host, for the colors.

![hi --add-tag web-dev dev --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-add-tag.svg)

### `hi --set-color`

`hi --set-color <type> <name> <color> [rrggbb] [--dry-run]`: pin a color in your colors file.

![hi --set-color hosttag prod red --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-set-color.svg)

### `hi --unset-color`

`hi --unset-color <type> <name> [--dry-run]`: remove a pin from your colors file.

![hi --unset-color username root --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-unset-color.svg)

### `hi --plugins`

`hi --plugins`: list the plugins: what rides, and what is off.

![hi --plugins](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-plugins.svg)

### `hi --plugin-off`

`hi --plugin-off <name>... [--dry-run]`: switch plugins off: nothing of theirs rides.

![hi --plugin-off bat --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-plugin-off.svg)

### `hi --plugin-on`

`hi --plugin-on <name>... [--dry-run]`: switch them back on.

![hi --plugin-on tmux --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-plugin-on.svg)

### `hi --add-plugin`

`hi --add-plugin <group> <name> <file>... [<key>=<value>...] [--dry-run]`: carry the configs of a tool hi does not know.

![hi --add-plugin cli lnav lnav/config.json home=~/.config/lnav/config.json --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-add-plugin.svg)

### `hi --remove-plugin`

`hi --remove-plugin <name> [--dry-run]`: stop carrying them.

![hi --remove-plugin lnav --dry-run](https://ivylikethevine.github.io/say-hi/docs/tapes/usage-remove-plugin.svg)
