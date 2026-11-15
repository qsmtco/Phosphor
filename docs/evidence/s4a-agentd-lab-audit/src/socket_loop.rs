// socket_loop.rs -- the init-managed AF_UNIX SOCK_SEQPACKET server (section 2.5).
//
// The listening fd is handed over by init (android_get_control_socket,
// erratum 19): init created it bound (seqpacket+passcred 0660) but NOT
// listening -- the daemon calls listen(2) itself, mirroring lmkd's
// consumption of its init socket. The daemon never binds and never unlinks:
// init owns /dev/socket/phosphor_agentd for the service's whole life.
//
// Admission is LABEL-ONLY (erratum 19): getpeercon(3) on the accepted fd must
// return exactly u:r:phosphor_shell:s0. SO_PEERCRED (enabled by init's
// +passcred) is read for the peer_rejected log only -- it is defense in
// depth, never an admission criterion (preflight PF-BUG #2).
//
// Framing: one datagram == one frame: 8-byte header (PhosphorIpc) + body.
// Frames over MAX_FRAME_LEN (1 MiB) => close + peer_rejected. S4 has zero
// message semantics: a well-formed frame is logged (frame_len=) and answered
// with NOT_IMPLEMENTED; S7 replaces this handler.

use crate::health;
use crate::health::HealthRecord;
use crate::logging;
use crate::platform;
use crate::phosphor_ipc;
use crate::stubs::Agentd;
use std::os::unix::io::RawFd;

pub enum LoopExit {
    Sigterm,
    TickLimit,
    Fatal(String),
}

enum FrameOutcome {
    Served,
    Closed,
    Rejected(&'static str),
}

struct PeerInfo {
    pid: u32,
    uid: u32,
}

struct Conn {
    fd: RawFd,
    peer: PeerInfo,
}

pub fn run(
    listen_fd: RawFd,
    health_path: &str,
    rec: &mut HealthRecord,
    _agent: &Agentd, // S7's frame handler takes these hooks; unused in S4
    tick_limit: u32,
) -> LoopExit {
    // init hands a bound, not-yet-listening socket (lmkd pattern: the daemon
    // listens). No bind here, and no unlink on any path.
    if unsafe { libc::listen(listen_fd, 8) } != 0 {
        return LoopExit::Fatal(format!("listen: {}", std::io::Error::last_os_error()));
    }
    let (uid, gid, mode) = platform::socket_ids(listen_fd);
    logging::socket_listening(&platform::socket_path(), uid, gid, mode);

    let waker = match platform::SignalWaker::install() {
        Ok(w) => w,
        Err(err) => return LoopExit::Fatal(format!("signal setup: {}", err)),
    };

    let mut conn: Option<Conn> = None;
    // +1 so a datagram of exactly MAX_FRAME_LEN+1 is received fully enough to
    // be detected as oversized (SOCK_SEQPACKET preserves message boundaries;
    // a too-large datagram is truncated to the buffer, the excess discarded).
    let mut buf = vec![0u8; phosphor_ipc::MAX_FRAME_LEN + 1];
    let mut ticks: u32 = 0;

    loop {
        let mut fds = [
            libc::pollfd { fd: listen_fd, events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: waker.read_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd {
                fd: conn.as_ref().map(|c| c.fd).unwrap_or(-1),
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), 3, 200) }; // 200 ms health tick
        if ready < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return LoopExit::Fatal(format!("poll: {}", err));
        }
        if fds[1].revents & libc::POLLIN != 0 {
            waker.drain();
            // Clean SIGTERM shutdown. NO unlink: init owns the socket file
            // (erratum 19; the spec section 5 "unlink socket" row is superseded).
            return LoopExit::Sigterm;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            match platform::accept(listen_fd) {
                Ok(fd) => match admit(fd) {
                    Ok(Some(c)) => {
                        // Single admitted peer: a new admission replaces the
                        // old one (the S7 single-peer invariant).
                        if let Some(old) = conn.take() {
                            unsafe { libc::close(old.fd) };
                        }
                        conn = Some(c);
                    }
                    Ok(None) => {} // rejected and closed inside admit()
                    Err(err) => return LoopExit::Fatal(err),
                },
                Err(err) => {
                    if err.kind() != std::io::ErrorKind::WouldBlock {
                        return LoopExit::Fatal(format!("accept: {}", err));
                    }
                }
            }
        }
        let mut close_conn = false;
        if let Some(c) = conn.as_mut() {
            if fds[2].revents & libc::POLLIN != 0 {
                let n = unsafe { libc::recv(c.fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
                if n <= 0 {
                    close_conn = true; // peer closed (or recv error)
                } else {
                    match handle_frame(c, &buf[..n as usize]) {
                        FrameOutcome::Served => rec.last_frame_at = platform::now_ms(),
                        FrameOutcome::Closed => close_conn = true,
                        FrameOutcome::Rejected(reason) => {
                            logging::peer_rejected(c.peer.pid, c.peer.uid, reason);
                            close_conn = true;
                        }
                    }
                }
            }
        }
        if close_conn {
            if let Some(c) = conn.take() {
                unsafe { libc::close(c.fd) };
            }
        }
        ticks += 1;
        if ticks >= tick_limit {
            return LoopExit::TickLimit;
        }
        health::touch_tick(health_path, rec); // section 2.6: touched each loop tick
    }
}

fn admit(fd: RawFd) -> Result<Option<Conn>, String> {
    let label = platform::peer_label(fd);
    let (pid, uid) = platform::peer_ucred(fd).unwrap_or((0, 0)); // logged, not admitted on
    let admitted = matches!(&label, Some(l) if l == phosphor_ipc::ACCEPTED_PEER_LABEL);
    if !admitted {
        logging::peer_rejected(pid, uid, "label_mismatch");
        unsafe { libc::close(fd) };
        return Ok(None);
    }
    Ok(Some(Conn { fd, peer: PeerInfo { pid, uid } }))
}

fn handle_frame(c: &Conn, frame: &[u8]) -> FrameOutcome {
    if frame.len() > phosphor_ipc::MAX_FRAME_LEN {
        return FrameOutcome::Rejected("oversized_frame"); // section 2.5: close + peer_rejected
    }
    let hdr = match phosphor_ipc::decode_header(frame) {
        Some(h) => h,
        None => return FrameOutcome::Rejected("malformed_frame"),
    };
    if hdr.version != phosphor_ipc::FRAME_VERSION
        || hdr.body_len as usize != frame.len() - phosphor_ipc::FRAME_HEADER_LEN
    {
        return FrameOutcome::Rejected("malformed_frame");
    }
    // Zero message semantics in S4: log the frame, answer TYPE_ERROR carrying
    // the ERROR code NOT_IMPLEMENTED (rev 2; audit BUG #6 -- S7 section 2.1
    // defines NOT_IMPLEMENTED as an ERROR code, not a frame type; S7's author
    // reconciles the reply shape, Related issue 10).
    logging::plain(&format!("frame_len={}", frame.len()));
    // AUDIT FIX (BUG #10): encode_header returns a fixed-size [u8; 8]; a
    // fixed-size array has no extend_from_slice (E0599, reproduced). to_vec()
    // is the minimal mechanical repair — as_ptr/len semantics unchanged.
    let mut reply = phosphor_ipc::encode_header(phosphor_ipc::FrameHeader {
        version: phosphor_ipc::FRAME_VERSION,
        frame_type: phosphor_ipc::TYPE_ERROR,
        body_len: phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED.len() as u32,
    })
    .to_vec();
    let body = phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED;
    reply.extend_from_slice(body);
    let sent = unsafe { libc::send(c.fd, reply.as_ptr() as *const libc::c_void, reply.len(), 0) };
    if sent < 0 {
        return FrameOutcome::Closed; // peer gone; not a rejection
    }
    FrameOutcome::Served
}
