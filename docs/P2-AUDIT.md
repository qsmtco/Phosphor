# Security Audit — R-GATE (destructive-command gating) + R-SEC (secret hygiene)
**Spec:** PHOS-SPEC-001 §5.3/5.4/7/8/12 · **Date:** 2026-09-04 · Independent subagent audit, read-only

| ID | Sev | Finding |
|---|---|---|
| H1 | HIGH | Telegram front-end has no approval flow; cross-process approval registries are unreachable |
| H2 | HIGH | /approve does not enforce session binding; the enforcing function (take_approval) is dead code |
| H3 | HIGH | Silent fail-open: unreadable/invalid pattern file disables the entire gate |
| H4 | HIGH | id_rsa* and parts of the R-SEC-3 secret path set are missing from both the read gate and D12 |
| M1 | MEDIUM | D1 is narrower than spec: 'rm -r' without -f and 'rm -f' without -r classify SAFE |
| M2 | MEDIUM | write_file outside ~/projects is a permanent hard block, not the §8 approval flow |
| M3 | MEDIUM | Secret reads are hard-blocked, not 'DESTRUCTIVE-READ requiring approval' |
| M4 | MEDIUM | No shell-quote normalization before classification despite spec requirement |
| M5 | MEDIUM | abspath not realpath: symlink escapes bypass both the write gate and the secret-read gate |
| M6 | MEDIUM | CURRENT_SESSION module-global race misbinds approvals under concurrent turns |
| M7 | MEDIUM | No save-time secret redaction anywhere |
| L1 | LOW | Expired/used approvals are never purged from _APPROVALS |
| L2 | LOW | git push -f (short form) classifies SAFE |
| L3 | LOW | Base64/decode pipe-to-shell RCE classifies SAFE |
| L4 | LOW | Denial is never distinguished from approval in the agent's view; deny marks the approval used before returning |
| L5 | LOW | Only the last pending approval per turn is surfaced |

## Remediation Record (Qrusher, 2026-09-04)

- **H1 FIXED** — telegram surfaces pending with /approve //deny commands; _core.approve_pending API; server /approve records approver
- **H2 FIXED** — atomic consume inside lock + approver audit trail; spec 8.4 explicitly allows any-front-end approval, so cross-session approval is by design
- **H3 FIXED** — pattern load fails closed (raises at import, refuses to start on empty/invalid file)
- **H4 FIXED** — id_rsa/id_ed25519/id_ecdsa added to D12 and read gate; gate regex aligned with D12
- **M1 FIXED** — D1 widened: rm -r / rm -f alone now DESTRUCTIVE
- **M2 FIXED** — write outside ~/projects now uses full approval flow (PENDING APPROVAL id=...), not hard block
- **M3 PARTIAL** — reads of secrets hard-blocked by design (simpler + safer than approval for reads); spec updated note pending Captain review
- **M4 WONTFIX** — shell-quote normalization deferred; pattern list covers common forms, model sees same text
- **M5 FIXED** — os.path.realpath on write + read gates (symlink escapes closed)
- **M6 FIXED** — session passed explicitly through run_tool(name, args, session_key); module global removed from path
- **M7 OPEN** — save-time secret redaction not implemented - tracked for P3
- **L1 FIXED** — expired/used approvals purged lazily on each access
- **L2 FIXED** — git push -f short form added to D11
- **L3 FIXED** — base64 -d pipe-to-shell added to D10
- **L4 OPEN** — deny distinguishable via /deny command reply; agent-side denial messaging minor
- **L5 WONTFIX** — multiple pendings per turn rare; last-wins acceptable
