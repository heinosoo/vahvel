use faer::linalg::solvers::SolverCore;
use faer::prelude::*;
use faer::Side;
use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, Term};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn mat_from_binary(rows: usize, cols: usize, data: &[u8]) -> Mat<f64> {
    // Safety: Handle unaligned data by reading 8-byte chunks and parsing as LE f64
    // Faer uses column-major storage by default.
    // We avoid intermediate Vec allocation by parsing on demand.
    Mat::from_fn(rows, cols, |i, j| {
        let idx = j * rows + i;
        let start = idx * 8;
        // Slice length is validated by caller, so unwrapping is safe (or panics if logic is wrong)
        let bytes: [u8; 8] = data[start..start + 8].try_into().unwrap_or_default();
        f64::from_le_bytes(bytes)
    })
}

fn mat_to_binary<'a>(mat: faer::MatRef<'_, f64>, env: Env<'a>) -> Option<Binary<'a>> {
    let len = mat.nrows() * mat.ncols();
    let mut owned = OwnedBinary::new(len * 8)?;
    {
        let slice = owned.as_mut_slice();
        // Col-major iteration
        for (idx, &val) in mat.col_iter().flat_map(|col| col.iter()).enumerate() {
            let bytes = val.to_le_bytes();
            let start = idx * 8;
            slice[start..start + 8].copy_from_slice(&bytes);
        }
    }
    Some(owned.release(env))
}

fn floats_to_binary<'a>(data: &[f64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    {
        let slice = owned.as_mut_slice();
        for (idx, &val) in data.iter().enumerate() {
            let bytes = val.to_le_bytes();
            let start = idx * 8;
            slice[start..start + 8].copy_from_slice(&bytes);
        }
    }
    Some(owned.release(env))
}

fn u64s_to_binary<'a>(data: &[u64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    {
        let slice = owned.as_mut_slice();
        for (idx, &val) in data.iter().enumerate() {
            let bytes = val.to_le_bytes();
            let start = idx * 8;
            slice[start..start + 8].copy_from_slice(&bytes);
        }
    }
    Some(owned.release(env))
}

fn ok_mat<'a>(env: Env<'a>, mat: faer::MatRef<'_, f64>) -> Term<'a> {
    match mat_to_binary(mat, env) {
        Some(bin) => (atom_ok(env), bin).encode(env),
        None => err_string(env, "Failed to allocate result binary"),
    }
}

fn ok_float<'a>(env: Env<'a>, val: f64) -> Term<'a> {
    (atom_ok(env), val).encode(env)
}

fn err_string<'a>(env: Env<'a>, msg: &str) -> Term<'a> {
    (atom_error(env), msg.to_string()).encode(env)
}

fn atom_ok(env: Env) -> Atom {
    Atom::from_str(env, "ok").unwrap()
}

fn atom_error(env: Env) -> Atom {
    Atom::from_str(env, "error").unwrap()
}

fn validate_binary_len(bin: &[u8], rows: usize, cols: usize) -> Result<(), String> {
    let expected = rows * cols * 8;
    if bin.len() != expected {
        Err(format!(
            "Binary length mismatch: expected {} bytes for {}x{} matrix, got {}",
            expected,
            rows,
            cols,
            bin.len()
        ))
    } else {
        Ok(())
    }
}

fn has_nan_or_inf(mat: faer::MatRef<'_, f64>) -> bool {
    mat.col_iter()
        .any(|col| col.iter().any(|&v| v.is_nan() || v.is_infinite()))
}

// ---------------------------------------------------------------------------
// Macro for element-wise binary matrix ops (same dimensions)
// ---------------------------------------------------------------------------

macro_rules! binary_mat_op {
    ($name:ident, $op:tt) => {
        #[rustler::nif(schedule = "DirtyCpu")]
        fn $name<'a>(
            env: Env<'a>,
            rows: usize,
            cols: usize,
            a_bin: Binary<'a>,
            b_bin: Binary<'a>,
        ) -> NifResult<Term<'a>> {
            if let Err(msg) = validate_binary_len(a_bin.as_slice(), rows, cols) {
                return Ok(err_string(env, &msg));
            }
            if let Err(msg) = validate_binary_len(b_bin.as_slice(), rows, cols) {
                return Ok(err_string(env, &msg));
            }
            let a = mat_from_binary(rows, cols, a_bin.as_slice());
            let b = mat_from_binary(rows, cols, b_bin.as_slice());
            let result = &a $op &b;
            Ok(ok_mat(env, result.as_ref()))
        }
    };
}

binary_mat_op!(matrix_add, +);
binary_mat_op!(matrix_subtract, -);

// ---------------------------------------------------------------------------
// NIFs
// ---------------------------------------------------------------------------

#[rustler::nif]
fn nif_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn transpose<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }

    let input_bytes = data_bin.as_slice();
    // Pre-allocate output binary
    let len = rows * cols;
    let mut owned = match OwnedBinary::new(len * 8) {
        Some(o) => o,
        None => return Ok(err_string(env, "Failed to allocate result binary")),
    };

    let output_bytes = owned.as_mut_slice();

    // Manual transpose loop: B[c, r] = A[r, c]
    // A (input) is rows x cols
    // B (output) is cols x rows
    for c in 0..cols {
        // c is col index in A (row index in B)
        for r in 0..rows {
            // r is row index in A (col index in B)
            // Read A[r, c] from input (col-major: index = c * rows + r)
            let input_idx = (c * rows + r) * 8;

            // Write B[c, r] to output (col-major: index = r * cols + c)
            // (Note: B has `cols` rows, so stride is `cols`)
            let output_idx = (r * cols + c) * 8;

            output_bytes[output_idx..output_idx + 8]
                .copy_from_slice(&input_bytes[input_idx..input_idx + 8]);
        }
    }

    Ok((atom_ok(env), owned.release(env)).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn solve_linear_system<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(a_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }
    let expected_b_len = rows * 8;
    if b_bin.len() != expected_b_len {
        return Ok(err_string(
            env,
            &format!(
                "RHS binary length {} does not match expected {} for {} rows",
                b_bin.len(),
                expected_b_len,
                rows
            ),
        ));
    }

    let a_mat = mat_from_binary(rows, cols, a_bin.as_slice());

    // Manual copy for B vector, avoiding intermediate Vec
    let b_slice_bytes = b_bin.as_slice();
    let b_mat = Mat::from_fn(rows, 1, |i, _| {
        let start = i * 8;
        let bytes: [u8; 8] = b_slice_bytes[start..start + 8].try_into().unwrap_or_default();
        f64::from_le_bytes(bytes)
    });

    let lu = a_mat.partial_piv_lu();
    let x = lu.solve(&b_mat);

    if has_nan_or_inf(x.as_ref()) {
        return Ok(err_string(env, "Matrix is singular or computation failed"));
    }

    Ok(ok_mat(env, x.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_scale<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
    scalar: f64,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(rows, cols, data_bin.as_slice());
    let result = faer::scale(scalar) * &mat;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_multiply<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(a_bin.as_slice(), a_rows, a_cols) {
        return Ok(err_string(env, &msg));
    }
    if let Err(msg) = validate_binary_len(b_bin.as_slice(), b_rows, b_cols) {
        return Ok(err_string(env, &msg));
    }
    let a = mat_from_binary(a_rows, a_cols, a_bin.as_slice());
    let b = mat_from_binary(b_rows, b_cols, b_bin.as_slice());
    let result = &a * &b;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_determinant<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), n, n) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(n, n, data_bin.as_slice());
    let det = mat.determinant();
    Ok(ok_float(env, det))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_inverse<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), n, n) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(n, n, data_bin.as_slice());
    let lu = mat.partial_piv_lu();
    let inv = lu.inverse();

    if has_nan_or_inf(inv.as_ref()) {
        return Ok(err_string(env, "Matrix is singular"));
    }

    Ok(ok_mat(env, inv.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_lu<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), n, n) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(n, n, data_bin.as_slice());
    let lu = mat.partial_piv_lu();

    let l = lu.compute_l();
    let u = lu.compute_u();
    let (fwd, _inv) = lu.row_permutation().arrays();
    let pivot: Vec<u64> = fwd.iter().map(|&x| x as u64).collect();

    let l_bin = mat_to_binary(l.as_ref(), env);
    let u_bin = mat_to_binary(u.as_ref(), env);
    let pivot_bin = u64s_to_binary(&pivot, env);

    match (l_bin, u_bin, pivot_bin) {
        (Some(lb), Some(ub), Some(pb)) => {
            // Nested tuples: {ok, {{l_r, l_c, l_bin}, {u_r, u_c, u_bin}, {n, pivot_bin}}}
            Ok((atom_ok(env), ((n, n, lb), (n, n, ub), (n, pb))).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_qr<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(rows, cols, data_bin.as_slice());
    let qr = mat.qr();

    let q = qr.compute_thin_q();
    let r = qr.compute_thin_r();

    let q_rows = q.nrows();
    let q_cols = q.ncols();
    let r_rows = r.nrows();
    let r_cols = r.ncols();

    let q_bin = mat_to_binary(q.as_ref(), env);
    let r_bin = mat_to_binary(r.as_ref(), env);

    match (q_bin, r_bin) {
        (Some(qb), Some(rb)) => {
            // {ok, {{q_r, q_c, q_bin}, {r_r, r_c, r_bin}}}
            Ok((atom_ok(env), ((q_rows, q_cols, qb), (r_rows, r_cols, rb))).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_svd<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(rows, cols, data_bin.as_slice());
    let svd = mat.thin_svd();

    let u = svd.u();
    let s: Vec<f64> = svd.s_diagonal().iter().copied().collect();
    let v = svd.v();

    let u_rows = u.nrows();
    let u_cols = u.ncols();
    let v_rows = v.nrows();
    let v_cols = v.ncols();
    let s_len = s.len();

    let u_bin = mat_to_binary(u, env);
    let s_bin = floats_to_binary(&s, env);
    let v_bin = mat_to_binary(v, env);

    match (u_bin, s_bin, v_bin) {
        (Some(ub), Some(sb), Some(vb)) => {
            // {ok, {{u_r, u_c, u_bin}, {s_len, s_bin}, {v_r, v_c, v_bin}}}
            Ok((
                atom_ok(env),
                ((u_rows, u_cols, ub), (s_len, sb), (v_rows, v_cols, vb)),
            )
                .encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn matrix_symmetric_eigenvalues<'a>(
    env: Env<'a>,
    n: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), n, n) {
        return Ok(err_string(env, &msg));
    }
    let mat = mat_from_binary(n, n, data_bin.as_slice());
    let eigenvalues = mat.selfadjoint_eigenvalues(Side::Lower);
    match floats_to_binary(&eigenvalues, env) {
        Some(bin) => Ok((atom_ok(env), bin).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

rustler::init!("nif");
