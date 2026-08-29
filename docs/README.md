# Documentation

Reference material that doesn't fit in [the README](../README.md)'s
walkthrough. Each doc says at the top what it covers versus the README (or
opens with a `## Contents` that makes it obvious), so this page is
deliberately just a map, not a summary. Ported from sharerr's identically-named
index, which solved the same "the list only lives in one place" problem there
first — before this, README's own "More docs" section was the only index.

| Doc | Covers |
| --- | --- |
| [Configuration](CONFIGURATION.md) | The config overlay: every toggle and environment variable hi reads. |
| [Supported](SUPPORTED.md) | Every target hi answers to, which OSes land a full session, and which shell you end up in. |
| [Not supported](UNSUPPORTED.md) | Every runtime, shell, channel and feature answered **no**, and why. |
| [Alternatives](ALTERNATIVES.md) | sshrc, xxh, kyrat, sshdot and homeshick, side by side. |
| [Testing](TESTING.md) | The runner, suite groups, parallel cases, the lint gate, relaying. |
| [Glossary](GLOSSARY.md) | The named idioms the code's `GLOSSARY:` tags point at; drift-checked by the lint suite. |
| [Security policy](SECURITY.md) | What hi touches on a target, and how to report a vulnerability. |
| [Packaging](PACKAGING.md) | The publishing runbook, the reproducibility contract, verifying a download, regenerating the demo GIFs. |
| [Roadmap](ROADMAP.md) | What is planned and what it is blocked on. |
| [Future](FUTURE.md) | Unscheduled research, not queued work. |
| [OpenSSF Best Practices draft](CII-BEST-PRACTICES-DRAFT.md) | The questionnaire, answered against this tree — scratch until it's transcribed to bestpractices.dev. |
| [Contributing](CONTRIBUTING.md) | The gate to run before a pull request, and which doc changes with what. |
