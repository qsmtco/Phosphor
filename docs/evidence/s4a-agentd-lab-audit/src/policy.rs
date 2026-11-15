// policy.rs -- the read-only risk-policy artifact (section 2.4 step 3).
// Missing, unparseable, or version-less => fail closed: a daemon that cannot
// classify must not exist (section 6.3 rationale). S4 reports the version
// and fingerprint only; real parsing/classification is S6.
//
// AUDIT NOTE (rev-2 delta re-transcription): byte-faithful to plan §4.5 —
// ONE serde_json code path. In the lab, `serde_json` resolves to the extern
// lab_serde stand-in rlib (rev-2 §7.2/§8: --extern serde_json=...); on
// device it is the real libserde_json via rustlibs. Identical code either
// way — this is the exact form rev-2 ships.

use crate::sha256;

pub struct LoadedPolicy {
    pub version: String,
    pub sha256: String,
}

pub fn load(path: &str) -> Result<LoadedPolicy, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("read_failed: {}", e))?;
    let v: serde_json::Value =
        serde_json::from_slice(&bytes).map_err(|e| format!("unparseable: {}", e))?;
    let ver = match v.get("policy_version") {
        None | Some(serde_json::Value::Null) => return Err("policy_version_missing".to_string()),
        Some(serde_json::Value::String(s)) => s.clone(),
        Some(serde_json::Value::Number(n)) => n.to_string(),
        Some(_) => return Err("policy_version_unparseable".to_string()),
    };
    if ver.is_empty() {
        return Err("policy_version_missing".to_string());
    }
    Ok(LoadedPolicy { version: ver, sha256: sha256::hex(&sha256::sha256(&bytes)) })
}
