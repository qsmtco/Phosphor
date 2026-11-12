"""Reconstruct rev 3 of docs/PHASE-4-PLATFORM-ARCHITECTURE.md by reversing
Coder's recorded rev-4 edits (feed timestamp >= 2026-11-11T03:00:00Z).
Read-only w.r.t. the repo: writes only to /tmp. Used for the P4 rev-4
narrow scope check.

Rationale: git HEAD (d44fa6e) captured the document mid-edit at rev 2, so
`git diff HEAD` is NOT a valid rev3->rev4 delta. The feed log's edit_file
calls are the authoritative record.
"""
import json
import sys

DOC = "docs/PHASE-4-PLATFORM-ARCHITECTURE.md"
CUT = "2026-11-11T03:00:00"

cards = json.load(open(".crabcakes/feed.json"))
edits = []
for c in cards:
    md = c.get("metadata") or {}
    ta = md.get("tool_args") or {}
    if "PHASE-4-PLATFORM" not in (ta.get("path") or ""):
        continue
    if md.get("tool_name") != "edit_file":
        continue
    if md.get("status") == "error":
        continue
    if c["timestamp"] < CUT:
        continue
    old, new = ta.get("old_text", ""), ta.get("new_text", "")
    if not old and not new:
        continue
    edits.append((c["timestamp"], old, new))

edits.sort(key=lambda x: x[0])
print("rev-4 edit_file calls: %d" % len(edits))

text = open(DOC).read()
print("worktree bytes=%d lines=%d" % (len(text), text.count("\n") + 1))

for i, (ts, old, new) in enumerate(reversed(edits), 1):
    n = text.count(new)
    if n != 1:
        print("REVERSE FAIL at edit %d (%s): new_text occurs %d times" % (i, ts, n))
        sys.exit(1)
    text = text.replace(new, old, 1)

print("reconstructed rev3 bytes=%d lines=%d" % (len(text), text.count("\n") + 1))
open("/tmp/rev3_reconstructed.txt", "w").write(text)
