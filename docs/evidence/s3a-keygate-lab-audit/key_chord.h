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
