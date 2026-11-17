mod driver;

#[rustler::nif]
fn nif_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

rustler::init!("vahvel_nif");
