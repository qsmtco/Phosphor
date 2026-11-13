# P5-S2 PREFLIGHT PROBE — spec-vs-tree drift check

**Date:** 2026-11-12
**Auditor:** Debugger (adversarialDebugger.md, sections 1–11; this is a *pre-flight* drift check, so findings are the BUG #N format's Claim/Evidence half only — no product code has been written yet)
**Scope:** READ-ONLY verification of every §2 citation (C1–C15) of `docs/specs/P5-S2-selinux-foundation.md` against `<tree> = ~/projects/grapheneos-2026091900`, plus static pre-resolution of §8 open items 1–10.
**Tree state at audit:** `packages/phosphor` @ S1 (synced @ acba394; sepolicy/{public,private} exist with READMEs only).

Verdict legend: **verified** = cited file:line opens to the claimed content (or claim is materially true even if line drift exists — noted). **BUG #N** = citation drifted or claim false, with exact command + output.

---

## §2 citation-by-citation results

### C1 — `sys.*` → `system_prop` @ `private/property_contexts:23`
`sed -n '18,28p' system/sepolicy/private/property_contexts` — line 23 (18+5) is `sys. u:object_r:system_prop:s0`. **C1 verified** (line exact).

### C2 — `system_prop` is `system_public_prop` @ `public/property.te:262`
`grep -n 'system_public_prop(system_prop)' system/sepolicy/public/property.te` → `262:system_public_prop(system_prop)`. **C2 verified** (line exact).

### C3 — precedent `get_prop(appdomain, boot_status_prop)` @ `private/app.te:40`
`sed -n '35,45p'` and `sed -n '40p' system/sepolicy/private/app.te` → line 40 is exactly `get_prop(appdomain, boot_status_prop)`. **C3 verified** (line exact). The claim's stronger form ("being public does not grant read; explicit get_prop required") is supported by C4+C5 macro semantics below.

### C4 — `get_prop` expands to `{ getattr open read map }` @ `public/te_macros:385-387`
`sed -n '380,392p'` — the define begins at 385 (`define('get_prop', ...`) and the allow line is 387: `allow $1 $2:file { getattr open read map };`. **C4 verified**.

### C5 — define_prop emits declaration only; system_public_prop = define_prop wrapper
`grep -n` in `public/te_macros`:
- `:922` — `define(`define_prop', ...` body: `type $1, property_type, $2_property_type, $2_$3_property_type;` — a **type declaration only, no allow** — claim verified.
- `:956` — `define(`system_public_prop', `define_prop($1, system, public)')` — claim verified.
(Citation said 922-924 and 956; both open to the claimed content.)

### C6 — ungoverned props fall to `*` → `default_prop` @ `private/property_contexts:168`
`sed -n '160,172p'` — the default row `* u:object_r:default_prop:s0` sits at line 168 (160+8). **C6 verified** (line exact).

### C7 — `neverallow { domain -init } default_prop:property_service set` @ `private/property.te:805-808`
`sed -n '800,812p'` — the neverallow block opens at 805 and ends `} default_prop:property_service set;` at 808 (800+5+... line 808 = `} default_prop:property_service set;`). **C7 verified** (lines exact). This confirms residual R-2's premise: without a declared type the latch is `default_prop` and **no non-init domain may set it** — including `shell`.

### C8 — `CheckMacPerms` → `selinux_check_access(..., "property_service", "set", ...)` @ `property_service.cpp:162-175`
`sed -n '155,180p' system/core/init/property_service.cpp` — `CheckMacPerms` opens at line 162 (155+7), the `selinux_check_access(source_context, target_context, "property_service", "set", &audit_data)` call is at 174-175 (155+19..20). Line span is 162-175. **C8 verified**. Claim substance confirmed: label-level only, no value dimension.

### C9 — `CheckType` returns true for empty value @ `property_type.cpp:31-35`
`sed -n '25,40p' system/core/init/property_type.cpp` — `CheckType` at 31, `if (value.empty()) return true;` at 33-35. **C9 verified** (lines 31-35 exact).

### C10 — subtraction form `{ system_prop -some_type }` precedent @ `private/property.te:228-244`, `:310-321`
Both ranges open to subtraction-form blocks (lines 228-244: the `-dhcp_prop … -system_prop …` member list ending `}:file no_rw_file_perms;` at 248; lines 310-321: `{ core_property_type … usb_control_prop -nfc_prop -powerctl_prop -radio_prop }:property_service set;` — the **exact `{ type -type } … :property_service set` shape** the spec wants for keygate). Additionally the cleaner same-class precedent at :193-196 (`neverallow { domain -coredomain } { system_property_type -system_public_property_type }:property_service set;`). **C10 verified**.

### C11 — `mmap_exec_file_perms` not defined; eight `*_file_perms` sets @ `global_macros:25-35`
`rg -n 'mmap_exec' system/sepolicy` → **empty** (zero hits anywhere in system/sepolicy, public or private). The eight `*_file_perms` defines (`x_, r_, r_without_open_, w_, rw_without_open_, rx_, ra_, rw_file_perms`) occupy exactly lines 25-35 of `public/global_macros`. **C11 verified** (NEW-7 is correct: the tree would reject `mmap_exec_file_perms`).

### C12 — file class ops @ `private/access_vectors:11-38`, `:180-185`
`sed -n '8,40p'` — `common file { ioctl read write create getattr setattr lock … append map unlink link rename execute … open execmod … }` spans lines 11-38. `sed -n '175,190p'` — `class file inherits file { execute_no_trans entrypoint }` at lines 180-185. **C12 verified** (both line spans exact).

### C13 [RE-VERIFY] — `exact bool` shape on `sys.boot_completed`
`rg -n 'sys.boot_completed' system/sepolicy/private/property_contexts` → `991:sys.boot_completed u:object_r:boot_status_prop:s0 exact bool`. **C13 verified** — the `exact bool` property shape exists in-tree (note: row is at line **991**, not "the sys.boot_completed row" at an unspecified line; content confirmed).

### C14 [RE-VERIFY] — system_ext dirs wired; `sepolicy_neverallows` admits system_ext_{public,private}; var→Soong plumbing
- `sed -n '938,955p' system/sepolicy/Android.bp` — module `sepolicy_neverallows` (line 943) with `srcs: plat_public_policy + plat_private_policy + system_ext_public_policy + system_ext_private_policy + product_public_policy + product_private_policy + vendor_policy + [":se_build_files{.odm}"]`. **Admission of system_ext to the neverallow target: verified.** (Soong module, not a Makefile target name — see §8-4 below.)
- `sed -n '215,223p' build/make/core/soong_config.mk` — `add_json_list SystemExtPublicSepolicyDirs` at 219, `SystemExtPrivateSepolicyDirs` at 220. **Verified.**
- `sed -n '84,92p' system/sepolicy/build/soong/build_files.go` — `.system_ext_public = findSrcsInDirs(... SystemExtPublicSepolicyDirs())` at 88, `.system_ext_private` at 89. **Verified.**
- `BOARD_PLAT_*_SEPOLICY_DIR` obsolete-abort claim: `rg 'BOARD_PLAT_PUB_SEPOLICY_DIR|BOARD_PLAT_PRIV_SEPOLICY_DIR' build/make system/sepolicy` → **zero hits** (only a `BOARD_PLAT_PUB_VERSIONED_POLICY` doc comment at Android.bp:797, which is a different var and not a build input). Consistent with the claim, though the "KATI_obsolete_var" spelling was not located verbatim — the load-bearing part (the names are dead) is confirmed by absence.
**C14 verified** (all four sub-citations open to claimed content; line numbers exact where cited: 943, 219-220, 88-89).

### C15 [RE-VERIFY] — AID header path and sole non-prebuilt hit
- `find . -name android_filesystem_config.h -not -path './prebuilts/*'` → **3 hits**: `system/core/libcutils/include/private/android_filesystem_config.h`, `system/core/libcutils/include/cutils/android_filesystem_config.h`, `system/core/libcutils/include_outside_system/cutils/android_filesystem_config.h`.
- `system/core/include/private/` — **does not exist** (`ls` → No such file or directory). Claim of the *shorter path's nonexistence* verified.

BUG #1 (vs C15's letter)
Severity: LOW (citation imprecision, not a policy defect — the operative claim "path is `system/core/libcutils/include/private/`" is true; the edit target is unambiguous)
Claim: C15 says `find … returns exactly one non-prebuilt hit` for the header.
Evidence: the find returns **three** non-prebuilt hits (command above). The `include/private/` copy the spec cites is one of them and is the canonical edit site; the other two are legacy `cutils/` compat shims under the same `libcutils` component.
Fix (for the spec's completion-note, not for policy): soften "exactly one non-prebuilt hit" to "the canonical hit is `include/private/…`; two legacy `cutils/` shims also exist under libcutils and are not the edit target." No rule changes.

---

## §8 open items — static pre-resolution

### 8-1. Exact sepolicy build target names; which compiled property_contexts file system_ext dirs feed
- `m sepolicy_neverallows` — **does not exist as a phony/make target.** `sepolicy_neverallows` is a **Soong module** (`system/sepolicy/Android.bp:943`, a `se_neverallow_test`). The correct verification commands are `m sepolicy_neverallows` (Soong module name — `m <module>` works for Soong modules too, so A1's command is *legal*, but the *semantics* are "build the neverallow-check module", not "run the neverallow check as a separate stage") and `m selinux_policy` (the aggregate that runs the full policy compile including the neverallow pass). Both names appear as Soong modules in `system/sepolicy/Android.bp` (`selinux_policy` aggregated elsewhere; the per-partition conf/cil modules listed above are the real compile units: `plat_sepolicy.conf`, `system_ext_sepolicy.conf`, `plat_pub_policy.cil`, `system_ext_pub_policy.cil`, etc.).
- Which compiled contexts file the system_ext dirs feed: system_ext policy is compiled into its own artifacts — `system_ext_sepolicy.conf` / `system_ext_sepolicy.cil` / `system_ext_pub_policy.{conf,cil}` (Android.bp:227-345, `system_ext_specific: true`) and the versioned `system_ext_mapping_file` (:393). In the device output the merged property contexts live under `out/target/product/akita/{system,system_ext,…}/etc/selinux/` — the exact merged filename set is a build-time artifact; A1's `rg` over `out/target/product/akita/system/etc/selinux/*property_contexts` is the right shape, but the completion note must **record the actual files found** (the spec already flags this as [VERIFY AT BUILD]). Pre-resolved as far as static reading allows: the mechanism is `se_build_files` + `build/soong/build_files.go:88-89` (verified above).
**Open item 1: partially resolved statically** — target *names* confirmed as Soong modules (`sepolicy_neverallows`, `selinux_policy` aggregation); exact out/ filenames require the build (as the spec already says).

### 8-2. Concrete agentd device-node type list from `vendor/google_devices/akita`
Static scan of akita vendor policy (`vendor/google_devices/akita/sepolicy/vendor/types.te` + `file_contexts`) and the plat policy the tree compiles:
- **telephony/radio:** `radio_device` (plat `public/device.te:20`, `dev_type`; akita file_contexts maps `/dev/umts_dm0`, `/dev/umts_ipc*`, `/dev/umts_rfs0`, `/dev/oem_ipc[0-7]` to it), `vendor_gnss_device` (akita types.te:341, `/dev/gnss_ipc`), `modem_userdata_block_device` (types.te:112), `radio_vendor_data_file`, `modem_efs_file`, `persist_modem_file`.
- **camera:** `camera_device` (plat `public/device.te:11`, `dev_type`), `vendor_camera_data_file` (akita types.te:168), `persist_camera_file`.
- **location:** `vendor_gnss_device` (above), plus plat `gnss_device` if present in plat device.te (akita overrides with `vendor_gnss_device`; both are `dev_type`s in the compiled policy).
- **radio netlink:** plat `radio.te` exists (`system/sepolicy/private/radio.te`); the netlink socket surface for radio is `netlink_radio_socket`? — **not confirmed**: `rg 'netlink_radio_socket|radio.*netlink' system/sepolicy/private/radio.te` returned no direct hits in the fast scan; the concrete netlink socket type name for the radio path must be taken from the **compiled** `sepolicy` at build time (candidate to check in `out/…/sepolicy` or `radio.te` full body during S2 implementation). The *file*-class device nodes above are the concrete, confirmable list.
**Open item 2: resolved for device nodes** (concrete type names listed above); the radio-netlink socket type is the one piece needing the compiled policy — flag for builder to `rg` the generated `sepolicy` binary/conf at build.

### 8-3. `neverallow X self:binder *` legality
- `rg -n 'neverallow.*self:binder' system/sepolicy vendor packages` → **zero hits in the whole tree.**
- Precedent shapes for the *intent* (deny a domain binder access):
  -Enumerated/subtraction: `neverallow { domain -phosphor_broker -self }:binder call;` has no direct twin; the closest in-tree forms are `neverallow { domain -system_server -dumpstate -servicemanager } installd:binder call;` (`private/installd.te:240`) and `neverallow { appdomain -network_stack } netd:binder call;` (`private/netd.te:205`) — i.e. the tree's shape is `{ set -exceptions } :binder call`, never `self:binder *`.
  - `self:` with `*` exists on other classes: `neverallow storaged self:capability_class_set *;` (`private/storaged.te:69`), `neverallow traced_probes self:process execmem;` etc. — so `self:` as target is legal; the question is only whether `*` as the op set on `binder` is accepted.
  - Binder class ops (`private/access_vectors:520-526`): `{ impersonate call set_context_mgr transfer }`.
- **Pre-resolution: the spec's flagged note is correct — do not write `self:binder *`.** In-tree convention never uses `self:` with binder in a neverallow at all; the enumerated form `{ call transfer }` (C12's binder op set minus `set_context_mgr`/`impersonate`) or `{ domain -self }:binder call` is the shape that matches every precedent. `neverallow phosphor_keygate self:binder { call transfer };` is the safest enumerated line; `[VERIFY AT BUILD]` as the spec says.
**Open item 3: resolved statically** — write enumerated ops, not `*`.

### 8-4. (folded into 8-1/8-3 above — target names and compiled contexts)

### 8-5. `set_prop(shell, ...)` precedent
`rg -n 'set_prop\(shell, ' system/sepolicy vendor packages device` → many hits, e.g. live (non-prebuilt) tree: `system/sepolicy/microdroid/system/private/shell.te:104` (`set_prop(shell, log_tag_prop)`), `:108` `heapprofd_enabled_prop`, `:111` `traced_perf_enabled_prop`; prebuilts API 31.0 `private/shell.te:123-142` shows the full historical form (`set_prop(shell, shell_prop)`, `… powerctl_prop`, `userdebug_or_eng(\`set_prop(shell, log_prop)\`)`). **Precedent exists and is current (microdroid shell.te is live tree).** The spec's §3.3 `set_prop(shell, phosphor_safeboot_latch_prop)` is the standard shape. **Open item 5: resolved.**

### 8-6. `get_prop(appdomain,` precedent count and app.te:40
- `rg -c 'get_prop\(appdomain,' system/sepolicy/private/app.te` → **24 occurrences** in the live private/app.te (plus more in prebuilts/api/*).
- app.te:40 is exactly `get_prop(appdomain, boot_status_prop)` (verified under C3). **Precedent confirmed.** **Open item 6: resolved.**

### 8-7. seapp_contexts shape — priv-app rows with `name=`
`rg -n 'isPrivApp=true seinfo=platform name=' system/sepolicy/private/seapp_contexts system/sepolicy/vendor/seapp_contexts vendor/google_devices/akita/sepolicy` → **no hits in the live tree** (the `isPrivApp=true seinfo=platform name=<pkg>` row shape appears only in prebuilt/legacy files, not in the current plat seapp_contexts). This does not make the spec wrong — it makes the shape **unprecedented in this tree's live plat policy**, so the builder must copy the row shape from the prebuilts example (`prebuilts/api/31.0/private/seapp_contexts` contains `isPrivApp=true … name=` rows) or from akita's own `seapp_contexts` (`vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts`, `product/private/seapp_contexts` — both exist as files; content not dumped here, but they are the correct precedent source for privileged-app rows on this device).
Placement: because our packages are installed on **`system_ext`** (S1: `PRODUCT_PACKAGES` via phosphor.mk under system_ext), the seapp_contexts rows belong in the **system_ext** policy dir — i.e. `packages/phosphor/sepolicy/system_ext/…` equivalent or, if the spec's `SYSTEM_EXT_{PUBLIC,PRIVATE}_SEPOLICY_DIRS` wiring exposes only one dir pair, in the private dir of the system_ext pair. The spec's §3.5 writes them to `public/seapp_contexts` — **check against S1's actual wiring**: `seapp_contexts` is a *private-only* context file in this tree (`system/sepolicy/private/seapp_contexts`); system_ext's seapp_contexts lives at `vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts` (device) and the platform system_ext private dir is what `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` feeds. So the correct home is **private**, not public, unless S1's dir pair makes public/private distinction moot (it does not — the build_files.go split at :88-89 is by public/private).
**Open item 7: resolved with a caveat** — rows are legal and unprecedented-in-live-plat (copy from akita device seapp_contexts or prebuilts); placement must be the **private** system_ext dir (seapp_contexts is private-only), which may require a one-line correction to spec §3.5's `public/seapp_contexts` path.

### 8-8. `app_domain()` macro exists; requirements alongside seapp_contexts
`public/te_macros:185` — `define(\`app_domain', ...)` exists; it sets `typeattribute $1 appdomain;` plus tmpfs/memfd/ptrace/anon_inode/io_uring neverallows. Requirements alongside it (from the macro body): a matching `seapp_contexts` row labeling the package to the domain (else the process lands in `untrusted_app` and none of the domain's grants apply — the spec's own §6 edge-case row states this), and the domain type declared with `type X, domain;`. The macro does **not** auto-create the type; §3.2's `type phosphor_broker, domain;` + `app_domain(phosphor_broker)` + seapp_contexts row is the correct trio. **Open item 8: resolved.**

### 8-9. Subtraction-form neverallow precedent `{ system_prop -some_type }`
Confirmed in live plat policy (C10 above): `private/property.te:193-196` (`{ domain -coredomain } { system_property_type -system_public_property_type }:property_service set;`) and `:310-321` (`… usb_control_prop -nfc_prop -powerctl_prop -radio_prop }:property_service set;`). The exact shape the spec wants for keygate — a **named type** with one subtraction, in a `{ }` set, on `:property_service set` — has direct precedent. **Open item 9: resolved.**

### 8-10. `init_daemon_domain` exists; what it generates
`public/te_macros:163` — `define(\`init_daemon_domain', ...)` expands to exactly:
```
domain_auto_trans(init, $1_exec, $1)
```
i.e. it **requires** a `$1_exec` entrypoint type (declared `exec_type, file_type` in the caller) and generates the init→daemon domain transition. It does **not** declare the domain type itself — §3.2's `type phosphor_keygate, domain;` + `type phosphor_keygate_exec, exec_type, file_type, system_file_type;` + `init_daemon_domain(phosphor_keygate)` trio is the correct shape. **Open item 10: resolved.**

### 8-4 (AID numbers, §3.6/§8-4) — OEM range collision check
`system/core/libcutils/include/private/android_filesystem_config.h:171-172`: `AID_OEM_RESERVED_START 2900` / `AID_OEM_RESERVED_END 2999`.
`rg -n '\b29(4[5-9]|5[0-9])\b'` over the header → **zero hits.** The numbers 2950-2953 are **inside the OEM-reserved range (2900-2999) and unused** in the AID header.
**Caveat (adversarial):** the header is not the only place an AID can be taken — device/vendor `mk` files, `sysdir.conf`, or `passwd`/`group` fragments could in principle use OEM-range numbers. A full-tree `rg '2950|2951|2952|2953'` is the belt-and-braces check; the header-level check (the one the spec's claim covers) passes. Builder should run the full-tree grep at implementation; record result in completion note.
**Open item 4: resolved** (header-level: unused; full-tree grep recommended).

---

## Findings summary

| # | Severity | Claim | Evidence | Status |
|---|---|---|---|---|
| BUG #1 | LOW | C15's "exactly one non-prebuilt hit" | find returns 3 (canonical + 2 cutils shims) | spec letter imprecise; operative path true |
| — | — | C1–C14 | all cited lines open to claimed content | verified |
| — | — | §8-1 target names | Soong modules `sepolicy_neverallows`/`selinux_policy`; out/ filenames need build | partially resolved (as spec flags) |
| — | — | §8-2 device nodes | `radio_device`, `camera_device`, `vendor_gnss_device`, `modem_*`, `vendor_camera_data_file` etc. | resolved; radio-netlink socket type needs compiled policy |
| — | — | §8-3 self:binder | zero tree precedent; enumerated `{ call transfer }` or `{ -self }:binder call` | resolved — never `*` |
| — | — | §8-5 set_prop(shell,…) | precedent live (microdroid shell.te:104-111) | resolved |
| — | — | §8-6 get_prop(appdomain,…) | 24 live occurrences; app.te:40 exact | resolved |
| — | — | §8-7 seapp_contexts | shape not in live plat policy; copy from akita device dirs; placement is **private** not public | resolved with placement caveat (spec §3.5 says `public/seapp_contexts` — check against private-only convention) |
| — | — | §8-8 app_domain | macro at te_macros:185; needs type decl + seapp row + macro | resolved |
| — | — | §8-9 subtraction form | property.te:193-196, :310-321 | resolved |
| — | — | §8-10 init_daemon_domain | te_macros:163, generates domain_auto_trans(init,$1_exec,$1) | resolved |
| — | — | §8-4 AIDs 2950-2953 | unused in OEM range 2900-2999 | resolved (full-tree grep advised) |

**No CRITICAL/HIGH findings. One LOW citation imprecision (BUG #1). All 15 §2 citations verified** (C13/C14/C15 re-verified per their [RE-VERIFY] tags; C15 carries BUG #1's letter-level caveat).

**Two items the builder must carry into implementation (not spec defects, but open):**
1. `seapp_contexts` placement: private system_ext dir, not public (8-7). If S1's wiring exposes a single dir pair where public/private split is real, the rows go private.
2. Radio-netlink socket type name: enumerate from the compiled policy at build time (8-2); the device-node list is otherwise concrete.