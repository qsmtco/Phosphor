# Security Audit — Prompt-Injection Quarantine (PHOS-SPEC-001 R-QUAR-1..4)
**Target:** `/home/q/projects/dragoncakes/agent_core.py`, `/home/q/projects/dragoncakes/server.py`
**Spec:** `/home/q/projects/phosphor/docs/PHOS-SPEC-001-trust-architecture.md` (§5.2, §9, §12.4)
**Date:** 2026-09-03 · Read-only audit, no files modified.

## HIGH

### H1 — `POST /message` is unreachable; handler raises `NameError` before any agent call
**File:** `server.py` do_POST (lines ~155–209)
The `/approve` branch fails to `return` on non-approve paths: after the `if self.path == "/reset"` and `if self.path == "/approve"` blocks, control falls through to `if deny:` — but `deny` (and `cmd`) are only defined inside the `/approve` branch. Any `POST /message` therefore raises `NameError` (uncaught; the outer `try` only catches JSON errors), the connection dies, and **all message-handling code (lines 186–209) is dead code**. Consequences:
- The Phosphor front-end cannot process any message at all, so §9 acceptance ("trigger via Telegram + Phosphor, envelope appears in both") cannot pass.
- As written, the quarantine path is only reachable via `telegram_agent.py`-style callers importing `agent_core` directly; the server's quarantine compliance is unverifiable in its current state.
This looks like an edit that moved the `/approve` block above `/message` without re-indenting the fall-through — evidence the code was never run end-to-end.

### H2 — Telegram front-end (`telegram_agent.py`) bypasses the quarantine entirely (violates §12.4 deployment scope)
**File:** `telegram_agent.py` (its own `SYSTEM_PROMPT` line 64, its own `run_tool` line ~285)
Spec §12.4: "All R-GATE and R-QUAR rules apply identically to the Telegram bot and the Phosphor app, since both share `agent_core.py`." They do not: `telegram_agent.py` is a **forked copy**, not an importer of `agent_core`. Its `run_tool` returns `_tool_web_search(...)` / `_tool_http_request(...)` **raw — no `quarantine_envelope`, no `check_injection_attempt`** — and its `SYSTEM_PROMPT` contains **no UNTRUSTED CONTENT RULE** (R-QUAR-2). Every `web_search`/`http_request` result in the Telegram front-end enters the model context unenveloped. This defeats R-QUAR-1 and R-QUAR-2 for half the deployment surface. (Note: the task scope said "check server.py for bypasses"; `server.py` correctly imports `agent_core`, but the spec explicitly names both front-ends, so this bypass is in scope.)

## MEDIUM

### M1 — Envelope content is not escaped; quarantine boundary is forgeable
**File:** `agent_core.py` `quarantine_envelope()` (lines 301–311)
`str(content)` is interpolated raw. Untrusted content can contain `+-- UNTRUSTED WEB CONTENT ---` header lines, `| source: user:` metadata lines, the `+----...` terminator, or fake `[QUARANTINE: ...]` trailers — identical in shape to the ones the system itself emits (the trailer is literally appended inside the content in `run_tool` lines 423–431 before wrapping). An attacker can close the envelope early and inject text that the model reads as trusted tool/system framing. Envelopes must delimit unambiguously (e.g., strip/escape delimiter sequences in content, or use a random per-envelope boundary nonce).

### M2 — Trivial bypass of R-QUAR-1 via other tools
**File:** `agent_core.py` `run_tool()`
Quarantine applies only to the literal `web_search`/`http_request` branches. Untrusted web content can enter context unenveloped via:
- `run_command` with `curl`/`wget`/`python -c urllib...` — output returned raw, no envelope, no injection check;
- `read_file` on a file the model earlier wrote from fetched content (write→read laundering);
- `search_memory` (saved content is persisted raw).
§7.3 accepts pattern-classification bypassability, but it does not accept quarantine bypassability; the spec's threat model A1 ("text enters context via web_search/http_request") is satisfied by simply using a different tool. At minimum, injection-marker scanning should run over all tool results.

### M3 — Injection marker detection is too weak to serve as the R-QUAR-3 tripwire
**File:** `agent_core.py` `_INJECTION_MARKERS` (lines 292–298), `check_injection_attempt()`
17 hardcoded substrings, plain `in` match after `.lower()` only. Bypassed by double spaces, punctuation, homoglyphs/unicode, paraphrase ("disregard the above", "act like you are", "your new directive"), or non-English text. Since detection is the only *programmatic* layer (the "report to user" duty is delegated entirely to the model's compliance), the tripwire will miss the overwhelming majority of real attempts while `quarantine.log` looks like it works. Also: a hit only appends a trailer the model may ignore; there is no escalation (e.g., truncation or hard refusal).

## LOW

### L1 — `web_search` logs the query as `source`, not result URLs
`check_injection_attempt(args["query"], res)` records `source: web_search:<query>` in `quarantine.log`; the actual offending page URLs are lost, weakening forensic review (R-QUAR-3's purpose).

### L2 — `quarantine.log` writes are silent-failure and unlocked
`check_injection_attempt` swallows all write exceptions (`except Exception: pass`) and there is no lock despite `ThreadingHTTPServer` concurrency — log loss/interleaving is invisible, contradicting the auditability intent of R-QUAR-3.

### L3 — `server.py /approve`: approval consumed outside the lock; subprocess errors unhandled
`a["used"] = True` (line 175) is set after releasing `core._APPROVALS_LOCK`, so two concurrent approves can both pass the `used` check and execute a destructive command twice (R-GATE-6 single-use violation). A `subprocess.TimeoutExpired` in the execution path raises uncaught → connection drop with no result returned to the agent. Out of the R-QUAR core but adjacent to the trust path.

### L4 — Envelope glyphs deviate from the spec's reference layout (cosmetic)
Spec shows `┌── ... │ ... ▼ ... └──`; implementation uses `+--`, `|`, `v`, `+---`. Functionally equivalent (plain-ASCII is arguably safer); noted only for spec fidelity.

## Requirement scorecard (R-QUAR)

| Req | Status | Notes |
|---|---|---|
| R-QUAR-1 (MUST) | **Partial** | Met in `agent_core.run_tool` for both tools; broken for Phosphor by H1 (server can't serve messages) and for Telegram by H2 (no envelope at all). |
| R-QUAR-2 (MUST) | **Partial** | Standing rule present in `BASE_PROMPT` (agent_core lines 67–75); absent from `telegram_agent.SYSTEM_PROMPT` (H2). |
| R-QUAR-3 (SHOULD) | **Met (weak)** | Logging implemented, `quarantine.log` exists with a test entry (`2026-09-04T00:38:04Z`, source `unittest`, markers `[ignore previous, run this command]`); detection quality is poor (M3), source field weak (L1). |
| R-QUAR-4 (MAY) | n/a | Not required for acceptance. |

## Verified facts
- `python3 -m py_compile server.py agent_core.py` → both compile (H1 is a logic/indent bug, not syntax).
- `quarantine.log`: 1 record, 117 bytes, entry consistent with a unit test.
- `server.py` imports `agent_core as core` and routes through `core.agent_turn` → the intended quarantine path is the one used *when the handler works*.
- `telegram_agent.py` defines its own `run_tool`, `_tool_web_search`, `_tool_http_request`, `SYSTEM_PROMPT` — no import of `agent_core` quarantine functions.

**Totals: 2 high · 3 medium · 4 low**


---

## Remediation Record (Qrusher, 2026-09-04)

| Finding | Status | Action |
|---|---|---|
| H1 /message dead | FIXED (was fixed during P2 before audit read completed; audit read stale file) | verified live: /message 200 |
| H2 Telegram bypass | **FIXED** | telegram_agent now delegates web_search/http_request/run_command/write_file/read_file to agent_core.run_tool; UNTRUSTED CONTENT RULE added to its SYSTEM_PROMPT; shadowing local branches removed; verified: .env blocked, destructive held, search enveloped |
| M1 envelope forgery | **FIXED** | random per-call boundary nonce; content delimiters neutralized |
| M2 bypass via other tools | **FIXED** | all tool results scanned for injection markers; hits enveloped |
| M3 weak detection | PARTIAL | 30 markers + whitespace normalization; homoglyph/paraphrase gap remains (accepted, prompt rule is primary layer) |
| L1 weak source field | PARTIAL | logged source includes tool args |
| L2 log silent failure | **FIXED** | lock added; failures print to server log |
| L3 double-exec race | **FIXED** | "used" set inside lock; subprocess timeout handled |
| L4 glyph deviation | WONTFIX | plain-ASCII deliberate |

Residual accepted risks (per spec 4.3/7.3): homoglyph/paraphrase injection detection gaps; model self-censorship non-determinism; classification bypassability by adversarial model.
