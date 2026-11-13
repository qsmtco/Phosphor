# P5-S2 Phase S2-A — SELinux policy plan (author round)

**Phase:** 5 · **Spec ID:** P5-S2 · **Phase:** S2-A (author) · **Author:** Coder, 2026-11-12
**Deliverable:** this file — byte-exact content for all 12 S2-A artifacts, for transcription by the Supervisor (S2-B) into the tree and the Phosphor-platform working repo.
**Authority chain:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` rev 4 (CLOSED) → `docs/specs/P5-S2-selinux-foundation.md` rev 1 + pending errata (seapp private path; C15 wording) → `docs/specs/P5-S2-PREFLIGHT-PROBE.md` (15/15 citations verified; BUG #1 LOW) → `docs/specs/P5-S2-PHASE-INSTRUCTIONS.md` (S2-A scope + 7 standing rulings) → this plan.
**Executed-evidence rule (standing):** every expected output below is labelled either **[EXECUTED — tree]** (run by Coder via read_file/search_files against `/home/cptjaqx/projects/grapheneos-2026091900`, which Coder's seat can read for verification but cannot write), **[QUOTED FROM SOURCE — not executed]** (taken verbatim from a file body in the authority chain), or **[EXPECT AT BUILD]** (cannot be known until the Supervisor's build). Nothing is invented.
**Word marker:** the delegation carried **please write** (author round). No `please proceed` execution marker is claimed.

---

## 0. Global execution rules (bind every S2-B step)

1. **Stop-and-report on any mismatch.** A FAILED state is a legitimate, auditable outcome. Never improvise, never "make it work", never edit a file a step did not name.
2. **Paste command + exact output** for every step into the evidence bundle. Expected strings are the pass condition; a near-miss is a fail.
3. **Payload flow is the only flow.** Policy files are committed in `SRCREPO` (`/home/cptjaqx/projects/Phosphor-platform`), the mirror (`/home/cptjaqx/projects/Phosphor-platform.git`) is refreshed, then `repo sync packages/phosphor` brings `TREE/packages/phosphor` to the new commit. **Direct edits inside `TREE/packages/phosphor` are FORBIDDEN** — they show as dirty payload and every later sync collides.
4. **Exactly one tree-direct edit:** the AID header `system/core/libcutils/include/private/android_filesystem_config.h` (+4 lines). Zero edits under `system/sepolicy/**`. No `.rc`, no daemon logic, no manifest changes. No device operation.
5. **Every block runs under `bash`.** `grep -c`/`wc -l`/`rg -c` over a directory is evidence only with a presence guard: `test -d <dir> || { echo 'TREE MISSING'; exit 1; }`, and grep's own exit status is captured (`0` matches, `1` none, `2` is a hard stop).
6. **`rg -n 'pattern' dir` prints 0 lines when dir is absent.** The tree is proven present before any count is trusted (same shape as S1's global rule 8).

Absolute paths used throughout:

```
TREE    = /home/cptjaqx/projects/grapheneos-2026091900
SRCREPO = /home/cptjaqx/projects/Phosphor-platform
MIRROR  = /home/cptjaqx/projects/Phosphor-platform.git
AIDHDR  = system/core/libcutils/include/private/android_filesystem_config.h   (relative to TREE)
```

---

## 1. `sepolicy/public/property.te` (SRCREPO path `packages/phosphor/sepolicy/public/property.te`)

Byte-exact content. Provenance: §3.1 of the spec, verbatim **[QUOTED FROM SOURCE]**. The spec's tree state note says `packages/phosphor/sepolicy/{public,private}` exist with READMEs only (preflight header, line 6), so this is a new file in an existing directory.

```
# Boot decision, written by keygate only, read by init (agentd gating) and by every app that
# must decide whether to be Phosphor's surface. exact bool: AOSP ships this shape for
# sys.boot_completed (C13); C8/C9 make the *value* unpoliceable, which is why §6.5's one-way
# claim rests on access, not on a value check.
system_public_prop(phosphor_safeboot_prop)

# The set-only safe-boot latch. Declared as its OWN type so that the host's documented
# escape hatch (setprop persist.phosphor.safeboot 1 over adb, while the device is otherwise
# healthy) is achievable at all -- residual R-2: without this declaration the latch inherits
# default_prop, and C7's neverallow makes it unwritable by every non-init domain, including
# the adb shell, so §6.5:307's promise could not be kept.
system_public_prop(phosphor_safeboot_latch_prop)
```

Provenance: §3.1 of the spec, verbatim **[QUOTED FROM SOURCE]**.

## 2. `sepolicy/public/property_contexts`

```
sys.phosphor.safeboot              u:object_r:phosphor_safeboot_prop:s0         exact bool
persist.phosphor.safeboot          u:object_r:phosphor_safeboot_latch_prop:s0   exact string
persist.phosphor.agent_state       u:object_r:phosphor_safeboot_latch_prop:s0   exact string
```

Provenance: §3.1, verbatim **[QUOTED FROM SOURCE]**. Note the alignment spacing is part of the spec's byte content; reproduce exactly (three spaces before `u:object_r`, then `exact bool`/`exact string` after the context column).

## 3. `sepolicy/public/phosphor_keygate.te`

```
type phosphor_keygate, domain;
type phosphor_keygate_exec, exec_type, file_type, system_file_type;
init_daemon_domain(phosphor_keygate)

# Writes exactly one property, and only that one.
set_prop(phosphor_keygate, phosphor_safeboot_prop)
# Reads the triggers: the host-set immutable ro.boot.* (already readable as boot_prop-derived
# context; granted explicitly only if C1's context proves insufficient) and the latch.
get_prop(phosphor_keygate, phosphor_safeboot_latch_prop)

# [S2-A clarification, not in the spec's §3.2 block] The spec's §3.2 says "and the
# subtraction-form neverallow from §8 (see 3.4)" — that neverallow is the same line that
# appears in the neverallow set below, so it is materialized here rather than left as
# prose. Form per C10 (property.te:193-196, :310-321): { system_prop -phosphor_safeboot_prop }.
neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;
```

Provenance: §3.2 + §3.4 (subtraction neverallow) **[QUOTED FROM SOURCE]**, plus the explicit S2-A clarification that the subtraction neverallow is materialized in this file rather than left as a cross-file prose reference.

## 4. `sepolicy/public/phosphor_agentd.te`

```
type phosphor_agentd, domain;
type phosphor_agentd_exec, exec_type, file_type, system_file_type;
init_daemon_domain(phosphor_agentd)

get_prop(phosphor_agentd, phosphor_safeboot_prop)       # to log/verify its own start condition
allow phosphor_agentd phosphor_risk_policy_file:file r_file_perms;
allow phosphor_agentd phosphor_agentd_data_file:dir create_dir_perms;
allow phosphor_agentd phosphor_agentd_data_file:{ file lnk_file } create_file_perms;
```

Provenance: §3.2, verbatim **[QUOTED FROM SOURCE]**.

## 5. `sepolicy/public/phosphor_broker.te` and `sepolicy/public/phosphor_shell.te`

`phosphor_broker.te`:

```
type phosphor_broker, domain;
app_domain(phosphor_broker)

# §6.3: broker gets read on the policy artifact; write is denied by the neverallow set.
allow phosphor_broker phosphor_risk_policy_file:file r_file_perms;
```

`phosphor_shell.te`:

```
type phosphor_shell, domain;
app_domain(phosphor_shell)

# §6.3: "The shell has no read access at all" — no allow line for phosphor_risk_policy_file.
```

Provenance: §3.2, last paragraph **[QUOTED FROM SOURCE]**. Note: `app_domain()` expands to attribute + neverallows (preflight §8-8, te_macros:185); it does not declare the type, hence the explicit `type X, domain;` first — the trio `type` + `app_domain` + `seapp_contexts` row is the correct shape (preflight 8-7/8-8).

## 6. `sepolicy/public/file.te`

```
type phosphor_risk_policy_file, file_type, system_file_type;
type phosphor_agentd_data_file, file_type, data_file_type;
```

Provenance: §3.5 **[QUOTED FROM SOURCE]**. (The four-file-type inventory: `phosphor_risk_policy_file`, `phosphor_agentd_data_file`, plus the two `_exec` types declared inside the domain files, artifact 3/4.)

## 7. `sepolicy/public/file_contexts`

```
/system/etc/phosphor(/.*)?                    u:object_r:phosphor_risk_policy_file:s0
/system/bin/phosphor-agentd                   u:object_r:phosphor_agentd_exec:s0
/system/bin/phosphor-keygate                  u:object_r:phosphor_keygate_exec:s0
/data/misc/phosphor(/.*)?                     u:object_r:phosphor_agentd_data_file:s0
```

Provenance: §3.5, verbatim **[QUOTED FROM SOURCE]**.

## 8. `sepolicy/private/seapp_contexts`

```
user=_app isPrivApp=true seinfo=platform name=com.phosphor.shell   domain=phosphor_shell type=privapp_data_file levelFrom=user
user=_app isPrivApp=true seinfo=platform name=com.phosphor.broker  domain=phosphor_broker type=privapp_data_file levelFrom=user
```

Provenance: §3.5 rows **[QUOTED FROM SOURCE]**, with the placement corrected to `private/` per standing ruling 1 (spec §3.5 says `public/seapp_contexts`; the spec's own pending errata ① records this correction; `seapp_contexts` is private-only in this tree — preflight §8-7). Row shape to copy at build: `vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts` **[EXPECT AT BUILD]**.

## 9. `sepolicy/private/app.te`

```
# Phase 5 rule required by §10.2 V-2: an app-layer read of sys.phosphor.safeboot is not implied
# by system_public_prop (C2/C5) and needs an explicit grant, precedent at app.te:40 (C3).
get_prop(appdomain, phosphor_safeboot_prop)

# R-2's *writer* (the half the type declaration alone does NOT provide). The documented recovery
# escape hatch is the host, over adb: `adb shell setprop persist.phosphor.safeboot 1` (§6.5,
# S8 D3). The adb shell runs in the `shell` domain, so without this grant the latch type exists
# but NO non-init domain may set it -- C7's default_prop neverallow would still deny it, and
# A5/A7 would pass textually while the drill (S3 A1, S8 D3/D7) is denied at runtime.
# Scope is deliberately minimal: ONE domain, ONE property, and `set` only (set_prop expands to
# property_service set -- C8: no value dimension, so "absent->1 only, 0 ignored" stays a
# keygate/S8 binary-level rule, not a claim about this rule).
set_prop(shell, phosphor_safeboot_latch_prop)
```

Provenance: §3.3, verbatim **[QUOTED FROM SOURCE]**. This is a Phosphor-local `app.te` — do NOT edit `system/sepolicy/private/app.te` (the `appdomain` attribute makes the local file sufficient; zero third-party surface).

## 10. `sepolicy/public/phosphor_neverallows.te`

```
# --- keygate: it decides, and is denied everything else (arch §8 lines 416-417, NEW-3) ---
neverallow phosphor_keygate phosphor_agentd_exec:file *;
neverallow phosphor_keygate phosphor_agentd_data_file:file *;

# keygate's property access as a subtraction, in the in-tree form (C10; arch §8 line 417):
# it may set nothing except the boot decision.
neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;

# keygate holds no binder, no network, no device node (arch §8 line 418). Enumerated
# per standing ruling 2 (preflight §8-3: zero tree precedent for `self:binder *`;
# enumerated form matches in-tree binder neverallows, e.g. private/installd.te:240,
# netd.te:205). S2-B amendment (audit BUG #5, PM-supervisor ruling): the binder class
# is exactly { impersonate call set_context_mgr transfer } (access_vectors:520-526,
# executed) and keygate needs none, so all four are named — denies strictly more than
# { call transfer } and closes the exhaustive-deny gap.
neverallow phosphor_keygate self:binder { impersonate call set_context_mgr transfer };
neverallow phosphor_keygate self:tcp_socket *;
neverallow phosphor_keygate self:udp_socket *;

# --- agentd: capability-adjacent device nodes are unreachable (arch §8 line 412; enumerated
# from akita policy per standing ruling 3; categories named >= 4: telephony/radio, camera,
# location/GNSS, modem userdata; radio-netlink socket type is a separate [EXPECT AT BUILD]
# line — preflight §8-2) ---
neverallow phosphor_agentd radio_device:file *;
neverallow phosphor_agentd camera_device:file *;
neverallow phosphor_agentd vendor_gnss_device:file *;
neverallow phosphor_agentd modem_userdata_block_device:file *;
# S2-B pre-resolution (audit BUG #2, executed): no radio-specific netlink class exists
# (rg netlink.*radio -> zero hits; radio.te uses only net_domain(radio)). The precedented
# generic type is netlink_generic_socket — used by hal_telephony.te:33-35 exactly for the
# telephony netlink path agentd must not reach. Resolved rule (no [EXPECT AT BUILD] remains):
neverallow phosphor_agentd netlink_generic_socket:socket_class_set *;

# --- agentd: exactly one binder target (arch §8 line 413: broker only, nothing to the shell) ---
neverallow phosphor_agentd { domain -phosphor_broker -self }:binder call;

# --- the safe-boot latch: exactly ONE non-init writer (R-2 discharged by enforcement, not
# by observation). §3.3 grants set_prop(shell, phosphor_safeboot_latch_prop); this line
# denies every other domain, init behaving as init. Without it "exactly one writer" is merely
# true today and quietly becomes false the next time someone grants anything near it.
neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set;

# --- shell: broker or nothing (arch §8 line 414: no binder to capability services directly) ---
neverallow phosphor_shell { domain -phosphor_broker -self }:binder call;

# --- the policy artifact is read-only to every Phosphor domain (NEW-4; arch §8 line 415) ---
neverallow { phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate } \
    phosphor_risk_policy_file:file { write append create rename setattr unlink };
```

Provenance: §3.4 set with standing rulings 2 and 3 applied **[QUOTED FROM SOURCE + rulings]**. Every rule above carries the architecture §8 citation (file:line of `docs/PHASE-4-PLATFORM-ARCHITECTURE.md`, the authority for this policy): §8 line 412 = agentd device-node denial; §8 line 413 = agentd binder = broker only; §8 line 414 = shell binder = broker or nothing; §8 line 415 = policy artifact typed + write-banned; §8 lines 416–417 = keygate file + property denials; §8 line 418 = keygate binder/network denial; §6.5 (line 285, NEW-6) = the latch neverallow's "exactly one writer" constraint. The `mmap_exec_file_perms` exclusion is honoured (NEW-7/C11: zero hits for `mmap_exec_file_perms` anywhere in `system/sepolicy` — preflight C11).

## 11. AID header diff (tree-direct, 4 lines)

File: `system/core/libcutils/include/private/android_filesystem_config.h` (C15; canonical hit of 3 — preflight BUG #1).

Anchor: the OEM range is at lines 171–172 (`AID_OEM_RESERVED_START 2900` / `AID_OEM_RESERVED_END 2999` — preflight §8-4). The four AID lines are inserted after `AID_OEM_RESERVED_END` inside the OEM range, with a blank line before the block, matching AOSP's own AID-block formatting.

The four added lines (this is the exact, fixed content; the numbers 2950–2953 are the confirmed-free AIDs of §3.6, preflight §8-4):

```
#define AID_PHOSPHOR_KEYGATE  2950
#define AID_PHOSPHOR_AGENTD   2951
#define AID_PHOSPHOR_BROKER   2952
#define AID_PHOSPHOR_SHELL    2953
```

[EXPECT AT BUILD] This is a 4-line *addition*, not a `git apply`-able unified diff: the surrounding context lines were not read from the real file by Coder (no executed read of `android_filesystem_config.h` in this round), so a hunk header with invented context would violate the executed-evidence rule. The Supervisor re-reads the file, re-anchors after `AID_OEM_RESERVED_END`, inserts the block above with a blank line before and after, and records the resulting line numbers. Post-edit gates: `grep -c 'AID_PHOSPHOR' $AIDHDR` → 4, and `rg -n '2950|2951|2952|2953' system/core/` → only the 4 new lines (belt-and-braces per preflight §8-4; the header-level check already passed there).

## 12. Commit message + mirror-refresh + repo sync sequence

### 12.1 Commit message (Phosphor-platform, on `main`)

```
sepolicy: Phase 5 S2 SELinux foundation (4 domains, 3 property types, 4 file types)

Implements P5-S2 (SELinux foundation): the four Phosphor domains
(phosphor_keygate, phosphor_agentd, phosphor_broker, phosphor_shell),
the two property types (phosphor_safeboot_prop, phosphor_safeboot_latch_prop)
with their contexts, the get_prop(appdomain, phosphor_safeboot_prop) rule
(§10.2 V-2) and set_prop(shell, phosphor_safeboot_latch_prop) writer (R-2),
the file types/contexts, the private seapp_contexts rows, and the
neverallow set from architecture §8 in compile-ready form (:file *;
keygate binder enumerated { call transfer }; agentd device nodes enumerated
from akita policy).

Payload only: no device operation, no .rc, no daemon logic. Build evidence
in docs/handoffs/P5-S2-POLICY-PLAN.md (this file, §12) and the S2-B evidence bundle.
```

### 12.2 Command sequence (S2-B, Supervisor)

```bash
# S2-B.1 — transcribe artifacts 1–10 into SRCREPO, verify byte-exactness
cd /home/cptjaqx/projects/Phosphor-platform
git status --porcelain          # expect: ?? packages/phosphor/sepolicy/... (new files only)
git add packages/phosphor/sepolicy
git commit -m "<12.1 message>"
NEW_HEAD=$(git rev-parse HEAD); echo "NEW_HEAD=$NEW_HEAD"   # record the 40-hex

# S2-B.2 — refresh the bare mirror. The mirror is a local bare clone of SRCREPO (S1
# created it with `git clone --bare SRCREPO MIRROR`), so its `origin` is SRCREPO:
# fetch, then fast-forward main to the fetched commit.
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git remote -v     # origin -> SRCREPO
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git fetch origin
test "$(git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse FETCH_HEAD)" = "$NEW_HEAD" || { echo 'FETCH_HEAD != NEW_HEAD — hard stop'; exit 1; }
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git update-ref refs/heads/main FETCH_HEAD
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse refs/heads/main   # == $NEW_HEAD

# S2-B.3 — sync the tree to the new commit
cd /home/cptjaqx/projects/grapheneos-2026091900
repo sync packages/phosphor
git -C packages/phosphor rev-parse HEAD            # == $NEW_HEAD
git -C packages/phosphor status --porcelain         # expect: (empty)

# S2-B.4 — the ONE tree-direct edit: AID header (artifact 11)
# apply the 4-line diff (re-anchor context from the real file first); then:
grep -c 'AID_PHOSPHOR' system/core/libcutils/include/private/android_filesystem_config.h   # -> 4
rg -n '2950|2951|2952|2953' system/core/   # expect: only the 4 new lines

# S2-B.5 — build gates (spec §5 A1)
m -j24 sepolicy_neverallows selinux_policy         # both exit 0

# S2-B.6 — A1..A10 evidence per spec §5
# (Every grep below carries a presence guard: test -d <dir> || { echo 'TREE MISSING'; exit 1; }
#  and grep's exit status is captured — 0 matches, 1 none, 2 is a hard stop. Global rule 5.)
# A1: rg -n 'phosphor_safeboot' out/target/product/akita/*/etc/selinux/*property_contexts
#     (record the actual filenames found — [EXPECT AT BUILD])
# A2: liveness negative test — remove ONE set_prop line, rebuild, confirm the expected
#     failure, restore. Done for BOTH set_prop(phosphor_keygate, phosphor_safeboot_prop)
#     and set_prop(shell, phosphor_safeboot_latch_prop).
# A3: every neverallow carries its architecture §8 file:line citation (see §10 provenance);
#     the §2 traceability table (C1–C15) is re-verified in the completion note.
# A4: rg -n 'mmap_exec_file_perms' packages/phosphor/sepolicy   -> empty
#     rg -c 'neverallow' packages/phosphor/sepolicy              -> matches declared count
# A5: rg -n 'phosphor_safeboot_latch_prop' out/.../selinux/*property_contexts -> 2 rows
#     rg -n 'set_prop\(shell, phosphor_safeboot_latch_prop\)' packages/phosphor/sepolicy/private/app.te
# A6: rg -n 'get_prop\(appdomain, phosphor_safeboot_prop\)' packages/phosphor/sepolicy/private/app.te
# A7: rg -n 'property_service set' packages/phosphor/sepolicy   -> exactly the declared set
# A8: rg -c 'type phosphor_.*, domain;' packages/phosphor/sepolicy   -> 4
# A9: repo status (expect: vendor/adevtool baseline + system/core 4-line + phosphor clean)
# A10: polarity audit — no Phosphor domain holds set on phosphor_safeboot_prop except keygate
```

FAILED states: any step's output deviating from EXPECTED → **STOP**, paste the output, do not improvise (e.g., if `repo sync` brings a different HEAD, do not force-update; if the mirror update-ref fails, do not re-init the mirror).

---

## COMPLETENESS template (one line per artifact)

- [ ] 1 `sepolicy/public/property.te` — 2 system_public_prop decls — transcribed byte-exact (§1)
- [ ] 2 `sepolicy/public/property_contexts` — 3 rows — transcribed byte-exact (§2)
- [ ] 3 `sepolicy/public/phosphor_keygate.te` — type/init_daemon_domain/set_prop/get_prop + subtraction neverallow (§3)
- [ ] 4 `sepolicy/public/phosphor_agentd.te` — type/init_daemon_domain/get_prop + 3 allows (§4)
- [ ] 5 `sepolicy/public/phosphor_broker.te` + `phosphor_shell.te` — app_domain + type; broker r_file_perms; shell nothing (§5)
- [ ] 6 `sepolicy/public/file.te` — 2 file types (§6)
- [ ] 7 `sepolicy/public/file_contexts` — 4 rows (§7)
- [ ] 8 `sepolicy/private/seapp_contexts` — 2 rows, private placement (ruling 1) (§8)
- [ ] 9 `sepolicy/private/app.te` — get_prop(appdomain, phosphor_safeboot_prop) + set_prop(shell, phosphor_safeboot_latch_prop) (§9)
- [ ] 10 `sepolicy/public/phosphor_neverallows.te` — full set, rulings 2–3 applied, §8 citations (§10); the radio-netlink line is resolved from the compiled policy before the neverallow audit (Related issue 2)
- [ ] 11 AID header — 4-line addition anchored after `AID_OEM_RESERVED_END`, fixed lines, context re-read from the real file at apply time (§11)
- [ ] 12 commit message + mirror/sync sequence (§12), executed in order S2-B.1 → S2-B.6

## Related issues

1. **seapp_contexts placement erratum (pending PM approval).** Spec §3.5 says `public/seapp_contexts`; this plan uses `private/` per ruling 1 (private-only in this tree). The erratum must be recorded against the spec before S2-C audit.
2. **Radio-netlink socket type [EXPECT AT BUILD].** Preflight §8-2: device-node types are concrete (`radio_device`, `camera_device`, `vendor_gnss_device`, `modem_userdata_block_device`); the netlink socket type name must be taken from the compiled policy at build. Artifact 10 carries the placeholder as a comment only — the final `.te` gets the real line, non-empty, before the neverallow audit.
3. **AID header context lines.** The 4 added lines are fixed; the surrounding context is [EXPECT AT BUILD] — the Supervisor re-reads the real file and inserts after `AID_OEM_RESERVED_END`, then records the resulting line numbers.
4. **BUG #1 (preflight, LOW).** C15's "exactly one non-prebuilt hit" is imprecise (3 hits; canonical = `include/private/`). The completion note must carry the corrected wording; no rule change.
5. **Spec §5 A1 target names.** `m -j24 sepolicy_neverallows selinux_policy` is the gate (preflight §8-1: `sepolicy_neverallows` is a Soong module, not a phony); exact compiled-context filenames are recorded at build.
6. **Spec §8 open item 5 (carried, gates S3 not S2):** whether `ro.boot.phosphor.safeboot` is readable by `phosphor_keygate` under its default `boot_prop`/`system_prop` context or needs an explicit `get_prop`. S2 does not write that rule; S3 records the outcome.
7. **Spec §8 open item 7:** confirm the `neverallow { domain -shell -init } …:property_service set` enumeration compiles in this tree; if `-init` proves unnecessary, drop the subtraction and record it — never drop the line.