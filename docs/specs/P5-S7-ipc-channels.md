# P5-S7 — IPC: agentd↔shell `AF_UNIX SOCK_SEQPACKET`, broker binder surface, credential-provisioning hooks

**Phase:** 5 · **Spec ID:** P5-S7 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (`services/PhosphorIpc/`), **P5-S2** (domains + the `neverallow` binder rules that make "denied outside the pair" enforceable), **P5-S4** (agentd's socket server, `SO_PEERCRED`, framing constants), **P5-S6** (broker's bound service + registry).
**Mutual dependency with S6, stated so it is not misread:** S6 depends on this spec because its A1/A2 are exercised through §2.2's client, and this spec depends on S6 because the client needs a service to call. That is a **deferred acceptance**, not a build cycle: S6's service is built first, §2.2's client next, S6's A1/A2 are signed off at this spec's landing, and S8 follows. No artifact of either spec requires a not-yet-existing artifact of the other.
**Blocks:** nothing downstream in Phase 5 except S8's diagnostics (which read the health surfaces this spec finalises). Phase 6's rendering and Phase 8's tool execution both consume these channels.
**Authority:** architecture §8's map and reconciliation notes 3–4 (shell↔agentd is `AF_UNIX SOCK_SEQPACKET`, shell connects, agentd verifies `SO_PEERCRED` + group/label; chosen *not* left as "binder AIDL / local socket"), §8's SELinux section (`neverallow phosphor_agentd { phosphor_broker }:binder call`; `neverallow phosphor_shell` binder to capability services), §6.4/§9 **OQ-2 DECIDED** (Keystore-wrapped + per-flash credential provisioning), §10.1's data-flow (Z2→Z1 carries the turn; Z2→Z3 carries tool calls).

---

## 1. Scope

Three channels, their denial properties, and the credential-provisioning seam:

| Channel | Mechanism | Direction | Carries |
|---|---|---|---|
| **C-A** agentd ↔ shell | `AF_UNIX` `SOCK_SEQPACKET`, shell connects, agentd verifies `SO_PEERCRED` | bidirectional | user text/audio **in**, normalised screen HTML + turn metadata **out**. **Not a capability path** (§8 note 4). |
| **C-B** agentd → broker | binder AIDL (`IPhosphorBroker`, S6) | agentd is client; broker is server | tool calls, re-checked in the broker |
| **C-C** shell → broker | binder AIDL, same interface | shell is client | `phosphorApi` proxy RPCs end here (§4/R-BRIDGE-1: "every `phosphorApi` method is a proxy that ends in a broker RPC") |
| **C-D** credential provisioning hooks | Keystore-backed interface, **stubbed** | agentd ← provisioning | OQ-2's per-flash provisioning; no secret material moves in S7 |

**The denial property is the deliverable.** "Round-trip each channel" is necessary but not sufficient: the spec's core acceptance is that each channel **refuses** peers outside its declared pair, and that refusal is enforced by **two independent layers** — the kernel/`SO_PEERCRED` check in the daemon and SELinux's `neverallow`/absence-of-`allow` in policy.

### Non-goals

- No message *semantics*: no turn handling, no screen rendering, no tool execution, no classifier. C-A frame types are defined and echoed/validated; the payload is a stub.
- No credential **use**: no unlock, no decrypt, no model-provider call. C-D is an interface plus a refusal shape.
- No new capability permissions anywhere.
- No device operation (§6).

---

## 2. Behaviour contract

### 2.1 C-A — the socket wire (chosen mechanism, not a fallback)

- `AF_UNIX`, `SOCK_SEQPACKET`, path from the shared constant in `services/PhosphorIpc/` (`/data/misc/phosphor/agentd.sock` as S4 fixed it).
- **Shell connects; agentd listens.** The reverse would let a compromised shell hold the listening socket and accept a fake brain.
- **Admission, three checks, all must pass on every `accept()`:**
  1. `SO_PEERCRED` UID == `AID_PHOSPHOR_SHELL`;
  2. `getSoPeerSid()`/`SO_PEERSEC` label == `u:r:phosphor_shell:s0`;
  3. PID is currently alive and is in the shell domain (catches a reused/raced SID).
  Failure ⇒ close immediately, log `peer_rejected` with `{pid, uid, label, reason}` — **and log it even if the log itself is the only side effect**, because §6.7's audit needs the attempt.
- **Socket file mode `0600`, owner `phosphor_agentd`.** The directory is `0700`. Two filesystem gates on top of the credential checks.
- **Framing:** `SOCK_SEQPACKET` is message-oriented, so no length-prefix *needed* for correctness; the frame carries a fixed header + body for versioning:
  ```
  struct phosphor_frame { u16 version; u16 type; u32 body_len; u8 body[]; }
  ```
  `version = 1`; an unknown version ⇒ `ERROR` reply + close (fail closed, do not "best effort" parse). Body max enforced from S4's constant (S4 open item 2 — freeze it here: **1 MiB**, with an explicit note that the Phase 6 screen payload must be chunked or the limit raised by a reviewed change, not silently exceeded).
- **Frame types (S7-minimal, and the vocabulary Phase 6 extends):**
  | type | direction | S7 behaviour |
  |---|---|---|
  | `HELLO` / `HELLO_ACK` | shell→agentd / agentd→shell | version exchange, agentd's `policy_version` and `safeboot` state |
  | `TEXT_IN` | shell→agentd | accepted, echoed back as `TEXT_ACK` (no agent loop yet) |
  | `SCREEN_OUT` | agentd→shell | a **fixed stub** document string (the S5 stub screen), proves the outbound path |
  | `STATE` | agentd→shell | `online` / `offline` heartbeat, consumed by S5's offline state |
  | `ERROR` | both | codes: `BAD_VERSION`, `BAD_FRAME`, `NOT_IMPLEMENTED`, `POLICY_INVALID` |
- **No capability in this channel.** Static assertion: `services/PhosphorIpc/` contains no tool-name table, no broker client, no permission-shaped API. The auditor enforces this — §8 note 4 and §5's asymmetry paragraph both make the channel *outside* the classifier, and that is only true if nothing capability-shaped rides it.
- **Ordering and backpressure:** one in-flight request per `SOCK_SEQPACKET` connection; on a full send buffer, drop the **oldest `SCREEN_OUT`** (a superseded screen is worthless) and never drop a `TEXT_IN`. Record this policy — it is the difference between "shell shows a stale screen" and "user's words vanish".
- **Reconnect:** the shell reconnects with exponential backoff (250 ms → 8 s, jittered); agentd accepts a new connection after the old closes; agentd never accumulates stale connections (each `accept` replaces the previous admitted peer, and the old fd is closed — one admitted peer at a time). Single-peer invariant is stated because S5's `singleTask` activity makes >1 shell process unexpected, and an accidental second is a bug to log, not to serve.

### 2.2 C-B / C-C — the broker binder surface

- **One AIDL interface** (`IPhosphorBroker`, defined in S6) used by **two** clients: agentd and shell. No second interface for the shell — if the shell needs a different method set, that is a method, not a surface (§3 is the single source; a second surface is how privilege drifts).
- **S7 adds the client side only:** `IPhosphorBroker` client wrappers in `services/PhosphorIpc/` plus the shell-side `phosphorApi` → broker RPC path. **This client is also S6 A1/A2's caller** (S6 depends on S7 for exactly that reason): the bind proof and the with-the-shell-dead card proof are exercised here, so this spec's landing closes S6's acceptance — record that sign-off in the completion note rather than re-running the proofs as an S6-own probe.
- **Wire rules:**
  - `submitForApproval` is **blocking with a deadline**: the client sets a 6-minute timeout (5-min TTL + 1-min margin), and on timeout treats it as `EXPIRED` ⇒ "user declined" (R-GATE-7). A blocking call with no deadline is a hung agent.
  - A `SecurityException`/`RemoteException` ⇒ `NOT_IMPLEMENTED`/fail-closed result, **never** a retry that could double-submit an approval.
  - The client must **not** cache decisions; single-use is the registry's job (S6).
- **Proxy chain (the R-BRIDGE topology, §4):** page JS → `phosphorApi` (whitelisted) → shell → binder → broker. **The shell is a dumb relay**: it adds no policy, no unlock, no "always allow" state (§4's "the page cannot fake an approval, cannot unlock a method, and cannot read the registry"). Static assertion: the shell holds no capability permission beyond `RECORD_AUDIO`, so a relay bug cannot escalate.
- **Denial property:** only `phosphor_agentd` and `phosphor_shell` may `binder call` `phosphor_broker`; every other domain is denied by policy, and S2's `neverallow` proves it at compile time rather than at runtime.

### 2.3 C-D — credential provisioning hooks (OQ-2, stubbed)

OQ-2 is **DECIDED**: Keystore-wrapped, hardware-backed, **per-flash provisioning**, with on-device secret-at-rest explicitly **best-effort until relock** (§9/§6.4). S7 builds the *shape* and refuses to build the secret path:

```cpp
// services/PhosphorIpc/credential_hooks.h
// OQ-2 DECIDED: Keystore-wrapped per-flash provisioning. NOT IMPLEMENTED in Phase 5.
// Provisioning is host-driven and therefore a DEVICE OPERATION: it requires PM approval
// and must never be triggered by an in-device component (no Phosphor domain holds the
// write path to the credential store -- see the S2 data-dir grant, deliberately not
// exercised here).
enum class ProvisionResult { NOT_PROVISIONED, PROVISIONED, KEY_UNAVAILABLE };
ProvisionResult credential_state();          // S7: always NOT_PROVISIONED
ProvisionResult provision(/* from host provisioning channel */) = delete;  // no in-device path
```

- The seam exposes **state**, not secrets. No function returns, accepts, or transports key material in Phase 5.
- `credential_state()` returning `NOT_PROVISIONED` is a **real** state the agent must handle (model turns fail gracefully, §5's degradation ladder) — S7 proves the *state* is reportable, not that provisioning works.
- **A refusal is the acceptance:** any attempt to add an in-device provisioning entry point (binder method, socket frame type, adb-reachable service) **fails review**. The host path is out-of-band (§6.5/§9's "per-flash"), and adding a device-side one would make the credential store reachable by every Phosphor process — precisely what §6.4's table treats as `DESTRUCTIVE-READ`.
- Keystore use is deferred; when it lands it must use `StrongBox` where available (8a is StrongBox-capable, §9) and fall back with a recorded, visible downgrade.

### 2.4 Health surfaces this spec finalises

- C-A liveness: agentd's `last_frame_at` in `/data/misc/phosphor/health` (S4's file) is updated by the socket layer, and S5's `STATE` heartbeat consumes it.
- C-B/C-C liveness: broker's bound-client count (via `dumpsys activity services`), plus a `ping()` the diagnostics tool calls.
- **No new health channel** — S8 reads what S4/S6/S7 already expose. Inventing a fourth surface here would fragment diagnostics.

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| Shared constants + frame header | `<tree>/packages/phosphor/services/PhosphorIpc/{ipc_constants.h, frame.h}` |
| Frame types + codec | `…/PhosphorIpc/frame_codec.{h,cpp}` |
| Socket client (shell side) | `<tree>/packages/phosphor/apps/PhosphorShell/…/AgentLink.java` (S5 seam, filled) |
| Socket server (agentd side) | `<tree>/packages/phosphor/services/PhosphorAgentd/src/socket.rs` (S4 skeleton, filled) |
| Broker client wrappers | `…/PhosphorIpc/BrokerClient.{h,cpp}` (agentd, C++) or `…/PhosphorIpc/broker.rs` (if agentd is Rust — S4 open item 1 decides) |
| Shell→broker relay | `…/apps/PhosphorShell/…/PhosphorApi.java` |
| AIDL | `…/apps/PhosphorBroker/aidl/com/phosphor/broker/IPhosphorBroker.aidl` (S6) |
| Credential seam | `…/PhosphorIpc/credential_hooks.h` |
| Policy | S2's `neverallow` binder rules; **no new rules expected** — if S7 needs one, that is a finding |

---

## 4. Acceptance criteria

**A1 — C-A round-trips.** With agentd alive: the shell connects, `HELLO`/`HELLO_ACK` exchange succeeds (versions match, `policy_version` non-empty, `safeboot=0`), a `TEXT_IN` yields `TEXT_ACK` with the same payload, a `SCREEN_OUT` arrives and is logged with its byte length, and `STATE` heartbeats appear at the declared interval. Evidence: the shell's and agentd's logcat lines plus `health`'s `last_frame_at` advancing.

**A2 — C-B/C-C round-trip.** agentd's client binds the broker and `ping()` returns; shell's `phosphorApi.request(...)` reaches the broker (broker logs the call; returns `NOT_IMPLEMENTED` per S6). Evidence: broker logcat shows **two distinct** client pids/UIDs (agentd's and shell's), and `dumpsys activity services com.phosphor.broker` lists two connections.

**A3 — Denied outside the pair (the primary acceptance).** Three negative tests, each must fail closed:
- **(a) Wrong UID/label on C-A:** a test client not in `phosphor_shell` (run as `shell`, or a `untrusted_app` helper) connects ⇒ `peer_rejected` logged with its uid+label, connection closed, **no data accepted**.
- **(b) Wrong domain on C-B/C-C:** an `untrusted_app` attempts to bind the broker ⇒ `SecurityException`; and the **policy** denies it independently — `rg` the compiled policy / cite S2's `neverallow` as the second layer. Two layers, both shown.
- **(c) agentd→shell binder:** agentd has **no** binder path to the shell at all (§8: "Removes rev 1's contradictory 'neverallow … except to broker + shell'"). Prove it by attempting a bind to any shell-exported service: there is none (S5 A6), and the policy names nothing — evidence is the **absence**, which must be demonstrated by the compiled policy not containing such an allow, plus a `neverallow` if expressible.

**A4 — Frame validation is strict.** Feed: unknown `version` ⇒ `ERROR(BAD_VERSION)` + close; a body over the 1 MiB limit ⇒ `ERROR(BAD_FRAME)` + close; a truncated/reordered frame cannot occur under `SOCK_SEQPACKET`, so the test is a raw `sendmsg` of a malformed header ⇒ rejected. Pass = all three rejected, none partially applied.

**A5 — One admitted peer, deterministic reconnect.** Kill the shell while connected, relaunch: agentd accepts exactly one new peer, logs the closed old fd, `health` updates; the shell's backoff is observable in its log (250 ms → 8 s, jittered) and never hot-loops.

**A6 — No capability rides C-A.** Static: `rg -n 'tel\.|sms\.|contacts\.|camera\.|settings\.|geo\.|clip\.' services/PhosphorIpc services/PhosphorAgentd/src/socket.rs` → empty (except comments naming the prohibition). If a tool vocabulary appears on the socket, the spec fails — the channel is outside the classifier by design (§8 note 4), and putting a tool name in it would make "every consequential action crosses the broker" false.

**A7 — Broker deadline and fail-closed client behaviour.** Simulate a broker that never answers (or an artificially long TTL): the client returns at its deadline as `EXPIRED`/"declined", not hanging. Simulate `SecurityException`: client returns fail-closed, **logs no retry**, and the registry has no duplicate entry.

**A8 — Credential seam refuses.** `credential_state()` returns `NOT_PROVISIONED` and the agent surfaces it as "model unavailable" rather than crashing or pretending. Static: no function in `PhosphorIpc` returns/accepts/transports key material; no binder method, socket frame, or service exposes provisioning. `rg -n 'provision' packages/phosphor` → the seam and its comment only.

**A9 — Redaction at both ends.** Neither side logs a `TEXT_IN` body verbatim; audit logs carry method + hash (S6's rule extended to C-A: a `TEXT_IN` body is user text). Assert with a sentinel string that must not appear in `logcat` after a send.

**A10 — No new permissions, no new policy surface.** The diff adds zero `<uses-permission>`, zero `<service>` beyond S6's, and (ideally) zero policy rules. Any new rule is a finding to be justified line-by-line against §8.

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| Shell starts before agentd is listening | Connect fails ⇒ backoff; on agentd's later bind, the shell connects. Never a busy loop, never a crash. |
| agentd restarts while the shell is connected | Socket fd becomes invalid; shell sees EOF/`EPIPE`, goes to `offline` state, reconnects with backoff. The screen shows the offline state (§2.2 crash-safe home). |
| Stale socket file after a hard kill | agentd unlinks-then-binds *only if the path is a socket it owns*; a non-socket at the path is a fatal error, never unlinked (symlink-planting defence, S4 §5). |
| Two shell processes (accidental) | Second `accept` replaces the first and logs; the first gets a clean close. Record it as a bug signal, not a feature. |
| Very large screen payload (>1 MiB) | Rejected with `ERROR(BAD_FRAME)`; Phase 6 must chunk or raise the limit by a reviewed change. **Never** truncate a screen silently — a truncated screen is a lie to the user. |
| Blocking `submitForApproval` while the user is away | Deadline ⇒ `EXPIRED` ⇒ "declined" tool result. No queue of unanswered prompts growing unbounded (S6's queue bound applies). |
| Broker not installed (build defect) | Bind fails ⇒ fail closed; every gated call returns "declined/unavailable". No fallback that executes. |
| C-A peer is the shell but the shell is compromised | Out of scope for the *channel*: the compromise is contained by the shell holding only `RECORD_AUDIO` and having no broker privileges beyond the same AIDL surface (§2.1's split is the mitigation). State this so the channel is not credited with a guarantee it does not provide. |
| Provisioning attempted from a device process | Refused by design; recorded as a review-blocking change (§2.3). |
| Relock changes Keystore semantics | OQ-5 (Phase 12): secret-at-rest becomes a guarantee only after relock (§9). The seam's comment must say so, so nobody claims at-rest protection now. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A10 pass; device work reuses the S3/S4-approved boot and in-session actions.
- [ ] C-A is `SOCK_SEQPACKET`, shell-connects, three-check admission (uid, label, liveness), `0600` socket in a `0700` dir.
- [ ] Frame header versioned; unknown version/malformed header rejected; 1 MiB limit frozen; drop policy for `SCREEN_OUT` stated.
- [ ] **Denied outside the pair** proven at both layers (credential check **and** policy), including agentd→shell's *absence*.
- [ ] Shell is a dumb relay; no policy in the proxy; no cached unlock.
- [ ] Client deadline on `submitForApproval`; fail-closed on `SecurityException`/`RemoteException`; no double-submit.
- [ ] Credential seam: state only, no secret transport, **no in-device provisioning path**; `NOT_PROVISIONED` handled as a real state; relock caveat recorded.
- [ ] No capability vocabulary on C-A (A6) — the channel stays outside the classifier.
- [ ] Redaction at both ends; sentinel test passes.
- [ ] Zero new permissions/services; any new policy rule justified.

## 7. Open items created by this spec

1. Frame body limit vs. Phase 6 screen size — chunking decision deferred, limit frozen at 1 MiB (§2.1).
2. agentd's language (Rust vs C++) decides the broker-client file (§3) — inherits S4 open item 1.
3. Keystore/StrongBox implementation and the host provisioning procedure — **Phase 5 debt carried to the phase that provisions**, gated as a device operation with PM approval; must not be implemented device-side.
4. `SCREEN_OUT` drop policy needs a Phase 6 review once screens are large and stateful.
5. Whether `SO_PEERSEC` label retrieval needs a specific API on this tree (`getSoPeerSid` on `LocalSocket` vs raw `getsockopt`) — builder, at implementation.
6. **[LEDGERED FROM S2, 2026-11-13 — pending PM batch approval]** S2's shell/broker inbound-binder neverallow was deferred (re-audit BUG #8: the generic plat binder-call baseline — 83 callers incl. `system_server` — cannot be denied to an app domain in S2; a rule written there was compile-time text only). **S7 owns this obligation:** author the broker-callable-by / shell-callable-by rules against S5/S6's real binder surfaces in this spec's §2.2 scope, validated by binary-mode `checkpolicy -M -c 30`, not by the (akita-disabled) build checker. S2's shipped state: agentd inbound is broker-only and strict-clean; shell inbound remains the plat baseline until this item lands. Note also: this spec's `:72,115,127(b)` lines cite "S2's neverallow" as the compile-time proof that only agentd/shell may call the broker — that citation is stale (no such rule ever existed in any S2 revision; S2's inbound rule restricts callers of *agentd*); rewrite those citations against the rule this item authors.
