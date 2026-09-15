# Getting help

Where to ask about say-hi, what to bring, and what to expect back. Whether hi
answers to a given OS, shell, or backend at all is
[COMPATIBILITY.md](COMPATIBILITY.md)'s job; read it first, since a "no" there
comes with its reason.

## Where to ask

| You have                                  | Go to                                                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| A usage question, or an idea to talk over | [Discussions](https://github.com/ivylikethevine/say-hi/discussions)                                          |
| Something hi did wrong, or failed to do   | [The bug report form](https://github.com/ivylikethevine/say-hi/issues/new?template=bug_report.yml)           |
| A setting, flag, or target hi should gain | [The feature request form](https://github.com/ivylikethevine/say-hi/issues/new?template=feature_request.yml) |
| Anything exploitable                      | Privately, per [SECURITY.md](SECURITY.md#reporting-a-vulnerability) - never a public issue or discussion     |
| A conduct problem in any of the above     | Privately, per [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md#enforcement)                                          |

## What to include

hi runs on two machines at once, so the useful report says which end
misbehaved, and `hi --doctor --json` answers most of that on its own:

```sh
hi --doctor --json            # the machine you typed `hi` on
hi --doctor --json <target>   # add this when the problem is on the far end
```

Along with it: the exact `hi` command, what you expected, and what you saw
instead. Redact hostnames and usernames freely; the versions, tiers, and sizes
are what matter. The bug report form asks for each of these.

## What to expect

say-hi has one maintainer, working on it in their own time
([GOVERNANCE.md](GOVERNANCE.md)). Questions and issues are read and answered
as time allows, with no guaranteed turnaround; a report with the doctor output
attached is the fastest one to act on. Security reports are the exception,
with the acknowledgement and fix targets in
[SECURITY.md](SECURITY.md#what-happens-to-a-report).
