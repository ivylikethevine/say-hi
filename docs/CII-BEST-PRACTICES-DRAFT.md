# OpenSSF Best Practices badge — questionnaire draft

Working notes for the [OpenSSF Best Practices badge](https://www.bestpractices.dev/)
(the project formerly known as the CII Best Practices badge — "CII" retired
when the Core Infrastructure Initiative folded into OpenSSF; the site,
criteria and badge are the same lineage under a new name). This file is scratch,
not a shipped artifact: delete it once the project is registered and the
answers below have been transcribed into the questionnaire — git history is
the ledger, per [ROADMAP.md](ROADMAP.md)'s own convention.

Tracked as an open gap in [TESTING.md](TESTING.md#the-score-has-a-ceiling-here)
and [ROADMAP.md](ROADMAP.md#blocked-until-someone-else-moves).

## Contents

- [Registering](#registering)
- [What's already true, in one place](#whats-already-true-in-one-place)
- [The passing-level criteria](#the-passing-level-criteria)
  - [Basics](#basics)
  - [Change Control](#change-control)
  - [Reporting](#reporting)
  - [Quality](#quality)
  - [Security](#security)
  - [Analysis](#analysis)
- [Not Met today, and what closes each one](#not-met-today-and-what-closes-each-one)
- [Once the project ID exists](#once-the-project-id-exists)

## Registering

1. Sign in at <https://www.bestpractices.dev> with GitHub.
2. Add project, repo URL `https://github.com/ivylikethevine/say-hi`.
3. The site issues a numeric project ID immediately and starts the badge at
   `in progress 0%` — that's a real, displayable state; you don't need every
   answer filled in before saving. It also autofills a number of criteria
   from the GitHub API (license, HTTPS site, public repo) — the table below
   only needs your attention where autofill can't reach.
4. Work through the six sections below in order; each maps onto a
   `bestpractices.dev` tab of the same name.

Source of truth for the criterion list and category (MUST / SHOULD /
SUGGESTED) is
[`criteria/criteria.yml`](https://github.com/ossf/best-practices-badge/blob/main/criteria/criteria.yml)
in the badge project's own repo — re-pull it if this file is more than a
few months old, since criteria do change between releases. 67 criteria sit at
the passing level; the table below covers all 67.

## What's already true, in one place

Cited once here rather than repeated in every row below:

- **License** — [`LICENSE.md`](../LICENSE.md), MIT, kept at the repo root
  specifically so both GitHub's and this badge's license detection find it
  (`scripts/install.sh:261`).
- **Contribution guide** — [`CONTRIBUTING.md`](CONTRIBUTING.md): the gate to
  run, what a review bounces on, which docs change with what.
- **Vulnerability reporting** — [`SECURITY.md`](SECURITY.md#reporting-a-vulnerability):
  GitHub private vulnerability reporting, linked directly.
- **CI** — [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs the
  fast suites and the lint gate on every push and PR;
  [`TESTING.md`](TESTING.md) is the runbook.
- **Static analysis** — [`.github/workflows/codeql.yml`](../.github/workflows/codeql.yml)
  (CodeQL) plus `tests/test_runner.sh --group lint`'s fourteen-way shellcheck
  fan-out; both run on every push/PR.
- **Delivery integrity** — `release.yml`'s `publish` job signs
  `SHA256SUMS.minisig` with minisign and attaches a build-provenance
  attestation (`actions/attest-build-provenance`); `SECURITY.md` states there
  is no `curl | bash` install path.
- **Credential hygiene** — GitHub secret scanning and push protection are on
  for the repo (`SECURITY.md#when-a-push-is-refused`); the only handled
  secrets (`AUR_SSH_KEY`, `HOMEBREW_TAP_TOKEN`) are generated locally, pasted
  into a settings page, and deleted, per `PACKAGING.md`.
- **Cryptography — almost entirely N/A.** `hi` implements no cryptography of
  its own: it execs `ssh`, `docker exec`, `podman exec`, `nomad alloc exec`,
  `kubectl exec` and lets each transport's own security stand
  (`SECURITY.md#what-hi-does---and-deliberately-doesnt`). The one wire-format
  choice that looks crypto-adjacent is explicitly not: the payload is
  armored with `base64`, never `openssl`
  ([GLOSSARY.md HI.17](GLOSSARY.md#hi17-base64-armor)) — pure transport
  encoding, not encryption. This one paragraph is the justification for
  every `crypto_*` row below; don't re-argue it per row.
- **Issue tracker** — GitHub Issues is on (`.github/ISSUE_TEMPLATE/`
  carries bug/feature/config templates); `open_issues_count` is 0 as of this
  writing, not an indicator of the tracker being unused.

## The passing-level criteria

Answer legend: **Met** / **Unmet** / **N/A**. `na?` marks criteria the site
allows an N/A answer for; where it doesn't allow one, the row must resolve to
Met or Unmet.

### Basics

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `description_good` | MUST | | Met | README opens with what `hi` is in the first paragraph. |
| `interact` | MUST | | Met | README's "In sixty seconds" section covers install, and `CONTRIBUTING.md` covers the contribution path. |
| `contribution` | MUST | | Met | `CONTRIBUTING.md`, linked from README's docs index. |
| `contribution_requirements` | SHOULD | | Met | `CONTRIBUTING.md#the-gate` and `#what-a-review-will-bounce-on`. |
| `floss_license` | MUST | | Met | MIT, `LICENSE.md`. |
| `floss_license_osi` | SUGGESTED | | Met | MIT is OSI-approved. |
| `license_location` | MUST | | Met | `LICENSE.md` at repo root. |
| `documentation_basics` | MUST | na | Met | README plus `docs/hi.1` (man page) plus `docs/CONFIGURATION.md`. |
| `documentation_interface` | MUST | na | Met | `docs/hi.1` and `docs/CONFIGURATION.md`'s per-setting table document every flag and variable. |
| `sites_https` | MUST | | Met | Repo, Pages site (`https://ivylikethevine.github.io/say-hi/`) and downloads are all `https://`. |
| `discussion` | MUST | | **judgment call** | GitHub Issues is on and is where discussion currently happens; Discussions itself is off (`has_discussions: false`) and is queued on `ROADMAP.md` ("linked from `ISSUE_TEMPLATE/config.yml`"). The criterion accepts a mailing list, chat, or issue tracker as "some" mechanism — Issues alone is plausibly sufficient. Answer Met citing Issues; revisit if the badge site pushes back. |
| `english` | SHOULD | | Met | All docs are English. |
| `maintained` | MUST | | Met | Active commit history; this is the only maintainer, which is fine — the criterion asks for activity, not headcount. |

### Change Control

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `repo_public` | MUST | | Met | Public GitHub repo, full history. |
| `repo_track` | MUST | | Met | Git; every commit is tracked with author and date. |
| `repo_interim` | MUST | | Met | `main` carries commits between releases (there being no release yet doesn't fail this — it asks whether interim states are visible, and they are). |
| `repo_distributed` | SUGGESTED | | Met | Git is inherently distributed. |
| `version_unique` | MUST | | **Unmet — see below** | No tag exists yet. |
| `version_semver` | SUGGESTED | | Unmet (for now) | `ROADMAP.md` names "the semver rule" as part of the still-unwritten stability contract. Answer honestly as Unmet or Unknown until that lands; it's SUGGESTED, not a blocker. |
| `version_tags` | SUGGESTED | | **Unmet — see below** | No tag exists yet. |
| `release_notes` | MUST | na | **Unmet — see below** | Mechanism exists (`release.yml`'s `publish` job composes notes via `releases/generate-notes` plus a verification checklist) but is unproven — no release has shipped through it. |
| `release_notes_vulns` | MUST | na | **Unmet — see below** | Same mechanism; also unproven. |

### Reporting

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `report_process` | MUST | | Met | GitHub Issues, with templates at `.github/ISSUE_TEMPLATE/`. |
| `report_tracker` | SHOULD | | Met | GitHub Issues is the tracker. |
| `report_responses` | MUST | | **see below** | Process exists; no published response-time commitment yet. |
| `enhancement_responses` | SHOULD | | Met | Feature requests go through the same Issues process (`feature_request.yml` template). |
| `report_archive` | MUST | | Met | GitHub Issues archives and is searchable by default. |
| `vulnerability_report_process` | MUST | | Met | `SECURITY.md#reporting-a-vulnerability`. |
| `vulnerability_report_private` | MUST | na | Met | GitHub private vulnerability reporting, linked directly from `SECURITY.md`. |
| `vulnerability_report_response` | MUST | na | **see below** | Process exists; no published response-time commitment yet — same gap as `report_responses`. |

### Quality

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `build` | MUST | na | Met | `packaging/nfpm/nfpm.yaml` plus `packaging/mkpkg.sh`/`bump.sh` build the deb/rpm/apk; `scripts/install.sh` is the from-source path. Both are one-command. |
| `build_common_tools` | SUGGESTED | na | Met | nfpm, standard shell tooling — nothing bespoke required to build. |
| `build_floss_tools` | SHOULD | na | Met | Every build tool in the chain (nfpm, shellcheck, shfmt, bash itself) is FLOSS. |
| `test` | MUST | | Met | `tests/test_runner.sh`; `TESTING.md` is the runbook. |
| `test_invocation` | SHOULD | | Met | `tests/test_runner.sh <suite>` or `--group fast`, one command, documented in `TESTING.md` and `CONTRIBUTING.md`. |
| `test_most` | SUGGESTED | | Met | The lint gate's fourteen halves plus the fast suites cover the large majority of `common/`, `hi.sh`, and `scripts/`; `tests/coverage.sh`'s own header cautions its percentage is untrustworthy, so don't cite a number — cite suite breadth instead. |
| `test_continuous_integration` | SUGGESTED | | Met | `.github/workflows/ci.yml`, every push and PR. |
| `test_policy` | MUST | | Met | `CONTRIBUTING.md#the-gate` requires the fast + lint groups to pass before a PR is opened. |
| `tests_are_added` | MUST | | Met | Same gate; `CONTRIBUTING.md#what-a-review-will-bounce-on` calls out missing test coverage as a bounce reason. |
| `tests_documented_added` | SUGGESTED | | Met | `TESTING.md`'s layout rule: a suite lives in `tests/<the directory it tests>/`, documented and enforced by the lint suite. |
| `warnings` | MUST | na | Met | `set -euo pipefail` throughout; shellcheck runs at the default (non-silenced) warning level. |
| `warnings_fixed` | MUST | na | Met | The lint suite fails the build on any shellcheck finding — nothing is suppressed wholesale. |
| `warnings_strict` | SUGGESTED | na | Met | shellcheck plus the bash-4-isms grep plus checkbashisms all run as hard gates, not advisory. |

### Security

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `know_secure_design` | MUST | | Met | `SECURITY.md`'s "What hi does — and deliberately doesn't" and "Trust boundaries" sections demonstrate the threat model is understood; single maintainer, self-attested. |
| `know_common_errors` | MUST | | Met | Same self-attestation; shellcheck's default rule set catches the shell-specific common-error class (unquoted expansion, word splitting) as a backstop. |
| `crypto_published` | MUST | na | N/A | See "Cryptography — almost entirely N/A" above. |
| `crypto_call` | SHOULD | na | N/A | ditto |
| `crypto_floss` | MUST | na | N/A | ditto |
| `crypto_keylength` | MUST | na | N/A | ditto |
| `crypto_working` | MUST | na | N/A | ditto |
| `crypto_weaknesses` | SHOULD | na | N/A | ditto |
| `crypto_pfs` | SHOULD | na | N/A | ditto |
| `crypto_password_storage` | MUST | na | N/A | ditto — `hi` stores no passwords. |
| `crypto_random` | MUST | na | N/A | ditto |
| `delivery_mitm` | MUST | | Met | HTTPS everywhere (repo, Pages, release downloads over GitHub's CDN). |
| `delivery_unsigned` | MUST | | Met | `release.yml`'s minisign-signed `SHA256SUMS.minisig` plus build-provenance attestation; verification steps are in `PACKAGING.md#verifying-a-release-download`. |
| `vulnerabilities_fixed_60_days` | MUST | | Met | No unaddressed public vulnerability report exists; policy is to fix promptly (self-attested, revisit if one is ever filed). |
| `vulnerabilities_critical_fixed` | SHOULD | | Met | Same. |
| `no_leaked_credentials` | MUST | | Met | `SECURITY.md#when-a-push-is-refused`: secret scanning and push protection are on; the four handled credentials never touch the repo. |

### Analysis

| criterion | category | na? | answer | evidence / justification |
|---|---|---|---|---|
| `static_analysis` | MUST | na | Met | shellcheck (`tests/test_runner.sh --group lint`, fourteen halves) plus CodeQL, both on every push/PR. |
| `static_analysis_common_vulnerabilities` | SUGGESTED | na | Met | CodeQL's default query suite covers this; `codeql.yml`'s header comment notes it exists partly to satisfy this class of check. |
| `static_analysis_fixed` | MUST | na | Met | CodeQL and shellcheck findings block CI; nothing is merged with an open finding. |
| `static_analysis_often` | SUGGESTED | na | Met | Both run on every push and PR, not just periodically. |
| `dynamic_analysis` | SUGGESTED | | **judgment call** | No sanitizer/fuzzer story exists for shell (this is also why Scorecard's Fuzzing check is marked `not-applicable` in `.scorecard.yml`). The e2e suites (ssh/docker/podman/nomad/kube, macOS/Windows/FreeBSD) do exercise real runtime behavior end-to-end; whether that counts as "dynamic analysis" in the site's sense is arguable. Lean Unmet rather than stretch the definition — it's SUGGESTED, costs little. |
| `dynamic_analysis_unsafe` | SUGGESTED | na | N/A | No memory-unsafe language in the tree (bash only). |
| `dynamic_analysis_enable_assertions` | SUGGESTED | | N/A | Not applicable to shell — no assertion mechanism in the relevant sense. |
| `dynamic_analysis_fixed` | MUST | na | N/A | Follows from `dynamic_analysis` being Unmet: nothing to have fixed. |

## Not Met today, and what closes each one

The actionable subset, pulled out of the tables above:

- **`version_unique`, `version_tags`** — need the first git tag. Tied to
  [ROADMAP.md's "Get a release out under branch protection"](ROADMAP.md#quick-wins).
- **`release_notes`, `release_notes_vulns`** — the mechanism already shipped
  in `release.yml`; both just need one real release to go through it and
  prove it out. No code change required.
- **`report_responses`, `vulnerability_report_response`** — both want a
  stated response-time commitment. `SECURITY.md` publishes the *process* but
  names no window. Adding one line to `SECURITY.md#reporting-a-vulnerability`
  (e.g., an acknowledgment-within-N-days commitment) closes both at once —
  the OpenSSF site's own guidance suggests 14 days as a reasonable figure for
  a solo-maintainer project.
- **`discussion`** — currently answered Met on the strength of GitHub Issues
  alone; enabling GitHub Discussions (already on `ROADMAP.md`) makes the
  answer uncontestable instead of arguable.
- **`dynamic_analysis`** (and its two dependents) — SUGGESTED, not MUST;
  leave Unmet rather than force a stretch justification. Revisit only if a
  shell-appropriate dynamic-analysis tool becomes available.
- **`version_semver`** — SUGGESTED; waits on the same stability-contract
  writeup `ROADMAP.md` already queues.

None of the MUST-level gaps blocks *registering* or reaching a meaningful
`in progress` percentage — only `version_unique`, `release_notes`, and
`release_notes_vulns` are release-gated, and everything else above is either
already Met or a one-line doc fix.

## Once the project ID exists

Uncomment the two placeholder badge lines in `README.md`'s badge block and
fill in the ID:

```markdown
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/<ID>/badge)](https://www.bestpractices.dev/projects/<ID>)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/<ID>/baseline)](https://www.bestpractices.dev/projects/<ID>)
```

(Same numeric ID for both — Baseline is a second, shorter self-assessment
against the same registered project.)

Then:

- Update [`TESTING.md`](TESTING.md#the-score-has-a-ceiling-here)'s
  `CII-Best-Practices sits at 0` bullet — it currently says "nobody has
  started it, so it isn't tracked as in-progress anywhere," which stops being
  true the moment the project is registered.
- Update [`ROADMAP.md`](ROADMAP.md#blocked-until-someone-else-moves)'s Best
  Practices sub-bullet to reflect what shipped (this draft, registration) vs.
  what's still blocked (passing, which needs the first release).
- Delete this file — its job is done once the answers live on
  `bestpractices.dev` instead.
