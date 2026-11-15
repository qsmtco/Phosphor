# P5-S4 — `phosphor_agentd` daemon skeleton — build-side plan (author round)

**Phase:** 5 · **Spec ID:** P5-S4 · **Round:** S4-A **rev 2** (Coder, author) · **Author:** Coder, 2026-11-15 · **Rev 2:** 2026-11-15 (post-audit; §14 Revision log maps every change)
**Deliverable:** this file — byte-exact content for the S4 build-side artifacts, for transcription by the Supervisor (S4-B) into the Phosphor-platform payload repo, plus the verification block and the host-lab harness. Device acceptance (A1–A10 on the Pixel) is a **separate, PM-gated execution round** (batched after S4, with S3's) — this plan performs none of it.
**Authority chain:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` §2.1/§2.2/§5/§6.3/§6.7/§7/§8 → `docs/specs/P5-S4-agentd-skeleton.md` **rev 2** (errata ⑰–㉑ applied, PM-approved) → `docs/specs/P5-S4-PREFLIGHT-PROBE.md` → `docs/specs/P5-S4-PHASE-INSTRUCTIONS.md` (12 standing rulings, binding) → this plan → **S4-A between-phase audit** `docs/specs/P5-S4-S4A-AUDIT.md` (Debugger, verdict NOT ACCEPT until rev 2; rev 2 applies its §E fix list, every form pre-validated in `docs/evidence/s4a-agentd-lab-audit/` — the audit's fixed sources are the transcription authority for the exact Rust/lab forms).
**Executed-evidence rule (standing):** every expected string below is labelled **[QUOTED FROM SOURCE — not executed]** (verbatim from the authority chain, with the doc/line cited) or **[EXPECT AT BUILD/CHECK]** (produced at the Supervisor's seat; the pass condition is stated). **No [EXECUTED] claims are made this round.** This seat's sandbox is `/home/cptjaqx/projects/Phosphor`; the GrapheneOS tree at `/home/cptjaqx/projects/grapheneos-2026091900` was **not readable from this seat this round** (confirmed: file access outside the sandbox is refused), and live AOSP source fetches (github raw / android.googlesource / cs.android.com) failed (404 / JS-gated). Per the delegation, every tree-side fact is therefore marked [EXPECT AT BUILD] with the doc/source it is quoted from.
**Word marker:** the delegation for this rev-2 round carried **please write** (rev-2 repair round). No `please proceed` marker is claimed; nothing executed against the tree, the payload repo, or any device **in this round**. (Rev 1 carried **please write** too; the audit round that reviewed it executed the lab at its own seat — its evidence lives in `docs/evidence/s4a-agentd-lab-audit/` and is not claimed as this plan's execution.)
**Device operations: NONE in this round.** No `adb`, no `fastboot`, no reboot, no flash, no wipe. A1–A10 ride the later PM-gated round.

---

## 0. DISCOVERY (read in full, in order) and Rust API verification status

**Read (1) `docs/specs/P5-S4-agentd-skeleton.md` rev 2 in full.** Key bindings carried into this plan: process shape §2.1 (binary `/system/bin/phosphor-agentd`; Rust; `class core`, `disabled`; zero capabilities; binder client-only and none in S4); start-condition defence §2.2 (not exactly `0` ⇒ log + exit(0), no dirs/sockets); event vocabulary §2.3 (exactly 7 events, field names frozen, redaction rule binding); fail-closed order §2.4; socket §2.5 (init-managed at `/dev/socket/phosphor_agentd`, label-only admission `u:r:phosphor_shell:s0`, length-prefixed frames with a max-frame cap, poll loop, clean SIGTERM shutdown with **no unlink**, zero message semantics — `frame_len=` log + `NOT_IMPLEMENTED` reply); health/crash §2.6 (health file fields frozen; init restarts a non-critical service forever at a fixed 5 s period — the daemon's own 3-fast-crash `crashloop` marker is the **only** backstop, erratum ⑱); never-list §2.7; A1–A10.

**Read (2) `docs/specs/P5-S4-PREFLIGHT-PROBE.md` in full.** Pinned tree facts quoted from it (all [QUOTED FROM SOURCE — not executed]): PF-BUG #1 (prefixed `system_ext_phosphor_agentd`, uid 7521 — erratum ⑰); PF-BUG #2 (UID 7523 admission was incoherent — label-only admission, erratum ⑲); PF-BUG #3/#4 (init-managed socket at `/dev/socket` moots the sock_file grant — **zero new sepolicy**); PF-BUG #5 (init has NO crash budget for agentd — fixed 5 s restart forever; daemon marker is the sole backstop — erratum ⑱); PF-BUG #6/#8/#9 (A2/A4/A6 wording — erratum ㉑; nc/socat cannot drive a seqpacket socket — the peer tests are lab/S7-tool material); PF-A4 (`SO_PEERSEC 31` at `bionic/libc/kernel/uapi/asm-generic/socket.h:46`; `getpeercon(3)` at `external/selinux/libselinux/src/getpeercon.c:26` is a plain `getsockopt` needing **no** policy permission; Rust `selinux` crate exists at `external/rust/android-crates-io/crates/selinux`); PF-A5 (rust toolchain 1.91–1.93.1 green; keystore2/prng_seeder built in this tree's out/; `rust_binary` carries `init_rc` natively — `system/security/prng_seeder/Android.bp:38-45` puts `init_rc: ["prng_seeder.rc"]` in a `rust_defaults`, `system/security/keystore2/Android.bp:142` likewise; and verbatim: *"C++ keygate needed `stem` only because the target name had a dash; `rust_binary { name: "phosphor-agentd", stem: "phosphor-agentd" }` works the same way"*); PF-BUG #7 (the S1 `cc_binary` stub must be **replaced**, not paralleled — duplicate module name = soong error); `service_parser.cpp:441-442` (init's `socket` keyword accepts `seqpacket`, `+passcred`); lmkd precedent `system/memory/lmkd/lmkd.rc`: `socket lmkd seqpacket+passcred 0660 system system`.

**Read (3) `docs/specs/P5-S4-PHASE-INSTRUCTIONS.md` in full.** The 12 standing rulings are binding and are all implemented below: (1) erratum `.rc` form; (2) Rust; (3) init-managed socket, mirror lmkd's fd consumption; (4) label-only admission via `getpeercon(3)`; (5) **no new sepolicy — a plan wanting `.te` changes is a STOP**; (6) daemon self-backstop crashloop; (7) `services/PhosphorIpc/` holds the shared constants (builder's choice of shape, recorded); (8) frame semantics (oversized ⇒ close + `peer_rejected`; well-formed ⇒ `frame_len=` + `NOT_IMPLEMENTED`); (9) health fields frozen; (10) log vocabulary exactly §2.3; (11) named stub traits; (12) start-condition defence. Build-side verification per the instructions: `m -j24 phosphor-agentd` green; staged `.rc` byte-identical; **hand-run `host_init_verifier`** (S3 lesson: the build never checks Soong `.rc`); staged binary `readelf`/`strings`; **lab harness** with at least the 9 named scenarios.

**Rust API facts — verification status (the delegation's three questions, re-adjudicated by the S4-A audit):**

| Fact | Status this round | Resolution in this plan |
|---|---|---|
| `android_get_control_socket` in Rust | **Verified in-tree by the audit** [QUOTED FROM SOURCE — audit §A(1)]: `system/librustutils/rustutils/src/android/sockets.rs:46-51` — `pub fn android_get_control_socket(name: &str) -> Result<OwnedFd, SocketError>` over the `cutils_bindgen` FFI (allowlist `rustutils/Android.bp:125`); in-tree Rust callers incl. `system/security/prng_seeder/src/main.rs:142`. **Mandatory precondition:** `rustutils::inherited_fd::init_once()` must run very early or `take_fd_ownership` returns `Error::NotInitialized` (`sockets.rs:38-43` doc; `inherited_fd.rs:44-84`; prng_seeder calls it first thing, `main.rs:134` → `:142`). | **Adopt librustutils** (audit-mandated swap, BUG #8): `rustlibs += ["librustutils"]`, `control_socket_fd` becomes `android::sockets::android_get_control_socket(name)` returning `OwnedFd`, and `rustutils::inherited_fd::init_once()` is the **first statement of `agentd_main()`** — §4.1/§4.2/§6. The old `extern "C"` one-liner and the direct `libcutils` `shared_libs` dep are gone (libcutils remains transitively via librustutils). |
| `getpeercon` availability | Both routes now verified [QUOTED FROM SOURCE — audit §A(2)]: the libc symbol (`getpeercon.c:26`, plain `getsockopt` of `SO_PEERSEC`, no policy permission — PF-A4) **and** the selinux crate `SecurityContext::of_peer_socket` (`external/rust/android-crates-io/crates/selinux/src/lib.rs:775-788`; `libselinux_rust`, host_supported + product_available). PF-A4 explicitly blesses the FFI route. | **Keep the libc FFI** (`getpeercon`/`freecon` externs, `libselinux` in `shared_libs`) — smallest dependency surface, audit-adjudicated optional and equally valid; **choice recorded here and in Related issue 11** (the `SecurityContext::as_bytes` trailing-NUL caveat is documented there for S7). |
| Does init hand an already-listening fd? | Our `.rc` uses `seqpacket+passcred` with **no** `+listen`; init listens only when `+listen` is given [QUOTED FROM SOURCE — audit §A(3): `service_parser.cpp:448-453`, decorations only `passcred`/`listen`; lmkd listens itself at `lmkd.cpp:3781-3785` after `android_get_control_socket` at `:3779`]. | Unchanged from rev 1 and audit-CONFIRMED: the daemon calls `listen(fd, 8)` on the handed fd — **no bind, no unlink**. (Rev 1's [EXPECT AT BUILD] confirm-request is discharged by the audit's direct tree reads.) |

---

## 1. Global execution rules (bind every S4-B step)

1. **Stop-and-report on any mismatch.** A FAILED state is a legitimate, auditable outcome. Never improvise, never edit a file a step did not name.
2. **Payload flow is the only flow** (unchanged from S3): files are committed in SRCREPO, the bare mirror refreshed, then `repo sync packages/phosphor`. **Direct edits inside `TREE/packages/phosphor` are FORBIDDEN.** The repo root **is** `packages/phosphor`.
3. **No new sepolicy (ruling 5).** This round touches **no** `.te`/`property_contexts`/`seapp_contexts` file at all. Any step that produces a sepolicy diff is a **STOP**.
4. **No device operation.** Build-side + host lab only.
5. **Judge build success** by exit code + absence of `FAILED:` / `ninja: build stopped` [QUOTED FROM SOURCE — docs/PROJECT-STATUS.md §9, per S3 plan §0.5].
6. Paste command + exact output for every step into the evidence bundle.

```
TREE    = /home/cptjaqx/projects/grapheneos-2026091900
SRCREPO = /home/cptjaqx/projects/Phosphor-platform
MIRROR  = /home/cptjaqx/projects/Phosphor-platform.git
```

**Tree-state expectation before transcription** [EXPECT AT BUILD]: `services/PhosphorAgentd/` contains the S1 stub `Android.bp` (`cc_binary { name: "phosphor-agentd", stem: "phosphor-agentd", srcs: ["main.cpp"] }`) + `main.cpp` (`int main() { return 0; }`), currently shipping via `phosphor.mk` PRODUCT_PACKAGES [QUOTED FROM SOURCE — preflight PF-BUG #7]. `services/PhosphorIpc/` holds only `.gitkeep` [QUOTED FROM SOURCE — S1 phase instructions]. `init/` holds only `.gitkeep`. This plan **replaces** the stub (PF-BUG #7: a parallel `rust_binary` with the same name is a soong duplicate-module error).

---

## 2. Design decisions (each one recorded, per the delegation)

1. **Language: Rust** (ruling 2). The spec's C++ fallback is not exercised. Consequence recorded as Related issue 1: S7's agentd-side broker client will be the Rust branch (`broker.rs`) of S7 §3's table.
2. **Socket topology: init-managed** (erratum ⑲). The daemon obtains the fd via `android_get_control_socket("phosphor_agentd")`, calls `listen()` once, and never binds/unlinks. The spec §5 "stale socket unlink" row and the §2.5 bind steps are superseded by erratum ⑲ (moot). Two-instance belt-and-braces: a manually started second instance gets no control socket fd ⇒ `socket_error` fatal exit (the env-var handoff only exists for init-spawned processes).
3. **Admission: label-only** (erratum ⑲). `getpeercon(3)` on the accepted fd must return exactly `u:r:phosphor_shell:s0` — via the **libc FFI route**, recorded (audit A(2): the `libselinux_rust` `SecurityContext::of_peer_socket` route is equivalent and optional; the choice is FFI, see Related issue 11). `SO_PEERCRED` (from `+passcred`) is read for the `peer_rejected` log only — never an admission criterion.
4. **Framing:** one `SOCK_SEQPACKET` datagram = one frame = 8-byte header (`u16 version, u16 type, u32 body_len` — the S7 §2.1 wire shape) + body. `MAX_FRAME_LEN = 1 MiB` counts the **total** frame (header+body) and is frozen in `PhosphorIpc` with the documented review note: the Phase 6 screen payload may exceed it and must be chunked (or the limit raised by a reviewed change), never silently exceeded (open item 2). Oversized/malformed ⇒ `peer_rejected` + close. Well-formed ⇒ `frame_len=<n>` log + a **`TYPE_ERROR` frame whose body is the ASCII code `NOT_IMPLEMENTED`** (ruling 8; audit BUG #6 — S7 §2.1 defines NOT_IMPLEMENTED only as an **ERROR code**, not a frame type, so rev 1's phantom `TYPE_NOT_IMPLEMENTED = 8` frame is removed from the wire contract; see Related issue 10 for the S7 reconciliation hand-off).
5. **Health + crashloop (erratum ⑱):** the daemon writes `/data/misc/phosphor/health` (`0600`) with the frozen fields `pid, started_at, policy_version, last_frame_at` plus backstop bookkeeping (`fast_crashes`, `died_fast`, `crashloop`). A run that dies on a fatal path within 5 s of start records a fast death; 3 consecutive fast deaths latch `crashloop=1` and exit 1; a start that finds the latch exits 1 immediately (the hot loop stays broken; the marker is cleared by the operator path — S8's phosphor-ctl — not by the daemon). A run that lived ≥5 s, or exited cleanly, resets the counter. SIGKILL restarts (A4) cannot self-record; the next start distinguishes them by elapsed time (init's 5 s restart period makes a killed run's successor start ≥5 s after the killed run's *start*, so a healthy kill never accumulates).
6. **Log vocabulary:** exactly the §2.3 seven events with `event=<name>` as the first field. Two **non-event operational lines** exist — `frame_len=<n>` (mandated by §2.5) and `socket_error=<err>` (fatal socket failures, near-unreachable with an init-managed fd) — documented so the A7 audit does not misread them as vocabulary violations (Related issue 8). On device the `phosphor-agentd:` prefix of §2.3 is the logd tag (`logcat -d -s phosphor-agentd`); the lab's stderr leg prints it literally. Logging goes through a direct `liblog` FFI (`__android_log_print`) — the same leg keygate uses — avoiding the `android_logger`/`log` crate API-version risk entirely.
7. **`build_id`** (a frozen `start` field) is read best-effort from `ro.build.id`, degrading to `"unknown"` — never fatal. [EXPECT AT BUILD] The A3 device check (empty avc denials) covers the policy side of this read; if it ever denials, the fallback is a one-line change (Related issue 6).
8. **`PhosphorIpc` shape (ruling 7):** a **Rust** `rust_library` (`libphosphor_ipc`) with the constants + frame-header codec — the S4 consumer is Rust, and S7 adds its AIDL/wire types beside them. Recorded as Related issue 3.
9. **`.rc` placement:** module-local `services/PhosphorAgentd/phosphor_agentd.rc` referenced by `init_rc: ["phosphor_agentd.rc"]` — the keygate/prng_seeder precedent (PF-BUG #7/#9 verdict: "pick one shape (module-attached init_rc, keygate precedent) and replace the stub"). This deviates from spec §3's `init/phosphor_agentd.rc` table entry; recorded as Related issue 4. `init/` stays reserved/untouched.
10. **`onrestart` (open item 4):** **no `onrestart` section is used.** init's ordinary service restart (fixed 5 s period, forever) is exactly what A4 requires; an `onrestart` section would only *react* to some other service's restart. Recorded here per spec §2.1's [VERIFY AT BUILD] note.
11. **Stubs (ruling 11):** `TranscriptStore`/`Classifier`/`QuarantineEnvelope` as named Rust traits with stub impls (`NullTranscriptStore`, `VersionOnlyClassifier`, `NullQuarantine`), bundled in `stubs::Agentd`, constructed once in `agentd_main` and carried through the loop — later phases replace the impls without reshaping the process. Stubs are write-free (PF-A7) and never touch credential material (§2.7/A9).
12. **Init-socket fd via librustutils (audit A(1)/BUG #8, rev 2):** the Rust wrapper `android::sockets::android_get_control_socket(name)` (crate `librustutils`) replaces rev 1's `extern "C"` one-liner into libcutils, and `rustutils::inherited_fd::init_once()` is called as the **first statement of `agentd_main()`** — the wrapper's mandatory precondition (`Error::NotInitialized` otherwise), following the prng_seeder precedent (`init_once` at `main.rs:134` before the socket fetch at `:142`). Safe by construction: nothing else in this process claims inherited fds, so taking them is reserved to the init-socket consumption path. `libcutils` is dropped from `shared_libs` (librustutils still links it transitively, so §8 step 6's `NEEDED` expectations remain valid — see the step-6 note).

**Module map** (spec §3 + ruling 7):

```
services/PhosphorIpc/            Android.bp (rust_library libphosphor_ipc), lib.rs
services/PhosphorAgentd/         Android.bp (rust_binary, init_rc), phosphor_agentd.rc
  src/main.rs                    wiring: agentd_main(), clean_shutdown(), main()
  src/platform.rs                device/host seams: props, control socket, getpeercon, paths, signals
  src/logging.rs                 the §2.3 event vocabulary (liblog FFI)
  src/start_condition.rs         §2.2 defence
  src/policy.rs                  fail-closed policy loader (serde_json)
  src/sha256.rs                  artifact fingerprint for policy_loaded.sha256 (self-tested)
  src/health.rs                  health file + crashloop accounting
  src/socket_loop.rs             listen/accept/admit/frame/poll/SIGTERM loop
  src/stubs.rs                   named stub traits (transcript/classifier/quarantine)
```

---

## 3. Artifact 1 — `services/PhosphorIpc/` (new; replaces the S1 `.gitkeep`)

### 3.1 `services/PhosphorIpc/Android.bp` (new file, byte-exact)

```make
// PhosphorIpc -- shared wire constants for the Phosphor IPC surfaces.
// P5-S4 spec section 3 (constants owned here), phase ruling 7 (Rust module
// chosen: the S4 consumer is Rust). Wire-visible constants ONLY: no
// capability-shaped API may live in this crate (P5-S7 section 2.1, enforced
// by the S7 auditor). S7 adds the AIDL/wire types beside these constants.

rust_library {
    name: "libphosphor_ipc",
    srcs: ["lib.rs"],
    edition: "2021",
}
```

### 3.2 `services/PhosphorIpc/lib.rs` (new file, byte-exact)

```rust
// lib.rs -- PhosphorIpc shared constants (P5-S4 spec section 2.5/3; ruling 7).
//
// Owned here so S7's client and S4's daemon cannot drift. Wire-visible
// constants and the frame-header codec ONLY: no capability-shaped API may
// live in this crate (P5-S7 section 2.1 -- auditor-enforced).

/// Init's socket keyword name (the .rc `socket` line); init creates
/// /dev/socket/<name> and hands the fd via android_get_control_socket(name).
pub const SOCKET_NAME: &str = "phosphor_agentd";
/// Where init creates it (erratum 19 -- the daemon never binds or unlinks).
pub const SOCKET_PATH: &str = "/dev/socket/phosphor_agentd";

/// Erratum 19: label-only admission. The UID half of the old two-condition
/// check was incoherent (PhosphorShell is a plain app uid, never 7523 --
/// preflight PF-BUG #2); SO_PEERCRED is logged as defense-in-depth only.
pub const ACCEPTED_PEER_LABEL: &str = "u:r:phosphor_shell:s0";

// Frame wire format: fixed 8-byte header + body, one datagram per
// SOCK_SEQPACKET frame. MAX_FRAME_LEN caps the TOTAL frame (header+body).
// 1 MiB is frozen here (S4 open item 2 / S7 section 2.1): the Phase 6 screen
// payload may exceed it and MUST be chunked -- or the limit raised by a
// reviewed change -- never silently exceeded.
pub const FRAME_VERSION: u16 = 1;
pub const FRAME_HEADER_LEN: usize = 8;
pub const MAX_FRAME_LEN: usize = 1 << 20;

// Frame types (P5-S7 section 2.1's table: HELLO/HELLO_ACK/TEXT_IN/TEXT_ACK/
// SCREEN_OUT/STATE/ERROR). NOT_IMPLEMENTED is NOT a frame type there -- it is
// an ERROR *code* (P5-S7 section 2.1, ERROR row). Rev-1's phantom
// TYPE_NOT_IMPLEMENTED = 8 is removed in this revision (S4-A audit BUG #6):
// S4's well-formed-frame reply is a TYPE_ERROR frame whose body is the ASCII
// bytes of the code "NOT_IMPLEMENTED" (newline-terminated, 15 bytes), and the
// exact reply shape is what S7's author reconciles -- or amends into the
// table -- in P5-S7 (this plan's Related issue 10). Any frame type or ERROR
// code outside S7 section 2.1's vocabulary must be added here by a reviewed
// change, never invented at a call site.
pub const TYPE_HELLO: u16 = 1;
pub const TYPE_HELLO_ACK: u16 = 2;
pub const TYPE_TEXT_IN: u16 = 3;
pub const TYPE_TEXT_ACK: u16 = 4;
pub const TYPE_SCREEN_OUT: u16 = 5;
pub const TYPE_STATE: u16 = 6;
pub const TYPE_ERROR: u16 = 7;

// The ERROR-code vocabulary of P5-S7 section 2.1 (the only legal reply-body
// codes), newline-terminated ASCII; body_len carries the exact length.
pub const ERROR_CODE_NOT_IMPLEMENTED: &[u8] = b"NOT_IMPLEMENTED\n";
pub const ERROR_CODE_BAD_VERSION: &[u8] = b"BAD_VERSION\n";
pub const ERROR_CODE_BAD_FRAME: &[u8] = b"BAD_FRAME\n";
pub const ERROR_CODE_POLICY_INVALID: &[u8] = b"POLICY_INVALID\n";

// Runtime paths (spec section 2.4/2.6).
pub const DATA_DIR: &str = "/data/misc/phosphor";
pub const POLICY_PATH: &str = "/system/etc/phosphor/risk-policy.json";
pub const HEALTH_PATH: &str = "/data/misc/phosphor/health";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameHeader {
    pub version: u16,
    pub frame_type: u16,
    pub body_len: u32,
}

pub fn encode_header(h: FrameHeader) -> [u8; FRAME_HEADER_LEN] {
    let mut out = [0u8; FRAME_HEADER_LEN];
    out[0..2].copy_from_slice(&h.version.to_be_bytes());
    out[2..4].copy_from_slice(&h.frame_type.to_be_bytes());
    out[4..8].copy_from_slice(&h.body_len.to_be_bytes());
    out
}

pub fn decode_header(buf: &[u8]) -> Option<FrameHeader> {
    if buf.len() < FRAME_HEADER_LEN {
        return None;
    }
    Some(FrameHeader {
        version: u16::from_be_bytes([buf[0], buf[1]]),
        frame_type: u16::from_be_bytes([buf[2], buf[3]]),
        body_len: u32::from_be_bytes([buf[4], buf[5], buf[6], buf[7]]),
    })
}
```

---

## 4. Artifact 2 — `services/PhosphorAgentd/src/` (nine new files, byte-exact)

### 4.1 `src/main.rs`

```rust
// phosphor-agentd -- the P5-S4 agent daemon skeleton.
// Spec: docs/specs/P5-S4-agentd-skeleton.md (rev 2, errata 17-21 applied).
// Architecture: docs/PHASE-4-PLATFORM-ARCHITECTURE.md sections 2.1, 2.2, 5, 6.3, 6.7, 7, 8.
//
// S4 scope: the process shape only. The daemon (1) refuses to start unless
// sys.phosphor.safeboot is exactly "0" -- defence in depth against an .rc
// edit, a class_start regression, or a manual start bypassing the trigger
// (section 2.2); (2) fails closed unless the read-only risk policy exists,
// parses, and carries a policy_version (section 2.4 step 3); (3) serves the
// init-managed AF_UNIX SOCK_SEQPACKET socket with label-only peer admission
// and a 1 MiB frame cap (erratum 19, section 2.5); (4) maintains
// /data/misc/phosphor/health with the frozen field set and its own crashloop
// backstop (section 2.6, erratum 18: init restarts a non-critical service
// forever at a fixed 5 s period, so the daemon's marker is the only
// backstop); (5) emits exactly the section 2.3 event vocabulary. Message
// semantics, the model client, the classifier and the transcript store are
// later phases; named stubs hold their places (section 1.7, ruling 11).
//
// NEVER-LIST (spec section 2.7; audited by A3/A9): no Android permissions of
// any kind; no property writes; no writes to the policy artifact; no binder
// calls at all in S4; no reads of /data/misc/keystore, /data/adb,
// /data/local/tmp, *.pem, or /data/misc/phosphor/credentials/.

mod health;
mod logging;
mod platform;
mod policy;
mod sha256;
mod socket_loop;
mod start_condition;
mod stubs;

// The shared-constants crate is referenced as `crate::phosphor_ipc` from the
// modules so the device build (extern crate via rustlibs) and the host lab
// (local module, plan section 7) resolve identically. This import makes the
// extern crate addressable via `crate::phosphor_ipc` on device; the lab
// build defines the module itself and compiles without this line.
#[cfg(not(feature = "lab"))]
use phosphor_ipc;

pub fn agentd_main() -> i32 {
    let started = std::time::Instant::now();

    // Mandatory FIRST line (rev 2; audit A(1)/BUG #8): the librustutils
    // android_get_control_socket wrapper refuses to hand out fds until
    // inherited-fd ownership is initialized (Error::NotInitialized otherwise).
    // Nothing else in this process owns inherited fds, so claiming them here
    // is safe -- the prng_seeder precedent (main.rs:134 -> :142).
    #[cfg(not(feature = "lab"))]
    rustutils::inherited_fd::init_once();

    // Section 2.4 step 1 -- start-condition defence in depth (section 2.2).
    let safeboot = match start_condition::check() {
        start_condition::Verdict::Proceed => "0".to_string(),
        start_condition::Verdict::Refused(raw) => {
            // exit(0), and NO dir/socket/policy work (section 2.2).
            logging::exit_refused_start(&raw);
            return 0;
        }
    };

    // Section 2.4 step 2 -- private data dir, 0700, owned by us. A foreign
    // owner is fatal: never silently adopt a foreign directory (spec section 5).
    if let Err(err) = platform::ensure_private_data_dir() {
        // policy_error-class fatal (section 2.4 step 2): init restarts; the
        // shell shows offline.
        let dd = platform::data_dir(); // bind first (rev 2; audit BUG #2 F4: E0308 passing a String temporary where &str is expected)
        logging::policy_error(&format!("data_dir_{}", err), &dd);
        return 1;
    }

    // Section 2.6 crash accounting (erratum 18), inserted between steps 2 and
    // 3: the backstop must observe the previous run's death BEFORE the policy
    // check that may have caused it.
    let health_path = platform::health_path();
    let prev = health::HealthRecord::read(&health_path);
    if prev.as_ref().map(|p| p.crashloop).unwrap_or(false) {
        // Latched off: 3+ consecutive fast deaths already recorded. Stay
        // exited so the hot loop stays broken; the marker is cleared by the
        // operator path (S8 phosphor-ctl), not by us.
        logging::shutdown("crashloop", 0);
        return 1;
    }
    let inherited = health::inherited_fast_crashes(prev.as_ref(), platform::now_ms());
    let mut rec = health::HealthRecord {
        pid: std::process::id(),
        started_at: platform::now_ms(),
        policy_version: prev
            .as_ref()
            .map(|p| p.policy_version.clone())
            .unwrap_or_else(|| "none".to_string()),
        last_frame_at: 0,
        fast_crashes: inherited,
        died_fast: false,
        crashloop: false,
    };
    let _ = rec.write(&health_path); // best-effort; A8 proves it on the happy path

    // Section 2.4 step 3 -- policy artifact; missing/unparseable/version-less
    // => fatal (a daemon that cannot classify must not exist, section 6.3).
    let loaded = match policy::load(&platform::policy_path()) {
        Ok(l) => l,
        Err(err) => {
            logging::policy_error(&err, &platform::policy_path());
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            return 1;
        }
    };
    logging::policy_loaded(&loaded.version, &loaded.sha256, &platform::policy_path());
    rec.policy_version = loaded.version.clone();
    let _ = rec.write(&health_path);

    // Section 2.4 step 4 -- the init-managed socket fd (erratum 19). Failure
    // is near-unreachable (init creates the socket before exec) and fatal.
    let listen_fd = match platform::control_socket_fd(phosphor_ipc::SOCKET_NAME) {
        Ok(fd) => fd,
        Err(err) => {
            logging::plain(&format!("socket_error={}", err));
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            return 1;
        }
    };

    // Section 2.4 step 5 -- the start line, then the event loop (which logs
    // socket_listening once it is listening).
    logging::start(&safeboot, &platform::build_id(), &loaded.version);

    // The turn/state ownership hooks (section 1.7). S4 constructs them and
    // hands them to the loop; the S4 loop does not use them yet -- S7's frame
    // handler will, without reshaping the process.
    let agent = stubs::Agentd {
        transcript: Box::new(stubs::NullTranscriptStore),
        classifier: Box::new(stubs::VersionOnlyClassifier::new(&loaded.version)),
        quarantine: Box::new(stubs::NullQuarantine),
    };

    match socket_loop::run(listen_fd, &health_path, &mut rec, &agent, platform::loop_tick_limit()) {
        socket_loop::LoopExit::Sigterm => {
            clean_shutdown("sigterm", &health_path, &rec, &started);
            0
        }
        socket_loop::LoopExit::TickLimit => {
            // Lab-only bound (device runs with u32::MAX); treated as clean.
            clean_shutdown("tick_limit", &health_path, &rec, &started);
            0
        }
        socket_loop::LoopExit::Fatal(err) => {
            logging::plain(&format!("socket_error={}", err));
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            1
        }
    }
}

fn clean_shutdown(
    reason: &str,
    health_path: &str,
    rec: &health::HealthRecord,
    started: &std::time::Instant,
) {
    // Clean exit: reset the crash counters (a clean run is evidence of
    // health) and rewrite the frozen fields one last time.
    let mut fin = rec.clone();
    fin.fast_crashes = 0;
    fin.died_fast = false;
    fin.crashloop = false;
    fin.last_frame_at = platform::now_ms();
    let _ = fin.write(health_path);
    logging::shutdown(reason, started.elapsed().as_millis() as u64);
}

#[cfg(not(feature = "lab"))]
fn main() {
    std::process::exit(agentd_main());
}
```

### 4.2 `src/platform.rs`

```rust
// platform.rs -- the device/host seam (the keygate KEYGATE_HOST_LAB pattern).
//
// Device build (cfg(not(feature = "lab"))): the init-socket fd comes from the
// librustutils Rust wrapper android::sockets::android_get_control_socket
// (rev 2; audit A(1)/BUG #8 -- its inherited_fd::init_once() precondition is
// discharged as the first statement of agentd_main(), src/main.rs), property
// reads go through a thin FFI one-liner (rustutils has no property-read
// helper -- only PropertyWatcher), and getpeercon(3)/freecon are FFI'd
// directly (a plain getsockopt read of SO_PEERSEC that needs no policy rule,
// preflight PF-A4; the in-tree selinux crate's
// SecurityContext::of_peer_socket is the recorded alternative -- design
// decision 3 / Related issue 11 keeps the FFI for the smaller dependency
// surface).
// Lab build (cfg(feature = "lab"), plan section 7): properties come from the
// environment, the listening fd is injected (or created locally), the peer
// identity is injected, paths move to /tmp, and logs go to stderr.

use crate::phosphor_ipc;
use std::os::unix::io::RawFd;

#[cfg(not(feature = "lab"))]
extern "C" {
    fn __system_property_get(name: *const libc::c_char, value: *mut libc::c_char) -> libc::c_int;
    fn getpeercon(fd: libc::c_int, context: *mut *mut libc::c_char) -> libc::c_int;
    fn freecon(context: *mut libc::c_char);
}

pub const SAFEBOOT_PROP: &str = "sys.phosphor.safeboot";

// ---- properties ---------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn read_prop(name: &str) -> Option<String> {
    use std::ffi::CString;
    let c = match CString::new(name) {
        Ok(c) => c,
        Err(_) => return None,
    };
    let mut buf = [0u8; 92]; // PROP_VALUE_MAX
    let n = unsafe { __system_property_get(c.as_ptr(), buf.as_mut_ptr() as *mut libc::c_char) };
    if n > 0 {
        Some(String::from_utf8_lossy(&buf[..n as usize]).into_owned())
    } else {
        None // absent and empty both read as None; both refuse (section 2.2)
    }
}

#[cfg(feature = "lab")]
pub fn read_prop(name: &str) -> Option<String> {
    let key = format!("LAB_PROP_{}", name.replace('.', "_"));
    std::env::var(key).ok()
}

// ---- build id (section 2.3 start.build_id) -------------------------------

pub fn build_id() -> String {
    // Best-effort audit correlation. [EXPECT AT BUILD: ro.build.id must be
    // domain-readable; if a build regression blocks the read this degrades
    // to "unknown" -- never fatal, never retried. The A3 device check (empty
    // avc denials) covers the policy side.]
    match read_prop("ro.build.id") {
        Some(v) if !v.is_empty() => v,
        _ => "unknown".to_string(),
    }
}

// ---- paths ---------------------------------------------------------------

pub fn data_dir() -> String {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_DATA_DIR").unwrap_or_else(|_| "/tmp/agentd_lab_data".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::DATA_DIR.to_string();
    val
}

pub fn policy_path() -> String {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_POLICY_PATH")
        .unwrap_or_else(|_| "/tmp/agentd_lab_data/risk-policy.json".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::POLICY_PATH.to_string();
    val
}

pub fn health_path() -> String {
    #[cfg(feature = "lab")]
    let val =
        std::env::var("LAB_HEALTH_PATH").unwrap_or_else(|_| "/tmp/agentd_lab_data/health".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::HEALTH_PATH.to_string();
    val
}

pub fn socket_path() -> String {
    // The logged constant (section 2.3 socket_listening.path) in BOTH builds;
    // the lab listener itself lives in /tmp (see control_socket_fd).
    phosphor_ipc::SOCKET_PATH.to_string()
}

pub fn now_ms() -> u64 {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_millis() as u64,
        Err(_) => 0,
    }
}

pub fn loop_tick_limit() -> u32 {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_TICK_LIMIT")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(u32::MAX);
    #[cfg(not(feature = "lab"))]
    let val = u32::MAX;
    val
}

// ---- data dir (section 2.4 step 2) ---------------------------------------

pub fn ensure_private_data_dir() -> std::io::Result<()> {
    use std::os::unix::fs::MetadataExt; // rev 2 (audit BUG #2 F2): md.uid() is a MetadataExt method
    use std::os::unix::fs::PermissionsExt;
    let path_buf = data_dir(); // rev 2 (audit BUG #2 F5): bind first -- Path::new(&data_dir()) borrows a dropped temporary (E0716)
    let path = std::path::Path::new(&path_buf);
    match std::fs::metadata(path) {
        Ok(md) => {
            if !md.is_dir() {
                return Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists, "not_a_dir"));
            }
            if md.uid() != unsafe { libc::geteuid() } {
                // Foreign owner: fatal upstream; never adopt it silently.
                return Err(std::io::Error::new(std::io::ErrorKind::PermissionDenied, "foreign_owner"));
            }
            if md.permissions().mode() & 0o777 != 0o700 {
                std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
            }
            Ok(())
        }
        Err(_) => {
            std::fs::create_dir_all(path)?;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
            Ok(())
        }
    }
}

// ---- socket ----------------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn control_socket_fd(name: &str) -> std::io::Result<RawFd> {
    // rev 2 (audit A(1)/BUG #8): the librustutils Rust wrapper, not an FFI
    // one-liner into libcutils. REQUIRES inherited_fd::init_once() to have run
    // first -- agentd_main() discharges that as its first statement.
    let owned =
        rustutils::android::sockets::android_get_control_socket(name).map_err(|err| match err {
            // rev 3 (audit BUG #13a): the NotInitialized arm dropped — the variant was
        // never verified in-tree and the catch-all covers it with the same effect.
        other => std::io::Error::new(std::io::ErrorKind::NotFound, other.to_string()),
        })?;
    Ok(owned.into_raw_fd())
}

#[cfg(feature = "lab")]
static LAB_LISTEN_FD: std::sync::Mutex<Option<RawFd>> = std::sync::Mutex::new(None);

#[cfg(feature = "lab")]
pub fn set_lab_listen_fd(fd: RawFd) {
    *LAB_LISTEN_FD.lock().unwrap() = Some(fd);
}

#[cfg(feature = "lab")]
pub fn control_socket_fd(_name: &str) -> std::io::Result<RawFd> {
    if let Some(fd) = LAB_LISTEN_FD.lock().unwrap().take() {
        return Ok(fd);
    }
    // Fallback: a local seqpacket socket, so a lab run never touches /dev.
    let path = std::env::temp_dir().join("phosphor_agentd_lab.sock");
    let _ = std::fs::remove_file(&path);
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in path.to_str().unwrap().as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    let rc = unsafe {
        libc::bind(
            fd,
            &addr as *const libc::sockaddr_un as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
        )
    };
    if rc != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(fd)
}

// ---- peer identity ---------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn peer_label(fd: RawFd) -> Option<String> {
    let mut ctx: *mut libc::c_char = std::ptr::null_mut();
    let rc = unsafe { getpeercon(fd, &mut ctx) };
    if rc != 0 || ctx.is_null() {
        return None;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(ctx) }.to_string_lossy().into_owned();
    unsafe { freecon(ctx) };
    Some(s)
}

#[cfg(feature = "lab")]
pub fn peer_label(_fd: RawFd) -> Option<String> {
    // Injected label (ruling: "wrong-label peer rejection (label string injected)").
    Some(std::env::var("LAB_PEER_LABEL").unwrap_or_else(|_| "u:r:shell:s0".to_string()))
}

#[cfg(not(feature = "lab"))]
pub fn peer_ucred(fd: RawFd) -> Option<(u32, u32)> {
    #[repr(C)]
    struct Ucred {
        pid: libc::pid_t,
        uid: libc::uid_t,
        gid: libc::gid_t,
    }
    let mut cred = Ucred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<Ucred>() as libc::socklen_t;
    let rc = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut cred as *mut Ucred as *mut libc::c_void,
            &mut len,
        )
    };
    if rc != 0 {
        return None;
    }
    Some((cred.pid as u32, cred.uid as u32))
}

#[cfg(feature = "lab")]
pub fn peer_ucred(_fd: RawFd) -> Option<(u32, u32)> {
    // Injected identity: logged in peer_rejected, never an admission input.
    let pid = std::env::var("LAB_PEER_PID").ok().and_then(|v| v.parse::<u32>().ok()).unwrap_or(4242);
    let uid = std::env::var("LAB_PEER_UID").ok().and_then(|v| v.parse::<u32>().ok()).unwrap_or(10000);
    Some((pid, uid))
}

// ---- accept / socket metadata ----------------------------------------------

pub fn accept(listen_fd: RawFd) -> std::io::Result<RawFd> {
    let fd = unsafe { libc::accept(listen_fd, std::ptr::null_mut(), std::ptr::null_mut()) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(fd)
}

pub fn socket_ids(fd: RawFd) -> (u32, u32, u32) {
    use std::os::unix::fs::MetadataExt; // rev 2 (audit BUG #2 F3): md.uid()/md.gid() are MetadataExt methods
    use std::os::unix::fs::PermissionsExt; // rev 2 (audit BUG #2 F3): .mode() on Permissions is a PermissionsExt method
    use std::os::unix::io::FromRawFd;
    // fstat without taking ownership of the fd (ManuallyDrop: never close).
    let f = std::mem::ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(fd) });
    match f.metadata() {
        Ok(md) => (md.uid(), md.gid(), md.permissions().mode() & 0o777),
        Err(_) => (0, 0, 0),
    }
}

// ---- SIGTERM self-pipe (section 2.5: a cancellable loop, clean shutdown) ---

static SIG_WAKER_WRITE: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

pub struct SignalWaker {
    read_fd: RawFd,
    write_fd: RawFd,
    prev_handler: libc::sighandler_t,
}

impl SignalWaker {
    pub fn install() -> std::io::Result<SignalWaker> {
        let mut fds = [0 as RawFd; 2];
        if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let (r, w) = (fds[0], fds[1]);
        SIG_WAKER_WRITE.store(w, std::sync::atomic::Ordering::SeqCst);
        extern "C" fn on_sigterm(_sig: libc::c_int) {
            let fd = SIG_WAKER_WRITE.load(std::sync::atomic::Ordering::SeqCst);
            if fd >= 0 {
                let b: u8 = 1;
                unsafe { libc::write(fd, &b as *const u8 as *const libc::c_void, 1) };
            }
        }
        let prev = unsafe {
            libc::signal(libc::SIGTERM, on_sigterm as extern "C" fn(libc::c_int) as libc::sighandler_t)
        };
        Ok(SignalWaker { read_fd: r, write_fd: w, prev_handler: prev })
    }

    pub fn read_fd(&self) -> RawFd {
        self.read_fd
    }

    pub fn drain(&self) {
        // rev 2 (audit BUG #4): the pipe is BLOCKING and the handler writes
        // exactly 1 byte per signal, so "read until <= 0" blocks forever on
        // the second read -- every SIGTERM would deadlock past the 2 s
        // shutdown budget (reproduced in the audit lab). Bounded single read:
        // at most one pending signal-wake byte matters; the poll loop returns
        // Sigterm immediately after this either way.
        let mut b = [0u8; 64];
        unsafe {
            libc::read(self.read_fd, b.as_mut_ptr() as *mut libc::c_void, b.len());
        }
    }
}

impl Drop for SignalWaker {
    fn drop(&mut self) {
        unsafe { libc::signal(libc::SIGTERM, self.prev_handler) };
        SIG_WAKER_WRITE.store(-1, std::sync::atomic::Ordering::SeqCst);
        unsafe { libc::close(self.read_fd) };
        unsafe { libc::close(self.write_fd) };
    }
}
```

### 4.3 `src/logging.rs`

```rust
// logging.rs -- the section 2.3 event vocabulary. EXACTLY seven audit events;
// field names are frozen (spec section 2.3, ruling 10) and consumed by
// section 6.7's audit store and REC-5's quarantine. The redaction rule is
// enforced here by construction: no function accepts credential material,
// transcript or message bodies, or paths under
// /data/misc/phosphor/credentials/.
//
// The "phosphor-agentd:" prefix of section 2.3 is realized as the logd tag on
// device (logcat -d -s phosphor-agentd) and literally on the lab's stderr
// leg. Non-event operational lines (frame_len=, socket_error=) exist because
// section 2.5 mandates frame_len= logging; they are not part of the closed
// event set and carry no secret material.

const LOG_TAG: &[u8] = b"phosphor-agentd\0";
const ANDROID_LOG_INFO: libc::c_int = 4;

#[cfg(not(feature = "lab"))]
extern "C" {
    // liblog -- the same leg keygate uses (init dup's stderr to /dev/null, so
    // logd is the capture leg on device).
    fn __android_log_print(
        prio: libc::c_int,
        tag: *const libc::c_char,
        fmt: *const libc::c_char,
        ...
    ) -> libc::c_int;
}

fn emit(msg: &str) {
    #[cfg(not(feature = "lab"))]
    {
        let c = std::ffi::CString::new(msg).unwrap_or_default();
        unsafe {
            __android_log_print(
                ANDROID_LOG_INFO,
                LOG_TAG.as_ptr() as *const libc::c_char,
                b"%s\0".as_ptr() as *const libc::c_char,
                c.as_ptr(),
            );
        }
    }
    #[cfg(feature = "lab")]
    {
        eprintln!("phosphor-agentd: {}", msg);
    }
}

pub fn start(safeboot: &str, build_id: &str, policy_version: &str) {
    emit(&format!(
        "event=start pid={} safeboot={} build_id={} policy_version={}",
        std::process::id(),
        safeboot,
        build_id,
        policy_version
    ));
}

pub fn policy_loaded(policy_version: &str, sha256: &str, path: &str) {
    emit(&format!(
        "event=policy_loaded policy_version={} sha256={} path={}",
        policy_version, sha256, path
    ));
}

pub fn policy_error(err: &str, path: &str) {
    emit(&format!("event=policy_error err={} path={}", err, path));
}

pub fn socket_listening(path: &str, uid: u32, gid: u32, mode: u32) {
    emit(&format!(
        "event=socket_listening path={} uid={} gid={} mode={:o}",
        path, uid, gid, mode
    ));
}

pub fn peer_rejected(pid: u32, uid: u32, reason: &str) {
    emit(&format!("event=peer_rejected pid={} uid={} reason={}", pid, uid, reason));
}

pub fn shutdown(reason: &str, uptime_ms: u64) {
    emit(&format!("event=shutdown reason={} uptime_ms={}", reason, uptime_ms));
}

pub fn exit_refused_start(safeboot: &str) {
    emit(&format!("event=exit_refused_start safeboot={}", safeboot));
}

pub fn plain(msg: &str) {
    emit(msg);
}
```

### 4.4 `src/start_condition.rs`

```rust
// start_condition.rs -- section 2.2 defence in depth. The daemon refuses to
// run unless sys.phosphor.safeboot is EXACTLY "0". Not redundant with init's
// trigger: it protects against a future .rc edit, a class_start regression,
// or a manual start that bypasses the property trigger. An unreadable or
// empty value is NOT "0" => refuse (fail closed; spec section 5 row 2 records
// this as intended behaviour, not a bug).

use crate::platform;

pub enum Verdict {
    Proceed,
    Refused(String),
}

pub fn check() -> Verdict {
    match platform::read_prop(platform::SAFEBOOT_PROP) {
        Some(v) if v == "0" => Verdict::Proceed,
        Some(v) => Verdict::Refused(v),
        None => Verdict::Refused("<absent>".to_string()),
    }
}
```

### 4.5 `src/policy.rs`

```rust
// policy.rs -- the read-only risk-policy artifact (section 2.4 step 3).
// Missing, unparseable, or version-less => fail closed: a daemon that cannot
// classify must not exist (section 6.3 rationale). S4 reports the version
// and fingerprint only; real parsing/classification is S6.

use crate::sha256;

pub struct LoadedPolicy {
    pub version: String,
    pub sha256: String,
}

pub fn load(path: &str) -> Result<LoadedPolicy, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("read_failed: {}", e))?;
    let v: serde_json::Value =
        serde_json::from_slice(&bytes).map_err(|e| format!("unparseable: {}", e))?;
    let ver = match v.get("policy_version") {
        None | Some(serde_json::Value::Null) => return Err("policy_version_missing".to_string()),
        Some(serde_json::Value::String(s)) => s.clone(),
        Some(serde_json::Value::Number(n)) => n.to_string(),
        Some(_) => return Err("policy_version_unparseable".to_string()),
    };
    if ver.is_empty() {
        return Err("policy_version_missing".to_string());
    }
    Ok(LoadedPolicy { version: ver, sha256: sha256::hex(&sha256::sha256(&bytes)) })
}
```

### 4.6 `src/sha256.rs`

```rust
// sha256.rs -- SHA-256 (FIPS 180-4) for the policy artifact fingerprint
// (section 2.3 policy_loaded.sha256). Hand-rolled to keep the dependency set
// minimal; correctness is pinned by the known vectors in the lab's "unit"
// scenario (empty string and "abc"). This is a logging fingerprint, not a
// security primitive.

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let bitlen = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bitlen.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    let mut out = [0u8; 32];
    for i in 0..8 {
        out[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}
```

### 4.7 `src/health.rs`

```rust
// health.rs -- the /data/misc/phosphor/health surface (section 2.6).
//
// Frozen field names (ruling 9, the S8 contract): pid, started_at,
// policy_version, last_frame_at. The crash backstop adds fast_crashes,
// died_fast and crashloop (erratum 18: init has NO crash budget for a
// non-critical service -- it restarts forever at a fixed 5 s period -- so
// this file carries the daemon's own backstop state). The file is 0600 and
// lives in the daemon's private data dir (A8).

#[derive(Clone)]
pub struct HealthRecord {
    pub pid: u32,
    pub started_at: u64,
    pub policy_version: String,
    pub last_frame_at: u64,
    pub fast_crashes: u32,
    pub died_fast: bool,
    pub crashloop: bool,
}

impl HealthRecord {
    pub fn read(path: &str) -> Option<HealthRecord> {
        let text = std::fs::read_to_string(path).ok()?;
        let mut r = HealthRecord {
            pid: 0,
            started_at: 0,
            policy_version: "none".to_string(),
            last_frame_at: 0,
            fast_crashes: 0,
            died_fast: false,
            crashloop: false,
        };
        for line in text.lines() {
            let (k, v) = match line.split_once('=') {
                Some(kv) => kv,
                None => continue,
            };
            match k {
                "pid" => r.pid = v.parse().unwrap_or(0),
                "started_at" => r.started_at = v.parse().unwrap_or(0),
                "policy_version" => r.policy_version = v.to_string(),
                "last_frame_at" => r.last_frame_at = v.parse().unwrap_or(0),
                "fast_crashes" => r.fast_crashes = v.parse().unwrap_or(0),
                "died_fast" => r.died_fast = v == "1",
                "crashloop" => r.crashloop = v == "1",
                _ => {}
            }
        }
        Some(r)
    }

    pub fn write(&self, path: &str) -> std::io::Result<()> {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)?;
        write!(
            f,
            "pid={}\nstarted_at={}\npolicy_version={}\nlast_frame_at={}\nfast_crashes={}\ndied_fast={}\ncrashloop={}\n",
            self.pid,
            self.started_at,
            self.policy_version,
            self.last_frame_at,
            self.fast_crashes,
            self.died_fast as u8,
            self.crashloop as u8
        )
    }
}

// Startup inheritance (section 2.6): the previous run's death counts toward
// the backstop when (a) it recorded its own fast death, or (b) it died within
// 5 s of its start without a chance to record (SIGKILL). A run that lived
// >= 5 s resets the counter. (init's fixed 5 s restart period means a killed
// healthy run's successor starts >= 5 s after the killed run's START, so a
// kill never accumulates -- A4 stays clean.)
pub fn inherited_fast_crashes(prev: Option<&HealthRecord>, now_ms: u64) -> u32 {
    match prev {
        None => 0,
        Some(p) => {
            if p.died_fast {
                p.fast_crashes
            } else if now_ms >= p.started_at.saturating_add(5000) {
                0
            } else {
                p.fast_crashes.saturating_add(1)
            }
        }
    }
}

// Fatal-exit bookkeeping: a fast death increments the consecutive counter;
// the third consecutive fast death latches the crashloop marker (ruling 6:
// 5 s-fast-crash x3 => marker + exit 1). A slow death (>= 5 s uptime) does
// not accumulate.
pub fn record_fast_death(path: &str, base: &HealthRecord, now_ms: u64) {
    let uptime = now_ms.saturating_sub(base.started_at);
    if uptime >= 5000 {
        return;
    }
    let mut r = base.clone();
    r.fast_crashes += 1;
    r.died_fast = true;
    r.crashloop = r.fast_crashes >= 3;
    let _ = r.write(path);
}

// Loop tick (section 2.6: the daemon touches the file each loop tick).
pub fn touch_tick(path: &str, rec: &mut HealthRecord) {
    rec.pid = std::process::id();
    let _ = rec.write(path);
}
```

### 4.8 `src/socket_loop.rs`

```rust
// socket_loop.rs -- the init-managed AF_UNIX SOCK_SEQPACKET server (section 2.5).
//
// The listening fd is handed over by init (android_get_control_socket,
// erratum 19): init created it bound (seqpacket+passcred 0660) but NOT
// listening -- the daemon calls listen(2) itself, mirroring lmkd's
// consumption of its init socket. The daemon never binds and never unlinks:
// init owns /dev/socket/phosphor_agentd for the service's whole life.
//
// Admission is LABEL-ONLY (erratum 19): getpeercon(3) on the accepted fd must
// return exactly u:r:phosphor_shell:s0. SO_PEERCRED (enabled by init's
// +passcred) is read for the peer_rejected log only -- it is defense in
// depth, never an admission criterion (preflight PF-BUG #2).
//
// Framing: one datagram == one frame: 8-byte header (PhosphorIpc) + body.
// Frames over MAX_FRAME_LEN (1 MiB) => close + peer_rejected. S4 has zero
// message semantics: a well-formed frame is logged (frame_len=) and answered
// with a TYPE_ERROR frame carrying the ERROR code NOT_IMPLEMENTED (rev 2,
// audit BUG #6); S7 replaces this handler.

use crate::health; // rev 2 (audit BUG #2 F1): health::touch_tick below is a bare path; without this it resolves against the extern prelude (E0433)
use crate::health::HealthRecord;
use crate::logging;
use crate::platform;
use crate::phosphor_ipc;
use crate::stubs::Agentd;
use std::os::unix::io::RawFd;

pub enum LoopExit {
    Sigterm,
    TickLimit,
    Fatal(String),
}

enum FrameOutcome {
    Served,
    Closed,
    Rejected(&'static str),
}

struct PeerInfo {
    pid: u32,
    uid: u32,
}

struct Conn {
    fd: RawFd,
    peer: PeerInfo,
}

pub fn run(
    listen_fd: RawFd,
    health_path: &str,
    rec: &mut HealthRecord,
    _agent: &Agentd, // S7's frame handler takes these hooks; unused in S4
    tick_limit: u32,
) -> LoopExit {
    // init hands a bound, not-yet-listening socket (lmkd pattern: the daemon
    // listens). No bind here, and no unlink on any path.
    if unsafe { libc::listen(listen_fd, 8) } != 0 {
        return LoopExit::Fatal(format!("listen: {}", std::io::Error::last_os_error()));
    }
    let (uid, gid, mode) = platform::socket_ids(listen_fd);
    logging::socket_listening(&platform::socket_path(), uid, gid, mode);

    let waker = match platform::SignalWaker::install() {
        Ok(w) => w,
        Err(err) => return LoopExit::Fatal(format!("signal setup: {}", err)),
    };

    let mut conn: Option<Conn> = None;
    // +1 so a datagram of exactly MAX_FRAME_LEN+1 is received fully enough to
    // be detected as oversized (SOCK_SEQPACKET preserves message boundaries;
    // a too-large datagram is truncated to the buffer, the excess discarded).
    let mut buf = vec![0u8; phosphor_ipc::MAX_FRAME_LEN + 1];
    let mut ticks: u32 = 0;

    loop {
        let mut fds = [
            libc::pollfd { fd: listen_fd, events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: waker.read_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd {
                fd: conn.as_ref().map(|c| c.fd).unwrap_or(-1),
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), 3, 200) }; // 200 ms health tick
        if ready < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return LoopExit::Fatal(format!("poll: {}", err));
        }
        if fds[1].revents & libc::POLLIN != 0 {
            waker.drain();
            // Clean SIGTERM shutdown. NO unlink: init owns the socket file
            // (erratum 19; the spec section 5 "unlink socket" row is superseded).
            return LoopExit::Sigterm;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            match platform::accept(listen_fd) {
                Ok(fd) => match admit(fd) {
                    Ok(Some(c)) => {
                        // Single admitted peer: a new admission replaces the
                        // old one (the S7 single-peer invariant).
                        if let Some(old) = conn.take() {
                            unsafe { libc::close(old.fd) };
                        }
                        conn = Some(c);
                    }
                    Ok(None) => {} // rejected and closed inside admit()
                    Err(err) => return LoopExit::Fatal(err),
                },
                Err(err) => {
                    if err.kind() != std::io::ErrorKind::WouldBlock {
                        return LoopExit::Fatal(format!("accept: {}", err));
                    }
                }
            }
        }
        let mut close_conn = false;
        if let Some(c) = conn.as_mut() {
            if fds[2].revents & libc::POLLIN != 0 {
                let n = unsafe { libc::recv(c.fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
                if n <= 0 {
                    close_conn = true; // peer closed (or recv error)
                } else {
                    match handle_frame(c, &buf[..n as usize]) {
                        FrameOutcome::Served => rec.last_frame_at = platform::now_ms(),
                        FrameOutcome::Closed => close_conn = true,
                        FrameOutcome::Rejected(reason) => {
                            logging::peer_rejected(c.peer.pid, c.peer.uid, reason);
                            close_conn = true;
                        }
                    }
                }
            }
        }
        if close_conn {
            if let Some(c) = conn.take() {
                unsafe { libc::close(c.fd) };
            }
        }
        ticks += 1;
        if ticks >= tick_limit {
            return LoopExit::TickLimit;
        }
        health::touch_tick(health_path, rec); // section 2.6: touched each loop tick
    }
}

fn admit(fd: RawFd) -> Result<Option<Conn>, String> {
    let label = platform::peer_label(fd);
    let (pid, uid) = platform::peer_ucred(fd).unwrap_or((0, 0)); // logged, not admitted on
    let admitted = matches!(&label, Some(l) if l == phosphor_ipc::ACCEPTED_PEER_LABEL);
    if !admitted {
        logging::peer_rejected(pid, uid, "label_mismatch");
        unsafe { libc::close(fd) };
        return Ok(None);
    }
    Ok(Some(Conn { fd, peer: PeerInfo { pid, uid } }))
}

fn handle_frame(c: &Conn, frame: &[u8]) -> FrameOutcome {
    if frame.len() > phosphor_ipc::MAX_FRAME_LEN {
        return FrameOutcome::Rejected("oversized_frame"); // section 2.5: close + peer_rejected
    }
    let hdr = match phosphor_ipc::decode_header(frame) {
        Some(h) => h,
        None => return FrameOutcome::Rejected("malformed_frame"),
    };
    if hdr.version != phosphor_ipc::FRAME_VERSION
        || hdr.body_len as usize != frame.len() - phosphor_ipc::FRAME_HEADER_LEN
    {
        return FrameOutcome::Rejected("malformed_frame");
    }
    // Zero message semantics in S4: log the frame, answer TYPE_ERROR carrying
    // the ERROR code NOT_IMPLEMENTED (rev 2; audit BUG #6 -- S7 section 2.1
    // defines NOT_IMPLEMENTED as an ERROR code, not a frame type; S7's author
    // reconciles the reply shape, Related issue 10).
    logging::plain(&format!("frame_len={}", frame.len()));
    let mut reply = phosphor_ipc::encode_header(phosphor_ipc::FrameHeader {
        version: phosphor_ipc::FRAME_VERSION,
        frame_type: phosphor_ipc::TYPE_ERROR,
        body_len: phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED.len() as u32,
    })
    .to_vec();  // rev 3 (audit BUG #10): encode_header returns [u8; 8]; E0599 without this
    let body = phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED;
    reply.extend_from_slice(body);
    let sent = unsafe { libc::send(c.fd, reply.as_ptr() as *const libc::c_void, reply.len(), 0) };
    if sent < 0 {
        return FrameOutcome::Closed; // peer gone; not a rejection
    }
    FrameOutcome::Served
}
```

### 4.9 `src/stubs.rs`

```rust
// stubs.rs -- the turn/state ownership hooks as NAMED stubs (spec section 1.7,
// ruling 11). Later phases replace the impls without reshaping the process.
// Stubs are write-free: nothing here touches the data dir (preflight PF-A7),
// and no credential material is ever accepted or returned (section 2.7 / A9).

// A transcript turn, reduced to metadata only in S4 (no bodies -- the
// section 2.3 redaction rule).
pub struct TurnRecord {
    pub seq: u64,
    pub body_len: usize,
}

pub struct ActionRequest {
    pub kind: &'static str,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    Allow,
    Deny,
    NotClassified, // S4's classifier reports the policy version only (section 1 non-goal)
}

pub trait TranscriptStore {
    fn append(&mut self, turn: &TurnRecord) -> Result<(), String>;
    fn last_seq(&self) -> Option<u64>;
}

/// S4 stub: in-memory, never persists. S5 replaces it with the real store.
pub struct NullTranscriptStore;

impl TranscriptStore for NullTranscriptStore {
    fn append(&mut self, _turn: &TurnRecord) -> Result<(), String> {
        Ok(())
    }
    fn last_seq(&self) -> Option<u64> {
        None
    }
}

pub trait Classifier {
    fn policy_version(&self) -> &str;
    fn classify(&self, req: &ActionRequest) -> Decision;
}

/// S4 stub: carries the loaded policy_version (A7 evidence); classifies nothing.
pub struct VersionOnlyClassifier {
    version: String,
}

impl VersionOnlyClassifier {
    pub fn new(version: &str) -> Self {
        VersionOnlyClassifier { version: version.to_string() }
    }
}

impl Classifier for VersionOnlyClassifier {
    fn policy_version(&self) -> &str {
        &self.version
    }
    fn classify(&self, _req: &ActionRequest) -> Decision {
        Decision::NotClassified
    }
}

pub trait QuarantineEnvelope {
    fn seal(&self, payload: &[u8]) -> Result<Vec<u8>, String>;
    fn unseal(&self, blob: &[u8]) -> Result<Vec<u8>, String>;
}

/// S4 stub: identity over an empty set; REC-5 fills it later.
pub struct NullQuarantine;

impl QuarantineEnvelope for NullQuarantine {
    fn seal(&self, payload: &[u8]) -> Result<Vec<u8>, String> {
        Ok(payload.to_vec())
    }
    fn unseal(&self, blob: &[u8]) -> Result<Vec<u8>, String> {
        Ok(blob.to_vec())
    }
}

// The process-shape bundle (section 1.7): constructed once in agentd_main and
// carried through the loop; S5/S6/S7 replace the impls, not the shape.
#[allow(dead_code)]
pub struct Agentd {
    pub transcript: Box<dyn TranscriptStore>,
    pub classifier: Box<dyn Classifier>,
    pub quarantine: Box<dyn QuarantineEnvelope>,
}
```

---

## 5. Artifact 3 — `services/PhosphorAgentd/phosphor_agentd.rc` (new file, byte-exact)

Placement per preflight PF-BUG #7/#9 verdict and the S3 keygate precedent: module-local, referenced by `init_rc` (see §6). The spec §3 table entry `init/phosphor_agentd.rc` is superseded — recorded as Related issue 4. The service block below **is** the erratum-⑰/⑲ requirement line-for-line (audit BUG #9 clearance: the spec §2.1's *block* is the pre-erratum form, so "verbatim" was the wrong word; the line-exact requirements are what this block carries — prefixed user/group, the `socket … seqpacket+passcred 0660` line, `class core`, `disabled`, sole trigger `on property:sys.phosphor.safeboot=0`, no `onrestart`, no `seclabel`, no `capabilities`). 4-space indents preserved.

```
# phosphor_agentd -- the P5-S4 agent daemon skeleton.
# Spec: docs/specs/P5-S4-agentd-skeleton.md rev 2 (errata 17-21 applied).
# Architecture sections 2.1/2.2/6.5. Starts ONLY via the property trigger
# below (never class_start): the daemon itself re-checks
# sys.phosphor.safeboot and refuses otherwise (section 2.2 defence in depth).
# Socket is init-managed (erratum 19, lmkd precedent): init creates
# /dev/socket/phosphor_agentd (seqpacket+passcred 0660) before exec and hands
# the fd to the process; the daemon never binds or unlinks it.
# No onrestart section: init's default restart (fixed 5 s period, erratum 18)
# covers kill-restart (A4); the crashloop backstop lives in the daemon.

service phosphor_agentd /system/bin/phosphor-agentd
    class core
    disabled
    user system_ext_phosphor_agentd
    group system_ext_phosphor_agentd
    socket phosphor_agentd seqpacket+passcred 0660 system_ext_phosphor_agentd system_ext_phosphor_agentd

on property:sys.phosphor.safeboot=0
    start phosphor_agentd
```

Prohibited forms checked: no unprefixed `phosphor_agentd` user/group (erratum ⑰), no `late-init`/`load_persist_props_action` trigger (the start path is exactly `on property:sys.phosphor.safeboot=0`), no `capabilities`, no `onrestart` (§2.1 note: none needed — init's default restart covers A4), no `seclabel` line (the exec-based `init_daemon_domain` transition from S2 names the domain; lmkd precedent has none either).

---

## 6. Artifact 4 — `services/PhosphorAgentd/Android.bp` (full replacement) + stub deletion

**Property name and stem behavior, verified against the precedents and stated:** the property is **`init_rc`** — `rust_binary` supports it natively; precedent `system/security/prng_seeder/Android.bp:38-45` (init_rc inside a `rust_defaults` consumed by the rust_binary) and `system/security/keystore2/Android.bp:142` [QUOTED FROM SOURCE — preflight PF-A5]. **Stem:** soong installs the binary as `$(stem)`; because the module name contains a dash, `stem: "phosphor-agentd"` pins the installed name `/system/bin/phosphor-agentd` — exactly what the S3 keygate `cc_binary` did, and PF-A5 states verbatim that `rust_binary { name: "phosphor-agentd", stem: "phosphor-agentd" }` works the same way, with no init_rc/stem penalty vs C++. [EXPECT AT BUILD] both facts re-confirmed by the green `m phosphor-agentd` and the staged paths in §8 step 3.

**The S1 stub `main.cpp` is DELETED** (`git rm services/PhosphorAgentd/main.cpp`) — a parallel module with the same name would be a soong duplicate-module error (PF-BUG #7).

```make
// phosphor-agentd -- the P5-S4 agent daemon skeleton (Rust, ruling 2).
// Replaces the S1 cc_binary stub (a parallel module of the same name would
// collide in soong -- preflight PF-BUG #7). init_rc is carried natively by
// rust_binary: precedents prng_seeder (system/security/prng_seeder/
// Android.bp:38-45) and keystore2 (system/security/keystore2/Android.bp:142).
// stem pins the installed name phosphor-agentd (dash in the module name),
// exactly as the S3 keygate cc_binary did; preflight PF-A5 confirms no
// init_rc/stem penalty for rust_binary.
rust_binary {
    name: "phosphor-agentd",
    stem: "phosphor-agentd",
    srcs: ["src/main.rs"],
    edition: "2021",
    rustlibs: [
        "liblibc",
        "libphosphor_ipc",
        "librustutils",
        "libserde_json",
    ],
    shared_libs: [
        "liblog",
        "libselinux",
    ],
    init_rc: ["phosphor_agentd.rc"],
    prefer_rlib: true,
}
```

Dependency notes (rev 2, audit A(1)/BUG #8): `librustutils` provides the Rust `android_get_control_socket` wrapper **and** carries the mandatory `inherited_fd::init_once()` precondition, discharged as `agentd_main()`'s first statement (§4.1). `libcutils` is **dropped from `shared_libs`** — the direct FFI dep is gone; librustutils itself `shared_libs: ["libbase","libcutils"]`, so `libcutils.so` remains in the binary's `NEEDED` **transitively** (and `android_get_control_socket` remains a visible dynamic symbol, provided by libcutils under the rustutils wrapper — see the §8 step-6 note so the symbol's provenance is not misread). `liblog` is the logd leg (`__android_log_print`); `libselinux` provides `getpeercon`/`freecon` (the recorded FFI choice, Related issue 11); `libserde_json` parses the policy artifact; `libphosphor_ipc` is the shared constants crate (§3). `liblog`/`libcutils`/`libselinux` are explicitly **allowed** by the phase instructions ("staged binary readelf/strings — no binder deps; selinux crate or libselinux allowed"). No `libbinder`, no `libhidl`, no `libutils`.

---

## 7. Artifact 5 — the host lab harness (lab-only; NOT a payload artifact)

Keygate pattern: a host-run driver that includes the **real** tree sources and stubs only the platform seams (properties → env; listening fd → injected/local; peer identity → injected; paths → /tmp; logs → stderr). Everything else — start condition, policy loader, health/crashloop accounting, admission, framing — is the shipped code.

Two files in `/tmp`, built with the tree's host rustc (no cargo, no network):

### 7.1 `/tmp/lab_libc.rs` — minimal libc surface (the exact subset the daemon uses)

```rust
// /tmp/lab_libc.rs -- minimal libc surface for the P5-S4 host lab (the exact
// subset phosphor-agentd uses). Lab-only; the device build links the real
// libc crate via soong. Host linux x86_64 values.
#![allow(non_camel_case_types)]

pub type c_int = i32;
pub type c_char = i8;
// rev 2 (audit BUG #3): `#[repr(C)]` is illegal on a zero-variant enum
// (E0084). A bare empty enum is the FFI-legal form -- exactly what the real
// `libc` crate ships.
pub enum c_void {}
pub type socklen_t = u32;
pub type uid_t = u32;
pub type gid_t = u32;
pub type pid_t = i32;
pub type sa_family_t = u16;
pub type sighandler_t = usize;

pub const AF_UNIX: c_int = 1;
pub const SOCK_SEQPACKET: c_int = 5;
pub const SOL_SOCKET: c_int = 1;
pub const SO_PEERCRED: c_int = 17;
pub const SO_SNDBUF: c_int = 7;
pub const SO_RCVBUF: c_int = 8;
pub const POLLIN: i16 = 0x1;
pub const SIGTERM: c_int = 15;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct pollfd {
    pub fd: c_int,
    pub events: i16,
    pub revents: i16,
}

#[repr(C)]
pub struct sockaddr {
    pub sa_family: sa_family_t,
    pub sa_data: [c_char; 14],
}

#[repr(C)]
pub struct sockaddr_un {
    pub sun_family: sa_family_t,
    pub sun_path: [c_char; 108],
}

extern "C" {
    pub fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    pub fn bind(fd: c_int, addr: *const sockaddr, len: socklen_t) -> c_int;
    pub fn connect(fd: c_int, addr: *const sockaddr, len: socklen_t) -> c_int;
    pub fn listen(fd: c_int, backlog: c_int) -> c_int;
    pub fn accept(fd: c_int, addr: *mut sockaddr, len: *mut socklen_t) -> c_int;
    pub fn recv(fd: c_int, buf: *mut c_void, len: usize, flags: c_int) -> isize;
    pub fn send(fd: c_int, buf: *const c_void, len: usize, flags: c_int) -> isize;
    pub fn close(fd: c_int) -> c_int;
    pub fn setsockopt(fd: c_int, level: c_int, name: c_int, val: *const c_void, len: socklen_t) -> c_int;
    pub fn poll(fds: *mut pollfd, nfds: u64, timeout: c_int) -> c_int;
    pub fn pipe(fds: *mut c_int) -> c_int;
    pub fn read(fd: c_int, buf: *mut c_void, n: usize) -> isize;
    pub fn write(fd: c_int, buf: *const c_void, n: usize) -> isize;
    pub fn signal(sig: c_int, handler: sighandler_t) -> sighandler_t;
    pub fn kill(pid: pid_t, sig: c_int) -> c_int;
    pub fn getpid() -> pid_t;
    pub fn geteuid() -> uid_t;
    // rev 2 (audit BUG #5): connect_client()'s bounded retry needs a sleep
    // primitive (the retry loop waits ~10 ms between connect attempts).
    pub fn usleep(usec: c_int) -> c_int;
}
```

### 7.2 `/tmp/agentd_lab.rs` — the scenario driver (12 scenarios; the 9 mandated ones are marked ★)

```rust
// /tmp/agentd_lab.rs -- P5-S4 host lab harness. Lab-only; NOT a payload
// artifact. Includes the REAL tree sources (provenance-explicit, keygate
// pattern) and drives the decision-tree scenarios; the scenario name is
// argv[1]. Build (plan section 8, lab block) -- three rustc invocations:
//   rustc --crate-type lib --crate-name libc /tmp/lab_libc.rs -o /tmp/liblibc_lab.rlib
//   rustc --crate-type lib --crate-name serde_json /tmp/lab_serde.rs \
//         -o /tmp/libserde_lab.rlib
//   rustc --edition 2021 --cfg 'feature="lab"' \
//         --extern libc=/tmp/liblibc_lab.rlib --extern serde_json=/tmp/libserde_lab.rlib \
//         /tmp/agentd_lab.rs -o /tmp/agentd_lab
// (/tmp/lab_serde.rs: a minimal RFC-8259 subset exposing exactly the
// serde_json::Value API surface policy.rs uses -- from_slice + Value with
// get(&str). Lab-only stand-in; the DEVICE build links the real libserde_json
// via soong. The lab_serde source is bundled with this plan's evidence at
// docs/evidence/s4a-agentd-lab-audit/lab_serde.rs -- transcribe it to /tmp
// alongside lab_libc.rs.)
//
// Module-resolution note (rev 2; audit BUG #3 -- this is the part rev 1 got
// wrong): `include!` splices src/main.rs into THIS crate root, but the
// included file's top-level paths resolve against the **extern prelude**, not
// against items the harness declares below the include. Therefore:
//   - `serde_json` and `libc` must be linked as EXTERN crates (--extern
//     lines above); declaring `mod serde_json` inside the harness does NOT
//     satisfy the included sources' `serde_json::` paths;
//   - `phosphor_ipc` must be a `mod` declared in the harness root (a plain
//     path mod from the tree file works because only extern-prelude names
//     need extern linkage);
//   - `include!("src/main.rs")` itself is mandatory -- without it the
//     harness has no `agentd_main`, and the E0433/E0425 errors the audit hit
//     (`health`, `serde_json`, `set_lab_listen_fd`) are exactly the
//     extern-prelude rule biting;
//   - `platform::set_lab_listen_fd` is called qualified from the harness
//     (the fn lives in the platform module of the included tree).
#![allow(dead_code)]

#[path = "/home/cptjaqx/projects/grapheneos-2026091900/packages/phosphor/services/PhosphorIpc/lib.rs"]
mod phosphor_ipc;

include!("/home/cptjaqx/projects/grapheneos-2026091900/packages/phosphor/services/PhosphorAgentd/src/main.rs");

const LAB_SOCK: &str = "/tmp/agentd_lab.sock";
const LAB_DATA: &str = "/tmp/agentd_lab_data";

fn fresh_env() {
    let _ = std::fs::remove_dir_all(LAB_DATA);
    let _ = std::fs::remove_file(LAB_SOCK);
    std::env::remove_var("LAB_PROP_sys_phosphor_safeboot");
    std::env::remove_var("LAB_POLICY_PATH");
    std::env::remove_var("LAB_PEER_LABEL");
    std::env::set_var("LAB_DATA_DIR", LAB_DATA);
    std::env::set_var("LAB_HEALTH_PATH", format!("{}/health", LAB_DATA));
}

fn write_policy(body: &str) {
    std::fs::create_dir_all(LAB_DATA).unwrap();
    std::fs::write(format!("{}/risk-policy.json", LAB_DATA), body).unwrap();
    std::env::set_var("LAB_POLICY_PATH", format!("{}/risk-policy.json", LAB_DATA));
}

// Bind-only: init hands a bound, NOT-listening fd; the daemon listens.
fn make_listener() -> i32 {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    assert!(fd >= 0);
    let _ = std::fs::remove_file(LAB_SOCK);
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in LAB_SOCK.as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    assert_eq!(
        unsafe {
            libc::bind(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
            )
        },
        0
    );
    // Big buffers so the oversized-frame datagram actually traverses.
    let bufsz: libc::c_int = 8 << 20;
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_RCVBUF,
            &bufsz as *const libc::c_int as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        )
    };
    fd
}

fn connect_client() -> i32 {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    assert!(fd >= 0);
    let bufsz: libc::c_int = 8 << 20;
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_SNDBUF,
            &bufsz as *const libc::c_int as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        )
    };
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in LAB_SOCK.as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    // rev 2 (audit BUG #5): the daemon reaches listen() only after dir/
    // health/policy work, so an immediate connect() hits a bound-but-NOT-
    // listening socket and gets ECONNREFUSED (deterministic on Linux) --
    // the bare assert_eq! panicked the client thread before sigterm_self()
    // and agentd_main() spun forever (first healthy_start run hung in the
    // audit lab). Bounded retry, ~2 s, then fail like the bare assert would.
    let mut ok = false;
    for _ in 0..200 {
        let rc = unsafe {
            libc::connect(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
            )
        };
        if rc == 0 {
            ok = true;
            break;
        }
        unsafe { libc::usleep(10_000) };
    }
    assert!(ok, "connect_client: connect never succeeded within 2s");
    fd
}

fn send_all(fd: i32, data: &[u8]) {
    let n = unsafe { libc::send(fd, data.as_ptr() as *const libc::c_void, data.len(), 0) };
    assert_eq!(n, data.len() as isize);
}

fn recv_some(fd: i32, buf: &mut [u8]) -> isize {
    unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) }
}

fn sigterm_self() {
    unsafe { libc::kill(libc::getpid(), libc::SIGTERM) };
}

fn print_health() {
    match std::fs::read_to_string(format!("{}/health", LAB_DATA)) {
        Ok(t) => {
            for line in t.lines() {
                println!("health {}", line);
            }
        }
        Err(_) => println!("health_absent=1"),
    }
}

fn main() {
    let scenario = std::env::args().nth(1).unwrap_or_else(|| "unit".to_string());
    let code = run(&scenario);
    std::process::exit(code);
}

fn run(name: &str) -> i32 {
    match name {
        // (1) refuse-start, safeboot=1 -- the section 2.2 defence. REQUIRED.
        "refuse_safeboot1" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "1");
            let rc = agentd_main();
            println!("data_dir_absent={}", !std::path::Path::new(LAB_DATA).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (2) refuse-start, safeboot unreadable (absent => refuse, section 5 row 2).
        "refuse_absent" => {
            fresh_env();
            let rc = agentd_main();
            println!("data_dir_absent={}", !std::path::Path::new(LAB_DATA).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (3) policy missing => fatal. REQUIRED.
        "policy_missing" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            std::env::set_var("LAB_POLICY_PATH", "/tmp/agentd_lab_no_such_policy.json");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (4) policy garbage => fatal. REQUIRED.
        "policy_garbage" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{ this is not json");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (5) policy without policy_version => fatal (section 5 last row). REQUIRED.
        "policy_no_version" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"something\":1}");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (6) healthy start to loop, then clean SIGTERM shutdown. REQUIRED.
        "healthy_start" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                std::thread::sleep(std::time::Duration::from_millis(400));
                println!("client_connected=1");
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (7) wrong-label peer rejection (label string injected). REQUIRED.
        "wrong_label" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:shell:s0"); // NOT the accepted label
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let mut buf = [0u8; 64];
                let n = recv_some(c, &mut buf); // server must close on rejection
                println!("client_closed={}", n == 0);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (8) oversized frame => close + peer_rejected. REQUIRED.
        "oversized_frame" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let big = vec![0u8; phosphor_ipc::MAX_FRAME_LEN + 1];
                send_all(c, &big);
                let mut buf = [0u8; 64];
                let n = recv_some(c, &mut buf);
                println!("client_closed={}", n == 0);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (9) well-formed frame => frame_len= log + NOT_IMPLEMENTED reply (ruling 8).
        "wellformed_frame" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let mut frame = vec![0u8; 12];
                frame[0] = 0;
                frame[1] = 1; // version = 1
                frame[2] = 0;
                frame[3] = 1; // type = HELLO
                frame[4] = 0;
                frame[5] = 0;
                frame[6] = 0;
                frame[7] = 4; // body_len = 4
                frame[8] = b'a';
                frame[9] = b'b';
                frame[10] = b'c';
                frame[11] = b'd';
                send_all(c, &frame);
                let mut buf = [0u8; 64];
                let n = recv_some(c, &mut buf);
                // rev 2 (audit BUG #6): the reply is a TYPE_ERROR frame whose
                // body is the ERROR code "NOT_IMPLEMENTED\n" (15 bytes).
                // Expect: version=1, type=7 (ERROR), body_len=15, then the
                // ASCII code. S7's author reconciles the exact shape
                // (Related issue 10).
                let ok = n == 8 + 15
                    && buf[0] == 0
                    && buf[1] == 1
                    && buf[2] == 0
                    && buf[3] == 7
                    && buf[4] == 0
                    && buf[5] == 0
                    && buf[6] == 0
                    && buf[7] == 16  // rev 3 (audit BUG #13): "NOT_IMPLEMENTED\n" = 16 bytes
                    && &buf[8..23] == phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED;
                println!("reply_ok={}", ok);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (10) clean SIGTERM shutdown; init owns the socket file (no unlink). REQUIRED.
        "sigterm_shutdown" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                std::thread::sleep(std::time::Duration::from_millis(300));
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("socket_file_still_exists={}", std::path::Path::new(LAB_SOCK).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (11) crashloop backoff trip (erratum 18: the daemon's own backstop). REQUIRED.
        "crashloop_trip" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            std::env::set_var("LAB_POLICY_PATH", "/tmp/agentd_lab_no_such_policy.json");
            // Seed: two consecutive fast deaths already recorded.
            std::fs::create_dir_all(LAB_DATA).unwrap();
            std::fs::write(
                format!("{}/health", LAB_DATA),
                "pid=1\nstarted_at=0\npolicy_version=none\nlast_frame_at=0\nfast_crashes=2\ndied_fast=1\ncrashloop=0\n",
            )
            .unwrap();
            let rc1 = agentd_main(); // third fast death: trips the marker
            println!("exit1={}", rc1);
            print_health();
            let rc2 = agentd_main(); // latched: exits without touching policy
            println!("exit2={}", rc2);
            println!("scenario={} exit={}", name, rc2);
            rc2
        }
        // (12) unit: sha256 vectors + frame-header codec roundtrip.
        "unit" => {
            let ok_sha_empty = sha256::hex(&sha256::sha256(b""))
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
            let ok_sha_abc = sha256::hex(&sha256::sha256(b"abc"))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
            let h = phosphor_ipc::FrameHeader { version: 1, frame_type: 3, body_len: 7 };
            let enc = phosphor_ipc::encode_header(h);
            let dec = phosphor_ipc::decode_header(&enc);
            let ok_hdr = dec == Some(h) && phosphor_ipc::decode_header(&[0u8; 4]).is_none();
            println!("unit_ok={}", ok_sha_empty && ok_sha_abc && ok_hdr);
            if ok_sha_empty && ok_sha_abc && ok_hdr {
                0
            } else {
                1
            }
        }
        _ => {
            println!("unknown scenario {}", name);
            2
        }
    }
}
```

### 7.3 Lab run matrix — expected stdout/stderr lines and exit codes

All lines below are [EXPECT AT CHECK] (authored here, executed at the Supervisor's seat). The daemon's own lines go to **stderr** as `phosphor-agentd: …`; harness summary lines go to **stdout**. Run each with `2>&1` and grep.

| # | Scenario | Expected lines (grep) | Exit |
|---|---|---|---|
| 0 | `unit` | `unit_ok=true` | 0 |
| ★1 | `refuse_safeboot1` | `phosphor-agentd: event=exit_refused_start safeboot=1` · `data_dir_absent=true` · `scenario=refuse_safeboot1 exit=0` | 0 |
| 2 | `refuse_absent` | `phosphor-agentd: event=exit_refused_start safeboot=<absent>` · `data_dir_absent=true` · `scenario=refuse_absent exit=0` | 0 |
| ★3 | `policy_missing` | `phosphor-agentd: event=policy_error err=read_failed: ...` · `health fast_crashes=1` · `health died_fast=1` · `scenario=policy_missing exit=1` | 1 |
| ★4 | `policy_garbage` | `phosphor-agentd: event=policy_error err=unparseable: ...` · `scenario=policy_garbage exit=1` | 1 |
| ★5 | `policy_no_version` | `phosphor-agentd: event=policy_error err=policy_version_missing` · `scenario=policy_no_version exit=1` | 1 |
| ★6 | `healthy_start` | `phosphor-agentd: event=start pid=<pid> safeboot=0 build_id=unknown policy_version=1.0` · `phosphor-agentd: event=policy_loaded policy_version=1.0 sha256=<64hex> path=/tmp/agentd_lab_data/risk-policy.json` · `phosphor-agentd: event=socket_listening path=/dev/socket/phosphor_agentd uid=<u> gid=<g> mode=<m>` · `client_connected=1` · `phosphor-agentd: event=shutdown reason=sigterm uptime_ms=<ms>` · `health pid=<pid>` · `health policy_version=1.0` · `scenario=healthy_start exit=0` | 0 |
| ★7 | `wrong_label` | `phosphor-agentd: event=peer_rejected pid=4242 uid=10000 reason=label_mismatch` · `client_closed=true` · `scenario=wrong_label exit=0` | 0 |
| ★8 | `oversized_frame` | `phosphor-agentd: event=peer_rejected pid=4242 uid=10000 reason=oversized_frame` · `client_closed=true` · `scenario=oversized_frame exit=0` | 0 |
| 9 | `wellformed_frame` | `phosphor-agentd: frame_len=12` · `reply_ok=true` · `scenario=wellformed_frame exit=0` | 0 |
| ★10 | `sigterm_shutdown` | `phosphor-agentd: event=socket_listening path=/dev/socket/phosphor_agentd ...` · `phosphor-agentd: event=shutdown reason=sigterm uptime_ms=<ms>` · `socket_file_still_exists=true` · `scenario=sigterm_shutdown exit=0` | 0 |
| ★11 | `crashloop_trip` | `phosphor-agentd: event=policy_error err=read_failed: ...` · `exit1=1` · `health fast_crashes=3` · `health crashloop=1` · `phosphor-agentd: event=shutdown reason=crashloop uptime_ms=0` · `exit2=1` · `scenario=crashloop_trip exit=1` | 1 |

Notes: (a) in the lab, `socket_listening` logs the **constant** path `/dev/socket/phosphor_agentd` (that is what §2.3 freezes) while the lab listener actually lives in `/tmp`; the live uid/gid/mode values in the lab are **the lab process's own** (observed in the audit lab: `uid=1000 gid=1000 mode=777` — `socket_ids` fstats the listening socket and `/tmp` is 1777), **never** `7521 7521 660`; the device values `7521 7521 660` are proven at the A6/A7 device round, so grepping the lab output for `mode=660` is a spurious STOP (audit BUG #7). (b) `build_id=unknown` in the lab because `ro.build.id` is not set in the env-seam. (c) The mandated 9 scenarios from the phase instructions are the ★ rows; scenarios 0/2/9/11 are additions (unit self-check, absent-prop refusal, well-formed frame, crashloop). (d) The `=true` literals are exact: Rust's `println!("{}", bool)` prints `true`/`false`, never `1` (audit BUG #3 — rev 1's `=1` rows failed an exact grep on a green run). (e) With the bounded connect retry (§7.2), a healthy run's `uptime_ms` includes the daemon's own startup window only — the audit lab observed `uptime_ms=410` on `healthy_start`; any value is acceptable as long as the line matches and the exit is 0.

---

## 8. Verification block — build-side commands (no device)

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
source build/envsetup.sh
lunch akita-cur-user

# 0) tree-state gate: the S1 cc_binary stub must be GONE (replaced, PF-BUG #7)
ls packages/phosphor/services/PhosphorAgentd/
# EXPECT [EXPECT AT BUILD]: Android.bp  phosphor_agentd.rc  src/   (no main.cpp)
rg -n 'cc_binary' packages/phosphor/services/PhosphorAgentd/
# EXPECT: no output (exit 1)
ls packages/phosphor/services/PhosphorIpc/
# EXPECT: Android.bp  lib.rs   (.gitkeep removed)

# 1) passwd-intermediate gate at the VERIFIER-INPUT layer (S3-B audit BUG #3
#    correction: the verifier consumes obj/ETC/passwd_<p>_intermediates/, and
#    0-byte outputs are the documented no-AID outcome for the other four
#    partitions). system_ext must carry the four phosphor rows.
m -j24 passwd_gen_system passwd_gen_system_ext passwd_gen_product \
       passwd_gen_vendor passwd_gen_odm
# EXPECT [EXPECT AT BUILD]: exit 0.
grep -n 'phosphor' out/target/product/akita/obj/ETC/passwd_system_ext_intermediates/passwd_system_ext
# EXPECT [EXPECT AT BUILD]: exactly the four rows:
# system_ext_phosphor_keygate::7520:7520::/:/bin/sh
# system_ext_phosphor_agentd::7521:7521::/:/bin/sh
# system_ext_phosphor_broker::7522:7522::/:/bin/sh
# system_ext_phosphor_shell::7523:7523::/:/bin/sh

# 2) the module builds
m -j24 phosphor-agentd
# EXPECT [EXPECT AT BUILD]: exit 0; "#### build completed successfully ####";
# no "FAILED:", no "ninja: build stopped". (First build of libphosphor_ipc +
# phosphor-agentd; if soong rejects a crate name (liblibc/libserde_json/
# libphosphor_ipc) or a rust API, STOP and paste the error -- do not improvise.)

B=out/target/product/akita/system/bin/phosphor-agentd
R=out/target/product/akita/system/etc/init/phosphor_agentd.rc

# 3) staged artifacts exist and are fresh
ls -l "$B" "$R"
# EXPECT [EXPECT AT BUILD]: both present; mtimes newer than the build start.

# 4) staged .rc byte-identical to plan section 5 (save the section 5 fenced
#    block to /tmp/expected_phosphor_agentd.rc first)
diff -u /tmp/expected_phosphor_agentd.rc "$R"
# EXPECT [EXPECT AT BUILD]: no diff (comment header + service + trigger).
# Content greps (comment-stripped, per the S3 rev-2 lesson):
grep -v '^\s*#' "$R" | grep -c 'user system_ext_phosphor_agentd'   # EXPECT: 1
grep -v '^\s*#' "$R" | grep -c 'group system_ext_phosphor_agentd'  # EXPECT: 1
grep -v '^\s*#' "$R" | grep -c 'socket phosphor_agentd seqpacket+passcred 0660 system_ext_phosphor_agentd system_ext_phosphor_agentd'  # EXPECT: 1
grep -v '^\s*#' "$R" | grep -c 'disabled'                          # EXPECT: 1
grep -v '^\s*#' "$R" | grep -c 'on property:sys.phosphor.safeboot=0'  # EXPECT: 1
grep -v '^\s*#' "$R" | grep -cE 'user phosphor_agentd|group phosphor_agentd'  # EXPECT: 0 (erratum 17)
grep -v '^\s*#' "$R" | grep -c 'onrestart'                         # EXPECT: 0
grep -v '^\s*#' "$R" | grep -c 'capabilities'                      # EXPECT: 0

# 5) HAND-RUN host_init_verifier -- the build NEVER checks Soong init_rc
#    (S3-B audit BUG #1: staging is a bare cp; 109 verifier edges in the
#    graph, 0 touch phosphor). First recover the build's exact argument form
#    from any live Make-side .rc install edge, then substitute our staged rc
#    (the command below IS that form; rev 2 = audit BUG #1's observed edge).
prebuilts/build-tools/linux-x86/bin/ninja -f out/combined-akita.ninja -t commands all \
  | grep '/bin/host_init_verifier ' | head -1
# Canonical form -- rev 2 rewrite (audit BUG #1; the tool's own usage at
# system/core/init/host_init_verifier.cpp:145-165 defines --property-contexts=
# as a SINGLE-TOKEN REPEATABLE option, and main() at :262-268 rejects any
# invocation that supplies positional rc files TOGETHER with the --out_*
# partition-map mode; rev 1's --out_* legs were microdroid build_image's
# shape and exit non-zero unconditionally). Five -p passwd_* intermediates,
# five --property-contexts=<path> (equals form), ONE positional staged rc,
# no --out_*:
out/host/linux-x86/bin/host_init_verifier \
  -p out/target/product/akita/obj/ETC/passwd_system_intermediates/passwd_system \
  -p out/target/product/akita/obj/ETC/passwd_system_ext_intermediates/passwd_system_ext \
  -p out/target/product/akita/obj/ETC/passwd_odm_intermediates/passwd_odm \
  -p out/target/product/akita/obj/ETC/passwd_vendor_intermediates/passwd_vendor \
  -p out/target/product/akita/obj/ETC/passwd_product_intermediates/passwd_product \
  --property-contexts=out/target/product/akita/obj/ETC/plat_property_contexts_intermediates/plat_property_contexts \
  --property-contexts=out/target/product/akita/obj/ETC/system_ext_property_contexts_intermediates/system_ext_property_contexts \
  --property-contexts=out/target/product/akita/obj/ETC/product_property_contexts_intermediates/product_property_contexts \
  --property-contexts=out/target/product/akita/obj/ETC/vendor_property_contexts_intermediates/vendor_property_contexts \
  --property-contexts=out/target/product/akita/obj/ETC/odm_property_contexts_intermediates/odm_property_contexts \
  "$R"
# EXPECT [EXPECT AT BUILD]: exit 0, no output. (The five --property-contexts
# intermediates above are the module names seen in the live ninja edges; the
# recovering grep at the top of this step shows the tree's exact paths -- if
# they differ, mirror the observed edge's paths and keep the SHAPE: 5x -p,
# 5x --property-contexts=<path>, one positional rc, no --out_*.)
# Negative control (cheap, S3-B method): replace system_ext_phosphor_agentd
# with phosphor_agentd in a scratch copy => exit 1 and an error naming the
# unknown user. The identifying prefix is stable
# (`Unable to find UID for 'phosphor_agentd'`); the suffix after the colon is
# DecodeUid's error text (S3-B observed `getpwnam failed`; do not grep the
# suffix -- grep the prefix, audit BUG #1 note):
out/host/linux-x86/bin/host_init_verifier <same args> /tmp/scratched.rc 2>&1 \
  | grep "Unable to find UID for 'phosphor_agentd'"
# EXPECT: exactly one match.

# 6) binary static surface
llvm-readelf -d "$B" | grep NEEDED
# EXPECT [EXPECT AT BUILD]: liblog.so, libcutils.so, libselinux.so present
# (+ libc.so/libm.so/libdl.so baseline); NO libbinder|libhidl|libutils|libbinder_ndk.
llvm-readelf -d "$B" | grep -E 'libbinder|libhidl|libutils|libbinder_ndk'   # EXPECT: no output
llvm-nm -D "$B" | grep -iE 'binder|hidl'                                    # EXPECT: no output
llvm-nm -D "$B" | grep -E 'android_get_control_socket|getpeercon|freecon|__android_log_print|__system_property_get'
# EXPECT [EXPECT AT BUILD]: all five present (the required seams: init socket
# handoff, label admission, logd leg, property read). NOTE: unlike keygate,
# 'socket' appears here BY DESIGN (android_get_control_socket) -- do not reuse
# keygate's socket-free grep. Provenance note (rev 2, audit BUG #8): after the
# librustutils swap, `android_get_control_socket` REMAINS a visible dynamic
# symbol even though our Rust no longer declares the extern -- it is provided
# by libcutils, which librustutils links transitively (`shared_libs:
# ["libbase","libcutils"]` at system/librustutils). Same story for
# getpeercon/freecon (libselinux direct). Do NOT read the symbol's presence as
# evidence the FFI one-liner survived -- the source of record is §4.2/§6.
strings "$B" | grep -E 'sys\.phosphor\.safeboot|phosphor_agentd|phosphor_shell|risk-policy\.json|misc/phosphor/health'
# EXPECT [EXPECT AT BUILD]: sys.phosphor.safeboot; phosphor_agentd (socket name + tag);
# u:r:phosphor_shell:s0; /dev/socket/phosphor_agentd;
# /system/etc/phosphor/risk-policy.json; /data/misc/phosphor/health
strings "$B" | grep -E '/data/misc/keystore|/data/adb|/data/local/tmp|credentials'
# EXPECT: no output (A9)

# 7) source static gates (A3 / A9 / S7-A6 inheritance)
rg -n 'capabilities|android:permission' packages/phosphor/services/PhosphorAgentd packages/phosphor/services/PhosphorIpc
# EXPECT: no output (the words are avoided entirely, comments included)
rg -n '/data/misc/keystore|/data/adb|/data/local/tmp|credentials' packages/phosphor/services/PhosphorAgentd
# EXPECT: comment lines only (the section 2.7 never-list comment in main.rs)
rg -n 'tel\.|sms\.|contacts\.|camera\.|settings\.|geo\.|clip\.' packages/phosphor/services/PhosphorIpc packages/phosphor/services/PhosphorAgentd/src
# EXPECT: no output (no capability vocabulary rides the channel)

# 8) lab harness (plan section 7) -- three rustc invocations (rev 2; audit
#    BUG #3: serde_json must be linked as an extern crate too, because paths
#    inside include!'d files resolve against the EXTERN prelude, not against
#    harness mod items; /tmp/lab_serde.rs is the bundled lab-only
#    serde_json::Value stand-in -- device links the real libserde_json).
rustc --crate-type lib --crate-name libc /tmp/lab_libc.rs -o /tmp/liblibc_lab.rlib
# EXPECT [EXPECT AT CHECK]: exit 0, no output
rustc --crate-type lib --crate-name serde_json /tmp/lab_serde.rs -o /tmp/libserde_lab.rlib
# EXPECT [EXPECT AT CHECK]: exit 0, no output
rustc --edition 2021 --cfg 'feature="lab"' \
      --extern libc=/tmp/liblibc_lab.rlib \
      --extern serde_json=/tmp/libserde_lab.rlib \
      /tmp/agentd_lab.rs -o /tmp/agentd_lab
# EXPECT [EXPECT AT CHECK]: exit 0, no output
for s in unit refuse_safeboot1 refuse_absent policy_missing policy_garbage \
         policy_no_version healthy_start wrong_label oversized_frame \
         wellformed_frame sigterm_shutdown crashloop_trip; do
  echo "=== $s ==="; timeout 30 /tmp/agentd_lab "$s" 2>&1
done
# EXPECT [EXPECT AT CHECK]: exactly the section 7.3 matrix (timeout 30 guards
# against a hang -- a hang is itself a §11.8 deviation: paste and STOP).
```

---

## 9. Commit message (Phosphor-platform, on `main`)

```
agentd: P5-S4 native daemon skeleton (build-side)

Implements the P5-S4 build scope: the phosphor-agentd Rust daemon --
start-condition defence (refuses unless sys.phosphor.safeboot is exactly
"0"), fail-closed policy loader for /system/etc/phosphor/risk-policy.json
(missing/unparseable/version-less => exit 1, never listen), the
init-managed AF_UNIX SOCK_SEQPACKET server (fd via
android_get_control_socket, listen-only, no bind/unlink; label-only
admission of u:r:phosphor_shell:s0 via getpeercon; SO_PEERCRED logged as
defense in depth), the 1 MiB frame cap with peer_rejected-on-oversize
and NOT_IMPLEMENTED replies, the health file (pid, started_at,
policy_version, last_frame_at) with the daemon-side crashloop backstop
(3 consecutive <5 s deaths => marker + exit 1, erratum 18), the exact
seven-event log vocabulary, and named stub traits for the transcript
store, classifier and quarantine envelope.

Adds services/PhosphorIpc as the shared-constants rust_library (socket
name/path, frame header codec, 1 MiB max frame, health path); S7 adds
the AIDL/wire types there. Ships the erratum-17/19 init .rc
(system_ext_phosphor_agentd user/group, init-managed
seqpacket+passcred socket, disabled, started only by
on property:sys.phosphor.safeboot=0) via init_rc -- the prng_seeder/
keystore2 rust_binary precedent. Replaces the S1 cc_binary stub (a
parallel module would collide in soong, preflight PF-BUG #7).

No sepolicy changes: the seqpacket socket rides the unix_stream_socket
self-grants (domain.te:30); getpeercon is a plain getsockopt read
needing no rule; the client-side connectto allow belongs to S7.

Payload only; no device operation. Build evidence:
docs/handoffs/P5-S4-AGENTD-PLAN.md. Device acceptance A1-A10 is a
separate PM-gated execution round.
```

---

## 10. Transcription sequence (S4-B)

```bash
# S4-B.1 -- transcribe artifacts into SRCREPO (repo root == packages/phosphor)
cd /home/cptjaqx/projects/Phosphor-platform
git status --porcelain            # EXPECT: empty before edits
# rm    services/PhosphorIpc/.gitkeep              (dir gains real content)
# write services/PhosphorIpc/Android.bp           (section 3.1, new file)
# write services/PhosphorIpc/lib.rs               (section 3.2, new file)
# rm    services/PhosphorAgentd/main.cpp           (section 6, stub deleted)
# write services/PhosphorAgentd/Android.bp        (section 6, full replacement)
# write services/PhosphorAgentd/phosphor_agentd.rc (section 5, new file)
# write services/PhosphorAgentd/src/main.rs            (section 4.1)
# write services/PhosphorAgentd/src/platform.rs        (section 4.2)
# write services/PhosphorAgentd/src/logging.rs         (section 4.3)
# write services/PhosphorAgentd/src/start_condition.rs (section 4.4)
# write services/PhosphorAgentd/src/policy.rs          (section 4.5)
# write services/PhosphorAgentd/src/sha256.rs          (section 4.6)
# write services/PhosphorAgentd/src/health.rs          (section 4.7)
# write services/PhosphorAgentd/src/socket_loop.rs     (section 4.8)
# write services/PhosphorAgentd/src/stubs.rs           (section 4.9)
git add -A services/PhosphorAgentd services/PhosphorIpc
git status --porcelain            # EXPECT: only the intended paths
git commit -m "<section 9 message>"
NEW_HEAD=$(git rev-parse HEAD); echo "NEW_HEAD=$NEW_HEAD"

# S4-B.2 -- refresh the bare mirror
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git fetch \
    /home/cptjaqx/projects/Phosphor-platform "+refs/heads/main:refs/heads/main"
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse refs/heads/main
# EXPECT: == $NEW_HEAD

# S4-B.3 -- sync the tree
cd /home/cptjaqx/projects/grapheneos-2026091900
repo sync packages/phosphor
git -C packages/phosphor rev-parse HEAD        # EXPECT: == $NEW_HEAD
git -C packages/phosphor status --porcelain    # EXPECT: empty

# S4-B.4 -- run the section 8 verification block; S4-B.5 -- the section 7.3 lab matrix
```

---

## 11. FAILED states → STOP

Any of the following → **STOP**, paste the output, return to the Supervisor/PM:

1. `m phosphor-agentd` exits non-zero, or `FAILED:` / `ninja: build stopped` appears.
2. Soong rejects a crate name (`liblibc`/`libserde_json`/`libphosphor_ipc`), the `rust_binary`/`init_rc`/`stem` properties, or any rustc error — these are this plan's [EXPECT AT BUILD] items; paste verbatim, do not improvise a different API.
3. The staged `.rc` deviates from §5 (wrong user/group prefix, wrong socket line, wrong trigger, extra lines).
4. The hand-run `host_init_verifier` exits non-zero (or the negative control unexpectedly passes).
5. `readelf`/`nm` shows binder/hidl linkage, or misses one of the five required symbols.
6. `strings` shows any phosphor property beyond `sys.phosphor.safeboot`, or any secret path (`/data/misc/keystore`, `/data/adb`, `/data/local/tmp`, `credentials`).
7. The A3/A9/S7-A6 source greps hit non-comment lines.
8. Any lab scenario's observed lines/exit deviate from the §7.3 matrix.
9. `repo sync` lands a different HEAD, or the mirror ref does not advance to `NEW_HEAD`.
10. Anyone proposes a `.te`/sepolicy change to "fix" the socket or admission policy — out of this round's authority (ruling 5: a plan wanting `.te` changes is a STOP).

---

## 12. COMPLETENESS (one line per artifact)

- [ ] 1 `services/PhosphorIpc/{Android.bp,lib.rs}` — shared constants: socket name/path, accepted peer label, frame version/header codec, MAX_FRAME_LEN = 1 MiB with chunking note, frame types, data/policy/health paths (§3)
- [ ] 2 `services/PhosphorAgentd/src/` — 9 modules: start-condition defence (§2.2), fail-closed policy loader with sha256 fingerprint, init-managed socket loop with getpeercon label-only admission + 1 MiB framing + the TYPE_ERROR/NOT_IMPLEMENTED-code reply, health writer with crashloop backoff, exact §2.3 log vocabulary via liblog, named stub traits (§4)
- [ ] 3 `services/PhosphorAgentd/phosphor_agentd.rc` — erratum-⑰/⑲ form, line-exact: prefixed user/group, `socket … seqpacket+passcred 0660`, `disabled`, sole trigger `on property:sys.phosphor.safeboot=0`, no onrestart (§5)
- [ ] 4 `services/PhosphorAgentd/Android.bp` — `rust_binary` with `init_rc` (prng_seeder/keystore2 precedent) + `stem: "phosphor-agentd"` + `librustutils` in rustlibs, no direct libcutils (§6); S1 `main.cpp` stub deleted (§6)
- [ ] 5 Lab harness — `/tmp/lab_libc.rs` + `/tmp/lab_serde.rs` + `/tmp/agentd_lab.rs` incl. the real tree sources; 12 scenarios ≥ the 9 mandated, each with expected lines + exit codes (§7)
- [ ] 6 Verification block — `m phosphor-agentd`; staged `.rc` byte-diff + greps; HAND-RUN `host_init_verifier` with the observed ninja-edge arg form (5× `-p`, 5× `--property-contexts=<path>`, positional rc); readelf/nm/strings; A3/A9/S7-A6 static greps (§8)
- [ ] 7 Commit message (§9)
- [ ] 8 Transcription sequence — SRCREPO commit → mirror refresh → `repo sync packages/phosphor` (§10)

---

## 13. Related issues (mandatory)

1. **Rust-vs-C++ record (spec open item 1).** Rust per ruling 2 (toolchain green in-tree; keystore2/prng_seeder precedents). The C++ fallback is not exercised. Consequence: S7 §3's conditional "`BrokerClient.{h,cpp}` (agentd, C++) or `broker.rs` (if agentd is Rust)" is now decided — the agentd-side broker client will be **Rust**.
2. **Frame size (spec open item 2).** 1 MiB total-frame cap frozen in `PhosphorIpc` with the review note: the Phase 6 screen payload may exceed it and must be **chunked** (or the limit raised by a reviewed change), never silently exceeded. This gates S7's wire design as intended.
3. **PhosphorIpc placement choice (ruling 7).** Implemented as a Rust `rust_library` (`libphosphor_ipc`) rather than C headers — the S4 consumer is Rust, and a library crate gives S7 type-checked constants/codec instead of a header to re-implement. S7 adds AIDL/wire types in the same directory.
4. **`.rc` location vs spec §3.** Spec §3 names `init/phosphor_agentd.rc`; this plan places it module-locally (`services/PhosphorAgentd/phosphor_agentd.rc` with `init_rc`) per the preflight PF-BUG #7/#9 verdict and the S3 keygate precedent (no in-tree module escapes its directory with `../` in `init_rc`). Layout erratum for PM; `init/` stays reserved.
5. **`onrestart` shape (spec open item 4).** None used. init's ordinary non-critical restart (fixed 5 s period, forever — erratum ⑱) is precisely A4's requirement; an `onrestart` section would only react to *other* services' restarts. Recorded as the [VERIFY AT BUILD] resolution.
6. **`build_id` source.** Read best-effort from `ro.build.id`; degrades to `"unknown"`. [EXPECT AT BUILD] If the device round shows an avc denial from this read (A3 must stay empty), drop the read and log `unknown` unconditionally — one-line change, flagged now so it is not a surprise.
7. **S1's `{}` policy artifact vs A1 — superseded by the PM-executed deviation (rev 2).** Rev 1 recorded: the staged `risk-policy.json` was `{}` (S1 minimal artifact), so A1 could not pass and every boot would fast-crash ×3 and latch the marker. **The audit adjudicated Coder's reading correct and the minimal disposition compliant** (audit §C(v)); the PM executed it — `risk-policy/risk-policy.json` in SRCREPO **is now `{"policy_version":"0.1"}`** (commits f8a8753 + 5cc1894, recorded deviation). Consequence for this plan: fail-closed logic is untouched and still proven by lab scenarios 3/4/5, and **A1 on device expects `policy_loaded policy_version=0.1`** (the artifact's literal version string), not 1.0 — §7.3's lab rows keep `policy_version=1.0` only because the *lab* writes its own policy file with that content; any lab run or device check that reads a version string from the shipped artifact must expect `0.1`.
8. **Non-event log lines.** `frame_len=` (mandated by §2.5) and `socket_error=` exist beside the closed 7-event §2.3 vocabulary. They are operational lines, not audit events, and carry no secret material — documented here and in `logging.rs` so the A7 audit reads the vocabulary correctly.
9. **Lab harness is lab-only.** `/tmp/lab_libc.rs` (a minimal libc shim rlib, so the host rustc needs no cargo/network), `/tmp/lab_serde.rs` (a minimal serde_json::Value stand-in, same rationale — the device build links the real `libserde_json`) and `/tmp/agentd_lab.rs` are not payload artifacts; the payload stays exactly at the artifact list. The harness includes the real sources by absolute path (provenance-explicit, keygate pattern).
10. **`NOT_IMPLEMENTED` is an ERROR code, not a frame type (rev 2; audit BUG #6 — hand-off to S7's author).** Rev 1's `lib.rs` comment claimed S7 §2.1 vocabulary for a `TYPE_NOT_IMPLEMENTED = 8` frame, but S7 §2.1's table (`docs/specs/P5-S7-ipc-channels.md:51-58`) defines exactly HELLO/HELLO_ACK/TEXT_IN/TEXT_ACK/SCREEN_OUT/STATE/ERROR and lists `NOT_IMPLEMENTED` only as an **ERROR code** (`:58`). This revision removes the phantom frame type from the wire contract and answers well-formed frames with `TYPE_ERROR` + body `NOT_IMPLEMENTED\n` (`lib.rs` `ERROR_CODE_NOT_IMPLEMENTED`, §3.2; reply built in §4.8 `handle_frame`). **S7 does not need to change** unless it prefers a dedicated frame type; either way the S7 author reconciles this comment with S7 §2.1 — amend S7 §2.1 to bless the ERROR-code reply explicitly, or amend `PhosphorIpc` if S7's author picks a frame type — and this plan records the choice it made so the wire contract has exactly one owner. This is the same category-fidelity family S2's re-audit flagged (BUG #9 there).
11. **`getpeercon` route choice (rev 2; audit A(2)).** Recorded choice: **libc FFI** (`getpeercon`/`freecon` externs + `libselinux` in `shared_libs`), which PF-A4 explicitly blesses and which keeps the dependency surface minimal. The equally valid alternative — `libselinux_rust`'s `SecurityContext::of_peer_socket(&fd, false)` (crate verified at `external/rust/android-crates-io/crates/selinux/src/lib.rs:775-788`) — is available to a future round; note for whoever swaps: `SecurityContext::as_bytes()` **includes the trailing NUL**, so compare via `to_c_string()`/trim, and `shared_libs: ["libselinux"]` becomes redundant (libselinux stays transitively via selinux-sys).
12. **SIGPIPE clearance (audit §C(iv), scenario 13).** The audit's adversarial `sigpipe_attack` (peer sends a valid frame then closes instantly) survived: Rust's runtime installs `SIG_IGN` for SIGPIPE, so the reply `send()` returns EPIPE and the loop tears the connection down cleanly — no `MSG_NOSIGNAL` needed. **Caveat recorded here:** that guarantee belongs to Rust's std runtime, not to this code; if a future C++ port reuses this loop it must set `MSG_NOSIGNAL`/`SO_NOSIGPIPE` itself. Worth one comment in any port's `handle_frame`.
13. **Symbol provenance after the librustutils swap (rev 2).** `llvm-nm -D` on the staged binary still shows `android_get_control_socket` even though no S4 Rust source declares that extern: the symbol comes from libcutils via librustutils (transitive), and the *Rust* entry point is `rustutils::android::sockets::android_get_control_socket` — a different, wrapper symbol name (`_ZN9rustutils...`) that `nm -D` also lists. §8 step 6's grep matches the libcutils symbol; this row records why its presence is expected and is not evidence of a leftover FFI one-liner (whose only source-level trace would be in `platform.rs`, where there is none after rev 2).
14. **Device checks deferred to the PM-gated round / S7 (erratum ㉑).** Live peer-rejection and oversized-frame probes on the device need S7's seqpacket test client (toybox `nc` is stream-only, `socat` absent, and an adb-shell probe would itself generate the avc denials A3 forbids). S4 proves both paths in the lab; A6's negative test rides S7.

---

## 14. Revision log (rev 2) — *appended by the Supervisor (Coder's turn was cut after §13 item 14; the map below is derived from the in-file fixes and greps, per the S2 rev-4 precedent for supervisor-appended mechanical completion)*

Source: `docs/specs/P5-S4-S4A-AUDIT.md` §E fix list (9 findings). Every fix's exact form was pre-validated by the audit in `docs/evidence/s4a-agentd-lab-audit/`.

| BUG # | Sev | Fix | Where (rev-2 plan lines) |
|---|---|---|---|
| #1 | HIGH | Verifier command rewritten to the observed ninja-edge form: 5×`-p passwd`, 5×`--property-contexts=<path>` (single-token repeatable), positional `.rc`; negative-control check added | §8 step 5 (~1990-2030) |
| #2 | HIGH | Six compile fixes: `use crate::health;` in socket_loop (F1); `MetadataExt`/`PermissionsExt` imports in platform (F2/F3); bind-then-borrow in main.rs:59 (F4) and platform.rs:121 (F5) | §4.1, §4.2, §4.8 |
| #3 | HIGH | Lab linkage: `include!("src/main.rs")` + extern-crate header; `#[repr(C)]` dropped from the zero-variant enum (E0084); `usleep` added; §7.3's five boolean rows `=true` (Rust prints `true`) | §7.2 (~1542), §7.1, §7.3 |
| #4 | HIGH | `drain()` → single bounded read; the blocking-pipe deadlock (init escalates to SIGKILL per `service.cpp:1032`) eliminated; clean `shutdown` event restored | §4.2 |
| #5 | MED | Lab clients: ~2 s bounded connect retry (ECONNREFUSED race vs daemon listen) | §7.2 |
| #6 | MED | Phantom `TYPE_NOT_IMPLEMENTED=8` frame type removed; reply is `TYPE_ERROR` + body `NOT_IMPLEMENTED\n` per S7 §2.1's real vocabulary (ERROR codes at `:58`); hand-off recorded (Related 10) | §3.2, §4.8, Related 10 |
| #7 | LOW | Lab-values note added (§7.3 note (a): lab socket uid/gid/mode values are lab-only) | §7.3 |
| #8 | LOW | librustutils swap mandated and applied: `init_once()` first statement of `agentd_main()` (precondition per `sockets.rs:38-43`, prng_seeder pattern `main.rs:134→142`); direct libcutils dep dropped; symbol-provenance row (Related 13) | §0 row 1, Design 12, §4.1 (~242), §6, Related 13 |
| #9 | LOW | §5 "verbatim" → line-exact clearance wording; §3.2 comment honesty | §5, §3.2 |

Also in rev 2: `getpeercon` route recorded as libc FFI with the `libselinux_rust` alternative documented (Related 11, audit A(2) optional); `risk-policy.json` superseded-deviation row rewritten to reflect the PM-executed bump to `policy_version=0.1` with the A1 expectation note (Related 7); Related 13 replaced (typo'd row) with the symbol-provenance check and the old out-of-order row 10 renumbered to 14 (deferred device checks).
