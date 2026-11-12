# P5-S5 — `PhosphorShell`: platform-signed HOME app (Phase 5 surface)

**Phase:** 5 · **Spec ID:** P5-S5 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (module `PhosphorShell`, `/system/app/PhosphorShell/`, `product_packages.txt` entry), **P5-S2** (`phosphor_shell` domain, `seapp_contexts` entry, `get_prop(appdomain, phosphor_safeboot_prop)`, no read on the policy artifact), **P5-S3** (`sys.phosphor.safeboot` written fail-closed on every boot; S5's hand-off polarity is only *correct* if keygate writes it).
**Blocks:** the visible half of **S8**'s exit checklist, and Phase 6 (which fills the rendering surface into this skeleton). Does not block S6/S7.
**Authority:** architecture §1.1 (renderer choice + kiosk constraints + WebView hardening set), §1.2 ("Launcher3 installed, not default; default resolves to PhosphorShell **except in safe boot**"), §4 / §4.1 (subresource policy; §4.1 Layer 2 is a MUST and lives in this app), §6.5 ("Plain surface" bullet + NEW-1's polarity), §8's map (shell box: "safe-boot: starts stock launcher by component and finishes"; "no binder server; socket client"), §2.1 (shell holds **exactly one** capability permission, `RECORD_AUDIO`).

---

## 1. Scope

Make Phosphor the device's **HOME** on a normal boot and **get out of the way** on a safe boot — the two halves of one mechanism (NEW-1), plus a hardened WebView whose subresource allow-list is real but whose *content* pipeline is a stub until Phase 6.

Delivered in S5:

1. `AndroidManifest.xml` with `HOME` + `DEFAULT` categories, platform-signed, privileged, `RECORD_AUDIO` **only**.
2. `MainActivity` with the **fail-closed hand-off**: hand off to the stock launcher **unless `sys.phosphor.safeboot` definitively reads `0`**.
3. WebView hardening exactly per §1.1/§4.1 Layer 2: `setAllowFileAccess(false)`, no universal access from file URLs, `JavaScriptEnabled(true)`, `setBlockNetworkLoads(true)`, and a `shouldInterceptRequest` that **denies every scheme except `data:`** with a synthetic empty response.
4. The CSP injection into the screen document head (§4.1 Layer 2, shell-injected, never model-emitted).
5. `addJavascriptInterface` exposing **only** `phosphorApi`, method-whitelisted, with every method returning `NOT_IMPLEMENTED` in S5.
6. A **stub screen**: a single locally-assembled HTML document rendered through the same hardened path, showing boot state. No agent connection.
7. The socket-client seam (§8: shell connects to agentd) — a named, non-functional stub in S5, implemented in S7.

### Non-goals

- **No rendering pipeline**: no agentd connection, no turn, no transcript, no TTS, no STT, no mic capture (the `RECORD_AUDIO` permission is *declared* — §2.1 fixes it — but not *used* in S5; a declared-but-unused dangerous permission is recorded, not silently granted at runtime).
- No approval card (§6.2: broker-hosted, never in the page — S6).
- No `phosphorApi` proxy to the broker (S7).
- No launcher features: no app list, no notification surface, no settings entry.
- No `/data` state.

---

## 2. Behaviour contract

### 2.1 The fail-closed hand-off (the polarity, exactly)

On `MainActivity.onCreate()`, **before** any UI work:

```
v = read sys.phosphor.safeboot        // app-layer read, S2's get_prop(appdomain, …)
if (v does not exist)          -> hand off     // absent
if (v is not parseable as 0|1)  -> hand off     // unparseable
if (v != "0")                   -> hand off     // 1
if (v == "0")                   -> continue as HOME
```

- **Hand off = start the stock launcher by explicit component, then `finish()` this activity.** Explicit component, **not** an implicit `ACTION_MAIN`/`CATEGORY_HOME` intent: an implicit intent would re-enter *this* activity (we are the resolved HOME) and loop.
- The component to hand off to is resolved **once** from `PackageManager.queryIntentActivities` for `CATEGORY_HOME`, filtered to exclude our own package, and the *first* non-Phosphor candidate is started. If **zero** candidates exist, that is a platform build defect: log it, show the minimal fallback UI (a plain `TextView` stating "Phosphor: safe boot, no launcher present"), and **do not crash**. `[VERIFY AT BUILD: the stock launcher's package/activity on this GrapheneOS tree — PROJECT-STATUS §9 says GrapheneOS apps are named by module, and Launcher3's package must be read out of the manifest, not assumed; record it. Architecture §1.2/§6.5 name it "Launcher3/Graphene launcher".]`
- **The check must not be defeatable by the app layer's own failure**: any exception during the property read ⇒ hand off (catch, do not propagate).
- The read happens in `onCreate` **and** in `onNewIntent`/`onResume` when returning to the activity, so a stale resumed activity cannot re-become the surface after a safe-boot boot. (Cheap, idempotent; the property only changes across boots, so this is belt-and-braces — record that it is *not* a live kill switch, matching S4's §5 row 3.)

**Why the polarity is inverted from the intuitive form — state it in the code comment (NEW-1):** "hand off when set" makes an absent or invisible property leave Phosphor rendering as HOME with no agent, which is exactly the opposite of REC-2's plain surface. The two halves of the mechanism must share polarity with agentd's `on property:…=0` start, so **absent ⇒ down** on both sides.

### 2.2 Manifest contract

```xml
<manifest package="com.phosphor.shell" android:versionCode="1" android:versionName="p5">
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>   <!-- exactly one -->

  <application android:label="Phosphor">
    <activity android:name=".MainActivity"
              android:exported="true"
              android:launchMode="singleTask"
              android:excludeFromRecents="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.HOME"/>
        <category android:name="android.intent.category.DEFAULT"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
```

- `Android.bp`: `android_app` with `platform_apis: true`, `certificate: "platform"`, `privileged: true`, `overrides:` nothing.
- **No `<service>`, no `<receiver>`, no `<provider>`, no `BIND_*` permission, no exported second component.** S5's surface is one activity. (Audit hook: A6 greps the merged manifest.)
- **No** `RECORD_AUDIO` runtime request in S5. The permission is declared because §2.1 fixes the shell's capability set; using it is Phase 6/7. The completion note states this explicitly so an auditor does not read a declared permission as an exercised one.

### 2.3 WebView hardening (MUST, §1.1 + §4.1 Layer 2)

Set on the single `WebView` instance, before `loadData`:

| Setting | Value | Source |
|---|---|---|
| `setJavaScriptEnabled` | `true` | R-UI-2; §1.1 (unchanged in content) |
| `setAllowFileAccess` | `false` | §1.1, §4.1 |
| `setAllowFileAccessFromFileURLs` | `false` | §1.1 "no universal access from file URLs" |
| `setAllowUniversalAccessFromFileURLs` | `false` | §4.1 |
| `setBlockNetworkLoads` | `true` | §1.1, §4.1 |
| `setAllowContentAccess` | `false` | not named in §1.1; a strict extension — **mark it as an added restriction** so it is not read as §1.1's content |
| `setDomStorageEnabled` | `false` (Phase 5) | no state in S5; re-enabling is a Phase 6 decision |
| `setMediaPlaybackRequiresUserGesture` | `true` | default; stated so it is not accidentally relaxed |
| `setMixedContentMode` | `MIXED_CONTENT_NEVER_ALLOW` | defence in depth with `blockNetworkLoads` |
| `setSafeBrowsingEnabled` | `false` | screens are local and `data:`-only; enabling it would send hashes to a remote service — **contradicts `connect-src 'none'` / no-network posture** |

`shouldInterceptRequest(view, request)`:

```
if (scheme(request.url).equalsIgnoreCase("data")) return null;      // allow the default handling
else { log("phosphor-shell: subresource blocked: " + scheme + ":"); return syntheticEmptyResponse(); }
```

- **Allow-list is `data:` only.** Not `file:`, not `content:`, not `about:` (blank/about URLs are navigations, not subresources; if one appears here it is blocked and logged).
- **Scope, stated so it is not later read as a bug (NEW-5):** the allow-list governs the **agent WebView only**. **No shell-side view ever loads remote content into it** — no link preview, no remote thumbnail, no embedded document. Remote content the user must *see* performs an explicit hand-off to the Vanadium browser (§4.1's renderer isolation note). Any future in-WebView remote fetch is a named, reviewed exception added here — never a relaxation of this list.
- The synthetic response is a valid empty `WebResourceResponse` (`200`, empty body) so the page does not hang, and the block is logged as a **visible system note** in the transcript per §4.1 Layer 1's "truthful signal" principle — in S5, "transcript" is the stub screen's note area.
- `WebViewClient` must **not** override `shouldOverrideUrlLoading` to permit anything: any main-frame navigation attempt away from `data:` is refused outright (return `true`, log).

### 2.4 CSP injection (§4.1 Layer 2)

The shell, **not the model and not the stub page**, injects into the document head:

```
default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline';
img-src data:; font-src data:; connect-src 'none'; frame-src 'none';
form-action 'none'; base-uri 'none'
```

- Implementation: `loadDataWithBaseURL(null, injectedHtml, "text/html", "utf-8", null)` after inserting `<meta http-equiv="Content-Security-Policy" content="…">` as the **first** element of `<head>`. A `<meta>` CSP is only honoured if it appears in `<head>`; injecting it after content defeats it.
- The CSP string is a **constant in the app**, not read from the page. A test asserts the injected document's first head element is the meta tag (A4).
- `script-src 'unsafe-inline'` with **no host source** is the R-UI-1/R-UI-3-compatible shape (§4.1) — do not "harden" it by removing `unsafe-inline`, which would break R-UI-1..3 and is explicitly forbidden by §4.1's requirement accounting.

### 2.5 `phosphorApi` surface (method-whitelisted, stubbed)

- Exactly one `addJavascriptInterface(obj, "phosphorApi")`.
- `obj` is a **proxy class with an explicit `@JavascriptInterface` method set** — no reflective dispatch, no `Object`-typed params that could reach arbitrary classes.
- S5 whitelist (minimal, and every method returns a not-implemented error object):
  `version()`, `bootState()`, `capabilities()` → `[]`, `request(tool, argsJson)` → `{"error":"not_implemented"}`.
- **No token, no credential, no socket handle, no file handle is exposed** (R-SEC-2/R-UI-4: page JS never sees the auth token — there is no token in S5 at all).
- Every call logs `phosphorApi.<method>` with **argument-free** structured logging (never the payload — a payload may contain user text; REC-5/audit rule).

### 2.6 Stub screen (proves the hardened path without a rendering pipeline)

A single HTML string assembled in code: a title, the boot state (`sys.phosphor.safeboot` value as observed, redacted of nothing since it is not secret), a note area that displays blocked-subresource notices, and an inline `<script>` that calls `phosphorApi.version()` and writes the result to the DOM. **That inline script is the proof R-UI-1/R-UI-2 still work** — a screen that renders nothing would not distinguish "hardened" from "broken".

### 2.7 Socket-client seam (stub; S7 fills it)

- A single `AgentLink` class with `connect()`/`send(frame)` returning `NOT_CONNECTED` in S5; the socket path constant comes from `services/PhosphorIpc/` (owned by S4).
- `SO_PEERCRED` is agentd's side (S4); the shell's obligation is to connect to the **declared** path and nothing else. Do not invent a second path.
- No connection attempt is made in S5 (offline state is the stub screen's normal state).

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| Module + manifest | `<tree>/packages/phosphor/apps/PhosphorShell/{Android.bp, AndroidManifest.xml}` |
| Activity | `…/src/com/phosphor/shell/MainActivity.java` (or `.kt`) |
| Hardening + CSP + intercept | `…/PhosphorWebViewClient.java`, `…/WebViewHardening.java` |
| Bridge | `…/PhosphorApi.java` |
| Socket seam | `…/AgentLink.java` |
| Stub screen | `…/Screen.java` (one HTML template constant) |
| Domain/permission | S2's `phosphor_shell.te`, `seapp_contexts`, `get_prop(appdomain, …)` |
| Home resolution | Product config: the HOME role/default must resolve to `com.phosphor.shell` (§1.1 "the role/default is set in our device config so first boot lands on Phosphor"). **Location: `[VERIFY AT BUILD]`** — candidate is the device overlay's `config_defaultHomeComponent`/`core/res/res/values/config.xml` `config_defaultModuleName`-class key in `vendor/google_devices/akita` or adevtool's config; record the exact key and file. |

---

## 4. Acceptance criteria

**A1 — Boots to the shell on a normal boot.** After the S3-approved normal boot: the home screen is Phosphor (screenshot evidence), `adb shell dumpsys activity activities | grep -i 'mResumedActivity'` names `com.phosphor.shell/.MainActivity`, and `getprop sys.phosphor.safeboot` → `0`.

**A2 — Safe boot lands on the stock launcher.** After the S3-approved safe-boot boot (`persist.phosphor.safeboot=1`): the resumed activity is the **stock** launcher's component, `com.phosphor.shell` appears **finished** (not in the back stack: `dumpsys activity activities` shows no `MainActivity` for our package in the active task), and `pidof com.phosphor.shell` may be empty or absent — the requirement is that it is **not the surface**. Screenshot evidence. Architecture §1.2/§6.5: "launcher + Settings + no agent".

**A3 — The three fail-closed hand-off cases.** Each is demonstrated (device or instrumented test with a stubbed property source):
- property **absent** ⇒ hand off;
- property **unparseable** (e.g. `garbage`) ⇒ hand off;
- property **`1`** ⇒ hand off;
- property **`0`** ⇒ continue.
Pass = all four, with the incidents logged. This is NEW-1's acceptance in the app half.

**A4 — Hardening set applied and verifiable.** For each row of §2.3, a code assertion (a `WebView` config dump or a unit test on the setter wrapper) + the CSP test: the rendered document's first `<head>` child is the `Content-Security-Policy` meta with the **exact** directive string of §2.4.

**A5 — Subresource allow-list works (`docs/P4-AUDIT.md` H1 re-run, the §4.1 verification).** Load the stub screen **plus** `<script src="https://evil.example/x.js">` and `<img src="https://evil.example/p.png">` into the same hardened WebView. Pass = (i) both blocked, each with a logged `subresource blocked:` note rendered visibly in the note area; (ii) the inline `<script>` in the same document **still executes** (it is what writes `phosphorApi.version()` to the DOM); (iii) `window.phosphorApi` is reachable; (iv) **no network request leaves the device** — proof by `adb shell dumpsys netstats` delta or by absence of any resolution attempt in `logcat`, with the method stated. This is §4.1's Phase 5 acceptance test, and it is S5's central deliverable.

**A6 — Exactly one capability permission, one component.**
```bash
aapt2 dump permissions out/target/product/akita/system/app/PhosphorShell/PhosphorShell.apk   # -> RECORD_AUDIO only
aapt2 dump badging …  | grep -E 'launchable|category'                                       # -> HOME/DEFAULT only
```
Pass = `RECORD_AUDIO` is the only `uses-permission`; the merged manifest has exactly one `<activity>` and zero `<service>/<receiver>/<provider>`; the APK carries **our platform certificate** (§2.1: platform-signed).

**A7 — `phosphorApi` is the only bridge and is method-whitelisted.** Code review artifact: exactly one `addJavascriptInterface` call in the module; the proxy class's `@JavascriptInterface` methods are exactly §2.5's four; no reflective dispatch. A test asserts a call to an unlisted method is unreachable (`phosphorApi.secret` is `undefined` in the page).

**A8 — No secret in page scope (R-UI-4/R-SEC-2).** The stub page's `document` contains no token, key, or path under `/data`. Grep the built HTML for `token|secret|key=` → only the `phosphorApi` names.

**A9 — Offline state is honest.** With nothing to connect to (S5 by construction), the screen states the agent is unavailable rather than showing a fake "ready". This is §2.2's "agent offline, retrying" shape in stub form.

**A10 — No binder server, no capability surface.** `dumpsys activity service` shows no service exported by our package; static: no `<service>` (A6). The shell holds no binder *server* (§8 map).

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| Property read throws / `SystemProperties` unavailable | Catch ⇒ **hand off**. Never propagate, never default to "continue". |
| `sys.phosphor.safeboot` = `00`, ` 0`, `0\n` | Parse strictly: trim, then require exactly `"0"` or `"1"`; anything else ⇒ hand off. Do not use `Integer.parseInt` alone (it accepts `+0`/`-0`); accept only the two literal strings. |
| Stock launcher absent from the build | Show the minimal fallback text (never crash) and log it as a **build defect**; A2 cannot pass without the stock launcher, so this is a stop-the-line finding. |
| Two HOME candidates | First non-Phosphor candidate, order stabilised by sorting component names so behaviour is deterministic across boots. Record the resolved component in the log. |
| Explicit component hand-off throws `ActivityNotFoundException` | Fall back to the constant limit: log + minimal text UI; do not re-enter the implicit-HOME loop. |
| Shell re-launched from recents in safe boot | `suspendTask`? No: `excludeFromRecents="true"` + re-check in `onResume` (§2.1). |
| Page tries `window.location = "https://…"` | `shouldOverrideUrlLoading` refuses and logs; the WebView never leaves `data:`. |
| Page tries `fetch()`/`XHR` | `connect-src 'none'` + `blockNetworkLoads`; assert in A5 (iv). |
| Model/page emits `<script src>` that Layer 1 (agentd) should have defanged | Not applicable in S5 (no agentd), and this is exactly why A5 injects the hostile tags **directly** into the stub document — S5 must be safe even with Layer 1 absent. |
| WebView engine is GrapheneOS-signed, not ours | Accepted (OQ-1 DECIDED, §1.1/§9): the engine's trust anchor is GrapheneOS's. The completion note must **not** claim the shell "owns" the engine — that overstated claim was withdrawn in rev 2 (NOTE-1). |
| `RECORD_AUDIO` declared but unused | Recorded (§2.2), not "cleaned up": §2.1 fixes the shell's capability set, and removing the declaration would contradict the architecture. |
| Dark-theme/font rendering differences | Out of scope for S5 acceptance; a screenshot is evidence of *which surface*, not of visual quality. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A10 pass; A1/A2 reuse S3's approved boots; A5 runs on device under the same approval (it is a UI-level check, no flash).
- [ ] Fail-closed hand-off: all four cases proven (A3); polarity comment cites NEW-1.
- [ ] Hand-off is **by explicit component**; implicit-HOME loop impossible; zero-candidate fallback is non-crashing.
- [ ] Hardening set complete per §2.3, with the `setAllowContentAccess`/`setSafeBrowsingEnabled` additions marked as extensions, not as §1.1's content.
- [ ] CSP injected by the shell as the first `<head>` element, exact string, constant in code.
- [ ] `data:`-only intercept; NEW-5 scope statement present (no shell-side remote content in the agent WebView).
- [ ] `phosphorApi` exactly four whitelisted methods, no reflection, no secret in scope.
- [ ] **H1 re-run passes**: remote script/img blocked **and** inline script still executes **and** no egress.
- [ ] One permission (`RECORD_AUDIO`), one component, platform certificate.
- [ ] OQ-1 trust caveat stated accurately (engine is GrapheneOS's).
- [ ] No `/data` state, no agent connection, no approval card in the page.

## 7. Open items created by this spec

1. The exact product-config key/file that makes `com.phosphor.shell` the resolved HOME (§3) — builder; without it A1 fails and S5 is not done.
2. The stock launcher's package/activity on this tree (§2.1) — builder, read from the manifest.
3. `setDomStorageEnabled` re-enable decision for Phase 6 (§2.3) — deferred.
4. `RECORD_AUDIO` **runtime grant** timing (Phase 6/7) — the permission is declared now; when it is first requested must be a recorded decision, since a system app must still be granted a dangerous permission.
5. Frame-size/socket-path coupling to S4's health and S7's wire design (§2.7).
