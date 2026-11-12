# P5-S2 — SELinux foundation: `phosphor_*` types, domains, and the safe-boot property

**Phase:** 5 · **Spec ID:** P5-S2 · **Rev:** 1 (draft for PM approval) · **Owner:** Coder (builder) / Debugger (auditor)
**Status:** DRAFT — awaiting PM approval.
**Depends on:** **P5-S1** (the `packages/phosphor/sepolicy/{public,private}` directories and the `SYSTEM_EXT_*_SEPOLICY_DIRS` wiring exist only after S1).
**Blocks:** **P5-S3, P5-S4, P5-S5, P5-S6, P5-S7** — every one of them needs its domain, its property access, or its file type from this spec. S8 depends on S2 transitively.
**Authority:** architecture §2.1 (four processes, UIDs, domains), §6.3 (policy artifact read grant), §6.4 (secret surface), §6.5 (safe boot + app-layer property visibility), §8 ("SELinux requirements (Phase 5 deliverables)" — the compile-ready rule set); `docs/P4-ARCH-AUDIT.md` residuals **R-2** and rev-4 findings **NEW-4/NEW-6/NEW-7**; `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` §10.2 row V-2.

---

## 1. Scope

Write the Phase 5 sepolicy that makes the architecture's four-domain split real, and make the safe-boot mechanism *achievable* rather than merely designed:

1. Four domains + their entrypoints/permissions: `phosphor_keygate`, `phosphor_agentd`, `phosphor_broker`, `phosphor_shell`. **Four is the whole set** — `phosphor-ctl` (the fifth module S1 installs) runs in the existing `shell` domain and takes no Phosphor domain (§5 A8 records the decision).
2. Three property types: **`phosphor_safeboot_prop`** (`sys.phosphor.safeboot`), **`phosphor_safeboot_latch_prop`** (`persist.phosphor.safeboot` — *the type R-2 says is missing*, together with its **one** writer), and their access rules.
3. The `get_prop(appdomain, phosphor_safeboot_prop)` grant (§10.2 V-2's one Phase 5 rule) **and** the `set_prop(shell, phosphor_safeboot_latch_prop)` grant that makes the documented host trigger actually work (§3.3).
4. The file-type declarations: `phosphor_risk_policy_file`, `phosphor_agentd_exec`, `phosphor_agentd_data_file`, plus app data types for shell/broker.
5. The architecture §8 `neverallow` set, in compile-ready form, all file rules written as **`:file *`** (NEW-7 — `mmap_exec_file_perms` does not exist in this tree).

### Non-goals

- No `.rc` files (S3/S4), no daemon logic, no app manifests.
- No permission grants on the §3 broker capability surface beyond what is needed to make the domain *exist* and *compile*; the per-capability manifest is S6.
- No `seapp_contexts` change for user apps; only our four packages.
- No device operation. This spec is verified by **policy compilation**, not by booting.

---

## 2. In-tree citations (every claim below carries one)

Verified against `<tree> = ~/projects/grapheneos-2026091900`. Rows marked **[RE-VERIFY]** were confirmed by the Phase 4 audit and must be re-confirmed by the builder before the rule is written, because this spec is an implementation contract and a wrong citation is worse than a tagged one.

| # | Claim | Citation |
|---|---|---|
| C1 | `sys.*` properties default to `system_prop` | `system/sepolicy/private/property_contexts:23` |
| C2 | `system_prop` is a `system_public_prop` | `system/sepolicy/public/property.te:262` |
| C3 | Being public does **not** grant an app read — an explicit `get_prop` is required; the tree ships the precedent | `system/sepolicy/private/app.te:40` — `get_prop(appdomain, boot_status_prop)` |
| C4 | `get_prop` expands to `{ getattr open read map }` | `system/sepolicy/public/te_macros:385-387` |
| C5 | `define_prop` / `system_public_prop` emit a **type declaration only** (no read grant) — which is why C3's rule is needed | `system/sepolicy/public/te_macros:922-924` (define_prop), `:956` (system_public_prop) |
| C6 | Ungoverned properties fall to `*` → `default_prop` | `system/sepolicy/private/property_contexts:168` |
| C7 | `neverallow { domain -init } default_prop:property_service set` — absent a declared type, **no non-init writer at all**, which is exactly residual **R-2** | `system/sepolicy/private/property.te:805-808` |
| C8 | Property `set` is a **label-level** check with no value dimension | `system/core/init/property_service.cpp:162-175` (`CheckMacPerms` → `selinux_check_access(..., "property_service", "set", ...)`) |
| C9 | `CheckType` returns `true` for any empty value — so no rule can distinguish `=1` from `=0` | `system/core/init/property_type.cpp:31-35` |
| C10 | The `-prop` subtraction form used for the keygate property rule is real in-tree policy shape | `system/sepolicy/private/property.te:228-244`, `:310-321` |
| C11 | `mmap_exec_file_perms` is **not defined** in this tree; the available `*_file_perms` sets are the eight in `global_macros` | `system/sepolicy/public/global_macros:25-35` |
| C12 | `file` class operation set (`execute`, `read`, `write`, `create`, `getattr`, `setattr`, `map`, `append`, `unlink`, `rename`, `open`) and `execute_no_trans`, `entrypoint` | `system/sepolicy/private/access_vectors:11-38`, `:180-185` |
| C13 | `exact bool` property shape is already used for `sys.boot_completed` | `system/sepolicy/private/property_contexts` (`sys.boot_completed` row) **[RE-VERIFY]** |
| C14 | The Phosphor policy dirs are wired as `SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` / `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` (S1 §3 B5), and **`system_ext` policy is admitted to the `sepolicy_neverallows` target** — which is why the §8 `neverallow` set is legal to compile there. (The obsolete `BOARD_PLAT_*_SEPOLICY_DIR` names are `KATI_obsolete_var` in this tree and hard-abort the build.) | `system/sepolicy/Android.bp:943` (`sepolicy_neverallows` srcs = plat_public, plat_private, **system_ext_public, system_ext_private**, product_public, product_private, vendor, odm); var→Soong plumbing `build/make/core/soong_config.mk:219-220`; consumer `system/sepolicy/build/soong/build_files.go:88-89` **[RE-VERIFY]** |
| C15 | System AIDs are declared centrally; our four UIDs need entries there. **Path is `system/core/libcutils/include/private/`, not `system/core/include/private/`** (the latter does not exist — `find . -name android_filesystem_config.h -not -path './prebuilts/*'` returns exactly one non-prebuilt hit) | `system/core/libcutils/include/private/android_filesystem_config.h` **[RE-VERIFY]** |

**Why C14 matters, and the mechanism stated correctly:** a `neverallow` is not legal in every policy dir — it is legal only where the `sepolicy_neverallows` target admits it. That target (`system/sepolicy/Android.bp:943`) compiles the neverallow set from `plat_public + plat_private + system_ext_public + system_ext_private + product_public + product_private + vendor + odm`. So **`system_ext` carries our `neverallow` because it is admitted to that target** — *not* "because system_ext is platform policy", which is the wrong reason and would let the next reader re-derive the choice wrongly (e.g. conclude that `BOARD_VENDOR_SEPOLICY_DIRS` is equivalent, or that any platform-ish dir will do). Using a dir *outside* that list would make the entire §8 rule set compile-fail, and the natural repair — deleting the rules — would silently drop every guarantee. This is the single most important structural choice in the spec, so it is cited to the target rather than to the variable name.

---

## 3. Behaviour contract

### 3.1 Property types (the part residual R-2 says is missing)

`packages/phosphor/sepolicy/public/property.te`:

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

`packages/phosphor/sepolicy/public/property_contexts`:

```
sys.phosphor.safeboot              u:object_r:phosphor_safeboot_prop:s0         exact bool
persist.phosphor.safeboot          u:object_r:phosphor_safeboot_latch_prop:s0   exact string
persist.phosphor.agent_state       u:object_r:phosphor_safeboot_latch_prop:s0   exact string
```

- `sys.phosphor.safeboot` **must not** be named with a `sys.powerctl`-style special case; `exact bool` is sufficient (architecture §8).
- `persist.phosphor.agent_state` is the **mirror property** that §6.5/§10.2 V-2 retain as the *escape hatch* only. It is typed here so the hatch is expressible without a later policy edit, but **nothing in S5 may use it as the primary read** — V-2's ruling is that the primary path is `get_prop(appdomain, phosphor_safeboot_prop)`.

### 3.2 Access rules — the four domains

`packages/phosphor/sepolicy/public/phosphor_keygate.te`:

```
type phosphor_keygate, domain;
type phosphor_keygate_exec, exec_type, file_type, system_file_type;
init_daemon_domain(phosphor_keygate)

# Writes exactly one property, and only that one.
set_prop(phosphor_keygate, phosphor_safeboot_prop)
# Reads the triggers: the host-set immutable ro.boot.* (already readable as boot_prop-derived
# context; granted explicitly only if C1's context proves insufficient) and the latch.
get_prop(phosphor_keygate, phosphor_safeboot_latch_prop)
```

and the subtraction-form `neverallow` from §8 (see 3.4).

`packages/phosphor/sepolicy/public/phosphor_agentd.te`:

```
type phosphor_agentd, domain;
type phosphor_agentd_exec, exec_type, file_type, system_file_type;
init_daemon_domain(phosphor_agentd)

get_prop(phosphor_agentd, phosphor_safeboot_prop)       # to log/verify its own start condition
allow phosphor_agentd phosphor_risk_policy_file:file r_file_perms;
allow phosphor_agentd phosphor_agentd_data_file:dir create_dir_perms;
allow phosphor_agentd phosphor_agentd_data_file:{ file lnk_file } create_file_perms;
```

`packages/phosphor/sepolicy/public/phosphor_broker.te` and `phosphor_shell.te`: `app_domain(phosphor_broker)` / `app_domain(phosphor_shell)` with `type phosphor_broker, domain;` / `type phosphor_shell, domain;`, broker gets `r_file_perms` on `phosphor_risk_policy_file` **and nothing writable on it**, shell gets **no** access to the policy artifact at all (§6.3: "The shell has no read access at all").

### 3.3 The app-layer safe-boot read (§6.5 / §10.2 V-2 / NEW-1) **and the latch writer (R-2 discharge)**

`packages/phosphor/sepolicy/private/app.te` (a Phosphor-local file — do **not** edit `system/sepolicy/private/app.te`; the `appdomain` attribute makes a local file sufficient and keeps the third-party edit surface at zero). It carries **two** rules, and both are required:

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

Consequence, stated so it is not later mistaken for a bug: **any app on the device can read the safe-boot bit.** That is intended — it is a boot-state flag, not a secret, and the polarity is fail-closed (unreadable ⇒ safe boot, §6.5). What no app gets is `set` on the *decision*; the only `set` any non-init domain gets is `shell` on the *latch*, in the one direction the host needs.

Why `shell` is the right domain and not a Phosphor one: the writer must be the host's adb path, and that path is the `shell` domain. Granting it to `phosphor_shell` (our app), `phosphor_agentd`, `phosphor_keygate` or `phosphor_broker` would let in-device code latch safe boot — which §6.5/NEW-6 forbid and A10 audits. `shell` is reachable only over adb with the cable attached, i.e. the "host + cable = trusted recovery authority" reasoning §6.5 already relies on. Nothing in-device gains the write, so the one-way property is unchanged.

### 3.4 The `neverallow` set (architecture §8, compile-ready)

`packages/phosphor/sepolicy/public/phosphor_neverallows.te`. All file rules use **`:file *`**; `mmap_exec_file_perms` is **not** named (NEW-7 / C11 — it would fail to compile and `:file *` denies strictly more).

```
# --- keygate: it decides, and is denied everything else (NEW-3) ---
neverallow phosphor_keygate phosphor_agentd_exec:file *;
neverallow phosphor_keygate phosphor_agentd_data_file:file *;

# keygate's property access as a subtraction, in the in-tree form (C10):
# it may set nothing except the boot decision.
neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set;

# keygate holds no binder, no network, no device node.
neverallow phosphor_keygate self:binder *;                          # * see note below
neverallow phosphor_keygate self:tcp_socket *;
neverallow phosphor_keygate self:udp_socket *;

# --- agentd: capability-adjacent nodes are unreachable ---
neverallow phosphor_agentd { device node surfaces that back telephony, camera, location,
                             and radio netlink are unreachable }:file *
# --- agentd: exactly one binder target ---
neverallow phosphor_agentd { domain -phosphor_broker -self }:binder call;

# --- the safe-boot latch: exactly ONE non-init writer (R-2 discharged by enforcement, not
# by observation). §3.3 grants set_prop(shell, phosphor_safeboot_latch_prop); this line
# denies every other domain, init behaving as init. Without it "exactly one writer" is merely
# true today and quietly becomes false the next time someone grants anything near it.
neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set;

# --- shell: broker or nothing ---
neverallow phosphor_shell { domain -phosphor_broker -self }:binder call;

# --- the policy artifact is read-only to every Phosphor domain (NEW-4) ---
neverallow { phosphor_agentd phosphor_broker phosphor_shell phosphor_keygate } \
    phosphor_risk_policy_file:file { write append create rename setattr unlink };
```

**Notes the builder must resolve rather than silently drop:**
- `neverallow phosphor_keygate self:binder *` — `neverallow` does not accept `*` as an operation set on every class. Write the enumerated form from C12 (`{ call transfer }`) or use the `-self` subtraction pattern; **[VERIFY AT BUILD: `m sepolicy_neverallows` reports the exact diagnostic]**. The *intent* is fixed: keygate has no binder.
- The agentd device-node line is written here in prose **deliberately**: the concrete node set differs by device tree and a guessed list would either fail to compile or be vacuous. The builder must enumerate real types (telephony, camera, location, radio netlink) from the generated `vendor/google_devices/akita` policy and paste them; the auditor checks the line is non-empty and names at least the four categories in §8.
- `neverallow { domain -phosphor_broker -self }:binder call` must **not** be widened to include `init`/`servicemanager` blindly — agentd calls broker through `servicemanager`, so `phosphor_agentd` needs `find` on `service_manager` but the `neverallow` is on `binder call`, not on `service_manager`. Keep the two classes separate.

### 3.5 File types and contexts

`public/file.te`:

```
type phosphor_risk_policy_file, file_type, system_file_type;
type phosphor_agentd_data_file, file_type, data_file_type;
```

`public/file_contexts`:

```
/system/etc/phosphor(/.*)?                    u:object_r:phosphor_risk_policy_file:s0
/system/bin/phosphor-agentd                   u:object_r:phosphor_agentd_exec:s0
/system/bin/phosphor-keygate                  u:object_r:phosphor_keygate_exec:s0
/data/misc/phosphor(/.*)?                     u:object_r:phosphor_agentd_data_file:s0
```

`public/seapp_contexts` (label the two apps to their domains):

```
user=_app isPrivApp=true seinfo=platform name=com.phosphor.shell   domain=phosphor_shell type=privapp_data_file levelFrom=user
user=_app isPrivApp=true seinfo=platform name=com.phosphor.broker  domain=phosphor_broker type=privapp_data_file levelFrom=user
```

### 3.6 UIDs

Four AIDs, declared in `system/core/libcutils/include/private/android_filesystem_config.h` (C15 — note the `libcutils` path component; `system/core/include/private/` does not exist) in the OEM range; `AID_PHOSPHOR_KEYGATE=2950`, `AID_PHOSPHOR_AGENTD=2951`, `AID_PHOSPHOR_BROKER=2952`, `AID_PHOSPHOR_SHELL=2953` — **[VERIFY AT BUILD: unused in this tree; the architecture leaves the broker's spelling provisional (§2.1/MINOR-1), the number is not]**.

**Four, not five:** `phosphor-ctl` gets no AID — it runs as the `shell` UID inside the existing `shell` domain (§5 A8). So this stays a 4-line edit and the "four UIDs" inventory stays literally true.

This is a **second third-party edit** beyond S1's single line. It is unavoidable — `user phosphor_agentd` in an `.rc` resolves through that header — so it is declared here rather than discovered in S4. S1's acceptance A5 is scoped to S1 and remains true; this spec adds 4 lines in 1 file and the auditor records it explicitly.

---

## 4. Implementation location

| Artifact | Path |
|---|---|
| All rules | `<tree>/packages/phosphor/sepolicy/{public,private}/*.te`, `*_contexts`, `file_contexts`, `seapp_contexts` |
| Neverallow set | `<tree>/packages/phosphor/sepolicy/public/phosphor_neverallows.te` |
| AID names | `<tree>/system/core/libcutils/include/private/android_filesystem_config.h` (+4 lines; the `libcutils` path is load-bearing — the shorter path does not exist) |
| Wiring | `packages/phosphor/phosphor.mk` (`SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` / `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS`, created in S1/§3 B5) |

**Never** in `system/sepolicy/**` directly (fork burden), and **never** in a dir outside the `sepolicy_neverallows` source list (C14 — `neverallow` would be rejected).

---

## 5. Acceptance criteria

**A1 — Policy compiles.** Primary gate:
```bash
m -j24 sepolicy_neverallows selinux_policy
```
Both targets exit 0; the `neverallow` checker reports no violation attributable to a Phosphor rule, and the generated compiled property contexts for the partition our dirs feed — `out/target/product/akita/system/etc/selinux/*property_contexts`, including the `system_ext` variant (`system_ext_property_contexts`) if the tree keeps it separate — contain both Phosphor property rows. **[VERIFY AT BUILD: exact target names and which compiled contexts file `SYSTEM_EXT_*_SEPOLICY_DIRS` (S1 §3 B5) feeds — record it; `selinux_policy` is the intended target and a full `m` also exercises it.]**

**A2 — No dead rule.** For every rule file, run the build's own unused-rule diagnostic if available; otherwise prove liveness by the negative test: remove one `allow` line, rebuild, confirm the build fails for the expected reason, restore. At minimum this is done for `set_prop(phosphor_keygate, phosphor_safeboot_prop)` **and for `set_prop(shell, phosphor_safeboot_latch_prop)`** — a rule that does not compile, or that is granted but never reachable, is not a guarantee.

**A3 — Every claim cited, in-tree, file:line.** The spec-to-policy traceability table (§2) is reproduced in the completion note **with each row re-verified**, and every `neverallow` in the policy names the file:line of the architecture text that requires it. Auditor samples ≥6 rows and re-checks them independently; a citation that does not open to the cited content fails the spec.

**A4 — `:file *` form and the NEW-7 exclusion.** `rg -n 'mmap_exec_file_perms' packages/phosphor/sepolicy` → empty; every file-class `neverallow` ends in `:file *` (or an explicitly enumerated subset, with the reason recorded); `rg -c 'neverallow' packages/phosphor/sepolicy` matches the declared count.

**A5 — R-2 is discharged, including the writer.** Proof that the latch is writable by exactly the documented writer, checked against the **compiled** contexts (not the source, per §6's "Type exists but no context" row):
- `phosphor_safeboot_latch_prop` exists as a distinct type and the compiled context carries it — not `default_prop` (C6/C7):
  ```bash
  rg -n 'phosphor_safeboot_latch_prop' out/target/product/akita/system/etc/selinux/*property_contexts
  ```
  → exactly two rows (`persist.phosphor.safeboot`, `persist.phosphor.agent_state`).
- Exactly one non-init domain (`shell`) holds `set` on it, and the grant is present in the rule source with the §6.5 recovery reasoning:
  ```bash
  rg -n 'set_prop\(shell, phosphor_safeboot_latch_prop\)' packages/phosphor/sepolicy/private/app.te
  rg -n 'phosphor_safeboot_latch_prop:property_service set' packages/phosphor/sepolicy
  ```
  → the grant, plus the `neverallow { domain -shell -init } …:property_service set` line from §3.4 and nothing else.
- **Functional proof the writer is real:** on a boot approved for the purpose, `adb shell setprop persist.phosphor.safeboot 1` succeeds and `getprop persist.phosphor.safeboot` reads `1` with **no** `avc: denied` for `phosphor_safeboot_latch_prop` in `logcat -b all -d`. A `setprop` that is *denied by SELinux* fails this criterion — that is the exact failure this finding was raised for. If PM approval for the device write is withheld, the row is recorded as **policy-compile-verified only, writer not exercised**, and R-2 is claimed no higher (see S8 D3).
- No Phosphor domain holds `set` on it: the §3.4 `neverallow` is the enforcement, not merely an observation.
- The completion note states plainly that **R-2 is closed as a policy item including its writer, and is only *exercised* on a device under S8's drill with PM approval.**

**A6 — V-2's rule exists and is app-scoped.** `get_prop(appdomain, phosphor_safeboot_prop)` present in Phosphor-local `private/app.te`; the completion note states the accepted consequence (every app can read the flag) and that the mirror property is the escape hatch, not the plan.

**A7 — No `set` grant is over-broad.** `rg -n 'property_service set' packages/phosphor/sepolicy` returns exactly these, and nothing else: keygate→`phosphor_safeboot_prop` (via `set_prop`), `shell`→`phosphor_safeboot_latch_prop` (via `set_prop`), the two `neverallow` subtraction/enumeration lines of §3.4, and any explicitly justified init/host grant recorded in the completion note. Any additional `allow … set` line fails — including any `allow` giving a Phosphor domain the latch or giving `shell` the decision.

**A8 — Domain inventory matches §2.1 exactly: four Phosphor domains, and `phosphor-ctl` is not one of them.**
```bash
rg -c 'type phosphor_.*, domain;' packages/phosphor/sepolicy   # -> 4
```
The four are `phosphor_keygate`, `phosphor_agentd`, `phosphor_broker`, `phosphor_shell` — nothing else. Four AIDs (§3.6), four `seapp_contexts`/`file_contexts` domain labels.

**The `phosphor-ctl` decision, recorded here so it is not re-opened in S8** (this is F5's resolution, and S8 A4 asserts it rather than asking it): S1 installs **five modules**, but only **four** of them are Phosphor *processes* in the architecture §2.1 sense. `phosphor-ctl` is a read-only, permission-free diagnostics binary invoked on demand from `adb shell`; it creates no init service, holds no capability, and owns no property or file it writes (S8 §1 non-goals, §2.1). It therefore runs in the **existing `shell` domain**:

- **no fifth `phosphor_*` domain** and no `phosphor_ctl` type — `rg -c 'type phosphor_.*, domain;'` stays 4;
- **no fifth AID** — it runs as `shell`'s UID, so §3.6 stays at four AIDs and the AID edit stays at exactly 4 lines (A9);
- **no policy rule of its own** — its reads (`sys.phosphor.safeboot`, `init.svc.*`, `persist.*`, the health file) are ordinary `shell` reads; if one turns out to need a grant that `shell` lacks, the grant is added to `shell` for that **one documented read** with the reason recorded, and still no new domain is created;
- consequence stated: the diagnostics tool cannot exceed what `adb shell` can already do, which is exactly S8's "zero privilege" non-goal — a diagnostics tool that needed its own privileged domain would be a backdoor.

So "five installed modules, four Phosphor domains" is the **correct** invariant, not a contradiction: S1 §1 and A3 count *installed modules*; this criterion counts *domains*. The question S8 A4 originally deferred to S2 ("does `phosphor-ctl` need a fifth domain?") is **closed here: no** — S8 A4 now asserts this outcome, and S8 §7 open item 1 is closed against this criterion.

**A9 — Third-party surface declared.** Exactly one new file edited (`system/core/libcutils/include/private/android_filesystem_config.h`, 4 lines) and zero files in `system/sepolicy/**` touched. `repo status` attached.

**A10 — Fail-closed audit of polarity.** The policy must not contain a rule that lets any Phosphor domain **clear** a safe boot. Stated test: no Phosphor domain holds `set` on `phosphor_safeboot_prop` except keygate (C8: value is unpoliceable, so the guarantee is *access*, per NEW-6(a)).

---

## 6. Edge cases and failure modes

| Case | Required handling |
|---|---|
| `neverallow` in a device dir | Must compile-fail. Confirm C14 first (the dir must be in the `sepolicy_neverallows` source list at `system/sepolicy/Android.bp:943`); if the tree rejects it, the fix is the dir choice, **never** deleting the rule. |
| `mmap_exec_file_perms` reintroduced by a helpful editor | Build fails. Cite NEW-7/C11 and restore `:file *`. |
| `set_prop(shell, …)` looks like granting the adb user the latch | It is the *point*: the documented writer is the host over adb (`adb shell setprop persist.phosphor.safeboot 1`), and `shell` is that path. The set-only semantics are **not** weakened — C8/C9 mean the rule cannot see a value at all, so "absent→1 only, 0 ignored" remains enforced in keygate's binary (S3 §2.1/2.2), and A10 still forbids any Phosphor domain clearing a safe boot. If someone proposes granting the latch to `phosphor_shell`/`agentd`/`keygate`/`broker` "so it can be cleared on-device", that is a **refused** change: it destroys the one-way property. |
| A future rule gives another domain `set` on the latch | §3.4's `neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set` (checked by A5/A7) makes it a **compile error**, which is the intent: "exactly one writer" is enforced, not merely observed. |
| `neverallow phosphor_keygate { system_prop -phosphor_safeboot_prop }:property_service set` — subtraction syntax | C10 shows the in-tree shape; if the build rejects the exact string, use the enumerated alternative and record it. Do not fall back to the blanket form (§8 explicitly forbids it). |
| `exact bool` on a `persist.*` property | `persist.*` is `string`; use `exact string` for the latch (see §3.1) and keep `exact bool` only for the `sys.*` decision. Mixing them fails at init property-load time, not at build time — a silent-late failure. |
| Latch value semantics | `persist.*` must be non-empty; init rejects empty values for `persist.`. `setprop persist.phosphor.safeboot 1` is the only meaningful write. |
| Type exists but no context | Property falls back to `default_prop` (C6) and *silently* loses the grant. A4/A5's `rg` on the **compiled** contexts files is the check, not on the source. |
| `app_domain()` needs a matching `seapp_contexts` entry | Both halves or the app runs as `untrusted_app` and none of the grants apply — silently. A3's liveness proof covers it. |
| Four AIDs collide with an existing OEM AID | `[VERIFY]` at C15; a collision is an SELinux *and* a filesystem-ownership fault. |
| `get_prop(appdomain, …)` looks like over-grant | It is intended (§3.3) and mirrors `app.te:40`. Do not narrow it to our two packages without recording why — the safe-boot flag must be readable by anything that must decide whether to be the surface. |

---

## 7. Definition of done / auditor checklist

- [ ] A1–A10 pass with attached evidence.
- [ ] Type table: **4 domains** (`phosphor_keygate`, `phosphor_agentd`, `phosphor_broker`, `phosphor_shell` — `phosphor-ctl` is not a domain, A8), **4 AIDs**, 3 property types (`phosphor_safeboot_prop`, `phosphor_safeboot_latch_prop`, plus agent_state sharing the latch type), 4 file types.
- [ ] Every `neverallow` traces to a §8 line, cited file:line.
- [ ] **R-2 closed as policy, with its writer**: latch type + `set_prop(shell, phosphor_safeboot_latch_prop)` + the `neverallow` that keeps it to exactly one non-init domain — and explicitly *not* claimed as device-verified until S8's drill runs.
- [ ] **V-2's `get_prop` rule present**, app-scoped, consequence stated.
- [ ] **NEW-7 honoured**: no `mmap_exec_file_perms`; `:file *`.
- [ ] **NEW-4 honoured**: `phosphor_risk_policy_file` typed, write-banned across all four domains, read granted to agentd+broker only, absent for shell.
- [ ] Zero edits under `system/sepolicy/**`; exactly one 4-line third-party edit declared, at `system/core/libcutils/include/private/android_filesystem_config.h`.
- [ ] No device operation performed.

## 8. Open items created by this spec

1. Actual sepolicy build target names in this tree (§5 A1) — builder.
2. Concrete agentd device-node type list (§3.4 note) — builder, from `vendor/google_devices/akita`.
3. `neverallow … self:binder *` enumeration legality (§3.4 note) — builder, resolved by compiler diagnostic.
4. AID numbers confirmed free (§3.6) — builder.
5. Whether `ro.boot.phosphor.safeboot` is readable by `phosphor_keygate` under its default `boot_prop`/`system_prop` context or needs an explicit `get_prop` — **carried from §10.2; gates S3, not S2's compilation.**
6. ~~Does `phosphor-ctl` need a fifth domain?~~ — **CLOSED (F5):** no. It runs in the existing `shell` domain: no fifth `phosphor_*` domain, no fifth AID, no rule of its own (§5 A8). S8 A4 asserts this outcome instead of re-opening it; the follow-up is only S8's wording alignment, not a policy change.
7. `neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set` (§3.4) — confirm the enumeration/subtraction form compiles in this tree; if `-init` is unnecessary because `init` is not in `domain` in the relevant sense, drop the subtraction and record it, but never drop the line.
