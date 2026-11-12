# P5-S1 Phase 1b — Rev 3 order (Supervisor → Coder), 2026-11-11

**Trigger:** Debugger's post-fix re-audit of plan rev 2. Verdict: **not executable as written.** BUG #1, #2, #3, #4, #6, #8, #9, #10, #11 are CLOSED. BUG #5 and #7 are half-closed, and the revision introduced **five new defects** (NEW-1 CRITICAL, NEW-2/NEW-3 HIGH, NEW-4/NEW-5 MEDIUM).

**Scope of this round: a small mechanical diff to S6.1, S6.2, S6.3, S7, and the S8 summary string. No re-architecture. No other section changes.**

Every corrected expectation must be **executed, not imagined** — that is the failure mode that produced NEW-1, and rule 7 exists precisely because of it. Below, each NEW item is followed by the executed evidence you must use.

---

## NEW-1 (CRITICAL) — S6.2's "literal" log string is fabricated

Your repair for BUG #5 demanded a literal string "quoted from a known-good run" and then invented one. `Generating mk for akita` does not exist anywhere.

Executed evidence (Supervisor, 2026-11-11):

```
$ grep -rn "Generating" vendor/adevtool/src/        → 0 matches
$ grep -n "Generating" /home/cptjaqx/adevtool-generate-all.log → no match, rc=1
$ tail -1 /home/cptjaqx/adevtool-generate-all.log | cat -A
Generated vendor module at vendor/google_devices/akita$
$ wc -l /home/cptjaqx/adevtool-generate-all.log
50
$ stat -c '%y' /home/cptjaqx/adevtool-generate-all.log
2026-09-24 17:58:16.068988579 -0700
```

The real known-good final line is **`Generated vendor module at vendor/google_devices/akita`** — from the Sep 24 17:58 run that produced the current 4739-file tree.

**Consequence at execution:** a correct `generate-all` exits 0, rewrites the tree, and then fails your gate. The executor's only options are to override a gate (which global rule 1 forbids) or halt the phase. It is also a false-pass twin: no run can ever match, so the check has zero discriminating power.

**Fix:** S6.2's expected string → `Generated vendor module at vendor/google_devices/akita`. Update every echo of it: S6.2 (~line 423), the FAILED clause (~426), S6.3's leg (c) (~480), S8's summary (~574), Part A (~614), the revision log (~669). Add provenance: "quoted from the executed `tail -1 /home/cptjaqx/adevtool-generate-all.log` (Sep 24 17:58, 50 lines, the run that produced the current tree)". **Keep** the record-verbatim-and-STOP behaviour for a differing final line — that is what makes it robust to an adevtool version change.

---

## NEW-2 (HIGH) — S6.0/S6.3 cross-block `$BEFORE_TS` breaks the mtime leg

`BEFORE_TS` is set in S6.0's block and consumed in S6.3's *separate* block. Global rule 5 says every block is self-contained, so a mechanical executor runs S6.3 with it unset.

Executed evidence:

```
$ bash -c 'find vendor/google_devices/akita -type f -newermt "@$BEFORE_TS" -printf "%p\n" | wc -l'
0
$ bash -c 'BEFORE_TS=0; find vendor/google_devices/akita -type f -newermt "@0" -printf "%p\n" | wc -l'
4738
```

Both directions are live: unset → false-fail on a correct run (0 instead of >0); `BEFORE_TS=0` → false-pass on a no-op (4738 of 4739 files are newer than epoch, so the check "passes" with no regeneration at all — the exact no-op it exists to catch).

Also: `/tmp/akita-before.mtime` is written in S6.0 and **never read** — dead weight.

**Fix (either, or both):** (a) S6.0 writes the marker to a file — `date +%s > /tmp/akita-before.ts` — and S6.3 reads it: `BEFORE_TS=$(cat /tmp/akita-before.ts)`, with an explicit "if that file is missing, STOP". (b) Give the mtime snapshot a purpose: S6.3 compares `find vendor/google_devices/akita -type f -newer /tmp/akita-before.mtime -printf '%p\n' | wc -l` against the same snapshot. State the carry-over as a **named exception in global rule 5** (S6.0 → S6.3 marker file; S7 is one shell, see NEW-3).

---

## NEW-3 (HIGH) — S7's promote gate reads `$REPO_EXIT` across shells

`REPO_EXIT` is set in the verify block and tested in the promote block — two bash invocations under rule 5. In a fresh shell it is unset and `case "" in 0)` falls through to `*)` → "not promoting". That direction is safe. The dangerous one is an executor pasting the echoed value to "restore state": if the `.new` is bad, the file gates still hold, but the exit-code gate is theater and the evidence bundle misleads.

Executed evidence:

```
$ bash -c 'case "$REPO_EXIT" in 0) echo ok;; *) echo "REPO_EXIT=[$REPO_EXIT] — not promoting"; exit 1;; esac'
REPO_EXIT=[] — not promoting
```

**Fix:** merge S7's verify + gates + `mv` into **one** bash block, capturing `REPO_EXIT` inside the same invocation as the `mv`. Name S7 as the rule-5 exception: "one shell, two phases". While you are in there, add post-`mv` verification on the promoted file — `grep -c 'path="packages/phosphor"' .repo/manifest-pinned.xml` → `1`, and a 40-hex revision check — so the loop closes on the real artifact, not only the temp.

---

## NEW-4 (MEDIUM) — S6.1 describes an "already loaded" branch the script does not have

Your S6.1 EXPECTED says "If it reports the profile already loaded, that is success." The script has no such branch (`grep -n "already" scripts/host-fix-nsjail-userns.sh` → no match). On this host the profile already exists and is loaded: `/etc/apparmor.d/nsjail-userns`, root, 775 bytes, Sep 24 17:55, containing the tree-absolute nsjail path — i.e. it was written by this script on Sep 24.

The script rewrites and reloads unconditionally, so a re-run is a **no-op reload**, and that is success. But the plan currently describes output the script cannot produce.

**Fix:** S6.1 EXPECTED → quote the script's real output shape, from its body:

```
==> Writing /etc/apparmor.d/nsjail-userns
==> Loading the profile
==> Verification
-- global restriction should still be ON (1) --
1
-- a plain unprivileged unshare should still FAIL --
   still blocked (correct: restriction intact, only nsjail exempted)
-- nsjail probe (this is what the build runs) --
   nsjail works now
==> Done.
```

Add: "The profile **pre-exists** on this host (Sep 24 17:55, root, 775 bytes). The script rewrites and reloads it unconditionally, so a re-run is a no-op reload and is success. The evidence bundle must record that the profile pre-existed (A6a's regeneration-from-config statement)."

---

## NEW-5 (MEDIUM) — no log-freshness gate on `$GALOG`

S6.2 keys on `tail -1` of a log the step itself writes via `tee`. If a run exits 0 while writing **zero** output (every device skipped), `tail -1` shows the *previous* run's final line — which, with NEW-1 fixed, now matches, and a no-op passes.

**Fix:** one line before S6.2: `rm -f /home/cptjaqx/adevtool-generate-all.log` (or capture `GALOG_TS=$(date +%s)` before and assert `find /home/cptjaqx/adevtool-generate-all.log -newermt "@$GALOG_TS"` after). State that a missing log after the run is a hard stop.

---

## Also close these two smaller items from the audit (non-blocking, do them in the same pass)

1. **S6.0's `xargs sha256sum` has no status check.** If `sha256sum` fails on one file the inventory silently shrinks; S6.3's `diff -q` would report CHANGED (safe direction), but make it explicit: assert before-count == after-count (both must equal `AFTER_FILES`).
2. **S8's summary line and Part A must echo the corrected strings** — S8 currently lists `Generating mk for akita`; Part A line ~614 too. A stale summary is how a fabricated string survives a repair.
3. Add one FAILED-note line: "generate-all rewrites the tree, then a second process restores a file to its pre-run content **and** restores its mtime — passes all three legs. Out of scope for this plan; noted so a future reader does not mistake the three legs for an anti-tamper proof."

---

## Deliverables for rev 3

1. `docs/handoffs/P5-S1-PHASE-1b-PLAN.md` → **rev 3**, with the revision log extended: `NEW-1..NEW-5` → what changed → rev-3 line numbers, and BUG #5/#7 marked as now closed with the evidence.
2. COMPLETENESS Part B: one `[x]` line per NEW item with the executed command that proves it (you may cite the Supervisor's executed evidence above, but you must re-run each command yourself before writing the expected string — no string in rev 3 may be unexecuted).
3. Related issues: carry forward, updating R-4 (1a hash confirmed) and R-6 (method corrected).
4. Invoke `/home/cptjaqx/projects/Phosphor/.crabcakes/prompts/steelFramedCodeWriter.md` this round. Word marker: **please write**.