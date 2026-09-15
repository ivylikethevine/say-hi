# Documentation

Reference material that doesn't fit in [the README](../README.md)'s
walkthrough. Each fact has one home, the doc named for it below; every other
page links to that home rather than repeating it. This page is the map.

## Using hi

| Doc                                                                          | Covers                                                                                                             |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| [Settings](SETTINGS.md)                                                      | The config overlay: every toggle and environment variable hi reads.                                                |
| [Integrations](INTEGRATIONS.md)                                              | The tools hi wires in where a target has them: your prompt program, mise, direnv, bat, eza, tmux, and the rest.    |
| [Compatibility](COMPATIBILITY.md)                                            | Every target, OS, and shell hi answers to, and every runtime, shell, and feature answered **no**, and why.         |
| [Packaging](PACKAGING.md)                                                    | The install channels, verifying a release download, and what a package leaves for you to do.                       |
| [Getting help](SUPPORT.md)                                                   | Where to ask a question or file a bug, what to include, and what response to expect.                               |
| [Security policy](SECURITY.md)                                               | The threat model, what hi touches on a target, and how to report a vulnerability.                                  |
| [Man page](https://github.com/ivylikethevine/say-hi/blob/main/docs/hi.1)     | `man hi`: every flag, setting, and exit status; `hi --help` is its short form. A roff page, so not on the site.    |
| [tldr page](https://github.com/ivylikethevine/say-hi/blob/main/docs/tldr.md) | The eight-example draft for tldr-pages, kept in step with `common/flags` by the lint gate. Not on the site either. |

## Understanding it

| Doc                                      | Covers                                                                                                                                                                                 |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [How it works](SETTINGS.md#how-it-works) | The architecture: client to transport to target session, how the payload is built and armored, and cleanup. [What runs where](SECURITY.md#what-runs-where) is the trust-boundary view. |
| [Files](FILES.md)                        | Every file say-hi is made of, reads, recognizes, and creates: on your machine, on a target, and in a package. Where state lives.                                                       |
| [Alternatives](ALTERNATIVES.md)          | sshrc, xxh, kyrat, sshdot, and homeshick, side by side.                                                                                                                                |
| [Glossary](GLOSSARY.md)                  | The named idioms the code's `GLOSSARY:` tags point at; drift-checked by the lint suite. Never ships.                                                                                   |

## Changing it

| Doc                                             | Covers                                                                                                                                |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| [Contributing](CONTRIBUTING.md)                 | The gate, what a review bounces on, what 1.x will not break, which docs change with what, AI-assisted contributions, push protection. |
| [Testing](TESTING.md)                           | The runner, suite groups, parallel cases, coverage, the lint gate, relaying.                                                          |
| [Releasing](RELEASING.md)                       | The maintainer's runbook: cutting a release, the release environment, publishing each channel, reproducibility, and the demo GIFs.    |
| [Governance](GOVERNANCE.md)                     | Who decides, the roles, how a change gets in, contributor certification, and continuity.                                              |
| [Code of conduct](CODE_OF_CONDUCT.md)           | The Contributor Covenant 2.1 as adopted here: the bar for behaviour, where to report a breach, and the enforcement ladder.            |
| [OpenSSF answer sheet](OPENSSF-IMPROVEMENTS.md) | Where the Scorecard number is capped here, and the Best Practices questionnaire answers.                                              |
