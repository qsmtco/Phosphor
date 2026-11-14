# P5-S3 Phase S3-B — post-execution adversarial audit (build side)

**Auditor:** Debugger, 2026-11-14. **Scope:** build-side execution only; A1–A10 device acceptance explicitly out of scope (PM-gated separately).
**Audited:** `packages/phosphor` @ `655fc08` (SRCREPO = bare mirror = tree, clean), staged akita artifacts, evidence bundle `docs/handoffs/P5-S3-PHASE-S3B-EVIDENCE.md`, plan `docs/handoffs/P5-S3-KEYGATE-PLAN.md` rev 2.
**Method:** `adversarialDebugger.md`, all 11 sections. Every check re-executed from primary sources; nothing accepted from the evidence bundle without independent reproduction.

---

## Part A — the five rev-2 fixes landed as prescribed (verified)

| Audit fix | Prescribed location | Verified state | Verdict |
|---|---|---|---|
| BUG #1 passwd gate | §8 step 0, lines 544–564, before build step | Present verbatim incl. `test -s` loop and 7520-row grep; build step renumbered 1 (lines 566–572) | LANDED |
| BUG #2 hoist | §2 block lines 121–141; design-note count 183→193 (line 81) | `enum class ReadResult` + 3 `Lab*` prototypes at global scope between `#include "key_chord.h"` and `namespace {`; header states the audit reason; `wc -l` = 193 | LANDED |
| BUG #3 +3 scenarios | Harness lines 458–469, matrix lines 517–522, narrative line 533, COMPLETENESS item 6 line 742 | `t2absent`/`t1empty`/`t2empty` present in all four places; 12 scenarios total | LANDED |
| BUG #4 bounded guard | §6 lines 385–392 | `rg -n '\bboot_prop\b|\bC1\b'` with EXPECT exactly 2 hits / lines 8–9 / STOP otherwise | LANDED |
| BUG #5 comment-strip | §8 step 3, lines 581–588 | All three greps `grep -v '^\s*#' "$R" |` first; counts 2/1/0 unchanged | LANDED |
| Mandated comments | stderr-leg note line 79; kError-unreachable note lines 170–173 | Both present | LANDED |
| Revision log | `## Revision log (rev 2)` after §11 | Present, maps all five BUGs to line numbers | LANDED |

---

## Part B — per-check results

### Check 1 — provenance chain: PASS
- SRCREPO HEAD = `655fc08ce2fa…` = tree `packages/phosphor` HEAD = bare mirror `refs/heads/main`; `git status --porcelain` empty on both repo and tree.
- `git show --stat 655fc08`: exactly 5 paths, +249/−3 — matches the plan's artifact list; no collateral files.

### Check 2 — byte-exactness of all four payload artifacts: PASS
Plan fenced blocks extracted mechanically (§2 L84–276, §3 L286–305, §4 L319–344, §5 L365–374) and byte-compared:
- `main.cpp` 8193 B: plan = SRCREPO = tree. `key_chord.h` 1022 B: plan = SRCREPO = tree.
- `phosphor_keygate.rc` 1363 B: plan = SRCREPO = tree = **staged** `out/target/product/akita/system/etc/init/phosphor_keygate.rc`.
- `Android.bp` 199 B: plan = SRCREPO = tree.
- Transcription fidelity is total: 4/4 artifacts byte-identical across all layers.
- Rev-2 fidelity: diff of rev-1 audit copy (`docs/evidence/s3a-keygate-lab-audit/main.cpp`) vs shipped shows only the declaration hoist, comment placement, and the two mandated comments; decision functions (`ReadT1`/`ReadT2`/`Decide`/`main`) byte-unchanged.

### Check 3 — build green + binary: PASS
- `/tmp/s3build.log`: `Build Succeeded: 20 steps`, `#### build completed successfully (6 seconds) ####`, zero `FAILED:`; our module compiled (clang++ main.cpp), linked, stripped, installed; staged `.rc` install edge = step 2.
- Staged binary: 51,736 B, `ELF 64-bit LSB pie executable, ARM aarch64 … for Android 37 … stripped` (matches evidence).
- Soong unstripped (`…/unstripped/phosphor-keygate`, 89,984 B) strips to byte-identical staged copy: sha256 `51381603c9b79cfe…` for both `out/soong/.intermediates/packages/phosphor/.../phosphor-keygate` and `out/target/product/akita/system/bin/phosphor-keygate`. Staged artifact is the just-built one, not stale.

### Check 4 — binary static surface (spec §2/§3 conformance): PASS
- `readelf -d` NEEDED: `libbase.so, liblog.so, libc++.so, libc.so, libm.so, libdl.so`. No `libbinder|libhidl|libutils|libbinder_ndk` (grep exit 1). `nm -D | grep -iE 'binder|socket'` → exit 1.
- `strings`: property names exactly `sys.phosphor.safeboot`, `ro.boot.phosphor.safeboot`, `persist.phosphor.safeboot` — the contract set and nothing else; log tag `phosphor-keygate` ×1.
- Undefined symbols: `__android_log_print@LIBLOG`, `__system_property_find@LIBC`, `__system_property_read_callback@LIBC_O`, `android::base::SetProperty(...)`. Reads = bionic libc, write = libbase, logd leg = liblog — exactly the ratified design (Related issue 4 + liblog leg).
- **A6 capture leg live:** `__android_log_print` present ⇒ the logd leg works as designed; on device init dup's stderr to `/dev/null` (S3-A audit fact, service_utils.cpp:156-166), so liblog is the capture leg, per the rev-2 design note.

### Check 5 — `.te` comment-only change + guards: PASS (one wording erratum → BUG #2)
- `git show 655fc08 -- sepolicy/private/phosphor_keygate.te`: +5/−2, every changed line begins `#`. No rule-line change (ruling 6 respected).
- NEW comment text byte-exact per plan §6 (verified in-file at te:7–11 and in compiled conf:97645–97650).
- Word-bounded guard `\bboot_prop\b|\bC1\b` over `packages/phosphor/sepolicy/` → **empty** (exit 1): the phantom citation is gone payload-wide.
- `rg 'reverse direction'` → empty (A10). S2 ledger intact: source `phosphor_neverallows.te` still has exactly 17 `^neverallow` rule lines; `git diff --stat 8adacb5..655fc08` shows the only sepolicy delta is `phosphor_keygate.te` (7 ±, comment-only).

### Check 6 — sepolicy validity, independently: PASS
- Conf provenance: `out/soong/.intermediates/system/sepolicy/system_ext_sepolicy.conf/android_common/akita/system_ext_sepolicy.conf`, 2,877,863 B, mtime **2026-11-14 13:08:48** (rebuilt in-round, after the 13:01:41 commit); contains the NEW comment text (`-- S3 preflight BUG #4` at conf:97650) and the old `boot_prop-derived` text is absent (grep exit 1). The on-disk conf corresponds to the post-edit source.
- Binary-mode gate: `out/host/linux-x86/bin/checkpolicy -M -c 30 -o …` on that conf → **EXIT=0**, zero stderr, 853,749 B binary policy produced.
- Conf carries 1563 `^neverallow` lines incl. all 8 Phosphor device rules (radio/camera/gnss/audio ×chr/blk at conf) and the S2 keygate rules (type_transition init phosphor_keygate_exec, set_prop, latch get_prop).
- Line-count parity note: 27 conf lines mention phosphor vs 17 source rule lines because CIL wraps brace-form neverallows across lines — parity is at rule level (17 source = unchanged from accepted S2), not line level.

### Check 7 — passwd gate resolution (deviation note 2): **RATIFIED — Supervisor is right**
0-byte passwd files for the four partitions without AIDs are **correct**, not stale. Evidence:
1. **Generator semantics, from the build system itself:** `build/make/tools/fs_config/Android.bp:75-76`, the `passwd_gen_system` genrule's own module comment: *"These files may be empty if no AIDs are defined in TARGET_FS_CONFIG_GEN files."* Empty is a defined, documented outcome.
2. **Mechanism:** each `passwd_gen_<p>` runs `fs_config_generator passwd --partition=<p>` over `target_fs_config_gen`. Our `packages/phosphor/config.fs` declares the four AIDs under `[AID_SYSTEM_EXT_PHOSPHOR_*]` sections only ⇒ only `--partition=system_ext` emits rows (196 B, 4 rows, `system_ext_phosphor_keygate::7520:7520::/:/bin/sh` at line 1). No other partition has any custom AID ⇒ empty output.
3. **Freshness proof:** all four 0-byte `passwd_gen_*` gen outputs re-stamped **2026-11-14 13:03:21** by the step-0 build; the five ETC verifier inputs (`out/target/product/akita/obj/ETC/passwd_<p>_intermediates/passwd_<p>`) re-stamped **13:04:13** — `system_ext` 196 B, the other four 0 B. This is fresh generator output, not the Sep-24 staleness my S3-A BUG #1 flagged.
4. **Verifier tolerance, empirical:** my direct `host_init_verifier` run consumed exactly those five inputs (four of them 0 B) → EXIT=0. The verifier requires *resolvable names*, not non-empty files; empty `-p` inputs contribute nothing to the getpwnam union.

One wording erratum (BUG #3): the evidence says all "other four" staged passwd copies are "0 bytes"; at the **staged** layer `odm/etc/passwd` does not exist at all (system/system_ext/product/vendor exist; odm's row is absent). Immaterial to correctness — see BUG #3.

### Check 8 — the `.rc` verifier story: **product PASS / premise FALSE → BUG #1 (MEDIUM)**
What I verified directly (product is clean):
- `host_init_verifier` run with the build's own argument form (observed verbatim from in-graph edges) and inputs — the five ETC passwd intermediates + five property_contexts — positional = our staged `.rc`: **EXIT=0, no output.**
- **Negative control:** same command, `.rc` with `system_ext_phosphor_keygate` → unprefixed `phosphor_keygate` (my S3-A lab method): **exit 1, 2 errors** — `Unable to find UID for 'phosphor_keygate': getpwnam failed` at rc:21 and `Unable to decode GID` at rc:22, `Failed to parse init scripts with 2 error(s)`. The prefix requirement (preflight BUG #1 mechanism) is real and load-bearing; the shipped form is clean.
What is false (the premise):
- §8 step 1's EXPECT text says "host_init_verifier … validates the .rc user/group lines inside this build". The ninja graph proves otherwise:
  - The staged-`.rc` edge is a **bare `cp`** (`ninja -t commands out/.../phosphor_keygate.rc`).
  - The Make-side verified copy is gated to Make modules only: `build/make/core/base_rules.mk:611` `ifneq ($(LOCAL_MODULE_MAKEFILE),$(SOONG_ANDROID_MK))` → our Soong `cc_binary`'s `init_rc` never enters it. (`definitions.mk:3135-3168` `copy-init-script-file-checked` — the mechanism the plan cited — exists but is on the other side of that gate; `:3137`'s TARGET_BUILD_UNBUNDLED note is unrelated.)
  - Graph census: `ninja -t commands all | grep '/bin/host_init_verifier '` → **109 edges, 0 referencing phosphor** (all are Make-side vendor/proprietary `.rc` installs, e.g. `init.gs_watchdogd.rc`, `mosey.rc`; +1 microdroid prebuilt edge).
  - The Soong-layer staging-dir check (`build/soong/filesystem/host_init_verifier_check.go`) never runs on this tree: `build/soong/fsgen/filesystem_creator.go:1714` unconditionally sets `Enable_host_init_verifier_check = proptools.BoolPtr(false)` for the auto-generated partition images; no `host_init_verifier_output.txt` exists anywhere under `out/` — including after S1's full image build (Sep-24 → Nov-12). The Make task stub (`build/make/core/tasks/host_init_verifier.mk:17-18`, self-described "can be removed after only supporting Soong") is included by nothing.
- Consequence for the record: deviation note 3's assumption ("the verifier consumes the now-populated ETC passwd inputs in a full build — re-verified at S3's device round or S8's image build") describes a leg that **will never fire on this tree**. No future build will validate this `.rc` automatically. The compensating coverage is (a) my direct run this round (EXIT=0), and (b) one explicit verifier command that must be added to S8's verification block (or the Soong check enabled). No product risk materialized this round — hence MEDIUM (paper/safety-premise), not HIGH.

### Check 9 — A4(a) lab, independently rebuilt and rerun: PASS (12/12 byte-match)
- Harness transcribed from plan §7 (L418–498) into `docs/evidence/s3b-keygate-build-audit/keygate_lab.cpp`; **transcription proven byte-identical to the plan block** (3490 B) by mechanical comparison.
- Compiled my own binary: `g++ -std=gnu++17 -Wall -Wextra -DKEYGATE_HOST_LAB …` → exit 0, no warnings; it `#include`s the tree's real `main.cpp` (`…/packages/phosphor/services/PhosphorKeygate/main.cpp`) — same provenance-explicit method as my S3-A lab.
- All 12 scenarios executed; **every line and exit byte-matches** the evidence table and the plan's EXPECT strings:

| Scenario | Observed line | last_write / read_calls / exit |
|---|---|---|
| error | `phosphor-keygate: safeboot=1 reason=undecided` | `=1` / 2 / 0 |
| normal | `phosphor-keygate: safeboot=0 reason=t1` | `=0` / 2 / 0 |
| t1 | `safeboot=1 reason=t1` | `=1` / 2 / 0 |
| t2 | `safeboot=1 reason=t2` | `=1` / 2 / 0 |
| t2zero | `safeboot=0 reason=t1` | `=0` / 2 / 0 |
| t2absent | `safeboot=0 reason=t1` | `=0` / 2 / 0 |
| t1empty | `safeboot=0 reason=t1` | `=0` / 2 / 0 |
| t2empty | `safeboot=0 reason=t1` | `=0` / 2 / 0 |
| t1garbage | `safeboot=1 reason=undecided` | `=1` / 2 / 0 |
| latchgarbage | `safeboot=1 reason=undecided` | `=1` / 2 / 0 |
| writefail | `safeboot=1 reason=undecided` | `<none>` / 2 / **exit=1** |
| slow | `safeboot=1 reason=undecided` | `=1` / **1** / 0 (~3 s deadline) |

The decision core implements spec §2.1 + ruling 8 exactly: any 1 wins; only an all-0 read yields 0; unreadable/unparseable/deadline fail closed to 1; latch 0/empty/absent all ignored, only literal 1 latches; write failure forces the safe write and exits 1.

### Check 10 — `.rc` content static gates: PASS
Comment-stripped staged `.rc`: `system_ext_phosphor_keygate` ×2 (user+group), `on load_persist_props_action` ×1, prohibited set `late-init|capabilities|socket|onrestart` ×0. Content byte-equal to plan §4 (erratum-⑬/⑭ form + NEW-6 header).

### Check 11 — scope coverage (prompt §9): PASS
Task scope = 5 payload paths + build + lab. All 5 committed in one commit, byte-exact; mirror advanced; tree synced clean; no sepolicy rule change; no device operation anywhere in the round (no adb/fastboot evidence, none claimed).

---

## Part C — findings

### BUG #1
**Severity:** MEDIUM
**Assumption violated:** Plan §8 step 1 (and deviation note 3's forward plan) assumes `host_init_verifier` validates Soong-`init_rc` files inside `m phosphor-keygate` (and again "in a full build"). On this tree it validates nothing for Soong modules, now or ever.
**Attack vector:** `ninja -t commands` on the staged `.rc` edge shows a bare `cp`; census of the whole graph shows 109 `host_init_verifier` execution edges, none touching phosphor (all Make-side vendor `.rc` installs); `build/make/core/base_rules.mk:611` gates `copy-many-init-script-files-checked` to non-Soong modules; `build/soong/fsgen/filesystem_creator.go:1714` sets `Enable_host_init_verifier_check=false` unconditionally; no `host_init_verifier_output.txt` exists anywhere in `out/` despite a full S1 image build having run.
**Reproduction:** `cd TREE && prebuilts/build-tools/linux-x86/bin/ninja -f out/combined-akita.ninja -t commands out/target/product/akita/system/etc/init/phosphor_keygate.rc` → bare cp; `find out -name 'host_init_verifier_output.txt'` → nothing.
**Root cause:** AOSP moved per-file init-rc verification to the filesystem/staging layer (2025 refactor), and the generated-image creator disables it; GrapheneOS tree inherits both. The plan quoted the old Make mechanism (`definitions.mk:3137-3168`).
**Fix:** (a) Amend plan §8 step 1's EXPECT text and evidence deviation note 3: state that the build does NOT verify Soong `init_rc`, and that coverage = the audit's direct verifier run (green, this round) — cite `docs/evidence/s3b-keygate-build-audit/REPORT.md` Check 8. (b) Add one explicit command to S8's verification block: `out/host/linux-x86/bin/host_init_verifier -p <obj/ETC/passwd_*_intermediates/passwd_*> … <staged phosphor_keygate.rc>` (exact argument form recorded in this report). (c) Optional hardening: re-enable the Soong check upstream-side; out of this round's authority.

### BUG #2
**Severity:** LOW
**Assumption violated:** Evidence "Static checks" claims payload-wide `boot_prop|C1` → empty, and plan §6-guards (L409) + §8 step 6 (L616) still specify the unbounded pattern as a pass/fail gate.
**Attack vector:** `rg -n 'boot_prop|C1' packages/phosphor` → 8 hits (6× `phosphor_safeboot_prop` substring, 2× `C14`/`C10` comments). The gate as written can never pass; the *bounded* rev-2 form is genuinely empty.
**Root cause:** Self-inflicted scope gap in my own S3-A BUG #4 fix: I bounded the §6 locate step but left the two guard lines unbounded. The Supervisor's evidence sentence inherited the unbounded form.
**Fix:** Word-bound both plan guard lines (`\bboot_prop\b|\bC1\b`) and amend the evidence line to cite the bounded form. Zero payload impact.

### BUG #3
**Severity:** LOW
**Assumption violated:** Evidence "Passwd gate" says the other four passwd copies are "0 bytes" (staged layer), and plan §8 step 0's `test -s` loop (L555–558) asserts non-empty at the **staged** `out/target/product/akita/<p>/etc/passwd` layer.
**Attack vector:** Actual staged layer today: system/system_ext/product/vendor exist, `odm/etc/passwd` **missing**; the non-system_ext staged copies are 0 B — which is *correct* per generator semantics (Check 7). Re-running §8 verbatim would spuriously STOP (step 0 `test -s` fails on odm) despite correct verifier inputs.
**Root cause:** Layer confusion: the verifier consumes `obj/ETC/passwd_<p>_intermediates/passwd_<p>`, not the staged `/<p>/etc/passwd` copies; emptiness at the staged layer is the documented no-AID outcome.
**Fix:** Reword evidence (0-byte vs absent); re-point step 0's `test -s` loop at `out/target/product/akita/obj/ETC/passwd_${p}_intermediates/passwd_${p}` and require non-empty **only for partitions that declare AIDs** (system_ext here), or accept documented-empty for the rest.

### BUG #4
**Severity:** LOW
**Assumption violated:** Plan §10.1 prescribes a byte-exact multi-line commit message; rule 1 forbids unrecorded deviation.
**Attack vector:** Actual commit `655fc08` message is a one-line summary ("P5-S3: keygate boot-decision service — decision binary (193 lines), …"), not the §10.1 body; the deviation is not in "Deviations of record".
**Root cause:** Supervisor compression at commit time.
**Fix:** Paper only — record the deviation (or amend the commit before it becomes an ancestor the device round depends on; content is fully represented in compressed form, so an amendment is optional).

---

## Part D — adjudications requested

1. **Deviation note 1 (`.te` OLD text `C1 context` vs plan's `C1's context`): RATIFIED.** `git show 655fc08` proves the pre-edit file read "…granted explicitly only if C1 context proves insufficient…" — the plan's OLD quote carried a possessive from an older revision of the line; the Supervisor adapted to the actual file, and the NEW text is byte-exact per plan with all guards green. Correct handling, correctly recorded.
2. **Deviation note 2 (0-byte passwd = correct): RATIFIED, with the proof in Check 7.** The build system's own module comment (`Android.bp:75-76`) states empty is the defined no-AID outcome; freshness re-proven by mtimes; the verifier is empirically satisfied by exactly these inputs (EXIT=0) and fails on unprefixed names (exit 1). The plan's step-0 wording (not the execution) is what needs the erratum — see BUG #3.
3. **Related issue 2 (reason=t1 on the normal path): RATIFIED as accepted design decision.** Spec §2.4's enum has no "no-trigger" value; "undecided" must stay reserved for fail-closed; the in-source rationale comment exists ("the normal decision rests on T1's 0/absent read"); A6 will show `reason=t1` on every normal boot — recorded, not hidden. Spec owner should amend the enum in a future rev ("t1" semantics = decision rests on T1); until then this interpretation stands.
4. **Related issue 4 (bionic reads vs libbase): RATIFIED as accepted design decision.** Ruling 8's absent-vs-unreadable distinction is not expressible with libbase `GetProperty` overloads (missing collapses to a default; no errno channel); reads via `__system_property_find/read_callback` are libc and §3.3's baseline permits it; the write uses libbase `SetProperty` as §3.3 prefers. Binary symbols confirm exactly this split. The kError leg is unreachable on device (find→absent, callback cannot fail) — documented in-source as cosmetic and exercised by the lab only. Accepted.

## Part E — verdict

**S3 build-side: ACCEPT** — device round (A1–A10) proceeds when the PM approves, with zero product findings: every artifact byte-exact through all layers, the decision core independently proven 12/12, policy valid under the strict binary-mode gate, the binary's surface exactly the spec contract, and the two contested resolutions (0-byte passwd; `.te` text adaptation) correct.

Four paper findings (1 MEDIUM + 3 LOW), none touching shipped bits:
- BUG #1 must be folded into the plan/evidence **and** carried into S8's verification block as an explicit `host_init_verifier` step — the build will never validate this `.rc` on its own on this tree.
- BUG #2/#3/#4 are wording/gate-layer/commit-message errata for the fold-back.

Silence-is-not-acceptance clause satisfied: this is an explicit accept with findings.
