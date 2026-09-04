# P3 AUDIT — Secret Hygiene (R-SEC) + R-UI Script Enablement

**Spec:** PHOS-SPEC-001 (§5.1 R-UI, §5.4 R-SEC-1..4, §9 acceptance)
**Scope:** `agent_core.py` (redact/save + UI addendum), `app-shell.html` (token handling, native proxy), `ShellView.swift` (phosphorApi proxy, configJS, phosphorConfig), `server.py` (pipeline only — R-GATE excluded per assignment).
**Method:** static read of all four files + dynamic verification of `save_session` and `redact_secrets` against the live module (findings marked **[verified]**).

## Verification summary by requirement

| Req | Status | Notes |
|---|---|---|
| R-UI-1 (no script stripping) | PASS | `server.py:41-48` `sanitize_screen_html` is a true passthrough; dead regexes remain (L4) |
| R-UI-2 (JS enabled) | PASS | WKWebView default; nothing disables it |
| R-UI-3 (on*= / javascript: allowed) | PASS | No stripping anywhere in pipeline; `split_reply` returns raw inner HTML |
| R-UI-4 (no secrets to page JS) | PASS w/ caveat | `configJS` no longer injects PH_TOKEN (ShellView.swift:94-100); caveat M7 (stale localStorage token readable by generated-screen JS) |
| R-SEC-1 (tokens unreadable from page JS) | PARTIAL | No injection path found; M6 (empty token posted to /reset) and M7 caveat |
| R-SEC-2 (native proxy, no page-global token) | PARTIAL | Proxy implemented correctly for `/message`; `/reset` bypasses it (M6); page stuck on setup screen (H1) |
| R-SEC-3 (secret-file read gating) | PASS w/ drift | Hard-block instead of spec's approval flow; `.envrc` missed (L6) |
| R-SEC-4 (save-time redaction) | FAIL | Redaction code never reaches disk because `save_session` drops the key assignment (H2); regex has destructive false positives (M1); `dcui_` tokens not covered (M2); Telegram path unredacted (M3) |

---

## HIGH

### H1 — Native app permanently stuck on setup screen; send/reply flow unreachable **[verified by code-path analysis]**
- **File:** `phosphor/ios-app/app-shell.html:285` (`needsSetup()`), with `:140-148` (CONFIG) and `:289-292` (native setup branch).
- The R-SEC-2 change removed `PH_TOKEN` injection, so on iOS `CONFIG.token` is **always `''`** (the localStorage fallback at `:144-145` is explicitly disabled when the `phosphorApi` handler exists). `needsSetup()` is `return !CONFIG.token` → always true in the native app → `boot()` (`:337`) always routes to `renderSetup()`, whose native branch renders "No configuration — Restart the app". `send()` is unreachable; the app cannot work at all. The page cannot distinguish "configured natively" from "unconfigured" because its only configured-state signal was the token it is no longer allowed to see.
- **Fix:** `function needsSetup() { return !CONFIG.token && !(window.webkit?.messageHandlers?.phosphorApi); }` (native handler present ⇒ configured natively).

### H2 — `save_session` never persists any session; redaction (R-SEC-4) is dead code **[verified live]**
- **File:** `dragoncakes/agent_core.py:558-575`.
- The function builds redacted `history` but **never assigns it into `data`** — the `data[str(key)] = history` line was dropped during the redaction edit, so the file is always rewritten as `{}`. Verified by importing the real module and calling `save_session`: the session file stays `{}` across multiple saves, `load_session` always returns `[]`. Every conversation is amnesiac after each turn (both front-ends share this path via `agent_turn`). Side effect: R-SEC-4 is vacuously "satisfied" — nothing persists, so nothing secret persists either.
- **Fix:** add `data[str(key)] = history` after the redaction list-comprehension (line 569).

---

## MEDIUM

### M1 — Redaction regex corrupts normal content: hashes, base64 images, long URLs **[verified live]**
- **File:** `dragoncakes/agent_core.py:544-551` (`_SECRET_RE`).
- Verified false positives when run against the real `redact_secrets()`:
  - `checksum is d41d8cd9...8427e ok` → `checksum is [REDACTED] ok` (any 32–64 hex string: md5/sha, git SHAs)
  - `data:image/png;base64,iVBORw0KGgo...` → `data:image/png;base64,[REDACTED]` (the generic base64 alternative) — multi-turn iteration on an inline-image screen feeds the model corrupted context
  - `https://example.com/download/AbCdEf123.../file` → `https://example.[REDACTED]` (`/` is in the `[A-Za-z0-9+/]` class, so it eats through URL paths)
- Damage is bounded (only persisted history → next-turn context), hence MEDIUM, not HIGH.
- **Fix:** drop or heavily constrain the generic hex and base64 alternatives (require a `sk-`/`key=`/`Authorization` context anchor or ≥50 chars with no `/`, and exempt `data:` URIs).

### M2 — `DC_UI_TOKEN` itself is not redacted
- **Files:** `dragoncakes/agent_core.py:544-551`; placeholder format `dcui_…` at `phosphor/ios-app/app-shell.html:303`.
- The deployment's own auth token (`dcui_…`, per the setup placeholder) matches none of the alternatives, so a token echoed into a persisted reply is stored verbatim — the one secret R-SEC-4 most directly targets is the one pattern misses.
- **Fix:** add `(dcui_[0-9A-Za-z_-]{8,})` to `_SECRET_RE`.

### M3 — R-SEC-4 drift: Telegram front-end saves history unredacted
- **File:** `dragoncakes/telegram_agent.py` (own `save_session`, no `redact_secrets`; own `agent_turn` loop calling it at `save_session(chat_id, history)`).
- Spec §12.4 requires all rules to apply identically to both front-ends. Tool results are not persisted by either loop (only user + final assistant reply), but on the Telegram path the assistant reply is persisted with no redaction at all — while `agent_core.save_session` (unused by Telegram) has the (broken) redaction.
- **Fix:** delete the Telegram-local `save_session` and route persistence through `agent_core.save_session`/`redact_secrets` (after fixing H2).

### M4 — Native proxy interpolates the raw response body into JS unvalidated
- **File:** `phosphor/ios/Phosphor/ShellView.swift:232-238`.
- `json = s` accepts any server body (e.g. a Cloudflare/tunnel 502 HTML page) and interpolates it into `window.__phApiResolve(\(json))`. Non-JSON body ⇒ JS syntax error ⇒ `evaluateJavaScript` fails silently ⇒ the page promise never settles until the 120 s timeout (app-shell.html:226). No HTTP-status check either.
- **Fix:** in Swift, `JSONSerialization.jsonObject` the body, re-serialize with `.sortedKeys`/`.fragmentsAllowed`, and on failure resolve `{"ok":false,"__error":"invalid server response (HTTP \(code))"}`.

### M5 — Shared `window.__phApiResolve` allows cross-request reply contamination
- **Files:** `phosphor/ios-app/app-shell.html:223-227`; `ShellView.swift:238,240`.
- One global resolver slot. After a timeout rejection (`:226`) the native request is still in flight; `state.busy` is reset in `finally`, the user retries, the new `send` overwrites `__phApiResolve`, and the stale first reply resolves the **second** request with the wrong data. The resolver is also never cleared on success/failure.
- **Fix:** tag each request with a nonce (`{req: id, ...}` echoed by native, `__phApiResolve(id, data)`) or null the resolver in the timeout handler and have native check for it.

### M6 — `clearSession()` bypasses the native proxy and can never succeed in-app
- **File:** `phosphor/ios-app/app-shell.html:321-330`.
- `/reset` is posted with `key: CONFIG.token`, which is `''` on iOS → server `check_auth` (server.py:66-72) returns 401 → the server session is never cleared, yet the UI shows "session cleared". Inconsistent with R-SEC-2/R-BRIDGE-2 ("server requests initiated by page JS are proxied through the native bridge").
- **Fix:** extend `phosphorApi` (or add `phosphorReset`) so `/reset` also goes through the native token-attached path.

### M7 — Stale pre-spec `ph:token` left in WKWebView localStorage, readable by generated-screen JS
- **Files:** `ShellView.swift:46` (`websiteDataStore = .default()`), `app-shell.html:140-148` (guard only affects app-shell's own read), and no `removeItem` anywhere in `configJS` (`ShellView.swift:97-100`).
- Installs upgraded from the pre-spec build still carry the token in `localStorage["ph:token"]` for the `file://` origin. Generated screens execute same-origin (R-UI enables their JS by design) and can call `localStorage.getItem('ph:token')` directly — app-shell's own guard does not protect them. R-SEC-1 acceptance (§9: "token absent from page-global scope") would pass while the token remains one `localStorage` read away.
- **Fix:** in `configJS`, add `try { localStorage.removeItem("ph:token"); } catch (e) {}`.

---

## LOW

### L1 — Error-string escaping in the proxy is incomplete
- **File:** `ShellView.swift:236` — replaces `"` with `'` but not backslashes; an error description ending in `\` yields an escaped quote and a JS syntax error (same silent-hang class as M4).
- **Fix:** build the error payload with `JSONSerialization` instead of string surgery.

### L2 — `dismantleUIView` misses the `phosphorApi` handler
- **File:** `ShellView.swift:179-184` — removes NFC/Config/Mic but not `phosphorApi`, leaking the script-message handler (strong coordinator ref) on teardown.
- **Fix:** add `removeScriptMessageHandler(forName: "phosphorApi")`.

### L3 — `configJS` escapes backslash/newline in `PH_SERVER` but not `"`
- **File:** `ShellView.swift:91-100` — a server string containing `"` (settable via `phosphorConfig` from page JS, ShellView.swift:249) breaks out of the JS string literal at document start.
- **Fix:** `JSONEncoder`-encode the value: `window.PH_SERVER = \("\"\(serverJSON)\";")` style, i.e. interpolate a JSON-quoted literal.

### L4 — Dead sanitizer regexes left behind
- **File:** `server.py:36-38` — `SCRIPT_RE`, `EVENT_ATTR_RE`, `JAVASCRIPT_URL_RE` are unused after the passthrough change; they invite someone to "re-enable" them.
- **Fix:** delete.

### L5 — Transcript fallback exposes raw JS source
- **File:** `server.py:216-221` — when a screen exists but has no trailing commentary, `"text"` falls back to `strip_tags(reply)`, which keeps `<script>` *contents* as visible transcript text; `SCREEN_RE` (`server.py:35`) is greedy, so two `ph-screen` blocks merge with everything between them.
- **Fix:** fall back to `strip_tags` only when `screen is None`; use a non-greedy/first-block regex.

### L6 — R-SEC-3 drift: hard block instead of approval, minor pattern gap
- **File:** `dragoncakes/agent_core.py:446-450` — spec R-SEC-3 says secret paths are DESTRUCTIVE-READ *requiring approval*; the code hard-denies. Stricter, but a drift (and the denial text tells the model to ask the user for the value, which lands it in chat unredacted since M2). `\.env\.` misses `.envrc`/`envrc`.
- **Fix:** either route through the §8 approval flow or amend the spec; extend the regex to `\.envrc\b`.

### L7 — `save_session` exception handler too narrow
- **File:** `dragoncakes/agent_core.py:574` — catches only `OSError`; a corrupt `telegram_sessions.json` raises uncaught `json.JSONDecodeError` (a `ValueError`) mid-turn. `load_session` (`:538`) already catches it — asymmetric.
- **Fix:** `except (OSError, json.JSONDecodeError)`.

### L8 — Desktop harness token in localStorage is by-design but unguarded against regression
- **Files:** `app-shell.html:143-145, 311-314` — acceptable for the desktop dev harness per threat model, but nothing (comment, assert, or build flag) stops a future edit from dropping the `!native` guard and reintroducing the leak the spec removed.
- **Fix:** add a comment referencing R-SEC-2 at both sites (or gate the desktop fallback behind an explicit `?desktop` flag).

---

## Explicitly checked and found clean
- `sanitize_screen_html` is a true passthrough; nothing in `split_reply`, `strip_tags`, or the `/message` handler strips or rewrites `<script>` content delivered to `setScreen` (R-UI-1/3 regression risk: none in the screen path — L5 affects only the transcript side-channel).
- `UI_PROMPT_ADDENDUM` (agent_core.py:78-87) explicitly enables `<script>` and `on*` handlers and forbids obfuscation/external JS (R-UI-5 satisfied).
- No `PH_TOKEN` injection remains in `configJS`; the unused `token` local at ShellView.swift:96 is dead but harmless.
- `send()`'s native path posts no credential; the token is attached natively (ShellView.swift:217) and never placed in page scope; error messages ("bad request body", "bad server url", "network error") contain no secret material.
- The `phosphorConfig` save path writes the token only to UserDefaults, never back to the page; the in-app setup screen never renders a token input.
- `dbg()` logging emits only `tokenSet=<bool>`, never the token.
- Tool results never reach `save_session` in either front-end's history (only user + final assistant reply are appended), so the R-SEC-4 "tool results" clause has no disk path today — but see H2/M3: after H2 is fixed, only the reply path is covered, which is the correct scope.
- Redaction correctly leaves short hex strings, normal prose, and typical URLs untouched (only ≥32-hex / ≥40-base64-ish runs are hit — see M1 for the damage boundary).
