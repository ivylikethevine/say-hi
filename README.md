# hi.sh -> sshrc supercharged

> EXPERIMENTAL UNTIL v1.0.0

_Don't `ssh`ush your hosts, say `hi`!_

`hi <host>` is `ssh <host>` with your shell setup along: the session opens
with your prompt, your aliases, and your editor configs, on a host that has
none of them, and what hi put there is removed when it ends. Nothing is
installed on the host. The same command opens a session in a container, a
Nomad allocation, or a Kubernetes pod.

![Payload](https://img.shields.io/badge/ssh_payload-67KB-4c1) [![Release](https://img.shields.io/github/v/release/ivylikethevine/say-hi)](https://github.com/ivylikethevine/say-hi/releases) [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14397/badge)](https://www.bestpractices.dev/projects/14397) [![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/ivylikethevine/say-hi?label=scorecard)](https://scorecard.dev/viewer/?uri=github.com/ivylikethevine/say-hi) [![OpenSSF Baseline](https://www.bestpractices.dev/projects/14397/baseline)](https://www.bestpractices.dev/projects/14397) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

## In Sixty Seconds

```sh
git clone https://github.com/ivylikethevine/say-hi ~/say-hi   # or any directory you like
~/say-hi/scripts/install.sh    # wires your shell's rc file and asks one question
exec $SHELL                    # reload
hi <anything>                  # ssh, with your prompt, aliases, and editors along
```

No sudo: the install links `~/.local/bin/hi` and writes only to your rc files
and `~/.config/say-hi`. `--dry-run` shows every write first.

![hi into a web host whose site answers 502: the site and errs aliases from the overlay find a refused upstream, sudo vim opens on the carried vimrc to fix the port, restart restarts nginx through systemd, and the site answers 200](docs/tapes/demo.gif)

> View these docs as a [website here](https://ivylikethevine.github.io/say-hi/).
> New here? [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) picks a
> starting path; [docs/README.md](docs/README.md) indexes the rest.

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
- [License](#license)

---

## What You Get

Each links to its story and GIF in [the tour](docs/GETTING-STARTED.md#a-tour).

- [**Your aliases, in every shell, on every host**](docs/GETTING-STARTED.md#your-aliases-in-every-shell-on-every-host):
  `~/.config/say-hi/` rides along on every connect, even to a box that does
  not run your shell.
- [**Your editors and your git**](docs/GETTING-STARTED.md#your-editors-and-your-git):
  your vimrc and nanorc, under `sudo` too, and your git aliases without your
  keys.
- [**Know where you are at a glance**](docs/GETTING-STARTED.md#know-where-you-are-at-a-glance):
  a color per host and tag, so prod looks like prod.
- [**One command, every backend**](docs/GETTING-STARTED.md#one-command-every-backend):
  ssh hosts, docker and podman containers, nomad allocations, and kubernetes
  pods, all through `hi <target>`.
- [**Survive a dropped link**](docs/GETTING-STARTED.md#survive-a-dropped-link):
  `hi --keep` runs the session in tmux on the box and reattaches after a drop.
- [**The header tells you what's missing**](docs/GETTING-STARTED.md#the-header-tells-you-whats-missing):
  a package check on every connect, quiet when the tools are there.
- [**Every target in one tab**](docs/GETTING-STARTED.md#every-target-in-one-tab):
  `hi <TAB>` lists your ssh hosts and every running container, allocation,
  and pod.

## Target Requirements

<!-- Shields endpoint badges, published by pages.yml
     (.github/scripts/platform_badges.sh, which says why check-runs cannot
     answer per job, and where a renamed CI job has to be mirrored). A new
     badge reads "inaccessible" until the next Pages deploy. -->

![Minimal](https://img.shields.io/badge/minimal-ssh%20%2B%20base64%20%2B%20tar-0A6E8A)
![Full](https://img.shields.io/badge/full-bash%203.2-0A8E8A)
![Linux](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Flinux.json)
![macOS](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fmacos.json)
![FreeBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ffreebsd.json)
![OpenBSD](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fopenbsd.json)
![Alpine client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Falpine.json)
![Windows](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows.json)
![Windows client](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fwindows-client.json)

- **Your machine**: bash 3.2+, `tar`, `gzip`, `base64`, and `ssh` or the
  backend's CLI (`docker`, `podman`, `nerdctl`, `finch`, `nomad`, `kubectl`).
- **The target**: `base64` (or `openssl`), `mktemp`, and a `tar` that reads
  gzip. With `bash` you get the full session; without it, your aliases and a
  colored prompt.
- **Shells hi styles**: bash 3.2, zsh 5.5, and fish 3.3 or newer.

The payload badge is what each connect sends. Every OS and shell, and
everything answered **no**: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Installation

From a clone, the four lines [above](#in-sixty-seconds). From a package
([docs/PACKAGING.md](docs/PACKAGING.md) has every channel):

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

# macOS
brew install ivylikethevine/tap/say-hi
```

Then run `hi --install` once per user to wire your shell.

- **Wiring**: the install wires your login shell and any of bash, zsh, and
  fish that already has an rc file, and asks which
  [preset](docs/SETTINGS.md#presets) to start from. It checks each rc's
  syntax first and leaves the rest of the file alone.
- **Your flags**: `--shell`, `--link`, `--preset`, and `--print-rc` (for an rc
  a dotfile manager owns) are in [docs/USAGE.md](docs/USAGE.md#hi---install);
  unattended installs are
  [Installing without a terminal](docs/GETTING-STARTED.md#installing-without-a-terminal).
- **Updating**: `hi --update` moves a clone to the newest signed release tag;
  a package updates through its package manager.
- **Uninstalling**: `hi --uninstall` removes hi's rc lines and its link;
  `--purge` removes `~/.config/say-hi` too. For a clone:

  ```sh
  hi --uninstall --purge && rm -rf ~/say-hi
  ```

All twenty flags are in [docs/USAGE.md](docs/USAGE.md) and `man hi`;
anything hi does not recognize goes to `ssh`. When something is slow or
failing, run `hi --doctor` and see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Configuration

Your config lives in `~/.config/say-hi/` (the overlay) and rides along to
every host you say `hi` to. `hi --configure` writes `settings.sh` there and
opens it in your editor. `hi --edit colors` and `hi --edit packages` copy the
shipped defaults in for editing. Your own `~/.vimrc`, `~/.nanorc`, and other
editor configs ride without a copy.

**_IMPORTANT: every file in the overlay is copied to every host you say `hi`
to. Keep local-only lines (a token, an internal hostname) in `~/.bashrc` and
friends instead._**
What lands on a target: [docs/SECURITY.md](docs/SECURITY.md#what-hi-writes-on-a-target).

More: every setting and preset in [docs/SETTINGS.md](docs/SETTINGS.md), the
tools hi wires in (your prompt program, mise, direnv, bat, eza) in
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md), and how a session reaches the
target in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

### Hostname, Username, and Group/Tag Colors

Every user and host gets a color derived from its name. Pin one in
`hi --edit colors` (`prod-db = "yellow"` under `[hostname]`), color a group
with a tag (`hi --add-tag web1 prod`), and check the result with
`hi --preview colors`. Patterns, truecolor schemes, and the hash in your own
prompt: [docs/COLORS.md](docs/COLORS.md).

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

`tests/test_runner.sh` runs the suites; `--group fast` and `--group lint` are
[the gate](docs/CONTRIBUTING.md#the-gate) CI runs on every push. Runbook:
[docs/TESTING.md](docs/TESTING.md).

![Tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Ftests.json)
[![Bashcov](https://img.shields.io/endpoint?url=https%3A%2F%2Fivylikethevine.github.io%2Fsay-hi%2Fbadges%2Fcoverage-v2.json)](docs/TESTING.md#coverage-and-profiling)

The coverage badge measures the shipped code over the full sweep and gates
nothing.

## Getting help and contributing

Questions, bugs, and ideas: [docs/SUPPORT.md](docs/SUPPORT.md)
(`hi --doctor --json` answers most of what a report needs). Anything
exploitable goes privately, per
[docs/SECURITY.md](docs/SECURITY.md#reporting-a-vulnerability). Changes:
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md); who decides:
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

[docs/ROADMAP.md](docs/ROADMAP.md): what is left to build, and what each release waits on.

## License

[MIT](LICENSE.md).
