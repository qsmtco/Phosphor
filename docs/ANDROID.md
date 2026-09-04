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

1. **Flash GrapheneOS** via web installer (PHOSPHOR_SPEC.md walkthrough).
   Verify model number first: GKV4X or G6GPR, factory unlocked, NOT Verizon.
2. **Termux first contact:** install Termux from F-Droid, SSH or curl the
   server — instant agent access before any custom code.
3. **Vanadium + shell.html:** the repo-root `shell.html` loads standalone.
   Kiosk it (home app = Vanadium, pin the tab). This gives the dark screen +
   mic + HTML rendering with zero native code.
4. **Voice in the browser:** Vanadium supports the mic capture APIs;
   wire `shell.html` to Whisper + the server. (iOS used SFSpeechRecognizer —
   browser WebSpeech/Whisper API is the Android equivalent.)
5. **phosphor-bridge (Rust):** build from `bridge/`, run as root via Magisk
   module or `adb` push to `/data/local/tmp`. Exposes `tel.dial`, `geo.*`,
   `sms.send`, battery, etc. over WebSocket on 127.0.0.1:7777.
6. **Trust port:** the shell must enforce what iOS enforced (see
   `PHOSPHOR_SPEC.md` § "What the iOS Proof-of-Concept Proved"): script
   re-execution rules, external-src block, token proxy, native approval
   dialog (Android AlertDialog / Compose) with server-verified content.
7. **Bridge calls gated:** every `window.phosphor.*` hardware call goes
   through the same risk classifier + approval registry the shell commands
   use (spec §7, §8; the R-BRIDGE-3 capability matrix in SPEC-001 tracks).
8. **Kiosk lockdown:** cage (postmarketOS path) or Android pin-screen +
   disabled launcher (GrapheneOS path). Autostart on boot.

## Open questions for the Captain

- Which GrapheneOS app distribution route for the shell (plain Vanadium tab
  vs a packaged APK wrapping WebView)?
- Bridge as root (Magisk) vs unprivileged with Termux:API sensors only?
- Does the Pixel replace the iPhone as daily driver during testing, or run
  parallel until the bridge is trusted?
