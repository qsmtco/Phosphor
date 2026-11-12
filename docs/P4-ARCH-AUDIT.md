# P4 Architecture Audit — `docs/PHASE-4-PLATFORM-ARCHITECTURE.md`

**Verdict: FIX FIRST** — *(this section audits rev 1; verdict history: rev 1 FIX FIRST, rev 2 FIX FIRST — narrow, **rev 3 ACCEPT**. See "Final narrow re-audit — rev 3" at the end of this file, which is the operative verdict.)*
**Auditor:** Debugger (develcakes), 2026-11-10, at Supervisor's Phase 4 acceptance gate
**Artifact audited:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` (34428 bytes, 271 lines, untracked, author Coder)
**Authority chain used:** `docs/PHOSPHOR-VISION.md` (wins on conflict) → `docs/PHOS-SPEC-001-trust-architecture.md` → `docs/PHOS-SPEC-002-system-integration.md` (base-OS choice superseded by SPEC-001 §14.4 / PM ruling 2026-11-10; L0–L4 + REC-1..5 staging model carries) → `docs/PHOSPHOR-BUILD-PLAN.md` §Phase 4 → `docs/PROJECT-STATUS.md` §2, §10, §14.

**Scope of this audit:** design document only. No code, build, or device operation was performed or is implied (verified: audited doc §"Scope" line 8, closing line 271; `git status` shows only the new untracked doc — no source or device artifacts touched).

**Method note (material to how findings were graded):** `web_search` is unavailable on `qoder` (`BRAVE_API_KEY` unset), so every Android API and permission claim below was verified **against the actual source tree** at `~/projects/grapheneos-2026091900` rather than from memory. File:line citations in the findings refer to that tree unless stated otherwise. Claims I could not settle in-tree are labelled `[UNVERIFIED]` and were not graded as defects.

---

## Verdict rationale

**FIX FIRST**, not ACCEPT and not REJECT.

- **Not ACCEPT:** one SPEC-002 MUST (REC-2) is answered with a mechanism that provably does not work (BLOCKER-1); the capability broker's privilege map contains an invented API, two wrong protection levels, two omitted signature permissions, and one undefined risk class; and the classifier — the security core of the whole design — is described in three mutually inconsistent places. A capability inventory with wrong privilege levels is not "understood well enough to begin native platform work without guessing" (BUILD-PLAN Phase 4 exit criterion line 261).
- **Not REJECT:** the architecture *shape* is correct and vision-aligned. Shell-as-system-HOME-app, three-process trust split with an unprivileged brain and a privileged broker, native approval card outside page scope, and init-supervised agentd all follow the vision and SPEC-001 without redirecting into an app/chatbot/browser-shell shape. The defects are in the detail layer and are all repairable in place.

Counts: **1 BLOCKER, 11 MAJOR, 8 MINOR, 6 NOTE.**

---

## BLOCKER

### BLOCKER-1 — REC-2 (safe mode) is answered with a mechanism that cannot satisfy it, on two independent grounds
**Audited doc:** §6.5 line 172; §7 line 184; §8 map line 223; §1.2 line 49.
**Violates:** SPEC-002 §5 REC-2 (MUST): *"Safe-mode boot path — a boot option that starts a plain shell + minimal network, skipping the agent, reachable without the agent's cooperation."* No marked decision drops it; line 172 claims to satisfy it.

The doc's answer is: *"the fallback launcher serves as the skip-the-agent surface — a boot into stock launcher + Settings without PhosphorShell default is achievable via safe boot (or `pm disable` over adb in dev). The requirement 'reachable without the agent's cooperation' is satisfied because disabling the HOME default never requires the agent to be healthy."*

This fails twice, verifiably:

1. **Android safe mode cannot stop `phosphor-agentd` at all.** Safe mode is a *PackageManager* concept — it gates APK components. The audited doc's own §2.1 (line 65) defines agentd as *"native daemon, declared in the device tree, started by `init` from a `.rc`"*, and §8 (line 197) draws it as `init ─▶ phosphor-agentd`. An init-supervised native binary has no package and no component; `PackageManagerService`'s safe-mode flag never sees it. Safe boot therefore does not skip the agent — the specific thing REC-2 demands.
2. **Safe mode does not disable system-image apps, which PhosphorShell must be.** `ComputerEngine.java:3684`:
   ```java
   if (safeMode && !ps.isSystem()) {
       return PackageManagerService.PACKAGE_STARTABILITY_NOT_SYSTEM;
   }
   ```
   and `PackageSetting.java:845-846`:
   ```java
   public boolean isSystem() {
       return (getFlags() & ApplicationInfo.FLAG_SYSTEM) != 0;
   }
   ```
   Safe mode disables only *non-system* apps. §1 line 27 and §1.1 line 33 require PhosphorShell to be a *"platform-signed, launcher-category system app"* inside the system image — i.e. `FLAG_SYSTEM` set. So PhosphorShell remains startable **and remains the resolved HOME** in safe mode. The stated fallback ("boot into stock launcher … without PhosphorShell default") does not occur: both are system apps, and the HOME role/default is unaffected by safe mode.

**Consequence:** a MUST-level recovery requirement has no working mechanism, and the doc presents it as satisfied. The "OS vs demo" line SPEC-002 §5 draws is exactly this requirement. `pm disable … over adb` (also offered, line 172) depends on a working adb host connection and a booted, cooperative device — it is *not* a boot option, and it is not "reachable without the agent's cooperation" in the boot-path sense REC-2 asks for.

**Fix direction (not prescriptive — architecture choice belongs to the Supervisor/Captain):** the answer must be a real boot-time switch that (a) prevents the HOME/default resolution pointing at PhosphorShell, and (b) prevents agentd from being started or held down — e.g. an `init` property/`androidboot.*` or kernel-cmdline-derived property consumed by agentd's `.rc` (`disabled` + `start` conditioned on a property) plus a distinct HOME-role holder selected by a build-time `overlay`/role-defaults entry, or a second explicitly-chosen launcher as default-on-safe-boot. Whatever the choice, REC-2 must be marked with its own `[ADAPTED FROM SPEC-002 REC-2]` line stating the mechanism *and* its residual gap, as REC-1's line 172 already honestly does for the backup gap.

---

## MAJOR

### MAJOR-1 — The risk classifier is specified three incompatible ways; R-GATE-4's "single deterministic classifier" is lost
**Audited doc:** §2.1 line 65, §4 line 124, §6.3 line 158, §8 map line 219.
**Violates:** SPEC-001 R-GATE-4 (MUST: classification uses a deterministic pattern list evaluated in code, not model judgment) and §7.1 (two classes).

- §2.1 line 65: agentd holds *"**quarantine**, **gating**, **redaction**"*.
- §4 line 124: *"classification and approval live in the broker"*.
- §6.3 line 158: *"ported to agentd/broker as the single classifier"* — a single classifier in two processes is not a single classifier.
- §8 line 219: agentd → broker tool calls are *"gated by broker-side re-classify"* — implying agentd classified once and the broker classifies again.

Two classifiers with independent policy files diverge, and under a fail-closed design the *weaker* instance wins the race to execute. R-GATE-4 is never cited in the document (see MAJOR-2). The doc must name exactly one authoritative classifier location, state whether the other path is a defence-in-depth re-check against a *shared* pattern artifact (and how shared — a single read-only file both domains can read, version-pinned), and make the fail-closed order explicit for the case where the two disagree.

### MAJOR-2 — Silent gaps: R-GATE-1 and R-GATE-4 never appear; R-SEC-3 has no Android location
**Audited doc:** §4 table lines 115-122, §3 line 90, §6.3 line 158.
**Violates:** audit criterion 1 — every SPEC-001 MUST must have a concrete implementation location *or* be explicitly marked unplaced.

Verified by enumeration (`grep -o "R-GATE-[0-9]"`): the document cites **R-GATE-2, 3, 5, 6, 7, 8** and never **R-GATE-1** (MUST: every tool invocation classified before execution) or **R-GATE-4** (MUST: deterministic, in-code pattern list). Both MUSTs are arguably satisfied in intent by §6.3/§5 step 4 — but "arguably" is what the exit criterion forbids, and R-GATE-4 is precisely the requirement MAJOR-1 shows being violated. Neither is in the silent-gap list.

**R-SEC-3** (MUST) is worse: line 117 restates it as *"`.env`-class reads gated"*. `R-SEC-3`'s actual content is a defined path set — `{server .env, .env.*, *.pem, *.p12, *.p8, *.key, id_rsa*, .git-credentials}` classified DESTRUCTIVE-READ by §7.2/D12. **There is no `.env` on an Android device**, and the doc never enumerates the Android equivalent (Keystore blobs under `/data/misc/keystore`, the OQ-2 provider-credential file, `avb.pem`-class material if ever staged, the agentd private dir). The single most secret-bearing requirement in SPEC-001 is mapped to a filename that will not exist. It needs its own translation with the actual Android secret path set.

### MAJOR-3 — `SmsManager.sendMessage` does not exist (invented API)
**Audited doc:** §3 line 90 (`sms.send` → *"`SmsManager.sendMessage`"*).
**Violates:** audit criterion 4.

Verified in `frameworks/base/telephony/java/android/telephony/SmsManager.java`: the class exposes `sendTextMessage` (lines 613, 635, 748), `sendMultipartTextMessage` (1218, 1237, 1267, 1503), and `sendTextMessageWithoutPersisting` (850). There is **no `sendMessage`**. The real method also now requires a `persistMessage`/`PendingIntent`-style signature (`sendTextMessage` is `@Deprecated` in favour of the multi-arg form in recent AOSP), so the inventory should cite the current signature, not a remembered one.

### MAJOR-4 — SMS and contacts privilege levels are wrong; the actual gate (`hardRestricted`) is missed
**Audited doc:** §3 line 90 (*"`READ_SMS` (signature-permission per AOSP policy)"*), line 90 privilege column (*"signature → broker"*).
**Violates:** audit criterion 4 (wrong privilege level), and it makes the design's central claim — "broker holds the permissions, agentd holds none" — under-specified as to *how* the broker gets them.

Verified in `frameworks/base/core/res/AndroidManifest.xml`:
- `READ_SMS` (line 1072-1077): `protectionLevel="dangerous"`, `permissionFlags="hardRestricted|allowedInPrivateComputeCore"`.
- `SEND_SMS` (line 1044-1049): `protectionLevel="dangerous"`, `permissionFlags="costsMoney|hardRestricted"`.
- `READ_CONTACTS` (line 907-912): `protectionLevel="dangerous"`. (The doc is right that this is runtime; it is wrong to imply the SMS family is signature.)

`READ_SMS`/`SEND_SMS` are **not** signature permissions — they are `dangerous` **and** `hardRestricted`. `hardRestricted` is the real constraint: such a permission cannot be granted unless the app is on a hard-restricted allowlist (`Permission.isHardRestricted()`, `Permission.java:234-235`; `PermissionManagerServiceImpl` consults it at install/grant time). This is a *build-system deliverable* — a privapp-permissions / role-defaults / allowlist entry — and the design needs to say where it lives, because it is the difference between the broker working and `sendSms` silently failing at runtime. The doc's privilege column should read `dangerous | hardRestricted → broker, requires allowlist entry in our tree`.

### MAJOR-5 — Telephony privilege claims are wrong in both directions, and `tel.status`'s permission is missing
**Audited doc:** §3 line 89 (*"answering/hanging up needs `MODIFY_PHONE_STATE` (signature) or Telecom `ConnectionService` participation"*; privilege column *"signature | privileged → **broker only**"*).
**Violates:** audit criterion 4.

Verified in `frameworks/base/telecomm/framework/java/android/telecom/TelecomManager.java` and `AndroidManifest.xml`:
- `placeCall()` (line 2748-2750): `@RequiresPermission(anyOf = {CALL_PHONE, …})`; `CALL_PHONE` is **`dangerous`** with `costsMoney` (`AndroidManifest.xml:1667-1672`). Not signature.
- `acceptRingingCall()` (2321-2324): `@RequiresPermission(anyOf = {ANSWER_PHONE_CALLS, MODIFY_PHONE_STATE})`; `ANSWER_PHONE_CALLS` is **`dangerous|runtime`** (`AndroidManifest.xml:1695-1699`). The doc omits it entirely and names only `MODIFY_PHONE_STATE`.
- `endCall()` (2293-2294): `@RequiresPermission(ANSWER_PHONE_CALLS)` **only** — `MODIFY_PHONE_STATE` will not do. Also `@Deprecated`, and it will not end emergency or (without privileged caller) self-managed/transactional calls (javadoc 2274-2290) — a real behavioural constraint for an agent that says "hang up".
- `getCallState()` (`tel.status`) (2235-2237): `@RequiresPermission(anyOf = {READ_PRIVILEGED_PHONE_STATE, READ_PHONE_STATE})`, `@SystemApi`, `@hide`. The doc lists `tel.status` with no privilege note at all.

Net effect: the row claims a *higher* minimum privilege than reality for dial/answer (`dangerous` suffices) while *understating* what `tel.status` needs, and it never notes that `endCall()` is deprecated and conditionally refuses. The privilege map is the artifact Phase 5 will build the manifest and sepolicy from; wrong here means wrong everywhere downstream.

**Corroborated in §8:** the process map's broker line (line 212) lists the broker's held permissions as *"MODIFY_PHONE_STATE, READ_SMS/SEND_SMS, READ_CONTACTS, FINE_LOCATION, CAMERA, WRITE_SECURE_SETTINGS, notification-listener binding"* — `CALL_PHONE`, `ANSWER_PHONE_CALLS` and `READ_PHONE_STATE` are absent from the map too. The error is not a single table cell; it propagates into the process map that Phase 5 will implement from.

### MAJOR-6 — Settings row: wrong permission for brightness, missing `DEVICE_POWER`, and a self-contradiction on classification
**Audited doc:** §3 line 93 (*"`Settings.Global/Secure/System` via `android.permission.WRITE_SECURE_SETTINGS`, `WindowManager` attrs for idle, brightness sysprop/hardware"*; consent *"brightness/idle = SAFE"*) vs §6.3 line 161 (*"system-config writes are DESTRUCTIVE until a policy file entry says otherwise"*).
**Violates:** audit criterion 4 + criterion 3 (internal consistency).

Verified:
- `Settings.System` writes (brightness included) require **`WRITE_SETTINGS`**, `protectionLevel="signature|preinstalled|appop|pre23|role"` (`AndroidManifest.xml:5428-5431`) — **not** `WRITE_SECURE_SETTINGS`. The doc conflates `Settings.System`/`Secure`/`Global` under one permission; they are three different gates (`WRITE_SECURE_SETTINGS` is `signature|privileged|development|role|installer`, line 5809-5810, and covers Secure/Global only).
- Screen idle/wake is **`PowerManager.goToSleep(long,int,int)`**, `@RequiresPermission(DEVICE_POWER)` (`PowerManager.java:1678-1681`), with `DEVICE_POWER` = `signature|role` (`AndroidManifest.xml:7723-7725`). *"`WindowManager` attrs for idle"* is not the mechanism and `DEVICE_POWER` never appears in the doc — an omitted signature permission the broker will need.
- Classification contradiction: line 93 says brightness/idle are **SAFE**; line 161 says system-config writes are **DESTRUCTIVE** by default. Both cannot hold. (Brightness *is* arguably SAFE — but then line 161 needs an explicit carve-out, or the doc has quietly decided REC-4 differently in two places.)
- **Corroborated in §8:** the broker's held-permission line (212) lists only `WRITE_SECURE_SETTINGS` — neither `WRITE_SETTINGS` nor `DEVICE_POWER` appears anywhere in the document, though both are required by the methods the §3 row assigns to the broker.

### MAJOR-7 — Undefined risk classes used as if normative ("system-tool class", "DESTRUCTIVE-READ")
**Audited doc:** §3 lines 90, 92, 93, 99; §6.3 line 161.
**Violates:** SPEC-001 §7.1 (class table defines exactly SAFE and DESTRUCTIVE); SPEC-002 REC-4 (extend with SYSTEM tool classes — same fail-closed engine).

Line 93 assigns toggling radios to a *"**system-tool class** (§6.3)"*. §6.3 never defines such a class — it describes new *patterns* in the existing engine. §3 also uses **DESTRUCTIVE-READ** (lines 90, 92, 99) as a class. SPEC-001 §7.1 lists only SAFE and DESTRUCTIVE; "DESTRUCTIVE-READ" appears in SPEC-001 only informally at line 190 and in §7.2/D12's rationale. So the capability inventory's consent column is populated with at least one class name that exists nowhere, and one that exists only by informal usage.

This matters operationally: Phase 5's classifier JSON must have a closed enum, and an inventory built on undefined class names cannot be turned into a pattern file without re-deciding every row. §6.3 must publish the actual class enum (SAFE / DESTRUCTIVE / DESTRUCTIVE-READ / SYSTEM-tool or whatever is chosen) and §3 must use only those names.

### MAJOR-8 — "27-method surface maps almost 1:1" is false; Bluetooth, vibrate and NFC are dropped without a marked decision
**Audited doc:** §2.1 line 71; §3 table lines 87-101; §8 migration table line 236.
**Violates:** SPEC-002 L2 adaptation completeness (the marked L2 line says the broker is *"the sole Phosphor-side component that talks to telephony/contacts/settings"* — silently dropping Bluetooth from an L2 translation that names it explicitly), and the vision's §Intended architecture item 3 (*"Sensors, vibration, flashlight, NFC, clipboard, and other hardware"*).

Verified by enumerating `bridge/src/handlers.rs` dispatch arms (exactly **27**): `tel.{dial,hangup,answer,status}`, `sms.{send,inbox}`, `geo.{get,watch,unwatch}`, `wifi.{status,list}`, **`bt.list`, `bt.connect`**, `sensor.read`, `battery`, `clip.{read,write}`, `notif.{set,cancel}`, **`vibrate`**, `flashlight`, `camera.snapshot`, `screen.{idle,wake}`, `brightness`, `app.open`, `app.share`, `tts.speak`, `web.fetch`, `kv.{get,set}`.

The §3 broker inventory contains **no Bluetooth row at all** (SPEC-002 §4 L2 explicitly names Bluetooth as an arbiter responsibility: *"sole owner of modem (ModemManager), GPS (geoclue), Bluetooth (bluez), camera"*), **no vibrate**, **no NFC** (vision line 81 names NFC and vibration explicitly), and **no calendar/alarms** (vision line 83: *"Calendar, alarms, and other user data where permitted"*). Meanwhile the doc *adds* `contacts.search`/`contacts.read` and `notif.listen` and claims the mapping is 1:1.

Three prototype methods are silently dropped, one SPEC-002-named arbiter domain is silently dropped, and four vision-listed hardware capabilities are absent. Each is defensible as "later phase" — but the document's own framing rule (§0 line 15) requires adaptations and drops to be *marked*, and this is a drop with no marker and a factually incorrect "almost 1:1" claim on top. Either add the rows (with Phase-N deferral notes) or add the drop to the recorded-concepts list at §0.

### MAJOR-9 — Process map contradicts the component sections on four points; OQ-3 is pre-decided inside §8
**Audited doc:** §2.1 lines 65-67, §2.2 line 76, §4 line 124, §5 step 1 line 134, §6.2 line 154, §8 map lines 203-228, §9 OQ-3 line 248.
**Violates:** audit criterion 3 (process map must match §1–§7 — same processes, same trust positions, same IPC paths) and criterion 5 (recommendations must not quietly decide open questions).

1. **OQ-3 is answered in the diagram.** OQ-3 (line 248) poses approval-card hosting as *open*, recommending **broker-hosted**. §6.2 line 154 keeps it open (*"hosted by the broker or shell process — **OQ-3**"*). But §8's process map draws **`native approval dialog UI (content from broker registry)` inside the `PhosphorShell` box** (line 207) — i.e. the diagram decides *shell-hosted*, the opposite of the doc's own recommendation, while §9 still presents it as undecided. A reader implementing from §8 gets the weaker design.
2. **The shell does and does not hold capability permissions.** §2.1 line 67: shell has *"No capability permissions of its own — it asks the broker like any client."* §5 step 1 line 134: *"mic is a runtime/foreground permission of the *shell*"*. `RECORD_AUDIO` **is** a capability permission. The trust-position statement is false as written.
3. **agentd → shell binder calls.** §2.1 line 65: agentd's powers are *"compute, network egress …, and binder calls *to* the broker"*. §8 sepolicy line 228: *"neverallow agentd binder calls except to broker **+ shell**"*. The sepolicy requirement grants a second privileged path the trust table denies — and the shell is the process holding the bridge to page JS.
4. **Shell ↔ agentd channel is unspecified and unanalysed.** §8 line 218 labels it *"binder AIDL / local socket"* — an undecided mechanism rendered as settled. This channel carries the turn (user text/audio in, screen HTML out) and is the path by which model output reaches the renderer. Given agentd is a native init-started daemon (line 65), an AIDL interface requires it to implement the binder wire protocol itself or be fronted by a Java service — the doc should say which. More importantly, this path is *outside* the broker's classification, so "every consequential capability crosses the broker's approval gate" (line 69) is true only for tool calls, not for the screen-render path. That asymmetry needs to be stated, because rendering is exactly where R-UI-1 (no script stripping) applies.

MINOR-1 also belongs to this cluster (UID naming) and is listed below.

### MAJOR-10 — The known HIGH defect from `docs/P4-AUDIT.md` H1 is silently not carried forward
**Audited doc:** §1.1 line 42, §4 line 115.
**Violates:** SPEC-001 R-UI-1/R-UI-3/R-UI-5 and the project's own audit trail; audit criterion 1 (silent gap).

The existing audit `docs/P4-AUDIT.md` H1 (lines 25-40) establishes a *live, unremediated* finding against the prototype shell: `setScreen()` in `ios-app/app-shell.html` **resurrects `<script src>` to arbitrary origins**, and WKWebView does not route subresource loads through the navigation allowlist, so a single model-emitted `<script src="https://evil.example/x.js">` executes attacker code with access to the native bridge. The Phase-4 document's §4 table (line 115) asserts R-UI-1..3 are satisfied by *"agentd emits `<ph-screen>` HTML verbatim … WebView executes it"* — which reproduces exactly the condition H1 exploits, in a WebView that has a *more* powerful bridge (`phosphorApi` → broker RPC → telephony/SMS/settings).

The doc's only gesture at this is line 42: *"CSP baseline forbids third-party CDN loads (R-UI-5)"* — but (a) R-UI-5 is a **SHOULD** about *system-prompt steering*, and it is silently upgraded to a technical control without a marker, and (b) a CSP baseline is not specified: no `script-src`/`connect-src` directive list, no statement of how a CSP is injected into agent-generated HTML without breaking R-UI-1/3 (`on*=` and inline `<script>` must keep working — so `script-src` must allow `'unsafe-inline'`, which does *not* by itself block remote `<script src>` unless a host allowlist is enumerated, and `'unsafe-inline'` + remote hosts is precisely the H1 path).

Required: a §4 subsection specifying the subresource policy (drop `src`-carrying scripts, or an explicit host allowlist), the exact CSP directives, and a statement that this closes P4-AUDIT H1 on the Android host. Carrying an open HIGH finding into a new platform without a decision is the single most consequential omission in the document after BLOCKER-1.

### MAJOR-11 — Two of six BUILD-PLAN Phase 4 deliverables are deferred behind the very open questions §3's inventory depends on
**Audited doc:** §10 table lines 259-268; §9 OQ-3/OQ-4.
**Violates:** BUILD-PLAN §Phase 4 deliverables (lines 252-257) and the exit criterion (line 261).

| Deliverable | Doc status (line) |
|---|---|
| System architecture document | this file — **delivered** |
| Component and process map | §8 — **delivered** (with MAJOR-9 defects) |
| Capability/API inventory | *"expand to full method-signature level after OQ-3/OQ-4"* (263) — **deferred** |
| Data-flow and trust-boundary diagrams | *"formalize (graphs) on request"* (264) — **deferred** |
| Policy model | §6.3, *"pattern-file schema draft"* outstanding (265) — **partial** |
| Prototype-to-native migration map | §8 table — **delivered** (with MAJOR-8 defects) |

Two deliverables are explicitly not delivered and a third is partial, while §268 nonetheless declares the exit criterion met *"pending the Captain's answers on OQ-1..OQ-8"*. The circularity is the problem: the full capability inventory is the artifact the exit criterion's "implementation locations understood without guessing" is measured *by*, and it cannot be written until OQ-3 (approval host) and OQ-4 (broker hosting) are settled. Phase 4 cannot close on this document alone; the acceptance should be conditional on the inventory landing, or the exit criterion should be re-scoped and that re-scoping marked as a Captain decision.

---

## MINOR

### MINOR-1 — Three names for one UID across §2.1 and §8
§2.1 line 65 gives agentd UID `AID_PHOSPHOR`; §8 line 198 gives `phosphor_agentd`. §2.1 line 66 gives broker `` `system` or dedicated AID ``; §8 line 209 gives *"UID: broker AID"*. Same intent, three spellings, and the broker's UID remains a choice (correctly, per OQ-4) but the map renders it as fixed. The map should carry the *decided* names only, with undecided ones marked as such.

### MINOR-2 — `R-QUAR-5` is an invented SPEC-001 requirement ID
§4 line 120: *"R-QUAR-5 → see §6.3 | system output as untrusted input | **new** (this phase)"*. SPEC-001 defines R-QUAR-1..4 only (verified by enumeration). The requirement the doc means is SPEC-002 **REC-5**, which the doc already cites correctly at line 162. Line 120 fabricates a SPEC-001 ID and duplicates REC-5, which will confuse any future traceability pass.

### MINOR-3 — R-UI-5 silently converted from a prompt SHOULD into a CSP control
§1.1 line 42 cites *"(R-UI-5)"* for *"CSP baseline forbids third-party CDN loads"*. R-UI-5 is *"The system prompt SHOULD steer the model toward maintainable UI JS (no obfuscation, no third-party CDN dependencies unless requested)"* — a prompt-level instruction. The substitution is a strengthening and probably a good idea, but it is a requirement-content change with no marker, which §0's framing rule forbids. (It does not fix MAJOR-10: see there.)

### MINOR-4 — Notification-listener privilege level imprecise; the actual build-time knob is absent
§3 line 92 says `BIND_NOTIFICATION_LISTENER_SERVICE` is a *"(privileged grant)"*. Verified `protectionLevel="signature"` (`AndroidManifest.xml:8426-8427`) — for a platform-signed broker that is simply satisfied, not "privileged". More useful and entirely absent: `config_defaultListenerAccessPackages` (`frameworks/base/core/res/res/values/config.xml:5122`, default `com.android.launcher3`) is the overlay key that grants notification-listener access *without* the user visiting Settings. For a design whose `notif.listen` is load-bearing (vision: "an incoming text arrives. Phosphor understands and classifies it"), that overlay entry is the concrete implementation location and belongs in §3.

### MINOR-5 — `airplane.toggle` names neither the API nor its permission
§3 line 93 lists `airplane.toggle` under Settings with no API. Verified: `ConnectivityManager.setAirplaneMode(boolean)` is `@SystemApi`, `@RequiresPermission(anyOf = {NETWORK_AIRPLANE_MODE, …})` (`packages/modules/Connectivity/framework/src/android/net/ConnectivityManager.java:3937-3943`), and `NETWORK_AIRPLANE_MODE` is `protectionLevel="signature"` (`AndroidManifest.xml:2471-2472`). A missing signature permission, in the row that MAJOR-6 already flags as self-contradictory.

### MINOR-6 — Wi-Fi row omits the deprecation constraint that governs it
§3 line 93 lists `wifi.list` (`WifiManager.startScan`). `setWifiEnabled` (which any `wifi.toggle` would need) is `@Deprecated` and *"for applications targeting Q or above, this API will always fail and return false"* except for DO/PO/system apps (`packages/modules/Wifi/framework/java/android/net/wifi/WifiManager.java:5490-5505`). The design put `wifi.toggle` in REC-4's DESTRUCTIVE set (line 161) without noting that the broker *must* be a system app for the call to work at all — which is an argument for OQ-4's standalone-platform-app option, and should be recorded as such.

### MINOR-7 — `setTorchMode` does not require `CAMERA`; the doc's privilege shorthand overstates it
§3 line 96 puts flashlight under a row whose privilege is *"`CAMERA` → broker"*. Verified `CameraManager.setTorchMode(String,boolean)` (`CameraManager.java:1531`) carries **no** `@RequiresPermission` — torch is gated by camera-service access, not by the `CAMERA` dangerous permission. Minor, but the inventory is meant to be the manifest source; `CAMERA` on the broker for torch alone would be an unnecessary grant.

### MINOR-8 — Exit-criterion gate over-lists OQ-5/6/7, which are not Phase-4 blockers
§268 gates the exit criterion on *"the Captain's answers on OQ-1..OQ-8"*, but §9 itself defers OQ-5 to Phase 12, OQ-6 to Phase 7 and OQ-7 to Phase 9. Only OQ-1 (Vanadium), OQ-2 (credential anchor), OQ-3 (card host) and OQ-4 (broker hosting) actually gate Phase 5 work. The gate should name those four; otherwise Phase 4 is blocked on decisions that are explicitly not needed yet.

---

## NOTE

### NOTE-1 — OQ-1 is pre-decided in §1.1 while still posed as open
§1.1 line 33 states as fact that with system WebView *"the rendering engine is GrapheneOS's hardened Vanadium WebView … with no added trust burden of our own"*; OQ-1 (line 246) then poses the choice and recommends (a). The recommendation is legitimate and labelled — but "no added trust burden of our own" contradicts SPEC-001 §14.2, which records that `app.vanadium.webview`'s signature **is not ours** and that *"if the shell is ever expected to enforce trust in the browser component itself, that signature is not ours yet."* The body text should carry that caveat rather than assert the burden away; the shell renders all agent-generated UI through that engine, so "the trust requirement is on the shell app, not the engine" (line 246) is a claim the Captain should accept explicitly, not inherit from a table cell.

### NOTE-2 — Open questions are otherwise genuine, and recommendations are marked as recommendations
OQ-2 (credential anchor), OQ-3 (card host), OQ-4 (broker hosting), OQ-8 (retiring SPEC-002 L1) are real architecture forks with material cost/risk asymmetries, correctly escalated, correctly recommending rather than deciding. OQ-8 in particular is honest: *"Needs the Captain's sign-off since it retires an entire SPEC-002 level"* — the right instinct. (OQ-3's recommendation is undermined by the §8 diagram; see MAJOR-9.1.)

### NOTE-3 — §0's "concepts that do NOT translate" list is good practice and should be the model for MAJOR-8
Recording eBPF/cgroup/PID-1 as superseded (line 19) and naming the SPEC-002 levels involved is exactly the discipline the framing rule asks for. Its existence is why the silent drops in MAJOR-8 stand out — the mechanism was built and then not used for the capability list.

### NOTE-4 — SPEC-002 L1/L3/L4 adaptations are correct, non-hand-wave translations
Spot-checked against the source: L1 (line 19 + OQ-8) correctly observes SELinux policy is compile-time and agent-authored eBPF is not viable on an Android kernel. L3 (line 105) correctly translates "no settings applications" to "Settings app remains as fallback; `Settings.Global/Secure` is the mechanism; agent never writes it directly" — with the privilege correction in MAJOR-6. L4 (line 79) correctly declines PID-1 ownership as a rewrite the vision forbids (vision: *"Modify and extend the platform rather than rewriting the kernel, modem stack, bootloader, or every Android component"*). L2 (line 71) is correct for telephony/contacts/settings but incomplete for Bluetooth (MAJOR-8). Markers REC-1, REC-3, REC-4, REC-5 are sound translations of their source requirements; REC-2 is not (BLOCKER-1).

### NOTE-5 — Vision traps are not triggered; the prototype is migration-sourced, not architecture-sourced
Checked against the vision's explicit "what Phosphor is not" list. The design does **not** become: a normal app calling stock Phone/Messages (broker calls framework APIs directly; §2.1 refusal to hold permissions in the shell), a chatbot on GrapheneOS (agentd is an init service with a UID/SELinux domain, §2.1-2.2), a browser shell as product (§1.1 explicitly rejects kiosk-browser and Custom Tabs, reasoning from the vision's "real operating-system surface rather than an isolated browser page"), or a Termux runtime (§8 migration table retires Termux/Termux:API/Termux:Boot; §2 formally retires `runtime/server.py`). The prototype is used as a *migration source* — method names preserved as tool vocabulary, `shell.html` as design reference only (§1.1 line 43: *"the prototype file is the design reference, **not** the shipped artifact"*) — which is what the vision permits. **PASS.** The residual risk is not shape but drift: §1.2 line 50 keeps SystemUI unmodified "initially", and absorbing it is deferred to a later phase — acceptable and explicitly framed as such.

### NOTE-6 — Design-only scope verified clean
The doc states design-only twice (§Scope line 8, closing line 271). `git status` shows `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` untracked and no source, script, or device artifact modified as part of this work (the modified `.gitignore` and `docs/PROJECT-STATUS.md` predate the delegation per PROJECT-STATUS §11 line 329). No flash, wipe, or device operation is implied anywhere in the document; the §8 recovery references correctly point at *existing proven* procedures rather than scheduling new ones. **PASS.**

---

## Silent-gap list (requirements with no concrete location and no explicit "open" marking)

| Req | Status in doc | Gap |
|---|---|---|
| **SPEC-001 R-GATE-1** | never cited | MUST (classify before execution) is arguably covered by §5 step 4, but not named. |
| **SPEC-001 R-GATE-4** | never cited | MUST (deterministic in-code pattern list) — and MAJOR-1 shows it being violated in practice. |
| **SPEC-001 R-SEC-3** | line 117, restated as "`.env`-class reads gated" | MUST. Android has no `.env`; the actual secret path set is never enumerated. MAJOR-2. |
| **SPEC-001 §10 capability matrix** | line 121 says "capability matrix maintained" | SHOULD (R-BRIDGE-3). §3 is the intended location but is deferred and wrong in five rows (MAJOR-3..7). |
| **SPEC-002 REC-2** | line 172 claims satisfied | MUST, mechanism provably non-functional. BLOCKER-1. |
| **SPEC-002 L2 (Bluetooth)** | dropped from line 71's translation | L2 names Bluetooth explicitly; no broker row exists. MAJOR-8. |
| **Vision §Native capability integration: NFC, vibration, calendar, alarms** | absent entirely | Four vision-listed capabilities, no rows, no deferral markers. MAJOR-8. |
| **BUILD-PLAN Phase 4: data-flow/trust-boundary diagrams** | line 264 "formalize on request" | Deliverable not produced. MAJOR-11. |
| **BUILD-PLAN Phase 4: capability/API inventory (full signatures)** | line 263 deferred behind OQ-3/OQ-4 | Deliverable not produced; circular with the exit criterion. MAJOR-11. |
| **`docs/P4-AUDIT.md` H1 (open HIGH)** | not carried forward | Live unremediated shell defect (remote `<script src>` → native bridge) reproduced on the new host. MAJOR-10. |

---

## What FIX FIRST requires before acceptance

1. **BLOCKER-1** — a working REC-2 mechanism, marked `[ADAPTED FROM SPEC-002 REC-2]` with its residual gap, replacing the safe-mode claim.
2. **MAJOR-1 + MAJOR-2** — one authoritative classifier with a stated shared pattern artifact and fail-closed disagreement order; R-GATE-1/R-GATE-4/R-SEC-3 given locations or marked open.
3. **MAJOR-3..7** — §3 rebuilt against the tree: correct APIs (`sendTextMessage`/`sendMultipartTextMessage`), correct protection levels (`CALL_PHONE`, `ANSWER_PHONE_CALLS`, `READ_SMS`/`SEND_SMS` = dangerous; the `hardRestricted` allowlist deliverable named), added `WRITE_SETTINGS`/`DEVICE_POWER`/`NETWORK_AIRPLANE_MODE`/`READ_PHONE_STATE`, and a closed risk-class enum used consistently.
4. **MAJOR-8** — Bluetooth/vibrate/NFC/calendar/alarms either added as rows with phase deferrals or recorded in §0's drop list; retire the "almost 1:1" claim.
5. **MAJOR-9** — §8 reconciled with §2.1/§5/§6.2 (approval-card host left genuinely open, shell's `RECORD_AUDIO` noted, agentd→shell path either removed from sepolicy or justified, shell↔agentd mechanism chosen and its trust properties stated).
6. **MAJOR-10** — a §4 subresource/CSP subsection that closes P4-AUDIT H1 explicitly.
7. **MAJOR-11** — capability inventory actually produced (after the Captain settles OQ-3/OQ-4), or the exit criterion re-scoped as a Captain decision.

Re-audit scope after fixes: §3 in full against the tree, §6.3's class enum, §6.5's REC-2 answer, §8's map, and §4's subresource policy. The remaining sections (§0 framing, §1.1's rejection reasoning, §2's trust-split rationale, §5's turn/degradation ladder, §7's failure table, NOTE-2/4/5 material) do not need rework.

---

## Also for the record — one pre-existing repo inconsistency found in passing

Not a defect in the audited document, but it will bite Phase 5 and is cheap to fix now: `docs/P4-AUDIT.md` is the **SPEC-001 R-UI** audit from 2026-09-03, so the filename `P4-AUDIT.md` now collides with "Phase 4". Recommend renaming the old PoC-era audits (`P1-AUDIT.md`…`P5-AUDIT.json`) to something phase-unambiguous — e.g. `POC-AUDIT-1..5` — before the Phase 4/5 audit trail starts using similar names. Flagged, not actioned: this audit modified no other file.

---

# Re-audit — rev 2 (`docs/PHASE-4-PLATFORM-ARCHITECTURE.md`, 75265 bytes, mtime 16:48)

**Re-audit verdict: FIX FIRST (narrow, single item).**
**Auditor:** Debugger, 2026-11-10. Rev 1 audited at 37585 bytes / 271 lines / mtime 11:43; rev 2 is 533 lines. This rev-1 audit file is unchanged since 16:16 (verified: only `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` and this file have mtimes after 16:16).
**Score: 25 of 26 rev-1 findings fully resolved. 1 unresolved in substance (MAJOR-2's R-SEC-3 sentence). 5 new findings, of which 1 is BLOCKER-class. All 12 `[ADAPTED FROM SPEC-002 …]` markers verified accurate.**

## What changed the verdict

Rev 2 is a genuine repair, not a cosmetic pass. It withdrew the false claims rather than rephrasing them (the "no added trust burden of our own" sentence is explicitly *withdrawn as overstated*, §1.1 line 40; "almost 1:1" is *withdrawn*, §2.1 line 76), it published closed enums where rev 1 had undefined class names, it produced the two missing BUILD-PLAN deliverables, and it added something rev 1 lacked entirely: **§10.2, a table of what the document has *not* verified**, with the unverifiable items marked `[TO VERIFY IN TREE]` (7 occurrences). That is the single most important improvement in the rev — the exit criterion can now be judged against declared debt instead of hidden assumption.

It still fails on one item, and the failure is the same *class* of error the BLOCKER was: a fail-closed claim contradicted by how the mechanism actually behaves once you trace the boot sequence.

---

## BLOCKER-1 — RESOLVED (redesign is sound); but see NEW-1, which inherits its class

The rev-1 grounds are correctly diagnosed in §6.5 lines 275-277, with the same two in-tree citations I used (`ComputerEngine.java:3684`, `PackageSetting.java:845`). The replacement satisfies **REC-2 as adapted**, and I verified the foundation rather than accepting it:

- **Host-set trigger is genuinely agent-proof.** `ro.boot.*` is immutable at runtime, and the host-side fastboot path is already the gated channel for every device operation (PROJECT-STATUS §8). "Reachable without the agent's cooperation" holds: a compromised agent cannot clear a property it cannot write.
- **Agent skipped, verifiably.** `service phosphor_agentd … disabled` + `on property:sys.phosphor.safeboot=0 start phosphor_agentd` (lines 292-299) is the correct idiom, and gating on `=0` means an *absent* property also never starts agentd — fail-closed on the agent, as claimed. Broker non-auto-start plus "every gated capability routes through it" gives fail-closed capabilities.
- **A non-init oneshot service *can* set a `sys.*` property — checked, because the whole mechanism rests on it.** `property_service.cpp:498-539` gates property writes on `CheckMacPerms` (SELinux on the target context) and `CheckType`, not on being init; only `sys.powerctl` and `sys.auto_reboot_ctl` are name-special-cased (lines 392, 629, 657). `property_contexts:23` types `sys.` as `system_prop`, and AOSP already ships exact-match single-property types for exactly this shape (`sys.boot_completed → boot_status_prop:…exact bool`, line 991). So keygate needs a dedicated `phosphor_safeboot_prop` typed `exact bool` with `set_prop(phosphor_keygate, phosphor_safeboot_prop)` — **a Phase 5 sepolicy line, not an architecture flaw.** NOTE-4 records it.
- **The fail-closed claim is coherent for the agent and correctly honest about its residual gap.** The residual (hardware chord is a Phase 5 deliverable; until then host+cable) is stated in the same spirit as REC-1's backup gap, and the host path works from the first bootable image.

**On the Supervisor's specific question — can keygate be used to *grant* anything?** No, and this is the strongest part of the redesign. Positive permission checks mean keygate can withhold the agent by *not* setting `sys.phosphor.safeboot=0`; it has no route to make a capability available, because capabilities require the broker's permissions, and the broker is not started by keygate and cannot be. The one-way property holds. The `neverallow` set is also *expressive*, which I checked because it is not automatic: "**`neverallow` it from writing any other property**" (line 405) is achievable via `neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;` — the subtraction form used in-tree at `system/sepolicy/private/property.te:237` and `:319` (`-powerctl_prop`). Three wording fixes below (NEW-2, NEW-3, NEW-4); none overturns the design.

## MAJOR-1, MAJOR-7 — RESOLVED
One authoritative classifier (agentd), broker as a **re-check against the same read-only artifact** rather than a second policy (§6.3 lines 214-223), with the divergence order stated explicitly and a version/hash fail-closed rule. The closed enum `SAFE` / `DESTRUCTIVE` / `DESTRUCTIVE-READ` is published (§6.3 lines 225-231) and §3 line 92 states no other class name appears — I verified §3 uses only those three. REC-4's "SYSTEM tool classes" are correctly folded into `DESTRUCTIVE` *patterns*, which is faithful: REC-4 asks for "same fail-closed pattern engine, new kingdom", not a new severity.

## MAJOR-2 — RESOLVED, except one surviving false sentence
R-GATE-1 and R-GATE-4 are now cited (§5 step 4 line 191, §6.3). **§6.4 is a real translation** — an Android secret-path table (keystore, agentd credential store, `/data/adb`, `/data/local/tmp`, `*.pem`/`*.p8`/`id_rsa*` anywhere) with two enforcement layers (SELinux `neverallow` + classifier `secret-path` patterns). That closes the substance.

**But the §4 requirements table still says `R-SEC-3` → "`.env`-class reads gated" (line 151).** The finding was that no `.env` exists on a device; the table row was not updated even though §6.4 now holds the correct answer. §6.4's pointer is prefixed "**translated for Android in §6.4**", which softens it, but the requirement row itself still asserts a control over a non-existent path. Same class of defect as the original, one sentence in size, self-contradicted eleven lines later by the document's own §3 line 140. Fix: make the row read `R-SEC-3 → Android secret-path set, §6.4`.

## MAJOR-3..7 — RESOLVED (all verified against the tree, again)
- **MAJOR-3:** `sendTextMessage(destAddr, scAddr, text, sentIntent, deliveryIntent, persistMessage)` / `sendMultipartTextMessage(...)`, with "`sendMessage` does not exist" stated inline. Correct.
- **MAJOR-4:** `SEND_SMS`/`READ_SMS` = `dangerous` + `hardRestricted`; the `hardRestricted` note (line 136) correctly identifies the allowlist as a build-system deliverable and warns the failure mode is a *silent* `SecurityException` at first SMS. Matches `Permission.java:234-235`.
- **MAJOR-5:** `CALL_PHONE` (dangerous, costsMoney) for dial; `ANSWER_PHONE_CALLS` (dangerous) for answer/hangup with the explicit note that `MODIFY_PHONE_STATE` will **not** satisfy `endCall()`; deprecation and emergency-call refusal recorded; `tel.status` now carries `READ_PHONE_STATE` / `READ_PRIVILEGED_PHONE_STATE` (`signature|privileged|role`, verified line 3471-3472). The deeper fix is also right: §8 line 367 no longer restates a hand-maintained broker permission list — it points at §3 as the single source, which is what let the rev-1 errors propagate.
- **MAJOR-6:** `WRITE_SETTINGS` (`signature|preinstalled|appop|pre23|role`) for `Settings.System`, explicitly distinguished from `WRITE_SECURE_SETTINGS`; `DEVICE_POWER` (`signature|role`) now present; the SAFE/DESTRUCTIVE contradiction resolved by an explicit carve-out list in §6.3 line 231. I verified `Device_POWER` is enforced at `PowerManagerService.java:6354-6433` for sleep. One small imprecision: `wakeUp()` carries **no** `@RequiresPermission` annotation and is `@hide` — the permission is enforced service-side rather than declared. Since the broker needs the permission either way, the row's conclusion stands; the annotation detail should be corrected so Phase 5 doesn't chase a non-existent annotation.
- **MAJOR-7:** as above — closed enum, and "system-tool class" removed as a class.

## MAJOR-8 — RESOLVED
`bt.list`, `bt.connect`, `vibrate` added with correct permissions (`BLUETOOTH_CONNECT` dangerous — verified line 2660-2664; `VIBRATE` normal|instant — verified line 2985-2988). NFC (Phase 10), Calendar (Phase 9), Alarms (Phase 9) are `[DEFERRED]` rows with phases, *and* the drop list in §0 line 23 records the decision. §8 line 419 replaces "almost 1:1" with real coverage accounting.

## MAJOR-9 — RESOLVED
All four contradictions closed, and closed honestly. The approval dialog is drawn **outside** both process boxes as an explicitly open OQ-3 annotation (§8 lines 378-382) — the diagram no longer pre-decides what §6.2 leaves open. The shell's permission line says `RECORD_AUDIO` only. agentd **loses** binder-to-shell (line 405: "except **to `phosphor_broker`**"). The shell↔agentd channel is **chosen**, not slurred: `AF_UNIX SOCK_SEQPACKET`, shell connects, agentd verifies `SO_PEERCRED`, with the Rust-daemon-needn't-implement-binder rationale — and, most importantly, §5 line 194 now states the **trust asymmetry explicitly**: the render path does not cross the classifier, which is exactly why §4.1 exists. That paragraph is a better argument than my finding asked for.

## MAJOR-10 — RESOLVED; H1 is closed for this design (with one caveat, NEW-5)
§4.1 is two real layers, and the *reasoning* is correct where rev 1's was not — specifically line 173, which states the non-obvious precondition: `script-src 'unsafe-inline'` is safe **only because no host source is admitted**. That is precisely the distinction rev 1 missed. Layer 2 is well-chosen for the actual H1 defect: `shouldInterceptRequest` does gate subresource loads (which is what the WKWebView nav allowlist failed to do), `setBlockNetworkLoads(true)` is a second belt, and the CSP adds `connect-src 'none'` killing the `fetch`/XHR channel outright. The Phase 5 acceptance test (line 178) tests inline-script-still-works alongside remote-blocked — the right pair, since a naive fix would break R-UI-1. **P4-AUDIT H1 is closed for the Android host**, pending that test.

## MAJOR-11 — RESOLVED
§3 is now the full inventory at API/permission/protection-level/risk-class/build-deliverable granularity and is **hosting-independent**, which correctly breaks the circularity (it does not depend on OQ-3/OQ-4). §10.1 delivers the data-flow diagram and a trust-zone table (Z0-Z5) with a "must never do" column that encodes the invariants. §6.3 delivers the policy model with a JSON schema. §10 line 496 states Phase 4 is **conditionally closed on OQ-1..OQ-4** and explicitly refuses to claim unconditional closure. That is the correct handling.

## MINORs / NOTEs — all 8+6 resolved
MINOR-1 (single UID spellings, provisional marked), MINOR-2 (`R-QUAR-5` removed, REC-5 cited), MINOR-3 (`[STRENGTHENS R-UI-5]` marked, R-UI-5's real content stated), MINOR-4 (overlay `config_defaultListenerAccessPackages` named as the concrete build location — the fix I most wanted, since `notif.listen` is load-bearing for the vision's incoming-text case), MINOR-5 (`setAirplaneMode` + `NETWORK_AIRPLANE_MODE` signature), MINOR-6 (Wi-Fi deprecation constraint + its OQ-4 implication), MINOR-7 (torch needs no `CAMERA`), MINOR-8 (gate reduced to OQ-1..OQ-4). NOTE-1 is well handled — the overstated sentence is **withdrawn** and OQ-1 now asks the Captain to explicitly accept an engine we do not sign. NOTE-2/3/5/6 preserved. My filename-collision note is recorded as recommendation-only (correctly not actioned).

## Marker verification — 12/12 accurate
| Marker | Verified |
|---|---|
| L1 (line 20) | accurate: SELinux is compile-time, agent eBPF not viable |
| L2 (line 76) | accurate **and now complete** (Bluetooth added, 1:1 claim withdrawn) |
| L3 (line 140) | accurate; also gains the three-gates correction |
| L4 (line 86) | accurate; **improved** — property-gated services mean a boot can deliberately start without Phosphor, which is closer to SPEC-002's intent than rev 1's version |
| REC-1 (line 306) | accurate, gap recorded |
| **REC-2 (line 273)** | **now accurate** — points at §6.5, stateable mechanism, gap recorded |
| REC-3 (line 210) | accurate; OQ-3 genuinely open |
| REC-4 (line 228) | accurate — patterns-within-DESTRUCTIVE is faithful to "new kingdom, same engine" |
| REC-5 (line 316) | accurate; rev 1's invented `R-QUAR-5` label corrected in place |
| L1/L4 identity (line 205) | accurate |
| L1 in §0 (line 20) | duplicate of above, consistent |
| **Total: 12, all accurate.** Plus 2 `[STRENGTHENS R-…]` markers, correctly used for genuine requirement-content changes. |

---

## NEW findings introduced by rev 2

### NEW-1 — BLOCKER — safe boot's surface half is fail-*open* in the one failure mode that matters
**§6.5 line 302:** *"`PhosphorShell`'s HOME activity reads `sys.phosphor.safeboot` in `onCreate` and, when set ["and when set"], immediately starts the stock launcher by explicit component and finishes itself."*
**§8 line 393** repeats it: *"shell declines HOME and hands off to the stock launcher by explicit component"*.
**§10.2 line 489** records *"how read without a live framework"* as undecided **for keygate only** — the shell-side read is never flagged.

The mechanism is fail-closed on the *agent* (absent property ⇒ agentd never starts) but fail-**open** on the *surface*: the shell hands off only when the property is **set** and **reads as truthy**. Two consequences, both reachable:

1. **Property not visible to the app layer ⇒ no hand-off.** If `sys.phosphor.safeboot` is not exported into the Android property namespace (`sys.*` properties are SELinux-typed; app-layer visibility is a separate question from init's read), the shell's read returns empty, the shell renders as HOME, and safe boot produces **launcher-less Phosphor UI with no agent** — the opposite of REC-2's "plain surface". The document's own §10.2 names this exact unknown for keygate but not for the consumer that acts on it.
2. **Not-configured / unknown value ⇒ no hand-off.** The condition is "when set", not "unless explicitly cleared". The correct fail-closed form is the inverse: *hand off to the stock launcher **unless** the property is definitively `0`* — the same discipline §2.2 already applies to agentd's start condition (`on property:…=0`, so absent ⇒ never start). The two halves of the same mechanism were written with opposite polarity.

This is the same class of error as rev 1's BLOCKER — a fail-closed claim contradicted by the actual conditional once traced — and it sits in the one requirement rev 2's headline change exists to satisfy. It is a one-sentence fix (invert the shell's condition; add the app-layer visibility question to §10.2), which is why it is narrow, but it must land before Phase 4 closes, because Phase 5 will implement the polarity as written.

### NEW-2 — MINOR — the `persist.` trigger can *clear* safe boot, contradicting the one-way claim
Keygate folds in `persist.phosphor.safeboot` (§6.5 line 282, §8 line 392) and the residual gap has the host set `persist` "or an adb-set `persist` property" (line 304). §6.1 line 206 and §8 line 405 claim keygate is *"a one-way switch rather than a privilege"* — but a `persist.*` source that can be written to `0` makes it two-way: anyone who can write that property can clear safe boot. Since the `ro.boot` source is already immutable and host-set, and is stated to work "from the first bootable Phosphor image", the `persist` source adds no availability the host path lacks while weakening the invariant. Either drop it, or restrict it to set-only (`0`→`1` transitions only, `neverallow` on the reverse) and say so.

### NEW-3 — MINOR — `neverallow keygate from … touching the agent's binary or data` is not SELinux-expressible
§8 line 405. `neverallow` operates on *permission checks*; "touching a binary" is a set of file accesses (`execute_no_trans`, `file r_file_perms`, `entrypoint`, `mmap_exec_file_perms`) that must each be denied per type. As written it invites a Phase 5 author to write a rule that will not compile and then to drop it. Rewrite as a list: `neverallow phosphor_keygate { phosphor_agentd_exec | phosphor_agentd_data_file }:file *;` (plus the property subtraction from NOTE-4).

### NEW-4 — MINOR — `neverallow` the policy artifact from *all* Phosphor domains is over-broad
§8 line 405: *"`neverallow` write on the risk-policy artifact from any Phosphor domain"* — but §6.3 line 218 deliberately grants **read** to agentd and broker, and the shell just needs no access. If written literally against `{ phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate }` it satisfies the intent, but "neverallow write" needs the artifact's type named before it can be compiled at all. Name it (`phosphor_risk_policy_file`) in §8 so Phase 5 inherits a compile-ready requirement.

### NEW-5 — MINOR — Layer 2's `data:`-only allow-list conflicts with an allowed screen state
§4.1 line 170: `shouldInterceptRequest` *"denies every request whose URL scheme is not `data:`"*. But §4.1 line 180 permits untrusted remote content to be *opened in the Vanadium browser* as a separate trust domain — a flow the user can reach from the shell. If any shell-side view renders such content in the agent WebView (a summary-with-thumbnail, a link preview), the allow-list silently blanks it rather than routing it to the browser. Minor and fixable in one line: either state that no shell view ever loads remote content (then the allow-list is exact) or add the explicit hand-off rule. Worth naming because "blocked and blank" looks like a bug rather than a policy at Phase 5 exit.

---

## Re-audit summary

| | Rev 1 | Rev 2 |
|---|---|---|
| BLOCKER | 1 (REC-2 mechanism non-functional) | 1 (NEW-1: shell polarity, same class, one sentence) |
| MAJOR | 11 | 0 |
| MINOR | 8 | 4 new (NEW-2..NEW-5); all 8 rev-1 MINORs resolved |
| NOTE | 6 | — (all rev-1 NOTEs handled) |
| Findings resolved | — | **25 of 26** |
| Deliverables missing | 2 of 6 | **0 of 6** |
| Unverified claims | hidden | **declared** (§10.2, 7 × `[TO VERIFY IN TREE]`) |

**Verdict: FIX FIRST — narrow.** Not ACCEPT: NEW-1 is a fail-open in the requirement rev 2's headline redesign exists to satisfy, and it will be implemented verbatim in Phase 5 if not corrected. Not REJECT: the architecture is sound, every rev-1 MAJOR and both rev-1 deliverable gaps are genuinely closed, and the remaining items are four sentences of specification plus one polarity inversion.

**Minimum to reach ACCEPT:** (1) NEW-1 — invert the shell's safe-boot condition to "hand off unless the property is definitively `0`", and add app-layer property visibility to §10.2; (2) the surviving `R-SEC-3 → ".env"-class` row at §4 line 151; (3) NEW-2's `persist` polarity. NEW-3/4/5 are wording accuracy that can land at Phase 5 pre-build alongside the `[TO VERIFY IN TREE]` items in §10.2 — they do not gate closure.

Re-audit scope if a rev 3 appears: §6.5 lines 279-304, §8 line 405, §4 line 151, §4.1 line 170 — and nothing else. Every other section of rev 2 stands as verified above.

**Process integrity.** `git status` shows only `.gitignore` (mtime 10:32) and `docs/PROJECT-STATUS.md` (mtime 10:40) as pre-existing modifications, plus the two new docs. `find -newermt "2026-11-10 16:16"` returns exactly `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` and this audit file. **No source, script, or device artifact was touched**, and rev 2's closing line ("no file other than this document was created or modified") is accurate. Design-only scope confirmed for rev 2 as for rev 1. The audited document was not modified by this re-audit.

---

*End of re-audit (rev 2). Verdict: **FIX FIRST** — 25/26 rev-1 findings resolved, 1 BLOCKER-class item introduced (NEW-1). No file other than this audit was modified.*

---

# Final narrow re-audit — rev 3 (`docs/PHASE-4-PLATFORM-ARCHITECTURE.md`, 80399 bytes, 555 lines, mtime 17:00)

**Verdict: ACCEPT.**
**Auditor:** Debugger, 2026-11-10. Scope: exactly the four locations and two appendix areas I fixed as the re-audit scope for rev 3 (§6.5:279-304, §8:405, §4:151, §4.1:170, the §10.2 row, and the §11 appendix) — nothing else re-examined, nothing else re-graded.

## Method note — how the rev 2→3 delta was established

`git diff` is **not** a valid rev 2→3 diff here: `HEAD` (`d44fa6e`, 16:59) captured the document **mid-edit**, at rev 2 plus Coder's first six rev-3 edits. Comparing the worktree to `HEAD` understates the delta and mixes it with the commit boundary.

Instead I reconstructed rev 2 exactly by replaying Coder's recorded `edit_file` calls in reverse. The feed archive (`.crabcakes/feed.json`) retains every call's `old_text`/`new_text`; 17 successful edits land after rev 2's last edit (00:48:29 UTC) and rev 3 begins at 00:54:31 UTC (one further edit errored and made no change). Reversing all 17 against the worktree reproduces a 72348-byte / 534-line rev 2, and **that reconstruction validates against my own rev-2 citations**: §4 lands on line 151 and §8's SELinux paragraph on line 405, exactly the lines I cited in the rev-2 re-audit. A reconstruction that lands my citations on the cited lines is the right rev 2.

The true rev 2→3 delta is therefore **10 hunks, 13 lines removed, 37 changed lines** — and it is surgical:

| Hunk (rev 3 lines) | Section | In declared scope? |
|---|---|---|
| 1-9 | Header: status line + rev-3 note + retained rev-2 note | Metadata, required |
| 149-152 | **§4:151-152** — the `R-SEC-3` row | ✅ cited |
| 169-172 | **§4.1:172** — new scope-of-the-allow-list bullet | ✅ cited |
| 281-307 | **§6.5:284** (keygate latch), **:304** (plain-surface polarity), **:306** (residual gap) | ✅ cited |
| 390-399 | **§8** diagram safe-boot block | ✅ §8 (block must mirror §6.5) |
| 406-419 | **§8:409-419** SELinux requirements section | ✅ §8:405 |
| 501-504 | **§10.2** new named debt row | ✅ cited |
| 514-517, 545-552 | **§11** appendix intro + header + NEW-1..5 rows | ✅ cited |
| (unchanged) | §0-§3, §5-§7, §9, §10.1 | — byte-identical |

Every hunk falls inside the declared scope or is a strictly necessary consequence of it (the §8 diagram block must match §6.5 or the map drifts from the text, which was MAJOR-9's original defect). **No content drifted.** Spot-checked anchors outside scope all survive verbatim: "almost 1:1" (3×, all in withdrawal/accounting contexts), "no added trust burden" (withdrawn sentence), `config_defaultListenerAccessPackages`, `NETWORK_AIRPLANE_MODE`, `AF_UNIX`/`SO_PEERCRED` (5× each), `conditionally closed`, `sanitize_screen_html`, `STRENGTHENS R-UI-5`, the Z0-Z5 trust table. Appendix rows are 32 (27 rev-1 + 5 NEW), all with exactly 3 cells — no broken table.

## NEW-1 — RESOLVED. Polarity now matches agentd's start condition on **both** halves.

The Supervisor asked specifically that both halves be checked against agentd's own start condition. Verified against the `disabled` service declaration, not against the prose:

- **Agent half** (§6.5:294-300, mirrored §8:351-352): `service phosphor_agentd … disabled` + `on property:sys.phosphor.safeboot=0 start phosphor_agentd`. Absent property ⇒ trigger never fires ⇒ never starts. Fail-closed, and unchanged from rev 2 — it was already correct.
- **Surface half** (§6.5:304): hands off to the stock launcher and finishes itself **unless the property definitively reads `0`**; "an absent property, a value the app layer cannot see, or any unparseable value **all** mean hand-off."
- **§8:396-398** states the same rule in one sentence: "`=1` (or absent/unreadable) ⇒ init never starts `phosphor_agentd`; broker not auto-started; shell hands off … UNLESS the property is definitively 0 — fail-closed on both halves."

The two halves are now the same predicate read in the same direction: *only `0` authorises the agent-present path*, on both. That is precisely the inversion NEW-1 demanded. I also checked that no stale polarity survives in normative text: the only occurrences of "when set" are §6.5:304 **repudiating** the old phrasing ("It is *not* 'hand off when set'") and the appendix row describing the fixed bug. Nothing in the document still tells a Phase 5 implementer to hand off "when set".

**§10.2 row present and correctly framed** (§10.2:504): app-layer visibility of a `sys.*` property is declared *not verified*, with the reason it is load-bearing (an unreadable property makes safe-boot the *permanent* state, not merely default to it), a Phase 5 gate ("before §6.5 is implemented"), and the mirror-property fallback. That is the right shape: the fail-closed polarity makes an unreadable property *safe*, and the debt row records that it would also be *wrong*.

*Supporting in-tree note for the Phase 5 owner of that row (informational, not a finding):* app-layer read is probably achievable and its route is a **typing decision, not a runtime check**. `system_prop` is `typeattribute system_prop core_property_type` (`system/sepolicy/private/property.te:164`), and `compatible_property_only` grants `get_prop({coredomain appdomain shell}, core_property_type)` (`system/sepolicy/private/domain.te:506`). So a `sys.*` property declared through the `system_public_prop` macro is readable by `appdomain`; a property declared as a bare `property_type` with only a `property_contexts` line would **not** be. The row's mirror-property fallback covers the second case, but the cheaper fix is to type it `system_public_prop` and add `get_prop(appdomain, phosphor_safeboot_prop)` if the macro route is not taken. Note the precedent the doc already leans on — `sys.boot_completed → boot_status_prop … exact bool` — is a `system_restricted_prop` that needed an **explicit** `get_prop(appdomain, boot_status_prop)` (`system/sepolicy/private/app.te:40`), so "exact bool" alone buys no read access.

## NEW-2 — RESOLVED in substance (latch is one-way against the agent); one enforcement *rationale* sentence is not expressible → NEW-6, non-gating

The Supervisor asked: does the latch actually open a two-way path? **No** — with one precision caveat about *how* the one-way property is enforced.

§6.5:284 now reads: keygate honours `persist.phosphor.safeboot` "**as a set-only latch — it can request safe boot, never cancel it** (transitions `absent→1` only; a `persist` value of `0` is ignored, and the sepolicy `neverallow` is on the reverse direction)." §8:393-395 mirrors it. Tracing the three sources in keygate's decision logic:

- `persist` absent ⇒ no request from this source.
- `persist`=1 ⇒ request.
- `persist`=0 ⇒ **ignored** ⇒ no request.

So the latch can only *add* a safe-boot request. It cannot subtract one, because there is no value that means "cancel". **Nothing on the device can cancel a host-requested `ro.boot` safe boot**, since `ro.boot.*` is immutable at runtime. The concern NEW-2 raised — a writable `0` turning a one-way switch into a two-way one — is closed at the value level.

### NEW-6 — MINOR (non-gating) — "the sepolicy `neverallow` is on the reverse direction" is not a SELinux-expressible rule

`property_service set` is checked on `(source context, target type, class, permission)` by `selinux_check_access` (`system/core/init/property_service.cpp:162-174`). **There is no value dimension in the check**, so a `neverallow` cannot distinguish writing `1` from writing `0`. A rule "banned in the reverse direction" cannot be compiled — the same class of defect Coder correctly fixed for NEW-3.

Worse, there is a clear path that no sepolicy rule can close: `CheckType` returns `true` unconditionally for an **empty** value —

```cpp
// system/core/init/property_type.cpp:31-35
bool CheckType(const std::string& type_string, const std::string& value) {
    // Always allow clearing a property such that the default value when it is not set takes over.
    if (value.empty()) {
        return true;
    }
```

so `exact bool` does **not** protect the latch from being cleared, and clearing returns the property to *absent*, which keygate reads as "no request". Consequence: whoever holds `set` on the latch can both set and clear it.

Why this does **not** gate closure:
1. The entity that matters is excluded by an *expressible* rule: `phosphor_agentd` and the other Phosphor domains simply are not granted `set` on the latch property. "The agent cannot clear it" — the security-relevant half of the claim — holds.
2. Clearing is symmetric with setting: the only documented writer is the host over adb (§6.5:306), so the actor who can clear a latch-requested safe boot is the actor who requested it, over the same gated channel.
3. The genuinely immutable trigger is untouched: `ro.boot.phosphor.safeboot` cannot be cleared by anything, so REC-2's "reachable without the agent's cooperation" never rests on the latch.
4. Failure mode is availability of an optional extra trigger, not a fail-open of REC-2.

**Fix direction (Phase 5 pre-build, alongside the §10.2 items — not a closure gate):** state the enforcement as what it is — *the latch is one-way because keygate's read logic ignores `0` and because no unprivileged domain holds `set` on the property; SELinux checks the name, not the value, so a `set`-holder can also clear it by writing empty, which is why the host-set `ro.boot` path remains the only immutable trigger.* Two sentences, and it removes a claim a Phase 5 author would otherwise try to implement and fail to compile.

## NEW-3 — RESOLVED, and compile-ready. One footnote.

§8:415 now enumerates permission checks rather than "touching the agent's binary": `neverallow phosphor_keygate phosphor_agentd_exec:file *;` and `neverallow phosphor_keygate phosphor_agentd_data_file:file *;`. I verified this rule **form** is real in-tree, not invented: `neverallow { domain -odsign -init} odsign_data_file:file *;` (`system/sepolicy/private/odsign.te:66`), `… odrefresh_data_file:file *;` (`odrefresh.te:72`), `… stats_data_file:file *;` (`statsd.te:176`). `:file *` is the whole operation set by construction, so the rules cover `execute`, `execute_no_trans`, `entrypoint`, `open`/`read`, `map`, `write`, `create`, `unlink`, `setattr` — all of which I confirmed exist in the `common file`/`file` class definitions (`system/sepolicy/private/access_vectors`). It compiles.

### NEW-7 — MINOR (non-gating) — the parenthetical operation list names a macro that does not exist in this tree

§8:415 lists "`map`/`mmap_exec_file_perms`" among the operations. `mmap_exec_file_perms` is **not defined** anywhere in this tree's sepolicy macros — the sets are `x_file_perms`, `r_file_perms`, `w_file_perms`, `rw_file_perms`, `rx_file_perms`, `rwx_file_perms`, `create_file_perms` (`system/sepolicy/public/global_macros:25-35`); there is no `mmap_exec_file_perms`. Harmless as written, because `:file *` subsumes it and nobody needs to expand the macro — but if a Phase 5 author copies that name into a rule, it fails to compile, which is the exact failure NEW-3 was raised to prevent. Replace with `map` (and, if exec-map is meant, `execmod`) when the sentence is next touched.

## NEW-4 — RESOLVED, and compile-ready.

§8:414 names the artifact and its type: a JSON document (`risk-policy.json`) stored as `phosphor_risk_policy_file`, with `neverallow { phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate } phosphor_risk_policy_file:file { write append create rename setattr unlink };`. Every permission in that list is a valid `file`-class permission (confirmed against `common file` in `system/sepolicy/private/access_vectors`), and the list-and-braces form has precedent (`neverallow pcc_component shell_data_file:file { write create setattr relabelfrom append unlink link rename };`, `system/sepolicy/private/pcc_component.te:331`). The rule is against a **named type**, not "any Phosphor domain", and it preserves §6.3:218's deliberate read grant to agentd and broker — the over-broad reading NEW-4 flagged is gone. The surviving phrase "rather than a vague 'any Phosphor domain'" is the row explaining what it replaced, not a live claim.

## NEW-5 — RESOLVED.

§4.1:172 is exactly the missing scope statement, and it resolves the conflict in the direction that keeps Layer 2 exact rather than weakening it: the `data:`-only allow-list "applies to the agent WebView only", "**no shell-side view ever loads remote content into that WebView** — there is no in-WebView link preview, no remote thumbnail, no embedded document", remote display "performs an explicit **hand-off to the Vanadium browser**", and any future in-WebView remote fetch "is added here as a named, reviewed exception — not by relaxing the allow-list." That is consistent with §4.1:182's renderer-isolation note and leaves the `shouldInterceptRequest` rule, the injected CSP, and the Phase 5 H1 acceptance test (both blocked + inline still executes) untouched. No regression to P4-AUDIT H1's closure.

## What ACCEPT means for the Phase 4 exit criterion

Stated plainly, because the §10.2 table changes what "accept" is worth.

BUILD-PLAN Phase 4's exit criterion (line 261) is: *"The major system boundaries and implementation locations are understood well enough to begin native platform work without guessing."*

**This ACCEPT is an ACCEPT of the document against that criterion, on the declared-debt boundary.** It means: the boundaries, implementation locations and trust assignments are specified well enough that Phase 5 does not have to *guess* — and, critically, that where the document does not know, it says so instead of asserting. §10.2 is now the operative artifact for that judgement: **9 declared rows**, of which 7 carry `[TO VERIFY IN TREE]`, each with an owner and a named Phase 5 step that it blocks. A criterion about "without guessing" is satisfied by a document whose residual unknowns are enumerated and gated; it is *not* satisfied by one whose unknowns are hidden, which is what rev 1 was. That shift — from hidden assumption to declared debt — is the substantive reason for ACCEPT, more than the count of resolved findings.

**It does not mean Phase 4 closes unconditionally, and this audit does not close it.** Three consequences, all already stated by the document itself (§10:511) and none of them softened here:

1. **Four Captain decisions still gate Phase 5 manifest/sepolicy work:** OQ-1 (engine trust acceptance), OQ-2 (credential anchor), OQ-3 (approval-card host), OQ-4 (broker hosting shape). The document correctly refuses to claim unconditional closure, and I am not supplying that claim for it.
2. **Two §10.2 rows gate implementation steps rather than the phase:** app-layer visibility of `sys.phosphor.safeboot` gates §6.5's implementation, and the `[TO VERIFY IN TREE]` protection levels gate the §3 manifest. Landing Phase 5 against §3 before the second is discharged would repeat rev 1's privilege-level errors in a built artifact.
3. **NEW-6 and NEW-7 are carried forward as non-gating wording debt**, with the same status as NEW-3/4/5 had in the rev-2 re-audit: they can land at Phase 5 pre-build alongside the `[TO VERIFY IN TREE]` items. If the Supervisor prefers zero carried debt, the cheapest path is to let Coder take them with the §6.5 property-visibility work — but nothing in the architecture rests on them, so they do not withhold acceptance.

The previously circular deferral of the capability inventory and the diagrams remains resolved (both delivered in §3 and §10.1), so the two rev-1 deliverable gaps stay closed.

## Process integrity (rev 3)

`git status --short` shows exactly one modified path: `docs/PHASE-4-PLATFORM-ARCHITECTURE.md`. `find -newermt "2026-11-10 17:00"` (excluding `.crabcakes/`) returns exactly that file. **No source, script, build or device artifact was touched by rev 3**, and the document's closing line — "Design only — no code, builds, or device operations were performed. No file other than this document was created or modified" — is accurate for this revision as well. My own scratch work for this re-audit is one reconstruction script at `.crabcakes/tmp/agent-debugger/replay_rev2.py` (writes only to `/tmp`), which is tooling, not a repo artifact, and I did not modify the audited document.

One process note worth recording for the trail: commit `d44fa6e` (16:59) committed the architecture document **mid-edit**, so the committed blob is neither rev 2 nor rev 3 — it is rev 2 plus six rev-3 edits. Anyone later diffing `HEAD` against rev 3 will read a misleadingly small delta and may conclude rev 3 was cosmetic. The authoritative rev 2 baseline is the reconstruction above, not `HEAD`.

---

*End of final re-audit (rev 3). Verdict: **ACCEPT** — NEW-1 resolved on both halves with the fail-closed polarity now matching agentd's start condition; the §4 `R-SEC-3` row, NEW-2's latch polarity, NEW-3, NEW-4 and NEW-5 all resolved and compile-ready; two non-gating wording items carried forward (NEW-6, NEW-7). Phase 4 remains conditionally closed on OQ-1..OQ-4, per §10:511. The audited document was not modified by this re-audit; no file other than this audit was modified.*

---

# Rev 4 closure check — narrow scope confirmation (`docs/PHASE-4-PLATFORM-ARCHITECTURE.md`, 94862 bytes / 92026 chars, 560 lines)

**Verdict: CONFIRMED.** Phase 4 architecture document **ACCEPTED**; exit criterion met on the declared-debt boundary; **Phase 5 may proceed.**
**Auditor:** Debugger, 2026-11-10. Scope: the five checks the Supervisor named — §9 rulings, the two closed §10.2 rows, NEW-6/NEW-7, the §10 closure claim, and diff scope. Not a fresh audit.

## Method note — the true rev3→rev4 delta

`git diff HEAD` is **not** a valid delta here either: `HEAD` (`d44fa6e`) still holds the mid-edit rev-2 blob, exactly as recorded in the rev-3 section above. I reconstructed the rev-3 baseline by reversing Coder's 33 recorded rev-4 `edit_file` calls from the feed log (`.crabcakes/tmp/agent-debugger/replay_rev4.py`, writes only to `/tmp`). The reconstruction is **80399 bytes / 556 lines — byte-identical to the rev-3 artifact this file accepted at line 387**, which independently validates the method and the patch's stated base. True delta: 20 hunks, 279 diff lines.

## (1) §9 rulings recorded DECIDED — correct, and downstream no longer contradicts them

All four rulings match the Captain's decision as relayed, verified line by line at §9:442-445: **OQ-1** ride GrapheneOS-signed Vanadium Phases 4–9 / revisit before Phase 12; **OQ-2** Keystore-wrapped + per-flash, secret-at-rest *best-effort* until relock; **OQ-3** broker-hosted card; **OQ-4** standalone platform-signed app, escalate only per-capability. OQ-5/6/7/8 correctly remain `Open` and correctly non-gating.

Every downstream site is brought into line and I found **no contradictory survivor**: §1.1:42, §2.1:73, §2.2:85, §3:112, §5:193, §6.2:215, §6.4:265-266, §8:365-366 + §8:370-371 + §8:374 + §8:405, §10:459, §10.2:506-507, §10:512. Specifically the item flagged in the request — **the §8 diagram annotation that left OQ-3 open is gone**: the `[OQ-3 — OPEN]` box (rev-3 lines 380-384) is deleted and the card is drawn inside the broker's box as `native approval card — OQ-3 DECIDED: rendered here` (§8:374). A tree-wide search for `NOT DECIDED`, `NOT DECIDED HERE`, `provisional — OQ-4`, and `hosting shape = OQ-4` open-forms returns only the corrected `DECIDED` forms. §10.1's trust-zone table (Z1 "must never … render an approval card") already agreed with broker-hosting and needs no change.

## (2) The two §10.2 rows — both results independently verified in-tree

**V-1 — CONFIRMED.** Against `projects/grapheneos-2026091900`: `NEARBY_WIFI_DEVICES` = `dangerous` (`frameworks/base/core/res/AndroidManifest.xml:2685`); `NFC` = `normal` (`:2811`); `MODIFY_AUDIO_ROUTING` = `signature|privileged|role` (`:7595`). All three exactly as cited, and all three match the levels §3 already quoted — so the tag, not the assertion, was the error. The three `[TO VERIFY IN TREE]` tags are removed from those rows (§3:109, §3:118, §3:134) and **`bt.connect`'s profile-API tag is untouched and still debt** (§3:126), as claimed.

**V-2 — CONFIRMED, citations exact.** `sys.` → `system_prop` (`private/property_contexts:23`); `system_prop` is a `system_public_prop` (`public/property.te:262`); `get_prop(appdomain, boot_status_prop)` precedent (`private/app.te:40`), macro at `public/te_macros:385-387` (`{ getattr open read map }`). The reasoning is **correct and non-trivial**: `define_prop` (`public/te_macros:922-924`) and `system_public_prop` (`:956`) emit only a *type declaration* — no read grant — so an app-layer read genuinely does require the named `get_prop`. Resolution to a Phase 5 sepolicy rule with the mirror-property retained as escape hatch is the right disposition; §8:417's subtraction form `{ system_prop -phosphor_safeboot_prop }` is real in-tree policy shape (`private/property.te:228-244, 310-321` use exactly this `-prop` subtraction).

**NEW-6 — CONFIRMED, and the correction is right.** `property_service.cpp:162-175` is `CheckMacPerms` → `selinux_check_access(..., "property_service", "set", ...)`, i.e. **label-level, no value dimension**; `property_type.cpp:31-35` is `CheckType` returning `true` for any empty value. So a `neverallow` "on the reverse direction" was indeed inexpressible, and withdrawing it was the correct call. The three replacement facts are the true statement.

**NEW-7 — CONFIRMED.** `mmap_exec_file_perms` appears nowhere in the tree; `public/global_macros:25-35` defines exactly the eight `*_file_perms` sets the finding named. It is dropped from §8:416 and the prose list reads the nine operations. All nine are valid `file`-class permissions — I verified `execute`, `read`, `write`, `create`, `getattr`, `setattr`, `map`, `append`, `unlink`, `rename`, `open` in `common file` (`private/access_vectors:11-38`) and `execute_no_trans`, `entrypoint` in `class file` (`:180-185`). `:file *` subsumes them, so the rule is compile-ready.

## (3) §10 closure claim — justified as stated

All four Phase-5-gating OQs are decided and both gating verification rows (property visibility → §6.5; the three protection levels → §3 manifest) are closed. The remaining §10.2 rows are `bt.connect`'s profile API, `tel.hangup`'s coverage path, keygate's key-chord semantics, the one `get_prop` rule to write, and the named Phase 5 acceptance tests — **all implementation work with an owner and a phase, none an undecided architecture fork.** "Closed on the declared-debt boundary" is the accurate claim, and §10:512 keeps it honest by saying explicitly that it does not mean the debt is discharged.

## (4) Scope — clean

`git status --short` shows the architecture doc and this audit as the only content changes (plus `.crabcakes/context.md`, the project diary); the rev-4 write window contains 33 `edit_file` calls, **all** on `docs/PHASE-4-PLATFORM-ARCHITECTURE.md`, and no `write_file`/`sed -i`/redirection against any other path. The 20 hunks fall in exactly the declared places plus the appendix and header. The document's closing line remains true for this revision.

## Residuals — recorded, **non-gating**, do not withhold Phase 5

Neither contradicts a ruling nor reopens an architecture fork; both are Phase-5/Phase-10 implementation facts, so I am not converting them into FIX FIRST. Recording them so they are not lost:

- **R-1 (MINOR, Phase 10, in the V-1 row).** The NFC row Coder de-tagged also asserts HCE `BIND_NFC_SERVICE` — `signature|privileged` (§3:134). In-tree it is **`signature|module`** (`AndroidManifest.xml:6430-6431`). That claim was never tagged, so it is outside V-1's declared scope and is not a rev-4 regression — but the row now reads "verified in tree", which makes the wrong neighbour level more credible than before. NFC is deferred to Phase 10, so nothing in Phase 5 depends on it. Fix when the row is next touched; the mechanism difference matters (module-boundary, not a `privapp-permissions` grant).
- **R-2 (MINOR, Phase 5, in the NEW-6 rewrite).** NEW-6(a) says no Phosphor domain holds `set` "on the latch's type", but **§8 declares a type only for `phosphor_safeboot_prop`; no type is declared for `persist.phosphor.safeboot`.** Absent a declaration it falls to `*` → `default_prop` (`private/property_contexts:168`), where `neverallow { domain -init } default_prop:property_service set` (`private/property.te:805-808`) blocks every non-init writer. NEW-6(c)'s "clearing is symmetric with setting" stays literally true, but §6.5:307's residual-gap promise of "setting the set-only `persist` latch over adb" is then unachievable until Phase 5 declares a dedicated type **and** grants the documented writer `set` on it. Not load-bearing — NEW-6(b) correctly makes `ro.boot` the REC-2 carrier — so this is a Phase 5 sepolicy item to name, not a flaw in the correction.

---

*End of rev 4 closure check. Verdict: **CONFIRMED** — all four OQ rulings recorded correctly with no downstream contradiction and the §8 OQ-3 annotation closed; V-1 and V-2 both independently reproduced in-tree (protection levels at `AndroidManifest.xml:2685/2811/7595`; property chain at `property_contexts:23` → `public/property.te:262` → `private/app.te:40`), `bt.connect`'s tag correctly left in place; NEW-6's inexpressible rationale withdrawn and replaced with claims that verify, NEW-7's `mmap_exec_file_perms` dropped with all nine remaining operations confirmed valid `file` permissions; §10's declared-debt closure justified; diff scope clean. **Phase 4 exit criterion met — Phase 5 may proceed.** Two non-gating residuals recorded (R-1 Phase 10, R-2 Phase 5). The architecture document was not modified by this check; no file other than this audit was modified.*
