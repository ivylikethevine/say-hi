# OpenSSF improvements

Where the Scorecard number is capped for a one-maintainer project, and the
Best Practices questionnaire answer sheet to enter at
[bestpractices.dev](https://www.bestpractices.dev/en/projects/14397/edit).
Work already shipped for either badge is not repeated here; git history is
the ledger, and [SECURITY.md#assurance-case](SECURITY.md#assurance-case) is
the security half. The account-side steps still open are in
[README's Roadmap](../README.md#post-10).

## Contents

- [The score has a ceiling here](#the-score-has-a-ceiling-here)
- [The Best Practices answer sheet](#the-best-practices-answer-sheet)
  - [Passing level](#passing-level)
  - [Silver level](#silver-level)
  - [Gold level](#gold-level)

## The score has a ceiling here

Scorecard weights each check (Binary-Artifacts, License and the rest that sit
at 10 count fully) and averages. Which of the low scores are fixable here:

- **Code-Review sits at 0** — 0 of the last several changesets carry an
  approved review: one maintainer, nobody else to approve a PR. A
  `Reviewed-by:` trailer would satisfy the scanner without a review having
  happened; that's not going to be added. The largest fixable-looking gap in
  the report, and not fixable without a second person.
- **Fuzzing sits at 0** — say-hi is bash; Scorecard's probe detects OSS-Fuzz,
  ClusterFuzzLite, Go native fuzzing, cargo-fuzz and OneFuzz, none of which
  targets shell. `.scorecard.yml` marks it `not-applicable`.
- **Contributors sits at 3** — the check wants ≥2 contributing organizations
  among recent contributors; there's one. `not-applicable` in
  `.scorecard.yml` too.
- **CII-Best-Practices** — the project is registered at
  [bestpractices.dev](https://www.bestpractices.dev/) (the OpenSSF Best
  Practices badge in README's badge block, a self-assessment questionnaire
  separate from Scorecard). The score reflects registration; three MUST
  criteria are release-shaped, and tagged releases now exist (`v0.1.0`
  onward) - re-check the live questionnaire rather than assuming _Passing_
  still waits on one.
- **Signed-Releases** was `-1` (excluded from the average) before any tag
  existed. `release.yml` ships `dist/SHA256SUMS.minisig` on every release,
  which the check's signature probe recognizes for 8/10; the build-provenance
  attestation `build` creates was invisible to it until `publish` also
  downloads that attestation and re-uploads it as `dist/say-hi.intoto.jsonl` -
  the literal filename the check's provenance probe looks for among release
  assets, for the full 10/10. Re-check the live score against a tag cut after
  that change; it doesn't move retroactively on tags that already shipped.
- **Pinned-Dependencies reads low for a reason outside this repo.** GitHub
  shipped same-repository `uses: $/...` references in July 2026
  ([changelog](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)):
  a local action or reusable workflow resolves at the exact commit running,
  with no `./` plus checkout and no separately-pinnable ref. `ci.yml` explains
  why `actionlint` is pinned to a fork that understands it (upstream doesn't
  yet); Scorecard's own dependency extraction is the same story - as of this
  writing it reads every `$/...` reference as an unresolvable third-party
  action with no `@sha`, which is where most of the check's "unpinned"
  count comes from. The actual third-party (non-`$/`) actions in the tree are
  100% SHA-pinned; re-run the numbers by hand
  (`grep -rhoE 'uses: +[^ ]+' .github/workflows .github/actions`) before
  assuming a `$/` reference is the gap. Not something to revert to `./` to
  chase a parser that hasn't caught up - that would trade a real improvement
  for a score built on a five-week-old blind spot.
- **Branch-Protection sits at 8, by choice.** The next tier up requires
  "include administrators", which would remove the maintainer's own ability to
  push past a failing check or merge without the full gate - kept, since
  that's the emergency valve for a one-person project. 10 additionally needs
  two required approving reviews, which needs a second person regardless.

A single maintainer cannot close these regardless of repo state: Scorecard's
`Code-Review` and `Contributors`, the Best Practices badge's
`access_continuity` (silver MUST - release continuity within a week of
losing the maintainer), and gold's `bus_factor`, `contributors_unassociated`
and `two_person_review`.

## The Best Practices answer sheet

Enter these at
[bestpractices.dev/en/projects/14397/edit](https://www.bestpractices.dev/en/projects/14397/edit).
**M** = Met, **N/A** = not applicable, **U** = Unmet. `access_continuity` (a
silver MUST) is answered Unmet on purpose - see
[above](#the-score-has-a-ceiling-here) - so silver will not be awarded
by filling in the rest; do it anyway, since a complete honest entry is the
point and it's a prerequisite the day a second maintainer exists.

### Passing level

Already 100%. Two corrections worth making:

| Criterion                            | Now                                                                      | Change to               | Why                                                                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------ | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `dynamic_analysis_enable_assertions` | U, "No fuzzer for bash/shell scripts."                                   | **M**                   | Wrong question answered - this criterion is about run-time assertions during testing, not fuzzing. Every entry point runs `set -euo pipefail`; the suites assert invariants directly, and `--require-run` turns a stood-down backend into a failure rather than a silent pass. |
| `dynamic_analysis`                   | U, "No sanitizer/fuzzer works for bash/shell scripts that I'm aware of." | **U**, tighten the text | Correct as-is. The alternate route ("an automated test suite with at least 80% branch coverage") doesn't apply either: kcov and bashcov both report _statement_ coverage (the README badges), not branch.                                                                      |

### Silver level

#### Basics / Project oversight

| Criterion                | Answer                    | Evidence                                                                                                                           |
| ------------------------ | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `dco`                    | M                         | [CONTRIBUTING.md#opening-the-pull-request](CONTRIBUTING.md#opening-the-pull-request) - DCO in spirit, no `Signed-off-by` required. |
| `governance`             | M                         | [CONTRIBUTING.md#governance](CONTRIBUTING.md#governance) - one maintainer, BDFL, stated explicitly.                                |
| `code_of_conduct`        | M                         | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), reporting address included.                                                              |
| `roles_responsibilities` | M                         | [CONTRIBUTING.md#governance](CONTRIBUTING.md#governance) + `.github/CODEOWNERS`.                                                   |
| `access_continuity`      | U                         | One maintainer holds the repo and every signing key; the license lets a fork carry on, which is not "release within a week."       |
| `bus_factor`             | U (SHOULD, doesn't block) | Single maintainer.                                                                                                                 |

#### Basics / Documentation

| Criterion                    | Answer | Evidence                                                                                                                                                                                                                |
| ---------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `documentation_roadmap`      | M      | [README.md#roadmap](../README.md#roadmap).                                                                                                                                                                              |
| `documentation_architecture` | M      | [SETTINGS.md#how-it-works](SETTINGS.md#how-it-works); [GLOSSARY.md](GLOSSARY.md).                                                                                                                                       |
| `documentation_security`     | M      | [SECURITY.md](SECURITY.md).                                                                                                                                                                                             |
| `documentation_quick_start`  | M      | [README.md#in-sixty-seconds](../README.md#in-sixty-seconds); [tldr.md](tldr.md); [hi.1](hi.1).                                                                                                                          |
| `documentation_current`      | M      | The lint gate mechanically fails on doc drift - GLOSSARY tags both ways, `SETTINGS.md`'s roster against `_HI_TOGGLES`, `runner_test.sh` against `ci.yml`'s `--group` roster, `packaging_test.sh` against `release.yml`. |
| `documentation_achievements` | M      | README's badge block links Best Practices, Scorecard and Baseline.                                                                                                                                                      |

#### Basics / Accessibility, i18n, other

| Criterion                      | Answer                    | Evidence                                                                                                           |
| ------------------------------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `accessibility_best_practices` | M                         | `NO_COLOR` honored and propagated to the target (`hi.sh:97`, `hi.sh:589`); `_HI_ASCII` for a no-Unicode rendering. |
| `internationalization`         | U (SHOULD, doesn't block) | Output is short English status text; no message catalog, not planned before 1.0.                                   |
| `sites_password_security`      | N/A                       | GitHub/GitHub Pages; the project stores no passwords.                                                              |

#### Change Control / Reporting

| Criterion                        | Answer | Evidence                                                                                                                                            |
| -------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `maintenance_or_update`          | M      | Semver, [CONTRIBUTING.md#what-1x-will-not-break](CONTRIBUTING.md#what-1x-will-not-break); a retiring toggle warns one minor release before it goes. |
| `report_tracker`                 | M      | Already answered - GitHub issues.                                                                                                                   |
| `vulnerability_report_credit`    | N/A    | No vulnerabilities resolved in the last 12 months.                                                                                                  |
| `vulnerability_response_process` | M      | [SECURITY.md#reporting-a-vulnerability](SECURITY.md#reporting-a-vulnerability) - 14-day acknowledgement, 60-day disclosure target.                  |

#### Quality / Coding standards and build

| Criterion                                          | Answer | Evidence                                                                                                                                                                      |
| -------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `coding_standards`                                 | M      | [CONTRIBUTING.md#what-a-review-will-bounce-on](CONTRIBUTING.md#what-a-review-will-bounce-on) - now names Google Shell Style Guide plus this project's deviations.             |
| `coding_standards_enforced`                        | M      | `--group lint`, a required check: shellcheck, shfmt, checkbashisms, `zsh -n`/`fish --no-execute`. Exceptions are per-line `# shellcheck disable=` comments at their location. |
| `build_standard_variables` / `build_non_recursive` | N/A    | No native binaries, no compile step.                                                                                                                                          |
| `build_preserve_debug`                             | N/A    | Shell sources ship as-is.                                                                                                                                                     |
| `build_repeatable`                                 | M      | `packaging-smoke` builds the deb/rpm/apk twice and diffs `SHA256SUMS` for byte-identical output; [PACKAGING.md#reproducibility](PACKAGING.md#reproducibility).                |

#### Quality / Installation and dependencies

| Criterion                         | Answer | Evidence                                                                                                                                           |
| --------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `installation_common`             | M      | apt/dnf/apk repo, Homebrew tap, `scripts/install.sh`; `--uninstall` is the exact inverse.                                                          |
| `installation_standard_variables` | M      | `scripts/install.sh` honors `$DESTDIR` and `--prefix` (`install.sh:141`, `:281-300`).                                                              |
| `installation_development_quick`  | M      | `git clone` then `tests/test_runner.sh`; fast suites are dependency-free.                                                                          |
| `external_dependencies`           | M      | `packaging/nfpm/nfpm.yaml` `depends:`; `.github/actions/setup-tool/tools.txt`; `.github/dependabot.yml`.                                           |
| `dependency_monitoring`           | M      | Dependabot weekly (actions, docker); `tool-versions.yml` weekly against `tools.txt`; `image-scan.yml` runs Trivy and tracks findings via an issue. |
| `updateable_reused_components`    | M      | Nothing is vendored; the packaged install declares its tools as package dependencies.                                                              |
| `interfaces_current`              | M      | Bash-3.2-floor grep; fish/zsh floor and ceiling exercised against pinned containers in `tests/lint/dialects_test.sh`.                              |

#### Quality / Tests and warnings

| Criterion                       | Answer | Evidence                                                                                                                                         |
| ------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `automated_integration_testing` | M      | `ci.yml` on every `pull_request` and `push` to `main`; seven required checks before a merge.                                                     |
| `regression_tests_added50`      | M      | ~55 suites under `tests/`; `.github/pull_request_template.md` requires ≥75% coverage on new code.                                                |
| `test_statement_coverage80`     | M      | README's kcov and bashcov badges, both past the bar, measured over the shipped product.                                                          |
| `test_policy_mandated`          | M      | [CONTRIBUTING.md](CONTRIBUTING.md) - a new suite has a home and a `test_runner.sh` registration.                                                 |
| `tests_documented_added`        | M      | `.github/pull_request_template.md` checklist.                                                                                                    |
| `warnings_strict`               | M      | `.shellcheckrc` disables nothing globally; shellcheck runs `-x` as a required gate alongside actionlint, zizmor and `mandoc -T lint -W warning`. |

#### Security

| Criterion                                                                          | Answer | Evidence                                                                                                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `implement_secure_design`                                                          | M      | [SECURITY.md#assurance-case](SECURITY.md#assurance-case) - new section.                                                                                                                                                                                                                                                    |
| `crypto_weaknesses`                                                                | M      | Already answered.                                                                                                                                                                                                                                                                                                          |
| `crypto_algorithm_agility` / `crypto_credential_agility`                           | N/A    | The shipped product performs no cryptography and never processes credentials or private keys - ssh does.                                                                                                                                                                                                                   |
| `crypto_used_network`                                                              | M      | All transport is ssh(2) or the container/orchestrator client's own channel; hi opens no socket of its own.                                                                                                                                                                                                                 |
| `crypto_tls12` / `crypto_certificate_verification` / `crypto_verification_private` | N/A    | The software does not use TLS.                                                                                                                                                                                                                                                                                             |
| `signed_releases`                                                                  | M      | `SHA256SUMS` signed with minisign, public key in [PACKAGING.md#verifying-a-release-download](PACKAGING.md#verifying-a-release-download); GPG signs the rpm and the apt/rpm repo metadata; a separate key signs the apk index. Private keys live in Actions secrets, never on the Pages site that distributes the packages. |
| `version_tags_signed`                                                              | M      | Tags verify - `git tag -v v0.1.5` returns a good signature.                                                                                                                                                                                                                                                                |
| `input_validation`                                                                 | M      | `_hi_safe_path` (`hi.sh:520`), `_hi_ssh_host_tag`/`_hi_ssh_pattern_hit` (`common/core.sh`) - allowlisted, not evaluated.                                                                                                                                                                                                   |
| `hardening`                                                                        | M      | `set -euo pipefail` in every entry point; session payload lands in a directory removed on exit.                                                                                                                                                                                                                            |
| `assurance_case`                                                                   | M      | [SECURITY.md#assurance-case](SECURITY.md#assurance-case) - new section.                                                                                                                                                                                                                                                    |

**Analysis** - `static_analysis_common_vulnerabilities` and
`dynamic_analysis_unsafe` already Met, unchanged.

### Gold level

Three MUSTs need a second person regardless of repo state: `bus_factor`,
`contributors_unassociated`, `two_person_review`. `achieve_silver` is Unmet as
a consequence of `access_continuity`. The rest, for a complete entry:

| Criterion                                                                           | Answer                         | Evidence                                                                                                                                                       |
| ----------------------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `achieve_silver` / `bus_factor` / `contributors_unassociated` / `two_person_review` | U                              | One maintainer, one contributing organization.                                                                                                                 |
| `copyright_per_file`                                                                | M                              | `# Copyright the say-hi contributors.` at the top of every source file.                                                                                        |
| `license_per_file`                                                                  | M                              | `# SPDX-License-Identifier: MIT` at the top of every source file; `LICENSE.md` holds the full text.                                                            |
| `repo_distributed`                                                                  | M                              | Already answered.                                                                                                                                              |
| `small_tasks`                                                                       | M _(needs one GitHub action)_  | Label two or three open issues `good first issue` and link the label URL - none exist yet.                                                                     |
| `require_2FA`                                                                       | M                              | [CONTRIBUTING.md#governance](CONTRIBUTING.md#governance) states 2FA is enabled on the maintainer account.                                                      |
| `secure_2FA`                                                                        | M _(confirm before answering)_ | TOTP/WebAuthn, not SMS.                                                                                                                                        |
| `code_review_standards`                                                             | M                              | [CONTRIBUTING.md#what-a-review-will-bounce-on](CONTRIBUTING.md#what-a-review-will-bounce-on) + the required-checks list.                                       |
| `build_reproducible`                                                                | M                              | [PACKAGING.md#reproducibility](PACKAGING.md#reproducibility); byte-identical rebuild in CI.                                                                    |
| `test_invocation`                                                                   | M                              | `tests/test_runner.sh` (also `hi --test`).                                                                                                                     |
| `test_continuous_integration`                                                       | M                              | `.github/workflows/ci.yml`.                                                                                                                                    |
| `test_statement_coverage90`                                                         | U                              | the README badges - short of 90%.                                                                                                                              |
| `test_branch_coverage80`                                                            | N/A                            | No FLOSS tool measures branch coverage for shell; kcov and bashcov both report statements only.                                                                |
| `crypto_used_network`                                                               | M                              | Same as silver.                                                                                                                                                |
| `crypto_tls12`                                                                      | N/A                            | Does not use TLS.                                                                                                                                              |
| `hardened_site`                                                                     | M _(check before answering)_   | Repository and releases on GitHub, which the criterion notes meets this; check `ivylikethevine.github.io/say-hi/` on securityheaders.com.                      |
| `security_review`                                                                   | M                              | [SECURITY.md#assurance-case](SECURITY.md#assurance-case) is a documented, dated review of the security requirements and boundary.                              |
| `hardening`                                                                         | M                              | Same evidence as silver, with the assurance-case URL.                                                                                                          |
| `dynamic_analysis`                                                                  | U                              | Same reasoning as passing's entry - the branch-coverage alternate route is unmeasurable here.                                                                  |
| `dynamic_analysis_enable_assertions`                                                | M                              | `set -euo pipefail` throughout; e2e suites exercise real ssh/docker/podman/nomad/kube backends, and `--require-run` turns a stood-down backend into a failure. |
