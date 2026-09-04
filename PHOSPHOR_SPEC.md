# Phosphor — A Generative UI Handheld

> **A phone where the AI is the OS, the browser is the shell, and every screen is a one-shot HTML page generated from your voice.**

---

## The Idea

A handheld "computer/phone" running Linux with a browser as the GUI. The browser loads a local HTML file. The page has an embedded connection to cloud AI (e.g., OpenRouter). You only talk to the phone — it sends speech to an STT model, then sends the text to an LLM that renders HTML on the fly. The browser renders the page on the fly. No apps. No traditional GUI. No keyboard. The LLM draws whatever UI is needed at that moment.

Because the surface is a browser, it *can* also show normal web pages. Because the surface is JavaScript, it can call device APIs (camera, mic, GPS, NFC, cellular, sensors, network, Bluetooth, USB) via the JS sandbox. There are no apps. There is no home screen. There is no notification shade. **The interface is whatever the moment requires, generated on demand by an AI that knows your context.**

This pattern is sometimes called **generative UI** or **liquid OS** when you push it hard enough. Phosphor is the form factor that makes it actually useful.

---

## The Experience

You pick up the phone. 3 seconds later Chromium is showing a single screen — a soft pulse, a mic icon, the time, the battery. You say **"call Dave"**. The system prompt + your contacts DB + "call Dave" goes to the LLM. It returns:

```html
<div class="call-card">
  <img src="dave.jpg" />
  <h1>Dave Matthews</h1>
  <p>Calling...</p>
  <button onclick="window.aiphone.call('tel.hangup')">End</button>
</div>
```

That HTML replaces the screen. The bridge makes the actual cellular call via ModemManager. Dave picks up. His voice comes through the speaker. You talk. When you hang up, the screen is replaced with a call summary card: "Call with Dave, 4 min 12 sec, ended 12:34 PM. Add note?" with yes/no buttons.

You say **"show me the weather for next weekend in Big Sur"**. The LLM returns an HTML page with the forecast, and *chooses* to inline a satellite map tile because it knows you like maps. You say **"navigate there"**. It either opens Google Maps via intent, or renders its own map view via Mapbox GL JS inline.

You say **"remind me when I get home to water the plants"**. It registers a geofence via `window.aiphone.geo.watch()`. When you cross the boundary, the device wakes, the screen comes back, the LLM renders "You're home. Water the plants?" with a "Done" button.

There are no icons. No app grid. No keyboard. **The OS looks like whatever the system prompt says it looks like.**

---

## The Hardware ($450–$600)

### Option A — Pixel 8a refurb (recommended) ≈ $215 device + accessories

| Part | Price | Source |
|---|---|---|
| Pixel 8a 128GB, Good–Mint condition (Swappa / Back Market) | $195–225 | Cellular-Seller LLC, model GKV4X |
| GrapheneOS installer (free, web-based) | $0 | grapheneos.org |
| 65W GaN charger + 2m USB-C cable | $25 | Ugreen / Anker |
| Sandisk 256GB microSD (offline LLM cache + offline HTML assets) | $22 | Amazon |
| Spigen Tough Armor case | $20 | Amazon |
| USB-C OTG hub + small Bluetooth speaker | $30 | Anker |
| Wireless Qi pad for always-on desk use | $20 | Any |
| **Subtotal** | **~$315–$365** | |

Leaves **~$235–$285** for a year of OpenRouter + Whisper API credits.

**Why the 8a and not the 7a:** Tensor G3 NPU is meaningfully faster for llama.cpp offline mode (~14 tok/s for 8b-q4 vs ~8 tok/s on G2). For a device whose whole reason to exist is on-device AI, that's the single spec that matters most. Same GrapheneOS support quality as the 7a, both stable since day one.

**Why GKV4X (international) and not G6GPR (US factory unlocked):** Swappa's refurb inventory in Aug 2026 is dominated by GKV4X because Japan/Australia carrier offloads flooded the secondary market when the 9a launched. The two models are identical hardware — same Broadcom BCM4378 Wi-Fi, same Samsung Exynos 5300 modem, same antennas. The only difference is firmware band table: GKV4X omits Verizon mmWave 5G (n257), which is irrelevant for voice, SMS, or LLM rendering. If you're on T-Mobile or AT&T, the GKV4X is genuinely better for international travel. If you're on Verizon, the missing mmWave costs you ~5 minutes a day of "ultra-fast" 5G+ in stadiums/airports/parts of Manhattan — invisible for everything Phosphor actually does.

**Battery**: 4492 mAh, Qi wireless, 18W wired. Plenty for a generative-UI device that mostly wakes on voice.

**RAM**: 8 GB LPDDR5X. Sufficient for GrapheneOS + the WebView app (system WebView: 1–2 GB for a single tab) + phosphor-bridge (~30 MB Rust binary) + llama.cpp's 8B model (~4.5 GB RAM-mapped). Headroom ~1 GB.

### Option B — Pixel 8a new ≈ $499

Same parts list, new in box, full warranty, US model (G6GPR). $499 + $100 accessories = $599. Stretches the budget but skips the refurb gamble.

### Option C — Pixel 9a refurb ≈ $260–$300

Tensor G4 — NPU is *trimmed* vs G3 (Google trimmed silicon to save power), so llama.cpp is actually ~10% slower than the 8a. But you get a 5100 mAh battery (16% more runtime) and 2700 nits display (visible in direct sunlight). Worth it if this is your only phone and you'll carry it everywhere.

### Option D — Pixel 10a ≈ $499 new, refurbs scarce in Aug 2026

Tensor G5 on TSMC 3nm — the first proper node shrink for Pixel Tensor. AI gains over G3 are marginal (whisper ~250ms vs ~300ms, llama-3.1-8b ~18 tok/s vs ~14). **Not recommended right now** because refurbs are scarce, MSRP destroys the API budget, and GrapheneOS support is only ~4 months mature (early-adopter tax: camera quirks, sensor mappings, battery drain edge cases).

### Option C — Build it twice

- 1× Pixel 7a refurb for dev/prototype unit
- 1× Raspberry Pi 5 + 7" touchscreen + PoE HAT for the desk version
- Total ~$580, two form factors, share the same code

---

## The Software Stack (5 layers)

### Layer 1 — Operating system

**GrapheneOS on the Pixel** (or postmarketOS if you want pure Linux with no Android at all).

#### What GrapheneOS actually is

GrapheneOS is **a hardened, de-Googled operating system built on top of the Android Open Source Project (AOSP)**. Same Android base, same APIs your apps expect, but every part that Google touches or that ships with telemetry or that weakens security has been removed or rewritten. It's not a "custom ROM" in the old CyanogenMod sense (forks of proprietary blobs). It's an **independent build of AOSP** that only runs on specific Google Pixel phones — because Pixels are the only Android hardware with enough of the security primitives exposed (the Titan M security chip, the verified boot chain, the firmware updates you can actually audit).

The project is led by Daniel Micay. Originally called CopperheadOS (2014), it was forked and rebuilt from scratch as GrapheneOS in 2018 after a governance dispute. It's used by journalists, dissidents, security researchers, and increasingly normal people who don't want their phone phoning home.

#### What it does differently from stock Android

1. **Google Play Services is opt-in, not required.** On stock Android, GMS is the background process syncing your location, contacts, calendar, crash logs, advertising ID, push notifications, and usage telemetry to Google. On GrapheneOS it's gone by default. You install apps as sandboxed APKs from F-Droid, Obtainium (pulls APKs direct from GitHub releases), Aurora Store (anonymous proxy to Google Play), or APKMirror. Apps can't talk to anything unless you grant it.

2. **Hardened memory allocator.** A custom allocator (built on Android's, rewritten) that **randomizes memory layout per-process, per-execution, and even per-allocation**. Makes the entire class of "buffer overflow → code execution → root the phone" attacks drastically harder. Stock Android does some ASLR; GrapheneOS turns it up.

3. **The Pixel's Titan M2 security chip is used properly.** Titan M is a separate physical processor that handles the lock screen, encryption keys, and verified boot. Stock Android uses it. GrapheneOS uses it more — it stores the device PIN's attempts counter in Titan M (so even with root you can't brute-force by flashing a tampered OS), and it can rate-limit unlock attempts at the hardware level.

4. **No telemetry, no analytics, no crash reporting phoning home.** Stock Android sends usage data, crash logs, and diagnostics to Google by default with no UI to disable most of it. GrapheneOS strips it at the source.

5. **Apps are sandboxed harder.** **Storage Scopes** (apps get exactly the files you select, only when they ask, iOS-style). **Network permission** as a first-class per-app toggle (upstreamed into stock Android 13). Per-app sensor, camera, microphone toggles. Some of these hardenings have been upstreamed back into stock Android — which is how you know they work.

6. **Verified boot is on by default and warns you loudly.** If anyone flashes a different OS image without unlocking the bootloader, the screen shows a bright red warning at boot. Even after legitimate OS updates, the chain of trust is checked at the hardware level.

7. **The OS is reproducible.** Anyone can take the source code, build it from scratch, and the resulting binary hash matches the one GrapheneOS publishes. **The only Android derivative I know of that does this.** No plausible deniability for "we shipped you source A but the binary is actually B."

#### What it costs you (the honest list)

**Wins:**
- Stops telling Google where you are, what apps you opened, when, for how long
- Apps can't silently access mic, camera, contacts, location — every permission is a tap
- Chromium on GrapheneOS is hardened against the kind of browser-side exploits that compromised iPhones for years
- Built-in network monitoring (no extra app) to audit what every app is doing
- Pixels get 7 years of security updates from Google, and GrapheneOS keeps publishing patches for those same devices

**Friction:**
- Google Pay, banking apps that hard-require Play Services, and some games don't work. GrapheneOS has a sandboxed "Play Services" compatibility layer, but if your daily driver relies on a Chase app that sniffs for GMS, it won't work.
- Push notifications for most apps don't work without Play Services. Either run the sandboxed Play Services (gives you push but also some Google) or accept that Slack-style notifications arrive when you open the app, not in real time. For Phosphor this doesn't matter.
- Pixel hardware only. No Samsung, no OnePlus, no Xiaomi. Deliberate security choice, but it limits your shopping.
- Some apps detect "non-Play-Integrity" devices and refuse to run. Netflix HD, some banking apps, some DRM-heavy streaming apps.

#### Why it's the right choice for Phosphor specifically

1. **Boot time is fast.** GrapheneOS boots to the Phosphor WebView app in ~3 seconds. Stock Android with all the Google services takes 15–30 seconds.
2. **You can kill every background service and lock the launcher.** Disable every app, set the Phosphor app as the default home, screen pinning means the only way to escape it is your PIN.
3. **The Tensor G3 NPU is exposed.** Stock Android with Play Services locks the NPU to Google's ML models. On GrapheneOS you can hit it directly with llama.cpp, Whisper.cpp, etc. — what makes the offline-LLM fallback work.
4. **No Google means no Google account requirement.** Contacts DB lives on-device and feeds the LLM context.
5. **Verified boot means your "OS" stays the OS.** If you drop the phone, nobody can swap in a malicious OS image. Titan M2 enforces this.

#### The short version

**GrapheneOS = Android without Google, with the Pixel security chip actually used to its full potential, reproducible builds, and a hardening model that's been upstreamed into stock Android multiple times because it's that good.** It's not a hobbyist ROM. It's the operating system that Edward Snowden uses, that journalists in hostile countries use, and that the security community points to when someone asks "what's the most secure phone OS that still runs real apps?" It happens to also be the perfect base for a phone where the AI is the OS and the browser is the shell.

For v1 do **not** go to postmarketOS yet. Pixel hardware (camera, modem, sensors) has best-in-class mainline Linux support but driver maturity is still rough in 2026. GrapheneOS gives you a battle-tested base with no Google lock-in, and the browser-as-OS still works because we kill everything else.

### Layer 2 — Window manager / display server

**SUPERSEDED by the app decision (2026-09-04).** The container is now a thin Android app (Kotlin + WebView), not a kiosk browser. A regular app owns the full screen on Android — no compositor gymnastics needed. Screen pinning (Settings → Security → Advanced → Pin windows) provides the kiosk lockdown; "no status bar, no nav bar" comes free because the app draws edge-to-edge.

Historical note: earlier drafts used **Cage** (kiosk Wayland compositor) on postmarketOS, or Chromium `--kiosk` with disabled nav gestures on GrapheneOS. Both work; both require the kiosk hacks (autostart scripts, nav-gesture suppression, home-app tricks) that the app approach eliminates.

### Layer 3 — The shell (WebView app, not kiosk browser)

**DECISION 2026-09-04: thin Android WebView app.** Mirrors the proven iOS architecture (App → WKWebView → app-shell.html → native handlers):

- **Container:** minimal Kotlin app. `MainActivity` + a fullscreen `WebView` + `addJavascriptInterface` bridges (`phosphorApi` for token-attached server calls, `phosphorApproval` for the native approval dialog, later `phosphorBridge` to supervise the Rust process).
- **Engine:** GrapheneOS's system WebView is Vanadium-powered — the hardened Chromium engine ships with the OS and updates with it. The app is a thin wrapper; it does not bundle its own browser.
- **Shell page:** the same `app-shell.html` proven on iOS (voice, generative screens, IIFE-wrapped script execution, external-src blocking).
- **Approval dialog:** native Android `AlertDialog`/Compose dialog with server-verified command content (P5-H1 pattern) — never HTML in the WebView.
- **Kiosk lockdown:** the app is the default home app + Android screen pinning. No cage, no Chromium flags, no nav-gesture suppression.

Web-API hardware access (WebBluetooth/WebUSB/WebHID) that the kiosk-browser plan relied on Chromium flags for is replaced by the Rust bridge's WebSocket API — a cleaner boundary: the JS sandbox talks to `window.phosphor.*` (bridge-backed), not to raw device protocols.

(Reference: the kiosk-browser launch command is preserved in git history for the postmarketOS variant, where a compositor + kiosk Chromium remains the right shape.)

### Layer 4 — Local bridge (the part that makes it a "phone")

A tiny **Rust or Go binary** (`phosphor-bridge`) running as a systemd service that exposes:

- **DBus interface** for: cellular (calls/SMS via ofono/ModemManager), WiFi (connman), Bluetooth (bluez), location, battery, audio, screen brightness, vibration, NFC
- **HTTP/WebSocket server on `localhost:7777`** that proxies those DBus calls into the browser as `window.phosphor.call("sms.send", {...})`

The browser calls `window.phosphor` JS API, the bridge translates to DBus, the OS does it. **All calls stay local on the device — no cloud roundtrip for hardware control.**

```rust
// pseudocode of the bridge
#[tauri::command]
async fn sms_send(to: String, body: String) -> Result<String, Error> {
    let conn = zbus::Connection::system().await?;
    let proxy = ModemManager1Proxy::new(&conn).await?;
    proxy.send_sms(to, body).await
}
```

### Layer 5 — The AI renderer (the actual "OS")

This is the whole point. Here's the loop:

```
[mic] → STT → text → LLM(system prompt + device state + history)
 → returns HTML/CSS/JS string
       → injected into <div id="screen">
       → browser renders
       → user interacts with rendered controls
       → events bubble back to LLM context
       → repeat
```

#### Components

| Piece | Recommendation | Cost |
|---|---|---|
| **STT (speech-to-text)** | OpenAI Whisper API ($0.006/min) — **cloud-only today**; Whisper.cpp on Tensor NPU is planned, not wired | $0–$5/mo |
| **LLM (the brain)** | **OpenRouter** — single API key, 200+ models. Current default `google/gemini-2.5-flash` (benchmarked on the real Phosphor workload for speed and instruction discipline; lighter and heavier alternates tested — see docs/). Fall back to a larger model when the task needs it | $5–$30/mo |
| **TTS (speech back)** | OpenAI TTS-1-HD or ElevenLabs — **cloud-only today**; Piper TTS local is planned, not wired | $0–$22/mo |
| **Image gen** | `stability/sdxl` via OpenRouter when UI asks | ~$0.01/image |
| **System prompt** | The design language. "You are the OS of Phosphor. Respond ONLY with valid HTML5 + inline CSS + inline JS. Viewport is 1080×2400px, touch-first, no keyboard. Use large tap targets (min 80px). Use `window.phosphor.*` JS API for actions. Never use external CDN — everything inline. Never use emoji unless requested. Prefer dark backgrounds with high-contrast text." | $0 |

#### Two-mode architecture

- **Online mode** (default): OpenRouter → Claude/GPT/etc. Smart, current, can browse (pipe the LLM a headless browser tool via MCP).
- **Offline mode** (no signal / battery saving): local LLM via **llama.cpp** + small model like `llama-3.1-8b-instruct-q4` on the Tensor G3 NPU. Worse but functional. Pixel 8a can hit ~15 tok/s locally on G3.

---

## Monthly Operating Cost

| Service | Cost |
|---|---|
| OpenRouter (heavy voice use) | $15–$40 |
| OpenAI Whisper STT | $2–$5 |
| ElevenLabs TTS (optional) | $5–$22 |
| Cellular plan (your existing) | unchanged |
| Pixel battery replacement (year 3–4) | $25 DIY |
| **Total ongoing** | **$22–$67/mo** |

Drop ElevenLabs and use OpenAI TTS-1 → **$10–$30/mo total**.

---

## Build Order (concrete)

1. **Buy the Pixel 8a refurb (model GKV4X, factory unlocked).** Unlock, factory reset, flash GrapheneOS via web installer. (1 day) — see full walkthrough below. (Earlier drafts said 7a; the 8a is the target — G3 NPU, and the walkthrough below applies identically.)
2. **Install F-Droid + Obtainium.** Disable everything else. (30 min)
3. **Build the `app-shell.html` + WebView app:** blank dark screen, mic button, mic-permission flow, transcript display, OpenRouter call, HTML injection. Test the shell in a desktop browser first, then wrap in the minimal Kotlin app. (1 weekend; the iOS `ios-app/app-shell.html` is the reference — port it)
4. **Voice loop end-to-end:** mic → Whisper → OpenRouter → render returned HTML. (1 weekend)
5. **Build the bridge:** Rust binary, ModemManager for SMS/calls, bluez for BT, connman for WiFi. Expose via WebSocket. (2 weeks)
6. **Kiosk it:** the WebView app is the default home app + screen pinning; autostart on boot is standard app behavior. (1 hour, no compositor needed)
7. **Add the local LLM fallback:** llama.cpp + 8B model on Tensor G3 NPU. (1 weekend)
8. **Write the system prompt** — ongoing art project. Refine weekly. The personality of Phosphor lives here.

---

## Installing GrapheneOS on the Pixel 7a (15 min, no command line)

The web installer does everything in the browser. You do not need a Linux box, ADB, or terminal access for the standard install — the only "command" is the URL.

### Prerequisites

- A **Pixel 7a** (any carrier, any condition — locked works too)
- A **USB-C cable** that supports data (not charge-only; the one in the box usually works)
- A **second device** (laptop or desktop) with Chrome, Edge, or Brave — used only as the flashing host
- 20 minutes and a working internet connection

### Step-by-step

**1. Go to the official installer on the host machine**

```
https://grapheneos.org/install/web
```

**Only use that URL.** GrapheneOS does not distribute its installer anywhere else. There are phishing sites that pretend to be it. If you're on a different domain, close the tab.

**2. Skip the in-box Android setup, get to the home screen**

- Power the phone on. Skip all Google sign-in prompts.
- Go to **Settings → About phone → tap "Build number" 7 times** to enable Developer options.
- Go to **Settings → System → Developer options → enable OEM unlocking**.

**3. Unlock the bootloader on the Pixel 7a**

- Power off the phone. Hold **Volume Down + Power** until you see "Fastboot mode."
- Plug the phone into the host machine via USB-C.
- Click **"Unlock the bootloader"** in the web installer. Confirm on the phone with Volume Up + Power.

> ⚠️ This wipes the phone. All data is gone. It is the price of admission. Back up photos first if you care.

**4. Flash GrapheneOS**

The web installer pulls the latest signed release from GrapheneOS's servers and writes it directly to the phone. You'll see progress in the browser. The phone reboots automatically when done.

**5. First boot setup**

- Language, Wi-Fi, set a 6+ digit PIN (longer is better — Titan M2 stores the attempt counter at the hardware level, so the PIN is the primary defense).
- **Disable** everything the setup wizard tries to enable: location, analytics, "send diagnostic data," "improvement program," etc.
- Skip the Google account step entirely.

**6. Verify the install**

The web installer shows a final screen comparing the binary hash of what it just flashed against the published hash. They will match. This is the reproducible-builds verification — if it ever doesn't match, you stop and ask what happened.

**7. Install the apps you actually need**

All from F-Droid (preinstalled on GrapheneOS):
- **Termux** — local terminal, optional, useful for debugging
- **Aurora Store** — anonymous Google Play proxy, in case you need an app
- **Obtainium** — pulls APKs straight from GitHub releases, sideload-style
- **Vanadium** — GrapheneOS's hardened Chromium build with extra exploit mitigations; **use Vanadium for Phosphor**, not stock Chromium

**8. Kiosk-mode Phosphor (app path, 2026-09-04 decision)**

- Build/install the WebView app (see `docs/ANDROID.md`)
- Set it as the default home app: **Settings → Apps → Default apps → Home app → Phosphor**
- Enable **screen pinning**: Settings → Security → Advanced → Pin windows → enable, then pin Phosphor
- The app fullscreens the WebView (edge-to-edge, no status/nav bar) and boots straight into `app-shell.html`

(Alternative kept for reference: the older kiosk-browser route — Vanadium as home app + pinned tab — works too but requires more manual lockdown steps and has no native approval dialog.)

**9. Disable everything else**

```
Settings → Apps → See all apps
```

For every app you don't actively use (Gmail, Maps, Photos, Messages, etc.):
- **Disable** the app
- **Revoke all permissions**

The fewer apps running, the faster the boot, the longer the battery, the more accurate the LLM's view of your device state.

**Total elapsed time:** ~20 minutes. **Total commands typed:** zero. **Total files downloaded by hand:** zero.

### Reverting (if you ever need to)

GrapheneOS can be uninstalled and stock Android restored in 10 minutes via the same web installer. It's a normal AOSP image, the Pixel's bootloader accepts it cleanly. You are not locked in.

### Sideloading apps without Play Services

If at any point you need an Android app that isn't on F-Droid (Spotify, WhatsApp, Signal):

1. Grab the APK from the developer's own GitHub releases (Obtainium handles this automatically for any repo URL)
2. Or fetch it via Aurora Store (anonymous Google Play proxy)
3. Or use **APKMirror** (manual download, verify the developer's signature matches)

Never install APKs from random APK sites. Stick to Obtainium / Aurora / APKMirror / developer's own repo.

---

## What Phosphor Actually Is

A **generative UI handheld**. A phone where the AI is the OS, the browser is the shell, and every screen is a one-shot HTML page generated from your voice.

The name is yours.

---

## What the iOS Proof-of-Concept Proved (2026-09)

The iOS app in `ios/` + `ios-app/` (TestFlight, `com.qsmtco.phosphor.app`) was built as a proof of concept for the parts of this spec that don't need Android: the voice loop, generative screens, a real CI/CD pipeline, and — most importantly — the trust architecture. It is done and frozen as a reference. The Android build replaces the container (WKWebView → Vanadium kiosk, iOS handlers → Rust bridge) and inherits everything else.

Lessons that MUST carry into the Android shell:

1. **`innerHTML` does not execute `<script>` tags.** The shell must re-create script nodes after injection. Wrap each resurrected script in an IIFE and hoist top-level `function` declarations to `window` so inline `onclick` handlers still resolve — otherwise screens collide with each other across turns (P4 audit).
2. **Block external `<script src>`.** Subresource loads bypass navigation allowlists in every WebView. The prompt already mandates inline JS; the loader must enforce it (P4 audit H1).
3. **Secrets never enter page scope.** The auth token lives in native storage; page JS talks to the server through a native proxy that attaches it. Purge stale tokens from page storage at boot. Verified by audit (P3).
4. **The approval card must be native AND server-verified.** Page-supplied command text cannot be trusted — fetch the stored command from the server registry before showing the card (P5 audit H1). Denials must be fed back into the agent's conversation (R-GATE-7) or the model never learns.
5. **Quarantine ALL untrusted content.** Search results and fetched pages enter the model's context in labeled DATA-only envelopes; instructions inside are ignored and reported. Scan every tool result for injection markers (P1/P3 audits).
6. **Destructive-command gating is deterministic, not model judgment.** A fail-closed pattern engine (data file, not hardcoded) classifies commands; safe ones run free for speed, destructive ones hold for a human tap. This is the "Danger-gate" from the README, production-grade (P2 audit).
7. **Secret-file access and out-of-scope writes are gated.** `.env`, `.ssh`, keys: blocked. Writes outside the project tree: approval. Conversation histories are redacted before disk (R-SEC-3/4).
8. **Independent audits are the process.** Four minimal-context subagent audits found ~35 real findings across P1–P5, including two would-be-brick bugs and a spoofable approval card. The Android shell gets the same treatment before it's trusted.

The full trust spec (requirements, threat model, verification): `docs/PHOS-SPEC-001-trust-architecture.md`. Audit reports: `docs/P1-AUDIT.md` … `docs/P5-AUDIT.md`. Verification: `docs/VERIFICATION.md`.

## Project Files

This spec lives alongside the working code in `projects/phosphor/`:

- `PHOSPHOR_SPEC.md` — this document
- `shell.html` — the original browser-as-OS UI (kiosk-browser variant, reference)
- `ios-app/app-shell.html` — the proven shell (voice, generative screens, trust port) — this is what the Android WebView app loads
- `bridge/` — the Rust bridge (`phosphor-bridge`): WebSocket JSON-RPC on 127.0.0.1:7777, 27 device methods
- `docs/ANDROID.md` — current Android build plan and next steps