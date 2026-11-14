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
- ETC verifier inputs (`out/target/product/akita/obj/ETC/passwd_*_intermediates/`): `passwd_system_ext` = 196 B carrying all four rows (`system_ext_phosphor_keygate::7520:7520::/:/bin/sh` at line 1); the other four are **0 bytes, which is correct** — those partitions declare no config.fs AIDs. The audit's stale-Sep-24 state was that these ETC modules had never been built as installs; now built and populated where required.

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
