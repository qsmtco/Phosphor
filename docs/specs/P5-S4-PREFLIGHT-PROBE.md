# P5-S4 PREFLIGHT PROBE — spec-vs-tree drift (Debugger, 2026-11-15)

**Scope:** read-only verification of `docs/specs/P5-S4-agentd-skeleton.md` (rev 1) against
`/home/cptjaqx/projects/grapheneos-2026091900` (payload `655fc08`, `packages/phosphor`
clean; compiled conf `out/soong/.intermediates/system/sepolicy/system_ext_sepolicy.conf/android_common/akita/system_ext_sepolicy.conf`
sha `1f14a382…`, mtime 2026-11-14 13:08 — the S3-close build). Applied
`adversarialDebugger.md` (all 11 sections) to the *spec's assumptions*; there is no S4
implementation yet. Probe-local numbering: PF-BUG #N (disjoint from S2's #1–#11, S3's
PF-BUG #1–#7, and this probe's PF-A1–A9 advisories).

**Verdict up front:** the spec is **not buildable/behaving as written**. §2.1's verbatim
`.rc` still carries the S3-probe BUG #1 class of defect (unprefixed users ⇒
`host_init_verifier` rejects the build), and §2.5's admission rule hard-codes an
impossible UID (CRITICAL: the intended peer can never be admitted as specified). The
seeded "SOCK_SEQPACKET gap" is **refuted as stated** — SOCK_SEQPACKET is governed by
`unix_stream_socket` in this tree, and `domain.te:30` already grants agentd the full
`create_stream_socket_perms` set on self — but the probe replaces it with a narrower real
gap (no `sock_file` create/unlink grant in the data dir) plus one discovery-grade finding
nobody listed: **placing the socket inside the 0700 private dir makes the endpoint
DAC-unreachable for the intended peer entirely**, so §2.5's topology needs a design
decision, not just a rule. The crash-budget seed is refuted with a replacement hazard:
init's only autonomous action is a fixed 5 s restart period, forever; "init's own limits
engage" is false for agentd. Rust toolchain: fully green on this tree. Five advisories
(A4–A9) complete coverage.

**Tree facts pinned by this probe** (inputs to later errata):
- `system/sepolicy/private/access_vectors:269-277` — classes `unix_stream_socket`
  (inherits `socket`, adds `connectto`) and `unix_dgram_socket` (bare). **No
  `unix_seqpacket_socket` class exists** in platform policy: grep across
  `system/sepolicy/{public,private}` → 0 hits; `socket_class_set`
  (`system/sepolicy/public/global_macros:14`) enumerates stream+dgram only.
- Kernel/uapi confirms the mapping and the API surface:
  `system/core/init/property_service.cpp:1641` and `system/core/init/subcontext.cpp:197`
  create `SOCK_SEQPACKET` socketpairs; `bionic/libc/kernel/uapi/asm-generic/socket.h:46`
  defines `SO_PEERSEC 31`; `external/selinux/libselinux/src/getpeercon.c:26` reads it via
  `getsockopt(fd, SOL_SOCKET, SO_PEERSEC, …)` (`getpeercon(3)`), also wrapped by the
  Rust crate `external/rust/android-crates-io/crates/selinux`.
- `system/sepolicy/private/domain.te:29-30` — `allow domain self:unix_dgram_socket
  { create_socket_perms sendto }` and `allow domain self:unix_stream_socket
  { create_stream_socket_perms }`; these compile into the shipped conf as
  attribute grants covering every domain, including `phosphor_agentd`.
- Compiled conf, agentd-specific allows exactly: conf:97461 (`phosphor_safeboot_prop`
  get), :97464 (policy read), :97465 (data **dir** `create_dir_perms`), :97466 (data
  **`{ file lnk_file }`** `create_file_perms`). `grep -c seqpacket conf` → **0**.
- `system/core/init/service_parser.cpp:441-442` — init's `.rc` `socket` keyword accepts
  `seqpacket` (`socket.type = SOCK_SEQPACKET`), i.e. init creates such sockets natively
  (precedent `lmkd.rc`: `socket lmkd seqpacket+passcred 0660 system system`).

---

## PF-BUG #1 — CRITICAL — §2.1 verbatim `.rc` uses unprefixed users; host_init_verifier rejects the build

**Assumption violated:** spec:49–60 (`.rc` verbatim block: `user phosphor_agentd` /
`group phosphor_agentd`) and :41 restate the exact defect class S3's preflight fixed for
keygate (S3 probe PF-BUG #1, erratum ⑰: `system_ext_` prefix required; build-time
enforcement via `copy-init-script-file-checked` → `host_init_verifier` → `DecodeUid`).

**Evidence (2026-11-15, post-S3-close):**
- `packages/phosphor/config.fs:3-4` — `AID_SYSTEM_EXT_PHOSPHOR_AGENTD value: 7521`
  (prefixed name).
- Device-side passwd is now populated (S3's build fixed the S3-probe BUG #6 staleness):
  `out/target/product/akita/system_ext/etc/passwd` contains
  `system_ext_phosphor_agentd::7521:7521::/:/bin/sh` among the four phosphor rows.
- bionic resolves only the prefixed line name for the system_ext passwd file
  (`bionic/libc/bionic/grp_pwd.cpp:59-64`, `grp_pwd_file.cpp:274-281,301-313`); the
  compiled `android_ids` table has no phosphor entry (grep → 0), so unprefixed
  `phosphor_agentd` cannot resolve; `init`'s `DecodeUid` (`system/core/init/util.cpp:76-79`)
  fails and the service block is rejected. The S3 spec already carries the corrected
  form: `services/PhosphorKeygate/phosphor_keygate.rc:17-21` uses
  `user system_ext_phosphor_keygate`.

**Fix:** §2.1:41 and the §6.5 verbatim block (:52–56) must become
`user system_ext_phosphor_agentd` / `group system_ext_phosphor_agentd`. No sepolicy change
is needed (exec-based `init_daemon_domain` transition; conf:97417-97453 unchanged).

---

## PF-BUG #2 — CRITICAL — §2.5 hard-codes an impossible admission UID (`AID_PHOSPHOR_SHELL`)

**Assumption violated:** spec:95 — "admit only a peer whose UID is `AID_PHOSPHOR_SHELL`
**and** whose domain is `phosphor_shell`"; A6's peer-rejection test; and S7:41–42 repeats
the same pair-check. The spec treats UID 7523 as an identity the shell app actually has.

**Evidence:**
1. `packages/phosphor/apps/PhosphorShell/AndroidManifest.xml` — plain `<application>`, no
   `android:sharedUserId`; `apps/PhosphorShell/Android.bp` — `android_app`,
   `certificate: "platform"`, `privileged: true`. No shared-uid anywhere in
   `packages/phosphor` (grep → 0 hits).
2. Therefore the shell installs as a standard app UID (10000+ range), and
   `SO_PEERCRED`'s uid for the shell peer is that app uid — never 7523.
3. `packages/phosphor/sepolicy/private/seapp_contexts:1` —
   `user=_app isPrivApp=true seinfo=platform name=com.phosphor.shell domain=phosphor_shell` —
   the *domain* half of the check is real; the *uid* half is fiction. (7523 exists only as
   the fs-config identity, useful for file ownership, not as the app's runtime uid.)
4. `docs/specs/P5-S2-selinux-foundation.md:215` even marks the AID block
   "[VERIFY AT BUILD: unused in this tree …]" — the S4 spec then used it anyway.

**Consequence:** as written, the two-condition AND admits **nobody**: the daemon rejects
every connection, including the genuine shell. A6's peer-rejected observation would "pass"
for the wrong reason (everything is rejected), and S7's client can never connect. This is
a spec+protocol bug, not an implementation detail.

**Fix:** §2.5:95 — either (a) drop the UID predicate and admit on the label
(`u:r:phosphor_shell:s0`) alone, hardening the endpoint with DAC (socket 0600 owned by
agentd) + SELinux `connectto` scoping (S7 owns the allow) — the label check is the
stronger of the two here; or (b) keep a two-factor check by pairing label with the
daemon-side **connection count/backoff** rather than a nonexistent uid; or (c) genuinely
share an fs identity via `sharedUserId="android.uid.system_ext_phosphor_shell"` +
`package` uid mapping (a real design change with S5 consequences, needs PM decision).
Recommended: (a), with the spec text recording why the uid half was dropped. S7:41 must
be corrected in the same erratum to avoid re-introducing the check there.

---

## PF-BUG #3 — CRITICAL (discovered; supersedes the seed's framing) — socket inside the 0700 private dir is unreachable by any client: §2.5's topology cannot work

**Assumption violated:** spec:94 — socket path `/data/misc/phosphor/agentd.sock`,
"created here", inside the daemon's private data dir; A6:169 expects `adb shell ls -l
/data/misc/phosphor/agentd.sock` to show `srw------- phosphor_agentd phosphor_agentd`.

**Evidence (DAC):**
1. S3's build ran `mkdir /data/misc/phosphor 0700 phosphor_agentd` (keygate `main.cpp`
   provisioning step; `phosphor_keygate.te:20-21` grants keygate exactly
   `dir { create setattr }` + `file { create write getattr open }` on the data type — a
   one-time bootstrap, no maintenance rights).
2. `0700` on the directory means **only** uid `phosphor_agentd` (7521) may
   search/`execute` the directory (DAC `x` bit governs path resolution). The shell app's
   uid (any app uid) lacks it, so its `connect()` to the socket fails with EACCES before
   SELinux is even consulted. `/dev/socket` works as a rendezvous precisely because init
   creates it `0775` root/root (`system/core/init/first_stage_init.cpp:361`) — the
   world-`x` bit is what makes the endpoint reachable while the socket node itself stays
   `0660`.
3. A6's `adb shell ls -l` succeeds only because shell is root-adjacent on debug builds —
   it proves nothing about the app's access.

**Evidence (SELinux, independent confirmation):** the compiled conf grants no non-agentd
domain any access to `phosphor_agentd_data_file` (grep → 0 lines beyond agentd's own
:97465-97466 and keygate's neverallow :97670), and `domain.te:1082-1125` confines
non-coredomains to `core_data_file_type` anyway. Even with the dir mode opened up, S7
must add an explicit `phosphor_shell` → `phosphor_agentd_data_file:sock_file` + `unix_stream_socket connectto` allow set.

**Consequence:** A6 (and S7's whole client story) cannot execute against the spec'd
topology. This is the largest unknown the probe removes: the socket must live at a
reachable rendezvous path (e.g. `/dev/socket/phosphor_agentd` created by init's `socket`
keyword — the `lmkd`/`prng_seeder` pattern, which also gives init-created fd passing and
solves the stale-socket edge case), or the dir must be a purpose-made shared-label
directory. Given §2.5's own "path is a shared constant owned by `services/PhosphorIpc/`",
the `socket`-keyword route is the precedented choice; note `socket … seqpacket+passcred`
is supported (`service_parser.cpp:441-442`) and `passcred` is exactly the `SO_PASSCRED`
needed for `SO_PEERCRED` on the accepted fd.

**Fix:** rewrite §2.5 path/ownership paragraphs and A6:169 for the chosen topology; move
the "stale socket unlink" edge case (spec:191) accordingly (init's `socket` keyword makes
it moot); coordinate the S7 allow-set and `PhosphorIpc` constant in the same erratum.

---

## PF-BUG #4 — HIGH (reframed from seed S2; narrower than claimed) — agentd cannot create/unlink the socket *node* in its data dir: `{ file lnk_file }` excludes `sock_file`

**Assumption violated:** seed premise "no sock_file allow and no seqpacket self-allow ⇒
cannot create+bind+accept the seqpacket socket". Half right.

**Evidence:**
1. **Create/bind/listen/accept/getopt/setopt/read/write on the socket itself: already
   granted.** `domain.te:30` gives every domain `create_stream_socket_perms` on
   `self:unix_stream_socket`, and this tree maps SOCK_SEQPACKET to that class (Tree-facts
   block above; also empirically: `lmkd.rc` runs a seqpacket listening socket with a
   policy that contains zero seqpacket rules — `system/sepolicy/private/lmkd.te` has only
   `allow lmkd lmkd_socket:sock_file write` (:84) beyond the generic domain set).
   Macro expansion (`public/global_macros:51-56`): `create_socket_perms` =
   `{ ioctl read getattr write setattr lock append bind connect getopt setopt shutdown
   map create }` + `listen accept` via `rw_stream_socket_perms` — exactly the server set
   including `accept`.
2. **The socket *node* is the gap.** `bind()` on an AF_UNIX pathname socket creates the
   filesystem inode, and the kernel checks it as `sock_file` against the **directory's**
   label (here `phosphor_agentd_data_file`). conf:97466 covers `{ file lnk_file }` only —
   `sock_file` is absent (grep `phosphor_agentd_data_file.*sock` → 0). Same for the
   stale-socket `unlink` on shutdown/rebind. Precedent for the exact fix shape:
   `bluetooth.te:24` `allow bluetooth bluetooth_socket:sock_file create_file_perms;`,
   `drmserver.te:38`, `shell.te:339`, `crosvm.te:135`.
3. **`connectto` for the client is genuinely absent** — no S2 rule lets `phosphor_shell`
   `connectto` agentd (grep conf → 0). But that is correctly S7's allow to write (the S2
   comment at `phosphor_neverallows.te:41-48` already ledgers outbound/inbound socket
   scoping to S6/S7), so it is a dependency note, not an S4 defect.

**Minimal S4 rule additions (if §2.5 keeps the self-created socket in the data dir):**
```
allow phosphor_agentd phosphor_agentd_data_file:sock_file create_file_perms;
```
(`create_file_perms` = `create rename setattr unlink rw_file_perms`, `global_macros:35` —
covers bind-create and clean-shutdown unlink; `rw_file_perms` = `r_file_perms
{ getattr open read ioctl lock map watch watch_reads }` + `w_file_perms { open append
write lock map }`.) If the daemon instead uses init's `socket` keyword, S4 needs **zero**
new rules for the socket itself (init creates it; see `init.te:100`-style patterns and
`init.te:709-710`), and only S7's client-side `connectto` remains. Also note: `ioctl` on
the socket is in the generic grant (`rw_socket_perms`), so no `allowxperm` is needed for
AF_UNIX socket ioctls at this level.

**Fix:** add the one `sock_file` line to `phosphor_agentd.te` + spec §2.5 (or switch
topology per PF-BUG #3 and drop it). Validate strict (binary-mode `checkpolicy -M -c 30`),
per the S2 audit's standing regime note.

---

## PF-BUG #5 — MEDIUM (reframed from seed S3) — init offers agentd no crash budget at all: fixed 5 s restart, forever; "init's own limits engage" is false

**Assumption violated:** spec:106 — the daemon writes a `crashloop` marker "and exit with
status 1 so init's own limits engage rather than a hot loop".

**Evidence (`system/core/init/service.cpp`, `service.h`, `init.cpp`):**
1. The crash-count block fires **only** for `SVC_CRITICAL || is_process_updatable`
   (`service.cpp:398-402`: `if (((flags_ & SVC_CRITICAL) || is_process_updatable) &&
   !(flags_ & SVC_RESTART) && !was_last_exit_ok_)`). agentd is neither: no `critical`
   keyword (spec §2.1 forbids escalation anyway) and `updatable` is an APEX-only option
   (`service_parser.cpp:580,625`), so `crash_count_` is never incremented for agentd.
2. What actually happens for a non-critical service: `Reap()` sets `SVC_RESTARTING`
   (:352-438 tail), runs `onrestart_`, and init's event loop restarts it when
   `now >= time_started_ + restart_period()` (`init.cpp:413-419`). Default period is a
   **constant 5 s** (`service.h:238` `default_restart_period_ = 5s`; settable only upward
   via the `restart_period` .rc option, `service_parser.cpp:374-376`). **No escalation,
   no cap, forever** — a fast-crashing agentd restarts every ~5 s indefinitely. (The MTE
   upgrade path at :382-395 and the `fatal_crash_window_` bookkeeping are both inside the
   critical/updatable gate — unreachable for agentd.)
3. Therefore the spec's premise is inverted: there are **no** init-side limits for this
   service, and the daemon's own backoff/marker is not a belt-and-braces complement to
   init's budget — it is the **only** backstop. (Worth noting: "hot loop starves boot"
   is also overstated for a 5 s period; the real cost is a forever-crashing service and
   log spam.)

**Fix (erratum ⑱):** §2.6:106 — replace "so init's own limits engage" with the honest
statement: *init restarts non-critical services at a fixed period (default 5 s,
`service.h:238`, `init.cpp:413-419`) with no escalation and no cap for agentd; the
daemon's own consecutive-fast-crash marker is the sole crash-loop backstop, and the
user-visible remedy is the shell's offline state.* Keep the daemon-side 3-in-5 s
`crashloop` marker requirement (A5) — it is now load-bearing, not redundant.

---

## PF-BUG #6 — MEDIUM — A6's `SO_PEERCRED`/`SO_PEERSEC` client test contradicts A3's "no avc denials" acceptance

**Assumption violated:** spec:153 (A3: `logcat -b all -d | grep 'avc: *denied' | grep
phosphor_agentd` → empty) vs :170 (A6: connect with `socat`/`nc -U` from a non-shell
context and observe `peer_rejected`).

**Evidence:**
1. ADB shell connects as uid `shell` (2000), SELinux domain `shell` — not
   `phosphor_shell`. The label half of the daemon's admission check (spec:95) rejects it
   — but only **after** the kernel has already performed the `connect()` permission
   check: `phosphor_shell` (the socket's owning domain, via the socket label inherited
   from the creating daemon... more precisely the socket's label is `phosphor_agentd`) —
   and `shell` has **no** `allow shell phosphor_agentd:unix_stream_socket connectto`
   (grep `shell.te` → only `traced`/`dumpstate` connects at :37,:356). The connect
   therefore fails at the kernel with an **avc denial naming `phosphor_agentd`** —
   precisely what A3 declares must never appear.
2. Ordering nuance that makes A6's wording wrong either way: for AF_UNIX, the kernel
   checks `unix_stream_socket:connectto` between peer labels at connect time. If the
   deny fires, the daemon's `accept()` never happens and `peer_rejected` is never
   logged; if an S7-era allow made the connect succeed for `shell`, then the daemon's
   `SO_PEERCRED/SO_PEERSEC` check rejects it — but A3's avc-grep would still be clean
   only because the connect was allowed. The two acceptance criteria as written cannot
   both pass in the same build. (`getpeercon(3)` itself needs no policy permission —
   it's a plain `getsockopt`; the kernel AVC check is on `connect`, and there is no
   `getopt`-side check for `SO_PEERSEC` beyond the socket's own `getopt`, which agentd
   holds on self.)
3. `netstat`/`adb shell`-side reproduction detail: toybox `netcat.c` supports `-U`
   (unix socket) and `-l` (netcat.c:7,14,32,160-171), but **no SEQPACKET type flag**
   (`usock()` passes only `SOCK_STREAM`/`SOCK_DGRAM`); `socat` does not exist on the
   image (no `socat` in `out/target/product/akita/system/bin`). So even the *tool* half
   of A6 needs a bespoke test client (S7's test tool) for a true seqpacket peer test.

**Fix:** A6 — replace the "avc must stay empty while an unauthorized connect is attempted"
construction: either (i) perform the unauthorized-connect test with `dontaudit`-scoped
expectation and drop A3's blanket grep to "no avc denials **from agentd's own
operations**" (grep excluding the injected connect), or (ii) keep A3 strict and test
`peer_rejected` only via a client that *is* kernel-allowed to connect (e.g. `shell` with
an explicit test-only allow, or S7's client against a test label) and is rejected by the
daemon's label check. Also record the toybox `-U`-stream-only fact in A6 so the deferred
check is specified precisely.

---

## PF-BUG #7 — MEDIUM — `.rc` naming/module-shape drift: `init/phosphor_agentd.rc` vs the shipped S1 skeleton (`services/PhosphorAgentd/`, `cc_binary`, no rc)

**Assumption violated:** spec §3:124 declares `services/PhosphorAgentd/{Android.bp,
src/main.rs}` and `init/phosphor_agentd.rc`; the tree already contains an S1-era
skeleton of a different shape; the keygate precedent maps rc files via `init_rc` inside
the module.

**Evidence:** tree state at `655fc08`:
- `packages/phosphor/services/PhosphorAgentd/Android.bp` — existing
  `cc_binary { name: "phosphor-agentd", stem: "phosphor-agentd", srcs: ["main.cpp"] }`
  (no `init_rc`, no rust).
- `packages/phosphor/services/PhosphorAgentd/main.cpp` — `int main() { return 0; }`
  stub.
- `packages/phosphor/init/` contains only `.gitkeep` — no `phosphor_agentd.rc`.
- `packages/phosphor/phosphor.mk:2-8` already lists `phosphor-agentd` in
  `PRODUCT_PACKAGES`, so the current stub is *shipping* in the image.
- Precedent for the spec's own module family:
  `services/PhosphorKeygate/Android.bp` attaches `init_rc: ["phosphor_keygate.rc"]`
  inside the module (keygate rc lives beside the source, not under `init/`).

**Consequence:** two divergent shapes exist in-tree for the same concept; if S4 is built
per spec §3 literally, the old `cc_binary` module name collides with the new
`rust_binary` (duplicate module name `phosphor-agentd` = soong error), and an
`init/phosphor_agentd.rc` installed via a different mechanism than the module's
`init_rc` would split the artifact from its config.

**Fix:** spec §3 — choose one shape and say so: either (a) replace
`services/PhosphorAgentd/Android.bp` with the `rust_binary` module (with `init_rc`), keep
the directory, and delete the stub `main.cpp`; or (b) keep `init/` as the rc home and
wire it via `PRODUCT_COPY_FILES` (disfavored: loses `host_init_verifier`'s checked path?
— no, copy-init-script-file-checked still applies — but loses module locality). Also
record that the S1 stub currently ships and must be replaced, not paralleled.

---

## PF-BUG #8 — LOW — A4's post-kill "exactly one restart" is init-accurate but the log assertion is under-specified; A4 needs the `restart_period` fact

**Assumption violated:** spec:162 — "No `onrestart` hot-loop; exactly one restart per
kill" and `sleep 3` then expect `running`.

**Evidence:** with the default `restart_period = 5s` (`service.h:238`, `init.cpp:414`),
the service is **not** running again 3 s after the kill — `init.svc.phosphor_agentd`
reads `restarting` and `pidof` is empty. A4's `sleep 3` + "running" assertion fails on a
correct system. (Kill -9 ⇒ `Reap` ⇒ `SVC_RESTARTING`; restart fires at
`time_started + 5s`.)

**Fix:** A4 — `sleep 6` (or poll up to ~10 s) before asserting `running` + new pid; and
reword "exactly one restart per kill" to "exactly one scheduled restart (5 s period),
no tight loop" so the criterion matches init's actual behavior (PF-BUG #5 facts).

---

## PF-BUG #9 — LOW — §2.6's `init.svc.phosphor_agentd` values are wrong: init reports `restarting`, not `restarting`/`stopped` as the spec's trio implies; and `stopped` is a real state A2 must handle precisely

**Assumption violated:** spec:103 — "`init.svc.phosphor_agentd` state
(`running`/`restarting`/`stopped`) — from init" treats the trio as equivalent health
readings; A2:148 calls `stopped` a failure in safe boot.

**Evidence:** init's `NotifyStateChange` values are `running`, `restarting`, `stopped`,
`stopping` (`service.cpp:350,430,437` etc.), and a `disabled` service that has never run
reports `stopped` (property `init.svc.<name>` reflects last state). So A2's expectation
("absent" as `getprop` result) is subtly wrong: on a safe boot the property exists and
reads `stopped` for a `disabled` service — the accurate pass condition is *`pidof`
empty AND no `phosphor-agentd` log lines AND the service never left `stopped`*; A2's
"`stopped` is a failure" as written contradicts the never-started state it is trying to
distinguish. (The real discriminator is: in safe boot the trigger `on
property:sys.phosphor.safeboot=0` never fires, so the service stays `stopped` with
**zero** log lines — exactly what A2:146 asserts. The :148 sentence should be reworded to
"the service must never have transitioned out of `stopped`", not "`stopped` is a
failure".)

**Fix:** A2/:148 — reword to "the service must remain `stopped` from boot (never
`restarting`/`running`), with `pidof` empty and an empty phosphor-agentd log"; align
§2.6's health table wording with the four real init states.

---

## PF-A1 — claim VERIFIED (was seed S1) — `.rc` user/group prefix: confirmed, becomes PF-BUG #1. Erratum ⑰ applies verbatim: `system_ext_phosphor_agentd` (uid 7521), no sepolicy change needed.

## PF-A2 — seed S2 (SOCK_SEQPACKET gap): REFUTED as stated, REPLACED.
- "domain.te grants only dgram+stream" — true, but irrelevant: **there is no seqpacket class**; SOCK_SEQPACKET rides `unix_stream_socket` (kernel `af_unix.c` maps SOCK_SEQPACKET onto the stream class; platform policy confirms via `lmkd` seqpacket socket with zero seqpacket rules). The needed self-perms (`create bind listen accept getopt setopt read write ioctl shutdown`) are already in `create_stream_socket_perms` granted by `domain.te:30`.
- "no sock_file allow" — **true and is the real (narrow) gap**: `phosphor_agentd_data_file:sock_file create_file_perms` is missing (conf:97466 = `{ file lnk_file }` only) → PF-BUG #4.
- Bigger than the seed: the spec'd **location** (inside 0700 dir) breaks reachability for *any* client → PF-BUG #3 (CRITICAL, discovered).
- Client-side `connectto` absence is real but belongs to S7 by S2's own ledger (`phosphor_neverallows.te:41-48`).
- Exact minimal S4 additions if topology unchanged: the single `sock_file` line above (plus S7's future `phosphor_shell` connect/`sock_file write` set). Nothing else.

## PF-A3 — seed S3 (crash budget): REFUTED with replacement (PF-BUG #5). Non-critical + non-updatable ⇒ no crash counter, no reboot, no `sys.init.updatable_crashing`; init's only behavior is restart every `restart_period` (default 5 s, constant) forever. Erratum ⑱ required; daemon's own marker is the sole backstop.

## PF-A4 — SO_PEERCRED + SO_PEERSEC (seed S4): VERIFIED AVAILABLE.
- Constants/uapi: `SO_PEERCRED` via `SO_PASSCRED` (lmkd uses `seqpacket+passcred`), `SO_PEERSEC 31` at `bionic/libc/kernel/uapi/asm-generic/socket.h:46`.
- Userspace API: `getpeercon(3)` (`libselinux`, `getpeercon.c:26`) — plain `getsockopt`, **no special policy permission** to call; used in-tree by `init/property_service.cpp:274`; Rust wrapper exists (`external/rust/android-crates-io/crates/selinux`). A Rust daemon can also read the raw `ucred` via `libc::getsockopt` — no wrapper dependency required.
- Policy: the peer-label read needs **no new allow** (it is a socket-option read on the accepted socket, which agentd owns); the *kernel AVC* happens on `connect` (client side), not on `getpeersec`. So S4's label check adds zero policy lines; the client-side `connectto` grants are S7's.
- Caveat recorded at PF-BUG #2 (the uid half is unsatisfiable as specified) and PF-BUG #6 (the A6 test as written generates denials).

## PF-A5 — Rust precedent health (seed S5): VERIFIED GREEN, choice sound.
- Toolchain ships in-tree: `prebuilts/rust-toolchain/linux-x86/{1.91.1,1.92.0,1.93.1}`; soong default `1.93.1` (`build/soong/rust/config/global.go:30`).
- Real akita build graph contains Rust binaries: `out/soong/.intermediates/system/security/prng_seeder/prng_seeder/android_arm64_armv9-a_cortex-a76/prng_seeder` and `.../keystore2/keystore2/...` both **built in the current out/** (products of this tree's normal build). `keystore2` is in `base_system.mk:149`; `prng_seeder` in `base_system.mk:266` — i.e., shipped on akita user builds by default.
- `rust_binary` supports `init_rc` natively — `system/security/prng_seeder/Android.bp:38-45` (`rust_defaults` carries `init_rc: ["prng_seeder.rc"]`, consumed by both the normal and microdroid `rust_binary`); `system/security/keystore2/Android.bp:142` likewise. **No init_rc/stem penalty vs C++.** (C++ keygate needed `stem` only because the target name had a dash; `rust_binary { name: "phosphor-agentd", stem: "phosphor-agentd" }` works the same way.)
- Precedent rc shape: `prng_seeder.rc` — plain `service`, `user prng_seeder`, `socket … stream+listen`; started via `on early-init`. For S4: `disabled` + property trigger is the novel part, and that combination is separately precedented (PF-A6).

## PF-A6 — `disabled` + `on property:` start precedents (seed S6): VERIFIED, 2+ real examples:
1. **`traced`** — `external/perfetto/perfetto.rc:14-23`: `service traced … class late_start, disabled, user nobody`; started by `on property:persist.traced.enable=1` (:76+). Closest analog: `disabled` service whose start is a property trigger, non-critical, restarts on crash.
2. **`console`** — `system/core/rootdir/init.rc:1301-1309`: `service console /system/bin/sh, class core, disabled, user shell` started by `on init && property:ro.debuggable=1` (:1320-1321). Class-core + disabled + property-gated — exactly S4's skeleton shape.
3. (bonus, `flash_recovery` — the classic `disabled` + `on property:sys.powerctl`… not present in this tree's init.rc; the two above suffice.)
- Also verified: the trigger-sweep ordering claim (seed S7) — **correct**: `QueueAllPropertyActions()` = `QueuePropertyChange("","")` (`action_manager.cpp:58-60`), invoked by `queue_property_triggers_action` (`init.cpp:686-689`) queued at `init.cpp:1286`; `Action::CheckEvent(PropertyChange)` with empty name checks all property triggers against current values (`action.cpp:197-208,225-228`); event-trigger-carrying actions are skipped for property events (`action.cpp:225` `event_trigger_.empty()`). So even if keygate writes `sys.phosphor.safeboot=0` before agentd's `.rc` is parsed — impossible anyway (all rc parsed at `init.cpp:347-369` before any action runs, as keygate's rc comment already records) — the sweep would still fire it. Double-covered.

## PF-A7 — health file + transcript-store stubs (seed S8): VERIFIED MINIMAL.
- Health file = ordinary file create/write in the data dir ⇒ covered by conf:97466 (`{ file lnk_file }` `create_file_perms` includes write). No new policy needed for S4's own writes.
- The *reader* (S8's `phosphor-ctl`) currently has **no** read grant on `phosphor_agentd_data_file` (grep conf → 0), and `phosphor-ctl`'s domain doesn't exist yet as a domain (S1 stub `cc_binary` only; the S2 AID set never gave it one). That is an S8-owned allow (`r_file_perms` on the health file only — recommend a dedicated `phosphor_health_file`-style narrowing or file-type split at S8 time, not S4). No S4 action.
- Transcript store stub: in-process (no IPC, no new files beyond the data dir) per §1.7 — no policy surface. The only S4-side caveat: if the "stub" writes anything under `/data/misc/phosphor/credentials/`, the spec already forbids reading it in S4 (§2.7:115) — keep the stub write-free to honor A9's static grep (`credentials` mentions comments-only).

## PF-A8 — tooling (seed S9): VERIFIED HONEST STATE POSSIBLE.
- `nc` exists (`/system/bin/nc -> toybox`, present in `out/target/product/akita/system/bin`), and toybox `netcat.c` supports `-U` (unix) with `-l/-L` listen modes (netcat.c:7,14,32,160-171) — **but only SOCK_STREAM/SOCK_DGRAM** (`usock()` type comes from `-u`/default; no seqpacket flag). So `nc -U` can prove the **peer-rejection path** (connect is type-agnostic on the client? — no: `connect()` on a SOCK_STREAM socket to a SOCK_SEQPACKET listening socket fails with ESOCKTNOSUPPORT/EPROTOTYPE), i.e. `nc -U` is **not** a valid seqpacket client.
- `socat` — absent from the image (no `/system/bin/socat` in out). 
- Therefore A6's "(checked with socat/nc -U or S7's test tool)" must be tightened: **neither tool can exercise the seqpacket socket**; the peer-rejected check is deferred to S7's test tool (a small Rust/C++ seqpacket client in `PhosphorIpc` or a `phosphor-agentd --selftest` mode), recorded as deferred per spec:170. (PF-BUG #6 additionally constrains what that test may assert about avc denials.)

## PF-A9 — `.rc` location/module shape: VERIFIED DRIFT (PF-BUG #7): tree has `services/PhosphorAgentd/{Android.bp,main.cpp}` (`cc_binary` stub, currently in PRODUCT_PACKAGES and shipping) and an empty `init/` dir; spec §3 promises `src/main.rs` + `init/phosphor_agentd.rc`. Pick one shape (module-attached `init_rc`, keygate precedent) and replace the stub.

---

## Section-coverage note (adversarialDebugger.md)
1 (assumptions challenged: uid identity, socket class, crash budget, reachability, tool
availability), 2 (traced backwards from each A-criterion to the init/kernel mechanism),
3 (hidden assumptions: passwd population, namespace memory, avc-vs-accept ordering),
4 (weakest links: bind failure paths, restart timing), 5 (error handling: avc swallowed
vs logged), 7 (external contract: init keyword grammar, getsockopt contract), 8 (weird
user: adb shell as impostor peer), 9 (scope: every seed + spec §2 claim enumerated
A1–A9/BUG1–9), 10 (docs: spec text vs tree reality deltas listed), 11 (tests: N/A —
pre-implementation probe; A-criteria corrections serve as the test-plan fix).

## Errata to raise (for the supervisor's chain)
- ⑰-reuse: PF-BUG #1 (prefixed users in S4's `.rc` — same erratum family as S3's).
- ⑱: PF-BUG #5 (init has no crash budget for agentd; fixed 5 s restart; daemon marker is sole backstop).
- ⑲: PF-BUG #2 + #3 (admission uid impossible; socket placement unreachable — S4 §2.5 topology decision, S7:41 correction).
- ⑳: PF-BUG #4 (sock_file grant — one line, or mooted by the §2.5 topology decision).
- ㉑: PF-BUG #6/#8/#9 (A2/A4/A6 wording vs init reality; nc/socat limits).
