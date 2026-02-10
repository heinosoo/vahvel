use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, Term};
use std::panic::catch_unwind;

#[rustler::nif]
fn nif_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn solve_linear_system<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let expected_a_len = rows * cols * 8;
    let expected_b_len = rows * 8;

    if a_bin.len() != expected_a_len {
        let error = format!(
            "Matrix binary length {} does not match expected {} for {}x{} matrix",
            a_bin.len(),
            expected_a_len,
            rows,
            cols
        );
        return Ok((Atom::from_str(env, "error").unwrap(), error).encode(env));
    }

    if b_bin.len() != expected_b_len {
        let error = format!(
            "RHS binary length {} does not match expected {} for {} rows",
            b_bin.len(),
            expected_b_len,
            rows
        );
        return Ok((Atom::from_str(env, "error").unwrap(), error).encode(env));
    }

    let result = catch_unwind(|| {
        let a_ptr = a_bin.as_ptr();
        let b_ptr = b_bin.as_ptr();

        unsafe {
            let a_slice = std::slice::from_raw_parts(a_ptr as *const f64, rows * cols);
            let b_slice = std::slice::from_raw_parts(b_ptr as *const f64, rows);

            use faer::prelude::*;
            let a_mat = Mat::from_fn(rows, cols, |i, j| {
                *a_slice.get(i + j * rows).unwrap_or(&0.0)
            });
            let b_mat = Mat::from_fn(rows, 1, |i, _| *b_slice.get(i).unwrap_or(&0.0));

            let lu = a_mat.partial_piv_lu();
            let x = lu.solve(&b_mat);

            let x_data: Vec<f64> = x.col_iter().next().unwrap().iter().copied().collect();

            for &val in &x_data {
                if val.is_nan() || val.is_infinite() {
                    return Err("Matrix is singular or computation failed");
                }
            }

            let mut owned =
                OwnedBinary::new(x_data.len() * 8).ok_or("Failed to allocate result binary")?;
            owned
                .as_mut_slice()
                .copy_from_slice(bytemuck::cast_slice(&x_data));

            Ok::<rustler::Binary<'_>, &str>(owned.release(env))
        }
    });

    match result {
        Ok(Ok(bin)) => Ok((Atom::from_str(env, "ok").unwrap(), bin).encode(env)),
        Ok(Err(e)) => {
            let error = format!("Solver failed: {}", e);
            Ok((Atom::from_str(env, "error").unwrap(), error).encode(env))
        }
        Err(_) => {
            let error = "Matrix is singular or computation failed".to_string();
            Ok((Atom::from_str(env, "error").unwrap(), error).encode(env))
        }
    }
}

rustler::init!("nif");
