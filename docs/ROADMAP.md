# Tooling & practices roadmap

What's left, sorted into four tiers by **how hard the work is**:

- **[Quick wins](#quick-wins)** — a single run, click, upstream PR, or
  one-line decision.
- **[Moderate](#moderate)** — bounded, with a precedent in the tree to copy,
  plus a test or budget to satisfy on the way out.
- **[Large](#large)** — reshapes a contract, a promise, or a path convention
  across many files.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.

Each entry opens with its **scope** in italics — what the work _is_, not how
long it takes — closing with _in-repo_ or _outside this checkout_. Ordering
inside a tier is dependency order first, then ascending scope.

Nothing is wired up until its checkbox is ticked. Finished entries and
questions decided against are **deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Large](#large)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below, and the one piece of product work left
(_[persistent sessions](#large)_) is explicitly deferred past the tag. What's
left is a single chain — the release below unblocks the channels after it.

- [ ] **A release has gone out under branch protection**, manifest step
      green — [Get a release out under branch protection](#quick-wins).
      `tap`/`aur` are `needs: publish`, so they can't start before this.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap
      half is the [Homebrew tap](#moderate) entry.
- [ ] **A stability contract is written down**, so "experimental" has an
      opposite: one page (`docs/STABILITY.md`, or a CONTRIBUTING section)
      naming what 1.x won't break — the eighteen `common/flags`, every
      CONFIGURATION.md row, `$_HI_OVERLAY_FILES`, the
      `# hi-config-start`/`-end` markers, the `$_HI_HOME/say-hi` +
      `/etc/profile.d/say-hi.sh` layout, `_HI_RELEASE` — plus the semver rule
      and how a toggle is retired (warns one minor, then goes). Same commit
      fills SECURITY.md's _Supported versions_ placeholder.

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see [Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates the rest of this tier: [Say what changed in a
release](#quick-wins), [Homebrew tap](#moderate) and
[AUR](#blocked-until-someone-else-moves) all wait on it.

- [ ] **Get a release out under branch protection** — _scope: one real
      release, plus one repository setting to confirm first; outside this
      checkout._ `main` requires a PR now, closing Scorecard's
      highest-severity finding — but no release has gone out under it yet.

  - `publish` opens a PR onto a `manifests-<tag>` branch instead of pushing to
    `main`; `tap`/`aur` read the manifests out of the `packages` artifact, so
    the release doesn't wait on that merge.
  - Confirm _Settings → Actions → General → Allow GitHub Actions to create
    and approve pull requests_ before the first tag — off, `gh pr create`
    fails at the last step, with the packages already published.
  - Required checks are still unset. Keep `markdownlint`, `hadolint`,
    `demo-staleness`, lychee, trivy advisory. `e2e (macOS)`, `e2e (Windows)`
    and the Windows client job are green on push and reasonable candidates.
  - **Ticks when:** a release has gone out under the rule, manifest PR opened
    rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ `release.yml`'s `publish` job composes
      the body from GitHub's `releases/generate-notes` plus the verification
      checklist (minisign key from
      [PACKAGING.md](PACKAGING.md#verifying-a-release-download)), appended
      after `--notes` since `gh` puts generated notes last. `CHANGELOG.md`
      stays out unless that turns out not to be enough. **Ticks when:** a
      release body names what changed and how to check it, unattended.

- [ ] **tldr page** — _scope: one upstream pull request; the gate it waited
      on has lifted; outside this checkout._ CLI surface is frozen (eighteen
      flags, CI-enforced both ways by `parse_test.sh`/`targets_test.sh`).
      Draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
      against tldr-pages. **Ticks when:** merged upstream.

- [ ] **Flip to stable** — _scope: one commit at tag time, listed now so
      nothing is missed; in-repo._ The EXPERIMENTAL banner has echoes:
      README's banner and anchor, ALTERNATIVES.md's pre-1.0 cell, SECURITY.md's
      _Supported versions_. **Ticks when:** every one reads as a released
      project in the same commit the tag points at.

- [ ] **A release candidate before the tag** — _scope: one `v1.0.0-rc.1` tag
      and one decision; in-repo then outside it._ `v0.0.x` tags skip
      `tap`/`aur` by design, so `v1.0.0` would be the first tag to walk
      `bump.sh` → manifests PR → tap PR → `brew audit` untested. Decide
      whether `-rc` tags should reach the tap (`release.yml` special-cases
      only `v0.0.x`), then cut one and read the run. **Ticks when:** an rc
      has gone through every job `v1.0.0` will, tap PR opened.

## Moderate

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
      real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
      `Formula/` dir), add a fine-grained PAT (contents + PRs write) as
      `HOMEBREW_TAP_TOKEN`, re-run the `brew install`/`test`/`audit` gate on
      an actual Mac (`/opt/homebrew`, not the Linuxbrew prefix used so far).
      **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
      `tap` job opened a PR for.

- [ ] **De-personalise the shipped defaults** — _scope: two shipped files and
      a `--group bench` run; in-repo._ `settings/packages` tiers 4-5 warn a
      bare Debian target for lacking `dotnet`/`php`/`ffmpeg`/etc. and shout
      about missing `sshpass`; `settings/aliases.sh` hardcodes `micro
      -colorscheme=darcula` and personal `IDE`/`zed`/`now` rebinds. Keep the
      fallthrough machinery (`_HI_BATCAT_BIN` and friends); demote the
      package ranks to 1/0 and move rebinding/colour choices to the overlay,
      where `~/.config/say-hi/packages` and `aliases.sh` already win.
      **Ticks when:** a stock session on a bare Debian target prints no
      yellow or red line for a tool a server has no reason to have, the
      personal aliases follow the overlay, and both payload numbers still
      fit.

- [ ] **Add `_HI_DISABLE_ALIASES`** to turn off the shipped alias/export set
      — _scope: one toggle plus a doc row; in-repo._ `settings/aliases.sh`
      unconditionally sets `EDITOR`/`IDE`/`EZA_CONFIG_DIR`/`GCC_COLORS` and a
      dozen aliases; the user's own file runs last but can't disable them
      wholesale — clobbering an `EDITOR` an admin deliberately set is the one
      most people hit first. `_HI_DISABLE_BAT_ALIAS` already does this for
      `cat` alone; generalize the pattern. **Ticks when:**
      `_HI_DISABLE_ALIASES=1` ships none of it, and CONFIGURATION.md's
      _Every setting_ table has the row.

- [ ] **A devcontainer Feature** — _scope: one publish to ghcr, which needs a
      release first; the code half has shipped; outside this checkout._
      `packaging/devcontainer/src/say-hi/` downloads the release tarball,
      verifies it against `SHA256SUMS`, and calls `scripts/install.sh
      --prefix /usr/share` + `packaging/stamp.sh` — the same two scripts
      every other channel calls — then runs `hi --install --yes --preset`.
      `release.yml`'s `feature` job publishes to ghcr behind the same
      approval as the tap and the AUR; covered by eight
      `packaging_test.sh` cases and
      [PACKAGING.md](PACKAGING.md#devcontainer-feature). Verified end to end
      against `version: main`. **Do:** cut the release, let `feature` run,
      install it from a real `devcontainer.json`. **Ticks when:** a
      `features` entry naming `ghcr.io/ivylikethevine/say-hi/say-hi` installs
      a working `hi` in a fresh devcontainer.

## Large

- [ ] **Persistent sessions on a disposable target** — _**deferred until
      after v1.0.0.** Scope: the largest entry here — cleanup semantics on
      both paths, a findable tree path and something to reap it, and
      SECURITY.md's footprint promise rewritten; in-repo._ This is research,
      not queued work.

  A dropped connection loses the session outright today (the tree is deleted
  on exit). Goal: keep the tree across a drop, reconnect into the same
  session, delete only on a definitive exit or a configurable timeout.
  **Opt-in, not the default** — a bare `hi <target>` stays disposable.

  - `hi --session <name> <target>` writes a deterministic tree
    (`${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>`, mode 0700, `<name>`
    restricted to alnum/`-`/`_`) instead of `mktemp`'s random one; a second
    call finds it, skips re-copying an unchanged payload, and reattaches.
  - `load.sh`'s on-exit hook (proven by
    `tests/targets/ssh_disconnect_test.sh`) needs to become conditional, not
    weaker — add a case for dropped-with-`--session` keeping the tree.
  - Reaping defaults to zero footprint: a tree older than
    `_HI_PERSIST_TIMEOUT` (unset means keep until `hi --session <name>
    --end`) is deleted the moment the _next_ `hi` touches that target. A
    detached watchdog (`sh -c 'sleep N; rm -rf ...' &`) is the stronger
    opt-in. SECURITY.md's _Footprint and cleanup_ needs both modes described.
  - Reattachment rides whatever multiplexer the target already has: `tmux` →
    `screen` → `dtach`, in that order; a target with none declines
    persistence with a clear message rather than pretending.
  - **Ticks when:** `--session` survives a dropped connection and reattaches,
    a bare `hi <target>` is unchanged, the timeout and watchdog are
    documented settings, SECURITY.md describes both cleanup modes, and the
    disconnect suite covers both paths.

- [ ] **Raise the client's bash floor to 4, keep 3.2 only for the target** —
      _scope: reshapes the eval/table plumbing across `common/`; in-repo._ No
      associative arrays, `mapfile`, or namerefs under bash 3.2, so tables
      are `|`-joined strings read back with `IFS='|' read`
      (`_HI_SHELL_TABLE`, `_HI_BACKENDS`, `_HI_TRIM_TABLE`, `common/flags`)
      and arrays are filled through `eval` (`_hi_read_lines`,
      `core.sh:159-165`) — safe, but every reader has to check it. The floor
      only matters for the macOS _client_ (Homebrew bash is the norm there
      already; `#!/usr/bin/env bash` picks it up); target-only code could
      stay at 3.2. **Ticks when:** the decision is written down, and — if
      raising the floor — client-side tables move to bash 4 associative
      arrays/`mapfile` and the lint suite's 3.2-floor grep is scoped to
      target-only files.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none is a v1.0.0 criterion.

- [ ] **Outside the repo, once a release exists** — _scope: a badge, a
      questionnaire, a toggle and a check; none in-repo._ Listed together so
      they're not forgotten between the tag and the announcement:
      - the [OpenSSF Best Practices](https://www.bestpractices.dev/) badge —
        achievable now that CONTRIBUTING.md exists;
      - a Repology badge, once deb/rpm/apk, the tap and the AUR carry a
        version;
      - GitHub Discussions, linked from `ISSUE_TEMPLATE/config.yml`;
      - a check that `ubi`/`mise use ubi:` finds `hi.sh` in the release
        tarball, and a PACKAGING.md line if it needs an `--exe` hint;
      - `actions/attest-sbom` beside the provenance step.

- [ ] **AUR** — _scope: nothing actionable until registration reopens; then
      an account, a key, and one manual first push; outside this checkout._
      Registration is closed to new accounts (spam). `release.yml`'s `aur`
      job stays written and unexercised until it reopens.

  - **When it reopens:** register; generate an ed25519 key, add the private
    half as the `AUR_SSH_KEY` repo secret. First push per package is manual
    (namcap gate against the published source, then only `PKGBUILD` +
    `.SRCINFO`); the `aur` job handles the versioned package after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.
