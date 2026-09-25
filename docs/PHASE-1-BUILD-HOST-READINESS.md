# Phase 1 — Build-Host and Device Readiness

**Status:** COMPLETE bar the recovery position — host and toolchain verified
(§4), source-fetch chain verified (§4.4), workspace under `~/projects` (§4.5),
device authorized and baseline captured (§5). Next: Phase 2.
**Project:** Phosphor
**Target device:** Google Pixel 8a (`akita`)
**Build host:** `qoder` — Ubuntu 26.04.1 LTS, AMD Ryzen 9 9950X, 59 GiB RAM
**Related:** `docs/PHOSPHOR-VISION.md`, `docs/PHOSPHOR-BUILD-PLAN.md` §5 Phase 1
**Created:** 2026-09-24

---

## 1. Purpose

Phase 1 answers one question: **can this computer build a GrapheneOS-derived
Phosphor image for the Pixel 8a, and can it talk to the Pixel safely?**

This document is read-only with respect to the device. It does not unlock,
wipe, flash, relock, or otherwise modify the Pixel. Destructive device
operations require explicit approval at the point of action
(`PHOSPHOR-VISION.md` §Development model).

Authority for everything below: <https://grapheneos.org/build> and
<https://grapheneos.org/install/cli>, retrieved 2026-09-24.

---

## 2. Host audit

| Item | Requirement | Actual | Status |
|---|---|---|---|
| Architecture | x86_64 Linux | x86_64, AMD Ryzen 9 9950X (16C/32T), 5756 MHz max | PASS |
| Memory | 32 GiB or more | 59 GiB total, 55 GiB available, 8 GiB swap | PASS |
| Storage (source) | 136 GiB+ with history, 90 GiB+ lightweight | 1.7 TiB free on `/dev/nvme0n1p2` | PASS |
| Storage (build) | 100 GiB+ additional for a full multiarch build | same volume | PASS |
| Filesystem | case-sensitive (AOSP hard requirement) | ext4 | PASS |
| Operating system | Arch, Debian bookworm, Ubuntu 24.10, Ubuntu 24.04 LTS | **Ubuntu 26.04.1 LTS (`resolute`)** | **UNSUPPORTED** |
| Kernel | — | 7.0.0-34-generic | — |
| Toolchain | see §4 | see §4 | PASS (2026-09-24) |
| Source fetch chain | repo + signed manifest | **verified end to end** (§4.4) | PASS |
| USB / udev | non-root device access | `plugdev` held; `51-android.rules` installed; device authorized | PASS |
| `adb` / `fastboot` | fastboot >= 35.0.1 | adb 1.0.41 / fastboot 37.0.1 (platform-tools 37.0.1) | PASS |

### 2.1 Storage budget

| Allocation | Size |
|---|---|
| GrapheneOS source sync with history | 136 GiB+ |
| Typical full-OS build output | 100 GiB+ |
| Emulator target build (`sdk_phone64_x86_64`) | tens of GiB |
| **Recommended reserve** | **~400 GiB** |

Free: 1.7 TiB. Headroom is not a constraint at any point.

Memory is the binding resource, not disk: "Link-Time Optimization (LTO)
creates huge peaks during linking and is mandatory for Control Flow
Integrity (CFI). Linking Vanadium (Chromium) and the Linux kernel with
LTO + CFI are the most memory demanding tasks." 59 GiB comfortably exceeds
the stated 32 GiB floor.

---

## 3. Decision record — build host distribution

**Context.** GrapheneOS lists four supported build hosts: Arch Linux, Debian
bookworm, Ubuntu 24.10, Ubuntu 24.04 LTS. This host runs Ubuntu 26.04.1 LTS.
Ubuntu offers no supported path backwards: there is no `do-release-downgrade`,
and reversing a release in place requires retargeting apt sources to an older
codename with pin files and `aptitude dist-upgrade`. Because LTS-to-LTS
reverse hops are not possible in a single run, that means 26.04 → 25.10 →
24.04, two unsupported transactions, which in practice leaves a hybrid system
(wrong default kernel, mismatched `libc6`, broken GRUB, Python conflicts).
The supported rollback is reinstall or snapshot restore.

A clean reinstall was rejected: this host is a working desktop, not a
dedicated build server.

**Note on the 26.04 install itself:** Canonical holds the 24.04 → 26.04
upgrade path closed until the first point release ships, so this machine is a
fresh 26.04 install rather than an upgraded one. There is no partially
migrated package state behind the distro question.

**Decision (2026-09-24):** proceed on Ubuntu 26.04 as-is (**Option E**).

Rationale: nothing in the GrapheneOS or AOSP build system enforces a distro
version. AOSP "provides a prebuilt toolchain and other utilities fulfilling
most of the build dependency requirements itself," runs the build "within a
loose sandbox to avoid accidental dependencies on the host system," and
targets "minimal external dependencies." The host's contribution is a short,
enumerable dependency list, not a compiler toolchain. The realistic failure
modes are host Python (`repo` and build scripts), host OpenJDK, and the
namespace-based build sandbox — all of which surface early rather than
silently.

Accepted cost: no upstream support if the build fails for
distribution-specific reasons; a failed late-stage build costs the sync plus
build time. The LTO link of Vanadium and the kernel is the expensive part.

**Fallback path, in order:**

1. **Option A — systemd-nspawn container.** Debootstrap a Debian bookworm or
   Ubuntu 24.04 LTS rootfs, bind-mount the source tree from the host ext4
   filesystem. `systemd` is already present, so no new daemon is needed and
   overhead is near-native. Note the build sandbox uses Linux namespaces and
   the container must be permissive enough for it, or the sandbox must be
   disabled explicitly rather than allowed to fail obscurely.
2. **Option B — Docker/Podman container.** Well-trodden for AOSP; existing
   images build GrapheneOS specifically. Containers commonly need
   `--privileged` or relaxed seccomp for the build sandbox.

Both keep the desktop untouched and put the build on a distro GrapheneOS
supports. Neither changes the source tree location: the tree lives on the
host ext4 filesystem and is bind-mounted, so it is safe to sync now under
Option E and keep it if we fall back.

**Trigger for falling back:** any fatal build failure attributable to the
host distribution that is not cheaply worked around. Record the failure and
the evidence before switching.

**De-risking step, independent of the distro decision:** build the
`sdk_phone64_x86_64` emulator target first. Same toolchain, same source tree,
no phone involved, and GrapheneOS recommends it "for use in most development
work" anyway. If the emulator target builds, the host is proven before the
Pixel is ever touched. This is Milestone B territory (Phase 2), not Phase 1.

---

## 4. Toolchain

### 4.1 Installed

| Component | Version | Location | Provenance |
|---|---|---|---|
| `repo` (standalone) | launcher 2.65 | `~/.local/bin/repo` | `storage.googleapis.com/git-repo-downloads/repo` |
| platform-tools (`adb`, `fastboot`) | 37.0.1 | `~/android-sdk/platform-tools` | `dl.google.com/android/repository/platform-tools-latest-linux.zip`, sha256 `d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1` |
| Node.js (for `adevtool`) | v24.21.0 LTS | `~/android-sdk/node24` | nodejs.org `latest-v24.x`, sha256 verified against published `SHASUMS256.txt` |

`repo` is deliberately the self-updating standalone variant rather than the
distribution package: GrapheneOS recommends it to avoid "dealing with
out-of-date distribution packages," and it depends on GPG to verify its own
updates.

`fastboot` 37.0.1 satisfies GrapheneOS's >= 35.0.1 requirement. The
distribution `platform-tools` package was deliberately not used: GrapheneOS
warns that most distributions "mistakenly package development snapshots of
fastboot" and clobber the upstream version scheme.

Node 24 LTS is kept **side by side** with the host's Node 26.10.0 rather than
replacing it. `adevtool` must be run against Node 24:

```bash
PATH="$HOME/android-sdk/node24/bin:$PATH" yarnpkg --cwd vendor/adevtool/ install
```

### 4.2 Host packages — INSTALLED 2026-09-24

Installed by `scripts/host-setup-phase1.sh` (`sudo bash
scripts/host-setup-phase1.sh`), which is idempotent and verifies itself. 18
packages are declared; 12 were already satisfied on this host, 6 installed:

| Installed 2026-09-24 | Version |
|---|---|
| `gperf` | 3.3 |
| `git-lfs` | 3.7.1 |
| `yarnpkg` | 4.1.0 |
| `libc6-i386` | 2.43 |
| `lib32gcc-s1` | 16 |
| `android-sdk-platform-tools-common` | 28.0.2 |

Independently re-verified after the install: every declared package resolves
against the archive, each of the six is on disk at the version above, the udev
rules landed at `/lib/udev/rules.d/51-android.rules` with the Google
`18d1` vendor entry, and `/usr/lib32/libc.so.6` plus `/usr/lib32/libgcc_s.so.1`
exist so the 32-bit Vanadium build path is live.

Why each package:

| Package | Why |
|---|---|
| `yarnpkg` | `adevtool` (Debian/Ubuntu reserve `yarn` for `cmdtest`) |
| `gperf` | AOSP host dependency |
| `git-lfs` | Vanadium (Chromium) build |
| `libc6-i386` | "32-bit glibc" for Vanadium |
| `lib32gcc-s1` | "32-bit gcc runtime library" for Vanadium |
| `fontconfig`, `fonts-dejavu-core`, `libfreetype6` | OpenJDK font stack — it is a headless variant but still needs freetype2, fontconfig and a TrueType font |
| `android-sdk-platform-tools-common` | udev rules for Pixel devices (GrapheneOS's own recommendation for Debian/Ubuntu) |

Already present and verified on this host: `python3` 3.14.4, `git` 2.53.0,
`make` 4.4.1, `openssl` 3.5.5, `ssh-keygen`, `gpg`/`gnupg`, `diffutils`,
`rsync`, `unzip`, `zip`, `wget`, `curl`, `cc`/`gcc`/`g++`.

Not required: `ccache`, `clang`, `ninja`. AOSP supplies its own prebuilt
toolchain from source-tree repositories.

### 4.3 PATH

Applied to `~/.bashrc` in a marked block:

```bash
export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"
export PATH="$HOME/.local/bin:$HOME/android-sdk/platform-tools:$HOME/android-sdk/node24/bin:$PATH"
```

The first line is GrapheneOS's documented fix — "many system administration
commands will fail" otherwise. The build must run from `bash` or `zsh`;
`envsetup.sh` is not compatible with other shells.

Verified in an interactive shell: `adb`, `fastboot`, `repo` all resolve.

### 4.4 Source fetch chain — VERIFIED

The risk that this unsupported host blocks source acquisition is now retired
by direct test rather than inference. Performed 2026-09-24:

```bash
mkdir ~/projects/grapheneos-2026091900 && cd ~/projects/grapheneos-2026091900
repo init -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/2026091900

curl https://grapheneos.org/allowed_signers > ~/.ssh/grapheneos_allowed_signers
cd .repo/manifests
git config gpg.ssh.allowedSignersFile ~/.ssh/grapheneos_allowed_signers
git verify-tag "$(git describe)"
```

Results:

| Check | Result |
|---|---|
| `repo init` on Ubuntu 26.04 | **succeeded** |
| `repo` on host Python 3.14.4 | **runs** (launcher 2.65) |
| Manifest tag | `2026091900` |
| Tag signature | `Good "git" signature for contact@grapheneos.org with ED25519 key SHA256:AhgHif0mei+9aNyKLfMZBh2yptHdw/aN7Tlh/j2eFwM` |
| Projects in manifest | 1057 |
| `akita` present in manifest | yes (`akita-kernels/6.1`) |
| Tree size after `repo init` | 33 MiB |
| Tree location | `~/projects/grapheneos-2026091900` |

**Tag choice.** `2026091900` is the current Stable release across Pixel 8a,
Beta and Alpha — the Pixel 8a's own Stable version, not a generic tag.
GrapheneOS advises using "the most recent stable tag, not the development
branch, even for developing a feature... It's easier to port between stable
tags that are known to work properly than dealing with a moving target." The
`17` branch is the Android 17 development branch and is the recommended
branch only for *generic* builds including the emulator.

**Signed-tag verification is not optional.** The manifest is signed by
`contact@grapheneos.org`; the allowed-signers file is fetched over HTTPS from
grapheneos.org and the tag verified locally. This is what makes the tree
provenanced rather than merely downloaded.

**Note for the emulator de-risk:** the emulator target belongs on the `17`
development branch, not this stable tag. Expect a second, separate tree (or a
`repo init` branch switch with `--force-sync`) when that build is attempted.

### 4.5 Workspace layout — develcakes convention

The development environment on this host is **develcakes** (CrabCakes:PDE,
`github.com/qsmtco/develcakes`), a GTK4 desktop project-development
environment. Its config defines `CRABCAKES_PROJECTS_DIR`, default `~/projects`,
as the "root directory for projects" — and that default is not overridden on
this machine.

Adopted 2026-09-24:

| Path | Role |
|---|---|
| `/home/cptjaqx/projects/Phosphor` | the Phosphor repository |
| `/home/cptjaqx/projects/grapheneos-<tag>` | the GrapheneOS source tree (upstream source, 1057 repositories; appears in develcakes as a project) |
| `~/android-sdk` | toolchain (platform-tools, Node 24 LTS) — deliberately outside `~/projects` |
| `~/.local/bin/repo`, `~/.ssh/grapheneos_allowed_signers` | toolchain and tag-verification trust file — outside `~/projects` |

Anything that is project source lives under `~/projects`; host tools and trust
material do not, so they never appear as bogus entries in the develcakes
project list.

**Move the tree before `repo sync`, never after.** An init-only tree carries no
absolute paths — verified, the sole absolute reference in `.repo` is
`allowedSignersFile`, which points into `~/.ssh` and stays valid wherever the
tree lives. Once synced, every repository under `.repo/projects/*/config`
records an absolute `worktree` path and relocating the tree is no longer safe.

---

## 5. Device readiness

**RESOLVED 2026-09-24 — the Pixel 8a is authorized and its baseline is captured.**

| Field | Value |
|---|---|
| USB ID | `18d1:4ee7` — Google Nexus/Pixel Device (charging + debug) |
| ADB interface | vendor-specific class `ff`, subclass `42`, protocol `01` |
| Product string | `Pixel 8a` |
| Serial | `3C121JEKB03922` |
| Transport | `usb:5-2`, direct on the PCI root controller (no hub) |
| Device node | `/dev/bus/usb/005/005`, `root:plugdev`, mode `crw-rw-r--` |
| `adb devices` | `3C121JEKB03922  device  product:akita model:Pixel_8a device:akita` |

The earlier MTP-only enumeration (`18d1:4ee1`) was the phone not offering an
ADB endpoint at all — that is a descriptor fact, not an authorization state,
which is why no amount of authorization would have made `adb` see it. The PID
meanings, read from the installed `51-android.rules` rather than inferred:
`4ee1` = mtp, `4ee2` = mtp+adb, `4ee5` = ptp, `4ee6` = ptp+adb, `4ee7` = adb,
`4ee9` = midi+adb. The device came up as `4ee7` once USB debugging was enabled
and the link was re-established by replugging.

### 5.1 No-change baseline — CAPTURED 2026-09-24

Raw capture with the full property set: `docs/evidence/pixel8a-baseline-20260924-1038.txt`.

| Field | Value |
|---|---|
| Model / codename | Pixel 8a / `akita` |
| SKU | **`GKV4X`** — international, factory unlocked |
| Build | `akita-user 17 CP2A.260805.005 2026091901 release-keys` |
| Android version | 17 |
| Security patch | 2026-09-01 |
| Verified boot state | **`yellow`** — custom OS signing key, bootloader locked |
| Bootloader | **LOCKED** (`ro.boot.flash.locked=1`, `vbmeta.device_state=locked`) |
| dm-verity | `enforcing` |
| Build type | `user`, `release-keys`, `ro.debuggable=0`, `ro.secure=1` |
| Active slot | `_a` |
| Bootloader version | `akita-17.0-15199481` |
| Carrier / Verizon check | **clean** — no Verizon or VZW strings anywhere in the property set |
| Uptime at capture | 2 days 8:41 |
| OEM unlocking permitted | **unknown** — not exposed via `getprop` on this build |

### 5.2 FINDING — GrapheneOS is already installed

This is not a stock Pixel; it is running official GrapheneOS:

- `app.grapheneos.*` packages: `gmscompat`, `gmscompat.config`, `gmscompat.lib`,
  `camera`, `pdfviewer`, `setupwizard`, `speechservices`, `logviewer`,
  `networklocation`, `carrierconfig2`, `backup.contacts`, `info`, `apps`,
  `AppCompatConfig`
- `app.vanadium.browser`, `app.vanadium.webview`, `app.vanadium.config`
  (Vanadium is GrapheneOS's hardened Chromium)
- overlays `android.overlay.grapheneos`, `android.overlay.akita.grapheneos`,
  `com.android.phone.overlay.grapheneos`
- **zero** `com.google.android.gms` / `com.android.vending` packages — de-Googled
- `ro.build.host = r-0123456789abcdef-0123`, GrapheneOS's redacted
  reproducible-build hostname
- verified boot `yellow` on a locked bootloader: GrapheneOS signs with its own
  keys, so `yellow` is the correct, expected state for a properly installed
  device — `green` would mean a Google-signed OS

Two consequences:

1. `PHOSPHOR_SPEC.md` build order step 1 (flash GrapheneOS via the web
   installer) and `docs/ANDROID.md` step 1 are **already done**. The device
   track starts at Milestone B (baseline custom build), not at the installer.
2. The device is **locked**. Any image of our own requires unlocking the
   bootloader first — which wipes it — because a self-signed image cannot
   satisfy the existing verified-boot chain.

**On the release numbers.** The device reports incremental `2026091901`, but
the only source tag published for this release is `2026091900`:
`refs/tags/2026091901` does not exist in `platform_manifest`, and the releases
page lists Pixel 8a Stable and Beta as `2026091900`. GrapheneOS replaces a
build mid-channel when Beta testing catches a problem ("a new release is made
via the Beta channel to replace the aborted one"), which leaves a device
carrying a build number with no matching source tag. The initialized tree at
tag `2026091900` is therefore the correct matching source. No change needed.

**Remaining device unknown.** Whether OEM unlocking is permitted. It is not
exposed via `getprop` on this build, so it must be read from Developer options
on the phone or from the bootloader with `fastboot getvar`. `GKV4X` is the
international SKU with no carrier lock, so the Verizon blocker does not apply.

### 5.3 Before any flash

GrapheneOS's CLI install guide notes that fwupd — which is running on this host
— "is known to incorrectly connect to arbitrary devices using the fastboot
protocol which will block using them for the intended purpose." Before any
flash operation:

```bash
sudo systemctl stop fwupd.service
```

Stopping it is temporary; it returns on reboot. Nothing to do until a flash is
actually scheduled.

**The Pixel will be wiped by unlocking the bootloader and again by relocking
it.** Anything on it worth keeping must be backed up before approval for
those operations is requested.

---

## 6. Recovery and backup position

**Host.** This machine holds the only copy of the build environment and will
hold the only copy of the source tree and signing keys. Before Phase 3
(signing) it needs an off-host backup path for key material. The host has a
Yubikey 4/5 on USB, which is a candidate for key custody per
`PHOSPHOR-BUILD-PLAN.md` §6.2 ("Never place private release keys in source
control, ordinary build directories, chat, logs, or unencrypted backups").
No keys have been generated; nothing to protect yet.

**Device.** Stock Android is restorable via the same GrapheneOS web installer
in roughly ten minutes, and the bootloader can be relocked. Recovery depends
on the current bootloader state, which is unknown until §5.1 is filled in.

**Build reproducibility.** `repo manifest -r` pins every repository to
commit hashes rather than tags, which is the mechanism that makes a build
reproducible across time. Capture it after each successful sync.

---

## 7. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Build fails on unsupported Ubuntu 26.04 | Medium | High — no upstream support, hours lost | Fall back to Option A, then B (§3). Prove the host with the emulator target before touching the Pixel |
| R2 | Host Python 3.14 breaks `repo` or build scripts | **Low — downgraded** | Medium | `repo` 2.65 verified running under 3.14.4, and the signed manifest fetched and verified (§4.4). Residual risk is build-system Python, not `repo` |
| R3 | Host OpenJDK version mismatch | Low | Medium | Fail-fast class of error; not yet exercised |
| R4 | Build sandbox blocked by namespaces in a container | Low (not containerized yet) | Low | Becomes relevant only under Option A/B; disable the sandbox explicitly if needed |
| R5 | fwupd claims the device over fastboot | Medium | Low | `sudo systemctl stop fwupd.service` before flashing |
| R6 | Wrong Pixel SKU (Verizon, locked bootloader) | **RESOLVED** | — | SKU confirmed `GKV4X` (international, no carrier lock); zero Verizon strings on the device |
| R7 | Data loss on the Pixel from an unlock/wipe | Certain if proceeded without backup | High | Backup first; explicit approval per operation |
| R8 | Signing keys lost or leaked | Not yet applicable | Catastrophic | Key-custody design is a Phase 3 deliverable; Yubikey present |
| R9 | Source tree synced to a tag that cannot build on this host | Low | Medium | Tag verified signed; emulator de-risk build precedes any `akita` build |

---

## 8. Exit criteria

From `PHOSPHOR-BUILD-PLAN.md`: "We know whether the existing computer can
build the target and communicate with the Pixel safely, and all destructive
prerequisites are clearly identified."

| Criterion | Status |
|---|---|
| Host hardware sufficient | **MET** — CPU, RAM, disk, filesystem all exceed requirements |
| Host toolchain complete | **MET** — all packages installed and independently re-verified (2026-09-24) |
| Source fetch chain works on this host | **MET** — `repo init` + signed manifest verification succeeded (§4.4) |
| Distro question resolved | **MET** — decision recorded, fallbacks specified |
| USB / udev / adb / fastboot ready | **MET for adb** — device authorized and enumerating as `18d1:4ee7`; `fastboot devices` untested (needs bootloader mode) |
| Device identified | **MET** — Pixel 8a `akita`, SKU `GKV4X`, GrapheneOS 17 build 2026091901, locked bootloader, baseline in `docs/evidence/` |
| Destructive prerequisites identified | **MET** — unlock and relock both wipe; backup required first; Verizon units are unusable |
| Storage budget confirmed | **MET** — 1.7 TiB free against ~400 GiB needed |
| Recovery position documented | PARTIAL — host backup path open; device state unknown |

---

## 9. Next actions

1. ~~`sudo bash scripts/host-setup-phase1.sh`~~ — **DONE 2026-09-24**, verified.
2. ~~Enable USB debugging; authorize the host on the device~~ — **DONE 2026-09-24**.
3. ~~Capture the no-change baseline and the `GKV4X`/`G6GPR` SKU check~~ —
   **DONE 2026-09-24**. `GKV4X`, no carrier lock, GrapheneOS already installed.
4. Read the OEM-unlock state, the one device fact still unknown (§5.2). Either
   Developer options on the phone, or `fastboot getvar` with the device in
   bootloader mode — the latter needs `sudo systemctl stop fwupd.service` first.
   **Entering bootloader mode is a device operation: ask before doing it.**
5. Phase 1 exit — move to Phase 2 (GrapheneOS source and build foundation).
   The source tree is initialized and tag-verified at
   `~/projects/grapheneos-2026091900`; `repo sync -j8` completes the download
   (136 GiB with history). Then build the `sdk_phone64_x86_64` emulator target
   to validate the host before committing to a full `akita` build.

---

*End of Phase 1.*
