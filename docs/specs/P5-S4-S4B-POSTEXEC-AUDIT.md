# P5-S4 Phase S4-B — Post-execution audit (Debugger, adversarial)

**Date:** 2026-11-15 · **Auditor:** Debugger · **Mode:** READ-ONLY (zero writes to the GrapheneOS tree or the payload repo; the only writes are this report, the audit lab `docs/evidence/s4b-build-lab-audit/`, and `/.crabcakes/tmp/s4b-probe/` rustc probes)
**Prompt:** `.crabcakes/prompts/adversarialDebugger.md` loaded fresh; all 11 sections worked. Mapping: §1 assumptions → every evidence number re-derived from artifacts (not trusted); §2 trace-backwards → the two suspect claims (label "absent" from strings; E0753 no-op suspicion) chased to root; §3 hidden assumptions → reviewer rerun in the build's exact verifier form incl. the flat plat path; §4 weakest links → timestamps/ninja edges/crate-doc obligation; §5 error handling → refuse paths order-of-operations (main.rs:65-82: refusal exits before any dir/socket/policy work); §6 type system → reply-arithmetic check (n==24, buf[7]==16); §7 external contract → NEEDED surface + dynsym contract; §8 weirdest user → negative controls on the verifier (first run this session, exit 1 with the exact recorded error) + oversized/oversized+1 frame buffers; §9 scope coverage → `git diff --name-only 655fc08..86f1f35` = 16 payload files only (services/*, risk-policy/*, main.cpp deleted), zero sepolicy / device.mk / init/ touches; §10 documentation audit → comments checked against behavior (findings #20/#21); §11 tests → §7 lab fully re-executed, real output below, not "tests pass".
**Inputs:** `docs/handoffs/P5-S4-PHASE-S4B-EVIDENCE.md` · plan rev 3b `docs/handoffs/P5-S4-AGENTD-PLAN.md` · `docs/specs/P5-S4-S4A-AUDIT.md` + `docs/specs/P5-S4-S4A-REAUDIT.md` (+ rev-3 addendum) · prior lab `docs/evidence/s4a-agentd-lab-audit/` · spec `docs/specs/P5-S4-agentd-skeleton.md` rev 2 · `docs/handoffs/P5-S4-BUILD-DEVIATIONS.md`
**Final payload:** `packages/phosphor` @ **86f1f35** — SRCREPO HEAD = mirror = tree, `git status` clean; payload flow re-proven (`diff -r` SRCREPO services/ vs TREE/packages/phosphor/services/ → identical).
**Staged binary:** `out/target/product/akita/system/bin/phosphor-agentd` — 206,320 B, mtime 2026-11-14 22:04:08, sha256 `19301d6a2b63de75111e17c86e948df8af30e7f530286faca0e8446d530179f3`, stripped ARM64 PIE (BuildID 17b705191b63e92b9b046e382080e039).

---

## Verdict: **S4 build-side ACCEPT.** The device round A1–A10 may proceed under the PM's batched approval.

All seven delegated checks pass independently. The findings (BUG #18–#21) are all **paper**: none touch the shipped artifacts; three are evidence/commit-message accuracy items, one is a build-economics item needing a PM disposition before S5. The evidence bundle's headline claims — including the strongest one, that the 10-fix chain never touched semantics — **all re-derived true**.

---

## (1) §8 verification block — all reproduced independently

| # | Check | Result | Evidence (commands + observed output) |
|---|---|---|---|
| 1 | Staged .rc byte-identical to source | PASS | `diff staged vs services/PhosphorAgentd/phosphor_agentd.rc` → empty. 1,018 B, mtime 19:32:46 (pre-dates first fix commit 19:38 — never rebuilt: the staged copy IS the transcribed bytes) |
| 2 | Dynamic deps | PASS | `llvm-readelf -d` NEEDED = `libcutils.so, liblog.so, libc.so, libselinux.so` — exactly 4, matching the evidence; no binder/HIDL/libbase/librustutils |
| 3 | Symbols; binder=0 | PASS | `llvm-nm -D`: `U android_get_control_socket`, `U getpeercon@LIBSELINUX_R`, `U freecon@LIBSELINUX_R`, `U __android_log_print@LIBLOG`, `U __system_property_get@LIBC`; `strings -a \| grep -ci binder` = **0**; no `bind`/`unlink` in dynsyms |
| 4 | Property/secret strings | PASS | Contract set present exactly: `sys.phosphor.safeboot` (only property string), `/data/misc/phosphor/health`, `/system/etc/phosphor/risk-policy.json`, `/dev/socket/phosphor_agentd`, `ro.build.id`, `/data/misc/phosphor`; `grep -c '^persist\.'` = 0; keystore/.pem//data/adb/data/local/tmp greps = 0 |
| 5 | host_init_verifier hand-run | PASS | 5×`-p` `obj/ETC/passwd_<p>_intermediates/passwd_<p>` + 5×`--property-contexts=` (plat at `obj/ETC/plat_property_contexts_intermediates/plat_property_contexts` — **flat, no /akita subdir**: nuance vs the audit's canned form, evidence handled it) + positional staged rc → **EXIT=0, no output**. Negative control (scratched `user nosuchuser777`, first run this session): **exit 1** + `Unable to find UID for 'nosuchuser777': getpwnam failed: No such file or directory` — the identical prefix/suffix form the evidence recorded |
| 6 | Never-greps, comments stripped | PASS | capabilities/android:permission outside comments = **0**; secret-path strings outside comments = **0**; capability vocabulary (`tel.\|sms.\|contacts.\|camera.\|settings.\|geo.\|clip.`) = 0; §8-step-4 content greps 1/1/1/1/0/0 exactly as expected (erratum-⑰/⑲ form confirmed live) |

## (2) §7 host lab — rebuilt from the PLAN's verbatim blocks vs the TREE's final payload

Method: harness files extracted byte-exact from plan §7.1/§7.2; the plan's `#[path]`/`include!` lines point at `/home/cptjaqx/projects/grapheneos-2026091900/packages/phosphor/...` — the synced tree copy, i.e. the final payload (proven identical to SRCREPO @ 86f1f35). Compiled with the tree's own rustc (`prebuilts/rust-toolchain/linux-x86/1.93.1`, `rustc 1.93.1-dev (01f6ddf75 2026-02-11)`, Android Rust Toolchain 14933020). Artifacts: `docs/evidence/s4b-build-lab-audit/` (lab_libc.rs, lab_serde.rs [bundled S4-A copy], agentd_lab.rs, two rlibs, agentd_lab binary). One benign warning (`unused variable: c`, healthy_start client thread — same shape as the S4-A lab).

**12/12 scenarios GREEN.** Observed (merged 2>&1, real output, pids/timestamps vary per §7.3 note (e)):

| # | Scenario | Key observed lines | Exit |
|---|---|---|---|
| 0 | unit | `unit_ok=true` | 0 |
| ★1 | refuse_safeboot1 | `event=exit_refused_start safeboot=1` · `data_dir_absent=true` | 0 |
| 2 | refuse_absent | `event=exit_refused_start safeboot=<absent>` · `data_dir_absent=true` | 0 |
| ★3 | policy_missing | `event=policy_error err=read_failed: No such file or directory (os error 2) path=…no_such_policy.json` · health `fast_crashes=1 died_fast=1 crashloop=0` | 1 |
| ★4 | policy_garbage | `event=policy_error err=unparseable: expected key …` · fast_crashes=1 | 1 |
| ★5 | policy_no_version | `event=policy_error err=policy_version_missing …` | 1 |
| ★6 | healthy_start | `policy_loaded policy_version=1.0 sha256=c6af935ebb7d9eef8acacff5022e5feb2d9466e3059ef5a11b3fbb3764bc98c4 …` · `start … safeboot=0 build_id=unknown policy_version=1.0` · `socket_listening path=/dev/socket/phosphor_agentd uid=1000 gid=1000 mode=777` · `client_connected=1` · `shutdown reason=sigterm uptime_ms=400` · health `policy_version=1.0 crashloop=0` | 0 |
| ★7 | wrong_label | `event=peer_rejected pid=4242 uid=10000 reason=label_mismatch` · `client_closed=true` | 0 |
| ★8 | oversized_frame | `event=peer_rejected pid=4242 uid=10000 reason=oversized_frame` · `client_closed=true` | 0 |
| 9 | wellformed_frame | `frame_len=12` · `reply_ok=true` (n==24; version=1, type=7, body_len=16, body = `NOT_IMPLEMENTED\n`) | 0 |
| ★10 | sigterm_shutdown | `shutdown reason=sigterm uptime_ms=300` · `socket_file_still_exists=true` | 0 |
| ★11 | crashloop_trip | `event=policy_error err=read_failed…` · `exit1=1` · health `fast_crashes=3 crashloop=1` · `shutdown reason=crashloop uptime_ms=0` · `exit2=1` | 1 |

Byte-comparison: every line matches plan §7.3's matrix and the evidence table (pids/uids/uptime as `<placeholders>` per matrix note (e)); the policy fixture sha `c6af935…` matches the evidence table's `c6af935…` exactly. Fidelity note: my harness vs the S4-A audit-lab copy = 130 diff lines, all of it header/comment text (rev-2→rev-3 provenance notes) plus the expected scenario deltas — the S4-A copy carries its own audit-only `sigpipe_attack` scenario and recv-loop instrumentation; the plan/rev-3b scenario set matches the rev-3 plan text I extracted from, which is the authority for this round.

## (3) The 10-fix chain — fix-by-fix adjudication (payload adda86f2 → 86f1f35)

| # | Commit | Diagnostic → fix | Class | Semantics vs audited plan? |
|---|---|---|---|---|
| 1 | d5e80b6 | soong `rust_library` needs explicit `crate_name` → added | soong-surface (plan defect, mechanical) | No — plan §3.1 verbatim block lacks `crate_name`; verified against the plan text |
| 2 | cacf8eb | `-D missing_docs` ×24 → 24 doc-comments, strict set kept | clippy-surface (plan defect, content) | No — `--numstat` = 28+/0−, insertions-only; all public surface of lib.rs documented per plan §3.2's own text |
| 3 | 41ce451 | bare `use phosphor_ipc;` (clippy single-component-path-imports); E0133 `init_once` needs `unsafe`; E0599 `IntoRawFd` import | soong-vs-lab surface (3 fixes) | No — exactly the forms a plain-rustc sandbox lab cannot reproduce; device `--extern` resolution differs from the lab's in-crate `mod` |
| 4 | f5f67cf | E0432 ×7 after #3's import removal → `#[cfg(feature="lab")]`-gated imports (2 modules) | own-fix consequence | No — the gated import lines are the only executable text; resolution-only |
| 5 | ce325d7 | dead_code on spec-mandated stubs → PM option (a): `#![allow(dead_code)]` scoped to stubs.rs + binary `//!` crate-doc | design decision (PM-approved) | No — scoped exactly as recommended in P5-S4-BUILD-DEVIATIONS.md; final-tree grep: **0 lint-suppression attributes anywhere in the payload outside stubs.rs** |
| 6 | 891e9c6 | `agentd_main` doc + `let _ =` for `init_once` Result (unused_must_use) | rustc-prescribed one-liners | No |
| 7 | e1e923c | transcription typo of #6's form: `unsafe { let _ = … }` → `let _ = unsafe { … }` | my-transcription | No — compiler's own help form; parse error proved the first form wrong |
| 8 | 8aca00e | SAFETY ×2 + c-string `c"%s"` + match→let + u32 cast removal | clippy-prescribed | No — the 2 executable deltas are identity-preserving (see below) |
| 9 | 48ad884 | SAFETY ×26 on remaining undocumented unsafe blocks | clippy-prescribed | **No — comment-only, proven:** `git show 48ad884` filtered to non-comment lines = EMPTY |
| 10 | 86f1f35 | `//!` → normal comment (E0753 under the lab's `include!` splice) | lab-splice-only surface | No on-device — 4 insertions/1 deletion, every line `//`; see §(4) |

Executable-text deltas in the entire chain: #3/#4 (import resolution), #5 (scoped allow), #6/#7 (`let _ =` discard of a Result — no behavior change; failure still surfaces at the next socket fetch), #8 (identity-preserving: the `match err { other => Error::new(NotFound, other.to_string()) }` became a pre-bound `err_kind` + identical `Error::new`; `cred.uid as u32` → `cred.uid` where `uid_t = u32`). **Zero spec contracts, decision-table rows, or policy surfaces changed.** The lab 12/12 on the final payload is the behavioral-identity proof and it holds.

**Budget exceedance (attempts 5–9 under PM gates):** handled with adequate discipline. Each excess attempt carries its own PM gate (option (a) at attempt 5 via P5-S4-BUILD-DEVIATIONS.md, which presents options (a)/(b)/(c) with trade-offs and a recommendation rather than improvising); attempts 6–9 are rustc/clippy's own prescribed forms, not design choices; the chain terminates with 0 remaining undocumented-unsafe (final tree: 29 `// SAFETY:` lines vs 27 `unsafe {` sites — the delta is the 2 doc-comment lines added at the two unsafe sites in logging.rs/main.rs; 0 undocumented-unsafe left); and nothing outside the named modules was touched. This matches the compiler-prescribed-boundary rule the delegation blessed.

## (4) The E0753 comment-only claim on 86f1f35 — VERIFIED, with one PM-decision finding

Facts: `git diff 48ad884..86f1f35` = `services/PhosphorAgentd/src/main.rs` only, 4 insertions/1 deletion, every touched line begins `//`. Mechanism reproduced at rustc 1.93.1 (probe (a) in `/.crabcakes/tmp/s4b-probe/`): `include!` of a file whose first line is `//!`, spliced after an existing item, → `error[E0753]: expected outer doc comment`. The device build never splices main.rs (`rust_binary` compiles it as its own crate root), so the fix is device-side zero-delta — the claim holds. The built binary at 48ad884 is unaffected by 86f1f35; the staged artifact and the final payload are consistent by construction.

Finding folded into BUG #19 below: ce325d7 added the `//!` line to satisfy `-D missing_docs` on the binary (P5-S4-BUILD-DEVIATIONS.md: "plus one crate-level `//!` doc line for the binary"); 86f1f35 removed it; no other crate-doc form exists in main.rs today (`grep '#!\[doc\]\|^//!'` → exit 1). Probe (b): `-D missing_docs` on a doc-less bin crate → `error: missing documentation for the crate`; with `//!` → the crate-level error clears. Consequence: a future **full-clean rebuild** of phosphor-agentd re-fails exactly the way attempt 5 did.

## (5) risk-policy 0.1 vs lab 1.0 — CONSISTENT across plan + evidence

Tree/SRCREPO artifact: `{"policy_version":"0.1"}\n` (25 B, newline-terminated, commits f8a8753 + 5cc1894 — PM-executed at audit adjudication). The lab writes its own `{"policy_version":"1.0"}` fixture per plan §7.2 (`write_policy("{\"policy_version\":\"1.0\"}")`) and §7.3 expects `policy_version=1.0` — observed. The evidence's "both expectations verified where they appear" claim is correct: the two versions are deliberately disjoint (device artifact vs lab fixture), the plan says so in §7.2's comments, and the daemon treats any non-empty version string identically (policy.rs accepts any string version). No consistency defect.

Standing exposure (carried from the S4-A audit's Related issue 7, NOT new): the **staged** device artifact in `out/target/product/akita/system/etc/phosphor/risk-policy.json` is still the S1-era `{}` (3 B, mtime 2026-11-12 08:15 — the S4-B `m phosphor-agentd` did not restage it; the risk-policy module has no phony dep on the daemon). Consequence: the daemon's §2.4 step-3 fail-closed check fires on device (`policy_version_missing` → exit 1 → 3 fast deaths → crashloop latch) — every boot, until S6 stages the real policy. This was already adjudicated PM-owned (A1 device check must be scheduled accordingly; daemon behavior is correct fail-closed, not a bug). Noted here because it is visible in the same artifacts this audit touched; **no action required from S4-B**; do NOT "fix" by editing the staged file — the artifact is S6's payload.

## (6) Built artifacts vs spec §2 — PASS

- **§2.1 process shape:** replaced cc_binary stub (PF-BUG #7; `main.cpp` deleted in the adda86f2 diff; step-0 ls = Android.bp + phosphor_agentd.rc + src/); module-local `init_rc` (erratum-⑰/⑲ .rc form byte-verified); stem pinned `phosphor-agentd`.
- **§2.2 start-condition defence:** source order verified (main.rs:65-82) — refusal logs `exit_refused_start` and returns 0 **before** any dir/socket/policy work; absent/empty both refuse (start_condition.rs + platform.rs read_prop comment); lab ★1/★2 prove it live.
- **§2.3 vocabulary:** exactly the 7 `event=` strings + the 2 documented non-event lines (`frame_len=`, `socket_error=`) present in the binary, each exactly once; field names match the frozen table (`start` = pid/safeboot/build_id/policy_version; `socket_listening` = path/uid/gid/mode; `peer_rejected` = pid/uid/reason; `shutdown` = reason/uptime_ms; `policy_loaded` = policy_version/sha256/path; `policy_error` = err/path; `exit_refused_start` = safeboot). `phosphor-agentd:` prefix = logd tag on device (`logging.rs:130` LOG_TAG), literal on the lab stderr leg. Redaction rule holds by construction: no logging function accepts bodies/credential paths (logging.rs:117-128 header comment is accurate, verified against the signatures).
- **§2.5 socket semantics:** fd via `android_get_control_socket` (dynsym U; source: rustutils wrapper with `init_once()` as agentd_main's first statement, main.rs:56-62); daemon `listen()`s (socket_loop.rs:64), never binds/unlinks (no bind/unlink in device-gated code paths; the only `libc::bind` in the tree is the **lab-gated** `#[cfg(feature = "lab")]` fallback at platform.rs:202 — device build excludes it; dynsyms contain no `bind`/`unlink`); label-only admission `u:r:phosphor_shell:s0` — **the evidence's strings claim is confirmed, with a mechanism note**: the constant appears **nowhere in the binary as contiguous bytes** (`grep -c` = 0), because LLVM folded the 21-byte compare into `mov/movk` immediates at the admission branch (disassembly at 0x23828-0x23878: x11=`u:r:phos`, x8=`phor_sh`, x10=`ell:s0\0` — full string reconstruction from the immediates, then `b.eq` to the accept path); SO_PEERCRED read for logging only (socket_loop.rs:164, `unwrap_or((0,0))` — never an admission input); oversized ⇒ close + `peer_rejected` (verified live ★8; buffer sized MAX+1 so an exactly-over datagram is detected); clean SIGTERM shutdown, no unlink (verified live ★10 `socket_file_still_exists=true`); zero message semantics: well-formed ⇒ `frame_len=` + TYPE_ERROR/16-byte `NOT_IMPLEMENTED\n` reply (verified live ★9, `reply_ok=true`).
- **§2.6 health/crashloop:** file 0600 (OpenOptions mode), frozen fields + backstop bookkeeping; 3-fast-death latch with the inheritance logic that keeps a SIGKILL'd healthy run from accumulating (health.rs:81-94); second start refuses when latched (verified live ★11). Init-side facts (fixed 5 s forever, no crash budget) are erratum ⑱, pinned by the preflight probe — not re-derived here (no device).
- **§2.7 never-list:** binary-level 0-binder (strings + dynsyms), 0 `persist.`, 0 secret-path strings, no property-write seam (`__system_property_get` is the only property symbol in dynsyms), scoped `allow(dead_code)` only in stubs.rs. A3/A9 never-greps green both source-side and binary-side.

## FINDINGS

### BUG #18
Severity: MEDIUM
Assumption violated: the evidence bundle and commit 8aca00e both state "25× SAFETY comments" (and the evidence headline "×25/×26").
Attack vector: `git show 8aca00e | grep -c '^+.*// SAFETY:'` → **2**; `git show 8aca00e --stat` → **10 insertions / 8 deletions across 2 files** (logging.rs 4+/2−, platform.rs 6+/6−). Commit 48ad884: 26 (matches its own "26 remaining" claim). True arithmetic: 2 + 26 = 28 added, final tree shows 29 `// SAFETY:` vs 27 `unsafe {` (delta = the 2 doc-comment lines added at unsafe sites), 0 undocumented-unsafe remaining — coverage is complete; only the recorded count is wrong.
Reproduction: the two commands above.
Root cause: aggregation/template error in the evidence bundle's fix-chain table and 8aca00e's commit message (48ad884's own numbers are self-consistent).
Fix: re-derive "×25" → "×2 (+26 in the following commit)" in the evidence bundle; amend 8aca00e's message at fold-back (PM-owned amendment, same class as prior LOW message nits).

### BUG #19
Severity: LOW (build-economics; needs a PM disposition before S5)
Assumption violated: attempt-5's binary crate-doc obligation ("plus one crate-level `//!` doc line for the binary") is discharged in the final payload.
Attack vector: 86f1f35 removed the `//!` line ce325d7 added; no crate-doc form remains in main.rs (`grep -n '#!\[doc\]\|^//!' main.rs` → exit 1). Rustc probe (b): `-D missing_docs` on a doc-less bin crate → `error: missing documentation for the crate`; control with `//!` → crate-level check clears.
Reproduction: any future full-clean rebuild (`m clobber`, toolchain bump, or new checkout) re-fails soong's strict lint set exactly as attempt 5 did.
Root cause: the E0753 fix chose the form that satisfies the lab splice but leaves the device-side lint obligation undischarged; the staged binary is unaffected (already built), so nothing shipped is wrong.
Fix: one `//!` crate-doc line in main.rs at the next S5 touch, **or** ledger the obligation explicitly into S5's brief / the S4 errata batch. A rebuild-only fix ("just rebuild") is not available — the lint will re-fire.

### BUG #20
Severity: LOW (plan-text bug, not payload bug)
Assumption violated: plan §8 step 0's gate `rg -n 'cc_binary' packages/phosphor/services/PhosphorAgentd/ → EXPECT: no output (exit 1)` — "comment-included" wording with no strip guard.
Attack vector: `grep -rn 'cc_binary' services/PhosphorAgentd/` → **2 hits, both comment lines** (Android.bp:2 "Replaces the S1 cc_binary stub…", :7 "…the S3 keygate cc_binary did…"). The gate as written would STOP a green payload today.
Reproduction: the grep above against the final payload.
Root cause: the S1 stub is referenced by name in the explanatory comments the plan itself mandated; the step-0 gate predates those comment texts and strips nothing.
Fix: bounded form per the S3 BUG #4 precedent — word-boundary + comment-strip (`rg -n 'cc_binary' <dirs> | grep -vE '^\S+:[0-9]+:\s*//'` → 0), or fold into the plan's next revision text. Note `grep -v '^\s*#'` (the .rc strip form) does NOT strip `//` comments — the step-4 .rc greps are unaffected (`.rc` uses `#`), but any .bp/.rs "comment-included" grep in the plan needs the `//`-aware form.

---

## What was ruled out (for the record)

- **Admission label missing from the binary** (first-pass suspicion): false alarm — immediate-fold optimization; proven present as `mov/movk` immediates by disassembly (§6/§2.5).
- **E0753 commit touching device semantics**: false — comment-only diff + probe (a) mechanism proof; device splice path doesn't exist.
- **86f1f35 stale-binary hazard**: none — payload provably does not affect the build; timeline + mtimes corroborate.
- **Lab result dependence on audit-lab copies**: excluded — rebuilt from the plan text against the synced tree payload; `diff -r` SRCREPO↔TREE proven empty first.
- **Verifier green as a stale-session artifact**: excluded — negative control run fresh this session exits 1 with the exact recorded error signature.
- **Scope leaks**: none — 16-file diff confined to payload paths; sepolicy/dirty-flag deltas none.

## Sign-off

S4 build-side ACCEPT. Device round A1–A10 proceeds under the PM's batched approval (per the standing ruling; each device op still needs its explicit per-op approval). PM actions carried: BUG #18 amendment at fold-back; BUG #19 disposition (add the `//!` line at S5 vs ledger it in S4's errata batch); BUG #20 plan-text fix at next plan revision. Related issue 7 exposure re-confirmed standing (staged `{}` policy fails closed on device until S6) — unchanged, S6-owned.
