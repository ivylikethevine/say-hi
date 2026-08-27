# Evaluation: would a senior sysadmin adopt hi?

A review of the `dev` tree at 33e23eb (2026-08-26), written from the seat of
someone who administers a fleet of servers, containers and clusters and is
deciding whether `hi` gets onto their workstation and, by extension, onto
every box they touch. Findings are ranked within each section; each carries
where it lives in the code and what would change the verdict. Compliments are
kept to the last section because they are not what a decision needs.

**Short verdict:** not on production hosts, not yet. The transport work is
genuinely good and the test discipline is well above the genre, but the
default session _writes to the target's rc files_, _throws away shell
history_, _hides the ssh login banner and host-key fingerprint_, and puts a
`/tmp` directory on `PATH`. Each is fixable and most are one flag away, but
the defaults are the product, and these defaults are wrong for the audience
the README courts ("every host you touch").

## Contents

- [Security](#security)
- [Usability](#usability)
- [Design](#design)
- [Customizability](#customizability)
- [What is actually good](#what-is-actually-good)
- [What would change the verdict](#what-would-change-the-verdict)

## Security

> **Status (2026-08-26): S1-S4 and S6-S9 are fixed; S5 is deferred with a
> reason.** Each heading below carries its outcome. One finding's *reasoning*
> was wrong even though its conclusion held - see S2, which is worth reading
> before trusting the rest of this section's confidence.

### S1. FIXED. ssh's stderr is swallowed for the whole connect — banners and fingerprints included

`_hi()` wraps the entire connect in `{ ... } 2>"$tmp"` (`hi.sh:993-1003`)
and only prints the file back if the exit code is non-zero. Everything ssh
says on stderr during a _successful_ session is therefore never shown:

- the server's `Banner` (the legal/acceptable-use notice regulated
  environments are required to display — it goes to stderr);
- `Warning: Permanently added ... to the list of known hosts`;
- the host-key fingerprint block on first contact. The `yes/no` prompt
  itself still appears (ssh reads it from `/dev/tty`), but the fingerprint
  the user is supposed to compare against is on stderr. hi turns trust-on-
  first-use into trust-blind. The first ssh call (`hi.sh:687-688`) adds its
  own `2>/dev/null` on top.

_Fix:_ do not redirect ssh's stderr. Capture hi's own diagnostics through a
function that writes to `$tmp`, and let the transport talk to the terminal.

**Done:** the `2>"$tmp"` around the connect is gone, as is the `2>/dev/null` on
both ssh calls — including `_hi_remote_root`, which is the one that opens the
ControlMaster and therefore the one carrying the banner and the fingerprint.
Every backend probe already silenced its own daemon chatter, so almost all of
what that redirect caught was the transport's. `$tmp` survives for the
container arm, which still files specific commands' stderr, and the failure
report prints it only when it is non-empty.

### S2. FIXED (and my reasoning here was wrong). The session edits the target user's real rc files, on every connect

`load.sh`'s `configure_files` appends a `# hi-config-start … # hi-config-end`
block to `~/.bashrc`, `~/.zshrc` and `~/.config/fish/config.fish` _on the
target_ and `clean_all` strips it on exit (`load.sh:50-86`). That is a write
to dotfiles on a production host every time someone says hello, which:

- races other writers (the rewrite is `sed > tmp; cat tmp > rc` —
  `core.sh:466-474` — not atomic, so a dropped connection mid-`cat` can leave
  a truncated `.bashrc`; the disconnect test checks that cleanup _fires_, not
  that the file survives a kill at the wrong instant);
- is visible to every other login on a shared account (`deploy`, `ubuntu`,
  `root`) for the duration of the session, and to file-integrity monitoring
  (AIDE, Wazuh, osquery) as a modification of a watched file — twice per
  session, per host, per admin. A SOC will ask about it;
- leaves the block behind on a hard kill of the `sh` running the bootstrap
  before `load.sh`'s trap is armed, or when `rm -rf $_HI_CLEANUP` fires but
  `clean_all` does not (the two cleanup paths are independent, as
  SECURITY.md says — which also means they can disagree).

The block is wrapped in a guard (`_hi_rc_guard`, `core.sh:264-272`) so a
stray one is inert, which limits the blast radius but not the audit noise.

_Fix:_ don't graft. Nested shells can be reached without touching `$HOME`:
`BASH_ENV`/`ENV` for sh-likes, `ZDOTDIR` for zsh (already used on the
fallback path, `hi.sh:584`), `XDG_CONFIG_HOME` for fish. Make grafting the
opt-in for the one case (tmux started inside the session) that needs it, and
say so in the header.

**What was actually done - and where the paragraph above was wrong.** The
conclusion held, but the sentence "the session itself never needed it" was
false, and the review should not have asserted it. `bash --rcfile` in
`hi.sh` starts the *bootloader*; the shell the user types at is started by
`load()` a step later, and it was a bare `$shell -i`, which reads
`~/.bashrc`. The graft was therefore how hi's prompt and aliases reached
**the session itself**, not merely a bystander shell. Making it opt-in on the
strength of this paragraph alone produced sessions with no prompt, no aliases,
and `hi: command not found` inside them - caught by
`tests/targets/ssh_relay_test.sh`, not by the reasoning.

So the graft was made opt-in (`_HI_GRAFT_RC`, default 0) *and*
`load.sh` gained `_hi_session_rc_setup`, which writes one rc per shell into a
scratch directory of hi's own and starts the session shell against it
(`--rcfile` / `ZDOTDIR` / `fish -C`), each sourcing the target's own rc first
so the host's config still applies underneath. `$ZDOTDIR` and `$ENV` are
exported, so nested zsh and sh/dash/ash inherit hi's config for free; bash and
fish get a wrapper in `settings/aliases.sh`. Documented as
[HI.46](GLOSSARY.md#hi46-session-rc-directory).

The lesson worth keeping: this review read `hi.sh`'s handoff and assumed it was
the session's shell. A claim about which process reads which rc file is
checkable in a container in about a minute, and this one was not checked.

### S3. FIXED. Command history is discarded by default

`common/history.sh` points `HISTFILE` into a `mktemp -d` that is removed on
exit, for every bash/zsh/fish session hi lands. On a server that means the
admin's commands vanish from `~/.bash_history` — the one record most shops
still fall back on when reconstructing "who ran what". Shell history is not
an audit control, but deleting it on the way out is what an attacker does,
and a tool that does it by default will be read that way. `_HI_DISABLE_HISTORY=1`
exists; the default is the wrong way round for the audience.

_Fix:_ default to the target's own history file; make the scratch-history
the opt-in ("leave nothing behind" mode), and name it honestly.

**Done:** `_HI_DISABLE_HISTORY` (default on) became `_HI_SCRATCH_HISTORY`
(default off). It could not stay in `core.sh`'s `_HI_TOGGLES`, whose polarity
is load-bearing in two places - `_hi_fallback_rc` exports the lot as `0` to
mean "hi's defaults", and `paths.sh`'s `_HI_DISABLE_LOCAL` gate sets the lot to
`1` to mean "off here" - so a second roster, `_HI_OPT_INS`, holds the settings
that ship off. `hi.sh`'s trim table grew an inverted row form (`!NAME`) so the
opt-in keeps `common/history.sh` off the wire until it is asked for.

### S4. FIXED. A `/tmp` directory goes on `PATH`

`_hi_restore_profile` ends with `export PATH="$PATH:$_HI_ROOT"`
(`load.sh:16`) where `$_HI_ROOT` is `/tmp/<user>.hi.XXXXXX/say-hi` on a
disposable session. It is appended, and the directory is 0700, so this is not
exploitable by another local user — but it fails every hardening baseline
that greps for `/tmp` in `PATH`, and it is there only so that `hi` can be
typed inside a session. An alias or function does that job.

**Done:** the line is gone, and `test_tree_is_never_put_on_path` pins it on
both the restore path and under the no-init guard. `paths.sh`'s
`alias hi="$_HI_LAUNCHER"` is what a session reaches the launcher through —
which only works because of the S2 rework above, since that alias arrives with
hi's rc.

### S5. DEFERRED, with the constraint written down. Sixty-odd `_HI_*` variables are exported into every process the session spawns

`env | grep -c '^_HI_'` in a session reports ~60 names (`_HI_CLEANUP`,
`_HI_ROOT`, `_HI_LOCAL_HOSTNAME`, the whole path roster from `paths.sh`).
They are inherited by everything launched from the shell — a service started
by hand, a `sudo -E`, a `systemd-run`, a cron entry pasted from the terminal.
Besides leaking the admin's workstation hostname and username into process
environments on the target, it makes `env` diffs useless and trips the
occasional program that validates its environment. The client side is the
same: the install wires ~60 exports into the local shell.

_Fix:_ export what child processes need (`EDITOR`, `VIMINIT`, maybe three
paths) and keep the rest as shell variables.

**Not done, and here is the blocker.** `common/paths.sh` is parsed by **fish**
as well as sh, zsh and bash, and that four-shell subset has no way to set a
variable *without* exporting it: `NAME=value` is not fish syntax and `set -g`
is not sh's. Every name in that file is exported because that is the only form
all four parse. Narrowing the set means splitting paths.sh into a per-dialect
pair that cannot drift — a new contract and a new drift check, not an edit —
so it is written down under
[Known, and not yet fixed](SECURITY.md#known-and-not-yet-fixed) and queued in
[ROADMAP.md](ROADMAP.md) rather than half-done here.

### S6. FIXED. `ControlPath` from `mktemp -u`

`_hi_ctl_open` (`hi.sh:346-351`) names the multiplex socket with `mktemp -u`
in `$TMPDIR` and hands it to `ControlMaster=auto`. `-u` is documented as
unsafe; with `auto`, an existing socket at that path is _used_, not replaced.
On a multi-user client with a shared `/tmp` and no `$XDG_RUNTIME_DIR`, the
window is tiny but the pattern is the one every hardening guide names.

_Fix:_ `ControlPath=~/.ssh/hi-%C` (the documented idiom), or a `mktemp -d`
directory with the socket inside it.

**Done:** the socket is now `"$(mktemp -d)/s"`. The short name is deliberate —
`ControlPath` goes into a `sockaddr_un` capped near 104 bytes and macOS's
per-user `$TMPDIR` already spends ~50 of them. A host with no writable temp
directory degrades to no multiplexing (two authentications) rather than no
session.

### S7. FIXED. The targets cache accepts a pre-existing, foreign-owned directory

`common/targets.sh:347-361` falls back to `${TMPDIR:-/tmp}/hi-$(id -u)`,
tries `mkdir -m 700`, and on failure `chmod 700` — silently. If another
local user created `/tmp/hi-1000` first, the `chmod` fails, `[ -d ]` passes,
and the completion cache and `write_cache`'s `$cache.$$` temp file land in a
directory they control. The content only ever becomes ssh/docker _names_,
so the impact is a poisoned picker, not code execution; but the check is
`-d` where it should be `-O` and a mode test, and a cache that cannot be
made safe should be skipped, not chmod'd at.

**Done, though not with `-O`:** `targets.sh` is the standalone-POSIX file (it
is what fish shells out to, and it runs on whatever `/bin/sh` a target has),
and `test -O` is a bash/ksh/zsh extension — the lint gate caught that
immediately. Ownership is read from `ls -ld`'s third column and compared
against both `id -un` and `id -u`, since a host with no passwd entry for the
caller prints a number. A directory that is not ours, or is a symlink, means
the cache is skipped and the backends are swept instead.

### S8. FIXED. What SECURITY.md gets right, and what it leaves out

The document is better than most projects of this size have: allow-listed
payload, no network calls, one string read back from the target and where
it goes. What it does not say:

- that rc files on the target are modified (S2) — "grafts hi's
  marker-delimited blocks onto the host's rc files" is one clause in
  "What runs where", and a reader scanning "Footprint" for _writes to
  `$HOME`_ will not find the words;
- that history is redirected and destroyed (S3);
- that `--update` is an unsigned `git pull` of `main` (no tags yet, so
  nothing to verify). Fine for a hobby install; say it;
- the overlay caveat ("treat every overlay file as public to every host
  you visit") is in SECURITY.md but the README's **IMPORTANT** box says only
  "is copied", which under-sells it. An `aliases.sh` with a token in it goes
  to every container the admin ever pokes.

**Done:** SECURITY.md gained a *What hi writes on a target* section — a table
of what lands where and when, with both opt-ins called out — plus the
unsigned-`--update` note, the `ControlMaster` and cache-directory rules, and a
*Known, and not yet fixed* heading carrying S5. The README box now says to
treat every overlay file as readable by every host visited, and states the
default that nothing is written to a target outside its own temp directory.

### S9. FIXED (the two that were real). Minor

- `_hi_cecho " no bash in [$DOMAIN] ... -> plain $fallback"` (`hi.sh:760`)
  prints a string a container produced (`$fallback`) to the client terminal
  unsanitised. Same class as any remote output; it just did not need to be.
  **Done, and it was worse than "printed":** `$fallback` is interpolated into
  `sh -c "... exec $fallback -i"` on the target a few lines later. It is now
  checked against `$_HI_SHELL_LADDER` — there is a fixed list of right answers
  — and a target that gives any other is refused rather than sanitised.
- `alias sudo="command sudo "` plus `alias cat="bat …"` means `sudo cat`
  runs `bat` as root. Harmless with `-P`, but a reviewer will pause at it.
  **Left alone deliberately:** the trailing space is the documented idiom that
  makes `sudo <alias>` work at all, and removing it breaks `sudo ll` and its
  siblings. Noted here rather than silently changed.
- `tar mxzf` from an untrusted-by-construction client into the target is
  fine; `tar x` of the _overlay_ into `$_HI_ROOT/config` without `--no-same-
  owner`/`-p` awareness is fine as non-root; as root it preserves nothing
  surprising because the archive was built by the same user. No finding,
  noted so the next reader does not re-derive it.

## Usability

### U1. `hi host cmd` is not `ssh host cmd`, though `--help` says it is

`_hi_parse` turns the trailing words into `CMDARG="cmd; exit"` and runs it
_inside the interactive rc_ on a pty (`hi.sh:399`, `hi.sh:908`). So:

- the connect banner, header and "hi loaded with…" line go to **stdout**
  ahead of the command's output — `hi web01 uptime | awk` gets the banner;
- there is always a tty, so programs that check `isatty` behave as
  interactive, and binary output is mangled by the pty;
- `ssh host` with a command never touches rc files; this does.

`--help` says "With [command …], runs that instead, the way ssh does." It
does not. Either make the command form `exec ssh "$@"` verbatim (no payload,
no pty) or document it as "runs the command in a hi session" and keep the
banner off stdout.

### U2. macOS client → Linux target lands in the PowerShell fallback

`boot_tmp="$(mktemp -u -t hi.boot.XXXXXX)"` (`hi.sh:682`) is resolved on the
_client_ and then used as the path of a `mkdir -m 700` (no `-p`) on the
_target_. With `$TMPDIR` set — every macOS login shell, and any Linux user
who sets it — the path is `/var/folders/…/T/hi.boot.XXXXXX`, which does not
exist on the target, the `mkdir` fails, and `_say_hi` falls into the branch
that runs `powershell` on a Linux server. Verified locally:
`TMPDIR=/var/folders/zz/T mktemp -u -t hi.boot.XXXXXX` →
`/var/folders/zz/T/hi.boot.oMwdRu`. The macOS e2e workflow only connects to
`127.0.0.1`, where the directory happens to exist, so CI cannot see it. The
container path already does this right ("a literal /tmp: created inside the
container", `hi.sh:751`); the ssh path needs the same.

### U3. The connect is chatty and the failure mode is worse

A default connect prints a size, a copy time, a load time, the greeting
("only bash today :("), a three-row header with UTC/local/version, sysinfo,
and a package check; the disconnect prints a size, a duration, a second
banner and a timestamp. Every one is a toggle; none is off by default. An
admin connecting forty times a day wants `user@host $`. Conversely, when
something goes wrong, `hi failed [code: 255]` followed by the whole captured
stderr (S1) arrives after the fact with `\r\r\r\r` in front of it.

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
_fail_ without the other noticing, and the rc graft (S2) is only undone by
one of them. One owner, one trap.

### D5. The fallback ladders are the best part of the design

`_HI_SHELL_TREE` as the single ordering (`core.sh:279`), the ladder probe
interpolated into both transports, the fish/zsh/sh arms of the fallback rc
constrained to a three-shell subset, `_hi_shquote` as the one quoting
function — these are the right shapes. The 4-shell/3-shell/POSIX dialect
constraints stated at the top of each file, and enforced by the lint suite,
are unusual discipline for a shell project.

### D6. Tests: strong on breadth, with two blind spots named above

Unit, lint (shellcheck, shfmt, checkbashisms, a bash-4 grep, doc drift), e2e
over five real backends, a real bash 3.2 target, a dash sweep, a disconnect
test. Very few shell projects have this. The two things it did not catch are
the two that matter most to this reviewer: the `$TMPDIR` cross-platform path
(U2 — loopback-only macOS CI) and what a hard kill mid-rewrite does to the
target's `.bashrc` (S2 — the disconnect test checks that cleanup happens,
not that the rc survives every instant it could be interrupted).

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

1. Stop swallowing ssh's stderr (S1). Banners and fingerprints reach the
   terminal.
2. Stop grafting rc files on the target by default (S2); make it the
   opt-in for tmux-inside-a-session.
3. Keep the target's own history by default (S3); rename the scratch mode.
4. Fix `boot_tmp` to be a target-side path (U2) and add a non-loopback
   macOS→Linux case to CI.
5. Make `hi host cmd` either exactly `ssh host cmd` or honestly documented
   as something else, with nothing on stdout that the command did not
   produce (U1).
6. `--plain` / `_HI_BACKEND=` overrides (U5, U6), and `_HI_DISABLE_ALIASES`
   (C1).
7. Take `$_HI_ROOT` off `PATH` and cut the exported variable set to what
   children need (S4, S5).
8. Ship the reviewed bytes; drop the comment stripper (D1).

With 1–4 done, this is a tool an admin could run against staging without
explaining themselves. With 5–8, against production.
