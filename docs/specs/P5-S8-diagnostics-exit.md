# P5-S8 — Diagnostics, health checks, and the deliberate safe-boot drill (Phase 5 exit)

**Phase:** 5 · **Spec ID:** P5-S8 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **all of S1–S7.** S8 adds no new mechanism; it makes the existing ones *observable* and *repeatable*, and it is the last spec so that its checklist can reference working components. S8 is also the only spec that closes Phase 5, so it carries the exit criterion.
**Blocks:** Phase 6 (the shell's real rendering surface), which should not start until the foundation is diagnosable.
**Authority:** BUILD-PLAN Phase 5 deliverables ("Diagnostics and recovery hooks") and exit criteria ("The Pixel boots a custom Phosphor build in which the core agent foundation starts reliably as part of the operating system"); architecture §6.5 (safe boot) and its residual gap; §6.7 (audit); §7 (degradation ladder); §10.2's "Phase 5 acceptance tests named in this doc (§4.1 H1 re-run; §3 hard-restricted grant landing; R-PERF microbench) — specified, not yet run"; `docs/PROJECT-STATUS.md` §8 (operational procedures), §9 (traps).

---

## 1. Scope

1. **`phosphor-ctl`** — one diagnostics binary (module created empty in S1) exposing the foundation's health: `status`, `health`, `policy`, `ipc`, `log`, `safeboot`.
2. **`dumpsys` surface** — a registered `dumpsys phosphor` (or `dumpsys activity service PhosphorBroker` plus an `adb shell phosphor-ctl status` equivalent), so diagnosis does not require a custom protocol.
3. **Health checks** — a single deterministic pass/fail over the foundation's own signals (S4's health file, S6's bound clients, S7's channels, S3's property).
4. **The safe-boot drill procedure** — a written, ordered, reversible procedure producing the Phase 5 acceptance evidence, **explicitly gated as a device operation requiring PM approval before any step runs**.
5. **The Phase 5 exit-criterion checklist** per BUILD-PLAN, with the three architecture-named acceptance tests (§4.1 H1, §3 hard-restricted grant landing, R-PERF microbench) marked by verdict — **run or explicitly deferred with a reason**, never silently omitted.

### Non-goals

- No new privileged surface: `phosphor-ctl` is a **read-only** tool with no capability permission; if a check needs privilege, it is dropped rather than granted (a diagnostics tool that needs `READ_SMS` to diagnose is a backdoor).
- No metrics/telemetry collection, no network, no upload.
- **No device operation performed by this spec's authoring.** The drill is a *procedure*; executing it requires PM approval per operation.
- No Phase 6+ diagnostics (rendering perf, conversation quality).

---

## 2. Behaviour contract

### 2.1 `phosphor-ctl` — command surface

Read-only, no arguments beyond the subcommand, exit codes meaningful for scripting (`0` healthy, `1` degraded, `2` broken, `3` unusable-invocation).

**Domain (closed by S2 A8, asserted in A4):** `phosphor-ctl` has **no domain of its own** — it runs in the existing `shell` domain, as the invoking `adb shell` UID, because it is a read-only on-demand tool with no init service. It is a fifth *installed module*, not a fifth Phosphor process or domain, and takes no fifth AID. Every read below is therefore bounded by what `shell` can already read; a command that would need more is dropped, never granted.

| Command | Reads | Output contract |
|---|---|---|
| `status` | `sys.phosphor.safeboot`, `init.svc.phosphor_agentd`, `init.svc.phosphor_keygate`, `pidof`, broker bound-state | One line per subsystem: `NAME=STATE (detail)`. States: `ok`, `absent`, `down`, `unknown`. |
| `health` | S4's `/data/misc/phosphor/health` + the above | Machine-greppable `key=value` lines; non-zero exit if any required subsystem is not `ok`. **The single check the drill's automation uses.** |
| `policy` | `/system/etc/phosphor/risk-policy.json` + the broker's `policyVersion()` | `policy_version=`, `sha256=`, `broker_version=`, `match=true|false`. **Read-only**; never writes the artifact. |
| `ipc` | socket presence/mode; agentd `last_frame_at`; broker client count | Per-channel: `c-a=ok|down`, `c-b=…`, `c-c=…`, with the observed evidence (mode, age, count). |
| `log` | logd buffers filtered to `phosphor-*` tags | The last N lines; **redaction-preserving** (it prints what was logged, and nothing was logged that contains a payload). Never unredacts, never dumps `/data`. |
| `safeboot` | both triggers + the decision + latch | `ro.boot.phosphor.safeboot=`, `persist.phosphor.safeboot=`, `sys.phosphor.safeboot=`, `decision=normal|safe|undecided`. **Explains** the decision so an operator does not have to re-derive NEW-6. |

- **No secrets, ever.** No command reads `/data/misc/phosphor/credentials/`, `/data/misc/keystore/`, `/data/adb`, and none prints a path under them.
- **No writes** except nothing at all: `phosphor-ctl` performs zero writes (not even a log file). If a future command needs to write, it is a separate, reviewed addition.
- Robustness: every read is individual and failure-tolerant; a missing file yields `unknown`, never an exception or a stack trace at the operator.

### 2.2 `dumpsys` surface

- **Preferred:** a `dumpsys phosphor` entry via a small registered service is a framework change (`frameworks/base` service registration) and is **out of Phase 5's declared scope** (BUILD-PLAN Phase 5 does say "Add required framework interfaces and service registration" — so if it is cheap in-tree, it is in scope; if not, the fallback below is the deliverable and the reason is recorded).
- **Deliverable fallback (mandatory):** `dumpsys activity service com.phosphor.broker/.PhosphorBrokerService` prints the broker's registry summary and bound clients (S6 already supports this via `dump()`); `dumpsys package com.phosphor.shell` shows the HOME resolution; `dumpsys activity activities | grep phosphor` shows the surface. Document the **exact** command set in the completion note so "check dumpsys" is executable rather than vague.
- Decision rule: the spec is satisfied by **a documented, working dumpsys-based diagnosis path**; a `dumpsys phosphor` registration is a bonus with its own review (framework edit). Record which was delivered.

### 2.3 Health checks (what "healthy" means)

Pass requires **all** of, on a normal boot:

| # | Check | Signal |
|---|---|---|
| H1 | keygate decided | `sys.phosphor.safeboot` present and in {0,1} |
| H2 | agentd running | `init.svc.phosphor_agentd=running`, one pid, no `crashloop` marker |
| H3 | policy valid | artifact readable, `policy_version` matches the build stamp (S6's check, surfaced) |
| H4 | agentd's own view healthy | `/data/misc/phosphor/health` fresh (`started_at` matches pid's start, `policy_version` non-empty) |
| H5 | C-A up | socket exists `0600`, `last_frame_at` younger than the heartbeat interval |
| H6 | broker bound | ≥1 bound client on `phosphor_shell`; `ping()` answered |
| H7 | shell is the surface | resolved HOME is `com.phosphor.shell`, activity resumed |
| H8 | no denials | `logcat -b all -d \| grep 'avc: *denied' \| grep phosphor` → empty |

`phosphor-ctl health` returns `0` iff H1–H8 all pass, and prints the failing check(s) by name otherwise. **H7 is app-layer**; if the ctl binary cannot read the resolved HOME without privilege, it is allowed to print `shell=unknown` and the drill records H7 from `dumpsys` — the check is not dropped, only sourced elsewhere.

On a safe boot, the healthy signature is **inverted** and must be stated explicitly so a correct safe boot is not diagnosed as broken: `sys.phosphor.safeboot=1`, agentd **absent**, broker **absent**, shell **not the surface**, stock launcher resumed, H3–H6 `absent` **by design**. `phosphor-ctl safeboot` prints `decision=safe` and the reasons.

### 2.4 The safe-boot drill (design only — **requires PM approval before any device operation**)

**This is the operative gate. The procedure below is a document. Executing any step marked ⚠ is a device operation and requires explicit PM approval for that operation, obtained before execution. No agent may run these steps on its own authority.**

Preconditions (each verified, none assumed):
1. Recovery ladder available and rehearsed (`docs/PROJECT-STATUS.md` §8): USB port proven by the three transitions; `sudo systemctl stop fwupd.service`; know that a rung-2 reflash **wipes**.
2. The acceptance build is a **signed release** or a known dev image whose provenance is recorded (never "some build").
3. A baseline capture from the *normal* boot exists (the H1–H8 evidence), so the drill has something to compare against.
4. The device's current state is on record (build fingerprint, slot, `ro.boot.vbmeta.digest`).

Drill steps:

| # | Step | Gate |
|---|---|---|
| D1 | Capture normal-boot evidence: `phosphor-ctl health` = 0, plus screenshots (shell is HOME). | in-session, no reboot |
| D2 | Capture the **H1 re-run** on this boot: inject the hostile screen (§4.1's test) and confirm block + inline-script-executes + no egress. | in-session |
| D3 | Set the latch **as the host**: `adb shell setprop persist.phosphor.safeboot 1`; confirm `getprop` reads `1`. This step is only meaningful because S2 §3.3 grants `set_prop(shell, phosphor_safeboot_latch_prop)` — an `avc: denied … phosphor_safeboot_latch_prop` in `logcat -b all -d` here is **S2's defect, not a drill failure**: stop, file it against S2 A5 (its "functional proof the writer is real" bullet), do not retry with `su`. | ⚠ **PM approval** (write to device state) |
| D4 | Reboot. | ⚠ **PM approval** |
| D5 | After boot: `phosphor-ctl safeboot` → `decision=safe` with reasons; `phosphor-ctl health` → the **safe-boot signature**; screenshot = stock launcher; `init.svc.phosphor_agentd` absent; broker absent. | in-session |
| D6 | Prove Settings + phone are usable (§6.5: "launcher + Settings + no agent"; §7: "the stock Dialer is usable during dev"). | in-session |
| D7 | Clear the latch **as the host** (`persist.phosphor.safeboot` → `0` or the documented clear form from S3 open item 3); reboot. | ⚠ **PM approval** ×2 |
| D8 | After boot: `phosphor-ctl health` = 0 again, shell is HOME. Confirms the drill is **reversible**. | in-session |
| D9 | Record: each step's command, output, timestamp, screenshot; the approval for D3/D4/D7 referenced by its text. | — |

**Reversibility is the point.** A drill that ends in a state the operator cannot leave is not a drill; D7/D8 exist to prove the exit. **Stop rules (any one halts the drill, no improvisation):** device does not return to adb after a reboot ⇒ recovery ladder, PM informed; `phosphor-ctl safeboot` reports `undecided` on the *normal* boot ⇒ **stop, this is a defect** (fail-closed worked, but the normal path is broken); any avc denial attributable to Phosphor ⇒ stop and file.

**What the drill must NOT do:** rely on `ro.boot.phosphor.safeboot` (kernel-cmdline) as the *only* demonstrated trigger — the latch path is demonstrated above because it needs no bootloader interaction; the `ro.boot` path is S3 A3's separate approval and, if not approved, is recorded as **not demonstrated** with the reason. Do not claim REC-2 fully proven from the latch alone: state which trigger was exercised. (§6.5's residual gap is exactly this honesty.)

### 2.5 The Phase 5 exit-criterion checklist (BUILD-PLAN)

BUILD-PLAN Phase 5's exit criterion: *"The Pixel boots a custom Phosphor build in which the core agent foundation starts reliably as part of the operating system."* Decomposed into verifiable rows, each with its owning spec:

| # | Row | Owner | Verdict required |
|---|---|---|---|
| E1 | The image builds from an unchanged recipe | S1 A2 | PASS + step count |
| E2 | All five modules are in the image | S1 A3 | PASS |
| E3 | sepolicy compiles, neverallows intact | S2 A1–A5 | PASS |
| E4 | Boot decision taken, fail-closed both ways | S3 A1/A2/A4 | PASS |
| E5 | Agent foundation **starts reliably** — the literal exit criterion | S4 A1/A4 (+ ≥5 consecutive normal boots, zero crash-loops) | PASS. **"Reliably" is quantified here as 5/5 boots and 3/3 kill-restarts**; the completion note says so, so the word is not left to opinion. |
| E6 | Shell is the surface on normal boot | S5 A1 | PASS |
| E7 | Safe boot lands on the stock launcher | S5 A2 | PASS |
| E8 | Broker binds; card renders with shell dead | S6 A1/A2, **exercised via S7 §2.2's client** (S6 depends on S7) | PASS |
| E9 | Channels round-trip and deny outsiders | S7 A1/A3 | PASS |
| E10 | Diagnostics reproducible by a second person | S8 §2.3, run twice, by a different operator if available | PASS |
| E11 | **§4.1 H1 re-run** (architecture-named) | S5 A5 | PASS, or DEFERRED with reason — **not omitted** |
| E12 | **§3 hard-restricted grant landing** (architecture-named) | Phase 9 (SMS/contacts not implemented in Phase 5) | **DEFERRED with reason** — the capability does not exist yet, so the grant cannot be exercised; the deliverable (allowlist entry) is Phase 9's. Recording this is mandatory; claiming it is not. |
| E13 | **R-PERF microbench** (architecture-named) | Phase 8 (classifier) / Phase 13 (final) | **DEFERRED with reason** — no classifier in Phase 5, so there is nothing to benchmark; the ≤5 ms/≤1 ms/±10% targets are unchanged and unattributed to Phase 5. |
| E14 | Drift check: the built tree matches the documented architecture | S8 | PASS — any place where implementation and §2.1/§6.5/§8 disagree is listed, with which one wins and why |

**E14 is the spec's real value.** Phase 5 is the first phase where design meets a build; the exit note must list every divergence found (property naming, init event choice, AID spelling, frame limits, card host mechanics) so Phase 6 inherits facts, not assumptions.

### 2.6 Evidence discipline

- Every claim in the exit note carries a command and its output (or a screenshot's filename). `docs/PROJECT-STATUS.md` §8: "do not trust 'it boots'" — the same discipline applies to every row here.
- Failures are **reported, not retried into passing**. A row that cannot be met is a finding with an owner, and the phase's status is "complete except <row>", never a silent pass.
- No row is satisfied by an assertion about code; each needs an observed signal.

---

## 3. Implementation location

| Artifact | Path |
|---|---|
| ctl binary | `<tree>/packages/phosphor/services/PhosphorDiagnostics/main.cpp` (module from S1) |
| Health-check logic | `…/checks.cpp` (+ `checks.h`), one function per H-row |
| Broker dump | `<tree>/packages/phosphor/apps/PhosphorBroker/…/PhosphorBrokerService.java` `dump()` (S6 hosts it) |
| Drill procedure | `<tree>/docs/specs/P5-S8-drill-runbook.md` — **created only if the PM wants the runbook separated from the spec**; otherwise §2.4 of this file *is* the runbook |
| Exit note | `docs/PHASE-5-EXIT.md` (new, at drill completion — not part of this spec's authoring) |
| Evidence | `docs/evidence/phase5-*/` (screenshots, `phosphor-ctl` outputs, logcat captures) |

---

## 4. Acceptance criteria

**A1 — `phosphor-ctl` exists, is read-only, and every subcommand works on a normal boot.** All six subcommands run without error; `health` exits 0 with H1–H8 pass; no command writes anything (verify by `strace`-free means: no file opened for write in the source, and `git status` on the device root unchanged across runs is not observable — so the static check stands and is stated as static).

**A2 — Health check is honest in both directions.** On the normal boot, `health` = 0. On the safe-boot drill boot (D5), `health` prints the **safe-boot signature** and does **not** report a false failure; the two modes are distinguishable in one command.

**A3 — Diagnosis path documented and reproduced.** The completion note's dumpsys/ctl command set is run **twice**, and the second run (ideally by a different operator) reaches the same conclusions without asking the author. If no second operator is available, that is recorded as a limitation.

**A4 — No secrets, no privilege.** Static: `rg -n 'READ_|ACCESS_|CAMERA|RECORD|keystore|credentials' packages/phosphor/services/PhosphorDiagnostics` → no permission declaration, no secret path; `Android.bp` declares no `uses-permission` (it is a binary, so this is structural). **Domain: `phosphor-ctl` runs in the existing `shell` domain and has no Phosphor domain of its own** — this is S2 A8's decision (fifth *module*, not a fifth *domain*, and not a fifth AID), and S8 asserts it rather than re-opening it:
```bash
rg -c 'type phosphor_.*, domain;' packages/phosphor/sepolicy   # -> 4 (phosphor-ctl is not among them)
```
Pass = the count is 4, the binary declares no `.rc`/`user` stanza (it is never started by init; it runs only when invoked from `adb shell`), and it therefore cannot do more than `adb shell` can already do. **If any diagnostics check needs a privilege `shell` lacks, the check is dropped — not granted, and above all not given a domain.** Adding a `phosphor_ctl` domain here would fail this spec and contradict S2 A8.

**A5 — The drill produces its evidence.** After PM approval and execution: D5 shows `decision=safe`, stock launcher screenshot, agentd/broker absent; D8 shows full restoration (`health` = 0, shell is HOME). The completion note references the approvals explicitly. **If PM approval for a step is withheld, the row is recorded as not-executed with that reason — the spec does not fail for a withheld approval, but the phase's exit is marked incomplete and the PM is told plainly.**

**A6 — Exit checklist complete, with honest deferrals.** E1–E14 each carry a verdict + evidence. E12/E13 are DEFERRED **with the stated reasons**; E11 PASS-or-explicitly-deferred. No row blank.

**A7 — Drift report exists (E14).** A list of every implementation-vs-architecture divergence found across S1–S7, each with: the divergence, which document is authoritative, and the follow-up owner. Examples expected: init event choice, AID spelling, frame limit, card launch mechanism, `phosphor-ctl`'s domain **as resolved by S2 A8** (recorded as a divergence closed in S2, `shell` domain, not as an open question).

**A8 — Reliability is quantified, not asserted.** E5's "starts reliably" evidenced by ≥5 consecutive normal boots with agentd `running` and no `crashloop` marker, plus 3/3 kill-restarts. Each boot's evidence captured.

**A9 — No device operation performed without recorded approval.** The session record shows an approval preceding each ⚠ step. An unapproved device operation fails the spec outright, regardless of outcome.

---

## 5. Edge cases

| Case | Required behaviour |
|---|---|
| `health` run in safe boot | Prints the safe-boot signature, exit 0 for *correct safe boot*. Do not make "healthy" mean "agentd running" — that would diagnose a working escape as a fault. |
| `health` run when the policy artifact is missing | `policy=invalid`, exit ≥1, and the message says the agent **should have refused to start** (S4 §2.4) — a running agentd with an invalid policy is a defect to report, not a state to tolerate. |
| `phosphor-ctl` cannot read `sys.phosphor.safeboot` | Prints `unknown`; does not infer `0`. (An inferred `0` would defeat fail-closed diagnosis.) |
| Operator runs the drill on an unsigned/dev image | Allowed for the *drill*, but the exit note must state the provenance; the exit criterion's "custom Phosphor build" means ours, and a `:user/test-keys` dev image is recorded as such (PROJECT-STATUS §8: fingerprint ending `:release-keys` is the release signal). |
| A reboot leaves no adb | Recovery ladder; drill halts; PM informed. Do not attempt repeated reboots to "see if it comes back". |
| The latch clear form is undocumented (S3 open item 3) | The drill **cannot proceed to D7**; S3's open item is pulled forward and closed first. A drill without a documented clear path is a trap, not a procedure. |
| avc denials appear on the normal boot | H8 fails ⇒ the phase's exit is incomplete until the denial is explained or fixed. Denials on the *drilled* boot that are expected (keygate writing its property) must be enumerated, not hand-waved. |
| Second operator unavailable | Recorded limitation (A3); the runbook's independence is claimed no higher than evident. |
| PM withholds drill approval | Exit marked incomplete with the reason; **no row is marked PASS by inference**. |
| Someone wants to add a network health check | Refused: diagnostics are on-device and read-only; no telemetry, no upload (§1 non-goals). |
| `phosphor-ctl` appears to need its own domain (A4) | It does not: it runs in the existing `shell` domain (S2 A8 — five installed modules, four Phosphor domains, four AIDs). Assert the count `rg -c 'type phosphor_.*, domain;'` → 4; if a check seems to need privilege, drop the check. Do not quietly add a domain in S8 — that would contradict S2's accepted invariant. |

---

## 6. Definition of done / auditor checklist

- [ ] A1–A9 pass, each with attached evidence.
- [ ] `phosphor-ctl`: six subcommands, read-only, zero permissions, secret-free.
- [ ] Health check passes on normal boot, correctly identifies safe boot as *correct* (not faulty).
- [ ] dumpsys-based diagnosis path documented with exact commands and reproduced once independently.
- [ ] Drill: procedure complete, **every ⚠ step gated on PM approval**, reversibility proven (D7/D8), stop rules stated.
- [ ] Exit checklist E1–E14 with verdicts; deferrals stated with reasons; no blanks.
- [ ] Drift report (E14) filed, with the `phosphor-ctl` domain recorded as **resolved in S2 A8 (`shell` domain, no fifth domain, no fifth AID)** rather than as an open question.
- [ ] "Starts reliably" quantified (5/5 boots, 3/3 restarts).
- [ ] Provenance of the tested image recorded; `:user/test-keys` distinguished from release.
- [ ] No unapproved device operation anywhere in the record.

## 7. Open items created by this spec

1. ~~`phosphor-ctl`'s domain~~ — **CLOSED (F5)** by S2 A8: it runs in the existing `shell` domain; no fifth Phosphor domain and no fifth AID. A4 asserts the outcome (`rg -c 'type phosphor_.*, domain;'` → 4); the residual, if any, is a single documented read grant requested for `shell` with its reason recorded — never a new domain.
2. `dumpsys phosphor` (framework registration) vs. the dumpsys-fallback path — which is delivered (§2.2).
3. Whether the drill runbook is separated into its own file (§3).
4. E12 (hard-restricted grant landing) and E13 (R-PERF microbench) are **named Phase 9 / Phase 8+13 debts**, carried forward explicitly by this spec so they cannot be mistaken for discharged.
5. The latch clear form (pulled forward from S3 open item 3) must be closed before the drill can run D7.
6. `docs/PHASE-5-EXIT.md` is created at drill completion, not now — this spec defines its required content.
