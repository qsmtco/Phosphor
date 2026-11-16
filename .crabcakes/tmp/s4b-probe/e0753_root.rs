// probe: include! splices inner doc comment at non-first position -> expect E0753
mod prior_item {}
include!("/home/cptjaqx/projects/Phosphor/.crabcakes/tmp/s4b-probe/e0753_inner.rs");
fn main() { let _ = x(); }
