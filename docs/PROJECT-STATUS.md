# Phosphor — Project Status

**Snapshot:** 2026-09-25
**Governs:** `docs/PHOSPHOR-VISION.md` (the goal and source of truth). This file is
a snapshot of *where we are*, not a specification. When it disagrees with the
vision, the vision wins. Per Captain JAQ (2026-09-25): most of the pre-existing
repo is proof-of-concept and testing material; details of the target architecture
are to be solved as they come up.

---

## One line

Phase 3 is complete and cryptographically verified: we built a GrapheneOS-derived
image, signed it with our own keys, flashed it to the Pixel 8a, booted it, and
proved the recovery path. The image is still **unmodified GrapheneOS** — no
Phosphor code is in it yet.

## Where the device is

| | |
|---|---|
| Device | Pixel 8a (`akita`), serial `3C121JEKB03922`, SKU `GKV4X` |
| Bootloader | **UNLOCKED** (`ro.boot.flash.locked=0`) |
| Verified boot | `orange` — not enforced (expected while unlocked) |
| Running build | `google/akita/akita:17/CP2A.260805.005/2026092500:user/release-keys` |
| Slot | `_a` |
| Userdata | **Wiped** (twice). Sitting at the setup wizard. Not set up on purpose. |
| Our AVB key | installed in the device's `avb_custom_key` partition |

## What is proven

- **The build/sign/flash chain works end to end.** The decisive check is
  cryptographic, not observational: the bootloader's `ro.boot.vbmeta.digest`
  equals `sha256()` of the first `ro.boot.vbmeta.size` bytes (7488) of the
  `vbmeta.img` we flashed —
  `bd17532d485543cabba4d54796461d3c972df9c8d7161930a68d0a0a1d9cf127`.
  Booting proves nothing on its own; an unlocked bootloader boots unverified
  images. This comparison is what settles it.
- **We own the key chain.** 9 signing keys + the AVB key, generated once,
  scrypt/PBES2-encrypted, passphrase sealed behind a YubiKey PIV wrap key.
  Signed release independently verified: OTA cert byte-identical to
  `releasekey.x509.pem`, vbmeta verifies against the key rebuilt from
  `avb_pkmd.bin`, system APKs carry our platform cert.
- **Keys are backed up off-host.** Escrow on the `PHOSPHOR-ESCROW` USB (offline)
  plus a paper copy; host copy shredded. The encrypted key set is also on that
  USB, verified 20/20 hash-identical.
- **The recovery path works.** Rung 2 (re-flash) tested deliberately, before it
  was ever needed.

## What is NOT proven

- **The product thesis.** That an agent-designed interface beats apps on a phone
  is a human-factors question, not a technical one. Nothing above touches it.
- **Any Phosphor code at all.** The image presents stock GrapheneOS. Vision step 2
  ("modify the platform, framework, system services, system shell") has not begun.
- The vision's first milestone has two halves: *build and boot a GrapheneOS-derived
  image* (**done**) and *that presents Phosphor as the primary system shell*
  (**not started**).

## Next action

Vision step 2 — put the first Phosphor component into the image. The natural first
increment is the vision's own post-milestone item 1: **system boot and a Phosphor
shell**, since the milestone names the shell and everything later is visible
through it. That means a build that boots to a Phosphor surface instead of the
launcher.

## Constraints worth remembering

- **`flash-all.sh` erases userdata and metadata.** Every reflash destroys data.
  It is a data-loss recovery, not a repair. Verified by test — our earlier claim
  that it preserves data was wrong.
- **Anti-rollback.** Our vbmeta rollback index is `1788220800` = `2026-09-01 UTC`,
  equal to the device patch level at build time. A newer GrapheneOS base means
  rebuild + re-sign; a stale device will refuse an older image, and unlocking does
  not help. Recurring cost, not a one-off.
- **One escrow medium is a single point of failure.** Key files and the passphrase
  escrow share one USB. Losing it loses both. A second encrypted medium is the fix
  and is cheap — worth doing before it matters.
- **`fwupd` grabs fastboot devices.** Stop it every session before any fastboot
  work, or preflights abort.
- **Don't trust `host-install-nct6687d.sh` readings** on this board.
- **No GitHub credential on qoder.** Pushing needs the token primed into git's
  in-memory cache first (see the `phosphor` skill). Never `credential.helper=store`
  — the host has no disk encryption.

## Where the detail lives

| | |
|---|---|
| The goal | `docs/PHOSPHOR-VISION.md` |
| Phase 1 — host readiness | `docs/PHASE-1-BUILD-HOST-READINESS.md` |
| Phase 2 — source and build | `docs/PHASE-2-SOURCE-AND-BUILD-FOUNDATION.md` |
| Phase 3 — flashing and recovery (status in §9) | `docs/PHASE-3-FLASHING-AND-RECOVERY.md` |
| Phase 3 — key management and custody | `docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md` |
| Evidence for everything above | `docs/evidence/phase3-key-generation-20260925.txt` |
| Host and key tooling | `scripts/*.sh` |

## Key facts for recovery

    GrapheneOS source tree   ~/projects/grapheneos-2026091900   (tag 2026091900)
    Signed release           .../releases/2026092500/release-akita-2026092500/
    Extracted flash images   ~/phosphor-flash/akita-install-2026092500/
    Key set (encrypted)      ~/phosphor-keys/akita
    avb_pkmd.bin sha256      2256f03c5d5189debf9466e6dfb8a63d2f66e8abb96f10c074cc289ccb36b602
    Platform cert sha256     4bcb40d3c470ee9346df9954276294904b0db167f317c940714872b5d6c74a96
    Escrow USB               /dev/sda1, label PHOSPHOR-ESCROW
    YubiKey                  serial 38381297, fw 5.7.4, PIV slot 9d
