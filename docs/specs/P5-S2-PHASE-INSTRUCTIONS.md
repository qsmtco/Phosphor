# P5-S2 Phase Instructions — SELinux foundation (2026-11-12)

**Authority chain:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` rev 4 → `docs/specs/P5-S2-selinux-foundation.md` rev 1 (+ pending errata ① seapp private path, ② C15 wording — PM approval requested, direction audit-verified) → preflight `docs/specs/P5-S2-PREFLIGHT-PROBE.md` (15/15 citations verified) → these instructions.

**Handoff discipline (unchanged from S1):** Coder authors exact file content into `docs/handoffs/` (inside its sandbox); the Supervisor transcribes into the tree; the handoff file is the fidelity authority. **Payloads are pointers.**

**S2 payload flow (differs from S1 — read carefully):** `packages/phosphor` is a synced git checkout of the Phosphor-platform repo. Policy files are payload → they are committed to `/home/cptjaqx/projects/Phosphor-platform` (working repo), the bare mirror is refreshed (`git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git fetch origin && git --git-dir=… update-ref refs/heads/main origin/main` — or equivalent; verify `ls-remote` shows the new hash), then `repo sync packages/phosphor` brings the tree to the new commit. Direct edits inside the tree's `packages/phosphor` are FORBIDDEN (would show as dirty payload). The ONE tree-direct edit is the AID header (declared third-party, A9).

**Standing rulings from preflight (do not re-litigate):**
1. `seapp_contexts` goes in `sepolicy/private/`, NOT public (private-only in this tree; precedent row to copy: `vendor/google_devices/akita/sepolicy/system_ext/private/seapp_contexts`).
2. Keygate binder neverallow: enumerated `neverallow phosphor_keygate self:binder { call transfer };` — `*` has zero precedent and risks compiler rejection.
3. Agentd device-node neverallow: enumerate from akita policy — `radio_device`, `camera_device`, `vendor_gnss_device`, `modem_userdata_block_device` (+ radio-netlink socket type resolved from compiled policy at build; placeholder list must name ≥4 categories and carry a [RESOLVE AT BUILD] tag for the netlink type).
4. AIDs 2950–2953 confirmed free (preflight); belt-and-braces full-tree grep in the plan.
5. Build targets: `m -j24 sepolicy_neverallows selinux_policy` (both exist; neverallows is a Soong module). Compiled contexts filenames recorded at build.
6. `set_prop(shell, …)` precedent: `microdroid/system/private/shell.te:104-111`. Subtraction neverallow precedent: `property.te:193-196,310-321`.
7. All file-class neverallows end `:file *` or enumerated subsets with reasons; `mmap_exec_file_perms` is banned (NEW-7).

**Hard boundaries:** no `.rc` files, no daemon logic, no app manifests (S3–S6); zero edits under `system/sepolicy/**`; exactly ONE third-party file edited (the AID header, 4 lines); no device operation — A5's functional latch test is *compile-verified only* this spec, exercised in S8 under PM approval.

---

## Phase S2-A — Author round (Coder)

Write `docs/handoffs/P5-S2-POLICY-PLAN.md` containing, byte-exact, every file:

1. `sepolicy/public/property.te` — the two `system_public_prop()` decls (§3.1 verbatim).
2. `sepolicy/public/property_contexts` — the three rows (§3.1 verbatim; `exact bool` for sys, `exact string` for the two persist rows).
3. `sepolicy/public/phosphor_keygate.te` — §3.2 + subtraction neverallow (C10 form).
4. `sepolicy/public/phosphor_agentd.te` — §3.2 incl. risk-policy read + data-file rules.
5. `sepolicy/public/phosphor_broker.te` / `phosphor_shell.te` — `app_domain()` + type decls; broker `r_file_perms` on the artifact, shell NOTHING on it.
6. `sepolicy/public/file.te` — the two file types (§3.5).
7. `sepolicy/public/file_contexts` — the four rows (§3.5).
8. `sepolicy/private/seapp_contexts` — the two rows (§3.5, **private placement per ruling 1**).
9. `sepolicy/private/app.te` — the two rules (§3.3 verbatim: `get_prop(appdomain, …)` + `set_prop(shell, …)`).
10. `sepolicy/public/phosphor_neverallows.te` — §3.4 set with rulings 2–3 applied; every neverallow carries an architecture §8 citation comment.
11. The AID header diff — exactly 4 lines in `system/core/libcutils/include/private/android_filesystem_config.h` (§3.6), shown as a unified diff against the real file (re-read it first; cite the anchor lines).
12. The commit message for Phosphor-platform + the mirror/sync command sequence (per payload-flow above).

Plan style: S1's — every command fenced, every expected output from an EXECUTED command (executed-evidence rule is standing; anything unexecutable is labelled "quoted from source"), FAILED states that STOP, COMPLETENESS template, Related-issues section. **Rule:** invoke `.crabcakes/prompts/steelFramedCodeWriter.md`. Word marker: **please write**.

## Phase S2-B — Transcription + build (Supervisor, after S2-A audit)

Transcribe → commit Phosphor-platform → refresh mirror → `repo sync packages/phosphor` (verify new HEAD, clean porcelain) → AID header edit (4 lines, diff asserted) → `m -j24 sepolicy_neverallows selinux_policy` → A1–A10 evidence per spec §5 (compiled contexts greps, liveness negative test on BOTH set_prop rules, A4/A7/A8 greps, `repo status` showing exactly `vendor/adevtool` baseline + `system/core` 4-line + phosphor clean-synced).

## Phase S2-C — Post-execution audit (Debugger) → close (post-mortem §6, commit, push, memory, canvas).
