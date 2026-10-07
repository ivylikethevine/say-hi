# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

`hi <host>` is `ssh <host>` with your shell setup along: the session opens
with your prompt, your aliases, and your editor configs, on a host that has
none of them, and what hi put there is removed when it ends. Nothing is
installed on the host. The same command opens a session in a container, a
Nomad allocation, or a Kubernetes pod.

![Payload](https://img.shields.io/badge/ssh_payload-77KB-4c1)
[![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

![hi into a container: the header and its package check, the git segment inside a checkout on the target, cat through the box's bat, and the empty /tmp it leaves behind](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).
>
> New here: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) has the words
> these docs use and a starting path for the way you work.
> [docs/README.md](docs/README.md) indexes the rest, the man page and the tldr
> draft included.

## Contents

- [In Sixty Seconds](#in-sixty-seconds)
- [What You Get](#what-you-get)
  - [Connect Via More Than SSH](#connect-via-more-than-ssh)
  - [The Header Tells You What's Missing](#the-header-tells-you-whats-missing)
  - [One Config Directory, Every Host, Every Shell](#one-config-directory-every-host-every-shell)
  - [Your Editors](#your-editors)
  - [Know Where You Are at a Glance](#know-where-you-are-at-a-glance)
  - [One Command, Any Backend](#one-command-any-backend)
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
- [License](#license)

---

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # the directory has to be named say-hi
~/say-hi/scripts/install.sh    # wires your shell's rc file and asks one question
exec $SHELL                    # reload
hi <anything>                  # ssh, with your prompt, aliases, and editors along
```

No sudo: the install links `~/.local/bin/hi` and writes only to your rc files
and `~/.config/say-hi`. `--preset balanced` answers without asking,
`--dry-run` shows every write first, and `hi --configure` has the settings
menu.

## What You Get

Each GIF below is one persona's real config - the settings behind every one
are in [docs/SETTINGS.md](docs/SETTINGS.md). Most leave the laptop as it is
(`_HI_DISABLE_LOCAL=1`), so the outside prompt is its distro's own and hi
begins at the target.

### Connect Via More Than SSH

`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation, and pod, each tagged with its backend;
`hi --<TAB>` answers hi's own flags without probing any backend. An operator
at a workstation, in fish for its pager's description column.

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

### The Header Tells You What's Missing

A package check of the tools you care about, in groups you switch on, in one
`packages` file (a copy of your own replaces the shipped one); the header
checks it on every target — one quiet line on a box that has them, a loud
one on a box that does not. A homelab: bash from an Ubuntu laptop into the
nas and the pihole, each keeping its distro's prompt — hi's is off
(`_HI_DISABLE_PROMPT=1`), and the header, the check, and the aliases ride
along anyway.

![hi's header package check on a box with the tools installed, then on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### One Config Directory, Every Host, Every Shell

`~/.config/say-hi/` ships to every target: one `aliases.sh` alias works in a
bash session on a debian container and a fish session on an alpine box, reached
through docker and podman. The operator again, in fish's own prompt at the
workstation and hi's on both boxes, with the header trimmed to the clocks, the
backend counts, and the check on a blue-to-red ramp of their own. A box with no
bash gets the aliases-only tier — hi's own aliases, not the overlay
([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your Editors

`nano` and `vim` open with the nanorc and vimrc you keep at home (or an
overlay copy), on a box with none of those files, and nothing is installed or
left running on the target. A developer, zsh on a Mac with its stock prompt,
into the team's shared dev box, where the prompt is starship's, not hi's
(`_HI_PROMPT_TOOL=starship`; hi keeps the header, editors, and aliases).

![nano and vim with the carried rc files inside a session](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know Where You Are at a Glance

`# Tags:` lines in `~/.ssh/config`, a `colors` overlay pinning each tag, and
`hi --preview colors` to see what every host resolves to — then a prod host
lands in red and a dev host in green. A sysadmin, bash from a laptop where
the prompt is hi's too (`_HI_PROMPT_TOOL=hi`), into two fish ssh hosts, with
a two-line fish prompt of their own riding the overlay, drawn on the colors
hi resolved.

![hi --preview colors, then hi into a prod-tagged host with a red prompt and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One Command, Any Backend

`hi <name> <command>` runs one command inside the session and only its output
comes back: the same loop over an ssh host, a docker container, a nomad
allocation, and a kubernetes pod (`-F` is ssh's, passed through unchanged; the
recording's ssh config is a throwaway). The pod is busybox `ash` with no bash
— the aliases-only tier — and hi says so, once, and runs the command anyway.
A researcher, in zsh on a Fedora laptop, sweeping the cluster's backends.

![a for loop running hi target cat over an ssh host, a docker container, a nomad allocation, and a kubernetes pod](https://ivylikethevine.github.io/say-hi/docs/tapes/run.gif)

## Target Requirements

<!-- Seven shields endpoint badges, published by pages.yml
     (.github/scripts/platform_badges.sh) - which says why
     img.shields.io/github/check-runs cannot answer per job here, and is where
     a renamed CI job has to be mirrored. A badge added here reads
     "inaccessible" until the next Pages deploy publishes its file. -->

![Minimal](https://img.shields.io/badge/minimal-ssh%20%2B%20base64-0A6E8A)
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

- **Client**: `bash` 3.2+ and `base64` (coreutils, busybox, macOS/BSD, and Git
  Bash all ship one; `openssl base64` stands in where none does), `ssh` for
  ssh targets, any of `docker`/`podman`/`nerdctl`/`finch` and
  `nomad`/`kubectl` for those backends. hi has no protocol of its own: `ssh`
  is the transport, `base64` is armor, not crypto
  ([docs/SECURITY.md](docs/SECURITY.md)).
- **Target**: `base64` (or `openssl`) for ssh targets; nothing extra for
  container/alloc/pod targets. `bash` gets the full session; without it you
  land in the best shell the target has, with a smaller one
  ([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).
- **A slow link**: the ssh wire is meant to stay at or under 128 KB — 8 s over
  a 128 kbps link — and the gzipped payload is held to 64 KB by the bench
  group. The payload badge above is today's wire size.
- **bash 3.2** is the floor on both ends (macOS still ships it; what that rules
  out of the code is
  [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on)),
  **fish 3.4** (Alpine 3.16's) and **zsh 5.5** (RHEL 8's) for the other two
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
  `~/.bashrc`. A first install asks whether hi styles this machine too, and
  nothing else. For an rc file a dotfile manager owns, `--print-rc` prints
  each block and writes none
  ([docs/SETTINGS.md](docs/SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)). `hi` is linked at `~/.local/bin/hi` (`--link system`
  for `/usr/bin/hi`, `--link none` for no link — the wired shells alias it
  either way). Then reload your shell. zsh completes `hi` through the
  `compinit` your `~/.zshrc` runs, before hi's line or after it; hi runs none
  of its own.
- `hi --configure` reopens the settings menu: pick a preset, or flip any setting
  on its pages — Header, its cells and package check, Prompt, Plugins,
  Aliases, Advanced — and save to `~/.config/say-hi/settings.sh` ([Configuration](#configuration)).
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
- `hi --set-color hostname prod-db yellow` pins a color in
  `~/.config/say-hi/colors`, copying the shipped pins there first;
  `hi --unset-color hostname prod-db` removes the pin.
- `hi --plugins` lists every config hi carries to a target, and what rides;
  `hi --plugin-off lazygit vim` keeps a plugin home and
  `hi --plugin-on` brings it back; `hi --add-plugin` and `hi --remove-plugin`
  carry the configs of a tool hi does not know
  ([docs/SETTINGS.md](docs/SETTINGS.md#switching-a-plugin-off)).
- The whole surface is twenty-six flags: `hi --help` (or bare `hi`) lists them,
  [docs/USAGE.md](docs/USAGE.md) shows what each prints, `man hi` is the long
  form, and everything hi does not answer goes to `ssh`.
- **A dropped connection ends the session** and nothing on the target
  outlives it, unless you ask: `hi --keep <target>` runs the session in `tmux`
  or `screen` on the target, the next `hi <target>` reattaches, and
  `hi --end <target>` or a day unattended closes it. `hi --mux <target>` does
  the wrapping on your side instead, in a local `tmux`, `zellij`, or `screen`
  ([both](docs/INTEGRATIONS.md#terminal-multiplexers)).
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
(`hi --add-package` and `hi --set-color` do the copying) or add an
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
`hi --set-color hostname prod-db yellow` writes) pins one, and
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
- [eza](https://github.com/eza-community/eza) — _in mind_ — (and its
  predecessor [exa](https://github.com/ogham/exa): colorized `ls` upgrades,
  both supported, with each one's flags kept apart for older hosts)
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

What's left; nothing here is parked or descoped. One list, in the order the
work is best done: what CI has yet to show, then the 1.0 tag. An entry is
deleted once its **Ticks when** holds. _Post 1.0_ entries wait on the tag:
what more a session carries first, then what is outside this checkout, an
account or an upstream review that lands when it lands.

1. [ ] _Before 1.0:_ **A blocked upstream shows as drift** — shipped:
       `check_tool_versions.sh` counts a problem, naming the host, when no
       lookup on one host answered (a blocked host, not a one-off rate
       limit). What is left is seeing it in CI. **Ticks when:** a
       `tool-versions.yml` dispatch with one upstream host removed from
       `allowed-endpoints` opens the tracking issue naming it.

2. [ ] _Before 1.0:_ **A dropped session is retried from any terminal** —
       the retry runs only in a pane of a local tmux, zellij, or screen, so a
       `hi --keep` in a bare terminal ends at the drop
       ([HI.65](docs/GLOSSARY.md#hi65-kept-session)); hi sets no keepalive,
       so a link that freezes is never a drop; and a keeping connect writes
       its record before it connects, so a target with no multiplexer is
       later told its kept session is gone. **Do:** retry wherever the
       session was up and ssh ended 255, for `_HI_KEEP_RETRY`; pass
       `ServerAliveInterval` on a connect that keeps unless the ssh config
       sets one; write the record from what the target's script answers.
       **Ticks when:** the `ssh_keep` suite drops a kept session's link in a
       terminal with no multiplexer and lands back in it, and a target with
       none of the three is never told a session is gone.

3. [ ] _Before 1.0:_ **Every tree has a claim and a timer** — a tree is
       removed by its session's exit hook, so a shell killed outright leaves
       it, and only an owner pane writes the `hi.kept` claim a later
       connect's sweep reads. **Do:** every session's `load()` writes the
       claim, and starts a watcher apart from the session that removes the
       tree once no shell has run on it for `_HI_KEEP_TIMEOUT`; the sweep
       reads every sibling tree's claim. **Ticks when:** a session shell
       killed with `kill -9` has its tree gone after the timeout with no
       connect in between, and a tree a reboot left is gone after the next
       connect.

4. [ ] _Before 1.0:_ **`--keep` holds on a target with no multiplexer** —
       there `--keep` warns and connects as usual, and the drop takes the
       tree. A shell cannot outlive its connection with nothing holding its
       terminal, but the tree can. **Do:** on such a target the hangup
       leaves the tree to the timer, with the directory the shell was in
       and its history beside it; a connect inside the window takes that
       tree and starts its shell there, and unpacks nothing. Its default
       window is fifteen minutes, where a live session's stays 24h.
       **Ticks when:** a drop and a reconnect on a target with none of the
       three land in the directory the first shell left, on one tree, and
       with no reconnect the tree is gone at the window's end.

5. [ ] _Before 1.0:_ **A multiplexer started in a session is the kept
       session** — `tmux` typed in a session that is not a kept one opens
       each pane on the host's own shell, which reads none of hi's rc, and
       outlives a drop on a tree that is then removed under it. **Do:** a
       bare `tmux`, `zellij`, or `screen` typed in a session runs what
       `hi --keep` typed there runs (`_hi_keep_here`): the session is
       `hi-<target>`, its panes hi's shell, the tree its own. One started
       with words of its own (`tmux new -s work`, `tmux attach`) is the
       user's, and passes through. **Ticks when:** `tmux` typed in a plain
       `hi <target>` session opens a pane that shows hi's prompt, and the
       next `hi <target>` after a drop attaches it.

6. [ ] _Before 1.0:_ **`--mux` goes** — it wraps the connect in a local
       multiplexer ([HI.52](docs/GLOSSARY.md#hi52-client-multiplexer-wrap)),
       which a dropped link ends with the connect inside it; what it does
       cover, a closed terminal, a kept session covers from the target, and
       the retry no longer needs its pane. **Do:** remove `--mux`,
       `--no-mux`, `_HI_MUX`, and `_hi_mux_wrap` with its zellij layout,
       keeping `_hi_mux_name` for the session's name; the docs name
       `tmux new -A -s <name> hi <target>` for a container or `--plain`
       session that has to outlive a terminal. **Ticks when:** `hi --mux`
       is refused as an unknown option, and no doc, completion, or setting
       names it.

7. [ ] _Before 1.0:_ **The release's GIF shows the package check** —
       shipped: the fixture's `packages` overlay
       (`docs/tapes/fixtures.sh`, `up:packages`) was rows of a shape hi no
       longer reads, so the check had nothing to draw; it is TOML rows now,
       its `colors` overlay with it, and `packages.tape` waits on the
       check's row after each connect, so a render without it fails. What is
       left is a render. **Ticks when:** a release's `demo.gif` shows the
       check's row on both boxes.

8. [ ] _At the 1.0.0 tag:_ **A stability contract is written down** —
       [docs/CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break).
       **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
       versions_ prose into its version table.

9. [ ] _Post 1.0:_ **A neovim config in more than one file** — only
       `nvim/init.lua` rides, and a `require` of a module under the config's
       `lua/` is dropped with the plugin managers', so a config split into
       modules starts nearly bare; an `init.vim` does not ride at all.
       **Do:** carry a module a `require` resolves under `lua/` the way an
       include is carried
       ([HI.57](docs/GLOSSARY.md#hi57-carried-configs-and-the-include-scan)),
       put the overlay's `nvim/` on `runtimepath` with no quote in the
       alias's body, and add `nvim/init.vim` as a member in the vim
       dialect. **Ticks when:** a target's `nvim` opens on an `init.lua`
       that requires two modules of its own, both loaded.

10. [ ] _Post 1.0:_ **Scripts of your own on a target's `$PATH`** — a file
        rides only as a config or under a `hi-carry` line. **Do:** a `bin/`
        directory of the overlay
        ([HI.58](docs/GLOSSARY.md#hi58-overlay-directory-members)), scripts
        alone and under a size cap, on a session's `$PATH`. **Ticks when:** a
        script in `~/.config/say-hi/bin/` runs by name in a session, and
        `hi --doctor` names a binary there as left home.

11. [ ] _Post 1.0:_ **git's aliases and settings, and none of its keys** —
        git has no plugin: a config that rode whole would bring identity,
        signing, and credential helpers to a box that must not have them.
        **Do:** a `git` plugin, off by default, added over the target's own
        config through `GIT_CONFIG_COUNT`'s `include.path` and never in its
        place, read in a dialect that drops `[user]`, `[credential]`, every
        signing and key setting, `includeIf`, and `url.*.insteadOf`. One of
        those rides only under a `hi-allow` line the user wrote above it,
        and `hi --plugins` names each that does. **Ticks when:** a carried
        alias runs on a target, `git config user.email` there is the
        target's own, and a `signingkey` rides only with its `hi-allow`.

12. [ ] _Post 1.0:_ **A nix flake** — the channels are deb, rpm, apk, the
        AUR, and Homebrew ([docs/PACKAGING.md](docs/PACKAGING.md)). **Do:**
        a flake with the package and a home-manager module that writes the
        rc block. **Ticks when:** `nix run` starts `hi`, and a CI job builds
        the flake.

13. [ ] _Post 1.0:_ **The portable rc block finds a Homebrew install** —
        `hi --install --print-rc`'s block looks in `$HOME`,
        `/usr/local/share`, and `/usr/share`, and whether an install from
        the formula writes its versioned keg into an rc is not yet known.
        **Do:** read what `hi --install` writes under a real `brew install`,
        name the tree through the formula's `opt` path where it is the keg,
        and add that path to the block. **Ticks when:** one rc loads hi on a
        machine with a clone and on one with the formula, across a
        `brew upgrade`.

14. [ ] _Post 1.0:_ **tldr page** — `docs/tldr.md` matches `docs/hi.1` and
        upstream style. **Do:** open the PR against tldr-pages. **Ticks
        when:** merged.

15. [ ] _Post 1.0:_ **Best Practices badge** — the answers are in
        [docs/OPENSSF-IMPROVEMENTS.md](docs/OPENSSF-IMPROVEMENTS.md). **Do:**
        settle its three flagged rows (`small_tasks`, `secure_2FA`,
        `hardened_site`) and enter it at bestpractices.dev. **Ticks when:**
        the live entry matches the sheet.

16. [ ] _Post 1.0:_ **AUR** — registration is closed to new accounts, so
        `publish-external.yml`'s `aur` job is written but unexercised. **When
        it reopens:** register, add `AUR_SSH_KEY` to the `release`
        environment, and push each package once by hand
        ([docs/RELEASING.md](docs/RELEASING.md#aur)). **Ticks when:** both
        packages are live and a dispatch has kept `say-hi` current for one
        release.

## License

[MIT](LICENSE.md).
