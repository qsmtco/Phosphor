# P5-S1 Build Integration Post-Mortem

**Date:** 2026-11-10 (loop start; executed through 2026-11-12)
**Supervisor:** Supervisor
**Builder:** Coder (plan author, revs 1–3) / Supervisor (revs 4–7, two-failed-rounds rule)
**Commits:** 2 in this repo (`d2462a7` S1 close; `2eaf344` spec set) + `acba394` in Phosphor-platform
**Phases:** 3 (1a skeleton → 1b tree integration → 1c build)
**Total bugs found:** 25 (1 CRITICAL, 7 HIGH, 10 MEDIUM, 7 LOW) — all in *plan* artifacts, zero in shipped tree
**Process:** spec → preflight probe → 3-phase execution with adversarial audit between every code-bearing turn; plan went through 6 revisions under audit before execution

---

## 1. Code Quality Grade: A- (91/100)

### Justification

The shipped artifact (16 files, 68 lines + one third-party makefile line) is exactly what the spec ordered — five empty-but-real Soong modules, zero boot behavior, byte-verified against B2/B3/B5/B7 by three independent parties (Coder, Debugger, Supervisor) and proven again by the build itself. Nothing in the tree had to be fixed after landing. The cost was process: the *plan* artifact cycled through six revisions and four audit rounds because expected-output strings kept being derived from rendered views instead of executed commands — the single dominant failure pattern of this loop, caught every time by audit but never fully eliminated until rev 5's "executed or it doesn't go in" discipline.

| Category | Score | Notes |
|---|---|---|
| Correctness | 19/20 | Tree artifact flawless; one plan-level false-fail pattern survived three revs |
| Architecture compliance | 10/10 | priv-app routing, B5 variable spellings, N+2 pin delta — all spec-exact |
| Test coverage | 9/10 | A1–A7 all evidenced + independently re-run; no device-level test (by design) |
| Documentation | 9/10 | Evidence bundles + revision logs complete; two LOW doc gaps caught at 1c audit |
| Maintainability | 8/10 | Plan file is 850+ lines for 68 lines of code — heavy but auditable |
| DX (Developer Exp.) | 8/10 | Four audit rounds before execution is thorough but slow |
| **Total** | **91/100** | **A- (audit-hardened, process-heavy)** |

Deducted points:
- 2 Maintainability: the execution plan's evidence discipline (markers, gates, totality) makes it unreadable as a *guide*; it is a *contract*, and future phases should split "what to run" from "how it's proven."
- 2 DX: no cheap way to pre-validate expected-output strings; every fabricated string cost a full audit round.
- 1 Correctness: my own rev-4 totality predicate (`BEFORE_TS`-anchored) selected all 4739 files — the exact class of bug the round existed to catch, shipped by the fixer.

---

## 2. What's Good About the Code

1. **Spec-exact minimal modules:** every module is the smallest thing that satisfies its B3/B7 clause — `int main() { return 0; }` stubs, manifest-only APKs with zero components (`services/PhosphorAgentd/main.cpp`, `apps/PhosphorShell/AndroidManifest.xml`) — so S1 provably adds zero boot behavior, verified statically (A4) and by construction.
2. **The one-line seam discipline:** the entire third-party footprint is a single `inherit-product` line at `device.mk:9` (`@@ -6,3 +6,4 @@`, 1 insertion, 0 deletions), landing through `printf >>` so a diff can only ever be an append — the A5 acceptance became mechanically checkable.
3. **Totality-gate regeneration proof:** the fixed-cutoff `2026-01-01` predicate (`find … ! -newermt`) + preserved-set diff + `NEWER+PRESERVED==BEFORE` arithmetic (plan S6.0/S6.3, executed 4736+3==4739) converts "generate-all ran" into "generate-all rewrote every file and preserved exactly the three zip-mtime archives" — a proof that survives `SKIP_DEP_BUILD` log verbosity and requires no git tracking of an untracked tree.

---

## 3. What's Bad About the Code

1. **Expected-output fabrication kept recurring:** across plan revs, at least six expectation strings were invented rather than executed (`Generating mk for akita` CRITICAL; device.mk "5 lines"; `ls-remote` parent-dir; "already loaded" branch; my rev-4 predicate; CA-2's "0 matches" claim).
   - Evolution: rev-5's rule — *no string enters the plan without the executed command that produced it pasted beside it* — should be a standing template from rev 1 of every future plan, not a rev-5 patch.
2. **Plan-to-artifact weight ratio:** 850 plan lines shepherding 68 code lines; three of four audit rounds were spent on the plan, not the product.
   - Evolution: for phases whose artifact is small and mechanical (S3/S4 stubs), pre-author the evidence gates once (they're now proven patterns in project memory) and spend audit rounds on the artifact only.

---

## 4. Bugs Found During Audit

| # | Phase | Severity | Bug | Found by | Fixed by |
|---|---|---|---|---|---|
| 1 | 1b plan rev 1 | HIGH | device.mk expected 5 lines / wrong paths (rendered view) | Debugger (probe) | Coder (rev 2) |
| 2 | 1b rev 1 | HIGH | void `ls-remote` parent-dir test | Debugger | Coder (rev 2) |
| 3 | 1b rev 1 | HIGH | pin delta N+1 (missed remote serialization) | Debugger (fixture) | Coder (rev 2) |
| 4 | 1b rev 1 | HIGH | vacuous regeneration proof (`vendor/google_devices` not git-tracked) | Debugger | Coder (rev 2) |
| 5 | 1b rev 2 | CRITICAL | fabricated log string `Generating mk for akita` | Debugger | Supervisor (rev 4→5) |
| 6 | 1b rev 2 | HIGH | cross-shell `$BEFORE_TS` / `$REPO_EXIT` | Debugger | Coder (rev 3) / Supervisor (rev 4) |
| 7 | 1b rev 4 | HIGH | totality predicate selected all 4739 files (my own fix) | Debugger (round 3) | Supervisor (rev 5, fixed cutoff) |
| 8 | 1b rev 5 | MEDIUM | journalctl discriminator un-gated; pattern too broad | Debugger (round 4) + execution | Supervisor (rev 6/7) |
| 9 | 1b execution | LOW | R5-2 pattern false-fired on `profile_replace` STATUS lines | Supervisor (execution) | Supervisor (corrected pattern, rev 7) |
| 10 | 1c audit | LOW | nsjail-line and B2-conformance not recorded in evidence | Debugger | Supervisor (amendments) |

(15 further MEDIUM/LOW plan defects across revs 2–6 — stale line maps, unscoped greps, vestigial wording — all repaired in-round; full tables in the plan's revision logs.)

**Summary:** no bug ever reached the tree. Every defect was caught at the plan stage or during execution gates; the two execution-time deviations (sudo seat, SKIP_DEP_BUILD) were logged, not hidden. The compounding pattern: *rendered-view-derived expectations*, which produced bugs 1, 5, and 7 in three consecutive generations — author, repairer, and auditor-proposal each re-committed it until the executed-evidence rule landed.

### Bug patterns

| Pattern | Count | Description |
|---|---|---|
| `fabricated-expectation` | 6 | expected output written from a file view or imagination, not an executed command |
| `cross-shell-state` | 3 | variable set in one bash block, consumed in another despite the self-containment rule |
| `tautological-check` | 3 | check that cannot fail by construction (equal-instant mtime predicates, untracked-tree git status) |
| `ungated-verdict` | 2 | evidence printed but never gated in code |

---

## 5. Process: What Worked

1. **Preflight spec-vs-tree probe before any authoring:** caught B6's broken dev-variant URL (`manifest_xml.py:232-233`) and the priv-app routing error *before* a single plan line was written; the priv-app catch alone saved a full ~1h build cycle.
2. **Adversarial audit between every code-bearing turn:** Debugger's 11-section protocol found defects in every plan revision including mine — the loop's catch rate on its own artifacts was 100% (nothing shipped un-audited, nothing audited shipped broken).
3. **File-based delegation (handoff discipline):** after my garbled payload produced D-1…D-4, moving all content into `docs/handoffs/` files with "the plan file is the fidelity authority" eliminated transcription-channel bugs entirely for the remaining five rounds.

---

## 6. Process: What Didn't Work

1. **Payload channel unreliability:** my re-sent delegation garbled three strings and truncated mid-word; Coder correctly refused to transcribe them, but the round was wasted.
   - Lesson: any delegation longer than a pointer + ruling should be a file on disk; the `/ask` payload carries scope and rulings only.
2. **Supervisor-as-fixer still needed three rounds:** rev 4 (mine) introduced the mis-wired predicate; rev 5 (mine) fixed it but only after executing the Debugger's *own* wrong proposal to reject it.
   - Lesson: the two-failed-rounds rule should trigger one round earlier for *expectation-string* defects specifically, and every proposed fix — including the auditor's — gets executed before it's adopted.
3. **Timer/poll orchestration for long jobs:** the build's "RUNNING" pgrep status was a self-match on my own probe command; the actual process had finished 50 minutes earlier.
   - Lesson: poll with `pgrep -f` on the nohup'd *command string minus the probe's own text*, or better, have the background job write an exit-code file on completion.

---

## 7. What the Code Actually Does (End-User Impact)

1. **Nothing — by specification.** S1 is a build-only phase; no device runs Phosphor code. The user-visible fact is for the *builder*: `m -j24 vendorbootimage vendorkernelbootimage target-files-package` now emits `system/bin/phosphor-{agentd,keygate,ctl}`, `system/priv-app/Phosphor{Shell,Broker}/`, and `system/etc/phosphor/risk-policy.json` into the target files (`out/target/product/akita/…`, verified in staging zip `SYSTEM/…`). Code path: `device.mk:9` → `packages/phosphor/phosphor.mk` → the five `Android.bp` modules.
2. **Provenance stays clean:** `repo manifest -r` pins our payload at `acba394…5c23` (`manifest-pinned.xml:10`) while all 1,084 GrapheneOS projects keep their signed-tag revisions — a future flash of this target-files zip is attributable line-by-line to upstream sources plus exactly one local commit.

---

## 8. Pre-Existing Issues Flagged (Not Caused by This Implementation)

1. **`vendor/adevtool` baseline dirt** (`package.json`, `yarn.lock`, `.yarn/`, `.yarnrc.yml`): pre-existing on this checkout before S1 began (baselined in the preflight probe, 2026-11-10). Excluded from A5 by spec; not touched.
2. **repo v2.68 vs 2.71 upgrade nag:** harmless log noise on every `repo` call; upstream tooling, out of scope.

---

## 9. Evolution Suggestions (Tier 2+)

| Suggestion | Effort | Impact |
|---|---|---|
| Extract the proven evidence-gate patterns (totality, freshness, marker files, DENIED discriminator) into a reusable snippet library in the Phosphor repo | 2–3 h | Future plans (S2–S8) start at rev-5 discipline; eliminates the fabricated-expectation class |
| Commit the GrapheneOS-tree state (local manifest + seam) as a patch series in the Phosphor repo for rebuild-from-clean | 1 h | Tree reproducibility after a fresh `repo init` |
| Bash wrapper that runs a plan's fenced blocks in order, capturing per-block exit codes | 3–4 h | Removes supervisor-transcription entirely; the plan becomes directly executable |

---

## 10. Lessons Learned / Process Rules to Carry Forward

1. **Executed-evidence rule:** no expected-output string enters any plan without the executed command that produced it pasted beside it.
   - Trigger: writing any EXPECTED block. Action: run it first; if you can't run it, label it "quoted from source" explicitly (rev-4 R4-4 pattern).
2. **Execute the fix before adopting it:** auditor-proposed repairs get executed against the real tree before being written into the plan (this loop rejected one with evidence: log-mtime anchor → 4738, not 3).
   - Trigger: any audit FIX field. Action: reproduce, then adopt or reject with output.
3. **Background jobs write exit files:** long builds/syncs end with `echo $? > /tmp/<job>.exit`; polls read the file, never pgrep.
   - Trigger: any nohup job. Action: append the exit-file write to the launch line.
4. **Payloads are pointers:** `/ask` carries scope + rulings; all file content lives on disk under `docs/handoffs/`.
   - Trigger: any delegation over ~10 lines of content. Action: write the file, send the path.

---

## 11. Sign-off

- [x] Code committed (`d2462a7` in Phosphor; `acba394` in Phosphor-platform)
- [x] All post-loop verification commands run and pasted (1b/1c evidence bundles, auditor-verified)
- [x] Captain notified with summary (this document + feed card)
- [ ] Tier 2+ backlog: evolution suggestions 1–3 logged for S2 planning; **erratum 4 (B6 dev-variant text) still awaiting PM approval**
