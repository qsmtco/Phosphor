# P5-S6 — `PhosphorBroker`: standalone platform-signed app (empty capability surface + approval-card host)

**Phase:** 5 · **Spec ID:** P5-S6 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (`PhosphorBroker` module, `/system/priv-app/PhosphorBroker/`), **P5-S2** (`phosphor_broker` domain, `seapp_contexts`, `r_file_perms` on `phosphor_risk_policy_file` and **no write**, `neverallow` on the artifact), **P5-S4** (agentd must be alive to prove the bind path), **P5-S7** (**the client side** — `IPhosphorBroker` client wrappers in `services/PhosphorIpc/`, S7 §2.2 — without which A1/A2 cannot be exercised at all).
**Blocks:** **P5-S7** — S7's broker binder surface (client wrappers, denial tests) builds on this app; S8's checklist references the card. Phase 8's real classifier and Phase 9's capabilities fill the surface left deliberately empty here.
**Order consequence (F4, stated so the cycle is not read as an error):** S6 *implements* the service before S7 (S7's client cannot exist without a service to call), but S6 *cannot be signed off* until S7's client exists, because A1/A2 are exercised through it. So the effective order is S6 service → S7 client → S6 acceptance → S8. This is a **deferred acceptance, not a circular dependency**: no artifact of S6 depends on an artifact of S7, only its acceptance criteria's *caller* does. The alternative the audit also allowed (S6 shipping its own throwaway probe) was rejected because it would duplicate S7 §2.2's client and leave two callers to keep in agreement.
**Authority:** architecture §9 **OQ-4 DECIDED** ("standalone platform-signed app; escalate … only if a specific capability demands it") and **OQ-3 DECIDED** (broker-hosted approval card); §6.2 (`[ADAPTED FROM SPEC-002 REC-3]` — card native, system-verified, content from the registry, renders even if the WebView is dead); §10.1 Z3 (may hold §3 permissions, must never exceed §3's surface / write the artifact / classify more weakly than agentd); §8's map (broker box); §3 (**the single source** for the permission set — MAJOR-5: "a list restated elsewhere is what let rev 1's errors propagate").

---

## 1. Scope

Stand up the broker **as a process and an app**, at the hosting shape the Captain ruled, with an **empty capability surface** and a **working approval card host**:

1. A launchable platform-signed `android_app`, package `com.phosphor.broker`, installed `/system/priv-app/PhosphorBroker/`, privileged.
2. A **bound binder service** (`PhosphorBrokerService`) with a minimal AIDL surface: `ping()`, `policyVersion()`, `submitForApproval(request)` → `decision`, `cancel(token)`.
3. The **pending-approval registry**: single-use, 5-min TTL, keyed to the originating session (§6.2/R-GATE-6) — real in S6, because the card must render *from* it.
4. The **approval card**: a platform-styled native dialog built from the registry entry, showing the exact tool call (method + arguments as a system-verified string), with Approve/Deny. **It must render with the shell dead.**
5. Policy-artifact read + `policy_version` check, fail-closed on missing/unparseable/mismatched version (§6.3(2)).
6. **Zero Android capability permissions granted** in S6 — the §3 set is a *Phase 9* manifest task, and granting it now would create a privileged surface with nothing behind it. This is the "empty capability surface" the Supervisor's order names.

### Non-goals

- **No capability execution.** No telephony, SMS, contacts, notifications, settings, audio, sensors, location, camera, Bluetooth, clipboard, torch, vibrator, apps, files. Not one row of §3 is implemented in S6.
- **No §3 permissions declared.** See §2.3 for the enforcement of this and the recorded reason.
- No classifier (Phase 8). S6 reads the artifact for its **version** and fails closed; it does not classify.
- No agentd→broker AIDL binding from agentd's side — that is **S7's** client (S7 §2.2: "S7 adds the client side only: `IPhosphorBroker` client wrappers in `services/PhosphorIpc/`"). S6 proves the *service* binds and is callable; **A1/A2 are exercised through S7's client**, which is why S6 now depends on S7. S6 ships no probe of its own (see §2.2).
- No notification-listener overlay entry (§3 `notif.listen`, Phase 9).
- No device operation beyond what S3/S4 already approved (see §6).

---

## 2. Behaviour contract

### 2.1 Hosting shape and lifecycle (C2 — OQ-4 DECIDED)

- `android_app`, `platform_apis: true`, `certificate: "platform"`, `privileged: true`, `minSdk` per tree.
- `PhosphorBrokerService` is a **bound** service, `android:exported="false"` plus an explicit signature-level `android:permission="com.phosphor.permission.BROKER"` defined by the app itself with `protectionLevel="signature"` — two independent gates (exported + signature permission), so only platform-signed callers can bind.
- **Starts on shell/agentd bind; survives agent death** (§2.2: "starts on shell bind; survives agent death so pending approvals are not lost"). Binding, not `START_STICKY` from boot: the broker must **not** auto-start in safe boot (§6.5: "`PhosphorBroker` likewise does not auto-start"). Consequence to state: in S6 the broker is not running until something binds — and in safe boot nothing binds, which is the required behaviour.
- The approval card's Activity is `exported="false"`, launched by the service with `FLAG_ACTIVITY_NEW_TASK` from a **broker process context**, so it renders without the shell.

### 2.2 AIDL surface (S6-minimal, S7 extends)

**The client side is S7's, not S6's.** S7 §2.2 owns the `IPhosphorBroker` client wrappers in `services/PhosphorIpc/`; S6 owns the service, the registry, and the card. Acceptance criteria A1/A2 below are therefore *exercised through S7's client*, which is exactly why S7 is in this spec's depends-on list and why S6's sign-off waits for S7 (§Depends-on, "Order consequence"). S6 deliberately ships **no** probe of its own: two callers to keep in agreement is a worse outcome than one caller arriving one spec later.

```aidl
interface IPhosphorBroker {
  int ping();
  String policyVersion();
  ParcelableDecision submitForApproval(in ApprovalRequest request);
  void cancel(long token);
}
```

- `ApprovalRequest` carries: `sessionId`, `method`, `argsJson` (the exact call), `classification` (`SAFE|DESTRUCTIVE|DESTRUCTIVE-READ` — the **closed enum**, §6.3/MAJOR-7; no other name ever appears), `policyVersion`.
- `Decision` = `APPROVED | DENIED | EXPIRED | NOT_IMPLEMENTED | VERSION_MISMATCH`.
- **No method in S6 executes anything.** The contract is that a `submitForApproval` for a real capability returns `NOT_IMPLEMENTED` **after** the card flow, so the UI path is exercised while capability surface stays empty. The alternative (short-circuit to `NOT_IMPLEMENTED` before the card) would leave the card untested — the one thing S6 exists to prove.
- `SAFE` handling in S6: also `NOT_IMPLEMENTED` (execution is Phase 8/9), and **no card** is shown — `SAFE` never prompts (§6.3, R-GATE-2).
- `DESTRUCTIVE-READ` is **never auto-approved by any policy entry** (§6.3) — S6 must reflect that even though nothing executes: the code path may not contain an auto-approve branch for it.

### 2.3 Permission surface: empty, and provably so

- `AndroidManifest.xml` declares **zero** `<uses-permission>` entries in S6. Not one row of §3.
- **Why:** §3's inventory is the Phase 9 build deliverable, and several rows are `dangerous`+`hardRestricted` (`READ_SMS`/`SEND_SMS`, MAJOR-4) requiring allowlist entries in our tree — a build deliverable that cannot be verified until the capability exists. Declaring the set now would ship a privileged app holding telephony/SMS/contacts grants with no code behind them: an unused-privilege surface, and the exact shape that MAJOR-5 says lets errors propagate.
- **The empty surface is audited, not asserted:** A5 greps the merged manifest and the APK, and A7 requires that the §3 rows are listed in the completion note as **Phase 9 deferred**, row by row, so nothing looks forgotten. `wifi.toggle`'s system-app requirement (MINOR-6) is satisfied *structurally* by the OQ-4 shape (privileged platform app) — record that this is a precondition met, not a capability delivered.

### 2.4 The pending-approval registry (real, not stubbed)

- In-memory, per-process; entries keyed by a monotonic `long token`; each entry records `sessionId`, `method`, `argsJson`, `classification`, `createdAt`.
- **Single-use**: a decision consumes the entry; a second `submitForApproval` with the same token/request creates a new entry (no idempotent re-approve).
- **TTL 5 minutes** (§6.2, R-GATE-6): a timed sweep marks stale entries `EXPIRED` and the waiting call returns `EXPIRED`, which the caller maps to the "user declined" tool result (R-GATE-7) — the *mapping* is Phase 8, the *expiry* is S6.
- **Denial-as-tool-result** (§5 step 4, R-GATE-3/6/7): `DENIED` is a returned decision, not an exception/throw. State it because a throw is how this gets lost.
- The registry **survives agent death** because it lives in the broker process; a `RemoteException` from the caller is caught and the entry is left to expire rather than being leaked or auto-approved.
- **Kill-switch property the card depends on:** the entry is snapshotted into an immutable string at submit time; the card renders **only** from that snapshot, never from a live page, never from a caller-supplied late binding (§6.2: "system-verified content, never page/script scope"; P5-H1 invariant).

### 2.5 The card (OQ-3 DECIDED — broker-hosted)

- A native dialog (`AlertDialog` with platform theme, or a `DialogFragment` — record which) in the **broker** process, showing:
  - the exact method (e.g. `sms.send`) and the exact arguments (`argsJson`, pretty-printed, truncated with an explicit "…truncated, N bytes" marker rather than silently clipped);
  - the risk class, **verbatim** from the closed enum;
  - Approve / Deny buttons; **no** "always allow", no "remember".
- Renders **even if the shell is dead/broken/attacker-influenced** — proven by §4 A4 (force-stop the shell, then trigger a card).
- A card must never be launched from a background *service* context in a way Android silently drops: use a full-screen-Intent-permitted or `ACTIVITY_NEW_TASK` launch with the broker's own activity; if the platform blocks background activity starts, the fallback is a high-priority notification **plus** the same registry entry — record which path was taken and why. **If the card cannot render, the capability is not gated and the design fails**, so this is a stop-the-line item (see A4's failure clause).
- SysUI/theme: platform-styled, not agent-styled. The card is **not** HTML and must not be rendered by the WebView (§10.1 Z1 "must never render an approval card").

### 2.6 Policy artifact: read for version, fail closed

- Read `/system/etc/phosphor/risk-policy.json` at first bind; extract `policy_version`.
- Missing / unparseable / **not equal to the build-stamped version** ⇒ every `submitForApproval` returns `VERSION_MISMATCH` (**deny**), an audit event is logged, and `policyVersion()` returns the observed (untrusted) value or `"<invalid>"` for diagnostics. §6.3(2) verbatim: "Broker refuses if `policy_version` is missing, unparseable, or not the build-stamped version → **deny** (fail closed), and log an audit event."
- The build-stamped version is compiled in (`BuildConfig`/`--define`), not read from the same file it validates — otherwise the check is circular and always passes. Call this out: it is the difference between a check and a ritual.
- Broker has **read** on the artifact and **no write** (S2 `neverallow`, NEW-4). S6 must not contain a code path that writes it.

### 2.7 Audit logging (§6.7)

Every classification decision the broker sees, every approval, denial, expiry, and version mismatch → structured log (`logcat`, tag `phosphor-broker`) **and** a durable append in the broker's private dir (`/data/data/com.phosphor.broker/audit.log`, `0600`). Redaction: `argsJson` is logged only as a **hash** plus a method name; the card shows the full string to the *human* but the audit store does not retain payloads (R-SEC-4 at save time; §6.7). Record this asymmetry explicitly — it is deliberate.

### 2.8 What the broker must never do (audited against Z3)

- Never exceed the §3 API surface (S6: does not implement any of it).
- Never write the policy artifact.
- Never classify more weakly than agentd (§6.3 fail-closed order; Phase 8 enforces it — S6 must not create a "SAFE" shortcut that would later excuse a weaker classification; the enum comparison `DESTRUCTIVE-READ > DESTRUCTIVE > SAFE` is the shape).
- Never render an approval card inside the WebView, never accept a card's content from the caller after submit time.
- Never auto-start at boot (safe boot must have no broker).

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| Module + manifest | `<tree>/packages/phosphor/apps/PhosphorBroker/{Android.bp, AndroidManifest.xml}` |
| Bound service | `…/PhosphorBrokerService.java` (broker process context) |
| AIDL | `…/aidl/com/phosphor/broker/IPhosphorBroker.aidl`, `ApprovalRequest.aidl`, `Decision.java` |
| Registry | `…/ApprovalRegistry.java` |
| Card | `…/ApprovalCardActivity.java` + `res/layout/approval_card.xml` |
| Policy check | `…/PolicyArtifact.java` |
| Audit | `…/AuditLog.java` |
| Domain/permission | S2's `phosphor_broker.te`, `seapp_contexts`, artifact read grant |

`[VERIFY AT BUILD: the broker's UID spelling is explicitly provisional in architecture §2.1 ("`AID_PHOSPHOR_BROKER` *(spelling provisional; hosting shape now fixed by the OQ-4 ruling)*"). S2 declares the AID; the *name* may be adjusted at implementation — record the final spelling so §2.1's caveat can be retired.]`

---

## 4. Acceptance criteria

**A1 — Bind from the agentd/shell path (the Supervisor's acceptance).** With agentd alive (S4's normal boot), the shell-side and agentd-side client from **S7 §2.2** (`services/PhosphorIpc/`) each bind: this criterion is signed off as part of S7's landing, since the client is S7's deliverable.
```bash
adb shell am startservice -n com.phosphor.broker/.PhosphorBrokerService    # expected: refused (not a started service / not exported)
adb shell dumpsys activity services com.phosphor.broker                     # shows the bound client records
```
Pass = the service appears with at least one live `Client connections` row whose package is `com.phosphor.shell` (or agentd's S7 client), `ping()` returns the expected `int` (via S7's client logcat line), and an **unprivileged third-party** bind attempt fails with `SecurityException`/`Permission Denial`. The negative case is mandatory: a bind that succeeds from `untrusted_app` fails the spec.

**A2 — The card renders with the shell dead (the Supervisor's other acceptance).**
```bash
adb shell am force-stop com.phosphor.shell
adb shell pidof com.phosphor.shell          # -> empty
# trigger a card from S7's client (submitForApproval, DESTRUCTIVE)
```
Pass = the card appears (screenshot), shows the method + args + class verbatim, and Approve/Deny both return the corresponding decision to the client (verified in logcat). Deny **and** Approve separately exercised. Then, with the shell killed, a second card ***also*** renders — proving independence, not a one-off.

**A3 — Empty capability surface.** `aapt2 dump permissions …/PhosphorBroker.apk` → output contains **no** `uses-permission` lines; `rg -n 'uses-permission' packages/phosphor/apps/PhosphorBroker` → empty; `dumpsys package com.phosphor.broker | grep -A20 'grantedPermissions'` → nothing §3-shaped. The completion note lists every §3 row as **Phase 9 deferred** (A7 cross-check).

**A4 — Card content is system-verified and single-use.**
- The client sends `argsJson`; the card displays exactly that string; then the client mutates its own copy and the displayed text does **not** change (snapshot proof).
- After Approve, a second Approve for the same token returns a fresh `EXPIRED`/no-entry result — single-use.
- 5-min TTL: an unattended card expires; the client's call returns `EXPIRED`; the entry is swept. `[VERIFY AT BUILD: use a shortened TTL in a debug build to avoid a 5-minute wait; the production constant is 5 min.]`

**A5 — Policy version fail-closed.** With the artifact renamed/masked (test build) or a deliberately mismatched build stamp: `submitForApproval` returns `VERSION_MISMATCH`, a `policy_error`-class audit event is logged, **no card renders**, and the code path contains no fallback that returns `APPROVED`. Demonstrate the negative: reverting the mask restores `APPROVED`-capable behaviour.

**A6 — No auto-start in safe boot.** On the S3-approved safe-boot boot: `adb shell pidof com.phosphor.broker` → empty; `dumpsys activity services com.phosphor.broker` → no such service running; no broker logcat lines for that boot. (Multi-trigger via bind only.)

**A7 — §3 deferral is documented, row by row.** The completion note reproduces §3's table with an explicit Phase 9 marker per row (telephony, SMS, contacts, notifications, settings, audio, sensors, location, camera/torch, Bluetooth, clipboard, vibrator, apps, files) and a one-line reason (`hardRestricted` allowlist not yet built, capability not implemented, etc.). Anything not marked is a defect.

**A8 — Audit logged, payload not retained.** Trigger one Approve, one Deny, one Expire: `logcat -s phosphor-broker` shows three structured events with method + hash + class; the durable `audit.log` contains no `argsJson` body (assert by searching for a sentinel payload string).

**A9 — No artifact write, no over-reach.** `logcat -b all -d | grep 'avc: *denied' | grep phosphor_broker` → empty; static: no `FileOutputStream`/write path touching `risk-policy.json`; `rg -n 'risk-policy' packages/phosphor/apps/PhosphorBroker` → read-only call sites.

**A10 — Escalation not taken.** The completion note states that OQ-4's standalone-app shape was used and that **no** `system_server` injection or hybrid was introduced, and lists any capability that S6 found to *demand* escalation (expected: none, since nothing is implemented). A silent escalation fails the spec.

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| Shell dead when a card is requested | Card renders from the broker (A2). This is the whole point of OQ-3. |
| Broker dead when a card is requested | Caller gets an exception ⇒ **fail closed**: the caller must treat "no broker" as "no gated capability" (§7: "no broker, no gated capability, period"). S6 records the caller-side obligation; S7 implements it. |
| Card cannot be shown (background-start restriction) | Stop-the-line: record the exact platform refusal, use the notification+registry fallback, and if neither renders, **S6 fails** — an unrenderable card means the gate does not exist. |
| Two simultaneous cards | Serialise: one card at a time, queued in arrival order; the registry does not accept a decision for a card not currently shown. Record the queue bound (reject beyond N with a logged denial) rather than growing unbounded. |
| Caller process dies while card is up | Entry expires normally; card stays dismissible; no crash. Never auto-approve on caller death. |
| Caller re-submits the same request 5× | New entries (single-use each), queue bound limits; no dedup that could merge two distinct approvals into one. |
| `SAFE` classification submitted | No card; `NOT_IMPLEMENTED` (execution is Phase 8). Never a card for `SAFE` — that would train users to approve reflexively. |
| `DESTRUCTIVE-READ` submitted | Card **always**, never auto-approved even with a permissive policy entry (§6.3). Assert no code branch can bypass. |
| Policy version matches but artifact hash changed | S6 has no hash check (it is Phase 8's re-check); record that the **hash** check is deferred so it is not mistaken for present. |
| Broker bound but artifact unreadable | Every submit denies with `VERSION_MISMATCH`; `ping()` still works (diagnostics must not require a healthy policy). |
| Escalation temptation: "just make it a system service" | Recorded refusal — OQ-4 is DECIDED; escalation is per-capability and recorded, never a drift. |
| Device reboots mid-approval | Registry is in-memory ⇒ entries lost. That is correct (single-use, no persistence of pending approvals) and must be stated so it is not later "fixed" into a persisted auto-approve. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A10 pass. A2/A4/A5/A6 use the S3/S4-approved boots and in-session actions; no new device operation.
- [ ] **A1/A2 exercised through S7 §2.2's client** (`services/PhosphorIpc/`), which is why S6 depends on S7 — sign-off recorded once S7 lands; no S6-owned throwaway probe.
- [ ] OQ-4 shape: standalone platform-signed privileged app; **no** escalation; documented in the completion note.
- [ ] OQ-3 shape: card rendered **inside the broker**, from the registry snapshot, with the shell dead (A2).
- [ ] Zero `<uses-permission>` — provably (A3), with §3's rows marked Phase 9 deferred (A7).
- [ ] Registry: single-use, 5-min TTL, denial-as-result not exception, survives agent death, queue bounded.
- [ ] Policy version: build-stamped constant vs. file value, fail-closed on all three failure modes, **no** write path.
- [ ] Closed class enum only (`SAFE`/`DESTRUCTIVE`/`DESTRUCTIVE-READ`); `SAFE` never prompts; `DESTRUCTIVE-READ` never auto-approves.
- [ ] Audit: events logged, payload hashed not retained.
- [ ] Card launched at most one at a time; unrenderable card = fail.
- [ ] No safe-boot auto-start (A6).

## 7. Open items created by this spec

1. Card launch mechanism vs. Android background-activity-start restriction (§2.5) — builder, with the fallback recorded.
2. `AlertDialog` vs `DialogFragment` and the platform theme (§2.5) — builder.
3. Final `AID_PHOSPHOR_BROKER` spelling (§3) so §2.1's "provisional" caveat can be retired.
4. Artifact **hash** verification deferred to Phase 8 (§5 row) — recorded, not silently absent.
5. The §3 permission set's manifest landing (Phase 9) including the `hardRestricted` allowlist build deliverable (MAJOR-4) and the notification-listener overlay (`config_defaultListenerAccessPackages`, MINOR-4) — owner: Phase 9, named here so it is not lost.
6. ~~S6's acceptance needs a client that S6 does not own~~ — **CLOSED (F4):** S7 is in the depends-on list, and A1/A2 name S7 §2.2's client as the caller. Residual for the Supervisor only: the *acceptance* order becomes S6 service → S7 client → S6 sign-off → S8 (§Depends-on, "Order consequence"), so S6 must not be marked complete before S7 lands.
