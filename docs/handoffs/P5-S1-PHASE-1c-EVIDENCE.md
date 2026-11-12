# P5-S1 Phase 1c — Build evidence & completion note

**Executed:** 2026-11-12 08:06–08:16 PST, Supervisor, from plan/instructions Phase 1c section.
**Recipe (A2, verbatim per PROJECT-STATUS §6):** `source build/envsetup.sh` → `lunch akita-cur-user` → `m -j24 vendorbootimage vendorkernelbootimage target-files-package`. No `OFFICIAL_BUILD`. Log: `/home/cptjaqx/akita-p5s1-build.log`.

## A2 — build completes, recipe unchanged
- `#### build completed successfully (02:34 (mm:ss)) ####` — exit 0.
- `ninja: 1m06.72s Build Succeeded: 4514 steps - 67.66/s`.
- Zero `FAILED:`, zero `ninja: build stopped`, zero `error:` (grep on full log).
- **Step-count delta:** 4,514 incremental steps vs the 168,199 from-scratch baseline (Sep 24). This was an incremental build on the existing 109G `out/` — the baseline documents a clean-tree build. No flag, target, variant, or lunch argument differed. The `[ 99% 4556/4557]` markers seen mid-build were the soong-analysis and packaging phases.
- `out/` size: 109G → 109G (no measurable delta; target-files zip rebuilt).
- Fresh vbmeta digest computed this run: `6cf7c98f…95b59c7` (add_img_to_target_files, 08:16:43).

## A3 — all five modules installed
- Binaries: `out/target/product/akita/system/bin/phosphor-agentd` (51392B), `phosphor-keygate` (51392B), `phosphor-ctl` (51464B), all `-rwxr-xr-x`, built 08:15.
- APKs at `system/priv-app/` (rev-2 erratum; `privileged: true` → priv-app per Soong app.go:1091-1093):
  - `PhosphorShell.apk` → `package: name='com.phosphor.shell' versionCode='37' versionName='17'`
  - `PhosphorBroker.apk` → `package: name='com.phosphor.broker' versionCode='37' versionName='17'`
- Platform certificate (apksigner, jdk25 on PATH): both APKs → `CN=Android` test platform cert, SHA-256 `c8a2e9bc…192ab8`, SHA-1 `27196e38…e33dfa` — **our platform certificate** (spec §A3: "with our platform certificate").
- `grep -cE '^(phosphor-|Phosphor)' product_packages.txt` → **exactly 5**: PhosphorBroker, PhosphorShell, phosphor-agentd, phosphor-ctl, phosphor-keygate.
- `PRODUCT_COPY_FILES` artifact: `system/etc/phosphor/risk-policy.json` (3 bytes, `{}`) installed.

## A4 — zero boot-time behavior (static proof)
- `grep -rn init_rc packages/phosphor` → 0.
- `packages/phosphor/sepolicy/{public,private}` contain READMEs only.
- `aapt2 dump xmltree` AndroidManifest.xml on both APKs → **0** activity/service/receiver/provider.
- `PRODUCT_COPY_FILES` in phosphor.mk = exactly 1 rule (the risk-policy json).

## A7 — no device operation
No adb/fastboot invocations anywhere in this phase. Build-only.

## Notes for the auditor
1. Incremental-vs-baseline step count (4,514 vs 168,199) is explained above; the spec's A2 records the delta — this is that record.
2. `BUILD_TIMESTAMP` epoch artifacts in APK entries (2009-01-01 zip normalization) are standard.
3. Deviation: none in 1c. Recipe verbatim. (1b's deviations are in the 1b evidence file.)

## Auditor amendments (2026-11-12, post-accept)

1. **nsjail line (closes the spec's [VERIFY AT BUILD] clause explicitly):** `grep -c 'Build sandboxing disabled due to nsjail error' akita-p5s1-build.log` → **0 occurrences** — expected, because the AppArmor profile re-applied in 1b S6.1 was already loaded; soong never hit the sandbox failure. Not a defect.
2. **B2 conformance (§7 requires it recorded before S2 starts):** verified on the synced tree — `packages/phosphor` carries exactly the 16-file layout matching spec §B2; `init/` and `services/PhosphorIpc/` hold `.gitkeep` placeholders as designed. A5 live: `repo status -j24` = `vendor/adevtool` only (device.mk +1 plus the 4 excluded baseline entries); `packages/phosphor` clean. A6 items recorded in the 1b evidence bundle, still true.

**S1 closure status:** Phases 1a/1b/1c all ACCEPT. S1 complete.
