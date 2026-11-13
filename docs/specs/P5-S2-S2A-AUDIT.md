# P5-S2 BETWEEN-PHASE AUDIT — S2-A policy plan (author round)

**Date:** 2026-11-12
**Auditor:** Debugger (adversarialDebugger.md, sections 1–11, loaded fresh this session)
**Target:** `docs/handoffs/P5-S2-POLICY-PLAN.md` (342 lines, author round)
**Authorities checked:** `docs/specs/P5-S2-selinux-foundation.md` (spec, verbatim §3.1–3.5), `docs/specs/P5-S2-PREFLIGHT-PROBE.md` (my own, 7 standing rulings), `docs/specs/P5-S2-PHASE-INSTRUCTIONS.md` (S2-A scope + 7 rulings), `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` rev 4 §8 (lines 410–418), live tree `~/projects/grapheneos-2026091900` (read-only), `Phosphor-platform` / `.git` mirror / `.repo` manifest wiring.
**Word marker:** please proceed. READ-ONLY — nothing modified.

Verdict legend per check: **PASS** (with command+output), **BUG #N** (assumption violated, with attack/repro/root cause/fix).

---

## Check 1 — every .te rule against spec §3.1–3.5 byte-for-byte (where verbatim) + 7 standing rulings

**1a. `property.te` (artifact 1) — spec §3.1.** Spec block (`docs/specs/P5-S2-selinux-foundation.md` §3.1, lines 63–74) vs plan §1 (lines 36–47): byte-identical — 2 `system_public_prop()` decls (`phosphor_safeboot_prop`, `phosphor_safeboot_latch_prop`), same comments, same blank line, same `--` ASCII dashes (not em-dashes). **PASS.** Rulings 1/2/3 n/a (property decls). NEW-7 n/a.

**1b. `property_contexts` (artifact 2) — spec §3.1.** Plan §2 (lines 54–58) vs spec (lines 80–82): 3 rows byte-identical (`sys.phosphor.safeboot … exact bool`, `persist.phosphor.safeboot … exact string`, `persist.phosphor.agent_state … exact string`), same alignment spacing (plan's §2 provenance even documents the "three spaces before `u:object_r`" requirement). **PASS.**

**1c. `phosphor_keygate.te` (artifact 3) — spec §3.2 + §3.4.** Plan §3 (lines 65–79): `type phosphor_keygate, domain;`, `type phosphor_keygate_exec, exec_type, file_type, system_file_type;`, `init_daemon_domain(phosphor_keygate)`, `set_prop(phosphor_keygate, phosphor_safeboot_prop)`, `get_prop(phosphor_keygate, phosphor_safeboot_latch_prop)` — all four byte-identical to spec lines 93–101. The 5th block (subtraction neverallow, line 79) is flagged as an S2-A clarification (materializing the §3.4 line rather than leaving it as prose) — same line appears verbatim in artifact 10 (line 180), consistent, and matches spec §3.4 line 156 exactly. **PASS.** Ruling 2 applies to binder (artifact 10), not here.

**1d. `phosphor_agentd.te` (artifact 4) — spec §3.2.** Plan §4 (lines 87–94): byte-identical to spec lines 109–116: `get_prop(phosphor_agentd, phosphor_safeboot_prop)       # to log/verify its own start condition` (7 spaces before `#`, matches), `allow phosphor_agentd phosphor_risk_policy_file:file r_file_perms;`, `allow phosphor_agentd phosphor_agentd_data_file:dir create_dir_perms;`, `allow phosphor_agentd phosphor_agentd_data_file:{ file lnk_file } create_file_perms;`. **PASS.**

**1e. `phosphor_broker.te` / `phosphor_shell.te` (artifact 5) — spec §3.2.** Plan §5 (lines 103–118): broker = `type phosphor_broker, domain;` + `app_domain(phosphor_broker)` + `allow phosphor_broker phosphor_risk_policy_file:file r_file_perms;` (matches spec line 119 + §6.3); shell = type + app_domain + no allow line (spec: "shell gets no access to the policy artifact at all"). Both correct, with the `app_domain()` caveat documented (preflight 8-7/8-8: macro does not declare the type; trio = type + macro + seapp row). **PASS.**

**1f. `file.te` (artifact 6) — spec §3.5.** Plan §6 (lines 125–126): `type phosphor_risk_policy_file, file_type, system_file_type;` + `type phosphor_agentd_data_file, file_type, data_file_type;` — byte-identical to spec §3.5 (lines 193–194). Four-file-type inventory note consistent with spec §7 checklist. **PASS.**

**1g. `file_contexts` (artifact 7) — spec §3.5.** Plan §7 (lines 134–137): 4 rows byte-identical to spec §3.5 (lines 200–203): `/system/etc/phosphor(/.*)?` → `phosphor_risk_policy_file`, `/system/bin/phosphor-agentd` → `phosphor_agentd_exec`, `/system/bin/phosphor-keygate` → `phosphor_keygate_exec`, `/data/misc/phosphor(/.*)?` → `phosphor_agentd_data_file`. **PASS.** (Context-line correctness — `system_ext` vs `system` partition — see BUG #7 below.)

**1h. `seapp_contexts` (artifact 8) — spec §3.5 + standing ruling 1.** Plan §8 (lines 145–146): 2 rows byte-identical to spec §3.5 (lines 209–210) (`user=_app isPrivApp=true seinfo=platform name=com.phosphor.shell|broker domain=… type=privapp_data_file levelFrom=user`), placed in `sepolicy/private/` — **ruling 1 applied correctly** (preflight 8-7: seapp_contexts is private-only; precedent source = `vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts`, which I verified exists). Erratum ① recorded in Related issues #1. **PASS on ruling 1.** See BUG #6 (seinfo=platform + MAC policy) and BUG #8 (row-shape precedent) for content caveats.

**1i. `app.te` (artifact 9) — spec §3.3.** Plan §9 (lines 154–166): byte-identical to spec §3.3 (lines 126–138): `get_prop(appdomain, phosphor_safeboot_prop)` + `set_prop(shell, phosphor_safeboot_latch_prop)` with all comments. Phosphor-local file, zero third-party surface — matches spec §3.3 "do NOT edit system/sepolicy/private/app.te". **PASS.**

**1j. `phosphor_neverallows.te` (artifact 10) — spec §3.4 + rulings 2/3.** Plan §10 (lines 174–219) vs spec §3.4 (lines 150–180):
- keygate file denials (2 lines): byte-identical.
- keygate subtraction neverallow: byte-identical.
- keygate binder: spec's `neverallow phosphor_keygate self:binder *;` **replaced** by `neverallow phosphor_keygate self:binder { call transfer };` — **ruling 2 applied correctly** (preflight 8-3: zero tree precedent for `self:binder *`; enumerated form matches in-tree binder neverallows). Note: spec §3.4's own note already flagged `*` as needing resolution; the ruling is the documented resolution. **PASS.**
- keygate tcp/udp: byte-identical (`self:tcp_socket *;` / `self:udp_socket *;` — socket classes accept `*` per `access_vectors`; the `*`-op restriction was binder-specific).
- agentd device nodes: spec §3.4's **prose** line ("{ device node surfaces that back telephony, camera, location, and radio netlink }") **replaced** by 4 concrete lines — **ruling 3 applied**: `radio_device`, `camera_device`, `vendor_gnss_device`, `modem_userdata_block_device` (all `:file *`). All four types verified in tree: `system/sepolicy/public/device.te:11` (`camera_device`), `:20` (`radio_device`), `vendor/google_devices/akita/sepolicy/vendor/types.te:341` (`vendor_gnss_device`), `:112` (`modem_userdata_block_device`). Categories named: telephony/radio (radio_device), camera (camera_device), location/GNSS (vendor_gnss_device), modem userdata (modem_userdata_block_device) — 4/4 categories. **PASS on ruling 3**, with BUG #2 (netlink category) below.
- agentd binder (line 206): `neverallow phosphor_agentd { domain -phosphor_broker -self }:binder call;` — byte-identical to spec §3.4 line 167. Matches arch §8 line 413. **PASS.**
- latch neverallow (line 212): `neverallow { domain -shell -init } phosphor_safeboot_latch_prop:property_service set;` — byte-identical to spec §3.4 line 173. Compiles? Subtraction-on-set precedent verified in tree (`property.te:193-196`, `:310-321`); the `-init` exclusion is safe (init is in `domain` but excluded; `-shell` needed because `set_prop(shell, …)` grants it). **PASS** (open item 7 compile-confirm is a build-time check, correctly left as such).
- shell binder (line 215): byte-identical to spec §3.4 line 176. **PASS.**
- policy artifact write-ban (lines 218–219): byte-identical to spec §3.4 lines 179–180 (`neverallow { … } phosphor_risk_policy_file:file { write append create rename setattr unlink };`). **PASS** (NEW-4 honoured; NEW-7: `:file *` form, zero `mmap_exec_file_perms`).
- Arch §8 citation mapping: verified against `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` §8 lines 410–418 — line 412 = agentd device-node bullet, 413 = agentd binder, 414 = shell binder, 415 = policy artifact, 416–417 = keygate file + property, 418 = keygate binder/network. All citations correct. **PASS.**

**Check 1 verdict: PASS on all 10 artifacts** (with 4 content caveats filed as BUG #2, #4, #5, #6 below).

---

## Check 2 — syntax-level validity of every rule (vs in-tree precedent)

- `system_public_prop(name)` — macro at `te_macros:956` → `define_prop($1, system, public)` → `type $1, property_type, system_property_type, system_public_property_type;`. Args: 1 identifier. Plan's 2 uses: valid. **PASS.**
- `init_daemon_domain(domain)` — `te_macros:163` → `domain_auto_trans(init, $1_exec, $1)`. Requires `$1_exec` entrypoint declared; plan declares `phosphor_keygate_exec`/`phosphor_agentd_exec` as `exec_type, file_type` — valid. **PASS.**
- `app_domain(domain)` — `te_macros:185`; sets `typeattribute $1 appdomain` + neverallows; does not declare type — plan declares `type phosphor_broker, domain;` first — valid trio. **PASS.**
- `set_prop(domain, prop)` — `te_macros:374-378` → `unix_socket_connect($1, property, init); allow $1 $2:property_service set; get_prop($1, $2)`. Both uses valid (keygate→safeboot, shell→latch). **PASS.**
- `get_prop(domain, prop)` — `te_macros:385-387` → `allow $1 $2:file { getattr open read map };`. Both uses valid. **PASS.**
- `type X, domain;` / `type X, exec_type, file_type, system_file_type;` / `type X, file_type, data_file_type;` — standard declarations, all types named in `file.te`/`device.te`/`access_vectors`. **PASS.**
- `allow … :file r_file_perms;` / `:dir create_dir_perms;` / `:{ file lnk_file } create_file_perms;` — macro perms from `global_macros:25-35` (C11); `create_dir_perms` used by agentd data dir. **PASS.**
- `neverallow` forms: subtraction-on-set (`property.te:193-196`), set-of-domains + single type + perm set (`installd.te:240`, `netd.te:205`), `self:` target + enumerated ops (`storaged.te:69` uses `self:capability_class_set *`), set-of-types + perm set (`domain.te:2271-2272`), `{ type -type }:property_service set` (`property.te:193-196`). All plan forms have direct in-tree precedent. **PASS.**
- `set_prop(shell, …)` precedent: `microdroid/system/private/shell.te:104-111` (live tree) — **PASS.**
- No rule uses `mmap_exec_file_perms` (C11/NEW-7) — verified zero hits in tree. **PASS.**

**Check 2 verdict: PASS.**

---

## Check 3 — the AID diff (4 lines, OEM range, no collision, anchor honest)

- 4 lines (plan §11, lines 233–236): `AID_PHOSPHOR_KEYGATE 2950`, `AGENTD 2951`, `BROKER 2952`, `SHELL 2953` — exactly 4 lines, correct spelling of the header macro form (`#define AID_X   N`). **PASS on count/shape.**
- OEM range: `AID_OEM_RESERVED_START 2900` / `AID_OEM_RESERVED_END 2999` (preflight §8-4, verified at `system/core/libcutils/include/private/android_filesystem_config.h:171-172`). 2950–2953 ∈ [2900, 2999]. **PASS.**
- No collision: preflight §8-4 header grep `\b29(4[5-9]|5[0-9])\b` → zero hits; plan carries the belt-and-braces `rg -n '2950|2951|2952|2953' system/core/` gate (line 239). **PASS** (header-level; full-tree at build).
- Anchor statement honest: plan line 228 says "the OEM range is at lines 171–172 (`AID_OEM_RESERVED_START 2900` / `AID_OEM_RESERVED_END 2999` — preflight §8-4)". **These are real, preflight-verified line numbers** (preflight §8-4: "`system/core/libcutils/include/private/android_filesystem_config.h:171-172`"). The line numbers are not invented. However: the plan's own global rule (line 6) defines **[EXECUTED — tree]** as "run by Coder via read_file/search_files against TREE" — and the plan §11 does **not** claim an executed read; it cites the preflight. The claim is traceable to a real prior verification (mine). The anchor is honest as a *citation*, but see BUG #3 (the Coder seat cannot re-verify it this round; the [EXPECT AT BUILD] label on the insertion mechanics is the right risk treatment). **PASS with note.**

**Check 3 verdict: PASS** (anchor honest; insertion mechanics correctly tagged [EXPECT AT BUILD]; one nit — the plan's line 239 gate `rg -n '2950|…' system/core/` expects "only the 4 new lines" but `system/core` contains prebuilt copies of the header? — no: prebuilts are excluded from `system/core` tree; verified no other `2950` hits in `system/core` at preflight time. Fine.)

---

## Check 4 — commit / mirror / sync command sequence

- **Order (S2-B.1 → B.6):** transcribe SRCREPO → `git add` + `commit` → `NEW_HEAD` captured → mirror `fetch origin` + FETCH_HEAD gate + `update-ref` → `repo sync packages/phosphor` → HEAD/porcelain checks → AID edit → build → A1–A10. Payload-flow (SRCREPO → MIRROR → TREE) matches PHASE-INSTRUCTIONS §"S2 payload flow" and plan global rule 3. **Correct order. PASS.**
- **Expected outputs executable, not imagined:** B.1 `git status --porcelain` expect `??` new files (executable); B.2 `remote -v` / `fetch` / `rev-parse FETCH_HEAD` / `update-ref` / `rev-parse` (all real git plumbing); B.3 `repo sync` + `git -C … rev-parse HEAD` + `status --porcelain` (real); B.4 greps (real); B.5 `m` (real); B.6 `rg` greps with presence guards (real). No invented output strings — the only expected strings are git's own (`??`, `40-hex`, `(empty)`), all labelled or self-evident. **PASS on executed-evidence rule (check 6).**
- **Exit-code gates:** B.2 has `test … || { echo 'FETCH_HEAD != NEW_HEAD — hard stop'; exit 1; }`. B.5 relies on `m`'s own exit status ("both exit 0"). B.1/B.3/B.4/B.6 use "expect:" comments but **no explicit `exit 1` gates** — the plan's global rule 1 ("Stop-and-report on any mismatch") covers this procedurally, and rule 5 requires grep exit status captured. **PASS (procedural gates; B.2/B.5 have hard gates, B.1/B.3/B.4/B.6 are human-gated by rule 1).**
- **No dirty-payload path:** global rule 3 forbids direct tree edits; B.1's `git add packages/phosphor/sepolicy` is in SRCREPO (the payload repo), not the tree; B.3's `git -C packages/phosphor status --porcelain` expects empty. **PASS.**

**BUG #2 (in this check's blast radius — see full text below): the mirror's `origin` remote.** Plan B.2 asserts "The mirror is a local bare clone of SRCREPO (S1 created it with `git clone --bare SRCREPO MIRROR`), so its `origin` is SRCREPO" and gates `remote -v` → "origin -> SRCREPO". **Assumption not re-verified this round.** If S1 created the mirror differently (e.g. `git init --bare` + `remote add`, or a different URL), `fetch origin` fetches from the wrong place or fails. The plan does gate it (`remote -v` expected output), but the *expectation itself* is an assumption about S1's action, not an executed fact. It is labelled as expectation, so the stop-and-report rule would catch a mismatch — **but the fix is cheap and the assumption is load-bearing for B.2/B.3.** See BUG #2.

**BUG #3 (in this check's blast radius):** `repo sync packages/phosphor` — the manifest's project name is `Phosphor-platform.git` (from `.repo/local_manifests/phosphor.xml`), path `packages/phosphor`. `repo sync` accepts either project name or path; `repo sync packages/phosphor` (path) works. **PASS** (verified manifest: `.repo/local_manifests/phosphor.xml` → `<project name="Phosphor-platform.git" path="packages/phosphor" remote="phosphor" revision="refs/heads/main" />`; remote `phosphor` fetch = `file:///home/cptjaqx/projects`; so mirror is `Phosphor-platform.git` at `file:///home/cptjaqx/projects` — matches MIRROR path. Sync will fetch from MIRROR, which B.2 has updated. **PASS.**)

**Check 4 verdict: PASS** with BUG #2 (mirror origin assumption) — the sequence is correct, executable, and dirty-payload-free; the one load-bearing unverified assumption is the mirror's origin, and the plan's `remote -v` gate catches it but the *expected* value is an S1-history assumption, not an executed fact.

---

## Check 5 — spec §5 A1–A10 evidence plan coverage

- **A1** (policy compiles): B.5 `m -j24 sepolicy_neverallows selinux_policy` + B.6 A1 `rg` on `out/target/product/akita/*/etc/selinux/*property_contexts` (record actual filenames, [EXPECT AT BUILD]). Covers A1's compile + contexts-row requirement. **PASS.**
- **A2** (no dead rule): B.6 A2 — "liveness negative test — remove ONE set_prop line, rebuild, confirm the expected failure, restore. Done for BOTH set_prop(phosphor_keygate, phosphor_safeboot_prop) and set_prop(shell, phosphor_safeboot_latch_prop)." **Both set_prop rules covered.** **PASS.**
- **A3** (citations): B.6 A3 — every neverallow carries arch §8 file:line; C1–C15 re-verified. **PASS.**
- **A4** (`:file *` / NEW-7): B.6 A4 — `rg mmap_exec_file_perms` empty + `rg -c neverallow` matches declared count. **PASS.**
- **A5** (R-2 discharged): B.6 A5 — `rg phosphor_safeboot_latch_prop` in compiled contexts → 2 rows; `rg set_prop\(shell, phosphor_safeboot_latch_prop\)` in private/app.te; the §3.4 neverallow grep. Compiled-contexts check present (spec's "checked against the compiled contexts, not the source" honoured). **PASS.**
- **A6** (V-2 rule): B.6 A6 — `rg get_prop\(appdomain, phosphor_safeboot_prop\)` in private/app.te. **PASS.**
- **A7** (no over-broad set): B.6 A7 — `rg 'property_service set'` returns exactly the declared set. **PASS.**
- **A8** (4 domains): B.6 A8 — `rg -c 'type phosphor_.*, domain;'` → 4. **PASS.**
- **A9** (third-party surface): B.6 A9 — `repo status` expect `vendor/adevtool` baseline + `system/core` 4-line + phosphor clean. **PASS.**
- **A10** (polarity): B.6 A10 — no Phosphor domain holds `set` on `phosphor_safeboot_prop` except keygate. **PASS.**

**Check 5 verdict: PASS** — all A1–A10 have a planned evidence step; A2's both-set_prop negative test and A5's compiled-contexts check (the two the brief called out) are both present and correctly shaped.

---

## Check 6 — the fraudulent-expectation class

Every expected string in the plan is either:
- a git/`m` self-evident output (`??`, 40-hex, `(empty)`, exit 0) — executable;
- labelled **[QUOTED FROM SOURCE]** (artifacts 1–10, spec §3.1–3.5 verbatim);
- labelled **[EXPECT AT BUILD]** (compiled-context filenames, AID insertion context, radio-netlink line, akita seapp row shape);
- or an explicit "expect:" comment tied to a real command (B.1–B.4, B.6).

**No string in the plan is presented as executed output that was not executed.** The one grey area: plan line 6 claims Coder "can read [TREE] for verification but cannot write" — Coder's seat indeed has read access (S2-A is an author round; Coder read TREE files during preflight? No — preflight was mine). Coder did **not** run any tree command this round; every tree fact in the plan is either [QUOTED FROM SOURCE] or [EXPECT AT BUILD]. **PASS** — the executed-evidence rule is honoured. (The plan's own global rule 6 — "`rg -n 'pattern' dir` prints 0 lines when dir is absent" — is the correct defensive posture and is stated.)

**Check 6 verdict: PASS.**

---

## Check 7 — anything that would compile-fail or silently no-op

This is where the findings are. Full BUG format below; summary:

| # | Severity | One-line |
|---|---|---|
| BUG #1 | MEDIUM | `get_prop(appdomain, phosphor_safeboot_prop)` grants the prop **file** read to all 24+ app domains; `property.te:193-196`'s `neverallow { domain -coredomain } { system_property_type … -system_public_property_type }:file no_rw_file_perms` may make the allow **redundant** (harmless) or the policy **compile-fail** (if `system_public_property_type` is not in the subtraction's set) — must be confirmed at build; plan doesn't mention the interaction |
| BUG #2 | MEDIUM | Radio-netlink socket type: **no `netlink_radio_socket` exists in this tree** (verified: zero hits; all 17 `netlink_*` classes in `access_vectors`; `radio.te` uses only `net_domain(radio)` → `netlink_selinux_socket`). The `[EXPECT AT BUILD]` line will find nothing to instantiate → category silently dropped. Pre-resolve to `netlink_generic_socket` (the class telephony HALs use) or drop the netlink line with a recorded reason |
| BUG #3 | MEDIUM | Mirror `origin` remote assumption (S1 history) unverified this round — B.2's `remote -v` gate catches it but the expected value is an assumption; one `git --git-dir=MIRROR remote -v` now would close it |
| BUG #4 | LOW | `set_prop(shell, phosphor_safeboot_latch_prop)` contradicts NEW-6 (arch rev-4): the latch is declared `system_public_prop` → `system_public_property_type`; the latch neverallow `{ domain -shell -init }` is the enforcement, but `set_prop` also expands to `get_prop` (read grant to shell) — harmless; the real issue is spec-level (R-2 discharge wording) not plan-level. Plan quotes spec verbatim — **not a plan bug**; record as spec-level erratum for PM |
| BUG #5 | LOW | `neverallow phosphor_keygate self:binder { call transfer };` — `transfer` is a binder op but **not** in the `call`-family the in-tree precedents use (`:binder call` only); enumerating `transfer` is *stricter* than precedent and valid, but if the compiler treats `{ call transfer }` as "deny these two, allow others" it could allow `impersonate`/`set_context_mgr` — `impersonate` is a real binder op. Safer: `neverallow phosphor_keygate self:binder call;` + separate `neverallow phosphor_keygate self:binder transfer;` or `~{ set_context_mgr impersonate }` form. Build-check needed |
| BUG #6 | LOW | `seinfo=platform` + `isPrivApp=true` rows: the platform seinfo is keyed to the platform signature in `mac_permissions.xml`; if the apps are not platform-signed, the row never matches → domains never applied → silent no-op (app runs as `untrusted_app`). Precedent rows in akita seapp_contexts mostly use `levelFrom=all` and no `seinfo=` on priv-app rows (`isPrivApp=true name=… domain=… levelFrom=all`). Plan copies spec rows verbatim (correct per spec) but the row shape is unprecedented in live plat policy (preflight 8-7) — verify `mac_permissions.xml` has a `platform` seinfo for our signature at build |
| BUG #7 | LOW | `/system/etc/phosphor(/.*)?` + `/system/bin/phosphor-*` + `/data/misc/phosphor` in `public/file_contexts`: the packages are `SYSTEM_EXT_*` (phosphor.mk installs to system_ext), but S1's `PRODUCT_COPY_FILES` copies risk-policy.json to `$(TARGET_COPY_OUT_SYSTEM)/etc/phosphor/` — so the policy file really is on `system`, and the bins are `PRODUCT_PACKAGES` → `/system_ext/bin/`. **`/system/bin/phosphor-agentd` may be the wrong path** (should be `/system_ext/bin/…` if the bins land on system_ext) → file_contexts rows silently never match → no exec labels → domains can't be entered. Verify where S1's modules actually install |
| BUG #8 | LOW | seapp_contexts row shape: `levelFrom=user` vs akita precedent `levelFrom=all`; `seinfo=platform` requires platform seinfo in `mac_permissions.xml`; if `PhosphorShell`/`PhosphorBroker` are not platform-signed the rows are dead. Plan labels the row shape [EXPECT AT BUILD] — correct — but should add the signing precondition to the build checklist |

---

## Full BUG entries

```
BUG #1
Severity: MEDIUM
Assumption violated: get_prop(appdomain, phosphor_safeboot_prop) is a clean, sufficient grant with no interaction with existing neverallows.
Attack vector: simulate the policy compile: appdomain expands to 24+ domains incl. shell, radio, system_server-adjacent app domains; the allow grants each `phosphor_safeboot_prop:file { getattr open read map }`. Meanwhile property.te:193-196 asserts neverallow { domain -coredomain } { system_property_type system_internal_property_type -system_restricted_property_type -system_public_property_type }:file no_rw_file_perms. If phosphor_safeboot_prop is a member of (system_property_type ∪ system_internal_property_type) \ (system_restricted ∪ system_public), the allow directly violates the neverallow → compile fail. If it is not (because system_public_property_type includes it), the neverallow does not apply and the allow is redundant-but-harmless.
Reproduction: check macro expansion: system_public_prop(phosphor_safeboot_prop) → type phosphor_safeboot_prop, property_type, system_property_type, system_public_property_type. Then test membership: is system_public_property_type in the subtraction set of property.te:193? The subtraction set is { system_property_type, system_internal_property_type } minus { system_restricted_property_type, system_public_property_type } — so system_public_property_type is SUBTRACTED OUT. Therefore phosphor_safeboot_prop is NOT in the neverallow's type set → the allow does not violate it. COMPILE SAFE. BUT: verify system_public_property_type actually contains phosphor_safeboot_prop via the attribute (system_public_prop macro adds it — C5 verified) — yes. So no compile fail.
Root cause: none — after full expansion, the allow is safe (phosphor_safeboot_prop is system_public_property_type, which the neverallow subtracts out).
Fix: none required for compile. BUT the plan should record this interaction in the completion note (the get_prop grant is redundant with property.te:193-196's subtraction — harmless but a reader may flag it). Severity downgraded to LOW.
```

```
BUG #2
Severity: MEDIUM
Assumption violated: a "radio netlink" socket type exists in the compiled policy to instantiate the [EXPECT AT BUILD] line with.
Attack vector: rg -rn 'netlink.*radio|radio.*netlink' system/sepolicy vendor/google_devices/akita --include='*.te' --include='access_vectors' → ZERO hits. The 17 netlink_* socket classes in access_vectors (lines 260-549) are all generic (netlink_socket, netlink_route_socket, … netlink_generic_socket); radio.te uses net_domain(radio) → netlink_selinux_socket only; no radio-specific netlink socket type exists. The placeholder line neverallow phosphor_agentd <netlink_radio_socket_type>:socket_class_set *; will find no type → category silently dropped.
Reproduction: rg -n '^class netlink' system/sepolicy/private/access_vectors (17 classes, none radio); rg -n 'radio' system/sepolicy/public/radio.te (only net_domain(radio)).
Root cause: preflight §8-2 flagged the netlink type as unconfirmed; the plan carried it as [EXPECT AT BUILD] but the build will confirm ABSENCE, not presence. The plan's own rule ("must name the category, non-empty") would then either fabricate a type (compile fail) or drop the line (silent guarantee loss).
Fix: pre-resolve now: the concrete netlink surface for telephony in this tree is netlink_generic_socket (used by hal_telephony_server per hal_telephony.te:35) and netlink_selinux_socket (net_domain macro). Write the line as neverallow phosphor_agentd netlink_generic_socket:socket_class_set *; OR record in the plan that the radio-netlink category is covered by the existing selinux restriction (agentd gets no netlink_socket allow at all) and drop the placeholder with a recorded reason. Update plan §10 + Related issue #2.
```

```
BUG #3
Severity: MEDIUM
Assumption violated: the bare mirror's origin remote points at SRCREPO (S1 created it with `git clone --bare SRCREPO MIRROR`).
Attack vector: S1's actual mirror creation is not in the S2-A context; if S1 used `git init --bare` + `git remote add origin <url>` with a different URL (or no origin at all), B.2's `git fetch origin` fetches from the wrong place or fails. The plan gates this (remote -v expected → origin -> SRCREPO) but the expected value is an S1-history assumption, not an executed fact this round.
Reproduction: git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git remote -v (run by Supervisor at B.2; would show actual origin).
Root cause: payload-flow correctness depends on mirror provenance that S2-A did not verify and cannot verify from the tree alone.
Fix: one command now (by Supervisor or me): git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git remote -v — if origin != SRCREPO, B.2's first step is `git remote set-url origin /home/cptjaqx/projects/Phosphor-platform` (or `git remote add origin …`). Add to plan B.2 as a pre-check: "if remote -v shows no origin or wrong URL → set it, record the correction".
```

```
BUG #4
Severity: LOW
Assumption violated: none at plan level — this is a spec-level note. set_prop(shell, phosphor_safeboot_latch_prop) grants shell BOTH set and read (get_prop) on the latch; NEW-6 (arch rev-4) says the latch is set-only for the host and the one-way property rests on "noPhosphor domain holds set". The plan quotes the spec verbatim (correct). The residual issue: the latch prop is system_public_prop (readable by any app via get_prop(appdomain, …) only if separately granted — it is not, so only shell + init + keygate read it). This is consistent with §6.5. No plan change; record as spec-level erratum for PM: "R-2 discharge wording: latch is system_public_prop; shell's set_prop also grants read — harmless; the one-way property is enforcement (neverallow), not observation."
Root cause: spec's R-2 narrative vs macro expansion (set_prop = set + get).
Fix: PM erratum; no plan change.
```

```
BUG #5
Severity: LOW
Assumption violated: `{ call transfer }` enumerated binder neverallow is the safest enumerated form.
Attack vector: binder class ops are { impersonate call set_context_mgr transfer } (access_vectors:520-526). The plan denies { call transfer } but not impersonate/set_context_mgr. If the neverallow checker treats an enumerated op set as exhaustive-deny (deny exactly these, allow the rest), then impersonate and set_context_mgr remain allowed for keygate. In-tree precedents use `:binder call` only (installd.te:240, netd.te:205) — the tree never enumerates transfer in a neverallow.
Reproduction: rg -n 'self:binder' system/sepolicy (zero hits — no self:binder precedent at all); rg -n ':binder (call|transfer)' system/sepolicy/private/*.te | head (only :binder call).
Root cause: the enumerated form { call transfer } is stricter than precedent on transfer but leaves impersonate/set_context_mgr open if the checker is exhaustive-deny. The spec's intent ("keygate has no binder") is better served by neverallow phosphor_keygate self:binder *; — which ruling 2 rejected for zero precedent. Compromise: neverallow phosphor_keygate self:binder { call transfer set_context_mgr impersonate }; (all four ops) — still enumerated, still no `*`, and matches the class definition exactly.
Fix: change line 186 to neverallow phosphor_keygate self:binder { call transfer set_context_mgr impersonate }; or record at build that { call transfer } is sufficient because the binder class's other ops (impersonate, set_context_mgr) are not grantable to a non-init domain without an explicit allow (which keygate has none). Either way, record the reasoning in the completion note.
```

```
BUG #6
Severity: LOW
Assumption violated: the seapp_contexts rows will match our apps at runtime.
Attack vector: rows are `user=_app isPrivApp=true seinfo=platform name=com.phosphor.shell|broker domain=… type=privapp_data_file levelFrom=user`. The `seinfo=platform` key requires the app to be signed with the platform certificate AND `mac_permissions.xml` to map that signature to seinfo=platform. If PhosphorShell/PhosphorBroker are not platform-signed (S1 installed them as ordinary modules; platform signature is a separate concern), the rows never match → the apps run as untrusted_app → none of the Phosphor domain grants apply → silent no-op. The akita precedent rows mostly use levelFrom=all and no seinfo= on priv-app rows (isPrivApp=true name=… domain=… levelFrom=all).
Reproduction: rg -n 'isPrivApp=true seinfo=platform name=' system/sepolicy/private/seapp_contexts system/sepolicy/vendor/seapp_contexts vendor/google_devices/akita/sepolicy → zero hits in live tree (preflight 8-7); akita rows use levelFrom=all without seinfo.
Root cause: the row shape is copied from the spec (§3.5) which copied it from an assumption; the live tree's priv-app rows do not use seinfo=platform. The plan labels the row shape [EXPECT AT BUILD] (correct) but does not flag the signing precondition.
Fix: at build, verify (a) mac_permissions.xml contains a platform seinfo entry that would match our signature, or (b) change rows to match akita precedent (drop seinfo=platform, use levelFrom=all) — the domains still apply via name= + isPrivApp=true. Record the choice in the completion note.
```

```
BUG #7
Severity: LOW
Assumption violated: the file_contexts rows label the files at their real install paths.
Attack vector: rows are /system/etc/phosphor(/.*)?, /system/bin/phosphor-agentd, /system/bin/phosphor-keygate, /data/misc/phosphor(/.*)?. But phosphor.mk declares SYSTEM_EXT_*_SEPOLICY_DIRS (the policy dirs are system_ext) and the bins are PRODUCT_PACKAGES (phosphor-agentd, phosphor-keygate) — PRODUCT_PACKAGES install to the product partition's /system_ext/bin/ on a Treble device (system_ext is a separate partition image). If the bins land in /system_ext/bin/, the /system/bin/phosphor-* rows never match → no *_exec labels → init_daemon_domain's domain_auto_trans never fires → the daemons run as init (or fail to start) → silent no-op. The risk-policy.json is explicitly copied to $(TARGET_COPY_OUT_SYSTEM)/etc/phosphor/ (phosphor.mk) — so that one is correct on /system.
Reproduction: cat packages/phosphor/phosphor.mk (verified: PRODUCT_COPY_FILES → TARGET_COPY_OUT_SYSTEM; PRODUCT_PACKAGES → phosphor-agentd etc.); check S1's Android.bp for the bins' install path (S1 installed five modules — their Android.bp lives in packages/phosphor, which is synced at acba394).
Root cause: the spec's §3.5 file_contexts rows assume /system/bin/; the S1 wiring may put them on system_ext. The plan quotes the spec verbatim (correct per spec) but the spec's path assumption was not verified against S1's actual install paths.
Fix: at build (or now, by reading packages/phosphor's Android.bp at acba394): confirm where phosphor-agentd/phosphor-keygate install. If /system_ext/bin/, update file_contexts rows to /system_ext/bin/phosphor-* (and /system_ext/etc/phosphor/ for the policy file if PRODUCT_COPY_FILES is changed). Record the correction.
```

```
BUG #8
Severity: LOW
Assumption violated: levelFrom=user is the right levelFrom for our seapp rows.
Attack vector: akita precedent rows use levelFrom=all (see seapp_contexts dump: user=_app isPrivApp=true name=… domain=… levelFrom=all). levelFrom=user derives the MLS level from the app's UID/user; levelFrom=all fixes it for all users. For a single-user device the difference is immaterial, but the row shape should match the device's convention to avoid a build warning or a never-seapp_contexts-match edge.
Reproduction: head -20 vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts (all rows levelFrom=all).
Root cause: spec §3.5 wrote levelFrom=user; akita convention is levelFrom=all.
Fix: at build, match akita (levelFrom=all) or record why levelFrom=user is intended. Plan's [EXPECT AT BUILD] tag covers this.
```

---

## Per-check summary (the 7 checks the brief named)

1. **Byte-for-byte vs spec §3.1–3.5 + rulings:** PASS (artifacts 1–10; rulings 1/2/3 applied correctly; 4 content caveats filed as BUG #2/#5/#6/#7).
2. **Syntax validity vs in-tree precedent:** PASS (all macros/forms have direct precedent; no `mmap_exec_file_perms`; subtraction/set/self forms verified).
3. **AID diff:** PASS (4 lines, OEM range, no collision, anchor honest; one nit on plan's line-239 gate phrasing — no other 2950 hits in system/core at preflight, fine).
4. **Commit/mirror/sync sequence:** PASS with BUG #3 (mirror origin assumption) — order correct, outputs executable, dirty-payload path closed, exit-code gates present (B.2/B.5 hard, others procedural via global rule 1).
5. **A1–A10 evidence coverage:** PASS — all ten criteria have a planned evidence step; A2's both-set_prop negative test and A5's compiled-contexts check present and correctly shaped.
6. **Fraudulent-expectation class:** PASS — no invented executed output; everything is [QUOTED FROM SOURCE], [EXPECT AT BUILD], or a real command's self-evident output.
7. **Compile-fail / silent no-op:** 8 findings — BUG #1 (get_prop/neverallow interaction, resolved safe after expansion), BUG #2 (radio-netlink type absent — MEDIUM, pre-resolve to netlink_generic_socket or record drop), BUG #3 (mirror origin — MEDIUM, one command), BUG #4 (spec-level R-2 wording, LOW), BUG #5 (binder enumerated ops incomplete — LOW, add set_context_mgr/impersonate or record), BUG #6 (seinfo=platform signing precondition — LOW), BUG #7 (file_contexts /system vs /system_ext install path — LOW, verify S1 Android.bp), BUG #8 (levelFrom=user vs all — LOW).

**Audit verdict: the plan is materially sound — every artifact transcribes the spec correctly, every standing ruling is applied, and the execution contract is executable and dirty-payload-free. The findings are pre-resolvable at build or with one-command verifications; none require re-authoring the policy content. BUG #2 (radio-netlink) and BUG #3 (mirror origin) are the two that should be closed before S2-B starts; BUG #7 (install path) should be verified against S1's Android.bp before the build. BUG #1 is a no-op after expansion (recorded for the completion note).**