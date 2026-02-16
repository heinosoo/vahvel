use faer::linalg::solvers::DenseSolveCore;
use faer::prelude::*;
use faer::{sparse, Side, Unbind};
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

// ---------------------------------------------------------------------------
// Sparse matrix operations
// ---------------------------------------------------------------------------

fn ints_to_binary<'a>(data: &[i64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
    Some(owned.release(env))
}

fn sparse_col_mat_to_csc(
    mat: &sparse::SparseColMat<usize, f64>,
) -> (usize, Vec<i64>, Vec<i64>, Vec<f64>) {
    let symbolic = mat.symbolic();
    let numeric = mat.val();

    let nnz = symbolic.compute_nnz();
    let ncols = symbolic.ncols();

    let mut col_ptr: Vec<i64> = Vec::with_capacity(ncols + 1);
    let mut row_indices: Vec<i64> = Vec::with_capacity(nnz);
    let mut values: Vec<f64> = Vec::with_capacity(nnz);

    let row_idx_slice = symbolic.row_idx();
    for col in 0..ncols {
        col_ptr.push(row_indices.len() as i64);
        let col_range = symbolic.col_range(col);
        for idx in col_range {
            let row = row_idx_slice[idx] as i64;
            let val = numeric[idx];
            row_indices.push(row);
            values.push(val);
        }
    }
    col_ptr.push(row_indices.len() as i64);

    (nnz, col_ptr, row_indices, values)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sparse_from_triplets<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    row_indices_bin: Binary<'a>,
    col_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }

    let row_indices = bytemuck::cast_slice::<u8, i64>(row_indices_bin.as_slice());
    let col_indices = bytemuck::cast_slice::<u8, i64>(col_indices_bin.as_slice());
    let values = bytemuck::cast_slice::<u8, f64>(values_bin.as_slice());

    if row_indices.len() != col_indices.len() || row_indices.len() != values.len() {
        return Ok(err_string(env, "Triplet arrays must have equal length"));
    }

    if row_indices.is_empty() {
        return Ok(err_string(env, "Triplet list cannot be empty"));
    }

    let triplets: Vec<sparse::Triplet<usize, usize, f64>> = row_indices
        .iter()
        .zip(col_indices.iter())
        .zip(values.iter())
        .filter_map(|((&r, &c), &v)| {
            if r < 0 || c < 0 || (r as usize) >= rows || (c as usize) >= cols {
                None
            } else {
                Some(sparse::Triplet::new(r as usize, c as usize, v))
            }
        })
        .collect();

    if triplets.is_empty() {
        return Ok(err_string(env, "No valid triplets after index validation"));
    }

    let result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(rows, cols, &triplets);

    let sparse_mat = match result {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_string(
                env,
                &format!("Failed to create sparse matrix: {:?}", e),
            ))
        }
    };

    let (nnz, col_ptr, row_idx, vals) = sparse_col_mat_to_csc(&sparse_mat);

    let col_ptr_bin = ints_to_binary(&col_ptr, env);
    let row_idx_bin = ints_to_binary(&row_idx, env);
    let vals_bin = floats_to_binary(&vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((atom_ok(env), (nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sparse_to_dense<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }

    let col_ptr = bytemuck::cast_slice::<u8, i64>(col_ptr_bin.as_slice());
    let row_indices = bytemuck::cast_slice::<u8, i64>(row_indices_bin.as_slice());
    let values = bytemuck::cast_slice::<u8, f64>(values_bin.as_slice());

    if col_ptr.len() != cols + 1 {
        return Ok(err_string(env, "col_ptr length must be cols + 1"));
    }

    if row_indices.len() != nnz || values.len() != nnz {
        return Ok(err_string(
            env,
            "row_indices and values length must equal nnz",
        ));
    }

    let mut dense: Vec<f64> = vec![0.0; rows * cols];

    for col in 0..cols {
        let start = col_ptr[col] as usize;
        let end = col_ptr[col + 1] as usize;
        for idx in start..end {
            let row = row_indices[idx] as usize;
            if row >= rows {
                return Ok(err_string(env, "Row index out of bounds"));
            }
            dense[col * rows + row] = values[idx];
        }
    }

    match floats_to_binary(&dense, env) {
        Some(bin) => Ok((atom_ok(env), bin).encode(env)),
        None => Ok(err_string(env, "Failed to allocate result binary")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sparse_from_dense<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if let Err(msg) = validate_binary_len(data_bin.as_slice(), rows, cols) {
        return Ok(err_string(env, &msg));
    }

    let data = bytemuck::cast_slice::<u8, f64>(data_bin.as_slice());

    let mut triplets: Vec<sparse::Triplet<usize, usize, f64>> = Vec::new();
    for col in 0..cols {
        for row in 0..rows {
            let val = data[col * rows + row];
            if val != 0.0 {
                triplets.push(sparse::Triplet::new(row, col, val));
            }
        }
    }

    if triplets.is_empty() {
        let col_ptr = vec![0i64; cols + 1];
        let col_ptr_bin = ints_to_binary(&col_ptr, env);
        let empty_vals = floats_to_binary(&[], env);
        let empty_rows = ints_to_binary(&[], env);

        match (col_ptr_bin, empty_rows, empty_vals) {
            (Some(cp), Some(ri), Some(v)) => {
                return Ok((atom_ok(env), (0usize, cp, ri, v)).encode(env));
            }
            _ => return Ok(err_string(env, "Failed to allocate result binaries")),
        }
    }

    let result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(rows, cols, &triplets);

    let sparse_mat = match result {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_string(
                env,
                &format!("Failed to create sparse matrix: {:?}", e),
            ))
        }
    };

    let (nnz, col_ptr, row_idx, vals) = sparse_col_mat_to_csc(&sparse_mat);

    let col_ptr_bin = ints_to_binary(&col_ptr, env);
    let row_idx_bin = ints_to_binary(&row_idx, env);
    let vals_bin = floats_to_binary(&vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((atom_ok(env), (nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sparse_transpose<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if rows == 0 || cols == 0 {
        return Ok(err_string(env, "Dimensions must be positive"));
    }

    let col_ptr = bytemuck::cast_slice::<u8, i64>(col_ptr_bin.as_slice());
    let row_indices = bytemuck::cast_slice::<u8, i64>(row_indices_bin.as_slice());
    let values = bytemuck::cast_slice::<u8, f64>(values_bin.as_slice());

    if col_ptr.len() != cols + 1 {
        return Ok(err_string(env, "col_ptr length must be cols + 1"));
    }

    let mut triplets: Vec<sparse::Triplet<usize, usize, f64>> = Vec::with_capacity(nnz);
    for col in 0..cols {
        let start = col_ptr[col] as usize;
        let end = col_ptr[col + 1] as usize;
        for idx in start..end {
            let row = row_indices[idx] as usize;
            let val = values[idx];
            triplets.push(sparse::Triplet::new(col, row, val));
        }
    }

    let result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(cols, rows, &triplets);

    let sparse_mat = match result {
        Ok(m) => m,
        Err(e) => return Ok(err_string(env, &format!("Failed to transpose: {:?}", e))),
    };

    let (new_nnz, new_col_ptr, new_row_idx, new_vals) = sparse_col_mat_to_csc(&sparse_mat);

    let col_ptr_bin = ints_to_binary(&new_col_ptr, env);
    let row_idx_bin = ints_to_binary(&new_row_idx, env);
    let vals_bin = floats_to_binary(&new_vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => {
            Ok((atom_ok(env), (cols, rows, new_nnz, cp, ri, v)).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn sparse_multiply_dense<'a>(
    env: Env<'a>,
    sp_rows: usize,
    sp_cols: usize,
    sp_nnz: usize,
    sp_col_ptr_bin: Binary<'a>,
    sp_row_indices_bin: Binary<'a>,
    sp_values_bin: Binary<'a>,
    d_rows: usize,
    d_cols: usize,
    d_data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if sp_cols != d_rows {
        return Ok(err_string(env, "Inner dimensions do not match"));
    }

    if let Err(msg) = validate_binary_len(d_data_bin.as_slice(), d_rows, d_cols) {
        return Ok(err_string(env, &msg));
    }

    let sp_col_ptr = bytemuck::cast_slice::<u8, i64>(sp_col_ptr_bin.as_slice());
    let sp_row_indices = bytemuck::cast_slice::<u8, i64>(sp_row_indices_bin.as_slice());
    let sp_values = bytemuck::cast_slice::<u8, f64>(sp_values_bin.as_slice());
    let d_data = bytemuck::cast_slice::<u8, f64>(d_data_bin.as_slice());

    if sp_col_ptr.len() != sp_cols + 1 {
        return Ok(err_string(env, "Sparse col_ptr length mismatch"));
    }

    let mut triplets: Vec<sparse::Triplet<usize, usize, f64>> = Vec::with_capacity(sp_nnz);
    for col in 0..sp_cols {
        let start = sp_col_ptr[col] as usize;
        let end = sp_col_ptr[col + 1] as usize;
        for idx in start..end {
            let row = sp_row_indices[idx] as usize;
            let val = sp_values[idx];
            triplets.push(sparse::Triplet::new(row, col, val));
        }
    }

    let sparse_result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(sp_rows, sp_cols, &triplets);

    let sparse_mat = match sparse_result {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_string(
                env,
                &format!("Failed to create sparse matrix: {:?}", e),
            ))
        }
    };

    let dense_mat = mat_from_binary(d_rows, d_cols, bytemuck::cast_slice(d_data));

    let result = &sparse_mat * &dense_mat;

    Ok(ok_mat(env, result.as_ref()))
}

fn csc_to_sparse_col_mat(
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr: &[i64],
    row_indices: &[i64],
    values: &[f64],
) -> Result<sparse::SparseColMat<usize, f64>, String> {
    let mut triplets: Vec<sparse::Triplet<usize, usize, f64>> = Vec::with_capacity(nnz);
    for col in 0..cols {
        let start = col_ptr[col] as usize;
        let end = col_ptr[col + 1] as usize;
        for idx in start..end {
            let row = row_indices[idx] as usize;
            let val = values[idx];
            triplets.push(sparse::Triplet::new(row, col, val));
        }
    }

    sparse::SparseColMat::try_new_from_triplets(rows, cols, &triplets)
        .map_err(|e| format!("Failed to create sparse matrix: {:?}", e))
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn sparse_multiply<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_cols != b_rows {
        return Ok(err_string(
            env,
            "Inner dimensions do not match for sparse multiply",
        ));
    }

    let a_col_ptr = bytemuck::cast_slice::<u8, i64>(a_col_ptr_bin.as_slice());
    let a_row_indices = bytemuck::cast_slice::<u8, i64>(a_row_indices_bin.as_slice());
    let a_values = bytemuck::cast_slice::<u8, f64>(a_values_bin.as_slice());

    let b_col_ptr = bytemuck::cast_slice::<u8, i64>(b_col_ptr_bin.as_slice());
    let b_row_indices = bytemuck::cast_slice::<u8, i64>(b_row_indices_bin.as_slice());
    let b_values = bytemuck::cast_slice::<u8, f64>(b_values_bin.as_slice());

    let a_mat =
        match csc_to_sparse_col_mat(a_rows, a_cols, a_nnz, a_col_ptr, a_row_indices, a_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let b_mat =
        match csc_to_sparse_col_mat(b_rows, b_cols, b_nnz, b_col_ptr, b_row_indices, b_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let result = &a_mat * &b_mat;

    let (nnz, col_ptr, row_idx, vals) = sparse_col_mat_to_csc(&result);

    let col_ptr_bin = ints_to_binary(&col_ptr, env);
    let row_idx_bin = ints_to_binary(&row_idx, env);
    let vals_bin = floats_to_binary(&vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => {
            Ok((atom_ok(env), (a_rows, b_cols, nnz, cp, ri, v)).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn sparse_add<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_rows != b_rows || a_cols != b_cols {
        return Ok(err_string(env, "Dimensions must match for sparse addition"));
    }

    let a_col_ptr = bytemuck::cast_slice::<u8, i64>(a_col_ptr_bin.as_slice());
    let a_row_indices = bytemuck::cast_slice::<u8, i64>(a_row_indices_bin.as_slice());
    let a_values = bytemuck::cast_slice::<u8, f64>(a_values_bin.as_slice());

    let b_col_ptr = bytemuck::cast_slice::<u8, i64>(b_col_ptr_bin.as_slice());
    let b_row_indices = bytemuck::cast_slice::<u8, i64>(b_row_indices_bin.as_slice());
    let b_values = bytemuck::cast_slice::<u8, f64>(b_values_bin.as_slice());

    let a_mat =
        match csc_to_sparse_col_mat(a_rows, a_cols, a_nnz, a_col_ptr, a_row_indices, a_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let b_mat =
        match csc_to_sparse_col_mat(b_rows, b_cols, b_nnz, b_col_ptr, b_row_indices, b_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let a_dense = a_mat.to_dense();
    let b_dense = b_mat.to_dense();
    let result = &a_dense + &b_dense;

    let triplets: Vec<sparse::Triplet<usize, usize, f64>> = result
        .col_iter()
        .enumerate()
        .flat_map(|(col, col_vec)| {
            col_vec.iter().enumerate().filter_map(move |(row, &val)| {
                if val != 0.0 {
                    Some(sparse::Triplet::new(row, col, val))
                } else {
                    None
                }
            })
        })
        .collect();

    if triplets.is_empty() {
        let col_ptr = vec![0i64; a_cols + 1];
        let col_ptr_bin = ints_to_binary(&col_ptr, env);
        let empty_vals = floats_to_binary(&[], env);
        let empty_rows = ints_to_binary(&[], env);

        match (col_ptr_bin, empty_rows, empty_vals) {
            (Some(cp), Some(ri), Some(v)) => {
                return Ok((atom_ok(env), (a_rows, a_cols, 0usize, cp, ri, v)).encode(env));
            }
            _ => return Ok(err_string(env, "Failed to allocate result binaries")),
        }
    }

    let sparse_result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(a_rows, a_cols, &triplets);

    let sparse_mat = match sparse_result {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_string(
                env,
                &format!("Failed to create sparse matrix: {:?}", e),
            ))
        }
    };

    let (nnz, col_ptr, row_idx, vals) = sparse_col_mat_to_csc(&sparse_mat);

    let col_ptr_bin = ints_to_binary(&col_ptr, env);
    let row_idx_bin = ints_to_binary(&row_idx, env);
    let vals_bin = floats_to_binary(&vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => {
            Ok((atom_ok(env), (a_rows, a_cols, nnz, cp, ri, v)).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn sparse_subtract<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_rows != b_rows || a_cols != b_cols {
        return Ok(err_string(
            env,
            "Dimensions must match for sparse subtraction",
        ));
    }

    let a_col_ptr = bytemuck::cast_slice::<u8, i64>(a_col_ptr_bin.as_slice());
    let a_row_indices = bytemuck::cast_slice::<u8, i64>(a_row_indices_bin.as_slice());
    let a_values = bytemuck::cast_slice::<u8, f64>(a_values_bin.as_slice());

    let b_col_ptr = bytemuck::cast_slice::<u8, i64>(b_col_ptr_bin.as_slice());
    let b_row_indices = bytemuck::cast_slice::<u8, i64>(b_row_indices_bin.as_slice());
    let b_values = bytemuck::cast_slice::<u8, f64>(b_values_bin.as_slice());

    let a_mat =
        match csc_to_sparse_col_mat(a_rows, a_cols, a_nnz, a_col_ptr, a_row_indices, a_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let b_mat =
        match csc_to_sparse_col_mat(b_rows, b_cols, b_nnz, b_col_ptr, b_row_indices, b_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_string(env, &e)),
        };

    let a_dense = a_mat.to_dense();
    let b_dense = b_mat.to_dense();
    let result = &a_dense - &b_dense;

    let triplets: Vec<sparse::Triplet<usize, usize, f64>> = result
        .col_iter()
        .enumerate()
        .flat_map(|(col, col_vec)| {
            col_vec.iter().enumerate().filter_map(move |(row, &val)| {
                if val != 0.0 {
                    Some(sparse::Triplet::new(row, col, val))
                } else {
                    None
                }
            })
        })
        .collect();

    if triplets.is_empty() {
        let col_ptr = vec![0i64; a_cols + 1];
        let col_ptr_bin = ints_to_binary(&col_ptr, env);
        let empty_vals = floats_to_binary(&[], env);
        let empty_rows = ints_to_binary(&[], env);

        match (col_ptr_bin, empty_rows, empty_vals) {
            (Some(cp), Some(ri), Some(v)) => {
                return Ok((atom_ok(env), (a_rows, a_cols, 0usize, cp, ri, v)).encode(env));
            }
            _ => return Ok(err_string(env, "Failed to allocate result binaries")),
        }
    }

    let sparse_result: Result<sparse::SparseColMat<usize, f64>, _> =
        sparse::SparseColMat::try_new_from_triplets(a_rows, a_cols, &triplets);

    let sparse_mat = match sparse_result {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_string(
                env,
                &format!("Failed to create sparse matrix: {:?}", e),
            ))
        }
    };

    let (nnz, col_ptr, row_idx, vals) = sparse_col_mat_to_csc(&sparse_mat);

    let col_ptr_bin = ints_to_binary(&col_ptr, env);
    let row_idx_bin = ints_to_binary(&row_idx, env);
    let vals_bin = floats_to_binary(&vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => {
            Ok((atom_ok(env), (a_rows, a_cols, nnz, cp, ri, v)).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn sparse_scale<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
    scalar: f64,
) -> NifResult<Term<'a>> {
    let col_ptr = bytemuck::cast_slice::<u8, i64>(col_ptr_bin.as_slice());
    let row_indices = bytemuck::cast_slice::<u8, i64>(row_indices_bin.as_slice());
    let values = bytemuck::cast_slice::<u8, f64>(values_bin.as_slice());

    let scaled_values: Vec<f64> = values.iter().map(|&v| v * scalar).collect();

    let vals_bin = floats_to_binary(&scaled_values, env);
    let col_ptr_bin = ints_to_binary(col_ptr, env);
    let row_idx_bin = ints_to_binary(row_indices, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => {
            Ok((atom_ok(env), (rows, cols, nnz, cp, ri, v)).encode(env))
        }
        _ => Ok(err_string(env, "Failed to allocate result binaries")),
    }
}

rustler::init!("nif");
