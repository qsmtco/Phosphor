# Phase 4 — Phosphor Platform Architecture (System Architecture + Component/Process Map)

**Status:** CLOSED rev 4 — architecture decided; residual verification debt declared (§10.2). Captain's four Phase-5-gating rulings recorded 2026-11-10
**Author:** Coder (develcakes), per Supervisor's Phase 4 kickoff
**Rev 3 note:** rev 2 passed 25 of 26 rev-1 findings; Debugger's re-audit (`docs/P4-ARCH-AUDIT.md`, from line 261) returned FIX FIRST — narrow, raised by **NEW-1** (safe boot's *surface* half was fail-open) plus four wording findings. Rev 3 lands the re-audit's stated minimum-to-ACCEPT and all four MINORs, touching only §6.5, §8, §4, §4.1 and one §10.2 row, per the re-audit's declared scope. `NEW-1..NEW-5` are resolved in the §11 appendix. No redesign: the mechanism was verified sound.
**Rev 4 note (this revision):** narrow closure patch, four changes, nothing else touched. **(1)** The Captain's 2026-11-10 rulings on the four Phase-5-gating questions are recorded in §9 as **DECIDED** — OQ-1 ride GrapheneOS-signed Vanadium for Phases 4–9 (revisit before Phase 12), OQ-2 Keystore-wrapped per-flash credential provisioning with secret-at-rest best-effort until relock, OQ-3 broker-hosted approval card, OQ-4 standalone platform-signed broker app with escalation only if a capability demands it — and every downstream passage that still presented them as open (§1.1, §2.1, §6.2, §8, §10.2, §10) is brought into line. **(2)** Two §10.2 verification-debt rows are **closed by in-tree results**: the `NEARBY_WIFI_DEVICES` / `NFC` / `MODIFY_AUDIO_ROUTING` protection levels are confirmed against `AndroidManifest.xml` and de-tagged in §3 (other tagged rows untouched); app-layer visibility of `sys.phosphor.safeboot` is resolved to an explicit `get_prop(appdomain, phosphor_safeboot_prop)` Phase 5 sepolicy rule, with the mirror-property fallback retained as the escape hatch. **(3)** **NEW-6** corrects the `persist.phosphor.safeboot` latch rationale: a sepolicy `neverallow` "on the reverse direction" is not expressible — `property_service set` has no value dimension. **(4)** **NEW-7** drops `mmap_exec_file_perms` from the enumerated `neverallow` operation set; it is not defined in this tree, and `:file *` is sufficient. Phase 4 is now stated **closed on the declared-debt boundary** — the debt is declared, not discharged.
**Rev 2 note (retained for the trail):** repaired against `docs/P4-ARCH-AUDIT.md` (Debugger, verdict FIX FIRST — 1 BLOCKER, 11 MAJOR, 8 MINOR, 6 NOTE). Finding-by-finding resolution appendix at §11; residual verification debt declared at §10.2. Android API and protection-level claims are aligned with the in-tree citations in that audit; claims not settled in-tree are marked `[TO VERIFY IN TREE]`. The single most consequential change in rev 2 is §6.5: REC-2's safe boot is no longer answered with PackageManager safe mode (which provably cannot work) but with a dedicated `phosphor-keygate` boot-decision service.
**Governing documents:** `docs/PHOSPHOR-VISION.md` (the vision — wins on conflict),
`docs/PHOS-SPEC-001-trust-architecture.md` (trust requirements, front-end-agnostic),
`docs/PHOS-SPEC-002-system-integration.md` (L0–L4 staging model and REC-1..5 — its base-OS choice is superseded per SPEC-001 §14.4; its *staging model* is translated into Android mechanisms throughout this document)
**Scope:** BUILD-PLAN Phase 4, first deliverable. Design only — no code, no build, no device operations in this phase.
**Predecessor state:** Phases 1–3 complete and cryptographically verified; the flashed image is **stock GrapheneOS with zero Phosphor code** (`docs/PROJECT-STATUS.md` §2). This document is the bridge from "we own the platform pipeline" to "Phosphor is in the platform."

---

## 0. Framing rule (PM ruling, 2026-11-10)

The vision wins: the target is the **GrapheneOS-derived Android platform on Pixel 8a (`akita`)**. SPEC-002 was written for a mainline-Linux/postmarketOS target and is therefore not applied literally; where this document translates an SPEC-002 concept (L-level or REC) into an Android mechanism, it is marked **`[ADAPTED FROM SPEC-002 …]`** so the audit can check each adaptation. SPEC-001's front-end-agnostic requirements (R-UI, R-QUAR, R-GATE, R-SEC, R-BRIDGE, R-PERF) carry forward **unchanged in intent**; only their host process changes. Where this document *strengthens* a SPEC-001 requirement rather than merely re-hosting it, that is marked **[STRENGTHENS R-…]** — a requirement-content change is never made silently.

**SPEC-002 concepts that do NOT translate** (recorded, not silently dropped):

- eBPF network policy, cgroup budgets written by the agent, a Rust PID-1 — **superseded by Android's own enforcement machinery** (init, `system_server`, SELinux, cgroups already run the platform). `[ADAPTED FROM SPEC-002 L1: kernel-level policy is owned by Android/SELinux, not by agent-loaded eBPF. See §6.6, OQ-8.]`
- ModemManager/DBus/geoclue/bluez as bridge targets — **superseded by Android framework APIs** behind a broker (§3).
- Mainline-kernel camera/power caveats — moot on the GrapheneOS foundation.
- **Capability domains deliberately deferred, with the decision recorded** (added in rev 2 per MAJOR-8): **NFC** (SPEC-002 L2 names the modem/GPS/Bluetooth/camera arbiter set; the vision §Intended architecture item 3 names "NFC" and "vibration") → vibration is **in** (§3), NFC reader/HCE is **DEFERRED to Phase 10** and the deferral is marked on its row. **Calendar and alarms** (vision line 83: "Calendar, alarms, and other user data where permitted") → **DEFERRED to Phase 9**, marked. These are deferrals, not silent drops; each carries the phase that picks it up.

---

## 1. The Phosphor system shell

**Definition.** The *Phosphor system shell* is the `HOME`/launcher-category system app the device presents after boot and after screen-on: the primary home surface, the notification surface, the voice entry point, and the host of the agent-rendered HTML/JS screen. It supersedes (absorbs, per vision §First real milestone) the ordinary launcher experience while the stock launcher remains installed as the **fallback surface** reached by the safe-boot mechanism in §6.5.

### 1.1 Renderer choice: system WebView, not Custom Tabs, not a browser

| Option | Verdict | Reason |
|---|---|---|
| **System `android.webkit.WebView` inside a platform app** | **CHOSEN** | The vision requires the HTML/JS surface to be "a real operating-system surface rather than an isolated browser page." A WebView inside a *platform-signed, launcher-category system app* gives us: full control of `WebSettings`, the JS bridge surface (`addJavascriptInterface` — the R-BRIDGE/R-SEC mechanism), no browser chrome, no navigation away, and a hardened engine we do not have to ship ourselves (see the trust caveat immediately below). |
| Vanadium *browser* in kiosk mode | rejected (again) | Re-confirmed: a browser tab cannot be the HOME app, cannot own the approval card natively, and would make the shell a guest of the browser's security model. |
| Custom Tabs | rejected | Custom Tabs are an *embedding-other-apps-content* mechanism; the content here is agent-generated and local, and CT gives no bridge surface. |
| Fully native renderer (Skia/custom) | rejected | Reimplements a browser engine — SPEC-002 §6 non-goal ("no display server"), and abandons the proven generated-screen path. |

**Trust caveat carried forward (SPEC-001 §14.2, audit NOTE-1).** The WebView engine is `app.vanadium.webview`, shipped **prebuilt and signed by GrapheneOS** — its certificate is `CN=GrapheneOS`, *not* our platform certificate. Choosing system WebView therefore means **the shell trusts an engine whose signature we do not own**, and every agent-generated screen renders through it. That is an accepted-in-principle position and it is now **accepted, not still pending**: **OQ-1 is DECIDED (Captain, 2026-11-10) — ride GrapheneOS-signed Vanadium for Phases 4–9, revisit before Phase 12 (§9).** The claim in rev 1 that this adds "no added trust burden of our own" is withdrawn as overstated; the accurate statement is *"no new engine-forking burden, but the engine's trust anchor is GrapheneOS's and that is a trust assumption we are accepting."*

**Kiosk constraints (shell app configuration):**

- Declares `android.intent.category.HOME` + `DEFAULT`; the role/default is set in our device config so first boot lands on Phosphor.
- On a platform build we do not need screen-pinning hacks; the shell *is* home. Settings remains reachable via the agent, the fallback launcher (§6.5), or the approval card.
- WebView hardening: `setAllowFileAccess(false)`, no universal access from file URLs, `JavaScriptEnabled(true)` (R-UI-2), `setBlockNetworkLoads(true)`, and a hard subresource allow-list enforced in `WebViewClient.shouldInterceptRequest` — see **§4.1**, which is the control that closes `docs/P4-AUDIT.md` H1.
- Shell UI chrome (status bar items, mic orb, transcript) is a port of the proven `shell.html` chat-mode layout into the WebView-hosted page; the prototype file is the design reference, **not** the shipped artifact.

### 1.2 What replaces what

| Stock role | Phosphor state at Phase 5+ exit |
|---|---|
| Launcher3/Graphene launcher | Installed, not default. Default intent resolves to PhosphorShell **except in safe boot** (§6.5). |
| SystemUI notification shade | Unmodified initially; PhosphorShell surfaces notifications via the broker (`NotificationListenerService`, §3) and renders them as agent screens. Absorption is a later phase (vision §10 "absorbing more system-app experiences"). |
| Setup wizard | Skipped on dev images (device sits wiped at setup per PROJECT-STATUS §3; final flow TBD Phase 11). |

---

## 2. Native agent service and process boundaries

**Definition.** The *Phosphor agent service* is a **native platform daemon**, declared in the device tree, started by `init` from a `.rc`, with a dedicated UID and SELinux domain. This is the vision's "agent service as a platform component, not a Termux process," and the retirement of `runtime/server.py` + Termux supervision.

### 2.1 Shape: three trust positions, four processes

Deliberately **splitting the agent brain from the privileged hands**. UID spellings are fixed once here and used identically in §8 (audit MINOR-1):

| Process | Type | UID & SELinux | Permissions held | Trust position |
|---|---|---|---|---|
| **`phosphor_keygate`** *(added in rev 2, §6.5)* | tiny `oneshot` init service | UID `AID_PHOSPHOR_KEYGATE`; domain `u:r:phosphor_keygate:s0` | **None.** Reads boot properties, the hardware key chord, and one `persist.*` value; writes exactly one property (`sys.phosphor.safeboot`); exits. | **Boot decision only.** Not a trust position: it can only *withhold* the agent, never grant it anything a policy would refuse, and it is fail-closed. Listed so the map has a complete process inventory. |
| **`phosphor_agentd`** | native daemon (Rust; the agent-core logic — conversation, tool schemas, model client, **the authoritative risk classifier**, **quarantine**, **redaction** — ported from `agent_core.py`/`server.py`) | UID `AID_PHOSPHOR_AGENTD`; domain `u:r:phosphor_agentd:s0` | **No Android runtime/signature capabilities.** Network egress; read of the read-only policy artifact; **server end** of the shell↔agentd Unix socket. Nothing else. | Trusted brain, unprivileged hands: its only route to a device capability is a binder call *into* the broker. |
| **`PhosphorBroker`** | privileged platform component (hosting shape = **OQ-4, DECIDED**: standalone platform-signed app, §9) | UID `AID_PHOSPHOR_BROKER` *(spelling provisional; hosting shape now fixed by the OQ-4 ruling)*; domain `u:r:phosphor_broker:s0` | **Exactly the permission set enumerated in §3** — no more, no fewer. §3 is the single source; a list restated elsewhere is what let rev 1's errors propagate. | Trusted hands: sole Phosphor component touching telephony, SMS, contacts, notifications, settings, audio, sensors, location, camera/torch, Bluetooth, clipboard, vibrator; owns the pending-approval registry. |
| **`PhosphorShell`** | system app (HOME category, platform-signed) | UID `AID_PHOSPHOR_SHELL`; domain `u:r:phosphor_shell:s0` | **Exactly one capability permission: `RECORD_AUDIO`** (microphone is the shell's own capture surface, R-BRIDGE-3 "Microphone: live"), plus the socket **client** connect to agentd and binder calls to the broker. Nothing else. | Rendering + capture surface only; every capability request goes to the broker like any other client. |

**Why the split:** the agent daemon parses untrusted model output and quarantined web content; the broker touches `ITelephony` and the contacts provider. If a prompt injection ever wins a turn, it wins *unprivileged* hands; every consequential capability still crosses the broker's risk-classified gate. This is the R-GATE philosophy (`SPEC-001 §7.3` — a guard against model error, accepted as non-sandbox) expressed as **process separation**, which the iOS/Termux prototype never had.

**`[ADAPTED FROM SPEC-002 L2]`** — SPEC-002 wanted the bridge to *become* the hardware resource arbiter ("sole owner of modem/GPS/Bluetooth… clients request; bridge + policy decide"). On Android, `system_server` already is the arbiter; the **broker is Phosphor's arbiter-shaped delegate**: the sole Phosphor-side component that talks to telephony/contacts/settings/**Bluetooth**/camera, and every agent request for hardware crosses its classifier. The prototype's `bridge/src/handlers.rs` dispatch surface is the interface sketch — the right interface drawn against the wrong platform. (Bluetooth, vibrate, NFC, calendar and alarms are individually accounted for in §3; rev 1's "almost 1:1" claim is withdrawn — see MAJOR-8 resolution.)

### 2.2 Lifecycle

- `phosphor_keygate`: `class core`, `oneshot`, started `on late-init`; sets `sys.phosphor.safeboot` and exits (§6.5). No capability permissions; fail-closed.
- `phosphor_agentd`: `service phosphor_agentd /system/bin/phosphor-agentd` declared **`disabled`**, started only by `on property:sys.phosphor.safeboot=0` (§6.5) — never unconditionally at `class_start core`. `onrestart` re-exec; logd logging.
- **Crash-safe home:** the shell must render without a healthy agent. Agent death → shell shows "agent offline, retrying" and the mic still captures (buffered). A reboot into safe boot (§6.5) is the always-available escape — note it requires a reboot, so it is not a *same-session* remedy; the same-session remedy is the shell's offline state plus the fallback launcher reachable from it by an explicit user action.
- `PhosphorBroker`: starts on shell bind; survives agent death so pending approvals are not lost. Hosting shape = OQ-4 (**DECIDED**: standalone platform-signed app, §9).
- `PhosphorShell`: HOME activity lifecycle; transcript state is owned by agentd (or its SQLite store) and re-rendered on shell restart.

**`[ADAPTED FROM SPEC-002 L4]`** — SPEC-002's "Phosphor owns boot" (init starts the session, nothing else ever runs) becomes: **init starts the platform; the session's default UI is Phosphor, and Phosphor's own services are property-gated so a boot can deliberately start without them.** Android's init/zygote/system_server stay stock (they *are* the platform we derive from); what Phosphor owns is the *first surface* and the *escape path*. Owning PID 1 on Android would mean rewriting the platform, which the vision forbids ("modify and extend rather than rewriting").

---

## 3. Capability broker — full inventory (BUILD-PLAN deliverable)

Rev 1's provisional table was wrong in five rows (MAJOR-3..7) and incomplete (MAJOR-8). This is the inventory at API/permission level. **Risk classes are the closed enum defined in §6.3** — `SAFE`, `DESTRUCTIVE`, `DESTRUCTIVE-READ`. No other class name is used anywhere in this document (audit MAJOR-7).

**Protection levels below are quoted from the in-tree citations in `docs/P4-ARCH-AUDIT.md`; `NEARBY_WIFI_DEVICES`, `NFC` and `MODIFY_AUDIO_ROUTING` were subsequently confirmed against `frameworks/base/core/res/AndroidManifest.xml` in rev 4.** Items still marked `[TO VERIFY IN TREE]` are lower-confidence and are a Phase 5 pre-build task, not an assumption to build on.

| Method (prototype vocabulary) | Android API (current) | Permission — protection level | Held by | Risk class | Build-time deliverable |
|---|---|---|---|---|---|
| `tel.dial` | `TelecomManager.placeCall(Uri, Bundle)` | `CALL_PHONE` — **`dangerous`, costsMoney** | broker | `DESTRUCTIVE` | runtime-grant default for broker (system/role default) |
| `tel.answer` | `TelecomManager.acceptRingingCall()` | `ANSWER_PHONE_CALLS` — **`dangerous`** (or `MODIFY_PHONE_STATE` — `signature\|privileged`) | broker | `DESTRUCTIVE` | — |
| `tel.hangup` | `TelecomManager.endCall()` — **`@Deprecated`; refuses emergency calls and (without a privileged caller) self-managed/transactional calls** | `ANSWER_PHONE_CALLS` — **`dangerous`** (`MODIFY_PHONE_STATE` will **not** satisfy it) | broker | `DESTRUCTIVE` | Phase 5 task: determine whether full hang-up coverage needs the privileged path or Telecom `ConnectionService` participation |
| `tel.status` | `TelecomManager.getCallState()` — `@SystemApi @hide` | `READ_PHONE_STATE` — `dangerous`; or `READ_PRIVILEGED_PHONE_STATE` — `signature\|privileged` | broker | `SAFE` | — |
| `sms.send` | `SmsManager.sendTextMessage(destAddr, scAddr, text, sentIntent, deliveryIntent, persistMessage)` / `sendMultipartTextMessage(...)` — **`sendMessage` does not exist** | `SEND_SMS` — **`dangerous`, costsMoney, `hardRestricted`** | broker | `DESTRUCTIVE` | **hard-restricted allowlist entry in our tree** (see note below) |
| `sms.inbox` | `ContentResolver` on `content://sms/inbox` | `READ_SMS` — **`dangerous`, `hardRestricted`** | broker | `DESTRUCTIVE-READ` | hard-restricted allowlist entry |
| `contacts.search` / `contacts.read` *(new vs prototype)* | `ContactsContract` via `ContentResolver` | `READ_CONTACTS` — `dangerous` | broker | `SAFE` for a targeted lookup by name/number resolving an already-approved action; **`DESTRUCTIVE-READ` for an unfiltered bulk dump** (matches §6.3's enum; the pattern distinguishes the two) | — |
| `contacts.write` *(not in prototype; named for completeness)* | `ContactsContract` insert/update/delete | `WRITE_CONTACTS` — `dangerous` | broker | `DESTRUCTIVE` | — |
| `notif.set` / `notif.cancel` | `NotificationManager.notify/cancel` (own notifications) | none | broker | `SAFE` | — |
| `notif.listen` *(new)* | `NotificationListenerService` | `BIND_NOTIFICATION_LISTENER_SERVICE` — **`signature`** (satisfied by platform signing, *not* a "privileged grant") **plus** overlay `config_defaultListenerAccessPackages` (`frameworks/base/core/res/res/values/config.xml`, default `com.android.launcher3`) | broker | `DESTRUCTIVE-READ` (notification content is message content) | overlay entry naming the broker package — **the concrete location that makes `notif.listen` work without a Settings visit** |
| `notif.reply` *(new; vision §"policy-approved message responses")* | `Notification.Action` + `RemoteInput` reply through the listener | as `notif.listen` | broker | `DESTRUCTIVE` | — |
| `wifi.status` / `wifi.list` | `WifiManager.getConnectionInfo()` / `getScanResults()` (scan via `startScan()`) | `ACCESS_FINE_LOCATION` — `dangerous`; `NEARBY_WIFI_DEVICES` — **`dangerous`** (verified in tree, `frameworks/base/core/res/AndroidManifest.xml:2685`) | broker | `SAFE` | — |
| `wifi.toggle` | `WifiManager.setWifiEnabled()` — **`@Deprecated`; for Q+ targets always fails and returns false unless DO/PO/system app** | same as above | broker | `DESTRUCTIVE` | **requires the broker to actually be a system app** — satisfied by the OQ-4 ruling (standalone platform-signed app), and independently an argument for it (audit MINOR-6) |
| `airplane.toggle` | `ConnectivityManager.setAirplaneMode(boolean)` — `@SystemApi` | `NETWORK_AIRPLANE_MODE` — **`signature`** | broker | `DESTRUCTIVE` | — |
| `brightness` | `Settings.System.putInt(SCREEN_BRIGHTNESS)` | `WRITE_SETTINGS` — **`signature\|preinstalled\|appop\|pre23\|role`** (this is **not** `WRITE_SECURE_SETTINGS`) | broker | `SAFE` — **explicit carve-out** in §6.3 (reconciling rev 1's self-contradiction) | — |
| `screen.idle` / `screen.wake` | `PowerManager.goToSleep(long,int,int)` / `wakeUp()` | `DEVICE_POWER` — **`signature\|role`** (rev 1's "`WindowManager` attrs" was wrong) | broker | `SAFE` — explicit carve-out (a screen nap is recoverable and non-consequential) | — |
| *(generic secure-settings write, not a prototype method)* | `Settings.Global` / `Settings.Secure` put | `WRITE_SECURE_SETTINGS` — `signature\|privileged\|development\|role\|installer` | broker | `DESTRUCTIVE` **unless the key is on the policy file's allowlist** | allowlist of writable keys in the policy artifact |
| `tts.speak` | `TextToSpeech.speak(...)` | none (engine binding) | broker | `SAFE` | — |
| `audio.route` *(generalises prototype absence)* | `AudioManager.setMode` / `setSpeakerphoneOn` | `MODIFY_AUDIO_SETTINGS` — `normal`; some routing modes `MODIFY_AUDIO_ROUTING` — **`signature\|privileged\|role`** (verified in tree, `frameworks/base/core/res/AndroidManifest.xml:7595`) | broker | `SAFE` outside a call; `DESTRUCTIVE` during an active call | — |
| `sensor.read` | `SensorManager` listeners | none (except `HIGH_SAMPLING_RATE_SENSORS`, normal) | broker | `SAFE` | — |
| `battery` | `BatteryManager` / `ACTION_BATTERY_CHANGED` | none | broker | `SAFE` | — |
| `geo.get` / `geo.watch` / `geo.unwatch` | `FusedLocationProviderClient.requestLocationUpdates` / `LocationManager` | `ACCESS_FINE_LOCATION` — `dangerous` (+ `ACCESS_BACKGROUND_LOCATION` if agentd-driven) | broker | `DESTRUCTIVE` (per-use, R-BRIDGE-3 class) | — |
| `camera.snapshot` | `CameraManager.openCamera` / Camera2 | `CAMERA` — `dangerous` | broker | `DESTRUCTIVE` (per-use) | — |
| `flashlight` | `CameraManager.setTorchMode(String, boolean)` | **no `@RequiresPermission`** — gated by camera-service access, **not** by `CAMERA` (audit MINOR-7) | broker | `SAFE` | do **not** grant `CAMERA` to the broker for torch alone |
| `vibrate` *(dropped in rev 1 — MAJOR-8)* | `VibratorManager.getDefaultVibrator().vibrate(VibrationEffect)` | `VIBRATE` — `normal` | broker | `SAFE` | — |
| `bt.list` *(dropped in rev 1 — MAJOR-8)* | `BluetoothAdapter.getBondedDevices()` | `BLUETOOTH_CONNECT` — `dangerous` (runtime) | broker | `SAFE` | — |
| `bt.connect` *(dropped in rev 1 — MAJOR-8)* | `BluetoothDevice` profile connect (A2DP/HFP/…), `[TO VERIFY IN TREE: profile-specific API choice]` | `BLUETOOTH_CONNECT` — `dangerous` | broker | `DESTRUCTIVE` (changes a device's routing/state, may pair with an unknown peer) | — |
| `clip.read` | `ClipboardManager.getPrimaryClip()` — **background clipboard access is restricted to focused/allowlisted callers** | none, focus-gated | broker (only when shell is focused) | `DESTRUCTIVE-READ` (the clipboard is arbitrary secret material) | — |
| `clip.write` | `ClipboardManager.setPrimaryClip()` | none | broker | `SAFE` | — |
| `app.open` | `PackageManager`/`LauncherApps` + `startActivity` | none on a platform build | broker | `DESTRUCTIVE` (as the prototype already classified it) | — |
| `app.share` | `Intent.ACTION_SEND` chooser | none | broker | `DESTRUCTIVE` (egress of user content) | — |
| `file.read` / `file.write` / `file.list` (supersedes `kv` for user data) | `MediaStore` / direct paths under the Phosphor data root | broker-scoped directory tree | broker | `SAFE` inside the Phosphor data root; `DESTRUCTIVE` outside it (R-GATE-8 analog: the workspace gate the prototype implemented as `PHOSPHOR_TRUSTED_DIRS`) | data-root definition + sepolicy |
| `web.fetch` / `web.search` | agentd's HTTP client — **not a device capability**, no Android permission | none | agentd | `SAFE` (call); result content → R-QUAR envelope | — |
| `kv.get` / `kv.set` / `save_memory` / `search_memory` | agentd private SQLite store | none | agentd | `SAFE` (R-SEC-4 redaction at save time applies) | — |
| **NFC** reader / HCE — **`[DEFERRED]` Phase 10** | `NfcAdapter.enableReaderMode` / HCE service | `NFC` — **`normal`** (verified in tree, `frameworks/base/core/res/AndroidManifest.xml:2811`); HCE `BIND_NFC_SERVICE` — `signature\|privileged` | broker | would be `DESTRUCTIVE` (tag reads can carry untrusted content; writes are consequential) | deferred per §0 drop list — vision item 3 names NFC; SPEC-002 L2 names the hardware-arbiter set |
| **Calendar** — **`[DEFERRED]` Phase 9** | `CalendarContract` | `READ_CALENDAR` / `WRITE_CALENDAR` — `dangerous` | broker | read `SAFE`, write `DESTRUCTIVE` | deferred per §0 — vision line 83 |
| **Alarms** — **`[DEFERRED]` Phase 9** | `AlarmClock.ACTION_SET_ALARM` intent | none | broker | `DESTRUCTIVE` (creating an alarm alters device wake state and can be user-visible); "replace an existing alarm" and "add a new one" may split into two patterns in Phase 9 — the class does not change | deferred per §0 — vision line 83 |

**`hardRestricted` note (audit MAJOR-4) — the difference between working and silently failing.** `READ_SMS`/`SEND_SMS` are **`dangerous` + `hardRestricted`**, not signature permissions. A hard-restricted permission cannot be granted unless the app appears on the hard-restricted allowlist consulted by `PermissionManagerServiceImpl` at grant time (`Permission.isHardRestricted()`, `Permission.java:234-235`). For the broker this is a **build-system deliverable in our tree** (allowlist entry / role-default grant), and Phase 5 must verify the grant actually lands on-device — the failure mode is a silent `SecurityException` at first SMS, long after the build "succeeded".

**Pattern:** every row is *broker-held permission + broker-enforced classification + approval card*. `phosphor_agentd` holds **none** of these Android permissions (the two agentd-owned rows — `web.*`, `kv.*`/memory — involve no device capability), and `PhosphorShell` holds only `RECORD_AUDIO`.

**`[ADAPTED FROM SPEC-002 L3]`** — "no settings applications exist; system administration is conversation" translates to: the Settings app remains (fallback surface), but every settings knob the user asks about is broker-addressable, and the default UX path is conversation. The settings *provider* (`Settings.System/Secure/Global`) is the mechanism; the agent never writes it directly, and the three are three different gates (`WRITE_SETTINGS` vs `WRITE_SECURE_SETTINGS`), not one.

---

## 4. Generated-HTML/JS rendering surface and native bridge

| Req | Requirement (unchanged in intent) | Android host |
|---|---|---|
| R-UI-1..3 | No script stripping; JS enabled; `on*=` allowed | agentd emits `<ph-screen>` HTML with inline script/`on*=` intact (the `sanitize_screen_html` passthrough survives as a hook, minus the subresource normalisation in §4.1); WebView executes it. |
| R-UI-4 / R-SEC-2 | No secrets in page scope | `addJavascriptInterface` exposes **only** `phosphorApi`, a method-whitelisted proxy object; **no token injection** — page JS never sees the auth token or any credential. |
| R-SEC-1 | Secrets not readable from page JS | Keystore-backed credential access lives in agentd/broker; the page has no file, socket, or Keystore reach. |
| R-SEC-3 | Android secret-path set gated (`.env`-class secret access) | **enumerated in §6.4** as the actual on-device secret surface — Keystore blobs, agentd's credential store and private dir, `/data/adb`, `/data/local/tmp`, and `*.pem`/`*.p12`/`*.p8`/`*.key`/`id_rsa*` anywhere — each `DESTRUCTIVE-READ`, with SELinux `neverallow` as the outer layer. There is no `.env` on a device; §6.4 is the binding table, this row is only its pointer. |
| R-SEC-4 | Histories redacted at save | unchanged, in agentd. |
| R-QUAR-1..3 | Envelope + standing prompt rule + logging | unchanged, in agentd — envelope format identical. |
| R-BRIDGE-1..3 | native handlers callable from page JS; sensitive caps system-prompted; capability matrix maintained | every `phosphorApi` method is a **proxy that ends in a broker RPC** — the page can never reach a capability directly. Approval prompts are native dialogs from the broker's registry (§6.2), never JS-rendered. §3 **is** the capability matrix (§10 deliverable). |
| R-PERF-1..3 | ≤5 ms SAFE overhead, ≤1 ms envelope, ±10% turn latency | classifier stays a data-driven JSON pattern file (R-GATE-5); microbench re-run on-device at Phase 5 exit. |
| **P4-AUDIT H1 (open HIGH, PoC-era)** | remote `<script src>` must not reach the native bridge | **closed by §4.1** on the Android host |

**Bridge topology change vs prototype:** in the prototype, `shell.html` held a `DANGEROUS` list *in page JS* and "unlocked" methods after one confirm — page-scope policy, spoofable by injected page content. Native, this is **inverted**: the page's bridge calls are plain RPC; *classification and approval live outside the page*, and the approval card is a native dialog whose content comes from the registry (P5-H1 invariant: **system-verified content, never page/script scope**). The page cannot fake an approval, cannot unlock a method, and cannot read the registry.

### 4.1 Subresource policy — the control that closes `docs/P4-AUDIT.md` H1 (audit MAJOR-10)

Rev 1 asserted R-UI-1..3 satisfied and gestured at "CSP forbids CDN loads". That reproduces exactly the H1 defect: `setScreen()` in `ios-app/app-shell.html` resurrects a model-emitted `<script src="https://evil.example/x.js">`, subresource loads bypass the navigation allowlist, and attacker JS then owns the native bridge — which on Android is a bridge that reaches telephony, SMS and settings. **Two independent layers close it; both are MUST.**

**Layer 1 — emitted-HTML normalisation (agentd, before the screen leaves the brain).**
- Any element carrying a *remote* resource reference is defanged to an inert placeholder at emit time: `<script src=…>`, `<link href=…>`, `<iframe src=…>`, `<img src=http(s)://…>`, `<object>/<embed>`, `<audio>/<video src=…>`, `@import` in inline `<style>`, and CSS `url(http…)`.
- Inline `<script>` bodies and `on*=` attributes are **untouched** (R-UI-1/R-UI-3 hold in content).
- Each defang is recorded as a visible system note in the turn's transcript ("remote resource blocked: <url>") so the model gets a truthful signal instead of silently-degraded output.

**Layer 2 — runtime enforcement in the shell's WebView (defence in depth; survives a model that outsmarts Layer 1).**
- `WebSettings.setBlockNetworkLoads(true)`, `setAllowFileAccess(false)`, no universal access from file URLs, and `WebViewClient.shouldInterceptRequest` **denies every request whose URL scheme is not `data:`**, returning a synthetic empty response. A remote `<script src>` therefore cannot load even if normalisation misses it.
- **Scope of that allow-list, stated so it does not later look like a bug (NEW-5):** it applies to the agent WebView only, and **no shell-side view ever loads remote content into that WebView** — there is no in-WebView link preview, no remote thumbnail, no embedded document. Any flow that must display remote content performs an explicit **hand-off to the Vanadium browser** (see the renderer isolation note below) rather than attempting an in-place load. If a future shell feature genuinely needs an in-WebView remote fetch, it is added here as a named, reviewed exception — not by relaxing the allow-list.
- A CSP is injected into the screen document by the **shell** (not by the model) as a `<meta http-equiv="Content-Security-Policy">` in the document head:
  `default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'`.
  `script-src 'unsafe-inline'` is required by R-UI-1/R-UI-3 and is safe **only because no host source is admitted**: with `default-src 'none'` and no host in `script-src`, a remote `src` has no matching source and is refused by the engine.
- `connect-src 'none'` means page JS cannot open its own network channels at all — matching R-SEC-2: *all* credentialed egress goes through `phosphorApi` → broker → agentd, never from page scope.

**Requirement accounting.** R-UI-1/R-UI-2/R-UI-3 are **unchanged in content**: inline script, `on*=`, and `javascript:` URLs still work. What §4.1 removes is *remote subresource fetch*, which R-UI-1..3 never granted. R-UI-5 is a SHOULD about *system-prompt steering*; §4.1 is a technical control, so it is marked **[STRENGTHENS R-UI-5]** rather than cited as if it were R-UI-5's content (audit MINOR-3).

**Verification (Phase 5 acceptance test for this subsection):** ask the agent to render `<script src="https://evil.example/x.js">` plus `<img src="https://evil.example/p.png">`. Pass = both blocked with visible notes, inline `<script>` in the same screen still executes, and `window.phosphorApi` is reachable but no request left the device. This is the Android re-run of `docs/P4-AUDIT.md` H1.

**Renderer isolation note:** untrusted *remote* content the user wants to *see* (rather than have summarized) must not render in the agent's WebView context — it opens in the Vanadium browser as a separate trust domain. That is a property of keeping the shell a WebView rather than a browser tab.

---

## 5. Voice, STT, model inference, tool execution, response rendering

**The turn (native):**

1. **Capture** — PhosphorShell (`RECORD_AUDIO`, R-BRIDGE-3 "Microphone: live") records via `AudioRecord`, echo-cancelled, mono. Push-to-talk remains the interaction model (proven); continuous listening is a later, explicitly-gated phase.
2. **STT** — **on-device first**: whisper.cpp (or a packaged Android on-device recognizer) inside agentd or a dedicated `phosphor-sttd`; the prototype's q5_1 warm server becomes a native library. `SpeechRecognizer` with an on-device recognizer is the platform-native alternative — both plug behind one `stt.transcribe` interface (OQ-6, Phase 7).
3. **Model inference** — agentd → model provider over the network (vision-consistent: STT local-or-remote "depending on the selected implementation"; inference remote for the foreseeable future). Credential anchoring = **OQ-2, DECIDED**: Keystore-wrapped + per-flash provisioning, with on-device secret-at-rest recorded as *best-effort* until relock (§9).
4. **Tool execution** — agentd classifies **every** invocation before execution (**R-GATE-1**), using the single deterministic, data-driven classifier of §6.3 (**R-GATE-4**). SAFE executes immediately (R-GATE-2, R-PERF-1); DESTRUCTIVE / DESTRUCTIVE-READ becomes a pending request in the broker's registry → native approval card → single-use grant, 5-min TTL, denial-as-tool-result (R-GATE-3/6/7).
5. **Response rendering** — reply splits into `<ph-screen>` HTML + text (port of `split_reply`); the screen is normalised (§4.1 Layer 1) and handed to the shell over the shell↔agentd channel (§8), which renders it in the WebView; the same turn's text is spoken via TTS when the user's mode is voice-out.

**Render path trust asymmetry (audit MAJOR-9.4) — stated explicitly.** The screen-render path (agentd → shell → WebView) is **not** a capability call and does **not** cross the broker's classifier. That is by design (R-UI-1: the agent's output is the interface) but it means "every consequential action crosses the broker's gate" is true only of *actions*, not of *rendering*. Rendering is where attacker-influenced content would land if a model emitted hostile HTML, which is precisely why §4.1's two layers exist and why the approval card lives outside the page.

**Degradation ladder (voice):** network down → local STT, all on-device capabilities fully usable, model turns fail gracefully with a status screen, nothing queues silently; model provider down/slow → clear on-screen state and a working cancel; **agent daemon down → mic + shell still alive, showing an offline state, with a reboot into safe boot (§6.5) as the always-available escape**; broker down → every gated capability fails closed.

---

## 6. Privilege, identity, consent, audit, policy boundaries

### 6.1 Privilege & identity

- Single-user device (SPEC-001 §4.3, SPEC-002 §6 — unchanged). No multi-user design.
- Device identity: the image is ours (proven Phase 3), bootloader unlocked for development. **Attestation is weak until relock** (SPEC-001 §14.1) — the agent must not treat "this device's identity" as a security property during development. `[ADAPTED FROM SPEC-002 L1/L4 identity discussion → Android verified boot + our AVB key are the identity mechanism once relocked.]`
- Per-process identity: each Phosphor process has its own UID (§2.1, spelled once) so Android permission checks and SELinux can distinguish them — the prototype's "everything runs as one Termux UID" is retired. `phosphor_keygate` is separate for the same reason: it decides, and is denied everything else.

### 6.2 Consent & the approval card

**`[ADAPTED FROM SPEC-002 REC-3]`** — "the approval card remains NATIVE and system-verified; its content MUST come from the system registry, never page/script scope." Android host: the **broker** owns the pending-approvals registry (single-use, 5-min TTL, keyed to the originating session — R-GATE-6 unchanged). The card is a **platform-styled native dialog** showing the exact tool call (command string / URI / contact / payload) with Approve/Deny, and it must render even if the WebView is dead, broken, or showing attacker-influenced content — the same rationale as the SwiftUI card decision (SPEC-001 §12.2).

**Host process = OQ-3, DECIDED (Captain, 2026-11-10): broker-hosted.** The card renders from the broker's pending-approvals registry, so it survives the shell being dead, broken, or showing attacker-influenced content. The consequence is accepted with the ruling: the broker must be able to show UI, which is why its hosting shape (OQ-4) is a standalone platform-signed app rather than a `system_server` injection. §8's diagram now draws the card inside the broker's box as a decided placement, not as a shared annotation.

### 6.3 The policy model — ONE classifier, ONE home, one closed class enum

**Authoritative location: `phosphor_agentd`.** The single evaluation point is agentd, because R-GATE-1 requires every invocation classified *before execution* and agentd is where invocations are born. The broker performs a **re-check against the same read-only artifact** as defence in depth — it is not a second classifier with its own policy.

**Shared artifact (how it stays one policy):** `/system/etc/phosphor/risk-policy.json`, build-time read-only, carrying a `policy_version` and a content hash. Both `phosphor_agentd` and `phosphor_broker` SELinux domains get `read`; **neither can write it** (`neverallow`). The shell has no read access at all.

**Fail-closed order when the two disagree** (explicit, per MAJOR-1):
1. **Either** classification being `DESTRUCTIVE` or `DESTRUCTIVE-READ` wins → the call is gated. A weaker classification never unlocks a stronger one.
2. Broker refuses if `policy_version` is missing, unparseable, or not the build-stamped version → **deny** (fail closed), and log an audit event.
3. Broker's re-check is authoritative *at the moment of execution*, since it is the process holding the permission and the approval registry; agentd's classification exists so that gated calls never leave the brain as if they were safe.

**Closed class enum (audit MAJOR-7).** Exactly three class names exist, and §3 uses only these:

- `SAFE` — executes immediately (R-GATE-2, R-PERF-1).
- `DESTRUCTIVE` — must be approved (R-GATE-3). **`[ADAPTED FROM SPEC-002 REC-4]`** SPEC-002's "SYSTEM tool classes" are *patterns within this class*, not a fourth class: `airplane.toggle`, `wifi.toggle`, radio/service-affecting writes, `Settings.Global/Secure` writes outside the allowlist, `poweroff`/reboot, `bt.connect`, package/state mutations — same fail-closed engine, new kingdom, new pattern entries.
- `DESTRUCTIVE-READ` — read-only, secret-bearing, always approval-gated, and **never auto-approved by any policy entry** (formalises SPEC-001 §7.2/D12 informal usage: `sms.inbox`, `notif.listen`, `clip.read`, contacts DB dump, secret-path reads). Its value is that a policy file cannot silently relax the secret surface the way it can for `SAFE`.

**Explicit carve-outs inside `DESTRUCTIVE`'s "system-config writes" posture** (reconciling rev 1's contradiction, MAJOR-6): `brightness`, `screen.idle`, `screen.wake`, `tts.speak`, `audio.route` outside a call are `SAFE` — recoverable, non-consequential, high-frequency. Everything that changes *reachability* (radios, airplane mode, network config), *communicates externally*, *deletes data*, or *touches secrets* is gated. The carve-out list lives in the policy file's `safe_allow` section so a reviewer can read the whole exception surface in one place.

**Pattern-file schema (BUILD-PLAN deliverable "policy model"), sketched:**

```json
{
  "policy_version": "<build id>",
  "classes": ["SAFE", "DESTRUCTIVE", "DESTRUCTIVE-READ"],
  "patterns": [
    {"id": "P-TEL-1", "class": "DESTRUCTIVE", "category": "external-communication",
     "match": {"method": "tel.dial"}},
    {"id": "P-SYS-3", "class": "DESTRUCTIVE", "category": "system-reachability",
     "match": {"method": "airplane.toggle"}},
    {"id": "P-SEC-1", "class": "DESTRUCTIVE-READ", "category": "secret-path",
     "match": {"path_regex": "^/data/misc/keystore/.*"}}
  ],
  "safe_allow": [
    {"method": "brightness"}, {"method": "screen.idle"}, {"method": "screen.wake"}
  ],
  "settings_allow": ["screen_brightness", "screen_off_timeout"]
}
```

Evaluation is deterministic, in code, first-match-wins with `DESTRUCTIVE-READ` > `DESTRUCTIVE` > `SAFE` in any conflicting match (R-GATE-4, R-GATE-5 — the file is data, the engine is compiled).

### 6.4 Secret hygiene on Android (audit MAJOR-2 — R-SEC-3 translation)

R-SEC-3's `.env`/`.pem`/`id_rsa` path set has **no `.env` on a device**; it is translated rather than repeated. The Android secret surface, all `DESTRUCTIVE-READ`:

| Path | Why |
|---|---|
| `/data/misc/keystore/**` | Keystore blobs (the OQ-2 wrapping keys — Keystore-wrapped, per-flash provisioning) |
| `/data/misc/phosphor/credentials/**` | agentd's provider credential store (OQ-2: Keystore-wrapped; secret-at-rest is *best-effort* until relock) |
| `/data/misc/phosphor/**` (agentd private dir) | conversation store, audit DB |
| `/data/misc/phosphor/risk-policy.override` if ever present | policy override surface |
| `/data/adb/**`, `/data/local/tmp/**` | adb/fastboot staging (prototype-era helpers lived here) |
| `*.pem`, `*.p12`, `*.p8`, `*.key`, `id_rsa*`, `avb.pem`-class material **anywhere** | mirrors D12's pattern set |

**Two enforcement layers, not one:** (a) SELinux `neverallow`s make most of these paths unreachable to `phosphor_agentd` at all — the classifier is not the only guard; (b) for paths agentd *can* read, the classifier's `secret-path` patterns gate them as `DESTRUCTIVE-READ`, so even an in-domain read requires the card. Save-time redaction (R-SEC-4) applies to histories and the audit store alike.

### 6.5 Recovery — safe boot (BLOCKER-1, redesigned)

**`[ADAPTED FROM SPEC-002 REC-2: safe-mode boot path — a boot that starts a plain surface and skips the agent, reachable without the agent's cooperation.]`**

Rev 1 answered this with Android's PackageManager safe mode. **That mechanism provably cannot satisfy REC-2**, on two independent grounds:
1. Android safe mode is a `PackageManagerService` concept — it gates **APK components**. `phosphor_agentd` is an init-started native binary with no package, so safe mode never sees it and cannot stop it (the very thing REC-2 asks to skip).
2. Safe mode disables only **non-system** apps (`ComputerEngine.java:3684`: `if (safeMode && !ps.isSystem()) … NOT_SYSTEM`; `PackageSetting.java:845`). `PhosphorShell` is mandated to be a platform-signed system app (`FLAG_SYSTEM`), so it stays startable **and stays the resolved HOME** — the claimed "boot into stock launcher" does not occur.

**The redesigned mechanism — a boot-time, property-gated safe boot in Phosphor's own code, with no dependence on a healthy device:**

- **Trigger sources.** (a) `androidboot.phosphor.safeboot=1` on the kernel command line, which init exposes as the read-only property `ro.boot.phosphor.safeboot` — set **host-side, out-of-band, by the same USB workflow that already gates every device operation** (PROJECT-STATUS §8; vision: no flash/wipe without explicit approval for that operation). `ro.boot.*` is immutable at runtime, so **the agent cannot clear it and cannot prevent it** — that is the "without the agent's cooperation" property. (b) A hardware-key chord evaluated on-device. Both sources are read by one small, purpose-built early service and collapsed into a single decision, so the boot logic never depends on property arithmetic or on any surface being up.
- **`phosphor-keygate` — the single decision point, evaluated before anything else of ours runs.** A tiny `class core`, `oneshot` init service with no capability permissions: it reads (i) `ro.boot.phosphor.safeboot` and (ii) the hardware key chord, and additionally honours (iii) `persist.phosphor.safeboot` **as a set-only latch — it can request safe boot, never cancel it** (transitions `absent→1` only; a `persist` value of `0` is ignored). **How that one-way property is actually enforced (NEW-6 — corrected):** not by a `neverallow` "on the reverse direction". A `neverallow` against `property_service set` has no value dimension at all — the permission check is on the property *label* only (`property_service.cpp:162-174`), and the value comparison in `CheckType` returns `true` for any empty value (`property_type.cpp:31-35`), so no policy rule can distinguish setting `=1` from setting `=0`. The one-way property therefore rests on three expressible facts, and is stated in those terms: **(a)** `phosphor_agentd` (and every other Phosphor domain) holds **no `set` permission at all** on the latch's type, so nothing inside the running system can write it in either direction; **(b)** the immutable host-set `ro.boot.phosphor.safeboot` carries REC-2 independently of the latch, so the latch is a convenience, not the load-bearing trigger; **(c)** for the one documented writer — the host, over adb, out-of-band — clearing is **exactly as reachable as setting**, deliberately symmetric, because the host+cable operator is already the trusted recovery authority (§6.5 residual gap, REC-1). This keeps the mechanism strictly one-way for everything on the device: the property can withhold the agent, and no on-device Phosphor process can clear a safe boot the host asked for. It then either sets `sys.phosphor.safeboot=0` and starts the agent, or sets `sys.phosphor.safeboot=1` and starts nothing. **Fail-closed default: if keygate does not run or cannot decide, safe boot is the assumption and the agent stays down.**
  ```
  service phosphor_keygate /system/bin/phosphor-keygate
      class core
      user phosphor_keygate
      group phosphor_keygate
      oneshot
  on late-init
      start phosphor_keygate

  service phosphor_agentd /system/bin/phosphor-agentd
      class core
      disabled
      user phosphor_agentd
      group phosphor_agentd
  on property:sys.phosphor.safeboot=0
      start phosphor_agentd
  ```
  (`on property:` triggers match one property; that is exactly why the decision is collapsed into `sys.phosphor.safeboot` by keygate instead of being expressed as a compound condition inside init. Exact init syntax is a Phase 5 implementation detail — the *architecture* is: one early decision, fail-closed, agent gated on its result.)
- **Agent and broker skipped.** `phosphor_agentd` never starts (above). `PhosphorBroker` likewise does not auto-start; because every gated capability routes through it, safe boot is **fail-closed for capabilities** — a plain phone, not a compromised one.
- **Plain surface — same polarity as the agent, i.e. fail-closed.** `PhosphorShell`'s HOME activity reads `sys.phosphor.safeboot` in `onCreate` and hands off to the **stock launcher by explicit component** and finishes itself **unless the property definitively reads `0`**. It is *not* "hand off when set": an absent property, a value the app layer cannot see, or any unparseable value **all** mean hand-off. This mirrors agentd's own start condition exactly (`on property:…=0`, so absent ⇒ never start), which is the point — the two halves of one mechanism must not be written with opposite polarity, or a property the app layer cannot read silently produces launcher-less Phosphor UI with no agent, the *opposite* of REC-2's plain surface. The HOME role is not *reassigned* (which PackageManager safe mode cannot do); the shell **declines to be the surface**. Result: launcher + Settings + no agent — REC-2's "plain shell + minimal network". **App-layer visibility of `sys.phosphor.safeboot` is settled (rev 4, §10.2):** `sys.*` defaults to `system_prop` (`property_contexts:23`), `system_prop` is a `system_public_prop` (`public/property.te:262`), but an *app* read is not implied by either — it needs an explicit `get_prop` rule, of which the tree already ships the precedent `get_prop(appdomain, boot_status_prop)` (`private/app.te:40`). Phase 5 therefore adds `get_prop(appdomain, phosphor_safeboot_prop)` to the sepolicy, and the mirror-property fallback stays as the escape hatch if that grant proves insufficient on-device.
- **Why this works where PackageManager safe mode does not:** the decision point is a boot property consumed by our own `.rc`, not a PackageManager flag; the surface change is our own activity declining, not a system-app disable; and the decision is taken before our UI exists, so no amount of agent health — or agent misbehaviour — can affect it.
- **Residual gap (recorded honestly, as REC-1's line does).** The hardware-key chord lives in `phosphor-keygate`, which is a Phase 5 deliverable; until it ships, on-device safe boot is reached via the host (the `ro.boot` path, or setting the set-only `persist` latch over adb while the device is otherwise healthy), i.e. host + cable — the same residual shape as REC-1's backup gap. The host-set `ro.boot` path is available on day one of Phase 5 and satisfies REC-2's "reachable without the agent's cooperation" from the first bootable Phosphor image.

**`[ADAPTED FROM SPEC-002 REC-1]`** — out-of-band recovery remains the **fastboot ladder** (PROJECT-STATUS §"Recovery ladder"), proven in Phase 3, with its recorded gap: `flash-all.sh` wipes userdata, so recovery restores the *device*, not the *data*; the backup gap is scheduled for Phase 11.

### 6.6 Residual SPEC-002 L1 (OQ-8)

SPEC-002 wanted agent-authored kernel-adjacent policy (eBPF). On Android this maps to nothing safe: SELinux policy is compile-time, and agent-authored eBPF on an Android kernel is a non-starter. Recommended: **declare L1 satisfied-by-platform** (Android/SELinux *is* the kernel-policy layer Phosphor rides). Needs the Captain's sign-off because it retires an entire SPEC-002 level.

### 6.7 Audit

Every approval, denial, expiry, classification decision, policy-version mismatch, and blocked subresource (§4.1) → structured log to a Phosphor audit store (agentd SQLite + logd). The agent may read only through a SAFE-class summarizing tool whose own results are quarantined per REC-5 adaptation. Save-time redaction (R-SEC-4) applies to the audit store.

**`[ADAPTED FROM SPEC-002 REC-5]`** — "quarantine applies to ALL system feedback the agent consumes (logs, statuses, dumpsys output)": every broker result and every diagnostic string entering agent context is wrapped in the **same** R-QUAR envelope as web content. (Rev 1 labelled this `R-QUAR-5`, which is not a SPEC-001 requirement ID — SPEC-001 defines R-QUAR-1..4 only; corrected, audit MINOR-2.)

---

## 7. Offline / degraded-network / unavailable-service behavior

Vision rule (design law): **dead network ≠ dead mic ≠ dead phone.**

| Failure | Required behavior | Host mechanism |
|---|---|---|
| No network | STT local; all on-device capabilities (calls/SMS/camera/contacts/sensors/settings) fully usable; model turns fail *gracefully* with a status screen; nothing queues silently | local STT mandatory path; broker has no network dependency |
| Model provider down/slow | clear on-screen state for in-flight turns; cancel must work (prototype behavior carried) | agentd timeout + abort path |
| Agent daemon crash-loop | shell shows offline state; mic still captures; safe boot (§6.5) is the always-available escape from a reboot, and the stock Dialer is usable during dev | init `onrestart`; `phosphor_keygate` + `sys.phosphor.safeboot` |
| Agent daemon deliberately absent (safe boot) | plain launcher + Settings, **no** gated capabilities | §6.5 |
| Broker crash | all `DESTRUCTIVE`/`DESTRUCTIVE-READ` calls fail closed; nothing is "safely" executed because the broker is missing | fail-closed rule: **no broker, no gated capability, period** |
| Approval TTL expiry | "user declined" tool result (R-GATE-7) | registry |

---

## 8. Component and process map

```
┌────────────────────────── Pixel 8a · Phosphor image (GrapheneOS-derived) ─────────────────────────┐
│  init (stock) ─▶ zygote / system_server (stock Android framework)                                 │
│                                                                                                    │
│  ┌─ phosphor_keygate (oneshot, class core, started `on late-init`) ─────────────────────────────┐ │
│  │  UID AID_PHOSPHOR_KEYGATE · u:r:phosphor_keygate:s0 · no capability permissions               │ │
│  │  reads: ro.boot.phosphor.safeboot (host-set, immutable) · hardware key chord · persist.*       │ │
│  │  sets:  sys.phosphor.safeboot=0|1   (fail-closed: undecided ⇒ 1 = safe boot)                  │ │
│  └───────────┬──────────────────────────────────────────────────────────────────────────────────┘ │
│              │ sys.phosphor.safeboot=0  ⇒  init starts agentd                                       │
│              ▼                                                                                     │
│  ┌─ phosphor_agentd ────────────────────────────────────────────────────────────────────────────┐ │
│  │  AID_PHOSPHOR_AGENTD · u:r:phosphor_agentd:s0 · `disabled`; started ONLY on                    │ │
│  │  property:sys.phosphor.safeboot=0                                                             │ │
│  │  • agent loop, tool schemas, model client (sole network egress)                              │ │
│  │  • AUTHORITATIVE risk classifier (reads /system/etc/phosphor/risk-policy.json — read-only)    │ │
│  │  • R-QUAR envelopes · R-SEC-4 redaction · audit store · §4.1 Layer-1 HTML normalisation      │ │
│  │  • on-device STT (whisper.cpp) or client of phosphor-sttd                                    │ │
│  │  • Android capability permissions: NONE (only network + policy-file read)                     │ │
│  └───────────┬──────────────────────────────────────────────────────┬──────────────────────────┘ │
│              │ binder AIDL (tool calls)                             │ AF_UNIX SOCK_SEQPACKET     │
│              │                                                      │ (shell connects; agentd    │
│              │                                                      │  verifies SO_PEERCRED)     │
│              ▼                                                      ▼                            │
│  ┌─ PhosphorBroker ─────────────────────────────────────┐  ┌─ PhosphorShell (system app, HOME) ─┐ │
│  │ AID_PHOSPHOR_BROKER (spelling provisional;           │  │ AID_PHOSPHOR_SHELL                │ │
│  │   OQ-4 DECIDED: standalone platform-signed app)      │  │                                   │ │
│  │ u:r:phosphor_broker:s0                                │  │ u:r:phosphor_shell:s0             │ │
│  │ • AIDL services: Tel · Sms · Contacts · Notif ·       │  │ • fullscreen WebView (Vanadium     │ │
│  │   Settings · Audio · Sensor · Location · Camera ·     │  │   WebView engine — signature is    │ │
│  │   App · Bluetooth · Clipboard · Torch · Vibrator      │  │   GrapheneOS's; OQ-1 DECIDED to    │ │
│  │ • holds §3's permission set (the one source)           │  │   ride it, Phases 4–9)             │ │
│  │   shell holds RECORD_AUDIO only, nothing else         │  │ • §4.1 Layer 2: blockNetworkLoads, │
│  │ • pending-approval registry (single-use, 5-min TTL)   │  │   shouldInterceptRequest allow-list,│
│  │ • native approval card — OQ-3 DECIDED: rendered here, │  │   injected CSP                     │
│  │   from this registry, never from page scope           │  │ • exposes ONLY `phosphorApi` via   │ │
│  │ • re-checks classification against the SAME policy    │  │   addJavascriptInterface (proxy)   │ │
│  │   artifact; fails closed on version mismatch          │  │ • holds exactly one capability     │ │
│  │ • consumes notification-listener overlay entry        │  │   permission: RECORD_AUDIO         │ │
│  └───────────────────────────────────────────────────────┘  │                                   │ │
│              ▲                                              │ • safe-boot: starts stock launcher │ │
│              │ binder AIDL (phosphorApi RPCs)              │   by component and finishes (§6.5) │ │
│              └──────────────────────────────────────────────┤ • no binder server; socket client │ │
│                                                             └────────────────────────────────────┘ │
│                                                                                                    │
│  page JS ──(JavascriptInterface, method-whitelisted)──▶ PhosphorShell ──(binder AIDL)──▶ PhosphorBroker
│  PhosphorShell ◀──(AF_UNIX SOCK_SEQPACKET, SO_PEERCRED-verified)──▶ phosphor_agentd
│       carries: user text/audio in, normalised screen HTML + turn metadata out (not a capability path)
│  phosphor_agentd ──(binder AIDL)──▶ PhosphorBroker  (tool calls, re-checked there)
│  phosphor_agentd ──(network)──▶ model provider      [ONLY network egress path in Phosphor]
│  agentd/broker/shell ──(private dirs / SQLite)──▶ /* phosphor data root: audit, histories, kv */
│                                                                                                    │
│  SAFE BOOT (§6.5): phosphor_keygate folds ro.boot.phosphor.safeboot (host-set, immutable),         │
│    the hardware key chord, and the set-only persist.phosphor.safeboot latch (absent→1 only; a      │
│    persist value of 0 cannot cancel a host-requested safe boot — latch is set-only by POLICY, not │
│    by a value check: no Phosphor domain holds `set` on its type, and clearing it is symmetric      │
│    with setting it for the one documented writer, the host (NEW-6) into sys.phosphor.safeboot.     │
│    =1 (or absent/unreadable) ⇒ init never starts phosphor_agentd; broker not auto-started;         │
│    shell hands off to the stock launcher by explicit component UNLESS the property is             │
│    definitively 0 — fail-closed on both halves. Result: launcher + Settings, no agent.             │
│  RECOVERY (REC-1): fastboot ladder, host+cable, wipes userdata — data gap = Phase 11.             │
└────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Reconciliation notes (audit MAJOR-9 — map now agrees with §2.1/§5/§6.2):**
1. The approval dialog is **inside the broker's box**: OQ-3 was DECIDED (Captain, 2026-11-10) as broker-hosted, so the map draws the decided placement rather than a shared annotation. §6.2 states the ruling and the accepted consequence (the broker must be able to show UI, which is part of why OQ-4 is a standalone platform-signed app).
2. The shell's permission line says **`RECORD_AUDIO` only**, matching §5 step 1, instead of claiming it holds no capability permissions.
3. `phosphor_agentd` has **no binder permission to the shell**. Shell↔agentd is a `AF_UNIX` `SOCK_SEQPACKET` channel that the *shell* connects to, with agentd verifying `SO_PEERCRED` and the group/label. This removes rev 1's contradictory "neverallow … except to broker + shell".
4. The shell↔agentd mechanism is **chosen, not left as "binder AIDL / local socket"**: a Unix socketpair, because a Rust daemon would otherwise have to implement the binder wire protocol or be fronted by a Java service, and because it gives length-framed messages with credential checks. Its trust properties are stated: the channel carries the turn and the render payload, is **outside** the broker's classifier, and is the reason §4.1 exists.

**SELinux requirements (Phase 5 deliverables).** Written to be compile-ready, because a rule that cannot be expressed invites a Phase 5 author to drop it and silently lose the guarantee:

- `neverallow phosphor_agentd` any capability-adjacent device node (telephony, camera, location, netlink for radios).
- `neverallow phosphor_agentd { phosphor_broker }:binder call` — the *only* permitted binder target; nothing to the shell.
- `neverallow phosphor_shell` binder to capability services directly (broker or nothing).
- **The policy artifact gets a type.** It is a **JSON document** (`risk-policy.json`), stored as type **`phosphor_risk_policy_file`**; `neverallow { phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate } phosphor_risk_policy_file:file { write append create rename setattr unlink };` — read is deliberately allowed for agentd and broker (§6.3) and absent for shell, so this rule states the write ban against its named type rather than a vague "any Phosphor domain".
- **`phosphor_keygate`'s file access, stated as the permission checks it actually is** (NEW-3 — "touching the agent's binary" is not a SELinux predicate, so it is enumerated): `neverallow phosphor_keygate phosphor_agentd_exec:file *;` and `neverallow phosphor_keygate phosphor_agentd_data_file:file *;` — denying the whole operation set on those two types covers `execute`, `execute_no_trans`, `entrypoint`, `read`, `map`, `write`, `create`, `unlink` and `setattr` together. **`mmap_exec_file_perms` is deliberately *not* named (NEW-7):** it is not defined in this tree (`global_macros:25-35` defines the macro set that is actually available, and that name is not among them), so naming it would make the rule fail to compile for no gain — `:file *` already denies strictly more than the macro would have.
- **`phosphor_keygate`'s property access, as a subtraction** (the form used in-tree against `powerctl_prop`): `neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;` — the subtraction is what makes the rule precise, so the blanket form is deliberately not used. `phosphor_safeboot_prop` is declared `exact bool` (AOSP already ships this shape for `sys.boot_completed`), which is also why no `sys.powerctl`-style name special-casing is needed.
- `neverallow phosphor_keygate` binder, network, and any device node other than the key input device.

That last group is what makes keygate a one-way switch rather than a privilege: it can withhold the agent, and it has no expressible route to grant anything. sepolicy lives in our build tree's device/platform overlay.

**Prototype → native migration map.**

| Prototype artifact | Native successor | Fate |
|---|---|---|
| `runtime/server.py` + `agent_core.py` | `phosphor_agentd` | port logic (quarantine, classifier, redaction, tool schemas); drop HTTP front-end/token auth |
| `shell.html` | PhosphorShell WebView page | port UI; bridge inverted to out-of-page policy (§4) |
| `bridge/src/*` dispatch surface | PhosphorBroker AIDL interfaces | method names preserved as tool vocabulary; §3 is the authoritative coverage list |
| Termux / Termux:API / Termux:Boot | init `.rc` + platform packages | retired |
| Tailscale / SSH dev access | adb / fastboot over USB | retired for production shape |
| whisper.cpp in Termux | packaged native STT component | recompiled for the platform |
| `ios/`, `ios-app/` | frozen PoC (TestFlight) | reference only; **H1 defect does not port** — closed in §4.1 |

**Coverage accounting (replaces rev 1's "almost 1:1"):** the prototype's dispatch surface is fully accounted for in §3 — every prototype method is either mapped with its real API/permission, superseded by a renamed native method (`file.*` over `kv.*` for user data), or in a domain marked `[DEFERRED]` with its phase. Bluetooth, vibrate are **added**; NFC, calendar and alarms are **deferred and marked**; `contacts.*`, `notif.listen`, `notif.reply` are **additions** required by the vision, not prototype carry-over.

---

## 9. Decisions and open questions for the Captain (real architectural forks)

*Phase-5-gating:* **OQ-1, OQ-2, OQ-3, OQ-4 — all four DECIDED by the Captain on 2026-11-10** (audit MINOR-8 — OQ-5/6/7 do not gate Phase 5 and remain open by design, listed for completeness). The rulings are recorded verbatim in intent below; the recommendations that preceded them are retained so the trail shows what was advised and what was ruled.

1. **OQ-1 — Vanadium's signature (gates §1.1, §4). DECIDED.** ~~Options: (a) ride GrapheneOS-signed Vanadium … (b) build Chromium from source under our keys …~~ **RULING: ride GrapheneOS-signed Vanadium for Phases 4–9, revisit before Phase 12.** Accepted consequence, recorded: the rendering engine stays under GrapheneOS's trust anchor and our trust requirement sits on the shell app; this is a deliberate acceptance, not an oversight (SPEC-001 §14.2, §1.1). The revisit at Phase 12 is bound to relock (OQ-5), because that is the point at which verification of the engine's provenance under our own key would become meaningful.
2. **OQ-2 — Agent-service credential trust anchor (gates §5, §6.4). DECIDED.** ~~Keystore-wrapped vs plain `/data` config …~~ **RULING: Keystore-wrapped (hardware-backed, StrongBox-capable on the 8a) + per-flash credential provisioning.** Accepted consequence, recorded explicitly: because the bootloader is unlocked until relock (OQ-5, Phase 12), **on-device secret-at-rest is *best-effort*, not a guarantee** — an attacker with the unlocked device can reach what the Keystore wraps. Per-flash provisioning means a re-flash requires re-provisioning, which is a deliberate cost, not a bug. §6.4 carries this qualifier on the credential-store row.
3. **OQ-3 — Approval-card host process (gates Phase 5 UI/manifest work). DECIDED.** ~~Broker-hosted vs shell-hosted …~~ **RULING: broker-hosted.** Rationale as ruled: highest assurance — the card renders from the broker's registry even with the shell dead, broken, or showing attacker-influenced content. Accepted consequence: the broker must be able to show UI, which constrains OQ-4 and is one of the reasons OQ-4 is a standalone app rather than a `system_server` injection. §6.2 and §8's map now draw this as decided.
4. **OQ-4 — Broker hosting shape (gates Phase 5 manifest/sepolicy). DECIDED.** ~~Standalone platform-signed app vs `system_server` injection vs hybrid …~~ **RULING: standalone platform-signed app; escalate (to `system_server` injection or a hybrid) only if a specific capability demands it** — and that escalation is a recorded, per-capability decision, not a drift. Note MINOR-6's constraint in support: `wifi.toggle` requires the broker to be a system app, which this ruling satisfies.
5. **OQ-5 — Relock timing (Phase 12 gate, not Phase 5). Open.** The design works better relocked (verified boot under our key, meaningful StrongBox anchoring) but relock wipes and bricks-on-bad-build. Recommend Phase 12. Note the coupling to the OQ-1 revisit and to OQ-2's best-effort qualifier: relock is what turns both from accepted risk into a guarantee.
6. **OQ-6 — STT engine (decide Phase 7). Open.** whisper.cpp (proven, fully local, models on-device) vs `SpeechRecognizer` on-device recognizer (platform-integrated, less control). Both behind one interface; model packaging is a build-design decision.
7. **OQ-7 — GMS compatibility retention (decide Phase 9). Open.** Nothing in this architecture depends on it either way; recommend drop-by-default.
8. **OQ-8 — Residual SPEC-002 L1 (§6.6). Open.** Recommend declaring L1 satisfied-by-platform; needs sign-off because it retires a SPEC-002 level.

---

## 10. BUILD-PLAN Phase 4 deliverables — status

| Deliverable | Status in this rev | Where |
|---|---|---|
| System architecture document | **delivered** (rev 2, post-audit) | §0–§7 |
| Component and process map | **delivered**, reconciled with §2/§5/§6 | §8 |
| Capability/API inventory | **delivered** at API + permission + protection-level + risk-class + build-deliverable granularity; **hosting-independent**, so OQ-3/OQ-4 never blocked it — and both are now decided anyway (§9) | §3 |
| Data-flow and trust-boundary diagrams | **delivered** (data-flow + trust-zone table) | §10.1 |
| Policy model | **delivered**: closed class enum, one authoritative location, fail-closed order, pattern-file schema | §6.3 |
| Prototype-to-native migration map | **delivered**, with explicit coverage accounting and marked deferrals | §8 |
| Residual verification debt (not a BUILD-PLAN deliverable; added so the exit criterion is not overclaimed) | **declared** | §10.2 |

### 10.1 Data-flow and trust-boundary diagrams

**A. Turn data flow across trust boundaries** (Z0..Z5 defined below):

```
Z0 untrusted ── web/search content, remote model output, notification text, broker results, logcat
      │                                     │
      │ (R-QUAR envelope / REC-5)           │ (R-QUAR envelope)
      ▼                                     ▼
Z2 agentd (unprivileged brain) ◀─────────────── broker results
      │  classify (R-GATE-1/4)  ── DESTRUCTIVE/DESTRUCTIVE-READ ──▶ Z3 broker → approval card (Z5 user)
      │  normalise HTML (§4.1 L1)
      ▼ AF_UNIX socket (SO_PEERCRED)
Z1 shell → WebView renders agent HTML (inline JS allowed, remote subresources blocked both layers)
      │  page JS ──phosphorApi only──▶ shell ──binder──▶ Z3 broker ──▶ Z4 Android services
      ▲                                                      │
      └──────────── user taps / voice (Z5 human) ◀────────────┘
```

**B. Trust zones**

| Zone | Components | What it may do | What it must never do |
|---|---|---|---|
| **Z0 untrusted input** | web content, search results, model output, remote notification bodies, diagnostic strings | enter context only inside R-QUAR envelopes | be treated as instruction |
| **Z1 renderer** | WebView + agent-generated page JS | render, run inline JS, call `phosphorApi` | hold credentials; fetch remote subresources; render an approval card |
| **Z2 brain** | `phosphor_agentd` | compute, network egress, classify, call broker, call shell over the socket | hold Android capabilities; read secret paths; write policy artifact |
| **Z3 privileged** | `PhosphorBroker` | hold the §3 permissions, execute approved calls, own the approval registry | exceed the §3 API surface; write policy artifact; classify more weakly than agentd |
| **Z4 platform** | `system_server`, SELinux, init | arbitrate hardware, enforce policy, gate safe boot | be bypassed by a Phosphor domain (neverallow-enforced) |
| **Z5 out-of-band / human** | host+cable (fastboot, safe-boot property), the user's taps and key chord | approve/deny, flash, force safe boot | be reachable from any in-device Phosphor process |

### 10.2 Residual verification debt (declared, not hidden)

Honest accounting of what this document asserts but has **not** verified in-tree, so Phase 5 does not inherit unexamined claims:

| Item | Status | Owner / when |
|---|---|---|
| `NEARBY_WIFI_DEVICES`, `MODIFY_AUDIO_ROUTING`, `NFC` protection levels marked `[TO VERIFY IN TREE]` in §3 | **CLOSED (rev 4)** — verified in tree: `NEARBY_WIFI_DEVICES` = `dangerous` (`frameworks/base/core/res/AndroidManifest.xml:2685`), `NFC` = `normal` (`:2811`), `MODIFY_AUDIO_ROUTING` = `signature\|privileged\|role` (`:7595`). All three match the levels §3 quoted, so the tags are removed from those rows and the levels stand as quoted | done — no Phase 5 action |
| `bt.connect` profile-specific API choice (A2DP/HFP/…) | not chosen | Phase 5 |
| `tel.hangup` full coverage path (privileged vs Telecom `ConnectionService`) | not decided | Phase 5 |
| `phosphor-keygate` hardware-key chord semantics (which chord; how read without a live framework) | not decided | Phase 5, §6.5 |
| **App-layer visibility of `sys.phosphor.safeboot`** — whether a non-init consumer (the shell's `onCreate`) can read a `sys.*` property, and under what label | **CLOSED (rev 4) — mechanism verified, one Phase 5 rule to write.** The chain: `sys.*` defaults to `system_prop` (`property_contexts:23`); `system_prop` is a `system_public_prop` (`public/property.te:262`); but an **app** read is not implied by either — it requires an explicit `get_prop` rule, of which the tree ships the precedent `get_prop(appdomain, boot_status_prop)` (`private/app.te:40`). **Resolution: Phase 5 adds `get_prop(appdomain, phosphor_safeboot_prop)`** alongside the `phosphor_safeboot_prop` type declaration already specified in §8. The mirror-property fallback (`persist.phosphor.agent_state`) is retained as the **escape hatch**, not the plan: it is used only if that grant proves insufficient on-device. §6.5's hand-off stays fail-closed either way. | Phase 5: write the `get_prop` rule with the manifest/sepolicy work (§8) |
| Approval-card host (OQ-3) and broker hosting shape (OQ-4) | **DECIDED — Captain, 2026-11-10** (broker-hosted card; standalone platform-signed broker app, escalation only if a capability demands it) | no longer a gate; §9 records the rulings, §6.2/§8 reflect them |
| Engine trust acceptance (OQ-1) and credential anchor (OQ-2) | **DECIDED — Captain, 2026-11-10** (ride GrapheneOS-signed Vanadium Phases 4–9, revisit before Phase 12; Keystore-wrapped + per-flash provisioning, secret-at-rest best-effort until relock) | no longer a gate; §1.1/§4 and §5/§6.4 reflect the rulings |
| Phase 5 acceptance tests named in this doc (§4.1 H1 re-run; §3 hard-restricted grant landing; R-PERF microbench) | specified, not yet run | Phase 5 exit |

None of these blocks the architecture; each blocks one specific Phase 5 step, and each is named at the step it blocks.

**Exit-criterion assessment.** The major boundaries, implementation locations and trust assignments are specified well enough to begin Phase 5 without guessing, and **the four dependencies that previously made closure conditional are no longer open**: OQ-1 (engine trust — decided: ride GrapheneOS-signed Vanadium, Phases 4–9), OQ-2 (credential anchor — decided: Keystore-wrapped + per-flash, best-effort at rest until relock), OQ-3 (card host — decided: broker-hosted), OQ-4 (broker hosting — decided: standalone platform-signed app, escalate only on a capability's demand) were all ruled by the Captain on 2026-11-10 (§9). **Phase 4 is therefore CLOSED — on the declared-debt boundary stated in §10.2.** That phrase is deliberate and is the whole of the claim: closure means every architectural fork is decided and every unverified assertion is *named with an owner and a phase* above; it does not mean the residual debt is discharged. What remains open (the §10.2 rows — `bt.connect`'s profile API, `tel.hangup`'s coverage path, keygate's key-chord semantics, one `get_prop` rule to write, and the Phase 5 acceptance tests) is implementation work inside Phase 5, not architecture left undecided here. The two rows that were genuinely unverified claims have been closed by in-tree evidence in this revision (the three protection levels; app-layer property visibility), so no item in §10.2 is an unexamined assertion any longer. Closable without this patch would have required reopening the architecture; closable *only* on this boundary is the honest statement.

---

## 11. Finding-resolution appendix (`docs/P4-ARCH-AUDIT.md`)

Rows 1–27 resolve the rev-1 audit (BLOCKER-1, MAJOR-1..11, MINOR-1..8, NOTE-1..6, plus the closing repo note). Rows 28–32 resolve the rev-2 re-audit (NEW-1..NEW-5). Rows 33–36 are rev 4: two wording corrections raised during Phase 4 closure (**NEW-6**, **NEW-7**) and the two verification-debt rows closed by in-tree evidence (**V-1**, **V-2**). Where a rev 4 row supersedes an earlier row's *wording*, the earlier row is annotated rather than deleted, so the trail shows what was claimed and what replaced it.

| # | Finding | Resolution |
|---|---|---|
| **BLOCKER-1** | REC-2 safe mode cannot work (PackageManager gates APK components only; system-image apps unaffected) | **Redesigned in §6.5**: a dedicated `phosphor-keygate` `oneshot` init service folds the trigger sources (`ro.boot.phosphor.safeboot` host-set/immutable, hardware key chord, and a *set-only* `persist.phosphor.safeboot` latch) into one `sys.phosphor.safeboot` decision, **fail-closed to safe boot if undecided**; `phosphor_agentd` is `disabled` and started only on `sys.phosphor.safeboot=0`; the broker is not auto-started (capabilities fail closed); `PhosphorShell`'s HOME activity hands off to the stock launcher by explicit component **unless the property definitively reads `0`** (polarity corrected in rev 3 — see NEW-1). Marked `[ADAPTED FROM SPEC-002 REC-2]` with its residual gap (hardware-key chord is a Phase 5 deliverable; until then host+cable triggers it). §2.2 and §8's map show keygate as a real process. |
| **MAJOR-1** | Classifier specified three incompatible ways | **§6.3 rewritten**: agentd is the *single authoritative* classifier; broker re-checks against the **same read-only artifact** (`/system/etc/phosphor/risk-policy.json`, version+hash, unwritable by any Phosphor domain); fail-closed disagreement order stated (either-side-DESTRUCTIVE wins; broker authoritative at execution; policy-version mismatch ⇒ deny). §2.1/§4/§5/§8 all now say the same thing. |
| **MAJOR-2** | R-GATE-1 and R-GATE-4 never cited; R-SEC-3 mapped to a non-existent `.env` | **R-GATE-1 cited in §5 step 4 and §6.3; R-GATE-4 cited in §5 step 4 and §6.3.** R-SEC-3 **translated in new §6.4** with the real Android secret-path table plus the two enforcement layers (SELinux `neverallow` + classifier `secret-path` patterns). **Rev 3 closes the surviving sentence** the re-audit caught: the §4 requirements row no longer says "`.env`-class reads gated" — it now reads *Android secret-path set gated* and points at §6.4 as the binding table, matching §3's own wording. |
| **MAJOR-3** | `SmsManager.sendMessage` invented | **§3 corrected** to `sendTextMessage(destAddr, scAddr, text, sentIntent, deliveryIntent, persistMessage)` / `sendMultipartTextMessage(...)`. |
| **MAJOR-4** | SMS/contacts privilege levels wrong; `hardRestricted` missed | **§3**: `SEND_SMS`/`READ_SMS` = `dangerous` + `hardRestricted`; explicit **hard-restricted allowlist entry in our tree** as a build deliverable with the silent-failure warning; privilege column reads `dangerous\|hardRestricted → broker + allowlist`. |
| **MAJOR-5** | Telephony privilege wrong both directions; `tel.status` missing | **§3**: `CALL_PHONE` (dangerous, costsMoney) for dial; `ANSWER_PHONE_CALLS` (dangerous) for answer/hangup, noting `MODIFY_PHONE_STATE` does **not** satisfy `endCall()`; `endCall()` deprecated + refuses emergency/self-managed; `tel.status` = `READ_PHONE_STATE`/`READ_PRIVILEGED_PHONE_STATE` (`@SystemApi @hide`). **§8's broker line no longer enumerates a hand-maintained permission list** (that list was where the errors propagated); it points at §3 as the single source. |
| **MAJOR-6** | Brightness permission wrong, `DEVICE_POWER` missing, SAFE/DESTRUCTIVE contradiction | **§3**: `WRITE_SETTINGS` for `Settings.System` (distinct from `WRITE_SECURE_SETTINGS` for Secure/Global); `PowerManager.goToSleep/wakeUp` with `DEVICE_POWER` (`signature\|role`). Contradiction resolved with explicit **carve-out list** in §6.3 (`brightness`, `screen.idle/wake` = SAFE; reachability-changing writes = DESTRUCTIVE). §8's broker box now cites §3 as the single permission source rather than restating a list that could drift. |
| **MAJOR-7** | Undefined risk classes used normatively | **§6.3 publishes a closed enum** — `SAFE`, `DESTRUCTIVE`, `DESTRUCTIVE-READ` — with REC-4's "SYSTEM tool classes" folded into `DESTRUCTIVE` **patterns**, not a new class. §3 uses only these three names; the word "system-tool class" is removed as a class. |
| **MAJOR-8** | Bluetooth/vibrate/NFC silently dropped; "almost 1:1" false | **§3 gains `bt.list`, `bt.connect`, `vibrate` rows**; **NFC (Phase 10), Calendar (Phase 9), Alarms (Phase 9) added as `[DEFERRED]` rows** with phase markers; **§0 records the deferral decisions** in the drop list; "almost 1:1" withdrawn and replaced by an explicit coverage-accounting paragraph in §8. |
| **MAJOR-9** | Process map contradicts §2.1/§5/§6.2; OQ-3 pre-decided | **§8 rewritten**: approval dialog drawn *outside* both process boxes as an open OQ-3 annotation; shell's permission line = `RECORD_AUDIO` only; agentd **loses** binder-to-shell (neverallow now says broker only); shell↔agentd **chosen** as `AF_UNIX SOCK_SEQPACKET` with `SO_PEERCRED`, with its trust properties and classifier-exemption stated (§8 note 4, §5 asymmetry paragraph). |
| **MAJOR-10** | P4-AUDIT H1 (remote `<script src>` → bridge) not carried forward | **New §4.1**: two MUST layers — agentd-side normalisation of all remote subresource references, plus shell-side `setBlockNetworkLoads`, `shouldInterceptRequest` scheme allow-list (`data:` only) and an injected CSP with no host sources and `connect-src 'none'`. R-UI-1..3 explicitly unchanged; the strengthening is marked **[STRENGTHENS R-UI-5]**; H1 declared **closed on the Android host** with a Phase 5 acceptance test. |
| **MAJOR-11** | Two deliverables deferred; circular exit criterion | **§3 is now the full inventory** (hosting-independent); **§10.1 delivers the data-flow diagram + trust-zone table**; **§6.3 delivers the policy model incl. JSON schema**; **new §10.2 declares the residual verification debt** (unverified protection levels, unchosen sub-decisions, open OQs, unrun acceptance tests); **§10's exit-criterion assessment is explicitly conditional** on OQ-1..OQ-4, with unconditional closure labelled a Captain decision this document does not claim. |
| **MINOR-1** | Three names for one UID | **§2.1 fixed spellings** (`AID_PHOSPHOR_AGENTD`, `AID_PHOSPHOR_SHELL`, `AID_PHOSPHOR_BROKER` *provisional, OQ-4*, plus `AID_PHOSPHOR_KEYGATE` added in rev 2) and **§8 uses the same names**, with the provisional one marked. |
| **MINOR-2** | Invented `R-QUAR-5` | Removed; **§6.7 cites REC-5 only**. |
| **MINOR-3** | R-UI-5 silently converted to a CSP control | **§4.1 marks it [STRENGTHENS R-UI-5]** and states R-UI-5's actual content; §1.1 no longer cites R-UI-5 for CSP. |
| **MINOR-4** | Notification-listener level imprecise; overlay key missing | **§3**: `BIND_NOTIFICATION_LISTENER_SERVICE` = `signature` (satisfied by platform signing), **plus** the concrete overlay `config_defaultListenerAccessPackages` as the build-time location. |
| **MINOR-5** | `airplane.toggle` had no API/permission | **§3**: `ConnectivityManager.setAirplaneMode(boolean)` (`@SystemApi`) + `NETWORK_AIRPLANE_MODE` (`signature`). |
| **MINOR-6** | Wi-Fi deprecation constraint omitted | **§3**: `setWifiEnabled` deprecated, fails for Q+ targets unless DO/PO/system app — recorded as an independent argument for OQ-4's standalone system-app broker; also surfaced in OQ-4. |
| **MINOR-7** | `setTorchMode` doesn't need `CAMERA` | **§3**: torch row states no `@RequiresPermission`, camera-service-gated; explicit note **not** to grant `CAMERA` for torch. |
| **MINOR-8** | Exit gate over-lists OQ-5/6/7 | **§9/§10 gate on OQ-1..OQ-4 only**, with OQ-5/6/7 labelled as later-phase decisions. |
| **NOTE-1** | OQ-1 pre-decided in §1.1; "no trust burden" contradicts SPEC-001 §14.2 | **§1.1 caveat rewritten**: engine is GrapheneOS-signed, that is a trust assumption we accept, OQ-1 must be explicitly accepted by the Captain; overstated claim withdrawn. |
| **NOTE-2** | Open questions genuine, recommendations marked | Preserved; OQ-3's recommendation no longer undermined by §8. |
| **NOTE-3** | §0 drop list is good practice; use it for MAJOR-8 | **§0 drop list extended** with NFC/calendar/alarms deferrals; §8 adds coverage accounting. |
| **NOTE-4** | L1/L3/L4 translations sound; REC-2 was not | L1/L3/L4 markers retained unchanged; **REC-2 rewritten (§6.5)** with `phosphor-keygate` as the decision point; REC-1/REC-3/REC-4/REC-5 markers retained. |
| **NOTE-5** | Vision traps not triggered | No shape changes made; §1.2/§8 keep SystemUI absorption explicitly deferred. |
| **NOTE-6** | Design-only scope verified clean | Still design-only: no code, build, or device operation; only this file was modified. |
| **NOTE (audit §"Also for the record")** | `docs/P4-AUDIT.md` filename collides with "Phase 4"; PoC-era audits `P1-AUDIT…P5-AUDIT.json` should be renamed `POC-AUDIT-1..5` | **Recorded as a recommendation only, not actioned** (no file renamed by this rev). Proposed: rename the five PoC-era audit artifacts to `POC-AUDIT-1..5` before the Phase 4/5 audit trail uses similar names. |
| **NEW-1 (rev-2 re-audit, BLOCKER)** | Safe boot's *surface* half is fail-**open**: the shell handed off to the stock launcher "when set", so an absent or app-invisible `sys.phosphor.safeboot` left Phosphor rendering as HOME with no agent — the opposite of REC-2 — while agentd's own start condition was correctly fail-closed on `=0` | **§6.5's "Plain surface" bullet inverted to the same polarity as the agent**: the shell hands off **unless the property definitively reads `0`**; absent, invisible or unparseable all mean hand-off. §8's map now states the same rule (`UNLESS the property is definitively 0 — fail-closed on both halves`). The two halves of one mechanism can no longer drift apart. Remaining unknown added to §10.2 as a named row: **app-layer visibility of `sys.phosphor.safeboot`** (with a mirror-property fallback if a `sys.*` property proves unreadable to an app). |
| **NEW-2 (MINOR)** | `persist.phosphor.safeboot` could be written to `0`, making keygate two-way and contradicting §6.1/§8's "one-way switch" claim | **§6.5 makes it a set-only latch**: `absent→1` only; a `persist` value of `0` is ignored ~~and the sepolicy `neverallow` sits on the reverse direction~~ (**this enforcement rationale is withdrawn — see NEW-6; `property_service set` has no value dimension, so no rule can sit "on the reverse direction"**). §6.5's residual-gap bullet and §8's safe-boot block restated to match. No availability is lost — the immutable host-set `ro.boot` path already covers the same case. |
| **NEW-3 (MINOR)** | "`neverallow` keygate from … touching the agent's binary or data" is not a SELinux predicate and would not compile | **§8's SELinux section rewritten as compile-ready permissions**: `neverallow phosphor_keygate phosphor_agentd_exec:file *;` and `… phosphor_agentd_data_file:file *;`, with the operation set (`execute`, `execute_no_trans`, `entrypoint`, `read`, `map`, `write`, `create`, `unlink`, `setattr`) named so the rule is expressible on the first attempt. (The list as written in rev 3 also named `mmap_exec_file_perms`; that name is removed in rev 4 — see NEW-7.) |
| **NEW-4 (MINOR)** | "`neverallow` write on the risk-policy artifact from any Phosphor domain" is over-broad and untyped, so it could not be compiled | **§8 names the artifact's type and format** — a **JSON document** (`risk-policy.json`) typed **`phosphor_risk_policy_file`** — and states the write ban against that type across the four Phosphor domains, while preserving §6.3's deliberate *read* grant to agentd and broker. |
| **NEW-5 (MINOR)** | The `data:`-only `shouldInterceptRequest` allow-list conflicts with §4.1's own permission to display remote content via the Vanadium browser, so a link preview or thumbnail would silently blank rather than route | **§4.1 gains an explicit scope bullet**: the allow-list governs the agent WebView only, **no shell-side view ever loads remote content into it**, and any remote display performs an explicit hand-off to the Vanadium browser. A future in-WebView remote fetch must be added as a named reviewed exception, not by relaxing the allow-list. |
| **NEW-6 (rev 4, wording)** | The `persist.phosphor.safeboot` one-way claim was justified by a sepolicy `neverallow` "on the reverse direction". **That is not expressible:** the `property_service` `set` check has no value dimension — it is a label-level permission (`property_service.cpp:162-174`) — and `CheckType` returns `true` for any empty value (`property_type.cpp:31-35`), so no rule can tell `=1` from `=0` | **§6.5's rationale replaced with the statement that is true and verifiable**: (a) `phosphor_agentd` — and every other Phosphor domain — holds **no `set` permission at all** on the latch type, so nothing in the running system can write it in either direction; (b) the host-set immutable `ro.boot.phosphor.safeboot` **carries REC-2 regardless**, so the latch is convenience, not the load-bearing trigger; (c) for the one documented writer (the host, over adb, out-of-band) clearing is **symmetric with setting** — deliberate, since a host+cable operator is already the trusted recovery authority. The one-way property is a *policy* fact, not a value check. §8's safe-boot block restated to match; NEW-2's wording annotated as superseded. |
| **NEW-7 (rev 4, wording)** | The §8 `neverallow` operation enumeration named **`mmap_exec_file_perms`**, which **is not defined in this tree** (`global_macros:25-35`), so naming it would make the rule fail to compile | **Removed from the enumeration**; the rule keeps `:file *`, which is sufficient and denies strictly more than the macro would have. The prose list now reads `execute`, `execute_no_trans`, `entrypoint`, `read`, `map`, `write`, `create`, `unlink`, `setattr`. NEW-3's row annotated so the trail shows the rev-3 wording and its removal. |
| **V-1 (rev 4, verification debt closed)** | §10.2 row: `NEARBY_WIFI_DEVICES`, `NFC`, `MODIFY_AUDIO_ROUTING` protection levels were marked `[TO VERIFY IN TREE]` in §3 | **Verified in tree, row CLOSED.** `NEARBY_WIFI_DEVICES` = `dangerous` (`frameworks/base/core/res/AndroidManifest.xml:2685`); `NFC` = `normal` (`:2811`); `MODIFY_AUDIO_ROUTING` = `signature\|privileged\|role` (`:7595`). **All three match the levels §3 already quoted**, so the assertion was correct and only the tag was wrong: the three `[TO VERIFY IN TREE]` tags are removed from those §3 rows, the levels are kept verbatim with their in-tree citations added, and **no other tagged row in §3 was touched** (`bt.connect`'s profile-API choice remains tagged and remains debt). |
| **V-2 (rev 4, verification debt closed)** | §10.2 row: app-layer visibility of `sys.phosphor.safeboot` — whether a non-init consumer can read it, and under what label | **Resolved to a Phase 5 sepolicy rule, row CLOSED.** `sys.*` defaults to `system_prop` (`property_contexts:23`); `system_prop` is a `system_public_prop` (`public/property.te:262`); but neither implies an *app* read — that needs an explicit `get_prop`, for which the tree ships the precedent `get_prop(appdomain, boot_status_prop)` (`private/app.te:40`). **Resolution: add `get_prop(appdomain, phosphor_safeboot_prop)` in Phase 5 sepolicy**, alongside the `phosphor_safeboot_prop` declaration §8 already specifies. The mirror-property fallback is **kept as the escape hatch** (§10.2, §6.5), not promoted to the plan. §6.5's hand-off remains fail-closed, so an unreadable property still yields safe boot. |

---
*End of Phase 4 system architecture, rev 4. Design only — no code, builds, or device operations were performed. No file other than this document was created or modified. Phase 4 is closed on the declared-debt boundary of §10.2: all four Phase-5-gating open questions are decided (§9), and the residual items are implementation work named with an owner and a phase, not undecided architecture.*
