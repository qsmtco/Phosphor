# Phosphor Build Plan

**Status:** High-level roadmap
**Project:** Phosphor
**Target device:** Google Pixel 8a (`akita`, model GKV4X)
**Foundation:** GrapheneOS-derived operating system
**Primary development host:** Linux computer connected to the Pixel by USB
**Related vision document:** `docs/PHOSPHOR-VISION.md`

---

## 1. Purpose

This document defines the high-level, multi-phase plan for realizing Phosphor as a deeply integrated, voice-first, agent-native phone operating system based on GrapheneOS.

Phosphor is not intended to remain a conventional Android application, a Termux-hosted Linux service, or a collection of loosely connected apps. Those mechanisms may be used temporarily for experiments, but the target system is a custom GrapheneOS-derived platform in which the Phosphor agent, system interface, communication capabilities, settings, hardware access, and generated user interface work together as one operating environment.

The plan is intentionally higher level than an implementation specification. Each phase will later receive its own detailed design document, acceptance criteria, work breakdown, test plan, and implementation tasks.

---

## 2. Target outcome

The completed system should allow the user to interact primarily by speaking naturally to Phosphor.

The intended interaction loop is:

```text
User speech
    ↓
Speech-to-text (STT)
    ↓
Phosphor agent and system capability layer
    ↓
Action, answer, or request for user input
    ↓
Agent-generated HTML/JavaScript interface
    ↓
Rendered on the phone as the active task-specific screen
```

Representative outcomes include:

- “Call Mom” resolves the contact and starts the phone call.
- An incoming text is surfaced to the user and classified.
- A harmless, well-understood message may be answered by the agent.
- An ambiguous, sensitive, or consequential message is presented to the user for input.
- “Turn on Wi-Fi,” “show my calendar,” “set an alarm,” or “open the camera” invokes the relevant system capability.
- The agent creates the controls, buttons, forms, status displays, confirmations, and other interface elements needed for the current task.

The final phone surface is therefore a real-time HTML/JavaScript rendering surface designed by the agent, backed by native operating-system capabilities.

---

## 3. Guiding principles

### 3.1 Build the chosen system, not an easier substitute

The goal is a GrapheneOS-derived Phosphor operating system. A conventional app, browser shell, Termux runtime, or remote server may support prototypes, but none of them replaces the platform project.

### 3.2 Investigate before making irreversible changes

Source, build, device, signing, licensing, hardware, and security assumptions must be verified before committing to major implementation paths. Device wipes, bootloader changes, flashes, key generation, and production-like signing operations require explicit approval at the point of action.

### 3.3 Preserve the secure foundation

Phosphor should use GrapheneOS and Android security mechanisms where possible rather than discarding them. Deeper control means carefully designed platform integration, services, privileges, policies, and system UI—not automatically removing every isolation boundary.

### 3.4 Native integration is the destination

The long-term implementation must live in the Android/GrapheneOS platform architecture. Temporary prototypes should be evaluated by whether they reduce uncertainty or validate behavior that will later be implemented natively.

### 3.5 Voice first, generated UI always available

Speech is the primary input path. Text and direct touch remain useful fallback and complementary modes. The agent must be able to render a usable interface for every operation rather than returning text alone.

### 3.6 Small verified increments

Each phase must produce a working artifact or a verified reduction in uncertainty. Builds, flashes, system services, generated screens, and communication actions must be tested on the real target or an appropriate emulator before being treated as complete.

### 3.7 Protect the project boundaries

Phosphor remains separate from DragonCakes and Eagle Dispatch. Existing code may be studied or reused where appropriate, but those projects, repositories, deployments, and apps must not be modified as part of Phosphor work.

---

## 4. Phase overview

| Phase | Name | Primary result |
|---|---|---|
| 0 | Project definition and control documents | Stable goals, boundaries, terminology, and decision record |
| 1 | Build-host and device readiness | Verified Linux/USB/Pixel development environment |
| 2 | GrapheneOS source and build foundation | Reproducible baseline source tree and stock-derived build |
| 3 | Signing, flashing, and recovery pipeline | Safe development image lifecycle on the Pixel |
| 4 | Phosphor platform architecture | Detailed system design and capability boundaries |
| 5 | Native Phosphor system foundation | Bootable platform components and trusted agent service foundation |
| 6 | Phosphor system shell and rendering surface | Primary agent-controlled phone interface |
| 7 | Voice, STT, and conversational loop | Reliable speech-first interaction |
| 8 | Agent capability and policy framework | Native action orchestration with explicit safety policy |
| 9 | Communications integration | Calls, contacts, SMS/messages, notifications, and escalation |
| 10 | Settings, apps, and hardware integration | Unified control of device functions and applications |
| 11 | Persistence, identity, data, and recovery | Durable user state, privacy, backups, and recovery behavior |
| 12 | Security hardening and adversarial testing | Secure, understandable, and resilient platform |
| 13 | Performance, reliability, and real-device validation | Daily-usable system on the Pixel |
| 14 | Update, release, and long-term maintenance system | Sustainable Phosphor distribution and servicing |
| 15 | Pilot deployment and iterative expansion | Controlled real-world use and continued platform evolution |

The phases are ordered, but some later design and prototyping work can proceed in parallel once its dependencies are understood.

---

# 5. Detailed phase outline

## Phase 0 — Project definition and control documents

### Objective

Establish a stable description of what Phosphor is, what it is not, and how decisions will be made so implementation does not drift toward an easier but different project.

### High-level scope

- Maintain the product vision and operating-system definition.
- Define the primary voice/STT/generated-HTML interaction model.
- Define project boundaries and protected external projects.
- Establish terminology for platform components, services, shells, agents, capabilities, policies, images, keys, and updates.
- Create the decision log and engineering assumptions register.
- Separate confirmed facts, hypotheses, and open questions.

### Deliverables

- Vision document.
- This high-level build plan.
- Architecture decision record format.
- Risk and open-questions register.
- Explicit change-control and device-operation rules.

### Exit criteria

The project’s goal, boundaries, success definition, and next phase are unambiguous.

---

## Phase 1 — Build-host and device readiness

### Objective

Verify that the Linux computer and Pixel 8a can support the intended build, USB development, recovery, and diagnostic workflow.

### High-level scope

- Audit CPU architecture, RAM, storage, filesystem, swap, network, and supported Linux distribution.
- Verify required build tools and dependencies.
- Verify USB connectivity, udev access, `adb`, and `fastboot` versions.
- Identify the Pixel model, codename, firmware state, bootloader state, and carrier-unlock constraints.
- Document backup and recovery requirements.
- Confirm available build storage before syncing the complete source tree.

### Deliverables

- Build-host audit.
- Device and USB readiness report.
- Storage and resource budget.
- Recovery and backup procedure.
- No-change baseline record of the current Pixel.

### Exit criteria

We know whether the existing computer can build the target and communicate with the Pixel safely, and all destructive prerequisites are clearly identified.

---

## Phase 2 — GrapheneOS source and build foundation

### Objective

Obtain, verify, understand, and build the GrapheneOS source for the Pixel 8a before adding Phosphor changes.

### High-level scope

- Select an appropriate stable GrapheneOS source revision.
- Synchronize the platform manifest and repositories.
- Verify source provenance and signed tags/manifests where applicable.
- Extract and prepare the required Pixel vendor files.
- Learn the target build configuration for `akita`.
- Produce a baseline build with documented inputs and outputs.
- Establish build logs, artifact storage, and reproducibility practices.

### Deliverables

- Verified GrapheneOS source tree.
- Documented `akita` build configuration.
- Baseline build artifacts.
- Build procedure and troubleshooting notes.
- Initial source and dependency map.

### Exit criteria

The Linux host can produce a documented GrapheneOS-derived Pixel 8a build, or any blocker is identified with evidence and a resolution path.

---

## Phase 3 — Signing, flashing, and recovery pipeline

### Objective

Create a safe and repeatable process for signing development images, flashing them to the Pixel, recovering from failed builds, and preserving the ability to return to a known-good state.

### High-level scope

- Define development versus release signing modes.
- Generate Phosphor development/release keys only after the key-management design is approved.
- Document AVB, Android release, APK, APEX, factory-image, and update-package signing roles.
- Protect keys using secure storage and encrypted backups.
- Establish unlocked-bootloader development flashing.
- Test boot, recovery, rollback, logs, and restoration procedures.
- Define the conditions for any future bootloader relock.

### Deliverables

- Key hierarchy and key custody design.
- Development signing configuration.
- USB flashing workflow.
- Recovery/unbrick procedure.
- Image verification checklist.
- Explicit release-signing and relock readiness criteria.

### Exit criteria

A known-good custom build can be flashed, booted, diagnosed, and restored with a repeatable process. No release-like relock is attempted until the required verification criteria are satisfied.

---

## Phase 4 — Phosphor platform architecture

### Objective

Translate the product vision into a concrete Android/GrapheneOS platform architecture before implementing deep system changes.

### High-level scope

- Define the Phosphor system shell.
- Define the native agent service and its process boundaries.
- Define the capability broker for telephony, messaging, contacts, notifications, settings, audio, sensors, storage, and applications.
- Define the generated HTML/JavaScript rendering surface and its bridge to native capabilities.
- Define voice input, STT, model inference, tool execution, and response rendering paths.
- Define privilege, identity, consent, audit, and policy boundaries.
- Define offline, degraded-network, and unavailable-service behavior.
- Map each planned feature to Android framework APIs, system services, privileged apps, new services, or vendor interfaces.

### Deliverables

- System architecture document.
- Component and process map.
- Capability/API inventory.
- Data-flow and trust-boundary diagrams.
- Policy model.
- Prototype-to-native migration map.

### Exit criteria

The major system boundaries and implementation locations are understood well enough to begin native platform work without guessing.

---

## Phase 5 — Native Phosphor system foundation

### Objective

Introduce Phosphor into the GrapheneOS platform as native system components rather than as a Termux-hosted runtime.

### High-level scope

- Add the initial Phosphor platform repositories/modules to the build.
- Establish the native agent service process and lifecycle.
- Add required framework interfaces and service registration.
- Define SELinux domains, permissions, resource limits, and privileged identities.
- Establish secure local communication between the agent, system services, and renderer.
- Add structured logging, diagnostics, health checks, and crash recovery.
- Preserve the ability to boot into a fallback system surface during early development.

### Deliverables

- Bootable image containing the initial Phosphor native foundation.
- Agent service skeleton.
- Native capability-service interfaces.
- SELinux and permission policy.
- Diagnostics and recovery hooks.

### Exit criteria

The Pixel boots a custom Phosphor build in which the core agent foundation starts reliably as part of the operating system.

---

## Phase 6 — Phosphor system shell and rendering surface

### Objective

Make Phosphor the primary interactive surface and establish the real-time generated HTML/JavaScript interface model.

### High-level scope

- Replace or supersede the default launcher/home experience.
- Implement the full-screen or primary Phosphor surface.
- Build the trusted HTML/JavaScript renderer and native bridge.
- Define screen lifecycle, navigation, state, focus, accessibility, and interruption behavior.
- Support agent-generated buttons, forms, controls, status panels, media, and confirmations.
- Handle phone calls, notifications, lock/unlock states, system dialogs, and external applications.
- Provide a fallback interface if agent generation or network access fails.

### Deliverables

- Phosphor primary shell.
- Secure generated-screen renderer.
- Native-to-renderer capability bridge.
- Screen and interaction lifecycle specification.
- Initial agent-designed task screens.

### Exit criteria

The Pixel presents Phosphor as its primary surface, and the agent can generate and render useful task-specific interfaces with reliable touch interaction.

---

## Phase 7 — Voice, STT, and conversational loop

### Objective

Make speech the dependable primary input mechanism for the operating system.

### High-level scope

- Integrate microphone capture through native Android audio services.
- Implement local STT as the baseline path where practical.
- Define optional remote STT behavior and privacy controls.
- Implement speech activity, recording, processing, interruption, cancellation, and error states.
- Connect STT output to the native agent service.
- Support text and touch fallback without making them the primary design.
- Define model hosting, network failure, latency, and resource behavior.
- Add spoken or visual feedback as appropriate.

### Deliverables

- Native voice-input pipeline.
- STT service integration.
- Local/remote transcription policy.
- Voice interaction state machine.
- End-to-end speech-to-generated-screen demo.

### Exit criteria

A user can speak a request on the Pixel, receive reliable transcription, have the agent process it, and see a generated interface for the resulting task.

---

## Phase 8 — Agent capability and policy framework

### Objective

Give the agent reliable, native, auditable ways to reason about and perform system actions.

### High-level scope

- Define typed capabilities and action schemas.
- Implement capability discovery and invocation.
- Define user identity, agent identity, and delegated authority.
- Establish policy categories for harmless, private, consequential, irreversible, and security-sensitive actions.
- Implement context, memory, task state, and interruption handling.
- Add confirmation and escalation behavior that is deliberate rather than repetitive.
- Record action results and failures accurately.
- Prevent fabricated success by requiring real capability results before reporting completion.

### Deliverables

- Capability framework.
- Policy and delegation model.
- Agent-to-system action protocol.
- Audit/event model.
- Failure and escalation behavior.
- Initial native actions replacing prototype tools.

### Exit criteria

The agent can perform verified native actions, explain failures accurately, and request user participation only when the policy or context genuinely requires it.

---

## Phase 9 — Communications integration

### Objective

Implement the core team-like phone behavior around calls, contacts, messages, notifications, and agent escalation.

### High-level scope

- Integrate contacts and contact resolution.
- Integrate telephony and call state.
- Support spoken call requests such as “call Mom.”
- Integrate SMS/MMS and supported messaging services.
- Receive, classify, summarize, and surface incoming messages.
- Define when the agent may draft or send a reply.
- Escalate ambiguous, sensitive, private, or consequential messages to the user.
- Render call and message controls as generated interfaces.
- Handle emergency calling and other protected communications according to platform requirements.

### Deliverables

- Contact-resolution capability.
- Native call-control capability.
- Message ingestion and notification pipeline.
- Agent message classification and escalation policy.
- Call/message generated screens.
- End-to-end communication test suite.

### Exit criteria

The user can manage ordinary calls and messages through Phosphor by voice and generated controls, with correct escalation for cases requiring human input.

---

## Phase 10 — Settings, applications, and hardware integration

### Objective

Expand Phosphor from communications into a general system coordinator.

### High-level scope

- Integrate core settings and device state.
- Control connectivity, audio, display, power, alarms, notifications, and permissions where permitted.
- Define application discovery, launching, focus, and handoff.
- Decide which system apps remain underneath Phosphor and which interfaces are replaced.
- Integrate camera, sensors, location, Bluetooth, NFC, storage, and other hardware capabilities as appropriate.
- Implement generated controls for each capability.
- Maintain user-visible explanations and status for system actions.

### Deliverables

- Capability coverage matrix.
- Native settings/action integrations.
- Application coordination model.
- Hardware-service integrations.
- Generated interfaces for core device operations.

### Exit criteria

Phosphor can coordinate the major daily phone functions without requiring the user to manually navigate a collection of unrelated apps for ordinary tasks.

---

## Phase 11 — Persistence, identity, data, and recovery

### Objective

Make Phosphor dependable across reboots, network changes, model changes, and failures while protecting user data.

### High-level scope

- Define persistent agent state, conversation state, preferences, contacts context, and task history.
- Integrate Android storage encryption and credential protection.
- Define data ownership, retention, export, deletion, and backup behavior.
- Support multiple model providers or local models without losing system identity.
- Handle reboot recovery, service restart, interrupted tasks, and incomplete actions.
- Define user and device identity across system components.
- Ensure generated interfaces can restore or safely discard state.

### Deliverables

- Data and persistence architecture.
- Backup and restore plan.
- Recovery behavior specification.
- State migration strategy.
- Privacy and retention controls.

### Exit criteria

The system remains coherent and safe across normal lifecycle events and can recover from interrupted work without claiming actions that did not complete.

---

## Phase 12 — Security hardening and adversarial testing

### Objective

Ensure that deep system integration does not create an unsafe or opaque device.

### High-level scope

- Threat-model the agent, generated UI, native bridge, model providers, communications, update system, and signing keys.
- Harden HTML/JavaScript rendering against injection and confused-deputy behavior.
- Restrict capabilities according to explicit policy and user delegation.
- Audit SELinux, privileged permissions, IPC, storage, logs, and network access.
- Test prompt injection, malicious messages, malicious web content, compromised model providers, and malformed generated screens.
- Test lost/stolen-device behavior, lock-screen boundaries, emergency functions, and account separation.
- Review key custody, release process, rollback protection, and update authenticity.

### Deliverables

- Threat model.
- Security architecture review.
- Adversarial test suite.
- Penetration and abuse-case findings.
- Remediation plan.
- Security release checklist.

### Exit criteria

Known high-severity security issues are resolved or explicitly accepted with documented mitigation, and the platform’s authority boundaries are understandable and testable.

---

## Phase 13 — Performance, reliability, and real-device validation

### Objective

Turn the integrated prototype into a system that is pleasant and dependable for daily use on the Pixel.

### High-level scope

- Measure boot time, voice latency, rendering latency, memory, CPU, storage, and battery behavior.
- Test weak network, no network, low battery, thermal pressure, background restrictions, and radio transitions.
- Test call audio, microphone, speaker, Bluetooth, sensors, camera, and notifications on real hardware.
- Test long-running agent sessions and repeated generated-screen transitions.
- Test crash recovery and service restarts.
- Test accessibility, readability, touch targets, and voice fallback.
- Define performance budgets and reliability targets.

### Deliverables

- Performance baseline.
- Reliability and soak-test reports.
- Hardware validation report.
- Battery and thermal profile.
- Usability findings and remediation backlog.

### Exit criteria

The system meets agreed performance and reliability thresholds for controlled daily use on the target Pixel.

---

## Phase 14 — Update, release, and long-term maintenance system

### Objective

Create the operational foundation required to maintain Phosphor securely after the initial build.

### High-level scope

- Establish Phosphor release channels and versioning.
- Build signed factory images, OTA packages, and recovery packages.
- Implement or adapt an updater using Phosphor’s own signing keys and endpoints.
- Define incremental updates, rollback, rollback protection, and failed-update recovery.
- Maintain GrapheneOS/AOSP, Pixel firmware, kernel, vendor, and security updates.
- Protect release infrastructure and signing keys.
- Publish build provenance, release notes, and verification metadata.
- Define development, beta, and stable channels.

### Deliverables

- Release engineering process.
- Update server or controlled USB-update process.
- Key-management and release-signing runbook.
- Rollback and recovery procedure.
- Security-update maintenance schedule.
- Reproducible-build and artifact-verification process.

### Exit criteria

Phosphor can receive authenticated updates and recover safely from failed or rejected updates without depending on official GrapheneOS update infrastructure.

---

## Phase 15 — Pilot deployment and iterative expansion

### Objective

Use Phosphor as a real phone in controlled stages and evolve it based on observed behavior without losing architectural discipline.

### High-level scope

- Define pilot users and deployment boundaries.
- Begin with a development Pixel and controlled data.
- Gradually enable communications, personal data, settings, and broader hardware capabilities.
- Log failures and user friction without hiding uncertainty.
- Prioritize improvements by real-world usefulness and safety.
- Continue platform, agent, model, UI, and hardware integration.
- Maintain a clear distinction between experimental, beta, and dependable functionality.

### Deliverables

- Pilot-readiness checklist.
- Daily-use test protocol.
- Feedback and incident process.
- Prioritized evolution roadmap.
- Stable milestone definitions.

### Exit criteria

Phosphor is useful as an integrated personal phone environment, and the project has a sustainable process for continued development.

---

# 6. Cross-phase workstreams

The following concerns run across multiple phases rather than belonging to only one phase.

## 6.1 Source and dependency management

Track upstream GrapheneOS/AOSP revisions, Pixel vendor files, kernel changes, Phosphor repositories, third-party libraries, licenses, and reproducibility metadata.

## 6.2 Signing and key custody

Keep development keys separate from release keys. Never place private release keys in source control, ordinary build directories, chat, logs, or unencrypted backups.

## 6.3 Testing

Maintain unit, integration, emulator, device, UI, voice, communications, security, performance, recovery, and update tests. Every capability should have both success and failure-path coverage.

## 6.4 Observability

Use structured logs, event traces, crash reports, action receipts, and device diagnostics. Observability must not leak message contents, credentials, private audio, or signing material.

## 6.5 Documentation

Every major platform change should have an architecture decision, implementation notes, verification evidence, and rollback/recovery guidance.

## 6.6 Prototype migration

Any temporary Termux, browser, Python, remote-server, or external-model implementation must have a documented purpose and a planned native replacement or an explicit decision to retain it.

## 6.7 User authority and consequential actions

The system should avoid unnecessary friction, but calls, messages, purchases, deletion, authentication, account changes, and other consequential actions need a clear delegation model. The goal is not constant permission prompts; the goal is predictable authority designed around the user’s intent.

---

# 7. Milestone sequence

The following milestones provide a simpler progress view across the phases:

### Milestone A — Feasibility confirmed

The host, target device, source, licensing assumptions, vendor requirements, and signing model are verified.

### Milestone B — Baseline custom build

An unmodified or minimally modified GrapheneOS-derived `akita` build is produced and documented.

### Milestone C — Safe development flash

A custom development image is flashed and booted on the Pixel through USB, with recovery documented.

### Milestone D — Native Phosphor foundation

The custom image contains a native Phosphor service foundation and diagnostics.

### Milestone E — Phosphor surface

Phosphor is the primary shell and can render agent-generated HTML/JavaScript screens.

### Milestone F — Voice loop

Speech becomes the primary input path from microphone through STT, agent processing, and generated screen output.

### Milestone G — First integrated action

A spoken request such as “Call Mom” resolves a contact and starts a real call through native system integration, with the appropriate generated interface.

### Milestone H — Communications teammate

Incoming messages are surfaced, classified, answered when authorized, and escalated when user input is required.

### Milestone I — System coordinator

Phosphor controls core settings, applications, notifications, and hardware capabilities through one agent-native interaction model.

### Milestone J — Secure daily-use pilot

The system is updated, recovered, tested, and used as a controlled daily phone environment.

---

# 8. Immediate next planning step

Before implementation begins, create the detailed document for **Phase 1 — Build-host and device readiness**. It should be read-only at first and cover:

- Host hardware and operating-system audit.
- Available storage and memory.
- Build dependency status.
- USB, `adb`, and `fastboot` capability.
- Pixel identity and bootloader state.
- Current backup/recovery position.
- Source-sync requirements.
- Risks, blockers, and evidence.

This next document should not unlock, wipe, flash, or otherwise modify the Pixel. It should establish whether the development environment is ready for Phase 2.