# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

![Payload](https://img.shields.io/badge/ssh_payload-65KB-4c1)
[![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

![hi into a container: the header and its package check, the git segment inside a checkout on the target, cat through the box's bat, and the empty /tmp it leaves behind](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).
>
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
  - [Before 1.0](#before-10)
  - [Post 1.0](#post-10)
- [License](#license)

---

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # the directory has to be named say-hi
~/say-hi/scripts/install.sh    # wires your rc files, then the settings menu (s saves, q skips)
exec $SHELL                    # reload
hi <anything>                  # ssh, with your prompt, aliases, and editors along
```

No sudo: the install links `~/.local/bin/hi` and writes only to your rc files
and `~/.config/say-hi`. `--preset balanced` answers the menu without opening
it, `--dry-run` shows every write first.

## What You Get

Each GIF below is one persona's real config - the settings behind every one
are in [docs/SETTINGS.md](docs/SETTINGS.md).

### Connect Via More Than SSH

`hi <TAB>` answers with the `Host` entries in `~/.ssh/config` _and_ every
running container, allocation, and pod, each tagged with its backend;
`hi --<TAB>` answers hi's own flags without probing any backend. An operator
at a bastion, in fish for its pager's description column.

![hi TAB listing ssh hosts and containers from every backend, then hi --TAB listing flags](https://ivylikethevine.github.io/say-hi/docs/tapes/complete.gif)

### The Header Tells You What's Missing

A package check of the tools you care about, each with a priority, organized
into a `packages.d/` of named groups, each in its own color (`default` and
`extra` ship, more of your own ride alongside); the header checks it on
every target — one quiet line on a box that has them, a loud one on a box
that does not. A homelab: bash from a laptop into the nas and the pihole,
keeping the distro prompt — hi's is off (`_HI_DISABLE_PROMPT=1`), and the
header, the check, and the aliases ride along anyway.

![hi's header package check on a box with the tools installed, then on a bare one](https://ivylikethevine.github.io/say-hi/docs/tapes/packages.gif)

### One Config Directory, Every Host, Every Shell

`~/.config/say-hi/` ships to every target: one `aliases.sh` alias works in a
bash session on a debian container and a fish session on an alpine box,
reached through docker and podman. The operator again, in fish, with the
header trimmed to the clocks, the backend counts, and the check on a
blue-to-red ramp of their own. A box with no bash gets the aliases-only tier —
hi's own aliases, not the overlay
([docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#the-shell-you-end-up-in)).

![one aliases.sh overlay, used in a bash session on a debian container and a fish session on an alpine container](https://ivylikethevine.github.io/say-hi/docs/tapes/overlay.gif)

### Your Editors

`nano`, `vim`, and `nvim` open with hi's nanorc, vimrc, and `init.lua` on a
box with none of those files, and nothing is installed or left running on the
target. A developer, zsh on a laptop into the team's shared dev box, where the
prompt is starship's, not hi's (`_HI_PROMPT_TOOL=starship`; hi keeps the
header, editors, and aliases).

![nano and vim with hi's rc files inside a session](https://ivylikethevine.github.io/say-hi/docs/tapes/editors.gif)

### Know Where You Are at a Glance

`# Tags:` lines in `~/.ssh/config`, a `colors` overlay pinning each tag, and
`hi --preview colors` to see what every host resolves to — then a prod host
lands in red and a dev host in green. A sysadmin, bash from a laptop into two
fish ssh hosts, with a two-line fish prompt of their own riding the overlay,
drawn on the colors hi resolved.

![hi --preview colors, then hi into a prod-tagged host with a red prompt and a dev-tagged host with a green one](https://ivylikethevine.github.io/say-hi/docs/tapes/colors.gif)

### One Command, Any Backend

`hi <name> <command>` runs one command inside the session and only its output
comes back: the same loop over an ssh host, a docker container, a nomad
allocation, and a kubernetes pod (`-F` is ssh's, passed through unchanged; the
recording's ssh config is a throwaway). The pod is busybox `ash` with no bash
— the aliases-only tier — and hi says so, once, and runs the command anyway.
A researcher, in zsh, sweeping the cluster's backends.

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
- **A slow link**: the ssh wire stays at or under 128 KB — 8 s over a 128 kbps
  link. Today's (the payload badge above) is about half that.
- **bash 3.2** is the floor on both ends (macOS still ships it; what that rules
  out of the code is
  [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#what-a-review-will-bounce-on)),
  **fish 3.7** (Ubuntu 24.04's) and **zsh 5.8** (Debian 11's) for the other
  two shells hi styles.
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
  (the one question before the settings menu; `--yes` answers it). A shell
  that is not installed gets no rc file; on macOS `~/.bash_profile` is taught
  to read `~/.bashrc`. `hi` is linked at `~/.local/bin/hi` (`--link system`
  for `/usr/bin/hi`, `--link none` for no link — the wired shells alias it
  either way). Then reload your shell.
- `hi --configure` reopens the settings menu: pick a preset, or flip any
  setting in its one list — Header, Features, Prompt, Advanced — and save to
  `~/.config/say-hi/settings.sh` ([Configuration](#configuration)).
- `hi --doctor [<target>]` when something is slow or failing (`--json` for a
  bug report); it also reports which rc files are wired and where `hi` on your
  `PATH` leads.
- `hi --update` moves a cloned install to the newest release tag (`--dry-run`
  names it first; a package upgrades through its package manager).
- `hi --add-package bat:3,batcat:3` adds a row to a
  `~/.config/say-hi/packages.d/` group (`--group <name>` picks which one,
  default `custom`) without touching the shipped roster.
- The whole surface is thirteen flags: `hi --help` (or bare `hi`) lists them,
  `man hi` is the long form, and everything hi does not answer goes to `ssh`.
- **A dropped connection ends the session** and nothing on the target
  outlives it ([why](docs/COMPATIBILITY.md#what-would-change-an-answer)). For
  a flaky link, `hi --mux <target>` starts the session inside a local `tmux`,
  `zellij`, or `screen`, which survives the drop.
- Done with it? `hi --uninstall` (or `scripts/install.sh --uninstall`) strips
  hi's lines from your rc files, removes the `settings.sh` it wrote, and
  unlinks `~/.local/bin/hi` (or a `/usr/bin/hi` of its own making; a
  package's stays). Left behind on purpose: the checkout or package
  (`apt remove say-hi` and friends), the rest of `~/.config/say-hi` (`--purge`
  removes that too), and the one-time `<rc>.hi-orig` backups. `--dry-run`
  names what would go. To take it all off a cloned install:

  ```sh
  hi --uninstall --purge && rm -rf ~/say-hi ~/.bashrc.hi-orig ~/.zshrc.hi-orig ~/.config/fish/config.fish.hi-orig
  ```

## Configuration

Your config lives in `${XDG_CONFIG_HOME:-$HOME/.config}/say-hi/` and rides
along to every host you say `hi` to. `settings.sh` is what `hi --configure`
writes; the install copies nothing else there, so the shipped `colors` and
`packages.d/` apply until you copy one out of the tree's `settings/` to edit
(`hi --add-package` does the copying for `packages.d/`) or add an
`aliases.sh` of your own. The editor rcs need no copy: hi carries your
own `~/.vimrc`, `~/.config/nvim/init.lua`, `~/.nanorc`, or `~/.emacs`
([why that works](docs/SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)).
The overlay file table, the settings menu, and every setting are in
[docs/SETTINGS.md](docs/SETTINGS.md); how a session reaches the target is
[How it works](docs/HOW-IT-WORKS.md). The tools hi wires in where a
target has them — your prompt program, mise, direnv, bat, eza, and more — are
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

**_IMPORTANT: every overlay file in that directory is copied to every host
you say `hi` to — keep local-only lines (a token, an internal hostname) in
`~/.bashrc` and friends instead._** What lands on a target, and that it is
removed on exit: [docs/SECURITY.md](docs/SECURITY.md#what-hi-writes-on-a-target).

### Hostname, Username, and Group/Tag Colors

Every username and hostname gets a color derived from its name; a line in
`~/.config/say-hi/colors` (`hostname,prod-db,yellow`) pins one, and
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

What's left; nothing here is parked or descoped. An entry is deleted once
its **Ticks when** holds.

### Before 1.0

Ordered by scope, narrowest first. An entry that names the tag in its **Ticks
when** is one the 1.0.0 release itself waits on; the rest are in this checkout
and are not.

1. [ ] **A release says where the package went, and shows what changed** —
       shipped: `release.yml`'s `publish` leaves `tap` and `demo` slots in the
       release body, which its `tap` job and `demos.yml`'s `attach` job fill
       (`.github/scripts/release_slot.sh`) with the tap PR link and the
       `packages` GIF. **Ticks when:** the next real tag's release page shows
       the tap link and renders the GIF.

2. [ ] **A stability contract is written down** — shipped as
       [docs/CONTRIBUTING.md's _What 1.x will not break_](docs/CONTRIBUTING.md#what-1x-will-not-break).
       **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
       versions_ prose into the version table it promises.

3. [ ] **What hi carries is linted against the target, not the client** —
       shipped: the nano rule. It exempted any `include` line merely
       _mentioning_ `/usr/share/nano`, so a `/usr/share/nano/extra/*.nanorc`
       (a Debian split, absent on Fedora, Alpine, and macOS) rode out clean
       and cost the whole rcfile a bell; it now reads the path as one word and
       exempts only what sits directly under that directory. What is left is
       one exemption, `shfix`'s `$ZSH`/`$OSH`: those name a framework tree the
       _target_ may not have, unlike the `$_HI_CONFIG_DIR` and `$_HI_ROOT`
       beside them, which ride along. The other three the entry used to name
       are not assumptions and want no change - vim's `runtime` searches the
       target vim's own `&runtimepath` and is silent on a miss, `$VIMRUNTIME`
       is defined by whichever vim the target has, and micro's `import` names
       micro's own Go packages. **Do:** decide what a theme sourcing
       `$ZSH/lib/*.zsh` should do on a target with no oh-my-zsh, against what
       `tests/targets/framework_test.sh` pins today. **Ticks when:** that
       decision is in `docs/INTEGRATIONS.md` and the framework e2e suite is
       green on it.

4. [ ] **The header closes on the right** — shipped: `_hi_row_line` reserves
       the last two columns, pads each row to what is left, and closes it with
       a space and a `|`, so a row now ends where the banner ends rather than
       at its last cell. Every caller inherits it - `full_check`'s rows,
       `hi --doctor`, `hi --configure`'s previews - and
       `_HI_DISABLE_RIGHT_EDGE=1` (`hi --configure` advanced) gives back the
       open-ended row, the way `_HI_DISABLE_LEAD_SPACE` gives back the leading
       space.
       **Ticks when:** the header suites are green on the closed row at 80 and
       at a narrow `_HI_MAX_WIDTH`, wrapped rows included.

5. [ ] **The payload badge is measured, not typed** — `README.md`'s
       `ssh_payload` badge says 65KB; `_hi_wire_bytes` on this checkout
       returns 69617 bytes, which is 68KB. `bench_payload_readme_badge`
       (`tests/bench/bench_test.sh`) holds the two within 5%, and 5% of 68KB
       is 4KB, so a 3KB error is green - and the band widens with the payload,
       so the badge is free to drift further the more there is to measure.
       **Do:** stamp the number instead of typing it, the way
       `packaging/stamp.sh` already stamps the version at build time, and then
       cut the slack to the rounding error it was meant to absorb rather than
       the whole drift. **Ticks when:** the badge equals `_hi_wire_estimate`
       exactly, and adding a kilobyte to the payload turns `--group bench` red
       until it is restamped.

6. [ ] **CI walks the upgrade path a tag creates** — every job today installs
       one version into a fresh box, so nothing exercises the case
       [HI.60](docs/GLOSSARY.md#hi60-a-shell-that-outlives-the-tree) is
       about: a shell that loaded the _previous_ release, the tree rewritten
       under it, and the rc re-sourced in that same shell. It was found by
       hand in a container. **Do:** a job the tag triggers (`release.yml`'s
       `gate`, so a bad upgrade stops the release) that installs the previous
       tag in a container, opens a shell per wired dialect, replaces the tree
       with the tag being cut, re-sources each rc in that shell, and fails on
       any stderr or any `_HI_*` path left empty. **Ticks when:** a pushed
       `v*` tag runs it green, and putting core.sh's load guard back in
       `common/bash.sh` turns it red.

7. [ ] **Every Ubuntu job's egress is allowlisted, not only audited** — shipped:
       36 of the 50 `harden-runner` steps run `egress-policy: block` with an
       `allowed-endpoints` list, up from 6, and each of the 14 left on `audit`
       carries a comment naming the limit that keeps it there rather than work
       not done. Eight cannot block at all: `windows-e2e.yml`'s four jobs,
       `windows-client.yml`'s two, `ci.yml`'s `test-macos` and `release.yml`'s
       `brew` - harden-runner's Windows agent logs no endpoint or DNS event
       where an Ubuntu run logs both, and blocking is an Ubuntu capability.
       `ci.yml`'s `test-arm` has no step at all for the same reason one step
       further out: the community tier ships no arm agent, so it would log that
       and exit. Three reach arbitrary hosts by design (`link-check.yml`,
       `image-scan.yml`, `scorecard.yml`). Three reach a host no fixed row
       names: `ci.yml`'s `e2e` takes Fedora packages off whichever mirrors the
       metalink hands it - six distinct `*.mm.fcix.net`,
       `mirror.cs.princeton.edu` and `fedora.mirror.constant.com` across two
       shards of one run - `pages.yml`'s `deploy` polls a
       `run-actions-N-azure-REGION.actions.githubusercontent.com` whose shard
       and region both rotate, and `openbsd-e2e.yml`'s guest opens
       DNS-over-HTTPS to a bare `9.9.9.9`, where `allowed-endpoints` matches on
       hostname. What keeps the lists short is measured, not assumed:
       harden-runner fetches GitHub's meta domains and auto-allows `github.com`,
       `*.github.com`, `*.githubapp.com`, `ghcr.io` and
       `productionresultssa0`-`19.blob.core.windows.net`, so artifacts need no
       row either way - `coverage.yml`'s shards upload through
       `productionresultssa18` and `demos.yml`'s `collect` reaches nothing else
       at all - while `*.githubusercontent.com` is not meta and every host under
       it has to be listed. The rest of the cost is cold runs: a job that hits
       its caches reaches fewer hosts than one that misses, and `e2e-backends`'
       first list came off a run where `kind-action` restored kind from
       `actions/cache` and so never fetched kubectl - shard 3 then went red on a
       blocked `dl.k8s.io`. **Do:** read a cold run of each blocking job, and
       take `demos.yml`'s `attach` list off a tagged run rather than off its
       three steps, which is where it comes from now. **Ticks when:** no job is
       on `audit` without a comment naming the reason, and adding an unlisted
       download to a blocking job fails it.

### Post 1.0

Outside this checkout, and not what the tag waits on: each is an account or
an upstream review that lands when it lands.

1. [ ] **tldr page** — CLI surface is frozen, matches `docs/hi.1`, and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

2. [ ] **AUR** — Registration is closed to new accounts (spam), so
       `publish-external.yml`'s `aur` job stays written and unexercised.
       **When it reopens:** register, add `AUR_SSH_KEY` to the `release`
       environment, and push each package the first time by hand
       ([docs/RELEASING.md](docs/RELEASING.md#aur)). **Ticks when:** both
       packages are live and a dispatch has kept `say-hi` current for one
       real release. <https://archlinux.org/news/>

3. [ ] **Best Practices badge entry** — the answer sheet is
       [docs/OPENSSF-IMPROVEMENTS.md](docs/OPENSSF-IMPROVEMENTS.md). **Do:**
       settle the three rows it flags (`small_tasks`, `secure_2FA`,
       `hardened_site`), then enter it at bestpractices.dev. **Ticks when:**
       the live entry matches the sheet.

4. [ ] **vhs v0.12** — `demos.yml` pins vhs v0.11.0 because v0.12.0 writes no
       output: it captures every frame and prints `Creating <file>.gif...`,
       then exits 0 having never run ffmpeg (strace: it resolves
       `/usr/bin/ffmpeg` and never execs it; the same frames encode fine by
       hand). Suspect: upstream's browser start/close rewrite (42f1776). No
       upstream issue or newer release as of 2026-09-14. **Do:** report it
       upstream with that evidence. **Ticks when:** a v0.12.x release renders
       all six tapes green on a `demos.yml` dispatch and the pin moves to it.

## License

[MIT](LICENSE.md).
