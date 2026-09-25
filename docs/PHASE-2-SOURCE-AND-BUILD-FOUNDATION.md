# Phase 2 — GrapheneOS Source and Build Foundation

**Status:** COMPLETE. Source tree acquired and provenance-verified (§3), vendor
files extracted (§4), `akita` build configuration established (§5), baseline
build produced and verified (§6–§7). Every blocker encountered is resolved with
evidence (§8). Phase 2 exit criteria met (§12). Next: Phase 3, starting with the
key-management design.
**Project:** Phosphor
**Target device:** Google Pixel 8a (`akita`), SKU `GKV4X`, serial `3C121JEKB03922`
**Build host:** `qoder` — Ubuntu 26.04.1 LTS (unsupported distro, Option E),
AMD Ryzen 9 9950X 16C/32T, 59 GiB RAM, ext4, 1.4 TiB free after this phase
**Source revision:** GrapheneOS tag `2026091900`
**Related:** `docs/PHOSPHOR-BUILD-PLAN.md` §5 Phase 2, `docs/PHASE-1-BUILD-HOST-READINESS.md`
**Created:** 2026-09-25

---

## 1. Purpose

Phase 2 answers one question: **can this host produce a documented,
reproducible GrapheneOS build for the Pixel 8a, before any Phosphor changes are
introduced?**

The value of doing this *before* writing Phosphor code is that it separates two
failure domains. When a build later breaks, the cause is either our changes or
the pipeline. This phase makes the pipeline a known quantity, so that afterwards
a broken build means broken Phosphor code — not an unknown host.

Nothing in this phase touched the device. No unlock, no wipe, no flash. The
Pixel's role here was to supply its identity (`akita`, `GKV4X`, build
`CP2A.260805.005`) so the build could be pinned to a matching stock revision.

---

## 2. Outcome

| | |
|---|---|
| Source tree | `~/projects/grapheneos-2026091900`, tag `2026091900`, 1057 projects |
| Provenance | Signed tag verified (§3.3) |
| Vendor files | `vendor/google_devices/akita`, 4739 files, 1.3 GB (§4) |
| Build target | `akita-cur-user` (§5.1) |
| Build command | `m -j24 vendorbootimage vendorkernelbootimage target-files-package` |
| Build result | **Build Succeeded**, 168,199 steps, 1h04m49s ninja / 1h06m30 total |
| Primary artifact | `akita-target_files.zip`, 3.6 GB, 8841 files, 17 images (§6.3) |
| Verification | Confirmed GrapheneOS, de-Googled, version-matched (§7) |
| Disk consumed | 361 GB total (219 source + 107 build + 16 adevtool deps) |
| Device state | Unchanged — still running GrapheneOS, bootloader still locked |

Phase 2's exit criterion — *"the Linux host can produce a documented
GrapheneOS-derived Pixel 8a build"* — is met, and not by argument: the build ran
to completion and its output was inspected.

---

## 3. Source acquisition and provenance

### 3.1 Revision selection

Tag `2026091900`, the current GrapheneOS **stable** release for the Pixel 8a.
Deliberately not the `17` development branch — that branch is for generic and
emulator targets, and using it would have produced a build not matching the
device.

**Release-number discrepancy, resolved:** the device reports incremental
`2026091901`, but `refs/tags/2026091901` does not exist in
`platform_manifest`, and the releases page lists `2026091900` for Pixel 8a
Stable and Beta. GrapheneOS replaces a build mid-channel when Beta testing
catches a problem, which leaves devices carrying a build number with no matching
source tag. `2026091900` is therefore the correct source, and the build
confirmed it: the resulting fingerprint's build ID matches the device exactly
(§6.4).

### 3.2 Synchronisation

```bash
repo init -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/2026091900
repo sync -j8
```

1057 projects, all present and checked out (verified by comparing the manifest's
`<project>` count against checked-out `.git` entries — 1057 against 1057).

The tree was **relocated before syncing, never after**: an init-only tree has no
baked absolute paths, but once synced every `.repo/projects/*/config` records an
absolute `worktree` path and moving it breaks the tree. This is why
`~/projects/grapheneos-2026091900` was created in place rather than moved later.

### 3.3 Provenance

The manifest's signed tag was verified before any build:

```
git verify-tag 2026091900
  -> Good "git" signature for contact@grapheneos.org
     with ED25519 key SHA256:AhgHif0mei+9aNyKLfMZBh2yptHdw/aN7Tlh/j2eFwM
```

Signature verification is not optional here — it is what makes the tree
provenanced rather than merely downloaded. `repo` itself verifies via GPG by
default, and the stable manifest refers to other repositories by commit hash
rather than tag name, so one verified tag transitively pins all 1057 projects.

### 3.4 Reproducibility pin

```bash
repo manifest -r > .repo/manifest-pinned.xml
```

1085 lines, every project pinned to a commit hash. This is the artifact that
makes a future rebuild of *this exact* revision possible, and it is the input a
reproducible-build comparison against an official GrapheneOS release would need.

---

## 4. Vendor files

The Pixel 8a's firmware and vendor blobs are not buildable from source and are
not in the manifest. They are extracted from stock factory images:

```bash
PATH="$HOME/android-sdk/node24/bin:$PATH" yarnpkg --cwd vendor/adevtool/ install
PATH="$HOME/android-sdk/node24/bin:$PATH" vendor/adevtool/bin/run generate-all -d akita
```

Result: `vendor/google_devices/akita` — 4739 files, 1.3 GB, including `akita.mk`,
`BoardConfig.mk`, `AndroidProducts.mk`, SELinux policy, overlays, and the
`firmware/` directory of bootloader/modem images.

Stock images unpacked (24 GB, cached in `vendor/adevtool/dl/`):

| Stock build | Note |
|---|---|
| `akita-CP2A.260805.005` | the build the device is running, and the one the build pins to |
| `akita-CP3A.260905.009` | a newer release of the same major line |

**The device tree is not `device/google/akita`.** The manifest declares no such
project — only `device/google/akita-kernels/6.1`. GrapheneOS keeps device trees
inside adevtool's config, and the generated product makefile inherits from
there:

```
vendor/google_devices/akita/akita.mk
  -> inherit-product vendor/adevtool/config/mk/google_devices/device/akita/device.mk
```

A missing `device/google/<codename>` is therefore normal on this project, not a
sign of a broken sync. This cost real time to establish, so it is recorded here
and in the `phosphor` skill.

---

## 5. Build configuration for `akita`

### 5.1 The `lunch` combo

Modern AOSP requires `<product>-<release>-<variant>`. A bare `lunch akita-user`
is rejected outright:

```
Invalid lunch combo: akita-user
Valid combos must be of the form <product>-<release>-<variant>
```

The release config for this project is **`cur`**, giving:

```bash
lunch akita-cur-user
```

which resolves to:

```
TARGET_PRODUCT       = akita
TARGET_BUILD_VARIANT = user
PLATFORM_VERSION     = 17
PLATFORM_SECURITY_PATCH = 2026-09-01
BUILD_ID             = CP2A.260805.005
OUT_DIR              = out
```

`user` is the production variant, chosen because it is the shape GrapheneOS
actually ships. `userdebug` allows `adb root` and is more convenient for
debugging; a later development iteration may prefer it.

**Do not choose the release config by listing `build/release/build_config/`.**
That directory contains only a stale AOSP `ap2a.scl` (SDK 34, UP1A, security
patch 2024-09-05). `lunch` accepts it, but it defines no
`RELEASE_KERNEL_AKITA_DIR`, so `TARGET_KERNEL_DIR` resolves empty and the build
aborts in the board config with a misleading message about
`vendor_kernel_boot.modules.load` — an error that reads like a corrupt tree but
is actually a wrong release config. See §8.2.

### 5.2 How `BUILD_ID` is established

`build/make/core/version_util.mk:43` resolves:

```make
BUILD_ID := $(BUILD_ID_$(TARGET_PRODUCT))
```

i.e. a **per-product** variable. It is supplied by adevtool's generated
`vendor/google_devices/akita/cmds-for-envsetup.sh`, which `envsetup.sh` sources
when the product is selected:

```bash
export BUILD_ID_akita="CP2A.260805.005"
```

and the generated `akita.mk` hard-errors if it does not match:

```make
ifneq ($(BUILD_ID),CP2A.260805.005)
  $(error BUILD_ID: expected CP2A.260805.005, got $(BUILD_ID))
endif
```

Without `envsetup.sh`, the fallback in `build/make/core/build_id.mk` is
`CP2A.260605.016` and the product config fails immediately. This is the mechanism
that pins the build to the same stock release the vendor files came from — and
therefore to the same release the device is running.

### 5.3 Kernel directory

Supplied by the release config as a flag:

```
build/release/flag_values/cur/RELEASE_KERNEL_AKITA_DIR.textproto
  -> "device/google/akita-kernels/6.1/grapheneos"
```

That directory holds the prebuilt kernel (`Image.lz4`, `dtbo.img`, `System.map`)
plus the module lists the board config reads: `modules.load`,
`vendor_kernel_boot.modules.load`, `vendor_dlkm.modules.load`,
`system_dlkm.modules.load`, and the blocklists.

**The kernel is not compiled by this build.** It ships prebuilt in the kernel
repo. This retires kernel LTO as a risk — the remaining peak-memory moment is
Vanadium's link, not the kernel's.

### 5.4 Build command

GrapheneOS's documentation specifies extra targets for the Pixel 8a:

```bash
m -j24 vendorbootimage vendorkernelbootimage target-files-package
```

The bare `target-files-package` alone is insufficient for the Pixel 7-and-later
family. `-j24` was chosen deliberately over the default `NumCPU()+2` = 34; see
§8.4.

---

## 6. The baseline build

### 6.1 Result

```
ninja: 1h4m49.60s Build Succeeded: 168199 steps - 43.24/s
#### build completed successfully (01:06:30 (hh:mm:ss)) ####
exit status: 0
```

168,199 ninja steps, clean on the first attempt, no retries and no partial
restarts.

### 6.2 What was compiled

The Android platform (system_server, ART, SELinux policy, native libraries), the
app set including GrapheneOS's own applications, and packaging. The kernel was
not compiled (§5.3). The build target was the production shape — the
target-files package the signing step consumes — rather than a bare `m`
development build, so it exercises more of the pipeline.

### 6.3 Artifacts

`out/target/product/akita/` — 23 `.img` files including `boot.img`,
`init_boot.img`, `vendor_boot.img`, `vendor_kernel_boot.img`, `dtbo.img`, and the
firmware images (`abl`, `bl1`, `bl2`, `bl31`, `gsa`, `modem`, `tzsw`, …).

Primary artifact:

```
out/target/product/akita/obj/PACKAGING/target_files_intermediates/akita-target_files.zip
  3.6 GB, 8841 files, 17 images inside
```

This is the input to the Phase 3 signing step. Note there is no `super.img` at
this stage — only `super_empty.img`; the assembled images are produced later in
the release pipeline.

### 6.4 Build identity

```
google/akita/akita:17/CP2A.260805.005/2026092500:user/test-keys
```

The build ID is identical to the device's — which is the whole point of the
§5.2 mechanism, and independent confirmation that the source revision, the
vendor files, and the device all agree.

`test-keys` is expected and is the Phase 3 problem: these images are signed with
AOSP's public test keys, which the device's locked bootloader will not accept.

---

## 7. Verification — how we know it is really GrapheneOS

A successful build of the wrong thing would still exit 0, so the output was
inspected rather than trusted:

```
product/app/TrichromeChrome.apk   -> app.vanadium.browser   153.0.8010.52.0
product/app/TrichromeWebView.apk  -> app.vanadium.webview   153.0.8010.52.0
product/app/VanadiumConfig.apk    -> app.vanadium.config
com.google.android.gms directories: 0
com.android.vending directories:    0
```

Package names confirmed with `out/host/linux-x86/bin/aapt2 dump badging`, not
inferred from filenames.

**GrapheneOS names applications by module, not by package.** The browser stages
as `TrichromeChrome` and *is* `app.vanadium.browser`. Searching the output for
`app.vanadium.*` finds nothing and looks like a catastrophic miss — see §8.3.

---

## 8. Problems encountered and resolved

### 8.1 BLOCKER: AOSP's build sandbox cannot run under Ubuntu's userns restriction

**Symptom.** `adevtool generate-all` aborted with:

```
Error: .../scripts/run-build.sh ...: unexpected stderr line:
17:47:22 Build sandboxing disabled due to nsjail error.
```

**Cause.** Ubuntu (23.10 onward, so 26.04 too) sets
`kernel.apparmor_restrict_unprivileged_userns=1`, blocking unprivileged user
namespaces. AOSP's build probes nsjail once per build; the probe fails, so soong
disables the sandbox, prints that warning, and continues — **the build itself
succeeds**. But adevtool's `spawnAsync` treats any unexpected stderr line as
fatal. There is no knob to silence it: `USE_NINJA_SANDBOX` does not exist
anywhere in the tree and the probe runs unconditionally.

Confirmed directly rather than guessed:

```
$ unshare --user --map-root-user true
write failed /proc/self/uid_map: Operation not permitted
```

**Resolution.** `scripts/host-fix-nsjail-userns.sh` grants `userns` to the nsjail
binaries via AppArmor (`/etc/apparmor.d/nsjail-userns`), following the pattern
Ubuntu ships for `mmdebstrap`. Deliberately **not** a global sysctl change — the
host-wide restriction stays in place and only those paths are exempted. The
script verifies this: the sysctl still reads 1 and a plain `unshare` still
fails, while nsjail works.

**Trap for future debugging.** Do not judge this fix with a hand-rolled nsjail
probe. A bare `nsjail -H android-build -e -u nobody -g nogroup
--disable_clone_newcgroup -- /bin/bash -c ...` fails with
`execve('/bin/bash') failed: No such file or directory` *even when the fix
works*, because it omits the bind mounts AOSP passes, so nsjail mounts an empty
tmpfs over `/`. Judge it by re-running the real build, or by
`journalctl -k | grep -i apparmor` — no `unprivileged_userns` transition after
the profile loads means it worked.

### 8.2 `lunch`: the wrong release config produces a misleading error

Attempting `lunch akita-ap2a-user` (a config picked by listing the directory)
failed deep in the board config:

```
vendor/adevtool/config/mk/google_devices/common/BoardConfig-common-gs201-plus.mk:8:
error: vendor_kernel_boot.modules.load not found or empty.
cat: /vendor_kernel_boot.modules.load: No such file or directory
```

The empty path prefix was the tell: `KERNEL_MODULE_DIR := $(TARGET_KERNEL_DIR)`
was empty because `ap2a` defines no `RELEASE_KERNEL_AKITA_DIR`. The file
`vendor_kernel_boot.modules.load` was present all along.

**Resolution.** Use `cur` (§5.1). The general lesson: a build-system error naming
a *missing file* when the file demonstrably exists usually means an unset
variable upstream, not a missing file.

### 8.3 Verification trap: "Vanadium is missing"

A search of the staged output for `app.vanadium.*` returned nothing, which
looked like a de-Googled build with the browser stripped out. It was a false
alarm caused by searching for the package name instead of the module name
(§7). Recorded because it is a failure mode of *verification*, not of the build:
a check that is wrong in a way that produces a confident negative answer.

**Countermeasure adopted:** confirm package identity with `aapt2 dump badging`
rather than by filename or directory name, and cross-check completeness against
`out/target/product/akita/product_packages.txt`.

### 8.4 Memory, not CPU, was the binding constraint

The build was run at `-j24` rather than the default `NumCPU()+2` = 34, on the
reasoning that the Chromium-scale Vanadium link is the peak-memory moment.
Afterwards, swap showed **899 MiB used** — the build did brush against memory
limits. Memory, not CPU, was the constraint, and the conservative `-j24` was
justified in retrospect.

Corroborating evidence that the machine was not stressed beyond its limits:

| Check | Result |
|---|---|
| Thermal/throttle events in kernel log | 0 |
| Machine-check (MCE) events | 0 |
| NVMe errors or resets | 0 |
| CPU boost during build | 5693 / 5756 MHz sustained |
| Idle temps afterwards | Tctl 45.0 °C, CCD0 37.5 °C, CCD1 39.2 °C |

Board-level (VRM/chipset) temperatures could **not** be obtained — see §10.2.

### 8.5 `grep -c 'error:'` on the build log is useless

It matches the Rust crate `thiserror`, producing dozens of false positives. Grep
for `ninja: build stopped` or `FAILED:` instead.

---

## 9. Resource ledger

| Item | Size |
|---|---|
| Source tree (excluding build output) | 219 GB |
| — of which `.repo` git history | 93 GB |
| — of which adevtool factory-image downloads | 24 GB |
| Build output `out/` | 107 GB |
| adevtool dependency build `out_adevtool_deps/` | 16 GB |
| **Total consumed** | **361 GB** (1.4 TiB free) |
| Build wall time | 1h06m30 |

Budget guidance for future work: ~360 GB per full build tree, and roughly an
hour per clean build. Incremental builds after a source change are dramatically
faster and are the normal development loop.

---

## 10. Deviations and known limitations

### 10.1 adevtool is no longer byte-identical to the pinned revision

`yarnpkg install` migrated `vendor/adevtool` to the newest Yarn, dirtying
`package.json` and `yarn.lock` and adding `.yarnrc.yml` and `.yarn/`. This is the
documented GrapheneOS step, not corruption — but it means that subproject no
longer matches tag `2026091900` exactly. Relevant to any future
reproducible-build comparison, which should either account for it or run the
install with a pinned Yarn.

### 10.2 Board-level temperatures are unavailable on this host

Attempted and abandoned. The board (ASRock B850 Pro RS WiFi) carries a Nuvoton
NCT6687-R reporting chip ID `0xd802`. The in-kernel `nct6683` driver will not
bind to it, there are no ACPI thermal zones, and nothing exposes fan RPM. The
out-of-tree `nct6687d` module attaches under `force=1` but reads a register map
that does not match, producing impossible values (256 °C, 0 °C, 65,280 RPM) and
an EC firmware version of `255.255` — i.e. `0xFF`, empty registers.

The module was removed; leaving a sensor source that reports fiction is worse
than having none. `/opt/nct6687d` is retained in case the register map is
pursued later. **No conclusion in this document depends on board sensors** —
CPU, NVMe, DIMM and iGPU sensors are reliable and were sufficient to confirm the
machine was never thermally limited.

The proper fix is upstream: a support request to the driver with the board's DMI
info and chip ID so `0xd802` is added to its table after the register map is
verified.

---

## 11. Source and dependency map

Initial map, to be extended in Phase 4.

**Repositories that matter for Phosphor work:**

| Path | Role |
|---|---|
| `build/`, `build/soong/`, `build/make/` | GrapheneOS's fork of the build system — this is where `BUILD_ID`, release configs and board config resolution live |
| `vendor/adevtool/` | device/vendor file generation, device trees (`config/mk/google_devices/device/<dev>/`) |
| `vendor/google_devices/akita/` | generated vendor module — do not hand-edit, regenerated by adevtool |
| `device/google/akita-kernels/6.1/grapheneos/` | prebuilt kernel and module lists |
| `build/release/flag_values/cur/` | per-release flags, including the kernel directory |
| `external/vanadium/` | prebuilt Vanadium browser, WebView and config APKs |
| `frameworks/base/` | the platform — the likely home for Phosphor system services |
| `packages/apps/` | system apps, including GrapheneOS's own |

**Host toolchain dependencies (all verified installed):** `repo` 2.65
(standalone, self-updating), Google platform-tools (`adb` 1.0.41 / `fastboot`
37.0.1, not apt), Node.js 24 LTS side-by-side with host Node 26 (adevtool
requirement), `yarnpkg` 4.1.0, `gperf` 3.3, `git-lfs` 3.7.1, 32-bit glibc
(`libc6-i386`) and 32-bit gcc runtime (`lib32gcc-s1`) for Vanadium,
`android-sdk-platform-tools-common` for udev rules. AOSP ships its own clang,
ninja and ccache equivalents — those are not host dependencies.

**Not used, deliberately:** `OFFICIAL_BUILD=true`. It enables the Updater app
pointed at GrapheneOS's real update server, which against a differently-signed
build is effectively a denial-of-service on their infrastructure. It stays unset
unless the update URL in `packages/apps/Updater/res/values/config.xml` is
repointed at our own server.

---

## 12. Exit criteria assessment

Phase 2's criterion: *"The Linux host can produce a documented GrapheneOS-derived
Pixel 8a build, or any blocker is identified with evidence and a resolution
path."*

**MET.** A complete production-shape build of GrapheneOS for `akita` was produced
and verified on this host, on an officially unsupported distro, with the
provenance chain intact.

Plan deliverables:

| Deliverable | Status |
|---|---|
| Verified GrapheneOS source tree | Done — §3 |
| Documented `akita` build configuration | Done — §5 |
| Baseline build artifacts | Done — §6.3 |
| Build procedure and troubleshooting notes | Done — §5, §8, Appendix A |
| Initial source and dependency map | Started — §11, to be extended in Phase 4 |

---

## 13. Handoff to Phase 3

Phase 3 is signing, flashing and recovery. Its first deliverable is a **key
hierarchy and custody design**, and its own text gates key generation behind that
design being approved — so the phase begins as design work, not action.

**The open decision is the bootloader unlock.** Phase 3's exit criterion ("a
known-good custom build can be flashed, booted, diagnosed, and restored")
eventually requires it, and unlocking wipes the device. Two considerations:

1. The images produced in this phase carry **public test keys** and the device's
   bootloader is locked and will not accept them. Nothing here is flashable as
   built.
2. Our build is currently *unmodified* GrapheneOS. Flashing it would wipe a
   working phone to install something functionally identical to what is already
   on it.

There is a sound argument for doing it early anyway — flashing our own
unmodified build is the control experiment, so that if a later Phosphor build
misbehaves we know it is our code and not the pipeline. That is a judgment call
about a working device and belongs to the project owner.

**Recommendation:** complete the key-management design and the
signing/flash/recovery tooling first (no device risk, all dry-runnable), and take
the unlock decision when there is either a Phosphor build worth installing or a
deliberate choice to validate the pipeline as a control.

---

## Appendix A — Exact reproduction recipe

```bash
# 1. Source (once)
mkdir -p ~/projects && cd ~/projects
repo init -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/2026091900
cd .repo/manifests && git config gpg.ssh.allowedSignersFile ~/.ssh/grapheneos_allowed_signers
git verify-tag "$(git describe)"        # expect: Good "git" signature for contact@grapheneos.org
cd ../.. && repo sync -j8                # ~219 GB, resumable
repo manifest -r > .repo/manifest-pinned.xml

# 2. Vendor files (once)
export PATH="$HOME/android-sdk/node24/bin:$PATH"
yarnpkg --cwd vendor/adevtool/ install
vendor/adevtool/bin/run generate-all -d akita

# 3. Build
source build/envsetup.sh
lunch akita-cur-user                     # NOT akita-user, NOT akita-ap2a-user
m -j24 vendorbootimage vendorkernelbootimage target-files-package

# 4. Verify
out/host/linux-x86/bin/aapt2 dump badging \
  out/target/product/akita/product/app/TrichromeChrome/TrichromeChrome.apk
cat out/target/product/akita/build_fingerprint-akita.txt
ls out/target/product/akita/obj/PACKAGING/target_files_intermediates/
```

## Appendix B — Where things live

| Thing | Path |
|---|---|
| GrapheneOS source tree | `~/projects/grapheneos-2026091900` |
| Pinned revisions | `~/projects/grapheneos-2026091900/.repo/manifest-pinned.xml` |
| Build output | `~/projects/grapheneos-2026091900/out/` |
| Target-files package | `.../out/target/product/akita/obj/PACKAGING/target_files_intermediates/akita-target_files.zip` |
| Build log | `~/akita-build.log` |
| Sandbox fix | `scripts/host-fix-nsjail-userns.sh` → `/etc/apparmor.d/nsjail-userns` |
| Host toolchain | `~/android-sdk/`, `~/.local/bin/repo` |
| adevtool source (unused sensor driver) | `/opt/nct6687d` |
