# Governance

Who decides what in say-hi, how a change gets in, and what happens to the
project if its one maintainer stops. Sending a change is
[CONTRIBUTING.md](CONTRIBUTING.md)'s job; this page is the part it leaves out.
Small on purpose, and written down so nobody has to guess.

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

The reasoning is public all the same. What is left to do is
[README's Roadmap](../README.md#roadmap); what was weighed and answered no, with
the reason, is [COMPATIBILITY.md](COMPATIBILITY.md) for targets, shells, and
features, [RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped) for
release channels, and [ALTERNATIVES.md](ALTERNATIVES.md) for the tools say-hi
is not trying to be. A reason that has stopped being true is worth an issue.

## Roles

| Role        | Who                                                                                        | What they do                                                                                                                                |
| ----------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Maintainer  | [ivylikethevine](https://github.com/ivylikethevine), the one owner in `.github/CODEOWNERS` | Owns the repository, reviews and merges every change, holds the release and signing keys, triages security reports, and sets the direction. |
| Contributor | Anyone who opens a pull request                                                            | Proposes a change. No merge rights; every pull request is reviewed by the maintainer.                                                       |
| Reporter    | Anyone who opens an issue or a discussion, or reports a vulnerability privately            | Raises a bug, an idea, or a vulnerability, through the channel [SUPPORT.md](SUPPORT.md) names for each.                                     |

There are no other roles today. A recurring contributor who wants one starts
the conversation in an issue, and whatever is decided is recorded here.

## How a change gets in

1. **Check it isn't already decided**, in the documents under
   [Decision-making](#decision-making).
2. **Open a pull request against `dev`**, the development branch, with the
   template's sections filled in.
3. **The gate passes**: `tests/test_runner.sh --group fast` and
   `--group lint` locally, and the CI jobs listed in
   [CONTRIBUTING.md's _What CI runs_](CONTRIBUTING.md#what-ci-runs).
4. **The maintainer reviews and merges** into `dev`.
5. **`main` is protected**: it takes pull requests from `dev` and requires the
   checks CONTRIBUTING names before a merge. Releases are built off `main` from
   a hand-pushed `v*` tag ([RELEASING.md](RELEASING.md#cutting-a-release)).

## Contributor certification

By opening a pull request you certify that you wrote the contribution or
otherwise have the right to submit it under the MIT license. That is the
[Developer Certificate of Origin](https://developercertificate.org/) in
spirit; no `Signed-off-by` line is required.

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
