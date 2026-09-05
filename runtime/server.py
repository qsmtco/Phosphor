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
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import agent_core as core

HERE = os.path.dirname(os.path.abspath(__file__))
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
