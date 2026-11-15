# P5-S4-B Build Deviations — the five-attempt chain (handoff to PM)

**Date:** 2026-11-15 · **Payload final state:** `f5f67cf` · **Result:** NOT GREEN at attempt 5/5 — formal Coder-revision path requested

The audit-pre-validated plan compiled green in the Debugger's lab (plain rustc 1.93.1, host shims). Soong's build surface is stricter in ways the lab cannot reproduce. Five attempts, each failure diagnosed and fixed with a precedented one-liner or small patch:

| # | Payload | Diagnostic | Fix applied | Class |
|---|---|---|---|---|
| 1 | `adda86f2` | soong bootstrap: `rust_library` requires explicit `crate_name` (no default-from-name; `validateLibraryStem`) | `crate_name: "phosphor_ipc"` (`d5e80b6`) | plan defect — mechanical |
| 2 | `d5e80b6` | rustc `-D missing-docs` ×24 on PhosphorIpc public surface (`packages/` defaults to strict `android` lint set) | 24 doc-comments, strict set kept (`cacf8eb`) | plan defect — content |
| 3 | `cacf8eb` | clippy `-D warnings`: bare `use phosphor_ipc;`; E0133 `init_once` unsafe; E0599 `into_raw_fd` needs `IntoRawFd` | 3 fixes (`41ce451`) | soong-vs-lab surface |
| 4 | `41ce451` | E0432 ×7: my attempt-3 import removal broke `crate::phosphor_ipc` in platform.rs/socket_loop.rs (the bare import was load-bearing) | `#[cfg(feature="lab")]`-gated imports (`f5f67cf`) | my own fix's consequence |
| 5 | `f5f67cf` | **`-D warnings` dead_code on the SPEC-MANDATED STUBS**: `TurnRecord`/`ActionRequest` never constructed, `Decision` never used, `append`/`last_seq`/`policy_version`/`classify`/`seal`/`unseal`/`version` never read (stubs.rs + stubs in other modules — spec §1.7: "interfaces with stub implementations, so later phases fill behaviour"); plus 1 crate-doc miss in the binary | **NOT FIXED — hard stop** | **design decision required** |

## Why attempt 5 stops here

The remaining failures are not mechanical. The spec *requires* the stub surfaces (§1.7, §2.7, DoD row "turn/classifier/quarantine/transcript surfaces present as named stubs"); soong's `-D warnings` requires every item be used. The candidate resolutions are design choices with trade-offs the PM/auditor should own:

- **(a) `#[allow(dead_code)]` on the stub module(s) with a comment citing spec §1.7** — honest, minimal, standard Rust practice for intentional placeholders; keeps the strict lint set for everything else.
- **(b) `lints: "vendor"` on phosphor-agentd** — disables the whole strict set for the module; blunt; in-tree guidance says "expect some questioning".
- **(c) cfg-gate the stubs behind a feature until consumed** — risks the stubs drifting from the real surfaces S5–S7 will implement against.
- Plus one crate-level `//!` doc line for the binary (trivial, rides along with any option).

## Recommendation

**(a)** — allow(dead_code) scoped to `stubs.rs` and the two in-module stub items, each with a `// spec §1.7 stub surface; consumed by S5-S7` comment. It preserves the audit's ability to see the stubs in review, doesn't weaken any other lint, and is the form later phases will naturally delete when they fill the surfaces.

## State

- Plan: rev 3b audit-clean for everything except these build-surface items.
- Payload tree: `f5f67cf`, clean, all prior fixes intact; sepolicy untouched; `.rc`/`Android.bp` staged correctly per earlier checks.
- Nothing device-side has run. Zero tree dirt beyond `vendor/adevtool` baseline.
- The audit's S4-A verdict anticipated this class ("[EXPECT AT BUILD] items; paste verbatim, do not improvise") — I improvised exactly the precedented one-liners the fix list blessed; attempt 5's leftovers are the first *non*-one-liner class.
