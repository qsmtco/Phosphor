# Phosphor Runtime

The agent runtime: brain + HTTP server. This is what runs on the device
(Pixel 8a, Termux Python) or on any server hosting a Phosphor client.

- `agent_core.py` — the agent loop: tools, trust architecture (quarantine,
  injection scanning, command risk gating, secret-file gates, save-time
  redaction), session store, OpenRouter client. Stdlib-only: no pip deps.
- `server.py` — HTTP front-end (`POST /message`, `/reset`, `/approve`,
  `/health`) speaking to agent_core. Auth: `DC_UI_TOKEN`.
- `command_risk_patterns.json` — destructive-command patterns (fail-closed:
  the runtime refuses to start without this file).
- `.env.example` — template for required secrets. Copy to `.env`.

Spec: `docs/PHOSPHOR_SPEC.md` + `docs/PHOS-SPEC-001-trust-architecture.md`.
Audits: `docs/P1-AUDIT.md` … `docs/P5-AUDIT.md`.

Run: `python3 server.py` (reads `.env`, binds 127.0.0.1:8787).
