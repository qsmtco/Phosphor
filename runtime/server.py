#!/usr/bin/env python3
"""
DRAGONCAKES UI SERVER
=====================
HTTP front-end for the Phosphor iOS app. Speaks to agent_core.

  POST /message   { "message": "...", "key": "<auth token>", "session": "<id>" }
                  -> { "ok": true, "html": "<ph-screen>...</ph-screen>",
                       "text": "...", "meta": {...} }

  POST /reset     { "key": "...", "session": "<id>" }
                  -> { "ok": true }

  GET  /health    -> { "ok": true, "model": "..." }

stdlib only. Runs on 127.0.0.1:8787 (Cloudflare tunnel handles TLS/public).
"""

import os
import re
import json
import hmac
import time
import urllib.parse
import urllib.request
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import agent_core as core

HERE = os.path.dirname(os.path.abspath(__file__))
_os_path = os.path.join

# ─────────────────────────────────────────────────────────────────────────
# Stage B debug page (mic -> MediaRecorder -> /transcribe). Served at
# GET /test. Log of every step renders on-page so failures are visible.
# ─────────────────────────────────────────────────────────────────────────
TEST_PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phosphor STT test</title>
<style>
 body{background:#1c1d22;color:#e8ecf4;font-family:monospace;margin:0;padding:16px}
 #btn{width:120px;height:120px;border-radius:50%;border:none;font-size:16px;
      color:#08301c;background:#35d07f;margin:12px auto;display:block}
 #btn.rec{background:#ff5555;color:#fff}
 #log{white-space:pre-wrap;font-size:12px;background:#111216;border-radius:8px;
      padding:10px;min-height:200px;margin-top:12px}
 .t{color:#6a7080}
 .err{color:#ff8080}
 .ok{color:#7cffb2}
</style></head><body>
<h3 style="text-align:center;font-weight:400">STT test (Stage B)</h3>
<button id="btn">REC</button>
<div style="text-align:center" id="state">idle</div>
<div id="log"></div>
<script>
const log = (cls, msg) => {
  const d = document.getElementById("log");
  const t = new Date().toTimeString().slice(0,8);
  d.innerHTML += `<span class="t">${t}</span> <span class="${cls}">${msg}</span>\\n`;
  d.scrollTop = d.scrollHeight;
};
const TOKEN = "__TOKEN__";
let media = null, rec = null, chunks = [];

document.getElementById("btn").onclick = async () => {
  const btn = document.getElementById("btn");
  const state = document.getElementById("state");
  if (rec && rec.state === "recording") {
    rec.stop();
    return;
  }
  try {
    log("", "requesting microphone…");
    media = await navigator.mediaDevices.getUserMedia({audio: true});
    log("ok", "mic acquired");
    chunks = [];
    rec = new MediaRecorder(media);
    rec.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
    rec.onstop = async () => {
      btn.classList.remove("rec"); btn.textContent = "REC";
      state.textContent = "transcribing…";
      log("", "stopped, blob size: " + chunks.reduce((s,c)=>s+c.size,0) + " bytes");
      const blob = new Blob(chunks, {type: chunks[0]?.type || "audio/webm"});
      try {
        const t0 = performance.now();
        const r = await fetch("/transcribe?key=" + encodeURIComponent(TOKEN),
                              {method: "POST", body: blob});
        const dt = ((performance.now()-t0)/1000).toFixed(1);
        const j = await r.json();
        if (j.ok) {
          log("ok", `transcribed in ${dt}s: "${j.text}"`);
          state.textContent = "✓ " + (j.text || "(empty)");
        } else {
          log("err", `server ${r.status}: ${j.error}`);
          state.textContent = "error (see log)";
        }
      } catch (e) {
        log("err", "fetch failed: " + e);
        state.textContent = "error (see log)";
      }
      media.getTracks().forEach(t => t.stop());
    };
    rec.start();
    btn.classList.add("rec"); btn.textContent = "STOP";
    state.textContent = "recording… tap STOP to transcribe";
    log("ok", "recording…");
  } catch (e) {
    log("err", "mic failed: " + e.name + " — " + e.message);
    state.textContent = "mic failed (see log)";
  }
};
log("", "page ready. tap REC, speak, tap STOP.");
</script></body></html>"""

PORT = int(os.environ.get("DC_UI_PORT", "8787"))
# Auth token: DC_UI_TOKEN in .env (shared with the iOS app). Required.
AUTH_TOKEN = os.environ.get("DC_UI_TOKEN", "")

SCREEN_RE = re.compile(r"<ph-screen>(.*?)</ph-screen>", re.S | re.I)  # L5: non-greedy
# L4 (audit): script/event/JS-URL stripping regexes removed per R-UI-1/3.


def sanitize_screen_html(html: str) -> str:
    """PHOS-SPEC-001 R-UI-1/3: JavaScript in generated screens is ENABLED.

    The trust model (spec section 1, 4.3) is a single-user device where the
    agent IS the OS - blanket script stripping is rejected. This function
    is kept as a passthrough hook for future, narrowly-scoped transforms.
    """
    return html


def split_reply(reply: str):
    """Split a ui-mode reply into (screen_html, transcript_text)."""
    m = SCREEN_RE.search(reply)
    if not m:
        return None, reply.strip()
    screen = sanitize_screen_html(m.group(1).strip())
    text = reply[:m.start()].strip() + " " + reply[m.end():].strip()
    return screen, text.strip()


def strip_tags(s: str) -> str:
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def check_auth(handler, body):
    key = body.get("key", "")
    if not AUTH_TOKEN:
        return False, "server has no DC_UI_TOKEN configured"
    if not key or not hmac.compare_digest(key, AUTH_TOKEN):
        return False, "bad key"
    return True, None


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("[http]", fmt % args, flush=True)

    def do_OPTIONS(self):
        # CORS preflight: WKWebView file:// pages send Origin: null.
        # Must echo allowed methods/headers or the browser blocks the POST.
        data = b""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self._send(200, {"ok": True, "model": core.MODEL})
        elif path == "/favicon.ico":
            svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">'
                   '<circle cx="62" cy="56" r="30" stroke="%23f2f4f8" stroke-width="9" fill="none"/>'
                   '<circle cx="62" cy="56" r="10.5" fill="%23f2f4f8"/>'
                   '</svg>')
            body = f'<html><head><link rel="icon" href="data:image/svg+xml,{svg}"></head><body></body></html>'
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/shell" or path == "/":
            # The product UI: mic orb -> /transcribe -> /message -> render.
            # Token injected server-side; never stored in a file.
            shell_path = _os_path(HERE, "..", "shell.html")
            try:
                body = open(shell_path, encoding="utf-8").read()
            except OSError:
                body = "<h1>shell.html missing</h1>"
            body = body.replace("__UI_TOKEN__", AUTH_TOKEN)
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/test":
            # Stage B debug page: mic -> MediaRecorder -> /transcribe.
            # Local debug tool; token injected server-side so it's not
            # stored in any file. NOT part of the product UI.
            body = TEST_PAGE.replace("__TOKEN__", AUTH_TOKEN)
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/":
            # Browser-facing status page (the API itself is POST /message)
            import html as _html
            body = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Phosphor Agent Server</title>
<style>body{{background:#1c1d22;color:#e8ecf4;font-family:-apple-system,system-ui,sans-serif;
display:grid;place-items:center;height:100vh;margin:0}}
.c{{text-align:center}} .ok{{color:#7cffb2;font-size:48px;margin-bottom:8px}}
h1{{font-weight:300;letter-spacing:.5px;margin:0 0 12px}} p{{color:#6a7080;font-size:14px}}</style></head>
<body><div class="c"><div class="ok">&#9679;</div><h1>Phosphor agent server</h1>
<p>Model: {_html.escape(core.MODEL)} &middot; API: POST /message &middot; status: online</p>
<p>This endpoint serves the Phosphor iOS app, not a web page.</p></div></body></html>"""
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        # /transcribe takes raw audio bytes (multipart-free: the shell sends
        # the audio blob as the request body with ?key= in the query string),
        # converts to 16 kHz mono WAV via ffmpeg, and runs whisper-cli.
        # Everything stays on-device: whisper.cpp compiled natively in Termux.
        if self.path.startswith("/transcribe"):
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            key = (qs.get("key") or [""])[0]
            mode = (qs.get("mode") or ["local"])[0]
            if not AUTH_TOKEN or not hmac.compare_digest(key, AUTH_TOKEN):
                self._send(401, {"ok": False, "error": "bad key"})
                return
            # Read exactly Content-Length bytes: read-to-EOF deadlocks
            # because the client keeps the connection open awaiting the
            # response (learned the hard way — 5-minute hangs).
            length = int(self.headers.get("Content-Length", 0))
            audio = self.rfile.read(length) if length > 0 else b""
            if not audio:
                self._send(400, {"ok": False, "error": "empty body"})
                return
            if len(audio) > 25_000_000:
                self._send(413, {"ok": False, "error": "audio too large"})
                return
            # ── REMOTE mode: OpenRouter transcription (whisper-large class).
            # Falls back to local automatically on any failure — a dead
            # network must never mean a dead mic.
            if mode == "remote":
                or_key = os.environ.get("OPENROUTER_STT_KEY", "")
                if not or_key:
                    mode = "local"  # no key configured: stay local, tell shell
                    remote_note = "no OPENROUTER_STT_KEY in .env — used local"
                else:
                    try:
                        import base64 as _b64
                        b64audio = _b64.b64encode(audio).decode()
                        payload = json.dumps({
                            "model": "openai/whisper-large-v3",
                            "audio": b64audio,
                        })
                        req = urllib.request.Request(
                            "https://openrouter.ai/api/v1/audio/transcriptions",
                            data=payload.encode(),
                            headers={
                                "Authorization": f"Bearer {or_key}",
                                "Content-Type": "application/json",
                            })
                        with urllib.request.urlopen(req, timeout=60) as resp:
                            j = json.loads(resp.read().decode())
                        text = (j.get("text") or "").strip()
                        self._send(200, {"ok": True, "text": text,
                                         "engine": "remote"})
                        return
                    except Exception as e:
                        remote_note = f"remote failed ({e}) — used local"
                        mode = "local"
            else:
                remote_note = None

            import tempfile, os as _os
            with tempfile.TemporaryDirectory() as td:
                raw = _os.path.join(td, "in.webm")
                wav = _os.path.join(td, "out.wav")
                with open(raw, "wb") as f:
                    f.write(audio)
                try:
                    subprocess.run(
                        ["ffmpeg", "-y", "-i", raw, "-ar", "16000", "-ac", "1",
                         "-c:a", "pcm_s16le", wav],
                        capture_output=True, timeout=30)
                except subprocess.TimeoutExpired:
                    self._send(400, {"ok": False, "error": "audio conversion timed out"})
                    return
                if not _os.path.exists(wav):
                    self._send(400, {"ok": False, "error": "unsupported audio format"})
                    return
                # Preferred path: warm whisper-server (model stays loaded,
                # q5_1 quantized) — no process spawn of the 148MB-model CLI.
                # Server wants multipart (file field); curl builds it.
                try:
                    r = subprocess.run(
                        ["curl", "-s", "--max-time", "120",
                         "-F", f"file=@{wav}",
                         "http://127.0.0.1:8788/inference"],
                        capture_output=True, text=True, timeout=125)
                    if r.returncode == 0 and r.stdout.strip():
                        # Server responds as JSON {"text": "..."} by default
                        try:
                            text = json.loads(r.stdout).get("text", "").strip()
                        except ValueError:
                            text = r.stdout.strip()
                        note = {"note": remote_note} if remote_note else {}
                        self._send(200, {"ok": True, "text": text,
                                         "engine": "server", **note})
                        return
                except Exception:
                    pass  # fall through to cold CLI path
                model = _os.path.expanduser(
                    "~/whisper.cpp/models/ggml-base.en-q5_1.bin")
                cli = _os.path.expanduser(
                    "~/whisper.cpp/build/bin/whisper-cli")
                if not (_os.path.exists(model) and _os.path.exists(cli)):
                    self._send(503, {"ok": False, "error": "whisper not built yet"})
                    return
                try:
                    r = subprocess.run(
                        [cli, "-m", model, "-f", wav, "-np", "-nt", "-t", "6"],
                        capture_output=True, text=True, timeout=120)
                except subprocess.TimeoutExpired:
                    self._send(504, {"ok": False, "error": "transcription timed out"})
                    return
            text = (r.stdout or "").strip()
            note = {"note": remote_note} if remote_note else {}
            self._send(200, {"ok": True, "text": text, "engine": "cli", **note})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 65536:
                self._send(413, {"ok": False, "error": "payload too large"})
                return
            body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"ok": False, "error": "invalid JSON"})
            return

        ok, err = check_auth(self, body)
        if not ok:
            self._send(401, {"ok": False, "error": err})
            return

        session = str(body.get("session") or "default")[:64]

        if self.path == "/reset":
            core.clear_session("ui-" + session)
            self._send(200, {"ok": True})
            return

        if self.path == "/approve":
            # P5-H1 (audit): preview mode - native card fetches the SERVER's
            # command before showing it, so page text can't spoof the card.
            if body.get("action") == "preview":
                prev = core.approval_preview(str(body.get("approval_id") or ""))
                if not prev:
                    self._send(404, {"ok": False, "error": "unknown or expired"})
                    return
                self._send(200, {"ok": True, **prev})
                return
            # PHOS-SPEC-001 R-GATE-3/6 + audit H2: consume atomically.
            # Spec 8.4 allows approval from ANY front-end, so we record the
            # approver session but do not require it to match the origin.
            aid = str(body.get("approval_id") or "")
            deny = bool(body.get("deny"))
            approver = str(body.get("session") or "unknown-approver")
            with core._APPROVALS_LOCK:
                core._load_external_approvals_locked()
                core._purge_expired_locked()
                a = core._APPROVALS.get(aid)
                if not a:
                    self._send(404, {"ok": False, "error": "unknown approval_id"})
                    return
                if a["used"]:
                    self._send(410, {"ok": False, "error": "already used"})
                    return
                if time.time() - a["created"] > core.APPROVAL_TTL_S:
                    self._send(410, {"ok": False, "error": "expired"})
                    return
                a["used"] = True           # atomic single-use (L3)
                a["approved_by"] = approver  # audit trail (H2)
                cmd = a["command"]
                origin = a["session"]      # M1: outcome must reach the agent
            if deny:
                # M1 (P5 audit): R-GATE-7 - the agent must learn of denial
                core.append_approval_outcome(origin, cmd, approved=False)
                self._send(200, {"ok": True, "denied": True})
                return
            try:
                r = subprocess.run(cmd, shell=True, capture_output=True,
                                   text=True, timeout=120)
            except subprocess.TimeoutExpired as te:
                out = ((te.stdout or b"") .decode("utf-8","replace") if isinstance(te.stdout, bytes) else (te.stdout or ""))
                core.append_approval_outcome(origin, cmd, approved=True,
                                             output=str(out) + " [timed out]")
                self._send(200, {"ok": True, "exit": -1, "output": (str(out) + " [timed out]")[:8000]})
                return
            out = ((r.stdout or "") + (r.stderr or ""))[:8000]
            core.append_approval_outcome(origin, cmd, approved=True, output=out)
            self._send(200, {"ok": True, "exit": r.returncode, "output": out})
            return

        if self.path != "/message":
            self._send(404, {"ok": False, "error": "not found"})
            return

        message = str(body.get("message") or "").strip()
        if not message:
            self._send(400, {"ok": False, "error": "empty message"})
            return

        print(f"[ui {session}] task: {message[:100]}", flush=True)
        reply, meta = core.agent_turn("ui-" + session, message, mode="ui")
        screen, text = split_reply(reply)

        # On error replies (no screen), return them as plain error JSON
        if screen is None and (reply.startswith("[error") or reply.startswith("(turn")):
            self._send(502, {"ok": False, "error": reply, "meta": meta})
            return

        self._send(200, {
            "ok": True,
            "html": screen or "",          # may be None for plain-text replies
            # L1/L2 (P4 audit): with a screen, transcript = commentary only
            # (never strip_tags of the reply - it would leak JS source and
            # any second ph-screen block into the text field)
            "text": (text if screen else strip_tags(reply)),
            "meta": meta,
        })


def main():
    if not AUTH_TOKEN:
        print("FATAL: set DC_UI_TOKEN in .env (shared secret for the iOS app)",
              flush=True)
        raise SystemExit(1)
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[dragoncakes-ui] listening on 127.0.0.1:{PORT} "
          f"model={core.MODEL} token=***", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
