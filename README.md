# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

`hi <host>` is `ssh <host>` with your shell setup along: the session opens
with your prompt, your aliases, and your editor configs, on a host that has
none of them, and what hi put there is removed when it ends. Nothing is
installed on the host. The same command opens a session in a container, a
Nomad allocation, or a Kubernetes pod.

![Payload](https://img.shields.io/badge/ssh_payload-65KB-4c1) [![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases) [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397) [![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/ivylikethevine/say-hi?label=scorecard)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi) [![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # or any directory you like
~/say-hi/scripts/install.sh    # wires your shell's rc file and asks one question
exec $SHELL                    # reload
hi <anything>                  # ssh, with your prompt, aliases, and editors along
```

No sudo: the install links `~/.local/bin/hi` and writes only to your rc files
and `~/.config/say-hi`. `--preset balanced` answers without asking,
`--dry-run` shows every write first, and `hi --configure` has the settings
menu.

![hi into a web host whose site answers 502: the site and errs aliases from the overlay find a refused upstream, sudo vim opens on the carried vimrc to fix the port, restart restarts nginx through systemd, and the site answers 200](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).
>
> New here: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) has the words
> these docs use and a starting path for the way you work.
> [docs/README.md](docs/README.md) indexes the rest, the man page and the tldr
> draft included.

## Contents

- [In Sixty Seconds](#in-sixty-seconds)
- [What You Get](#what-you-get)
- [Target Requirements](#target-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Hostname, Username, and Group/Tag Colors](#hostname-username-and-grouptag-colors)
- [Built from/with/in mind](#built-fromwithin-mind)
- [say-hi and the alternatives](#say-hi-and-the-alternatives)
- [Testing](#testing)
- [Getting help and contributing](#getting-help-and-contributing)
- [AI usage](#ai-usage)
- [Roadmap](#roadmap)
- [Release Stages](#release-stages)
- [License](#license)

---

## What You Get

A line each here; [the tour](docs/TOUR.md) has each one's story, its GIF, and
the config it was recorded with.

- [**Your aliases, in every shell, on every host**](docs/TOUR.md#your-aliases-in-every-shell-on-every-host):
  `~/.config/say-hi/` rides along on every connect, to a box that does not
  run your shell too.
- [**Your editors and your git**](docs/TOUR.md#your-editors-and-your-git):
  your vimrc and nanorc, under `sudo` as well, and your git aliases without
  your keys.
- [**Know where you are at a glance**](docs/TOUR.md#know-where-you-are-at-a-glance):
  a color a host and a tag, so prod looks like prod.
- [**One command, every backend**](docs/TOUR.md#one-command-every-backend):
  ssh hosts, docker and podman containers, nomad allocations, and kubernetes
  pods, one `hi <target>` for all of them.
- [**Survive a dropped link**](docs/TOUR.md#survive-a-dropped-link): `hi --keep`
  keeps the session in tmux on the box and reattaches it after a drop.
- [**The header tells you what's missing**](docs/TOUR.md#the-header-tells-you-whats-missing):
  a package check on every connect, quiet where the tools are there.
- [**Every target in one tab**](docs/TOUR.md#every-target-in-one-tab):
  `hi <TAB>` lists your ssh hosts and every running container, allocation,
  and pod.

## Target Requirements

<!-- Seven shields endpoint badges, published by pages.yml
     (.github/scripts/platform_badges.sh) - which says why
     img.shields.io/github/check-runs cannot answer per job here, and is where
     a renamed CI job has to be mirrored. A badge added here reads
     "inaccessible" until the next Pages deploy publishes its file. -->

![Minimal](https://img.shields.io/badge/minimal-ssh%20%2B%20base64%20%2B%20tar-0A6E8A)
![Full](https://img.shields.io/badge/full-bash%203.2-0A8E8A)
![Linux](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Flinux.json)
![macOS](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fmacos.json)
![FreeBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ffreebsd.json)
![OpenBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fopenbsd.json)
![Alpine client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Falpine.json)
![Windows](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows.json)
![Windows client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows-client.json)

Which OSes hi lands a session on, which shell you end up in, what proves each
row, and everything answered **no**, and why:
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

- **Client**: `bash` 3.2+, `tar` and `gzip` (a libarchive `tar` compresses on
  its own and needs no `gzip`), and `base64` (coreutils, busybox, macOS/BSD, and Git
  Bash all ship one; `openssl base64` stands in where none does), `ssh` for
  ssh targets, any of `docker`/`podman`/`nerdctl`/`finch` and
  `nomad`/`kubectl` for those backends. hi has no protocol of its own: `ssh`
  is the transport, `base64` is armor, not crypto
  ([docs/SECURITY.md](docs/SECURITY.md)).
- **Target**: `base64` (or `openssl`), `mktemp`, and a `tar` that reads
  gzip (`tar -z`), on every backend: the payload lands the same way over
  ssh and an exec. `bash` gets the full session; without it you
  land in the best shell the target has, with a smaller one
  ([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).
- **A slow link**: the ssh wire is meant to stay at or under 128 KB — 8 s over
  a 128 kbps link — and the gzipped payload is held to 64 KB by the bench
  group. The payload badge above is today's wire size.
- **bash 3.2** is the floor on both ends (macOS still ships it; what that rules
  out of the code is
  [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on)),
  **fish 3.3** (Ubuntu 22.04's) and **zsh 5.5** (RHEL 8's) for the other two
  shells hi styles.
- Everything else is plain POSIX/bash/zsh/fish — no compiled artifacts, no
  package manager, no build step.

## Installation

- The `.deb`/`.rpm`/`.apk` are on
  [the releases page](https://github.com/ivylikethevine/say-hi/releases), and
  [the package repository](docs/PACKAGING.md#package-repository) serves them
  signed and subscribable, so upgrades ride your package manager:

  ```sh
  # Debian, Ubuntu
  sudo curl -fsSLo /etc/apt/keyrings/say-hi.asc https://ivylikethevine.github.io/say-hi/say-hi.asc
  echo 'deb [signed-by=/etc/apt/keyrings/say-hi.asc] https://ivylikethevine.github.io/say-hi/apt stable main' |
    sudo tee /etc/apt/sources.list.d/say-hi.list
  sudo apt update && sudo apt install say-hi

  # Fedora, RHEL, and derivatives
  sudo curl -fsSLo /etc/yum.repos.d/say-hi.repo https://ivylikethevine.github.io/say-hi/say-hi.repo
  sudo dnf install say-hi

  # Alpine
  wget -O /etc/apk/keys/say-hi.rsa.pub https://ivylikethevine.github.io/say-hi/say-hi.rsa.pub
  echo https://ivylikethevine.github.io/say-hi/apk >>/etc/apk/repositories
  apk add say-hi
  ```

  A packaged install still needs `hi --install` once per user, for the rc
  lines; it leaves the package's `/usr/bin/hi` to the package manager. macOS:
  `brew install ivylikethevine/tap/say-hi`
  ([the tap](docs/PACKAGING.md#homebrew-tap)), then `hi --install`.

- `say-hi/scripts/install.sh`, or `hi --install` once hi is on your `PATH`.
  It syntax-checks `~/.bashrc`, `~/.zshrc`, and `~/.config/fish/config.fish`
  with each shell's own checker first and asks before continuing if any fails
  (`--yes` answers it). Your login shell is wired, and any other of the three
  with an rc file already; `--shell bash,zsh` names them instead, and `all` is
  every one installed. Each line tests for the tree first, so a deleted
  checkout costs a shell nothing. On macOS `~/.bash_profile` is taught to read
  `~/.bashrc`. A first install asks one thing, which preset to start from
  ([docs/SETTINGS.md](docs/SETTINGS.md#presets)), and nothing else. For an rc file a dotfile manager owns, `--print-rc` prints
  each block and writes none
  ([docs/SETTINGS.md](docs/SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)). `hi` is linked at `~/.local/bin/hi` (`--link system`
  for `/usr/bin/hi`, `--link none` for no link — the wired shells alias it
  either way). Then reload your shell. zsh completes `hi` through the
  `compinit` your `~/.zshrc` runs, before hi's line or after it; hi runs none
  of its own.
- `hi --configure` reopens the settings menu: pick a preset, or flip any setting
  on its pages — Header, its cells and package check, Prompt, Plugins — or
  by a switch's key on the first, and save to `~/.config/say-hi/settings.sh` ([Configuration](#configuration)).
- `hi --doctor [<target>]` when something is slow or failing (`--problems` for
  only what needs fixing, `--json` for a bug report); it also reports which rc
  files are wired and where `hi` on your `PATH` leads.
  [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) goes symptom by symptom.
- `hi --update` moves a cloned install to the newest release tag, or on the
  `dev` branch fast-forwards it (`--dry-run` says what it would do; a package
  upgrades through its package manager).
- `hi --add-package core bat,batcat` adds a row to the `core` group of
  `~/.config/say-hi/packages`, copying the shipped roster there first;
  `hi --remove-package bat` takes it out again.
- `hi --add-tag web1 prod` writes the `# Tags: prod` line above `Host web1`
  in `~/.ssh/config`, which a `hosttag` row then colors
  ([docs/COLORS.md](docs/COLORS.md)).
- `hi --add-color hostname prod-db yellow` pins a color in
  `~/.config/say-hi/colors`, copying the shipped pins there first;
  `hi --remove-color hostname prod-db` removes the pin.
- `hi --plugins` lists every config hi carries to a target, and what rides;
  `hi --disable-plugin lazygit vim` keeps a plugin home and
  `hi --enable-plugin` brings it back; `hi --edit plugins` opens your plugins
  file in your editor, for the configs of a tool hi does not know
  ([docs/SETTINGS.md](docs/SETTINGS.md#switching-a-plugin-off)).
- The whole surface is twenty-four flags: `hi --help` (or bare `hi`) lists them,
  [docs/USAGE.md](docs/USAGE.md) shows what each prints, `man hi` is the long
  form, and everything hi does not answer goes to `ssh`.
- **A dropped connection ends the session** and nothing on the target
  outlives it, unless you ask: `hi --keep <target>` runs the session in
  `tmux`, `zellij`, or `screen` on the target, the next `hi <target>`
  reattaches, and `hi --end <target>` or a day unattended closes it. On a
  target with none of the three, its files and directory wait fifteen
  minutes for you
  ([how](docs/INTEGRATIONS.md#terminal-multiplexers)).
- Done with it? `hi --uninstall` (or `scripts/install.sh --uninstall`) strips
  hi's lines from your rc files, removes the `settings.sh` it wrote, and
  unlinks `~/.local/bin/hi` (or a `/usr/bin/hi` of its own making; a
  package's stays). A one-time `<rc>.hi-orig` backup goes once the rc matches
  it again; one that differs is kept, with the differing lines printed. Left
  behind on purpose: the checkout or package (`apt remove say-hi` and
  friends), and the rest of `~/.config/say-hi` (`--purge` removes that too).
  `--dry-run` names what would go. To take it all off a cloned install:

  ```sh
  hi --uninstall --purge && rm -rf ~/say-hi
  ```

## Configuration

Your config lives in `${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` and rides
along to every host you say `hi` to. `settings.sh` is what `hi --configure`
writes; the install copies nothing else there, so the shipped `colors` and
`packages` apply until you copy one out of the tree's `config/` to edit
(`hi --add-package` and `hi --add-color` do the copying) or add an
`aliases.sh` of your own. The editor rcs need no copy: hi carries your
own `~/.vimrc`, `~/.config/nvim/init.lua`, `~/.nanorc`, or `~/.emacs`
([why that works](docs/SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).
The overlay file table, the settings menu, and every setting are in
[docs/SETTINGS.md](docs/SETTINGS.md); how a session reaches the target is
[How it works](docs/HOW-IT-WORKS.md). The tools hi wires in where a
target has them — your prompt program, mise, direnv, bat, eza, and more — are
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

**_IMPORTANT: every overlay file in that directory is copied to every host you
say `hi` to — keep local-only lines (a token, an internal hostname) in
`~/.bashrc` and friends instead._** What lands on a target, and that it is
removed on exit:
[docs/SECURITY.md](docs/SECURITY.md#what-hi-writes-on-a-target).

### Hostname, Username, and Group/Tag Colors

Every username and hostname gets a color derived from its name; a line in
`~/.config/say-hi/colors` (`prod-db = "yellow"` under `[hostname]`, which
`hi --add-color hostname prod-db yellow` writes) pins one, and
`hi --preview colors` shows what every host and your user resolve to. Tags
(`# Tags:` lines in `~/.ssh/config`, which sshm writes), patterns, truecolor
schemes of your own, and using the hash in your own prompt:
[docs/COLORS.md](docs/COLORS.md).

## Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) — _from_ — (**became** `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) — _with_ — (optional, but _highly_
  recommended for `~/.ssh/config` host tags)
- [bat](https://github.com/sharkdp/bat) — _in mind_ — (the reason the
  aliases.sh fallthrough logic works as portably as it does; `bat` is
  sometimes `batcat`)
- [eza](https://github.com/eza-community/eza) — _in mind_ — (the colorized
  `ls` upgrade, with its flags kept apart from plain `ls`'s for older hosts)
- [fish](https://github.com/fish-shell/fish-shell) — _with_ — (my preferred
  shell: its defaults/built-ins are easy to understand, but it is not POSIX)

## say-hi and the alternatives

How say-hi compares to similar tools, and when to use something else:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

## Testing

`tests/test_runner.sh` runs the suites with a colored pass/fail summary;
`--group fast` and `--group lint` are [the gate](docs/CONTRIBUTING.md#the-gate)
CI runs on every push. Runbook: [docs/TESTING.md](docs/TESTING.md).

![Tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)
[![Kcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage.json)](docs/TESTING.md#coverage-and-profiling)
[![Bashcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage-v2.json)](docs/TESTING.md#coverage-and-profiling)

Both coverage badges measure the shipped product over the full sweep and gate
nothing; read their average as the figure
([why two](docs/TESTING.md#coverage-and-profiling)).

## Getting help and contributing

A question, a bug, or an idea: [docs/SUPPORT.md](docs/SUPPORT.md) says where
each one goes and what to bring (`hi --doctor --json` answers most of it).
Anything exploitable goes privately, per
[docs/SECURITY.md](docs/SECURITY.md#reporting-a-vulnerability). A change:
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the gate, what a review
bounces on, and which docs change with what; who decides is
[docs/GOVERNANCE.md](docs/GOVERNANCE.md).

## AI usage

Heavily inspired by
[Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency).

This started as code written entirely by
[me](https://github.com/ivylikethevine), but I have used generative AI to write
large parts of it. All of the code here is my _responsibility_ regardless: AI
is a tool, not an owner of a project. I have personally understood, reviewed,
and approved all of the AI-generated code in this repository, and **mainline
releases** carry the same accountability to me as anything I write and publish
myself.

## Roadmap

The features and changes left to build; nothing here is parked or descoped.
One list, in the order the work is best done. Once its **Ticks when** holds,
an entry leaves as one sentence for [CHANGELOG.md](CHANGELOG.md)'s
`## Unreleased` section. What a release waits on is
[Release Stages](#release-stages).

- [ ] **Every default and preset audited before the tag** —
      [CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break)
      freezes the name and default of all 46 rows of
      [SETTINGS.md's _Every setting_](docs/SETTINGS.md#every-setting) and the
      five presets, and a toggle removal is a 2.0. **Do:** read each row's
      default as a stranger's first run, with the `balanced` first-install
      default and `hi --update`'s verification as the known changes.
      **Ticks when:** the 1.0.0 release note lists the defaults that moved,
      or says none did.

- [ ] **The session starts once the core files land** — on a fresh
      connection a script past about 45 KB costs two extra round trips over
      a small one, and one under 40 KB costs one (at 150 ms added); the
      unarmored script is about 65 KB (the payload badge), while the tree a bash session needs
      to start is a fraction of what ships: without
      `hi.sh`, the completion files, the fish and zsh files, and `keep.sh`,
      it is 29.4 KB gzipped against 56.6 KB, a script of about 35 KB.
      **Do:** the core members first on the boot call's stdin and the rest
      after, the stub starting once the core is in while the rest lands
      behind it. **Ticks when:** a cold connect is a round trip shorter at
      150 ms added, with nothing dropped from the tree, and the relay, fish,
      zsh, and kept-session suites pass.

- [ ] **A connect without a tty overlaps too** — a scripted `hi host cmd`
      keeps the two calls in series, since a failed boot leaves the stub
      waiting on the target and only a tty's hangup ends it. **Do:** a stub
      that ends on its own when the boot call fails, with no timeout as its
      signal. **Ticks when:** a connect with stdin off a tty is about two
      round trips shorter, and the forced-command and `maxsessions1` cases
      pass that way.

- [ ] **The target side keeps up on a starved CPU** — with the target held
      to an eighth of one core (`scratch/slow_target.sh`: a CFS quota on the
      suites' sshd image, loopback, no netem; 16CPU/60GB host, at b55dacb8),
      what a cold connect adds over a plain `ssh host true` grows from
      143 ms to 473 ms, while sshd's own handshake moves from 128 ms to
      159 ms. That is about what the connect's round trips cost at 150 ms
      added. It grows faster than the cap does: a quarter core to an eighth
      doubles the shell work but takes hi's share from 215 ms to 473 ms, so
      some of the target side runs side by side or waits out a slice.
      **Do:** profile the target side under the cap and cut what scales.
      **Ticks when:** the same script puts hi's share at an eighth of a core
      within twice its full-core figure.

- [ ] **ssh's own `Tag` keyword beside the `# Tags:` line** — OpenSSH 9.4
      added `Tag` and `Match tagged`, so a block can carry one tag ssh itself
      reads and `ssh -G host` reports as `tag`, with no comment to keep in
      step. **Do:** take a block's `Tag` where it has no `# Tags:` line, in
      the config walk and in the `ssh_tags` member that rides the overlay;
      `hi --add-tag` says when a block already carries one, `hi --doctor`
      names which of the two a tag came from. **Ticks when:** a host under
      `Tag prod` and no comment colors by its `hosttag` row, reads
      `settings.prod.sh`, and carries the tag past the first hop, with the
      relay suite passing.

## Release Stages

What the 1.0 tag and the releases after it wait on, in order. Once its
**Ticks when** holds, an entry leaves as one sentence for
[CHANGELOG.md](CHANGELOG.md)'s `## Unreleased` section, as the roadmap's do.
_Post 1.0_ entries are outside this checkout: an account or an upstream
review that lands when it lands.

- [ ] **I.** _At the 1.0.0 tag:_ **A stability contract is written down** —
      [docs/CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break).
      **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
      versions_ prose into its version table.

- [ ] **II.** _Post 1.0:_ **tldr page** — `docs/tldr.md` matches `docs/hi.1`
      and upstream style. **Do:** open the PR against tldr-pages. **Ticks
      when:** merged.

- [ ] **III.** _Post 1.0:_ **AUR** — registration is closed to new accounts, so
      `publish-external.yml`'s `aur` job is written but unexercised. **When
      it reopens:** register, add `AUR_SSH_KEY` as a repository secret,
      and push each package once by hand
      ([docs/RELEASING.md](docs/RELEASING.md#aur)). **Ticks when:** both
      packages are live and a dispatch has kept `say-hi` current for one
      release.

- [ ] **IV.** _Post 1.0:_ **nixpkgs** — the flake in this repository is the
      nix channel until then
      ([docs/RELEASING.md](docs/RELEASING.md#channels-weighed-and-not-shipped)).
      **Do:** open the package PR against nixpkgs, with a maintainer entry.
      **Ticks when:** merged, and one release's bump has landed through the
      usual update bot or by hand.

## License

[MIT](LICENSE.md).
