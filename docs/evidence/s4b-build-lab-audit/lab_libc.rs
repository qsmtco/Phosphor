// /tmp/lab_libc.rs -- minimal libc surface for the P5-S4 host lab (the exact
// subset phosphor-agentd uses). Lab-only; the device build links the real
// libc crate via soong. Host linux x86_64 values.
#![allow(non_camel_case_types)]

pub type c_int = i32;
pub type c_char = i8;
// rev 2 (audit BUG #3): `#[repr(C)]` is illegal on a zero-variant enum
// (E0084). A bare empty enum is the FFI-legal form -- exactly what the real
// `libc` crate ships.
pub enum c_void {}
pub type socklen_t = u32;
pub type uid_t = u32;
pub type gid_t = u32;
pub type pid_t = i32;
pub type sa_family_t = u16;
pub type sighandler_t = usize;

pub const AF_UNIX: c_int = 1;
pub const SOCK_SEQPACKET: c_int = 5;
pub const SOL_SOCKET: c_int = 1;
pub const SO_PEERCRED: c_int = 17;
pub const SO_SNDBUF: c_int = 7;
pub const SO_RCVBUF: c_int = 8;
pub const POLLIN: i16 = 0x1;
pub const SIGTERM: c_int = 15;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct pollfd {
    pub fd: c_int,
    pub events: i16,
    pub revents: i16,
}

#[repr(C)]
pub struct sockaddr {
    pub sa_family: sa_family_t,
    pub sa_data: [c_char; 14],
}

#[repr(C)]
pub struct sockaddr_un {
    pub sun_family: sa_family_t,
    pub sun_path: [c_char; 108],
}

extern "C" {
    pub fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    pub fn bind(fd: c_int, addr: *const sockaddr, len: socklen_t) -> c_int;
    pub fn connect(fd: c_int, addr: *const sockaddr, len: socklen_t) -> c_int;
    pub fn listen(fd: c_int, backlog: c_int) -> c_int;
    pub fn accept(fd: c_int, addr: *mut sockaddr, len: *mut socklen_t) -> c_int;
    pub fn recv(fd: c_int, buf: *mut c_void, len: usize, flags: c_int) -> isize;
    pub fn send(fd: c_int, buf: *const c_void, len: usize, flags: c_int) -> isize;
    pub fn close(fd: c_int) -> c_int;
    pub fn setsockopt(fd: c_int, level: c_int, name: c_int, val: *const c_void, len: socklen_t) -> c_int;
    pub fn poll(fds: *mut pollfd, nfds: u64, timeout: c_int) -> c_int;
    pub fn pipe(fds: *mut c_int) -> c_int;
    pub fn read(fd: c_int, buf: *mut c_void, n: usize) -> isize;
    pub fn write(fd: c_int, buf: *const c_void, n: usize) -> isize;
    pub fn signal(sig: c_int, handler: sighandler_t) -> sighandler_t;
    pub fn kill(pid: pid_t, sig: c_int) -> c_int;
    pub fn getpid() -> pid_t;
    pub fn geteuid() -> uid_t;
    // rev 2 (audit BUG #5): connect_client()'s bounded retry needs a sleep
    // primitive (the retry loop waits ~10 ms between connect attempts).
    pub fn usleep(usec: c_int) -> c_int;
}
