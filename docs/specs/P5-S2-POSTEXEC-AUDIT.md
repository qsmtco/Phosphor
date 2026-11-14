# P5-S2 POST-EXECUTION ADVERSARIAL AUDIT — S2-B (SELinux foundation)

**Auditor:** Debugger (adversarialDebugger.md, all 11 sections, re-loaded fresh 2026-11-13)
**Input under audit:** `docs/handoffs/P5-S2-PHASE-S2B-EVIDENCE.md`; plan `docs/handoffs/P5-S2-POLICY-PLAN.md`; preflight `docs/specs/P5-S2-PREFLIGHT-PROBE.md`; spec `docs/specs/P5-S2-selinux-foundation.md`
**Payload:** `packages/phosphor` @ `59efc92c47897a89185d510149bc09d1ce695c5d` (verified: `git -C packages/phosphor rev-parse HEAD`)
**Mode:** READ-ONLY. No file in the GrapheneOS tree was modified. Experimental artifacts (`/tmp/repro*`, `/tmp/audit*`, `/tmp/cp.*`) are throwaway probe outputs only.
**Verdict: S2 NOT ACCEPT — findings.** BUG #1 and BUG #2 must be dispositioned by the PM before S2 closes. Core data guarantees (latch exactly-one-writer, keygate one-property, policy write-ban, four domains, AIDs, zero third-party surface) are verified true of the shipped binary; the neverallow *verification regime* on this device is hollow, and two §8 guarantees are not true of the shipped binary.

---

## §0. Verification summary (what was independently reproduced)

| # | Check | Command (abridged) | Result |
|---|---|---|---|
| V1 | Payload commit | `git -C packages/phosphor rev-parse HEAD` | `59efc92c…` ✓ |
| V2 | Compiled property rows | `grep phosphor out/target/product/akita/system_ext/etc/selinux/system_ext_property_contexts` | rows at lines 6-8, three properties, two types ✓ |
| V3 | mmap_exec_file_perms | grep across `packages/phosphor/sepolicy` | 0 hits ✓ |
| V4 | Domain inventory | `grep -c 'type phosphor_.*, domain;'` | 4 (keygate, agentd, broker, shell); `phosphor-ctl` absent ✓ |
| V5 | set/get inventory | grep + compiled CIL scan | exactly `set_prop(keygate, safeboot)` + `set_prop(shell, latch)`; `get_prop(appdomain, safeboot)`; CIL tuples at system_ext_sepolicy.cil:329/332/414 ✓ |
| V6 | AID rows | `out/soong/.intermediates/.../passwd_gen_system_ext/gen/passwd` | 7520-7523, prefixed `AID_SYSTEM_EXT_PHOSPHOR_*` ✓; tree-wide `config.fs` collision scan clean; sdv precedent (7500-7511) confirmed ✓ |
| V7 | Third-party surface | `repo status` | exactly `vendor/adevtool` (S1 baseline + device.mk +1 line); `packages/phosphor` clean ✓ |
| V8 | types.te honest-record comment | read | records bisect invalidation, 142-line constant noise, stale-cache passes, real cause = coredomain/core_data_file_type ✓ |
| V9 | A2 latch differential artifact | `/tmp/s2-a2.out` | REMOVED_CIL_HITS=0 / RESTORED_CIL_HITS=1, byte-identical restore ✓ (CIL:332 tuple proven live) |
| V10 | sepolicy_tests on **fresh** policy | binary-mode hand-run, 5×`-f` + `-p`, policy = `out/soong/.intermediates/.../akita/precompiled_sepolicy` (mtime 21:44) | **HAND_EXIT=0, 142 noise lines, 0 other, 0 stdout** — evidence's headline reproduced ✓ |
| V11 | coredomain / core_data_file_type fix | compiled CIL memberships + V10 | `phosphor_agentd phosphor_keygate` present in compiled `coredomain` set; `phosphor_agentd_data_file` in compiled `core_data_file_type`; system_ext_file_contexts:4 carries the `/data/misc/phosphor` row ✓ |
| V12 | Compiled latches/neverallows | CIL 423-462 | all 13 authored statements compiled, `lmx` provenance markers cite our files ✓ |
| V13 | Latch source attribute | plat_sepolicy.cil:84172-84173 | `base_typeattr_923 = (and (domain) (not (init shell)))` — exactly the intended set; no `allow` rule anywhere references attrs 923/1190/1191/1192 ✓ |
| V14 | Latch strict-clean | BUG #2 experiment (below) | 0 violations involving latch/keygate/policy-file rules ✓ |
| V15 | **Strict neverallow evaluation** | binary-mode `checkpolicy -M -c 30` on `system_ext_sepolicy.conf` (the exact conf the build consumed, mtime 21:55) | **CP_EXIT=1, 95 neverallow failures** — all cite Phosphor lines 35, 37, 53. See BUG #2. |

---

## BUG #1 — CRITICAL: the neverallow checker never runs on this device

**Assumption violated:** Every "enforced by neverallow" claim in the spec (§3.4, §5 A5/A7/A10, §6 edge cases "makes it a **compile error**"), the plan (§10), and the evidence (A4, A5, A10) assumes `neverallow` assertions are machine-checked when the policy compiles.

**Attack vector / evidence chain (all verified this audit):**
1. `vendor/google_devices/akita/BoardConfig.mk:100` — `SELINUX_IGNORE_NEVERALLOWS := true` (vendor baseline, unmodified by this project; absent from `repo status`).
2. `system/sepolicy/build/soong/sepolicy_neverallow.go` (module `se_neverallow_test`, name `sepolicy_neverallows`) — early return: `if ctx.Config().SelinuxIgnoreNeverallows() { WriteFileRule(ctx, n.testTimestamp, ""); return }`. The check is a stamped empty file.
3. Ninja confirms the skip path: the stamp is produced by `rawFileCopy` from `raw-akita/ad/adc83b19e793491b1c6ea0fd8b46cd9f32e592fc` — SHA-1 of `"\n"`. The `sepolicy_neverallows` stamp on this tree is dated **Sep 24** (session baseline) and is *expected* to be stale forever.
4. The final merge, `secilc` (rule `m.precompiled_sepolicy_android_common.secilc`, `out/soong/build.akita.8.ninja`), runs `secilc -m -M true -G -c 30 … **-N**` — neverallow checking explicitly disabled.
5. The per-partition CIL build (`m.system_ext_sepolicy.cil_android_common.cil`, `checkpolicy -C -M -L -c 30`, **no `-N`**) does run — but experiment shows CIL mode does not evaluate neverallow assertions against attribute-expanded allows: same conf, `-C` mode → exit 0; binary mode → 95 failures (BUG #2). `system_ext_sepolicy.conf` provably contains both sides of the conflicts (conf:28527-28532 plat allows vs conf:97694-97696 our neverallows).

**Consequence:** The evidence's final build line "m -j24 sepolicy_neverallows … → exit 0" is **vacuous on this device** — the module is a no-op stamp; exit 0 carries zero neverallow information. A1's wording "the `neverallow` checker reports no violation" is unfalsifiable here. The spec's C14 rationale (system_ext admitted to the neverallow target) is correct as *mechanism* but moot as *guarantee* on akita.

**Honest self-audit note:** the S2-A preflight (mine) verified C14's admission wiring but never asked whether the check *executes*. That gap is mine, and it is the root finding of this audit.

**Fix (PM disposition, not executed):** either (a) override `SELINUX_IGNORE_NEVERALLOWS := false` in a project-owned board/product fragment so the strict checker runs on Phosphor builds (verify override precedence in `build/soong` product variables first), and make `sepolicy_neverallows` a hard gate in S8's acceptance build; or (b) accept the vendor baseline and re-scope every spec/evidence sentence that says "enforced by neverallow" to "declared, not machine-checked on this device," plus add a documented strict-mode gate to S8. Option (a) is the only path that preserves the spec's §3.4/§6 semantics as written.

---

## BUG #2 — HIGH: 95 strict-eval neverallow failures in the shipped policy unit; two §8 guarantees are not true of the shipped binary

**Assumption violated:** "agentd touches NO device node at all — stricter than the spec's list" (tree comment, `phosphor_neverallows.te:29-33`) and "no domain may CALL `phosphor_shell` except broker" (`:50-53`, counted toward arch §8 line 414).

**Attack vector:** binary-mode `checkpolicy -M -c 30 -o /tmp/repro2.policy system_ext_sepolicy.conf` → `CP_EXIT=1`, `libsepol.check_assertions: 95 neverallow failures occurred`. Every failure cites a Phosphor line:

| Authored line | Rule | Violations | Violating allows (attribute-expanded) |
|---|---|---|---|
| `phosphor_neverallows.te:35` (conf:97694) | `neverallow phosphor_agentd dev_type:chr_file *` | 10 | agentd inherits chr_file rw via `domain` attr on: `ashmem_device`, `ashmem_libcutils_device`, `binder_device`, `hwbinder_device`, `null_device`, `owntty_device`, `pmsg_device`, `ptmx_device`, `random_device`, `zero_device` (grants at `domain.te:71-96`, e.g. `allow domain null_device:chr_file rw_file_perms`) |
| `phosphor_neverallows.te:37` (conf:97696) | `neverallow phosphor_agentd dev_type:file *` | 2 | `property_info`, `properties_serial` (file rw) |
| `phosphor_neverallows.te:53` | `neverallow { domain -phosphor_broker -phosphor_shell } phosphor_shell:binder call` | 83 | essentially every domain — `system_server`, `shell`, `servicemanager`, `dumpstate`, all `untrusted_app*`/`priv_app`/vendor apps — may call `phosphor_shell:binder` (appdomain baseline + per-app grants) |

Lines 35+37+53 = 95; **zero** violations implicate plat-authored neverallows — our additions are the only conflicting rules. The three *other* headline rules are strict-clean (V14): the latch (`{domain -shell -init}` set), keygate's property subtraction, keygate binder/tcp/udp, keygate exec/data denials, the policy-file write ban, and agentd's inbound-binder rule.

**Runtime semantics (why this matters):** `neverallow` is compile-time-only. Where a neverallow conflicts with an allow that survives into the shipped binary, **the allow wins at runtime**. Therefore in the shipped policy: agentd **can** rw `/dev/binder`, `/dev/hwbinder`, ashmem, null, zero, random, ptmx, owntty, pmsg, property_info, properties_serial — exactly the plat `domain`-attribute baseline; the blanket text is inert. And `phosphor_shell` is callable by every domain in the tree; "broker or nothing" (arch §8 line 414) is not enforced (the delivered rule restricts the wrong direction — see BUG #3).

**Bounded impact (stated fairly):** the shipped binary is not *weaker than the akita baseline* — agentd's device surface is exactly the generic domain baseline (the §8 categories telephony/camera/location/radio genuinely have no grants), and shell's binder surface is exactly the generic appdomain surface. No new capability was granted. But the spec's deliverable *is* the restriction set, and two of its headline restrictions are compile-time text that (i) conflicts with the baseline and (ii) would be rejected by the very checker the tree defines (BUG #1) if it were enabled. Under any config where the checker runs, this tree does not build.

**Fix (PM disposition):** rewrite the two blanket `dev_type` rules to the spec §3.4 original shape (`radio_device`, `camera_device` + the platform-visible location/modem types — `radio_device`/`camera_device` are plat `public/device.te` types and strict-clean because no baseline grant touches them), or enumerate a subtraction of the domain-wide baseline types; replace the shell inbound rule with either an honest deferral ("shell outbound restriction lands in S5 via app_neverallows-style rules") or a strict-coherent outbound form; and record the whole episode in the errata chain. All rewrites must be validated by a strict (binary-mode) checkpolicy run, not by CIL compile.

---

## BUG #3 — HIGH: binder neverallows flipped source↔target vs plan/spec, with "Same semantics" comments that are false

**Assumption violated:** tree comments `phosphor_neverallows.te:46-49` ("Same semantics: no domain may CALL agentd except broker … which is covered by broker-only outgoing via the inverse rule below") and `:50-52` ("Same source-side form for shell … outgoing restriction enforced by the app-domain macro set + S5's own rules").

**Facts (verified):**
- Plan §10 (lines 208, 217) and spec §3.4 declare **outbound** restrictions: `neverallow phosphor_agentd { domain -phosphor_broker -self }:binder call` ("exactly one binder *target*"), same shape for shell ("broker or nothing", arch §8 line 414).
- The tree ships **inbound** rules (targets `phosphor_agentd` / `phosphor_shell`, subtraction on the source set). Inbound ≠ outbound: they are different predicates about different rule sources.
- The claimed "inverse rule below" (the shell rule) does not restrict agentd's outbound at all; and the "app-domain macro set" grants shell the *generic* appdomain surface (CIL: `allow appdomain servicemanager/binderservicedomain/appdomain/sdk_sandbox_all/virtual_camera/ephemeral_app (binder (call transfer))`) — not "broker-only". S5's rules do not exist yet. Both halves of both comments are false today.
- The mechanism is a real compiler limitation: `module_to_cil.c:1212` — neverallow rules whose *target* contains minus-self are not CIL-convertible, and the tree's attempt-6 diagnostic (recorded in-tree) says plain target-side minus is also unsupported. So the spec's outbound form could not be transcribed verbatim. That makes the *form change* forced; it does not make the *semantics claim* true.
- Consequence for agentd specifically: the outbound "broker-only" backstop — the thing that would permanently enforce S6/S7's design — does not exist. The shipped inbound rule is strict-clean today only because no allow grants `*:phosphor_agentd:binder call` yet; when S6/S7 adds broker→agentd calling, that rule becomes load-bearing but the outbound guarantee remains undelivered.

**Fix (PM disposition):** correct both comments to state the delivered predicate exactly; record in the errata chain that arch §8 line 413's *outbound* intent for agentd is deferred to S6/S7 allow-scoping (with the CIL minus-self limitation cited), and that §8 line 414 for shell is deferred to S5; renumber/annotate the neverallow-count claims accordingly (see BUG #4).

---

## BUG #4 — MEDIUM: silent netlink-rule drop; neverallow-count bookkeeping is comment-inflated

**Assumption violated:** A3 ("every neverallow traces to a §8 line") and A4 ("`rg -c 'neverallow'` matches the declared count").

**Facts:**
- Plan §10 declares **15** neverallow statements (keygate×6, agentd device-node×4, agentd netlink×1, agentd binder×1, latch×1, shell binder×1, write-ban×1). The tree ships **13** statements.
- The agentd netlink rule (`netlink_generic_socket:socket_class_set *`, plan line 205) was dropped **and appears nowhere in the evidence's deviation chain ①-⑪**. It could not have compiled from system_ext scope (`netlink_generic_socket` has zero public-policy visibility — declared in vendor scope; only mention in plat policy is `global_macros:14` socket_class_set), so the drop was *forced* — but unrecorded is still unrecorded.
- The evidence's A4 "neverallow_lines=18 (16 + 1 + 1)" counts **grep lines including comments**: actual statement counts are 13 (`phosphor_neverallows.te`) + 0 (`app.te`) + 0 (`phosphor_broker.te`); the +1s in app.te/broker.te and 3 of the 16 in phosphor_neverallows.te are comment mentions. Neither 18 nor 13 reconciles to the plan's declared 15 without explanation.
- Erratum ⑥/⑦ in-tree comments record the device-node 4→3 blanket re-expression, which is proper; the netlink drop is the sole unrecorded delta.

**Fix:** add erratum ⑫ (netlink drop, forced by scope invisibility, §8 line 412's netlink category carried by the blanket text but enforced by baseline absence — see BUG #2); reconcile A4's count to "13 statements (15 declared − 1 netlink dropped − 1 device-node set merged into blanket)".

---

## BUG #5 — LOW: A2 keygate liveness remains compile-level only, and with BUG #1 the "compile" evidence is weaker than it reads

**Assumption violated:** none not already disclosed — the evidence honestly flags this ("no separate removal cycle was run for it"). This item records the audit's ruling on the supervisor's question.

**Adjudication:** The latch differential (removed→0 CIL hits at :332, restored→1, byte-identical restore) is genuine negative-liveness proof and is accepted. For keygate, the compiled-CIL tuple `allow phosphor_keygate phosphor_safeboot_prop (property_service (set))` (system_ext_sepolicy.cil:414, `lmx 6 phosphor_keygate.te`) plus the strict-clean keygate neverallows (V14) is strong *static* evidence; a *device* removal cycle is not required for S2. What would close the §5 A2 wording gap with zero device time: repeat the latch's differential on `set_prop(phosphor_keygate, phosphor_safeboot_prop)` (remove → rebuild `system_ext_sepolicy.cil` → expect tuple gone → restore → tuple back). Recommended, not blocking.

---

## BUG #6 — LOW: three divergent copies of `precompiled_sepolicy` in out/; the stale one reproduces the exact pre-fix violations

**Assumption violated:** "the tree is green" is copy-dependent. During this audit: `out/soong/.intermediates/.../akita/precompiled_sepolicy` (21:44, sha256 5da5dc20…) passes; `out/target/product/akita/obj/ETC/.../precompiled_sepolicy` (21:18, sha256 5667abc4…) fails with **exactly the two violations the evidence quotes as fixed** (coredomain for agentd/keygate; core_data_file_type for phosphor_agentd_data_file); the S1-era target_files copy (08:16) differs again. The first hand-run in this audit hit the stale copy and "reproduced the bug" before the divergence was understood.

**Significance:** this is precisely the stale-artifact false-green/false-red class the evidence bundle itself warns about (its bisect post-mortem). The supervisor's cache-bust deleted `sepolicy_test` intermediates but the `obj/ETC` install-copy later lagged the 21:44 fix by 26 minutes of build activity. Not a product defect (no release artifact consumed it), but any future acceptance build must pin *which* copy was tested — the soong module output, not an obj/ETC install copy.

---

## Errata chain ①-⑪ adjudication

| # | Claim | Audit result |
|---|---|---|
| ① seapp_contexts → private/ | **Verified.** Compiled `system_ext_seapp_contexts` carries both rows (lines 1-2); placement worked. Preflight's 8-7 concern resolved in practice. |
| ② C15 wording (3 header copies) | **Verified** (preflight BUG #1, LOW, carried). |
| ③ backslash join | **Verified** real (checkpolicy rejects markdown continuation); honest build-driven fix. |
| ④ vendor-scope device types unknown | **Verified** real (vendor_gnss_device etc. not visible at platform scope). But see BUG #2: the *replacement* (blanket dev_type) is the part that fails strict eval; the spec's original plat-visible subset (`radio_device`, `camera_device`) was available and strict-clean. |
| ⑤ config.fs route | **Verified end-to-end**: generator rejects header AIDs in OEM range (fs_config_generator.py `_verify_valid_range`, "must be prefixed with a partition name"); sdv precedent 7500-7511 confirmed in `device/google/sdv/sdv_core_base/config.fs`; generated passwd rows 7520-7523; tree-wide collision scan clean; installed 0-byte `/etc/passwd` on all partitions is tree-normal (all partitions ship 0-byte passwd here), so the gen artifact is the correct evidence anchor. |
| ⑥ blanket dev_type | Mechanism **verified** (target-side minus unconvertible); but the replacement is a strict-eval conflict (BUG #2) and its in-tree "touches NO device node at all" comment is false at runtime (inherits 10 chr_file + 2 file grants). |
| ⑦ public→private move | **Verified** (subtraction neverallows unconvertible in public CIL; in-tree comment cites zero subtraction neverallows under public — consistent; `lmx` provenance markers show our rules compiling from `packages/phosphor/sepolicy/private/`). |
| ⑧ binder source-side subtraction | Mechanism **verified** (module_to_cil.c:1212 minus-self limitation; installd.te:242-246 does contain both inbound and outbound shapes); but the delivered predicate is inbound, not the spec's outbound, and the "Same semantics" claim is false (BUG #3). |
| ⑨ f5ddca6 raw declarations | **Verified exactly as the evidence now records it**: the bisect conclusion was false; 142-line stderr is constant noise on both states (confirmed across independent runs in this audit); the stale-ninja-cache mechanism is real (BUG #6 is a live instance of the same class). The in-tree `types.te` comment states the correction plainly — the corrected record **is** in the tree, as the supervisor asked me to verify. |
| ⑩ e477f4b coredomain + core_data_file_type | **Verified** as the *real* fix: my hand-run against the stale pre-fix policy reproduced those two violations verbatim; against the fresh policy, exit 0 / 142 noise / 0 other. Precedents (netd.te:1, mmd_setup.te:3 shape) consistent. |
| ⑪ AIDs 7520-7523 | **Verified** forced and correctly executed (generator partition-prefix + range enforcement; ⑤ above). Spec §3.6's 2950-2953 cannot survive this tree's generator — erratum justified. |

**Net:** ⑪ of ⑪ mechanics verified real; ⑥ and ⑧'s *replacements* carry the defects in BUG #2/#3; ⑨'s correction is honestly recorded in-tree; one additional unrecorded deviation (netlink drop, BUG #4) belongs in the chain as ⑫.

---

## §4. Semantic-strength review (supervisor question 4)

- **Blanket dev_type denial** — weaker than intended in effect (inert at runtime; conflicts at strict eval); the §8 categories themselves (telephony/camera/location/radio) remain unreachable because the baseline never grants them — i.e., the *outcome* approximates the spec's intent today purely via baseline absence, with zero backstop against future grants. See BUG #2.
- **Source-side binder neverallows** — agentd: outbound intent undelivered (BUG #3); shell: inbound rule conflicts with baseline (83 violations), outbound "broker or nothing" unenforced beyond generic appdomain surface (BUG #2/#3).
- **Property types as raw public declarations** — acceptable: attribute memberships in compiled CIL are exactly the `system_public_prop()` equivalents (`property_type, system_property_type, system_public_property_type` all present; CIL lines 8/12/34), the akita precedent uses the identical shape, and the macro-vs-raw difference is declaration-syntax only. The honest-record comment removes the misleading history. No semantic delta found.
- **Policy entirely in private/** — verified sound: the `lmx` markers and CIL tuples show grants/neverallows landed; `get_prop(appdomain, …)` (macro) works from a private-dir file (CIL:329); seapp_contexts rows compiled. The public/ dir retains only types.te + README. No liveness gap found beyond A2's disclosed keygate item.
- **AIDs 7520-7523** — no collision tree-wide; range-valid (7500-7999 system_ext); sdv occupies 7500-7511; names partition-prefixed as the generator requires. Sound.
- **Two coredomain additions** — verified minimal and precedented: `typeattribute … coredomain` on the two /system daemons (required by sepolicy_tests.py:147-166 for off-/system execution), `core_data_file_type` on the /data type (required by :102-107). Side effect: coredomain membership carries ~47 attribute-wide allows (property reads etc.); sampled against our types — no coredomain-sourced allow touches `phosphor_safeboot_prop`/`latch` beyond the explicit rules; polarity intact (A10 verified strict-clean).
- **`phosphor_risk_policy_file` read-leak check** — `system_file` is a *concrete type* (`public/file.te:200`), not an attribute, so `domain.te:164`'s `{appdomain coredomain} system_file` grant does NOT reach our type; zero target-position allows on `file_type`/`system_file_type` attributes (plat CIL greps: 0 and 6 — the 6 are heapprofd/traced_perf only). Shell's "no read" holds. §6.3 intent intact.
- **Latch/keygate/policy-write-ban** — strict-clean and runtime-real; R-2's core and A10's polarity are the strongest parts of the deliverable.

## §5. Evidence-green-but-tree-wrong scenarios (supervisor question 5)

**Yes — two live instances, both now evidenced:**
1. **BUG #1/#2 is the systemic one:** every neverallow-dependent criterion (A1's checker clause, A4, A5's "the neverallow is the enforcement", A7, A10) reads green on a device where the checker is a stamped empty file, while strict evaluation of the same conf yields 95 failures implicating three authored rules. The compiled-artifact checks (rows, tuples, memberships) are genuine; the *assertion* checks are decorative here.
2. **BUG #6 is the operational one:** the same hand-run procedure returns exit 0 or exit 1 depending on which of three divergent `precompiled_sepolicy` copies is tested; the stale copy reproduces the exact violations the evidence says were fixed.

## §6. Verdict

**S2 NOT ACCEPT — findings.** Reproduced green: V1-V14 (payload, compiled rows, AID mechanism, third-party surface, latch differential, fresh-policy sepolicy_tests exit 0/142-noise/0-other, coredomain fix live, CIL provenance, latch strict-clean). Blocking findings: **BUG #1** (neverallow regime disabled on this device — PM must choose enforcement path per Fix) and **BUG #2** (95 strict failures; blanket dev_type + shell inbound rules must be rewritten strict-coherent). High: **BUG #3** (direction flip + false comments; record intent deferrals). Medium: **BUG #4** (netlink drop → erratum ⑫; count reconciliation). Low/non-blocking: **BUG #5** (keygate CIL differential recommended), **BUG #6** (pin the tested artifact copy in acceptance evidence).

S2 may close only after BUG #1's disposition is chosen and BUG #2's rules are rewritten and *strict-validated* (binary-mode checkpolicy, not CIL compile), with the errata chain extended per BUG #3/#4. No device operation is required for any of it.

*Audit trail: probe outputs in `/tmp/audit-fresh.{out,err}`, `/tmp/cp.{out,err}`, `/tmp/repro-cil.cil`, `/tmp/repro2.policy` (throwaway); this report is the audit artifact of record.*
