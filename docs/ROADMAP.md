# Tooling & practices roadmap

What's left, in four tiers by **how hard the work is**:

- **[Quick wins](#quick-wins)** — a single run, click, upstream PR, or
  one-line decision.
- **[Moderate](#moderate)** — bounded, with a precedent in the tree to copy
  and a test or budget to satisfy.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.
- **[Not scheduled](#not-scheduled)** — research and decisions nobody has
  made yet. Nothing there gates a release; an entry moves up a tier once
  someone commits to it.

Each entry opens with its **scope** in italics, ending _in-repo_ or _outside
this checkout_. Within a tier: dependency order, then ascending scope.
Nothing is wired up until its checkbox is ticked. Finished entries and
questions decided against are **deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)
- [Not scheduled](#not-scheduled)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below, and the one piece of product work left
(_[persistent sessions](#not-scheduled)_) is deferred past the tag. The
release below unblocks the channels after it.

- [ ] **A release has gone out under branch protection**, manifest step
      green — [Get a release out under branch protection](#quick-wins).
      `tap`, `aur`, `feature` and `brew` are `needs: publish`, so none can
      start before it.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap
      half is the [Homebrew tap](#moderate) entry.
- [ ] **A stability contract is written down**, so "experimental" has an
      opposite: one page (`docs/STABILITY.md`, or a CONTRIBUTING section)
      naming what 1.x won't break — the eighteen `common/flags`, every
      SETTINGS.md row, `$_HI_OVERLAY_FILES`, the `$_HI_HOME/say-hi` +
      `/etc/profile.d/say-hi.sh` layout, `_HI_RELEASE` — plus the semver rule
      and how a toggle is retired (warns one minor, then goes). The same
      commit turns SECURITY.md's _Supported versions_ prose into the version
      table it promises.

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see [Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates [Say what changed in a release](#quick-wins),
[Homebrew tap](#moderate) and [AUR](#blocked-until-someone-else-moves); the
rest of the tier is independent of it.

- [ ] **Get a release out under branch protection** — _scope: one real
      release, plus one repository setting to confirm first; outside this
      checkout._ `main` requires a PR (closing Scorecard's highest-severity
      finding), but no release has gone out under it yet.

  - `publish` opens a PR onto a `manifests-<tag>` branch instead of pushing to
    `main`; `tap`/`aur` read the manifests out of the `packages` artifact, so
    the release doesn't wait on that merge.
  - Confirm _Settings → Actions → General → Allow GitHub Actions to create
    and approve pull requests_ before the first tag — off, `gh pr create`
    fails at the last step, with the packages already published.
  - Required checks are still unset. Keep `advisory lint` (markdownlint,
    hadolint, demo-staleness), lychee and trivy advisory. `e2e (macOS)`,
    `e2e (Windows)` and the Windows client job are green on push and
    reasonable candidates. Requiring even one — `fast suites (ubuntu-latest)`
    is the obvious pick — also lifts Scorecard's Branch-Protection score from
    6 to 8 of 10 ("require ≥1 status check" is the whole of its tier 3).
    Confirm in _Settings → Branches → Branch protection rules_.
  - Stop there. Tier 4 needs ≥2 reviewers _and_ code-owner review, which a
    solo maintainer can't satisfy, and tier 5 (_dismiss stale
    reviews_/_include administrators_) scores nothing while tier 4 is unmet.
    Leave _Do not allow bypassing the above settings_ off: zero points, and
    it locks the only maintainer out of merging their own PRs.
  - `snapshot.yml` already does a tag push and `gh release create`/`upload`
    from a workflow (the per-commit `snapshot-<sha>` prerelease,
    [PACKAGING.md](PACKAGING.md#snapshot-builds)), so the token side is
    proven and no tag-protection ruleset covers `snapshot-*`. Unproven: the
    environment gate and the manifest PR.
  - **Ticks when:** a release has gone out under the rule, manifest PR opened
    rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ `release.yml`'s `publish` job composes
      GitHub's `releases/generate-notes` output plus the verification
      checklist (minisign key from
      [PACKAGING.md](PACKAGING.md#verifying-a-release-download)) into one
      `--notes` body, generated notes first — `gh --generate-notes` would put
      its own after `--notes`. `CHANGELOG.md` stays out unless that proves
      not enough. **Ticks when:** a release body names what changed and how
      to check it, unattended.

- [ ] **tldr page** — _scope: one upstream pull request; outside this
      checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
      by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
      draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
      against tldr-pages. **Ticks when:** merged upstream.

- [ ] **Flip to stable** — _scope: one commit at tag time; in-repo._ The
      EXPERIMENTAL banner has echoes: README's banner and its anchor
      (CONTRIBUTING.md's first paragraph links it by name), ALTERNATIVES.md's
      maturity cell, SECURITY.md's _Supported versions_. **Ticks when:** every
      one reads as a released project in the commit the tag points at.

- [ ] **A release candidate before the tag** — _scope: one `v1.0.0-rc.1` tag
      and one decision; in-repo then outside it._ `v0.0.x` tags skip
      `tap`/`aur` by design and no `v*` tag has ever been cut, so `v1.0.0`
      would walk `bump.sh` → manifests PR → tap PR → `brew audit` untested —
      the highest-value entry on the page. Decide whether `-rc` tags should
      reach the tap (`release.yml` special-cases only `v0.0.x`), then cut one
      and read the run. **Ticks when:** an rc has gone through every job
      `v1.0.0` will, tap PR opened.

## Moderate

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
      real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
      `Formula/` dir), add a fine-grained PAT (contents + PRs write) as
      `HOMEBREW_TAP_TOKEN`, re-run the `brew install`/`test`/`audit` gate on
      an actual Mac (`/opt/homebrew`, not the Linuxbrew prefix used so far).
      **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
      `tap` job opened a PR for.

- [ ] **A devcontainer Feature** — _scope: one publish to ghcr, after a
      release; the code half has shipped; outside this checkout._
      `packaging/devcontainer/src/say-hi/` and `release.yml`'s `feature` job
      are done ([PACKAGING.md](PACKAGING.md#devcontainer-feature)), verified
      end to end against `version: main`. **Do:** cut the release, let
      `feature` run, install it from a real `devcontainer.json`. **Ticks
      when:** a `features` entry naming `ghcr.io/ivylikethevine/say-hi/say-hi`
      installs a working `hi` in a fresh devcontainer.

## Blocked until someone else moves

Tracked, not actionable; none is a v1.0.0 criterion.

- [ ] **Outside the repo, once a release exists** — _scope: a badge, a
      questionnaire, a toggle and a check; mostly outside this checkout._

  - the [OpenSSF Best Practices](https://www.bestpractices.dev/) badge —
    [CII_BEST_PRACTICES_DRAFT.md](CII_BEST_PRACTICES_DRAFT.md) answers all 67
    passing-level criteria and README's badge block carries two commented-out
    lines waiting on a project ID. Left: register at bestpractices.dev,
    transcribe the draft, uncomment the badge. The tick means _passing_,
    blocked on three release-shaped MUST criteria until the first tag ships;
  - a Repology badge — in README's badge block already (renders empty for
    now); ticks once it carries a real version, after deb/rpm/apk, the tap
    and the AUR do;
  - GitHub Discussions, linked from `ISSUE_TEMPLATE/config.yml`;
  - a check that `ubi`/`mise use ubi:` finds `hi.sh` in the release tarball,
    and a PACKAGING.md line if it needs an `--exe` hint;
  - `actions/attest-sbom` beside the provenance step.

- [ ] **AUR** — _scope: nothing until registration reopens; then an account,
      a key, and one manual first push; outside this checkout._ Registration
      is closed to new accounts (spam). `release.yml`'s `aur` job stays
      written and unexercised until it reopens.

  - **When it reopens:** register; generate an ed25519 key, add the private
    half as the `AUR_SSH_KEY` repo secret. First push per package is manual
    (namcap gate against the published source, then only `PKGBUILD` +
    `.SRCINFO`); the `aur` job handles the versioned package after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.

- [ ] **Bump zizmor past 1.29.0** — _scope: one line in
      `.github/actions/setup-tool/tools.txt`, once actionlint catches up;
      in-repo._ zizmor 1.30.0's `self-repository` audit flags every `./...`
      action/workflow reference in the tree (38 of them) in favour of
      GitHub's `$/...` syntax, and `ci.yml`'s `workflow-lint` job gates on
      zizmor with no `--min-severity`, so the pin bump alone breaks CI.
      actionlint `1.7.12` (also pinned in `tools.txt`; current as of
      2026-08-31) rejects `$/...`, so no version of the pair agrees today.
      `.github/scripts/check_tool_versions.sh` reports zizmor as the one
      outdated pin meanwhile.

  - **When actionlint catches up:** a release past `1.7.12` that accepts
    `$/...`. zizmor's own `--fix=safe` does the `./...` → `$/...` rewrite, so
    the pin bump and the rewrite land in one commit.
  - **Ticks when:** zizmor is back on its latest release and
    `check_tool_versions.sh` reports every pin current.

## Not scheduled

Research and decisions nobody has made yet; nothing here gates a release or
is queued.

- [ ] **Persistent sessions on a disposable target** — _scope: the largest
      entry here — cleanup semantics on both paths, a findable tree path and
      something to reap it, and SECURITY.md's footprint promise rewritten;
      in-repo._ A dropped connection loses the session today (the tree is
      deleted on exit). Goal: keep the tree across a drop, reconnect into the
      same session, delete only on a definitive exit or a configurable
      timeout. **Opt-in, not the default** — a bare `hi <target>` stays
      disposable.

  - `hi --session <name> <target>` writes a deterministic tree
    (`${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>`, mode 0700, `<name>`
    restricted to alnum/`-`/`_`) instead of `mktemp`'s random one; a second
    call finds it, skips re-copying an unchanged payload, and reattaches.
  - `load.sh`'s on-exit hook (proven by
    `tests/targets/ssh_disconnect_test.sh`) becomes conditional, not
    weaker — add a case for dropped-with-`--session` keeping the tree.
  - Reaping defaults to zero footprint: a tree older than
    `_HI_PERSIST_TIMEOUT` (unset means keep until `hi --session <name>
--end`) is deleted the moment the _next_ `hi` touches that target. A
    detached watchdog (`sh -c 'sleep N; rm -rf ...' &`) is the stronger
    opt-in. SECURITY.md's _Footprint and cleanup_ describes both modes.
  - Reattachment rides whatever multiplexer the target has: `tmux` →
    `screen` → `dtach`, in that order; a target with none declines
    persistence with a clear message.
  - **Ticks when:** `--session` survives a dropped connection and reattaches,
    a bare `hi <target>` is unchanged, the timeout and watchdog are
    documented settings, SECURITY.md describes both cleanup modes, and the
    disconnect suite covers both paths.

- [ ] **Raise the client's bash floor to 4, keep 3.2 only for the target** —
      _scope: reshapes the eval/table plumbing across `common/`; in-repo._
      Bash 3.2 has no associative arrays, `mapfile` or namerefs, so tables
      are `|`-joined strings read back with `IFS='|' read`
      (`_HI_SHELL_TABLE` in `common/core.sh`, `_HI_BACKENDS` and
      `_HI_TRIM_TABLE` in `hi.sh`, `common/flags`) and arrays are filled
      through `eval` (`_hi_read_lines` in `common/core.sh`) — safe, but every
      reader has to check it. The floor only matters for the macOS _client_
      (Homebrew bash is the norm there; `#!/usr/bin/env bash` picks it up);
      target-only code could stay at 3.2. **Ticks when:** the decision is
      written down, and — if raising the floor — client-side tables move to
      bash 4 associative arrays/`mapfile` and the lint suite's 3.2-floor grep
      is scoped to target-only files.

- [ ] **A subscribable package repository** — _scope: a decision, then an
      OBS project or a PPA and a fourth manifest to keep current; outside
      this checkout._ PACKAGING.md's trade — no `apt upgrade` for not
      maintaining a repository — stands until people ask; this is where the
      asking lands. **Ticks when:** a decision is written down, and — if
      yes — one `.deb` or `.rpm` user gets a new release through their
      package manager.
