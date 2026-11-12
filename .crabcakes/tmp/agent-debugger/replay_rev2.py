"""Reconstruct rev 2 of docs/PHASE-4-PLATFORM-ARCHITECTURE.md by reversing
Coder's recorded rev-3 edits. Read-only w.r.t. the repo: writes only to
/tmp for comparison. Used for the P4 rev-3 narrow re-audit.
"""
import json
import sys

DOC = "docs/PHASE-4-PLATFORM-ARCHITECTURE.md"
CUT = "2026-11-11T00:54:00"

cards = json.load(open(".crabcakes/feed.json"))
edits = []
for c in cards:
    md = c.get("metadata") or {}
    ta = md.get("tool_args") or {}
    if "PHASE-4-PLATFORM" in (ta.get("path") or "") and md.get("tool_name") == "edit_file":
        if md.get("status") == "complete" and c["timestamp"] >= CUT:
            edits.append((c["timestamp"], ta.get("old_text", ""), ta.get("new_text", "")))
edits.sort(key=lambda x: x[0])

text = open(DOC).read()
print("worktree bytes=%d lines=%d" % (len(text), text.count("\n") + 1))

for i, (ts, old, new) in enumerate(reversed(edits), 1):
    n = text.count(new)
    if n != 1:
        print("REVERSE FAIL at edit %d (%s): new_text occurs %d times" % (i, ts, n))
        sys.exit(1)
    text = text.replace(new, old, 1)

print("reconstructed rev2 bytes=%d lines=%d" % (len(text), text.count("\n") + 1))
open("/tmp/rev2_reconstructed.txt", "w").write(text)
print("nil=None")

# Now emit a diff of reconstructed-rev2 -> worktree (true rev2->rev3 delta)
