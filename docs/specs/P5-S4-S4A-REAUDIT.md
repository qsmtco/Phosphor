# P5-S4 rev-2 delta re-audit — S4-A follow-up (Debugger, 2026-11-15)

**Target:** `docs/handoffs/P5-S4-AGENTD-PLAN.md` rev 2 (2,246 lines incl. the supervisor-appended §14). Narrow scope per the S4-A audit's §E list; method: `prompts/adversarialDebugger.md` re-loaded, sections applied to the delta. READ-ONLY on the plan. Authorities: `docs/specs/P5-S4-S4A-AUDIT.md` + `docs/evidence/s4a-agentd-lab-audit/`. The rev-2 lab was **re-built and re-run at this seat** (tree rustc 1.93.1; delta modules re-transcribed plan-faithfully; every audit-side deviation marked `AUDIT FIX (BUG #10/#11)` inline).

**Marker:** please proceed (this round).

---

## VERDICT: NOT ACCEPT — 2 code-bearing findings (BUG #12, #13), both one-line mechanical, pre-validated below; everything else landed clean

Rev 2 is a faithful and nearly complete execution of the S4-A §E list. The daemon sources now compile and all 12 scenarios run green in the rebuilt lab; the supervisor-appended §14 map is accurate with two attribution nits. The two findings that block S4-B are: the §8 step-5 verifier command (canned paths don't exist — verified against the live tool), and rev 2's own new reply arithmetic (15 vs 16 bytes — the wellformed_frame row can never pass as written).

---

## Per-check results

### (1) §E items landed in the plan text — per-item verification

| §E item | Landed? | Evidence (rev-2 plan lines) |
|---|---|---|
| A(1) rustutils swap | **YES** | §0 row 1 (:24) mandates the swap incl. init_once; Design 12 (:62); `rustutils::inherited_fd::init_once()` as first statement of `agentd_main()` (:241-242, cfg'd out in lab); `control_socket_fd` rewritten over `android::sockets::android_get_control_socket` returning `OwnedFd`→`into_raw_fd()` (:522-536); `android_get_control_socket`/libcutils FFI removed from the extern block (:393-398 — only `__system_property_get`/`getpeercon`/`freecon` remain); Android.bp `rustlibs: ["liblibc","libphosphor_ipc","librustutils","libserde_json"]`, `shared_libs: ["liblog","libselinux"]` (:1413-1422); dep note (:1428) + symbol-provenance note (:2038-2044, Related 13 :2211). ⚠ One **un-validated API detail**: `SocketError::NotInitialized` (:529) — see BUG #13a below. |
| A(2) getpeercon choice recorded | **YES** | FFI kept; recorded in §0 row 2 (:25), Design 3 (:53), Related 11 (:2209, incl. the as_bytes trailing-NUL caveat). |
| A(3) lmkd listen | **YES (unchanged)** | §0 row 3 (:26) — audit-confirmed wording. |
| BUG #1 verifier command | **PARTIAL — BUG #12** | Shape correct: 5×`-p passwd` + 5×`--property-contexts=<path>` + one positional rc, no `--out_*`; usage citation (:1993-2000); negative control now greps the stable prefix (:2018-2026). But 2 of the 5 canned `--property-contexts` paths point at files that **do not exist** — see BUG #12. |
| BUG #2 six compile fixes | **YES — all six** | F1 `use crate::health;` (:1087 with the E0433 rationale); F2 `MetadataExt` (:494); F3 both imports in `socket_ids` (:640-641); F4 `let dd = platform::data_dir();` bind (:259-260); F5 `let path_buf = data_dir();` bind (:496); F6 LOG_TAG cast retained (cleared suspicion, no change — correct). |
| BUG #3 lab linkage + bools | **YES** | `include!("src/main.rs")` (:1553); extern-prelude note (:1532-1547) — accurate, matches my S4-A empirical errors verbatim; `#[repr(C)]` dropped (:1448-1451); `usleep` added (:1506-1508); §7.3 rows now `=true` (unit_ok/data_dir_absent×2/client_closed×2/socket_file_still_exists/reply_ok) + note (d) explains why (:1925). |
| BUG #4 drain | **YES** | Single bounded read, blocking-pipe rationale inline (:686-697). No read-loop remains anywhere (`grep "read until"` → 0). Lab: clean `shutdown reason=sigterm` events within budget on every socket scenario (observed 0–410 ms). |
| BUG #5 connect retry | **YES** | ~2 s/200-attempt retry in `connect_client()` (:1626-1647); no hang in the re-run. |
| BUG #6 phantom type | **YES** | `TYPE_NOT_IMPLEMENTED` constant **gone** from §3.2's live code (sole remaining mentions are prose/documentation: §2 decision 4 :54, the §3.2 removal comment :130-138, Related 10 :2208); reply is `TYPE_ERROR` + `ERROR_CODE_NOT_IMPLEMENTED` body (:1245-1262); full ERROR-code vocabulary added (:149-152); S7 hand-off recorded (Related 10). ⚠ The new reply arithmetic is off by one — BUG #13. |
| BUG #7 lab-values note | **YES** | §7.3 note (a) :1925 — exactly the observation my lab produced (`uid=1000 gid=1000 mode=777`). |
| BUG #8 init_once + rustlibs | **YES** | Same rows as A(1); `libcutils` gone from `shared_libs`. |
| BUG #9 wording | **YES** | §5 :1364 "line-for-line … line-exact" with the erratum-item enumeration; §12 row 3 (:2188) updated to "line-exact". |
| (v) policy disposition | **YES** | Related 7 (:2205) rewritten: PM-executed bump recorded (commits f8a8753+5cc1894), A1 expects `policy_version=0.1`, lab keeps 1.0 with the reason. |

### (2) Recompile + 12-scenario re-run vs rev-2 text — GREEN after two audit-side mechanical repairs

Re-transcribed the delta modules (`phosphor_ipc.rs` §3.2, `src/policy.rs` §4.5 single-branch serde_json form, `src/socket_loop.rs` §4.8 reply block, harness §7.2 linkage form) into `docs/evidence/s4a-agentd-lab-audit/`; built with the plan's §8-step-8 recipe (3 rustc invocations + my audit `vendor` shim for the fd seam).

- **BUG #10 (reproduced)**: rev-2 §4.8's `let mut reply = phosphor_ipc::encode_header(...)` then `reply.extend_from_slice(body)` → **E0599: no method named `extend_from_slice` found for array `[u8; 8]`**. `encode_header` returns a fixed-size array. Audit fix: `.to_vec()` (semantics unchanged; my copy carries the `AUDIT FIX (BUG #10)` marker). One-line plan fix.
- **BUG #11→#13 (root-caused, reproduced)**: plan-faithful build ran 11/12 green but `wellformed_frame` printed `reply_ok=false`. Instrumented hexdump of what the **daemon actually sends**: `reply_total=24 hex=00010007000000104e4f545f494d504c454d454e5445440a` — header says body_len=**16**, body is `NOT_IMPLEMENTED\n` = 15 chars + `\n` = **16 bytes**. The wire is self-coherent; the plan's *prose arithmetic* (§3.2's "newline-terminated, 15 bytes", §7.2's `n == 8 + 15`, `buf[7] == 15`, `buf[8..23]`) is off by one against its own `ERROR_CODE_NOT_IMPLEMENTED` constant. As written, `reply_ok=true` is **unreachable** → guaranteed §11.8 STOP on a correct run. Audit fix: expect 24 bytes total / body_len 16 (my copy carries the marker). Plan fixes: the three 15s → 16 (§3.2 comment, §7.2 check), and §7.3 row 9 is fine as-is (`reply_ok=true`, `frame_len=12` — the client-side length is internal to the scenario).
- **Final matrix (rev-2 text + the two fixes), actual output**: unit `unit_ok=true`/0; refuse_safeboot1 `exit_refused_start safeboot=1`, `data_dir_absent=true`, exit 0; refuse_absent same, exit 0; policy_missing `policy_error err=read_failed: …` + `health fast_crashes=1 died_fast=1`, exit 1; policy_garbage `err=unparseable: expected key`, exit 1; policy_no_version `err=policy_version_missing`, exit 1; healthy_start full event chain (`start … policy_version=1.0` → `policy_loaded sha256=c6af935e…` → `socket_listening path=/dev/socket/phosphor_agentd uid=1000 gid=1000 mode=777`) + `client_connected=1` + `shutdown reason=sigterm uptime_ms=410` + clean health, exit 0; wrong_label `peer_rejected pid=4242 uid=10000 reason=label_mismatch` + `client_closed=true`, exit 0; oversized_frame `peer_rejected … reason=oversized_frame` + `client_closed=true`, exit 0; wellformed_frame `frame_len=12` + `reply_ok=true`, exit 0; sigterm_shutdown `shutdown reason=sigterm uptime_ms=300` + `socket_file_still_exists=true`, exit 0; crashloop_trip `exit1=1` + `fast_crashes=3 crashloop=1` + `shutdown reason=crashloop` + `exit2=1`, exit 1. **12/12 match §7.3 modulo the 15→16 arithmetic; clean SIGTERM well inside any budget.** SIGPIPE adversarial re-check: daemon survives the dead-peer reply (survives past 3 s; loop intact — Rust std SIG_IGN, as recorded in Related 12).

### (3) §14 revision-log map — accurate, two attribution nits (BUG #14, report-only)

Checked every row against the in-file changes:
- **#1 row** says "negative-control check added" — the negative control existed in rev 1 (:2023-2025 rev 1; rewritten in rev 2 to grep the prefix). Rewording nit only; the substantive map is right.
- **#8 row** attributes the §7.2 linkage repair to "include! line added" — the include! line already existed in rev 1's §7.2 *header*; what Coder actually added in rev 2 is the **explanatory resolution-note block** (:1532-1547), the extern-crate linkage, and the recipe. Attribution nit only; the fix itself is real and verified.
- **#2 row** says "bind-then-borrow in main.rs:59 and platform.rs:121" — the line numbers are rev-1's (now :259-260 and :496). Cosmetic.
- **#3 row**'s "§7.2 (~1542)" points into the new resolution-note block — correct landing zone.
- All other rows (#4/#5/#6/#7/#9 + the "Also in rev 2" tail) verified accurate against the text.
- **Not the log's fault but worth stating:** §14 says "every fix's exact form was pre-validated by the audit" — true for rev-1-era fixes, but BUG #12/#13 show two rev-2-*authored* forms that were **not** pre-validated (the verifier path list and the reply arithmetic). Recommendation: rev 3 of the two one-liners should be re-validated by a quick grep/diff at the author seat (both now are, by this report).

### (4) Related-7 policy_version consistency — PASS

`policy_version=1.0` appears exactly once outside code (§7.3 ★6, lab-written policy file) and Related 7 (:2205) explains precisely that and states the device expectation (`0.1`). SRCREPO verified: `risk-policy/risk-policy.json` = `{"policy_version":"0.1"}` (f8a8753 + 5cc1894, newline-terminated fix). No contradiction anywhere in the plan. (Minor: A1/A7's `start`-line expectation in the spec still says nothing about 0.1 — the spec's A-criteria don't pin a version string, so nothing to fix there; the plan's Related 7 is the operative record.)

---

## New findings

### BUG #12
**Severity:** HIGH (blocker: §8 step 5 fails at the tool)
**Assumption violated:** rev 2's canned step-5 command assumes five `--property-contexts` intermediates live at `plat_property_contexts_intermediates/{plat,system_ext,product}_property_contexts` and `vendor_property_contexts_intermediates/{vendor,odm}_property_contexts`.
**Attack vector:** ran the exact canned command (with the S3 keygate rc as a valid positional): `host_init_verifier: Could not read properties from 'out/target/product/akita/obj/ETC/plat_property_contexts_intermediates/system_ext_property_contexts': No such file or directory` — exit non-zero unconditionally → §11.4 false STOP. Tree check: **five separate intermediates dirs exist** (`plat_`, `system_ext_`, `product_`, `vendor_`, `odm_property_contexts_intermediates`, each holding its one file); the live ninja edge I recovered in S4-A uses one per partition, and the plan's own recovering-grep instruction would have shown exactly that.
**Root cause:** the path list was transcribed from memory of the grep output instead of pasted from it (the step's own instruction says to mirror the observed edge).
**Fix (one line each, shape unchanged):** `--property-contexts=…/system_ext_property_contexts_intermediates/system_ext_property_contexts`, `--property-contexts=…/product_property_contexts_intermediates/product_property_contexts`, `--property-contexts=…/odm_property_contexts_intermediates/odm_property_contexts` (plat and vendor rows are already correct).
**Validated here:** corrected form → **exit 0, no output** (keygate rc as stand-in positional; phosphor rc identical shape post-S4-B). Negative control → exit 1 with `Unable to find UID for 'phosphor_keygate': getpwnam failed: No such file or directory` — grep-prefix instruction confirmed correct (live suffix differs from S3's note; the plan's "do not grep the suffix" is exactly right).

### BUG #13
**Severity:** HIGH (blocker: §7.3 row 9 can never pass as written)
**Assumption violated:** §3.2's "newline-terminated, 15 bytes" / §7.2's `n == 8 + 15` + `buf[7] == 15` + `buf[8..23]`.
**Attack vector:** reproduced — see check (2): the daemon's own reply is 8+16=24 bytes (body_len=16, `4e4f…440a` hexdump); the client check expects 23 and can never succeed on a correct daemon.
**Root cause:** arithmetic error: `"NOT_IMPLEMENTED"` is 15 chars; +`\n` = 16. The constant (`ERROR_CODE_NOT_IMPLEMENTED: &[u8] = b"NOT_IMPLEMENTED\n"`, `.len()` at the reply site) is correct; the prose/checks disagree with it.
**Fix:** §3.2 comment "15 bytes" → "16 bytes (15 chars + newline)"; §7.2 `n == 8 + 15` → `n == 8 + 16`, `buf[7] == 15` → `== 16`, `buf[8..23]` → `buf[8..24]`. (Or simpler and drift-proof: assert `&buf[8..8+15+1] == phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED` and `total == 8 + phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED.len()`.)

### BUG #14
**Severity:** LOW (report-only; no plan change strictly required)
**Assumption violated:** §14's rows #1/#8 attribute wording to Coder that was supervisor-carried-in (negative control pre-existed) or describe rev-1 line numbers (:59/:121) that moved.
**Fix (optional):** two-word touch-ups in the §14 rows; or leave as-is — the substantive map is accurate and this report is the correction record.

### BUG #15 (doc nits, bundle)
**Severity:** LOW
- §7.2 header (:1518) and §8 step 8 (:2060) both say "FOUR rustc invocations" but list **three** (libc, serde_json, harness). Fix the count.
- §7.2 header (:1520-1521) names the serde rlib `libserde_lab.rlib`; step 8 uses `/tmp/libserde_lab.rlib` — consistent. ✔ (no change; recorded to show it was checked).
- §8 step 2's crate-name guard list ("liblibc/libserde_json/libphosphor_ipc") should now include **librustutils** (new rev-2 dep; a soong rejection there is the most plausible new STOP). One word.

### BUG #13a (merged into #13's fix set; API-verification gap)
**Severity:** MEDIUM
**Assumption violated:** §4.2 `control_socket_fd` (:529) matches `rustutils::android::sockets::SocketError::NotInitialized` — a variant **I have not verified exists** (my S4-A read pinned the enum as `{InvalidName(String), OwnershipFailed(inherited_fd::Error)}`; `take_fd_ownership`'s `Error::NotInitialized` lives in `inherited_fd`, and whether `sockets.rs` re-exports it as a `SocketError` variant was not in the verified excerpt).
**Fix:** either drop the `NotInitialized` match arm (the catch-all `other =>` arm already maps any error, including a `NotInitialized`-flavored one, into an `io::Error` — the comment can name the cause without matching on it), **or** keep the arm only after a tree read of `sockets.rs`' current enum at the S4-B seat. Cheapest safe fix: delete the specific arm; behavior and logging are unchanged. This is exactly the §11.2 "rust API mismatch" STOP the plan already anticipates — pre-clearing it here.

---

## Rev-3 fix list (all pre-validated in this report + the audit dir)

1. §8 step 5: three `--property-contexts` paths → the per-partition intermediates dirs (BUG #12; corrected form verified exit 0 here).
2. §3.2 comment + §7.2 wellformed check: 15 → 16 (three spots; BUG #13; verified `reply_ok=true` at 24 bytes here).
3. §4.8: `.to_vec()` on the `encode_header` result before `extend_from_slice` (BUG #10; verified compiling + serving here).
4. §4.2: drop the `SocketError::NotInitialized` match arm (BUG #13a; catch-all arm already covers it) — or tree-verify the variant first.
5. Doc nits: "FOUR" → "THREE" rustc invocations (×2); add `librustutils` to the §8 step-2 crate-name guard; optional §14 attribution touch-ups (BUG #14/#15).

Items 1–4 are the minimum for S4-B: without them, step 5 false-STOPs (BUG #12) and the lab matrix false-STOPs on row 9 (BUG #13), plus `m phosphor-agentd` fails on rev-2's own new reply code (BUG #10) — all three are §11 STOP conditions that would halt a correct build.

— Debugger, rev-2 delta re-audit round. Silence is not acceptance: this report is the acceptance gate for rev 3 (four one-liners) before S4-B transcription.

---

# Rev-3 verification addendum (Debugger, 2026-11-15)

**Target:** `docs/handoffs/P5-S4-AGENTD-PLAN.md` rev 3 (2,231 lines, commit a19237a, supervisor-applied from this report's fix list). Method: full rev2→rev3 diff (`git diff dc7f3c8 a19237a`, six hunks — the delta contains nothing beyond the fix list), grep sweeps for every stale pattern, tree re-check of all five intermediates paths, and a fresh compile-and-run probe of the changed §4.8 fenced block (tree rustc 1.93.1, `.crabcakes/tmp/rev3_socket_loop_tail.rs`, exit 0, runtime assert body_len=16/total=24 OK). No full lab matrix re-run needed: the only lab-compiled code change is §4.8's `.to_vec()` (probe-verified); §4.2's block is `cfg`'d out of the lab; the harness's `buf[7]` 15→16 line was already carried green in the rev-2 lab's AUDIT FIX copy.

**Marker:** please proceed (rev-3b round).

## VERDICT: NOT ACCEPT — BUG #13 is only partially applied (1 of 6 pre-validated spots); one nit open

| Fix-list item | Applied? | Evidence |
|---|---|---|
| 1. BUG #12 three paths | **YES** | :2007/:2008/:2010 now per-partition intermediates; re-checked against the tree (5/5 exist); supervisor's live verifier run exit 0 independently cross-checks. |
| 2. BUG #13 15→16 | **PARTIAL — BUG #16** | Only `buf[7] == 16` (:1832) landed. Five pre-validated spots still stale — see BUG #16. |
| 3. BUG #10 `.to_vec()` | **YES** | :1253, verbatim; probe compiles+runs at 1.93.1. |
| 4. BUG #13a arm drop | **YES** | :528–532, catch-all only + rev-3 comment; zero lab impact (cfg'd out). |
| 5a. FOUR→three ×2 | **YES** | :1517, :2059. |
| 5b. librustutils guard | **NO — BUG #17** | :2171 still lists only liblibc/libserde_json/libphosphor_ipc. |
| 5c. §14 touch-ups | skipped | Optional per BUG #14; this addendum is the correction record. |

## BUG #16
**Severity:** HIGH (blocker: §7.3 row 9 still can never pass; the check is now internally inconsistent)
**Assumption violated:** the rev-3 application assumed `buf[7] == 16` alone discharges the BUG #13 fix list. BUG #13's fix named six textual spots; the diff shows one.
**Attack vector (arithmetic, no execution needed):** the daemon's reply is 24 bytes (proven at the rev-2 lab: hexdump `reply_total=24`, body_len=16, `4e4f…440a`). Rev-3 harness: `n == 8 + 15` (→ 24 == 23 false, short-circuits) and `&buf[8..23]` is a 15-byte slice compared to a 16-byte constant (false even if reached) while `buf[7] == 16` is correct. `reply_ok=true` remains unreachable → guaranteed §11.8 STOP on a correct run, now with the added confusion of a correct byte-7 check sitting between two stale ones.
**Root cause:** partial transcription of a pre-validated multi-spot fix — every dropped spot was enumerated verbatim in this report's BUG #13 Fix line.
**Fix (five one-liners, all pre-validated):** :134 `"…(newline-terminated, 15 bytes)"` → 16 bytes (15 chars + newline); :1820 `"(15 bytes)"` → `"(16 bytes)"`; :1821 `body_len=15` → `body_len=16`; :1824 `n == 8 + 15` → `n == 8 + 16`; :1833 `buf[8..23]` → `buf[8..24]`. (Or the drift-proof form from BUG #13: assert against `ERROR_CODE_NOT_IMPLEMENTED`/`.len()` directly.) Cosmetic while in the neighborhood: the rev-3 comment at :529–530 is mis-indented (inside the §4.2 fence S4-B transcribes line-exact).
**Validated here:** the corrected 16/24 arithmetic is the exact form the rev-2 lab ran green (`reply_ok=true`, 12/12).

## BUG #17
**Severity:** LOW (one word)
:2171's crate-name guard omits `librustutils` (rev-2's new dep; the most plausible new soong rejection). Append it to the backticked list.

## Rev-3b fix list (completes rev 3; total five one-liners + one word)
1. The five BUG #16 spots above. 2. `librustutils` into :2171. Everything else in rev 3 is landed and verified; S4-B transcription may proceed immediately after these land — no re-audit round needed beyond a diff check against this addendum's list.

— Debugger, rev-3 verification round.
