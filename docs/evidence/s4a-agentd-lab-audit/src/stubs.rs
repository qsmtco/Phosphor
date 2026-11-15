// stubs.rs -- the turn/state ownership hooks as NAMED stubs (spec section 1.7,
// ruling 11). Later phases replace the impls without reshaping the process.
// Stubs are write-free: nothing here touches the data dir (preflight PF-A7),
// and no credential material is ever accepted or returned (section 2.7 / A9).

// A transcript turn, reduced to metadata only in S4 (no bodies -- the
// section 2.3 redaction rule).
pub struct TurnRecord {
    pub seq: u64,
    pub body_len: usize,
}

pub struct ActionRequest {
    pub kind: &'static str,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    Allow,
    Deny,
    NotClassified, // S4's classifier reports the policy version only (section 1 non-goal)
}

pub trait TranscriptStore {
    fn append(&mut self, turn: &TurnRecord) -> Result<(), String>;
    fn last_seq(&self) -> Option<u64>;
}

/// S4 stub: in-memory, never persists. S5 replaces it with the real store.
pub struct NullTranscriptStore;

impl TranscriptStore for NullTranscriptStore {
    fn append(&mut self, _turn: &TurnRecord) -> Result<(), String> {
        Ok(())
    }
    fn last_seq(&self) -> Option<u64> {
        None
    }
}

pub trait Classifier {
    fn policy_version(&self) -> &str;
    fn classify(&self, req: &ActionRequest) -> Decision;
}

/// S4 stub: carries the loaded policy_version (A7 evidence); classifies nothing.
pub struct VersionOnlyClassifier {
    version: String,
}

impl VersionOnlyClassifier {
    pub fn new(version: &str) -> Self {
        VersionOnlyClassifier { version: version.to_string() }
    }
}

impl Classifier for VersionOnlyClassifier {
    fn policy_version(&self) -> &str {
        &self.version
    }
    fn classify(&self, _req: &ActionRequest) -> Decision {
        Decision::NotClassified
    }
}

pub trait QuarantineEnvelope {
    fn seal(&self, payload: &[u8]) -> Result<Vec<u8>, String>;
    fn unseal(&self, blob: &[u8]) -> Result<Vec<u8>, String>;
}

/// S4 stub: identity over an empty set; REC-5 fills it later.
pub struct NullQuarantine;

impl QuarantineEnvelope for NullQuarantine {
    fn seal(&self, payload: &[u8]) -> Result<Vec<u8>, String> {
        Ok(payload.to_vec())
    }
    fn unseal(&self, blob: &[u8]) -> Result<Vec<u8>, String> {
        Ok(blob.to_vec())
    }
}

// The process-shape bundle (section 1.7): constructed once in agentd_main and
// carried through the loop; S5/S6/S7 replace the impls, not the shape.
#[allow(dead_code)]
pub struct Agentd {
    pub transcript: Box<dyn TranscriptStore>,
    pub classifier: Box<dyn Classifier>,
    pub quarantine: Box<dyn QuarantineEnvelope>,
}
