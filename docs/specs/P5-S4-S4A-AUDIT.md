# P5-S4 S4-A plan audit — between-phase adversarial audit (Debugger, 2026-11-15)

**Target:** `docs/handoffs/P5-S4-AGENTD-PLAN.md` (author round, 2091 lines, Coder 2026-11-15).
**Authorities:** spec `P5-S4-agentd-skeleton.md` rev 2 (errata ⑰–㉑) → preflight `P5-S4-PREFLIGHT-PROBE.md` → `P5-S4-PHASE-INSTRUCTIONS.md` (12 rulings).
**Method:** `prompts/adversarialDebugger.md` loaded fresh, all 11 sections worked. READ-ONLY on the plan; the GrapheneOS tree (`grapheneos-2026091900`) was read directly from this seat (via exec; `read_file` remains sandbox-refused, as Coder's plan §:6 records). The plan's §3.2/§4/§7 artifacts were transcribed byte-faithfully into `docs/evidence/s4a-agentd-lab-audit/` and **compiled and executed** with the tree's rustc 1.93.1 (S3-A method) — every deviation from the plan text is marked `AUDIT FIX (BUG #x)` inline in that directory.
**Marker:** please proceed (this round).

---

## VERDICT: NOT ACCEPT — findings (rev 2 required before S4-B transcription)

The plan's **decision core is proven correct**: start-condition defence, fail-closed policy order, label-only admission, framing, health/crashloop accounting, the `.rc` erratum form, the lmkd listen-after-handoff pattern, and the stub architecture all **execute green in my independently built lab** (12/12 §7.3 scenarios, plus one adversarial scenario of my own). The three Supervisor tree gifts are all **verified at source** and the plan must adopt them.

But the plan is **not transcribable as written**: the payload sources carry six compile errors that rustc rejects (edition-independent — `m phosphor-agentd` fails at S4-B step 2, and §11.2 then forces a STOP), the §8 step-5 `host_init_verifier` command is a CLI form the tool does not accept (verified against its own usage text and the live ninja graph), and the §7.2/§8 lab build block cannot resolve or compile. All fixes are mechanical; none touch the design.

---

## A. Supervisor's three tree gifts — verified and mandated

**(1) `android_get_control_socket` exists as Rust in librustutils.** CONFIRMED — `system/librustutils/rustutils/src/android/sockets.rs:46-51`: `pub fn android_get_control_socket(name: &str) -> Result<OwnedFd, SocketError>`, wrapping the `cutils_bindgen` FFI (bindgen allowlist at `rustutils/Android.bp:125`). In-tree Rust callers: `system/server_configurable_flags/aconfigd/src/aconfigd_commands.rs`, `system/security/prng_seeder/src/main.rs:142`, `system/software_defined_vehicle/platform/media/audio_mixer/src/main.rs`. **Critical wiring fact the plan must absorb:** the wrapper has a *mandatory* precondition — `rustutils::inherited_fd::init_once()` must be called very early or `take_fd_ownership` returns `Error::NotInitialized` (`sockets.rs:38-43` doc; `inherited_fd.rs:44-84`); prng_seeder calls it first thing (`main.rs:134` → `:142`). The plan's §0 table swap line ("trivial follow-up, behavior identical") must become a **mandated change**: Android.bp `rustlibs += ["librustutils"]`, drop the `android_get_control_socket` extern, call `rustutils::inherited_fd::init_once()` as the first statement of `agentd_main()` (safe: nothing else in the process owns inherited fds; prng_seeder precedent). `libcutils` may then be dropped from `shared_libs` — note `librustutils` itself `shared_libs: ["libbase","libcutils"]`, so liblog/libcutils remain in `readelf -d NEEDED` transitively and §8 step 6's expectations stay valid. The plan's own `__system_property_get` and `getpeercon`/`freecon` externs stay (rustutils has no property-read helper — only `PropertyWatcher`).

**(2) `getpeercon` exists as the selinux crate's `SecurityContext::of_peer_socket`.** CONFIRMED — `external/rust/android-crates-io/crates/selinux/src/lib.rs:775-788` (`getpeercon`/`getpeercon_raw` via `selinux_sys`; `selinux-sys/Android.bp:30` carries `shared_libs: ["libselinux"]`; crate module `libselinux_rust`, `crate_name: "selinux"`, host_supported + product_available). Admission comparison then becomes `SecurityContext::of_peer_socket(&fd, false)?.as_bytes()` vs `ACCEPTED_PEER_LABEL` (note: `as_bytes` includes the trailing NUL — trim or compare with `to_c_string`). **Adjudication: optional.** PF-A4 explicitly blesses the libc-FFI route ("no wrapper dependency required"), and the FFI keeps the dependency surface minimal. Either is acceptable; if adopted, swap `shared_libs: ["libselinux"]` for `rustlibs += ["libselinux_rust"]` (libselinux remains transitively via selinux-sys). Record the choice.

**(3) init does NOT pre-listen; the daemon listens.** CONFIRMED — `system/memory/lmkd/lmkd.cpp:3779` (`android_get_control_socket("lmkd")`) → `:3781-3785` (`ret = listen(ctrl_sock.sock, MAX_DATA_CONN);` with error path). init's `socket` keyword creates the socket **bound but not listening** unless `+listen` is given (`service_parser.cpp:448-453` — decorations are only `passcred`/`listen`; `lmkd.rc:7` has none). The plan's §0 row 3, §4.8 comment, and `socket_loop.rs:1085-1089` (`listen(listen_fd, 8)` after handoff) are **correct as written** — no change.

---

## B. Findings

### BUG #1
**Severity:** HIGH
**Assumption violated:** §8 step 5's claim that the canonical verifier invocation uses `-p passwd×5 --property-contexts <5 space-separated inputs> --out_system=<dir> … "$R"`.
**Attack vector:** Run the plan's exact command shape. `host_init_verifier`'s own usage (`system/core/init/host_init_verifier.cpp:145-165`) defines `--property_contexts=FILE` as a **single-token, repeatable** option and `--out_system=DIR` etc. as **multiple-script-mode** options; `main()` at `:262-268` rejects any invocation that supplies positional rc files together with the partition-map mode (`PrintUsage(); return EXIT_FAILURE`). The live graph confirms the real single-rc form — observed Make-side edge (109 `-p` edges total), e.g. `init.gs_watchdogd.rc`:
```
host_init_verifier -p <passwd_system> -p <passwd_system_ext> -p <passwd_vendor> -p <passwd_odm> -p <passwd_product> \
  --property-contexts=<obj/ETC/plat_property_contexts_intermediates/plat_property_contexts> \
  --property-contexts=<…system_ext…> --property-contexts=<…product…> --property-contexts=<…vendor…> --property-contexts=<…odm…> \
  vendor/google_devices/akita/proprietary/system_ext/etc/init/init.gs_watchdogd.rc
```
The plan's form exits non-zero **unconditionally**, so §8 step 5 would STOP a perfectly good build (§11.4), and the "recover the build's exact argument form first" instruction would find the answer but the canned command below it is still what the executor is told to run.
**Root cause:** S3-B REPORT recorded the correct shape in prose but the plan re-derived it and invented `--out_*` legs (those belong to microdroid's `build_image` path — the only other verifier edge in the graph).
**Fix:** Replace step 5's command with the observed form: five `-p passwd_*` intermediates, five `--property-contexts=<path>` (equals-sign form), positional staged rc; no `--out_*`. Also soften the negative-control expected string to a `grep 'Unable to find UID'` (the suffix after the colon is `DecodeUid`'s error text; S3-B observed `getpwnam failed`).

### BUG #2
**Severity:** HIGH
**Assumption violated:** that the §4 payload sources compile (§11.2 treats any rustc error as a [EXPECT AT BUILD] STOP — they do not compile, so step 2 stops before producing any evidence).
**Attack vector:** Compiled the byte-transcribed §3.2/§4 sources with the tree's rustc 1.93.1 (`prebuilts/rust-toolchain/linux-x86/1.93.1`). Six distinct errors, all edition-independent, all reproduced (audit copies in `docs/evidence/s4a-agentd-lab-audit/` carry `AUDIT FIX (BUG #…)` markers at each site):
| # | Site | Error | Fix |
|---|---|---|---|
| F1 | `socket_loop.rs:1177` | E0433 `health::touch_tick` — file imports only `crate::health::HealthRecord`; bare `health::` resolves against the **extern prelude** (no crate named `health` exists in the soong graph) | add `use crate::health;` |
| F2 | `platform.rs` `ensure_private_data_dir` | E0599 `.uid()` — `MetadataExt` not in scope | add `use std::os::unix::fs::MetadataExt;` |
| F3 | `platform.rs` `socket_ids` | E0599 `.mode()` on `Permissions` — `PermissionsExt` not in scope | add the import (MetadataExt already needed there too) |
| F4 | `main.rs:59` | E0308 `platform::data_dir()` (String) passed where `&str` expected | bind `let dd = …;` and pass `&dd` |
| F5 | `platform.rs:121` | E0716 `Path::new(&data_dir())` borrows a dropped temporary | bind the String first |
| F6 | `logging.rs` `const LOG_TAG: &[u8]` passed as `*const c_char` | compiles only because `as_ptr() as *const libc::c_char` casts `*const u8` → `*const i8` — **valid**, no error; retained after adversarial type check (documented so nobody "fixes" it into a regression) | none |
(Note F6 is a *cleared* suspicion, not a bug — listed because §11.2's STOP discipline means every rustc diagnostic at S4-B must be pre-triaged.)
**Reproduction:** `rustc --edition 2021 --cfg 'feature="lab"' … agentd_lab.rs` on the transcribed sources → exact error set above; the same errors necessarily reproduce under `m phosphor-agentd` (same compiler, edition 2021).
**Root cause:** author-seat could not compile (sandbox), so the Rust was never even syntax-gated.
**Fix:** six mechanical one-liners at the cited sites; no redesign. After rev 2, `m phosphor-agentd` is a fair gate again.

### BUG #3
**Severity:** HIGH
**Assumption violated:** §7.2's claim that including `src/main.rs` at the crate root makes "the modules' `use crate::phosphor_ipc` resolve to the local mod" and that §8's two `rustc` lines are a sufficient lab build recipe; §7.3's expectation lines `unit_ok=1`, `data_dir_absent=1`, `client_closed=1`, `socket_file_still_exists=1`, `reply_ok=1`.
**Attack vector:** Built the harness per §8 step 8 verbatim. Results, all reproduced:
- E0433 `health` / `serde_json` / E0425 `set_lab_listen_fd` inside the included sources — **include! does not put the includer's `mod` items into the included file's resolution scope**; top-level paths in `src/*.rs` resolve against the extern prelude. The plan's harness has no `include!` line at all (the §7.2 comment describes one), no `serde_json` linkage, and the lab `set_lab_listen_fd` lives in `platform` (needs `platform::` qualification in the harness).
- §7.1 `lab_libc.rs`: E0084 — `#[repr(C)]` is illegal on the zero-variant `enum c_void {}` (drop the attribute; that is exactly what the real libc crate ships). Also `usleep` (needed by any connect-retry, see BUG #5) is missing from the extern block.
- **§7.3 boolean literals are wrong**: Rust's `println!("{}", bool)` prints `true`/`false`, never `1`. Every `=1` row in the matrix fails an exact grep — five spurious STOPs (§11.8) on a green run. Observed live: `unit_ok=true`, `data_dir_absent=true`, `client_closed=true`, `socket_file_still_exists=true`, `reply_ok=true`.
**Root cause:** author-seat could not run the lab; both the linkage story and the output strings were authored, not executed.
**Fix (rev 2, §7.2 + §8 step 8):** add the `include!("src/main.rs");` line; add extern-crate linkage for the lab (`--extern` lines) or local `mod` declarations *inside* the harness root and route the included files' cross-module paths through `crate::`; drop `#[repr(C)]` from `c_void`; add `usleep`; rewrite the five §7.3 rows to expect `=true`. The audit directory `docs/evidence/s4a-agentd-lab-audit/` contains a working recipe (4 rustc invocations) the plan can transcribe.

### BUG #4
**Severity:** HIGH (daemon behaviour, would be live on device)
**Assumption violated:** §2.5/spec §5 "clean SIGTERM shutdown, timeout ≤ 2 s" — `SignalWaker::drain()` (`platform.rs`, plan lines 652-660) makes **every** SIGTERM a deadlock.
**Attack vector:** reproduced in the lab (scenario `healthy_start`): the signal handler writes exactly 1 byte into a **blocking** pipe; `drain()` loops `read()` until it returns ≤ 0; the second `read()` blocks forever. Observed: log stops at `client_connected=1`; no `event=shutdown`; process alive past 10 s; exit only via external kill. On device: init's stop paths use SIGKILL for non-gentle services anyway (`service.cpp:1003-1034` — `StopOrReset` goes straight to `KillProcessGroup(SIGKILL)` unless `SVC_GENTLE_KILL`), so the shutdown-event log and the ≤2 s window are lost whenever a SIGTERM does arrive (reboot/shutdown paths, future `gentle` use, tests).
**Root cause:** drain-loop written for an O_NONBLOCK pipe that was never made non-blocking.
**Fix:** read once (bounded), or set `O_NONBLOCK` on the read end and drain until `EAGAIN`. One-line class change; the audit copy uses the bounded single read.

### BUG #5
**Severity:** MEDIUM (lab determinism; masks product behaviour)
**Assumption violated:** §7.2's client threads `connect()` immediately after spawning, while the daemon is still doing dir/health/policy work; the listening socket is bound-but-not-listening for that window.
**Attack vector:** reproduced: `connect()` on a bound-not-listening AF_UNIX socket returns ECONNREFUSED (deterministic on Linux); the plan's bare `assert_eq!(connect, 0)` panics the client thread **before** `sigterm_self()`; `agentd_main()` then polls forever (no SIGTERM ever arrives). All five socket scenarios hang; an S4-B executor following §7.3 hits §11.8 STOPs and may misread the hang as a product bug. (First healthy_start run hung; fixed in the audit copy with a ~2 s bounded retry loop.)
**Fix:** retry `connect()` for up to ~2 s in `connect_client()` (and add `usleep` to `lab_libc.rs`), or have the harness wait for the daemon's `socket_listening` stderr line before connecting. Also note §7.3's healthy_start row expects `shutdown … uptime_ms=<ms>` — with the retry, observed uptime_ms=410.

### BUG #6
**Severity:** MEDIUM (wire-contract drift vs S7)
**Assumption violated:** PhosphorIpc §3.2 comment "Frame types (P5-S7 section 2.1 vocabulary)" — `TYPE_NOT_IMPLEMENTED = 8` is **not** in S7 §2.1's table (`docs/specs/P5-S7-ipc-channels.md:51-58`: HELLO/HELLO_ACK/TEXT_IN/TEXT_ACK/SCREEN_OUT/STATE/ERROR; NOT_IMPLEMENTED appears only as an ERROR *code*, :58).
**Attack vector:** S4 consumes this crate and S7 extends it; the phantom type is now in the shared wire contract the S7 author will transcribe against — the exact category-fidelity failure S2's re-audit flagged (BUG #9 family).
**Fix (pick one, record it):** (a) reply `TYPE_ERROR` + `NOT_IMPLEMENTED` body per S7's own vocabulary (small §4.8 change), or (b) amend S7 §2.1 to add the NOT_IMPLEMENTED frame type explicitly. Do not leave the comment claiming an S7 vocabulary that does not exist.

### BUG #7
**Severity:** LOW
**Assumption violated:** §7.3 note (a) says on-device `socket_listening` shows `7521 7521 660` — correct — but the lab row's live values are the lab process's own (`uid=1000 gid=1000 mode=777` observed: `socket_ids` fstats the listening socket, and `/tmp` is 1777). An S4-B executor grepping for `mode=660` in the lab fails.
**Fix:** one sentence in note (a): lab values are process-owned (uid/gid of the runner, mode of the lab socket), never 7521/660; the device values are proven at the A6/A7 device round.

### BUG #8
**Severity:** LOW
**Assumption violated:** §0's FFI one-liners row frames the rustutils/swap as "behavior identical, trivial follow-up" — it is, **but only with the `init_once()` call** (see A(1)); a swap executed without it fails at runtime with `NotInitialized` (a lab-invisible failure: the lab path never exercises the FFI).
**Fix:** §6 Android.bp + §4.1/§4.2 diffs per A(1); add a §8 step-6 `nm -D` expectation note that `android_get_control_socket` remains visible (provided by libcutils transitively) so the executor does not misread the symbol's provenance after the swap.

### BUG #9
**Severity:** LOW
**Assumption violated:** none — a clearance note. §5's "the §6.5/erratum-⑰/⑲ form **verbatim**" is loose (the spec's §2.1 block is the *pre-erratum* form; the plan's block is the corrected form), but line-by-line the plan's `.rc` is exactly the erratum-⑰/⑲ requirement: prefixed user/group, `socket phosphor_agentd seqpacket+passcred 0660 system_ext_phosphor_agentd system_ext_phosphor_agentd`, `class core`, `disabled`, sole trigger `on property:sys.phosphor.safeboot=0`, no `onrestart`, no `seclabel` (S2 exec-transition covers the domain), no `capabilities`. Verified against lmkd.rc:7 (socket shape) and prng_seeder/keystore2 (init_rc+stem precedents: `prng_seeder/Android.bp:38-45`, `keystore2/Android.bp:142`, `prng_seeder_microdroid` stem-for-dash precedent). No change — recorded so the S4-B byte-diff gate (§8 step 4) judges the right thing.

---

## C. Per-check results (the delegation's (i)–(viii))

**(i) The 9 Rust modules vs spec §2 — PASS with BUG #2/#4 compile/behaviour fixes.** Start-condition refuse (`start_condition.rs`: exactly-"0", absent→`<absent>` refusal, exit 0, no side effects — lab scenarios 1/2 prove `data_dir_absent=true`); policy fail-closed incl. version-absent (`policy.rs`: missing file / unparseable / `policy_version` absent-or-empty / wrong type all → exit 1, **no socket work** — scenarios 3/4/5 prove, health records the fast death); init-socket consumption (`platform.rs::control_socket_fd` + `socket_loop::run` listen-only — A(1)/(3)); label-only admission (`admit()` compares `getpeercon` label to `u:r:phosphor_shell:s0` exactly; SO_PEERCRED pid/uid logged only — scenario 7); framing 1 MiB cap on **total** frame incl. the +1 receive buffer for the boundary case (§4.8 comment) — scenario 8; health fields frozen (§4.7 writes exactly `pid, started_at, policy_version, last_frame_at` + backstop bookkeeping — ruling 9); crashloop self-backstop 5s×3 (`record_fast_death`/`inherited_fast_crashes`/latch — scenario 11 proves trip + latch + no-policy-touch on the latched run); SIGTERM clean (§4.1 `clean_shutdown` resets counters, logs `shutdown` — scenario 6/10, after BUG #4 fix); stub traits (§4.9: named `TranscriptStore`/`Classifier`/`QuarantineEnvelope` + `NullTranscriptStore`/`VersionOnlyClassifier`/`NullQuarantine`, write-free, credential-free); log vocabulary exact §2.3 (seven `event=` forms, field names verbatim; `frame_len=`/`socket_error=` documented as non-event lines — Related issue 8 handles the A7-audit risk) with the redaction rule honored by construction (no body text is ever a log argument; verified per-emitter).

**(ii) `.rc` byte-exact erratum form + Android.bp shape — PASS (BUG #9 note).** Verified above. `PhosphorIpc` as `rust_library` (`libphosphor_ipc`): shape fine; consumes via `rustlibs`. **Zero sepolicy files touched anywhere** — the artifact list contains only `services/PhosphorIpc/*` and `services/PhosphorAgentd/*`; sepolicy appears only in rule 3 and STOP item 10. Ruling 5 honored.

**(iii) main.cpp-stub deletion — CORRECT.** Duplicate module name `phosphor-agentd` is a soong duplicate-module error (preflight PF-BUG #7); leaving `main.cpp` would strand an orphan source with no module. Soong inventory implication: none beyond the module — `phosphor.mk:2` keeps `phosphor-agentd` in PRODUCT_PACKAGES (same package name), staged path unchanged (`/system/bin/phosphor-agentd` via stem; `init_rc` installs the rc to `system/etc/init/`). `.gitkeep` removal for PhosphorIpc is right (dir gains real content).

**(iv) The 12-scenario lab — PASS after BUG #3/#5 harness fixes; compile-and-run DONE by me.** Mapping to spec rows: 1→§2.2/§5-row-1; 2→§5-row-2; 3/4/5→§2.4(3)/A5/§5-last-row; 6→§2.4 happy path; 7→erratum ⑲ admission; 8→§2.5 cap; 9→ruling 8; 10→§2.5/§5 SIGTERM; 11→erratum ⑱; 12→sha256/codec vectors. All 9 mandated scenarios from the phase instructions are present (refuse-start, policy-missing, policy-garbage, policy-version-absent, healthy-start, crashloop-trip, oversized-frame, wrong-label, clean-SIGTERM). **Fail-open coverage:** a start-condition fail-open flips scenario 1/2; a policy fail-open flips 3/4/5; an admission fail-open flips 7 (and the close-vs-reply observable distinguishes it); a cap fail-open flips 8; a shutdown regression flips 6/10; a latch regression flips 11. **My execution (rustc 1.93.1, audit dir): 12/12 scenarios match the §7.3 matrix modulo BUG #3's boolean strings and the two harness fixes**, plus my adversarial scenario 13 (`sigpipe_attack`: peer sends a valid frame and closes instantly; the reply `send()` hits a dead socket — daemon **survived**: Rust std installs `SIG_IGN` for SIGPIPE, `send` returns EPIPE, loop closes cleanly; `frame_len=12` logged then connection torn down. No MSG_NOSIGNAL needed; recorded as a clearance, with the caveat that this guarantee belongs to Rust's runtime, not to this code — worth one source comment so a future C++ port does not inherit the assumption).

**(v) risk-policy.json `{}` — Coder's reading ADJUDICATED CORRECT.** The staged artifact is literally `{}` (verified: `packages/phosphor/risk-policy/risk-policy.json`). §2.4(3) + §5-last-row + A5 mandate: version absent ⇒ `policy_error(policy_version_missing)` ⇒ exit 1 ⇒ no socket. So **A1 cannot pass on device** until the artifact carries a `policy_version`, and worse: today's image would fast-crash ×3 within ~15 s of every boot and **latch the crashloop marker**, staying dead even after a later policy fix until an operator clears it. Minimal compliant disposition (recommended, PM-owned since it touches an S1 artifact): **bump the artifact in SRCREPO as a recorded S4-B deviation** — `risk-policy/risk-policy.json` → `{"policy_version":"0.1"}` (one file, no spec text change, §2.4's fail-closed logic is untouched and still proven by lab scenarios 3/4/5) — and note it in the completion record; deferring A1 leaves the boot-time latch hazard live on any interim flash. Coder's Related issue 7 identified the conflict correctly; only the disposition was open.

**(vi) Evidence-labeling integrity — PASS.** Zero `[EXECUTED]` claims (grep: 1 hit = the rule sentence itself; plan :6-7). `[QUOTED]` spot-checks all verified in-tree: SO_PEERSEC 31 (`socket.h:46`); getpeercon getsockopt (`getpeercon.c:26`); init socket-keyword grammar (`service_parser.cpp:441-453`); lmkd.rc:7 socket line (verbatim); prng_seeder/keystore2 init_rc lines; S1 stub shape (`services/PhosphorAgentd/{Android.bp,main.cpp}` in SRCREPO today); `phosphor.mk:2`; PhosphorIpc `.gitkeep`; passwd intermediate rows (exactly the four prefixed 7520-7523 rows the plan's §8 step 1 expects — verified against today's `out/.../passwd_system_ext_intermediates/passwd_system_ext`); `create_dir_perms` includes `setattr` (plan's foreign-owner chmod is policy-covered). The labeling discipline held.

**(vii) §2.7 never-list — PASS.** No permissions/capability lines anywhere (§8 step 7 greps + read the sources); no property **writes** (only `__system_property_get` reads; §8 step 6 `strings` gate); no policy-artifact write (read-only load); no binder (no binder-family linkage; §8 step 6 nm gate; plan §6 explicitly excludes libbinder/libhidl/libutils); no §6.4 secret paths (code reads only the policy path, health path, control socket; A9 grep is comments-only); stubs write-free; redaction holds at every emitter (args are ids/enums/paths-outside-credentials/os-error text only).

**(viii) Verdict:** **plan ready for S4-B transcription only after the rev-2 fix set: adopt the three gift swaps (A), fix BUG #1-#6 (BUG #7-#9 are one-line notes), and record the A1 disposition per (v).** The decision core needs no redesign; every fix is mechanical and pre-validated in `docs/evidence/s4a-agentd-lab-audit/`.

---

## D. 11-section coverage (adversarialDebugger.md)

1 Assumptions challenged: init hands a listening fd (refuted by lmkd.cpp:3781 + service_parser decorations); verifier CLI shape (refuted — BUG #1); lab linkage story (refuted — BUG #3); "false prints as 1" (refuted); "SIGTERM drain loop terminates" (refuted — BUG #4); "connect succeeds immediately" (refuted — BUG #5). 2 Traced backwards: every §7.3 expected line to its emitter and every fatal path to its exit code. 3 Hidden assumptions: extern-prelude resolution inside include!; blocking-pipe read semantics; ECONNREFUSED on bound-not-listening; rustutils init_once precondition; bool Display. 4 Weakest links: error paths (socket_error fast-death accounting verified in code); signal path (broke — fixed); accept/replacement of an existing peer connection (§4.8 closes the old fd — correct). 5 Error handling: errors never swallowed silently (every Err → log + exit non-zero or connection close); the error handler itself cannot panic (logging CString fallback). 6 Type system: LOG_TAG cast cleared (F6); `body_len` u32 vs usize subtraction guarded by the ≥header check first (checked: `frame.len() - 8` underflows only if decode_header succeeded, which requires len ≥ 8 — safe). 7 External contract: init keyword grammar; host_init_verifier CLI (broke — fixed); getsockopt contracts. 8 Weirdest user: dead peer (sigpipe_attack — survived, cleared); oversized exact-boundary frame (+1 buffer — cleared); latched crashloop re-entry (scenario 11 second run — stays dead, by design, S8 clears). 9 Scope coverage: every §12 completeness row mapped to an artifact and checked; zero-sepolicy verified by artifact enumeration; the 9 mandated scenarios all present. 10 Documentation: §3.2's false S7-vocabulary claim (BUG #6); §0 row-3/trivial-swap wording (BUG #8); §5 "verbatim" (BUG #9). 11 Tests: the lab IS the test suite — executed, 12/12 + 1 adversarial, with the exact deviations recorded.

## E. Rev-2 fix list (all pre-validated in docs/evidence/s4a-agentd-lab-audit/)

1. §8 step 5: rewrite the verifier command to the observed edge form (BUG #1).
2. Six payload compile fixes: `use crate::health;` (socket_loop), `MetadataExt`/`PermissionsExt` imports (platform ×2 fns), bind-then-borrow in main.rs:59 and platform.rs:121 (BUG #2 F1-F5).
3. §7.2/§8 step 8: add `include!("src/main.rs");`, extern linkage lines, drop `#[repr(C)]` on `c_void`, add `usleep`, retry connect ~2 s (BUG #3/#5); rewrite §7.3's five boolean rows to `=true` (BUG #3).
4. `drain()`: single bounded read (BUG #4).
5. Frame-type decision: TYPE_ERROR+code, or amend S7 §2.1 (BUG #6).
6. A(1) swap: librustutils + `inherited_fd::init_once()` first line of `agentd_main()`; drop the socket FFI + libcutils direct dep (BUG #8/A). A(2) getpeercon: FFI or `libselinux_rust` — record the choice.
7. A1 disposition: bump `risk-policy/risk-policy.json` to `{"policy_version":"0.1"}` as a recorded deviation (PM-owned), or explicitly defer A1 accepting the boot-latch hazard (v).
8. §7.3 note (a) lab-values sentence; §5 "verbatim" wording; §3.2 comment honesty (BUG #7/#9/#6).

— Debugger, S4-A between-phase audit round. Silence is not acceptance: this report is the acceptance gate for rev 2.
