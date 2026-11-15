# P5-S4 Phase Instructions — agentd daemon skeleton (2026-11-15)

**Authority chain:** architecture §2.1/§2.2/§5/§6.3/§6.7/§7/§8 → `docs/specs/P5-S4-agentd-skeleton.md` **rev 2** (errata ⑰–㉑ applied, PM-approved) → preflight `docs/specs/P5-S4-PREFLIGHT-PROBE.md` → these instructions.

**Handoff discipline & payload flow:** unchanged (Coder authors to `docs/handoffs/`; Supervisor transcribes via SRCREPO → mirror → `repo sync packages/phosphor`).

**Standing rulings from the preflight (binding):**
1. `.rc` verbatim is the erratum form: prefixed `user/group system_ext_phosphor_agentd`, `socket phosphor_agentd seqpacket+passcred 0660 system_ext_phosphor_agentd system_ext_phosphor_agentd`, `disabled`, trigger `on property:sys.phosphor.safeboot=0`. lmkd precedent: `system/memory/lmkd/lmkd.rc`.
2. **Language: Rust** (`rust_binary`; toolchain 1.91–1.93.1 green in-tree; precedents keystore2/prng_seeder/aconfigd built on this tree; `rust_binary` carries `init_rc` natively). The spec allows C++ only as a recorded fallback — Rust it is.
3. Socket is **init-managed**: fd via `android_get_control_socket("phosphor_agentd")`; no bind/unlink; the daemon only `listen`s on the handed fd... actually init hands a *bound* socket (+listen if specified) — verify from lmkd's code how it consumes the fd (getControlSocket then listen? already listening?) and mirror it.
4. **Peer admission = label-only** via `getpeercon(3)` (libselinux; Rust: the selinux crate or a tiny libc wrapper — check what keystore2-style code uses). Accept only `u:r:phosphor_shell:s0`. `SO_PEERCRED` (from +passcred) is logged, not an admission criterion.
5. **No new sepolicy** for the socket: seqpacket rides `unix_stream_socket` (granted by `domain.te:30`); the init-managed socket is typed by init (seclabel defaults to service context) — the only S4 policy delta is **nothing**. If the plan wants a `.te` change, STOP-and-report.
6. Crash semantics per erratum ⑱: daemon self-backstop (5s-fast-crash ×3 ⇒ `crashloop` marker + exit 1); init restarts forever at 5s; no SVC_CRITICAL.
7. `services/PhosphorIpc/` gets the shared constants (socket name, frame header, max frame = 1 MiB recorded, health path) as Rust module or headers — builder's choice, recorded.
8. Frame semantics: length-prefixed; oversized ⇒ close + `peer_rejected` (lab-proof); well-formed ⇒ `frame_len=` log + `NOT_IMPLEMENTED` reply.
9. Health file: `pid`, `started_at`, `policy_version`, `last_frame_at` — field names frozen here (S8 contract).
10. Log vocabulary exactly §2.3 (7 events; redaction rule binding). `start` fields include `safeboot`, `build_id`, `policy_version`.
11. Stub surfaces (transcript store, classifier entry, quarantine envelope) as named Rust traits/modules with stub impls — later phases fill without reshaping.
12. Start-condition defence: read `sys.phosphor.safeboot`; not exactly `0` ⇒ log `exit_refused_start` + exit(0), no dir/socket work.

**Build-side verification (no device):** `m -j24 phosphor-agentd` green; staged `.rc` byte-identical; **hand-run `host_init_verifier`** with the build's exact arg form (S3 lesson: the build never checks Soong .rc — the command is in docs/evidence/s3b-keygate-build-audit/REPORT.md); staged binary `readelf`/`strings` (no binder deps; selinux crate or libselinux allowed); **lab harness** (keygate pattern): a host-run main with the property/socket/policy seams stubbed, driving the decision-tree scenarios — at minimum: refuse-start (safeboot≠0), policy-missing fatal, policy-garbage fatal, policy-version-absent fatal, healthy-start-to-loop, crashloop-backoff trip, oversized-frame rejection, wrong-label peer rejection (label string injected), clean SIGTERM shutdown. Each scenario's expected log line + exit code stated. Device A1–A10 rides the batched PM-gated session after S4 (with S3's).

**Scope guard:** S4 is the skeleton — no model client, no network use, no classifier logic beyond version reporting, no STT/tools/broker. The §2.7 never-list is audited.
