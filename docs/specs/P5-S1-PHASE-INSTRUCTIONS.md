# P5-S1 Phase Instructions — Build integration (PM-approved errata applied 2026-11-10)

**Authority chain:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` rev 4 (CLOSED) is the floor; `docs/specs/P5-S1-build-integration.md` **rev 2** narrows it; these instructions phase the spec. Read the S1 spec in full before any phase. Pre-flight probe: `docs/specs/P5-S1-PREFLIGHT-PROBE.md` (verdict: executable, 2 findings → fixed in rev 2).

**Hard boundaries for S1 (all phases):**
- No device operation of any kind: no flash, wipe, reboot, `adb`, `fastboot`. A7.
- Only ONE edit to a third-party GrapheneOS file: +1 inherit-product line in `vendor/adevtool/config/mk/google_devices/device/akita/device.mk`. Never hand-edit `vendor/google_devices/akita`. A5.
- Build recipe unchanged: `source build/envsetup.sh` → `lunch akita-cur-user` → `m -j24 vendorbootimage vendorkernelbootimage target-files-package`. No `OFFICIAL_BUILD=true`. A2.
- Zero boot-time behavior: no `init_rc`, no sepolicy content, no manifest components, no property writes, no `/data` files. A4.
- `privileged: true` is mandatory for both apps (OQ-4 shape); therefore install paths are `/system/priv-app/Phosphor*` (Soong `app.go:1091-1093`). Rev-2 erratum — do NOT write `/system/app/...` anywhere.

**Baselines captured pre-flight (2026-11-10):** `repo status -j24` = 1 dirty project (`vendor/adevtool`: `package.json`, `yarn.lock` modified; `.yarn/`, `.yarnrc.yml` untracked — all pre-existing, NOT S1's); `out/` = 109G; ninja baseline = 168,199 steps, 1h4m49s, `BUILD_EXIT=0` (`Build Succeeded: 168199 steps` line — NOT the `168534/168534` progress counter).

---

## Phase 1a — Repository skeleton (Coder) — filesystem-local, zero tree impact

**Scope:** create the `Phosphor-platform` repo content locally at `/home/cptjaqx/projects/Phosphor-platform` (verified not to exist). It will become a bare git repo mirrored to `/home/cptjaqx/projects/Phosphor-platform.git` in Phase 1b. Do NOT yet touch `/home/cptjaqx/projects/grapheneos-2026091900`.

**Exact file set** (B2 layout, B3, B5, B7):

```
packages/phosphor/  (== repo root contents)
  phosphor.mk                       # B5 verbatim: PRODUCT_PACKAGES (5), PRODUCT_COPY_FILES (1 json), SYSTEM_EXT_PUBLIC/PRIVATE_SEPOLICY_DIRS
  sepolicy/public/README            # S1: README only, no policy
  sepolicy/private/README           # S1: README only, no policy
  risk-policy/risk-policy.json      # minimal valid read-only JSON artifact (content: {} is acceptable in S1)
  init/                             # empty dir in S1 (use .gitkeep)
  services/PhosphorAgentd/Android.bp + main.cpp      # cc_binary phosphor-agentd, stem:; int main() { return 0; }
  services/PhosphorKeygate/Android.bp + main.cpp     # cc_binary phosphor-keygate, stem:; int main() { return 0; }
  services/PhosphorDiagnostics/Android.bp + main.cpp # cc_binary phosphor-ctl, stem:; prints "phosphor-ctl: not implemented" to stderr, returns 2
  services/PhosphorIpc/                             # empty dir in S1 (.gitkeep)
  apps/PhosphorShell/Android.bp + AndroidManifest.xml   # android_app PhosphorShell, platform_apis/certificate:"platform"/privileged:true, package="com.phosphor.shell", android:label only, NO components, NO init_rc
  apps/PhosphorBroker/Android.bp + AndroidManifest.xml  # same shape, package="com.phosphor.broker", zero permissions
```

**Constraints:**
- No `init_rc` in any `Android.bp`; no `src/` in apps; no sepolicy `.te` files; no `.rc` files in `init/`.
- `phosphor.mk` uses `SYSTEM_EXT_*_SEPOLICY_DIRS` exactly (B5 — `BOARD_PLAT_*` hard-aborts at `config.mk:163-164`).
- `PRODUCT_COPY_FILES` copies exactly one file: `risk-policy.json` → `$(TARGET_COPY_OUT_SYSTEM)/etc/phosphor/risk-policy.json`.
- Init the repo (`git init`), commit everything on branch `main`, and report the 40-hex commit (A6a needs it).

**Deliverables:** files-changed list with line counts (`wc -l` per file), `git log -1 --oneline`, `git status --porcelain` (must be empty), `find . -type f | sort` output, plus:
- grep proof `rg -n 'init_rc|BOARD_PLAT_' <repo>` → empty
- self-check that `phosphor.mk` B5 content matches spec lines 87-98 verbatim in variable names (fence delimiters at 86/99) and package list
- COMPLETENESS checklist: one `[x]` or `[not done]` line per file above, each with evidence
- "Related issues found, not fixed in this phase" section (mandatory even if empty)

**Rule:** invoke `/home/cptjaqx/projects/Phosphor/.crabcakes/prompts/steelFramedCodeWriter.md` this round. Word marker: **please write**.

---

## Handoff discipline (from Phase 1b, Debugger process fix 2026-11-10)

Coder's seat cannot write outside `/home/cptjaqx/projects/Phosphor`. For tree operations, Coder authors the exact content/commands to `/home/cptjaqx/projects/Phosphor/docs/handoffs/P5-S1-PHASE-<N>-PLAN.md` (inside its sandbox), the Supervisor transcribes mechanically, and the plan file is the fidelity authority for the audit. Chat reports are not the authority.

---

## Phase 1b — Tree integration (Coder) — after 1a audit is clean

**Scope:** bare mirror at `/home/cptjaqx/projects/Phosphor-platform.git`; `.repo/local_manifests/phosphor.xml` (B6 development variant with the corrected `file:///home/cptjaqx/...` path); `repo sync -n` (dry) then `repo sync` for our project only; `repo manifest | grep -c 'path="packages/phosphor"'` → 1 (A1); +1 line in `vendor/adevtool/.../device.mk`; `PATH="$HOME/android-sdk/node24/bin:$PATH" vendor/adevtool/bin/run generate-all -d akita` (B4; re-apply `scripts/host-fix-nsjail-userns.sh` first, from the Phosphor project); `repo manifest -r > .repo/manifest-pinned.xml`.

**Evidence:** `repo status -j24` full output; `git diff` of the `device.mk` one-liner; generate-all log tail; pinned-manifest line-count delta. Stop and report if `vendor/google_devices/akita` shows the line hand-edited.

**Rule:** steelFramedCodeWriter.md again. Word marker: **please proceed**.

---

## Phase 1c — Full acceptance build (Coder, ~1h06m — run under `nohup` with log polling)

**Scope:** A2 recipe verbatim; judge on exit code 0, absence of `ninja: build stopped` / `FAILED:` (the `Build sandboxing disabled due to nsjail error.` stderr line is EXPECTED, not a failure); record `out/` delta and `Build Succeeded: N steps` delta vs 168,199. **B5 [VERIFY AT BUILD]:** confirm `rg -n 'SYSTEM_EXT_(PUBLIC|PRIVATE)_SEPOLICY_DIRS' build/make/core` spelling before trusting `phosphor.mk`; if the tree differs, STOP and report (never fall back to `BOARD_PLAT_*`).

**Evidence:** A3 (three binaries `ls -l`; `aapt2 dump badging` on both `priv-app` APKs; `grep -cE '^(phosphor-|Phosphor)' product_packages.txt` → exactly 5), A4 greps, A5 `repo status`, A6 completion note, A7 no-device confirmation. Attach all command outputs.

**Rule:** steelFramedCodeWriter.md again. Word marker: **write when done**.

---

## Audit handoffs (Supervisor → Debugger, every phase)

After each Coder delivery the Supervisor hands the phase scope + changed files to Debugger via `/ask`, who loads `/home/cptjaqx/projects/Phosphor/.crabcakes/prompts/adversarialDebugger.md` fresh, works all 11 sections, and reports BUG #[N] (or explicit "no bugs found"). Bugs route back to Coder → re-audit. Supervisor then verifies independently (diffs, greps, counts, build logs) before the next phase. No post-mortem, no "done" (§6 format).
