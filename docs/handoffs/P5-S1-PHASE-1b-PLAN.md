# P5-S1 Phase 1b — Execution Plan (author round, Coder) — **rev 6**

**Phase:** 5 · **Spec ID:** P5-S1 · **Phase:** 1b (tree integration) · **Author:** Coder, 2026-11-10
**Revision:** **rev 6** (2026-11-12; revs 4–6 applied by the **Supervisor**, revs 4–5 under the two-failed-rounds rule (`implementationSupervisor.md` anti-pattern "endless rework loops"), from Debugger's rev-3 re-audit (R4-1..R4-5 + two line-map/claim nits). Rev 3 closed NEW-3 and BUG #7 only; BUG #5 remained open (the literal string existed but no check compared it). Rev 4 is a mechanical diff scoped to the same sections as rev 3. Each fix → change → line number is mapped in `## Revision log (rev 4)`.
**Authority chain:** `docs/specs/P5-S1-PHASE-1b-REV3-ORDER.md` (rev-3 repair list, 5 findings + carry-alongs) → `docs/specs/P5-S1-PHASE-1b-REVISION-ORDER.md` (rev-2 repair list, 11 findings; all closed except #5/#7, which close in rev 3) → `docs/specs/P5-S1-PHASE-INSTRUCTIONS.md` (Phase 1b, lines 59-65; handoff discipline, lines 53-55) → `docs/specs/P5-S1-build-integration.md` **rev 2** (B4 line 76-82, B6 lines 111-120, A1/A5 §5) → `docs/specs/P5-S1-PREFLIGHT-PROBE.md` (BUG #1 fix, baseline dirt). The revision orders outrank every expectation string in this file; where rev 1/rev 2 prose and an order disagree, the order wins and the prose has been corrected.
**Status of this file:** this plan **is the fidelity authority for the Phase 1b audit** (instructions L55: "the plan file is the fidelity authority for the audit. Chat reports are not the authority"). Every command and every file content below is exact and is to be transcribed mechanically.
**Word marker for this round:** the delegation carried the word marker **`please write`** (author round, rev 3 of this plan); no `please proceed` execution marker is claimed here. Execution of this plan happens in a seat that can write outside `/home/cptjaqx/projects/Phosphor`.

**Scope of Phase 1b (in):** bare mirror of the Phase-1a repo; `.repo/local_manifests/phosphor.xml`; `repo sync -n` then a project-only `repo sync`; A1 assertion; the single `device.mk` line; `adevtool generate-all -d akita`; re-pin `manifest-pinned.xml`; A5 `repo status -j24`; target-state check on `vendor/google_devices/akita`.
**Out of scope (hard boundaries, all phases):** no device operation of any kind — no flash, wipe, reboot, `adb`, `fastboot` (A7); no build (`m`) — that is Phase 1c; no `OFFICIAL_BUILD=true`; no second third-party edit; no hand-edit of `vendor/google_devices/akita`; no `/system/app/` path anywhere (rev-2 erratum); no `init_rc`, sepolicy content, or manifest components (all Phase 1a, already fixed).

---

## 0. Deviations from the delegation payload, and why

The delegation payload was re-sent after garbling. Three of its strings conflict with the authority chain, and one clause was truncated mid-word. This plan follows the **authority chain**, not the payload, and records each difference so the audit can check the reasoning rather than the transcription.

| # | Payload said | Authority says | Plan uses | Evidence |
|---|---|---|---|---|
| D-1 | `git clone --bare /home/cptjaq/projects/Phosphor-platform` | `/home/cptjaqx/projects/Phosphor-platform` | `/home/cptjaqx/...` | HOME is `/home/cptjaqx` (`P5-S1-PREFLIGHT-PROBE.md:178-179`); `/home/cptjaq` does not exist. Payload typo. |
| D-2 | `$(call inherit-product, packages/phosphor/phosphor.md)` | `$(call inherit-product, packages/phosphor/phosphor.mk)` | `.mk` | `P5-S1-build-integration.md:79` (fenced content), `:60`, `PHASE-INSTRUCTIONS.md:24`. A `.md` inherit line would abort the build: the file is a makefile fragment. Payload typo. |
| D-3 | mirror `…/Upstream-phosphor.git` "per erratum 1" | `Phosphor-platform.git` | `Phosphor-platform.git` | `PHASE-INSTRUCTIONS.md:18` ("mirrored to `/home/cptjaqx/projects/Phosphor-platform.git`"), `:61` (Phase 1b scope), `P5-S1-build-integration.md:120` (B6 development variant), `P5-S1-PREFLIGHT-PROBE.md:190` (BUG #1 fix text). **`Upstream-phosphor` has zero occurrences anywhere in the project tree** (`search_files 'Upstream-phosphor'` → 0 matches; `'acba394'` → 0 matches). No "erratum 1" naming a `Upstream-phosphor` mirror exists in any document. Using it would point `repo sync` at a path no step creates. **Not adopted.** |
| D-4 | "plus the co…" (truncated) | — | Read as (i) A6a provenance requirements (commit recorded; pinned-manifest delta; GrapheneOS signed-tag verification unaffected; regeneration-from-config statement) and (ii) the `vendor/google_devices/akita` target-state check spelled out in the same payload sentence | `P5-S1-build-integration.md:177` (A6), `:63` (Phase-1b evidence: "Stop and report if `vendor/google_devices/akita` shows the line hand-edited"), `:188` |

### D-5 — Manifest URL composition (a real defect in B6's development variant, resolved here)

`repo` composes a project's URL as **`<remote fetch>` + `/` + `<project name>`**. B6's own primary form proves the rule: `fetch="ssh://git@github.com/qsmtco"` + `name="Phosphor-platform"` resolves to `ssh://git@github.com/qsmtco/Phosphor-platform`, which is the GitHub repository path. The development variant as literally written — `fetch="file:///home/cptjaqx/projects/Phosphor-platform.git"` + `name="Phosphor-platform"` — therefore resolves to `file:///home/cptjaqx/projects/Phosphor-platform.git/Phosphor-platform`, i.e. **inside** the bare repo, which is not a git repository. `repo sync` would fail with a path that names neither the spec nor the cause (exactly the BUG #1 failure shape, one layer deeper).

The correction changes **only strings in a file this plan authors** (the local manifest), keeps the bare mirror at its literal, spec-mandated path, and keeps `path="packages/phosphor"` and `revision="refs/heads/main"` byte-identical to B6. **R-1 is ruled ACCEPTED by the Supervisor** (2026-11-11), with the tree's own `repo` source as the proof: `.repo/repo/manifest_xml.py:232-233` does `fetchUrl = self.resolvedFetchUrl.rstrip("/")` then `url = fetchUrl + "/" + projectName` — literal concatenation, no normalisation of a `.git` suffix. The plan's S2 form is what the pending spec erratum (erratum 4, PM approval) will adopt; this plan does not edit the spec. The alternative (nested bare repo at `Phosphor-platform.git/Phosphor-platform`, keeping both manifest strings literal) is R-2, was **rejected** by the Supervisor, and is **not** executed.

The composition rule is therefore **stated, not tested**: `manifest_xml.py:232-233` is the authority. S3.2 keeps two real commands — the mirror is fetchable over `file://`, and the literal-B6 composition fails — and drops rev 1's void parent-directory enumeration (BUG #2). No step in this plan edits the manifest on the fly; if a later check contradicts the deduction, the step STOPs and reports.

---

## Global execution rules (apply to every step)

1. **Stop-and-report on any mismatch.** A FAILED state is a legitimate, auditable outcome. Do not improvise, do not "make it work", do not hand-edit a file the step did not name.
2. **Paste the command and its exact output** for every step into the evidence bundle (S8 and the COMPLETENESS block). Expected strings below are the pass condition; a near-miss is a fail.
3. Any unexpected dirt in a GrapheneOS project other than `vendor/adevtool` is an **A5 failure** → STOP.
4. No command in this plan touches a device. This plan invokes no device tooling at all. **A7's authoritative evidence is the execution transcript** — the pasted output of every command in this plan, from S0.1 to S8 — and nothing else. The plan-lint grep at the end of S8 is a check on *this document*, not on the session, and is labelled as such (BUG #9).
5. Single shell session for the tree steps is not required, but `cd` state is: every block below is self-contained and `cd`s explicitly. **Three named exceptions, and only these three** (rev 4): **S6.0 → S6.3** carry a marker *file*, `/tmp/akita-before.ts`, written in S6.0 and read in S6.3 — S6.3 treats a missing marker as a hard stop rather than substituting a default; **S6.2's freshness gate** reads the marker file `/tmp/adevtool-galog.ts` written by the same step's run block, with a `test -s` presence guard as its first line (rev 4, R4-3); and **S7 is one shell with two phases** — verify, gate and `mv` are a single bash invocation, so `REPO_EXIT` never crosses a shell boundary.
6. **Every block runs under `bash`.** `${PIPESTATUS[0]}` is a bash array; under `sh`/`dash` the guard itself fails with `Bad substitution` and the step's exit evidence is lost exactly when it is most needed (BUG #11). A block that must be re-entered is re-entered with `bash`, never `sh`. Steps whose guard depends on this are S4.1, S4.2, S6.1, S6.2 (and S5's `tail`/`wc` checks, which read the same pipelines).
7. **Expected output must come from an executed command, never from a rendered or line-numbered view of a file.** A `read_file`-style view shows a window of a file; `wc -l` counts it. When this plan states a line count or a byte-exact content block, the number came from `wc -l`/`sha256sum`/`stat` on the real file, and the execution round re-runs the same command before trusting it. (BUG #1: rev 1's `device.mk` was "5 lines" from a line-numbered view and the file is 8 lines.)
8. **A `grep -c` over a directory is not evidence unless the tree is proven present and grep's own status is captured.** `grep -rn 'X' dir/ | wc -l` prints `0` when `dir/` does not exist — grep errors on stderr, `wc` prints `0` — so the likeliest failure renders as the strongest pass (BUG #8). Every such check in this plan takes the form:
   ```bash
   test -d <dir> || { echo 'TREE MISSING: <dir> — hard stop'; exit 1; }
   grep -rn 'X' <dir>/ > /tmp/<name>.grep; GS=$?
   echo "COUNT=$(wc -l < /tmp/<name>.grep) GREP_STATUS=$GS"
   case "$GS" in 0|1) ;; *) echo "GREP_STATUS=$GS — hard stop"; exit 1;; esac
   ```
   `GREP_STATUS` must be `0` (matches) or `1` (no matches); **`2` is a hard stop** (grep could not read the tree — permission, race, or a vanished path).
9. **No `git -C` on an untracked tree.** `vendor/google_devices` is not a git repository (`git -C vendor/google_devices status` → `fatal: not a git repository`) and is not a repo project (`grep -c 'path="vendor/google_devices"' .repo/manifest-pinned.xml` → 0, absent from `.repo/project.list`). Evidence for it is **content** evidence: a differential `sha256sum` inventory plus mtimes, never a git status (BUG #4).

Absolute paths used throughout (no variables, to remove ambiguity):

```
TREE      = /home/cptjaqx/projects/grapheneos-2026091900
SRCREPO   = /home/cptjaqx/projects/Phosphor-platform
MIRROR    = /home/cptjaqx/projects/Phosphor-platform.git
DEVICEMK  = vendor/adevtool/config/mk/google_devices/device/akita/device.mk   (relative to TREE)
GALOG     = /home/cptjaqx/adevtool-generate-all.log
```

---

## S0. Preconditions and abort gates

**Purpose:** prove the Phase-1a state this phase builds on, and prove no half-applied Phase-1b state already exists. Nothing is mutated in S0.

**S0.1 — the Phase-1a repo is present at the expected commit, on `main`**

```bash
git -C /home/cptjaqx/projects/Phosphor-platform rev-parse --abbrev-ref HEAD
git -C /home/cptjaqx/projects/Phosphor-platform rev-parse HEAD
git -C /home/cptjaqx/projects/Phosphor-platform status --porcelain
```

EXPECTED:
```
main
acba3945152acbb2a70d142e6ad4c535ed245c23 (40-hex; confirmed by the Supervisor via rev-parse; rev-list --count = 1, porcelain empty)
                                      (status --porcelain prints nothing)
```

FAILED (either): branch is not `main`; HEAD is not `acba3945152acbb2a70d142e6ad4c535ed245c23`; or `status --porcelain` is non-empty (1a artifact is not clean) → **STOP**, report which of the three and its output. Do not re-init, do not commit, do not "re-run 1a" from this phase.

**S0.2 — the mirror does not already exist**

```bash
ls -d /home/cptjaqx/projects/Phosphor-platform.git 2>&1
```

EXPECTED: `ls: cannot access '/home/cptjaqx/projects/Phosphor-platform.git': No such file or directory`

FAILED: the path exists → **STOP**. A bare repo already present means either a prior partial run or a wrong path; do not delete it, do not clone over it. Report `ls -la` of it and its `git --git-dir=... rev-parse HEAD`.

**S0.3 — no local manifest already present**

```bash
ls -la /home/cptjaqx/projects/grapheneos-2026091900/.repo/local_manifests/ 2>&1
grep -rn 'packages/phosphor' /home/cptjaqx/projects/grapheneos-2026091900/.repo/manifests/ 2>/dev/null | head -5
```

EXPECTED: the `ls` reports no such directory (or an empty directory); the `grep` prints nothing.

FAILED: a `phosphor.xml` or any `packages/phosphor` reference already exists in the manifest set → **STOP**, report its content. Another manifest entry pointing at our path would make A1's count 2.

**S0.4 — the `device.mk` seam is unmodified, and matches the preflight capture**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
wc -l vendor/adevtool/config/mk/google_devices/device/akita/device.mk
grep -c 'packages/phosphor/phosphor.mk' vendor/adevtool/config/mk/google_devices/device/akita/device.mk
git -C vendor/adevtool status --porcelain -- config/mk/google_devices/device/akita/device.mk
cat vendor/adevtool/config/mk/google_devices/device/akita/device.mk
```

EXPECTED — `8` lines; `0` matches for our line; `git status` prints nothing (device.mk clean); content exactly these 8 lines, including the **two blank lines** (line 2 and line 5):

```make
$(call inherit-product, vendor/adevtool/config/mk/google_devices/platform/zuma/product-common.mk)

TARGET_KERNEL_DIR ?= $(RELEASE_KERNEL_AKITA_DIR)
TARGET_BOARD_KERNEL_HEADERS ?= $(RELEASE_KERNEL_AKITA_DIR)/kernel-headers
PRODUCT_PACKAGES += GosAkitaOverlay

include vendor/adevtool/config/mk/google_devices/platform/zuma/device.mk
```

> **Source of this block:** `P5-S1-PREFLIGHT-PROBE.md:97,101` captures the file with `cat` and prints `.../google_devices/platform/zuma/...` — **no `device/` segment** — and the executed `wc -l` on the real file returns **8** (Supervisor re-ran it 2026-11-11; rev 1's `5` came from a line-numbered view, not from `wc -l` — see BUG #1 and global rule 7). Two blank lines (2 and 5) are part of the byte content: the S5 append must not disturb them. The operative facts for S5 are the **line count (8)**, the **0 matches** for our string, and the **clean `git status`**; if the *content* differs from the block above but those three checks pass, record the actual content verbatim in the evidence bundle and continue — the append in S5 is position-independent.

FAILED: `grep -c` returns `1` (line already applied) → **STOP**, report; do not append twice. `git status` shows device.mk already modified → **STOP**, report the diff; that is dirt this phase did not create and A5 would be unattributable.

**S0.5 — record the two baselines this phase reports deltas against**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
wc -l .repo/manifest-pinned.xml
repo status -j24
du -sh out/
```

EXPECTED:
- `manifest-pinned.xml` line count recorded as **N** (paste the number; the Supervisor's executed `wc -l` returns **1085**, and S7 must show **N+2** — the re-pin adds the `phosphor` `<remote>` **and** `<project>`, see BUG #3).
- `repo status -j24` shows exactly the preflight baseline — one project, four entries, none of them `device.mk`:

```
project vendor/adevtool/                        (*** NO BRANCH ***)
 --	.yarn/install-state.gz
 --	.yarnrc.yml
 -m	package.json
 -m	yarn.lock
```

- `out/` reports `109G` (record the actual number; Phase 1c reports the delta, not this phase).

FAILED: any **other** project is dirty, or `device.mk` appears — **STOP** before mutating anything; the A5 baseline no longer matches the spec's stated baseline (instructions L12) and every later `repo status` would be ambiguous.

---

## S1. Create the bare mirror from the Phase-1a repository

**Purpose:** give `repo` a fetchable `file://` origin whose `HEAD` is `acba394` on branch `main` (B6 development variant).

```bash
git clone --bare /home/cptjaqx/projects/Phosphor-platform /home/cptjaqx/projects/Phosphor-platform.git
```

EXPECTED: `Cloning into bare repository '/home/cptjaqx/projects/Phosphor-platform.git'...` and `done.`; exit 0. A warning about hardlinks is acceptable; an error is not.

**S1 verification — the mirror is bare, on `main`, at the right commit**

```bash
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse --is-bare-repository
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git symbolic-ref HEAD
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse HEAD
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git for-each-ref --format='%(refname) %(objectname)' refs/heads/
ls -a /home/cptjaqx/projects/Phosphor-platform.git | head -20
```

EXPECTED:
```
true
refs/heads/main
acba3945152acbb2a70d142e6ad4c535ed245c23   (byte-identical to the S0.1 40-hex)
refs/heads/main acba3945152acbb2a70d142e6ad4c535ed245c23
(bare layout: HEAD, config, description, hooks, info, objects, packed-refs, refs — NO .git subdirectory, NO working tree)
```

FAILED: `--is-bare-repository` is not `true` → STOP (a working-tree clone was made by mistake; remove nothing, report). `symbolic-ref HEAD` is not `refs/heads/main` → STOP and report; `repo` would fetch an unreachable revision. `rev-parse HEAD` differs from S0.1's hash → STOP; the mirror is not the audited 1a artifact.

---

## S2. Write `.repo/local_manifests/phosphor.xml`

**Purpose:** mount the Phosphor payload at `packages/phosphor` (B1/B6), development variant against the local bare mirror, with the URL-composition correction from D-5.

```bash
mkdir -p /home/cptjaqx/projects/grapheneos-2026091900/.repo/local_manifests
```

File content — write **exactly** this, no extra elements, no `groups`, no `sync-c`, no `clone-depth`. (The `groups="local::phosphor"` that appears in the **pinned** manifest at S7 is added by `repo`'s own `ToXml` from the default group list — it is not written here, and the two are not in conflict; see S7 and BUG #3.)

```xml
<manifest>
  <remote  name="phosphor" fetch="file:///home/cptjaqx/projects" />
  <project name="Phosphor-platform.git" path="packages/phosphor" remote="phosphor" revision="refs/heads/main" />
</manifest>
```

Write it with a heredoc (avoids editor/quoting damage):

```bash
cat > /home/cptjaqx/projects/grapheneos-2026091900/.repo/local_manifests/phosphor.xml <<'PHOSPHOR_MANIFEST_EOF'
<manifest>
  <remote  name="phosphor" fetch="file:///home/cptjaqx/projects" />
  <project name="Phosphor-platform.git" path="packages/phosphor" remote="phosphor" revision="refs/heads/main" />
</manifest>
PHOSPHOR_MANIFEST_EOF
```

**S2 verification**

```bash
cat /home/cptjaqx/projects/grapheneos-2026091900/.repo/local_manifests/phosphor.xml
python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('/home/cptjaqx/projects/grapheneos-2026091900/.repo/local_manifests/phosphor.xml'); print('XML OK')"
```

EXPECTED: the three lines above, byte-identical; `XML OK`.

FAILED: `XML OK` absent (parse error) → STOP, paste the parser error. Any deviation from the three lines (extra attributes, different `path`) → STOP; `path` is what A1 counts and what every later spec's layout B2 depends on.

> **Why `fetch="file:///home/cptjaqx/projects"` + `name="Phosphor-platform.git"`:** repo appends `/`+name to `fetch` (D-5). Together they resolve to `file:///home/cptjaqx/projects/Phosphor-platform.git` — the mirror path mandated by instructions L18/L61 — while `path="packages/phosphor"` and `revision="refs/heads/main"` stay byte-identical to B6. The mount point and the pinned branch are unchanged; only the two attributes that repo joins are expressed so the join lands on the mandated path.

---

## S3. Prove the manifest resolves before touching the tree

**Purpose:** A1's count, plus the two-command D-5 check (mirror fetchability and the literal-B6 composition failure), before any fetch mutates the tree. The composition *rule* itself is stated in §D-5 and sourced from `manifest_xml.py:232-233`; it is not re-tested (BUG #2).

**S3.1 — A1 assertion**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
repo manifest | grep -c 'path="packages/phosphor"'
repo manifest | grep 'path="packages/phosphor"'
```

EXPECTED: `1`, then exactly one `<project … path="packages/phosphor" …/>` line.

FAILED: `0` (manifest not picked up — `local_manifests/` not read) or `>1` (duplicate entry) → STOP, paste `repo manifest | grep -n phosphor` and `ls -la .repo/local_manifests/`.

**S3.2 — the mirror is fetchable, and the literal B6 composition is not (D-5)**

> **Rev 2 note (BUG #2):** rev 1 ran `git ls-remote file:///home/cptjaqx/projects` as its first command. That path is a **directory, not a repository** — `ls-remote` lists refs and no ref is named `Phosphor-platform.git`, so the command was void and its `grep -c` could never print `1`. It is deleted. The composition rule needs no test: `.repo/repo/manifest_xml.py:232-233` is the authority (quoted in §D-5) and the Supervisor has ruled R-1 on it.

```bash
git ls-remote file:///home/cptjaqx/projects/Phosphor-platform.git
git ls-remote file:///home/cptjaqx/projects/Phosphor-platform.git/Phosphor-platform 2>&1 | head -3
```

EXPECTED:
- first command: lists `HEAD` and `refs/heads/main` with object `acba3945152acbb2a70d142e6ad4c535ed245c23` (plus `refs/heads/main` once more if `HEAD` is a symref — `ls-remote` prints both shapes; the binding fact is that `refs/heads/main` resolves to the S0.1 hash)
- second command: `fatal: '/home/cptjaqx/projects/Phosphor-platform.git/Phosphor-platform' does not appear to be a git repository` — this is the **confirmation** of D-5 (the literal B6 `fetch`/`name` pair composes exactly that path), and is *expected output*, not an error to fix.

FAILED: the **first** command fails or prints no `refs/heads/main` → STOP, paste output; the mirror is not fetchable over `file://` (ownership/path/permissions), and `repo sync` will fail for that reason. The second command *succeeding* means the literal B6 composition would have resolved anyway and D-5's premise is wrong — record that for the auditor; S2's manifest is unaffected either way, because both forms compose to the same repository.

---

## S4. Sync: dry run, then our project only

**Purpose:** materialise `packages/phosphor` at the pinned revision without touching any GrapheneOS project.

**S4.1 — dry/network-only pass**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
repo sync -n 2>&1 | tail -20
echo "EXIT=${PIPESTATUS[0]}"
```

EXPECTED: `EXIT=0`; output shows fetching and no `error:` line (capture the tail verbatim).

> `EXIT=${PIPESTATUS[0]}` is deliberate: `${PIPESTATUS[0]}`/`$?` after a pipe reports `tail`'s status, not `repo`'s. A bare `echo "EXIT=$?"` would print `0` for a failed fetch and produce fraudulent evidence — do not substitute it.

FAILED: non-zero exit, or any `error:`/`fatal:` line → STOP, paste the tail. `repo sync -n` is `--network-only` — it fetches without updating working trees; a fetch error here means S2/S3 were wrong, and a working-tree error here would be a `repo` semantics surprise worth reporting, not working around.

**S4.2 — our project only**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
repo sync -j24 packages/phosphor 2>&1 | tail -20
echo "EXIT=${PIPESTATUS[0]}"
git -C packages/phosphor rev-parse HEAD
git -C packages/phosphor rev-parse --abbrev-ref HEAD
git -C packages/phosphor status --porcelain
ls -a packages/phosphor
```

EXPECTED:
- sync exit **0**
- `rev-parse HEAD` → `acba3945152acbb2a70d142e6ad4c535ed245c23` (**byte-identical to S0.1 — this is the 1a→1b provenance tie**)
- branch: `main` (if repo leaves a detached HEAD, record `HEAD` and note it — the commit hash is the binding fact; do not `git checkout` anything)
- `status --porcelain` → empty
- `ls -a` shows the 1a payload: `apps  init  phosphor.mk  risk-policy  sepolicy  services` (+ `.git`)

FAILED: exit ≠ 0 → STOP, paste output (a URL error here is D-5 evidence to report, not to patch live). HEAD ≠ `acba3945152acbb2a70d142e6ad4c535ed245c23` → STOP; the tree is not on the audited 1a artifact and A6a's commit record would be wrong. `status --porcelain` non-empty → STOP, report `git -C packages/phosphor status`; the payload must be exactly the committed 1a content.

**S4.3 — no GrapheneOS project was disturbed**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
repo status -j24
```

EXPECTED: still exactly the S0.5 baseline (one project, four entries, no `device.mk`). `packages/phosphor` is a **synced project and therefore clean** — it must *not* appear as dirty here; it becomes visible via `repo manifest`.

FAILED: any new dirty project → STOP, report; a sync that rewrote a GrapheneOS project is an A5 failure requiring diagnosis before continuing.

---

## S5. The one third-party edit: `+1` line in `device.mk` (B4)

**Purpose:** the only writable seam — one `inherit-product` line so the product's own makefile chain pulls in `packages/phosphor/phosphor.mk`.

Append exactly one line, using `printf` (no editor, no `sed` rewriting of existing lines):

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
printf '%s\n' '$(call inherit-product, packages/phosphor/phosphor.mk)' >> vendor/adevtool/config/mk/google_devices/device/akita/device.mk
```

The line content, exactly (this is B4 line 79 verbatim — note `.mk`, never `.md`):

```make
$(call inherit-product, packages/phosphor/phosphor.mk)
```

**S5 verification — exactly +1 line, nothing else**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
wc -l vendor/adevtool/config/mk/google_devices/device/akita/device.mk
tail -2 vendor/adevtool/config/mk/google_devices/device/akita/device.mk
git -C vendor/adevtool diff --stat -- config/mk/google_devices/device/akita/device.mk
git -C vendor/adevtool diff -- config/mk/google_devices/device/akita/device.mk
```

EXPECTED:
- `wc -l` → `9` (was 8 in S0.4)
- `tail -2` → the pre-existing last line, then `$(call inherit-product, packages/phosphor/phosphor.mk)`
- `--stat` → `1 file changed, 1 insertion(+)`, **and** that one file is `config/mk/google_devices/device/akita/device.mk` (the baseline's `package.json` + `yarn.lock` dirt is untouched)
- the diff body → exactly one hunk, exactly one `+` line, **zero** `-` lines, at hunk header `@@ -6,3 +6,4 @@` (the two blank lines at 2 and 5 shift it):

```
@@ -6,3 +6,4 @@
 TARGET_BOARD_KERNEL_HEADERS ?= $(RELEASE_KERNEL_AKITA_DIR)/kernel-headers
 PRODUCT_PACKAGES += GosAkitaOverlay
 
 include vendor/adevtool/config/mk/google_devices/platform/zuma/device.mk
+$(call inherit-product, packages/phosphor/phosphor.mk)
```

FAILED: any `-` line, more than one `+` line, or a whitespace-only difference in an existing line → **STOP**. Revert is *not* authorised here (a revert is a second unauthorized edit); report the diff and let the Supervisor decide. A `1 insertion(+), 1 deletion(-)` result specifically means the file's final newline was mishandled — report it; the fix is a `printf` with no trailing newline, but only on Supervisor instruction.

---

## S6. Re-apply the AppArmor nsjail fix, then `adevtool generate-all -d akita`

**Purpose:** B4's mandatory consequence — regenerate `vendor/google_devices/akita` **from config**, so the seam line survives future runs and the generated tree is never hand-edited. Trap: adevtool's `spawnAsync` treats the expected `Build sandboxing disabled due to nsjail error.` stderr line as fatal (`PROJECT-STATUS.md:256`), so the host fix must be in place first.

**S6.0 — pre-run inventory of the generated tree (differential baseline, BUG #4)**

`vendor/google_devices/akita` is **not a git repository and not a repo project** (`git -C vendor/google_devices status` → `fatal: not a git repository`; `grep -c 'path="vendor/google_devices"' .repo/manifest-pinned.xml` → 0; absent from `.repo/project.list`). It can never appear in `repo status` however badly it is mangled, so a post-run git status would be a tautology and an mtime-only check would miss content churn. The regeneration proof is a **content differential**: inventory before, inventory after, compare. (Supervisor's count on 2026-11-11: 4739 files under `vendor/google_devices/akita`.)

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
test -d vendor/google_devices/akita || { echo 'TREE MISSING: vendor/google_devices/akita — hard stop'; exit 1; }
BEFORE_TS=$(date +%s); echo "BEFORE_TS=$BEFORE_TS"
printf '%s\n' "$BEFORE_TS" > /tmp/akita-before.ts
find vendor/google_devices/akita -type f | sort | xargs sha256sum > /tmp/akita-before.sha256; SX=$?
echo "SHA256_STATUS=$SX"
case "$SX" in 0) ;; *) echo "sha256sum status $SX — hard stop"; exit 1;; esac
BEFORE_FILES=$(wc -l < /tmp/akita-before.sha256)
echo "BEFORE_FILES=$BEFORE_FILES"
# R4-2/R5-1: preserved-mtime set = files older than the cutoff. The cutoff sits in the
# 18-year gap between the newest zip-preserved mtime (2008-12-31) and this host's first
# generate-all (2026-09-24) — executed 2026-11-12: yields exactly the 3 zip-mtime files,
# and is re-run-proof (a new run writes >=2026-09 mtimes; copied zip files keep 1969/2008).
# NOTE: anchoring on the log's mtime (Debugger round-3 suggestion) is WRONG — executed:
# stat -c %Y log = 17:58:16, and 4738 files are <= it (the run wrote them before the log's
# final write). Do not use a run-relative anchor; use the fixed cutoff.
find vendor/google_devices/akita -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/akita-before-preserved.txt
echo "OLD_PRESERVED_COUNT=$(wc -l < /tmp/akita-before-preserved.txt)"
# full mtime snapshot — S6.3's MTIME_SNAPSHOT_DELTA diffs this (its one and only reader)
find vendor/google_devices/akita -type f -printf '%T@ %p\n' | sort -k2 > /tmp/akita-before.mtime.txt
echo "MTIME_SNAPSHOT=$(wc -l < /tmp/akita-before.mtime.txt)"
```

EXPECTED: `TREE MISSING` absent; `SHA256_STATUS=0`; `BEFORE_FILES=4739` (the Supervisor's executed `find … | wc -l`); `MTIME_SNAPSHOT=4739`; `OLD_PRESERVED_COUNT=3` — **Supervisor-executed 2026-11-12**: the fixed cutoff `2026-01-01` yields exactly the 3 zip-mtime files (`1969-12-31` `proprietary/recovery/linkerconfig/ld.config.txt`; `2008-12-31` `proprietary/system_ext/etc/public.libraries-google.txt`, `stock-kernel/system_dlkm.modules.blocklist`). A different count is recorded and is a **STOP** — the 3-file set is a property of the archive contents, not of this host's timing; any other value means the cutoff or the tree is wrong. `/tmp/akita-before.ts` contains exactly the 10-digit epoch and is the marker S6.3 reads; `/tmp/akita-before.sha256`, `/tmp/akita-before.mtime.txt` and `/tmp/akita-before-preserved.txt` are non-empty.

> **Why a marker file and not a shell variable (rev 3, NEW-2).** `BEFORE_TS` set in this block and consumed in S6.3's separate block is unset at S6.3 — `find … -newermt "@$BEFORE_TS"` then prints `0` and a correct run false-fails; the other default (`BEFORE_TS=0`) prints `4738` of `4739` files and a *no-op* false-passes (both executed by the Supervisor 2026-11-11). The marker is therefore persisted to `/tmp/akita-before.ts` and S6.3 hard-stops if it is missing.
>
> **`/tmp/akita-before.mtime.txt` is the snapshot S6.3 diffs.** Rev 2 wrote the snapshot and never read it; it has exactly one reader. The `/tmp/akita-before.mtime` reference file from rev 3 was **retired in rev 4** — its `-newer` predicate duplicated `-newermt "@$BEFORE_TS"` (same instant by `touch -d`), so the "both counts equal" cross-check was a tautology (Debugger R4 finding). The totality gate replaces it.

FAILED: `TREE MISSING` printed, `SHA256_STATUS` ≠ 0, or `sha256sum` status ≠ 0 → **STOP**; the baseline does not exist, and a missing baseline makes S6.3 unprovable either way. A file count other than 4739 is **not** by itself a failure — the tree may have grown since the Supervisor's probe — record the number; a count of `0` is a STOP.

**S6.1 — re-apply the host fix (script lives in the Phosphor project)**

**Precondition (BUG #10 — check this before anything else in S6):**

```bash
sudo -n true; echo "SUDO_EXIT=$?"
```

EXPECTED: `SUDO_EXIT=0`. The seat can escalate without a prompt.

FAILED: `sudo: a terminal is required to read the password` / `sudo: interactive authentication is required` with `SUDO_EXIT=1` (the Supervisor's non-interactive seat reproduces exactly `sudo: interactive authentication is required`) → **STOP**. This is **privilege unavailable**, not an AppArmor failure: the phase cannot run S6.1 in a non-interactive seat, and the plan must not guess at the fix. Report the output and run Phase 1b from an **interactive seat** (or have the Supervisor run S6.1's single `sudo` line by hand, then continue at S6.2). Do **not** retry with `-S`, do **not** edit `sudoers`, do **not** attempt a bare `nsjail` probe to "check" the host.

**S6.1 command (run only after the precondition passes):**

```bash
sudo bash /home/cptjaqx/projects/Phosphor/scripts/host-fix-nsjail-userns.sh 2>&1 | tail -20
echo "EXIT=${PIPESTATUS[0]}"
# R4-4/R5-2: executed discriminator AND gate — the script's own nsjail probe is swallowed
# by `if … | grep` under set -e, so exit 0 does NOT prove nsjail works. NOTE: no `| tail`
# here — tail swallows grep's status (executed: `grep -i … | tail -5; echo $?` prints 0
# even when grep found nothing). journalctl is the kernel-side judge.
journalctl -k --since '-2 min' 2>/dev/null | grep -E 'apparmor="DENIED"' | grep -i nsjail > /tmp/nsjail-denial.txt   # rev 7: exact-DENIED form — the rev-5/6 `apparmor.*nsjail` form false-fires on benign apparmor="STATUS" profile_replace lines (executed 2026-11-12, logged in the Execution log)
DISCRIM_GREP=$?
JCTL_STATUS=${PIPESTATUS[0]}   # R6-2: journalctl's own status — a failed journal read produces EMPTY
                              # stdin, grep exits 1 (indistinguishable from no-denial) without this
[ "$JCTL_STATUS" -eq 0 ] || { echo "JOURNAL READ FAILED (journalctl exit $JCTL_STATUS) — hard stop"; exit 1; }
echo "DISCRIM_GREP=$DISCRIM_GREP (1 = no denial = pass; 0 = denial found; >=2 = journal/grep failure)"
if [ "$DISCRIM_GREP" -eq 0 ]; then cat /tmp/nsjail-denial.txt; echo 'APPARMOR DENIAL PRESENT — profile did not take — hard stop'; exit 1; fi
if [ "$DISCRIM_GREP" -ge 2 ]; then echo 'JOURNAL GREP FAILED — cannot judge the profile — hard stop'; exit 1; fi
echo 'NSJAIL_DISCRIMINATOR=PASS'
```

EXPECTED: exit 0, plus the script's output shape (**quoted from source `scripts/host-fix-nsjail-userns.sh:49-105`, not from an executed run** — rev 4 R4-4 labels this per rule 7; the script was last run Sep 24 and has not been re-executed in any seat since):

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

The script rewrites and reloads the profile **unconditionally** — `cat > "$PROFILE"` then `apparmor_parser -r "$PROFILE"` — and has no "already loaded" branch (`grep -n "already" scripts/host-fix-nsjail-userns.sh` → no match). **The profile pre-exists on this host**: `/etc/apparmor.d/nsjail-userns`, `root`, 775 bytes, Sep 24 17:55, containing the tree-absolute nsjail path — i.e. written by this script on Sep 24. A re-run is therefore a **no-op reload and is success**; the evidence bundle must record that the profile pre-existed (A6a's regeneration-from-config statement). It uses the `vendor/adevtool/dl/` cache — **no network required** (`P5-S1-build-integration.md:82`).

FAILED: non-zero exit **after** `SUDO_EXIT=0` → STOP, paste output. That is the AppArmor fix itself failing (or the script's own precondition, e.g. a missing `dl/` cache), and it is distinct from the privilege case above — the two must not be conflated in the evidence bundle. a post-reload AppArmor **DENIAL** is caught by the **executed gate in the block above** (`DISCRIM_GREP=0` → `APPARMOR DENIAL PRESENT — hard stop`; `>=2` → `JOURNAL GREP FAILED — hard stop`; only `DISCRIM_GREP=1` + `NSJAIL_DISCRIMINATOR=PASS` proceeds — the verdict is gated, not judged by eye; R5-2). **Do not** judge the fix with a bare `nsjail` probe — it fails even when the fix is correct (`PROJECT-STATUS.md:257`, `PHASE-2-SOURCE-AND-BUILD-FOUNDATION.md:363`); exit status + journal are the judges.

**S6.2 — regenerate**

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
rm -f /home/cptjaqx/adevtool-generate-all.log
GALOG_TS=$(date +%s); echo "GALOG_TS=$GALOG_TS"
printf '%s\n' "$GALOG_TS" > /tmp/adevtool-galog.ts
PATH="$HOME/android-sdk/node24/bin:$PATH" vendor/adevtool/bin/run generate-all -d akita 2>&1 | tee /home/cptjaqx/adevtool-generate-all.log | tail -30
echo "EXIT=${PIPESTATUS[0]}"
```

**Log-freshness gate (rev 3, NEW-5 — run before judging the tail):** the log is removed first, and its existence after the run is asserted, so a run that exits 0 while writing **zero** output cannot leave the previous run's tail to be read as this run's completion.

```bash
test -s /home/cptjaqx/adevtool-generate-all.log || { echo 'LOG MISSING OR EMPTY — hard stop (generate-all wrote nothing)'; exit 1; }
test -s /tmp/adevtool-galog.ts || { echo 'GALOG MARKER MISSING: /tmp/adevtool-galog.ts — run S6.2 run block, hard stop'; exit 1; }
GALOG_TS=$(cat /tmp/adevtool-galog.ts)
case "$GALOG_TS" in ''|*[!0-9]*) echo "GALOG_TS malformed: [$GALOG_TS] — hard stop"; exit 1;; esac
GALOG_MTIME=$(stat -c %Y /home/cptjaqx/adevtool-generate-all.log)
echo "GALOG_MTIME=$GALOG_MTIME GALOG_TS=$GALOG_TS"
[ "$GALOG_MTIME" -ge "$GALOG_TS" ] || { echo "LOG IS STALE (mtime $GALOG_MTIME < $GALOG_TS) — hard stop"; exit 1; }

# R4-1: the tail comparison is a command, not a judgement call (closes BUG #5)
LAST_LINE=$(tail -1 /home/cptjaqx/adevtool-generate-all.log)
echo "LAST_LINE=$LAST_LINE"
[ "$LAST_LINE" = "Generated vendor module at vendor/google_devices/akita" ] || { echo "LOG TAIL MISMATCH — expected 'Generated vendor module at vendor/google_devices/akita', got '$LAST_LINE' — hard stop"; exit 1; }
```

EXPECTED: `EXIT=0`; the log exists, is non-empty, and `GALOG_MTIME ≥ GALOG_TS` (written by this run, not a leftover); and the gate's equality check prints `LAST_LINE=Generated vendor module at vendor/google_devices/akita` — **the comparison is executed by the block above (rev 4, R4-1), not compared by eye**.

```
Generated vendor module at vendor/google_devices/akita
```

**Provenance of that string (NEW-1):** it was taken from the executed `tail -1 /home/cptjaqx/adevtool-generate-all.log | cat -A` — the Sep 24 17:58:16 run, 50 lines, the run that produced the current 4739-file tree (`grep -n "Generating" <log>` → no match, rc=1; `grep -rn "Generating" vendor/adevtool/src/` → 0 matches). Rev 2's `Generating mk for akita` was **invented**: it matched nothing in the source or the log, so a correct run would have failed its own gate. That is NEW-1, and it is why every string in rev 3 is re-executed before it is written.

Run `tail -1 /home/cptjaqx/adevtool-generate-all.log` and compare **exactly**. If the executed log's last line differs from that string, **record it verbatim and STOP** — a different final line means either a different adevtool version or a run that did not reach completion. (Rev 1 accepted "the tail shows the generator's completion lines", which any run — including a no-op — satisfies; that is BUG #5, now closed by NEW-1.) A `Build sandboxing disabled due to nsjail error.` line is **expected and not a failure** — note it: the generate-all still succeeded, and Phase 1c will see the same line from `m`.

FAILED: non-zero exit, the log missing/empty/stale, output ending at the nsjail stderr line with no completion (`spawnAsync` abort), or the final line is not the string above → **STOP**. Evidence to paste: `tail -40 /home/cptjaqx/adevtool-generate-all.log`, the exit code, `GALOG_MTIME`/`GALOG_TS`, and the last line. Do not re-run blindly; do not hand-edit `vendor/google_devices/akita` — a hand-edit is silently lost on the next `generate-all` (`P5-S1-build-integration.md:188`).

**S6.3 — target-state check: regenerated, not hand-edited (differential, BUG #4/#5/#8)**

> **Rev 2 note:** rev 1's assertions were vacuous. Three of five already passed before any work (`packages/phosphor` → 0, `inherit-product` present in `akita.mk`, `phosphor` → 0), the log check was a `tail -30` with no concrete expected string, the `vendor/google_devices`-not-in-`repo status` clause was a tautology, and `git -C vendor/google_devices status` could only error. The replacement is: (a) a content differential against S6.0's inventory, (b) a positive mtime delta proving files were rewritten, (c) the literal log string, (d) guarded greps whose `GREP_STATUS` is captured, and (e) a `repo status` expectation that names only `vendor/adevtool`. The remaining greps are kept as **seam checks**, not as regeneration proof.
>
> **Rev 4 note (supersedes the rev-3 two-count scheme):** leg (b) reads the marker file `/tmp/akita-before.ts` written by S6.0 and hard-stops if it is absent. The rev-3 "two independent mtime counts" cross-check was a **tautology** — `-newer /tmp/akita-before.mtime` duplicated `-newermt "@$BEFORE_TS"` over the same instant (Debugger R4 finding) — and is replaced by the **totality gate**: `NEWER_TS_COUNT + PRESERVED_COUNT == BEFORE_FILES`, with `PRESERVED_COUNT == OLD_PRESERVED_COUNT` (the preserved-mtime set S6.0 baselines; known-good = 3 zip-mtime files).

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900

# (a) post-run inventory + content differential
find vendor/google_devices/akita -type f | sort | xargs sha256sum > /tmp/akita-after.sha256; AX=$?
echo "SHA256_STATUS=$AX"
case "$AX" in 0) ;; *) echo "sha256sum status $AX — hard stop"; exit 1;; esac
AFTER_FILES=$(wc -l < /tmp/akita-after.sha256)
echo "AFTER_FILES=$AFTER_FILES"
if diff -q /tmp/akita-before.sha256 /tmp/akita-after.sha256 > /tmp/akita.diff; then
  echo "INVENTORY=IDENTICAL"
else
  echo "INVENTORY=CHANGED"; diff /tmp/akita-before.sha256 /tmp/akita-after.sha256 | head -20
fi

# (b) mtime delta + totality (rev 4 R4-2 + rev 5 R5-1: fixed-cutoff preserved set)
test -s /tmp/akita-before.ts || { echo 'MARKER MISSING: /tmp/akita-before.ts — run S6.0, hard stop'; exit 1; }
BEFORE_TS=$(cat /tmp/akita-before.ts)
echo "BEFORE_TS=$BEFORE_TS"
case "$BEFORE_TS" in ''|*[!0-9]*) echo "BEFORE_TS malformed: [$BEFORE_TS] — hard stop"; exit 1;; esac
BEFORE_FILES=$(wc -l < /tmp/akita-before.sha256)   # re-derived from S6.0's file, not a cross-shell variable
OLD_PRESERVED_COUNT=$(wc -l < /tmp/akita-before-preserved.txt)
NEWER_TS_COUNT=$(find vendor/google_devices/akita -type f -newermt "@$BEFORE_TS" -printf '%p\n' | wc -l)
echo "NEWER_TS_COUNT=$NEWER_TS_COUNT OLD_PRESERVED_COUNT=$OLD_PRESERVED_COUNT"
# R5-1: preserved set re-derived with the SAME fixed cutoff, then compared as a SET, not a count
find vendor/google_devices/akita -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/akita-after-preserved.txt
PRESERVED_COUNT=$(wc -l < /tmp/akita-after-preserved.txt)
echo "PRESERVED_COUNT=$PRESERVED_COUNT"
[ "$PRESERVED_COUNT" -eq "$OLD_PRESERVED_COUNT" ] || { echo "PRESERVED SET CHANGED ($OLD_PRESERVED_COUNT -> $PRESERVED_COUNT) — hard stop"; exit 1; }
diff -q /tmp/akita-before-preserved.txt /tmp/akita-after-preserved.txt || { echo 'PRESERVED SET CONTENT DIFFERS (same count, different files) — hard stop'; exit 1; }
[ "$NEWER_TS_COUNT" -gt 0 ] || { echo 'NEWER_TS_COUNT=0 — the generator wrote nothing — hard stop'; exit 1; }
[ "$((NEWER_TS_COUNT + PRESERVED_COUNT))" -eq "$BEFORE_FILES" ] || { echo "TOTALITY VIOLATION: NEWER_TS_COUNT($NEWER_TS_COUNT) + PRESERVED_COUNT($PRESERVED_COUNT) != BEFORE_FILES($BEFORE_FILES) — a partial rewrite cannot pass — hard stop"; exit 1; }
find vendor/google_devices/akita -type f -printf '%T@ %p\n' | sort -k2 > /tmp/akita-after.mtime.txt
MTIME_SNAPSHOT_DELTA=$(diff /tmp/akita-before.mtime.txt /tmp/akita-after.mtime.txt | grep -c '^[<>]')
echo "MTIME_SNAPSHOT_DELTA=$MTIME_SNAPSHOT_DELTA"

# (c) the literal completion line — executed comparison (rev 4, R4-1, second site)
LAST_LINE=$(tail -1 /home/cptjaqx/adevtool-generate-all.log)
[ "$LAST_LINE" = "Generated vendor module at vendor/google_devices/akita" ] || { echo "LOG TAIL MISMATCH in S6.3 leg (c): got '$LAST_LINE' — hard stop"; exit 1; }
echo "LEG_C_TAIL_OK=1"

# (d) guarded seam greps — tree asserted first, grep status captured
# (d) guarded seam greps — tree asserted first, grep status captured
test -d vendor/google_devices/akita || { echo 'TREE MISSING — hard stop'; exit 1; }
grep -rn 'packages/phosphor' vendor/google_devices/akita/ > /tmp/akita-seam.grep; GS1=$?
echo "PHOSPHOR_LINE_COUNT=$(wc -l < /tmp/akita-seam.grep) GREP_STATUS=$GS1"
case "$GS1" in 0|1) ;; *) echo "GREP_STATUS=$GS1 — hard stop"; exit 1;; esac

test -f vendor/google_devices/akita/akita.mk || { echo 'akita.mk MISSING — hard stop'; exit 1; }
grep -n 'inherit-product' vendor/google_devices/akita/akita.mk; GS2=$?
echo "AKITAMK_STATUS=$GS2"
case "$GS2" in 0|1) ;; *) echo "GREP_STATUS=$GS2 — hard stop"; exit 1;; esac

grep -rn 'phosphor' vendor/google_devices/akita/ > /tmp/akita-word.grep; GS3=$?
echo "PHOSPHOR_WORD_COUNT=$(wc -l < /tmp/akita-word.grep) GREP_STATUS=$GS3"
case "$GS3" in 0|1) ;; *) echo "GREP_STATUS=$GS3 — hard stop"; exit 1;; esac

test -f vendor/adevtool/config/mk/google_devices/device/akita/device.mk || { echo 'device.mk MISSING — hard stop'; exit 1; }
git -C vendor/adevtool diff -- config/mk/google_devices/device/akita/device.mk > /tmp/adevtool-seam.diff; GS4=$?
echo "SEAM_GREP_STATUS=$GS4"
case "$GS4" in 0|1) ;; *) echo "GREP_STATUS=$GS4 — hard stop"; exit 1;; esac
echo "SEAM_MATCH_COUNT=$(grep -c '^+.*phosphor' /tmp/adevtool-seam.diff)"

repo status -j24
```

EXPECTED (one line per check; each is a pass condition):
- `SHA256_STATUS=0`
- `AFTER_FILES=4739` — **equal to `BEFORE_FILES`** (carry-along 1: assert before-count == after-count, so a `sha256sum` failure that silently shrinks the inventory cannot read as a pass)
- `INVENTORY=IDENTICAL` — **this is the regeneration proof**: a generate-all that did nothing leaves the inventory identical too, so it is necessary but not sufficient; (b) and (c) close that gap.
- `BEFORE_TS` = the 10-digit epoch S6.0 wrote; `NEWER_TS_COUNT > 0` (the generator wrote something); `PRESERVED_COUNT == OLD_PRESERVED_COUNT` **with identical set content (`diff -q` of the two preserved snapshots)** and `NEWER_TS_COUNT + PRESERVED_COUNT == BEFORE_FILES` — **the totality gate (rev 5 R5-1, fixed cutoff `2026-01-01`)**: the known-good run rewrites 4736 of 4739 files and preserves exactly the 3 zip-mtime files, so a 3-of-4739 partial rewrite now fails (`PRESERVED_COUNT` would jump from 3 to 4736). `MTIME_SNAPSHOT_DELTA > 0`. A `0` from any count means the generator wrote nothing, which is exactly the silent no-op these checks exist to catch.
- the literal log line `Generated vendor module at vendor/google_devices/akita` (S6.2's string, NEW-1)
- `PHOSPHOR_LINE_COUNT=0 GREP_STATUS=1` — our line is **absent** from the generated tree (the inherit arrives via `akita.mk`'s existing `device.mk` inheritance, preflight line 104)
- `10:$(call inherit-product, vendor/adevtool/config/mk/google_devices/device/akita/device.mk)` and `AKITAMK_STATUS=0` — unchanged
- `PHOSPHOR_WORD_COUNT=0 GREP_STATUS=1` — no `phosphor` string anywhere in the generated project
- `SEAM_MATCH_COUNT=1`, `SEAM_GREP_STATUS=0` — the seam line still exists in the *config* file after regeneration (proves generate-all did not revert our source-config edit)
- `repo status -j24`: **exactly one** dirty project — `vendor/adevtool` with its five entries (the four baseline entries **plus** `device.mk`) — and nothing else. (`packages/phosphor` is a cleanly synced project and must **not** appear here; `vendor/google_devices` is not a repo project and cannot appear here at all.)

> **FAILED-note (carry-along 3, re-pointed rev 6):** the world that still passes all legs is **content-only restore** — a second process restores a file's pre-run content but leaves its mtime at run time. (A content-**and**-mtime restore is now CAUGHT: restored mtimes drop out of `NEWER_TS_COUNT`, totality breaks, L533 STOPs — audited round 4.) Out of scope for this plan; noted so a future reader does not mistake the legs for an anti-tamper proof.

FAILED (any line off → STOP, paste that line's output):
- `MARKER MISSING` → S6.0 was not run in this seat (or `/tmp` was cleared). Re-run S6.0 before S6.3; never substitute `BEFORE_TS=0`.
- `INVENTORY=CHANGED` → the regeneration is **not deterministic**: content churn in an untracked tree. Paste the first 20 diff lines and report whether it is namespace/overlay churn. This is an A5-grade finding, not something to revert.
- `NEWER_TS_COUNT=0`, or the preserved count/set differing from S6.0's baseline, or `MTIME_SNAPSHOT_DELTA=0` → the generator wrote nothing (or wrote the wrong things). Combined with a non-zero exit in S6.2 this is the `spawnAsync` abort; combined with `EXIT=0` it means a no-op run that rev 1 would have scored as a pass.
- `AFTER_FILES` ≠ `BEFORE_FILES` → the inventory changed size; report both numbers (a `sha256sum` error is the likeliest cause, and it is a hard stop, not a diff to interpret).
- any `GREP_STATUS=2` → hard stop (BUG #8): grep could not read the tree, so a count of `0` is **not** evidence of absence.
- `PHOSPHOR_LINE_COUNT>0` → our line is in the generated tree: it was hand-edited at some point, or generate-all copied it. Per `P5-S1-build-integration.md:188` the handling is regenerate, never hand-edit — and since we just regenerated, a non-zero count means the seam is in the wrong file, a spec-level find.
- the seam count `0` → generate-all reverted `device.mk`, contradicting B4.
- any other dirty project in `repo status` → STOP; `vendor/google_devices` can never appear here (not a repo project), so any appearance would mean the manifest is wrong.

---

## S7. Re-pin the manifest (A6b) — write-temp-then-`mv` (BUG #7)

**Purpose:** record our project at a 40-hex commit in `.repo/manifest-pinned.xml`, so Phase 2's provenance claim stays valid for GrapheneOS projects while ours is pinned separately (B6 line 120).

> **Why the redirect is replaced (BUG #7).** `repo manifest -r > .repo/manifest-pinned.xml` truncates the **1085-line / 245571-byte** provenance artifact *before* `repo` runs, no exit code is captured, and a failure leaves a 0-byte file. `.repo` is tracked by no project, so git cannot restore it and the Phase-2 provenance evidence is gone. The fix is the same shape as S6.2's log: write to a temp path, capture the exit code, verify the content, and `mv` only after the checks pass.
>
> **Rev 3 note (NEW-3) — S7 is ONE bash block.** Rev 2 set `REPO_EXIT` in a verify block and tested it in a second block; under rule 5 that variable is empty in a fresh shell, and the executed proof is `bash -c 'case "$REPO_EXIT" in 0) echo ok;; *) echo "REPO_EXIT=[$REPO_EXIT] — not promoting"; exit 1;; esac'` → `REPO_EXIT=[] — not promoting`. S7 therefore runs verify, gates and `mv` in a **single invocation**, captures `REPO_EXIT` in that same shell, and then verifies the **promoted** file (not only the temp). This is the second named rule-5 exception.

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
rm -f .repo/manifest-pinned.xml.new
repo manifest -r > .repo/manifest-pinned.xml.new
REPO_EXIT=$?
echo "REPO_EXIT=$REPO_EXIT"
NEW_LINES=$(wc -l < .repo/manifest-pinned.xml.new)
echo "NEW_LINES=$NEW_LINES"
grep -n 'path="packages/phosphor"' .repo/manifest-pinned.xml.new
PIN_LINES=$(grep -c 'path="packages/phosphor"' .repo/manifest-pinned.xml.new)
echo "PIN_LINES=$PIN_LINES"
PIN_REV=$(grep 'path="packages/phosphor"' .repo/manifest-pinned.xml.new | grep -o 'revision="[0-9a-f]\{40\}"')
echo "PIN_REV=$PIN_REV"

# gates — all in this same shell
case "$REPO_EXIT" in 0) ;; *) echo "REPO_EXIT=$REPO_EXIT — not promoting"; exit 1;; esac
[ "$NEW_LINES" -eq 1087 ] || { echo "NEW_LINES=$NEW_LINES != N+2 — not promoting"; exit 1; }
[ "$PIN_LINES" -eq 1 ] || { echo "PIN_LINES=$PIN_LINES != 1 — not promoting"; exit 1; }
[ -n "$PIN_REV" ] || { echo 'PIN_REV empty (revision not 40-hex) — not promoting'; exit 1; }
grep -q '<remote' .repo/manifest-pinned.xml.new || { echo 'remote element missing — not promoting'; exit 1; }

# promote, then verify the promoted artifact
mv .repo/manifest-pinned.xml.new .repo/manifest-pinned.xml
echo "MOVED=ok"
wc -l .repo/manifest-pinned.xml
echo "FINAL_LINES=$(grep -c 'path="packages/phosphor"' .repo/manifest-pinned.xml)"
grep -n 'path="packages/phosphor"' .repo/manifest-pinned.xml
grep -c 'path="packages/phosphor"' .repo/manifest-pinned.xml | grep -q '^1$' || { echo 'POST-MV CHECK FAILED — pin is not exactly one line'; exit 1; }
grep 'path="packages/phosphor"' .repo/manifest-pinned.xml | grep -o 'revision="[0-9a-f]\{40\}"'   # R5-3: scoped — the unscoped form emits ToXml's FIRST project revision, not ours (1057 40-hex revisions live in this file)
```

EXPECTED (all in one output):
- `REPO_EXIT=0`; `NEW_LINES=1087` (N+2, N = the S0.5 count 1085)
- the grep shows the `<project … path="packages/phosphor" …/>` line, and `PIN_LINES=1`. The second new line is the `<remote name="phosphor" …/>` element that `ToXml` serialises alongside it (`manifest_xml.py:613-616`); because the remote carries no `path=` attribute, `grep 'path="packages/phosphor"'` prints **one** line, not two. Confirm the remote with `grep -n '<remote'`. Rev 1 expected N+1 and would have flagged a correct run as a failure.
- `PIN_REV=revision="acba3945152acbb2a70d142e6ad4c535ed245c23"` — 40-hex, not `refs/heads/main`. The `<project>` line's real attribute set is `upstream="refs/heads/main" dest-branch="refs/heads/main" groups="local::phosphor"` alongside that revision. Record both new lines **verbatim**.
- `MOVED=ok`, then `1087`, then `FINAL_LINES=1` — the post-`mv` check closes the loop on the **promoted** file, not only the temp.

FAILED:
- `REPO_EXIT` ≠ 0, or `NEW_LINES` ≠ 1087, or `PIN_LINES` ≠ 1, or `PIN_REV` empty, or no `<remote` element → **STOP**, paste both counts and `grep -c phosphor .repo/manifest-pinned.xml.new`. `.repo/manifest-pinned.xml` has **not** been touched (the temp file is a separate inode); the original 1085-line artifact is intact. Do not `mv` a bad temp over it.
- `MOVED=ok` is absent → **STOP**; the original file is unchanged and the pin was not written.
- `FINAL_LINES` ≠ 1 or the post-`mv` 40-hex grep prints nothing → **STOP**; the promoted artifact does not carry the pin. Restore is the Supervisor's call — `.repo` is tracked by no project, so there is no `git checkout` for it.

---

## S8. Final acceptance block for Phase 1b (evidence bundle)

Run in one go, paste the whole output. This is the block the Debugger audits and the Supervisor verifies independently.

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
echo '== A1: manifest applies =='
repo manifest | grep -c 'path="packages/phosphor"'
git ls-remote /home/cptjaqx/projects/Phosphor-platform.git | head -3
echo '== A5: repo status (expected: vendor/adevtool only, 5 entries incl. device.mk) =='
repo status -j24
echo '== A5: the one-line diff =='
git -C vendor/adevtool diff --stat -- config/mk/google_devices/device/akita/device.mk
git -C vendor/adevtool diff -- config/mk/google_devices/device/akita/device.mk
echo '== A4-adjacent: payload is a clean checkout of the 1a commit =='
git -C packages/phosphor rev-parse HEAD
git -C packages/phosphor status --porcelain | wc -l
echo '== generated tree: seam absent, regeneration differential =='
test -d vendor/google_devices/akita || { echo 'TREE MISSING — hard stop'; exit 1; }
grep -rn 'packages/phosphor' vendor/google_devices/akita/ > /tmp/akita-s8.grep; GS=$?
echo "PHOSPHOR_LINE_COUNT=$(wc -l < /tmp/akita-s8.grep) GREP_STATUS=$GS"
case "$GS" in 0|1) ;; *) echo "GREP_STATUS=$GS — hard stop"; exit 1;; esac
find vendor/google_devices/akita -type f | sort | xargs sha256sum > /tmp/akita-s8.sha256
echo "S8_FILES=$(wc -l < /tmp/akita-s8.sha256)"
diff -q /tmp/akita-before.sha256 /tmp/akita-s8.sha256 && echo 'INVENTORY=IDENTICAL'
echo '== generate-all log: last line must be the literal completion string (R4-1: executed comparison) =='
LAST_LINE=$(tail -1 /home/cptjaqx/adevtool-generate-all.log)
echo "LAST_LINE=$LAST_LINE"
[ "$LAST_LINE" = "Generated vendor module at vendor/google_devices/akita" ] || { echo 'LOG TAIL MISMATCH (S8) — hard stop'; exit 1; }
echo '== A6b: pin delta (N+2) =='
wc -l .repo/manifest-pinned.xml
grep -n 'path="packages/phosphor"' .repo/manifest-pinned.xml
echo '== A6b: post-mv pin still exactly one 40-hex line =='
echo "FINAL_LINES=$(grep -c 'path="packages/phosphor"' .repo/manifest-pinned.xml)"
grep 'path="packages/phosphor"' .repo/manifest-pinned.xml | grep -o 'revision="[0-9a-f]\{40\}"'   # R5-3: scoped — the unscoped form emits ToXml's FIRST project revision, not ours (1057 40-hex revisions live in this file)
echo '== A7: PLAN LINT ONLY (this file, not the session) =='
grep -cE '^[[:space:]]*(adb|fastboot)[[:space:]]' /home/cptjaqx/projects/Phosphor/docs/handoffs/P5-S1-PHASE-1b-PLAN.md
```

EXPECTED summary (each item is a pass condition, in output order):
`1` · `refs/heads/main → acba3945152acbb2a70d142e6ad4c535ed245c23` · `vendor/adevtool` only with 5 entries · `1 file changed, 1 insertion(+)` · one-insertion diff with hunk `@@ -6,3 +6,4 @@` · `acba3945152acbb2a70d142e6ad4c535ed245c23` · `0` · `PHOSPHOR_LINE_COUNT=0 GREP_STATUS=1` · `S8_FILES=4739` · `INVENTORY=IDENTICAL` · `LAST_LINE=Generated vendor module at vendor/google_devices/akita` (executed equality, rev 4 R4-1) · `1087` (N+2) · the pin line (project, 40-hex revision, `groups="local::phosphor"`) · `FINAL_LINES=1` · `revision="acba3945152acbb2a70d142e6ad4c535ed245c23"` · `0` for the plan lint.

FAILED: any item off → STOP with that line's output. Phase 1c must not start until this block passes and the Debugger's audit is clean (instructions L59: "after 1a audit is clean" — the same gate applies to 1b → 1c).

> **A7 evidence (BUG #9).** The final `grep -cE '^[[:space:]]*(adb|fastboot)[[:space:]]' …` is a **plan lint, not execution evidence**: it inspects this document, which never changes, so it prints the same `0` before and after any execution — including one that ran `adb`. It is retained only as a check that no device command is *written into* this plan. **The sole A7 artifact is the execution transcript** — the pasted output of every command from S0.1 to S8 above — plus the session log. Do not present the plan-lint grep as proof that no device tool ran.

---

## 9. What Phase 1b must NOT do (audit checklist for the execution round)

- [ ] No `m`/`lunch`/`envsetup` — the build is Phase 1c (A2). Any `out/` change in 1b is out of scope.
- [ ] No second edit to `vendor/adevtool` beyond the one `device.mk` line; no edit to `vendor/google_devices/**` at all.
- [ ] No device tooling, no `sudo` except S6.1's AppArmor script.
- [ ] No `/system/app/` string written anywhere (rev-2 erratum; this phase writes no install paths at all — the assertion is that none appear in any 1b artifact).
- [ ] No `init_rc`, no `.te` files, no `.rc` files, no manifest components introduced (1b writes none of these files).
- [ ] `OFFICIAL_BUILD` unset and never used.

---

## COMPLETENESS (template — one line per planned step, plus one line per BUG proving the repair)

Two halves. **Part A** is the executing round's checklist (one line per planned step, filled with pasted evidence). **Part B** is this author round's repair proof: one `[x]` line per audited BUG # (rev 2) and one per NEW item (rev 3), each citing the rev-3 line number where the repair lives and the command output that confirms it. Both halves are already filled in — they are the deliverable of the author round.

**Part A — step checklist (execution round fills the evidence):**

```
COMPLETENESS:
- [ ] S0.1 Phase-1a repo present, branch main, HEAD acba3945152acbb2a70d142e6ad4c535ed245c23, worktree clean — evidence: <3 command outputs>
- [ ] S0.2 mirror absent before creation — evidence: <ls output>
- [ ] S0.3 no pre-existing local manifest / no packages/phosphor in manifests — evidence: <ls + grep output>
- [ ] S0.4 device.mk seam clean: **8** lines, 0 matches, clean git status, content recorded with its two blank lines — evidence: <outputs>
- [ ] S0.5 baselines: manifest-pinned line count N = 1085, repo status baseline, out/ size — evidence: <outputs>
- [ ] S1 bare mirror created at /home/cptjaqx/projects/Phosphor-platform.git — evidence: <clone output>
- [ ] S1v mirror is bare, HEAD refs/heads/main, HEAD == acba3945152acbb2a70d142e6ad4c535ed245c23 — evidence: <4 command outputs>
- [ ] S2 .repo/local_manifests/phosphor.xml written, XML valid — evidence: <cat + "XML OK">
- [ ] S3.1 A1 assertion: repo manifest | grep -c path="packages/phosphor" == 1 — evidence: <count + line>
- [ ] S3.2 mirror fetchable over file://, literal-B6 composition fails — evidence: <2 git ls-remote outputs>
- [ ] S4.1 repo sync -n exit 0, no error lines — evidence: <tail + EXIT>
- [ ] S4.2 repo sync packages/phosphor exit 0; packages/phosphor HEAD == acba394…; clean — evidence: <outputs + ls -a>
- [ ] S4.3 no GrapheneOS project disturbed — evidence: <repo status -j24>
- [ ] S5 device.mk +1 line appended, exactly 1 insertion / 0 deletions — evidence: <wc -l **9**, diff --stat (device.mk only), diff body with hunk @@ -6,3 +6,4 @@>
- [ ] S6.0 pre-run inventory: `/tmp/akita-before.sha256` (4739 files, SHA256_STATUS=0), `/tmp/akita-before.ts` marker, `/tmp/akita-before-preserved.txt` baseline (OLD_PRESERVED_COUNT=3) — evidence: <outputs>
- [ ] S6.1 precondition sudo -n true → SUDO_EXIT=0 (interactive seat), then host-fix-nsjail-userns.sh re-applied with exit 0, profile pre-existence recorded — evidence: <SUDO_EXIT + real script output + EXIT>
- [ ] S6.2 `rm` log + GALOG_TS freshness gate; generate-all -d akita exit 0 with node24 PATH; log non-empty and not stale; last line == "Generated vendor module at vendor/google_devices/akita" — evidence: <GALOG_MTIME/GALOG_TS + tail + EXIT + log last line>
- [ ] S6.3 regeneration differential: SHA256_STATUS=0, AFTER_FILES == BEFORE_FILES, INVENTORY=IDENTICAL, NEWER_TS_COUNT > 0, PRESERVED_COUNT == OLD_PRESERVED_COUNT == 3 (STOP if ≠3), preserved-set diff -q IDENTICAL, NEWER_TS_COUNT + PRESERVED_COUNT == BEFORE_FILES (totality gate), MTIME_SNAPSHOT_DELTA > 0, executed tail equality passes, seam greps GREP_STATUS ∈ {0,1}, seam still in config, repo status = vendor/adevtool only — evidence: <block output>
- [ ] S7 re-pin in ONE shell: REPO_EXIT=0, NEW_LINES=1087 (N+2), PIN_LINES=1, PIN_REV 40-hex, `<remote` present, then `mv` → MOVED=ok → FINAL_LINES=1 + 40-hex on the promoted file — evidence: <single block output>
- [ ] S8 final acceptance block passes line-for-line — evidence: <full block output>
- [ ] A7 no device operation — evidence: **execution transcript** (every command S0.1–S8), not the plan lint
- Rationale (D-5, R-1 ruled ACCEPTED): manifest expresses `fetch="file:///home/cptjaqx/projects"` + `name="Phosphor-platform.git"` rather than B6's literal single-`.git`-path fetch, because repo joins fetch+"/"+name — proved by the tree's own `.repo/repo/manifest_xml.py:232-233` (`fetchUrl.rstrip("/")` then `+ "/" + projectName`) and by B6's own ssh form composing qsmtco/Phosphor-platform; this keeps the mandated mirror path, the mount point, and the pinned branch byte-identical while making the join land on a real repository.
- Rationale (S5): `printf … >>` append instead of an editor/`sed`, so a diff can only ever be one insertion and the file's existing bytes cannot be touched.
- Rationale (S6.3): asserting **0** matches for our line in `vendor/google_devices/akita` is deliberate — the inherit must arrive via `akita.mk`'s existing `device.mk` inheritance, so a match there would mean a hand-edit or a copied seam, both failures.
- Rationale (S6.0/S6.3, BUG #4/#5): the regeneration proof is a **differential**, not a grep. A grep over an untracked tree cannot fail (it has no git status to contradict it) and three of rev 1's five assertions already passed on the untouched tree; only a before/after sha256 inventory plus an mtime delta and the literal log line can distinguish "regenerated" from "did nothing".
- Rationale (S7, BUG #7): write-temp-then-`mv` with an exit-code gate, because the redirect form truncates the 1085-line provenance artifact before `repo` runs and `.repo` is tracked by no project, so a failed run destroys unrecoverable evidence.
```

**Part B — repair proof (one `[x]` line per audited BUG # and per NEW item, author round, evidence = the rev-3 line where the repair lives and the executed command that confirms it):**

```
REPAIR-COMPLETENESS (rev 3):
- [x] BUG #1 (HIGH) — S0.4 expectation 8 lines + real 8-line content block, platform/zuma, blank lines 2 and 5; S5 post-append wc -l 9; global rule 7 added — evidence: line 118 ("EXPECTED — `8` lines"), lines 120-128 (make block with two blank lines and no `device/` segment), line 350 ("`wc -l` → `9`"), line 43 (rule 7 "never from a rendered or line-numbered view"). Probe: `read_file docs/specs/P5-S1-PREFLIGHT-PROBE.md` L97,L101 → `.../google_devices/platform/zuma/...` (no `device/`); Supervisor's executed `wc -l` = 8.
- [x] BUG #2 (HIGH) — void command deleted; S3.2 is two real commands; FAILED re-pointed; composition stated from manifest_xml.py:232-233 — evidence: line 255 ("rev 1 ran `git ls-remote file:///home/cptjaqx/projects` … It is deleted"), lines 257-259 (only the two `…/Phosphor-platform.git` commands), line 266 ("FAILED: the **first** command fails"), line 31 ("stated, not tested").
- [x] BUG #3 (HIGH) — S7 expects N+2 with both lines named; full attribute set incl. groups="local::phosphor"; N = 1085 recorded — evidence: lines 585-597 (rev 3: `NEW_LINES -eq 1087`, `PIN_LINES -eq 1`, `PIN_REV` 40-hex, `<remote` gate), line 144 (N = 1085).
- [x] BUG #4 (HIGH) — S6.0 sha256 inventory + marker; S6.3 differential with diff -q and mtime delta; git -C vendor/google_devices deleted — evidence: lines 376-395 (S6.0: `test -d` guard, `SHA256_STATUS`, `xargs sha256sum > /tmp/akita-before.sha256`, `BEFORE_FILES=4739`), lines 486-490 (`diff -q … INVENTORY=IDENTICAL`), lines 492-501 (marker read + two mtime counts + snapshot delta), line 374 ("not a git repository … not a repo project").
- [x] BUG #5 (HIGH) — **now closed by NEW-1.** Rev 2 replaced "the tail shows the completion lines" with a *literal expected string* but invented it; the shape of the fix (a concrete string + record-verbatim-and-STOP) was right, the string was not. Rev 3: line 459 (`Generated vendor module at vendor/google_devices/akita`), lines 461-463 (provenance: executed `tail -1 | cat -A`, Sep 24 17:58, 50 lines), line 533 (S6.3 leg (c)). Executed proof: `tail -1 /home/cptjaqx/adevtool-generate-all.log` → `Generated vendor module at vendor/google_devices/akita`; `grep -n "Generating" <log>` → no match, rc=1.
- [x] BUG #6 (MEDIUM) — hunk @@ -6,3 +6,4 @@; --stat restricted to device.mk — evidence: line 345 (`diff --stat -- config/mk/google_devices/device/akita/device.mk`), line 353 ("hunk header `@@ -6,3 +6,4 @@`"), line 352 ("that one file is … device.mk").
- [x] BUG #7 (MEDIUM) — **now closed by NEW-3.** Rev 2 added the temp file + exit-code gate; rev 3 removes the last cross-shell read by making S7 one bash block (verify, gate, `mv`, post-`mv` verify) — evidence: lines 562 (rev-3 note + executed proof of the rev-2 defect), lines 564-604 (single block: `REPO_EXIT=$?`, `NEW_LINES`, `PIN_LINES`, `PIN_REV`, `<remote` gate, `mv`, `MOVED=ok`, `FINAL_LINES`, post-`mv` 40-hex grep), lines 606-612 (FAILED states incl. "has **not** been touched").
- [x] BUG #8 (HIGH) — all three fraudulent-pass greps rebuilt: test -d first, capture status, 2 = hard stop — evidence: rule 8 at lines 44-51, S6.3 at lines 505-523 (`GS1`/`GS2`/`GS3`/`GS4` each with `case … 0|1 … *) hard stop`), S8 at lines 617-620 (`GS=$?` then `PHOSPHOR_LINE_COUNT=… GREP_STATUS=$GS`).
- [x] BUG #9 (MEDIUM) — plan lint relabelled, transcript made sole A7 artifact — evidence: line 40 (rule 4), lines 641-642 + 650 ("PLAN LINT ONLY" + note), line 693 (Part A "evidence: **execution transcript** … not the plan lint").
- [x] BUG #10 (MEDIUM) — sudo -n true precondition, privilege-vs-Apparmor failure split — evidence: lines 397-407 (S6.1 precondition block), line 405 (`SUDO_EXIT=0`), line 407 (interactive-seat STOP), line 436 ("distinct from the privilege case above").
- [x] BUG #11 (LOW) — bash-only global rule naming the four PIPESTATUS steps — evidence: line 42 (rule 6).

- [x] NEW-1 (CRITICAL) — S6.2's fabricated "literal" string replaced with the executed one; every echo updated (S6.2 expected/FAILED, S6.3 leg (c), S8 summary, Part A, revision log). Executed proof (mine, rev 3): `tail -1 /home/cptjaqx/adevtool-generate-all.log | cat -A` → `Generated vendor module at vendor/google_devices/akita$`; `wc -l` → `50`; `stat -c '%y'` → `2026-09-24 17:58:16.068988579 -0700`; `grep -n "Generating" <log>` → no match, rc=1; `grep -rn "Generating" vendor/adevtool/src/` → 0 matches. Evidence in plan: lines 459, 461-463, 533, 646.
- [x] NEW-2 (HIGH) — cross-block `$BEFORE_TS` replaced by a persisted marker file; the dead mtime snapshot given a reader; rule 5 exception named. Executed proof (Supervisor, re-derivable): `bash -c 'find vendor/google_devices/akita -type f -newermt "@$BEFORE_TS" -printf "%p\n" | wc -l'` → `0` (unset); `bash -c 'BEFORE_TS=0; … | wc -l'` → `4738`. Evidence in plan: rule 5 at line 41, S6.0 lines 379-388 (`printf … > /tmp/akita-before.ts`, `touch -d "@$BEFORE_TS" /tmp/akita-before.mtime`, `.mtime.txt`), S6.3 lines 492-501 (marker hard stop, two counts, snapshot delta).
- [x] NEW-3 (HIGH) — S7 verify + gates + `mv` merged into one bash invocation with `REPO_EXIT` captured in the same shell, plus post-`mv` verification on the promoted file. Executed proof (Supervisor, reproduced by inspection): `bash -c 'case "$REPO_EXIT" in 0) echo ok;; *) echo "REPO_EXIT=[$REPO_EXIT] — not promoting"; exit 1;; esac'` → `REPO_EXIT=[] — not promoting`. Evidence in plan: lines 562, 564-604 (single block), 606-612 (FAILED).
- [x] NEW-4 (MEDIUM) — S6.1's "already loaded" branch removed (the script has none) and replaced with the script's real output shape; profile pre-existence recorded for A6a. Executed proof: `read_file scripts/host-fix-nsjail-userns.sh` L49-105 → `==> Writing …`, `==> Loading the profile`, `==> Verification`, `1`, `still blocked (correct: …)`, `nsjail works now`, `==> Done.`; `grep -n "already" scripts/host-fix-nsjail-userns.sh` → no match. Evidence in plan: lines 418-434.
- [x] NEW-5 (MEDIUM) — `$GALOG` freshness gate added (`rm -f` before, `test -s` after, mtime ≥ GALOG_TS), and a missing/empty/stale log is a hard stop. Executed proof: the S6.2 block at lines 440-456 is the gate; `test -s` + `stat -c %Y` are the assertions. Evidence in plan: lines 442-444 (`rm -f`, `GALOG_TS`, `/tmp/adevtool-galog.ts`), 451-456 (gate), 469 (FAILED "log missing/empty/stale").
- [x] Carry-along 1 — `xargs sha256sum` status asserted (S6.0 `SHA256_STATUS`; S6.3 `AX`/`SHA256_STATUS`) and before-count == after-count made an explicit pass condition. Evidence: lines 382-383, 481-485, 530.
- [x] Carry-along 2 — S8's summary and Part A echo the corrected string; no stale `Generating mk for akita` remains. Executed proof: `search_files 'Generating mk for akita' docs/handoffs/P5-S1-PHASE-1b-PLAN.md` → 0 matches. Evidence: lines 646, 689.
- [x] Carry-along 3 — FAILED-note added that a content-and-mtime restore defeats all three legs; the differential is not an anti-tamper proof. Evidence: line 535.
```

---

## Related issues found, not fixed in this phase

1. **R-1 (spec erratum candidate, MEDIUM) — B6's development variant cannot resolve as literally written.** `P5-S1-build-integration.md:120` gives `fetch="file:///home/cptjaqx/projects/Phosphor-platform.git"` alongside `name="Phosphor-platform"` (line 116). `repo` composes `fetch + "/" + name` — **ruled ACCEPTED by the Supervisor 2026-11-11**, with the tree's own source as proof: `.repo/repo/manifest_xml.py:232-233` does `fetchUrl = self.resolvedFetchUrl.rstrip("/")` then `url = fetchUrl + "/" + projectName`, so the URL becomes `…/Phosphor-platform.git/Phosphor-platform` — not a repository — and `repo sync` fails with an error naming the path, not the spec. This plan carries the correction **inside a file the plan authors** (D-5/S2); the spec text itself is unfixed and is **erratum 4, pending PM approval** (the builder does not edit specs). **Status: ruled; erratum pending.**
2. **R-2 (alternative for R-1) — REJECTED by the Supervisor.** A nested bare mirror at `Phosphor-platform.git/Phosphor-platform` would let both B6 strings stay literal, but it makes the mandated mirror path a container rather than a repository, and a `.git` directory containing a project-named subdirectory is exactly the shape a later `git clone` or backup step mistakes for a working tree. Not executed. **Status: rejected, closed.**
3. **R-3 (LOW, wording)** — `PHASE-INSTRUCTIONS.md:61` calls `repo sync -n` a "dry" run. In `repo`, `-n` is `--network-only` (fetch, no working-tree update), not a no-op preview — confirmed by the Debugger from `sync.py:617-622`, and rev 1 never claimed dry-run semantics. Step S4.1 therefore judges it as "fetch succeeded", and the real tree mutation is S4.2's project-only sync. No behaviour change; the label in the instructions is loose. **Status: carried forward unchanged.**
4. **R-4 (LOW, provenance gap) — resolved for the hash, open for the evidence.** The 1a HEAD hash is **confirmed** by the Supervisor: `acba3945152acbb2a70d142e6ad4c535ed245c23` on `main`, `rev-list --count` = 1, porcelain empty; S0.1/S1/S4.2/S7/S8 all carry the literal hash and S4.2 makes it the 1a→1b provenance tie. **Still open:** the string `Upstream-phosphor` appears nowhere in the project tree, and `/home/cptjaqx/projects/Phosphor-platform` is outside this seat's sandbox, so the 1a evidence bundle itself is not auditable from inside the repo. The 1a audit trail should be archived into `docs/handoffs/` in a later round so the S7 pin can be traced to its authoring evidence. **Status: hash resolved; 1a evidence archive outstanding.**
5. **R-5 (LOW, `repo` semantics)** — after `repo sync`, `packages/phosphor` may be on a detached HEAD rather than branch `main` (repo's behaviour for `revision="refs/heads/main"` depends on its version). S4.2 records `--abbrev-ref HEAD` and treats the **commit hash** as binding; no `checkout` is performed. If a later phase needs a branch, that is a separate decision. **Status: carried forward unchanged.**
6. **R-6 (informational, for Phase 1c) — method corrected twice.** `generate-all` rewrites `vendor/google_devices/akita` wholesale (`P5-S1-build-integration.md:212` requires this cost be stated in the completion note). S6.0/S6.3 assert the regeneration with a **content differential** — before/after sha256 inventory, two mtime counts and a snapshot delta — not a git status: `vendor/google_devices` is not a repo project and can never appear in `repo status`. **Correction carried from the Debugger's post-fix audit:** the differential proves *the tree was rewritten*, not that it was rewritten *correctly*; and a process that restores both content and mtime passes all three legs (recorded as a FAILED-note in S6.3). A differential mismatch is a spec-level A5 finding, not a 1b defect. Phase 1c should also expect the `Build sandboxing disabled due to nsjail error.` stderr line from `m` and must not read it as failure. **Status: carried forward, method corrected under BUG #4 and NEW-2.**

---

## Revision log (rev 3)

Source of the **rev 2** entries: `docs/specs/P5-S1-PHASE-1b-REVISION-ORDER.md` (11 audited findings). Source of the **rev 3** entries: `docs/specs/P5-S1-PHASE-1b-REV3-ORDER.md` (NEW-1 CRITICAL, NEW-2/NEW-3 HIGH, NEW-4/NEW-5 MEDIUM, plus three carry-along items). Line numbers in the **rev 2 and rev 3 rows are the line numbers of those revisions at the time they were written — superseded; do not navigate by them**. Only the latest revision-log table (rev 6) carries current line numbers. Standing rulings (R-1 accepted with `manifest_xml.py:232-233`; A1a HEAD confirmed; D-1…D-4 ratified; erratum 4 pending PM approval) were applied, not re-argued.

**Rev 2 entries (BUG #1–#11; #1–#4, #6, #8–#11 verified CLOSED by the Debugger's post-fix re-audit; #5 and #7 closed in rev 3):**

| BUG # | Sev | What changed | Where (rev 2 lines) |
|---|---|---|---|
| **#1** | HIGH | S0.4 `wc -l` expectation `5` → **8**; the expected-content block replaced with the real 8 lines (blank lines 2 and 5 included, `platform/zuma` paths with **no `device/` segment**); the "if the content differs, continue" hedge rewritten to name the preflight capture (`P5-S1-PREFLIGHT-PROBE.md:97,101`) as the source. New global rule 7: *expected output comes from an executed command, never a rendered or line-numbered view.* S5's post-append `wc -l` `6` → **`9`**. | 118–132 (S0.4), 350 (S5), 43 (rule 7), 597 (Part A) |
| **#2** | HIGH | S3.2's first command (`git ls-remote file:///home/cptjaqx/projects \| grep -c 'Phosphor-platform.git'`, a void parent-directory enumeration) **deleted**; a rev-2 note records why. Two real commands kept (mirror fetchable; literal-B6 composition fails). FAILED re-pointed at the **first remaining** command. The composition rule is now **stated, not tested**, sourced to `manifest_xml.py:232-233` in §D-5. | 253–266 (S3.2), 239 (S3 purpose), 31 (D-5), 603 (Part A) |
| **#3** | HIGH | S7 EXPECTED `N+1` → **`N+2`**, both new lines named (the `phosphor` `<remote>` from `ToXml`, `manifest_xml.py:613-616`, **and** the `<project>`), FAILED clause `N+>2`. The pinned-line attribute set recorded in full: `upstream="refs/heads/main" dest-branch="refs/heads/main" groups="local::phosphor"` — rev 1 mentioned only `upstream=` yet demanded the line "verbatim". S0.5 records N = 1085 (executed `wc -l`). | 143–144 (S0.5), 512–513 (S7 expected), 531 (S7 FAILED), 202 (S2 note), 613 (Part A) |
| **#4** | HIGH | New **S6.0** pre-run inventory (`find … -type f \| sort \| xargs sha256sum` → `/tmp/akita-before.sha256`, mtime snapshot, `BEFORE_TS`, 4739 files) replacing the vacuous regeneration proof. S6.3 rebuilt as a **differential**: after-inventory, `diff -q` verdict, mtime delta `> 0`, literal log line. `git -C vendor/google_devices status` **deleted everywhere** and the tautological "`vendor/google_devices` must not appear in `repo status`" clause removed; global rule 9 now states the tree is not a git repo / not a repo project. | 372–387 (S6.0), 430–490 (S6.3), 52 (rule 9), 615 (Part A), 623 (rationale) |
| **#5** | HIGH | **CLOSED in rev 3 (was half-closed in rev 2).** Rev 2 replaced "the tail shows the generator's completion lines" with a literal expected string and a `tail -1` check — the right shape — but invented the string (`Generating mk for akita`), so no run could match. Rev 3 substitutes the executed string `Generated vendor module at vendor/google_devices/akita`, records its provenance, and keeps the record-verbatim-and-STOP behaviour. | 458–465 (S6.2 expected + provenance), 533 (S6.3 leg (c)), 646 (S8 summary), 689 (Part A) |
| **#6** | MEDIUM | S5 diff hunk `@@ -3,3 +3,4 @@` → **`@@ -6,3 +6,4 @@`** (the blank lines shift it); `--stat` restricted to the one file (`git -C vendor/adevtool diff --stat -- config/mk/google_devices/device/akita/device.mk`) so `1 file changed, 1 insertion(+)` is achievable instead of 3 files. Zero-`-`-lines requirement kept. | 345, 349–362 (S5), 611 (Part A) |
| **#7** | MEDIUM | **CLOSED in rev 3 (was half-closed in rev 2).** Rev 2 added the temp file, the captured exit code and the pre-`mv` gates. Rev 3 removes the remaining cross-shell read (`REPO_EXIT` set in one block, tested in another) by making S7 **one bash invocation** — verify, gate, `mv`, post-`mv` verify — and adds post-`mv` verification on the promoted file (`FINAL_LINES=1`, 40-hex revision). FAILED states the original 1085-line / 245571-byte artifact is untouched on any gate failure. | 562–612 (S7 single block + FAILED), 691 (Part A), 698 (rationale) |
| **#8** | HIGH | Fraudulent-pass construct eliminated in **all three** places. Pattern is now: `test -d vendor/google_devices/akita` first, then `grep … > /tmp/x.grep; GS=$?`, `COUNT=$(wc -l < …)`, and `case "$GS" in 0\|1) ;; *) hard stop;; esac`. Applies to S6.3 (both directory greps **and** the seam grep on the config file), S8 (generated-tree grep), and is generalised as global rule 8. | 44–51 (rule 8), 453–471 (S6.3), 554–557 (S8), 615 (Part A) |
| **#9** | MEDIUM | The A7 plan-lint grep relabelled **"PLAN LINT ONLY — this file, not the session"** in S8, with a note that it is unchanged by execution and therefore not evidence; **the execution transcript is now the sole A7 artifact** (global rule 4 and the COMPLETENESS line both say so). | 40 (rule 4), 561–562, 566–567 (S8), 618 (Part A) |
| **#10** | MEDIUM | New **S6.1 precondition block**: `sudo -n true` must print `SUDO_EXIT=0`, else STOP as *privilege unavailable* (the Supervisor's seat reproduces `sudo: interactive authentication is required`) and the phase must run in an **interactive seat**; the AppArmor-fix failure is now explicitly distinguished from the privilege failure in S6.1's FAILED clause. | 389–410 (S6.1 precondition + command), 613 (Part A) |
| **#11** | LOW | Global rule 6 added: **every block runs under `bash`** (`PIPESTATUS` is a bash array; under `sh`/`dash` the guard dies with `Bad substitution`), naming the four affected steps. | 42–43 (rule 6) |

**Rev 3 entries (NEW-1..NEW-5 + carry-alongs; all five are repairs to S6.0–S6.3, S7 and S8):**

| NEW # | Sev | What changed | Where (rev 3 lines) |
|---|---|---|---|
| **NEW-1** | CRITICAL | S6.2's fabricated "literal" string `Generating mk for akita` **deleted everywhere** and replaced with the executed one, `Generated vendor module at vendor/google_devices/akita`. Provenance recorded (executed `tail -1 \| cat -A`, Sep 24 17:58, 50 lines, the run that produced the current tree). The record-verbatim-and-STOP behaviour is kept. Every echo updated: S6.2 expected, S6.2 FAILED, S6.3 leg (c), S8 summary, Part A, revision log. | 458–465 (S6.2), 533 (S6.3 (c)), 646 (S8 summary), 689 (Part A), 752 (BUG #5 row) |
| **NEW-2** | HIGH | The mtime leg no longer depends on a variable set in another block. S6.0 persists `BEFORE_TS` to `/tmp/akita-before.ts`, makes `/tmp/akita-before.mtime` the `-newer` reference **and** writes a real snapshot `/tmp/akita-before.mtime.txt`; S6.3 reads the marker, hard-stops if it is missing, and reports two independent mtime counts plus a snapshot delta. Global rule 5 names the S6.0→S6.3 carry-over as one of only two exceptions. | 41 (rule 5), 376–395 (S6.0), 475 (S6.3 rev-3 note), 492–501 (S6.3 leg (b)), 532 (expected) |
| **NEW-3** | HIGH | S7 merged into **one bash block**: verify, gates and `mv` in a single invocation, `REPO_EXIT` captured in that same shell, plus post-`mv` verification on the promoted artifact (`FINAL_LINES=1`, 40-hex). Global rule 5 names S7 as the second exception. | 41 (rule 5), 562 (rev-3 note + executed proof), 564–604 (single block), 606–612 (FAILED), 638–640 (S8 post-mv echo) |
| **NEW-4** | MEDIUM | S6.1's "already loaded" branch (the script has none) replaced with the script's **real output shape**, quoted from its body (`scripts/host-fix-nsjail-userns.sh:49-105`); the profile's pre-existence on this host is recorded for A6a (root, 775 bytes, Sep 24 17:55, no-op reload = success). | 418–434 (S6.1 EXPECTED) |
| **NEW-5** | MEDIUM | `$GALOG` freshness gate added: `rm -f` the log before the run, `test -s` after, and assert `GALOG_MTIME ≥ GALOG_TS` (the epoch persisted to `/tmp/adevtool-galog.ts` and re-read in the gate block); a missing, empty or stale log is a hard stop. | 440–456 (S6.2 command + gate), 469 (FAILED "log missing/empty/stale") |
| **CA-1** | — | `xargs sha256sum` status asserted in S6.0 (`SHA256_STATUS`) and S6.3 (`SHA256_STATUS`), and before-count == after-count made an explicit pass condition (`BEFORE_FILES` vs `AFTER_FILES`). | 382–383, 481–485, 530 |
| **CA-2** | — | S8's summary string and Part A's S6.2 line echo the corrected log string. Count of the fabricated string in this file: **5 matches (rev-4 grep), all in revision-log/provenance text naming it as invented — 0 in any EXPECTED/FAILED/command block**, which is the check that matters. | 646, 689 |
| **CA-3** | — | FAILED-note added: a second process that restores a file's content **and** its mtime passes all three legs; the differential is not an anti-tamper proof. | 535 |

Also carried into rev 3 unchanged: R-3's `repo sync -n` = `--network-only` wording; the correction that `packages/phosphor` is a cleanly synced project and must not appear dirty in `repo status`; S5's refusal to self-revert or to fix newline-mangling without Supervisor instruction; S2's heredoc ordering.

---

## Revision log (rev 4)

**Author of rev 4: the Supervisor, not Coder** — applied under the two-failed-rounds rule (`implementationSupervisor.md`, anti-pattern "endless rework loops": after 2 failed attempts on a normal phase, fix it yourself). Coder produced rev 2 (11 repairs) and rev 3 (5 repairs); the Debugger's re-audits found rev 2 half-closing BUG #5/#7 and rev 3 closing NEW-3 only, so the repair authorship shifted seats. The repair list was the Debugger's rev-3 re-audit findings; every expectation changed below carries the executed command that produced it. All 26 bash blocks in this file pass `bash -n` (block 0's `<dir>` placeholders excepted by design).

| # | Sev | What changed (rev 4) | Where (rev-4 lines) |
|---|---|---|---|
| **R4-1** | MEDIUM→closes BUG #5 | The tail comparison is now an **executed equality** in three sites: S6.2's gate (`LAST_LINE=…; [ "$LAST_LINE" = "Generated vendor module at vendor/google_devices/akita" ] \|\| hard stop`), S6.3 leg (c) (`LEG_C_TAIL_OK=1`), and S8. No site relies on eyeball comparison. The literal string itself was already executed (NEW-1); what was missing was the check, and it now exists as code. | 469–471 (S6.2 gate), 527–531 (S6.3 (c)), 660–664 (S8), 674 (summary) |
| **R4-2** | MEDIUM→closes Debugger R4 finding | The tautological "both mtime counts equal" cross-check deleted (`-newer` reference file `/tmp/akita-before.mtime` retired; its only reader removed with it; the `.mtime.txt` snapshot write **kept** — it is `MTIME_SNAPSHOT_DELTA`'s one reader). Replaced by the **totality gate**: S6.0 baselines the preserved-mtime set (`/tmp/akita-before-preserved.txt`, `OLD_PRESERVED_COUNT=3` — Supervisor-executed 2026-11-11: the Sep 24 known-good run rewrote 4736/4739, preserving exactly 3 zip-mtime files: `ld.config.txt` 1969-12-31, `public.libraries-google.txt` and `system_dlkm.modules.blocklist` 2008-12-31); S6.3 asserts `PRESERVED_COUNT == OLD_PRESERVED_COUNT` **and** `NEWER_TS_COUNT + PRESERVED_COUNT == BEFORE_FILES`. A 3-of-4739 partial rewrite now fails (`PRESERVED_COUNT` jumps 3 → 4736). `BEFORE_FILES` is re-derived from S6.0's sha256 file, not carried across shells. | 386–391 (S6.0 baseline + snapshot), 394 (EXPECTED, executed evidence), 507–517 (S6.3 leg (b)), 560 (EXPECTED), 718 (Part A) |
| **R4-3** | MEDIUM→closes Debugger R4 finding | S6.2's freshness gate gets the missing presence guard: `test -s /tmp/adevtool-galog.ts \|\| hard stop` **and** a numeric-validation `case` on `GALOG_TS` (`''\|*[!0-9]*` → malformed → hard stop) — the empty-marker path no longer throws `[: integer expression expected`, it stops cleanly with a message. Rule 5's exception list updated to **three** named exceptions (S6.0→S6.3 marker, S6.2's galog marker, S7 one shell). | 41 (rule 5), 460–464 (gate) |
| **R4-4** | MEDIUM→closes Debugger R4 finding | S6.1's output block is now **labelled** "quoted from source `scripts/host-fix-nsjail-userns.sh:49-105`, not from an executed run" (rule-7 honesty), and an **executed discriminator** is added to the command: `journalctl -k --since '-2 min' \| grep -i 'apparmor.*nsjail\|DENIED.*nsjail'` — because the script's own nsjail probe is swallowed by `if … \| grep` under `set -e` (exit 0 even when the probe failed). FAILED updated: a post-reload AppArmor **DENIAL** in the journal is a STOP; exit status + journal are the judges, never a bare nsjail probe. | 416–422 (command + discriminator), 426 (label), 444 (FAILED) |
| **R4-5** | LOW→closes Debugger R4 finding | The revision-log header now states rev-2/rev-3 line numbers are **superseded — do not navigate by them**; only this rev-4 table carries current line numbers. CA-2's false "0 matches" claim corrected to the executed truth: **5 matches, all in revision-log/provenance text naming the string as invented, 0 in any EXPECTED/FAILED/command block** (rev-4 `grep -c` = 5, `grep -n` at 477/748/777/789/795). | 770 (header), 798 (CA-2) |
| **S6.3 note** | — | The rev-3 note describing the retired two-count scheme is superseded in place by a rev-4 note naming the tautology and the replacing totality gate. | 490 |

No other section changed in rev 4. S0–S5 and S7 are byte-identical to rev 3 (S7's single-block form was already accepted by the Debugger as the closed NEW-3/BUG #7 repair). The plan remains Coder's work under the handoff discipline; rev 4 is a supervisor-applied mechanical repair, logged here for the audit trail.

---

## Revision log (rev 5)

**Author: the Supervisor.** Repairs from the Debugger's round-3 re-audit (which itself re-verified R4-1/R4-3/R4-4-command/R4-5 and the snapshot chain as closed). One audit finding — the log-mtime anchor proposed for R5-1 — was **executed and rejected**: it yields 4738, not 3; the fix uses a fixed cutoff instead. All rev-5 expectation strings and gate arithmetic are backed by the executed probes cited inline.

| # | Sev | What changed (rev 5) | Where (rev-5 lines) |
|---|---|---|---|
| **R5-1** | HIGH→closes BUG #4 (round 3) | The preserved-set predicate no longer uses `BEFORE_TS` (S6.0's now — selects all 4739, executed) and does **not** use the audit's log-mtime anchor (executed: yields 4738 — the run wrote its files before the log's final write). It uses the **fixed cutoff `2026-01-01`**, in the 18-year gap between the newest zip-preserved mtime (2008-12-31) and this host's first generate-all (2026-09-24): executed → exactly the 3 zip-mtime files. Re-run-proof: a new run writes ≥2026-09 mtimes; zip-copied files keep 1969/2008. `OLD_PRESERVED_COUNT≠3` is now a **STOP** (it is a property of the archive contents, not host timing). S6.3 re-derives the set with the same cutoff and adds `diff -q` (same-count-different-set hole closed). Six-scenario simulation executed (fixture, plan's exact code): known-good CONTINUE; partial-normal, zip-rewritten-same-count, deleted, no-op all STOP; created-during-run passes totality but is caught by leg (a) `AFTER_FILES == BEFORE_FILES` + `INVENTORY=IDENTICAL`, per the audit's own prescription. | 386–395 (S6.0 predicate + note), 404 (EXPECTED), 513–534 (S6.3 leg (b)) |
| **R5-2** | MEDIUM→closes BUG #5 (round 3) | The journalctl discriminator is now **gated, not printed**: `DISCRIM_GREP` is captured after a grep with **no `| tail`** (executed: tail swallows grep's status — `grep … \| tail -5; echo $?` prints 0 even on no-match); `DISCRIM_GREP=0` → `APPARMOR DENIAL PRESENT` hard stop (with the journal lines cat'd); `>=2` → `JOURNAL GREP FAILED` hard stop; only `1` prints `NSJAIL_DISCRIMINATOR=PASS`. The FAILED clause now points at the executed gate instead of asking the executor to eyeball the journal. | 422–437 (command + gate), 455–456 (FAILED) |
| **R5-3** | LOW→closes BUG #6 (round 3) | The two unscoped post-mv 40-hex greps (S7 + S8) scoped to `grep 'path="packages/phosphor"' \| grep -o 'revision=…'` — the unscoped form emits ToXml's **first** project revision (1057 40-hex revisions live in the pin file), not ours; it could not false-fail but its transcript line was not what it claimed to be. | 631 (S7 post-mv), 681 (S8) |
| **stale refs** | LOW | CA-2/R4-5 hit-line refs refreshed by re-execution at rev 5: `grep -n 'Generating mk for akita'` → the five occurrences sit in provenance/revision-log text only; no EXPECTED/FAILED/command block contains it. | 480/751/780/792 + this table |

`bash -n` census re-run after rev 5: 26 blocks, 0 failures. S0–S5 and S7 otherwise byte-identical to rev 4.

---

## Revision log (rev 6 — hygiene)

**Author: the Supervisor.** Applies the two LOW, non-gating findings from the Debugger's round-4 re-audit, which returned **EXECUTABLE AS WRITTEN** on rev 5. The auditor pre-specified both fixes; their application is folded into the post-execution audit rather than costing a sixth pre-execution round.

| # | Sev | What changed (rev 6) |
|---|---|---|
| **R6-1** | LOW→closes BUG #7 (round 4) | Six stale prose sites refreshed: header → rev 6; the S6.3 EXPECTED bullet now credits rev-5 R5-1 and names the `diff -q` set check; the FAILED bullet's vestigial "two counts disagreeing" replaced with the preserved-count/set conditions; the carry-along-3 FAILED-note re-pointed to the content-only-restore world (a content+mtime restore is now CAUGHT by the totality gate — audited round 4); the revision-log header's "only rev 4" wording → latest table; Part A's S6.3 line gains `== 3 (STOP if ≠3)` and the set-diff clause. |
| **R6-2** | LOW→closes BUG #8 (round 4) | S6.1's discriminator captures `JCTL_STATUS=${PIPESTATUS[0]}` and hard-stops if journalctl itself failed — a failed journal read produces empty stdin, grep exits 1 (looks like no-denial), so without this a broken journal silently passes. Not live on this host (cptjaqx ∈ adm, journalctl -k executed clean by the auditor), but the gate is now honest in all worlds. |

No behavioral change to any pass/fail path that round 4 verified. The plan's audit status: **round 4 verdict EXECUTABLE AS WRITTEN stands for rev 6 subject to post-execution verification of R6-1/R6-2.**

---

## Execution log — deviations of record (rev 6, executed 2026-11-12)

| Where | What happened | Ruling |
|---|---|---|
| S6.1 | PM executed the sudo line interactively (SUDO_EXIT path bypassed by design). Probe printed `Couldn't launch the child process` — the documented red herring: the userns/AppArmor layer worked (uid/gid maps built; profile_replace STATUS lines at 08:07:17), the failure is execve of `/bin/bash` inside the chroot-ish sandbox, which PROJECT-STATUS §9 says never to judge by. The R5-2 gate as written FALSE-FAILED: pattern `apparmor.*nsjail` matched benign `apparmor="STATUS" operation="profile_replace"` lines naming the nsjail profiles. | Pattern corrected at execution to `apparmor="DENIED"` (exact) AND `nsjail` → `DISCRIM_GREP=1`, `NSJAIL_DISCRIMINATOR=PASS`. The one DENIED in the window is `comm="unshare"` — the script's own intended verification (global restriction still on). Executed evidence preserved in transcript. R5-2's intent (gate on denials, not eyeball) unchanged; only the pattern narrowed. |
| S4.1/S4.2 | `repo sync` ran in background under nohup with timer polls (plan prescribed tail+EXIT in one window; network fetch of 1085 projects exceeded any single window). Both finished successfully, 0 error lines. One `Bad substitution` occurred when the Supervisor's own exec wrapper used sh not bash — the plan's rule 6 (BUG #11) caught it; re-ran under bash. | No plan change; rule 6 validated in practice. |

---

## Revision log (rev 7 — post-execution fold-back)

Auditor post-execution verdict (2026-11-12): **Phase 1b ACCEPT**, no findings. Two fold-backs applied:

| # | Change |
|---|---|
| **R7-1** | S6.1 discriminator pattern corrected to the exact-DENIED form executed during Phase 1b (`grep -E 'apparmor="DENIED"' | grep -i nsjail`) — the rev-5/6 `apparmor.*nsjail` pattern false-fired on benign `apparmor="STATUS" operation="profile_replace"` lines. Ratified by the auditor (deviation-of-record adjudication #2). |
| **R7-2** | `ADEVTOOL_SKIP_DEP_BUILD=1` recorded as the standing S6.2 invocation (sound per the fix script's own note: the Sep-24 full run already built the deps). **Carry-forward to Phase 1c:** the build plan must note that `dl/` dependency state comes from the Sep-24 run and that `m` does not consume adevtool's dependency build; if any adevtool dep doubt arises, re-run generate-all without the skip. |

Status: **Phase 1b closed** (evidence `P5-S1-PHASE-1b-EVIDENCE.md`; auditor ACCEPT). Loop proceeds to Phase 1c.
