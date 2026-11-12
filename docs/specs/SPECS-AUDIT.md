# Phase 5 spec audit — adversarial review of `docs/specs/P5-S1..S8`

**Auditor:** Debugger, 2026-11-10. **Artifacts audited:** the eight Phase 5 specs, 1743 lines / 154,768 bytes.
**Governing documents read in full:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` rev 4, `docs/P4-ARCH-AUDIT.md` (incl. R-1/R-2, NEW-1..NEW-7), `docs/PHOSPHOR-BUILD-PLAN.md` Phase 5, `docs/PHOSPHOR-VISION.md`, `docs/PROJECT-STATUS.md` §6/§8/§9.
**Location rationale:** a separate artifact class from the Phase 4 architecture audit, therefore a separate file rather than an appended section of `docs/P4-ARCH-AUDIT.md`. No spec file was modified.

---

## Verdict summary

| Spec | Verdict | Blocking findings |
|---|---|---|
| P5-S1 build-integration | **FIX FIRST** | F1 (obsolete sepolicy variables → guaranteed build abort) |
| P5-S2 selinux-foundation | **FIX FIRST** | F1-inherited, F2 (latch writer granted nowhere), F3 (wrong AID header path) |
| P5-S3 keygate-service | **ACCEPT** | F7 (minor) |
| P5-S4 agentd-skeleton | **ACCEPT** | F8 (minor) |
| P5-S5 shell-app | **ACCEPT** | F9 (minor) |
| P5-S6 broker-app | **FIX FIRST** | F4 (acceptance depends on an S7 deliverable) |
| P5-S7 ipc-channels | **ACCEPT** | — |
| P5-S8 diagnostics-exit | **FIX FIRST** | F5 (fifth-process contradiction unresolved) |

**Overall: FIX FIRST.** Four findings block. The set is otherwise strong: evidence discipline, per-operation device gating, and honest deferral are consistently present, and every Phase 4 residual is carried forward explicitly. The blocking class is small, mechanical, and one-line-scale — but most of it would surface only *after* implementation time was spent, which is why it is caught here.

**Verification honesty note.** Three findings I initially formed were **retracted after re-testing** and are recorded as RETRACTED below (R1–R3), with the evidence that overturns them. They are kept in the record rather than silently deleted, because a re-audit that re-derived them would waste the same effort.

---

## Findings

### F1 — BLOCKER — `BOARD_PLAT_*_SEPOLICY_DIR` are fatal in this tree (S1 §3 B5; S2 §2 C14)

S1 §3 B5 writes:

```make
BOARD_PLAT_PUBLIC_SEPOLICY_DIR += packages/phosphor/sepolicy/public
BOARD_PLAT_PRIVATE_SEPOLICY_DIR += packages/phosphor/sepolicy/private
```

Both names are `KATI_obsolete_var` in this tree:

- `build/make/core/config.mk:163` — `BOARD_PLAT_PUBLIC_SEPOLICY_DIR` → "Use SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS instead"
- `build/make/core/config.mk:164` — `BOARD_PLAT_PRIVATE_SEPOLICY_DIR` → "Use SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS instead"
- `system/sepolicy/README.md:48-49` — "The old `BOARD_PLAT_PUBLIC_SEPOLICY_DIR` … have been deprecated in favour of `SYSTEM_EXT_*`."

I verified empirically that this is a **hard abort, not a warning**, using the tree's own `ckati`:

```
$ printf '$(KATI_obsolete_var FOO,Use BAR instead)\nFOO := 1\nall:\n\t@echo built\n' > m.mk
$ prebuilts/build-tools/linux-x86/bin/ckati -f m.mk all
m.mk:2: *** FOO is obsolete. Use BAR instead.
EXIT=1
```

S1 does carry `[VERIFY AT BUILD: rg -n 'BOARD_PLAT_(PUBLIC|PRIVATE)_SEPOLICY_DIR' build/make/core]`, but the stated remedy ("if the variable names differ, record the actual names … before writing `phosphor.mk`") understates it: that grep returns **only the two `KATI_obsolete_var` lines**, and the build dies on the first `m` of the spec that gates all others.

**Fix:** `SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` / `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS`. Verified live: `build/make/core/soong_config.mk:219-220` feeds them to Soong as `SystemExtPublicSepolicyDirs`/`SystemExtPrivateSepolicyDirs`, consumed at `system/sepolicy/build/soong/build_files.go:88-89`.

**Second-order, must be stated:** S2 C14 justifies the choice by "a `neverallow` is only permitted in platform policy dirs". The conclusion is right, the mechanism as stated is not. `sepolicy_neverallows` (`system/sepolicy/Android.bp:943`) admits `plat_public + plat_private + **system_ext_public + system_ext_private** + product_public + product_private + vendor + odm` — so `system_ext` carries `neverallow` because it is *admitted to that target*, not because it is "platform policy". S2 must restate C14 against `Android.bp:943`, or the next reader re-derives it wrongly.

### F2 — BLOCKER — the latch writer is granted in acceptance text but in no rule (S2 §3.2 vs §5 A5/A7)

R-2's discharge requires the latch be writable by exactly the documented writer (the host, over adb). S2 §5 A5 demands it: "exactly one non-init domain (`shell`, the adb path) holds `set` on it". §5 A7 permits it: "`rg -n 'property_service set'` returns only: keygate→safeboot (via `set_prop`), **shell→latch**, and any explicitly justified init/host grant."

§3.2, which actually writes the policy, contains no such rule. `grep -n 'phosphor_safeboot_latch_prop'` across the whole spec returns lines 16, 74, 81, 82, 101, 231, 267 — a type declaration, two context rows, a `get_prop` for **keygate**, and acceptance prose. The only `set_prop` anywhere is `set_prop(phosphor_keygate, phosphor_safeboot_prop)` (line 98). §3.3's Phosphor-local `private/app.te` adds only `get_prop(appdomain, phosphor_safeboot_prop)`.

Consequence: the type exists, but no domain holds `set` on it — so `adb shell setprop persist.phosphor.safeboot 1` is denied. **This breaks S3 A1 (the primary safe-boot acceptance), S8 D3 and D7 (the drill's set and clear steps), and §6.5's documented recovery escape hatch.** R-2 is closed on paper, open in practice. This is the most consequential finding in the set, because it is invisible to a textual review: the type exists, the reasoning is correct, and only the grant is missing.

**Fix:** add `set_prop(shell, phosphor_safeboot_latch_prop)` to the Phosphor-local `private/app.te` (not to `system/sepolicy`, preserving the zero-fork rule), annotated with §6.5's residual-gap reasoning; make A5's second bullet a concrete grep against the compiled contexts; and add a `neverallow` covering every other domain so "exactly one writer" is enforced, not merely observed.

### F3 — MAJOR — the AID header path does not exist (S2 §2 C15, §3.6, §4)

S2 cites `system/core/include/private/android_filesystem_config.h`, in the citation table (§2 C15), the UID section (§3.6) and the implementation-location table (§4, "+4 lines"). That path does not exist. The real one is:

```
system/core/libcutils/include/private/android_filesystem_config.h
```

(`find . -name android_filesystem_config.h -not -path './prebuilts/*'` returns exactly one non-prebuilt hit, under `system/core/libcutils/include/private/`.) A builder following §4 would create a file in a directory that is not there.

**The AID numbers themselves are sound, also verified:** `AID_OEM_RESERVED_START 2900` / `AID_OEM_RESERVED_END 2999` (lines 171-172 of the correct header), and 2950-2953 are unused. Only the path is wrong.

### F4 — MAJOR — S6's headline acceptance needs an S7 deliverable, and S6 does not depend on S7 (S6 §4 A1/A2 vs §Depends-on; S7 §2.2)

S6's depends-on line names S1, S2, S4 only. Its two central criteria reference a component that does not exist at S6 time:

- A1: "the shell-side and **agentd-side test client** each bind".
- A2: "trigger a card from the **test client** (`submitForApproval`, DESTRUCTIVE)".

S7 §2.2 states: "**S7 adds the client side only:** `IPhosphorBroker` client wrappers in `services/PhosphorIpc/`". So the client is S7's, and A2 — which S6 calls "the whole point of OQ-3" and a "stop-the-line item" — cannot be demonstrated when S6 is accepted.

S6 hedges in §1 ("S6 proves the *service* binds from the shell/agentd path"), but proving a bind requires a client. **Fix:** either S6 ships a minimal probe of its own (a `bindercall`/`am`-driven harness, declared in §1 and §3), or S6 depends on S7 and the order the Supervisor named is amended. Shipping the probe is cheaper and preserves the stated order.

### F5 — MAJOR — the fifth-process contradiction is unresolved, and S2's A8 fails as soon as S1 lands (S1 §1, S2 §1/A8, S8 §4 A4/§5/§7)

- **S1** installs **five** modules, one of which — `phosphor-ctl` — is a distinct process.
- **S2** §1 says "Four domains", and A8 asserts "Four domains, four exec/data types, **no fifth Phosphor domain**" with `rg -c 'type phosphor_.*, domain;'` → 4.
- **S8** §4 A4 discovers it and defers: "`phosphor-ctl` is a fifth process … **Resolve here and feed back to S2**"; §5: "Do not quietly add a domain in S8"; §7 lists it as open item 1.

S8's honesty is commendable but the deferral is in the wrong direction: S2's A8 is an *acceptance gate that fails* once S1's five modules exist, and S2 is accepted **before** S8 exists to raise the point. The named dependency order makes the defect certain rather than merely possible.

**Fix (cheap, and consistent with S8's own contract):** `phosphor-ctl` is read-only, permission-free, and invoked from `adb shell` — it does not need a Phosphor domain. Running it in the existing `shell` domain satisfies S8's "zero privilege" non-goal and needs **no S2 change at all**. S2 should record that decision explicitly (a fifth *process* that is not a fifth *Phosphor domain*, and why), and S8 A4 should assert that outcome instead of re-opening a question S2 can close now. Only if a dedicated `phosphor_ctl` domain is actually wanted must S2's literal "4" change.

### F6 — MINOR — S2's local `app.te` name reads as a fork (S2 §3.3)

Placing `get_prop(appdomain, phosphor_safeboot_prop)` in `packages/phosphor/sepolicy/private/app.te` is correct in mechanism — `appdomain` is public (`system/sepolicy/public/attributes:204`), so a local file may reference it. But a file *named* `app.te` in our private dir shadows nothing yet reads as a merged fork of the real one. Rename to `phosphor_app.te`. Cosmetic; recorded so it is not mistaken for a fork during review.

### F7 — MINOR — S3's `fail_closed_write()` path invites a retry loop (S3 §2.4, §3.2, §3.4)

S3 §3.2's sketch returns `fail_closed_write()` when the `setprop` fails, but the fail-closed action *is* the write. If it fails, the property is absent and agentd does not start — correct, and consistent with §2.1's table. The sketch nonetheless implies a second attempt. State explicitly that `fail_closed_write()` **retries the write of `1` exactly once** and then exits 1, since §3.4's 2 s bound exists precisely to forbid unbounded retry.

### F8 — MINOR — S4 promises a `shutdown` log without a grace window (S4 §2.3/§2.5/A7)

S4 requires a clean 2 s shutdown and A7 requires observing `shutdown`. init's `SVC_GENTLE_KILL` comment (`system/core/init/service.h:60-61`) states: "This service should be stopped with SIGTERM instead of SIGKILL / Will still be SIGKILLed after **timeout period of 200 ms**". Without an explicit `timeout` line, the handler may be SIGKILLed before it logs. **Fix:** add `timeout` (and, if SIGTERM-on-stop is wanted, `gentle_kill` — the parser supports it at `service_parser.cpp:595`), or restate A7 so `shutdown` is best-effort.

### F9 — MINOR — S5 bounds the Safe Browsing decision too narrowly (S5 §2.3)

S5 disables Safe Browsing because enabling it "would send hashes to a remote service", which is right and consistent with §4.1's no-egress posture. But the row reads as an unconditional hardening win when it also removes a defence for any content that reaches the WebView. Since S5's content is local and `data:`-only, the choice is correct *here*. **Fix:** say "no-op-and-correct for a `data:`-only surface; revisit if Phase 6 ever admits fetched content", so it is bounded rather than inherited as a principle.

---

## Retracted findings (recorded so a re-audit does not re-derive them)

- **R1 — RETRACTED (was drafted as BLOCKER): "`init.svc.<name>` reads `absent` for a defined-but-never-started service is wrong; init reports `stopped`."** This is **false**; the specs are right. `Service::StartIfNotDisabled()` (`system/core/init/service.cpp:944-951`) returns without starting and calls **no** `NotifyStateChange()`, so no `init.svc.*` property is ever created for a service that was never started. `NotifyStateChange` is only reached from `Reap()` (`:351`), `Start()` (`:834`, `:935`), and `StopOrReset`/`Timeout` (`:974`, `:986`, `:1035`, `:1037`) — all of which require the service to have run. So `absent` genuinely distinguishes "never started" from "started and exited", and S3 A1 / S4 A2 / S8 §2.3's discriminator is **correct**. This would have been the most damaging false positive in the audit had I shipped it.
- **R2 — RETRACTED (was drafted as MAJOR): "S1 A3's `product_packages.txt` count of 5 is fragile because the file is a transitive package list."** The premise is false. `product_packages.txt` is `strings.Join(ProductPackages, "\n")` (`build/soong/android/product_packages_file.go:36`), and `ProductPackages` is literally `$(PRODUCT_PACKAGES)` (`build/make/core/soong_config.mk:544`) — **top-level only, no dependency closure**. Verified against the real artifact: 1661 lines, zero duplicates, `libc`/`libbase` (dependency-only) absent, `Launcher3QuickStep` (a real `PRODUCT_PACKAGES` entry) present. S1 A3's count of 5 is therefore sound, and `grep -cE '^(phosphor-|Phosphor)'` → 5 will hold as long as the five modules are named as specified. No fix needed.
- **R3 — RETRACTED (was drafted as MAJOR): "S2's `neverallow` on `phosphor_agentd_data_file` violates Treble partition scoping because `data_file_type` belongs to the data scope."** Not supported. `data_file_type` is declared in **public** policy (`system/sepolicy/public/attributes:40`) and is used freely in `plat` `neverallow`s in-tree — e.g. `private/traced_perf.te:64` (`neverallow traced_perf app_data_file_type:file *;`), `private/init.te:837`, `private/isolated_app_all.te:59`. So the shape S2 proposes is precedented and will compile. Not a finding.

---

## Cross-spec consistency

| # | Issue | Specs | Status |
|---|---|---|---|
| X1 | Four domains (S2 A8) vs five installed modules (S1) vs "resolve in S8" | S1, S2, S8 | **Unresolved** — F5; fixable in S2 today |
| X2 | S6 A1/A2 need S7's client; S6 does not depend on S7 | S6, S7 | **Unsatisfied dependency** — F4 |
| X3 | Latch writer required by S2 A5/A7, exercised by S3 A1 and S8 D3/D7, granted by no rule | S2, S3, S8 | **Broken chain** — F2 |
| X4 | Dependency order S1 → S2 → S3–S7 → S8 | all | **Holds**, except the S6↔S7 co-dependency (F4) |
| X5 | No spec requires a capability another spec defers | all | **Holds.** The §3 capability set is uniformly deferred (S6 A7 row-by-row, S8 E12); S7's C-D provisioning deferral is consistent; S5's `RECORD_AUDIO` is declared-but-unused and stated as such |
| X6 | Health-surface ownership: S4 defines, S7 finalises liveness, S8 consumes | S4, S7, S8 | **Holds.** S7 §2.4 explicitly adds no fourth surface |
| X7 | Frame-size coupling: S4 open item 2 ↔ S7 §2.1 | S4, S7 | **Holds.** S7 freezes it at 1 MiB and names the Phase 6 chunking review |

**On the two items Coder surfaced:**

- *The fifth process* — real and **worse than "surfaced"**: S2's A8 is an acceptance gate that fails once S1 lands, and S2 is accepted before S8 can raise it (F5).
- *S1's one adevtool-owned `device.mk` line + `generate-all` re-run* — **verified fully correct.** `vendor/adevtool/config/mk/google_devices/device/akita/device.mk` exists (333 bytes) and `vendor/google_devices/akita/akita.mk:10` does `$(call inherit-product, vendor/adevtool/config/mk/google_devices/device/akita/device.mk)`. The seam S1 picks is the right one, one line is genuinely sufficient, and the regenerate is genuinely mandatory because the generated tree is overwritten. Best-verified claim in the set.

---

## Build reality (criterion 4)

| S1 claim | Verification | Result |
|---|---|---|
| Recipe: `source build/envsetup.sh` → `lunch akita-cur-user` → `m -j24 vendorbootimage vendorkernelbootimage target-files-package` | `docs/PROJECT-STATUS.md:163-168` | **Byte-identical** — same three lines, flags, targets, variant |
| `device.mk` is the writable seam; `akita.mk` inherits it | `akita.mk:10` | PASS |
| `product_packages.txt` is a real build artifact | `product_packages_file.go:36`; present in `out/` (1661 lines) | PASS — not invented (see R2) |
| The count of 5 is achievable | top-level `$(PRODUCT_PACKAGES)` only; 0 pre-existing matches | PASS (see R2) |
| `aapt2` at `out/host/linux-x86/bin/aapt2` | present | PASS |
| `prebuilts/jdk/jdk25/linux-x86/bin/java` | present | PASS |
| `BOARD_PLAT_*_SEPOLICY_DIR` | `KATI_obsolete_var`, fatal (tested with `ckati`) | **FAIL — F1** |
| `selinux_policy` / `sepolicy_neverallows` targets | `build/make/core/Makefile:5450`; `Android.bp:943,1300` | PASS |
| AID numbers 2950-2953 free | OEM range 2900-2999; no collisions | PASS (path wrong — F3) |

**No invented build mechanism found.** Every mechanism S1 relies on exists in-tree. The single failure is a stale variable name, not fabrication.

---

## The six criteria, answered

1. **Fidelity to rev 4 — correct.** OQ-1..OQ-4 are honoured precisely: S5 defers to the GrapheneOS-signed engine and forbids claiming ownership (NOTE-1); S2/S7 carry OQ-2's per-flash Keystore with an explicit stubbed seam and a deleted in-device provisioning path; S6 hosts the card inside the broker and proves it with the shell dead (OQ-3) as a standalone privileged app with a recorded no-escalation statement (OQ-4). §4.1's two layers are correctly split — S5 owns Layer 2 with a `data:`-only intercept, the CSP injected as first head element, and NEW-5's scope statement. NEW-7 is honoured: no `mmap_exec_file_perms` anywhere, `:file *` throughout, verified against `global_macros:25-35`. The one substantive gap is F2 — the latch writer, without which the safe-boot mechanism S3/S8 implement cannot be triggered.
2. **Residuals — R-2 is *not* solved; NEW-1 is locked.** R-2's type is created (S2 §3.1) with correct reasoning, but its writer is granted nowhere (F2) — closed on paper, open in practice. NEW-1's polarity is genuinely protected on both halves: S5 §2.1 gives the four-case table (hand off on absent / unparseable / `1`), a strict parse rejecting `00`/`+0`/`-0`, exception⇒hand-off, a re-check in `onResume`, with A3 making all four acceptance criteria; S3 A4(b) and S4 §2.2 supply the daemon half. It cannot regress without failing an acceptance test.
3. **Cross-spec consistency — X1, X2, X3 are real.** Dependency order holds otherwise; capability deferral is coherent; of Coder's two surfaced items, one is real (fifth process) and one is correct as written (adevtool seam).
4. **Build reality — one blocker, everything else verified.** No invented mechanism.
5. **Vision traps — PASS on both.** The only mention of `agent_core.py`/`server.py` is S4 §2.1's language row naming them as the **source of a port**, matching architecture §8's migration map. No Termux path, no Python runtime, no HTTP front-end, no `runtime/` deployment. Device operations are PM-gated per operation everywhere they appear — S1 §1/A7 forbid them outright, S3 §7 is a dedicated gate, S8 §2.4 marks every `⚠` step and A9 fails the spec for an unapproved operation, with a withheld approval marking the phase incomplete rather than forcing a pass.
6. **Real contracts — yes.** Behaviour, acceptance, edge cases, implementation location and Definition-of-Done are present in all eight. The weak spots are acceptance criteria that cannot pass (F1, F2, F4) — exactly the class an audit must catch, since they surface only at execution time.

---

## Required before acceptance

1. **F1** — use `SYSTEM_EXT_*_SEPOLICY_DIRS`; restate S2 C14 against `Android.bp:943`.
2. **F2** — grant the latch writer (`set_prop(shell, phosphor_safeboot_latch_prop)`) and make A5/A7 check the compiled contexts. *Until this lands, the safe-boot drill cannot run.*
3. **F4** — give S6 a runnable client probe of its own, or make S6 depend on S7.
4. **F5** — close the fifth-process question in S2 (recommended: `phosphor-ctl` runs in the `shell` domain; no fifth domain).
5. **F3, F6, F7, F8, F9** — correct in the same pass.

---

# Repair round — final narrow re-audit (rev 2 of this audit)

**Re-audited:** the five changed specs — `P5-S1`, `P5-S2`, `P5-S6`, `P5-S7` (F4 wording), `P5-S8` (F5 wording).
**Unchanged and verified byte-identical:** `P5-S3` (18394 B, 20:27:16), `P5-S4` (17880 B, 20:23:26), `P5-S5` (20871 B, 20:24:16) — the three ACCEPT specs were not touched, so nothing in them was weakened.
**This audit file was not modified during the repair round** (still 21051 B, mtime 20:44:19), and R1–R3 were not re-litigated by Coder: S1 §5 A3 still asserts the count-of-5 that R2 vindicated, S3:149 still carries the `absent`-vs-`stopped` discriminator that R1 vindicated, and S2:152 still carries the `phosphor_agentd_data_file:file *` neverallow that R3 found unobjectionable.

**Verdict: CONFIRMED — all eight specs ACCEPT. The Phase 5 spec set is approved and implementation may proceed on PM delegation.**

## F1 — CLOSED

S1 §3 B5 now specifies `SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` / `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` (S1:97-98), and §3 B5's residue paragraph states the abort correctly, with the evidence I supplied: `config.mk:163-164`, `sepolicy/README.md:48-49`, and the explicit warning that "the abort fires on the first `m`, i.e. **before any Phosphor module is reached**" (S1:107). §8's open item 1 is struck through and marked CLOSED with the same citations (S1:210).

**S2 C14 restates the mechanism correctly** (S2:49): "`system_ext` policy is admitted to the `sepolicy_neverallows` target — which is why the §8 `neverallow` set is legal to compile there", citing `Android.bp:943`. The "platform policy dirs" hand-wave is gone. Verified against the tree: `se_neverallow_test` srcs at `Android.bp:946-953` do include `system_ext_public_policy + system_ext_private_policy`.

**No obsolete-variable residue anywhere in the spec set.** The only occurrences of `BOARD_PLAT_*_SEPOLICY_DIR` in the eight specs are S1:101-105 (the prohibition and its citations) and S1:210 (the closed item) — both prohibitive, neither usage.

**One placement nuance (non-blocking, recorded).** `SYSTEM_EXT_*_SEPOLICY_DIRS` are **board** variables (`product_validation_checks.mk:28-33` lists them in `known_board_variables`), and S1 sets them in `phosphor.mk`, a **product** makefile. That works because `envsetup.mk` includes `product_config.mk` at :350 and `board_config.mk` at :366, so the product-inherited assign lands before board config is consumed — and in any case akita already assigns both in `BoardConfig.mk:95,98`, so S1's `+=` accumulates onto a live list. The spec's own `[VERIFY AT BUILD]` (S1:109) covers the spelling. No action required; recorded so a builder who sees the board/product asymmetry does not "fix" it into a `BoardConfig` edit and break the one-line-seam constraint of B4.

## F2 — CLOSED

The latch is now closed in practice, not on paper:

- **Grant:** `set_prop(shell, phosphor_safeboot_latch_prop)` at S2:138, with a comment (S2:130-137) that names the exact failure mode I raised — "without this grant the latch type exists but NO non-init domain may set it … A5/A7 would pass textually while the drill (S3 A1, S8 D3/D7) is denied at runtime."
- **Enforcement:** `neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set;` at S2:173, with the reasoning that without it "exactly one writer" is merely true today and quietly becomes false the next time someone grants anything near it.
- **Functional acceptance:** A5's bullet now requires the device proof — "`adb shell setprop persist.phosphor.safeboot 1` succeeds and `getprop` reads `1` with **no** `avc: denied` for `phosphor_safeboot_latch_prop`" (S2:262), explicitly noting "a `setprop` that is *denied by SELinux* fails this criterion — that is the exact failure this finding was raised for", and demanding that an unapproved write be recorded as "policy-compile-verified only, writer not exercised". A7's expected-line list is now exact and exhaustive (S2:268). A2 extends the liveness test to the new rule (S2:244).
- **Set-only semantics unchanged:** S2:297 states that C8/C9 mean the rule cannot see a value at all, so "absent→1 only, 0 ignored" remains enforced in keygate's binary (S3 §2.1/2.2), and that any proposal to grant the latch to `phosphor_shell`/`agentd`/`keygate`/`broker` "so it can be cleared on-device" is a **refused** change.

**Re-derived coherence — I could not open a second writer path, and found no contradiction with keygate's reads:**

| Claim | Verification |
|---|---|
| The grant is precedented, not novel | `set_prop(shell, remote_prov_prop)` (`private/shell.te:115`) against `system_public_prop(remote_prov_prop)` (`public/property.te:259`) — **exactly** S2's shape (shell setting a `system_public_prop`) |
| `system_public_prop` emits no conflicting neverallow | `public/te_macros:956` is `define_prop` only — a type declaration, no rules |
| No broad neverallow blocks shell's set | No `neverallow` in `private/property.te` names `appdomain`/`shell`; `system_property_type:property_service` appears in no rule |
| `shell` is a legitimate target | `public/shell.te:2` — `type shell, domain, mlstrustedsubject` |
| keygate's **read** is not touched by the **set** neverallow | `get_prop(…latch…)` (S2:101) expands to `{getattr open read map}` on the `file` class; the neverallow constrains `property_service set`. Disjoint permission classes — no contradiction. **Confirmed coherent.** |
| `-init` subtraction is necessary | `public/init.te:2` — `type init, domain, mlstrustedsubject`. `init` **is** in `domain`, so the subtraction is required, and the rule is well-precedented in form (`private/apexd.te:244`, `derive_sdk.te:13`, `domain.te:846`) |

S2's own open item 7 asks whether `-init` is needed; the evidence above **closes it**: keep the subtraction.

## F4 — CLOSED (deferred acceptance, no cycle)

S6's depends-on now names **P5-S7** with the precise reason (S6:5), and S6:7 states the order consequence: "S6 *implements* the service before S7 … but S6 *cannot be signed off* until S7's client exists … the effective order is S6 service → S7 client → S6 acceptance → S8. This is a **deferred acceptance, not a circular dependency**: no artifact of S6 depends on an artifact of S7, only its acceptance criteria's *caller* does."

S7:6 mirrors it from the other side ("Mutual dependency with S6, stated so it is not misread … S6's A1/A2 are signed off at this spec's landing"), and both agree on the same four-step order. S7 retains everything my audit accepted: `SOCK_SEQPACKET`, `SO_PEERCRED` uid+label, `peer_rejected` logging, the versioned frame header, and the 1 MiB limit frozen with the Phase 6 chunking note (S7:50,130,154,167,178). The rejection of the throwaway-probe alternative is justified on the right ground — two callers to keep in agreement.

**No cycle:** S6 supplies the service artifact, S7 supplies the client artifact; neither requires a not-yet-existing artifact of the other. The dependency graph is acyclic at artifact level, which is the level that matters for build order.

## F5 — CLOSED (invariant now true everywhere it appears)

| Site | Statement |
|---|---|
| S1:19 | `phosphor-ctl` "**not** a fifth Phosphor process/domain — it is an on-demand tool invoked from `adb shell` and runs in the existing `shell` domain, so it needs no `phosphor_*` domain and no fifth AID" |
| S1:48 | Same invariant in the summary row, cross-referencing S2 A8 and S8 A4 |
| S2 A8 | "four Phosphor domains, and `phosphor-ctl` is not one of them"; `rg -c 'type phosphor_.*, domain;'` → 4; "Four AIDs (§3.6), four `seapp_contexts`/`file_contexts` domain labels" |
| S2:312 | Definition-of-done: "**4 domains** … **4 AIDs**, 3 property types … 4 file types" |
| S8 A4 | "runs in the existing `shell` domain and has no Phosphor domain of its own — this is S2 A8's decision … S8 asserts it rather than re-opening it"; and "If any diagnostics check needs a privilege `shell` lacks, the check is dropped — not granted, and above all not given a domain" |
| S8:198, S8 open item 1 | Recorded as **resolved in S2 A8**, not as an open question |

**Does `phosphor-ctl`-in-`shell` break anything my audit assumed?** No. My F5 recommended exactly this, and I re-checked its two preconditions: (a) `shell` is a real `domain` type (`public/shell.te:2`) with no `init.svc`/`.rc` stanza needed — S8:169-172 requires the binary declare no `user`/`.rc` and be never started by init, so no service-context or sepolicy addition is implied; (b) it needs no AID, since it runs under the pre-existing shell UID. The four-AID/four-domain invariant is therefore both true and sufficient. The one consequence worth stating for the builder: `phosphor-ctl` inherits `shell`'s access, so a diagnostics check that needs a privilege `shell` lacks must be dropped — which S8 A4 now says explicitly, closing the escalation path rather than leaving it as a judgement call.

## Scope

Only the five reported files changed (S1 +2266 B, S2 +9766 B, S6 +2246 B, S7 +768 B, S8 +1608 B). The three ACCEPT specs are byte-identical. `SPECS-AUDIT.md` was untouched by the repair round. R1–R3 stand as retracted; nothing was re-litigated in their favour or against.

**One residual note, non-gating, for the builder (not a spec defect).** S2 places `allow`/`set_prop`/`neverallow` statements in its own `sepolicy/public/` directory. AOSP's convention for *its* `public/` dirs is types-only ("DO NOT ADD allow, neverallow, or dontaudit statements here", `public/app.te:11-13`), and no real OEM `system_ext/public` dir in this tree carries rules. I verified this is a **style** concern, not a build failure: `system_ext_public_policy` is included in `system_ext_sepolicy.conf` (`Android.bp:338`) and in `sepolicy_neverallows` (:946-953), the API-freeze test covers only `base_plat_pub_policy_for_freeze_test` (`Android.bp:965-985`), so these rules compile and their neverallows are checked. No action needed for Phase 5; noted so the convention violation is a recorded, deliberate choice rather than a later surprise.

---

*End of repair-round re-audit. Verdict: **CONFIRMED — all eight specs ACCEPT; the Phase 5 spec set is approved and implementation may proceed on PM delegation.** F1 closed with the mechanism corrected and S2's C14 restated against `Android.bp:943`; F2 closed with the grant, the enforcement, the functional acceptance proof, and the set-only semantics intact — and independently re-derived as coherent (precedent `shell.te:115` + `property.te:259`, no second writer path, no conflict with keygate's `get_prop`); F4 closed as a deferred acceptance with an acyclic artifact graph, mirrored consistently in S6/S7/S8; F5 closed with the four-domain/four-AID invariant now true at all six sites and no hidden cost in the `shell`-domain resolution. The three previously ACCEPTed specs are byte-identical to the audited versions. One non-gating style note recorded on S2's `public/` rule placement. No spec file was modified by this re-audit; no device operation was performed.*