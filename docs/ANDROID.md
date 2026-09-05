# Android / Pixel 8a — Current State & Next Steps

**Context:** The iOS app (`ios/`, `ios-app/`) is the completed proof of concept
(TestFlight, frozen). The product target is the Pixel 8a + GrapheneOS per
`PHOSPHOR_SPEC.md`. The trust architecture (`docs/PHOS-SPEC-001`) is
implemented and audited in the shared agent core and applies to any client.

## Already done (from the iOS PoC — inherits directly)

- Voice loop: mic → STT → LLM → HTML on screen (proven at ~1s latency)
- Generative screens with working JavaScript (IIFE-wrapped, collision-safe)
- Trust architecture: quarantine envelopes, injection scanning, fail-closed
  command gating with human approval, secret-file gates, save-time redaction
- Approval flow: native card (iOS) + Telegram commands, server-verified
  content, single-use, 5-min TTL, outcomes fed back to the agent
- Four independent audits + one final (P1–P5), all findings remediated
- Server: `agent_core.py` shared brain, `server.py` HTTP, tunnel on
  phosphor.smtco.co, model `google/gemini-2.5-flash`

## Pixel 8a next steps (in order)

**CONTAINER DECISION (2026-09-04): thin Android WebView app** — the iOS
architecture ported. NOT a kiosk Vanadium tab. The app fullscreens a WebView
(Vanadium engine via GrapheneOS's system WebView), owns the bridge process,
and holds the native pieces: token (never in page scope), approval dialog
(server-verified content), bridge supervision. Steps below reflect this.

1. **Flash GrapheneOS** via web installer (PHOSPHOR_SPEC.md walkthrough).
   Verify model number first: GKV4X or G6GPR, factory unlocked, NOT Verizon.
2. **Sanity check (any client):** confirm network path to the server —
   curl phosphor.smtco.co/health from any terminal on the phone (Termux is
   fine for this one-off debug step; it is not part of the product).
3. **Build the WebView app:** minimal Kotlin — MainActivity + fullscreen
   WebView + `addJavascriptInterface` bridges (phosphorApi, phosphorApproval,
   later phosphorBridge). Load `ios-app/app-shell.html` (the proven shell —
   port as-is: script re-execution, external-src block, token proxy).
   Set as home app + screen pinning = kiosk. Reference: `ios/` skeleton.
4. **Voice:** Android SpeechRecognizer (the SFSpeechRecognizer equivalent)
   via the native bridge — same pattern as iOS. Wire to Whisper + server.
5. **phosphor-bridge (Rust):** build from `bridge/` (27 methods, WebSocket
   JSON-RPC on 127.0.0.1:7777 — already written and compiling). The APP
   supervises the process (spawn on launch, restart on death) — no Magisk
   autostart scripts needed.
6. **Trust port:** the shell enforces what iOS enforced (PHOSPHOR_SPEC.md §
   "What the iOS Proof-of-Concept Proved"): script re-execution rules,
   external-src block, token proxy (addJavascriptInterface replaces
   WKScriptMessageHandler), native approval dialog with server-verified
   content (P5-H1 pattern).
7. **Bridge calls gated:** every `window.phosphor.*` hardware call goes
   through the same risk classifier + approval registry the shell commands
   use (spec §7, §8; the R-BRIDGE-3 capability matrix in SPEC-001 tracks).
8. **Kiosk lockdown:** app = home app, screen pinning on, edge-to-edge
   WebView. No cage, no Chromium flags, no nav-gesture suppression.

## Resolved

- **Container (2026-09-04): thin Android WebView app** (Kotlin + WebView +
  native bridges), not a kiosk Vanadium tab. Mirrors the proven iOS
  architecture; kiosk lockdown via home-app + screen pinning.

## Pending decisions (do not lose these)

- **Naming:** `agent_core.py` → `phosphor_core.py` (agreed); server rename
  pending — candidates `gateway.py` (Q's rec: the authenticated front door)
  vs `phosphor_host.py` vs keep `server.py`. Apply at Android-app build time.

## The 10-step path (canonical)

**Captain (hands-on):**
1. Flash GrapheneOS — web installer, ~20 min. Model check: GKV4X/G6GPR, NOT Verizon.
2. First boot: skip Google sign-in, set PIN, decline telemetry. F-Droid preinstalled.
3. Install: Termux + Termux:Boot (F-Droid), Tailscale.
4. Termux: `pkg install python`; copy `runtime/` from this repo + `.env` (real keys).
5. Termux: `python3 server.py` → confirm `127.0.0.1:8787/health`.
6. Tailscale on phone + desk machine (remote access done).

**Q (code, after 1–6):**
7. Build the WebView app: fullscreen shell, phosphorApi proxy, native approval dialog; set as home app + pin.
8. Bridge port: Rust handler bodies → Android APIs, one method at a time, tested on-device (kv → screen → clip → notif → geo → camera → sms → tel).
9. Bridge methods as agent tools + risk classes (dial/sms/camera gated by the approval card).
10. End-to-end: "Call Dave" → tool → gate → card → real dial.

## Open questions for the Captain

- Bridge privileges: root (Magisk module, full DBus/modem access) vs
  unprivileged app-owned process (fewer permissions, some methods limited)?
- Does the Pixel replace the iPhone as daily driver during testing, or run
  parallel until the bridge is trusted?
