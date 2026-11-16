// probe: bin crate WITH crate-level inner doc under -D missing_docs (control)
//! probe crate doc
pub fn helper() -> u32 { 1 }
fn main() { let _ = helper(); }
