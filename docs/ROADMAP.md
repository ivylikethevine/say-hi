# Tooling & Practices Roadmap

What's left, in one list ordered by **ascending scope** — the smallest work
first. Every entry is open for consideration; nothing here is parked or
descoped. Each opens with its scope in italics, ending _in-repo_ or _outside
this checkout_; an externally gated entry says what it waits on where it
sits. Nothing is wired up until its checkbox is ticked. Finished entries and
questions decided against are **deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [By scope](#by-scope)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below. The release unblocks the channels after it.

- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. deb/rpm/apk
      are live, signed, and have carried a second release to a subscriber in
      place. What's left is the tap half - the **Homebrew tap** entry.
- [ ] **A stability contract is written down** — shipped as
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break):
      the eighteen `common/flags`, every SETTINGS.md row,
      `$_HI_OVERLAY_FILES`, the install layout, `_HI_RELEASE`, the semver rule
      and how a toggle retires. **Ticks when** the tag commit turns
      SECURITY.md's _Supported versions_ prose into the version table it
      promises (the **Flip to stable** entry).

**The AUR is excluded on purpose** — v1 shouldn't wait on somebody else's
spam problem; see the **AUR** entry below.

## By scope

1. [ ] **tldr page** — _scope: one upstream pull request; outside this
       checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
       by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

2. [ ] **Retune the default package colors** — _scope: an eyeball pass; in-repo._
       Both `common/header.sh` color tables now order `_HI_YES`/`_HI_NO`
       intensity-major (normal, normal, bright, bright per priority 0-3)
       instead of the old hue-major order, which zigzagged - priority 1
       rendered louder than priority 2. `hi --packages-preview` renders the
       full legend with real examples, which is the tool to judge it with.
       **Ticks when:** the preview has been read on both a light and a dark
       terminal and holds up - a missing favorite (priority 3) the loudest
       thing in the check, installed trivia the quietest.

3. [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
       real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
       `Formula/` dir), add a fine-grained
       PAT (contents + PRs write) as `HOMEBREW_TAP_TOKEN`, re-run the
       `brew install`/`test`/`audit` gate on an actual Mac (`/opt/homebrew`,
       not the Linuxbrew prefix used so far). **Ticks when:**
       `brew install ivy/tap/say-hi` works, from a release
       `publish-external.yml`'s `tap` job (dispatched by hand against that
       tag) opened a PR for.

4. [ ] **AUR** — _scope: nothing until registration reopens; then an
       account, a key, and one manual first push; outside this checkout._
       Registration is closed to new accounts (spam), and
       `publish-external.yml`'s `aur` job stays written and unexercised
       until it reopens. **When it reopens:** register; generate an ed25519
       key, add the private half as the `AUR_SSH_KEY` repo secret; the first
       push per package is manual (namcap gate against the published
       source, then only `PKGBUILD` + `.SRCINFO`), and dispatching
       `publish-external.yml` handles the versioned package after.
       **Ticks when:** both packages are live on the AUR and a dispatch has
       kept `say-hi` current for one real release.
