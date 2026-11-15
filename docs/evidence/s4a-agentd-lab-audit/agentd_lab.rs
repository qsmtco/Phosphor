// /tmp/agentd_lab.rs -- P5-S4 host lab harness. Lab-only; NOT a payload
// artifact. Includes the REAL tree sources (provenance-explicit, keygate
// pattern) and drives the decision-tree scenarios; the scenario name is
// argv[1]. Build (plan section 8, lab block):
//   rustc --crate-type lib --crate-name libc lab_libc.rs -o liblibc_lab.rlib
//   rustc --edition 2021 --cfg 'feature="lab"' --extern libc=liblibc_lab.rlib \
//         agentd_lab.rs -o agentd_lab
//
// Module-resolution note: the real src/main.rs is included at the crate ROOT
// (include!), so its own `mod` declarations resolve against the real src/
// directory, and the modules' `use crate::phosphor_ipc` resolves to the local
// mod declared below. main.rs's device `fn main` is cfg'd out under the lab
// feature, so the harness's own main is the only one.
#![allow(dead_code)]

#[path = "phosphor_ipc.rs"] // rev-2 §7.2 form (mod from a tree-file path)
mod phosphor_ipc;
// AUDIT: serde_json + vendor are compiled as EXTERN crate libs per rev-2
// §7.2's include!-resolution note (top-level paths in include!'d files
// resolve against the extern prelude).

const LAB_SOCK: &str = "/tmp/agentd_lab.sock";
const LAB_DATA: &str = "/tmp/agentd_lab_data";

include!("src/main.rs"); // rev-2 §7.2: the REAL tree main.rs included at crate root

fn fresh_env() {
    let _ = std::fs::remove_dir_all(LAB_DATA);
    let _ = std::fs::remove_file(LAB_SOCK);
    std::env::remove_var("LAB_PROP_sys_phosphor_safeboot");
    std::env::remove_var("LAB_POLICY_PATH");
    std::env::remove_var("LAB_PEER_LABEL");
    std::env::set_var("LAB_DATA_DIR", LAB_DATA);
    std::env::set_var("LAB_HEALTH_PATH", format!("{}/health", LAB_DATA));
}

fn write_policy(body: &str) {
    std::fs::create_dir_all(LAB_DATA).unwrap();
    std::fs::write(format!("{}/risk-policy.json", LAB_DATA), body).unwrap();
    std::env::set_var("LAB_POLICY_PATH", format!("{}/risk-policy.json", LAB_DATA));
}

// Bind-only: init hands a bound, NOT-listening fd; the daemon listens.
fn make_listener() -> i32 {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    assert!(fd >= 0);
    let _ = std::fs::remove_file(LAB_SOCK);
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in LAB_SOCK.as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    assert_eq!(
        unsafe {
            libc::bind(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
            )
        },
        0
    );
    // Big buffers so the oversized-frame datagram actually traverses.
    let bufsz: libc::c_int = 8 << 20;
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_RCVBUF,
            &bufsz as *const libc::c_int as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        )
    };
    fd
}

fn connect_client() -> i32 {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    assert!(fd >= 0);
    let bufsz: libc::c_int = 8 << 20;
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_SNDBUF,
            &bufsz as *const libc::c_int as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        )
    };
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    for (i, b) in LAB_SOCK.as_bytes().iter().enumerate() {
        addr.sun_path[i] = *b as libc::c_char;
    }
    // AUDIT FIX (BUG #E): the daemon reaches listen() only after dir/health/
    // policy work, so an immediate connect() hits a bound-but-not-listening
    // socket and gets ECONNREFUSED (reproduced: thread panic, SIGTERM never
    // sent, agentd_main spins forever -> lab hang on all socket scenarios).
    // Retry for up to ~2 s, then fail like the plan's bare assert would.
    let mut ok = false;
    for _ in 0..200 {
        let rc = unsafe {
            libc::connect(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
            )
        };
        if rc == 0 {
            ok = true;
            break;
        }
        unsafe { libc::usleep(10_000) };
    }
    assert!(ok, "connect_client: connect never succeeded within 2s");
    fd
}

fn send_all(fd: i32, data: &[u8]) {
    let n = unsafe { libc::send(fd, data.as_ptr() as *const libc::c_void, data.len(), 0) };
    assert_eq!(n, data.len() as isize);
}

fn recv_some(fd: i32, buf: &mut [u8]) -> isize {
    unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) }
}

fn sigterm_self() {
    unsafe { libc::kill(libc::getpid(), libc::SIGTERM) };
}

fn print_health() {
    match std::fs::read_to_string(format!("{}/health", LAB_DATA)) {
        Ok(t) => {
            for line in t.lines() {
                println!("health {}", line);
            }
        }
        Err(_) => println!("health_absent=1"),
    }
}

fn main() {
    let scenario = std::env::args().nth(1).unwrap_or_else(|| "unit".to_string());
    let code = run(&scenario);
    std::process::exit(code);
}

fn run(name: &str) -> i32 {
    match name {
        // (1) refuse-start, safeboot=1 -- the section 2.2 defence. REQUIRED.
        "refuse_safeboot1" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "1");
            let rc = agentd_main();
            println!("data_dir_absent={}", !std::path::Path::new(LAB_DATA).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (2) refuse-start, safeboot unreadable (absent => refuse, section 5 row 2).
        "refuse_absent" => {
            fresh_env();
            let rc = agentd_main();
            println!("data_dir_absent={}", !std::path::Path::new(LAB_DATA).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (3) policy missing => fatal. REQUIRED.
        "policy_missing" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            std::env::set_var("LAB_POLICY_PATH", "/tmp/agentd_lab_no_such_policy.json");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (4) policy garbage => fatal. REQUIRED.
        "policy_garbage" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{ this is not json");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (5) policy without policy_version => fatal (section 5 last row). REQUIRED.
        "policy_no_version" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"something\":1}");
            let rc = agentd_main();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (6) healthy start to loop, then clean SIGTERM shutdown. REQUIRED.
        "healthy_start" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                std::thread::sleep(std::time::Duration::from_millis(400));
                println!("client_connected=1");
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            print_health();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (7) wrong-label peer rejection (label string injected). REQUIRED.
        "wrong_label" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:shell:s0"); // NOT the accepted label
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let mut buf = [0u8; 64];
                let n = recv_some(c, &mut buf); // server must close on rejection
                println!("client_closed={}", n == 0);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (8) oversized frame => close + peer_rejected. REQUIRED.
        "oversized_frame" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let big = vec![0u8; phosphor_ipc::MAX_FRAME_LEN + 1];
                send_all(c, &big);
                let mut buf = [0u8; 64];
                let n = recv_some(c, &mut buf);
                println!("client_closed={}", n == 0);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (9) well-formed frame => frame_len= log + NOT_IMPLEMENTED reply (ruling 8).
        "wellformed_frame" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let mut frame = vec![0u8; 12];
                frame[0] = 0;
                frame[1] = 1; // version = 1
                frame[2] = 0;
                frame[3] = 1; // type = HELLO
                frame[4] = 0;
                frame[5] = 0;
                frame[6] = 0;
                frame[7] = 4; // body_len = 4
                frame[8] = b'a';
                frame[9] = b'b';
                frame[10] = b'c';
                frame[11] = b'd';
                send_all(c, &frame);
                // AUDIT DIAG (BUG #11): loop-recv exactly 23 bytes and dump
                // what arrives, to split fragmentation vs content mismatch.
                let mut buf = [0u8; 64];
                let mut total = 0usize;
                while total < 24 {
                    let n = recv_some(c, &mut buf[total..]);
                    if n <= 0 {
                        break;
                    }
                    total += n as usize;
                }
                let hexdump: String =
                    buf[..total].iter().map(|b| format!("{:02x}", b)).collect::<String>();
                println!("reply_total={} hex={}", total, hexdump);
                let ok = total == 24 && buf[..24] == phosphor_ipc::ERROR_CODE_NOT_IMPLEMENTED_REPLY();
                println!("reply_ok={}", ok);
                unsafe { libc::close(c) };
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (10) clean SIGTERM shutdown; init owns the socket file (no unlink). REQUIRED.
        "sigterm_shutdown" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                std::thread::sleep(std::time::Duration::from_millis(300));
                sigterm_self();
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("socket_file_still_exists={}", std::path::Path::new(LAB_SOCK).exists());
            println!("scenario={} exit={}", name, rc);
            rc
        }
        // (11) crashloop backoff trip (erratum 18: the daemon's own backstop). REQUIRED.
        "crashloop_trip" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            std::env::set_var("LAB_POLICY_PATH", "/tmp/agentd_lab_no_such_policy.json");
            // Seed: two consecutive fast deaths already recorded.
            std::fs::create_dir_all(LAB_DATA).unwrap();
            std::fs::write(
                format!("{}/health", LAB_DATA),
                "pid=1\nstarted_at=0\npolicy_version=none\nlast_frame_at=0\nfast_crashes=2\ndied_fast=1\ncrashloop=0\n",
            )
            .unwrap();
            let rc1 = agentd_main(); // third fast death: trips the marker
            println!("exit1={}", rc1);
            print_health();
            let rc2 = agentd_main(); // latched: exits without touching policy
            println!("exit2={}", rc2);
            println!("scenario={} exit={}", name, rc2);
            rc2
        }
        // (12) unit: sha256 vectors + frame-header codec roundtrip.
        "unit" => {
            let ok_sha_empty = sha256::hex(&sha256::sha256(b""))
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
            let ok_sha_abc = sha256::hex(&sha256::sha256(b"abc"))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
            let h = phosphor_ipc::FrameHeader { version: 1, frame_type: 3, body_len: 7 };
            let enc = phosphor_ipc::encode_header(h);
            let dec = phosphor_ipc::decode_header(&enc);
            let ok_hdr = dec == Some(h) && phosphor_ipc::decode_header(&[0u8; 4]).is_none();
            println!("unit_ok={}", ok_sha_empty && ok_sha_abc && ok_hdr);
            if ok_sha_empty && ok_sha_abc && ok_hdr {
                0
            } else {
                1
            }
        }
        // (13) AUDIT ADVERSARIAL: peer sends a valid frame then closes
        // instantly -- the server's reply send() hits a dead socket. With
        // flags=0 and no SIGPIPE disposition, POSIX raises SIGPIPE: default
        // action terminates the process. (Plan §4.8 send calls carry no
        // MSG_NOSIGNAL and no SIGPIPE handler exists.)
        "sigpipe_attack" => {
            fresh_env();
            std::env::set_var("LAB_PROP_sys_phosphor_safeboot", "0");
            write_policy("{\"policy_version\":\"1.0\"}");
            std::env::set_var("LAB_PEER_LABEL", "u:r:phosphor_shell:s0");
            let lfd = make_listener();
            platform::set_lab_listen_fd(lfd);
            let t = std::thread::spawn(|| {
                let c = connect_client();
                let mut frame = vec![0u8; 12];
                frame[1] = 1; // version = 1
                frame[3] = 1; // type = HELLO
                frame[7] = 4; // body_len = 4
                send_all(c, &frame);
                unsafe { libc::close(c) }; // gone before the reply can land
                println!("client_closed_instantly=1");
            });
            let rc = agentd_main();
            let _ = t.join();
            println!("survived=1 scenario={} exit={}", name, rc);
            0
        }
        _ => {
            println!("unknown scenario {}", name);
            2
        }
    }
}
