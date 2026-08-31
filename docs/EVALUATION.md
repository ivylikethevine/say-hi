# Pre-1.0 evaluation

A point-in-time gap analysis (2026-08-30): what a Linux user — a developer, a
homelab maintainer, a hobbyist — would want from say-hi before a v1.0.0 tag,
ranked by how hard each gap bites. It complements [ROADMAP.md](ROADMAP.md)
rather than duplicating it: the roadmap is queued work sorted by effort; this
page is findings sorted by user impact, and where the roadmap already owns an
item this page links to it and moves on.

Conventions follow the roadmap's: nothing is fixed until its checkbox is
ticked, and a fixed entry is **deleted** — git history is the ledger. When
every checkbox here is gone, this file goes with them.

## Contents

- [The verdict](#the-verdict)
- [What already clears the bar](#what-already-clears-the-bar)
- [Tier 1 — will bite the named audience](#tier-1--will-bite-the-named-audience)
- [Tier 2 — release process, already owned by the roadmap](#tier-2--release-process-already-owned-by-the-roadmap)
- [Tier 3 — polish and hygiene](#tier-3--polish-and-hygiene)
- [Decisions already made, acknowledged here](#decisions-already-made-acknowledged-here)

## The verdict

The product is feature-complete and unusually polished for a pre-1.0 shell
project. Every real gap found is release-process or upgrade-story, not code —
and the roadmap already names most of the process half. The single
highest-value action on any list is the roadmap's
[release candidate before the tag](ROADMAP.md#quick-wins): zero `v*` tags have
ever been cut, so the whole `release.yml` chain (`bump.sh` → manifests PR →
tap PR → `brew audit`) has never executed end to end.

## What already clears the bar

Named so the evaluation is fair, and so nobody "fixes" one of these sideways:

- a real man page ([hi.1](hi.1)), drift-checked against `common/flags`
- completions in bash, zsh and fish off one data source (`common/targets.sh`)
- `hi --doctor [--json]` for bug reports; error messages that name the missing
  thing and the box it is missing from
- marker-based install/uninstall that repairs itself and leaves user files
  alone; config in `~/.config/say-hi/` that survives upgrades
- MIT license at the root; a genuine threat model
  ([SECURITY.md](SECURITY.md)); no `curl | bash`, no telemetry, no network
  calls of hi's own
- reproducible, minisign-signed, provenance-attested deb/rpm/apk, with CI
  proving byte-identical rebuilds
- zero `TODO`/`FIXME`/`XXX` markers in the tree; open questions live in
  [ROADMAP.md](ROADMAP.md) instead

## Tier 1 — will bite the named audience

Gaps the roadmap does not cover, in impact order.

### 1. The upgrade path for package users is a dead end

No apt/dnf/apk repository exists to subscribe to — a deliberate trade,
recorded in [PACKAGING.md](PACKAGING.md) ("No `apt upgrade` — the trade for
not maintaining a repository") — no AUR (registration closed), no tap yet. So
a `.deb`/`.rpm`/`.apk` user upgrades by manually re-downloading the next
release asset, and that is stated once, in a PACKAGING.md aside, and nowhere a
user installing from the README would see it. Worse, `hi --update` on a
packaged install prints `_HI_NO_GIT` (`common/paths.sh:91`): "if a package
manager installed say-hi, update it there" — pointing at a channel that cannot
update it.

- [ ] An **Upgrading** section in README's Installation/Usage: checkout →
      `hi --update`; package → re-download from the releases page (link the
      verification steps in
      [PACKAGING.md](PACKAGING.md#verifying-a-release-download)).
- [ ] Reword `_HI_NO_GIT` so the packaged arm points at the releases page
      instead of a package manager with no upgrade channel. Mind that
      `common/paths.sh` ships in the payload (check both size numbers) and
      that suites may pin the message text.
- [ ] A [ROADMAP.md](ROADMAP.md#not-scheduled) entry weighing a subscribable repo (OBS or a
      PPA) post-1.0, so the trade is revisited if people ask — PACKAGING.md
      already says "revisit OBS only if people ask"; give that sentence a
      place where decisions live.

### 2. No documented Arch path

Arch users are overrepresented in the homelab/hobbyist audience, the AUR is
externally blocked ([the roadmap tracks it](ROADMAP.md#blocked-until-someone-else-moves)),
and yet `packaging/aur/say-hi/PKGBUILD` exists and builds. The interim path is
one command and nobody is told about it.

- [ ] Document `makepkg -si` from `packaging/aur/say-hi/` (in README's install
      section or PACKAGING.md, linked from README) as the Arch path until the
      AUR opens. Note the caveat that applies until a release exists: the
      versioned PKGBUILD points at a release tarball, so pre-release the
      `-git` package (`packaging/aur/say-hi-git/`) is the one that builds.

### 3. A dropped connection loses the session, silently

The tree is deleted on exit by design, so a Wi-Fi blip or a laptop lid ends
the session with no way back in. Persistent sessions are deliberately deferred
past 1.0 ([ROADMAP.md](ROADMAP.md#not-scheduled) —
a sound call), and mosh cannot be the transport
([ALTERNATIVES.md](ALTERNATIVES.md#adjacent-tools-and-how-they-compose)
documents why). What is missing is one sentence of expectation-setting where a
user would look before being surprised.

- [ ] One line in README (or SETTINGS.md's _How it works_): a dropped
      connection ends the session and cleans up; run under `tmux`/`screen` on
      the client if you need to survive drops; persistent sessions are future
      work (link the ROADMAP.md entry).

## Tier 2 — release process, already owned by the roadmap

Nothing to add beyond endorsement — the
[v1.0.0 gate](ROADMAP.md#what-v100-means) is the right list, and every item
was re-confirmed by this evaluation as still open: no release under branch
protection, no channel published by hand, no `docs/STABILITY.md`, SECURITY.md's
_Supported versions_ still a placeholder, the EXPERIMENTAL banner unflipped,
required status checks unset, no tap repo or token, tldr PR unsent. Of these,
the **stability contract** is the one a user feels directly: it is what makes
"1.0" mean something for the eighteen flags and ninety-odd settings they will
build muscle memory and dotfiles around. The **rc tag** is the one that
de-risks everything else.

## Tier 3 — polish and hygiene

First-impression and diligence items; none blocks a user, all are cheap.

- [ ] `dist/staging/` is committed build output (`etc/profile.d/say-hi.sh`);
      remove it and ignore `dist/`.
- [ ] `.claude/RESUME.md` is a committed agent-session checkpoint; remove or
      ignore.
- [ ] `tests/coverage.sh` (kcov) and `tests/coverage_v2.sh` (bashcov) are two
      implementations of one undecided decision; decide, or record in
      TESTING.md that both stay and why.
- [ ] No `CODE_OF_CONDUCT.md` anywhere. GitHub surfaces CONTRIBUTING and
      SECURITY from `docs/`, but a code of conduct only from the root,
      `.github/`, or `docs/` — it is absent entirely, and the community-health
      checklist (and Discussions, once enabled) will point at the hole.
- [ ] A one-time security pass over the remote-script assembly before
      STABILITY.md makes promises: the `HIBOOT:` path is validated (absolute
      plus a charset allowlist) before interpolation, but `$remote_root` —
      also target-supplied (`hi.sh:742-756`) — is interpolated unvalidated
      into the script sent back to that same target. No privilege is gained
      (the target attacks only itself), but symmetry costs one `case` guard,
      or a "reviewed, accepted" note in SECURITY.md costs one sentence.
      `/security-review` over `_say_hi`'s assembly is the cheap version.
- [ ] `hi --test` on a packaged install prints `_HI_NO_CHECKOUT`
      (`common/paths.sh:89`): "needs the full say-hi checkout - not available
      in a hi session". Not shipping tests is the right call, but the message
      only names the session case — on a packaged install it dead-ends without
      saying where a checkout comes from. One clause fixes it.

## Decisions already made, acknowledged here

Weighed, answered, and documented — listed so nobody re-litigates them from
this page: no nix packaging ([SUPPORT.md](SUPPORT.md)), no mosh
transport ([ALTERNATIVES.md](ALTERNATIVES.md#adjacent-tools-and-how-they-compose)),
no shipping a shell the target lacks (xxh's niche,
[ALTERNATIVES.md](ALTERNATIVES.md#xxh--the-one-that-solves-a-harder-problem)),
no `CHANGELOG.md` while generated release notes suffice
([ROADMAP.md](ROADMAP.md#quick-wins)), persistent sessions after 1.0
([ROADMAP.md](ROADMAP.md#not-scheduled)), and the
AUR excluded from the v1 gate ([ROADMAP.md](ROADMAP.md#what-v100-means)).
