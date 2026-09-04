# P4 Audit — JavaScript in LLM-generated screens (R-UI-1..5)

**Scope:** PHOS-SPEC-001 §5.1 + §9 (R-UI rows) only. Prior R-QUAR / R-GATE / R-SEC audits not revisited.
**Files:** `dragoncakes/server.py` (sanitize passthrough, SCREEN_RE/split_reply/strip_tags, /message text path), `dragoncakes/agent_core.py` (UI_PROMPT_ADDENDUM), `phosphor/ios-app/app-shell.html` (setScreen, phosphor.approvalResult, shared scope). Supporting evidence read from `phosphor/ios/Phosphor/ShellView.swift` for runtime context only.
**Date:** 2026-09-03. No files modified; no services touched.

---

## Compliance summary (R-UI-1..5)

| Req | Status | Evidence |
|---|---|---|
| R-UI-1 (MUST: don't strip `<script>`) | **PASS** | `sanitize_screen_html()` is a pure passthrough (server.py:39-46); old stripping regexes removed (comment :36). Only caller is `split_reply` (:54). No other sanitizer remains in the /message path. |
| R-UI-2 (MUST: JS enabled in WKWebView) | **PASS** | ShellView creates a plain WKWebView; no JS disabling anywhere. |
| R-UI-3 (MUST: `on*=` + `javascript:` allowed) | **PASS** | Passthrough preserves everything; innerHTML keeps `on*` attributes live; `javascript:` URLs unaffected. |
| R-UI-4 (MUST NOT: secrets to screen JS) | **PASS (in-app)** | `CONFIG.token` resolves to `''` in-app (ShellView.swift:94-101 removes `ph:token`; app-shell.html:143-145 localStorage fallback gated on absent `phosphorApi`). Desktop legacy path is spec-accepted. See L3 for residual shared-scope risk. |
| R-UI-5 (SHOULD: steer to maintainable JS) | **PASS** | UI_PROMPT_ADDENDUM (agent_core.py:78-87): JS "allowed and encouraged", "no external JS libraries, no obfuscation", "short and readable". |

The core mechanism is correct: `setScreen()` (app-shell.html:170-192) re-creates `<script>` nodes after innerHTML (which does not execute scripts), so generated screen JS runs. The findings below are defects in and around that mechanism.

---

## HIGH

### H1 — `setScreen()` resurrects `<script src>` to arbitrary origins; no subresource allowlist exists
**File:** app-shell.html:181-190; interaction with ShellView.swift:328-369.

The re-execution loop explicitly supports external scripts:
```js
if (oldScript.src) { s2.src = oldScript.src; }
```
Two facts combine badly:

1. The navigation policy in ShellView (`decidePolicyFor navigationAction`, allowlist: about/blob/file, server host, fonts.googleapis.com/gstatic; everything else `.cancel`) only governs **navigations**. WKWebView does **not** route subresource loads (classic `<script src>`, img, XHR) through that delegate — so a `<script src="https://evil.example/x.js">` inside a generated screen is fetched and executed despite the allowlist. Classic scripts are not CORS-gated, and the page origin is `file://`.
2. There is no content check on the server either — `sanitize_screen_html()` is a deliberate passthrough (correct per R-UI-1), so nothing anywhere enforces the prompt's "NO external JS libraries" rule.

Consequence: a single `<script src>` emitted by the model — including one steered by quarantined-content injection (adversary A1, rated HIGH likelihood in §4.2, whose only mitigation chain is R-QUAR → model judgment, i.e. prompt vs prompt) — executes attacker-controlled code in the shell's window with full access to `CONFIG`, `state`, `send()`, `window.phosphor.*`, and the native `phosphorApi` proxy (i.e. the ability to drive the agent). R-UI-5 is only a SHOULD and is the sole control here; the shell's loader path *actively enables* the violation rather than merely permitting it.

**Recommendation:** in `setScreen()`, refuse or drop `src`-carrying scripts (or restrict `s2.src` to the same allowlisted hosts as the nav policy); keep inline scripts. This preserves R-UI-1/3 (the prompt-mandated authoring style is inline `<script>` + `on*=`) while closing the remote-code path. One-line deny-and-log is enough for a single-user device.

---

## MEDIUM

### M1 — `window.phosphor.approvalResult` assigned before `window.phosphor` exists; shell survival depends on an out-of-file injection ordering
**File:** app-shell.html:275 vs :281.

```js
window.phosphor.approvalResult = function (...) {...};   // :275
...
window.phosphor = window.phosphor || {};                 // :281
```
Lines 275-278 execute before the object is created. This works **only** because ShellView's `WKUserScript` at `.atDocumentStart` (ShellView.swift:77) pre-creates `window.phosphor` before the page script runs. In any context without that userscript — the desktop/browser harness loading this file, or any future regression in the userscript — line 275 throws `TypeError: Cannot set property of undefined`, aborting the remainder of the single `<script>` block: `micToggle`, `voice*`, `sendFromVoice`, `openURL`, `needsSetup`, `renderSetup`, `clearSession`, the `#mic`/`#clear`/`#settings` bindings, **and the `boot()` call (:439) never execute** → the app hangs on the splash/"CONNECTING" screen with no error visible to the user.

**Recommendation:** move `window.phosphor = window.phosphor || {}` above line 275 (or use optional assignment). Trivial fix, currently masked by a cross-file ordering invariant that nothing documents.

### M2 — Screens are appended and scripts run in shared global scope; `let/const/class` redeclaration breaks interactivity from the second turn onward
**Files:** app-shell.html:170-192 (`setScreen(html, append)`; `send()` always uses `append=true`, :256-257), agent_core.py UI_PROMPT_ADDENDUM (no IIFE/unique-namespace guidance).

Every generated screen's inline script executes as a **classic global script** in the same window, and previous screens are never removed (append mode keeps old wrappers and their live scripts/handlers in the DOM). Typical model output declares top-level helpers (`const btn = ...`, `let count = 0`, `function update(){}` — note top-level `function` redeclaration is silently allowed, masking the pattern). On the next turn, a redeclaration of any `let`/`const`/`class` name from a prior screen throws `SyntaxError: Identifier ... has already been declared`, and that screen's interactivity is dead with no visible error (script errors don't surface in the UI). Common names (`count`, `items`, `update`, `state` — note the shell itself owns global `state` and `send` and `$`) make collisions likely, not rare. Additionally, a generated screen that assigns `state`/`send`/`$`/`CONFIG` clobbers the shell's own bindings.

**Recommendation:** either (a) wrap each resurrected inline script in an IIFE (`s2.textContent = '(function(){' + src + '}())'` — preserves behavior, kills collisions), or (b) add one line to UI_PROMPT_ADDENDUM requiring an IIFE wrapper / discouraging top-level declarations. (a) is technical and prompt-independent.

### M3 — Script re-creation drops `type`/module semantics: module screens and data blocks break
**File:** app-shell.html:181-190.

The clone copies only `src` or `textContent`. A generated screen using `<script type="module">` (valid modern authoring; `import` statements, top-level await) is resurrected as a **classic** script → immediate `SyntaxError` on `import`, silently dead interactivity. Same for `<script type="importmap">` (becomes executed JS garbage) and `<script type="application/json">` data islands. Since R-UI's goal is "interactivity the moment requires," the mechanism silently rejects a legitimate JS authoring style the model may choose.

**Recommendation:** copy `type` (and `async`) when re-creating; or explicitly instruct the model in UI_PROMPT_ADDENDUM to use classic scripts only. Either closes the gap; copying `type` is the robust one.

---

## LOW

### L1 — Screen-only replies leak raw JS source into the transcript `text` field
**File:** server.py:217 (with :49-56, :59-61).

`"text": (text if (screen and text) else strip_tags(reply))` — the prompt makes post-screen commentary *optional* (agent_core.py:86), so screen-only replies are the common case. Then `strip_tags(reply)` runs over the whole reply including `<ph-screen>` content: it removes the tags but keeps the **JavaScript source text** as visible text, so `text` returned to the client is a garbled blob of JS. No XSS (the shell only uses `text` when `html` is falsy, and escapes it), but any consumer of the `text`/transcript field (logs, future front-ends) gets code as prose. Fix: when a screen is present, derive `text` only from outside the screen tags (even if empty).

### L2 — Multi-`<ph-screen>` replies: second screen's raw HTML (incl. scripts) lands in `text`
**File:** server.py:35, :49-56.

`SCREEN_RE` is non-greedy and captures only the **first** block; `text = before + " " + after` where `after` still contains any second `<ph-screen>...</ph-screen>` block verbatim. With a screen present and text non-empty, that raw HTML (including `<script>` blocks) is returned as `text`. Same benign-in-current-client / ugly-in-transcript impact as L1. Consider `re.sub`-ing all screen blocks out of `text`, or warning on multiple blocks.

### L3 — Generated JS can override shell globals the native side calls, including the approval transcript
**Files:** app-shell.html:275-278, :239; ShellView.swift:242-247.

Generated screens share scope with `window.phosphor`, so a screen can replace `window.phosphor.approvalResult` and `window.__phApiResolve`. The native side invokes approvalResult with optional chaining and no identity check, so an overridden version controls what the user *sees* as approval output ("Approved — exit 0 …" fabricated arbitrarily). The actual approve/deny/execute decision is native (per §12.2's rationale), so this is spoofing of the transcript only — but it directly undercuts the stated intent that page content cannot spoof approval UI. Similarly an overridden `__phApiResolve` could capture later native-proxy responses (agent replies, pending-approval metadata — no token, R-SEC-2 holds). Low severity given the trust model, but cheap to harden: capture `approvalResult`/`__phApiResolve` in a closure at document-start (native side already runs first) instead of reading mutable globals.

### L4 — Dead/incorrect `document.currentScript` branch in `setScreen()`
**File:** app-shell.html:188-189.

`document.currentScript ? document.currentScript.replaceWith(s2) : oldScript.replaceWith(s2)` — `currentScript` is non-null only during initial evaluation of the shell's own script tag, which never calls `setScreen()`; in every real call path it is null, so the fallback always runs. If the branch ever *did* trigger, it would replace the **shell's own main script element** with the screen's script — removing the shell's script node from the DOM. Dead code with a harmful-if-alive semantics; delete the branch or invert the comment so a future refactor doesn't "fix" it into the active path.

---

## Verified non-issues (checked, no finding)

- **innerHTML script re-execution order:** inline scripts are replaced in DOM order synchronously — execution order within a screen is preserved.
- **Script errors can't take down the shell:** errors in resurrected scripts report to `window.onerror`, not into `setScreen()`'s stack; the shell survives hostile/broken screen JS (contrast M1, which is a *shell-authored* ordering bug).
- **`on*=` attributes and `javascript:` URLs survive end-to-end** (passthrough sanitizer → innerHTML): R-UI-3 satisfied, including the `tel:`/`sms:`/`mailto:`/`facetime:` handoff in ShellView:340-349.
- **UI_PROMPT_ADDENDUM vs R-UI-5:** covers interactivity, readability, no obfuscation, no external JS libs. Compliant (note: it does not mention IIFE/namespace hygiene — see M2 — nor that screens share the shell's window; both would be reasonable one-line additions).
- **R-UI-4 in-app:** token absent from page scope (`CONFIG.token === ''`, stale `ph:token` purged at document start); §9's R-UI-4/R-SEC-2 grep checks should pass.
- **`esc()` discipline in shell-authored HTML paths** (user bubbles, errors, approval result): consistent; no shell-side XSS via its own strings found.
