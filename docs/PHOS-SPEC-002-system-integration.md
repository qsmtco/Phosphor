# PHOS-SPEC-002: System Integration — Phosphor as an Operating System
**Status:** DRAFT — concept approved for discussion (Captain JAQ, 2026-09-05); not yet requirements-approved
**Depends on:** PHOS-SPEC-001 (trust architecture, complete)
**Supersedes:** nothing; extends Phosphor below the UI layer

---

## 1. Abstract

Phosphor today occupies the interface layer of a host Linux system: the
agent renders screens, and the host OS provides boot, services, and device
policy. This spec defines the staged descent by which Phosphor takes
ownership of the remaining operating-system responsibilities — boot,
service lifecycle, system configuration, hardware arbitration, and kernel
policy — turning "Phosphor, an app on Linux" into "Phosphor, the operating
system of a Linux handheld."

Core principle: the Linux kernel remains stock. Phosphor's OS-ness is
implemented in USERSPACE (init integration, service control, device
arbitration, eBPF policy). No runtime-generated kernel code; eBPF is the
sanctioned dynamic-policy mechanism.

## 2. Conventions

RFC 2119 (MUST/SHOULD/MAY) per PHOS-SPEC-001 §2.

## 3. The Four Jobs of an OS (definition used here)

1. Boot the machine (init, session bring-up)
2. Arbitrate hardware (who uses the modem/camera/GPS, when radios sleep)
3. Enforce policy (permissions, budgets, network rules)
4. Provide the interface (what the human touches)

Phosphor owns #4 today (proven, TestFlight). This spec climbs 4 → 1.

## 4. Integration levels

### L4 — Phosphor owns boot (the boot experience)
- The init system starts Phosphor (runtime + bridge + kiosk browser) as
  the session, before any other UI exists. No login manager, no desktop.
- Implementation: systemd unit chain (or tiny init script) on
  postmarketOS/mainline Linux for the Pixel 8a.
- Exit criterion: power-on → Phosphor screen, nothing else ever runs.

### L3 — Phosphor owns system configuration
- Network (Wi-Fi/cellular via iwd/ModemManager), audio (PipeWire), display
  brightness, power profiles, time — all exposed as AGENT TOOLS through the
  bridge.
- No settings applications exist; system administration is conversation.
- All new tools enter the §7 risk classifier (e.g. network-down, service
  stop = DESTRUCTIVE; brightness = SAFE).

### L2 — Phosphor arbitrates hardware
- The Rust bridge becomes the RESOURCE ARBITER: sole owner of modem
  (ModemManager), GPS (geoclue), Bluetooth (bluez), camera. Clients
  (including the agent) request; the bridge + approval policy decide.
- Agent sets power policy for radios (sleep/wake decisions).
- This is the role Android's system_server plays — implemented as a
  minimal Rust arbiter.

### L1 — Phosphor holds kernel policy
- eBPF programs for network policy, written/loaded by the agent via
  verifier-safe tooling (never hand-rolled kernel code).
- cgroup CPU/memory budgets per task, set by the agent.
- PID 1 is a tiny static supervisor; the agent is its policy brain.
- Kernel itself remains stock mainline Linux, always.

### L0 — Conceptual endpoint
Natural language as the syscall interface. Compiled artifacts optional.
Not a separate phase: it is L1/L2 with the UX fully realized.

## 5. Security & recovery requirements (the difference between OS and demo)

- **REC-1 (MUST):** Out-of-band recovery — USB/SSH path into the device
  that does not depend on Phosphor being healthy.
- **REC-2 (MUST):** Safe-mode boot path — a boot option that starts a
  plain shell + minimal network, skipping the agent, reachable without
  the agent's cooperation.
- **REC-3 (MUST):** The approval card remains NATIVE and system-verified
  (P5-H1 invariant). As tool stakes rise (L3+), the card is the root
  prompt of the OS; its content MUST come from the system registry, never
  page/script scope.
- **REC-4 (MUST):** Risk classifier extended with SYSTEM tool classes
  (network down, service stop, poweroff, driver params) — same fail-closed
  pattern engine, new kingdom.
- **REC-5 (SHOULD):** Quarantine scanning applies to ALL system feedback
  the agent consumes (logs, statuses) — system output is untrusted input.

## 6. Non-goals

- LLM in the kernel. Never.
- Writing a display server or libc. Compose existing Linux components.
- Multi-user. Single-user device (per PHOS-SPEC-001 §4.3).

## 7. Hardware prerequisites

- Second Pixel (or the same 8a post-iOS-freeze) for development; USB
  recovery cable always at hand; serial console if obtainable.
- Development happens on postmarketOS or Debian-for-Pixel with mainline
  kernel; GrapheneOS remains the daily-driver fallback during development.

## 8. Open questions (for the Captain)

1. Target base OS: postmarketOS (Alpine) vs Debian-on-Pixel?
2. Init: minimal systemd vs tiny custom Rust supervisor as PID 1?
3. Recovery: is a physical USB/serial escape acceptable, or must safe-mode
   be on-device?
4. Acceptable downtime during L4 bring-up experiments on the 8a?

## 9. References

- PHOS-SPEC-001 (trust architecture — the foundation this builds on)
- docs/ANDROID.md (current device state)
- PHOSPHOR_SPEC.md (product vision, hardware guide)

### Openness research (2026-09-05, Qrusher)

**GrapheneOS forkable components (all permissively licensed):**
- `GrapheneOS/kernel_pixel` — monolithic kernel sources, 6th–9th gen Pixels
  (8a/akita included). GPLv2. Buildable; GOS ships kernels built from it.
- GrapheneOS AOSP hardening tree — hardened malloc, SELinux policies,
  bionic/framework patches. Apache-2.0/BSD.
- Vanadium — BSD-3-Clause hardened Chromium.
- Apps/infrastructure — MIT.

**Firmware reality (closed, permanent):** modem firmware, GPU firmware,
camera ISP firmware, Trusty — proprietary binaries on separate processors.
Linux loads them; they are not inspectable. Every Linux phone lives with this.

**Mainline modem milestone (Exynos 5300 — the 8a's modem):**
- Developer Steffen Deusch (2026) brought up the Exynos 5300 on the Pixel 9a
  (same modem family): SMS works, calls work (2G CS + VoLTE), mobile data
  works, wired into ModemManager via a custom SIT plugin. Kernel sources and
  tools published (github.com/SteffenDE/linux-google-tegu,
  git.deusch.me/pixel-mainline).
- Directly relevant to the 8a: same modem silicon, and the bridge's
  ModemManager-based design (original handlers.rs) matches this stack.

**Weak points on mainline (honest):** camera ISP lacks mainline drivers
(libcamera/software-ISP workaround at best); power management/suspend is
Android-tuned on GOS vs rougher on mainline; Pixel device trees and some
driver binaries are being withdrawn from easy access by Google (post-Android-16
shift of AOSP reference target to cuttlefish) — GOS self-hosts what it needs.

**Implication for Phosphor:** on GrapheneOS (now) the bridge speaks Android
APIs; on pure Linux (SPEC-002 target) the bridge speaks ModemManager/DBus and
the community SIT plugin makes the 8a's modem a viable target. Kernel source
base: GrapheneOS kernel_pixel + mainline Exynos-modem work.
