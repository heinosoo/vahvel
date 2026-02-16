use crate::utils::{
    binary_to_cow_f64, binary_to_cow_u64, err_term, floats_to_binary, ok, u64s_to_binary,
    WaffleError,
};
use faer::sparse::{SparseColMat, SparseColMatRef, SymbolicSparseColMatRef, Triplet};
use faer::MatRef;
use rustler::{Binary, Encoder, Env, NifResult, Term};

fn make_sparse_mat<'a>(
    rows: usize,
    cols: usize,
    col_ptr: &'a [u64],
    row_indices: &'a [u64],
    values: &'a [f64],
) -> Result<SparseColMatRef<'a, u64, f64>, WaffleError> {
    if col_ptr.len() != cols + 1 {
        return Err(WaffleError::DimensionMismatch(format!(
            "col_ptr length {} mismatch for cols {}",
            col_ptr.len(),
            cols
        )));
    }
    let nnz = (col_ptr[cols] - col_ptr[0]) as usize;
    if row_indices.len() < nnz || values.len() < nnz {
        return Err(WaffleError::DimensionMismatch(format!(
            "indices/values length too small for nnz {}",
            nnz
        )));
    }

    let symbolic = SymbolicSparseColMatRef::new_checked(rows, cols, col_ptr, None, row_indices);

    Ok(SparseColMatRef::new(symbolic, values))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn sparse_from_triplets<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    row_indices_bin: Binary<'a>,
    col_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let row_indices = binary_to_cow_u64(row_indices_bin.as_slice());
    let col_indices = binary_to_cow_u64(col_indices_bin.as_slice());
    let values = binary_to_cow_f64(values_bin.as_slice());

    if row_indices.len() != col_indices.len() || row_indices.len() != values.len() {
        return Ok(err_term(
            env,
            &WaffleError::InvalidInput("Triplet arrays must have equal length".to_string()),
        ));
    }

    let triplets: Vec<Triplet<u64, u64, f64>> = row_indices
        .iter()
        .zip(col_indices.iter())
        .zip(values.iter())
        .map(|((&r, &c), &v)| Triplet::new(r, c, v))
        .collect();

    let mat = match SparseColMat::try_new_from_triplets(rows, cols, &triplets) {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed(format!("Failed to create sparse matrix: {:?}", e)),
            ))
        }
    };

    let symbolic = mat.symbolic();
    let col_ptr = symbolic.col_ptr();
    let row_idx = symbolic.row_idx();
    let vals = mat.val();
    let nnz = symbolic.compute_nnz();

    let col_ptr_bin = u64s_to_binary(col_ptr, env);
    let row_idx_bin = u64s_to_binary(row_idx, env);
    let vals_bin = floats_to_binary(vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn sparse_to_dense<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    _nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let col_ptr = binary_to_cow_u64(col_ptr_bin.as_slice());
    let row_indices = binary_to_cow_u64(row_indices_bin.as_slice());
    let values = binary_to_cow_f64(values_bin.as_slice());

    let sparse_mat = match make_sparse_mat(rows, cols, &col_ptr, &row_indices, &values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dense = sparse_mat.to_dense();

    match crate::utils::mat_to_binary(dense.as_ref(), env) {
        Some(bin) => Ok((ok(), bin).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn sparse_from_dense<'a>(
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

    let mut triplets = Vec::new();
    for j in 0..cols {
        for i in 0..rows {
            let val = slice[j * rows + i];
            if val != 0.0 {
                triplets.push(Triplet::new(i as u64, j as u64, val));
            }
        }
    }

    let mat = match SparseColMat::try_new_from_triplets(rows, cols, &triplets) {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed(format!("Failed to create sparse matrix: {:?}", e)),
            ))
        }
    };

    let symbolic = mat.symbolic();
    let col_ptr = symbolic.col_ptr();
    let row_idx = symbolic.row_idx();
    let vals = mat.val();
    let nnz = symbolic.compute_nnz();

    let col_ptr_bin = u64s_to_binary(col_ptr, env);
    let row_idx_bin = u64s_to_binary(row_idx, env);
    let vals_bin = floats_to_binary(vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn sparse_transpose<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    _nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let col_ptr = binary_to_cow_u64(col_ptr_bin.as_slice());
    let row_indices = binary_to_cow_u64(row_indices_bin.as_slice());
    let values = binary_to_cow_f64(values_bin.as_slice());

    let sparse_mat = match make_sparse_mat(rows, cols, &col_ptr, &row_indices, &values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let transposed = sparse_mat.transpose();

    let csc = match transposed.to_col_major() {
        Ok(m) => m,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed(
                    "Failed to transpose (allocation error)".to_string(),
                ),
            ))
        }
    };

    let symbolic = csc.symbolic();
    let new_nnz = symbolic.compute_nnz();
    let new_col_ptr = symbolic.col_ptr();
    let new_row_idx = symbolic.row_idx();
    let new_vals = csc.val();

    let col_ptr_bin = u64s_to_binary(new_col_ptr, env);
    let row_idx_bin = u64s_to_binary(new_row_idx, env);
    let vals_bin = floats_to_binary(new_vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (cols, rows, new_nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn sparse_multiply_dense<'a>(
    env: Env<'a>,
    sp_rows: usize,
    sp_cols: usize,
    _sp_nnz: usize,
    sp_col_ptr_bin: Binary<'a>,
    sp_row_indices_bin: Binary<'a>,
    sp_values_bin: Binary<'a>,
    d_rows: usize,
    d_cols: usize,
    d_data_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if sp_cols != d_rows {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Inner dimensions do not match".to_string()),
        ));
    }

    let sp_col_ptr = binary_to_cow_u64(sp_col_ptr_bin.as_slice());
    let sp_row_indices = binary_to_cow_u64(sp_row_indices_bin.as_slice());
    let sp_values = binary_to_cow_f64(sp_values_bin.as_slice());

    let sparse_mat =
        match make_sparse_mat(sp_rows, sp_cols, &sp_col_ptr, &sp_row_indices, &sp_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_term(env, &e)),
        };

    let d_slice = binary_to_cow_f64(d_data_bin.as_slice());
    if d_slice.len() != d_rows * d_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Dense binary length mismatch".to_string()),
        ));
    }
    let d_mat = MatRef::from_column_major_slice(&d_slice, d_rows, d_cols);

    let result = sparse_mat * d_mat;

    Ok(crate::utils::ok_mat(env, result.as_ref()))
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn sparse_multiply<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    _a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    _b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_cols != b_rows {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Inner dimensions do not match".to_string()),
        ));
    }

    let a_col_ptr = binary_to_cow_u64(a_col_ptr_bin.as_slice());
    let a_row_indices = binary_to_cow_u64(a_row_indices_bin.as_slice());
    let a_values = binary_to_cow_f64(a_values_bin.as_slice());

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let b_col_ptr = binary_to_cow_u64(b_col_ptr_bin.as_slice());
    let b_row_indices = binary_to_cow_u64(b_row_indices_bin.as_slice());
    let b_values = binary_to_cow_f64(b_values_bin.as_slice());

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat * b_mat;

    let symbolic = result.symbolic();
    let nnz = symbolic.compute_nnz();
    let col_ptr = symbolic.col_ptr();
    let row_idx = symbolic.row_idx();
    let vals = result.val();

    let col_ptr_bin = u64s_to_binary(col_ptr, env);
    let row_idx_bin = u64s_to_binary(row_idx, env);
    let vals_bin = floats_to_binary(vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (a_rows, b_cols, nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn sparse_add<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    _a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    _b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_rows != b_rows || a_cols != b_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Dimensions mismatch".to_string()),
        ));
    }

    let a_col_ptr = binary_to_cow_u64(a_col_ptr_bin.as_slice());
    let a_row_indices = binary_to_cow_u64(a_row_indices_bin.as_slice());
    let a_values = binary_to_cow_f64(a_values_bin.as_slice());

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let b_col_ptr = binary_to_cow_u64(b_col_ptr_bin.as_slice());
    let b_row_indices = binary_to_cow_u64(b_row_indices_bin.as_slice());
    let b_values = binary_to_cow_f64(b_values_bin.as_slice());

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat + b_mat;

    let symbolic = result.symbolic();
    let nnz = symbolic.compute_nnz();
    let col_ptr = symbolic.col_ptr();
    let row_idx = symbolic.row_idx();
    let vals = result.val();

    let col_ptr_bin = u64s_to_binary(col_ptr, env);
    let row_idx_bin = u64s_to_binary(row_idx, env);
    let vals_bin = floats_to_binary(vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (a_rows, a_cols, nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn sparse_subtract<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    _a_nnz: usize,
    a_col_ptr_bin: Binary<'a>,
    a_row_indices_bin: Binary<'a>,
    a_values_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    _b_nnz: usize,
    b_col_ptr_bin: Binary<'a>,
    b_row_indices_bin: Binary<'a>,
    b_values_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    if a_rows != b_rows || a_cols != b_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Dimensions mismatch".to_string()),
        ));
    }

    let a_col_ptr = binary_to_cow_u64(a_col_ptr_bin.as_slice());
    let a_row_indices = binary_to_cow_u64(a_row_indices_bin.as_slice());
    let a_values = binary_to_cow_f64(a_values_bin.as_slice());

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let b_col_ptr = binary_to_cow_u64(b_col_ptr_bin.as_slice());
    let b_row_indices = binary_to_cow_u64(b_row_indices_bin.as_slice());
    let b_values = binary_to_cow_f64(b_values_bin.as_slice());

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat - b_mat;

    let symbolic = result.symbolic();
    let nnz = symbolic.compute_nnz();
    let col_ptr = symbolic.col_ptr();
    let row_idx = symbolic.row_idx();
    let vals = result.val();

    let col_ptr_bin = u64s_to_binary(col_ptr, env);
    let row_idx_bin = u64s_to_binary(row_idx, env);
    let vals_bin = floats_to_binary(vals, env);

    match (col_ptr_bin, row_idx_bin, vals_bin) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (a_rows, a_cols, nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn sparse_scale<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr_bin: Binary<'a>,
    row_indices_bin: Binary<'a>,
    values_bin: Binary<'a>,
    scalar: f64,
) -> NifResult<Term<'a>> {
    let values = binary_to_cow_f64(values_bin.as_slice());
    let scaled: Vec<f64> = values.iter().map(|v| v * scalar).collect();

    let col_ptr = binary_to_cow_u64(col_ptr_bin.as_slice());
    let row_indices = binary_to_cow_u64(row_indices_bin.as_slice());

    let col_ptr_bin_out = u64s_to_binary(&col_ptr, env);
    let row_idx_bin_out = u64s_to_binary(&row_indices, env);
    let vals_bin_out = floats_to_binary(&scaled, env);

    match (col_ptr_bin_out, row_idx_bin_out, vals_bin_out) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (rows, cols, nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}
