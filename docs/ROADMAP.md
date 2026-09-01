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
entry below. The release unblocks the channels after it.

- [ ] **A release has gone out** and proved the whole path —
      [Get a release out](#quick-wins). `tap`, `aur`, `feature` and `brew`
      are `needs: publish`, so none can start before it.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap
      half is the [Homebrew tap](#moderate) entry.
- [ ] **A stability contract is written down** — shipped as
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break):
      the eighteen `common/flags`, every SETTINGS.md row,
      `$_HI_OVERLAY_FILES`, the install layout, `_HI_RELEASE`, the semver rule
      and how a toggle retires. **Ticks when** the tag commit turns
      SECURITY.md's _Supported versions_ prose into the version table it
      promises ([Flip to stable](#quick-wins)).

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see [Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates [Homebrew tap](#moderate) and
[AUR](#blocked-until-someone-else-moves); the rest of the tier is independent
of it.

- [ ] **Get a release out** — _scope: one tag and one repository setting;
      outside this checkout._ Push a `v*` tag; `publish` opens a manifest PR
      onto a `manifests-<tag>` branch (`tap`/`aur` read the manifests out of
      the `packages` artifact, so the release doesn't wait on the merge).
      Confirm _Settings → Actions → General → Allow GitHub Actions to create
      and approve pull requests_ first: off, `gh pr create` fails at the last
      step with the packages already published. Three things ride on the same
      run and are proven by it, not by more code:

  - the release body — `publish` composes `releases/generate-notes` plus the
    verification checklist
    ([PACKAGING.md](PACKAGING.md#verifying-a-release-download)) into one
    `--notes` body; `CHANGELOG.md` stays out unless that proves not enough;
  - the devcontainer Feature — `packaging/devcontainer/src/say-hi/` and the
    `feature` job are done ([PACKAGING.md](PACKAGING.md#devcontainer-feature));
    install it from a real `devcontainer.json` naming
    `ghcr.io/ivylikethevine/say-hi/say-hi` and run `hi`;
  - **Ticks when:** the manifest PR opened, the release body names what
    changed and how to check it, and the Feature installs a working `hi` in
    a fresh devcontainer.

- [ ] **A release candidate before the tag** — _scope: one `v1.0.0-rc.1` tag;
      outside this checkout._ No `v*` tag has ever walked `bump.sh` →
      manifests PR → tap PR → `brew audit` (`v0.0.x` tags skip the channels by
      design). Decided: `-rc` tags reach the tap and every other channel —
      `release.yml` special-cases only `v0.0.x`, so nothing to change. Cut the
      rc and read the run. **Ticks when:** an rc has gone through every job
      `v1.0.0` will, tap PR opened.

- [ ] **tldr page** — _scope: one upstream pull request; outside this
      checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
      by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
      draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
      against tldr-pages. **Ticks when:** merged upstream.

- [ ] **Flip to stable** — _scope: one commit at tag time; in-repo._ The
      EXPERIMENTAL banner has echoes: README's banner and its anchor
      (CONTRIBUTING.md's first paragraph links it by name), ALTERNATIVES.md's
      maturity cell, and SECURITY.md's _Supported versions_, which becomes the
      version table it promises. **Ticks when:** every one reads as a released
      project in the commit the tag points at.

## Moderate

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
      real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
      `Formula/` dir), add a fine-grained PAT (contents + PRs write) as
      `HOMEBREW_TAP_TOKEN`, re-run the `brew install`/`test`/`audit` gate on
      an actual Mac (`/opt/homebrew`, not the Linuxbrew prefix used so far).
      **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
      `tap` job opened a PR for.

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

- [ ] **A subscribable package repository** — _scope: a decision, then one
      hosted repository and a fourth manifest to keep current; outside this
      checkout._ PACKAGING.md's trade — no `apt upgrade` for not maintaining
      a repository — stands until people ask; this is where the asking lands.
      Every option below has to be fed from `release.yml`'s `publish` job,
      signed with a key that lives in Actions secrets, and added to the drift
      guard in `tests/packaging/packaging_test.sh` beside the formula.

  - **A static repo on the existing Pages site** (`reprepro`/`apt-ftparchive`
    for deb, `createrepo_c` for rpm, an `APKINDEX` for apk) — _scope: a
    publish step and three index generators._ Pro: consumes the `.deb`/`.rpm`/
    `.apk` nfpm already builds, covers all three formats, no third party, no
    new account. Con: the site build gains a signing key and a hundred MB of
    packages over time, index generation is ours to keep correct, and Pages
    has a 1GB soft limit — the closest fit, and the one most work to own.
  - **openSUSE Build Service (OBS)** — _scope: an account, a project, and a
    `.spec` + `.dsc` source layout beside nfpm's._ Pro: one project builds and
    hosts signed deb and rpm repos for Debian, Ubuntu, Fedora, openSUSE and
    more, with per-distro `apt`/`dnf` instructions generated for you. Con:
    OBS builds from _sources_, so the nfpm packages are not reusable — a
    second packaging description to keep in step with `install.sh`'s file
    list; no apk; a web UI and `osc` CLI to learn.
  - **Launchpad PPA** — _scope: a Launchpad account, a GPG key, `dput` from
    `publish`._ Pro: the channel Ubuntu users already know how to add. Con:
    Ubuntu-only and deb-only, a signed source package rather than nfpm's
    binary, one series per supported Ubuntu release to build for.
  - **Fedora COPR** — _scope: an account and a `.spec`._ Pro: the rpm
    equivalent of a PPA, free, well understood. Con: rpm-only, Fedora/EL
    only, a `.spec` to maintain.
  - **A hosted service (packagecloud, Cloudsmith, Gemfury)** — _scope: an
    account, an API token, one upload step._ Pro: takes nfpm's deb/rpm/apk
    as-is, generates and signs the indexes, all three formats. Con: a
    third-party account and free-tier limits (storage, bandwidth, repo count)
    that a hobby project can outgrow or that can change under it; users add a
    vendor hostname to their sources.
  - **Ticks when:** a decision is written down, and — if yes — one `.deb` or
    `.rpm` user gets a new release through their package manager.
