// platform.rs -- the device/host seam (the keygate KEYGATE_HOST_LAB pattern).
//
// Device build (cfg(not(feature = "lab"))): thin FFI one-liners into
// libc/libcutils/libselinux. No in-tree Rust consumer of an init socket was
// verifiable this round, so the delegation-approved FFI form is used for
// android_get_control_socket; getpeercon(3) is a plain getsockopt read
// (SO_PEERSEC) that needs no policy rule (preflight PF-A4) and is likewise
// FFI'd -- the in-tree `selinux` Rust crate exists but its getpeercon
// surface was not verifiable from the author seat.
// Lab build (cfg(feature = "lab"), plan section 7): properties come from the
// environment, the listening fd is injected (or created locally), the peer
// identity is injected, paths move to /tmp, and logs go to stderr.

use crate::phosphor_ipc;
use std::os::unix::io::RawFd;

#[cfg(not(feature = "lab"))]
extern "C" {
    fn __system_property_get(name: *const libc::c_char, value: *mut libc::c_char) -> libc::c_int;
    fn android_get_control_socket(name: *const libc::c_char) -> libc::c_int;
    fn getpeercon(fd: libc::c_int, context: *mut *mut libc::c_char) -> libc::c_int;
    fn freecon(context: *mut libc::c_char);
}

pub const SAFEBOOT_PROP: &str = "sys.phosphor.safeboot";

// ---- properties ---------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn read_prop(name: &str) -> Option<String> {
    use std::ffi::CString;
    let c = match CString::new(name) {
        Ok(c) => c,
        Err(_) => return None,
    };
    let mut buf = [0u8; 92]; // PROP_VALUE_MAX
    let n = unsafe { __system_property_get(c.as_ptr(), buf.as_mut_ptr() as *mut libc::c_char) };
    if n > 0 {
        Some(String::from_utf8_lossy(&buf[..n as usize]).into_owned())
    } else {
        None // absent and empty both read as None; both refuse (section 2.2)
    }
}

#[cfg(feature = "lab")]
pub fn read_prop(name: &str) -> Option<String> {
    let key = format!("LAB_PROP_{}", name.replace('.', "_"));
    std::env::var(key).ok()
}

// ---- build id (section 2.3 start.build_id) -------------------------------

pub fn build_id() -> String {
    // Best-effort audit correlation. [EXPECT AT BUILD: ro.build.id must be
    // domain-readable; if a build regression blocks the read this degrades
    // to "unknown" -- never fatal, never retried. The A3 device check (empty
    // avc denials) covers the policy side.]
    match read_prop("ro.build.id") {
        Some(v) if !v.is_empty() => v,
        _ => "unknown".to_string(),
    }
}

// ---- paths ---------------------------------------------------------------

pub fn data_dir() -> String {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_DATA_DIR").unwrap_or_else(|_| "/tmp/agentd_lab_data".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::DATA_DIR.to_string();
    val
}

pub fn policy_path() -> String {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_POLICY_PATH")
        .unwrap_or_else(|_| "/tmp/agentd_lab_data/risk-policy.json".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::POLICY_PATH.to_string();
    val
}

pub fn health_path() -> String {
    #[cfg(feature = "lab")]
    let val =
        std::env::var("LAB_HEALTH_PATH").unwrap_or_else(|_| "/tmp/agentd_lab_data/health".to_string());
    #[cfg(not(feature = "lab"))]
    let val = phosphor_ipc::HEALTH_PATH.to_string();
    val
}

pub fn socket_path() -> String {
    // The logged constant (section 2.3 socket_listening.path) in BOTH builds;
    // the lab listener itself lives in /tmp (see control_socket_fd).
    phosphor_ipc::SOCKET_PATH.to_string()
}

pub fn now_ms() -> u64 {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_millis() as u64,
        Err(_) => 0,
    }
}

pub fn loop_tick_limit() -> u32 {
    #[cfg(feature = "lab")]
    let val = std::env::var("LAB_TICK_LIMIT")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(u32::MAX);
    #[cfg(not(feature = "lab"))]
    let val = u32::MAX;
    val
}

// ---- data dir (section 2.4 step 2) ---------------------------------------

pub fn ensure_private_data_dir() -> std::io::Result<()> {
    use std::os::unix::fs::MetadataExt; // AUDIT FIX (BUG #C): md.uid() needs this
    use std::os::unix::fs::PermissionsExt;
    let path_buf = data_dir(); // AUDIT FIX (BUG #D): bind; &temp is E0716
    let path = std::path::Path::new(&path_buf);
    match std::fs::metadata(path) {
        Ok(md) => {
            if !md.is_dir() {
                return Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists, "not_a_dir"));
            }
            if md.uid() != unsafe { libc::geteuid() } {
                // Foreign owner: fatal upstream; never adopt it silently.
                return Err(std::io::Error::new(std::io::ErrorKind::PermissionDenied, "foreign_owner"));
            }
            if md.permissions().mode() & 0o777 != 0o700 {
                std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
            }
            Ok(())
        }
        Err(_) => {
            std::fs::create_dir_all(path)?;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
            Ok(())
        }
    }
}

// ---- socket ----------------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn control_socket_fd(name: &str) -> std::io::Result<RawFd> {
    use std::ffi::CString;
    let c = CString::new(name)
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "bad socket name"))?;
    let fd = unsafe { android_get_control_socket(c.as_ptr()) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(fd)
}

#[cfg(feature = "lab")]
static LAB_LISTEN_FD: std::sync::Mutex<Option<RawFd>> = std::sync::Mutex::new(None);

#[cfg(feature = "lab")]
pub fn set_lab_listen_fd(fd: RawFd) {
    vendor::set_lab_listen_fd(fd as i32);
}

#[cfg(feature = "lab")]
pub fn control_socket_fd(_name: &str) -> std::io::Result<RawFd> {
    if let Some(fd) = vendor::take_lab_listen_fd() {
        return Ok(fd as RawFd);
    }
    // Fallback: a local seqpacket socket, so a lab run never touches /dev.
    let path = std::env::temp_dir().join("phosphor_agentd_lab.sock");
    let _ = std::fs::remove_file(&path);
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in path.to_str().unwrap().as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    let rc = unsafe {
        libc::bind(
            fd,
            &addr as *const libc::sockaddr_un as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
        )
    };
    if rc != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(fd)
}

// ---- peer identity ---------------------------------------------------------

#[cfg(not(feature = "lab"))]
pub fn peer_label(fd: RawFd) -> Option<String> {
    let mut ctx: *mut libc::c_char = std::ptr::null_mut();
    let rc = unsafe { getpeercon(fd, &mut ctx) };
    if rc != 0 || ctx.is_null() {
        return None;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(ctx) }.to_string_lossy().into_owned();
    unsafe { freecon(ctx) };
    Some(s)
}

#[cfg(feature = "lab")]
pub fn peer_label(_fd: RawFd) -> Option<String> {
    // Injected label (ruling: "wrong-label peer rejection (label string injected)").
    Some(std::env::var("LAB_PEER_LABEL").unwrap_or_else(|_| "u:r:shell:s0".to_string()))
}

#[cfg(not(feature = "lab"))]
pub fn peer_ucred(fd: RawFd) -> Option<(u32, u32)> {
    #[repr(C)]
    struct Ucred {
        pid: libc::pid_t,
        uid: libc::uid_t,
        gid: libc::gid_t,
    }
    let mut cred = Ucred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<Ucred>() as libc::socklen_t;
    let rc = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut cred as *mut Ucred as *mut libc::c_void,
            &mut len,
        )
    };
    if rc != 0 {
        return None;
    }
    Some((cred.pid as u32, cred.uid as u32))
}

#[cfg(feature = "lab")]
pub fn peer_ucred(_fd: RawFd) -> Option<(u32, u32)> {
    // Injected identity: logged in peer_rejected, never an admission input.
    let pid = std::env::var("LAB_PEER_PID").ok().and_then(|v| v.parse::<u32>().ok()).unwrap_or(4242);
    let uid = std::env::var("LAB_PEER_UID").ok().and_then(|v| v.parse::<u32>().ok()).unwrap_or(10000);
    Some((pid, uid))
}

// ---- accept / socket metadata ----------------------------------------------

pub fn accept(listen_fd: RawFd) -> std::io::Result<RawFd> {
    let fd = unsafe { libc::accept(listen_fd, std::ptr::null_mut(), std::ptr::null_mut()) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(fd)
}

pub fn socket_ids(fd: RawFd) -> (u32, u32, u32) {
    use std::os::unix::fs::MetadataExt; // AUDIT FIX (BUG #C): md.uid()/gid()
    use std::os::unix::fs::PermissionsExt; // AUDIT FIX (BUG #C): .mode() on Permissions
    use std::os::unix::io::FromRawFd;
    // fstat without taking ownership of the fd (ManuallyDrop: never close).
    let f = std::mem::ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(fd) });
    match f.metadata() {
        Ok(md) => (md.uid(), md.gid(), md.permissions().mode() & 0o777),
        Err(_) => (0, 0, 0),
    }
}

// ---- SIGTERM self-pipe (section 2.5: a cancellable loop, clean shutdown) ---

static SIG_WAKER_WRITE: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

pub struct SignalWaker {
    read_fd: RawFd,
    write_fd: RawFd,
    prev_handler: libc::sighandler_t,
}

impl SignalWaker {
    pub fn install() -> std::io::Result<SignalWaker> {
        let mut fds = [0 as RawFd; 2];
        if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let (r, w) = (fds[0], fds[1]);
        SIG_WAKER_WRITE.store(w, std::sync::atomic::Ordering::SeqCst);
        extern "C" fn on_sigterm(_sig: libc::c_int) {
            let fd = SIG_WAKER_WRITE.load(std::sync::atomic::Ordering::SeqCst);
            if fd >= 0 {
                let b: u8 = 1;
                unsafe { libc::write(fd, &b as *const u8 as *const libc::c_void, 1) };
            }
        }
        let prev = unsafe {
            libc::signal(libc::SIGTERM, on_sigterm as extern "C" fn(libc::c_int) as libc::sighandler_t)
        };
        Ok(SignalWaker { read_fd: r, write_fd: w, prev_handler: prev })
    }

    pub fn read_fd(&self) -> RawFd {
        self.read_fd
    }

    pub fn drain(&self) {
        // AUDIT FIX (BUG #F): the pipe is blocking; looping read() until <=0
        // deadlocks on the second read (the handler writes exactly 1 byte per
        // signal). Read the pending bytes only.
        let mut b = [0u8; 64];
        unsafe {
            libc::read(self.read_fd, b.as_mut_ptr() as *mut libc::c_void, b.len());
        }
    }
}

impl Drop for SignalWaker {
    fn drop(&mut self) {
        unsafe { libc::signal(libc::SIGTERM, self.prev_handler) };
        SIG_WAKER_WRITE.store(-1, std::sync::atomic::Ordering::SeqCst);
        unsafe { libc::close(self.read_fd) };
        unsafe { libc::close(self.write_fd) };
    }
}
