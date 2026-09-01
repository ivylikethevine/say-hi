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

- [ ] **A subscribable package repository is live**, so a `.deb`/`.rpm`/`.apk`
      user gets the next release through their package manager —
      [Package repository on the Pages site](#moderate).

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see [Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates [Homebrew tap](#moderate) and
[AUR](#blocked-until-someone-else-moves); the rest of the tier is independent
of it.

- [ ] **Get a release out** — _scope: one tag; outside this checkout._ Push
      a `v*` tag and approve the `release` environment when `publish` pauses;
      it opens a manifest PR onto a `manifests-<tag>` branch (`tap`/`aur` read
      the manifests out of the `packages` artifact, so the release doesn't
      wait on the merge; a PR opened with `GITHUB_TOKEN` gets no CI run of its
      own, so read it before merging). Then check the two things only a real
      run can prove:

  - the release body names what changed and how to verify the download
    ([PACKAGING.md](PACKAGING.md#verifying-a-release-download)); add a
    `CHANGELOG.md` only if it doesn't;
  - the devcontainer Feature installs from a real `devcontainer.json` naming
    `ghcr.io/ivylikethevine/say-hi/say-hi` and `hi` runs in it
    ([PACKAGING.md](PACKAGING.md#devcontainer-feature)).
  - **Ticks when:** manifest PR opened, release body right, Feature installs
    a working `hi`.

- [ ] **A release candidate before the tag** — _scope: one `v0.1.0-rc.1` tag;
      outside this checkout._ Cut `v0.1.0-rc.1` and read the run: it walks
      the tag → `build` → `release` gate → `publish` for the first time, and
      the release must come out marked _Pre-release_, not _Latest_, with
      every artifact attached and the body right. A candidate reaches no
      channel and opens no manifest PR (`0.1.0-rc.1` is not a legal
      `pkgver`), so the tap PR, the AUR push and `brew audit` wait for the
      final tag. **Ticks when:** the rc is published as a prerelease with
      packages, tarball, `SHA256SUMS` and manifests attached.

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

- [ ] **Package repository on the Pages site** — _scope: one new secret, a
      step in `release.yml`'s `build` and `publish` jobs, a trigger and a copy
      step in `pages.yml`, three runbook sections, and their drift guards;
      in-repo, then one key outside it._ Serves `apt`, `dnf` and `apk` from
      `https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}` out of the
      packages nfpm already builds; no second packaging description.

  - **Key:** a GPG key as a repository secret (`GPG_SIGNING_KEY`, beside
    `APK_SIGNING_KEY`, not sealed to the `release` environment): `dnf
gpgcheck=1` verifies the RPMs themselves, and nfpm signs them in `build`
    (`rpm.signature.key_file`, env-expanded like the apk key) before
    `SHA256SUMS` and the attestation are computed. The same key signs the
    apt and rpm indexes in `publish`. Its public half and fingerprint go in
    PACKAGING.md next to the minisign key and are drift-checked the same
    way; the apk index reuses `packaging/apk/say-hi.rsa.pub`.
  - **`publish`:** after the upload, build `dist/repo/` from this release's
    packages — `apt/` (`apt-ftparchive packages`/`release`, `InRelease` +
    `Release.gpg`, pool under `pool/main/s/say-hi/`), `rpm/` (`createrepo_c`,
    `repodata/repomd.xml.asc`), `apk/x86_64/` and `apk/aarch64/` (the noarch
    apk in each, `apk index` + `abuild-sign` inside `alpine:3.24`), plus the
    public keys and a ready `say-hi.repo` — then `gh release upload` it as one
    asset, `package-repo.tar.gz`. `apt-utils`, `createrepo-c` and `gpg` are on
    the ubuntu runner; alpine comes from docker. Snapshots stay out: they are
    unsigned and replaced on every push.
  - **`pages.yml`:** add `Release` to the `workflow_run` list (the `if`
    already accepts a push event, which a tag push is), download
    `package-repo.tar.gz` from the latest `v*` release with
    `gh release download`, unpack into `_site/`. Release assets, not a run
    artifact, so the repo survives the 90-day artifact expiry and any later
    docs-only rebuild. Only the latest release is in the repo; older packages
    stay on their release pages.
  - **Docs:** PACKAGING.md's _deb / rpm / apk_ section gains the three
    sources lines (`deb [signed-by=/etc/apt/keyrings/say-hi.gpg] … stable
main`, the `.repo` file, the `/etc/apk/repositories` line); README's
    _Upgrading_ bullet stops saying there is no repository.
  - **Guards:** `packaging_test.sh` asserts the `build` signing block, the
    `publish` repo step and the `package-repo.tar.gz` upload, `pages.yml`'s
    download, and the GPG pin in PACKAGING.md; `packaging-smoke` in `ci.yml`
    adds `apt-get install` from a throwaway local copy of the generated `apt/`
    tree with a throwaway key, the way it already installs the apk.
  - **Ticks when:** `apt install say-hi`, `dnf install say-hi` and
    `apk add say-hi` each work from the published URL after a release, and a
    second release upgrades one of them in place.

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

Research and decisions nobody has made yet; nothing here gates a release.
Empty today — a proposal lands here when it is raised and not yet decided.
