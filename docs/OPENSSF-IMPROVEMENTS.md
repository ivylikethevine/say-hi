# OpenSSF improvements

The Best Practices questionnaire answer sheet for this project - still to be
entered by hand at
[bestpractices.dev](https://www.bestpractices.dev/en/projects/14397/edit) -
and what a single maintainer cannot close regardless of repo state. Work
already shipped for the Scorecard and Best Practices badges is not repeated
here; git history is the ledger, and
[TESTING.md#the-score-has-a-ceiling-here](TESTING.md#the-score-has-a-ceiling-here)
and [SECURITY.md#assurance-case](SECURITY.md#assurance-case) are the current
state of the two things this file used to narrate.

## Contents

- [What still needs a second person](#what-still-needs-a-second-person)
- [The Best Practices answer sheet](#the-best-practices-answer-sheet)
  - [Passing level](#passing-level)
  - [Silver level](#silver-level)
  - [Gold level](#gold-level)
- [Left for a human](#left-for-a-human)

## What still needs a second person

Unchanged by anything above - a single maintainer cannot close these
regardless of repo state:

- Scorecard's `Code-Review` (0 - no second approver), `Contributors` (3 - one
  contributing organization).
- The Best Practices badge's `access_continuity` (silver MUST - release
  continuity within a week of losing the maintainer), and gold's
  `bus_factor`, `contributors_unassociated`, `two_person_review`.

Detail on each is [TESTING.md#the-score-has-a-ceiling-here](TESTING.md#the-score-has-a-ceiling-here)
and the answer sheet below.

## The Best Practices answer sheet

Enter these at
[bestpractices.dev/en/projects/14397/edit](https://www.bestpractices.dev/en/projects/14397/edit).
**M** = Met, **N/A** = not applicable, **U** = Unmet. `access_continuity` (a
silver MUST) is answered Unmet on purpose - see
[above](#what-still-needs-a-second-person) - so silver will not be awarded
by filling in the rest; do it anyway, since a complete honest entry is the
point and it's a prerequisite the day a second maintainer exists.

### Passing level

Already 100%. Two corrections worth making:

| Criterion                            | Now                                                                      | Change to               | Why                                                                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------ | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `dynamic_analysis_enable_assertions` | U, "No fuzzer for bash/shell scripts."                                   | **M**                   | Wrong question answered - this criterion is about run-time assertions during testing, not fuzzing. Every entry point runs `set -euo pipefail`; the suites assert invariants directly, and `--require-run` turns a stood-down backend into a failure rather than a silent pass. |
| `dynamic_analysis`                   | U, "No sanitizer/fuzzer works for bash/shell scripts that I'm aware of." | **U**, tighten the text | Correct as-is. The alternate route ("an automated test suite with at least 80% branch coverage") doesn't apply either: kcov and bashcov both report _statement_ coverage (86.91% / 87.59%), not branch.                                                                        |

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
| `test_statement_coverage80`     | M      | 86.91% (kcov) / 87.59% (bashcov), measured over the shipped product.                                                                             |
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
| `test_statement_coverage90`                                                         | U                              | 86.91% / 87.59% - short of 90%.                                                                                                                                |
| `test_branch_coverage80`                                                            | N/A                            | No FLOSS tool measures branch coverage for shell; kcov and bashcov both report statements only.                                                                |
| `crypto_used_network`                                                               | M                              | Same as silver.                                                                                                                                                |
| `crypto_tls12`                                                                      | N/A                            | Does not use TLS.                                                                                                                                              |
| `hardened_site`                                                                     | M _(check before answering)_   | Repository and releases on GitHub, which the criterion notes meets this; check `ivylikethevine.github.io/say-hi/` on securityheaders.com.                      |
| `security_review`                                                                   | M                              | [SECURITY.md#assurance-case](SECURITY.md#assurance-case) is a documented, dated review of the security requirements and boundary.                              |
| `hardening`                                                                         | M                              | Same evidence as silver, with the assurance-case URL.                                                                                                          |
| `dynamic_analysis`                                                                  | U                              | Same reasoning as passing's entry - the branch-coverage alternate route is unmeasurable here.                                                                  |
| `dynamic_analysis_enable_assertions`                                                | M                              | `set -euo pipefail` throughout; e2e suites exercise real ssh/docker/podman/nomad/kube backends, and `--require-run` turns a stood-down backend into a failure. |

## Left for a human

- Entering the answer sheet above at bestpractices.dev - this session cannot
  log in to a third-party site.
- Labeling `good first issue` on a couple of open issues, for `small_tasks`.
- Confirming `secure_2FA` (TOTP/WebAuthn, not SMS) and checking
  `hardened_site` against securityheaders.com before answering either.
- All git operations (commit, push, tag) stay with the user, same as always.
