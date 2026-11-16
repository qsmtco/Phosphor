// probe: bin crate with NO crate-level doc under -D missing_docs
pub fn helper() -> u32 { 1 }
fn main() { let _ = helper(); }
