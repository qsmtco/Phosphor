// start_condition.rs -- section 2.2 defence in depth. The daemon refuses to
// run unless sys.phosphor.safeboot is EXACTLY "0". Not redundant with init's
// trigger: it protects against a future .rc edit, a class_start regression,
// or a manual start that bypasses the property trigger. An unreadable or
// empty value is NOT "0" => refuse (fail closed; spec section 5 row 2 records
// this as intended behaviour, not a bug).

use crate::platform;

pub enum Verdict {
    Proceed,
    Refused(String),
}

pub fn check() -> Verdict {
    match platform::read_prop(platform::SAFEBOOT_PROP) {
        Some(v) if v == "0" => Verdict::Proceed,
        Some(v) => Verdict::Refused(v),
        None => Verdict::Refused("<absent>".to_string()),
    }
}
