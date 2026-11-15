//! lab_vendor.rs -- AUDIT-ONLY host stand-in for the plan §6 vendor-lib
//! linkage (liblibc + a host-visible set_lab_listen_fd seam). The DEVICE
//! build links the real liblibc crate and calls the real librustutils
//! android::sockets wrapper. Compiled as extern crate `vendor`; platform.rs's
//! lab `set_lab_listen_fd` resolves through it.

pub use libc as _libc_reexport;

/// Host-lab fd injection point (mirrors the device seam without the FFI).
pub static LAB_LISTEN_FD: std::sync::Mutex<Option<i32>> = std::sync::Mutex::new(None);

pub fn set_lab_listen_fd(fd: i32) {
    *LAB_LISTEN_FD.lock().unwrap() = Some(fd);
}

pub fn take_lab_listen_fd() -> Option<i32> {
    LAB_LISTEN_FD.lock().unwrap().take()
}
