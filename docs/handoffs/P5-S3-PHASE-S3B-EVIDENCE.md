# P5-S3 Phase S3-B — Build-side execution evidence

**Executed:** 2026-11-14, Supervisor, from `docs/handoffs/P5-S3-KEYGATE-PLAN.md` rev 2 (audit fixes applied). Payload: `packages/phosphor` @ `655fc08`, clean synced. **No device operations** — A1–A10 device acceptance is a separate PM-gated round.

## Build

- `m -j24 phosphor-keygate` → exit 0, 0 `FAILED:` (log `/tmp/s3build.log`).
- `m -j24 sepolicy_neverallows selinux_policy` → exit 0 (comment-only `.te` change; policy-neutral).

## Staged artifacts

- `out/target/product/akita/system/etc/init/phosphor_keygate.rc` — **byte-identical to source** (`diff` empty). Content: erratum-⑬/⑭ form (`user/group system_ext_phosphor_keygate`, `on load_persist_props_action`), NEW-6 facts in comment.
- `out/target/product/akita/system/bin/phosphor-keygate` — 51,736 B ELF aarch64 PIE, Android 37, stripped.

## Passwd gate (audit HIGH finding resolution)

- `m -j24 passwd_gen_system passwd_gen_system_ext passwd_gen_product passwd_gen_vendor passwd_gen_odm` → exit 0.
- ETC verifier inputs (`out/target/product/akita/obj/ETC/passwd_*_intermediates/`): `passwd_system_ext` = 196 B carrying all four rows (`system_ext_phosphor_keygate::7520:7520::/:/bin/sh` at line 1); the other four are empty-or-absent (odm: file absent), which is correct — those partitions declare no config.fs AIDs (fs_config Android.bp:75-76: "may be empty if no AIDs are defined"). The audit's stale-Sep-24 state was that these ETC modules had never been built as installs; now built and populated where required.

## Static checks

- Dynamic deps (`readelf -d`): `libbase.so`, `liblog.so`, `libc++.so`, `libc.so`, `libm.so`, `libdl.so` — **no binder/HIDL/BpHw** linkage.
- Property strings in binary: exactly `persist.phosphor.safeboot`, `ro.boot.phosphor.safeboot`, `sys.phosphor.safeboot` — the contract set and nothing else.
- `.te` diff guard: comment-only lines (+5/−2 all `#`); payload-wide `boot_prop|C1` outside target file → empty.

## A4(a) host lab — 12/12

Harness: plan §7 verbatim (`/tmp/keygate_lab.cpp`, 81 lines), compiled `g++ -std=c++17 -O1 -DKEYGATE_HOST_LAB` against the tree's real `main.cpp` (`#include` with `main` renamed). Results (executed 2026-11-14):

| Scenario | rc | Output line |
|---|---|---|
| error (all reads fail) | 0 | `phosphor-keygate: safeboot=1 reason=undecided` |
| normal (T1 absent, T2=0) | 0 | `phosphor-keygate: safeboot=0 reason=t1` |
| t1 | 0 | `safeboot=1 reason=t1` |
| t2 | 0 | `safeboot=1 reason=t2` |
| t2zero | 0 | `safeboot=0 reason=t1` |
| t2absent | 0 | `safeboot=0 reason=t1` |
| t1empty | 0 | `safeboot=0 reason=t1` |
| t2empty | 0 | `safeboot=0 reason=t1` |
| t1garbage | 0 | `safeboot=1 reason=undecided` |
| latchgarbage | 0 | `safeboot=1 reason=undecided` |
| writefail | **1** | `safeboot=1 reason=undecided` (§2.4 exit-1 on write failure) |
| slow (deadline) | 0 | `safeboot=1 reason=undecided`, read_calls=1 (deadline after first read) |

All 12 byte-match the plan's EXPECT lines. Harness `last_write=` lines also verified: `sys.phosphor.safeboot=<0|1>` in every decided case; `<none>` only in writefail (the attempted write failed, exit 1).

## Deviations of record

1. `.te` comment replacement: the shipped S2 text read `C1 context` (not `C1's context` as the plan quoted) — adapted to the actual file; replacement content byte-exact per plan; guards green.
2. Passwd-gate nuance: the audit's step-0 wording assumed all five passwd files should be non-empty; execution established 0-byte is *correct* for the four partitions with no AIDs, and only `passwd_system_ext` requires our rows. Recorded here rather than editing the plan.
3. `host_init_verifier` full-build leg not exercised this round (module-only build); the verifier consumes the now-populated ETC passwd inputs in a full build — re-verified at S3's device round or S8's image build, whichever comes first.

## Open

- S3-B post-exec audit (Debugger) — this bundle is its input.
- Device acceptance A1–A10: **PM-gated, per-operation** (4 reboots + 1 cmdline path). Not scheduled.
- Related issues 2 (reason=t1 on normal path) and 4 (bionic read path vs libbase) from the plan — carried to the audit for ratification.

## Post-exec audit fold-back (2026-11-14, Debugger S3-B audit — ACCEPT)

- **BUG #1 (MEDIUM) accepted as a durable tree fact:** this tree's build NEVER runs `host_init_verifier` on Soong-installed `init_rc` files (staging is a bare `cp`; `base_rules.mk:611` gates the verified copy to non-Soong modules; `fsgen/filesystem_creator.go:1714` disables the Soong check; 109 verifier edges in the graph, 0 touch phosphor; no `host_init_verifier_output.txt` exists even from S1's full image build). The verifier must be run **by hand**: Debugger's EXIT=0 run with the build's exact argument form is the accepted proof; the exact command is recorded in docs/evidence/s3b-keygate-build-audit/REPORT.md and is added to S8's exit-checklist obligations. Deviation note 3's "re-verified at S8 full build" leg is amended: S8 must hand-run the verifier, not rely on the build.
- **BUG #2 (LOW):** the §6 payload-wide guard is valid only in the bounded rev-2 form (`rg '\bboot_prop\b|\bC1\b'` on the target file); the unbounded `rg 'boot_prop|C1'` quoted in S3-B evidence has 8 substring false-positives. The bounded form is the check of record.
- **BUG #4 (LOW):** payload commit 655fc08's message is a one-line compression of the plan §10.1 message; recorded here as a wording deviation, content accurate.
- Ratified this round: deviation 1 (`.te` `C1 context` adaptation), deviation 2 (passwd gate semantics — "may be empty" is the tree's own words), Related issues 2 (reason=t1 normal path) and 4 (bionic-read/libbase-write split) as accepted design decisions.
