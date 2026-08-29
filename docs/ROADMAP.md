# Tooling & practices roadmap

What's left, sorted into four tiers by **how hard the work is**:

- **[Quick wins](#quick-wins)** — a single run, click, upstream PR, or
  one-line decision.
- **[Moderate](#moderate)** — bounded, with a precedent in the tree to copy,
  plus a test or budget to satisfy on the way out.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.

Research and undecided questions — nothing scheduled, nothing gating a
release — live in [FUTURE.md](FUTURE.md) instead of here; an entry moves over
once someone commits to it.

Each entry opens with its **scope** in italics — what the work _is_, not how
long it takes — closing with _in-repo_ or _outside this checkout_. Ordering
inside a tier is dependency order first, then ascending scope.

Nothing is wired up until its checkbox is ticked. Finished entries and
questions decided against are **deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below, and the one piece of product work left
(_[persistent sessions](FUTURE.md#persistent-sessions-on-a-disposable-target)_)
is deferred past the tag, tracked in [FUTURE.md](FUTURE.md) rather than here.
What's left is a single chain — the release below unblocks the channels after
it.

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
      CONFIGURATION.md row, `$_HI_OVERLAY_FILES`, the `$_HI_HOME/say-hi` +
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
  - Required checks are still unset. Keep `advisory lint` (markdownlint,
    hadolint, demo-staleness), lychee, trivy advisory. `e2e (macOS)`, `e2e (Windows)`
    and the Windows client job are green on push and reasonable candidates.
    Requiring even one — `fast suites (ubuntu-latest)` is the obvious pick —
    is also what Scorecard's Branch-Protection check is waiting on: it scores
    in tiers, and "require ≥1 status check" is the whole of tier 3 (6→8 of
    10). Confirm in _Settings → Branches → Branch protection rules_.
  - Stop there. Tier 4 needs ≥2 reviewers *and* code-owner review, which a
    solo maintainer can't satisfy, and Scorecard requires a tier fully met
    before the next one scores anything — so tier 5's *dismiss stale
    reviews*/*include administrators* earns nothing while tier 4 is unmet.
    Concretely: leave _Do not allow bypassing the above settings_ off. Turning
    it on would cost zero points and lock the only maintainer out of merging
    their own PRs.
  - `snapshot.yml` has exercised a tag push and `gh release create`/`upload`
    from a workflow on a push to `main` (the per-commit `snapshot-<sha>`
    prerelease, [PACKAGING.md](PACKAGING.md#snapshot-builds)), so the token
    side of publishing is proven, and no tag-protection ruleset covers the
    `snapshot-*` pattern.
    What it cannot prove is the environment gate and the manifest PR.
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

- [ ] **A devcontainer Feature** — _scope: one publish to ghcr, which needs a
      release first; the code half has shipped; outside this checkout._
      `packaging/devcontainer/src/say-hi/` and `release.yml`'s `feature` job
      are done and described in
      [PACKAGING.md](PACKAGING.md#devcontainer-feature); verified end to end
      against `version: main`. **Do:** cut the release, let `feature` run,
      install it from a real `devcontainer.json`. **Ticks when:** a
      `features` entry naming `ghcr.io/ivylikethevine/say-hi/say-hi` installs
      a working `hi` in a fresh devcontainer.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none is a v1.0.0 criterion.

- [ ] **Outside the repo, once a release exists** — _scope: a badge, a
      questionnaire, a toggle and a check; mostly outside this checkout._
      Listed together so they're not forgotten between the tag and the
      announcement:
      - the [OpenSSF Best Practices](https://www.bestpractices.dev/) badge —
        the in-repo half has shipped:
        [CII-BEST-PRACTICES-DRAFT.md](CII-BEST-PRACTICES-DRAFT.md) answers
        all 67 passing-level criteria against this tree, and README's badge
        block carries the two commented-out lines waiting on a project ID.
        What's left is outside this checkout — register at bestpractices.dev,
        transcribe the draft, uncomment the badge — and the tick still means
        *passing*, which stays blocked on three release-shaped MUST criteria
        until the first tag ships;
      - a Repology badge — added to README's badge block already (renders
        empty for now); the tick still means it's carrying a real version,
        once deb/rpm/apk, the tap and the AUR do;
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
