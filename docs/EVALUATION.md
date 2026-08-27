# Evaluation: would a senior sysadmin adopt hi?

A review of the `dev` tree at 33e23eb (2026-08-26), written from the seat of
someone who administers a fleet of servers, containers and clusters and is
deciding whether `hi` gets onto their workstation and, by extension, onto
every box they touch. Findings are ranked within each section; each carries
where it lives in the code and what would change the verdict. Compliments are
kept to the last section because they are not what a decision needs.

**Short verdict:** staging yes, production not yet. The transport work is
genuinely good and the test discipline is well above the genre, and the
security findings that blocked the first pass have been fixed (git history is
the ledger). What remains is usability and customizability: a chatty connect,
no backend override, no `--plain`, and shipped aliases that cannot be turned
off as a set.

## Contents

- [Usability](#usability)
- [Design](#design)
- [Customizability](#customizability)
- [What is actually good](#what-is-actually-good)
- [What would change the verdict](#what-would-change-the-verdict)

## Usability

### U3. The connect is chatty and the failure mode is worse

A default connect prints a size, a copy time, a load time, the greeting
("only bash today :("), a three-row header with UTC/local/version, sysinfo,
and a package check; the disconnect prints a size, a duration, a second
banner and a timestamp. Every one is a toggle; none is off by default. An
admin connecting forty times a day wants `user@host $`. Conversely, when
something goes wrong, `hi failed [code: 255]` followed by the whole captured
stderr arrives after the fact with `\r\r\r\r` in front of it.

### U4. The package check runs ~100 `command -v` probes on every connect

`settings/packages` lists roughly a hundred names; `full_check` walks them
at each header. On a fast box it is tens of milliseconds; on a busy or
NFS-homed box it is the visible pause before the prompt. It is also a
strange thing to see on a production server ("✗ btop ✗ gping ✗ httpie"). A
sysadmin would want this at most once per host, cached, or off.

### U5. Backend resolution has no override

Resolution is `~/.ssh/config` Host → docker → podman → nomad → kube → plain
ssh (`hi.sh:995-1002`). A container named `web01` shadows a DNS host `web01`
not in `~/.ssh/config`, and there is no `hi --ssh web01`, `hi docker:web01`,
or `_HI_BACKENDS=ssh` to say which one was meant. The kube grammar already
has prefixes (`ns:pod`); extend the idea to the backend.

### U6. `/tmp` on the target must be writable and `$HOME` must exist

A pod with a read-only root filesystem and no writable `/tmp`, or a
distroless image with no `$HOME`, fails with "failed to copy say-hi into
[pod]" and stops (`hi.sh:809-814`). `kubectl exec -it pod -- sh` would have
worked. There is no `--plain`/`--no-payload` to say "just get me a shell".
The no-bash fallback proves the plumbing exists; it is not reachable on
purpose.

### U7. Good, and worth keeping

The picker on bare `hi`, backend-tagged completion shared by three shells,
`--doctor --json`, `--check-configs` validating the rc files with each
shell's own parser before writing, and the install taking a `.hi-orig`
backup. These are the parts of the usability story that are done right.

## Design

### D1. The complexity budget is spent on the wrong things

`hi.sh` is 1140 lines that build a POSIX script out of nested heredocs, each
with three armored streams inside, then substitute a size token back into
the script it measured (`_hi_wire_bytes`, HI.44). The payload has its
comments stripped by an awk program that parses shell heredocs with a regex
(`_hi_strip_awk`, `hi.sh:180-206`) to get the gzipped tar from 66KB to 33KB —
so what runs on the target is a transformed copy of what was reviewed, and a
comment-looking line inside a multi-line string would be silently deleted.
Over ssh, 33KB is not a number that buys this. Ship the reviewed bytes.

The glossary has 45 numbered idioms (`docs/GLOSSARY.md`, HI.01–HI.45) and
the code carries 82 `GLOSSARY:` back-references. That is a well-kept map of
a large surface, and the honest reading of it is that the surface is too
large for what the tool does: copy a directory and start a shell.

### D2. bash 3.2 as the floor shapes everything

No associative arrays, no `mapfile`, no namerefs — so tables are `|`-joined
strings read back with `IFS='|' read` (`_HI_SHELL_TABLE`, `_HI_BACKENDS`,
`_HI_TRIM_TABLE`, `common/flags`), arrays are filled through `eval`
(`_hi_read_lines`, `core.sh:312-318`), and every toggle is defaulted via
`eval ": \"\${$_hi_t:=0}\""`. The evals take fixed names and are safe; the
cost is that every reader has to check that each time. The floor exists for
the macOS _client_ (bash 3.2 as `/bin/bash`). Homebrew bash is the norm on
any admin's Mac, and a `#!/usr/bin/env bash` already picks it up. Requiring
bash 4 on the client and keeping the 3.2 floor only for what runs on the
_target_ would remove most of the eval and half the table plumbing.

### D3. `settings.sh` has two parsers

It is sourced as shell by `core.sh:224-226` and read as data by
`_hi_setting_get` (`core.sh:511-537`), which understands exactly
`export NAME=value` and `export NAME='value'`. HI.36 explains why (the file,
not the environment, decides what ships). The consequence is that a
perfectly valid `export _HI_DISABLE_OSC52=$((1))` or a `_HI_DISABLE_OSC52=1;
export _HI_DISABLE_OSC52` is honoured by one reader and invisible to the
other. A settings file that is data should be data (`key=value`, one
reader); one that is shell should be sourced once and the result inspected.

### D4. Two independent cleanup paths

`trap 'rm -rf $_HI_CLEANUP' exit` in the bootstrap and `_hi_on_exit
clean_all` in `load.sh` (SECURITY.md calls this belt and braces). Two paths
that can each fire without the other is also two paths that can each
_fail_ without the other noticing, and the opt-in rc graft (`_HI_GRAFT_RC`)
is only undone by one of them. One owner, one trap.

### D5. The fallback ladders are the best part of the design

`_HI_SHELL_TREE` as the single ordering (`core.sh:279`), the ladder probe
interpolated into both transports, the fish/zsh/sh arms of the fallback rc
constrained to a three-shell subset, `_hi_shquote` as the one quoting
function — these are the right shapes. The 4-shell/3-shell/POSIX dialect
constraints stated at the top of each file, and enforced by the lint suite,
are unusual discipline for a shell project.

### D6. Tests: strong on breadth, with one blind spot

Unit, lint (shellcheck, shfmt, checkbashisms, a bash-4 grep, doc drift), e2e
over five real backends, a real bash 3.2 target, a dash sweep, a disconnect
test. Very few shell projects have this. One blind spot remains: what a hard
kill mid-rewrite does to a grafted `.bashrc` (the disconnect test checks that
cleanup happens, not that the rc survives every instant it could be
interrupted). It matters less now that the graft is opt-in.

## Customizability

### C1. Shipped aliases and exports cannot be turned off as a set

`settings/aliases.sh` unconditionally sets `EDITOR`, `IDE`, `EZA_CONFIG_DIR`,
`GCC_COLORS`, and defines `l`, `le`, `lr`, `lsx`, `now`, `zed`, `micro`, `sudo`
and a dozen more. The user's `aliases.sh` runs last and can override any one
of them, but there is no `_HI_DISABLE_ALIASES` and no way to ship _only_ the
user's. Clobbering `EDITOR` on a target where the admin deliberately set it
is the one most people will hit first. (`_HI_DISABLE_BAT_ALIAS` covers `cat`,
which is the right idea applied to one alias.)

### C2. The prompt is a shape, not a template

What can change: the end character per shell, the colours per host/user/tag,
starship deference. What cannot: the order of user/host/cwd, whether the
cwd is there, the git segment's format, anything after `\w`. Anyone with a
prompt they like will set `_HI_DISABLE_PROMPT=1` and use their own — at
which point the per-host colour hashing, which is hi's best idea, is gone
too. Expose the colour escapes as variables the user's own `PS1` can use
(they already exist: `_hi_host_escape_var`), and document that path.

### C3. The header is toggles, not layout

`_HI_HEADER_TIMESTAMP`, `_HI_HEADER_SYSINFO`, `_HI_HEADER_IDENTITY`,
`_HI_HEADER_GHZ`, `_HI_HEADER_CHECK` turn rows on and off. No row can be
added, and the "one-line header" most admins would actually want is not a
combination of them.

### C4. What is good here

The overlay model — a directory outside the checkout, one file overriding
one file, `--overlay-init` putting it under git, per-file `_HI_COLORS`
relocation — is right. Presets in `--configure` and a wizard that previews
what each answer decides are more than most tools bother with. The
`packages` priority tiers are a neat design for the one feature that should
probably be off.

## What is actually good

- Transport coverage is real: ssh with an installed-tree fast path, docker,
  podman, nomad (with tasks), kube (with context/namespace/container
  grammar), Windows fallback. The multiplexed single-auth probe is clever
  and correct.
- Cleanup on abrupt disconnect is tested, not assumed.
- The three-shell fallback subset (`aliases.sh` parses in sh, zsh _and_
  fish) is hard to get right and is enforced by tooling.
- `--doctor --json`, `--check-configs`, the `.hi-orig` backup and the
  pre-write syntax validation are what a careful operator wants from an
  installer.
- The AI-usage statement is honest and the code's comment density shows a
  maintainer who understands it. The docs are voluminous but they are
  _correct_ — every claim checked in this review matched the code, which is
  rarer than it should be.

## What would change the verdict

In order of how much each moves a "no" toward a "yes":

1. `--plain` / `_HI_BACKEND=` overrides (U5, U6), and `_HI_DISABLE_ALIASES`
   (C1).
2. Ship the reviewed bytes; drop the comment stripper (D1).

With these done, this is a tool an admin could run against production
without explaining themselves.
