// phosphor_ipc.rs -- byte-transcription of the plan rev 2 §3.2
// services/PhosphorIpc/lib.rs (audit copy; the payload file lives in the
// tree post-S4-B.3). Referenced by the lab harness as
// `#[path = "phosphor_ipc.rs"] mod phosphor_ipc` so the daemon sources'
// `crate::phosphor_ipc` resolves exactly as on device.

/// Init's socket keyword name (the .rc `socket` line); init creates
/// /dev/socket/<name> and hands the fd via android_get_control_socket(name).
pub const SOCKET_NAME: &str = "phosphor_agentd";
/// Where init creates it (erratum 19 -- the daemon never binds or unlinks).
pub const SOCKET_PATH: &str = "/dev/socket/phosphor_agentd";

/// Erratum 19: label-only admission. The UID half of the old two-condition
/// check was incoherent (PhosphorShell is a plain app uid, never 7523 --
/// preflight PF-BUG #2); SO_PEERCRED is logged as defense-in-depth only.
pub const ACCEPTED_PEER_LABEL: &str = "u:r:phosphor_shell:s0";

// Frame wire format: fixed 8-byte header + body, one datagram per
// SOCK_SEQPACKET frame. MAX_FRAME_LEN caps the TOTAL frame (header+body).
// 1 MiB is frozen here (S4 open item 2 / S7 section 2.1): the Phase 6 screen
// payload may exceed it and MUST be chunked -- or the limit raised by a
// reviewed change -- never silently exceeded.
pub const FRAME_VERSION: u16 = 1;
pub const FRAME_HEADER_LEN: usize = 8;
pub const MAX_FRAME_LEN: usize = 1 << 20;

// Frame types (P5-S7 section 2.1's table: HELLO/HELLO_ACK/TEXT_IN/TEXT_ACK/
// SCREEN_OUT/STATE/ERROR). NOT_IMPLEMENTED is NOT a frame type there -- it is
// an ERROR *code* (P5-S7 section 2.1, ERROR row). Rev-1's phantom
// TYPE_NOT_IMPLEMENTED = 8 is removed in this revision (S4-A audit BUG #6):
// S4's well-formed-frame reply is a TYPE_ERROR frame whose body is the ASCII
// bytes of the code "NOT_IMPLEMENTED" (newline-terminated, 15 bytes), and the
// exact reply shape is what S7's author reconciles -- or amends into the
// table -- in P5-S7 (this plan's Related issue 10). Any frame type or ERROR
// code outside S7 section 2.1's vocabulary must be added here by a reviewed
// change, never invented at a call site.
pub const TYPE_HELLO: u16 = 1;
pub const TYPE_HELLO_ACK: u16 = 2;
pub const TYPE_TEXT_IN: u16 = 3;
pub const TYPE_TEXT_ACK: u16 = 4;
pub const TYPE_SCREEN_OUT: u16 = 5;
pub const TYPE_STATE: u16 = 6;
pub const TYPE_ERROR: u16 = 7;

// The ERROR-code vocabulary of P5-S7 section 2.1 (the only legal reply-body
// codes), newline-terminated ASCII; body_len carries the exact length.
pub const ERROR_CODE_NOT_IMPLEMENTED: &[u8] = b"NOT_IMPLEMENTED\n";
pub const ERROR_CODE_BAD_VERSION: &[u8] = b"BAD_VERSION\n";
pub const ERROR_CODE_BAD_FRAME: &[u8] = b"BAD_FRAME\n";
pub const ERROR_CODE_POLICY_INVALID: &[u8] = b"POLICY_INVALID\n";

// Runtime paths (spec section 2.4/2.6).
pub const DATA_DIR: &str = "/data/misc/phosphor";
pub const POLICY_PATH: &str = "/system/etc/phosphor/risk-policy.json";
pub const HEALTH_PATH: &str = "/data/misc/phosphor/health";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameHeader {
    pub version: u16,
    pub frame_type: u16,
    pub body_len: u32,
}

pub fn encode_header(h: FrameHeader) -> [u8; FRAME_HEADER_LEN] {
    let mut out = [0u8; FRAME_HEADER_LEN];
    out[0..2].copy_from_slice(&h.version.to_be_bytes());
    out[2..4].copy_from_slice(&h.frame_type.to_be_bytes());
    out[4..8].copy_from_slice(&h.body_len.to_be_bytes());
    out
}

pub fn decode_header(buf: &[u8]) -> Option<FrameHeader> {
    if buf.len() < FRAME_HEADER_LEN {
        return None;
    }
    Some(FrameHeader {
        version: u16::from_be_bytes([buf[0], buf[1]]),
        frame_type: u16::from_be_bytes([buf[2], buf[3]]),
        body_len: u32::from_be_bytes([buf[4], buf[5], buf[6], buf[7]]),
    })
}
