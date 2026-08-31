# Phosphor

A handheld where am LLM draws the next screen as HTML. You talk. It listens. The screen that appears is whatever the moment calls for.

That's it. That's the whole product.

I built this because I got tired of the modern smartphone. Not the hardware — the hardware is fine. The model is broken. An operating system that hides everything behind icons you have to remember, arranged in a grid that some unimaginative arrogant slob at Google/Apple decided was the right metaphor for the seventeenth year in a row. Notifications designed by narcissist who hate you. Apps that demand permissions to spy on you. Forty-seven settings menus, none of which let you do the one thing you actually opened the app to do.

The web won. It won twenty years ago. HTML, CSS, and JavaScript are the most deployed runtime in the history of computing. Every phone in your pocket ships with a faster browser than most laptops had in 2010. And we're still pretending the answer to "what should the home screen be?" is a folder of oversaturated jpegs you have to swipe past.

Phosphor is my answer. The home screen is whatever I need in the moment. Sometimes it's a button to call your mom. Sometimes it's a weather card with the next six hours. Sometimes it's a settings page because you asked it to turn off the ringer. The browser renders it. There is no home screen. There is no app grid. There is no keyboard... There is a microphone, a model, and a black screen that fills with whatever makes sense.

## How it actually works

Three pieces. That's all.

**A Pixel 8a running GrapheneOS.** Picked because Google's Tensor G3 NPU actually runs local LLMs at usable speed, and GrapheneOS gives me a base I can verify — no Google Play Services, no bloat I didn't install, no telemetry phoning home. Cost me $200 used from Swappa. Make sure you check the model number first because Verizon Pixels have a permanently-locked bootloader and I refuse to live under anyone's thumb on a device I bought.

**A Rust binary that talks to the OS.** Twenty-eight thousand lines of Rust in production is a lot. Phosphor's bridge is six hundred. It runs as root, binds `127.0.0.1:7777`, and exposes a JSON-RPC API. That's it. Every device capability — the modem, the GPS, the camera, NFC, Bluetooth, USB, the battery thermals, the clipboard — comes through as a method call. `tel.dial`. `geo.fix`. `battery.read`. No magic. No SDK. You could rewrite it in Python over a weekend if you really wanted to.

**A browser locked into kiosk mode.** Vanadium, the GrapheneOS-maintained Chromium fork, held in a single tab by `cage`, a tiny Wayland compositor whose entire job is to fullscreen one window. The page it loads is `shell.html` — one static file that talks to the bridge over a WebSocket. When the model responds, it sends back HTML. The page swaps it in. No router. No state library. No bundler. It's the simplest thing that could possibly work. This is the layer that I am focused on the most right now.

```
   you ──► whisper (STT) ──► LLM ──► HTML/CSS/JS ──► Vanadium
                                       ▲
                                       │
                       device APIs ◄───┘
                       (cell, GPS, NFC, sensors, BT, USB, camera, mic)
                               via WebSocket to a 30-MB Rust binary
```

## What it isn't

Phosphor is not a product. It's a personal project I'm open-sourcing because other people might want to live this way too, and because the next ten years of personal computing are going to be defined by this kind of thing whether we admit it or not.

It is not a phone you can buy. You build it from a Pixel 8a and an afternoon.

It does not have an app store. There are no apps. There is the AI and what you need in the moment

If it goes offline. The bridge will fall back to a local llama.cpp build when the network is gone, but I'm not going to pretend the local models are good enough to replace the cloud ones yet. They're not. They will be. Today the cloud path is the good path. Things are moving so fast that the limitations that make this clunky now will be gone VERY SOON. So im doing it now. Do I know what im doing? Absolutely not.

## Cost

What I actually spent:

| Item | Cost |
|---|---|
| Pixel 8a 128GB, factory unlocked, refurb | $200 |
| USB-C cable + 30W charger + Spigen case | $45 |
| OpenRouter (default LLM, 12 months at my usage) | $120 |
| Whisper API (12 months at my usage) | $30 |
| **Total** | **$395** |

No subscription. No in-app purchase. The phone is mine. The data stays on it sort of... The model calls go to OpenRouter so check to make sure the model you use, uses your data in a way that you can live with, and that's the end of it.

## Getting it running

You will need:

1. **A Pixel 8a 128GB, factory unlocked, model GKV4X or G6GPR.** Used from Swappa or eBay, $180–225. **Do not buy a Verizon-locked one.** Their bootloaders are welded shut and there is no workaround that doesn't involve a court order.
2. **GrapheneOS.** Flash it via the official web installer. Twenty minutes. Gives you a phone that respects you.
3. **USB debugging on.** Developer Options, toggle, plug in the cable.
4. **`./scripts/install.sh`.** Builds the Rust binary, pushes it to `/data/local/tmp/phosphor/`, installs Termux + Termux:API for sensor access, and registers a Magisk module so the whole thing boots into kiosk mode on startup.
5. **API keys.** OpenRouter, OpenAI Whisper. Paste them in when prompted. Or don't, and use the local paths — but I warned you about those.
6. **Reboot.**

When it comes back, you see a dark screen with a microphone button. Push it. Say anything. Watch HTML appear.

## The system prompt is the product

The single most important file in this repo is not the Rust. It's `SYSTEM_PROMPT.md`.

Everything Phosphor does — its tone, its safety boundaries, what it considers a sensible response, what device APIs it knows about, what HTML it generates, how it handles ambiguity — comes from that file. The bridge is dumb on purpose. The model is the interface. Tune the prompt, you tune the device.

I keep it in a separate file because prompts are meant to be edited. I edit mine constantly. You'll edit yours.

## What's done, what isn't

Done:

- [x] Bridge ↔ shell wire-up (real JSON-RPC over WebSocket, not stubbed)
- [x] Kiosk lockdown (`cage` + `vanadium --kiosk`)
- [x] Magisk autostart module
- [x] One-shot installer
- [x] Cloud STT/LLM/TTS via OpenRouter

Not done, in priority order:

- [ ] Offline mode — llama.cpp + whisper.cpp paths are **not implemented**; the cloud paths (OpenRouter + Whisper API) are the only wired-up loop today. README line 40 describes intent, not current state.
- [x] **Danger-gate** — the shell confirms sensitive bridge calls (`tel.dial`, `sms.send`, …) with a human tap before they reach the bridge; fetched web pages run in a same-origin-less sandbox.
- [ ] Battery thermals + adaptive model switching
- [ ] Multi-turn memory persistence
- [ ] Geofence + push wake from sleep

I publish what I have because waiting until something is "done" is how we got the software industry we have.

## The boring technology, on purpose

WebSocket. JSON-RPC. SQLite. Rust. A crusty old Wayland compositor. A single HTML file. No build step. No bundler. No React. No Next.js. No Astro. No Vite. No webpack. No container. No orchestrator. No Kubernetes. No microservices.

The whole stack fits in your head over a weekend. That's a feature.

## License

Apache 2.0. The bridge talks to proprietary APIs (OpenRouter, Whisper, the cellular modem), and I want a patent grant in the license for everyone who builds on this. The shell page and the system prompt are pure creative work — MIT would have been fine for those — but one license across the repo is cleaner than two, and the patent grant doesn't hurt anyone who was going to use it under MIT terms anyway.

`NOTICE` lists the upstream: GrapheneOS, Vanadium, Cage, llama.cpp, whisper.cpp, tokio, axum, reqwest, serde. All permissive. No GPL contamination.

## Contributing

The bridge is small enough to read in one sitting. The interesting surface is `bridge/src/handlers.rs` — every device API lives there as a JSON-RPC method. The other lever is `SYSTEM_PROMPT.md`. Edit either, send a PR, I'll read it.

Issues filed with steps-to-reproduce on real hardware get fixed first. "It doesn't work" with no device model and no `phosphor-bridge --logs` paste gets closed in three days.

## Upstream

- [GrapheneOS](https://grapheneos.org) — base OS (MIT)
- [Vanadium](https://github.com/GrapheneOS/Vanadium) — Chromium fork (BSD-3-Clause)
- [Cage](https://www.hjdskes.nl/projects/cage/) — Wayland kiosk compositor (MIT)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — local LLM (MIT)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — local STT (MIT)
- [OpenRouter](https://openrouter.ai) — cloud LLM routing
- [OpenAI Whisper API](https://platform.openai.com/docs/api-reference/audio) — cloud STT
