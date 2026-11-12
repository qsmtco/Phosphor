#!/usr/bin/env bash
# Round-4 adversarial probe (v2): six-scenario simulation of the REV-5 totality gate,
# plan's EXACT code, fixture tree, /tmp/r5-* fixtures.
set -u
W=$(mktemp -d /tmp/r5sim.XXXXXX); cd "$W" || exit 1
mkdir -p tree
for f in a b c; do printf 'x-%s\n' "$f" > tree/$f.txt; touch -d '1969-12-31 23:59:59' tree/$f.txt; done
for f in d e; do printf 'y-%s\n' "$f" > tree/$f.txt; touch -d '2026-09-24 17:58:00' tree/$f.txt; done

# ---------- S6.0 verbatim (fixed cutoff) ----------
BEFORE_TS=$(date +%s); printf '%s\n' "$BEFORE_TS" > /tmp/r5-before.ts
find tree -type f | sort | xargs sha256sum > /tmp/r5-before.sha256; SX=$?
BEFORE_FILES=$(wc -l < /tmp/r5-before.sha256)
find tree -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/r5-before-pres.txt
OLD_PRESERVED_COUNT=$(wc -l < /tmp/r5-before-pres.txt)
find tree -type f -printf '%T@ %p\n' | sort -k2 > /tmp/r5-before.mtime.txt
echo "S6.0: SHA256_STATUS=$SX BEFORE_FILES=$BEFORE_FILES OLD_PRESERVED_COUNT=$OLD_PRESERVED_COUNT (plan expects 3)"

# ---------- S6.3 leg (a)+(b) verbatim ----------
leg_ab () {
  find tree -type f | sort | xargs sha256sum > /tmp/r5-after.sha256; AX=$?
  AFTER_FILES=$(wc -l < /tmp/r5-after.sha256)
  diff -q /tmp/r5-before.sha256 /tmp/r5-after.sha256 >/dev/null && INV=IDENTICAL || INV=CHANGED
  BEFORE_TS=$(cat /tmp/r5-before.ts)
  BEFORE_FILES=$(wc -l < /tmp/r5-before.sha256)
  OLD_PRESERVED_COUNT=$(wc -l < /tmp/r5-before-pres.txt)
  NEWER_TS_COUNT=$(find tree -type f -newermt "@$BEFORE_TS" -printf '%p\n' | wc -l)
  find tree -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/r5-after-pres.txt
  PRESERVED_COUNT=$(wc -l < /tmp/r5-after-pres.txt)
  V=PASS
  [ "$AFTER_FILES" -eq "$BEFORE_FILES" ] || V="STOP[after-count $AFTER_FILES!=$BEFORE_FILES]"
  [ "$INV" = IDENTICAL ] || V="STOP[inventory CHANGED]"
  [ "$PRESERVED_COUNT" -eq "$OLD_PRESERVED_COUNT" ] || V="STOP[pres-count $OLD_PRESERVED_COUNT->$PRESERVED_COUNT]"
  diff -q /tmp/r5-before-pres.txt /tmp/r5-after-pres.txt >/dev/null || V="STOP[pres-set differs]"
  [ "$NEWER_TS_COUNT" -gt 0 ] || V="STOP[newer=0]"
  [ "$((NEWER_TS_COUNT + PRESERVED_COUNT))" -eq "$BEFORE_FILES" ] || V="STOP[totality $NEWER_TS_COUNT+$PRESERVED_COUNT!=$BEFORE_FILES]"
  echo "  VERDICT=$V (newer=$NEWER_TS_COUNT pres=$PRESERVED_COUNT old=$OLD_PRESERVED_COUNT after=$AFTER_FILES before=$BEFORE_FILES inv=$INV)"
}

# reset to S6.0 state (5 files, 3 preserved)
reset () {
  rm -f tree/NEW.txt tree/s.txt
  for f in a b c; do printf 'x-%s\n' "$f" > tree/$f.txt; touch -d '1969-12-31 23:59:59' tree/$f.txt; done
  for f in d e; do printf 'y-%s\n' "$f" > tree/$f.txt; touch -d '2026-09-24 17:58:00' tree/$f.txt; done
}
NOW_TS=$(date +%s); POST_EPOCH=$((NOW_TS + 60))
echo "(post-run rewrite timestamp used in scenarios: epoch $POST_EPOCH, +60s past baseline; touch -d @epoch is TZ-unambiguous)"

echo; echo "=== S1 known-good: full rewrite (a,b,c untouched; d,e now) ==="
reset; touch -d "@$POST_EPOCH" tree/d.txt tree/e.txt
leg_ab

echo; echo "=== S2 partial: rewrite 1 of 5 (d now; e pre-baseline) ==="
reset; touch -d "@$POST_EPOCH" tree/d.txt; touch -d '1969-12-31 23:59:59' tree/e.txt
leg_ab

echo; echo "=== S3 set-swap: rewrite 3 incl. one zip file (c), skip one normal (e) — SAME counts ==="
reset; touch -d "@$POST_EPOCH" tree/a.txt tree/b.txt tree/c.txt; touch -d '1969-12-31 23:59:59' tree/e.txt
leg_ab

echo; echo "=== S4 created-during-run: generator adds NEW.txt ==="
reset; touch -d "@$POST_EPOCH" tree/d.txt tree/e.txt; echo new > tree/NEW.txt
leg_ab

echo; echo "=== S5 deleted-during-run: e deleted ==="
reset; touch -d "@$POST_EPOCH" tree/d.txt; rm -f tree/e.txt
leg_ab

echo; echo "=== S6 no-op (nothing touched) ==="
reset
leg_ab

echo; echo "=== S7 pre-existing straggler: s.txt post-baseline BEFORE S6.0; no-op run ==="
reset; echo s > tree/s.txt; touch -d '2026-11-11 21:00:00' tree/s.txt
BEFORE_TS=$(date +%s); printf '%s\n' "$BEFORE_TS" > /tmp/r5-before.ts
find tree -type f | sort | xargs sha256sum > /tmp/r5-before.sha256
find tree -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/r5-before-pres.txt
echo "  (straggler present at S6.0; OLD_PRESERVED_COUNT=$(wc -l < /tmp/r5-before-pres.txt))"
leg_ab

echo; echo "=== S8 same-COUNT-different-SET, totality BALANCED: rewrite a,b (zip members), skip d,e ==="
# preserved-after = {c,d,e}: count 3==3 passes; NEWER=2, PRESERVED=3, 2+3=5==5 passes;
# INVENTORY=IDENTICAL (mtime-only churn). ONLY the diff -q set comparison can catch this.
reset
baseline () {
  BEFORE_TS=$(date +%s); printf '%s\n' "$BEFORE_TS" > /tmp/r5-before.ts
  find tree -type f | sort | xargs sha256sum > /tmp/r5-before.sha256
  find tree -type f ! -newermt "2026-01-01" -printf '%T@ %p\n' | sort > /tmp/r5-before-pres.txt
}
baseline
echo "  (re-baselined clean; OLD_PRESERVED_COUNT=$(wc -l < /tmp/r5-before-pres.txt))"
touch -d "@$POST_EPOCH" tree/a.txt tree/b.txt
leg_ab