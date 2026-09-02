# Tooling & Practices Roadmap

What's left, in one list ordered by **ascending scope** — the smallest work
first. Every entry is open for consideration; nothing here is parked or
descoped. Each opens with its scope in italics, ending _in-repo_ or _outside
this checkout_; an externally gated entry says what it waits on where it
sits, and dependencies are named inline — the release gates the Homebrew
tap, the AUR and the outside-the-repo bundle. Nothing is wired up until its
checkbox is ticked. Finished entries and questions decided against are
**deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [By scope](#by-scope)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below. The release unblocks the channels after it.

- [ ] **A release has gone out** and proved the whole path — the **Get a
      release out** entry below. `tap`, `aur` and `brew` are
      `needs: publish`, so none can start before it.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap
      half is the **Homebrew tap** entry.
- [ ] **A stability contract is written down** — shipped as
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break):
      the eighteen `common/flags`, every SETTINGS.md row,
      `$_HI_OVERLAY_FILES`, the install layout, `_HI_RELEASE`, the semver rule
      and how a toggle retires. **Ticks when** the tag commit turns
      SECURITY.md's _Supported versions_ prose into the version table it
      promises (the **Flip to stable** entry).

- [ ] **A subscribable package repository is live**, so a `.deb`/`.rpm`/`.apk`
      user gets the next release through their package manager — the
      **Package repository on the Pages site** entry.

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see the **AUR** entry below.

## By scope

1. [ ] **Bump zizmor past 1.29.0** — _scope: one line in
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

2. [ ] **Fan out e2e and merge the coverage workflows** — _scope: three
       workflow files; in-repo._ `e2e-backends` (`ci.yml`) installs podman,
       nomad and kind once and runs `podman`/`nomad`/`kube` serially inside
       forty minutes on one runner, because `test_runner.sh`'s suite-level
       width pins to 1 whenever a `backends` suite is selected - they share
       one container daemon. A three-way matrix job, one backend per runner,
       sidesteps that: separate runners are separate daemons. `e2e` (eight
       suites, twenty-five minutes) has the same shape, and the runner's own
       `--shard i/n` (already used by `windows-client.yml`) is the tool for
       it. `coverage.yml` and `coverage-v2.yml` are also identical in shape -
       the same `workflow_run` + `workflow_dispatch` trigger, the same
       push/success gate, the same `cancel-in-progress: true` concurrency -
       differing only in which tool (kcov vs. bashcov) runs over the fast
       suites; one workflow with a two-job matrix replaces both.

   - **Ticks when:** `e2e-backends` and `e2e` are each a matrix/shard of
     several runners instead of one, and `coverage.yml`/`coverage-v2.yml`
     are one workflow.

3. [ ] **Get a release out** — _scope: one tag; outside this checkout._ Push
       a `v*` tag and approve the `release` environment when `publish` pauses;
       it opens a manifest PR onto a `manifests-<tag>` branch (`tap`/`aur` read
       the manifests out of the `packages` artifact, so the release doesn't
       wait on the merge; a PR opened with `GITHUB_TOKEN` gets no CI run of its
       own, so read it before merging). `v0.0.2-rc.4` proved everything up to
       there - build, gate, signed sums, the body's notes and checklist - so a
       `CHANGELOG.md` stays out. Gates the **Homebrew tap**, the **AUR** and
       the **Outside the repo** bundle. **Ticks when:** a final tag's manifest
       PR is opened.

4. [ ] **Flip to stable** — _scope: one commit at tag time; in-repo._ The
       EXPERIMENTAL banner has echoes: README's banner and its anchor
       (CONTRIBUTING.md's first paragraph links it by name), ALTERNATIVES.md's
       maturity cell, SECURITY.md's _Supported versions_, which becomes the
       version table it promises, and the _what works today_ notes at the top
       of README's install section and PACKAGING.md, which go once the channels
       they name are live. **Ticks when:** every one reads as a released
       project in the commit the tag points at.

5. [ ] **tldr page** — _scope: one upstream pull request; outside this
       checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
       by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

6. [ ] **A per-tag overlay** — _scope: a directory convention, one tar, one
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

7. [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
       real Mac; outside this checkout._ Waits on **Get a release out**.
       Create `homebrew-tap` (plain repo, `Formula/` dir), add a fine-grained
       PAT (contents + PRs write) as `HOMEBREW_TAP_TOKEN`, re-run the
       `brew install`/`test`/`audit` gate on an actual Mac (`/opt/homebrew`,
       not the Linuxbrew prefix used so far). **Ticks when:**
       `brew install ivy/tap/say-hi` works, from a release the `tap` job
       opened a PR for.

8. [ ] **Package repository on the Pages site** — _scope: one key, one secret,
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

9. [ ] **Outside the repo, once a release exists** — _scope: a badge, a
       toggle and two checks; mostly outside this checkout._ Waits on
       **Get a release out**. Four small pieces: a Repology badge (in
       README's badge block already, rendering empty; ticks once it carries
       a real version, after deb/rpm/apk, the tap and the AUR do); GitHub
       Discussions, linked from `ISSUE_TEMPLATE/config.yml`; a check that
       `ubi`/`mise use ubi:` finds `hi.sh` in the release tarball, plus a
       PACKAGING.md line if it needs an `--exe` hint; and
       `actions/attest-sbom` beside the provenance step.

10. [ ] **AUR** — _scope: nothing until registration reopens; then an
       account, a key, and one manual first push; outside this checkout._
       Registration is closed to new accounts (spam), and `release.yml`'s
       `aur` job stays written and unexercised until it reopens. **When it
       reopens:** register; generate an ed25519 key, add the private half
       as the `AUR_SSH_KEY` repo secret; the first push per package is
       manual (namcap gate against the published source, then only
       `PKGBUILD` + `.SRCINFO`), and the `aur` job handles the versioned
       package after. **Ticks when:** both packages are live on the AUR and
       the `aur` job has kept `say-hi` current for one real release.
