# P5-S3 — `phosphor_keygate` boot-decision service — build-side plan (author round)

**Phase:** 5 · **Spec ID:** P5-S3 · **Round:** S3-A (Coder, author) · **Author:** Coder, 2026-11-14
**Deliverable:** this file — byte-exact content for the S3 build-side artifacts, for transcription by the Supervisor (S3-B) into the Phosphor-platform payload repo, plus the verification block and the A4(a) host-lab procedure. Device acceptance (A1–A10 on the Pixel) is a **separate, PM-gated execution round** — this plan performs none of it.
**Authority chain:** `docs/PHASE-4-PLATFORM-ARCHITECTURE.md` §6.5/§2.1/§2.2/§8 → `docs/specs/P5-S3-keygate-service.md` **rev 2** (errata ⑬–⑯ applied, PM-approved) → `docs/specs/P5-S3-PREFLIGHT-PROBE.md` → `docs/specs/P5-S3-PHASE-INSTRUCTIONS.md` (build-side scope + 8 standing rulings, binding) → this plan.
**Executed-evidence rule (standing):** every expected string below is labelled **[EXECUTED — remote source]** (fetched live by Coder this round, source URL given), **[QUOTED FROM SOURCE — not executed]** (verbatim from the authority chain), or **[EXPECT AT BUILD/CHECK]** (produced by the Supervisor's seat; the pass condition is stated). Nothing is invented. This seat's sandbox is `/home/cptjaqx/projects/Phosphor`; the GrapheneOS tree at `/home/cptjaqx/projects/grapheneos-2026091900` was **not readable from this seat this round**, so every tree-side check is written for the Supervisor's seat with its expected string stated up front.
**Word marker:** the delegation carried **please write** (author round). No `please proceed` marker is claimed; nothing in this plan has been executed against the tree, the payload repo, or any device.
**Device operations: NONE in this round.** The §7 gate text is reproduced verbatim in §9 and binds the *later* execution round.

---

## DISCOVERY (steel-framed rule 1)

- **Read `docs/specs/P5-S3-keygate-service.md` (rev 2) in full:** the decision table §2.1 (any `1` wins; only an all-`0` read yields `0`; any read error / unparseable value / indecision ⇒ `1`); T1 `ro.boot.phosphor.safeboot` (unreadable ⇒ 1), T2 `persist.phosphor.safeboot` (set-only latch; `0` ignored, `1` latches — asymmetry must be commented in source), T3 chord (stub ⇒ never `t3`); exactly one property write `sys.phosphor.safeboot`; one structured log line `phosphor-keygate: safeboot=<0|1> reason=<t1|t2|t3|undecided>`; 2 s self-deadline (§3.4); ≤300 lines, libc/libbase only (§3.3); A1–A10; §7 device-op gate; §5 edge rows (absent-as-empty vs unreadable by read-errno for T1; chord successor must fail closed).
- **Read `docs/specs/P5-S3-PREFLIGHT-PROBE.md` in full:** BUG #1 (unprefixed AID fails `host_init_verifier`; real precedent `user system_ext_sdv_sbr`), BUG #2 (`late-init` precedes `load_persist_props` ⇒ trigger must be `load_persist_props_action`), BUG #3 (compound-trigger ban is runtime grounds, action.cpp:225-228), BUG #4 (T1 is `bootloader_prop` via the `ro.boot.` prefix row `property_contexts:1088` + `get_prop(domain, bootloader_prop)` at `domain.te:519` — **zero sepolicy needed**), BUG #5 (`phosphor_keygate.te:8-9` cites a phantom `boot_prop`/C1 — comment-only fix), BUG #6 (staged `/system_ext/etc/passwd` is a stale 0-byte S1 artifact — must verify the 7520 row), BUG #7 (all `.rc` parse before any action; `init_rc` installs to `/system/etc/init` for a system `cc_binary`). V2: libbase property API is the precedented minimal-daemon dependency (watchdogd/gatekeeperd/llkd). V4: **no new sepolicy is required for S3**.
- **Read `docs/specs/P5-S3-PHASE-INSTRUCTIONS.md` in full:** the 8 standing rulings (binding, not re-litigated) and the build-side scope list; verification list (`m -j24 phosphor-keygate`; staged `.rc` path; staged passwd 7520 row; `host_init_verifier`; `strings`/`nm` static checks).
- **Read S1/S2 handoffs** (`P5-S1-PHASE-1b-PLAN.md`, `P5-S1-PHASE-1c-EVIDENCE.md`, `P5-S2-POLICY-PLAN.md`, `P5-S2-PHASE-S2B-EVIDENCE.md`): handoff-file format; payload flow (SRCREPO commit → bare-mirror refresh → `repo sync packages/phosphor`; the repo root **is** `packages/phosphor` — do not nest, S2 deviation 1); S1 skeleton facts (`services/PhosphorKeygate/{Android.bp,main.cpp}` exist as `cc_binary` stubs, `stem:` = module name, stub `main(){return 0;}`, **no `init_rc` anywhere yet**, `init/` holds only `.gitkeep`); S2 landed the 4 domains/property types and the staged passwd rows (`system_ext_phosphor_keygate::7520:7520::/:/bin/sh` — executed S2 evidence).
- **Fetched in-tree `cc_binary`+`init_rc` precedents [EXECUTED — remote source]** (aosp-mirror `platform_system_core`, `raw.githubusercontent.com`, fetched 2026-11-14):
  - `system/core/gatekeeperd/Android.bp`: `cc_binary { name: "gatekeeperd", ..., srcs: ["main.cpp"], init_rc: ["gatekeeperd.rc"] }` — and `gatekeeperd.rc` sits **beside the `Android.bp`** (module-local). Fetched: `https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/gatekeeperd/Android.bp` and `.../gatekeeperd/gatekeeperd.rc`.
  - `system/core/watchdogd/Android.bp`: plain `cc_binary`, no `init_rc` (fetched, same host).
  - `system/trusty/keymaster/Android.bp`: `init_rc: ["3.0/android.hardware.keymaster@3.0-service.trusty.rc"]` — relative paths resolve **inside** the module directory (subdirectory form). Fetched: `https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/trusty/keymaster/Android.bp`.
  - **Conclusion (the instruction's verify item):** `init_rc` entries are module-relative and every in-tree precedent keeps the `.rc` inside the module's directory tree. There is **no precedent for a `../` parent escape** in `init_rc`, so the `.rc` is placed **beside the module**: `services/PhosphorKeygate/phosphor_keygate.rc`, referenced as `init_rc: ["phosphor_keygate.rc"]`. Tree-side re-verification is a §8 step.
- **Architecture:** `packages/phosphor` is the payload repo; keygate owns `services/PhosphorKeygate/`; the `.rc` reaches init via the module's `init_rc` (→ `/system/etc/init/`, scanned at `init.cpp:353`); sepolicy is **untouched** except the comment-only `.te` fix.

---

## 0. Global execution rules (bind every S3-B step)

1. **Stop-and-report on any mismatch.** A FAILED state is a legitimate, auditable outcome. Never improvise, never edit a file a step did not name.
2. **Payload flow is the only flow.** Files are committed in `SRCREPO` (`/home/cptjaqx/projects/Phosphor-platform`, branch `main`), the bare mirror is refreshed, then `repo sync packages/phosphor` brings `TREE/packages/phosphor` to the new commit. **Direct edits inside `TREE/packages/phosphor` are FORBIDDEN.** The repo root **is** `packages/phosphor` (S2 lesson): payload paths below are given both as repo-relative (`services/PhosphorKeygate/...`) and tree-relative (`packages/phosphor/services/PhosphorKeygate/...`).
3. **No new sepolicy (ruling 6).** The only sepolicy-file touch is the §6 comment replacement. A diff showing any non-comment change in a `.te`/`property_contexts`/`seapp_contexts` file is a **STOP**.
4. **No device operation** (§9 gate). No `adb`, no `fastboot`, no reboot, no flash, no wipe — this round is build-side only.
5. **Judge build success** by exit code + absence of `FAILED:` / `ninja: build stopped`, not by grepping for `error:` (`docs/PROJECT-STATUS.md` §9) [QUOTED FROM SOURCE — not executed].
6. Paste command + exact output for every step into the evidence bundle.

```
TREE    = /home/cptjaqx/projects/grapheneos-2026091900
SRCREPO = /home/cptjaqx/projects/Phosphor-platform
MIRROR  = /home/cptjaqx/projects/Phosphor-platform.git
```

---

## 1. The decision, as implemented (spec §2.1 exactly)

Inputs in fixed precedence — **any `1` wins; only an all-`0` read yields `0`**:

| T1 | T2 | T3 | `sys.phosphor.safeboot` | Implemented by |
|---|---|---|---|---|
| 0 | 0/absent | none | **0** | `Decide()` fall-through → `{false, "t1"}` |
| 1 | * | * | **1** | `t1 == 1` → `{true, "t1"}` |
| 0 | 1 | * | **1** | `t2 == 1` → `{true, "t2"}` |
| * | * | held | **1** | `t3 == 1` → `{true, "t3"}` (unreachable in S3: stub) |
| any read error / unparseable / cannot decide | | | **1** | `-1` ⇒ `{true, "undecided"}`; deadline ⇒ `{true, "undecided"}`; write-failure ⇒ force `"1"`, exit 1 |
| keygate never ran | | | *absent* | oneshot + agentd's `on property:sys.phosphor.safeboot=0` (S4) — absent ⇒ down |

Read mapping (ruling 8 — absent-vs-unreadable by **read result**, never by emptiness alone):

| read outcome | T1 (`ro.boot.phosphor.safeboot`) | T2 (`persist.phosphor.safeboot`) |
|---|---|---|
| `kAbsent` (property not set) | contributes **0** (normal case on this build, spec §5) | **ignored** → 0 |
| `kFound` = `"1"` | **1** | **1** (the only latching value) |
| `kFound` = `"0"` | 0 | **ignored** → 0 (deliberate asymmetry, commented in source) |
| `kFound` = `""` (empty) | 0 (absent-as-empty, §5) | ignored → 0 |
| `kFound` = anything else | **1** (unparseable ⇒ fail-closed) | **1** (unparseable ⇒ fail-closed) |
| `kError` (read failed) | **1** (unreadable ⇒ fail-closed) | **1** (unreadable ⇒ fail-closed) |

Notes recorded for the auditor:
- The spec's T2 row compresses the latch rule as "`absent→1` only, a value of `0` is ignored"; the phase instructions' **ruling 8 disambiguates**: absent/empty/0 all ⇒ ignore (contribute 0); only literal `1` ⇒ safe; errno-unreadable ⇒ 1. This plan implements ruling 8 (binding; not re-litigated).
- `reason=` on the **normal** path (`safeboot=0`) is `"t1"`: the §2.4 enum has no "none", and "undecided" is reserved for the fail-closed row. Rationale is commented in the source: the normal decision rests on T1's 0/absent read (T1=1 would force 1 regardless of T2/T3). Flagged in Related issues 2 for ratification.
- The 2 s deadline (§3.4) is checked after each trigger read and again before the write; on breach the decision becomes `{1, "undecided"}`. No sleep loops; each property is read at most once.

---

## 2. Artifact 1 — `services/PhosphorKeygate/main.cpp` (byte-exact; full-file replacement of the S1 stub)

Design notes (why it is built this way):
- **Reads go through bionic's property API** (`__system_property_find` / `__system_property_read_callback`, i.e. libc — the §3.3 baseline), because ruling 8 requires distinguishing *absent* from *unreadable*, which libbase's `GetProperty` overloads cannot express. **The write uses libbase `android::base::SetProperty`** (the preferred API per §3.3). No `libbinder`, no `libhidl`, no framework dependency.
- **The one log line is emitted twice, deliberately:** once via liblog into logd under the tag `phosphor-keygate` (this is what A6's `logcat -d -s phosphor-keygate` captures), and once to `stderr` (the spec §2.4 literal "to stderr" leg). One logical line per run on every path; any single capture shows exactly one line. Note (audit): on device, init starts keygate with stderr dup'ed to `/dev/null`, so the stderr leg is effectively invisible there — **liblog is the A6 capture leg**; the stderr write exists to satisfy §2.4's literal wording and is the leg the A4(a) lab sees.
- `KEYGATE_HOST_LAB` compiles the same decision logic on the host with the property/log plane replaced by the A4(a) harness (§7). The guard touches only the seams, not the decision core.
- Line count as authored: **193 lines** — under the 300 cap (§3.3). (rev 2: 183 → 193 — the BUG #2 global-scope hoist and the two audit-mandated comments.) Pass condition at transcription: `wc -l` ≤ 300 [EXPECT AT CHECK].

```cpp
// phosphor-keygate -- the P5-S3 boot-decision service.
// Spec: docs/specs/P5-S3-keygate-service.md (rev 2); architecture
// docs/PHASE-4-PLATFORM-ARCHITECTURE.md §6.5 (safe boot), §2.1, §2.2.
//
// Reads the three safe-boot triggers and folds them into exactly one property
// write, sys.phosphor.safeboot: 0 = normal boot, 1 = safe boot. Any read
// error, any unparseable value, or exceeding the 2 s self-deadline fails
// CLOSED to 1 (spec §2.1, §3.4). The service is oneshot: it exits after the
// write; the property, not the exit status, is the contract (§2.4).
//
// NEW-6 facts (spec §2.2; restated here per acceptance criterion A10):
//   (a) No Phosphor domain holds `set` on the latch type: nothing inside
//       the running system can write persist.phosphor.safeboot in either
//       direction. Keygate reads it only; it never clears it.
//   (b) The immutable host-set ro.boot.phosphor.safeboot carries REC-2
//       independently of the latch; the latch is a convenience.
//   (c) For the one documented writer -- the host, over adb, out-of-band --
//       clearing is exactly as symmetric as setting: host+cable is the
//       trusted recovery authority.
// The policy guarantee is ACCESS-level (who may write), never a value-level
// rule (NEW-6/C8). The latch's "0 ignored, only a literal 1 latches"
// asymmetry is therefore enforced HERE, in this binary -- see ReadT2().
//
#include <chrono>
#include <cstdio>
#include <string>

#ifdef KEYGATE_HOST_LAB
// A4(a) host-lab build: the lab harness provides the property/log seams
// below (see the plan's lab procedure). No Android headers in this mode.
#else
#include <sys/system_properties.h>

#include <android-base/properties.h>
#include <android/log.h>
#endif

#include "key_chord.h"

// Read outcome for a trigger property. Three outcomes give the
// absent-vs-unreadable distinction the spec demands (§2.1 T1 row, §5):
// kAbsent (property not set -- the NORMAL case for T1 on this build)
// contributes 0; kFound carries the value; kError (the read itself
// failed) is fail-closed. Emptiness of a value alone must never be used
// to infer "absent".
// Global scope, not the anonymous namespace (audit BUG #2): the A4(a)
// host-lab harness (plan §7) defines the Lab* seams at global scope, and
// these prototypes must match those definitions or the lab link fails.
enum class ReadResult { kFound, kAbsent, kError };

#ifdef KEYGATE_HOST_LAB
// Lab seams -- provided by the A4(a) harness (plan §7), not shipped.
ReadResult LabReadProp(const char* name, std::string* value);
bool LabWriteProp(const char* name, const std::string& value);
void LabEmitLine(const char* payload);
#endif

namespace {

constexpr const char* kBootTrigger = "ro.boot.phosphor.safeboot";  // T1
constexpr const char* kLatch = "persist.phosphor.safeboot";        // T2
constexpr const char* kDecision = "sys.phosphor.safeboot";         // the one write
constexpr const char* kLogTag = "phosphor-keygate";

// Hard self-imposed deadline (spec §3.4): if keygate has not decided within
// 2 s of main(), it writes 1 and exits. No sleep loops; each trigger
// property is read at most once.
constexpr std::chrono::seconds kDeadline{2};

std::chrono::steady_clock::time_point g_start{};

bool DeadlineExceeded() { return std::chrono::steady_clock::now() - g_start >= kDeadline; }

#ifdef KEYGATE_HOST_LAB
ReadResult ReadProp(const char* name, std::string* value) { return LabReadProp(name, value); }
bool WriteProp(const char* name, const std::string& value) { return LabWriteProp(name, value); }
void EmitLine(const char* payload) { LabEmitLine(payload); }
#else
ReadResult ReadProp(const char* name, std::string* value) {
  const prop_info* pi = __system_property_find(name);
  if (pi == nullptr) return ReadResult::kAbsent;  // T1 => normal(0); T2 => ignored
  std::string out;
  auto cb = [](void* cookie, const char* /*name*/, const char* val,
               uint32_t /*serial*/) { static_cast<std::string*>(cookie)->assign(val); };
  __system_property_read_callback(pi, cb, &out);
  *value = out;
  // kError is unreachable on device (cosmetic): __system_property_find either
  // resolves the property or reports it absent, and the read callback cannot
  // fail -- the kError leg is exercised only by the A4(a) host-lab harness
  // (plan §7); it exists for the spec's unreadable=>1 fail-closed row (§2.1).
  return ReadResult::kFound;
}

bool WriteProp(const char* name, const std::string& value) {
  return android::base::SetProperty(name, value);
}

void EmitLine(const char* payload) {
  // The one structured line (§2.4): safeboot=<0|1> reason=<t1|t2|t3|undecided>.
  // liblog lands it in logd under the tag A6 greps for
  // (logcat -d -s phosphor-keygate); the stderr write is the spec's
  // literal "to stderr" leg.
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "%s", payload);
  fprintf(stderr, "%s: %s\n", kLogTag, payload);
}
#endif

// T1: ro.boot.phosphor.safeboot. "1" => 1; "0"/empty/absent => 0
// (absent-as-empty is the normal case on this build, §5); unreadable or
// unparseable => -1 (fail-closed, §2.1).
int ReadT1() {
  std::string v;
  switch (ReadProp(kBootTrigger, &v)) {
    case ReadResult::kError:
      return -1;  // unreadable => fail-closed upstream
    case ReadResult::kAbsent:
      return 0;  // absent: normal build case, distinct from kError
    case ReadResult::kFound:
      if (v == "1") return 1;
      if (v == "0" || v.empty()) return 0;
      return -1;  // unparseable => fail-closed
  }
  return -1;  // unreachable
}

// T2: persist.phosphor.safeboot, the set-only latch. DELIBERATE ASYMMETRY
// (spec §2.1; this comment is mandated): absent/empty/"0" are ALL ignored
// (contribute 0); only a literal "1" latches. Enforced here because
// property_service set has no value dimension (NEW-6/C8): no sepolicy
// rule could express it. Unreadable or unparseable => -1 (fail-closed).
int ReadT2() {
  std::string v;
  switch (ReadProp(kLatch, &v)) {
    case ReadResult::kError:
      return -1;  // unreadable => fail-closed upstream
    case ReadResult::kAbsent:
      return 0;  // absent => ignored (not a latch value)
    case ReadResult::kFound:
      if (v == "1") return 1;  // the only latching value
      if (v == "0" || v.empty()) return 0;  // 0/empty ignored
      return -1;  // unparseable => fail-closed
  }
  return -1;  // unreachable
}

struct Decision {
  bool safe;
  const char* reason;  // one of: t1 | t2 | t3 | undecided (spec §2.4)
};

// The §2.1 truth table. Any 1 wins; only an all-0 read yields 0; any -1
// (read error or unparseable value) yields the fail-closed 1 with
// reason=undecided.
Decision Decide() {
  const int t1 = ReadT1();
  if (DeadlineExceeded()) return {true, "undecided"};  // §3.4 bound
  const int t2 = ReadT2();
  if (DeadlineExceeded()) return {true, "undecided"};
  const int t3 = chord_held() ? 1 : 0;  // stub => 0 in S3; never "t3"
  if (DeadlineExceeded()) return {true, "undecided"};

  if (t1 == -1 || t2 == -1) return {true, "undecided"};  // fail-closed
  if (t1 == 1) return {true, "t1"};  // host asked; trusted authority
  if (t2 == 1) return {true, "t2"};  // latch set-only; cannot be cancelled
  if (t3 == 1) return {true, "t3"};  // chord held (unreachable in S3)
  // Normal boot: the only path to 0. reason names T1, the load-bearing
  // trigger: the normal decision rests on T1's 0/absent read (T1=1 would
  // force 1 regardless of T2/T3).
  return {false, "t1"};
}

}  // namespace

int main() {
  g_start = std::chrono::steady_clock::now();

  Decision d = Decide();

  // §3.4: not decided within 2 s of main() => write 1 and exit.
  if (DeadlineExceeded()) d = {true, "undecided"};

  const char* value = d.safe ? "1" : "0";
  if (WriteProp(kDecision, value)) {
    EmitLine((std::string("safeboot=") + value + " reason=" + d.reason).c_str());
    return 0;  // decided write (§2.4)
  }

  // Fail-closed on setprop failure (§2.1 sketch): force the safe side,
  // then report the failure. Exactly one log line per run on every path.
  WriteProp(kDecision, "1");
  EmitLine("safeboot=1 reason=undecided");
  return 1;  // write failure after the fail-closed attempt (§2.4)
}
```

---

## 3. Artifact 2 — `services/PhosphorKeygate/key_chord.h` (byte-exact; new file)

The declared §10.2 seam. Header-only (`inline`) — no `.cpp`, so `srcs` stays `["main.cpp"]`.

```cpp
// key_chord.h -- the hardware key-chord seam (P5-S3 spec §1 non-goals, §3.2, §8 item 1).
//
// OPEN ITEM (architecture §10.2, owner Phase 5): which chord, and how to read it without
// a live framework. S3 ships this stub so the chord can never block S3's acceptance; a
// stub is fail-safe because T1 and T2 carry REC-2 on their own (spec §2.1, NEW-6(b)).
//
// STUB CONTRACT: chord_held() always reports "no chord" (false). reason= is therefore
// never "t3" in S3 -- recorded by A6, not hidden.
//
// FAIL-CLOSED REQUIREMENT FOR THE SUCCESSOR IMPLEMENTATION (spec §5, last edge-case row):
// when the real chord reader lands, an unreadable or errored chord device MUST be treated
// as HELD (chord_held() => true => safe boot). A chord-read failure must never contribute
// 0. Record this in the successor's review; it is the price of reading a device node
// before the framework is up.

#pragma once

inline bool chord_held() {
  return false;  // STUB: no chord reader in S3. Fail-closed requirement above.
}
```

---

## 4. Artifact 3 — `services/PhosphorKeygate/phosphor_keygate.rc` (byte-exact; new file)

**Location decision (the instruction's verify item):** `init_rc` paths are module-relative. In-tree precedent (§ DISCOVERY): `system/core/gatekeeperd` keeps `gatekeeperd.rc` beside its `Android.bp` with `init_rc: ["gatekeeperd.rc"]` [EXECUTED — remote source]; `system/trusty/keymaster` uses module-subdirectory relative paths; no in-tree `cc_binary` escapes the module directory with `../`. Therefore the `.rc` lives **beside the module**: `services/PhosphorKeygate/phosphor_keygate.rc`, and `init_rc: ["phosphor_keygate.rc"]`. The `init/` directory stays as S1 left it (S4 faces the same choice). This deviates from spec §3's `init/phosphor_keygate.rc` table entry — recorded as Related issue 1 (layout erratum for PM).

Install destination: `/system/etc/init/phosphor_keygate.rc` (system partition, same as the module — preflight BUG #7(3)); scanned by init at `init.cpp:353` [QUOTED FROM SOURCE — not executed].

Content — the §3.1 erratum-⑬/⑭ blocks are **verbatim** (4-space indents preserved); the comment header carries the NEW-6 facts A10 requires from the `.rc` comment:

```
# phosphor_keygate -- the P5-S3 boot-decision service.
# Spec: docs/specs/P5-S3-keygate-service.md (rev 2). Architecture §6.5.
#
# NEW-6 facts (acceptance A10 requires them here):
#  (a) No Phosphor domain holds `set` on the latch type: nothing inside the running system
#      can write persist.phosphor.safeboot in either direction. Keygate reads it only.
#  (b) The immutable host-set ro.boot.phosphor.safeboot carries REC-2 independently of the
#      latch; the latch is a convenience.
#  (c) For the one documented writer -- the host, over adb, out-of-band -- clearing is
#      exactly as symmetric as setting: host+cable is the trusted recovery authority.
#
# Trigger: load_persist_props_action, NOT late-init (erratum 14: late-init forks keygate
# before load_persist_props, so T2 would read absent on every boot). All .rc files are
# parsed before any action executes (init.cpp:347-369), so agentd's
# `on property:sys.phosphor.safeboot=0` is already registered when keygate writes; the
# queue_property_triggers sweep re-checks property actions after parse (preflight BUG #7).
# A9's >=5-boot empirical ordering proof remains mandatory.

service phosphor_keygate /system/bin/phosphor-keygate
    class core
    user system_ext_phosphor_keygate
    group system_ext_phosphor_keygate
    oneshot

on load_persist_props_action
    start phosphor_keygate
```

Prohibited forms checked: no `late-init` trigger (erratum ⑭), no compound `on <event> && property:` block (ruling 3), no `capabilities`/`socket`/`onrestart` (§2.4/A7), unprefixed user/group absent (erratum ⑬).

---

## 5. Artifact 4 — `services/PhosphorKeygate/Android.bp` edit (additive)

The S1 stub is expected to be the minimal `cc_binary` (S1 phase instructions: `cc_binary phosphor-keygate, stem:, int main(){return 0;}`) [QUOTED FROM SOURCE — not executed]. **Verify first**, then edit additively:

```bash
cd /home/cptjaqx/projects/Phosphor-platform
cat services/PhosphorKeygate/Android.bp
```

EXPECTED: a single `cc_binary` block with `name: "phosphor-keygate"`, `stem: "phosphor-keygate"`, `srcs: ["main.cpp"]`, and no `init_rc` (S1 forbade `init_rc`; `rg -n init_rc packages/phosphor` → 0 was S1-A4) [QUOTED FROM SOURCE — not executed]. **FAILED:** different module name, extra modules, or an existing `init_rc` → **STOP**, paste the file.

Edit: keep every existing line; add `shared_libs` and `init_rc` so the final file reads:

```
cc_binary {
    name: "phosphor-keygate",
    stem: "phosphor-keygate",
    srcs: ["main.cpp"],
    shared_libs: [
        "libbase",
        "liblog",
    ],
    init_rc: ["phosphor_keygate.rc"],
}
```

(If the stub carries a license/package header or cflags, leave them untouched — the edit adds exactly the two properties above. `liblog` is added for the logd leg of the one log line; precedented by the same minimal-daemon set the preflight cites (V2: watchdogd/gatekeeperd/llkd all link libbase+liblog). Flagged as Related issue 3 since §3.3 names only libbase.)

---

## 6. Artifact 5 — `sepolicy/private/phosphor_keygate.te` comment cleanup (comment-ONLY)

Ruling 7 / preflight BUG #5: lines 8–9 cite a phantom `boot_prop`/C1 mechanism. The real mechanism (preflight BUG #4 / erratum ⑯): `ro.boot.` prefix row types T1 `bootloader_prop` (`system/sepolicy/private/property_contexts:1088`), readable by every domain via `get_prop(domain, bootloader_prop)` (`system/sepolicy/private/domain.te:519`).

Locate and bound the phantom citation (expect exactly the two comment lines, and nothing else in the file):

```bash
cd /home/cptjaqx/projects/Phosphor-platform
rg -n '\bboot_prop\b|\bC1\b' sepolicy/private/phosphor_keygate.te
```

EXPECTED: exactly 2 hits — lines 8 and 9, both comment lines [EXPECT AT CHECK; the two-line text is quoted from the S2 plan §3, authored content]. FAILED (0 hits, or any hit outside those two lines) → **STOP**, paste the output. Replace exactly those two lines:

OLD (remove):
```
# Reads the triggers: the host-set immutable ro.boot.* (already readable as boot_prop-derived
# context; granted explicitly only if C1's context proves insufficient) and the latch.
```

NEW (insert; the `get_prop(phosphor_keygate, phosphor_safeboot_latch_prop)` line and everything else stay byte-identical):
```
# Reads the triggers. T1, the host-set immutable ro.boot.*, needs NO grant here: the global
# prefix row types it bootloader_prop (system/sepolicy/private/property_contexts:1088) and
# every domain may read it via get_prop(domain, bootloader_prop)
# (system/sepolicy/private/domain.te:519) -- S3 preflight BUG #4. The latch read is the
# explicit grant below.
```

Guards: `git diff HEAD -- sepolicy/private/phosphor_keygate.te` shows **only lines beginning with `#`** as +/-; `rg -n 'boot_prop|C1' <repo>` over the payload → empty; `m -j24 sepolicy_neverallows selinux_policy` still green (comments are policy-neutral). Any rule-line change → **STOP** (ruling 6).

---

## 7. Artifact 6 — A4(a) host-lab check procedure (spec §4 A4(a): reads stubbed to fail ⇒ safe=1)

Lab-only harness at `/tmp/keygate_lab.cpp` (NOT a payload artifact — keeps the S1 module inventory clean; Related issue 6). It `#include`s the real `main.cpp` (absolute path, provenance-explicit), renames its `main`, stubs the property/log seams, and drives the decision per scenario from `argv[1]`.

```cpp
// /tmp/keygate_lab.cpp -- A4(a) host-lab harness for phosphor-keygate. Lab-only;
// NOT part of the payload. Stubs the property/log plane and drives main.cpp's
// decision logic per scenario (argv[1]).
#include <chrono>
#include <cstdio>
#include <string>
#include <thread>

#define main keygate_main
#include "/home/cptjaqx/projects/grapheneos-2026091900/packages/phosphor/services/PhosphorKeygate/main.cpp"
#undef main

static std::string g_scenario = "error";
static std::string g_last_write = "<none>";
static int g_read_calls = 0;

ReadResult LabReadProp(const char* name, std::string* value) {
  ++g_read_calls;
  const std::string prop = name;
  if (g_scenario == "error") return ReadResult::kError;  // every read fails (required A4a case)
  if (g_scenario == "slow") {  // trip the 2 s deadline (§3.4)
    std::this_thread::sleep_for(std::chrono::seconds(3));
    return ReadResult::kError;
  }
  if (g_scenario == "normal") {  // T1 absent (normal build), T2 "0" (ignored)
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = "0"; return ReadResult::kFound; }
  }
  if (g_scenario == "t1") {  // host-set trigger latches
    if (prop == kBootTrigger) { *value = "1"; return ReadResult::kFound; }
    if (prop == kLatch) return ReadResult::kAbsent;
  }
  if (g_scenario == "t2") {  // latch set
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = "1"; return ReadResult::kFound; }
  }
  if (g_scenario == "t2zero") {  // latch "0" ignored -> normal boot
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = "0"; return ReadResult::kFound; }
  }
  if (g_scenario == "t2absent") {  // latch property not set -> ignored -> normal boot
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) return ReadResult::kAbsent;
  }
  if (g_scenario == "t1empty") {  // T1 present but empty value -> absent-as-empty (§5) -> normal boot
    if (prop == kBootTrigger) { *value = ""; return ReadResult::kFound; }
    if (prop == kLatch) return ReadResult::kAbsent;
  }
  if (g_scenario == "t2empty") {  // latch present but empty -> ignored (ruling 8) -> normal boot
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = ""; return ReadResult::kFound; }
  }
  if (g_scenario == "t1garbage") {  // unparseable T1 -> fail-closed
    if (prop == kBootTrigger) { *value = "maybe"; return ReadResult::kFound; }
    if (prop == kLatch) return ReadResult::kAbsent;
  }
  if (g_scenario == "latchgarbage") {  // unparseable T2 -> fail-closed
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = "on"; return ReadResult::kFound; }
  }
  if (g_scenario == "writefail") {  // decided normal, but the write fails
    if (prop == kBootTrigger) return ReadResult::kAbsent;
    if (prop == kLatch) { *value = "0"; return ReadResult::kFound; }
  }
  return ReadResult::kError;  // unknown property: fail-closed
}

bool LabWriteProp(const char* name, const std::string& value) {
  if (g_scenario == "writefail") return false;
  g_last_write = std::string(name) + "=" + value;
  return true;
}

void LabEmitLine(const char* payload) { printf("phosphor-keygate: %s\n", payload); }

int main(int argc, char** argv) {
  if (argc > 1) g_scenario = argv[1];
  int rc = keygate_main();
  printf("last_write=%s read_calls=%d exit=%d\n", g_last_write.c_str(), g_read_calls, rc);
  return rc;
}
```

Procedure (host only; no device, no tree mutation — builds in `/tmp`):

```bash
g++ -std=gnu++17 -Wall -Wextra -DKEYGATE_HOST_LAB /tmp/keygate_lab.cpp -o /tmp/keygate_lab
# EXPECT [EXPECT AT CHECK]: exit 0, no output

/tmp/keygate_lab error        # EXPECT: phosphor-keygate: safeboot=1 reason=undecided
                              #         last_write=sys.phosphor.safeboot=1 read_calls=2 exit=0
/tmp/keygate_lab normal       # EXPECT: phosphor-keygate: safeboot=0 reason=t1
                              #         last_write=sys.phosphor.safeboot=0 read_calls=2 exit=0
/tmp/keygate_lab t1           # EXPECT: phosphor-keygate: safeboot=1 reason=t1
                              #         last_write=sys.phosphor.safeboot=1 read_calls=2 exit=0
/tmp/keygate_lab t2           # EXPECT: phosphor-keygate: safeboot=1 reason=t2
                              #         last_write=sys.phosphor.safeboot=1 read_calls=2 exit=0
/tmp/keygate_lab t2zero       # EXPECT: phosphor-keygate: safeboot=0 reason=t1
                              #         last_write=sys.phosphor.safeboot=0 read_calls=2 exit=0
/tmp/keygate_lab t2absent     # EXPECT: phosphor-keygate: safeboot=0 reason=t1
                              #         last_write=sys.phosphor.safeboot=0 read_calls=2 exit=0
/tmp/keygate_lab t1empty      # EXPECT: phosphor-keygate: safeboot=0 reason=t1
                              #         last_write=sys.phosphor.safeboot=0 read_calls=2 exit=0
/tmp/keygate_lab t2empty      # EXPECT: phosphor-keygate: safeboot=0 reason=t1
                              #         last_write=sys.phosphor.safeboot=0 read_calls=2 exit=0
/tmp/keygate_lab t1garbage    # EXPECT: phosphor-keygate: safeboot=1 reason=undecided
                              #         last_write=sys.phosphor.safeboot=1 read_calls=2 exit=0
/tmp/keygate_lab latchgarbage # EXPECT: phosphor-keygate: safeboot=1 reason=undecided
                              #         last_write=sys.phosphor.safeboot=1 read_calls=2 exit=0
/tmp/keygate_lab writefail    # EXPECT: phosphor-keygate: safeboot=1 reason=undecided
                              #         last_write=<none> read_calls=2 exit=1
/tmp/keygate_lab slow         # EXPECT: phosphor-keygate: safeboot=1 reason=undecided
                              #         last_write=sys.phosphor.safeboot=1 read_calls=1 exit=0   (~3 s)
```

The **required** A4(a) case is `error` (all reads fail ⇒ `safe=1`). The other scenarios are the decision-table audit: each one can fail if the implemented table deviates from §2.1 (e.g. `t2zero` catches a latch that wrongly treats `0` as latching; `t2absent`/`t1empty`/`t2empty` pin the absent-vs-empty edges of ruling 8 — an empty value must never latch and an absent T1 must stay normal; `slow` proves the deadline is real; `writefail` proves the fail-closed write + exit 1). All expected strings are [EXPECT AT CHECK] — authored here, executed by the Supervisor.

---

## 8. Artifact 7 — build-side verification command block (no device)

```bash
cd /home/cptjaqx/projects/grapheneos-2026091900
source build/envsetup.sh
lunch akita-cur-user

# 0) passwd-intermediate gate (rev 2, audit BUG #1) -- run BEFORE the build step:
#    host_init_verifier (inside `m phosphor-keygate`) validates the .rc user/group
#    names against the staged per-partition passwd files, and the Sep-24 staged
#    intermediates are stale 0-byte artifacts. The audit proved the .rc FAILS
#    verification against the stale files and PASSES against populated ones, so
#    refresh all five passwd_* intermediates and verify them first.
m -j24 passwd_gen_system passwd_gen_system_ext passwd_gen_product \
       passwd_gen_vendor passwd_gen_odm
# EXPECT [EXPECT AT BUILD]: exit 0 (S2 executed passwd_gen_system_ext green; the
# other four are the same generator for the remaining partitions). If a module
# name is not recognized at this seat: STOP, paste the output.
for p in system system_ext product vendor odm; do
  P="out/target/product/akita/$p/etc/passwd"
  test -s "$P" || { echo "FAILED: $P is empty or missing"; exit 1; }
done
# EXPECT [EXPECT AT BUILD]: every verifier-input passwd file is non-empty (a
# 0-byte file is the stale Sep-24 artifact -- STOP, report to PM per BUG #6).
grep -n 'system_ext_phosphor_keygate::7520' out/target/product/akita/system_ext/etc/passwd
# EXPECT [EXPECT AT BUILD]: system_ext_phosphor_keygate::7520:7520::/:/bin/sh
# (the 7520 row lives in the system_ext passwd; the other partitions have no
# phosphor rows, so non-empty is their only bar). FAILED => STOP-and-report.

# 1) the module builds; host_init_verifier runs inside the build
m -j24 phosphor-keygate
# EXPECT [EXPECT AT BUILD]: exit 0; "#### build completed successfully ####"; no "FAILED:",
# no "ninja: build stopped". host_init_verifier (definitions.mk:3137-3168,
# copy-init-script-file-checked, runs with all five partitions' passwd files) validates the
# .rc user/group lines inside this build: an unresolvable name would fail it (preflight
# BUG #1) [QUOTED FROM SOURCE].

B=out/target/product/akita/system/bin/phosphor-keygate
R=out/target/product/akita/system/etc/init/phosphor_keygate.rc

# 2) staged artifacts exist and are fresh
ls -l "$B" "$R"
# EXPECT [EXPECT AT BUILD]: both present; mtimes newer than the build start.

# 3) staged .rc content == §4 (erratum form verbatim). Comment lines are
#    stripped first (rev 2, audit BUG #5): the .rc's own comment header mentions
#    late-init in the erratum-⑭ note, and that comment must not trip the A7
#    static grep -- only service/trigger CONTENT is checked.
cat "$R"
grep -v '^\s*#' "$R" | grep -c 'system_ext_phosphor_keygate'      # EXPECT: 2 (user + group lines)
grep -v '^\s*#' "$R" | grep -c 'on load_persist_props_action'     # EXPECT: 1
grep -v '^\s*#' "$R" | grep -cE 'late-init|capabilities|socket|onrestart'   # EXPECT: 0 (A7 static)

# 4) ruling 5 / BUG #6: staged system_ext passwd carries the 7520 row
m -j24 passwd_gen_system_ext                    # S2-proven target; green
grep -n 'phosphor' out/target/product/akita/system_ext/etc/passwd
# EXPECT [EXPECT AT BUILD] (rows quoted from executed S2 evidence):
# system_ext_phosphor_keygate::7520:7520::/:/bin/sh
# system_ext_phosphor_agentd::7521:7521::/:/bin/sh
# system_ext_phosphor_broker::7522:7522::/:/bin/sh
# system_ext_phosphor_shell::7523:7523::/:/bin/sh
# FAILED (0-byte or missing row) => STOP-and-report to PM: this gates the device round
# (A1/A7), not this build (the build anchors on the generated passwd_gen_system_ext file).

# 5) binary static checks
strings "$B" | grep -E 'ro\.boot\.phosphor|persist\.phosphor|sys\.phosphor'
# EXPECT [EXPECT AT BUILD] — exactly the contract set, nothing else:
# ro.boot.phosphor.safeboot
# persist.phosphor.safeboot
# sys.phosphor.safeboot
strings "$B" | grep -c 'phosphor-keygate'       # EXPECT: >= 1 (the log tag; benign)
nm -D "$B" | grep -iE 'binder|socket'           # EXPECT: no output (exit 1)
readelf -d "$B" | grep NEEDED                   # record; EXPECT: libbase.so + liblog.so present
readelf -d "$B" | grep -E 'libbinder|libhidl|libutils|libbinder_ndk'   # EXPECT: no output
# (host binutils handle aarch64 ELF; if absent, use llvm-nm/llvm-readelf from
#  prebuilts/clang/host/linux-x86/*/bin/. ldd does not apply to target binaries.)

# 6) A10 + cleanup static gates
rg -n 'reverse direction' packages/phosphor                 # EXPECT: empty
rg -n 'boot_prop|C1' packages/phosphor/sepolicy             # EXPECT: empty
rg -n 'init_rc' packages/phosphor/services/PhosphorKeygate/Android.bp
# EXPECT: init_rc: ["phosphor_keygate.rc"],
wc -l packages/phosphor/services/PhosphorKeygate/main.cpp   # EXPECT: <= 300

# 7) policy neutrality of the .te comment edit (cheap re-proof)
m -j24 sepolicy_neverallows selinux_policy      # EXPECT: both green (S2 baseline)
```

FAILED states: any deviating output → **STOP**, paste it, do not improvise (see §11).

---

## 9. Device-operation gate (spec §7 — reproduced verbatim; NOT executed this round)

> A1, A2, A3 and A4(b) each require **a reboot of the Pixel**, and A3 requires a kernel-cmdline mutation. Each is a separate, explicitly-approved device operation:
> - Approval: **PM, per operation**, before execution (vision: "Do not flash or wipe the phone without the user's clear approval for that specific operation"; architecture §6.5 makes the host path the trusted recovery authority).
> - No flash, no wipe is required by this spec. If a build must be installed, that is S1/S8's gate, and the recovery ladder of `docs/PROJECT-STATUS.md` §8 must be re-confirmed available (USB rehearsal, `fwupd` stopped) **before** the reboot.
> - Stop rule: if A1 cannot be reached without a flash, stop and return to the PM; do not extend the spec's authority.

Per the phase instructions: the build-side work (this plan) needs **no device op** and proceeds independently; A1–A10 execution is a separate PM-gated round after audit.

---

## 10. Commit message + transcription sequence (S3-B)

### 10.1 Commit message (Phosphor-platform, on `main`)

```
keygate: P5-S3 boot-decision service (build-side)

Implements the P5-S3 build scope: the phosphor-keygate decision binary
(T1 ro.boot.phosphor.safeboot / T2 persist latch / T3 chord stub folded
per spec 2.1 -- any 1 wins, only an all-0 read yields 0, any read error
or unparseable value fails closed to 1; 2 s self-deadline; exactly one
structured log line safeboot=<0|1> reason=<t1|t2|t3|undecided>; exit 0
on a decided write, 1 after a failed fail-closed write), the key_chord.h
stub seam with the fail-closed successor requirement, and the erratum
13/14 init .rc (user/group system_ext_phosphor_keygate, trigger on
load_persist_props_action) installed via init_rc (module-local, per the
gatekeeperd cc_binary precedent).

No sepolicy changes: T1 is bootloader_prop via the global prefix row and
domain-readable (preflight BUG #4); the phosphor_keygate.te comment now
cites the real grant (comment-only cleanup). The latch asymmetry (0
ignored, only a literal 1 latches) is enforced in the binary per
NEW-6/C8.

Payload only; no device operation. Build evidence:
docs/handoffs/P5-S3-KEYGATE-PLAN.md. Device acceptance A1-A10 is a
separate PM-gated execution round.
```

### 10.2 Command sequence

```bash
# S3-B.1 — transcribe artifacts 2–5 into SRCREPO (repo root == packages/phosphor)
cd /home/cptjaqx/projects/Phosphor-platform
git status --porcelain            # EXPECT: empty before edits
# write services/PhosphorKeygate/main.cpp        (§2, full file)
# write services/PhosphorKeygate/key_chord.h     (§3, new file)
# write services/PhosphorKeygate/phosphor_keygate.rc  (§4, new file)
# edit  services/PhosphorKeygate/Android.bp      (§5, additive)
# edit  sepolicy/private/phosphor_keygate.te     (§6, comment lines only)
git status --porcelain            # EXPECT: only the five intended paths
git diff HEAD -- sepolicy/private/phosphor_keygate.te   # EXPECT: comment-line changes only
git add -A services/PhosphorKeygate sepolicy/private/phosphor_keygate.te
git commit -m "<10.1 message>"
NEW_HEAD=$(git rev-parse HEAD); echo "NEW_HEAD=$NEW_HEAD"

# S3-B.2 — refresh the bare mirror (instructions' form)
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git fetch \
    /home/cptjaqx/projects/Phosphor-platform "+refs/heads/main:refs/heads/main"
git --git-dir=/home/cptjaqx/projects/Phosphor-platform.git rev-parse refs/heads/main
# EXPECT: == $NEW_HEAD

# S3-B.3 — sync the tree
cd /home/cptjaqx/projects/grapheneos-2026091900
repo sync packages/phosphor
git -C packages/phosphor rev-parse HEAD        # EXPECT: == $NEW_HEAD
git -C packages/phosphor status --porcelain     # EXPECT: empty

# S3-B.4 — run the §8 verification block; S3-B.5 — run the §7 A4(a) lab matrix
```

---

## 11. FAILED states → STOP

Any of the following → **STOP**, paste the output, return to the Supervisor/PM:

1. `m phosphor-keygate` exits non-zero, or `FAILED:` / `ninja: build stopped` appears.
2. The staged `.rc` is missing, or its content deviates from §4 (wrong user/group, wrong trigger, extra lines).
3. The staged `/system_ext/etc/passwd` lacks `system_ext_phosphor_keygate::7520` (or is still 0 bytes after `m passwd_gen_system_ext`) — report to PM per BUG #6; it gates the device round, not this build.
4. `strings` shows any phosphor-related property name beyond the three contract names.
5. `nm -D`/`readelf -d` shows binder/socket/hidl linkage.
6. The `.te` diff contains any non-comment change; or `rg 'boot_prop|C1'` still matches.
7. The `Android.bp` stub shape differs from the §5 expectation (different name, pre-existing `init_rc`, extra modules).
8. `repo sync` lands a different HEAD, or the mirror ref does not advance to `NEW_HEAD`.
9. Any A4(a) scenario's observed line/exit deviates from the §7 expected strings.
10. Anyone proposes a device operation, a sepolicy rule change, or a compound trigger to "fix" a failure — those are out of this round's authority (rulings 3, 6; §9).

---

## Revision log (rev 2 — P5-S3-A plan-revision round; audit fixes applied as prescribed)

| Audit finding | Fix applied | Where (this file, rev 2) |
|---|---|---|
| **BUG #1 (HIGH)** — `host_init_verifier` validates the `.rc` user/group names against the staged passwd intermediates, and the Sep-24 staged copies are stale 0-byte artifacts (preflight BUG #6). The audit proved the `.rc` **fails** verification with the stale inputs and **passes** with populated ones. | New **§8 step 0** passwd-intermediate gate, run **before** the build step: `m -j24` all five `passwd_gen_*` modules (system, system_ext, product, vendor, odm) to refresh the intermediates; assert every verifier-input passwd file is non-empty (`test -s`); verify the `system_ext_phosphor_keygate::7520:7520::/:/bin/sh` row; any empty/stale file → STOP-and-report to PM. The original build step is renumbered step 1, unchanged. | §8, plan lines 544–564 (step 0); step 1 now lines 566–572 |
| **BUG #2** — `enum class ReadResult` and the `Lab*` seam prototypes sat inside the anonymous namespace, but the A4(a) harness defines `LabReadProp`/`LabWriteProp`/`LabEmitLine` at global scope; the mismatch breaks the lab link. | In the §2 `main.cpp` block, hoisted `enum class ReadResult { kFound, kAbsent, kError }` and the three `Lab*` prototypes to **global scope** (placed between the `#include "key_chord.h"` and `namespace {`, with a comment stating the audit reason); the enclosing `namespace {` now opens right after the prototypes, so all other content is untouched — a 3-line move, no redesign. | §2 block, plan lines 121–141 (hoisted decls 123–139); §2 design-notes line count updated 183 → 193 (plan line 81) |
| **BUG #3** — the A4(a) matrix covered only 9 scenarios; the absent/empty edges of ruling 8 were not pinned. | Added three scenarios to the §7 harness — `t2absent` (latch property not set), `t1empty` (T1 present-but-empty → absent-as-empty, §5), `t2empty` (latch present-but-empty) — each with harness stub logic and a run-matrix row. All three EXPECT `safeboot=0 reason=t1` / `last_write=sys.phosphor.safeboot=0` / `read_calls=2` / `exit=0`. Matrix is now **12** scenarios; COMPLETENESS item 6 updated 9 → 12. | Harness stubs: plan lines 458–469; run-matrix rows: lines 517–522; narrative: line 533; COMPLETENESS: line 742 |
| **BUG #4** — the §6 locator `grep -n 'boot_prop-derived'` matched only line 8, so it could not prove the cleanup covers both phantom lines, and it would pass vacuously after an incomplete edit. | §6 locate step replaced with the bounded check `rg -n '\bboot_prop\b\|\bC1\b' sepolicy/private/phosphor_keygate.te`; EXPECT **exactly 2 hits — lines 8 and 9, both comment lines**, with FAILED (0 hits, or any hit outside those two lines) → STOP. The OLD/NEW replacement text and the comment-only guard are unchanged. | §6, plan lines 385–392 |
| **BUG #5** — the §8 step-3 A7 static grep ran over the raw `.rc`, whose own comment header mentions `late-init` in the erratum-⑭ note, so the comment would false-trip the `late-init\|capabilities\|socket\|onrestart` prohibition. | All three §8 step-3 greps now comment-strip first: `grep -v '^\s*#' "$R" \| grep -c ...` (the `.rc` header is full-line `#` comments only). Expected counts unchanged (2 / 1 / 0); rationale comment added in the block. | §8 step 3, plan lines 581–588 |
| Audit-required source comments | (a) **stderr-leg note** added to the §2 design notes: on device init dup's keygate's stderr to `/dev/null`, so the stderr leg is effectively invisible there — **liblog is the A6 capture leg**; stderr exists for §2.4's literal wording and is the leg the A4(a) lab sees. (b) **kError-unreachable-on-device cosmetic note** added in the §2 device `ReadProp()` just before `return ReadResult::kFound;`. | (a) plan line 79; (b) plan lines 170–173 |

Byte-stability: every other section (header, DISCOVERY, §0–§1, §3–§5, §9–§11, Related issues, the byte-exact `.rc`/`key_chord.h`/`Android.bp` contents, and the commit message) is unchanged from the audited rev-1 text.

---

## COMPLETENESS template (one line per artifact)

- [ ] 1 `services/PhosphorKeygate/main.cpp` — §2.1 table incl. 2 s deadline, one structured log line, fail-closed write on setprop failure, ≤300 lines, libbase SetProperty + bionic read seam (§2)
- [ ] 2 `services/PhosphorKeygate/key_chord.h` — stub + documented fail-closed successor requirement (§3)
- [ ] 3 `services/PhosphorKeygate/phosphor_keygate.rc` — erratum-⑬/⑭ form verbatim + NEW-6 comment (§4)
- [ ] 4 `services/PhosphorKeygate/Android.bp` — srcs kept, +shared_libs(libbase, liblog), +init_rc; gatekeeperd precedent stated (§5)
- [ ] 5 `sepolicy/private/phosphor_keygate.te` — phantom `boot_prop`/C1 comment replaced with the real bootloader_prop/domain.te:519 citation; comment-only (§6)
- [ ] 6 A4(a) host-lab procedure — 12 scenarios, required all-reads-fail ⇒ safe=1 (§7)
- [ ] 7 Verification command block — `m phosphor-keygate`; staged `.rc` path+content; staged passwd 7520 row; host_init_verifier; strings/nm/readelf; A10 rg (§8)
- [ ] 8 Commit message + mirror-refresh + `repo sync` sequence (§10)

## Related issues (mandatory)

1. **`.rc` location vs spec §3/S1-B2 layout.** The spec's table places the file at `packages/phosphor/init/phosphor_keygate.rc`; Soong `init_rc` is module-relative and no in-tree `cc_binary` escapes the module directory with `../` (gatekeeperd/trusty-keymaster precedents fetched this round). The file therefore lives at `services/PhosphorKeygate/phosphor_keygate.rc`. Layout erratum for PM; `init/` stays reserved (S4 decides its own placement).
2. **`reason=` on the normal path.** Spec §2.4's enum (`t1|t2|t3|undecided`) has no value for "no trigger fired". Implemented as `t1` with the in-source rationale (the normal decision rests on T1's 0/absent read); flagged for the spec owner to ratify or amend the enum in a future rev. Not silently hidden from A6.
3. **liblog dependency.** §3.3 names libbase; the logd leg of the one log line needs liblog (`__android_log_print`, tag = A6's `logcat -s` filter), with the stderr write keeping §2.4's literal "to stderr". Precedented (watchdogd/gatekeeperd/llkd, preflight V2). Recorded here for the auditor.
4. **Read seam uses bionic, not libbase `GetProperty`.** Ruling 8's absent-vs-unreadable distinction (empty ⇒ 0, error ⇒ 1) is not expressible with libbase's `GetProperty` overloads; spec §3.3's baseline is "libc only", so `__system_property_find/read_callback` (libc) is used for reads and libbase `SetProperty` for the write. Ruling-compliant resolution of an internal tension between ruling 8 and the "libbase only" phrasing.
5. **BUG #6 staged-passwd staleness.** The §8 check enforces ruling 5 before any device round; a stale 0-byte staged copy is a STOP-and-report to PM, not something this plan silently repairs.
6. **A4(a) harness is lab-only** (`/tmp`), not a payload artifact — the payload stays exactly at the spec's artifact list; the harness source lives in this plan (§7) for reproducibility.
7. **`key_chord.h` is header-only.** No `.cpp`; the successor implementer replaces the `inline` body and must honor the in-file fail-closed requirement (unreadable chord ⇒ held ⇒ safe boot).
