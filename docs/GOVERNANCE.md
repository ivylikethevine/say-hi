# Governance

Who decides what in say-hi, how a change gets in, and what happens to the
project if its one maintainer stops. Sending a change is
[CONTRIBUTING.md](CONTRIBUTING.md)'s job; this page is the part it leaves out.

## Contents

- [Decision-making](#decision-making)
- [Roles](#roles)
- [How a change gets in](#how-a-change-gets-in)
- [Contributor certification](#contributor-certification)
- [Sensitive access](#sensitive-access)
- [Continuity](#continuity)

## Decision-making

say-hi is a **single-maintainer project**: one person makes the final call on
scope and direction (the model usually filed under BDFL). There is no
committee, no vote, and nobody else to appeal to.

The reasoning is public all the same: what is left to do is
[README's Roadmap](../README.md#roadmap), and what was answered no, with the
reason, is listed in
[SUPPORT.md's _Already turned down_](SUPPORT.md#already-turned-down), with
the runtime, packaging, and tool verdicts reached from
[CONTRIBUTING.md's _Before you start_](CONTRIBUTING.md#before-you-start). A
reason that has stopped being true is worth an issue.

## Roles

| Role        | Who                                                                                        | What they do                                                                                                                                |
| ----------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Maintainer  | [ivylikethevine](https://github.com/ivylikethevine), the one owner in `.github/CODEOWNERS` | Owns the repository, reviews and merges every change, holds the release and signing keys, triages security reports, and sets the direction. |
| Contributor | Anyone who opens a pull request                                                            | Proposes a change. No merge rights; every pull request is reviewed by the maintainer.                                                       |
| Reporter    | Anyone who opens an issue or a discussion, or reports a vulnerability privately            | Raises a bug, an idea, or a vulnerability, through the channel [SUPPORT.md](SUPPORT.md) names for each.                                     |

There are no other roles today. A recurring contributor who wants one starts
the conversation in an issue, and whatever is decided is recorded here.

## How a change gets in

1. **A pull request against `dev`**, after the gate, as
   [CONTRIBUTING.md](CONTRIBUTING.md#the-gate) describes.
2. **The maintainer reviews and merges** it into `dev` once CI is green.
3. **`dev` reaches `main` by pull request.** `main` is protected: it requires
   signed commits and the checks
   [CONTRIBUTING.md's _What CI runs_](CONTRIBUTING.md#what-ci-runs) names.
4. **A release is a signed `v*` tag on `main`**, pushed by the maintainer
   ([RELEASING.md](RELEASING.md#cutting-a-release)).

## Contributor certification

By opening a pull request you certify that you wrote the contribution or
otherwise have the right to submit it under the MIT license: the
[Developer Certificate of Origin](https://developercertificate.org/) in
spirit, with no `Signed-off-by` line required.

## Sensitive access

Repository settings, secrets (the signing and publishing keys), and the
`release` environment are reachable by the maintainer alone, and two-factor
authentication is enabled on that account.

## Continuity

Everything needed to carry the project on is public: the tree is
MIT-licensed ([LICENSE.md](../LICENSE.md)), releases are reproducible from it
([RELEASING.md](RELEASING.md#reproducibility)), and nothing load-bearing lives
outside this repository. If the maintainer goes permanently quiet, fork it and
carry on; the license is the succession plan.

That is not a second person able to cut a release within a week, which is why
the OpenSSF `access_continuity` and `bus_factor` criteria are answered unmet in
[OPENSSF-IMPROVEMENTS.md](OPENSSF-IMPROVEMENTS.md#basics--project-oversight).
