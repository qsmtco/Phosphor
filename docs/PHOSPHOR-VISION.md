# Phosphor Vision and Project Direction

**Status:** Active north-star specification
**Owner:** Captain JAQ
**Project:** Phosphor
**Target device:** Google Pixel 8a (GKV4X)
**Target foundation:** GrapheneOS-derived operating system
**Development host:** Linux computer connected to the Pixel by USB

## The actual goal

Phosphor is not intended to be merely an Android application, a browser shell, a chatbot, or a Python service running inside a terminal emulator.

The goal is to build an **agent-native phone operating system**, based on GrapheneOS, in which the AI agent is the primary interface and a deeply integrated system coordinator. The user should be able to use the phone and the agent together as a team, without constantly switching between unrelated apps or fighting unnecessary boundaries.

The desired experience is:

> The user speaks naturally to Phosphor. Phosphor understands the intent, uses the appropriate system capability, and presents the result through one coherent interface.

Examples:

- “Call Mom.” Phosphor resolves the contact and starts the phone call.
- An incoming text arrives. Phosphor understands and classifies it.
- If the message is routine, harmless, and within the rules, Phosphor can answer it.
- If the message is ambiguous, sensitive, personal, or requires judgment, Phosphor alerts the user and asks for input.
- “Turn on Wi-Fi,” “set an alarm,” “show my appointments,” “open the camera,” or “send this photo” should be direct agent actions, not instructions for the user to manually navigate a maze of apps.
- Phone calls, messages, notifications, contacts, settings, media, sensors, and other device capabilities should be coordinated through the Phosphor experience.

## What Phosphor is not

Do not redirect this project into any of the following merely because they are easier:

- A normal Android app that calls the existing Phone or Messages app.
- A chatbot floating on top of GrapheneOS.
- A browser-based shell presented as the final product.
- A Termux-based runtime presented as the operating system.
- A Debian VM presented as the operating system.
- A collection of loosely connected apps with an AI front end.
- A simplified substitute chosen because the real project is difficult or lengthy.

Termux, the current Python runtime, local Whisper, the browser shell, the Rust bridge, and remote access tooling are prototype and bring-up material only. They may be useful for learning, experimentation, or migration, but they are not the intended final architecture.

## Intended architecture

The long-term architecture is approximately:

```text
User
  ↕
Phosphor system shell and agent interface
  ↕
Phosphor agent service / orchestration layer
  ↕
Android framework and system services
  ↕
Phone hardware, telephony, audio, sensors, storage, and applications
```

More concretely, Phosphor should become a set of integrated system components in a GrapheneOS-derived build:

1. **Phosphor system shell**
   - The primary home and interaction surface.
   - Voice, text, notifications, generated UI, status, and system actions in one coherent experience.
   - Responsible for presenting agent activity and user decisions.
   - Eventually replaces or substantially supersedes the ordinary launcher experience.

2. **Phosphor agent service**
   - A native/system-integrated service rather than a process hosted by Termux.
   - Maintains agent state, conversations, capability routing, and model communication.
   - Coordinates actions through defined platform interfaces.
   - Must know the device, current user, available capabilities, and current context accurately.

3. **Native capability integration**
   - Telephony and call control.
   - Contacts.
   - SMS/RCS or the applicable messaging interfaces.
   - Notifications and notification replies.
   - Audio input/output and voice interaction.
   - Settings and connectivity.
   - Camera and media.
   - Sensors, vibration, flashlight, NFC, clipboard, and other hardware.
   - Files and storage.
   - Calendar, alarms, and other user data where permitted.

4. **Phosphor policy and trust layer**
   - The agent should not be obstructed by pointless prompts for routine actions.
   - The user should retain control over consequential or sensitive actions.
   - Policies should be explicit, understandable, configurable, and lightweight.
   - The system must distinguish reading information, drafting, communicating externally, changing settings, deleting data, financial activity, authentication, and other consequential actions.
   - Safety must be implemented as part of the operating system integration, not as a chaotic permission prompt on every shell command.

5. **GrapheneOS foundation**
   - Preserve the existing secure foundation, device support, verified boot model, hardware support, and Android framework wherever possible.
   - Modify and extend the platform rather than rewriting the kernel, modem stack, bootloader, or every Android component.
   - Use the system image and platform services as the integration boundary.

## Development model

The Linux development computer is the build and control workstation. The Pixel is the target device.

```text
Linux development computer
        │ USB
        ▼
Pixel 8a in bootloader / fastboot or development mode
        ▼
Phosphor GrapheneOS-derived image
```

The intended workflow is:

1. Study the GrapheneOS/AOSP source, build system, device configuration, signing, and development workflow.
2. Keep the current phone available as a development/test device.
3. Build custom images on the Linux computer.
4. Verify artifacts, images, signatures, and hashes before flashing.
5. Transfer and flash images directly over USB.
6. Boot and test on the Pixel.
7. Collect logs and test results.
8. Iterate on the platform source.

Bootloader unlocking, development signing, image flashing, and data wipes must be treated as explicit device operations. Do not flash or wipe the phone without the user's clear approval for that specific operation.

## First real milestone

The first meaningful milestone is not another Termux feature. It is:

> Build and boot a GrapheneOS-derived Phosphor development image on the Pixel that presents Phosphor as the primary system shell.

After that, capabilities can be integrated incrementally:

1. System boot and Phosphor shell.
2. Agent service running as a platform component.
3. Voice and text interaction.
4. Contacts and call initiation.
5. Incoming notification and message awareness.
6. User-reviewed or policy-approved message responses.
7. Settings and connectivity control.
8. Audio, sensors, camera, NFC, and other hardware capabilities.
9. Replacement or absorption of more system-app experiences.
10. Hardening, signing, recovery, update, rollback, and daily-use reliability.

## Current prototype context

The existing Phosphor work is valuable as experimental material but must not be mistaken for the final architecture. It currently includes or has included:

- A copied DragonCakes-derived Python agent runtime.
- A Python HTTP runtime.
- A browser-based shell.
- Local Whisper transcription and an experimental remote transcription path.
- A Rust hardware bridge.
- Termux on GrapheneOS.
- Termux:API and Termux:Boot.
- Tailscale and SSH for remote development access.
- A workspace directory on the Pixel.

These components helped prove agent behavior, generated UI, voice input, hardware calls, and deployment mechanics. They are not requirements for the final Phosphor operating system. Do not keep adding infrastructure around them just to preserve the prototype shape.

DragonCakes and its Telegram runtime remain separate projects. Eagle Dispatch remains strictly isolated and must not be modified, touched, pushed to, or used as a writable source. Code may be studied or copied only under the previously agreed isolation rules.

## Design principles

- Build the project Captain actually chose, not the easiest adjacent project.
- Investigate deeply before changing code or flashing a device.
- Prefer platform integration over app-to-app workarounds.
- Preserve GrapheneOS security properties where possible.
- Make the agent capable and direct in normal use.
- Avoid unnecessary components, daemons, emulators, remote tunnels, and installation steps.
- Do not confuse a prototype workaround with the target architecture.
- Do not claim an operation succeeded without verifying the real result.
- Keep the system understandable: identify what is required, temporary, optional, or removable.
- Treat the phone as the product, not merely as a host for a remote server.
- Take as much time as the project needs; difficulty and duration are not reasons to redirect it.

## Communication rule for future work

When the project is difficult, explain the engineering reality and continue toward the chosen goal. Do not talk the user out of the goal, substitute a smaller project, or use convenience as an argument for changing direction.

If a decision genuinely affects architecture, present the tradeoff and ask. If the intended direction is already clear, follow it.

## Build, signing, flashing, and feasibility findings

A research review of the official GrapheneOS build documentation, GrapheneOS CLI installation documentation, GrapheneOS source documentation, Android Verified Boot documentation, and GrapheneOS licensing/FAQ material confirms that the Phosphor operating-system project is technically viable.

There is no fundamental Google signing or licensing barrier that prevents us from building and flashing a GrapheneOS-derived Phosphor image onto the Pixel 8a. The relevant term for the concern about a "valid signature token" is the Android Verified Boot (AVB) key and the broader set of Android release-signing keys.

We do not need Google's private signing keys. The intended process is:

1. Fork and build the GrapheneOS source for the Pixel 8a, whose device codename is `akita`.
2. Modify the platform, framework, system services, system shell, and other components needed by Phosphor.
3. Generate and securely retain Phosphor's own release-signing keys and AVB key.
4. Build and sign Phosphor images with those keys.
5. Flash the images over USB while the development device bootloader is unlocked.
6. Install/configure the Phosphor AVB public key as the device's custom verified-boot root of trust.
7. Relock the bootloader only when the build and key chain are ready for a secured development/release device.

### Development and release bootloader modes

During active development, the bootloader should remain unlocked so images can be rebuilt and flashed repeatedly. This is efficient, but the device displays an unlocked/custom-OS warning and does not provide the full locked-device verified-boot guarantees.

For a release-like Phosphor device, the bootloader can be relocked after the device trusts Phosphor's AVB public key and the installed partitions are signed correctly. Pixel devices support a user-provided custom AVB key. A locked device running an OS signed by that key may show the standard custom-OS warning, normally a yellow screen, while still using verified boot and rollback protection.

Unlocking or relocking the bootloader is destructive: both transitions wipe user data. No unlock, relock, wipe, or flash operation may be performed without explicit approval for that specific operation.

### Google, GrapheneOS, AOSP, and proprietary components

GrapheneOS is an open-source project built largely from AOSP with its own open-source platform modifications, forks, and components. Its source and build systems support custom builds. Google does not need to authorize a private GrapheneOS-derived build for it to boot on a Pixel with its own AVB trust root.

Google-related components are a separate issue. Android framework and AOSP system services are available to build upon. Some Pixel firmware, vendor binaries, drivers, and hardware components remain proprietary and signed by Google; the build process uses the required device-specific components rather than replacing every one of them. GrapheneOS documents an `adevtool` workflow for preparing Pixel vendor files.

Google Play services and Google Play Store are not part of the open-source GrapheneOS base. GrapheneOS provides a compatibility layer for installing official Play components as sandboxed applications. Phosphor can decide later whether to retain that model, make those components optional, or provide another service design. Their absence does not prevent the Phosphor operating system from booting.

### Consequences of Phosphor's own keys

A self-signed Phosphor build will not be an official GrapheneOS release. We would therefore need to operate our own update and release pipeline. The official GrapheneOS updater must not be used with images signed by different keys; it would reject them and repeatedly fetch incompatible official updates unless disabled or replaced with a Phosphor update configuration.

We would need to maintain and protect, as applicable:

- Android release/platform signing keys.
- APK signing keys for privileged system components.
- The AVB verified-boot key.
- Factory-image and update-package signing metadata.
- Any separate APEX or independently updated component keys required by the final design.

These keys must be generated once, protected with strong passphrases, backed up securely, and reused. Changing them later can require reflashing factory images and wiping the device. Phosphor would also be responsible for rebuilding and shipping security updates.

Some applications may behave differently because they check Google Play Integrity, hardcode Google or GrapheneOS identities, or expect Google services. That is a compatibility concern, not a boot or build blocker. GrapheneOS Auditor would not automatically identify a self-signed Phosphor build as an official GrapheneOS build.

### Actual engineering constraints

The real barriers are engineering scope and maintenance, not permission to flash the phone:

- The complete GrapheneOS build requires a supported x86-64 Linux host, substantial storage, and substantial memory. Current GrapheneOS documentation lists at least 32 GiB of RAM, roughly 136 GiB or more for a standard source sync, and 100 GiB or more additional free storage for a typical full build.
- Android framework, telephony, messaging, notification, permission, audio, settings, and system UI work spans many layers.
- The Phosphor agent must eventually be implemented as a native/system-integrated Android platform component rather than a Python process hosted by Termux.
- Proprietary firmware and vendor components remain boundaries around specific hardware functions, although they do not prevent replacing the Android system behavior around them.
- Phosphor needs its own secure signing-key storage, update server or USB update workflow, rollback strategy, and ongoing security-patch process.
- Optional Google service compatibility must be tested rather than assumed for every application.

### Feasibility conclusion

The project can follow this path:

```text
GrapheneOS source
        ↓
Phosphor platform modifications
        ↓
Phosphor release and AVB keys
        ↓
Signed Pixel 8a (`akita`) images
        ↓ USB
Unlocked development Pixel
        ↓
Eventually: relocked Pixel using Phosphor's custom AVB key
```

The first technical investigation should be read-only: audit the Linux build host, verify available storage/RAM/toolchain, inspect the GrapheneOS source/build targets, and map the signing and flashing workflow. Before modifying the phone, it is prudent to prove the complete build/sign/flash chain with an unmodified or minimally modified development build. This is a validation step, not a change in the Phosphor goal.

## Primary interaction model: voice and generated screens

Speech is the primary way to use Phosphor. The user speaks naturally to the system, and speech-to-text (STT) converts the voice input into the agent's working input. STT may initially be local or remote depending on the selected implementation, but voice interaction is the intended default rather than a secondary feature.

The agent's output is not limited to a text reply. Phosphor's agent renders its answers and task interfaces as HTML and JavaScript so it can present the buttons, controls, forms, status displays, confirmations, media, and other interactions required by the current situation.

The phone's primary user-interface surface is therefore an HTML rendering surface controlled by Phosphor. The agent designs the active screen in real time according to the user's request and the current device state. A request to call Mom, an incoming message, a settings change, a camera task, or another operation may each produce a different contextual interface with exactly the controls needed at that moment.

This is a voice-first, agent-designed interface—not a conventional chatbot with a fixed screen and a collection of manually navigated apps. The generated HTML/JavaScript screen is the final presentation layer through which the user sees and operates the system. It must be integrated into the Phosphor system shell and designed with the necessary platform capabilities, lifecycle, permissions, security, and hardware access to be a real operating-system surface rather than an isolated browser page.

## One-sentence definition

**Phosphor is a GrapheneOS-based, voice-first, agent-native phone operating system whose agent designs and renders the active HTML/JavaScript interface in real time, allowing Captain JAQ to use the Pixel as a coordinated team member—calling, messaging, managing settings, using hardware, and handling everyday phone tasks through one deeply integrated interface.**
