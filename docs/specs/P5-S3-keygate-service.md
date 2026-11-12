# P5-S3 — `phosphor_keygate`: the boot-decision service

**Phase:** 5 · **Spec ID:** P5-S3 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (module `phosphor-keygate`, `packages/phosphor/init/`, `/system/bin/phosphor-keygate`) and **P5-S2** (`phosphor_keygate` domain, `phosphor_keygate_exec`, `phosphor_safeboot_prop`, `phosphor_safeboot_latch_prop`, the subtraction-form property `neverallow`). Neither is optional: without S2 the service cannot write its one property, and without the latch type the adb trigger is unachievable (audit R-2).
**Blocks:** **P5-S4** (agentd's start condition *is* this service's output), and therefore S5–S7's normal-boot path. Also the *normal* half of S8's acceptance.
**Authority:** architecture §6.5 (safe boot, redesigned — BLOCKER-1 resolution), §2.2 (lifecycle), §2.1 (keygate row), §8's map + SELinux section; rev-4 findings **NEW-6** (the one-way property is a policy fact, not a value check) and **NEW-1** (polarity); `docs/P4-ARCH-AUDIT.md` residual **R-2**.

---

## 1. Scope

One file of init config plus one small native binary that:

1. Runs once, early, **`class core`, `oneshot`**, started `on late-init`.
2. Reads three trigger sources and folds them into a single decision.
3. Writes exactly one property, `sys.phosphor.safeboot`, as `0` (normal) or `1` (safe boot).
4. **Fails closed**: any indecision, any read error, any short-circuit ⇒ `1`.
5. Exits. It holds no capabilities, starts nothing, and cannot grant anything.

Downstream: `phosphor_agentd` is `disabled` and starts only on `on property:sys.phosphor.safeboot=0` (S4 provides the `.rc`; this spec owns the property contract).

### Non-goals

- **Not** the hardware key chord implementation. §10.2 lists "keygate hardware-key chord semantics (which chord; how read without a live framework)" as undecided, owner Phase 5. This spec therefore ships a **stub chord reader that always reports "no chord"** and names the seam; the chord must not block S3's acceptance, and shipping a stub is fail-safe because the other two triggers carry REC-2 (§6.5 residual gap; NEW-6(b)).
- No agentd start, no broker interaction, no logging to a socket, no network, no binder.
- No shell/app behaviour (S5).
- No device operation without PM approval (§7).

---

## 2. Behaviour contract

### 2.1 The decision

Inputs, in fixed precedence — **any `1` wins; only an all-`0` read yields `0`**:

| # | Source | Read | Semantics |
|---|---|---|---|
| T1 | `ro.boot.phosphor.safeboot` | `ro.boot.*`, immutable at runtime, set host-side via kernel cmdline out-of-band | `1` ⇒ safe boot. **The load-bearing trigger** (NEW-6(b)). Unreadable ⇒ treat as `1`. |
| T2 | `persist.phosphor.safeboot` | the set-only latch; **`absent→1` only, a value of `0` is ignored** | `1` ⇒ safe boot. Unreadable ⇒ treat as `1`. |
| T3 | hardware key chord | stub reader in this spec → reports "no chord" | chord held ⇒ safe boot |

Decision table (the whole truth table, no omissions):

| T1 | T2 | T3 | `sys.phosphor.safeboot` | Rationale |
|---|---|---|---|---|
| 0 | 0/absent | none | **0** | normal boot — the only path to `0` |
| 1 | * | * | **1** | host asked; host is the trusted recovery authority |
| 0 | 1 | * | **1** | latch set-only, cannot be cancelled by anything on-device |
| * | * | held | **1** | chord |
| any read error / any unparseable value / binary cannot decide | | | **1** | **fail-closed (§6.5)** |
| keygate never ran at all | | | *property absent* | agentd never starts (`on property:…=0` cannot fire ⇒ absent ⇒ down). Correct by construction; see §6 edge case 1. |

**T2's asymmetry is deliberate and must be commented in the source:** `0` is ignored, `1` latches. This is *not* enforceable by policy — `property_service set` has no value dimension (NEW-6, C8) — so it is enforced **in this binary** and stated as such. A binary-level rule is honest; a sepolicy rule pretending to do it would not be.

### 2.2 The latch's one-way property, stated correctly (NEW-6)

The completion note and the source comment must both say the true thing, not the withdrawn thing:

- **(a)** No Phosphor domain holds `set` on `phosphor_safeboot_latch_prop` — enforced in S2's policy. Nothing inside the running system can write the latch in **either** direction. (Keygate **reads** it only; it does not clear it.)
- **(b)** The immutable host-set `ro.boot.phosphor.safeboot` carries REC-2 **independently** of the latch. The latch is a convenience.
- **(c)** For the one documented writer — the host, over adb, out-of-band — clearing is **exactly as symmetric as setting**, because the host+cable operator is already the trusted recovery authority (§6.5 residual gap, REC-1).

**Explicitly forbidden in this spec:** writing any comment, commit message, or doc line claiming a `neverallow` sits "on the reverse direction". That formulation is withdrawn as inexpressible (NEW-6).

### 2.3 What keygate must never do

- Never write any property other than `sys.phosphor.safeboot` (S2's subtraction `neverallow` enforces it; the binary must not attempt it either — an attempted denied write is a `DENIED` in the log, and the auditor treats a Phosphor-caused avc denial as a defect).
- Never start, signal, or probe agentd; never touch `phosphor_agentd_exec` or `phosphor_agentd_data_file` (S2 `:file *` neverallows).
- Never use binder, sockets, or a device node other than the key input device (stub: none).
- Never block boot: bound its own runtime (§3.4) and exit.

### 2.4 Runtime shape

- `oneshot`, `class core`, `user phosphor_keygate`, `group phosphor_keygate`, no `capabilities`, no `socket`, no `onrestart`.
- Structured log: exactly one line, `phosphor-keygate: safeboot=<0|1> reason=<t1|t2|t3|undecided>` to stderr → logd. **No secret content; no property dumps.**
- Exit status: `0` on a decided write, `1` on write failure after the fail-closed attempt. Exit status is not consumed by init (it is a oneshot), so it exists only for diagnostics — the *property*, not the status, is the contract.

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| init config | `<tree>/packages/phosphor/init/phosphor_keygate.rc` |
| Source | `<tree>/packages/phosphor/services/PhosphorKeygate/main.cpp` |
| Module | `<tree>/packages/phosphor/services/PhosphorKeygate/Android.bp` (created in S1 as a stub; S3 fills `srcs` + `init_rc`) |
| Chord seam | `<tree>/packages/phosphor/services/PhosphorKeygate/key_chord.h` — a single function `bool chord_held()` returning `false`, documented as the §10.2 open item |
| Domain/property | S2's `phosphor_keygate.te`, `property.te`, `property_contexts` |

### 3.1 `.rc` verbatim (architecture §6.5, verbatim by intent)

```
service phosphor_keygate /system/bin/phosphor-keygate
    class core
    user phosphor_keygate
    group phosphor_keygate
    oneshot

on late-init
    start phosphor_keygate
```

`[VERIFY AT BUILD: exact init syntax — architecture §6.5 explicitly defers "exact init syntax" to Phase 5. If `on late-init` proves too early to read `persist.*` or too late to beat the agentd trigger, record the actual trigger used (`on early-init`/`on init`/`on property:sys.boot_completed=1`) and justify it; the architecture's constraint is "one early decision, fail-closed, agent gated on its result", not the literal event name.]`

**Ordering hazard — check it explicitly, do not assume it.** init evaluates `on property:` triggers when the property is **set**. If keygate writes `sys.phosphor.safeboot=0` before agentd's `.rc` (and therefore the `on property:sys.phosphor.safeboot=0` block) has been parsed, the trigger never fires and agentd never starts on a **normal** boot — a fail-closed-looking system that is simply dead.

- **Primary resolution:** keygate runs `on late-init`, by which point all `.rc` files are loaded, so its write lands after the trigger is registered. Verify this on device (A9).
- **Forbidden resolutions:** (a) a second-condition trigger such as `on late-init && property:…` — this tree's init matches one property per `on property:` block (§6.5: "`on property:` triggers match one property"); (b) any design where agentd **re-derives** the decision at startup (re-evaluating `ro.boot`/the latch/chord) — that is a **second decision point**, which §6.5 forbids and which would restore the very split-brain NEW-1 closed. Note the distinction from S4 §2.2: agentd's own start-condition check is **refuse-only** — it may *withhold* itself when the property is not `0`, and it can never *grant* itself anything, so it adds a fail-closed guard rather than a second decision; (c) an unconditional `start phosphor_agentd` anywhere.

So there are exactly two compliant outcomes: keygate's write lands after the trigger is registered (proven, not assumed), or S3 **fails** and the finding returns to the architecture owner — a start condition that depends on unverified init parse order is not a contract.

### 3.2 Source sketch (contract, not final code)

```cpp
// Reads T1/T2/T3, folds, writes exactly sys.phosphor.safeboot. Fail-closed.
int main() {
  int t1 = read_ro_boot();      // -1 = unreadable  -> treated as 1
  int t2 = read_latch();        // -1 = unreadable  -> treated as 1; 0 = IGNORED
  int t3 = chord_held() ? 1 : 0;
  bool safe = (t1 != 0) || (t2 == 1) || (t3 == 1);   // -1 != 0 -> safe
  if (!setprop_bool("sys.phosphor.safeboot", safe)) return fail_closed_write();
  log("phosphor-keygate: safeboot=%d reason=%s", safe ? 1 : 0, reason);
  return 0;
}
```

The `chord_held()` stub returning `false` is a **declared seam**, not a silent gap: `reason=` is never `t3` in S3.

### 3.3 Size and dependencies

≤ 300 lines, libc only (`libbase` for `android::base::SetProperty`/`GetProperty` is acceptable and preferred). No `libbinder`, no `libhidl`, no framework dependency — keygate must be able to run **before** any surface is up (§6.5's whole point).

### 3.4 Bounds

Hard self-imposed deadline: if keygate has not decided within **2 s** of `main()`, it writes `1` and exits (fail-closed, bounded). No sleep loops, no retries beyond one property read.

---

## 4. Acceptance criteria

**A1 — Forced property ⇒ no agentd (the primary acceptance).** Requires **PM approval for this device operation** (§7). With S4 landed:
```bash
adb shell setprop persist.phosphor.safeboot 1
adb reboot
# after boot:
adb shell getprop sys.phosphor.safeboot          # -> 1
adb shell getprop init.svc.phosphor_agentd       # -> absent  (NOT "stopped")
adb shell pidof phosphor-agentd                  # -> empty
```
Pass = the three lines above. `absent` vs `stopped` is the discriminator: the service must never have been *started*, not merely have exited. A `stopped` reading fails the spec.

**A2 — Normal boot ⇒ `0` and agentd runs.** Clear the latch **as the host** (the documented writer):
```bash
adb shell setprop persist.phosphor.safeboot ""     # or the tree's documented clear form
adb reboot
adb shell getprop sys.phosphor.safeboot            # -> 0
adb shell getprop init.svc.phosphor_agentd         # -> running
```
Pass = `0` **and** `running`. (A2 depends on S4; if S3 is verified before S4 lands, the accepted substitute is `sys.phosphor.safeboot` = `0` plus `init.svc.phosphor_agentd` = `absent` *by design* because the service does not exist yet — recorded as a partial, and A2 is re-run at S4.)

**A3 — Host-immutable trigger ⇒ no agentd, on a *normal* latch.** `ro.boot.phosphor.safeboot=1` via kernel cmdline (`fastboot oem`/`fastboot boot` path per the tree's support; requires PM approval). Pass = `sys.phosphor.safeboot` = `1`, agentd absent, and `ro.boot.phosphor.safeboot` unchangeable at runtime (`setprop` on it is refused — this is the REC-2 "without the agent's cooperation" property).

**A4 — Fail-closed on indecision.** Two sub-cases, both without a device:
- (a) **Static/lab:** the binary run on the host (or a `cbindgen`-free shim) with property reads stubbed to fail returns `safe=1`. Recorded as a unit-level check.
- (b) **On-device:** unload the `.rc` (keygate never runs) and boot. Pass = `sys.phosphor.safeboot` **absent** and agentd **absent** — the absence of a decision lands on the safe side because agentd's start condition is `=0`. This is the pairing NEW-1 demanded; A4(b) is its device proof.

**A5 — One property, only.** `logcat -b all -d | grep -E 'avc: *denied' | grep phosphor_keygate` → empty. Any keygate-caused denial fails the spec (it means the binary attempted something S2 denied, or S2 mis-granted).

**A6 — Structured log, one line.** `logcat -d -s phosphor-keygate` shows exactly one line per boot with `safeboot=` and `reason=`; the reason is `t1`, `t2`, `undecided` — **never `t3`** in S3 (stub), and that is recorded, not hidden.

**A7 — No capability surface.** The `.rc` has no `capabilities`/`socket`/`onrestart` line; `ps -A -o NAME,LABEL` for the (brief-lived) process shows `u:r:phosphor_keygate:s0` — or, since it is oneshot and exits fast, the label is proven instead by `dmesg`/`avc` naming `s:0` in A5 plus the compiled `seapp`/domain assignment from S2. Do not claim a process-label observation that was not captured.

**A8 — Bounded runtime.** Time from `start` to exit `≤ 2 s`; `logcat` timestamps or an init-triggered marker. No boot stall.

**A9 — Ordering proven, not assumed** (§3.1): the completion note states how init's property-trigger ordering was established (e.g. keygate's log line timestamp precedes `init.svc.phosphor_agentd=running`, per boot, ≥5 boots). If ordering cannot be proven, S3 **fails** and the finding returns to the architecture owner.

**A10 — Documentation honesty.** The source comment, the `.rc` comment, and the completion note each state NEW-6's three facts and **do not** claim a value-level `neverallow`. `rg -n 'reverse direction' packages/phosphor` → empty.

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| `persist.phosphor.safeboot` = `0` after being `1` (host cleared it) | Latch ignores `0` **per boot**; a cleared latch does not force safe boot. Keygate does **not** write `0` back to the latch (it has no `set` there). So: `1` boot → host sets `0` → next boot reads `0` ⇒ ignored ⇒ normal. This is the documented clear path; it is the *only* clear path and it is host-only. |
| `ro.boot.phosphor.safeboot` absent (normal case on our build) | Empty `ro.boot.*` reads as empty string ⇒ **not** `"1"` ⇒ contributes `0`. Distinguish carefully: absent-as-empty is *normal*, absent-because-unreadable is *fail-closed*. The binary must tell them apart by read-`errno`, not by emptiness alone. |
| `ro.boot.phosphor.safeboot=0` explicitly | `0` ⇒ contributes `0`. Only `1` triggers. |
| Property already `1` from a previous boot and keygate never runs | agentd absent (A4b). Never "recovered" automatically — recovery is host or chord. Correct: safe boot must not self-clear. |
| Two triggers disagree (T1=0, T2=0, chord held) | chord wins ⇒ `1` (any-`1`-wins). |
| Keygate crashed before the write | No property ⇒ agentd absent ⇒ safe boot. Fail-closed. (`oneshot` + no `onrestart` ⇒ no crash loop.) |
| Keygate crashed **after** writing `0` | agentd starts. Accepted: the decision was taken and written; a post-write crash cannot un-take it, and it holds no privilege to have abused. Recorded, not hidden. |
| `late-init` fires more than once (some trees) | `oneshot` makes extra `start` a no-op. Idempotent anyway: the decision is a pure function of the triggers. |
| Full-disk / no logd | `setprop` still succeeds; the one log line may be lost. A6 tolerance: a missing log line on a verified-good boot is a NOTE, not a failure — the *property* is the contract. |
| Key chord reads a device node before it exists | Stub returns `false`, so S3 cannot hit this. When the chord lands (Phase 5 debt), the reader must fail **closed** (`chord_held()` unreadable ⇒ treat as held ⇒ safe boot) — record this requirement now so the later implementer inherits it. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A10 pass; A1/A2/A3/A4b carry PM-approved device operations.
- [ ] Decision table implemented exactly as §2.1; T2's `0`-is-ignored asymmetry present **and commented**.
- [ ] Fail-closed proven both ways (decided-and-wrong-side via A4a/a/b, never-ran via A4b).
- [ ] NEW-6's three facts stated; no "reverse direction" claim anywhere.
- [ ] NEW-1's polarity pairing shown: agentd starts only on `=0`; absence ⇒ down.
- [ ] R-2's latch **exercised** on-device (A1) — this is where the audit residual becomes device-proven rather than policy-proven.
- [ ] Chord stub is a named seam with the fail-closed requirement recorded for the future implementer.
- [ ] Ordering (A9) proven, not assumed.
- [ ] Zero keygate-caused avc denials.

## 7. Device-operation gate (must appear in the builder's plan)

A1, A2, A3 and A4(b) each require **a reboot of the Pixel**, and A3 requires a kernel-cmdline mutation. Each is a separate, explicitly-approved device operation:
- Approval: **PM, per operation**, before execution (vision: "Do not flash or wipe the phone without the user's clear approval for that specific operation"; architecture §6.5 makes the host path the trusted recovery authority).
- No flash, no wipe is required by this spec. If a build must be installed, that is S1/S8's gate, and the recovery ladder of `docs/PROJECT-STATUS.md` §8 must be re-confirmed available (USB rehearsal, `fwupd` stopped) **before** the reboot.
- Stop rule: if A1 cannot be reached without a flash, stop and return to the PM; do not extend the spec's authority.

## 8. Open items created by this spec

1. The key chord (which chord, how to read without a live framework) — **still open**, §10.2 owner Phase 5; this spec ships the stub and the fail-closed requirement for the successor.
2. The correct early init trigger that both reads `persist.*` and precedes agentd's consumer (§3.1/A9) — builder, proven empirically.
3. The documented host **clear** form for the latch (§5 row 1) — builder, must be stated in the completion note so the recovery procedure is written down somewhere executable.
4. `ro.boot.phosphor.safeboot` readability under keygate's domain (§2 A3) — carried, gates A3 only.
