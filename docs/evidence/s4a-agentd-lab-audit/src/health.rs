// health.rs -- the /data/misc/phosphor/health surface (section 2.6).
//
// Frozen field names (ruling 9, the S8 contract): pid, started_at,
// policy_version, last_frame_at. The crash backstop adds fast_crashes,
// died_fast and crashloop (erratum 18: init has NO crash budget for a
// non-critical service -- it restarts forever at a fixed 5 s period -- so
// this file carries the daemon's own backstop state). The file is 0600 and
// lives in the daemon's private data dir (A8).

#[derive(Clone)]
pub struct HealthRecord {
    pub pid: u32,
    pub started_at: u64,
    pub policy_version: String,
    pub last_frame_at: u64,
    pub fast_crashes: u32,
    pub died_fast: bool,
    pub crashloop: bool,
}

impl HealthRecord {
    pub fn read(path: &str) -> Option<HealthRecord> {
        let text = std::fs::read_to_string(path).ok()?;
        let mut r = HealthRecord {
            pid: 0,
            started_at: 0,
            policy_version: "none".to_string(),
            last_frame_at: 0,
            fast_crashes: 0,
            died_fast: false,
            crashloop: false,
        };
        for line in text.lines() {
            let (k, v) = match line.split_once('=') {
                Some(kv) => kv,
                None => continue,
            };
            match k {
                "pid" => r.pid = v.parse().unwrap_or(0),
                "started_at" => r.started_at = v.parse().unwrap_or(0),
                "policy_version" => r.policy_version = v.to_string(),
                "last_frame_at" => r.last_frame_at = v.parse().unwrap_or(0),
                "fast_crashes" => r.fast_crashes = v.parse().unwrap_or(0),
                "died_fast" => r.died_fast = v == "1",
                "crashloop" => r.crashloop = v == "1",
                _ => {}
            }
        }
        Some(r)
    }

    pub fn write(&self, path: &str) -> std::io::Result<()> {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)?;
        write!(
            f,
            "pid={}\nstarted_at={}\npolicy_version={}\nlast_frame_at={}\nfast_crashes={}\ndied_fast={}\ncrashloop={}\n",
            self.pid,
            self.started_at,
            self.policy_version,
            self.last_frame_at,
            self.fast_crashes,
            self.died_fast as u8,
            self.crashloop as u8
        )
    }
}

// Startup inheritance (section 2.6): the previous run's death counts toward
// the backstop when (a) it recorded its own fast death, or (b) it died within
// 5 s of its start without a chance to record (SIGKILL). A run that lived
// >= 5 s resets the counter. (init's fixed 5 s restart period means a killed
// healthy run's successor starts >= 5 s after the killed run's START, so a
// kill never accumulates -- A4 stays clean.)
pub fn inherited_fast_crashes(prev: Option<&HealthRecord>, now_ms: u64) -> u32 {
    match prev {
        None => 0,
        Some(p) => {
            if p.died_fast {
                p.fast_crashes
            } else if now_ms >= p.started_at.saturating_add(5000) {
                0
            } else {
                p.fast_crashes.saturating_add(1)
            }
        }
    }
}

// Fatal-exit bookkeeping: a fast death increments the consecutive counter;
// the third consecutive fast death latches the crashloop marker (ruling 6:
// 5 s-fast-crash x3 => marker + exit 1). A slow death (>= 5 s uptime) does
// not accumulate.
pub fn record_fast_death(path: &str, base: &HealthRecord, now_ms: u64) {
    let uptime = now_ms.saturating_sub(base.started_at);
    if uptime >= 5000 {
        return;
    }
    let mut r = base.clone();
    r.fast_crashes += 1;
    r.died_fast = true;
    r.crashloop = r.fast_crashes >= 3;
    let _ = r.write(path);
}

// Loop tick (section 2.6: the daemon touches the file each loop tick).
pub fn touch_tick(path: &str, rec: &mut HealthRecord) {
    rec.pid = std::process::id();
    let _ = rec.write(path);
}
