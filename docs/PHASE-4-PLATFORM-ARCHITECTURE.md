# Phase 4 — Phosphor Platform Architecture (System Architecture + Component/Process Map)

**Status:** DRAFT rev 2 (post-audit) for Captain JAQ review — 2026-11-10
**Author:** Coder (develcakes), per Supervisor's Phase 4 kickoff
**Rev 2 note:** repaired against `docs/P4-ARCH-AUDIT.md` (Debugger, verdict FIX FIRST — 1 BLOCKER, 11 MAJOR, 8 MINOR, 6 NOTE). Finding-by-finding resolution appendix at §11; residual verification debt declared at §10.2. Android API and protection-level claims are aligned with the in-tree citations in that audit; claims not settled in-tree are marked `[TO VERIFY IN TREE]`. The single most consequential change is §6.5: REC-2's safe boot is no longer answered with PackageManager safe mode (which provably cannot work) but with a dedicated `phosphor-keygate` boot-decision service.
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

**Trust caveat carried forward (SPEC-001 §14.2, audit NOTE-1).** The WebView engine is `app.vanadium.webview`, shipped **prebuilt and signed by GrapheneOS** — its certificate is `CN=GrapheneOS`, *not* our platform certificate. Choosing system WebView therefore means **the shell trusts an engine whose signature we do not own**, and every agent-generated screen renders through it. That is an accepted-in-principle position, not a solved one: **OQ-1 must be explicitly accepted by the Captain.** The claim in rev 1 that this adds "no added trust burden of our own" is withdrawn as overstated; the accurate statement is *"no new engine-forking burden, but the engine's trust anchor is GrapheneOS's and that is a trust assumption we are accepting."*

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
| **`PhosphorBroker`** | privileged platform component (hosting shape = **OQ-4, open**) | UID `AID_PHOSPHOR_BROKER` *(provisional; fixed by OQ-4)*; domain `u:r:phosphor_broker:s0` | **Exactly the permission set enumerated in §3** — no more, no fewer. §3 is the single source; a list restated elsewhere is what let rev 1's errors propagate. | Trusted hands: sole Phosphor component touching telephony, SMS, contacts, notifications, settings, audio, sensors, location, camera/torch, Bluetooth, clipboard, vibrator; owns the pending-approval registry. |
| **`PhosphorShell`** | system app (HOME category, platform-signed) | UID `AID_PHOSPHOR_SHELL`; domain `u:r:phosphor_shell:s0` | **Exactly one capability permission: `RECORD_AUDIO`** (microphone is the shell's own capture surface, R-BRIDGE-3 "Microphone: live"), plus the socket **client** connect to agentd and binder calls to the broker. Nothing else. | Rendering + capture surface only; every capability request goes to the broker like any other client. |

**Why the split:** the agent daemon parses untrusted model output and quarantined web content; the broker touches `ITelephony` and the contacts provider. If a prompt injection ever wins a turn, it wins *unprivileged* hands; every consequential capability still crosses the broker's risk-classified gate. This is the R-GATE philosophy (`SPEC-001 §7.3` — a guard against model error, accepted as non-sandbox) expressed as **process separation**, which the iOS/Termux prototype never had.

**`[ADAPTED FROM SPEC-002 L2]`** — SPEC-002 wanted the bridge to *become* the hardware resource arbiter ("sole owner of modem/GPS/Bluetooth… clients request; bridge + policy decide"). On Android, `system_server` already is the arbiter; the **broker is Phosphor's arbiter-shaped delegate**: the sole Phosphor-side component that talks to telephony/contacts/settings/**Bluetooth**/camera, and every agent request for hardware crosses its classifier. The prototype's `bridge/src/handlers.rs` dispatch surface is the interface sketch — the right interface drawn against the wrong platform. (Bluetooth, vibrate, NFC, calendar and alarms are individually accounted for in §3; rev 1's "almost 1:1" claim is withdrawn — see MAJOR-8 resolution.)

### 2.2 Lifecycle

- `phosphor_keygate`: `class core`, `oneshot`, started `on late-init`; sets `sys.phosphor.safeboot` and exits (§6.5). No capability permissions; fail-closed.
- `phosphor_agentd`: `service phosphor_agentd /system/bin/phosphor-agentd` declared **`disabled`**, started only by `on property:sys.phosphor.safeboot=0` (§6.5) — never unconditionally at `class_start core`. `onrestart` re-exec; logd logging.
- **Crash-safe home:** the shell must render without a healthy agent. Agent death → shell shows "agent offline, retrying" and the mic still captures (buffered). A reboot into safe boot (§6.5) is the always-available escape — note it requires a reboot, so it is not a *same-session* remedy; the same-session remedy is the shell's offline state plus the fallback launcher reachable from it by an explicit user action.
- `PhosphorBroker`: starts on shell bind; survives agent death so pending approvals are not lost. Hosting shape = OQ-4.
- `PhosphorShell`: HOME activity lifecycle; transcript state is owned by agentd (or its SQLite store) and re-rendered on shell restart.

**`[ADAPTED FROM SPEC-002 L4]`** — SPEC-002's "Phosphor owns boot" (init starts the session, nothing else ever runs) becomes: **init starts the platform; the session's default UI is Phosphor, and Phosphor's own services are property-gated so a boot can deliberately start without them.** Android's init/zygote/system_server stay stock (they *are* the platform we derive from); what Phosphor owns is the *first surface* and the *escape path*. Owning PID 1 on Android would mean rewriting the platform, which the vision forbids ("modify and extend rather than rewriting").

---

## 3. Capability broker — full inventory (BUILD-PLAN deliverable)

Rev 1's provisional table was wrong in five rows (MAJOR-3..7) and incomplete (MAJOR-8). This is the inventory at API/permission level. **Risk classes are the closed enum defined in §6.3** — `SAFE`, `DESTRUCTIVE`, `DESTRUCTIVE-READ`. No other class name is used anywhere in this document (audit MAJOR-7).

**Protection levels below are quoted from the in-tree citations in `docs/P4-ARCH-AUDIT.md`.** Items marked `[TO VERIFY IN TREE]` are lower-confidence and are a Phase 5 pre-build task, not an assumption to build on.

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
| `wifi.status` / `wifi.list` | `WifiManager.getConnectionInfo()` / `getScanResults()` (scan via `startScan()`) | `ACCESS_FINE_LOCATION` — `dangerous`; `NEARBY_WIFI_DEVICES` — `[TO VERIFY IN TREE]` | broker | `SAFE` | — |
| `wifi.toggle` | `WifiManager.setWifiEnabled()` — **`@Deprecated`; for Q+ targets always fails and returns false unless DO/PO/system app** | same as above | broker | `DESTRUCTIVE` | **requires the broker to actually be a system app** — a constraint that independently supports OQ-4's standalone-platform-app option (audit MINOR-6) |
| `airplane.toggle` | `ConnectivityManager.setAirplaneMode(boolean)` — `@SystemApi` | `NETWORK_AIRPLANE_MODE` — **`signature`** | broker | `DESTRUCTIVE` | — |
| `brightness` | `Settings.System.putInt(SCREEN_BRIGHTNESS)` | `WRITE_SETTINGS` — **`signature\|preinstalled\|appop\|pre23\|role`** (this is **not** `WRITE_SECURE_SETTINGS`) | broker | `SAFE` — **explicit carve-out** in §6.3 (reconciling rev 1's self-contradiction) | — |
| `screen.idle` / `screen.wake` | `PowerManager.goToSleep(long,int,int)` / `wakeUp()` | `DEVICE_POWER` — **`signature\|role`** (rev 1's "`WindowManager` attrs" was wrong) | broker | `SAFE` — explicit carve-out (a screen nap is recoverable and non-consequential) | — |
| *(generic secure-settings write, not a prototype method)* | `Settings.Global` / `Settings.Secure` put | `WRITE_SECURE_SETTINGS` — `signature\|privileged\|development\|role\|installer` | broker | `DESTRUCTIVE` **unless the key is on the policy file's allowlist** | allowlist of writable keys in the policy artifact |
| `tts.speak` | `TextToSpeech.speak(...)` | none (engine binding) | broker | `SAFE` | — |
| `audio.route` *(generalises prototype absence)* | `AudioManager.setMode` / `setSpeakerphoneOn` | `MODIFY_AUDIO_SETTINGS` — `normal`; some routing modes `MODIFY_AUDIO_ROUTING` — `[TO VERIFY IN TREE]` | broker | `SAFE` outside a call; `DESTRUCTIVE` during an active call | — |
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
| **NFC** reader / HCE — **`[DEFERRED]` Phase 10** | `NfcAdapter.enableReaderMode` / HCE service | `NFC` — `normal` `[TO VERIFY IN TREE]`; HCE `BIND_NFC_SERVICE` — `signature\|privileged` | broker | would be `DESTRUCTIVE` (tag reads can carry untrusted content; writes are consequential) | deferred per §0 drop list — vision item 3 names NFC; SPEC-002 L2 names the hardware-arbiter set |
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
3. **Model inference** — agentd → model provider over the network (vision-consistent: STT local-or-remote "depending on the selected implementation"; inference remote for the foreseeable future). Credential anchoring = **OQ-2**.
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

**Host process = OQ-3, genuinely open.** Recommendation (not a decision): **broker-hosted**, because that is what makes the card render with the shell dead; the cost is that the broker must be able to show UI, which constrains its hosting shape (OQ-4). This document does not settle it, and §8's diagram draws it as a shared annotation, not inside either process box.

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
| `/data/misc/keystore/**` | Keystore blobs (OQ-2's wrapping keys) |
| `/data/misc/phosphor/credentials/**` | agentd's provider credential store (OQ-2) |
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
- **`phosphor-keygate` — the single decision point, evaluated before anything else of ours runs.** A tiny `class core`, `oneshot` init service with no capability permissions: it reads (i) `ro.boot.phosphor.safeboot` and (ii) the hardware key chord, and additionally honours (iii) `persist.phosphor.safeboot` **as a set-only latch — it can request safe boot, never cancel it** (transitions `absent→1` only; a `persist` value of `0` is ignored, and the sepolicy `neverallow` is on the reverse direction). This keeps the mechanism strictly one-way: the property can withhold the agent, and nothing on the device can clear a safe boot the host asked for. It then either sets `sys.phosphor.safeboot=0` and starts the agent, or sets `sys.phosphor.safeboot=1` and starts nothing. **Fail-closed default: if keygate does not run or cannot decide, safe boot is the assumption and the agent stays down.**
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
- **Plain surface — same polarity as the agent, i.e. fail-closed.** `PhosphorShell`'s HOME activity reads `sys.phosphor.safeboot` in `onCreate` and hands off to the **stock launcher by explicit component** and finishes itself **unless the property definitively reads `0`**. It is *not* "hand off when set": an absent property, a value the app layer cannot see, or any unparseable value **all** mean hand-off. This mirrors agentd's own start condition exactly (`on property:…=0`, so absent ⇒ never start), which is the point — the two halves of one mechanism must not be written with opposite polarity, or a property the app layer cannot read silently produces launcher-less Phosphor UI with no agent, the *opposite* of REC-2's plain surface. The HOME role is not *reassigned* (which PackageManager safe mode cannot do); the shell **declines to be the surface**. Result: launcher + Settings + no agent — REC-2's "plain shell + minimal network". The app-layer visibility of `sys.phosphor.safeboot` is recorded as verification debt in §10.2.
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
│  │ AID_PHOSPHOR_BROKER (provisional — OQ-4 open)        │  │ AID_PHOSPHOR_SHELL                │ │
│  │ u:r:phosphor_broker:s0                                │  │ u:r:phosphor_shell:s0             │ │
│  │ • AIDL services: Tel · Sms · Contacts · Notif ·       │  │ • fullscreen WebView (Vanadium     │ │
│  │   Settings · Audio · Sensor · Location · Camera ·     │  │   WebView engine — signature is    │ │
│  │   App · Bluetooth · Clipboard · Torch · Vibrator      │  │   GrapheneOS's, see OQ-1)          │ │
│  │ • holds §3's permission set (the one source)           │  │ • §4.1 Layer 2: blockNetworkLoads, │ │
│  │   shell holds RECORD_AUDIO only, nothing else         │  │   shouldInterceptRequest allow-list,│ │
│  │ • pending-approval registry (single-use, 5-min TTL)   │  │   injected CSP                     │ │
│  │ • re-checks classification against the SAME policy    │  │ • exposes ONLY `phosphorApi` via   │ │
│  │   artifact; fails closed on version mismatch          │  │   addJavascriptInterface (proxy)   │ │
│  │ • consumes notification-listener overlay entry        │  │ • holds exactly one capability     │ │
│  └───────────────────────────────────────────────────────┘  │   permission: RECORD_AUDIO         │ │
│              ▲                                              │ • safe-boot: starts stock launcher │ │
│              │ binder AIDL (phosphorApi RPCs)              │   by component and finishes (§6.5) │ │
│              └──────────────────────────────────────────────┤ • no binder server; socket client │ │
│                                                             └────────────────────────────────────┘ │
│  ┌─ [OQ-3 — OPEN] native approval dialog ───────────────────────────────────────────────────────┐ │
│  │  Content comes from the broker's registry in ALL cases (never page scope).                    │ │
│  │  Host = broker (recommended: renders with shell dead) OR shell (normal dialog machinery,      │ │
│  │  dies with shell). NOT DECIDED HERE. Phase 5 manifest/UI work depends on it.                  │ │
│  └──────────────────────────────────────────────────────────────────────────────────────────────┘ │
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
│    persist value of 0 cannot cancel a host-requested safe boot) into sys.phosphor.safeboot.        │
│    =1 (or absent/unreadable) ⇒ init never starts phosphor_agentd; broker not auto-started;         │
│    shell hands off to the stock launcher by explicit component UNLESS the property is             │
│    definitively 0 — fail-closed on both halves. Result: launcher + Settings, no agent.             │
│  RECOVERY (REC-1): fastboot ladder, host+cable, wipes userdata — data gap = Phase 11.             │
└────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Reconciliation notes (audit MAJOR-9 — map now agrees with §2.1/§5/§6.2):**
1. The approval dialog is drawn **outside** both process boxes as an explicitly open OQ-3 annotation. §6.2 keeps it open; the diagram no longer pre-decides shell-hosting.
2. The shell's permission line says **`RECORD_AUDIO` only**, matching §5 step 1, instead of claiming it holds no capability permissions.
3. `phosphor_agentd` has **no binder permission to the shell**. Shell↔agentd is a `AF_UNIX` `SOCK_SEQPACKET` channel that the *shell* connects to, with agentd verifying `SO_PEERCRED` and the group/label. This removes rev 1's contradictory "neverallow … except to broker + shell".
4. The shell↔agentd mechanism is **chosen, not left as "binder AIDL / local socket"**: a Unix socketpair, because a Rust daemon would otherwise have to implement the binder wire protocol or be fronted by a Java service, and because it gives length-framed messages with credential checks. Its trust properties are stated: the channel carries the turn and the render payload, is **outside** the broker's classifier, and is the reason §4.1 exists.

**SELinux requirements (Phase 5 deliverables).** Written to be compile-ready, because a rule that cannot be expressed invites a Phase 5 author to drop it and silently lose the guarantee:

- `neverallow phosphor_agentd` any capability-adjacent device node (telephony, camera, location, netlink for radios).
- `neverallow phosphor_agentd { phosphor_broker }:binder call` — the *only* permitted binder target; nothing to the shell.
- `neverallow phosphor_shell` binder to capability services directly (broker or nothing).
- **The policy artifact gets a type.** It is a **JSON document** (`risk-policy.json`), stored as type **`phosphor_risk_policy_file`**; `neverallow { phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate } phosphor_risk_policy_file:file { write append create rename setattr unlink };` — read is deliberately allowed for agentd and broker (§6.3) and absent for shell, so this rule states the write ban against its named type rather than a vague "any Phosphor domain".
- **`phosphor_keygate`'s file access, stated as the permission checks it actually is** (NEW-3 — "touching the agent's binary" is not a SELinux predicate, so it is enumerated): `neverallow phosphor_keygate phosphor_agentd_exec:file *;` and `neverallow phosphor_keygate phosphor_agentd_data_file:file *;` — covering `execute`, `execute_no_trans`, `entrypoint`, `read`, `map`/`mmap_exec_file_perms`, `write`, `create`, `unlink`, `setattr` by denying the whole operation set on those two types.
- **`phosphor_keygate`'s property access, as a subtraction** (the form used in-tree against `powerctl_prop`): `neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;` — plus `neverallow phosphor_keygate system_prop:property_service set;` is *not* written, since the subtraction form is the precise one. `phosphor_safeboot_prop` is declared `exact bool` (AOSP already ships this shape for `sys.boot_completed`).
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

## 9. Open questions for the Captain (real architectural forks)

*Phase-5-gating:* **OQ-1, OQ-2, OQ-3, OQ-4** (audit MINOR-8 — OQ-5/6/7 do not gate Phase 5 and are listed for completeness).

1. **OQ-1 — Vanadium's signature (gates §1.1, §4).** The rendering engine is GrapheneOS-signed, not ours (SPEC-001 §14.2). Options: (a) ride GrapheneOS-signed Vanadium — fast, works, engine stays under *their* trust anchor, and our trust requirement sits on the shell app; (b) build Chromium from source under our keys — owns the signature, large recurring cost, against "modify and extend, don't rewrite". **Recommend (a) for Phases 4–9, revisit before Phase 12.** *This asks the Captain to explicitly accept that the shell trusts an engine we do not sign.* Biggest fork in the platform.
2. **OQ-2 — Agent-service credential trust anchor (gates §5, §6.4).** Where the model-provider credentials live and what binds them to agentd: Keystore-wrapped (hardware-backed, StrongBox-capable on the 8a) config vs plain `/data` config in agentd's private dir. Given the unlocked bootloader, hardware backing is only worth what an unlocked device guarantees — recommend **Keystore-wrapped + per-flash provisioning**, and record that on-device secret-at-rest is *best-effort* until relock.
3. **OQ-3 — Approval-card host process (gates Phase 5 UI/manifest work).** Broker-hosted (highest assurance: renders with shell dead; forces broker to show UI, constraining OQ-4) vs shell-hosted (normal dialog machinery; dies with the shell). Recommend **broker-hosted**. Left genuinely open here; §8 draws it as an annotation.
4. **OQ-4 — Broker hosting shape (gates Phase 5 manifest/sepolicy).** Standalone platform-signed app + signature permissions vs `system_server` injection vs a hybrid. Recommend **standalone platform-signed app**, with escalation only if a capability demands it. Note MINOR-6's constraint: `wifi.toggle` requires a system app, which argues for this option.
5. **OQ-5 — Relock timing (Phase 12 gate, not Phase 5).** The design works better relocked (verified boot under our key, meaningful StrongBox anchoring) but relock wipes and bricks-on-bad-build. Recommend Phase 12.
6. **OQ-6 — STT engine (decide Phase 7).** whisper.cpp (proven, fully local, models on-device) vs `SpeechRecognizer` on-device recognizer (platform-integrated, less control). Both behind one interface; model packaging is a build-design decision.
7. **OQ-7 — GMS compatibility retention (decide Phase 9).** Nothing in this architecture depends on it either way; recommend drop-by-default.
8. **OQ-8 — Residual SPEC-002 L1 (§6.6).** Recommend declaring L1 satisfied-by-platform; needs sign-off because it retires a SPEC-002 level.

---

## 10. BUILD-PLAN Phase 4 deliverables — status

| Deliverable | Status in this rev | Where |
|---|---|---|
| System architecture document | **delivered** (rev 2, post-audit) | §0–§7 |
| Component and process map | **delivered**, reconciled with §2/§5/§6 | §8 |
| Capability/API inventory | **delivered** at API + permission + protection-level + risk-class + build-deliverable granularity; **hosting-independent**, so OQ-3/OQ-4 do not block it | §3 |
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
| `NEARBY_WIFI_DEVICES`, `MODIFY_AUDIO_ROUTING`, `NFC` protection levels marked `[TO VERIFY IN TREE]` in §3 | not verified | Phase 5 pre-build: read `frameworks/base/core/res/AndroidManifest.xml` for each |
| `bt.connect` profile-specific API choice (A2DP/HFP/…) | not chosen | Phase 5 |
| `tel.hangup` full coverage path (privileged vs Telecom `ConnectionService`) | not decided | Phase 5 |
| `phosphor-keygate` hardware-key chord semantics (which chord; how read without a live framework) | not decided | Phase 5, §6.5 |
| Approval-card host (OQ-3) and broker hosting shape (OQ-4) | **open — Captain** | gates Phase 5 manifest/sepolicy |
| Engine trust acceptance (OQ-1) and credential anchor (OQ-2) | **open — Captain** | gates §1.1/§4 and §5/§6.4 |
| Phase 5 acceptance tests named in this doc (§4.1 H1 re-run; §3 hard-restricted grant landing; R-PERF microbench) | specified, not yet run | Phase 5 exit |

None of these blocks the architecture; each blocks one specific Phase 5 step, and each is named at the step it blocks.

**Exit-criterion assessment.** The major boundaries, implementation locations and trust assignments are specified well enough to begin Phase 5 without guessing — **with four named dependencies**: OQ-1 (engine trust acceptance), OQ-2 (credential anchor), OQ-3 (card host), OQ-4 (broker hosting). Phase 4 is **conditionally closed** on those four decisions; the previously circular deferral of the inventory and diagrams is removed (both delivered above). If the Captain prefers to close Phase 4 unconditionally, that re-scoping is a Captain decision and must be recorded as one — this document does not claim it.

---

## 11. Finding-resolution appendix (`docs/P4-ARCH-AUDIT.md`)

| # | Finding | Resolution in rev 2 |
|---|---|---|
| **BLOCKER-1** | REC-2 safe mode cannot work (PackageManager gates APK components only; system-image apps unaffected) | **Redesigned in §6.5**: a dedicated `phosphor-keygate` `oneshot` init service folds three trigger sources (`ro.boot.phosphor.safeboot` host-set/immutable, hardware key chord, `persist.phosphor.safeboot`) into one `sys.phosphor.safeboot` decision, **fail-closed to safe boot if undecided**; `phosphor_agentd` is `disabled` and started only on `sys.phosphor.safeboot=0`; the broker is not auto-started (capabilities fail closed); `PhosphorShell`'s HOME activity declines and hands off to the stock launcher by explicit component. Marked `[ADAPTED FROM SPEC-002 REC-2]` with its residual gap (hardware-key chord is a Phase 5 deliverable; until then host+cable triggers it). §2.2 and §8's map now show keygate as a real process. |
| **MAJOR-1** | Classifier specified three incompatible ways | **§6.3 rewritten**: agentd is the *single authoritative* classifier; broker re-checks against the **same read-only artifact** (`/system/etc/phosphor/risk-policy.json`, version+hash, unwritable by any Phosphor domain); fail-closed disagreement order stated (either-side-DESTRUCTIVE wins; broker authoritative at execution; policy-version mismatch ⇒ deny). §2.1/§4/§5/§8 all now say the same thing. |
| **MAJOR-2** | R-GATE-1 and R-GATE-4 never cited; R-SEC-3 mapped to a non-existent `.env` | **R-GATE-1 cited in §5 step 4 and §6.3; R-GATE-4 cited in §5 step 4 and §6.3.** R-SEC-3 **translated in new §6.4** with the real Android secret-path table plus the two enforcement layers (SELinux `neverallow` + classifier `secret-path` patterns). |
| **MAJOR-3** | `SmsManager.sendMessage` invented | **§3 corrected** to `sendTextMessage(destAddr, scAddr, text, sentIntent, deliveryIntent, persistMessage)` / `sendMultipartTextMessage(...)`. |
| **MAJOR-4** | SMS/contacts privilege levels wrong; `hardRestricted` missed | **§3**: `SEND_SMS`/`READ_SMS` = `dangerous` + `hardRestricted`; explicit **hard-restricted allowlist entry in our tree** as a build deliverable with the silent-failure warning; privilege column reads `dangerous \| hardRestricted → broker + allowlist`. |
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

---
*End of Phase 4 system architecture, rev 2. Design only — no code, builds, or device operations were performed. No file other than this document was created or modified.*
