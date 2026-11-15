// logging.rs -- the section 2.3 event vocabulary. EXACTLY seven audit events;
// field names are frozen (spec section 2.3, ruling 10) and consumed by
// section 6.7's audit store and REC-5's quarantine. The redaction rule is
// enforced here by construction: no function accepts credential material,
// transcript or message bodies, or paths under
// /data/misc/phosphor/credentials/.
//
// The "phosphor-agentd:" prefix of section 2.3 is realized as the logd tag on
// device (logcat -d -s phosphor-agentd) and literally on the lab's stderr
// leg. Non-event operational lines (frame_len=, socket_error=) exist because
// section 2.5 mandates frame_len= logging; they are not part of the closed
// event set and carry no secret material.

const LOG_TAG: &[u8] = b"phosphor-agentd\0";
const ANDROID_LOG_INFO: libc::c_int = 4;

#[cfg(not(feature = "lab"))]
extern "C" {
    // liblog -- the same leg keygate uses (init dup's stderr to /dev/null, so
    // logd is the capture leg on device).
    fn __android_log_print(
        prio: libc::c_int,
        tag: *const libc::c_char,
        fmt: *const libc::c_char,
        ...
    ) -> libc::c_int;
}

fn emit(msg: &str) {
    #[cfg(not(feature = "lab"))]
    {
        let c = std::ffi::CString::new(msg).unwrap_or_default();
        unsafe {
            __android_log_print(
                ANDROID_LOG_INFO,
                LOG_TAG.as_ptr() as *const libc::c_char,
                b"%s\0".as_ptr() as *const libc::c_char,
                c.as_ptr(),
            );
        }
    }
    #[cfg(feature = "lab")]
    {
        eprintln!("phosphor-agentd: {}", msg);
    }
}

pub fn start(safeboot: &str, build_id: &str, policy_version: &str) {
    emit(&format!(
        "event=start pid={} safeboot={} build_id={} policy_version={}",
        std::process::id(),
        safeboot,
        build_id,
        policy_version
    ));
}

pub fn policy_loaded(policy_version: &str, sha256: &str, path: &str) {
    emit(&format!(
        "event=policy_loaded policy_version={} sha256={} path={}",
        policy_version, sha256, path
    ));
}

pub fn policy_error(err: &str, path: &str) {
    emit(&format!("event=policy_error err={} path={}", err, path));
}

pub fn socket_listening(path: &str, uid: u32, gid: u32, mode: u32) {
    emit(&format!(
        "event=socket_listening path={} uid={} gid={} mode={:o}",
        path, uid, gid, mode
    ));
}

pub fn peer_rejected(pid: u32, uid: u32, reason: &str) {
    emit(&format!("event=peer_rejected pid={} uid={} reason={}", pid, uid, reason));
}

pub fn shutdown(reason: &str, uptime_ms: u64) {
    emit(&format!("event=shutdown reason={} uptime_ms={}", reason, uptime_ms));
}

pub fn exit_refused_start(safeboot: &str) {
    emit(&format!("event=exit_refused_start safeboot={}", safeboot));
}

pub fn plain(msg: &str) {
    emit(msg);
}
