# Tooling & practices roadmap

What is left to do on say-hi. [What v1.0.0 means](#what-v100-means) is the gate
the tag waits on; everything below it is sorted into four tiers by **how hard
the work is**, so the file answers "what should I pick up next" rather than
"where does this work happen":

- **[Quick wins](#quick-wins)** — a single run, click, upstream pull request or
  one-line decision. Nothing here needs a design.
- **[Moderate](#moderate)** — a bounded feature or fix with a precedent already
  in the tree to copy, plus the tests that pin it.
- **[Large](#large)** — reshapes a contract, a promise or a path convention
  across many files, or is not yet scoped enough to start.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.

Each entry still opens with its **scope** in italics, and the scope still says
what the work _is_ rather than how long it takes: "one CI run" and "a backend
across seven files" are the useful distinction, and a guessed number of days is
not. The tier heading is the difficulty; the scope is the detail. Each scope
closes by naming where the work happens — _in-repo_ for what can be written and
finished in this checkout, _outside this checkout_ for what is gated on a
machine, an account, a key or a click that no file here can perform.

Ordering inside a tier is dependency order first, then ascending scope. That
matters most in [Quick wins](#quick-wins), where the first entry blocks three
others spread across three tiers.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Large](#large)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)

## What v1.0.0 means

README carries EXPERIMENTAL UNTIL v1.0.0 and the tiers below are sorted by
difficulty rather than against it, so this is the list that says what actually
gates the tag: what has to be true before it, each line naming the entry or file
that satisfies it. It is a **gate, not a wish list** — anything that would
merely be nice by v1 stays an ordinary unticked entry below rather than padding
this, and the one piece of product work left (_[persistent
sessions](#large)_) is explicitly deferred past the tag rather than held in
front of it. The point is a list short enough to finish — and what
is left of it is no longer a list but a single chain: the release below unblocks
the channels after it, and nothing else gates the tag.

- [ ] **A release has gone out under branch protection**, with the manifest
      step green — the [Get a release out under branch
      protection](#quick-wins) entry. The criterion below it cannot start until
      this one lands: `tap` and `aur` are `needs: publish`, and `publish` is the
      job the rule currently refuses.
- [ ] **Every publishable channel has been published once by hand**, before the
      automation is trusted with it: deb/rpm/apk and the Homebrew tap, per
      [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap half is
      the [Homebrew tap](#moderate) entry.

**The AUR is excluded on purpose.** Registration is closed to new accounts
because of spam, so there is nothing to do and no date to do it by; v1 should
not wait on somebody else's spam problem. Its entry stays tracked under
[Blocked until someone else moves](#blocked-until-someone-else-moves) and ticks
whenever it reopens.

## Quick wins

A run, a click, an upstream pull request, or a decision written down. None of
these needs a design first, and the first one gates more of this file than
anything else in it: [Say what changed in a release](#quick-wins) below,
[Homebrew tap](#moderate), and [AUR](#blocked-until-someone-else-moves) are all
waiting on it.

- [ ] **Get a release out under branch protection** — _scope: one real release,
      plus one repository setting to confirm first; outside this checkout._
      _The rule is on:_ `main` requires a pull request and refuses a direct
      push, which closes Scorecard's highest-severity finding. What has not
      happened is a release under it, and until one does **both release-channel
      entries below are blocked behind this one**: `tap` and `aur` are
      `needs: publish`.

  - **The code half has shipped.** `publish` no longer pushes to `main`: its
    credential-keeping checkout writes the regenerated `PKGBUILD`, `.SRCINFO`
    and `say-hi.rb` onto a `manifests-<tag>` branch and opens a pull request,
    on the `tap` job's precedent, with `pull-requests: write` on the job to do
    it. No workflow in the tree pushes to `main` any more. The release does not
    wait on that merge either - `tap` and `aur` read the manifests out of the
    `packages` artifact, not out of `main`.
  - **Confirm one setting before the first tag.** A workflow can only open that
    pull request if _Settings → Actions → General → Allow GitHub Actions to
    create and approve pull requests_ is on. With it off, `gh pr create` fails
    with "GitHub Actions is not permitted to create or approve pull requests" -
    at the last step of the release, with the packages already published, which
    is exactly the failure the PR conversion was meant to remove.
  - **The required checks are still unset.** Only the pull-request requirement
    is configured. When they go on, per the note on the markdownlint job, do
    not make the advisory ones required — `markdownlint`, `hadolint`, lychee
    and trivy are all designed to be ignorable. `e2e (macOS)` and
    `e2e (Windows)` are now green on push and are reasonable candidates.
  - **Ticks when:** a release has gone out under the rule, with the manifest
    pull request opened rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ say-hi ships to deb, rpm, apk and
      Homebrew, and nothing told a packaged user what moved between two
      versions. `git log` is not something a `brew upgrade` reaches, which is
      exactly why deleting finished entries from this file — right for a to-do
      list — left that gap: the ledger has to be published, not merely kept.

  - **What shipped.** `release.yml`'s publish job now composes the release body
    out of both halves. GitHub's `releases/generate-notes` endpoint supplies the
    top — the PR titles merged since the last tag, derived rather than
    hand-kept, so it cannot go stale — and the _verification checklist_ this
    entry once wrongly claimed was already there is appended below it, reading
    its minisign public key straight out of
    [PACKAGING.md](PACKAGING.md#verifying-a-release-download) so the key exists
    once in the tree.
  - **Why it is composed rather than two flags.** `gh` appends generated notes
    _after_ `--notes`, which would bury what changed under how to check it.
  - **A `CHANGELOG.md` is still not open**, and should only be opened if the
    generated notes turn out not to be enough — the same test as before.
  - **Ticks when:** a release has gone out whose body names what changed as well
    as how to check it, with nobody hand-writing the list. Blocked behind
    [Get a release out under branch protection](#quick-wins), like everything
    else that needs a real tag.

- [ ] **Get a demo render onto the site** — _scope: one repository variable,
      then one `publish` run; outside this checkout._ Both halves of the
      autogeneration are in: `demos.yml`'s `publish` job renders every tape but
      `demo`, `pages.yml` lays the result over the site, the six GIFs are out
      of the tree, and README and [CONFIGURATION.md](CONFIGURATION.md) link
      them at their published URLs. `docs/demos/demo.gif` stays committed on
      purpose - it is the hand-rendered one, and `.githooks/demo_staleness.sh`
      is what says when it has gone stale.

  - **Everything this entry used to say about merge order is out of date, and
    the situation it warned about has already happened.** The deletion and the
    URL repoint are on `main`, not only on `dev` - both branches carry
    `demo.gif` and nothing else under `docs/demos/`, and both link the other
    seven at `ivylikethevine.github.io`. So there is no window to keep at zero
    by dispatching before a merge: **all seven of those URLs 404 today**, six
    of them from the front page. The site itself is up and `demo.gif` serves,
    which is what narrows it to the rendered ones.
  - **`publish` is not waiting for a run. It has had four and failed all
    four.** Three pushes to `main` and the weekly cron (most recently
    2026-08-24), every one red at _Render every tape but demo_. `pages.yml`
    serves the newest **successful** run's `demo-gifs` artifact, so there has
    never been one to serve. The PR-side `render` job is green every time and
    says nothing about this: it is a hosted runner rendering exactly
    `color_preview`, which is the one tape that needs no backend.
  - **One repository variable is the whole cause.** `publish` is
    `runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}`, and `RUNNER_LABEL`
    is unset - the failing runs report a `runner_name` of "GitHub Actions
    …" and skip the `runner.environment != 'github-hosted'` step, which is
    conclusive. So the job falls back to a hosted runner, where its own comment
    already says only one of the seven tapes can render; `--require-run` then
    turns the other six into the failure it is meant to be. The same fallback
    appears in nine other workflows and is right in all of them - coverage,
    link-check, codeql, scorecard and the rest do their job on a hosted runner.
    `publish` is the one place where it is a guaranteed failure rather than a
    degradation.
  - **The code half now fails legibly, which is all this checkout can do about
    it.** A preflight step fails `publish` immediately, before the first apt
    call, naming `RUNNER_LABEL` and where to set it - rather than five minutes
    of installs and a death inside vhs that no log line explains. It fails
    rather than skips on purpose: `pages.yml` reads the last _successful_ run,
    so a job that quietly stood down would leave the site serving nothing while
    reporting green.
  - **Do, in order:** set `RUNNER_LABEL` (Settings → Secrets and variables →
    Actions → Variables) to the self-hosted box's label, then dispatch
    `demos.yml`. It never runs on a pull request - push to `main`, the weekly
    cron, or a manual dispatch - so a dispatch is the fast path.
  - **Watch for the renderer's own dependencies on that first green.** A tape
    that opens `Set Shell zsh` wants that shell on the machine doing the
    recording, not on the target, so `publish` installs zsh, fish and nomad the
    way `ci.yml`'s backends job does; docker, podman, kind and kubectl are what
    the box is expected to already carry. That step has never run on the real
    machine, because nothing has reached it.
  - **Ticks when:** a `publish` run has been green end to end and the seven
    published URLs actually serve an image — README's six, plus the
    `color_preview` one that [CONFIGURATION.md](CONFIGURATION.md) is the only
    link to. Seven tapes render; six GIFs left the tree, because `complete` was
    never committed in the first place.

- [ ] **Confirm the tar padding fix on the macOS job** — _scope: one CI run to
      read; the code half has shipped; in-repo._ `_hi_payload_tar` and
      `_hi_overlay_tar` let tar do the compressing (`tar czf -`), and the two
      userlands pad different things: GNU tar rounds the _uncompressed_ archive
      up to the 10240-byte blocking factor and then gzips it, so the NULs
      compress away to about thirty bytes, while bsdtar - macOS's
      `/usr/bin/tar` - pads the _compressed stream_. Every payload a BSD client
      built was rounded up to a whole multiple of 10240.

  - **What shipped.** A `_hi_tar_gz` helper in `hi.sh` compresses in a second
    process (`tar cf - … | gzip -n`), checking both halves of the pipeline
    through `${PIPESTATUS[@]}` - `hi.sh` turns `pipefail` back off for
    interactive sourcing, so a failing tar would otherwise hide behind a
    successful gzip and ship a truncated payload - and degrading to `tar czf -`
    where the client has no `gzip`. All three call sites go through it:
    `_hi_overlay_tar`, and `_hi_payload_tar`'s `_HI_KEEP_COMMENTS` and staged
    arms.
  - **It was reproduced against real bsdtar rather than inferred.** libarchive
    is what macOS's tar is built on, so shimming `tar` to `bsdtar` reproduces
    that client without a Mac. On this tree, before against after: the payload
    **40960 → 32286 B**, so a stock macOS session shipped 27% more than it
    needed; a one-file overlay **10240 → 140 B**. Four cases in
    `tests/hi/payload_test.sh` pin it, and the two that shim bsdtar are the ones
    that fail against the old code - the GNU-tar pair passes either way, which
    is exactly how this survived unnoticed.
  - **The OSC 52 delta now agrees between the userlands.** Under `tar czf -`,
    `_HI_DISABLE_OSC52=1` trimmed 693 bytes under GNU tar and **0** under
    bsdtar, because the trim never crossed a block boundary - which is what made
    `doctor_payload_diff`'s _Payload diff shown when a toggle trims the wire_
    red on the macOS job and green everywhere else. Split, the two agree to
    within 52 bytes on the full wire figure.
  - **The 128-byte floor needs no change, and this entry's note saying
    otherwise was wrong.** It claimed measured jitter was zero across five runs.
    It is not: six runs 1.1s apart give 9 bytes under GNU tar and 8 under
    bsdtar, because the staged tree's stripped files carry each run's own mtime.
    That is the "few bytes to a couple dozen" `scripts/doctor.sh`'s comment
    already describes, so the comment stands as written - and the jitter, like
    the 52-byte spread between userlands, sits far under the floor.
  - **Ticks when:** `doctor`'s payload-diff case is green on the macOS job.
    That is the only half left, and it needs a macOS runner - which is why this
    is now a run to read rather than work to do.

- [ ] **Make the Windows client job green** — _scope: one dispatch to read,
      plus two repository steps once it is; the fixture half has shipped;
      in-repo._ `.github/workflows/windows-client.yml` has been dispatched
      twice, most recently 2026-08-22, and was red both times:
      **37 failures across 8 suites, none of them a portability bug in
      `hi`.** Every one traced to two facts about Git Bash - it cannot create
      symbolic links (`ln -s` wants Developer Mode or administrator) and it has
      no POSIX execute bit (MSYS answers `access(X_OK)` from a file's magic or
      extension unless the mount carries `acl`). The question this entry used
      to ask was whether the affected cases should stand down yellow or the job
      stay red-but-explained.

  - **The decision was neither: most of them were fixture bugs, and they are
    fixed.** Only eleven cases actually need a real symlink; the rest were the
    fixtures failing to say what they meant, and every fix below is worth
    having on any platform rather than being a Windows concession.
    - `_hi_real_path` (`tests/lib/fixtures.sh`) builds a toolbox of symlinks
      and never checked `ln`'s result - it was the tail of an `&&` list, so a
      failure neither aborted nor reported, and the `[ ! -d ]` build-once guard
      then cached the **empty** directory forever. A caller splices that into
      `$PATH` and has no `sh`, `awk` or `sed` at all, which is why `targets`'
      three sweep cases, `packages_preview`'s two and most of `doctor`'s five
      failed in ways that looked nothing like symlinks. It now checks, and
      falls back to a `#!/bin/sh` exec wrapper - the shape `_hi_fake_path`
      next door already relies on, and the one MSYS's magic-based
      `access(X_OK)` accepts where an empty file's `chmod +x` does not.
    - `_hi_probe_home` (`tests/hi/remote_test.sh`) made its launcher with
      `: >hi.sh` - an empty file, so `chmod +x` does not stick on MSYS and
      `_hi_remote_root_probe`'s `[ -x … ]` correctly answered "nothing
      installed" for all fourteen `hi_remote` cases. The probe was right; the
      fixture could not say what it meant. It writes a shebang now, through a
      `_hi_probe_tree` helper that also absorbed the copy of itself further
      down the suite.
    - `packaging`'s two checksum cases read `awk '{ print $2 }'` over
      `SHA256SUMS` and saw `*name`, because `sha256sum` opens binary by default
      on Windows. `SHA256SUMS` is written by Linux CI and `sha256sum -c` reads
      both spellings, so the assertion was the brittle half: `_HI_SUMS_NAMES`
      strips the `*`.
    - Two more fixtures leaned on a symlink for no reason and stopped.
      `_hi_bsdtar_shim` (`tests/hi/payload_test.sh`) takes `_hi_real_path`'s
      fallback, since it is the same "a symlink to a binary on `$PATH`" shape;
      `_hi_subcmd_home` (`tests/hi/parse_test.sh`) now copies the tree into its
      fake target instead of linking it, which is also what a real target has -
      it unpacks the payload tar, so what lands there are regular files.
  - **The eleven that genuinely need a symlink stand down**, on the backend
    suites' doctrine, behind a probe rather than an OS sniff: `_hi_capable`
    (`tests/lib/fixtures.sh`) answers `symlink` by making one and testing
    `[ -L ]`, so a filesystem that silently _copies_ reads as "no" too, and
    `_hi_check_capable` / `_hi_par_check_capable` are `_hi_check_requires`'
    twins for a facility rather than a binary. Seven cases in `install`, two in
    `packaging`, one in `install_location` and `hi_payload`'s Stow case use
    it, all of them cases where a link is the subject rather than the
    scaffolding. The twelfth stand-down is `test_lib`'s pty case, which was gated on
    `command -v python3` - Windows _has_ python3 and lacks the Unix-only `pty`
    module, so `$_HI_PTY_FORCED` is now filled from an `import pty, tty` probe
    and the case asks `_hi_check_capable pty`.
  - **All of it was proven without a Windows box.** A `ln` shim that fails on
    `-s` and passes hard links through _is_ Git Bash without Developer Mode,
    and a `python3` that exits non-zero on `import pty` is its interpreter.
    Under the shim, the job's own invocation (`--group fast --skip
    shellcheck`) is **green across all 25 suites with eleven yellow skips**;
    without it, green with none. The second half is the one that matters: a guard that
    skipped on Linux too would be hiding coverage rather than reporting a
    platform.
  - **What is left is a run and two settings.** Dispatch
    `windows-client.yml`; any failure now is new information rather than one of
    these classes. Two things to read rather than assume. The skip count
    should be twelve (eleven symlink, one pty) on top of the 45 zsh/fish ones.
    And `packaging`'s _staged_launcher shims a misnamed checkout_ should
    **skip**, not fail: it needs a symlink to a _directory_, it is guarded now,
    and the original run counted it green, so a failure there would say the
    guard is in the wrong place.
  - **Unchanged from before the run:** it runs `--group fast --skip
shellcheck`, because `.github/actions/setup-tool` resolves linux/darwin
    asset slugs and `run_shellcheck` exits 1 rather than standing down when
    shellcheck is missing. There is no zsh or fish on the runner either, so 45
    cases skip yellow before any of the above. Nothing is blocked on this
    either way: a Windows _client_ is deliberately not a v1.0.0 criterion,
    because a Windows client is not what "stable" promises. `windows-e2e.yml`
    covers the target side, and that is the half the tag rests on.
  - **Ticks when:** the job is green once, `ci.yml` calls it on push, and
    [SUPPORTED.md](SUPPORTED.md#the-targets-os)'s Windows row reads ✅ for the
    client half as well as the target half.

- [ ] **Decide whether to keep the Scorecard badge** — _scope: a judgement call
      and one README line either way, with nothing to judge before 2026-08-25;
      outside this checkout._ `scorecard.yml` runs weekly with
      `publish_results: true` and `README.md` carries the badge, but **no score
      has been published yet**: `api.scorecard.dev` and
      `api.securityscorecards.dev` both 404 for this repo, and the badge
      renders `openssf scorecard: invalid repo path` — on `main` as much as
      here. The cause is benign. `publish_results` only takes effect on a
      _scheduled_ run against the default branch, the cron is `41 7 * * 2`, and
      the schedule-only trigger landed on `main` on Wed 2026-08-19 — so the
      first run is Tue 2026-08-25 and there has not been one. If the badge is
      still an error after that date, a run fired and failed rather than never
      having fired, and the Actions tab is the only place that tells those two
      apart.

  - **Until then the README shows an error rather than a number.** Leave it:
    re-adding the line afterwards is a second commit spent on a few days of
    cosmetic blemish, on a repo whose first heading already says EXPERIMENTAL.
    Pull it only if that reads worse in practice than it does written down.
  - **The question the number has to answer** is whether showing it helps. Two
    checks a solo maintainer cannot move — Code-Review and CI-Tests — dominate
    it, so it reads partly as a verdict on the project's headcount rather than
    on its engineering, sitting next to badges that measure something real.
  - **CII-Best-Practices used to be on that list and is not.** It reads for a
    contribution guide among other things, so it was movable by writing one —
    and `docs/CONTRIBUTING.md` has since shipped. That is one unmovable check
    fewer than when this entry was written, which is the other reason to judge
    the first real report rather than guess at it.
  - **The rest of the report is settled and needs nothing.** SAST counts
    `codeql.yml`'s `actions` pack over the workflows (worth having on its own
    merits, and a poor reason to believe the resulting number, since the
    product is still bash and still unread by it); Fuzzing has no obvious
    target in a shell tree; everything else already passes.
  - **Ticks when:** the badge either stays, with a sentence here saying why the
    number is worth showing, or comes back out of the README.

- [ ] **tldr page** — _scope: one upstream pull request; the gate it waited on
      has lifted; outside this checkout._ Seven example lines reach everyone
      who types `tldr hi` before anyone reads a man page. Upstream has its own
      style guide and review, so this is a submission, not a file here; the
      draft is at `docs/tldr.md`.

  - **The CLI surface is frozen, which is what this was waiting on.** All twelve
    flags agree across `hi.sh`'s `_HI_SUBCOMMANDS` table and case arms,
    `docs/hi.1`, and `common/targets.sh`'s completion roster — and the agreement
    is CI-enforced in both directions rather than read: `tests/hi/parse_test.sh`
    checks that every `--help` flag reaches the man page _and_ that the page
    groups them the way the roster does, while `tests/common/targets_test.sh`
    checks the roster against `--help` each way round. Examples that churn are
    worse than no page, and these can no longer churn quietly.
  - **The draft now reads like upstream's, which is the other thing review
    catches.** It was structurally right already - `# hi`, a `>` block ending
    in `More information:`, `{{placeholder}}` syntax, single-backtick command
    lines, seven examples against a cap of eight - and wrong in the small ways
    the style guide is explicit about: three lines over the 80-column cap,
    inline backticks inside two example descriptions where upstream wants plain
    prose, and a literal `...` in the last one. All fixed; the longest line is
    79 now. What is left is genuinely just the submission.
  - **Do:** open the PR against tldr-pages. The draft leans on three flags —
    `--doctor`, `--version` and `--configure` — all of them frozen.
  - **Ticks when:** it is merged upstream.

## Moderate

Bounded work with a precedent already in the tree to copy from, and a test or a
budget to satisfy on the way out. Nothing here is a research problem; each one
names the files it touches.

- [ ] **A job-started hook on the self-hosted runner** — _scope: a script and an
      env var on that machine, plus one commit here deleting fifteen copies;
      outside this checkout._ Fifteen jobs across ten workflows open with the
      same `Reclaim the workspace` step: a `sudo chown -R` of
      `$GITHUB_WORKSPACE`, guarded on `runner.environment != 'github-hosted'`,
      because that box's `_work` persists between jobs and one root-owned file
      from a container test makes the next checkout's cleanup throw
      (docs/PACKAGING.md has the full account). It cannot be factored into a
      composite action, since it has to run _before_ `actions/checkout` and
      `uses: ./.github/actions/...` needs the checkout that has not happened
      yet.

  - **Where it actually belongs:** `ACTIONS_RUNNER_HOOK_JOB_STARTED` on the
    runner itself — a script the runner executes before every job, which is
    exactly this step's scope. Setting it is a file and an env var on that
    machine, which is the half of this no file in the checkout can perform.
  - **Recount before deleting rather than trusting the number here.** It was
    thirteen across eight when this entry was written and is fifteen across ten
    now, because workflows keep arriving;
    `grep -rc 'Reclaim the workspace' .github/workflows/` is the whole check.
  - **Ticks when:** the hook is in place and every copy is deleted in one
    commit. Do both at once: the copies are harmless, but leaving them after
    the hook exists means two mechanisms for one problem.

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, and one gate re-run on a
      real Mac; outside this checkout._ Create the `homebrew-tap` repo (a plain
      GitHub repo with a `Formula/` directory), add a fine-grained PAT scoped
      to it (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then
      re-run the `brew install`/`test`/`audit` gate on an actual Mac (the keg
      lives under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

## Large

One is left, and it reshapes something the rest of the tree leans on rather
than adding to it: the footprint promise [SECURITY.md](SECURITY.md) makes. It
is deferred past v1.0.0 on purpose - it rewrites the sentence the tag is being
cut on. The Windows client job used to sit here as the second; the decision it
was waiting on has been made and its fixture half has shipped, so it is a run
to read now and lives in [Quick wins](#quick-wins).

- [ ] **Persistent sessions on a disposable target** — _**deferred until after
      v1.0.0.** Scope: the largest entry here. It changes cleanup semantics on
      both paths, needs a findable tree path and something to reap it, and
      rewrites SECURITY.md's footprint promise; in-repo._ Deferred because the
      thing it changes is the promise v1 is being tagged on: SECURITY.md says a
      machine you visited looks untouched, and every other entry left is a run
      or a click rather than a rewrite of that sentence. The plan below is the
      research, not queued work.

  A dropped connection currently loses the session outright: the
  tree is deleted when the session ends, so there is nothing to reconnect
  to. This entry is that changed — keep the tree across a dropped
  connection, reconnect into the same session later, and delete only on a
  definitive exit or after a configurable timeout. **Opt-in, not the
  default**: a bare `hi <target>` stays exactly as disposable as it is
  today — a named session is what asks for the tradeoff below, on the same
  "nothing changes for people who never asked" precedent every toggle in
  this project follows.

  - **The plan, in one line.** `hi --session <name> <target>` writes a
    deterministic tree instead of `mktemp`'s random one, `load.sh`'s cleanup
    trap becomes conditional on whether that session is still wanted, and
    reattachment rides whatever multiplexer the target already has -
    nothing new ships to provide one.
  - **What has to stop happening, carefully.** Cleanup has two independent
    paths — the bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s
    own on-exit hook — and `tests/targets/ssh_disconnect_test.sh` exists
    specifically to prove they fire on an _abrupt_ disconnect rather than only
    a clean exit. That is the current contract and it is deliberate, so this
    makes it conditional rather than weaker: the suite gains a second case
    (dropped **with** `--session` keeps the tree) beside the one it has
    (dropped **without** still reaps it).
  - **The tree has to be findable again, and only when asked for by name.**
    `mktemp -d -t $(_hi_whoami).hi.XXXXXX` (`hi.sh`) stays the default - a
    fresh random name every session, exactly as unfindable as it is meant to
    be for a one-off connection. `--session <name>` swaps that for a
    deterministic path scoped to the same user and target,
    `${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>` (mode 0700, same as
    today's tree - GLOSSARY: HI.33's derivation, not a new convention). A
    second `hi --session <name> <target>` finds it already there, skips
    re-copying the payload once its manifest matches, and reattaches instead
    of bootstrapping fresh. `<name>` is a plain token (alnum, `-`, `_`) so it
    can never walk the path outside `$TMPDIR` - the same shape a target name
    is already constrained to.
  - **Reaping it defaults to zero footprint, not a background process.** The
    default is reap-on-next-connect: a session tree older than
    `_HI_PERSIST_TIMEOUT` (documented in [CONFIGURATION.md](CONFIGURATION.md),
    unset means "keep indefinitely until an explicit `hi --session <name>
--end`") is deleted the moment the _next_ `hi` of any kind touches that
    target, not by anything running in the meantime - keeping "a machine you
    visited looks untouched" true in the stronger sense of leaving no process
    behind, at the cost of a stale tree sitting there if you never reconnect
    at all. A detached watchdog (`sh -c 'sleep N; rm -rf ...' &`, disowned) is
    the opt-in stronger guarantee for someone who wants the timeout enforced
    even if they never come back - a second flag, not the default, because a
    process left running on every persistent session is exactly the kind of
    footprint SECURITY.md currently promises against. Either way, SECURITY.md's
    _Footprint and cleanup_ section needs rewriting to describe the two modes
    rather than the one guarantee it states today.
  - **Keeping the shell alive rides what the target already has, nothing
    ships to provide it.** This keeps the _tree_ alive; the _shell_ needs a
    reattachable process, and hi ships no multiplexer config to lean on
    (`--tmux` and `misc/tmux.conf` were removed). The plan is the same ladder
    hi already uses for everything else it does not want to own two
    implementations of ([SUPPORTED.md](SUPPORTED.md), `_HI_SHELL_PREFERENCE`):
    detect what is already on the target and drive it, in order `tmux` →
    `screen` → `dtach` (the last needs nothing but a bare `dtach -A
<socket> <shell>` - no config file to ship, unlike tmux). `--session`
    wraps the session in whichever of the three is found first,
    `tmux new-session -A -s hi-<name>` or the equivalent. A target with **none**
    of the three declines persistence outright with a clear message at
    connect time - `--session` on that target behaves like today's plain `hi`,
    rather than silently pretending the reattach half of the promise held.
  - **Ticks when:** `hi --session <name> <target>` survives a dropped
    connection and reattaches on the next `hi --session <name> <target>`, a
    bare `hi <target>` is unchanged, the timeout and its watchdog opt-in are
    documented settings, SECURITY.md's footprint section describes both
    cleanup modes, and the disconnect suite covers persisted-and-reattached
    alongside the existing dropped-and-reaped case.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none of them is a v1.0.0 criterion.

- [ ] **AUR** — _scope: nothing actionable until registration reopens; then an
      account, a key, and one manual first push; outside this checkout._
      _Externally blocked:_ registration is closed to new accounts because of
      spam, so there is no account to push from and nothing in this checkout
      changes that. `release.yml`'s `aur` job stays written and unexercised
      until it reopens, and this entry is tracked rather than actionable — it
      is deliberately not a v1 criterion.

  - **When it reopens:** register; `ssh-keygen -t ed25519`, add the public half
    there, add the private half as the `AUR_SSH_KEY` repo secret and delete the
    local copy. For each package's first push, re-run the namcap gate against
    the published source and push only `PKGBUILD` + `.SRCINFO` — that first
    push is manual, `release.yml`'s `aur` job handles the versioned package
    after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.
