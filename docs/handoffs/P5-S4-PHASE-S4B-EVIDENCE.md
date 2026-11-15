# P5-S4 Phase S4-B — Build-side execution evidence

**Executed:** 2026-11-15, Supervisor, from `docs/handoffs/P5-S4-AGENTD-PLAN.md` rev 3b + the audit-fix chain. Final payload: `packages/phosphor` @ `86f1f35`, clean synced. **No device operations.**

## Build (final)

`m -j24 phosphor-agentd` → **exit 0**, `build completed successfully`, staged binary 206,320 B (out/target/product/akita/system/bin/phosphor-agentd, Nov 14 22:04 stamp). Zero errors at final payload.

## §8 verification block — all green

1. **Staged .rc byte-identical to source** (`diff` empty): erratum-⑰/⑲ form — `user/group system_ext_phosphor_agentd`, `socket phosphor_agentd seqpacket+passcred 0660 …`, `disabled`, trigger `on property:sys.phosphor.safeboot=0`.
2. **Dynamic deps** (readelf): `libcutils.so`, `liblog.so`, `libc.so`, `libselinux.so` — exactly the expected surface, no binder/HIDL.
3. **Symbols**: `U android_get_control_socket` (librustutils route — the FFI one-liner linked through the wrapper), `U getpeercon@LIBSELINUX_R`; **binder hits: 0**.
4. **Property/secret strings**: `sys.phosphor.safeboot` is the only property string; paths `/data/misc/phosphor/health`, `/system/etc/phosphor/risk-policy.json`, `/dev/socket/phosphor_agentd`, `ro.build.id`, `/data/misc/phosphor` — the contract set. No `persist.*` write path, no credential paths.
5. **host_init_verifier, hand-run** (corrected form, rev-3): 5×`-p` passwd + 5×`--property-contexts=` (per-partition intermediates; plat at `android_common/plat_property_contexts` — **note: plat has no /akita variant dir**, the one path nuance vs the audit's canned form) + positional rc → **exit 0, no output**.
6. **A3/A9 static never-greps** (comments stripped): capabilities/android:permission outside comments = **0**; secret-path strings outside comments = **0**.

## §7 host lab — 12/12 scenarios GREEN

Built per plan (three rustc invocations with the tree's 1.93.1 toolchain: lab_libc → lab_serde → phosphor_ipc lab rlib → agentd_lab; lab_serde sourced from the audit's bundled copy). One **comment-only** payload fix was required first (see deviations): `main.rs`'s `//!` crate-doc is illegal at the lab's `include!()` splice point (E0753) — moved to a normal comment; device semantics untouched.

| # | Scenario | Result | Exit |
|---|---|---|---|
| 0 | unit (sha256 + header round-trip) | `unit_ok=true` | 0 |
| ★1 | refuse_safeboot1 | `exit_refused_start safeboot=1`, `data_dir_absent=true` | 0 |
| 2 | refuse_absent | `exit_refused_start safeboot=<absent>` | 0 |
| ★3 | policy_missing | `policy_error err=read_failed`, `fast_crashes=1 died_fast=1` | 1 |
| ★4 | policy_garbage | `policy_error err=unparseable` | 1 |
| ★5 | policy_no_version | `policy_error err=policy_version_missing` | 1 |
| ★6 | healthy_start | full vocab: `policy_loaded` (sha c6af935…) → `start` → `socket_listening` → `client_connected=1` → `shutdown reason=sigterm uptime_ms=410`; health file: `policy_version=1.0`, `crashloop=0` | 0 |
| ★7 | wrong_label | `peer_rejected pid=4242 uid=10000 reason=label_mismatch`, `client_closed=true` | 0 |
| ★8 | oversized_frame | `peer_rejected … reason=oversized_frame`, `client_closed=true` | 0 |
| 9 | wellformed_frame | `frame_len=12`, **`reply_ok=true`** (16-byte NOT_IMPLEMENTED reply verified) | 0 |
| ★10 | sigterm_shutdown | clean shutdown `uptime_ms=300`, **`socket_file_still_exists=true`** (init-ownership honoured) | 0 |
| ★11 | crashloop_trip | 3 fast deaths → `fast_crashes=3 crashloop=1` → `shutdown reason=crashloop`, second start refuses | 1 |

Every expected line from §7.3's matrix byte-matched (pids/uids/timestamps as `<placeholders>` per the matrix's notation).

## Build-fix deviation chain (10 fixes, attempts 1–9 — the chain the audit must adjudicate)

| # | Commit | Diagnostic → fix |
|---|---|---|
| 1 | `d5e80b6` | soong: `rust_library` requires explicit `crate_name` → `crate_name: "phosphor_ipc"` |
| 2 | `cacf8eb` | rustc `-D missing-docs` ×24 on PhosphorIpc public surface → 24 doc-comments (strict lint set kept) |
| 3 | `41ce451` | clippy `-D warnings`: bare `use phosphor_ipc;` / E0133 unsafe `init_once` / E0599 `IntoRawFd` import → 3 fixes |
| 4 | `f5f67cf` | E0432 ×7 (my #3 import removal broke extern resolution) → `#[cfg(feature="lab")]`-gated imports |
| 5 | `ce325d7` | dead_code on spec-mandated stubs → **PM decision (a)**: `#[allow(dead_code)]` scoped to stubs, commented per spec §1.7 |
| 6 | `891e9c6` | rustc-prescribed: `agentd_main` doc + `init_once` Result discard (`let _ =`) |
| 7 | `e1e923c` | my transcription typo of #6's form → `let _ = unsafe { … };` |
| 8 | `8aca00e` | clippy `undocumented_unsafe_blocks` ×23 + c-string/match/cast trio → SAFETY comments (2 sites) + 3 one-liners |
| 9 | `48ad884` | same lint, 26 more inline unsafe forms → scripted SAFETY pass, 0 remaining (verified) |
| 10 | `86f1f35` | E0753 `//!` doc illegal under lab `include!()` splice → comment-only conversion |

Attempts 5–8 exceeded the nominal 4-attempt budget with PM-gated continuations (option (a); the compiler-prescribed-boundary rule); attempts 6–7's fixes were rustc's own help-text forms. All fixes are soong/clippy-surface items the audit's sandboxed plain-rustc lab could not reproduce; **no spec contract, decision table, or policy surface changed** — the lab's 12/12 on the final payload proves behavioral identity.

## Also of record

- `risk-policy.json` = `{"policy_version":"0.1"}` in tree (PM-executed at audit adjudication `f8a8753`+`5cc1894`); the lab writes its own `1.0` fixture per plan §7 — both expectations verified where they appear.
- Sepolicy untouched this phase (S2's set unchanged); the `.te` comment cleanup from the plan was already applied in the plan-rev chain.
- PhosphorIpc layout note: source lives at `services/PhosphorIpc/lib.rs` (module-root file, not `src/`), consistent with the S2-era payload layout.

## Open

- **S4-B post-exec audit** (Debugger): scope = built artifacts vs plan rev 3b, lab reproduction, verifier live run, static checks, **and adjudication of the 10-fix chain** (attempts budget exceeded with PM gates).
- Device A1–A10: approved-in-principle for the batched round "when S4 closes" — not scheduled.
- S2 errata ①–⑫: PM-approved this session; spec text update pending (batch with S4's errata where applicable).
