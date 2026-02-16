use faer::linalg::solvers::DenseSolveCore;
use faer::prelude::*;
use faer::{Side, Unbind};
use rand::distr::{Bernoulli, Uniform};
use rand::rngs::StdRng;
use rand::{rng, RngExt, SeedableRng};
use rand_distr::Normal;
use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, Term};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn mat_from_binary(rows: usize, cols: usize, data: &[u8]) -> Mat<f64> {
    let slice = bytemuck::cast_slice::<u8, f64>(data);
    Mat::from_fn(rows, cols, |i, j| slice[j * rows + i])
}

fn mat_to_binary<'a>(mat: faer::MatRef<'_, f64>, env: Env<'a>) -> Option<Binary<'a>> {
    let col_major: Vec<f64> = mat.col_iter().flat_map(|col| col.iter().copied()).collect();
    let mut owned = OwnedBinary::new(col_major.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(&col_major));
    Some(owned.release(env))
}

fn floats_to_binary<'a>(data: &[f64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
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
    let mat = mat_from_binary(rows, cols, data_bin.as_slice());
    Ok(ok_mat(env, mat.transpose()))
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
    let b_slice = bytemuck::cast_slice::<u8, f64>(b_bin.as_slice());
    let b_mat = Mat::from_fn(rows, 1, |i, _| b_slice[i]);

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
    let result = faer::Scale(scalar) * &mat;
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

    let l = lu.L();
    let u = lu.U();
    let p = lu.P();

    let pivot: Vec<u64> = p.arrays().0.iter().map(|&x| x.unbound() as u64).collect();

    let l_bin = mat_to_binary(l, env);
    let u_bin = mat_to_binary(u, env);
    let pivot_bin = floats_to_binary(bytemuck::cast_slice(&pivot), env);

    match (l_bin, u_bin, pivot_bin) {
        (Some(lb), Some(ub), Some(pb)) => {
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

    let q = qr.compute_thin_Q();
    let r = qr.R();

    let q_rows = q.nrows();
    let q_cols = q.ncols();
    let r_rows = r.nrows();
    let r_cols = r.ncols();

    let q_bin = mat_to_binary(q.as_ref(), env);
    let r_bin = mat_to_binary(r.as_ref(), env);

    match (q_bin, r_bin) {
        (Some(qb), Some(rb)) => {
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
    let svd = match mat.thin_svd() {
        Ok(s) => s,
        Err(_) => return Ok(err_string(env, "SVD computation failed")),
    };

    let u = svd.U();
    let s: Vec<f64> = svd.S().column_vector().iter().copied().collect();
    let v = svd.V();

    let u_rows = u.nrows();
    let u_cols = u.ncols();
    let v_rows = v.nrows();
    let v_cols = v.ncols();
    let s_len = s.len();

    let u_bin = mat_to_binary(u, env);
    let s_bin = floats_to_binary(&s, env);
    let v_bin = mat_to_binary(v, env);

    match (u_bin, s_bin, v_bin) {
        (Some(ub), Some(sb), Some(vb)) => Ok((
            atom_ok(env),
            ((u_rows, u_cols, ub), (s_len, sb), (v_rows, v_cols, vb)),
        )
            .encode(env)),
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
    let eigenvalues = match mat.self_adjoint_eigenvalues(Side::Lower) {
        Ok(e) => e,
        Err(_) => return Ok(err_string(env, "Eigenvalue computation failed")),
    };
    match floats_to_binary(&eigenvalues, env) {
        Some(bin) => Ok((atom_ok(env), bin).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

// ---------------------------------------------------------------------------
// Random matrix generation
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn random_uniform<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    min: f64,
    max: f64,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Uniform::new(min, max) {
        Ok(d) => d,
        Err(_) => return Ok(err_string(env, "Invalid uniform distribution parameters")),
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..rows * cols).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn random_uniform_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    min: f64,
    max: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Uniform::new(min, max) {
        Ok(d) => d,
        Err(_) => return Ok(err_string(env, "Invalid uniform distribution parameters")),
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..rows * cols).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn random_normal<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    mean: f64,
    std_dev: f64,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Normal::new(mean, std_dev) {
        Ok(d) => d,
        Err(_) => return Ok(err_string(env, "Invalid normal distribution parameters")),
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..rows * cols).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn random_normal_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    mean: f64,
    std_dev: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Normal::new(mean, std_dev) {
        Ok(d) => d,
        Err(_) => return Ok(err_string(env, "Invalid normal distribution parameters")),
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..rows * cols).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn random_bernoulli<'a>(env: Env<'a>, rows: usize, cols: usize, p: f64) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Bernoulli::new(p) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_string(
                env,
                "Invalid bernoulli probability (must be in [0, 1])",
            ))
        }
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..rows * cols)
        .map(|_| if rng.sample(dist) { 1.0 } else { 0.0 })
        .collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn random_bernoulli_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    p: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }
    let dist = match Bernoulli::new(p) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_string(
                env,
                "Invalid bernoulli probability (must be in [0, 1])",
            ))
        }
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..rows * cols)
        .map(|_| if rng.sample(dist) { 1.0 } else { 0.0 })
        .collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((atom_ok(env), (rows, cols, bin)).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

rustler::init!("nif");
