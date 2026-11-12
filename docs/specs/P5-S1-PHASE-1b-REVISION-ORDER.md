# P5-S1 Phase 1b — Plan revision order (Supervisor → Coder), 2026-11-11

**Authority:** Debugger's between-phase audit of `docs/handoffs/P5-S1-PHASE-1b-PLAN.md` (11 findings). This file is the repair list. Revise the plan **in place** to rev 2; do not re-architect.

**Standing rulings — already decided, do NOT re-litigate, DO make the plan implement them:**

- **R-1 ACCEPTED (B6 dev-variant defect is real).** Evidence: tree's own `repo` source `.repo/repo/manifest_xml.py:232-233` → `fetchUrl = self.resolvedFetchUrl.rstrip("/")` then `url = fetchUrl + "/" + projectName` — literal concatenation. So the manifest must be `fetch="file:///home/cptjaqx/projects"` + `name="Phosphor-platform.git"`, keeping `path="packages/phosphor"` and `revision="refs/heads/main"` byte-identical to B6. Your S2 already does this — keep it.
- **A1a HEAD is confirmed:** `acba3945152acbb2a70d142e6ad4c535ed245c23` on `main` (Supervisor re-derived via `rev-parse`; `rev-list --count` = 1, porcelain empty).
- **D-1…D-4 ratified.** The authority chain beat my garbled payload. Note for the record: payload typos were mine.
- **Erratum 4 pending PM approval** (B6 spec text). You do not edit the spec; the plan's S2 form stands.

**Repair each finding. Every corrected step keeps: exact command, exact expected output, a FAILED state that STOPs.**

## BUG #1 (HIGH) — S0.4 expectations are fabricated from a line-numbered view
- `device.mk` is **8 lines**, not 5, and its internal paths are `.../google_devices/platform/zuma/...` — **no `device/` segment**. Your own cited authority `P5-S1-PREFLIGHT-PROBE.md:97,101` prints them correctly, so the plan contradicts its source.
- Fix: S0.4 `wc -l` → `8`; replace the expected-content block with the real 8 lines (blank lines included, `platform/zuma`); keep `grep -c` → `0` and clean `git status`. S5's post-append `wc -l` becomes `9`.
- General rule to add to §Global execution rules: **expected output must come from an executed command, never from a rendered or line-numbered view of the file.**

## BUG #2 (HIGH) — S3.2 command 1 is void and can never print `1`
- `git ls-remote file:///home/cptjaqx/projects` is not a git repository; `ls-remote` lists **refs**, and no ref is named `Phosphor-platform.git`. Enumerating a parent dir is not a git operation. Your COMPLETENESS rationale ("falsifiable before any sync") is therefore false.
- Fix: **delete command 1**. Keep commands 2 and 3 (they do test fetchability and the literal-B6 composition). State the composition rule with the `manifest_xml.py:232-233` cite instead of testing it. Define the FAILED state for the *first remaining* command.

## BUG #3 (HIGH) — S7 re-pin delta is **N+2**, not N+1
- `ToXml` serialises remotes as well as projects (`manifest_xml.py:613-616`). Adding our local manifest adds **two** lines: the `phosphor` `<remote>` and the `<project>`. Proven on an offline fixture with this tree's `repo` v2.68.1 (9 → 11 lines).
- Fix: EXPECTED → `N+2`, name both lines; FAILED clause `N+>2`. Also record the real pinned-line attributes: `upstream="refs/heads/main" dest-branch="refs/heads/main" groups="local::phosphor"` — the plan currently mentions only `upstream=`, and it asks for the line "verbatim".

## BUG #4 (HIGH) — the regeneration proof is vacuous
- `vendor/google_devices` is **not a git repo and not a repo project** (`git -C` → `fatal: not a git repository`; `grep -c 'path="vendor/google_devices"' .repo/manifest-pinned.xml` → 0; absent from `.repo/project.list`). It can never appear in `repo status` however badly it is mangled, so S6.3's "`vendor/google_devices` must not appear" is a tautology and S6.2's prescribed `git -C vendor/google_devices status --porcelain` can only error.
- Fix: replace with evidence that exists for an untracked tree — (a) pre-run inventory `find vendor/google_devices/akita -type f | sort | xargs sha256sum > /tmp/akita-before.sha256` (4739 files today), (b) the same after, (c) an mtime/`find -newermt` check, (d) the generate-all log. Mark the `git -C vendor/google_devices` command invalid, or delete it.

## BUG #5 (HIGH) — S6.3 assertions hold on the untouched tree
- Three of five already pass before any work (`packages/phosphor` → 0, `inherit-product` present in `akita.mk`, `phosphor` → 0), and the log check is only `tail -30` with no concrete expected string. A generate-all that silently did nothing passes completely — exactly the hand-edit gap the spec assigns to this phase (`P5-S1-build-integration.md:63,188`).
- Fix: make S6.3 **differential** (before/after sha256 inventory + mtime delta from BUG #4) and replace "the tail shows the generator's completion lines" with a **literal expected string quoted from a known-good run**.

## BUG #6 (MEDIUM) — S5 expected hunk and `--stat` are wrong
- Real hunk is `@@ -6,3 +6,4 @@` (blank lines shift it), not `@@ -3,3 +3,4 @@`. And `git -C vendor/adevtool diff --stat` reports **3** files after the append, because the documented baseline already carries `package.json` + `yarn.lock`.
- Fix: hunk → `@@ -6,3 +6,4 @@`; restrict the stat to the one file (`git -C vendor/adevtool diff --stat -- config/mk/google_devices/device/akita/device.mk`) so `1 file changed, 1 insertion(+), 0 deletions(-)` is achievable. Keep the zero-`-`-lines requirement.

## BUG #7 (MEDIUM) — S7 truncates a file it cannot restore
- `repo manifest -r > .repo/manifest-pinned.xml` truncates the 1085-line / 245571-byte provenance artifact *before* `repo` runs, no exit code is captured, and a failure leaves 0 bytes. `.repo` is tracked by no project, so git cannot restore it.
- Fix: write to `.repo/manifest-pinned.xml.new`, capture `EXIT=$?`, verify 40-hex + `N+2`, then `mv` only after both pass. Same shape as the generate-all log.

## BUG #8 (HIGH) — fraudulent-pass construct, three occurrences
- `grep -rn 'X' dir/ | wc -l` prints `0` when `dir/` does not exist (grep errors on stderr, `wc` prints 0) — so the most likely generate-all failure mode renders as the strongest pass. Occurrences: S6.3 lines ~384, ~386 and S8 ~441.
- Fix: assert the tree first (`test -d vendor/google_devices/akita`) and capture grep's status: require the count **and** `PIPESTATUS[0]` ∈ {0,1}; any `2` is a hard stop.

## BUG #9 (MEDIUM) — A7 evidence is a static-file grep
- The A7 grep runs against the plan file, which never changes, so it prints `0` before and after any execution — including one that ran `adb`. The plan concedes this at line 39 yet still lists the grep as A7's evidence (S8 and COMPLETENESS line ~492).
- Fix: relabel it **"plan lint, not execution evidence"** in S8 and in COMPLETENESS; make the **execution transcript** the sole A7 artifact.

## BUG #10 (MEDIUM) — S6.1 assumes non-interactive sudo
- `sudo -n true` → `sudo: interactive authentication is required` (rc=1) in a non-interactive seat. S6.1 expects exit 0 and STOPs on non-zero with no mention of prompting — an ambiguous failure at the step whose purpose is to pre-empt an ambiguous failure.
- Fix: add the precondition `sudo -n true` must exit 0; otherwise the phase must run in an interactive seat. Distinguish "privilege unavailable" from "AppArmor fix failed".

## BUG #11 (LOW) — `PIPESTATUS` needs bash
- Four steps (S4.1, S4.2, S6.1, S6.2) rely on `${PIPESTATUS[0]}`; under `sh`/`dash` the guard itself errors (`Bad substitution`) and the step's exit evidence is lost.
- Fix: one line in §Global execution rules — **every block runs under `bash`.**

## Also carry forward (not bugs)
- Keep the `repo sync -n` = `--network-only` correction (R-3) — Debugger confirmed it from `sync.py:617-622` and confirmed the plan does not claim dry-run semantics.
- Correction to my check-5 wording, for your S4.3/S8 expectations: `packages/phosphor` will **not** show as "new" in `repo status` — it is a cleanly synced project. S6.3's "exactly two projects… and nothing else dirty" is the right expectation.
- S5 must keep refusing self-revert and newline-mangling fixes without Supervisor instruction — Debugger flagged that as correct.
- S2's heredoc ordering is fine for the executing seat.

## Deliverables for this round
1. `docs/handoffs/P5-S1-PHASE-1b-PLAN.md` → rev 2, with a `## Revision log (rev 2)` section listing each BUG # → what changed → line numbers.
2. Update the COMPLETENESS block: one line per step, plus a line per BUG proving the repair.
3. "Related issues found, not fixed in this phase" — carry R-1…R-6 forward, updated (R-1 now ruled, R-2 rejected, R-4 partly resolved by the confirmed 1a hash).
4. Invoke `/home/cptjaqx/projects/Phosphor/.crabcakes/prompts/steelFramedCodeWriter.md` this round. Word marker: **please write**.