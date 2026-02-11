use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, Term};

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

    // Safe conversion from binary to f64 slices using bytemuck
    let a_slice = bytemuck::cast_slice::<u8, f64>(a_bin.as_slice());
    let b_slice = bytemuck::cast_slice::<u8, f64>(b_bin.as_slice());

    // Create faer matrices from slices (column-major layout)
    use faer::prelude::*;
    let a_mat = Mat::from_fn(rows, cols, |i, j| a_slice[i + j * rows]);
    let b_mat = Mat::from_fn(rows, 1, |i, _| b_slice[i]);

    // Solve the linear system
    let lu = a_mat.partial_piv_lu();
    let x = lu.solve(&b_mat);

    // Extract solution and validate
    let x_data: Vec<f64> = x.col_iter().next().unwrap().iter().copied().collect();

    for &val in &x_data {
        if val.is_nan() || val.is_infinite() {
            let error = "Matrix is singular or computation failed".to_string();
            return Ok((Atom::from_str(env, "error").unwrap(), error).encode(env));
        }
    }

    // Allocate and copy result
    match OwnedBinary::new(x_data.len() * 8) {
        Some(mut owned) => {
            owned
                .as_mut_slice()
                .copy_from_slice(bytemuck::cast_slice(&x_data));
            Ok((Atom::from_str(env, "ok").unwrap(), owned.release(env)).encode(env))
        }
        None => {
            let error = "Failed to allocate result binary".to_string();
            Ok((Atom::from_str(env, "error").unwrap(), error).encode(env))
        }
    }
}

#[rustler::nif]
fn transpose<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let expected_len = rows * cols * 8;
    if data_bin.len() != expected_len {
        let error = format!(
            "Binary length mismatch: expected {} bytes for {}x{} matrix, got {}",
            expected_len,
            rows,
            cols,
            data_bin.len()
        );
        return Ok((Atom::from_str(env, "error").unwrap(), error).encode(env));
    }

    // Safe conversion from binary to f64 slice using bytemuck
    let data_slice = bytemuck::cast_slice::<u8, f64>(data_bin.as_slice());

    // Create column-major faer matrix
    use faer::prelude::*;
    let mat = Mat::from_fn(rows, cols, |i, j| data_slice[j * rows + i]);

    // Transpose and extract in column-major order
    let transposed = mat.transpose();
    let col_major: Vec<f64> = transposed
        .as_ref()
        .col_iter()
        .flat_map(|col| col.iter().copied())
        .collect();

    // Allocate and copy result
    match OwnedBinary::new(col_major.len() * 8) {
        Some(mut owned) => {
            owned
                .as_mut_slice()
                .copy_from_slice(bytemuck::cast_slice(&col_major));
            Ok((Atom::from_str(env, "ok").unwrap(), owned.release(env)).encode(env))
        }
        None => {
            let error = "Failed to allocate output binary".to_string();
            Ok((Atom::from_str(env, "error").unwrap(), error).encode(env))
        }
    }
}

rustler::init!("nif");
