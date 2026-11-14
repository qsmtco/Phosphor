# P5-S2 Phase S2-B — Execution evidence bundle

**Executed:** 2026-11-12 by the Supervisor, from `docs/handoffs/P5-S2-POLICY-PLAN.md` (Coder author round, Debugger S2-A audit "materially sound — transcribe") + `docs/specs/P5-S2-PREFLIGHT-PROBE.md` (15/15 citations verified).
**Final payload:** `packages/phosphor` @ `59efc92c47897a89185d510149bc09d1ce695c5d`, clean synced via bare mirror.
**Device operations: NONE.** No adb, fastboot, flash, wipe, reboot. A5's functional latch test remains compile-verified only (exercised in S8 under PM approval, per spec).

## Build evidence (final, cache-busted)

Command: `m -j24 sepolicy_neverallows selinux_policy passwd_gen_system_ext` with `out/soong/.intermediates/system/sepolicy/sepolicy_test` and `out/target/product/akita/obj/ETC/sepolicy_test_intermediates/sepolicy_test` deleted before launch (lesson: genrule inheritance).

- `/tmp/s2build.exit` = `0`; `#### build completed successfully (17 seconds) ####`; `FAILED:` count `0`.
- Hand-run of `sepolicy_tests` with streams separated: `HAND_EXIT=0`, `NOISE=142` constant `"isolated_compute_allowed_property_type" does not exist` stderr lines (identical on the S1 control), `OTHER_STDERR_LINES=0`, `STDOUT_LINES=0` — the two real violation messages are gone.

## Acceptance criteria

| Criterion | Result | Evidence |
|---|---|---|
| **A1** policy compiles; compiled contexts carry the rows | PASS | `out/target/product/akita/system_ext/etc/selinux/system_ext_property_contexts:6-8` — `sys.phosphor.safeboot` (`exact bool`), `persist.phosphor.safeboot` + `persist.phosphor.agent_state` (`exact string`, both `phosphor_safeboot_latch_prop`). Also present in `out/soong/.intermediates/system/sepolicy/contexts/system_ext_property_contexts/android_common/akita/`. |
| **A2** no dead rule | PASS | Both `set_prop` gates compile (build green) **and the latch writer's liveness is proven by compiled-CIL differential**: with `set_prop(shell, phosphor_safeboot_latch_prop)` removed from `private/app.te`, `m -j24 system_ext_sepolicy.cil` produces `REMOVED_CIL_HITS=0` for `(allow shell phosphor_safeboot_latch_prop (property_service (set)))` at `system_ext_sepolicy.cil:332`; with the source restored (byte-identical), `RESTORED_CIL_HITS=1`. Both builds exit 0. Recorded in `/tmp/s2-a2.out`. Honest note: my first A2 attempt was a **bad test** — removing a *grant* cannot make a neverallow checker fail; the differential above is the corrected form. The keygate `set_prop` rule's liveness is evidenced by the same compiled CIL family (`(allow phosphor_keygate phosphor_safeboot_prop …)`); no separate removal cycle was run for it, so A2's "at minimum both rules" wording is met for the latch writer and compile-proven for keygate — flagged for the post-execution audit. |
| **A3** every claim cited, in-tree, re-verified | PASS | `docs/specs/P5-S2-PREFLIGHT-PROBE.md`: C1–C15 all verified live (one LOW wording nit, C15: 3 header copies rather than 1). Every neverallow in `phosphor_neverallows.te` carries an architecture §8 citation comment. |
| **A4** NEW-7 `:file *` / no `mmap_exec_file_perms` | PASS | `mmap=0`; **fix-round final: 17 `^neverallow` rule lines** in `phosphor_neverallows.te` (fix-round ledger: 12 base rules + 8 named device rules − 3 blanket originals replaced = 17 at `22809e3`/`8adacb5`; grep-with-comments = 21). All file-class neverallows use `:file *` or the explicitly enumerated write-ops subset. |
| **A5** R-2 discharged incl. writer | PASS (policy) | compiled latch rows = 2; `set_prop(shell, phosphor_safeboot_latch_prop)` at `private/app.te:13`; `neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set` at `private/phosphor_neverallows.te:47`. Functional device write NOT exercised (spec allows compile-verified only). |
| **A6** V-2 app-layer read | PASS | `get_prop(appdomain, phosphor_safeboot_prop)` at `private/app.te:3`. Consequence accepted: every app can read the flag; mirror property is the escape hatch. |
| **A7** no over-broad set grant | PASS | inventory: `set_prop(phosphor_keygate, phosphor_safeboot_prop)` (`phosphor_keygate.te:6`), `set_prop(shell, phosphor_safeboot_latch_prop)` (`app.te:13`), and the two declared neverallow subtraction lines (`phosphor_neverallows.te:12,47`). Nothing else. |
| **A8** four domains, phosphor-ctl not one | PASS | `type phosphor_.*, domain;` count = **4**. `phosphor-ctl` runs in `shell`; no fifth domain. |
| **A9** third-party surface | PASS (ZERO) | `repo status -j24`: only `vendor/adevtool` — the S1 baseline (`.yarn/install-state.gz`, `.yarnrc.yml`, `package.json`, `yarn.lock`) + S1's `device.mk` +1 line. `packages/phosphor` clean. **No `system/core` edit**: AIDs delivered via `TARGET_FS_CONFIG_GEN += packages/phosphor/config.fs` (payload-owned), better than spec §3.6's 4-line header edit. |
| **A10** fail-closed polarity | PASS | No Phosphor domain holds `set` on the decision except keygate; A7 inventory + the neverallows prove it. |

**AID generation:** `passwd_gen_system_ext` green; `out/soong/.intermediates/build/make/tools/fs_config/passwd_gen_system_ext/gen/passwd` rows:
```
system_ext_phosphor_keygate::7520:7520::/:/bin/sh
system_ext_phosphor_agentd::7521:7521::/:/bin/sh
system_ext_phosphor_broker::7522:7522::/:/bin/sh
system_ext_phosphor_shell::7523:7523::/:/bin/sh
```

## Deviations of record / spec errata (PM batch approval pending)

Payload commits in order (`acba394` = S1 skeleton base; `987e4e5` = Coder's authored policy):

1. `7134601` — un-nested sepolicy files: the repo root **is** `packages/phosphor`; my first transcription nested another `packages/phosphor/`. Caught by the plan's sync-verification gate, fixed by object-restoring renames (byte-identical).
2. `3694628` — **erratum ③**: checkpolicy rejects the spec §3.4 fenced block's markdown-style `\` line continuation. Joined to one line.
3. `726efec` — **erratum ④**: spec/preflight's vendor-scope device types (`vendor_gnss_device` etc.) are unknown in the platform policy scope. Re-expressed at `dev_type` attribute scope.
4. `958cf96` — **erratum ⑤**: subtraction neverallows are unconvertible in **public** system_ext CIL. Set moved to `private/`.
5. `aa97626` — **erratum ⑥**: `fs_config_generator` rejects header AIDs in the OEM reserved range. Replaced with `config.fs` + `TARGET_FS_CONFIG_GEN` (sdv_ivi precedent) — third-party edit surface drops from 4 lines to zero.
6. `9ee03c3` — **erratum ⑦**: target-side `-null_device -zero_device` subtraction also CIL-unconvertible. Blanket `dev_type` denial (stricter than the spec's four categories; agentd barred from every device node). `phosphor-ctl` reads stay in `shell` domain.
7. `263e6d1` — **erratum ⑧**: `version_policy` rejects any `type_transition` in system_ext **public** policy (attribute-versioned scope). All policy files moved to `private/`; `public/` holds only `types.te` + README. Rule content unchanged.
8. `a810272` — **erratum ⑨**: target `-self` in binder neverallows unconvertible; re-expressed as source-side subtraction following `installd.te:242-246` precedent.
9. `f5ddca6` — **erratum ⑩ (later INVALIDATED, see below)**: property types as raw declarations in `public/types.te`, based on a bisect conclusion that the `system_public_prop()` macro route broke `sepolicy_test`. **That conclusion was FALSE.** The form is retained only because it is precedented (akita system_ext) and compiles; the macro was never proven broken. `public/types.te`'s comment was corrected in `e477f4b` to say so.
10. `e477f4b` — **the real fix**: the true `sepolicy_test` violations were found only after separating stdout/stderr: (a) `phosphor_keygate`/`phosphor_agentd` need `coredomain` (executed from `/system`), (b) `phosphor_agentd_data_file` needs `core_data_file_type` (`/data/` type). Both precedented (`private/netd.te:1`, `mmd_setup.te:3`).
11. `59efc92` — **erratum ⑪**: `passwd_gen_system_ext` rejected unprefixed AID names (`AID "phosphor_keygate" must be prefixed with a partition name`, `fs_config_generator.py:624`). In-tree `config.fs` uses partition prefixes/ranges: `AID_SYSTEM_EXT_PHOSPHOR_*` at 7520–7523 (7500–7999 system_ext range; sdv occupies 7500–7511). Spec §3.6's 2950–2953 legacy OEM values cannot survive this tree's generator.

**Pending pre-existing errata (preflight):** ① `seapp_contexts` → `private/` (applied); ② C15 wording (3 header copies, not 1). Total batch for PM: ①–⑪.

## The bisect experiment, honestly recorded

Nine build variants (B, D, G, J, M, plus full-payload attempts 1–9) were run to chase `"isolated_compute_allowed_property_type" does not exist`. **The investigation was invalidated by two facts discovered late:**

1. **Stale ninja cache.** The variant-G "pass" was a stale `sepolicy_test` genrule output: hand-running the test binary at G's state reproduces exit 1 and the same 142 stderr lines. The S1 "control pass" was only genuine after the genrule intermediates were deleted and rebuilt (fresh run: exit 0).
2. **The 142 stderr lines are constant noise on BOTH states** — `sepol_wrap.cpp:120` printing a missing-but-harmless attribute; S1 hand-run: `HAND_EXIT=0`, same 142 lines. Only the exit code flips.

With streams separated, stderr beyond the noise showed the actual violations verbatim:
```
The following types on /data/ must be associated with the "core_data_file_type" attribute.
Violator types and corresponding paths:
('phosphor_agentd_data_file', '/data/misc/phosphor(/.*)?')
The following domain(s) must be associated with the "coredomain" attribute because they are executed off of /system:
phosphor_agentd phosphor_keygate
```
`e477f4b` fixed exactly those. Every earlier "fix" that survived (backslashes, placement, forms) is a real compiler-driven improvement with its own diagnostic; the *reasoning* attached to `f5ddca6` was wrong and is corrected in-tree.

## Option (b) fix round (2026-11-13, post-audit, PM-approved)

**Audit verdict was NOT ACCEPT (BUG #1 CRITICAL / #2/#3 HIGH, both independently reproduced by the Supervisor).** PM chose option (b): make the rules strict-clean; enforcement-regime decision deferred to S8.

- Payload `225c3a9`: blanket `dev_type` rules (inert — 12 plat-baseline violations, allow wins at runtime) replaced by §8's named types `radio_device`/`camera_device`/`audio_device` chr+blk (plat-public, `public/device.te:5,11,20`). Shell inbound-binder neverallow (83 violations = generic app-domain binder baseline; rule was written against S5's future rules) **deferred to S5**, obligation recorded in-tree + here. Rule count restored to the plan's 15.
- **Decisive gate, executed:** binary-mode `checkpolicy -M -c 30` on the fresh build conf (mtime 23:10): `CP_EXIT=0`, **zero neverallow violations of any kind** — strict-clean, not merely phosphor-clean. Hand-run `sepolicy_tests`: exit 0, 142 noise, 0 other. Full build targets green.
- **Erratum ⑫:** the plan's 15th neverallow (`netlink_generic_socket`) was silently dropped at build (type not public-visible) — now recorded as a deviation, not silent.
- BUG #1 (checker disabled on akita via `BoardConfig.mk:100` `SELINUX_IGNORE_NEVERALLOWS := true`) is **open for S8** with PM disposition: enforce on Phosphor builds or re-scope the "enforced by neverallow" language.
- Focused re-audit of this fix round requested from Debugger (scope: neverallows.te, binary-mode validation, deferral honesty).

## Open items

- **A2:** the latch writer's negative-liveness differential is PASS (above); the keygate rule got only compile-level proof, no removal cycle — offered to the auditor as the one remaining §5 wording gap.
- **Errata ①–⑪** awaiting PM batch approval (spec text updates).
- **Post-execution adversarial audit** (Debugger) — this bundle is its input.
- PM instruction: **STOP after the audit handoff; do NOT start S3.**
