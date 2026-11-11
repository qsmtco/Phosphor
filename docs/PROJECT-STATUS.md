# Phosphor — Project Status and Handoff

**Snapshot:** 2026-11-10 (supersedes the 2026-09-25 snapshot; that version is in git history at commit `842da7a`)
**Audience:** the develcakes team (Coder / Debugger / Supervisor) and Captain JAQ.
**Purpose:** get an engineer — human or agent — from zero to productive on Phosphor without re-deriving anything.
**Governing document:** `docs/PHOSPHOR-VISION.md` (the goal and source of truth). This file records *where we are*; when it disagrees with the vision, the vision wins.

---

## 1. What Phosphor is

An **agent-native phone operating system**: a GrapheneOS-derived Android platform in which the AI agent is the primary interface and a system coordinator, not an app. The user speaks; the agent resolves intent, calls the appropriate platform capability, and renders the active screen as HTML/JavaScript in real time. Home, notifications, calls, messages, settings, camera and sensors all flow through that one agent-controlled surface.

One-sentence definition (from the vision): *Phosphor is a GrapheneOS-based, voice-first, agent-native phone operating system whose agent designs and renders the active HTML/JavaScript interface in real time, allowing Captain JAQ to use the Pixel as a coordinated team member.*

- **Target device:** Google Pixel 8a, codename `akita`, model GKV4X (international, not carrier-locked). Serial `3C121JEKB03922`.
- **Target foundation:** GrapheneOS-derived image, our own signing keys, our own AVB root of trust.
- **Development host:** `qoder` (Linux) + USB to the Pixel.

### What Phosphor is NOT

Do not redirect this project into any of these because they are easier:

- a normal Android app that calls the stock Phone/Messages apps;
- a chatbot floating on top of GrapheneOS;
- a browser shell presented as the final product;
- a Termux-hosted runtime presented as the operating system;
- a Debian VM presented as the OS;
- a collection of loosely connected apps with an AI front-end.

The repo's pre-existing material — the copied DragonCakes-derived Python agent runtime, the Python HTTP runtime, the browser shell, local Whisper, the Rust bridge, Termux/:API/:Boot, Tailscale/SSH, the on-device workspace — is **prototype and bring-up material only**. Commit `a1dc69a` marks those PoC-era architecture decisions as superseded. `docs/VERIFICATION.md` verifies the **iOS proof-of-concept** (2026-09-04, front-end-agnostic trust requirements); it is not Android/GrapheneOS verification.

---

## 2. Where we are, in one line

**Phases 1–3 are complete and cryptographically verified:** we built a GrapheneOS-derived image from source, signed it with Phosphor's own key chain, flashed it to the Pixel 8a, booted it, and proved the recovery path. **The image is still unmodified GrapheneOS — zero lines of Phosphor code are in it.**

The vision's first milestone has two halves: *build and boot a GrapheneOS-derived image* (**done**) and *that presents Phosphor as the primary system shell* (**not started**).

### What is proven

| Claim | How it was settled |
|---|---|
| The build/sign/flash chain works end to end | Cryptographic, not observational: the bootloader's `ro.boot.vbmeta.digest` equals `sha256()` of the first `ro.boot.vbmeta.size` bytes (7488) of the `vbmeta.img` we flashed — `bd17532d485543cabba4d54796461d3c972df9c8d7161930a68d0a0a1d9cf127`. Booting proves nothing on an unlocked bootloader; this comparison is what settles it. |
| We own the key chain | 9 APK/platform keys + the AVB key, generated once, scrypt/PBES2-encrypted, passphrase sealed behind a YubiKey PIV wrap key. Signed release independently verified: OTA cert byte-identical to `releasekey.x509.pem`; vbmeta verifies against the key rebuilt from `avb_pkmd.bin`; system APKs carry our platform cert. |
| Keys are backed up off-host | Escrow on the offline `PHOSPHOR-ESCROW` USB plus a paper copy; the host copy was shredded. The encrypted key set is also on that USB, verified 20/20 hash-identical. |
| The recovery path works | Rung 2 (re-flash an official factory image) tested deliberately, before it was ever needed. |
| AOSP builds on this host | adevtool's dependency build ran 7485 steps to `Build Succeeded`, and a full `akita` build completed (see §6). |

### What is NOT proven

- **The product thesis.** That an agent-designed interface beats apps on a phone is a human-factors question, not a technical one. Nothing above touches it.
- **Any Phosphor code at all.** The image presents stock GrapheneOS; vision step 2 ("modify the platform, framework, system services, system shell") has not begun.
- **The shell, the agent service, voice, capabilities, policy** — all of it is still design (Phases 4+).

---

## 3. Device state

Verified on-device 2026-09-25; this is the standing state unless something reflashed it.

| | |
|---|---|
| Device | Pixel 8a (`akita`), serial `3C121JEKB03922`, SKU `GKV4X` |
| Bootloader | **UNLOCKED** (`ro.boot.flash.locked=0`); `fastboot flashing get_unlock_ability` returns `1` |
| Verified boot | `orange` — not enforced (expected while unlocked) |
| Running build | `google/akita/akita:17/CP2A.260805.005/2026092500:user/release-keys` |
| Slot | `_a` (hardcoded `--set-active=a` in `flash-all.sh`) |
| Userdata | **Wiped** (twice). Sitting at the setup wizard, deliberately not set up. |
| Our AVB key | installed in the device's `avb_custom_key` partition |
| 2026-11-10 | Reconnected over USB during this session and correctly identified on the bus as `18d1:4ee1` (MTP), product "Pixel 8a", serial matching the record. Not attached at the moment of writing. |

**A locked device cannot run our image** — a self-signed image cannot satisfy the existing verified-boot chain, so flashing required unlocking, which wipes. The bootloader is deliberately **left unlocked** for the whole development period.

### adb vs MTP — the trap that costs an hour

A Pixel with USB debugging OFF enumerates as MTP only and `adb devices` is empty. That is a USB descriptor fact, not an authorization state — no amount of authorizing, re-plugging or udev fixing will make adb see it. Check the PID, not `adb devices`:

| PID | mode |
|---|---|
| `4ee1` | MTP — debugging OFF; adb cannot see the device at all |
| `4ee2` | MTP + adb |
| `4ee5` / `4ee6` | PTP / PTP + adb |
| `4ee7` | adb only |
| `4ee9` | MIDI + adb |
| `4ee0` | fastboot (bootloader mode) |

After enabling USB debugging, **replug the cable** — USB does not renegotiate its descriptor set without a reconnect, so an already-plugged phone keeps reporting the old PID. Authorization is per-host RSA key in `~/.android/adbkey` and never carries over from another machine.

---

## 4. The host: `qoder`

- Ubuntu **26.04.1 LTS**, Ryzen 9 9950X (32 threads), 59 GiB RAM, 1.8 TB ext4 root with ~1.4 TB free.
- **Distro decision (2026-09-24): proceed on 26.04 (Option E).** GrapheneOS officially supports Arch, Debian bookworm, Ubuntu 24.10 and 24.04; 26.04 is unsupported but nothing enforces it, and the full build succeeded. **Never propose downgrading the host distro** — there is no supported reverse path (an in-place reverse would leave a hybrid system). If a distro-specific build failure ever appears, the fallback order is (A) a `systemd-nspawn` container of Debian bookworm/Ubuntu 24.04, then (B) Docker/Podman (usually needs `--privileged` for AOSP's namespace build sandbox). Record the failure before switching.
- **`sudo` requires an interactive password** — an agent cannot install packages or run privileged commands. Pattern: write an idempotent script, hand the user `sudo bash <script>`, then verify the result independently.
- **No disk encryption** (plain ext4 root, `/swap.img` swap, zero LUKS). Consequences: secrets staged in tmpfs can be paged out to disk, and plaintext credentials on disk are a real exposure. **Run `sudo swapoff -a` before signing and `swapon -a` after** — swap defeats the guarantee that keys return to rest when signing ends.
- **No GitHub credential.** No token, no `~/.git-credentials`, no credential helper, no SSH key. `qsmtco/Phosphor` is public, so anonymous reads succeed and make the host *look* authenticated when it is not. The user primes git's in-memory cache as one typed line when a push is needed; never `credential.helper=store` on this host.

### Toolchain (all verified on this host)

- **`repo`**: the self-updating standalone at `~/.local/bin/repo` (host Python 3.14.4 runs it fine) — not the apt package.
- **`adb` / `fastboot`**: Google platform-tools at `~/android-sdk/platform-tools`, never apt (distro packages ship development snapshots and clobber the version scheme). fastboot must be ≥ 35.0.1.
- **`adevtool`** needs Node.js 24 LTS, kept side by side at `~/android-sdk/node24`. Invoke as `PATH="$HOME/android-sdk/node24/bin:$PATH" yarnpkg --cwd vendor/adevtool/ install` (`yarn` is `yarnpkg` on Debian/Ubuntu). That install migrates adevtool to the newest Yarn, dirtying `package.json`/`yarn.lock` and adding `.yarnrc.yml` + `.yarn/` — harmless, do not mistake it for corruption.
- **`ykman`** at `/usr/bin/ykman`; YubiKey 5 NFC, serial 38381297, fw 5.7.4, PIV slot 9d. Appears on USB as `1050:0407` when plugged in (not at the moment of writing).
- Add `/sbin:/usr/sbin:/usr/local/sbin` to PATH or "many system administration commands will fail".
- Not needed: ccache, clang, ninja — AOSP ships its own prebuilt toolchain.

### Artifacts on disk

| What | Path |
|---|---|
| Phosphor repo | `~/projects/Phosphor` (qsmtco/Phosphor) |
| GrapheneOS source tree (tag `2026091900`) | `~/projects/grapheneos-2026091900` |
| Signed release | `~/projects/grapheneos-2026091900/releases/2026092500/release-akita-2026092500/` |
| Extracted flash images | `~/phosphor-flash/akita-install-2026092500/` |
| Key set (encrypted) + wrap material | `~/phosphor-keys/akita`, `~/phosphor-keys/{passphrase.sealed,piv-wrap-pub.pem,yubikey.conf}` |
| Signing / verification tooling | `~/projects/Phosphor/scripts/*.sh` |
| Evidence | `~/projects/Phosphor/docs/evidence/phase3-key-generation-20260925.txt`, `pixel8a-baseline-20260924-1038.txt` |
| Escrow USB | label `PHOSPHOR-ESCROW` (offline; not attached) |

**Workspace rule:** everything project-related lives under `~/projects` (also `DEVELCAKES_PROJECTS_DIR`'s default). Host tools and trust material stay *outside* it (`~/android-sdk`, `~/.local/bin/repo`, `~/.ssh/grapheneos_allowed_signers`) so they do not appear as bogus projects in the develcakes list. **Move a repo tree before `repo sync`, never after** — an init-only tree has no baked absolute paths, but once synced every `.repo/projects/*/config` records an absolute `worktree` path and relocating it breaks the tree.

---

## 5. Signing keys, custody, and identities (public values only)

The key set is **permanent** — the AVB key cannot change without another wipe. It is **10 private keys** (GrapheneOS's own set from `script/common.sh`): `bluetooth gmscompat_lib media networkstack nfc platform releasekey sdk_sandbox shared` plus `avb.pem`. APK keys are RSA 4096; the passphrase is identical across all keys; `make_key`/`encrypt-keys` use scrypt + AES256.

Custody model: **one key set; the YubiKey gates access rather than performing the signing.** The mechanism that makes token-gating work with zero patching: `script/decrypt-keys` only prompts when the `password` variable is undefined, so a wrapper unwraps the passphrase via the token, exports it, and GrapheneOS's own flow runs untouched. `generate-release.sh` is file-based (`sign_target_files_apks -o -d "$KEY_DIR" --avb_vbmeta_key "$KEY_DIR/avb.pem"`), so supplying key files is the flow's native mode.

Why the token is not the signer: PIV has 4 usable primary slots for 10 keys, and RSA-4096 signatures on the token are slow and serial across the thousands of APKs a release signs. RSA key size is **not** a constraint (fw 5.7+ supports RSA-3072/4096 in PIV). If signing must ever be hardware-bound, a YubiHSM 2 (~$650) supports RSA 4096 and PKCS#11; `avbtool` has `--signing_helper` and `SignApk.java` references PKCS#11.

Public identities to check artifacts against:

| Value | sha256 |
|---|---|
| `avb_pkmd.bin` | `2256f03c5d5189debf9466e6dfb8a63d2f66e8abb96f10c074cc289ccb36b602` |
| Platform certificate | `4bcb40d3c470ee9346df9954276294904b0db167f317c940714872b5d6c74a96` |
| Flashed `vbmeta.img` digest (first 7488 bytes) | `bd17532d485543cabba4d54796461d3c972df9c8d7161930a68d0a0a1d9cf127` |
| Vanadium (browser/WebView) signature | `c6adb8b8…`, DN `CN=GrapheneOS` — **not ours**, see below |

**Vanadium carries GrapheneOS's signature, not ours — expected, and load-bearing.** `external/vanadium` ships prebuilt, already-signed Trichrome/WebView APKs; `generate-release.sh` re-signs AOSP/APEX components to our keys but leaves these alone. Do **not** "fix" it by re-signing them: they are GrapheneOS's component under GrapheneOS's trust anchor. Since the browser/WebView is Phosphor's intended *shell*, owning that signature requires building Chromium from source — an architectural decision for Phase 4, not a build tweak. Check APK signatures against `com.android.settings` or `com.android.shell`, never Vanadium.

**Where keys live:** at rest in `keys/<device>/` (keep it OUTSIDE the source tree — 1057 git repos is the last place a private key belongs; mode 0700); during signing in `mktemp -d /dev/shm/...` so plaintext exists in RAM only, removed by an EXIT trap. **Never back up the encrypted key files without the means to unwrap them** (the wrapped passphrase blob + a reproducible/escrowed PIV key) — that yields a backup that looks complete and is worthless.

---

## 6. What was done, phase by phase

### Phase 0 — Project definition and control documents — done
Vision, build plan (16 phases), architecture and trust specs.

### Phase 1 — Build-host and device readiness — done
Host audited and prepared; toolchain installed and verified. The device was found **already running official GrapheneOS** (Android 17, `CP2A.260805.005`, zero GMS/Vending), which retired the "install GrapheneOS first" steps. Baseline evidence: `docs/evidence/pixel8a-baseline-20260924-1038.txt`.

### Phase 2 — GrapheneOS source and build foundation — done
Source synced at tag `2026091900` with the **signed tag verified** (`Good "git" signature for contact@grapheneos.org`; `gpg.ssh.allowedSignersFile` set for the manifests repo). The device tree is **not** at `device/google/akita` — GrapheneOS keeps it in `vendor/adevtool/config/mk/google_devices/device/akita/`, so a missing `device/google/<codename>` is normal. `adevtool generate-all -d akita` produced `vendor/google_devices/akita` (~4.7k files, 1.3 GB, includes firmware); the lunch target afterwards is plain `akita`.

**Verified build recipe:**

```bash
cd ~/projects/grapheneos-2026091900
source build/envsetup.sh
lunch akita-cur-user            # NOT akita-user, NOT akita-ap2a-user
m -j24 vendorbootimage vendorkernelbootimage target-files-package
```

~1 h 06 m at `-j24`; 168,199 ninja steps; `out/` ends at ~107 GB. Outputs: 23 `.img` files in `out/target/product/akita/`, plus the signing input `out/target/product/akita/obj/PACKAGING/target_files_intermediates/akita-target_files.zip` (~3.6 GB, 8,841 files, 17 images inside). There is no `super.img` at this stage — only `super_empty.img`; assembled images come later. Expected fingerprint here ends `:user/test-keys` (unsigned test keys — correct before the release pipeline). Pixel 8a needs `vendorbootimage vendorkernelbootimage` before `target-files-package`; a bare `target-files-package` is not enough.

`lunch` needs `<product>-<release>-<variant>`; the release config is **`cur`** (GrapheneOS's own guide shows `lunch husky-cur-user`). Never pick it by listing `build/release/build_config/` — that directory holds only a stale AOSP `ap2a.scl` (SDK 34, UP1A, patch 2024-09-05) which `lunch` accepts but which defines no `RELEASE_KERNEL_AKITA_DIR`, producing `TARGET_KERNEL_DIR` empty and a misleading board-config abort on `vendor_kernel_boot.modules.load not found or empty`. Correct values live in `build/release/flag_values/<release>/RELEASE_KERNEL_<DEV>_DIR.textproto`. Do not set `OFFICIAL_BUILD=true` unless the Updater URL in `packages/apps/Updater/res/values/config.xml` is repointed at our own server.

### Phase 3 — Signing, flashing, recovery — done, verified
Key generation → signing wrapper (`scripts/keys-sign-release.sh`) → release pipeline → unlock → flash → cryptographic verification → deliberate recovery reflash. Every destructive step was approved explicitly, for that operation, at the time. Detail: `docs/PHASE-3-FLASHING-AND-RECOVERY.md` (§9 = status and open items) and `docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md`.

Key generation follows GrapheneOS's documented procedure: `mkdir -p keys/<device> && cd keys/<device>`, then `../../development/tools/make_key <name> "/CN=.../"` for each of the nine, then `openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem`, then `../../external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin`.

Release pipeline: Phase 2's `target_files.zip` is **not flashable**. `m otatools-package` → `script/finalize.sh` → `script/generate-release.sh akita <BUILD_NUMBER>` → output in `releases/<BUILD_NUMBER>/release-akita-<BUILD_NUMBER>/`. For fast iteration the raw images in `out/target/product/akita/` can be flashed directly with `fastboot flash <partition> <img>` — faster, but it skips the signing path, so it is not the production shape.

---

## 7. The build-plan map (what follows)

| Phase | Name | Primary result |
|---|---|---|
| 0–3 | Definition; host; source/build; signing/flashing/recovery | **DONE** |
| 4 | Phosphor platform architecture | Detailed system design and capability boundaries |
| 5 | Native Phosphor system foundation | Bootable platform components + trusted agent service foundation |
| 6 | Phosphor system shell and rendering surface | Primary agent-controlled phone interface |
| 7 | Voice, STT, conversational loop | Reliable speech-first interaction |
| 8 | Agent capability and policy framework | Native action orchestration with explicit safety policy |
| 9 | Communications integration | Calls, contacts, SMS/messages, notifications, escalation |
| 10 | Settings, applications, hardware integration | Unified control of device functions |
| 11 | Persistence, identity, data, recovery | Durable state, privacy, backup, recovery |
| 12 | Security hardening and adversarial testing | Secure, understandable, resilient platform |
| 13 | Performance, reliability, real-device validation | Daily-usable system on the Pixel |
| 14 | Update, release, long-term maintenance | Sustainable distribution and servicing |
| 15 | Pilot deployment and iterative expansion | Controlled real-world use and evolution |

Phases are ordered, but some later design work can proceed in parallel once dependencies are understood. The vision's own post-milestone order is the same shape: shell → agent service as a platform component → voice/text → contacts and calls → notification/message awareness → policy-approved replies → settings/connectivity → audio, sensors, camera, NFC → absorbing more system apps → hardening, update, rollback.

### Live specs that constrain the design

- **`docs/PHOS-SPEC-001-trust-architecture.md`** — trust architecture and interactive-UI security: generated-screen JS rules (R-UI), untrusted-content quarantine (R-QUAR), destructive-action gating (R-GATE), secret hygiene (R-SEC), bridge/hardware access (R-BRIDGE), latency (R-PERF), the command risk policy classes, and the approval flow. Its requirements are front-end-agnostic and carry over to the Android build.
- **`docs/PHOS-SPEC-002-system-integration.md`** — defines the four jobs of an OS and five **integration levels** (L1 kernel policy, L2 hardware arbitration, L3 system configuration, L4 Phosphor owns boot), plus the security/recovery requirements that separate an operating system from a demo, hardware prerequisites, and open questions for the Captain. Phase 4 must answer inside this frame.

---

## 8. Operational procedures

### Flash / reflash (production shape)

```bash
sudo systemctl stop fwupd.service        # every session; fwupd claims fastboot devices
# hold VOLUME DOWN while booting to enter the bootloader
unzip <release>.zip && cd <dir> && bash flash-all.sh
# if the flash fails on space, /tmp is tmpfs and too small:
mkdir tmp && TMPDIR="$PWD/tmp" ./flash-all.sh
```

`bsdtar` is the guide's extraction command but `libarchive-tools` is not installed on qoder; `unzip` is what actually runs, and the script is invoked as `bash flash-all.sh` so the executable bit is irrelevant.

**`flash-all.sh` WIPES USERDATA AND METADATA** — it is a data-loss recovery, not a repair. It also does `fastboot erase avb_custom_key` then flashes our `avb_pkmd.bin` (that is what lets the bootloader verify our images while unlocked), and hardcodes `--set-active=a` (which is why a flashed device always reports `ro.boot.slot_suffix=_a`). Plant a marker file in `/sdcard` before a reflash test if you need to distinguish "recovered" from "recovered and wiped".

**Rehearse the USB transitions before any flash** — a bad port aborts a flash mid-sequence, because `flash-all.sh` runs `fastboot reboot-bootloader` *between* flashing the bootloader to the other slot and flashing the OS:

```bash
adb reboot bootloader; fastboot reboot-bootloader; fastboot devices; fastboot reboot; adb devices
```

Observed on qoder: from one port `adb reboot bootloader` worked every time, but the device never came back after `fastboot reboot` (2/2 attempts, absent from `lsusb` entirely — so not an adb or authorization problem), and replugging into the *same* port did not fix it; a different port gave clean passes on all three transitions. Diagnose with `lsusb -d 18d1:` plus per-port emptiness under `/sys/bus/usb/devices`; change port first, then cable. The rehearsal touches no partition and is the cheap way to prove the path before committing.

### Recovery ladder

fastboot is the normal failure mode and it is recoverable — the unlocked bootloader is what makes a bad build survivable. The dependable floor (rung 2) is reflashing an official verified GrapheneOS factory image:

```bash
ssh-keygen -Y verify -f allowed_signers -I contact@grapheneos.org -n "factory images" -s <zip>.sig < <zip>
```

It needs none of our keys or artifacts. **Never relock the bootloader while troubleshooting:** `fastboot flashing lock` on a device with a non-booting or wrongly-signed build can make it unbootable.

### Verifying a flashed device (do not trust "it boots")

An unlocked bootloader does not enforce verification, so a device that boots says nothing about signing. The check that settles it: compare the bootloader's `ro.boot.vbmeta.digest` against `sha256()` of the first `ro.boot.vbmeta.size` bytes of the `vbmeta.img` that was flashed. Supporting signals: fingerprint ending `:user/release-keys` (an unsigned build says `:user/test-keys`), and a platform-signed app such as `com.android.settings` carrying our platform cert.

---

## 9. Traps and hard-won lessons

Each of these cost real time. Read before touching the build or the device.

**Platform / build**

- **nsjail vs Ubuntu's userns restriction.** `kernel.apparmor_restrict_unprivileged_userns=1` makes AOSP's build-sandbox probe fail, so soong prints `Build sandboxing disabled due to nsjail error.` on stderr and continues with the sandbox off — **the build itself still succeeds**. But **adevtool's `spawnAsync` treats any unexpected stderr line as fatal** and aborts `generate-all` on exactly that line. There is no knob to silence it (`USE_NINJA_SANDBOX` does not exist in the tree; `build/soong/ui/build/sandbox_linux.go` probes unconditionally). Fix: grant `userns` to the nsjail binaries via AppArmor (`scripts/host-fix-nsjail-userns.sh` writes `/etc/apparmor.d/nsjail-userns`), following the pattern Ubuntu ships for `mmdebstrap` — preferable to setting the sysctl to 0, which would drop the restriction host-wide. The profile attaches to an **absolute path inside the tree**, so re-run the script if the tree moves or is recreated.
- **Never hand-test the probe to judge that fix.** A bare `nsjail -H android-build -e -u nobody -g nogroup --disable_clone_newcgroup -- /bin/bash -c ...` fails with `execve('/bin/bash') failed: No such file or directory` *even when the fix works*, because it omits the bind mounts AOSP passes. Judge by re-running the real build, or with `journalctl -k | grep -i apparmor` — no `unprivileged_userns` transition and no `DENIED` line after the profile loads means it worked.
- **GrapheneOS apps are named by *module*, not package.** The browser stages as `product/app/TrichromeChrome/TrichromeChrome.apk` and *is* `app.vanadium.browser` (also `TrichromeWebView.apk` = `app.vanadium.webview`, `TrichromeLibrary.apk`, `VanadiumConfig.apk`). Searching the output for `app.vanadium.*` finds nothing and looks like a catastrophic miss. Confirm with `out/host/linux-x86/bin/aapt2 dump badging <apk>`.
- `GmsCompatLib.apk` in `system/app` is **GrapheneOS's own** GMS-compat library (added by their `build` fork), not Google GMS. The real de-Google check is `com.google.android.gms` / `com.android.vending` — both should count 0.
- Judge completeness against `out/target/product/akita/product_packages.txt`. `grep -c 'error:'` on the build log is useless — it matches the Rust crate `thiserror`. Grep `ninja: build stopped` or `FAILED:`.
- **`apksigner` needs a JDK on PATH**, and pick the linux-x86 one: the tree's `out/host/linux-x86/bin/apksigner` is a wrapper that execs `java`; without it you get a bare `exec: java: not found` (exit 127). Use `prebuilts/jdk/jdk25/linux-x86/bin/java` — **not** a bare `find` for `java`, which happily returns the `linux-arm64` build and fails with `Exec format error` (exit 126). There is no JVM in `/usr/lib/jvm` on qoder.

**Keys, tokens, and the token device**

- **`make_key` ALWAYS exits 1 — even on complete success.** Its trap is `trap 'rm -rf ${tmpdir}; echo; exit 1' EXIT INT QUIT`, and `exit 1` in an EXIT trap sets the status on every run. Call it with `|| true` and verify the artifacts (`[[ -s $key.pk8 && -s $key.x509.pem ]]`) instead of trusting the status. It reads its password from stdin (a blank line = unencrypted) and refuses to overwrite existing keys.
- **`encrypt-keys` must be driven by piping.** Unlike `decrypt-keys` it has no `${var+defined}` env shortcut: it `read -s`s old, new and confirm from stdin, so use `printf '\n%s\n%s\n' "$NEW" "$NEW" | script/encrypt-keys <keysdir>` (blank first line = nothing encrypted yet). It encrypts the `.pk8` files **and `avb.pem`** in one pass, which is why generating everything unencrypted and encrypting once is the clean order.
- **Two certificate-subject formats — use the right one per tool.** `ykman piv certificates generate -s` wants an **RFC 4514** string (`CN=Phosphor,O=Phosphor`), while `development/tools/make_key <name> <subject>` feeds `openssl req -subj` and wants OpenSSL's **`/CN=x/O=y`** form. Passing the OpenSSL form to ykman makes `cryptography` raise a `ValueError` with an **empty message**, surfaced as a bare unexplained ykman error — it fails *before* prompting, so no PIN attempt is consumed, which is the tell.
- **RSA-OAEP parameters must match on both sides.** Encrypt with `openssl pkeyutl -encrypt -pubin -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256` and decrypt with `pkcs11-tool --decrypt --mechanism RSA-PKCS-OAEP --hash-algorithm SHA256 --mgf MGF1-SHA256`. OpenSSL defaulting to SHA-1 on one side while the other expects SHA-256 is the classic silent failure.
- **Never paste a multi-line block around an interactive PIN prompt.** Pasted text still sitting in the tty buffer can be swallowed as the PIN and rejected (`CKR_PIN_INCORRECT`), and a rejected PIN decrements a counter that does not refill: **3 wrong PINs lock the PIV PIN** (unblock via `ykman piv access unblock-pin`; 3 wrong PUKs lock that too). Run PIN-gated commands as a single typed line, check `ykman piv info | grep 'PIN tries'` before any retry, and keep a test blob pre-sealed so the user types exactly one command. Make the test cheap: sealing needs only the public key and no PIN.
- **`pkcs11-tool`'s PIN prompt needs BOTH stdin and stdout to be a terminal.** OpenSC's `util_getpass` calls `tcgetattr(fileno(stdout))` then reads with `getchar()` from stdin, so a *redirected stdout* breaks it exactly as a captured stdin does — both give the opaque `error: util_getpass error`, with the prompt line never appearing. It fails *before* `C_Login`, so no PIN try is consumed. Fix: give the prompt a terminal on both fds (`</dev/tty >/dev/tty`). Never `$(...)`, never `| cmd`, never `> /dev/null`. `util_get_pin` accepts `env:VAR` but explicitly rejects `file:`, so there is no PIN-from-file option.
- **YubiKey CCID access trap (cost a real debugging cycle).** Installing the smartcard tooling while the token is already plugged in leaves the device node at `root:root`, because udev applies `/usr/lib/udev/rules.d/92-libccid.rules` (`GROUP="pcscd"`) only when a device *appears*. Symptom: `ccid_usb.c ... LIBUSB_ERROR_ACCESS`, `ykman piv info` → "Failed to connect to YubiKey", `opensc-tool --list-readers` → "No smart card readers found" — while the *seat user* keeps working over the HID path (`ykman info` succeeds), because `69-yubikey.rules` tags the device `uaccess`. Fix: `udevadm control --reload-rules && udevadm trigger --subsystem-match=usb --action=add`, then physically replug if the group is still wrong (`scripts/host-fix-yubikey-ccid.sh`). Never run `pcsc_scan` without a bound — `pcsc_scan -n` does not exit and will hang the command until timeout.
- **Verify a generated set by artifact, not by message.** Every `.pk8` must reject a wrong passphrase; `openssl asn1parse` should show `PBES2`; certs should be RSA-4096 and all distinct; `avb_pkmd.bin` is exactly `8 + 2*(bits/8)` bytes (1032 for RSA-4096) with `n0inv == 2^32 - modinv(N, 2^32)` and `rr == (2^bits)^2 mod N` — and note there is **no trailing hash** in that format. The definitive end-to-end check: unseal with the token, confirm it equals the escrow copy, decrypt a `.pk8` with it, and `openssl rsa -pubout` the result to confirm it matches that key's `.x509.pem`.
- **Do not test "is this PKCS#8 encrypted?" with a wrong passphrase.** `openssl pkcs8 -inform DER -in k.pk8 -passin pass:wrong` exits **non-zero for an unencrypted key too** (verified empirically), so it cannot distinguish them and silently passes plaintext keys. Test the DER structure: an `EncryptedPrivateKeyInfo` is `SEQUENCE { SEQUENCE(algid), OCTET STRING }` while a plaintext `PrivateKeyInfo` is `SEQUENCE { INTEGER version, … }`, so line 2 of `openssl asn1parse -inform DER -in k.pk8` contains `prim: INTEGER` only for the plaintext case. (`-nocrypt` is not the answer either — it is a `-topk8` output flag.)
- **YubiKey provisioning creates files outside the source tree:** `~/phosphor-keys/` (`yubikey.conf`, `piv-wrap-pub.pem`, `.seal-tested`). The `.seal-tested` marker is a deliberate interlock — `keys-generate.sh` refuses to generate the permanent key set until the seal/unseal round trip is proven, so a passphrase is never left unprotected between generation and sealing. `ykman piv info` reports `Using default PIN!/PUK!/Management key!`: the PIN gates unsealing and **must** be changed off `123456`; the management key only authorises key management and cannot decrypt, so leaving it default is defensible (worst case is DoS via overwriting the wrap key).

**Storage / device handling**

- **Never use `blkid -L <label>` to test whether a drive is attached.** Its cache survives unplugging: it reported `/dev/sda1` for `PHOSPHOR-ESCROW` while the USB was physically disconnected, which would have sent key material to a stale device path. Read live sysfs: `lsblk -rno NAME,LABEL | awk -v L="$LABEL" '$2==L {print "/dev/"$1; exit}'`, then confirm with `-b "$dev"`.
- **`lsblk` reports `RM` (removable) and `TRAN` (transport) on the DISK, not the partition.** Asking on `/dev/sda1` silently yields empty strings, so a `[[ $tran == usb ]]` guard fails with `TRAN=` and looks like the wrong drive when it is fine. Resolve the parent first: `disk=/dev/$(lsblk -no PKNAME "$dev" | head -1)`.
- **A newly `mkfs`'d ext4 USB is `root:root 755` at its root, so the normal user cannot write to it** — the write fails as a bare `mkdir: Permission denied` long after the interesting work is done. `mkfs.ext4` creates the root owned by root and an ext4 mount cannot be told otherwise (`uid=`/`gid=` are vfat/NTFS options only), so `sudo chown "$USER:$USER" <mountpoint>` once after formatting is the fix. Have the *format* script do it, not the backup script.
- **Formatting a USB the desktop auto-mounted:** `umount` fails with "target is busy" because the file manager holds the directory open (`udisksctl unmount` fails too — udisks cannot close another process's descriptor). Identify the holder with `fuser -vm /dev/sdX`, release it with `nautilus -q` run as the *real* user with `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus`. **Never `umount -l` a device about to be repartitioned** — the detached filesystem's cached pages can be written back over the newly-created one. Order the destructive steps so unmount happens *before* `wipefs`, so a busy mount fails safely instead of half-erasing.

---

## 10. Constraints, risks, and open items

### Constraints that shape every decision

- **`flash-all.sh` erases userdata and metadata.** Every reflash destroys data. Plan for state that lives off-device or is re-provisioned per flash.
- **Anti-rollback.** Our vbmeta rollback index is `1788220800` = `2026-09-01 UTC`, equal to the device patch level at build time. A newer GrapheneOS base means rebuild + re-sign; a stale device refuses an older image, and unlocking does not help. A recurring cost, not a one-off.
- **One escrow medium is a single point of failure** — key files and the passphrase escrow share one USB; losing it loses both. A second encrypted medium is the fix and is cheap. Worth doing before it matters.
- **The key set is permanent.** Changing the AVB key later requires another wipe.
- **`fwupd` runs by default and claims devices speaking the fastboot protocol**, blocking fastboot ("already in use (claimed)"). `sudo systemctl stop fwupd.service` before any flash (temporary; returns on reboot).
- **This host has no disk encryption**, hence the swap-off rule around signing and the ban on `credential.helper=store`.
- **Don't trust `host-install-nct6687d.sh` readings on this board.** Its ASRock-customised Nuvoton Super I/O is read by no driver (in-kernel `nct6683` refuses it; `nct6687d` attaches only with `force=1` and reports garbage). Board/VRM/chipset temps and fan RPM are simply unavailable on this host — only CPU (k10temp), NVMe, DIMM, iGPU and NIC report.

### Open items

1. **Relocking — revisit the "D4: never relock" decision.** `flash-all.sh` erases and then writes `avb_custom_key` with our `avb_pkmd.bin`, which is what lets the bootloader verify our images on an unlocked device. So verified boot under *our* key may be achievable by relocking, whereas the earlier posture rested partly on the assumption that it was not possible. Relocking still wipes and still risks a brick on a bad build — a deliberate design review, not a step to take casually.
2. **Vanadium's signature** — decide in Phase 4: ride GrapheneOS-signed Vanadium (fast, works, sits under their trust anchor) or build Chromium from source (owns the signature, large effort).
3. **Optional:** the Ed25519 factory-image signing key (`keys/akita/id_ed25519`) that `generate-release.sh` uses when present.
4. **Second escrow medium** (see constraints).
5. **Pre-flash USB rehearsal** remains a requirement for every flash, not a one-off.
6. **Phases 4–15 are the actual project.** Nothing of Phosphor itself has been built yet.

---

## 11. Repository map and housekeeping

```
~/projects/Phosphor/
  docs/PHOSPHOR-VISION.md                       the goal; source of truth
  docs/PHOSPHOR-BUILD-PLAN.md                   the 16-phase plan (§4 overview, §5 detail)
  docs/PROJECT-STATUS.md                        this file — current status and handoff
  docs/ANDROID.md                               Android/GrapheneOS track notes
  docs/PHASE-1-BUILD-HOST-READINESS.md          Phase 1 (host, toolchain, device baseline)
  docs/PHASE-2-SOURCE-AND-BUILD-FOUNDATION.md   Phase 2 (source tree, adevtool, build)
  docs/PHASE-3-FLASHING-AND-RECOVERY.md         Phase 3 (§9 = status and open items)
  docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md         key generation, custody, wrapper design
  docs/PHOS-SPEC-001-trust-architecture.md      trust + interactive-UI security requirements
  docs/PHOS-SPEC-002-system-integration.md      OS integration levels L0–L4, hard requirements
  docs/VERIFICATION.md                          PHOS-SPEC-001 verification — iOS PoC scope only
  docs/P1-AUDIT.md … P5-AUDIT.json              PoC-era audits (quarantine, gating, secret hygiene)
  docs/evidence/                                raw evidence for Phases 1 and 3
  scripts/*.sh                                  host setup, key custody, signing, nsjail fix
  (pre-existing bring-up code: Termux/Python runtime, browser shell, Rust bridge, iOS PoC)
```

Repo state at this snapshot: last commit `842da7a`; `.gitignore` locally modified and `.crabcakes/` present as untracked project-state (created by the develcakes app when it opened this repo as a workspace). Neither is part of the build.

**GitHub:** `qsmtco/Phosphor` is public. Pushing from qoder needs the user to prime git's in-memory credential cache first (exact one-line command in the `phosphor` skill); the host stores no credential by design. Never ask for a token in chat, scan project docs for secrets before committing, and verify a push independently (`git ls-remote` plus the API) rather than from the push output.

---

## 12. Working environment notes (for the develcakes team)

- The development/agent environment on qoder is **develcakes (CrabCakes:PDE)**, installed at `~/projects/develcakes`; `DEVELCAKES_PROJECTS_DIR` defaults to `~/projects`, which is why the repo and the source tree live there. It is the tool the team works *in*, not part of Phosphor.
- An agent definition's `llm_name` must name an existing provider card in `~/.config/develcakes/providers.yaml`. A name that does not resolve fails validation **and makes the definition un-editable from the UI** (the edit drawer refuses to open), so a bad provider name locks you out of the only in-app fix. Provider names currently configured: DecisionModel, DeepSeek 4.1 Flash, GLM 5.3, HY4, ImproveModel, Mercury-3 (Mercury-3 currently 404s upstream).
- Whole-tree scans are expensive here: the GrapheneOS source tree is ~136 GB with history, `out/` another ~107 GB. Scope searches to `~/projects/Phosphor` unless the build is the subject.

---

## 13. Glossary

- **akita** — Pixel 8a device codename.
- **AVB** — Android Verified Boot; `vbmeta` holds the hashes/signatures, `avb_pkmd.bin` is our public metadata flashed into `avb_custom_key`.
- **Rollback index** — monotonic counter in vbmeta; a device refuses images older than its stored value.
- **adevtool** — GrapheneOS's tool that prepares Pixel vendor files and device config from stock factory images.
- **Vanadium** — GrapheneOS's hardened Chromium (browser + WebView), shipped prebuilt and signed by them.
- **Rung 1 / rung 2** — recovery ladder: rung 1 = reflash our own image; rung 2 = flash an official GrapheneOS factory image (needs none of our keys). Both wipe.
- **Slot `_a`** — active A/B slot; `flash-all.sh` hardcodes it.
- **`:user/test-keys` vs `:user/release-keys`** — fingerprint suffix distinguishing an unsigned dev build from a release-signed one.
- **L0–L4** — PHOS-SPEC-002's integration levels: kernel policy → hardware arbitration → system configuration → Phosphor owns boot → conceptual endpoint.

---

## 14. Next action

**Phase 4 — Phosphor platform architecture.** Define the system shell, the native agent service and its process boundaries, the capability broker, the HTML/JS rendering surface and its native bridge, the voice/STT/inference/tool paths, and the privilege, identity, consent and audit boundaries — mapping each planned feature to Android framework APIs, system services, privileged apps, new services, or vendor interfaces, inside the L0–L4 frame of PHOS-SPEC-002 and the requirements of PHOS-SPEC-001.

Exit criterion: the major system boundaries and implementation locations are understood well enough to begin native platform work without guessing. The natural first *visible* increment after that is Phases 5–6 — a bootable image containing the Phosphor native foundation, then a build that boots to a Phosphor surface instead of the launcher.
