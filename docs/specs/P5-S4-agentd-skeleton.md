# P5-S4 — `phosphor_agentd`: native daemon skeleton

**Phase:** 5 · **Spec ID:** P5-S4 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (module `phosphor-agentd`), **P5-S2** (`phosphor_agentd` domain, `phosphor_agentd_exec`, `phosphor_agentd_data_file`, `phosphor_risk_policy_file` read grant, the binder-target `neverallow`), **P5-S3** (`sys.phosphor.safeboot` must exist and be written, or the start condition never fires).
**Blocks:** **P5-S7** (the AF_UNIX end that S7's client connects to) and every later phase's agent brain. S6's "bind from agentd path" acceptance needs this daemon alive.
**Authority:** architecture §2.1 (agentd row: "no Android runtime/signature capabilities"), §2.2 (lifecycle: `disabled`, started by `on property:sys.phosphor.safeboot=0`, `onrestart` re-exec, logd logging; crash-safe home), §5 (turn ownership), §6.3 (authoritative classifier location), §6.7 (audit), §7 (degradation ladder row "agent daemon crash-loop"), §8 (map).

---

## 1. Scope

A native daemon that **is** the agent's platform home, with **zero** capability permissions, that:

1. Is declared `disabled` and starts **only** on `on property:sys.phosphor.safeboot=0` — never at `class_start core`.
2. Exits immediately and cleanly if it ever finds itself starting without that condition (defence in depth against an `.rc` mistake).
3. Emits structured logs (logd) from first instruction, with a stable event vocabulary.
4. Owns a health surface and is restarted by init on crash, with a documented restart policy and crash-loop behaviour.
5. Creates and owns its private data dir `/data/misc/phosphor/`, reads the read-only policy artifact at startup (and fails closed if it is missing/unparseable).
6. Hosts the **server side** of the shell↔agentd `AF_UNIX SOCK_SEQPACKET` channel with `SO_PEERCRED` verification (framing implemented here; message *semantics* are S7).
7. Holds the turn/state ownership hooks: transcript store, classifier entry point, quarantine envelope — as **interfaces with stub implementations**, so later phases fill behaviour without touching the process shape.

### Non-goals (S4 is a skeleton)

- No model client, no network use (§2.1 grants network egress to this process; S4 does not exercise it — and note **S2's policy grants no network rule**; it is added when the client lands).
- No classifier logic beyond loading the artifact and reporting a version.
- No STT, no tool execution, no broker calls.
- No shell/app work.
- No device operation in this spec's own gates (see §6 for the two that S3 already approved).

---

## 2. Behaviour contract

### 2.1 Process shape

| Property | Value | Source |
|---|---|---|
| Binary | `/system/bin/phosphor-agentd` | §2.1, §8 map |
| Language | Rust (the agent-core logic is ported from `agent_core.py`/`server.py`) — C++ is acceptable only if the port is deferred, and the choice is recorded | §2.1, §8 migration map |
| `.rc` | `class core`, `disabled`, `user phosphor_agentd`, `group phosphor_agentd` | §6.5 verbatim |
| UID | `AID_PHOSPHOR_AGENTD` | §2.1 (S2 declares it) |
| Domain | `u:r:phosphor_agentd:s0` | §2.1 |
| Capabilities | **none.** No `capabilities` line, no `CAP_*`; no Android permission of any kind; no signature permission | §2.1: "**No Android runtime/signature capabilities.**" |
| Network | egress only, when the model client lands (not S4) | §2.1, §8 ("ONLY network egress path in Phosphor") |
| Binder | **client to `phosphor_broker` only**; no binder server; nothing to shell | §8: `neverallow phosphor_agentd { domain -phosphor_broker -self }:binder call` |
| Socket | AF_UNIX SOCK_SEQPACKET **server**, shell connects, agentd verifies peer | §8 note 3/4 |

`.rc` verbatim (architecture §6.5):

```
service phosphor_agentd /system/bin/phosphor-agentd
    class core
    disabled
    user phosphor_agentd
    group phosphor_agentd

on property:sys.phosphor.safeboot=0
    start phosphor_agentd
```

`[VERIFY AT BUILD: `onrestart` syntax — architecture §2.2 says "`onrestart` re-exec". Record the actual `onrestart` block used, e.g. `onrestart restart phosphor_shell`? No: agentd's own re-exec is init's ordinary service restart; an `onrestart` section is for *reacting* to it. The spec requires: init restarts the daemon on unexpected exit (the default for a non-`oneshot` service) and any `onrestart` action is declared and justified in the completion note.]`

### 2.2 Start-condition defence in depth

Before doing anything: read `sys.phosphor.safeboot`. If it is not exactly `0`, **log and exit(0)** without creating dirs or sockets. This is not redundant with init — it protects against a future `.rc` edit, a `class_start` regression, or a manual `start` that bypasses the trigger. Comment it as such.

### 2.3 Structured logging (the event vocabulary)

One line per event, JSON or `key=value`, prefixed `phosphor-agentd:` — stable field names, because §6.7's audit store and REC-5's quarantine both consume these strings:

| Event | Fields | When |
|---|---|---|
| `start` | `pid`, `safeboot`, `build_id`, `policy_version` | after start-condition check |
| `policy_loaded` | `policy_version`, `sha256`, `path` | after the artifact read |
| `policy_error` | `err`, `path` | artifact missing/unparseable ⇒ **fail closed** (§2.4) |
| `socket_listening` | `path`, `uid`, `gid`, `mode` | after the AF_UNIX bind |
| `peer_rejected` | `pid`, `uid`, `reason` | on `SO_PEERCRED` failure |
| `shutdown` | `reason`, `uptime_ms` | on clean exit |
| `exit_refused_start` | `safeboot` | §2.2 refusal |

**Redaction rule (binding on this table):** no field may carry a credential, a transcript body, a message body, or an absolute path under `/data/misc/phosphor/credentials/`. R-SEC-4 applies at write time, not at read time.

### 2.4 Startup ordering and fail-closed points

1. Start-condition check (§2.2) — refuse.
2. Create/verify `/data/misc/phosphor/` with `0700`, owner `phosphor_agentd`. Failure ⇒ log `policy_error`-class fatal, exit non-zero (init restarts; the shell shows offline — §2.2's crash-safe home).
3. Read `/system/etc/phosphor/risk-policy.json`; parse `policy_version`. **Missing or unparseable ⇒ exit non-zero, do not listen.** Rationale: §6.3's fail-closed order starts with the policy existing; a daemon that runs without a policy version cannot classify, and §6.3(2) makes version mismatch a deny. Starting anyway would create a brain that can never lawfully act — worse than being absent, because the shell would show "controlled" with no gate behind it.
4. Open the AF_UNIX socket (§2.5). Failure ⇒ exit non-zero.
5. Log `start` + `socket_listening`; enter the event loop.

### 2.5 The socket (framing only; semantics are S7)

- `AF_UNIX`, `SOCK_SEQPACKET`, path `/data/misc/phosphor/agentd.sock` (S7 may move it; **the path is a shared constant owned by `services/PhosphorIpc/`**, created here).
- Bind with `umask` such that the socket is `0600` owned by `phosphor_agentd`; on every `accept`, read `SO_PEERCRED`, and admit **only** a peer whose UID is `AID_PHOSPHOR_SHELL` **and** whose domain is `phosphor_shell`. Two checks, not one: a UID alone would admit a shell process that had been subverted into a different label, and a label alone would admit any process in that domain.
- Framing: length-prefixed, max frame size enforced (`[VERIFY AT BUILD: choose and record — suggested 1 MiB, with a documented "screen payload may exceed" review]`), oversized frame ⇒ close connection, log `peer_rejected`.
- No blocking accept loop that cannot be cancelled: one `poll()`/epoll loop, clean `SIGTERM` shutdown that unlinks the socket.
- **Zero message semantics in S4**: a well-formed frame is logged as `frame_len=` and dropped with a `NOT_IMPLEMENTED` reply. S7 replaces the handler.

### 2.6 Health and crash restart

- **Health surface for S8, defined here:**
  - `init.svc.phosphor_agentd` state (`running`/`restarting`/`stopped`) — from init.
  - `/data/misc/phosphor/health` — a file the daemon touches/updates each loop tick with `pid`, `started_at`, `policy_version`, `last_frame_at`. **Written by agentd, read by `phosphor-ctl` (S8).** Not a socket, not a binder call: S4 needs **no** IPC to be healthy.
- **Restart:** init's default for a non-`oneshot` service. No `onrestart` action required; if one is added it must be justified (§2.1 note).
- **Crash-loop behaviour (architecture §7 row 3):** init's `service … ` has a default crash-restart budget; the daemon must additionally back off **itself** on a fast-crash pattern: if it starts and dies within 5 s more than 3 consecutive times, it must write a `crashloop` marker to `/data/misc/phosphor/health` and exit with status 1 so init's own limits engage rather than a hot loop. Rationale: a hot loop starves the boot; the shell's offline state (§2.2) is the user-visible remedy and **must be reachable**.
- **Kill ⇒ restart** is an acceptance criterion (§4 A4), so no `oneshot`, no `disabled`-only-once behaviour, no `setprop` self-clear.

### 2.7 What the daemon must never do (audited)

- Never hold an Android permission, a signature permission, or a runtime grant.
- Never `set` any property (S2 grants it only `get_prop` on `phosphor_safeboot_prop`; a write attempt is a `DENIED`).
- Never write the policy artifact (S2 `neverallow`).
- Never binder-call the shell, `system_server` services, or any capability service.
- Never read the secret paths of §6.4 (`/data/misc/keystore/**`, `/data/adb/**`, `/data/local/tmp/**`, `*.pem` class) — S2 must make most of them unreachable; the capability store at `/data/misc/phosphor/credentials/` is *permitted* by the data-dir rule but **must not be read in S4** (no credential use exists yet). Record that the rule is broader than S4 exercises.

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| Module + source | `<tree>/packages/phosphor/services/PhosphorAgentd/{Android.bp, src/main.rs}` |
| init config | `<tree>/packages/phosphor/init/phosphor_agentd.rc` |
| Shared constants (socket path, framing, health file) | `<tree>/packages/phosphor/services/PhosphorIpc/` (created here as headers/constants; S7 fills the AIDL/wire types) |
| Private data dir | `/data/misc/phosphor/` (created at runtime, `0700`, typed `phosphor_agentd_data_file` by S2) |
| Policy artifact | `/system/etc/phosphor/risk-policy.json` (staged by S1) |
| Health file | `/data/misc/phosphor/health` (written at runtime) |

---

## 4. Acceptance criteria

**A1 — Starts on normal boot.** After the S3-approved normal boot (`sys.phosphor.safeboot=0`):
```bash
adb shell getprop init.svc.phosphor_agentd     # -> running
adb shell pidof phosphor-agentd                # -> one pid
adb shell getprop sys.phosphor.safeboot        # -> 0
```
Pass = all three. Plus `logcat -d -s phosphor-agentd | head` shows the `start` line with `safeboot=0`.

**A2 — Absent in safe boot.** The S3 A1 boot (`persist.phosphor.safeboot=1`):
```bash
adb shell getprop init.svc.phosphor_agentd     # -> absent
adb shell pidof phosphor-agentd                # -> empty
logcat -d -s phosphor-agentd                   # -> empty (it never ran, not even to refuse)
```
Pass = absent/empty. **`stopped` is a failure** (it would mean init started it and it exited — i.e. the trigger fired).

**A3 — Zero capabilities, proven not asserted.**
- `rg -n 'capabilities|android:permission' packages/phosphor/services/PhosphorAgentd packages/phosphor/init/phosphor_agentd.rc` → only comment lines.
- On device: `adb shell dumpsys package` shows no `com.phosphor.agentd` package (there is none — it is a binary).
- `logcat -b all -d | grep 'avc: *denied' | grep phosphor_agentd` → empty.
- **Policy-side proof:** the compiled policy contains no `allow phosphor_agentd …:binder call` except toward `phosphor_broker`, and no `set` on any property.

**A4 — Restart on kill.**
```bash
adb shell 'pid=$(pidof phosphor-agentd); kill -9 $pid'
sleep 3; adb shell getprop init.svc.phosphor_agentd   # -> running
adb shell pidof phosphor-agentd                        # -> a NEW pid
```
Pass = running with a different pid, and `logcat` shows a second `start` line with a later timestamp. No `onrestart` hot-loop; exactly one restart per kill.

**A5 — Fail-closed on missing/unparseable policy.** Device or lab:
- Rename/mask the artifact in a test build (or point `--policy` at a nonexistent path in a host-run unit test) ⇒ the daemon logs `policy_error`, exits non-zero, does **not** create the socket, and init retries (observed as an init restart, and once the crash-loop backoff trips, the `crashloop` marker appears).
- Pass = no socket file, `policy_error` logged, `health` carries `crashloop` after the pattern.

**A6 — Socket is peer-restricted and framed.**
- `adb shell ls -l /data/misc/phosphor/agentd.sock` → `srw------- phosphor_agentd phosphor_agentd`.
- From a shell that is **not** `phosphor_shell` (`adb shell`): connect attempt is accepted by the kernel then `peer_rejected` logged with the caller's uid and the connection closed. (S4 does not implement a full client, so this is checked with `socat`/`nc -U` or S7's test tool — if the tool does not exist yet, the check is deferred to S7 **and recorded as deferred**, not skipped silently.)
- Oversized frame ⇒ closed + `peer_rejected`.

**A7 — Structured log vocabulary present.** Each of `start`, `policy_loaded`, `socket_listening`, `shutdown` observed in one session. `peer_rejected` observed in A6. Field names exactly as §2.3.

**A8 — Health surface readable.** `/data/misc/phosphor/health` contains `pid`, `started_at`, `policy_version`, `last_frame_at`, is `0600 phosphor_agentd`, and its `pid` matches `pidof`. (Consumption by `phosphor-ctl` is S8's acceptance; S4 only proves the file.)

**A9 — No secret-path reads, no property writes.** `avc` denials empty (A3) **and** the daemon's own log shows no attempt. Static: `rg -n '/data/misc/keystore|/data/adb|/data/local/tmp|credentials' packages/phosphor/services/PhosphorAgentd` → comments only.

**A10 — Shell-dead resilience is not regressed.** With the shell app force-stopped (`am force-stop com.phosphor.shell`), agentd remains `running` and logs no fatal. (Architecture §2.2's crash-safe home has two halves; S4 owns this half.)

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| `class_start core` regression (service not `disabled`) | §2.2's self-check refuses and logs `exit_refused_start`. A regression test: manually `adb shell start phosphor_agentd` in safe boot ⇒ refuses, `init.svc` returns to `stopped`, agentd absent from `pidof`. |
| `sys.phosphor.safeboot` unreadable by agentd | It holds `get_prop` (S2). If a build regression removes it, the read returns empty ⇒ **not `0` ⇒ refuse**. Fail-closed preserved. Record this as the intended behaviour, not a bug. |
| Property flips to `1` while running | No `on property:` stop trigger exists (safe boot is a **boot** decision, §6.5). agentd keeps running; the *next* boot is gated. Do **not** add a live stop trigger — that would create an in-session kill switch writable by a property, and no domain may write it anyway. |
| `/data/misc/phosphor/` exists with wrong owner/mode | Fix mode if owned by us; if owned by someone else ⇒ fatal exit (init restarts; do not silently adopt a foreign directory). |
| Stale socket file from a killed run | Unlink before bind — but only if it is a socket we own; never `unlink` a non-socket path (a symlink planted there would be an attack). |
| Two agentd instances | init enforces one. Belt-and-braces: the bind fails for the second ⇒ fatal exit, logged. |
| Filesystem full (logd/dir) | Log is best-effort; the *socket* creation failure is fatal (fail-closed). Do not run brainless. |
| `SIGTERM` from init on shutdown | Clean: unlink socket, log `shutdown`, exit 0. Timeout ≤ 2 s. |
| Shell connects from a different netns/user | `SO_PEERCRED` uid+label check rejects. |
| Policy artifact present but `policy_version` missing | `policy_error` ⇒ fatal (same as unparseable) — §6.3(2) makes a missing version a deny, and a brain that cannot classify must not exist. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A10 pass; A1/A2 reuse S3's approved boots (no new device operation is required by S4; A4's kill is a non-destructive in-session action on an already-approved build — if policy treats any `adb` interaction as a device operation, PM approval is obtained first).
- [ ] `.rc` matches §6.5: `disabled`, and the **only** start path is `on property:sys.phosphor.safeboot=0`.
- [ ] Self-check §2.2 present and demonstrated (A/A5 row 1).
- [ ] Zero capabilities — proven statically **and** by empty avc denials.
- [ ] Log vocabulary exactly §2.3, with no secret-bearing fields.
- [ ] Socket: `SOCK_SEQPACKET`, `0600`, `SO_PEERCRED` uid **and** label check, bounded frames, clean shutdown.
- [ ] Health file written; crash-loop backoff implemented and demonstrated.
- [ ] Policy fail-closed (missing/unparseable/absent-version) demonstrated.
- [ ] Turn/classifier/quarantine/transcript surfaces present as **named stubs**, so later phases extend without reshaping the process.

## 7. Open items created by this spec

1. Rust vs C++ for the daemon skeleton — builder, recorded in the completion note (Rust is the architecture's direction).
2. Max frame size (§2.5) and whether the screen payload needs chunking — gates S7's wire design.
3. Network policy rule for agentd is **deliberately absent** until the model client lands; the missing rule must be recorded so a later phase does not mistake it for a forgotten grant.
4. The `onrestart` shape actually used (§2.1 note) — builder.
5. Health-file schema becomes S8's contract; freeze the field names here.
