# P5-S3 PREFLIGHT PROBE — spec-vs-tree drift (Debugger, 2026-11-14)

**Scope:** read-only verification of P5-S3-keygate-service.md (rev 1) implicit claims against
`/home/cptjaqx/projects/grapheneos-2026091900` (payload `8adacb5`, S2 closed; repo `ba140ca`).
**Method:** adversarialDebugger.md sections applied to the *spec's assumptions*, not to code
(there is no S3 code yet — this is a pre-build spec audit). Compiled conf cited where stronger
than source: `out/soong/.intermediates/system/sepolicy/system_ext_sepolicy.conf/android_common/
akita/system_ext_sepolicy.conf`, sha `01738c13…` (the exact S2-verified artifact).

**Verdict up front: the spec is NOT buildable as written.** Two CRITICAL drift findings —
the `.rc` user line cannot resolve (BUG #1) and the `on late-init` trigger reads `persist.*`
before it exists, inverting the decision table on every normal boot (BUG #2). The probe's own
T1 premise is refuted (BUG #4): **no** property_contexts row or get_prop grant is needed for
`ro.boot.phosphor.safeboot`. Bug numbers are probe-local (PF-BUG #N); the S2 audit's #1–#11
are a different series.

---

## BUG #1 — CRITICAL — `user phosphor_keygate` cannot resolve; the verbatim §3.1 `.rc` is invalid

**Assumption violated:** spec §2.4/:96-98 and §3.1 say `user phosphor_keygate` /
`group phosphor_keygate`; the probe task asserted "sdv precedent at
`device/google/sdv/sdv_core_base/sdv.agents.rc:124` uses `user sdv_sd_agent`".

**Attack vector (name resolution, statically proven):**

1. S2's `config.fs` declares partition-prefixed AIDs:
   `packages/phosphor/config.fs` — `[AID_SYSTEM_EXT_PHOSPHOR_KEYGATE] value: 7520` (plus
   7521/7522/7523). Build generates `passwd_gen_system_ext` with **prefixed** names —
   `out/soong/.intermediates/build/make/tools/fs_config/passwd_gen_system_ext/gen/passwd`:
   ```
   system_ext_phosphor_keygate::7520:7520::/:/bin/sh
   system_ext_phosphor_agentd::7521:7521::/:/bin/sh
   system_ext_phosphor_broker::7522:7522::/:/bin/sh
   system_ext_phosphor_shell::7523:7523::/:/bin/sh
   ```
   `passwd_gen_system/gen/passwd` is empty (tree-normal; matches the S2 audit's 0-byte note).
2. Runtime `getpwnam` reads five passwd files; the system_ext file **requires the partition
   prefix** on every line: `bionic/libc/bionic/grp_pwd.cpp:59-64`
   (`{"/system_ext/etc/passwd", "system_ext_"}`), enforced in
   `bionic/libc/bionic/grp_pwd_file.cpp:274-281` — lines without `system_ext_` are skipped with
   a libc error log.
3. `FindByName` exact-matches the **full** line name (`grp_pwd_file.cpp:301-313`): the lookup
   name must equal `system_ext_phosphor_keygate`; `phosphor_keygate` does not match.
4. `getpwnam_internal` order (`grp_pwd.cpp:558-573`): compiled-in `android_ids` table → the
   five passwd files → `oem_` name form → app-id form. No phosphor entry exists in the
   compiled table: `grep -c PHOSPHOR system/core/libcutils/include/private/android_filesystem_config.h`
   → **0** (S2 deliberately chose config.fs over the header route, per config.fs:2-4).
5. Therefore `DecodeUid("phosphor_keygate")` (`system/core/init/util.cpp:76-79`) fails, and
   init's service parser rejects the service block.

**The cited precedent is a false one.** `sdv.agents.rc:124 user sdv_sd_agent` resolves because
`AID_SDV_SD_AGENT 1099` is **hardcoded in the platform header**
(`android_filesystem_config.h:154`), which `find_android_id_info` matches — their prefixed
`config.fs` entries (`sdv_core_base/config.fs:18-42`, `AID_SYSTEM_EXT_SDV_VPM` …) are a
*separate* set of users used elsewhere. The genuine prefixed precedent in the same file is
`sdv.agents.rc:25 user system_ext_sdv_sbr` (and :36/:67/:86).

**Build-time gate (will catch this):** `copy-init-script-file-checked`
(`build/make/core/definitions.mk:3137-3168`) runs `host_init_verifier` with all five partitions'
passwd files (`-p`, :3156-3160) and validates `user` lines (`system/core/init/check_builtins.cpp:78`
→ `DecodeUid`). On a normal akita build the `.rc` **fails the build** with an unresolved user.
(Under `TARGET_BUILD_UNBUNDLED` or darwin the check is skipped — do not rely on that.)

**Fix:** §3.1/§2.4 change to `user system_ext_phosphor_keygate` / `group system_ext_phosphor_keygate`.
UID 7520 is irrelevant to the SELinux domain (init_daemon_domain transition is exec-based,
conf:97597-97621), so **no S2 sepolicy change** is needed.

---

## BUG #2 — CRITICAL — `on late-init` runs before `load_persist_props`: T2 misreads on every boot, normal boots read as safe

**Assumption violated:** §1/:15 "started `on late-init`" + §2.1 decision table assume keygate's
reads see real trigger values; §3.1/:105 flagged this as `[VERIFY AT BUILD]`; §3.1's primary
resolution (:109) asserts late-init works. The tree now answers that VERIFY statically — and
the answer is **no**.

**Execution-order evidence (second-stage init):**

1. `LoadBootScripts` parses **all** rc roots before anything executes:
   `system/core/init/init.cpp:1208` → `:347-369` (`/system/etc/init/hw/init.rc`, :353
   `/system/etc/init`, :358 `/system_ext/etc/init`, vendor/odm/product).
2. Event queue is then populated FIFO: `QueueBuiltinAction(SetupCgroups…)` →
   `QueueEventTrigger("early-init")` (:1225-1226) … `QueueEventTrigger("init")` (:1248) …
   `QueueEventTrigger("late-init")` (:1282) … `QueueBuiltinAction(queue_property_triggers_action)` (:1286).
3. `late-init` immediately cascades the boot stages: `system/core/rootdir/init.rc:517-545` —
   `trigger early-fs / fs / post-fs / late-fs / post-fs-data / load-bpf-programs /
   zygote-start / firmware_mounts_complete / early-boot / boot`.
4. **Persist properties load inside `post-fs-data`**, well after late-init's own commands:
   `init.rc:731 load_persist_props` (with the companion event at :739
   `trigger load_persist_props_action`). Before that point `persist.phosphor.safeboot` reads
   as **empty**.
5. Keygate, started by late-init's `start` command, forks immediately and races the cascade
   (init does not wait for oneshot services). It therefore almost certainly reads T2 before
   `load_persist_props` has run.

**Consequence against §2.1's own truth table:** T2 = empty = **absent**, and the table maps
`absent → 1` (this is an absent-read, not a read *error*, so the fail-closed rule does not
fire — it is a wrong-value read with defined semantics). Result:
`sys.phosphor.safeboot=1` on **every normal boot**; `on property:sys.phosphor.safeboot=0`
never fires; agentd never starts; A2 is unsatisfiable; the system is dead in exactly the
way §3.1's ordering-hazard paragraph :107 warns about — via the *latch* path rather than the
trigger path.

**Fix direction (for the architecture owner; §3.1 :112 makes this S3-fail-⇒-return, which is
what this finding is):** move the start to an event at-or-after persist-load:
`on load_persist_props_action` (fired at init.rc:739 immediately after the props land — the
event exists precisely for consumers of persist props), `on zygote-start`, `on early-boot`,
or `on boot`. The spec's constraint ("one early decision, fail-closed, agent gated on its
result", :105) is preserved by any of these; the literal event name was explicitly deferred,
and the deferral is now resolved: **not** `late-init`.

---

## BUG #3 — MEDIUM — §3.1's compound-trigger premise is false at parse level; the true constraint is runtime-only, and the spec text records the wrong reason

**Assumption violated:** :110 "Forbidden resolutions: (a) a second-condition trigger such as
`on late-init && property:…` — *this tree's init matches one property per `on property:` block*
(§6.5 …)".

**Parse level — compound triggers are legal.** `system/core/init/action_parser.cpp:97-133`
(`ParseTriggers`): odd-indexed tokens must be `&&` (:115-118); a section may carry **one event
trigger plus many property triggers**; property triggers live in a `std::map`, and a duplicate
property is rejected (:78 "multiple property triggers found for same property"). In-tree
in-use proof: `system/core/rootdir/init.rc:1235` — `on boot && property:ro.debuggable=1`.

**Runtime level — the spec's conclusion survives, with the correct reason.**
`Action::CheckEvent(const PropertyChange&)` (`system/core/init/action.cpp:225-228`) requires
`event_trigger_.empty()`; a compound `on late-init && property:X` action is **never** evaluated
against property-change events — it is evaluated only when the `late-init` **event** fires,
at which moment `CheckPropertyTriggers()` reads the *current* value of every listed property
(action.cpp:177-208). So:

- a compound event+property block cannot be a reaction to a write (this is why it must stay
  forbidden as an agentd-start mechanism); but
- the mechanism §6.5 recorded ("one property per block") is factually wrong and will mislead
  the next reader.

**Fix:** keep (a) forbidden; rewrite the reason in §3.1 (and the architecture doc's §6.5 line)
to the runtime semantics: *property-change dispatch ignores any action carrying an event
trigger (action.cpp:225-228); compound blocks evaluate only at their event, reading current
values.*

---

## BUG #4 — MEDIUM (probe premise refuted) — T1 `ro.boot.phosphor.safeboot` is readable by keygate as-shipped: NO property_contexts row, NO get_prop grant

**Assumption violated:** the probe premise "ro.boot.phosphor.safeboot is ungoverned → inherits
default_prop → keygate cannot read it → S3 must add a row + grant".

**Evidence:**

1. The blanket prefix row **exists**: `system/sepolicy/private/property_contexts:1088`
   `ro.boot.  u:object_r:bootloader_prop:s0` (comment at :1086-1087: "ro.boot. properties are
   set based on kernel commandline arguments"). It is the only global `ro.boot.` row in the
   tree (cuttlefish/sdv re-type specific `ro.boot.*` names — e.g.
   `device/google/sdv/sdv_base/sepolicy/system_ext/private/property_contexts:15-22` — none of
   which exist on akita; and nothing in any akita-relevant property_contexts mentions
   `phosphor` except our own `packages/phosphor/sepolicy/private/property_contexts`).
2. Every domain may read it: `system/sepolicy/private/domain.te:519`
   `get_prop(domain, bootloader_prop)` in the **unconditional** "Public readable properties"
   block (:516-551); the macro expands to `allow $1 $2:file { getattr open read map }`
   (`system/sepolicy/public/te_macros:385-387`).
3. Compiled proof, shipped S2 conf (`01738c13…`): `:9147`
   `type bootloader_prop, property_type, system_property_type, system_restricted_property_type;`
   and `:29985` `allow domain bootloader_prop:file { getattr open read map };`. The only
   neverallows on the type are **set-side** (`:9153` CTS treble rule `{ domain -coredomain }`,
   `:53670` `{ domain -init }` — matching `init.te:881`). Zero file-side neverallows.
4. keygate holds the `domain` attribute (conf:97585) and `coredomain` (conf:97656). Nothing
   subtracts it from any relevant attribute.

**Consequences:** A3 and the whole T1 column are **unblocked with zero sepolicy work**; the
"question: boot_prop? own type?" resolves to *neither* — `bootloader_prop` already governs it.
Also verified while here, supporting A3's runtime claim: `setprop ro.boot.phosphor.safeboot 1`
from shell is refused by policy (conf:53670), which is exactly the REC-2 immutability property.

---

## BUG #5 — LOW (paper) — `phosphor_keygate.te:8-9` comment cites a nonexistent mechanism

`packages/phosphor/sepolicy/private/phosphor_keygate.te:8-9`: "the host-set immutable ro.boot.*
(already readable as **boot_prop-derived** context; granted explicitly only if **C1** context
proves insufficient)". There is no `boot_prop` type anywhere (`grep '^type boot_prop'`
public/private property.te → empty); the actual mechanism is `bootloader_prop` +
`domain.te:519` (BUG #4). The conclusion is accidentally right, the citation wrong. Fix the
comment when S3 touches the file; name the real grant.

---

## BUG #6 — MEDIUM (verification gate) — device-side `/system_ext/etc/passwd` must be proven non-empty at S3's build; today's staged copy is a stale 0-byte S1-era artifact

`out/target/product/akita/system_ext/etc/passwd` is **0 bytes** in the current (S1-incremental)
`out/`; the populated generator output `passwd_gen_system_ext` (4 rows, BUG #1) post-dates the
last full image build. `build/make/target/product/base_system_ext.mk:23` does install
`passwd_system_ext`, and bionic reads the device file at runtime
(`/system_ext/etc/passwd`, grp_pwd.cpp:64) — so with BUG #1's prefixed names the resolution
works **only if** the installed file actually carries the rows. The S2 audit's "0-byte passwd
on ALL partitions is tree-normal (gen artifact is the anchor)" holds for `/system` (its gen
file is empty) but **not** for system_ext post-S2. S3's build acceptance must add: verify
`out/target/product/akita/system_ext/etc/passwd` (or the flashed image) contains
`system_ext_phosphor_keygate::7520:…` before any A1/A7 claim that depends on the UID.

---

## BUG #7 — LOW (documentation of mechanism; strengthens §3.1) — the ordering premise holds in a stronger form than the spec states

1. **Registration precedes all execution.** All `.rc` files — including whichever partition
   hosts ours — are parsed by `LoadBootScripts` (init.cpp:347-369) before the first queued
   event runs (init.cpp:1224+). Agentd's `on property:sys.phosphor.safeboot=0` action object
   exists in `ActionManager::actions_` before late-init executes. The spec's feared
   configuration — keygate's write landing before the trigger is *registered* — is impossible
   by construction; §3.1's :107-109 mechanism description ("init evaluates `on property:`
   triggers when the property is set … by which point all `.rc` files are loaded") should be
   corrected: parse order was never the risk.
2. **The real race is enable/sweep timing, and it is self-correcting.** Property triggers are
   disabled until `queue_property_triggers_action` runs (flag at init.cpp:125, set at :682;
   dispatch gate at :390-392 — sets arriving while disabled are **not** queued). That builtin
   is queued *after* `late-init` (:1286 vs :1282, FIFO), and it ends with
   `QueueAllPropertyActions()` — a `("", "")` property-change event
   (`action_manager.cpp:74-76`) that re-checks every property action against current values.
   Therefore: keygate's write landing **before** the sweep → sweep fires agentd's trigger;
   landing **after** (triggers enabled by then) → live dispatch at init.cpp:391 fires it.
   Both orderings converge on "agentd starts on `=0`". A9's ≥5-boot empirical proof is still
   mandatory per spec — but the static analysis predicts success, unlike BUG #2 which it
   cannot survive.
3. **`.rc` install location.** `phosphor-keygate` is a plain `cc_binary` → `/system/bin`
   (S1 spec :18, verified in `out/.../system/bin/phosphor-keygate`); adding `init_rc` in S3
   installs the `.rc` to `/system/etc/init/` (same partition as the module). init scans it:
   init.cpp:353. A system_ext placement would need `system_ext_specific: true` (init.cpp:358
   scans that too) — unnecessary here; either partition is scanned.

---

## Verified claims (no bug)

- **V1 — init scans both partitions' rc dirs** (init.cpp:353 `/system/etc/init`, :358
  `/system_ext/etc/init`). Consistent with BUG #7(3).
- **V2 — libbase property API in minimal native daemons:** `android-base/properties.h` is
  used by `system/core/watchdogd/watchdogd.cpp`, `system/core/gatekeeperd/gatekeeperd.cpp`,
  `system/core/llkd/libllkd.cpp`, `system/core/libprocessgroup/processgroup.cpp` — small,
  early, non-binder daemons; `GetProperty`/`SetProperty` (plus `GetBoolProperty`) fit §3.3's
  constraint. libbase is the right dependency.
- **V3 — oneshot + class core semantics:** `oneshot` = no restart on exit
  (`system/core/init/README.md:319`); `class core` services start at `class_start core` in
  `on boot` (init.rc:1232) — irrelevant to S3 since §3.1 uses an explicit `start`, but the
  `class core` line is harmless and conventional (SDV agents do the same).
- **V4 — S2 policy imposes no S3 conflict:** the one write is granted
  (`set_prop(phosphor_keygate, phosphor_safeboot_prop)`, conf:97638), the latch read is
  granted (conf:97651), the init transition is complete (conf:97597-97621), and keygate's
  neverallow set (conf:97666-97679) touches nothing the `.rc` path needs. **No new sepolicy
  is required for S3** (BUG #4 removes the last candidate).
- **V5 — A1's adb latch write path:** `set_prop(shell, phosphor_safeboot_latch_prop)` shipped
  in S2 (`packages/phosphor/sepolicy/private/app.te:12-14`) — the acceptance command works.

## Required spec changes (summary for the supervisor)

| # | Spec locus | Change |
|---|---|---|
| BUG #1 | §2.4 :96-97, §3.1 :97-98 | `user/group system_ext_phosphor_keygate` (or switch AIDs to the platform header route — config.fs route requires the prefix) |
| BUG #2 | §1 :15, §3.1 :100-103 | Replace `on late-init` with `on load_persist_props_action` (recommended: event exists for exactly this, init.rc:739) or `zygote-start`/`early-boot`; record the static proof in the spec instead of deferring to build |
| BUG #3 | §3.1 :110(a) | Keep forbidden; replace the false "one property per block" reason with the action.cpp:225-228 runtime semantics; fix §6.5's line in the architecture doc |
| BUG #4 | §2.1 T1 row, §8 item 4 | Delete the anticipated property_contexts/get_prop work — T1 is governed by `bootloader_prop` and domain-readable |
| BUG #5 | (S2 file, next touch) | Fix the te:8-9 comment citation |
| BUG #6 | §4 A1/A7 preconditions | Add on-device passwd-row verification gate |
| BUG #7 | §3.1 :107-112, A9 | Rewrite ordering rationale (parse-time registration; enable/sweep convergence); A9 empirical proof unchanged |

Per §3.1 :112's own rule, BUG #1/#2 mean the spec's verbatim `.rc` section fails preflight and
returns to the spec/architecture owner for revision before Coder builds — these are one-line
edits, but they are contract changes, not implementation detail.
