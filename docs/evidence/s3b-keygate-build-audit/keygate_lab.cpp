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
