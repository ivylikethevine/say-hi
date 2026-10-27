# Simplify `packaging/`

## Context

`/simplify packaging` asked for a cleanup review of `packaging/` (16 files,
about 2,000 lines). It reviews the directory, not a diff. Each finding is
numbered and nothing is applied until findings are picked by number. The
review was done in a single context with no agents, per the session's agent
limits. Each finding says what gets deleted and which test pins the current
behavior.

## Findings

1. **Remove the stale "checkout must be named say-hi" workarounds
   (altitude).** `scripts/install.sh` locates the tree from its own path and
   copies from `$_HI_ROOT/$item`, under any checkout name (GLOSSARY: HI.33;
   added in e9df00f3 on 2026-10-16). The workarounds predate that change (the
   `staged_launcher` shim was added in 71bf8c5d on 2026-08-15), so:
   - `packaging/mkpkg.sh`: delete `staged_launcher` (lines 27-42) and call
     `"$_HI_ROOT/scripts/install.sh"` directly. Drop the shim test at
     `tests/packaging/packaging_ci_mkpkg_test.sh:420` and its registration at
     `:729`.
   - `packaging/aur/say-hi/PKGBUILD`: drop `prepare()` and use
     `$srcdir/$pkgname-$pkgver` in `package()`.
   - `packaging/aur/say-hi-git/PKGBUILD`: drop the `say-hi::` alias and its
     comment, and use `$srcdir/$pkgname`. The pinning test is
     `tests/packaging/packaging_ci_test.sh:277-281`.
   - `packaging/nix/package.nix`: drop the `postUnpack` rename.

   The installed name stays as it is: `/usr/share/say-hi` and
   `libexec/say-hi` are still how `$_HI_HOME/say-hi` resolves. The AUR and
   nix recipes ship to users, so picking those two is a recipe change, not
   only a cleanup. The `src_tarball` prefix stays `say-hi-<version>/`.

2. **`packaging/stamp.sh` sources the shared helpers (reuse).** Its header
   says sourcing `lib.sh` would abort outside a checkout named say-hi. That no
   longer holds: `lib.sh` sources `$_HI_ROOT/common/core.sh` from its own
   path. Have it source `packaging/lib.sh`, then delete:
   - its `rewrite` copy (lines 99-113). `_hi_rewrite`, through
     `_hi_write_back`, also writes back with `cat` and restores the mode, so
     the exec bit survives.
   - the hand-written value guard (lines 45-51), replaced by finding 3's
     helper.
   - the standalone paragraph in the header.

   No test matches `stamp.sh:` message text. To confirm at apply time:
   `core.sh` has no top-level step that needs a home directory or a tty in the nix
   sandbox or the Homebrew build. Pick this together with 1.

3. **Replace `_hi_need_value` and the `--*=*` split with
   `_hi_flag_word_or_die` (reuse).** `_hi_flag_word` already handles
   `--x=y`, and returns 2 when the caller must shift
   (`tests/test_runner.sh:374` uses the same pattern). This deletes
   `packaging/lib.sh:53-67` (the function and its comment, which argues it
   can't be done) and the split line in `bump.sh`, `mkpkg.sh` and
   `mkrepo.sh`. Each value flag becomes
   `--x | --x=*) _hi_flag_word_or_die VAR "--x requires a value" "$@" || shift ;;`,
   with `_HI_ME` set per script. The tests match `*"requires a value"*`
   (`packaging_ci_mkpkg_test.sh:392,455,673`), so the message is unchanged.

4. **Check whether the nfpm apk workaround is still needed.**
   `packaging/nfpm/nfpm.yaml:64-102` works around a directory-mode bug in
   nfpm 2.47.0, but `tools.txt` now pins 2.48.0. If 2.48.0 fixed it, the two
   per-packager tree entries and seven apk globs become one tree entry. This
   couldn't be checked from here (the release-notes lookup was denied). At
   apply time, build the apk and have `mkrepo.sh`'s `apk index` accept it;
   if it doesn't, update the comment to name 2.48.0.

5. **Smaller simplifications.**
   - `packaging/bump.sh`: `rewrite_srcinfo_lines`'s optional `url` fallback
     (line 180) exists only for `packaging_ci_mkpkg_test.sh:173`. Make the
     argument required and have the test pass it.
   - `packaging/bump.sh`: inline the single-use `_hi_nonempty_match`.
   - `packaging/mkrepo.sh`: SHA256 is computed two ways: `sha256_of` at
     line 208 and `dgst_of sha256` in `release_hashes`. Use `dgst_of` for
     all three digests in `build_apt`.
   - `packaging/mkrepo.sh` `deb_control`: the three arms repeat the
     `tar -x … && cat` tail. Pick the decompressor (`gzip -dc`, `xz -dc`,
     `cat`) in the `case`, then run one pipeline.
   - Rejoin comments split mid-sentence: `packaging/lib.sh:2-4`,
     `packaging/mkrepo.sh:10-12` and `:48`, and `packaging/stamp.sh:16-17`
     and `:100-102` (that last one goes away with 2).

Not proposed:

- the three copies of the locator, which the package boundary requires and
  which are documented.
- the HI.06 source guards.
- the formula's contents list, which tests check against install.sh's.
- `srctar.sh`. `release.yml:366` runs it as an entry point and never sources
  `lib.sh` there, so it is what keeps `git archive` out of the YAML.

## Verification

Per the working rules, no suites are run from the session. After applying,
the user runs:

- `npm ci --prefix .github`, if not already done.
- `_HI_HOME="$(dirname "$PWD")" tests/test_runner.sh --group fast`, then
  `--group lint`.
- `tests/test_runner.sh` with the packaging suites
  (`tests/packaging/packaging_test.sh` and the `packaging_ci_*` suites).
- For 1 and 2, `packaging/mkpkg.sh --stage-only` from a checkout not named
  say-hi.
- For 1, `makepkg` on an Arch machine and `nix build` (or CI's runs of them).
- For 4, `packaging/mkpkg.sh` followed by `packaging/mkrepo.sh`.
- `typos --config .typos.toml` over the touched files.

## Outcome

All five applied, except:

- 1: the `-git` PKGBUILD keeps `$srcdir/say-hi`, because makepkg names a git
  clone after the URL, not after `pkgname`, so dropping `say-hi::` changes no
  path. The pinning test now checks that each PKGBUILD runs install.sh from
  the directory its source unpacks to.
- 4: nfpm 2.48.0's apk has 0755 directory modes. `apk index` and the Alpine
  install were not run here: docker is not reachable from the session, so
  `ci.yml`'s `packaging-smoke` job is the proof. The apk-copy tests are
  removed along with the copy.
- 5: `_hi_nonempty_match` stays. `_hi_manifest_check` runs its predicate as
  one command, so an inline `&&` would escape it.
