// policy.rs -- the read-only risk-policy artifact (section 2.4 step 3).
// Missing, unparseable, or version-less => fail closed: a daemon that cannot
// classify must not exist (section 6.3 rationale). S4 reports the version
// and fingerprint only; real parsing/classification is S6.
//
// AUDIT NOTE: the device branch (`not(feature = "lab")`) is the plan's
// original serde_json code path, unchanged. The lab branch swaps in the
// audit lab_serde parser (same `Value`/`get` surface) because the plan's
// §8 harness build block links no JSON crate; the loader's decision
// semantics (parse/absent/version-type) are identical, and the device path
// still compiles against real serde_json at `m phosphor-agentd` time
// (§11.2 STOP item covers a soong-level linkage failure there).

use crate::sha256;

pub struct LoadedPolicy {
    pub version: String,
    pub sha256: String,
}

#[cfg(not(feature = "lab"))]
pub fn load(path: &str) -> Result<LoadedPolicy, String> {
    device_load(path)
}

#[cfg(not(feature = "lab"))]
fn device_load(path: &str) -> Result<LoadedPolicy, String> {
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

#[cfg(feature = "lab")]
pub fn load(path: &str) -> Result<LoadedPolicy, String> {
    lab_load(path)
}

#[cfg(feature = "lab")]
fn lab_load(path: &str) -> Result<LoadedPolicy, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("read_failed: {}", e))?;
    let v: lab_serde::Value =
        lab_serde::from_slice(&bytes).map_err(|e| format!("unparseable: {}", e))?;
    let ver = match v.get("policy_version") {
        None | Some(lab_serde::Value::Null) => return Err("policy_version_missing".to_string()),
        Some(lab_serde::Value::String(s)) => s.clone(),
        Some(lab_serde::Value::Number(n)) => n.to_string(),
        Some(_) => return Err("policy_version_unparseable".to_string()),
    };
    if ver.is_empty() {
        return Err("policy_version_missing".to_string());
    }
    Ok(LoadedPolicy { version: ver, sha256: sha256::hex(&sha256::sha256(&bytes)) })
}
