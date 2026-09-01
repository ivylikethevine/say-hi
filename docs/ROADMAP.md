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
      [Get a release out](#quick-wins). `tap`, `aur` and `brew` are
      `needs: publish`, so none can start before it.
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
      own, so read it before merging). `v0.0.2-rc.4` proved everything up to
      there - build, gate, signed sums, the body's notes and checklist - so a
      `CHANGELOG.md` stays out. **Ticks when:** a final tag's manifest PR is
      opened.

- [ ] **tldr page** — _scope: one upstream pull request; outside this
      checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
      by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
      draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
      against tldr-pages. **Ticks when:** merged upstream.

- [ ] **Flip to stable** — _scope: one commit at tag time; in-repo._ The
      EXPERIMENTAL banner has echoes: README's banner and its anchor
      (CONTRIBUTING.md's first paragraph links it by name), ALTERNATIVES.md's
      maturity cell, SECURITY.md's _Supported versions_, which becomes the
      version table it promises, and the _what works today_ notes at the top
      of README's install section and PACKAGING.md, which go once the channels
      they name are live. **Ticks when:** every one reads as a released
      project in the commit the tag points at.

## Moderate

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
      real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
      `Formula/` dir), add a fine-grained PAT (contents + PRs write) as
      `HOMEBREW_TAP_TOKEN`, re-run the `brew install`/`test`/`audit` gate on
      an actual Mac (`/opt/homebrew`, not the Linuxbrew prefix used so far).
      **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
      `tap` job opened a PR for.

- [ ] **Package repository on the Pages site** — _scope: one key, one secret,
      one committed file, one release; outside this checkout._ The code half
      shipped: `packaging/mkrepo.sh` builds the apt, rpm and apk repositories
      out of `mkpkg.sh`'s packages, `release.yml` signs the rpm in `build` and
      attaches `package-repo.tar.gz` in `publish`, `pages.yml` serves it from
      the newest non-prerelease release at
      `https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}`, packaging-smoke
      builds one per PR and `tests/packaging/repo_test.sh` installs from one
      as all three clients. Every step skips loudly until the key exists.
      **Do:** generate the GPG key, add `GPG_SIGNING_KEY`, commit
      `packaging/gpg/say-hi.asc`
      ([PACKAGING.md](PACKAGING.md#package-repository)), cut a release.
      **Ticks when:** `apt install say-hi`, `dnf install say-hi` and
      `apk add say-hi` each work from the published URL, and a second release
      upgrades one of them in place.

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

- [ ] **A per-tag overlay** — _scope: a directory convention, one tar, one
      SETTINGS.md section; in-repo._ One overlay ships to every target
      (README's _Configuration_ warning, SECURITY.md's _Trust boundaries_);
      the only per-host lever is a color. `_HI_TARGET_TAG` already resolves
      the leftmost `# Tags:` word before the payload is built, so
      `~/.config/say-hi/tags/<tag>/` holding the same `$_HI_OVERLAY_FILES` —
      shipped instead of, or layered after, the base overlay — needs no new
      probe. Open: precedence (replace vs. layer) and whether an untagged
      host gets the base overlay or nothing. Until decided, an admin with
      prod and customer hosts keeps the overlay empty or runs two
      `XDG_CONFIG_HOME`s.

- [ ] **A system-wide settings layer** — _scope: one file, one source line;
      in-repo._ A root-owned tree (`install.sh --prefix`) serves every user,
      but every setting lives in each user's `settings.sh`; there is no
      `/etc/say-hi/settings.sh` for a platform team's defaults, and no way to
      share an alias set short of a dotfiles repo. Whether that is wanted at
      all, and whether it ships to targets, is the question.
