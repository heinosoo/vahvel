use crate::utils::{
    binary_to_cow_f64, err_term, has_nan_or_inf, ok, ok_float, ok_mat, WaffleError,
};
use faer::linalg::solvers::DenseSolveCore;
use faer::prelude::*;
use faer::{MatRef, Scale, Side};
use rustler::{Binary, Encoder, Env, NifResult, Term};

#[rustler::nif(schedule = "DirtyCpu")]
pub fn transpose<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, rows, cols);
    Ok(ok_mat(env, mat.transpose()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn solve_linear_system<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let a_slice = binary_to_cow_f64(a_bin.as_slice());
    if a_slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("A length mismatch".to_string()),
        ));
    }
    let a_mat = MatRef::from_column_major_slice(&a_slice, rows, cols);

    let b_slice = binary_to_cow_f64(b_bin.as_slice());
    if b_slice.len() != rows {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("B length mismatch".to_string()),
        ));
    }
    let b_mat = MatRef::from_column_major_slice(&b_slice, rows, 1);

    let lu = a_mat.partial_piv_lu();
    let x = lu.solve(b_mat);

    if has_nan_or_inf(x.as_ref()) {
        return Ok(err_term(
            env,
            &WaffleError::ComputationFailed("Matrix is singular or computation failed".to_string()),
        ));
    }

    Ok(ok_mat(env, x.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_add<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let a_slice = binary_to_cow_f64(a_bin.as_slice());
    if a_slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("A length mismatch".to_string()),
        ));
    }
    let a = MatRef::from_column_major_slice(&a_slice, rows, cols);

    let b_slice = binary_to_cow_f64(b_bin.as_slice());
    if b_slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("B length mismatch".to_string()),
        ));
    }
    let b = MatRef::from_column_major_slice(&b_slice, rows, cols);

    let result = a + b;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_subtract<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let a_slice = binary_to_cow_f64(a_bin.as_slice());
    if a_slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("A length mismatch".to_string()),
        ));
    }
    let a = MatRef::from_column_major_slice(&a_slice, rows, cols);

    let b_slice = binary_to_cow_f64(b_bin.as_slice());
    if b_slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("B length mismatch".to_string()),
        ));
    }
    let b = MatRef::from_column_major_slice(&b_slice, rows, cols);

    let result = a - b;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_scale<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
    scalar: f64,
) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, rows, cols);

    let result = Scale(scalar) * mat;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_multiply<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let a_slice = binary_to_cow_f64(a_bin.as_slice());
    if a_slice.len() != a_rows * a_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("A length mismatch".to_string()),
        ));
    }
    let a = MatRef::from_column_major_slice(&a_slice, a_rows, a_cols);

    let b_slice = binary_to_cow_f64(b_bin.as_slice());
    if b_slice.len() != b_rows * b_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("B length mismatch".to_string()),
        ));
    }
    let b = MatRef::from_column_major_slice(&b_slice, b_rows, b_cols);

    let result = a * b;
    Ok(ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_determinant<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != n * n {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, n, n);

    let det = mat.determinant();
    Ok(ok_float(env, det))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_inverse<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != n * n {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, n, n);

    let lu = mat.partial_piv_lu();
    let inv = lu.inverse();

    if has_nan_or_inf(inv.as_ref()) {
        return Ok(err_term(
            env,
            &WaffleError::ComputationFailed("Matrix is singular".to_string()),
        ));
    }

    Ok(ok_mat(env, inv.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_lu<'a>(env: Env<'a>, n: usize, data_bin: Binary<'a>) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != n * n {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, n, n);

    let lu = mat.partial_piv_lu();

    let l = lu.L();
    let u = lu.U();
    let p = lu.P();

    let pivot: Vec<u64> = p.arrays().0.iter().map(|&x| x as u64).collect();
    let pivot_f64: &[f64] = bytemuck::cast_slice(&pivot);

    let l_bin = crate::utils::mat_to_binary(l, env);
    let u_bin = crate::utils::mat_to_binary(u, env);
    let pivot_bin = crate::utils::floats_to_binary(pivot_f64, env);

    match (l_bin, u_bin, pivot_bin) {
        (Some(lb), Some(ub), Some(pb)) => Ok((ok(), ((n, n, lb), (n, n, ub), (n, pb))).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_qr<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, rows, cols);

    let qr = mat.qr();

    let q_mat = qr.compute_thin_Q();
    let r_mat = qr.R();

    let q_rows = q_mat.nrows();
    let q_cols = q_mat.ncols();
    let r_rows = r_mat.nrows();
    let r_cols = r_mat.ncols();

    let q_bin = crate::utils::mat_to_binary(q_mat.as_ref(), env);
    let r_bin = crate::utils::mat_to_binary(r_mat.as_ref(), env);

    match (q_bin, r_bin) {
        (Some(qb), Some(rb)) => {
            Ok((ok(), ((q_rows, q_cols, qb), (r_rows, r_cols, rb))).encode(env))
        }
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_svd<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != rows * cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, rows, cols);

    let svd = match mat.thin_svd() {
        Ok(s) => s,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed("SVD computation failed".to_string()),
            ))
        }
    };

    let u = svd.U();
    let s_diag = svd.S();
    let v = svd.V();

    let u_rows = u.nrows();
    let u_cols = u.ncols();
    let v_rows = v.nrows();
    let v_cols = v.ncols();

    let s_len = s_diag.column_vector().nrows();
    let s_vec_data: Vec<f64> = s_diag.column_vector().iter().copied().collect();

    let u_bin = crate::utils::mat_to_binary(u, env);
    let s_bin = crate::utils::floats_to_binary(&s_vec_data, env);
    let v_bin = crate::utils::mat_to_binary(v, env);

    match (u_bin, s_bin, v_bin) {
        (Some(ub), Some(sb), Some(vb)) => Ok((
            ok(),
            ((u_rows, u_cols, ub), (s_len, sb), (v_rows, v_cols, vb)),
        )
            .encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn matrix_symmetric_eigenvalues<'a>(
    env: Env<'a>,
    n: usize,
    data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let slice = binary_to_cow_f64(data_bin.as_slice());
    if slice.len() != n * n {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Binary length mismatch".to_string()),
        ));
    }
    let mat = MatRef::from_column_major_slice(&slice, n, n);

    let eigenvalues = match mat.self_adjoint_eigenvalues(Side::Lower) {
        Ok(e) => e,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed("Eigenvalue computation failed".to_string()),
            ))
        }
    };

    match crate::utils::floats_to_binary(&eigenvalues, env) {
        Some(bin) => Ok((ok(), bin).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}
