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

- [x] **A release has gone out** and proved the whole path — tag, gate,
      signed sums, packages, source tarball, the body's notes and checklist.
      `v0.1.0` through `v0.1.2` have each walked it.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap,
      per [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. deb/rpm/apk
      are live - the **Package repository on the Pages site** entry is what's
      left of that half. The tap half is the **Homebrew tap** entry.
- [ ] **A stability contract is written down** — shipped as
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break):
      the eighteen `common/flags`, every SETTINGS.md row,
      `$_HI_OVERLAY_FILES`, the install layout, `_HI_RELEASE`, the semver rule
      and how a toggle retires. **Ticks when** the tag commit turns
      SECURITY.md's _Supported versions_ prose into the version table it
      promises (the **Flip to stable** entry).

- [ ] **A subscribable package repository is live**, so a `.deb`/`.rpm`/`.apk`
      user gets the next release through their package manager. The URLs are
      live and signed; what's left is the **Package repository on the Pages
      site** entry's own remaining half — a release landing on a subscriber.

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
   - **A fork exists but isn't a confirmed fix:** `kjanat/actionlint` (an
     actively maintained fork, currently `v1.14.0` on its own versioning)
     adds policy checks, composite-step validation and shell completion on
     top of upstream — but nothing in its README documents `$/...` support
     either, so swapping the pin is not yet a known way out of this same
     deadlock. Worth re-checking before assuming upstream is the only path.
   - **Ticks when:** zizmor is back on its latest release and
     `check_tool_versions.sh` reports every pin current.

2. [ ] **tldr page** — _scope: one upstream pull request; outside this
       checkout._ CLI surface is frozen (eighteen flags, CI-enforced both ways
       by `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`) and the
       draft (`docs/tldr.md`) matches upstream style. **Do:** open the PR
       against tldr-pages. **Ticks when:** merged upstream.

3. [ ] **Retune the default package colors** — _scope: two color tables and
       an eyeball pass; in-repo._ The check colors every line from
       `_HI_YES`/`_HI_NO` in `common/header.sh` — one installed and one
       missing color per priority 0-3 — and `hi --packages-preview` renders
       the full legend with real examples, which is the tool to judge a
       candidate set with. The ramp should read monotonic in both
       directions: a missing favorite (priority 3) the loudest thing in the
       check, installed trivia the quietest, every pair legible on light
       and dark terminals. **Ticks when:** the preview reads that way on
       both backgrounds and any suite pinning the tables moved with them.

4. [ ] **Collapse the CPU cell's redundant number** — _scope: one
       `header_row` call reordered, one conditional; in-repo._
       `system_info()`'s CPU cell always prints two clocks,
       `${base_mhz}/${boost_mhz} GHz` via `_hi_ghz()`, even when the boost
       probe found nothing (`boost_mhz` is never probed for at all on
       Windows or macOS, so those render `CPU: 2.8/? GHz`) or when the two
       are equal — no real turbo range to show. It also sits two cells after
       `Cores:`, separated by `RAM:`, rather than beside it. Two changes:
       fold to a single `CPU: <n> GHz` when `boost_mhz` is empty or matches
       `base_mhz`, and move the `CPU:` cell next to `Cores:` in the
       `header_row` call. **Ticks when:** a single-clock host reads
       `CPU: <n> GHz`, a real base/boost pair still reads
       `<base>/<boost> GHz`, the cell sits beside `Cores:`, and
       `tests/common/header_test.sh`'s `test_system_info_cpu_cell_is_ghz`
       covers both shapes.

5. [ ] **Consistent container/backend display** — _scope: `identity()`'s
       three backend cells; in-repo._ Docker and podman are merged into one
       `Containers: <n>` cell — `_hi_probe_launch`'s `container_bin` picks
       docker over podman when both are present, so the label never says
       which backend actually answered — with a fallback string,
       `"No docker/podman :("`, when neither is found. Nomad's `Jobs: <n>`
       and Kube's `Pods: <n>` cells instead hide entirely at a zero count,
       with no equivalent "not found" text, so a reachable-but-idle nomad or
       kube and an absent one render identically. Pick one rule — always
       show with a per-backend fallback, or hide at zero consistently across
       all three — and a shared label convention. **Ticks when:** all three
       cells follow the same show/hide rule and fallback wording, and
       `tests/common/header_test.sh` covers the zero and not-found case for
       each backend.

6. [ ] **Give uptime its own header row** — _scope: one row function, one
       `_HI_HEADER_ORDER` word, one toggle; in-repo._ `up` renders as the
       last cell of `system_info`'s row today, sharing space with
       arch/os/cores/ram/cpu — already the widest row in the header.
       `_hi_header_row()`'s dispatch already covers exactly this shape for
       `timestamp`/`sysinfo`/`identity`/`check`; a new `uptime` word behind a
       new `_HI_HEADER_UPTIME` toggle (default `1`, following
       `_HI_HEADER_SYSINFO`'s pattern) is the same mechanism, not a new one.
       Needs a drift-checked SETTINGS.md row and a `hi --configure` prompt
       roster entry alongside the existing `_HI_HEADER_ORDER` one; `header.sh`
       ships in the ssh payload, so `bench_payload_size` and the README badge
       bound the new function. **Ticks when:** uptime renders in its own row
       by default, `_HI_HEADER_ORDER` can still reposition or omit it, and
       `tests/common/header_test.sh`'s uptime and row-order cases cover it.

7. [ ] **Wrap the header at `_HI_MAX_WIDTH`** — _scope: one wrap loop,
       shared by three rows; in-repo._ `full_check()` already wraps its
       cells at `_HI_MAX_WIDTH` (`80` by default), starting a new line
       whenever the next item would overflow it; `header_row()` — what
       `timestamp`, `system_info` and `identity` all build their line
       through — has no such awareness and just concatenates cells into one
       `printf`, so a narrow terminal line-wraps wherever the shell happens
       to break mid-cell. Extend `full_check`'s width-tracking loop (or
       factor it out) so those three rows wrap between cells instead of
       within one; `header.sh` ships in the ssh payload, so
       `bench_payload_size` and the README badge bound the shared helper.
       **Ticks when:** none of the four rows breaks mid-cell at a narrow
       `_HI_MAX_WIDTH` in `tests/common/header_test.sh`, and the default
       width still renders one line per row on a normal terminal.

8. [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, one gate re-run on a
       real Mac; outside this checkout._ Create `homebrew-tap` (plain repo,
       `Formula/` dir), add a fine-grained
       PAT (contents + PRs write) as `HOMEBREW_TAP_TOKEN`, re-run the
       `brew install`/`test`/`audit` gate on an actual Mac (`/opt/homebrew`,
       not the Linuxbrew prefix used so far). **Ticks when:**
       `brew install ivy/tap/say-hi` works, from a release
       `publish-external.yml`'s `tap` job (dispatched by hand against that
       tag) opened a PR for.

9. [ ] **Package repository on the Pages site** — _scope: one observation;
       outside this checkout._ Both halves shipped: `packaging/mkrepo.sh`
       builds the apt, rpm and apk repositories out of `mkpkg.sh`'s packages,
       `release.yml` signs the rpm in `build`, attaches
       `package-repo.tar.gz` in `publish` and redeploys `pages.yml` so the
       release does not wait for an unrelated push to main to carry it,
       packaging-smoke builds one per PR and `tests/packaging/repo_test.sh`
       installs from one as all three clients; `GPG_SIGNING_KEY` is set in
       the release environment and `packaging/gpg/say-hi.asc` is committed
       ([PACKAGING.md](PACKAGING.md#package-repository)). Live and verified:
       `say-hi.repo`, `apt/dists/stable/{Release,InRelease}` (clearsigned),
       `apt/dists/stable/main/binary-amd64/Packages`, `rpm/repodata/repomd.xml`
       and `apk/x86_64/APKINDEX.tar.gz` all resolve, signed with the
       committed key, at `https://ivylikethevine.github.io/say-hi/{apt,rpm,apk}`.
       **Ticks when:** a second release is seen landing on a subscriber -
       `apt`/`dnf`/`apk upgrade` picking it up in place, not just a fresh
       install.

10. [ ] **Outside the repo, once a release exists** — _scope: a badge, a
        toggle and two checks; mostly outside this checkout._ Four small
        pieces: a Repology badge (in README's badge block already, rendering
        empty; ticks once it carries a real version, after deb/rpm/apk, the
        tap and the AUR do); GitHub Discussions, linked from
        `ISSUE_TEMPLATE/config.yml`; a check that `ubi`/`mise use ubi:` finds
        `hi.sh` in the release tarball, plus a PACKAGING.md line if it needs
        an `--exe` hint; and `actions/attest-sbom` beside the provenance step.

11. [ ] **AUR** — _scope: nothing until registration reopens; then an
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
