# Whole-repo simplify pass

Status: paused for a suite run. Ticked items are in the working tree, unrun; the
unticked ones are open, and items 44, 45, 46, 70 and 71 are partly done (below).
No suite is run from a session, so the closing loop goes to the maintainer.

Partly done: 44 has all but `_hi_ctl_case`; 45 has 11 cases on `_hi_refused`, the
packaging sites assert a nonzero exit and stay; 46 has the helper only; 71 has
`ci.yml:777`, `coverage.yml:471` and the docs plugin; 70 has `setup-shells` only.

Also decided against: 57 (twin counters fold into `bad`, and a wrong tally in a
lint gate is the worst place to find out), 70's `session_verdict.sh` (Windows-only
paths, verifiable only on a CI round trip).

Behavior stays as it is unless an item says otherwise. No new `eval` or kin, the
bash 3.2 floor holds, a failing case keeps its reason, and nothing adds a fork or
capture on a test's passing path.

Decided against, each changing behavior or losing a pin: 23 (exports all of
`hi.keep` on the hold path); 29's `<on>` field (ten pinned patterns, no runtime
gain); 32's `doctor_row` under `--problems` (`_hi_state_row` writes rows directly,
which would then draw); 40's `setting_value` memo (it would turn reads into
answers); 44's `rm -f settings.sh` in `paths_test.sh` (it removes a file the
fixture wrote).

## Possible bugs

- [x] 1. `hi.sh:308`: a bare `cat` reads stdin when a site settings file exists
      and no tag file does. Guard it on the array's length.
- [x] 2. `scripts/pack.sh:491`: `_hi_ssh_tags_file` recuts and moves `hi.ssh_tags`
      on every lookup when the ssh config has an `Include`; that file is in
      `cache_also`, so the overlay cache stays cold. Replace only on a change.
- [x] 3. `tests/scripts/preview_packages_test.sh:121,307`: assign shared output
      through `_hi_shared_out`.
- [x] 4. `tests/scripts/doctor_target_test.sh:221`: a bare `return 1` gets a reason.
- [x] 5. `tests/common/header_whole_test.sh:504-608`: `vscode` names no scheme,
      the "24-word" case passes `$_HI_TEST_SCHEME48`. Fixed with item 61.

## Shipped: dead code and leftovers

- [x] 6. `hi.sh:1518-1529`: delete the warm subshell, its `wait`, and "warm below"
      at 1511. If a miss's stderr can surface, keep the subshell's redirect in the
      foreground.
- [x] 7. `scripts/pack_stream.sh:290-300`: delete `_hi_overlay_bytes`.
- [x] 8. `scripts/pack.sh:172-174,376,380-381`, `scripts/pack_plugins.sh:97-98`:
      drop `_HI_PLUGIN_GEN` and `_HI_OVERLAY_INDEX_GEN`; reset `_HI_OVERLAY_INDEX=""`
      in the plugin load and test `-z` (a built index holds at least a newline).
- [x] 9. `scripts/configure_menu.sh:326-336`: drop `_hi_menu_rows`, call
      `_hi_menu_row` at 428-429, drop `configure_test.sh:695-702`.
- [x] 10. `common/config.fish:591-595`, `common/zsh.zsh:292`: source the overlay
      with the plain test-and-source shape, delete both comments.
- [x] 11. `load.sh:77-80`: stand-in becomes `return 1`; drop the limit from
      `load_session_test.sh:459`'s expected string.
- [x] 12. `common/targets.sh`: inline `plugin_tables` (161-166) in the
      `--disable-plugin` arm; inline `scratch_dir` (298-304) at 389; one
      `_hi_ns` default at the top of `kube_rows` (471-476); fix the header (19-22).
- [x] 13. `common/header.sh:426-428` (double validation), `:203,230` (unread print
      in `_hi_header_version`, plus `configure_preview.sh:64`, `header_test.sh:288,291`),
      `common/core.sh:757-758` (redundant primes).
- [x] 14. `common/header.sh:854-858`: delete the orphaned comment.
- [x] 15. `scripts/pack_scan.sh:108-109`; `scripts/install.sh:57-59`; one-line
      HI.05 notes at `common/env_prompt.sh:52-54`, `common/git_prompt.sh:13-17`.
- [x] 16. `hi.sh:1895` guard, its test `parse_help_test.sh:602-610,678`; `hi.sh:1041,1047`
      move `handoff=` into the branch; `hi.sh:1216-1218` call `_hi_wire_done`;
      `hi.sh:859` `_hi_out`; `hi.sh:1633-1636,970` `_hi_list_has`;
      `common/keep.sh:491-500` drop `probes`.
- [x] 17. `hi.sh:233-243,910-917`: spell the format literals; fix comments at
      193, 232, 907; drop the test at `remote_test.sh:318-325`.

## Shipped: reuse and duplication

- [x] 18. `scripts/pack_plugins.sh:481-488`: drop `_hi_hook_off`; call
      `_hi_plugin_switched_off` at `pack.sh:288,704` and in the scripts library (`_hi_hr_n`); move its note.
- [x] 19. `common/git_prompt.sh:147-153`, `common/env_prompt.sh:128-141`: tail is
      `_hi_opts_restore`; `_hi_out "${1:-}" "($_hi_out) "`; source `$_HI_CORE` first
      in `env_prompt_test.sh:124`.
- [x] 20. `scripts/doctor_target.sh:15-38`: `arms=("ssh|ssh host||_hi_is_ssh_host"
"${_HI_BACKENDS[@]}")`; `:144-162`: one chain on `_hi_list_has`.
- [x] 21. `scripts/add_package.sh:105-130`: inline at 144 and 164.
- [x] 22. `common/targets.sh:544-554,571-586`: flatten the age check, one cleanup
      in `write_cache`.
- [ ] 23. `common/keep.sh:358-386`: move the `_hi_mux_here` check below the export
      loop; `_hi_keep_hold_here` reads `$_HI_KEEP_AS`.
- [x] 24. `hi.sh:121-129`, `scripts/pack_stream.sh:305-314`: one `printf -v` after
      the fallback chain.
- [x] 25. `hi.sh:1572-1595`: one early-exit block; hoist the errlog line above 1587.
- [x] 26. `scripts/preview.sh:192-201`: `_hi_colors_names hostname | grep '[*?]' || true`;
      `:281-302,371-374`: keep keys and escapes only, outvar with a prefixed name.
- [x] 27. `common/header.sh:70-85` and the scripts library's copy: `_hi_term_cols` in
      `core.sh`; the tput memo stays in `_hi_draw_width`.
- [x] 28. `scripts/configure.sh:224-229`, `configure_menu.sh:838`: `_hi_list_has
"$vocab"`; `configure_test.sh:173,207-210` use `_hi_is_header_order`.
- [ ] 29. `scripts/configure_menu.sh:26,523-526`: length check; `:961-968,1020-1021`:
      drop arguments and the `<on>` field, update `configure_wizard_test.sh:686-690`.
- [x] 30. `scripts/plugins.sh:98-105`: `--text` arm in `_hi_args`, gated on
      `_HI_TEXT=1`.
- [x] 31. `scripts/doctor.sh:96-101` drop; `:507-523` one `case`; `:423-429` and
      `doctor_target.sh:39,42,47,188,190,197` `_hi_doc_now`.
- [ ] 32. scripts library: derive `eff` in the member rows, `_hi_plugin_word_ok`'s required argument;
      `doctor.sh:301-303,874` `_hi_count_lines`; `:287,318-320` `armor`;
      `:931-933` one condition; `:210-213,260` no buffering under `--problems`.
- [x] 33. `scripts/zshrc.sh:24-28` with `_hi_rc_last_match` moved there;
      `pack_stream.sh:203-212` outvar-only key, `cache_test.sh` follows;
      `pack.sh:237-254` one theme loop.
- [x] 34. `_hi_prompt_fits` for `configure.sh:244-246`, `configure_preview.sh:290-325`;
      `configure.sh:78-84` drop `<off>`; `set_color.sh:21-29` add/remove;
      `_hi_strip_escapes` in `table.sh`, used by `configure_preview.sh:27-32`.
- [x] 35. `common/core.sh:985,1030,1055`, `common/header.sh:554`: `l="${X:+$X;}"` then
      `r="${l%%;*}" l="${l#*;}"`. Not `_hi_ramp_ok`.
- [x] 36. `common/git_prompt.sh:24-41,81`.
- [x] 37. `_hi_prompt_ext <shell>` in `core.sh`, used by `bash.sh:212-221`,
      `zsh.zsh:95-100`, keeping word splitting; drop `bash.sh:80-81`.
- [x] 38. `common/paths.sh:29-31`: export from `tests/test_lib.sh`; update GLOSSARY.
- [x] 39. `common/header.sh:1121-1125`: drop the source-time palette; add it to
      `preview.sh` and suites that call `check_line` directly.
- [ ] 40. `_hi_load_preview_sources` once in `run_configure` and `config_hub`;
      `configure_menu.sh:411` notes only when drawing; `configure.sh:66-76` memo for
      `$_HI_SETTINGS` reads only.
- [x] 41. `common/config.fish:368-407`: plain statements; rewrite the pins at
      `prompt_test.sh:216,232`.
- [x] 42. `common/targets.sh:533-534`: `set -- $(exec ls -ldn ...)`, test `${3:-}`.

## Tests: cross-suite

- [x] 43. `_hi_prints <want> <cmd...>` in the harness's report helpers; rows for
      `dispatch_test.sh:56-138`, `parse_test.sh:40-46,392-399,470-499`,
      `container_test.sh:174-216`, `payload_overlay_test.sh:18-23,126-141,196-201,637-643`.
- [ ] 44. Remove pre-`$_HI_WORKDIR` cleanups: `cache_test.sh:40-44` and 39 call sites
      plus `_hi_ctl_case`; `rc_prompt_test.sh:57,83-84,211,566,616,637`,
      `rc_test.sh:392,410,763` (common), `git_prompt_test.sh:164,178,215,241`,
      `paths_test.sh:264,310,341,356`, `core_identity_test.sh:501,516`,
      `load_session_test.sh:277,300`, `load_test.sh:245,248`, `header_whole_test.sh:663`,
      `targets_complete_test.sh:189`; `tests/scripts/rc_test.sh:383,461`,
      `doctor_target_test.sh:323`, `plugins_test.sh:40-47`, `edit_test.sh:36-41`,
      `configure_test.sh:845`. Keep removals of a `mktemp` outside the workdir.
- [ ] 45. `_hi_refused <phrase> <cmd...>`: `install_run_test.sh:56-93,252-259,570-593`,
      `doctor_report_test.sh:40-105`, `preview_test.sh:61-73,92-97,636-640`,
      `install_test.sh:199-203`, suite twins in `set_color_test.sh:33`, `plugins_test.sh:65`;
      16 `! out="$(` sites in `tests/packaging`; `parse_test.sh:90-129,197-207,401-429`.
      Sites asserting an exact other rc stay.
- [ ] 46. `_hi_script` reads stdin given no lines: 28 `chmod +x` in `tests/packaging`;
      `core_test.sh:779,792`, `header_bare_test.sh:236-244`, `load_session_test.sh:701-707`,
      `targets_test.sh:640-652`.
- [x] 47. Join 57 adjacent `local` pairs in `tests/hi`.

## Tests: per suite

- [x] 48. `doctor_config_test.sh`: `_hi_doc_at <dir> <fn...>`.
- [x] 49. `lib_report_test.sh:339-709`: `_hi_ended`, prefix assignments.
- [x] 50. `core_identity_test.sh:19,205,223,253,302-364`, `core_test.sh:413,462`:
      `_hi_colors_say`, `_hi_tag_is`.
- [ ] 51. Duplicate coverage: `_hi_human_bytes`, `_hi_require`, trap strings, overlay rc
      strip, separator in `tests/hi`; keep the union.
- [x] 52. `header_check_test.sh`, `header_test.sh:629-653`: one-line form; 249 stays.
- [ ] 53. `install_test.sh:295-470`, `configure_wizard_test.sh:375-424`: `_hi_config_hi_at`.
- [x] 54. `_hi_deal <n>` in the harness's parallel helpers for `shellcheck_test.sh:184-233`,
      `test_runner.sh:444-453`.
- [x] 55. Delete `test_package_sh_rejects_unknown_arguments`,
      `test_bump_b2_fallback_agrees_with_b2sum`, `test_src_tarball_uses_the_versioned_prefix`,
      `test_package_sh_reads_the_version_from_the_pkgbuild`.
- [ ] 56. `_hi_ledger image` in `_hi_build_image` for `*-$$` tags; sweep in
      `_hi_test_cleanup`; drop the six per-suite cleanups.
- [ ] 57. `_hi_lint_fail` bumps `$bad`; `lint_site_links` keeps its per-file count.
- [ ] 58. `packaging_ci_release_test.sh:490-626`: `_hi_in_mkpkg` moved, `_hi_checksum_dist`,
      `_hi_checksums_with`.
- [ ] 59. `cache_test.sh:237-405`: parameterized freshness and stability cases.
- [ ] 60. `ssh_keep_test.sh`: `_hi_keep_connect`, `_hi_keep_next_alone`, `_hi_keep_retry_said`.
- [ ] 61. `header_whole_test.sh:504-728` `_hi_hues_differ`; `header_bare_test.sh:94-351`
      one header helper, `_HI_IP_PROBE`; `ok` flags to `|| _hi_why` in `header_check_test.sh:467-501`,
      `header_whole_test.sh:505,729`, `targets_test.sh:523`, `load_test.sh:211-228`;
      `targets_test.sh:48-59,389-445` shim helpers; `rc_prompt_test.sh:669-694,803-805`
      registration loop, `:364` subsumed case; `header_test.sh:27,96` strip once;
      `core_test.sh:735` with `_hi_shell_agrees` reason; `paths_test.sh:228,314`;
      `header_check_test.sh:372-378`.
- [ ] 62. `preview_test.sh` `_hi_tree_preview`, `_hi_source_agrees`; `_HI_SETTINGS_SHAPE`
      at five sites; `install_run_test.sh:204-212,308-322,339-347,648-676`; `update_test.sh:333-401`;
      `configure_test.sh:610-616,833-874`; one-line wrappers; `rc_test.sh:28-48`;
      redundant statements `doctor_config_test.sh:652`, `table_test.sh:13-14`,
      `rc_test.sh:635`, `doctor_target_test.sh:344`.
- [ ] 63. `runner_test.sh:12,55-56,93-99,403-453,508,631-644,699-714,819`,
      `runner_ci_test.sh:14-16,32-39,78-91,232-331,343-375`; `lib_test.sh:108-213`.
- [ ] 64. `_hi_lint_run` for `tools_test.sh`, `dialects_test.sh:67-72`; `drift_test.sh:93-114`
      one `awk`; `drift_docs_test.sh:298-331,479-483` `_hi_jekyll_excluded`;
      `drift_test.sh:336,344-346,660-662`, `tools_test.sh:112-114`.
- [ ] 65. `alias_fallthrough_test.sh:28,92-102,177-189,244,386,436-480,564`;
      `keep_test.sh:604-743`; `remote_test.sh:540-576`; `prompt_test.sh:26-36,69-87,278`;
      `parse_help_test.sh` `_HI_MAN`, `_HI_HELP_OUT`; `payload_test.sh:316-373,513-524`;
      `payload_scan_test.sh`, `payload_home_test.sh:449-477`, `payload_overlay_test.sh:471`
      in-process exports; dead assertions and stranded comments.
- [ ] 66. `stage_fixture` to `_hi_staged_999`; dotfile scan through a moved
      `_hi_wf_steps_missing`; `docker_test.sh:14-58`; redundant `mkdir -p "$ctx"`;
      `packaging_ci_mkpkg_test.sh:409-413`; `ssh_wire_test.sh:120-194`; `_hi_gpg_export_key`;
      `framework_test.sh:183-186`; `ssh_test.sh:23-323` flags.
- [ ] 67. `update_test.sh:35-61`: build once in `$_HI_SUITE_WORKDIR`, `cp -R` per case.
- [ ] 68. `add_tag_test.sh:20-221`; `preview_test.sh:710`, `doctor_test.sh:423`,
      `configure_test.sh:757` setup moved to its users; `lib_test.sh:715-717` parallel;
      `bench_test.sh:149`.

## CI, packaging, scratch

- [x] 69. `coverage.yml:121-138,617`; `release.yml:952,1007`; `ci.yml:101,131`, workflow-level
      `_HI_RUN_DEADLINE`.
- [ ] 70. `setup-shells/action.yml:41` through `setup-backends/install.sh` with
      `HI_BACKENDS: none`; `.github/scripts/session_verdict.sh` for `windows-e2e.yml:99,136,351`,
      `ci.yml:522`, `bsd_loopback.sh:56`.
- [ ] 71. `windows-client.yml:50` with `platform_badges.sh:62`; `ci.yml:777`; `coverage.yml:471`;
      `platform_badges.sh:94`; `prettier-plugin-docs.mjs:82`; `scratch/coverage_data.py`.
- [x] 72. `setup-tool`'s unused overrides: a shared file, so it goes on the shared CI
      batch list, not into this repo alone.
