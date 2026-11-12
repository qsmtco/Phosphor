# P5-S1 Phase 1b — Execution evidence bundle & completion note

**Executed:** 2026-11-12, by the Supervisor, from plan `docs/handoffs/P5-S1-PHASE-1b-PLAN.md` rev 6 (Debugger round-4 verdict: EXECUTABLE AS WRITTEN).
**Tree:** `/home/cptjaqx/projects/grapheneos-2026091900` · **Payload:** `packages/phosphor` @ `acba3945152acbb2a70d142e6ad4c535ed245c23`
**Device operations: NONE** (A7). No adb, no fastboot, no flash, no wipe, no reboot.

## Step-by-step results (all pass conditions met)

| Step | Command(s) | Result | Expected | ✓ |
|---|---|---|---|---|
| S0.1 | git rev-parse/status (Phosphor-platform) | `main`, `acba394…5c23`, porcelain 0 | same | ✓ |
| S0.2 | ls mirror | absent | absent | ✓ |
| S0.3 | ls local_manifests; grep manifests | absent; 0 | absent; 0 | ✓ |
| S0.4 | wc -l device.mk; grep -c; git status | 8; 0; clean | 8; 0; clean | ✓ |
| S0.5 | pin lines; repo status; du | 1085; adevtool 4-entry baseline; 109G | N=1085; baseline; ~107-109G | ✓ |
| S1 | git clone --bare + verify | bare=true, `refs/heads/main`, `acba394…5c23` | same | ✓ |
| S2 | heredoc phosphor.xml + xml parse | 3 lines exact; `XML OK` | same | ✓ |
| S3.1 | repo manifest \| grep -c | `1` + one project line (`groups="local::phosphor"` added by repo) | 1 | ✓ |
| S3.2 | ls-remote mirror / literal-B6 | mirror: `acba394` HEAD+main; literal: `fatal: … does not appear to be a git repository` | same | ✓ |
| S4.1 | repo sync -n | `repo sync has finished successfully.`, 0 error lines (ran under nohup, 2 poll cycles) | exit 0, no errors | ✓ |
| S4.2 | repo sync -j24 packages/phosphor | finished successfully; HEAD=`acba394…`, porcelain 0, full B2 layout present | same | ✓ |
| S4.3 | repo status -j24 | baseline dirt only (adevtool 4 entries) | same | ✓ |
| S5 | printf append + diff | `wc -l` 9; `1 file changed, 1 insertion(+)`; hunk `@@ -6,3 +6,4 @@`; 0 `-` lines | same | ✓ |
| S6.0 | inventory | `BEFORE_FILES=4739`, `OLD_PRESERVED_COUNT=3`, `MTIME_SNAPSHOT=4739`, `SHA256_STATUS=0` | same | ✓ |
| S6.1 | sudo gate → PM ran interactively | profile written+loaded; sysctl=1; unshare blocked; **probe red herring** (see deviations) | script shape | ✓* |
| S6.1 gate | corrected R5-2 discriminator | `DISCRIM_GREP=1`, `NSJAIL_DISCRIMINATOR=PASS`; sole DENIED = `comm="unshare"` (the script's own intended check) | PASS | ✓ |
| S6.2 | generate-all -d akita | `EXIT=0`; log fresh (`GALOG_MTIME=1794499802 ≥ GALOG_TS=1794499796`); `LAST_LINE=Generated vendor module at vendor/google_devices/akita` | same | ✓ |
| S6.3 (a) | sha256 differential | `AFTER_FILES=4739`, `INVENTORY=IDENTICAL` | same | ✓ |
| S6.3 (b) | totality gate | `NEWER_TS_COUNT=4736 + PRESERVED_COUNT=3 == BEFORE_FILES=4739`; preserved set count AND content identical; `MTIME_SNAPSHOT_DELTA=9472` | same | ✓ |
| S6.3 (c) | executed tail equality | `LEG_C_TAIL_OK=1` | same | ✓ |
| S6.3 (d) | seam greps | `PHOSPHOR_LINE_COUNT=0 GS=1`; `akita.mk:10` unchanged; `PHOSPHOR_WORD_COUNT=0 GS=1`; `SEAM_MATCH_COUNT=1`; repo status = adevtool only, now 5 entries incl. device.mk | same | ✓ |
| S7 | one-shell re-pin | `REPO_EXIT=0`, `NEW_LINES=1087` (N+2), `PIN_LINES=1`, `PIN_REV=40-hex acba394…`, remote present, `MOVED=ok`, post-mv `FINAL_LINES=1` + scoped revision | same | ✓ |
| S8 | full acceptance block | all 16 summary items green (A1=1; mirror refs; adevtool-only 5-entry status; 1-insertion diff; payload clean; seam absent; 4739 identical inventory; tail equality; 1087; FINAL_LINES=1; scoped 40-hex; plan lint 0) | same | ✓ |

## A6 — Completion note (required items)

- **(a) Our project's commit:** `acba3945152acbb2a70d142e6ad4c535ed245c23` (Phase-1a skeleton, 16 files), pinned in `.repo/manifest-pinned.xml` as a 40-hex revision with `upstream/dest-branch=refs/heads/main`, `groups="local::phosphor"`.
- **(b) Pin delta:** `1085 → 1087` lines (**N+2**: one `<remote name="phosphor" fetch="file:///home/cptjaqx/projects">` + one `<project … path="packages/phosphor" …>`; exactly as audited in BUG #3).
- **(c) GrapheneOS signed-tag verification unaffected:** the re-pin regenerated the same GrapheneOS project lines (aosp/grapheneos/grapheneos-gitlab remotes and all 1084 GOS projects at their existing pinned revisions — the only delta is the 2 Phosphor lines; verified by line-count delta + `repo manifest -r` determinism). No GOS tag, revision, or remote was modified.
- **(d) Regeneration from config, not hand-edit:** proven by the S6.3 differential — 4736 of 4739 files rewritten during the run (mtime totality), content inventory byte-identical before/after, exactly the 3 zip-mtime archive files preserved, and the seam line absent from the generated tree (it arrives via `akita.mk:10`'s existing inheritance of the config `device.mk`, which still carries our +1 line: `SEAM_MATCH_COUNT=1`).
- **(e) adevtool regeneration cost (spec §8.3):** a full `generate-all -d akita` run; `vendor/google_devices/akita` wholesale-rewritten (4736 files in ~6 s of tool time with `ADEVTOOL_SKIP_DEP_BUILD=1`; the Sep-24 full run without skip took ~3 min including dependency build). Later specs must not treat regeneration as free: it requires sudo (AppArmor profile re-apply), node24 on PATH, and rewrites the entire generated tree (any local change there is lost).

## Deviations of record (also logged in plan §Execution log)

1. **S6.1 privilege:** the sudo precondition failed in the Supervisor's non-interactive seat exactly as the plan predicts (BUG #10); the PM executed the sudo line interactively. Output matched the audited shape except the nsjail probe line — the documented red herring.
2. **R5-2 pattern false-fail:** the plan's `apparmor.*nsjail` pattern matched benign `apparmor="STATUS" operation="profile_replace"` audit lines (profiles loading *successfully*). Corrected at execution to exact `apparmor="DENIED"` AND `nsjail`; the sole DENIED in the window is `comm="unshare"` — the script's own intended verification that the global restriction remains on. Intent (gated, denial-based) unchanged; to be folded back into the plan at next revision.
3. **S6.2 `ADEVTOOL_SKIP_DEP_BUILD=1`:** added per the fix script's own printed guidance; deviation from the plan's verbatim command. Consequence: 2-line log (vs 50) — dependency-build lines suppressed; all tree-level evidence unaffected (totality gate passed on tree facts). Flagged for the auditor; not silently justified.
4. **S4.1 backgrounding:** `repo sync -n` exceeded any single command window (network fetch, 1085 projects); ran under nohup with timer polls. Also: one `Bad substitution` when the Supervisor's exec wrapper used sh, not bash — the plan's own rule 6 (BUG #11) caught it; re-ran under bash.

## Open items

- Post-execution adversarial audit (Debugger) — this bundle is its input.
- Plan rev 7 fold-back: corrected DENIED pattern (deviation 2) + `SKIP_DEP_BUILD` decision record (deviation 3).
- Phase 1c (the build) follows after audit-clean, per instructions L59's gate.
