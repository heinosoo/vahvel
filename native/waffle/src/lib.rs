mod dense;
mod opt;
mod random;
mod sparse;
mod utils;

#[rustler::nif]
fn nif_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

rustler::init!("nif");
