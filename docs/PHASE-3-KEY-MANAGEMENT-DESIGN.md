# Phase 3 — Key Management Design (signing, custody, bootloader posture)

**Status:** **APPROVED** (Captain JAQ, 2026-09-25). Key generation is now
unblocked per `docs/PHOSPHOR-BUILD-PLAN.md`. No keys have been generated yet —
that is the next action, and it is the first irreversible step in Phase 3. This
document records the decisions taken, the verified mechanics they depend on, and
the open items.
**Project:** Phosphor
**Target device:** Google Pixel 8a (`akita`), serial `3C121JEKB03922`
**Source revision:** GrapheneOS tag `2026091900`
**Related:** `docs/PHOSPHOR-BUILD-PLAN.md` §5 Phase 3, `docs/PHASE-2-SOURCE-AND-BUILD-FOUNDATION.md`,
`docs/PHOS-SPEC-001-trust-architecture.md`
**Created:** 2026-09-25

---

## 1. Purpose

Phase 3 establishes a safe, repeatable way to sign development images, flash
them, recover from failures, and return to a known-good state.

Its first deliverable is this design, because the plan gates key generation on
it. The reason for that ordering is not ceremony: **some of these keys cannot be
changed later without wiping the device**, so they are chosen once, deliberately.

This document covers the key hierarchy, custody, the signing flow, and the
bootloader posture. It does **not** yet cover the flashing workflow or the
unbrick procedure — those are the remaining Phase 3 deliverables and are listed
as open items in §10.

---

## 2. Decisions recorded

| # | Decision | Rationale |
|---|---|---|
| D1 | **One permanent key set** for this device — no separate dev/release sets | The AVB key is what the bootloader trusts; changing it means unlocking and wiping again. Committing once avoids a second wipe. |
| D2 | **The YubiKey gates access to encrypted keys** (not hardware signing) | Gets the physical-token property with zero changes to GrapheneOS's signing flow. See §5. |
| D3 | **Backup and loss mechanics deferred** — risk documented now, mechanics decided when keys are generated | Keeps the decision where it belongs, next to the actual key generation. See §7. |
| D4 | **The bootloader stays unlocked during development and is relocked when the build and key chain are ready** | Efficiency for the development loop, with the end state the vision specifies. Consequences and the relock path recorded in §8. Revised 2026-09-25 against `PHOSPHOR-VISION.md`, which is the source of truth. |

D4 is the decision with the widest blast radius, and §8 states plainly what it
costs. It is not a security-neutral choice.

---

## 3. The key hierarchy

Taken from GrapheneOS's own tooling (`script/common.sh`, `script/generate-keys`),
not invented:

```
signing_keys = bluetooth  gmscompat_lib  media  networkstack  nfc
               platform   releasekey     sdk_sandbox  shared
plus avb.pem  (AVB / verified boot)
```

**Ten private keys.** Each APK-signing key is an RSA-4096 keypair —
`development/tools/make_key` runs `openssl genrsa -f4 4096` — producing
`<name>.pk8` (PKCS#8 DER private) and `<name>.x509.pem` (public certificate).
`avb.pem` is a separate RSA-4096 key, and `avb_pkmd.bin` is its public key
metadata — the value embedded in `vbmeta` that the bootloader verifies against.

Roles, briefly:

| Key | Signs |
|---|---|
| `releasekey` | most APKs, and the default for anything unspecified |
| `platform` | the platform — signature-level permissions depend on it |
| `shared`, `media` | shared-UID and media APKs |
| `networkstack`, `bluetooth`, `nfc`, `sdk_sandbox`, `gmscompat_lib` | the APK/APEX modules of those subsystems |
| `avb.pem` | `vbmeta` — the verified-boot chain, and APEX payloads |

---

## 4. Where keys live

GrapheneOS's convention, verified in `script/generate-release.sh`:

| Stage | Location |
|---|---|
| At rest | `keys/<device>/` — encrypted, persistent |
| During signing | a `mktemp -d /dev/shm/...` directory, i.e. RAM, removed by an `EXIT` trap |
| Handed to the signer | symlinked as `keys/` in the tree root, pointed at by `KEY_DIR` |

The important property of this flow is that **plaintext private keys only ever
exist in RAM**, and only for the duration of a signing run.

For Phosphor, the persistent directory stays **outside the GrapheneOS source
tree** — the tree is 1057 git repositories and the last place a private key
should sit. `generate-release.sh` takes the key directory as a path, so
relocating it costs nothing. Directory mode `0700`.

---

## 5. Custody: the YubiKey gates the passphrase

### 5.1 Why this shape

The token is a YubiKey 5 NFC (USB `1050:0407`, serial 38381297, firmware 5.7.4,
OTP+FIDO+CCID). What rules out hardware *signing* with it:

- **Slot count.** PIV has four usable primary slots (9a–9d) and there are ten
  keys. Retired slots (82–95) can hold keys, so it is not strictly impossible —
  but it means juggling slots and driving AOSP's signing tooling through a
  PKCS#11 path it does not use by default.
- **Throughput.** A release signs a large number of APKs plus `vbmeta`. RSA-4096
  signatures performed on the token are slow and serial, and each signing
  session needs the PIN. It would work, and it would be painful.

> **Correction to an earlier draft of this document.** It stated that YubiKey PIV
> caps at RSA 2048 and that RSA 4096 was OpenPGP-only. That is true only for
> firmware below 5.7. Yubico's technical manual states that **5.7.x and later
> firmware supports RSA-3072 and RSA-4096**, and Yubico's PIV documentation
> agrees: "YubiKeys with firmware 5.7 and up also support RSA 3072, RSA 4096,
> Ed25519, and X25519 keys." This token runs 5.7.4, so **the key-size constraint
> does not exist.** The earlier claim came from a secondary source rather than
> Yubico's own docs. The decision below is unchanged, because slot count and
> throughput still rule out token-side signing — but the reasoning is corrected
> here rather than left standing.

So the token cannot conveniently hold and use the key set. What it *can* do — and
what D2 chooses — is hold the secret that unlocks it.

### 5.2 Design

1. Generate an **RSA-2048 keypair inside the YubiKey's PIV slot 9d** (Key
   Management). It never leaves the token.
2. Choose a strong random **scrypt passphrase** for the key set.
3. **Wrap** that passphrase to the PIV key's public half (RSA-OAEP) and store the
   wrapped blob next to the encrypted keys.
4. To sign: unwrap the passphrase using the token (requires the **PIV PIN**),
   export it as `password`, run `script/decrypt-keys`, sign, and let the flow
   wipe `/dev/shm` on exit.

**Why this works — and it is not about key size.** The token performs exactly
**one small RSA unwrap per signing session**, rather than one signature per APK.
That is what sidesteps both real constraints at once: slot count (one slot, not
ten) and throughput (one slow operation, not thousands). The wrap key is
generated at **RSA-2048** deliberately — ample for wrapping a 64-byte passphrase,
fast on the token, and the best-exercised path in OpenSC — even though this
firmware supports RSA-4096 if more margin is ever wanted. An earlier draft
justified this by an RSA-2048 ceiling that does not exist; the real justification
is the operation count.

### 5.3 Why no patching of GrapheneOS's scripts is required

`script/decrypt-keys` reads:

```bash
[[ "${password+defined}" = defined ]] || read -rp "Enter key passphrase: " -s password
```

If `password` is already present in the environment, it **does not prompt** — it
uses the environment value. So a wrapper can supply the unwrapped passphrase and
GrapheneOS's own flow runs untouched. This was verified in the tree, not assumed.

The same is true of the signer itself: `generate-release.sh` calls
`sign_target_files_apks -o -d "$KEY_DIR" --avb_vbmeta_key "$KEY_DIR/avb.pem"`,
which is file-based. Supplying key files is exactly what the flow already does.

Had hardware signing been chosen instead, this is where the plumbing would have
gone: `avbtool` supports `--signing_helper` and `SignApk.java` references PKCS#11,
so it is possible — but it would have meant modifying a release path that
GrapheneOS maintains and tests. D2 avoids that entirely.

### 5.4 What this protects against, honestly

It protects against **theft of the key files alone**. An attacker with the
encrypted keys but not the token cannot sign anything, which is the property
worth having — it means a backup of the key files is not itself a compromise.

It does **not** protect against an attacker who has both the token and the PIN,
or one with root on the build host during a signing run. Neither does any
file-based scheme. Stated so the protection is not oversold.

### 5.5 Host hygiene during signing — swap must be off

GrapheneOS's own guidance warns that the encryption of keys at rest is defeated
if the machine swaps:

> "If you use swap, make sure it's encrypted, ideally with an ephemeral key...
> Even with an ephemeral key, swap will reduce the security gained from
> encrypting the keys since it breaks the guarantee that they become at rest as
> soon as the signing process is finished. Consider disabling swap, at least
> during the signing process."

**This applies to `qoder` and is verified, not theoretical:**

| Check | Result |
|---|---|
| Swap present | `/swap.img`, 8 GiB |
| Swap backed by | plain ext4 on `/dev/nvme0n1p2` |
| LUKS / crypt layer | **none found** |
| Swap actually in use | **857 MiB** |
| Where keys are decrypted | `/dev/shm` — tmpfs, 29.7 GiB |

`/dev/shm` is tmpfs, and tmpfs pages **can be written to swap**. So during a
signing run, plaintext private keys could be paged out to an unencrypted
swapfile and survive there after the `EXIT` trap has cleared `/dev/shm` — which
is precisely the guarantee the design depends on.

**Required mitigation:** `sudo swapoff -a` before signing and `sudo swapon -a`
afterwards. This is safe here (55 GiB RAM free against 857 MiB of swap in use),
and it should be automated in the signing wrapper so it cannot be forgotten
rather than left as a checklist item.

**Related:** `keys/<device>/` at rest is scrypt + AES256 encrypted, per
GrapheneOS's `make_key`/`encrypt-keys`. The passphrase must be **identical across
all ten keys** for the scripts to work, and the AVB key is generated with
`openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt`, i.e. encrypted from the
start rather than encrypted later.

---

## 6. The signing flow, end to end

```
    encrypted keys at rest          keys/akita/  (0700, outside the source tree)
              |
              |  unwrap passphrase using the YubiKey (PIV slot 9d, PIN required)
              v
    export password=<unwrapped>
              |
              |  script/decrypt-keys "$KEY_DIR"     <- sees $password, does not prompt
              v
    plaintext keys in /dev/shm only
              |
              |  sign_target_files_apks -d "$KEY_DIR" --avb_vbmeta_key avb.pem
              v
    signed target-files package
              |
              |  EXIT trap removes /dev/shm/... and the keys symlink
              v
    plaintext gone; encrypted keys unchanged
```

The input to this flow is the artifact Phase 2 already produces:
`out/target/product/akita/obj/PACKAGING/target_files_intermediates/akita-target_files.zip`
(3.6 GB, 8841 files, 17 images).

---

## 7. Backup, escrow and loss

**Resolved at generation (2026-09-25).** D3 deferred these mechanics to the moment
keys are actually generated, and that moment arrived. Two things were decided and
implemented:

1. **The passphrase is escrowed at generation.** `keys-generate.sh` writes it to a
   mode-600 file beside the keys, *before* sealing it to the token. Deliberate
   ordering: generation is the only moment the passphrase exists outside the
   token, and writing it first means a failure in the seal step leaves it
   recoverable rather than stranded.
2. **Losing the token therefore no longer loses the key set.** The escrow file
   must be stored offline (paper in a safe, or an encrypted volume on removable
   media) and then removed from the build host — while it sits there, the token is
   *not* the only way in, which is the exact property the token was chosen for.

Verified rather than assumed: the token-unsealed passphrase was compared against
the escrow copy and they **match**, and that passphrase was used to decrypt a
`.pk8` whose derived public key matches its `.x509.pem`. See
`docs/evidence/phase3-key-generation-20260925.txt`.

**Still open:** an encrypted backup of the key material itself. The escrow covers
losing the *token*; it does not cover losing the *host*.

**What is at stake.** Losing `avb.pem` or the APK signing keys means the device
will not accept future updates signed by the replacement set without being
unlocked and reflashed — i.e. another wipe. There is no recovery path that
preserves the device's data.

**Options for the remaining question (backing up the keys themselves):**

| Option | Notes |
|---|---|
| Two encrypted copies, separate media, one off-site | Standard practice. The wrapped passphrase (or the PIV key) must be backed up too, or the copies are inert. |
| Wrap the keys to a second YubiKey | Keeps the physical-token property across backups, at the cost of a second token and careful PIV provisioning. |
| YubiHSM-style key wrapping to a file | Not applicable unless an HSM is bought later. |

**A trap to avoid:** backing up the encrypted key files but not the means to
unwrap them. That produces a backup that looks complete and is worthless. The
wrapped passphrase blob and the PIV key's public half belong in the backup set,
and the PIV key itself must be reproducible or escrowed — this is the detail the
deferred decision actually needs to resolve.

---

## 8. Bootloader posture: unlocked during development, relock when ready (D4)

**Decision (revised 2026-09-25 against the vision):** the bootloader **stays
unlocked throughout development** and is **relocked when the build and key chain
are ready**. It is not relocked now, and it is not intended to stay open forever.

> *Revision note.* This decision originally read: "the bootloader stays unlocked.
> It will not be relocked." Captain JAQ has since confirmed that
> `docs/PHOSPHOR-VISION.md` is the goal and the source of truth, and the vision is
> explicit about the intended arc — keep the bootloader unlocked during active
> development, install Phosphor's AVB public key as the device's custom
> verified-boot root of trust, and *"relock the bootloader only when the build and
> key chain are ready for a secured development/release device"* (vision §Build,
> signing, flashing, and feasibility findings, steps 6–7). It adds that a locked
> device running our key "may show the standard custom-OS warning, normally a
> yellow screen, while still using verified boot and rollback protection".
> The vision's §Design principles also warn against confusing a prototype
> workaround with the target architecture, and a permanently unlocked bootloader
> is exactly that. The cost is unchanged and real — both transitions wipe — so
> relocking stays a deliberate step for the Phase 15 revisit below, not a
> convenience.

**What that means, stated plainly:**

- **Verified boot is not enforced.** An unlocked bootloader will boot an image
  that fails AVB verification, after showing a warning. So the `avb.pem` key
  stops being a security control and becomes a build-consistency requirement.
- **Anything can be flashed by anyone with physical access**, including a
  modified OS, without needing our keys.
- **The AVB key is no longer a permanence risk in practice** — the argument in
  D1 was that changing it forces another wipe, but with the bootloader open,
  images signed with test keys or with any other key boot regardless. D1 still
  stands for cleanliness and for the possibility of relocking later, but its
  urgency is reduced by this decision.
- This is the normal posture for a development device, and it is a real
  reduction in the device's security guarantees compared to the locked
  GrapheneOS installation currently on it.

**Escape hatch, recorded so it is not a surprise:** relocking later is possible,
but it requires flashing a build signed with keys the device will accept and
then relocking — and unlocking again in future would wipe the device. The
practical consequence is that D4 is cheap to keep and expensive to reverse.

*Mechanism, established 2026-09-25 (Phase 3 flash):* "keys the device will
accept" is now concrete rather than hand-waving. `flash-all.sh` runs
`fastboot erase avb_custom_key` followed by `fastboot flash avb_custom_key
avb_pkmd.bin` (lines 92–93 of the installed script), so our AVB public key is
installed into the device's custom-key partition on every flash. `avb_custom_key`
is exactly the slot a Pixel uses to verify against a non-Google key, which makes
verified boot under OUR key look achievable by relocking — without anything new
having to be built. What keeps it from being a casual step is unchanged: it costs
another wipe, and a non-booting build plus a locked bootloader equals a brick,
recoverable only by unlocking again (which wipes). Treat it as a deliberate step
for the Phase 15 revisit below, not a convenience.

**Worth noting for later phases:** this posture is in tension with
`PHOS-SPEC-001`'s trust architecture, which is concerned with what the OS can be
made to trust. It is defensible during development and should be revisited
before any Phase 15 pilot deployment, where a locked device with our keys
enrolled would be the appropriate target state. As of 2026-09-25 the posture is
*realised* rather than theoretical: the flashed device reports
`ro.boot.verifiedbootstate=orange` and `ro.boot.flash.locked=0`, i.e. verified
boot is not enforced on it.

**Naming caution:** the label `D4` in this document means "do not relock the
bootloader". In `PHOS-SPEC-001` §7.2, `D4` is an unrelated command-risk pattern
(`chmod`/`chown` on system paths). Same label, different subjects — read the
containing document.

---

## 9. Tooling to install

| Package | Purpose | Status |
|---|---|---|
| `yubico-piv-tool` | generate the PIV key in slot 9d; wrap/unwrap the passphrase | available, not installed |
| `pcscd` | smartcard daemon the PIV applet needs | available, not installed |
| `opensc` | PKCS#11 provider (`pkcs11-tool`) | available, not installed |
| `yubikey-manager` | inspect and provision the token | available, not installed |
| `libfido2-1` | alternative gating mechanism (hmac-secret) | **installed** |

All are distro packages, so installation is an idempotent script run with
`sudo`, as with the Phase 1 toolchain.

---

## 10. Open items

1. **This design needs approval** before any key is generated.
2. **Backup mechanics** — D3 defers them; §7 lists what the decision must cover,
   including the trap of backing up keys without the means to unwrap them.
3. **Flashing workflow** — not yet designed. Needs: `fastboot` flow with
   `fwupd` stopped first (it claims fastboot-protocol devices), the unlock
   operation itself (wipes the device, requires explicit approval for that
   specific operation), and image verification.
4. **Unbrick / recovery procedure** — not yet designed. Must cover the case where
   a build does not boot: recovery mode, `fastboot` access, and the fallback of
   flashing a known-good GrapheneOS release from the official web installer.
5. **Image verification checklist** — not yet written.
6. **The unlock decision itself** — still open. Nothing in this document requires
   it, and Phase 2's images are unmodified GrapheneOS, so flashing them would
   wipe a working device to install something functionally identical.

---

## 11. What this document deliberately does not do

It does not generate keys, does not touch the device, and does not decide the
unlock. Key generation is the next action **only after this design is approved**,
in accordance with the phase plan.
