# Phase 3 — Flashing and Recovery Procedure

**Status:** EXECUTED 2026-09-25 — this is now the record of a procedure that has
been run, not a proposal. The device was unlocked (which wiped it) and our signed
build was flashed to it twice: once to install, once to exercise the recovery
path in §7 rung 2. It boots our build, verified cryptographically — see §6. The
bootloader is **UNLOCKED** and data **has** been wiped, twice.
**Project:** Phosphor
**Target device:** Google Pixel 8a (`akita`), serial `3C121JEKB03922`, SKU `GKV4X`
**Source revision:** GrapheneOS tag `2026091900`
**Related:** `docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md`, `docs/PHASE-2-SOURCE-AND-BUILD-FOUNDATION.md`,
`docs/PHASE-1-BUILD-HOST-READINESS.md`,
`docs/evidence/phase3-key-generation-20260925.txt`
**Created:** 2026-09-25 · **Revised:** 2026-09-25 (review corrections; P6/P7/P9
exercised; the USB re-enumeration fault diagnosed and fixed; the unlock and two
flashes executed; and one substantive error corrected — `flash-all.sh` *does*
wipe userdata, see §5)

---

## 1. Scope and the decision that gates everything

This document covers: pre-flight checks, producing our own signed factory
images, unlocking, flashing, verifying, and the recovery ladder for a device that
will not boot.

**The gate:** unlocking the bootloader **wipes all data on the device** — and so
does flashing it (`flash-all.sh` erases `userdata`; see §5). Per the project's
operating rules, each such operation requires explicit approval for that specific
operation, given at the time — not implied by approval of this document. That
approval was given on 2026-09-25, and the unlock and two flashes were carried out.

**Why it was open, and why it was closed.** The unlock was deferred while the only
build available was *unmodified GrapheneOS* — the sole difference being who signed
it — because unlocking would wipe a working, secure phone to install something
functionally identical. It became worth doing once the question changed from "is
this nicer?" to "does our signing pipeline actually produce a device that boots?"
It does, verified cryptographically (§6). The next flash is worth doing when it
carries Phosphor code rather than GrapheneOS code.

---

## 2. Pre-flight checks

| # | Check | Command / evidence | Status |
|---|---|---|---|
| P1 | `fwupd` stopped | `sudo systemctl stop fwupd.service` | **required every time** — see §2.1 |
| P2 | fastboot ≥ 35.0.1 | `fastboot --version` → **37.0.1** at `~/android-sdk/platform-tools` | pass — but see §2.4 |
| P3 | udev rules present | `/lib/udev/rules.d/51-android.rules` (38813 bytes) | pass |
| P4 | Flashing as non-root | covered by P3; no `sudo` for `fastboot` itself | pass |
| P5 | Device authorized | `adb devices -l` → `3C121JEKB03922 … product:akita model:Pixel_8a` | pass |
| P6 | Device reaches bootloader | `adb reboot bootloader` → appears as `3C121JEKB03922 fastboot` | **pass** — exercised 2026-09-25 |
| P7 | OEM unlocking permitted | `fastboot flashing get_unlock_ability` → `1` | **pass** — verified 2026-09-25, see §2.3 |
| P8 | `TMPDIR` has room | see §2.2 | to check at flash time |
| P9 | USB survives a mode transition | rehearse both transitions (§2.5) | **pass** on the current port — re-run before every flash |

### 2.1 Why `fwupd` must be stopped

GrapheneOS's install guide is explicit:

> "The fwupd software often used on Linux distributions for updating firmware is
> known to incorrectly connect to arbitrary devices using the fastboot protocol
> which will block using them for the intended purpose. This can result in
> receiving an error about the USB device already being in use (claimed)."

`sudo systemctl stop fwupd.service` — note this does **not** disable the service;
it returns on reboot, so it must be done in every flashing session.

### 2.2 The `/tmp`-as-tmpfs trap

> "A common issue on Linux distributions is that they mount the default temporary
> file directory `/tmp` as tmpfs... This is often not enough for the flashing
> process, especially since `/tmp` is shared between applications and users."

Confirmed on this host: `/tmp` **is** tmpfs, 29.7 GiB, and `/dev/shm` is a
separate 29.7 GiB tmpfs. Both are RAM-backed, so extraction into `/tmp` consumes
memory rather than disk, and `/tmp` is shared with everything else on the machine.

Workaround if the flash fails on space:

```bash
mkdir tmp && TMPDIR="$PWD/tmp" bash flash-all.sh
```

### 2.3 P7 — OEM unlocking, and how it was verified

OEM unlocking is a Developer-options toggle, and on this GrapheneOS build
`sys.oem_unlock_allowed` / `ro.oem_unlock_supported` are not exposed through
`getprop`. The bootloader answers it directly:

```bash
fastboot flashing get_unlock_ability      # 1 = unlocking allowed, 0 = not
```

Confirmed present in fastboot 37.0.1 ("Check whether unlocking is allowed (1) or
not(0)"). This is a **device operation** and therefore approval-gated like
everything else in §4 — but it gives a definite answer rather than requiring a
visual check of a toggle.

**Result, 2026-09-25: `1` — unlocking is permitted.**

It returned **`0`** on the first attempt. Worth recording, because the cause was
mundane and the failure mode is easy to misdiagnose: the **Settings → System →
Developer options → OEM unlocking** toggle was off. Enabling it on the device
flipped the value to `1` on the next bootloader session, with no other change. So
the earlier `0` was a configuration state, not a carrier lock or a hardware
restriction.

The same bootloader session confirmed the rest of the posture: `unlocked: no`
(still locked), `current-slot: a`, `product: akita`.

The SKU is `GKV4X`, the international factory-unlocked variant with no carrier
lock, so the carrier-check caveat in GrapheneOS's guide does not apply to us.

### 2.4 `adb` and `fastboot` resolve only in interactive shells

Both live at `~/android-sdk/platform-tools/` (adb 1.0.41, fastboot 37.0.1), and
the PATH export is in `~/.bashrc` — which non-interactive shells skip. So they
resolve in a terminal session and **not** in a script, cron job or `ssh host
'command'` context. That is fine for a human running `flash-all.sh`, and
`flash-all.sh` itself checks for `fastboot` and reports clearly when it is
missing — but do not assume a scripted context will find them.

### 2.5 USB re-enumeration on mode transitions — diagnosed, fixed by changing port

This cost real time on 2026-09-25. It is recorded in detail because, unfixed, it
would have aborted a flash mid-sequence.

**Symptom.** `adb reboot bootloader` worked reliably, but after `fastboot reboot`
(returning to Android) the device did **not** come back. It disappeared from
`lsusb` entirely — not merely from `adb`, so not an authorization problem — and
was still absent 120 seconds later. It happened on two attempts out of two, and
only a physical replug restored it. `fwupd` was confirmed inactive, the udev
rules were present, and the device had enumerated as `18d1:4ee7` immediately
beforehand, so this was never a driver or permissions fault.

**Diagnosis.** The device was on **Bus 005**, a 2-port USB 2.0 root hub that —
once the phone dropped off — was completely empty. The host saw no device on that
port at all, which is a physical-layer symptom. It also did not survive a replug
into the same port.

**Resolution.** Moving the phone to a different port fixed it completely. The
transitions were then rehearsed deliberately, and all three passed:

| Transition | Result |
|---|---|
| `adb reboot bootloader` (adb → fastboot) | OK, 14 s |
| `fastboot reboot-bootloader` (fastboot → fastboot — the mid-flash one) | OK, 6 s |
| `fastboot reboot` (fastboot → Android — the one that had failed) | OK, 44 s |

The device now enumerates on `Bus 001` as `usb:1-6.2`, i.e. behind an internal
hub, and works. So the fault was the **port** — not hubs in general, not the
cable, and nothing in software.

**Standing requirement: rehearse the transitions before every flash.** It costs
under a minute and touches no partition:

```bash
adb reboot bootloader
fastboot reboot-bootloader      # fastboot -> fastboot
fastboot devices                # must re-appear within seconds
fastboot reboot                 # fastboot -> Android
adb devices                     # must re-appear
```

If any transition needs a manual replug, **stop and fix the physical layer** —
change port first, then cable — before flashing. Note that the transitions are not
equivalent, which is why all of them are rehearsed: re-entering the bootloader is
a different code path from returning to Android.

**Why it matters.** `flash-all.sh` reboots the device *in the middle* of its
sequence:

```
fastboot flash --slot=other bootloader bootloader-…img
fastboot --set-active=other
fastboot reboot-bootloader          <- the device must come back, unattended
sleep 5
fastboot flash --slot=other bootloader bootloader-…img
… then the OS partitions
```

If the device does not re-appear there, the next `fastboot flash` fails, `set -e`
aborts the script, and the device is left with the bootloader flashed to one slot
and the active slot already switched to the other. Recoverable via §7 rung 2, but
it is the worst place to stop — and a five-second `sleep` will not survive needing
a replug.

---

## 3. Producing our own signed factory images

Phase 2 produced a **target-files package**, not a flashable factory image. The
GrapheneOS release pipeline converts one into the other, and Phase 3 wrapped that
pipeline in a script that handles key custody:

```bash
bash ~/projects/Phosphor/scripts/keys-sign-release.sh [BUILD_NUMBER]
```

**That wrapper is the supported path.** It is what produced and signed the
release recorded in `docs/evidence/phase3-key-generation-20260925.txt`. It:

1. symlinks `<tree>/keys/akita` to the real key set (§3.1),
2. turns swap **off**,
3. unseals the passphrase with the YubiKey (one PIN prompt),
4. exports `$password` and runs the pipeline below,
5. wipes the temp passphrase and restores swap on **every** exit path.

Underneath, unchanged, it runs:

```bash
cd ~/projects/grapheneos-2026091900
source build/envsetup.sh
lunch akita-cur-user

m otatools-package          # packages the tools that build update/factory zips
script/finalize.sh          # copies build artifacts into the releases directory
script/generate-release.sh akita <BUILD_NUMBER>
```

Output lands in `releases/<BUILD_NUMBER>/release-akita-<BUILD_NUMBER>/` and
contains the factory images and a full update package. The update zip performs a
full OS installation and can update from any previous version.

`script/generate-release.sh` is where the key custody design from
`PHASE-3-KEY-MANAGEMENT-DESIGN.md` §6 plugs in: it copies `keys/<device>/` into
`/dev/shm`, calls `script/decrypt-keys` (which reads `$password` from the
environment when the wrapper has set it, instead of prompting), signs, and
removes the plaintext on exit via an `EXIT` trap.

### 3.1 Three traps in the pipeline

**The key set must appear at `keys/<device>` relative to the tree root.**
`generate-release.sh` sets `PERSISTENT_KEY_DIR=keys/$DEVICE` — a relative path.
Our key set deliberately lives outside the tree (1057 git repositories is no
place for a private key), so the wrapper creates `<tree>/keys/akita` as a
**symlink** to `~/phosphor-keys/akita`. A manual run without that symlink fails.

**The release number must match the target_files.** `lunch` sets *and exports*
`BUILD_NUMBER` from `out/soong/build_number.txt`. If the number used for the
release differs from the one baked into the target_files being signed, the images
carry one version internally and another in their filename. The wrapper derives
it from `ro.build.version.incremental` inside the target_files
(`SYSTEM/build.prop`) rather than assuming today's date.

**Swap must be off before anything is decrypted.** `/dev/shm` is tmpfs and tmpfs
pages can be written to swap; this host's `/swap.img` sits on plain ext4 with no
LUKS layer. The wrapper does this in the correct order, so no plaintext key
material reaches disk. Related: do **not** set `OFFICIAL_BUILD=true` — it points
the Updater app at GrapheneOS's real update server, which would be a DoS on their
infrastructure from a differently-signed build.

**Alternative for development iterations:** the individual images in
`out/target/product/akita/` can be flashed directly with
`fastboot flash <partition> <image>`, which skips the release packaging step.
Faster, but it is not the production shape and does not exercise the signing path
— a development convenience, not the path to validate.

---

## 4. Unlocking the bootloader

Only with explicit, per-operation approval.

```bash
sudo systemctl stop fwupd.service      # P1
adb reboot bootloader                  # or hold volume down during boot
fastboot devices                       # confirm the device is visible
fastboot flashing get_unlock_ability   # P7 — returns 1 (verified, §2.3)
fastboot flashing unlock
```

The `unlock` command **must be confirmed on the device**: use the volume buttons
to move the selection to accept, then the power button to confirm. This wipes all
data.

**After unlocking**, the device will show a warning on every boot and verified
boot is no longer enforced — the consequence recorded as D4 in the key design.
Expect the first boot after unlock to be a factory-reset setup flow.

Note that P7's `1` is a *permission*, not an action: it means the unlock would be
accepted, and nothing has been unlocked.

---

## 5. Flashing

From the extracted factory image directory:

```bash
unzip akita-install-<VERSION>.zip
cd akita-install-<VERSION>
bash flash-all.sh
```

(`bsdtar` works too, but `libarchive-tools` is **not** installed on this host, so
`unzip` is the command that actually runs here. The script is invoked as
`bash flash-all.sh`, so the executable bit does not matter either way.)

`flash-all.sh` handles the whole sequence. Read from our own install zip, it:

- requires `fastboot` on PATH and version ≥ 35.0.1,
- verifies `fastboot getvar product` is `akita` and `slot-count` is `2`,
- flashes the bootloader to the **other** slot, `--set-active=other`,
  `fastboot reboot-bootloader`, then flashes the bootloader again,
- verifies `max-download-size` is `0xf900000`,
- **forces `--set-active=a`** — the super partition layout depends on the current
  slot, which the script hardcodes to slot A, so a flash always ends on slot A
  regardless of which slot the device was on,
- flashes the radio, then `fastboot erase avb_custom_key` followed by
  `fastboot flash avb_custom_key avb_pkmd.bin` — i.e. it **installs our AVB public
  key into the device's custom-key partition**, which is what lets the bootloader
  verify our images on an unlocked device,
- `fastboot oem uart disable`, then erases `fips`, `dpm_a`, `dpm_b`,
- checks the `android-info.txt` requirements (`--disable-super-optimization
  --skip-reboot update android-info.zip`) and cancels any pending snapshot update,
- flashes `boot`, `init_boot`, `dtbo`, `vendor_kernel_boot`, `pvmfw`,
  `vendor_boot`, `vbmeta`,
- **`fastboot erase userdata` and `fastboot erase metadata`** — see below,
- writes `super_1`…`super_15` to the `super` partition.

**IT WIPES USERDATA.** An earlier revision of this document claimed the opposite —
that the wipe came only from the unlock, so a reflash over an existing install
would preserve data. That was **wrong**, and it was tested on 2026-09-25: a marker
file written to `/sdcard` before a second `flash-all.sh` run was gone afterwards,
and the device came up at the setup wizard. `flash-all.sh` erases `userdata` and
`metadata` explicitly (lines 108-109 of the installed script).

The operational consequence: **every recovery reflash destroys user data.** Rung 2
in §7 is a data-loss recovery, not a gentle repair. Back up before flashing, and
treat "I can always just reflash" as false.

**Do not interact with the device until it finishes.**

**Rehearse the USB transitions first** (§2.5, P9). They passed on 2026-09-25 on
the current port, but the mid-sequence `fastboot reboot-bootloader` is
unattended, and this host has a demonstrated port that drops the device on a mode
switch. The rehearsal costs under a minute and touches no partition.

### 5.1 Anti-rollback: why an older build cannot be flashed

The bootloader enforces a rollback index, and our images derive theirs from the
security patch date. Ours is `1788220800`, which is exactly
`2026-09-01 00:00:00 UTC` — the build's security patch level. A build carrying a
**lower** index is refused by the bootloader, and an unlocked bootloader does not
help.

Today this is not an obstacle: the phone's own security patch is also
`2026-09-01`, so our build is neither older nor newer than what is installed. But
as soon as the device runs anything with a later patch — a future GrapheneOS
update, or a later Phosphor build — flashing an *older* Phosphor build will be
refused. The fix is not to unlock anything; it is to rebuild at an equal or newer
patch level.

This matters for the recovery ladder in §7: "reflash the known-good build" only
works if that build is not older than what is already on the device.

For our own builds the zip is the one produced in §3. For an official
GrapheneOS image the download must be verified first:

```bash
curl -O https://releases.grapheneos.org/allowed_signers
curl -O https://releases.grapheneos.org/akita-install-<VERSION>.zip
curl -O https://releases.grapheneos.org/akita-install-<VERSION>.zip.sig
ssh-keygen -Y verify -f allowed_signers -I contact@grapheneos.org \
  -n "factory images" -s akita-install-<VERSION>.zip.sig < akita-install-<VERSION>.zip
```

Expected output on success:

```
Good "factory images" signature for contact@grapheneos.org with ED25519 key SHA256:AhgHif0mei+9aNyKLfMZBh2yptHdw/aN7Tlh/j2eFwM
```

That is the same key already verified during Phase 2's `repo init`, so the trust
anchor is unchanged.

---

## 6. Verifying the flash

**Every check below has now been run** (2026-09-25) against a real flash, and §6.1
records what the device actually reported. The table stays as the regression
checklist for any future flash.

| Check | How |
|---|---|
| Device boots to a usable OS | observe |
| Build identity is ours | `adb shell getprop ro.build.fingerprint` — expect exactly `google/akita/akita:17/CP2A.260805.005/2026092500:user/release-keys` |
| **Signing took effect** | the same fingerprint must end `:user/release-keys`, **not** `:user/test-keys`. The Phase 2 build said `test-keys`; the signed build says `release-keys`. This is the single best post-flash signal that the images are ours |
| Verified boot state | expect **orange** (unlocked) — it was yellow before the unlock |
| Bootloader state | `adb shell getprop ro.boot.flash.locked` → expect `0` |
| APK signatures are ours | **Check a platform-signed app, not Vanadium.** `com.android.settings` or `com.android.shell` → signer SHA-256 `4bcb40d3c470ee9346df9954276294904b0db167f317c940714872b5d6c74a96`. Vanadium is GrapheneOS's, by design — see the note below. |
| Vanadium present | `app.vanadium.browser` / `app.vanadium.webview` — confirms a coherent GrapheneOS-derived build |
| No GMS | zero `com.google.android.gms` / `com.android.vending` packages |
| **The image really is ours** | `ro.boot.vbmeta.digest` must equal `sha256()` of the first `ro.boot.vbmeta.size` bytes of our `vbmeta.img`. An unlocked bootloader does not enforce verification, so a device that boots proves nothing about signing — this comparison does. |

The fingerprint and signature checks are the ones that actually distinguish our
build from official GrapheneOS. The "no GMS / Vanadium present" checks are the
same ones used in Phase 2 and are cheap regression tests that the build is what
we think it is.

**Asterisk on the APK check — Vanadium is not ours.** GrapheneOS ships Vanadium
as *prebuilt, already-signed* APKs (`platform_external_vanadium`, pinned to their
tag), carrying GrapheneOS's own release key. `generate-release.sh` re-signs AOSP
and APEX components to our keys, but not those. Verified on-device:
`app.vanadium.browser` and `app.vanadium.webview` report certificate DN
`CN=GrapheneOS` and digest `c6adb8b83c6d4c17d292afde56fd488a51d316ff8f2c11c5410223bff8a7dbb3`,
**not** our platform certificate. Expected, not a signing failure — but it means
the browser and WebView, which the Phosphor architecture treats as the shell, sit
under GrapheneOS's trust anchor rather than ours. Changing that means building
Chromium from source and signing it ourselves.

### 6.1 Results — measured on the device, 2026-09-25

```
ro.build.fingerprint            google/akita/akita:17/CP2A.260805.005/2026092500:user/release-keys
ro.boot.flash.locked            0
ro.boot.verifiedbootstate       orange
ro.boot.slot_suffix             _a
ro.boot.vbmeta.size             7488
ro.boot.vbmeta.digest           bd17532d485543cabba4d54796461d3c972df9c8d7161930a68d0a0a1d9cf127
sha256(vbmeta.img[0:7488])      bd17532d485543cabba4d54796461d3c972df9c8d7161930a68d0a0a1d9cf127   <- identical
```

The digest comparison is what settles it: the bootloader hashed those 7488 bytes
and reported the result, and it matches the bytes of the `vbmeta.img` we flashed,
so the device is running the vbmeta we built and signed. That same `vbmeta.img`
records `Public key (sha1): 831d31b6f9cba40341b90b1ed50fb8b2143a60f0` (ours).

On the APK side, `com.android.settings` and `com.android.shell` both report signer
SHA-256 `4bcb40d3c470ee9346df9954276294904b0db167f317c940714872b5d6c74a96` — our
platform certificate — while Vanadium reports GrapheneOS's, as described above.

**Baseline before flashing** (measured 2026-09-25, before the unlock — kept as the
record of the pre-flash state):

```
ro.boot.flash.locked            1            (locked)
ro.boot.verifiedbootstate       yellow
ro.build.version.incremental    2026091901
ro.build.version.security_patch 2026-09-01
ro.build.fingerprint            google/akita/akita:17/CP2A.260805.005/2026091901:user/release-keys
```

Two notes on this baseline. P7's developer-options change does not appear in it:
it alters the unlock *permission*, not the running system's properties. And the
§2.5 rehearsal was re-measured afterwards and reproduced this baseline exactly,
which is the evidence that the rehearsal itself is non-destructive.

---

## 7. Recovery — the unbrick ladder

Ordered from cheapest to most drastic. **Stop at the first rung that works.**

**Rung 1 — the device boots but the OS misbehaves.**
Reboot; if it persists, boot to the bootloader (volume down) and reflash just the
suspect partition from the known-good image set.

**Rung 2 — the device will not boot, but fastboot is reachable.**
This is the normal failure mode and it is recoverable. Boot to the bootloader
interface and re-run `flash-all.sh` from a known-good factory image directory.
Because the bootloader is unlocked, a build that fails verification still flashes
and still boots. **Subject to §5.1** — the known-good image must not carry a
lower rollback index than what is already installed.

**This rung destroys user data.** `flash-all.sh` erases `userdata` and `metadata`
(§5), so it is a data-loss recovery rather than a repair: it brings the device
back, and everything on it is gone. Verified by test on 2026-09-25 — which is how
the earlier "reflashing preserves data" claim was disproved. Back up before you
need it, not after.

**Rung 3 — flash-all fails or the device is in a boot loop.**
Capture the **full text output** — GrapheneOS's guide stresses this is the
essential diagnostic. Check the `/tmp`-as-tmpfs space trap (§2.2) and whether the
device is still enumerating at all (§2.5) first, since those are the two known
host-specific causes here, then re-run with an explicit `TMPDIR`.

**Rung 4 — return to official GrapheneOS.**
Download the official `akita` factory image, verify it against `allowed_signers`
(§5), and flash it. This restores a known-good, Google/GrapheneOS-signed OS. It
does not require our keys and does not depend on anything we have built, which is
what makes it the dependable floor.

This rung is also the **safe way to relock**, should D4's escape hatch ever be
taken: official GrapheneOS is signed with a key the device will accept, so
flashing it and then `fastboot flashing lock` produces a locked device that
boots. (Any *later* unlock wipes the device again, which is why D4 is cheap to
keep and expensive to reverse.)

**Rung 5 — recovery mode.**
The Pixel's recovery mode remains available. From the bootloader, select
recovery; it supports factory reset and ADB sideload of a full OTA package. A
sideload of the full update zip is a viable path when `flash-all.sh` is not.

**Rung 6 — the hardware/firmware floor.**
If the device does not respond to fastboot at all, the remaining options are
Google's official Android Flash Tool (browser-based) and, failing that, warranty
service. Nothing we have done is expected to reach this rung, and it is listed
for completeness rather than as an anticipated path.

**Non-recovery, stated so it is not mistaken for one:** relocking the bootloader
is *not* a recovery step. On a device with a non-booting or wrongly-signed build,
`fastboot flashing lock` can produce a device that will not boot at all; recovery
then means unlocking again, which wipes. Do not relock while troubleshooting.

---

## 8. Risks specific to this device and host

| Risk | Mitigation |
|---|---|
| Unlock wipes the phone — the current GrapheneOS install and its data are gone | Approval-gated; back up anything needed first. The device is a development unit. |
| **USB drops off the bus on a mode transition, mid-flash** (§2.5) | Diagnosed 2026-09-25 as a port fault and fixed by moving the device to another port. Rehearse both transitions before every flash; if either needs a replug, change port first, then cable. Recoverable via rung 2, but it stops the flash mid-sequence. |
| **Anti-rollback refuses an older build** (§5.1) | Build at an equal or newer security patch level than the installed one. Check `ro.build.version.security_patch` on the device before choosing what to flash. |
| `fwupd` claims the fastboot device | Stop it every session (§2.1) |
| `/tmp` tmpfs too small for the flash | Explicit `TMPDIR` (§2.2) |
| Plaintext keys paged to unencrypted swap during signing | `sudo swapoff -a` before signing — automated in the wrapper (§3) |
| A bad build makes the phone unbootable | Rungs 2–4; the unlocked bootloader is what makes this recoverable, so it works in our favour here |
| Relocking during troubleshooting produces a device that will not boot | Never relock while troubleshooting (§7); relock only via rung 4 |
| Flashing our images while `ro.boot.flash.locked=1` | Impossible — the flash is refused. The unlock must happen first. |
| `adb`/`fastboot` missing in a scripted context | They resolve only in interactive shells (§2.4) |
| Signing key set lost | Escrow exists on USB (verified, sha256 `ec76466f…`) and on paper; token PIN tries 3/3 |

---

## 9. Status and open items

**Executed 2026-09-25.** The device was unlocked (which wiped it), our signed
build was flashed, verified, and then reflashed to exercise rung 2 of the recovery
ladder. Everything below marked done was done on that date.

1. ~~Approval for this procedure~~ — **given and exercised.** The unlock and both
   flashes were approved explicitly, for those operations, at the time.
2. ~~Key generation~~ — **done.** The key set is generated, encrypted, verified
   and escrowed — and now also backed up off-host, as the encrypted key set on the
   escrow USB, verified against the host copy.
3. ~~The signing wrapper~~ — **written and proven**: `scripts/keys-sign-release.sh`.
   It signed the release whose signatures were independently verified (OTA otacert
   byte-identical to `releasekey.x509.pem`, vbmeta verifying against the public key
   rebuilt from `avb_pkmd.bin`, APKs carrying our platform certificate).
4. ~~P7 (OEM unlocking permitted)~~ — **verified: returns `1`** (§2.3).
5. ~~The USB re-enumeration problem~~ — **diagnosed and fixed** (§2.5). Rehearsing
   the transitions remains a pre-flash requirement, not a one-off.
6. ~~The unlock~~ — **done.** The bootloader is unlocked and the device is wiped.
7. ~~The flash~~ — **done, twice**, and verified cryptographically (§6): the
   bootloader's `ro.boot.vbmeta.digest` matches `sha256()` of the first
   `ro.boot.vbmeta.size` bytes of our `vbmeta.img`.
8. ~~The recovery path~~ — **rung 2 tested and working**; it destroys userdata (§7).
9. **Relocking — D4 should be revisited.** `flash-all.sh` erases and then writes
   `avb_custom_key` with our `avb_pkmd.bin` (lines 92–93), which is what lets the
   bootloader verify our images on an unlocked device. That means verified boot
   under OUR key may be achievable by relocking, whereas the D4 "never relock"
   posture rested partly on the assumption that it was not possible. Relocking
   still wipes, and still risks a brick on a bad build, so this is a deliberate
   design review, not a step to take casually.
10. **Vanadium is signed by GrapheneOS, not by us** (§6). Expected, but it means
    the browser and WebView — the shell in the Phosphor architecture — sit under
    GrapheneOS's trust anchor. Claiming that signature means building Chromium from
    source, which belongs in the platform architecture (Phase 4).
11. **Remaining key-custody work**, design doc §7: the encrypted backup of the key
    material is now done. Still optional: the Ed25519 factory-image signing key
    (`keys/akita/id_ed25519`) that `generate-release.sh` uses when present.