# Docs and comments pass

Status: done in the working tree, uncommitted, awaiting the closing loop
(`--group fast`, `--group lint`), which no session runs. Delete this file once
that passes and the work is committed.

Goal: simpler, shorter, deduplicated docs and code comments. Each fact keeps
one home and every other mention is a sentence and a link. Net negative lines.

## User docs

- [x] 1. README _Installation_: the install channels only; the flag tour goes
      to USAGE.md.
- [x] 2. README and GETTING-STARTED: one "what hi is" and one first install
      (README); GETTING-STARTED starts at its word list.
- [x] 3. README _Target Requirements_: badges and a short summary; the detail
      is COMPATIBILITY.md's.
- [x] 4. One overlay table, FILES.md's; SETTINGS.md links to it.
- [x] 5. What a session writes on a target: HOW-IT-WORKS keeps the mechanics,
      SECURITY a short list of guarantees.
- [x] 6. Kept session and the hold: INTEGRATIONS _Terminal multiplexers_ is the
      home; elsewhere one sentence and a link.
- [x] 7. SETTINGS.md's old-shape conversion detail moves to
      `scripts/convert_settings.sh`'s header.
- [x] 8. `scripts/settings` rows cut to one sentence each.
- [x] 9. SETTINGS _Not settings_ keeps the names a user can use; the rest go
      to FILES.md.
- [x] 10. Short sentences across SETTINGS, INTEGRATIONS, COLORS,
      COMPATIBILITY, SECURITY.
- [x] 11. `docs/README.md` index cells cut to a few words.
- [x] 12. USAGE.md generator: no "No image" boilerplate; the in-session flags
      listed once.

## Code comments

- [x] 13. A comment with a `GLOSSARY: HI.nn` tag says what the code does in a
      line; the why stays in the glossary.
- [x] 14. Remaining long block comments: one sentence per reason. Shellcheck
      directives and trap warnings stay.
- [x] 15. GLOSSARY.md entries: reason first, overlaps merged.

Items 13 and 14 covered every comment block of six or more lines in the
shipped tree (`hi.sh`, `load.sh`, `common/`, `scripts/`) and the harness
(`tests/lib/`, `tests/test_lib.sh`, and `tests/test_runner.sh`'s blocks of
seven or more); `scratch/comment_blocks.sh -n 6 <files>` lists what is left.
Suites' own per-case comments were not part of it. Each file was checked with
`bash -n` (and `zsh -n`, `dash -n`, `fish -n` where those shells read it) and
`shellcheck -x`.

Item 15 goes through `docs/GLOSSARY.md` longest entry first, replacing whole
sections (codes and headings unchanged, so every tag still resolves). Done: the
nineteen entries of 36 lines or more (HI.65, HI.57, HI.50, HI.32, HI.63,
HI.41, HI.62, HI.33, HI.61, HI.19, HI.59, HI.47, HI.67, HI.54, HI.46, HI.43,
HI.26, HI.64, HI.13); the shorter ones are as they were. No entry is merged:
a merge would retire a code and move its tags.

## Constraints

- Generated text changes at its source: `## Contents` lists and the settings
  table (`.github/prettier-plugin-docs.mjs`, `scripts/settings`), USAGE.md
  (`common/flags`, `docs/tapes/usage`).
- Test-read doc text: SETTINGS.md's `## Presets` first column and
  `### Not settings` names, PACKAGING.md's checksum and key lines, README's
  payload badge, `docs/hi.1`, `docs/tldr.md`, every `GLOSSARY: HI.nn` tag's
  heading.
- Each touched doc passes prettier with the docs plugin, markdownlint, and
  typos.
