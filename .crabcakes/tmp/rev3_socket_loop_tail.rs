// AUDIT PROBE (rev-3 verification): plan §4.8 tail extracted from
// docs/handoffs/P5-S4-AGENTD-PLAN.md rev 3 (:1240-1261) verbatim, wrapped in
// the minimal context that lets it typecheck as the plan intends.
// Purpose: prove the rev-3 reply block (BUG #10 fix) compiles.

pub mod phosphor_ipc {
    pub const FRAME_VERSION: u16 = 1;
    pub const TYPE_ERROR: u16 = 7;
    pub const ERROR_CODE_NOT_IMPLEMENTED: &[u8] = b"NOT_IMPLEMENTED\n";

    #[derive(Debug, Clone, Copy)]
    pub struct FrameHeader {
        pub version: u16,
        pub frame_type: u16,
        pub body_len: u32,
    }

    pub fn encode_header(h: FrameHeader) -> [u8; 8] {
        let mut b = [0u8; 8];
        b[0] = (h.version >> 8) as u8;
        b[1] = (h.version & 0xff) as u8;
        b[2] = (h.frame_type >> 8) as u8;
        b[3] = (h.frame_type & 0xff) as u8;
        b[4] = (h.body_len >> 24) as u8;
        b[5] = (h.body_len >> 16) as u8;
        b[6] = (h.body_len >> 8) as u8;
        b[7] = (h.body_len & 0xff) as u8;
        b
    }
}

pub struct Client {
    pub fd: i32,
}

pub enum FrameOutcome {
    Served,
    Closed,
    Rejected(&'static str),
}

#[link(name = "c")]
extern "C" {
    fn send(fd: i32, buf: *const u8, len: usize, flags: i32) -> isize;
}

// ---- begin plan text (verbatim from rev 3 :1240-1261) ----
fn handle_zero_frame(c: &Client, frame: &[u8]) -> FrameOutcome {
    if frame.len() < 8 {
        return FrameOutcome::Rejected("malformed_frame");
    }
    // Zero message semantics in S4: log the frame, answer TYPE_ERROR carrying
    // the ERROR code NOT_IMPLEMENTED (rev 2; audit BUG #6 -- S7 section 2.1
    // defines NOT_IMPLEMENTED as an ERROR code, not a frame type; S7's author
    // reconciles the reply shape, Related issue 10).
    let _ = format!("frame_len={}", frame.len());
    let mut reply = phosphor_ipc::encode_header(phosphor_ipc::FrameHeader {
        version: phosphor_ipc::FRAME_VERSION,
        frame_type: phosphor_ipc::TYPE_ERROR,
        body_len: phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED.len() as u32,
    })
    .to_vec();  // rev 3 (audit BUG #10): encode_header returns [u8; 8]; E0599 without this
    let body = phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED;
    reply.extend_from_slice(body);
    let sent = unsafe { send(c.fd, reply.as_ptr(), reply.len(), 0) };
    if sent < 0 {
        return FrameOutcome::Closed; // peer gone; not a rejection
    }
    FrameOutcome::Served
}
// ---- end plan text ----

pub fn main() {
    // Sanity at runtime: wire self-coherence, matching the audit lab hexdump
    // (reply_total=24, header body_len=16, body 4e4f...440a).
    let c = Client { fd: -1 };
    let f = [0u8; 8];
    match handle_zero_frame(&c, &f) {
        FrameOutcome::Closed => {
            // fd -1 => send returns -1 => Closed path; assert arithmetic here:
            assert_eq!(phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED.len(), 16);
            println!("probe: reply block compiles; body_len=16, total=24 — OK");
        }
        _ => panic!("unexpected outcome"),
    }
}
