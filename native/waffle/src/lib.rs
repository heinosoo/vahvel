#[rustler::nif]
fn add_floats(a: f64, b: f64) -> f64 {
    a + b
}

rustler::init!("waffle_ffi");
