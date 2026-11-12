# P5-S1 pre-flight drift probe — spec vs tree

**Auditor:** Debugger · **Date:** 2026-11-10 · **Mode:** READ-ONLY (nothing modified)
**Spec:** `docs/specs/P5-S1-build-integration.md` (read in full, 212 lines)
**Tree:** `/home/cptjaqx/projects/grapheneos-2026091900`
**Prompt:** `.crabcakes/prompts/adversarialDebugger.md` (loaded fresh; sections 1–11 worked)

**Result: 2 findings (1 MEDIUM, 1 LOW). 5 of 7 claims verified clean. No CRITICAL/HIGH drift — S1 is executable as written once the two items below are corrected.**

---

## Claim-by-claim

### Claim 1 — sepolicy variable names and wiring — **no drift — claim 1 verified**

All four sub-claims reproduce exactly.

```
$ awk 'NR>=162 && NR<=165 {print NR": "$0}' build/make/core/config.mk
162: $(KATI_obsolete_var LOCAL_SANITIZE_BLACKLIST,Use LOCAL_SANITIZE_BLOCKLIST instead)
163: $(KATI_obsolete_var BOARD_PLAT_PUBLIC_SEPOLICY_DIR,Use SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS instead)
164: $(KATI_obsolete_var BOARD_PLAT_PRIVATE_SEPOLICY_DIR,Use SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS instead)
165: $(KATI_obsolete_var TARGET_NO_VENDOR_BOOT,Use PRODUCT_BUILD_VENDOR_BOOT_IMAGE instead)
```

```
$ awk 'NR>=218 && NR<=221 {print NR": "$0}' build/make/core/soong_config.mk
219: $(call add_json_list, SystemExtPublicSepolicyDirs,       $(SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS))
220: $(call add_json_list, SystemExtPrivateSepolicyDirs,      $(SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS))
```

```
$ awk 'NR>=87 && NR<=90 {print NR": "$0}' system/sepolicy/build/soong/build_files.go
88: 	b.srcs[".system_ext_public"] = b.findSrcsInDirs(ctx, ctx.DeviceConfig().SystemExtPublicSepolicyDirs()...)
89: 	b.srcs[".system_ext_private"] = b.findSrcsInDirs(ctx, ctx.DeviceConfig().SystemExtPrivateSepolicyDirs()...)
```

```
$ awk 'NR>=943 && NR<=954 {print NR": "$0}' system/sepolicy/Android.bp
943: se_neverallow_test {
944:     name: "sepolicy_neverallows",
946:     srcs: plat_public_policy +
947:         plat_private_policy +
948:         system_ext_public_policy +
949:         system_ext_private_policy +
950:         product_public_policy +
951:         product_private_policy +
952:         vendor_policy +
953:         [":se_build_files{.odm}"],
954: }
```

Note on precision: the spec cites `Android.bp:943` for the neverallow admission. Line 943 is the `se_neverallow_test {` opener; the actual admission evidence is the `srcs` span **946-953**, with `system_ext_public_policy`/`system_ext_private_policy` at 948-949. The claim is **true**; the citation is one line early. Not a finding — the spec's own §3 B5 `[VERIFY AT BUILD]` covers re-confirmation, and the referenced line does open the correct block.

Also confirmed: `system_ext_public_policy`/`system_ext_private_policy` are distinct variables (`Android.bp:152-153`), not folded into `plat_*_policy` — so the admission is genuinely additive, which is what makes S2's `neverallow` set legal there.

### Claim 2 — zero module-name collisions — **no drift — claim 2 verified**

```
$ grep -rn '"phosphor-' --include=Android.bp . | wc -l
0
$ grep -rn '"Phosphor' --include=Android.bp . | wc -l
0
```

I widened the probe beyond the spec's regex, because a collision need not use the exact prefix the spec greps for:

```
$ grep -rniE '"phosphor[_-]' --include=Android.bp --include=Android.mk . | wc -l
0
$ grep -rn 'LOCAL_MODULE *:= *phosphor\|LOCAL_MODULE *:= *Phosphor' --include=Android.mk . | wc -l
0
```

Case-insensitive, both build systems, both name forms: zero. The five names in B5 (`phosphor-agentd`, `phosphor-keygate`, `phosphor-ctl`, `PhosphorShell`, `PhosphorBroker`) are all free.

### Claim 3 — no `soong_namespace` hiding `packages/phosphor` — **no drift — claim 3 verified**

```
$ grep -rn 'soong_namespace' packages/ --include=Android.bp | wc -l
0
$ ls packages/Android.bp
ls: cannot access 'packages/Android.bp': No such file or directory
$ ls -la packages/phosphor
ls: cannot access 'packages/phosphor': No such file or directory
```

No namespace anywhere in the `packages/` chain, no `Android.bp` at the `packages/` root to carry one, and the tree root's `Android.bp` declares none. `packages/phosphor` does not exist yet — correct for pre-S1. Modules added there will be visible to Soong without a namespace declaration or `import`.

### Claim 4 — adevtool `device.mk` seam — **no drift — claim 4 verified**

```
$ ls -l vendor/adevtool/config/mk/google_devices/device/akita/device.mk
-rw-rw-r-- 1 cptjaqx cptjaqx 333 Sep 24 11:04 .../device.mk

$ cat .../device.mk
$(call inherit-product, vendor/adevtool/config/mk/google_devices/platform/zuma/product-common.mk)
TARGET_KERNEL_DIR ?= $(RELEASE_KERNEL_AKITA_DIR)
TARGET_BOARD_KERNEL_HEADERS ?= $(RELEASE_KERNEL_AKITA_DIR)/kernel-headers
PRODUCT_PACKAGES += GosAkitaOverlay
include vendor/adevtool/config/mk/google_devices/platform/zuma/device.mk

$ grep -n 'device.mk\|inherit-product' vendor/google_devices/akita/akita.mk
10:$(call inherit-product, vendor/adevtool/config/mk/google_devices/device/akita/device.mk)
```

`inherit-product` is the established convention in that file (line 1 uses it), so B4's appended line matches local style. The generated `akita.mk:10` does inherit it, so the seam is real and one line is sufficient. `PRODUCT_NAME := akita` (`akita.mk:20`) confirms the product identity lunch will resolve.

### Claim 5 — `.repo/local_manifests/`, repo baseline, `out/` baseline — **no drift — claim 5 verified, with one baseline caveat (see BUG #2)**

```
$ ls -d .repo
.repo
$ ls -la .repo/local_manifests/
ls: cannot access '.repo/local_manifests/': No such file or directory
$ ls -ld .repo
drwxrwxr-x 7 cptjaqx cptjaqx 4096 Sep 24 11:22 .repo      # WRITABLE
```

`.repo` is a real repo checkout (`manifest.xml`, `manifests/`, `project-objects/`, `projects/`, `manifest-pinned.xml` all present) and is writable, so `local_manifests/` is creatable — `repo` creates the directory on demand. `.repo/manifest.xml` is the standard generated include of `default.xml`, and its own comment directs customisation to `local_manifests/`, confirming B6's mechanism.

**`repo status -j24` baseline (A5 dirt baseline), captured verbatim:**

```
project vendor/adevtool/                        (*** NO BRANCH ***)
 --	.yarn/install-state.gz
 --	.yarnrc.yml
 -m	package.json
 -m	yarn.lock
```

Exactly one project dirty, and **`device.mk` is not among the modified files** — so S1's one-line edit will be the only change to that file. See BUG #2 for why this baseline matters.

**`out/` size baseline (A2 delta):** `du -sh out/` → **109G** (114.3 GB decimal). The spec/PROJECT-STATUS figure is "~107 GB"; the 2 GB difference is post-build artifacts accumulated since, which is expected and does not invalidate the delta method — A2 records a *delta*, not an absolute.

**Ninja step baseline — verified exactly, from the real build log:**

```
$ grep -n 'Build Succeeded: 168199' /home/cptjaqx/akita-build.log
230532:ninja: 1h4m49.60s Build Succeeded: 168199 steps - 43.24/s
```

The spec's `168,199` baseline is **exact**, and the duration (1h4m49s) matches PROJECT-STATUS §6's "~1 h 06 m". I initially misread a mid-build progress counter (`168534/168534`) as the total; the authoritative figure is the `Build Succeeded:` line. `grep -c 'ninja: build stopped\|FAILED:'` → 0, so the log is a clean successful build and a valid baseline.

### Claim 6 — spec path staleness — **DRIFT CONFIRMED — see BUG #1**

### Claim 7 — A2 recipe paths resolve — **no drift — claim 7 verified**

```
$ ls -l build/envsetup.sh
lrwxrwxrwx ... build/envsetup.sh -> make/envsetup.sh
$ ls build/release/flag_values/ | grep -x cur
cur
$ cat build/release/flag_values/cur/RELEASE_KERNEL_AKITA_DIR.textproto
name: "RELEASE_KERNEL_AKITA_DIR"
  string_value: "device/google/akita-kernels/6.1/grapheneos"
$ ls vendor/google_devices/akita/akita.mk
vendor/google_devices/akita/akita.mk
$ grep -n 'PRODUCT_NAME' vendor/google_devices/akita/akita.mk
20:PRODUCT_NAME := akita
```

`envsetup.sh` exists (symlink to `make/envsetup.sh`), the `cur` release config exists, and critically **`RELEASE_KERNEL_AKITA_DIR` is defined in `cur`** — which is exactly the trap PROJECT-STATUS §6 warns about (`ap2a` defines none, producing an empty `TARGET_KERNEL_DIR` and a misleading board-config abort). `akita-cur-user` therefore resolves to a real product+release+variant triple.

A3's tool paths also resolve: `out/host/linux-x86/bin/aapt2` (24 MB, executable) and `prebuilts/jdk/jdk25/linux-x86/bin/java` both present. `product_packages.txt` exists (1661 lines) and currently has **0** matches for `^(phosphor-|Phosphor)`, so A3's expected count of 5 is a clean delta from zero. I re-confirmed the count semantics: the file is `strings.Join(ProductPackages, "\n")` where `ProductPackages` is literally `$(PRODUCT_PACKAGES)` (`soong_config.mk:544`, `product_packages_file.go:36`) — top-level only, so the five names will each appear once and the count of 5 is sound.

---

## Findings

```
BUG #1
Severity: MEDIUM
Claim violated: Claim 6 — B6's development-variant mirror path names a home directory that does not exist on this host.
Assumption violated: The spec assumes the operator's home is /home/qoder. It is /home/cptjaqx.
Attack vector: A builder following B6's development variant verbatim writes a local manifest whose `fetch` points at a non-existent path. `repo sync` then fails with a fetch error that names the URL, not the spec, and the natural diagnosis is "the mirror is missing" rather than "the spec has a stale home directory" — sending the builder to create a mirror in the wrong place.
Reproduction:
  $ echo $HOME
  /home/cptjaqx
  $ ls -d /home/qoder
  ls: cannot access '/home/qoder': No such file or directory
  $ ls -d /home/qoder/projects/Phosphor-platform.git
  ls: cannot access '/home/qoder/projects/Phosphor-platform.git': No such file or directory
  $ grep -rn '/home/qoder' docs/
  docs/specs/P5-S1-build-integration.md:120: ... fetch="file:///home/qoder/projects/Phosphor-platform.git" ...
  (count: 1 — the only occurrence in the entire docs tree)
  $ grep -rn '/home/cptjaqx' docs/ | wc -l
  4   (PHASE-1-BUILD-HOST-READINESS.md:268-269, evidence/phase3-*.txt:30,283)
Root cause: The spec was drafted against an earlier host identity. Every other document in the repo already uses /home/cptjaqx, so this is an isolated stale string, not a systematic error.
Fix: In S1 §3 B6 line 120, replace /home/qoder with /home/cptjaqx. Note that the corrected path also does not exist yet (/home/cptjaqx/projects/Phosphor-platform.git is absent) — that is expected, since B6 describes creating the mirror; the spec should say the mirror is *to be created* at that path rather than implying it exists. Non-blocking for the build itself (B6's primary form uses the ssh remote), but it is the exact line a builder executes in the development variant.
```

```
BUG #2
Severity: LOW
Claim violated: Claim 5 — the A5 dirt baseline is not clean, and A5's pass condition as written does not account for it.
Assumption violated: A5 assumes `repo status -j24` will show modifications "only in vendor/adevtool (one line added to device.mk) and in packages/phosphor (new)". It assumes vendor/adevtool starts clean.
Attack vector: vendor/adevtool is ALREADY dirty before S1 runs — four entries, none of them device.mk. A builder who runs A5 after adding the one line sees five changed paths in vendor/adevtool, not one, and must decide unaided whether the four pre-existing entries are their fault. A strict reading of A5 ("Any other modified GrapheneOS project fails this spec") is satisfiable, but a strict reading of "one line added to device.mk" is not — the project has other modifications that S1 did not make.
Reproduction:
  $ cd /home/cptjaqx/projects/grapheneos-2026091900 && repo status -j24
  project vendor/adevtool/                        (*** NO BRANCH ***)
   --	.yarn/install-state.gz
   --	.yarnrc.yml
   -m	package.json
   -m	yarn.lock
  $ cd vendor/adevtool && git status --short
   M package.json
   M yarn.lock
  ?? .yarn/
  ?? .yarnrc.yml
  $ git status --short | grep -c 'device.mk'
  0        # device.mk is currently clean — S1's edit will be the only change to it
Root cause: The adevtool checkout carries pre-existing local modifications (yarn install state and package manifests) from the Phase 2/3 tooling setup. They are unrelated to S1 and were present before this spec existed. The spec's A5 was written assuming a pristine tree.
Fix: Record this baseline in S1 §5 A5 (or the completion note) as the pre-S1 state, and restate the pass condition as "no NEW modified project beyond vendor/adevtool and packages/phosphor, and within vendor/adevtool no new modified file beyond device.mk". The baseline above is the exact text to attach. This is a documentation/acceptance-precision issue only — it does not block the build, and device.mk itself is clean, so S1's one-line edit remains isolable.
```

---

## Summary table

| # | Claim | Result |
|---|---|---|
| 1 | sepolicy vars + wiring + neverallow admission | **verified** (citation at `Android.bp:943` is one line early; evidence span is 946-953 — cosmetic) |
| 2 | zero module-name collisions | **verified** (widened to case-insensitive + Android.mk: still 0) |
| 3 | no `soong_namespace` in `packages/` chain | **verified** |
| 4 | adevtool `device.mk` seam + generated inherit | **verified** |
| 5 | `.repo/local_manifests/` creatable; repo + `out/` baselines | **verified**, with BUG #2 on the A5 baseline's cleanliness |
| 6 | B6 mirror path | **DRIFT — BUG #1** (`/home/qoder` → `/home/cptjaqx`) |
| 7 | A2 recipe paths resolve | **verified** (`cur` defines `RELEASE_KERNEL_AKITA_DIR`, avoiding the §6 trap) |

**Baselines recorded for later use:**
- `repo status -j24`: 1 dirty project (`vendor/adevtool`), 4 entries, `device.mk` clean.
- `out/`: 109G (114.3 GB decimal).
- Ninja: **168,199 steps**, 1h4m49s, `BUILD_EXIT=0`, zero `FAILED:`/`build stopped` — matches the spec's baseline exactly.

**Verdict: S1 is executable as written.** Neither finding blocks the build: BUG #1 affects only B6's development variant (the primary ssh form is unaffected), and BUG #2 is an acceptance-precision gap whose baseline I have now captured. Both should be corrected in the spec before the builder runs, since both are one-line documentation fixes and both would otherwise cost the builder a diagnosis cycle.

*No file was modified by this probe. All commands were read-only (`grep`, `awk`, `ls`, `du`, `cat`, `repo status`, `git status`). No build, no device operation, no `repo sync`.*