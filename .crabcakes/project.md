# Phosphor — Project Manifest

## Purpose

**Phosphor is an agent-native phone operating system**: a GrapheneOS-derived Android
platform in which the AI agent is the primary interface and system coordinator, not an
app. The user speaks; the agent resolves intent, calls the appropriate platform
capability, and renders the active screen as HTML/JavaScript in real time. Home,
notifications, calls, messages, settings, camera and sensors all flow through one
agent-controlled surface.

- Source of truth: `docs/PHOSPHOR-VISION.md`. Status/handoff: `docs/PROJECT-STATUS.md`.
- Target device: Pixel 8a (`akita`), serial `3C121JEKB03922`. Target foundation:
  GrapheneOS-derived image, our own signing keys, our own AVB root of trust.
- Development host: `qoder` (Ubuntu 26.04, Ryzen 9 9950X, 59 GiB RAM), USB to the Pixel.

### What Phosphor is NOT

Never redirect into these because they are easier: a normal Android app, a chatbot on
top of GrapheneOS, a browser shell as the final product, a Termux-hosted runtime as the
OS, a Debian VM as the OS, or loosely connected apps with an AI front-end.

## Stack

- **Target platform:** GrapheneOS-derived Android build (source tag `2026091900` at
  `~/projects/grapheneos-2026091900`), built with AOSP's own prebuilt toolchain
  (no ccache/clang/ninja needed on host). Recipe: `source build/envsetup.sh` →
  `lunch akita-cur-user` (NOT `akita-user` / `akita-ap2a-user`) →
  `m -j24 vendorbootimage vendorkernelbootimage target-files-package`.
- **Signing:** GrapheneOS's own `make_key`/`encrypt-keys`/`generate-release.sh` flow with
  our 10-key set (9 APK/platform keys + `avb.pem`), scrypt/PBES2-encrypted, passphrase
  sealed behind a YubiKey PIV wrap key (YubiKey 5 NFC serial 38381297).
- **Prototype material (NOT the target architecture):** Python DragonCakes-derived agent
  runtime (`runtime/agent_core.py`, `runtime/server.py`), browser shell (`shell.html`),
  Rust hardware bridge (`bridge/`), iOS PoC (`ios/`, `ios-app/`), Termux, local Whisper.
  Bring-up and learning material only — do not build infrastructure around them.
- **Live specs that constrain all design:** `docs/PHOS-SPEC-001-trust-architecture.md`
  (trust + interactive-UI security, front-end-agnostic) and
  `docs/PHOS-SPEC-002-system-integration.md` (L0–L4 integration levels).

## Entry Points

| What | Where |
|---|---|
| The goal (source of truth) | `docs/PHOSPHOR-VISION.md` |
| Current status + full handoff | `docs/PROJECT-STATUS.md` |
| 16-phase build plan | `docs/PHOSPHOR-BUILD-PLAN.md` |
| Trust/UI security spec | `docs/PHOS-SPEC-001-trust-architecture.md` |
| OS integration spec (L0–L4) | `docs/PHOS-SPEC-002-system-integration.md` |
| GrapheneOS build recipe + traps | `docs/PROJECT-STATUS.md` §6–§9 |
| Phase detail docs | `docs/PHASE-1-…`, `docs/PHASE-2-…`, `docs/PHASE-3-…` |
| Host/key/signing scripts | `scripts/*.sh` |
| Raw evidence | `docs/evidence/` |

## Conventions

- **Never flash or wipe the phone without the user's explicit approval for that specific
  operation.** `flash-all.sh` erases userdata and metadata every time.
- **USB rehearsal before every flash** (`adb reboot bootloader; fastboot
  reboot-bootloader; fastboot devices; fastboot reboot; adb devices`); stop
  `fwupd.service` every session (it claims fastboot devices).
- **Never relock the bootloader while troubleshooting.**
- **No sudo for agents** on qoder: write an idempotent script, hand the user
  `sudo bash <script>`, verify the result independently. `sudo swapoff -a` before
  signing, `swapon -a` after (no disk encryption on host).
- **No GitHub credential on host**: user primes git's in-memory cache for pushes; never
  `credential.helper=store`. Never ask for a token in chat; scan docs for secrets before
  committing.
- **Keys stay outside the source tree** (`~/phosphor-keys/akita`), plaintext only in
  `/dev/shm` during signing. Never back up encrypted keys without the unwrap means.
- **Never re-sign Vanadium** (Trichrome*/WebView APKs carry GrapheneOS's signature —
  expected and load-bearing; Chromium-from-source is a Phase 4 decision).
- **Verify flashing cryptographically**, never by "it boots": compare
  `ro.boot.vbmeta.digest` to sha256 of the flashed `vbmeta.img` first 7488 bytes.
- **Scope whole-tree searches to `~/projects/Phosphor`** — the GrapheneOS tree is ~136 GB
  plus ~107 GB `out/`.
- **Python:** PEP 8, Ruff (lint+format), mypy, pytest — standard tooling; the prototype
  runtime is the only Python in scope today.
- **adb/MTP trap:** PID `4ee1` = debugging OFF (adb blind); replug after enabling USB
  debugging; check the PID, not `adb devices`.

## Team

- **PM:** Captain JAQ (qsmtco) — project owner, device/key custodian, sole approver of
  destructive operations.
- **Supervisor** (`agent:supervisor`) — onboarding & implementation orchestration.
- **Coder** (`agent:coder`) — implementation.
- **Debugger** (`agent:debugger`) — adversarial audit.

## Current state (2026-11-10)

Phases 0–3 (definition, host readiness, source/build, signing/flashing/recovery) are
**complete and cryptographically verified**; the flashed image is stock GrapheneOS with
**zero Phosphor code**. **Next action: Phase 4 — Phosphor platform architecture**
(system shell, native agent service boundaries, capability broker, HTML/JS rendering
surface + native bridge, voice/STT paths, privilege/consent/audit boundaries), inside
the L0–L4 frame of PHOS-SPEC-002 and the requirements of PHOS-SPEC-001.