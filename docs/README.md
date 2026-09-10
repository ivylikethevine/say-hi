# Documentation

Reference material that doesn't fit in [the README](../README.md)'s
walkthrough.

## Using hi

| Doc                                   | Covers                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [Settings](SETTINGS.md)               | The config overlay: every toggle and environment variable hi reads.                                      |
| [Integrations](INTEGRATIONS.md)       | The tools hi wires in where a target has them: starship, oh-my-posh, zoxide, atuin, mise, direnv, bat, eza, tmux and the rest. |
| [Support](SUPPORT.md)                 | Every target, OS and shell hi answers to, and every runtime, shell and feature answered **no**, and why. |
| [Alternatives](ALTERNATIVES.md)       | sshrc, xxh, kyrat, sshdot and homeshick, side by side.                                                   |
| [Security policy](SECURITY.md)        | The threat model, what hi touches on a target, and how to report a vulnerability.                        |
| [Packaging](PACKAGING.md)             | Verifying a release download, what a package installs, and the publishing runbook behind them.           |
| [Man page](https://github.com/ivylikethevine/say-hi/blob/main/docs/hi.1) | `man hi`: every flag, setting and exit status; `hi --help` is its short form. A roff page, so not on the site. |
| [tldr page](https://github.com/ivylikethevine/say-hi/blob/main/docs/tldr.md) | The eight-example draft for tldr-pages, kept in step with `common/flags` by the lint gate. Not on the site either. |

## Working on hi

| Doc                                   | Covers                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [Contributing](CONTRIBUTING.md)       | The gate, what a review bounces on, what 1.x will not break, push protection, governance.                |
| [Testing](TESTING.md)                 | The runner, suite groups, parallel cases, coverage, the lint gate, relaying.                             |
| [Glossary](GLOSSARY.md)               | The named idioms the code's `GLOSSARY:` tags point at; drift-checked by the lint suite. Never ships.     |
| [Code of conduct](CODE_OF_CONDUCT.md) | The bar for behaviour in issues, pull requests and discussions, and where to report a breach.            |

The OpenSSF Best Practices answer sheet is a maintainer worksheet, kept at
[.github/OPENSSF-IMPROVEMENTS.md](../.github/OPENSSF-IMPROVEMENTS.md).
