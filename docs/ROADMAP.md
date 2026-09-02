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

2. [ ] **Get a release out** — _scope: one tag; outside this checkout._ Push
       a `v*` tag and approve the `release` environment when `publish` pauses;
       it opens a manifest PR onto a `manifests-<tag>` branch (`tap`/`aur` read
       the manifests out of the `packages` artifact, so the release doesn't
       wait on the merge; a PR opened with `GITHUB_TOKEN` gets no CI run of its
       own, so read it before merging). `v0.0.2-rc.4` proved everything up to
       there - build, gate, signed sums, the body's notes and checklist - so a
       `CHANGELOG.md` stays out. Gates the **Homebrew tap**, the **AUR** and
       the **Outside the repo** bundle. **Ticks when:** a final tag's manifest
       PR is opened.

3. [ ] **tldr page** — _scope: one upstream pull request; outside this
       checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
       by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

4. [ ] **A per-tag overlay** — _scope: a directory convention, one tar, one
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

5. [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
       real Mac; outside this checkout._ Waits on **Get a release out**.
       Create `homebrew-tap` (plain repo, `Formula/` dir), add a fine-grained
       PAT (contents + PRs write) as `HOMEBREW_TAP_TOKEN`, re-run the
       `brew install`/`test`/`audit` gate on an actual Mac (`/opt/homebrew`,
       not the Linuxbrew prefix used so far). **Ticks when:**
       `brew install ivy/tap/say-hi` works, from a release the `tap` job
       opened a PR for.

6. [ ] **Package repository on the Pages site** — _scope: one key, one secret,
       one committed file, one release; outside this checkout._ The code half
       shipped: `packaging/mkrepo.sh` builds the apt, rpm and apk repositories
       out of `mkpkg.sh`'s packages, `release.yml` signs the rpm in `build` and
       attaches `package-repo.tar.gz` in `publish`, `pages.yml` serves it from
       the newest non-prerelease release at
       `https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}`, packaging-smoke
       builds one per PR and `tests/packaging/repo_test.sh` installs from one
       as all three clients. The key half shipped too: `GPG_SIGNING_KEY` is
       set in the release environment and `packaging/gpg/say-hi.asc` is
       committed ([PACKAGING.md](PACKAGING.md#package-repository)).
       **Do:** cut a release from a tag that carries `say-hi.asc`.
       **Ticks when:** `apt install say-hi`, `dnf install say-hi` and
       `apk add say-hi` each work from the published URL, and a second release
       upgrades one of them in place.

7. [ ] **Outside the repo, once a release exists** — _scope: a badge, a
       toggle and two checks; mostly outside this checkout._ Waits on
       **Get a release out**. Four small pieces: a Repology badge (in
       README's badge block already, rendering empty; ticks once it carries
       a real version, after deb/rpm/apk, the tap and the AUR do); GitHub
       Discussions, linked from `ISSUE_TEMPLATE/config.yml`; a check that
       `ubi`/`mise use ubi:` finds `hi.sh` in the release tarball, plus a
       PACKAGING.md line if it needs an `--exe` hint; and
       `actions/attest-sbom` beside the provenance step.

8. [ ] **AUR** — _scope: nothing until registration reopens; then an
       account, a key, and one manual first push; outside this checkout._
       Registration is closed to new accounts (spam), and `release.yml`'s
       `aur` job stays written and unexercised until it reopens. **When it
       reopens:** register; generate an ed25519 key, add the private half
       as the `AUR_SSH_KEY` repo secret; the first push per package is
       manual (namcap gate against the published source, then only
       `PKGBUILD` + `.SRCINFO`), and the `aur` job handles the versioned
       package after. **Ticks when:** both packages are live on the AUR and
       the `aur` job has kept `say-hi` current for one real release.

### Miscellaneous

1. Add uptime to header
2. Allow header items to be rearranged
3. Ship default package floor at 2
4. Improve default package colors
5. Add ram usage, similar to CPU usage
