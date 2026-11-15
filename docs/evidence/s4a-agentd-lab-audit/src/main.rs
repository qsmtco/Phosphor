// phosphor-agentd -- the P5-S4 agent daemon skeleton.
// Spec: docs/specs/P5-S4-agentd-skeleton.md (rev 2, errata 17-21 applied).
// Architecture: docs/PHASE-4-PLATFORM-ARCHITECTURE.md sections 2.1, 2.2, 5, 6.3, 6.7, 7, 8.
//
// S4 scope: the process shape only. The daemon (1) refuses to start unless
// sys.phosphor.safeboot is exactly "0" -- defence in depth against an .rc
// edit, a class_start regression, or a manual start bypassing the trigger
// (section 2.2); (2) fails closed unless the read-only risk policy exists,
// parses, and carries a policy_version (section 2.4 step 3); (3) serves the
// init-managed AF_UNIX SOCK_SEQPACKET socket with label-only peer admission
// and a 1 MiB frame cap (erratum 19, section 2.5); (4) maintains
// /data/misc/phosphor/health with the frozen field set and its own crashloop
// backstop (section 2.6, erratum 18: init restarts a non-critical service
// forever at a fixed 5 s period, so the daemon's marker is the only
// backstop); (5) emits exactly the section 2.3 event vocabulary. Message
// semantics, the model client, the classifier and the transcript store are
// later phases; named stubs hold their places (section 1.7, ruling 11).
//
// NEVER-LIST (spec section 2.7; audited by A3/A9): no Android permissions of
// any kind; no property writes; no writes to the policy artifact; no binder
// calls at all in S4; no reads of /data/misc/keystore, /data/adb,
// /data/local/tmp, *.pem, or /data/misc/phosphor/credentials/.

mod health;
mod logging;
mod platform;
mod policy;
mod sha256;
mod socket_loop;
mod start_condition;
mod stubs;

// The shared-constants crate is referenced as `crate::phosphor_ipc` from the
// modules so the device build (extern crate via rustlibs) and the host lab
// (local module, plan section 7) resolve identically. This import makes the
// extern crate addressable via `crate::phosphor_ipc` on device; the lab
// build defines the module itself and compiles without this line.
#[cfg(not(feature = "lab"))]
use phosphor_ipc;

pub fn agentd_main() -> i32 {
    let started = std::time::Instant::now();

    // Section 2.4 step 1 -- start-condition defence in depth (section 2.2).
    let safeboot = match start_condition::check() {
        start_condition::Verdict::Proceed => "0".to_string(),
        start_condition::Verdict::Refused(raw) => {
            // exit(0), and NO dir/socket/policy work (section 2.2).
            logging::exit_refused_start(&raw);
            return 0;
        }
    };

    // Section 2.4 step 2 -- private data dir, 0700, owned by us. A foreign
    // owner is fatal: never silently adopt a foreign directory (spec section 5).
    if let Err(err) = platform::ensure_private_data_dir() {
        // policy_error-class fatal (section 2.4 step 2): init restarts; the
        // shell shows offline.
        let dd = platform::data_dir(); // AUDIT FIX (BUG #D): bind to outlive the call
        logging::policy_error(&format!("data_dir_{}", err), &dd);
        return 1;
    }

    // Section 2.6 crash accounting (erratum 18), inserted between steps 2 and
    // 3: the backstop must observe the previous run's death BEFORE the policy
    // check that may have caused it.
    let health_path = platform::health_path();
    let prev = health::HealthRecord::read(&health_path);
    if prev.as_ref().map(|p| p.crashloop).unwrap_or(false) {
        // Latched off: 3+ consecutive fast deaths already recorded. Stay
        // exited so the hot loop stays broken; the marker is cleared by the
        // operator path (S8 phosphor-ctl), not by us.
        logging::shutdown("crashloop", 0);
        return 1;
    }
    let inherited = health::inherited_fast_crashes(prev.as_ref(), platform::now_ms());
    let mut rec = health::HealthRecord {
        pid: std::process::id(),
        started_at: platform::now_ms(),
        policy_version: prev
            .as_ref()
            .map(|p| p.policy_version.clone())
            .unwrap_or_else(|| "none".to_string()),
        last_frame_at: 0,
        fast_crashes: inherited,
        died_fast: false,
        crashloop: false,
    };
    let _ = rec.write(&health_path); // best-effort; A8 proves it on the happy path

    // Section 2.4 step 3 -- policy artifact; missing/unparseable/version-less
    // => fatal (a daemon that cannot classify must not exist, section 6.3).
    let loaded = match policy::load(&platform::policy_path()) {
        Ok(l) => l,
        Err(err) => {
            logging::policy_error(&err, &platform::policy_path());
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            return 1;
        }
    };
    logging::policy_loaded(&loaded.version, &loaded.sha256, &platform::policy_path());
    rec.policy_version = loaded.version.clone();
    let _ = rec.write(&health_path);

    // Section 2.4 step 4 -- the init-managed socket fd (erratum 19). Failure
    // is near-unreachable (init creates the socket before exec) and fatal.
    let listen_fd = match platform::control_socket_fd(phosphor_ipc::SOCKET_NAME) {
        Ok(fd) => fd,
        Err(err) => {
            logging::plain(&format!("socket_error={}", err));
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            return 1;
        }
    };

    // Section 2.4 step 5 -- the start line, then the event loop (which logs
    // socket_listening once it is listening).
    logging::start(&safeboot, &platform::build_id(), &loaded.version);

    // The turn/state ownership hooks (section 1.7). S4 constructs them and
    // hands them to the loop; the S4 loop does not use them yet -- S7's frame
    // handler will, without reshaping the process.
    let agent = stubs::Agentd {
        transcript: Box::new(stubs::NullTranscriptStore),
        classifier: Box::new(stubs::VersionOnlyClassifier::new(&loaded.version)),
        quarantine: Box::new(stubs::NullQuarantine),
    };

    match socket_loop::run(listen_fd, &health_path, &mut rec, &agent, platform::loop_tick_limit()) {
        socket_loop::LoopExit::Sigterm => {
            clean_shutdown("sigterm", &health_path, &rec, &started);
            0
        }
        socket_loop::LoopExit::TickLimit => {
            // Lab-only bound (device runs with u32::MAX); treated as clean.
            clean_shutdown("tick_limit", &health_path, &rec, &started);
            0
        }
        socket_loop::LoopExit::Fatal(err) => {
            logging::plain(&format!("socket_error={}", err));
            health::record_fast_death(&health_path, &rec, platform::now_ms());
            1
        }
    }
}

fn clean_shutdown(
    reason: &str,
    health_path: &str,
    rec: &health::HealthRecord,
    started: &std::time::Instant,
) {
    // Clean exit: reset the crash counters (a clean run is evidence of
    // health) and rewrite the frozen fields one last time.
    let mut fin = rec.clone();
    fin.fast_crashes = 0;
    fin.died_fast = false;
    fin.crashloop = false;
    fin.last_frame_at = platform::now_ms();
    let _ = fin.write(health_path);
    logging::shutdown(reason, started.elapsed().as_millis() as u64);
}

#[cfg(not(feature = "lab"))]
fn main() {
    std::process::exit(agentd_main());
}
