# Phosphor

**A handheld where AI generates the UI as HTML on demand — no apps, no keyboard, just talk.**

Phosphor turns a Pixel 8a into a voice-first generative-OS device. You talk to it. The bridge sends speech to STT (Whisper), the transcript to an LLM (Claude Sonnet 4.5 by default), and the LLM returns HTML/CSS/JS that the browser renders on the fly. The next "screen" is whatever the moment requires — a call card, a weather page, a navigation map, a settings dialog — generated on demand by an AI that knows your context.

There are no icons. No app grid. No keyboard. No notification shade. **The interface is whatever the system prompt says it looks like.**

## How it works (60-second version)

```
voice ──► whisper (STT) ──► LLM ──► HTML/CSS/JS ──► Vanadium (kiosk browser)
                                          ▲
                                          │
                          device APIs ◄───┘
                          (cell, GPS, NFC, sensors, BT, USB, camera, mic, file)
                                  via WebSocket to a 30-MB Rust binary
```

The Rust binary (`phosphor-bridge`) binds `127.0.0.1:7777` and exposes a tiny JSON-RPC API to the browser. The browser is locked into a single-tab kiosk mode at boot via the `cage` Wayland compositor. GrapheneOS is the base OS for verifiable trust.

## Repo layout

```
phosphor/
├── PHOSPHOR_SPEC.md       — full design spec (read this first)
├── SYSTEM_PROMPT.md       — the prompt that runs every turn
├── shell.html             — the browser shell (kiosk home page)
├── bridge/                — Rust binary that talks to the OS
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs        — WebSocket server, RPC dispatch, broadcast
│       ├── handlers.rs    — JSON-RPC method implementations
│       └── state.rs       — shared app state
└── scripts/
    ├── install.sh         — build + adb push + Magisk autostart
    └── phosphor-init.sh   — kills bgservices, starts bridge + cage + Vanadium
```

## Quick start

**Hardware required:** Pixel 8a 128GB, factory unlocked (model `GKV4X` or `G6GPR`). 
**Do NOT buy a Verizon-locked device** — its bootloader is permanently locked.

1. Buy a factory-unlocked Pixel 8a (recommended: Swappa, $180-225 refurb).
2. Flash GrapheneOS via the [official web installer](https://grapheneos.org).
3. Enable USB debugging in Developer Options.
4. Extract this repo and run `./scripts/install.sh`.
5. The installer builds the bridge, pushes everything to `/data/local/tmp/phosphor/`, installs Termux + Termux:API, and registers a Magisk module for boot autostart.
6. Reboot. Phosphor comes up to a dark screen with a mic button.
7. Paste in your OpenRouter and Whisper API keys when prompted.
8. Say anything. Watch HTML appear.

## API surface

The shell page calls `window.phosphor.call(method, params)` and gets a Promise back. Background events arrive via `window.phosphor.onEvent(handler)`.

| Method | Purpose |
|---|---|
| `llm.complete` | Send conversation turn, get next assistant message |
| `llm.stream` | Same, but with token streaming over the WebSocket |
| `tts.speak` | Synthesize speech for the reply |
| `tel.dial` | Place a cellular call |
| `tel.sms` | Send SMS via the modem |
| `geo.fix` | One-shot GPS fix |
| `geo.watch` | Subscribe to location updates |
| `geo.fence.add` | Register a geofence trigger |
| `camera.snap` | Take a photo, returns base64 |
| `mic.record` | Record audio clip, returns base64 |
| `sensor.read` | Read any device sensor (light, accel, gyro, etc.) |
| `bt.pair` / `bt.scan` | Bluetooth pairing / discovery |
| `wifi.list` / `wifi.connect` | Wi-Fi network management |
| `nfc.read` / `nfc.write` | NFC tag operations |
| `usb.host` | Drive a USB device |
| `clipboard.read` / `clipboard.write` | Clipboard |
| `battery.read` | Battery level, charging state, thermals |
| `file.read` / `file.write` | Sandboxed file I/O on `/sdcard/phosphor/` |
| `notification.post` | Show a heads-up notification (rare in Phosphor) |
| `home.show` | Replace the current screen with the home shell |

## Cost

- Phone (refurb): ~$195-225
- Cables + charger + case: ~$50-60  
- OpenRouter API (12 months): ~$120
- Whisper API (12 months): ~$30
- **Total: ~$300-350 of a $600 budget, with $250+ cushion**

Cloud inference is the only ongoing cost. There is no subscription.

## License

Apache-2.0. See [LICENSE](LICENSE). Patent grant covers the bridge code (which talks to proprietary APIs). Permissive upstream matches GrapheneOS, Vanadium, Cage, llama.cpp, whisper.cpp.

## Status

- [x] Bridge ↔ shell wire-up (JSON-RPC over WebSocket, real, not stubbed)
- [x] Kiosk lockdown (`cage` + `vanadium --kiosk`)
- [x] Magisk autostart module
- [x] One-shot installer (`install.sh`)
- [x] On-device STT/LLM/TTS via OpenRouter
- [ ] Offline mode (llama.cpp + whisper.cpp binary paths wired but not yet turned on)
- [ ] Battery thermals + adaptive LLM model switching
- [ ] Multi-turn conversation memory persistence
- [ ] Geofence + push wake from sleep

See `PHOSPHOR_SPEC.md` for the full design and roadmap.

## Upstream

- [GrapheneOS](https://grapheneos.org) — base OS (MIT)  
- [Vanadium](https://github.com/GrapheneOS/Vanadium) — Chromium fork (BSD-3-Clause)
- [Cage](https://www.hjdskes.nl/projects/cage/) — Wayland kiosk compositor (MIT)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — local LLM (MIT)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — local STT (MIT)
- [OpenRouter](https://openrouter.ai) — cloud LLM routing
- [OpenAI Whisper API](https://platform.openai.com/docs/api-reference/audio) — cloud STT

## Contributing

Issues and PRs welcome. The bridge is the main surface for changes — it's small (~600 lines of Rust) and the API contract is in `handlers.rs`. The system prompt in `SYSTEM_PROMPT.md` is the other big lever: tune the persona, the response style, the safety rules, the device-API surface hints.