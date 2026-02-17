use crate::parse_mat;
use crate::utils::{
    binary_to_cow_f64, binary_to_cow_u64, err_term, floats_to_binary, ok, u64s_to_binary,
    WaffleError,
};
use faer::sparse::{SparseColMat, SparseColMatRef, SymbolicSparseColMatRef, Triplet};
use rustler::{Binary, Encoder, Env, NifResult, Term};

/// Parses three CSC binaries (col_ptr, row_indices, values) into typed slices.
/// Returns early with an error term if any binary has a length not divisible by 8.
macro_rules! parse_sparse {
    ($col_ptr:ident, $row_idx:ident, $vals:ident, $env:expr,
     $col_ptr_bin:expr, $row_idx_bin:expr, $vals_bin:expr) => {
        let $col_ptr = match binary_to_cow_u64($col_ptr_bin.as_slice()) {
            Ok(s) => s,
            Err(e) => return Ok(err_term($env, &e)),
        };
        let $row_idx = match binary_to_cow_u64($row_idx_bin.as_slice()) {
            Ok(s) => s,
            Err(e) => return Ok(err_term($env, &e)),
        };
        let $vals = match binary_to_cow_f64($vals_bin.as_slice()) {
            Ok(s) => s,
            Err(e) => return Ok(err_term($env, &e)),
        };
    };
}

struct CscOutput {
    rows: usize,
    cols: usize,
    nnz: usize,
    col_ptr: Vec<u64>,
    row_idx: Vec<u64>,
    vals: Vec<f64>,
}

impl CscOutput {
    fn from_sparse_mat(mat: &SparseColMat<u64, f64>) -> Self {
        let symbolic = mat.symbolic();
        Self {
            rows: symbolic.nrows(),
            cols: symbolic.ncols(),
            nnz: symbolic.compute_nnz(),
            col_ptr: symbolic.col_ptr().to_vec(),
            row_idx: symbolic.row_idx().to_vec(),
            vals: mat.val().to_vec(),
        }
    }

    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match (
            u64s_to_binary(&self.col_ptr, env),
            u64s_to_binary(&self.row_idx, env),
            floats_to_binary(&self.vals, env),
        ) {
            (Some(cp), Some(ri), Some(v)) => (ok(), (self.nnz, cp, ri, v)).encode(env),
            _ => err_term(env, &WaffleError::AllocationFailed),
        }
    }

    fn encode_with_dims<'a>(&self, env: Env<'a>) -> Term<'a> {
        match (
            u64s_to_binary(&self.col_ptr, env),
            u64s_to_binary(&self.row_idx, env),
            floats_to_binary(&self.vals, env),
        ) {
            (Some(cp), Some(ri), Some(v)) => {
                (ok(), (self.rows, self.cols, self.nnz, cp, ri, v)).encode(env)
            }
            _ => err_term(env, &WaffleError::AllocationFailed),
        }
    }
}

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

    // Validate col_ptr is monotonically non-decreasing
    for window in col_ptr.windows(2) {
        if window[0] > window[1] {
            return Err(WaffleError::InvalidInput(
                "col_ptr is not monotonically non-decreasing".to_string(),
            ));
        }
    }

    let nnz = col_ptr[cols]
        .checked_sub(col_ptr[0])
        .ok_or_else(|| WaffleError::InvalidInput("col_ptr[cols] < col_ptr[0]".to_string()))?
        as usize;

    if row_indices.len() < nnz || values.len() < nnz {
        return Err(WaffleError::DimensionMismatch(format!(
            "indices/values length too small for nnz {}",
            nnz
        )));
    }

    // Validate row indices are in-range and sorted within each column
    let rows_u64 = rows as u64;
    for window in col_ptr.windows(2) {
        let start = window[0] as usize;
        let end = window[1] as usize;
        let col_rows = &row_indices[start..end];
        for (i, &idx) in col_rows.iter().enumerate() {
            if idx >= rows_u64 {
                return Err(WaffleError::InvalidInput(format!(
                    "row index {} out of range for {} rows",
                    idx, rows
                )));
            }
            if i > 0 && col_rows[i - 1] > idx {
                return Err(WaffleError::InvalidInput(
                    "row indices are not sorted within a column".to_string(),
                ));
            }
        }
    }

    // Safety: we validated all conditions that new_checked asserts
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
    let row_indices = match binary_to_cow_u64(row_indices_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let col_indices = match binary_to_cow_u64(col_indices_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let values = match binary_to_cow_f64(values_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };

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

    let csc = CscOutput::from_sparse_mat(&mat);
    Ok(csc.encode(env))
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
    parse_sparse!(
        col_ptr,
        row_indices,
        values,
        env,
        col_ptr_bin,
        row_indices_bin,
        values_bin
    );

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
    parse_mat!(mat, env, rows, cols, data_bin);

    let mut triplets = Vec::new();
    for (j, col) in mat.col_iter().enumerate() {
        for (i, &val) in col.iter().enumerate() {
            if val != 0.0 {
                triplets.push(Triplet::new(i as u64, j as u64, val));
            }
        }
    }

    let sparse_mat = match SparseColMat::try_new_from_triplets(rows, cols, &triplets) {
        Ok(m) => m,
        Err(e) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed(format!("Failed to create sparse matrix: {:?}", e)),
            ))
        }
    };

    let csc = CscOutput::from_sparse_mat(&sparse_mat);
    Ok(csc.encode(env))
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
    parse_sparse!(
        col_ptr,
        row_indices,
        values,
        env,
        col_ptr_bin,
        row_indices_bin,
        values_bin
    );

    let sparse_mat = match make_sparse_mat(rows, cols, &col_ptr, &row_indices, &values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let transposed = sparse_mat.transpose();

    let csc = match transposed.to_col_major() {
        Ok(m) => CscOutput::from_sparse_mat(&m),
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::ComputationFailed(
                    "Failed to transpose (allocation error)".to_string(),
                ),
            ))
        }
    };

    Ok(csc.encode_with_dims(env))
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

    parse_sparse!(
        sp_col_ptr,
        sp_row_indices,
        sp_values,
        env,
        sp_col_ptr_bin,
        sp_row_indices_bin,
        sp_values_bin
    );

    let sparse_mat =
        match make_sparse_mat(sp_rows, sp_cols, &sp_col_ptr, &sp_row_indices, &sp_values) {
            Ok(m) => m,
            Err(e) => return Ok(err_term(env, &e)),
        };

    parse_mat!(d_mat, env, d_rows, d_cols, d_data_bin);

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

    parse_sparse!(
        a_col_ptr,
        a_row_indices,
        a_values,
        env,
        a_col_ptr_bin,
        a_row_indices_bin,
        a_values_bin
    );

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    parse_sparse!(
        b_col_ptr,
        b_row_indices,
        b_values,
        env,
        b_col_ptr_bin,
        b_row_indices_bin,
        b_values_bin
    );

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat * b_mat;

    let csc = CscOutput::from_sparse_mat(&result);
    Ok(csc.encode_with_dims(env))
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

    parse_sparse!(
        a_col_ptr,
        a_row_indices,
        a_values,
        env,
        a_col_ptr_bin,
        a_row_indices_bin,
        a_values_bin
    );

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    parse_sparse!(
        b_col_ptr,
        b_row_indices,
        b_values,
        env,
        b_col_ptr_bin,
        b_row_indices_bin,
        b_values_bin
    );

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat + b_mat;

    let csc = CscOutput::from_sparse_mat(&result);
    Ok(csc.encode_with_dims(env))
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

    parse_sparse!(
        a_col_ptr,
        a_row_indices,
        a_values,
        env,
        a_col_ptr_bin,
        a_row_indices_bin,
        a_values_bin
    );

    let a_mat = match make_sparse_mat(a_rows, a_cols, &a_col_ptr, &a_row_indices, &a_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    parse_sparse!(
        b_col_ptr,
        b_row_indices,
        b_values,
        env,
        b_col_ptr_bin,
        b_row_indices_bin,
        b_values_bin
    );

    let b_mat = match make_sparse_mat(b_rows, b_cols, &b_col_ptr, &b_row_indices, &b_values) {
        Ok(m) => m,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let result = a_mat - b_mat;

    let csc = CscOutput::from_sparse_mat(&result);
    Ok(csc.encode_with_dims(env))
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
    parse_sparse!(
        col_ptr,
        row_indices,
        values,
        env,
        col_ptr_bin,
        row_indices_bin,
        values_bin
    );

    let scaled: Vec<f64> = values.iter().map(|v| v * scalar).collect();

    let col_ptr_bin_out = u64s_to_binary(&col_ptr, env);
    let row_idx_bin_out = u64s_to_binary(&row_indices, env);
    let vals_bin_out = floats_to_binary(&scaled, env);

    match (col_ptr_bin_out, row_idx_bin_out, vals_bin_out) {
        (Some(cp), Some(ri), Some(v)) => Ok((ok(), (rows, cols, nnz, cp, ri, v)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}
