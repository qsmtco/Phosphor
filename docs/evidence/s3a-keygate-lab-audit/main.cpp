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
// [AUDIT TRANSCRIPTION] byte-copy of P5-S3-KEYGATE-PLAN.md §2 with ONE
// audit-local fix (BUG #2): the three Lab* prototypes are hoisted out of the
// anonymous namespace (internal linkage broke the A4(a) harness link --
// 3 undefined references). Decision logic untouched.
#include <chrono>
#include <cstdio>
#include <string>

#ifdef KEYGATE_HOST_LAB
// A4(a) host-lab build: the lab harness provides the property/log seams
// below (see the plan's lab procedure). No Android headers in this mode.
// [AUDIT FIX] (BUG #2) the shared enum + Lab* prototypes live at GLOBAL scope
// so the harness's out-of-namespace definitions match: inside the anonymous
// namespace they had internal linkage (3 undefined references at link).
enum class ReadResult { kFound, kAbsent, kError };
ReadResult LabReadProp(const char* name, std::string* value);
bool LabWriteProp(const char* name, const std::string& value);
void LabEmitLine(const char* payload);
#else
#include <sys/system_properties.h>

#include <android-base/properties.h>
#include <android/log.h>
#endif

#include "key_chord.h"

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

// Read outcome for a trigger property. Three outcomes give the
// absent-vs-unreadable distinction the spec demands (§2.1 T1 row, §5):
// kAbsent (property not set -- the NORMAL case for T1 on this build)
// contributes 0; kFound carries the value; kError (the read itself
// failed) is fail-closed. Emptiness of a value alone must never be used
// to infer "absent".
#ifdef KEYGATE_HOST_LAB
#else
enum class ReadResult { kFound, kAbsent, kError };
#endif

#ifdef KEYGATE_HOST_LAB
// Lab seams -- provided by the A4(a) harness (plan §7), not shipped.
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
