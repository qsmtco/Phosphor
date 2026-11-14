# P5-S3 Phase Instructions — keygate boot-decision service (2026-11-14)

**Authority chain:** architecture §6.5/§2.2/§2.1/§8 → `docs/specs/P5-S3-keygate-service.md` **rev 2** (errata ⑬–⑯ applied, PM-approved) → preflight `docs/specs/P5-S3-PREFLIGHT-PROBE.md` → these instructions.

**Handoff discipline:** unchanged — Coder authors to `docs/handoffs/`, Supervisor transcribes, handoff file is the fidelity authority, payloads are pointers.

**Payload flow:** as S2 — commits to `/home/cptjaqx/projects/Phosphor-platform` (branch main), mirror refresh (`git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git fetch /home/cptjaqx/projects/Phosphor-platform "+refs/heads/main:refs/heads/main"`), `repo sync packages/phosphor`. No direct tree edits.

**Standing rulings from the preflight (do not re-litigate):**
1. `.rc` verbatim is the erratum-⑬/⑭ form: `user/group system_ext_phosphor_keygate`, trigger `on load_persist_props_action`. (Unprefixed names fail `host_init_verifier`; late-init reads persist as absent.)
2. T1 (`ro.boot.phosphor.safeboot`) is `bootloader_prop` via the prefix row — readable by keygate with **zero** sepolicy changes. Do not add any property_contexts row or get_prop grant for it.
3. Compound event+property triggers are banned on runtime grounds (action.cpp:225-228), not parse grounds. Never use them.
4. Ordering: all `.rc` files parse before any action runs; the queue_property_triggers sweep re-checks after parse. A9 still requires the ≥5-boot empirical proof.
5. A7's evidence MUST verify the staged `/system_ext/etc/passwd` contains `system_ext_phosphor_keygate::7520` (current out/ copy is a stale 0-byte S1 artifact) — before any device op.
6. S3 needs **no new sepolicy at all** — S2's set is complete for this contract. If the plan wants a sepolicy change, that's a STOP-and-report.
7. Comment cleanup carried: `phosphor_keygate.te:8-9`'s phantom `boot_prop`/C1 citation gets fixed (comment-only, same commit).
8. Decision-table implementation detail (spec §2.1 + §5): absent-as-empty vs unreadable MUST be distinguished by read errno for T1 (empty ⇒ contributes 0; error ⇒ 1). For T2, absent/empty/0 all ⇒ ignore (contribute 0); only literal `1` ⇒ safe. Unreadable T2 (errno) ⇒ 1.

**Device-operation gate (from spec §7 — must appear in the plan verbatim):** A1/A2/A3/A4(b) each require a Pixel reboot; A3 additionally a kernel-cmdline path. PM approval **per operation, before execution**. No flash, no wipe. If a build install seems needed → STOP, return to PM. Recovery ladder (`docs/PROJECT-STATUS.md` §8: USB rehearsal, fwupd stopped) re-confirmed before the first reboot. The build-side work (S3-A/S3-B) needs NO device op and proceeds independently.

**Build-side scope (what Coder authors):**
- `services/PhosphorKeygate/main.cpp` — the decision binary: reads T1/T2/T3 per the table; `chord_held()` stub in `key_chord.h` returning false with the fail-closed successor requirement documented; 2-second self-deadline writing 1 and exiting; one structured stderr line `phosphor-keygate: safeboot=<0|1> reason=<t1|t2|undecided>`; exit 0 on decided write, 1 on write failure after fail-closed attempt. ≤300 lines, libbase only (`android::base::GetProperty/SetProperty`).
- `services/PhosphorKeygate/key_chord.h` — the stub seam.
- `init/phosphor_keygate.rc` — erratum form verbatim.
- `services/PhosphorKeygate/Android.bp` — fill `srcs` + `init_rc: ["phosphor_keygate.rc"]`... **verify**: the `.rc` lives in `init/` but init_rc paths are module-relative — either move the `.rc` beside the module or use the correct relative path; check what the tree does (precedent: any cc_binary with init_rc).
- A4(a) lab check — host-run with stubbed property reads failing ⇒ safe=1.
- The S2 comment cleanup (ruling 7).

**Verification (build-side, no device):** `m -j24 phosphor-keygate` green; `.rc` installed (find its staged path; record it); staged `/system_ext/etc/passwd` has the 7520 row (ruling 5); `host_init_verifier` passes (it runs in the build); binary static checks (strings: no forbidden property names other than the contract set; no binder/socket linkage — `nm`/`ldd` clean). Device acceptance A1–A10 is a **separate, PM-gated execution round** after audit.
