use crate::utils::{
    binary_to_cow_f64, binary_to_cow_u64, err_term, floats_to_binary, ok, WaffleError,
};
use highs::{ColProblem, HighsModelStatus, Sense};
use rustler::{Binary, Encoder, Env, NifResult, Term};

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn solve_ilp<'a>(
    env: Env<'a>,
    direction: i32,
    obj_offset: f64,
    obj_coeffs_bin: Binary<'a>,
    con_rows: usize,
    con_cols: usize,
    _con_nnz: usize,
    con_col_ptr_bin: Binary<'a>,
    con_row_idx_bin: Binary<'a>,
    con_vals_bin: Binary<'a>,
    con_bounds_bin: Binary<'a>,
    var_bounds_bin: Binary<'a>,
    var_types_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let obj_coeffs = match binary_to_cow_f64(obj_coeffs_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let con_col_ptr = match binary_to_cow_u64(con_col_ptr_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let con_row_idx = match binary_to_cow_u64(con_row_idx_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let con_vals = match binary_to_cow_f64(con_vals_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let con_bounds = match binary_to_cow_f64(con_bounds_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let var_bounds = match binary_to_cow_f64(var_bounds_bin.as_slice()) {
        Ok(s) => s,
        Err(e) => return Ok(err_term(env, &e)),
    };
    let var_types = var_types_bin.as_slice();

    if obj_coeffs.len() != con_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Objective coefficients length mismatch".to_string()),
        ));
    }
    if con_col_ptr.len() != con_cols + 1 {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch(
                "Constraint matrix col_ptr length mismatch".to_string(),
            ),
        ));
    }
    if con_bounds.len() != con_rows * 2 {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Constraint bounds length mismatch".to_string()),
        ));
    }
    if var_bounds.len() != con_cols * 2 {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Variable bounds length mismatch".to_string()),
        ));
    }
    if var_types.len() != con_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Variable types length mismatch".to_string()),
        ));
    }

    let mut pb = ColProblem::new();

    let mut row_handles = Vec::with_capacity(con_rows);
    for i in 0..con_rows {
        let lb = con_bounds[i * 2];
        let ub = con_bounds[i * 2 + 1];
        row_handles.push(pb.add_row(lb..=ub));
    }

    // Reuse vector for column constraints to avoid reallocations
    let mut col_constraints = Vec::with_capacity(con_rows.min(100));

    for col in 0..con_cols {
        let start = con_col_ptr[col] as usize;
        let end = con_col_ptr[col + 1] as usize;

        col_constraints.clear();
        if end > start {
            col_constraints.reserve(end - start);
        }

        for idx in start..end {
            let row_idx = con_row_idx[idx] as usize;
            if row_idx >= con_rows {
                return Ok(err_term(
                    env,
                    &WaffleError::InvalidInput("Constraint row index out of bounds".to_string()),
                ));
            }
            col_constraints.push((row_handles[row_idx], con_vals[idx]));
        }

        let lb = var_bounds[col * 2];
        let ub = var_bounds[col * 2 + 1];
        let coeff = obj_coeffs[col];

        if var_types[col] == 1 {
            pb.add_integer_column(coeff, lb..=ub, &col_constraints);
        } else {
            pb.add_column(coeff, lb..=ub, &col_constraints);
        }
    }

    let sense = if direction == 1 {
        Sense::Maximise
    } else {
        Sense::Minimise
    };
    let mut model = pb.optimise(sense);
    model.set_option("presolve", "on");

    let solved = model.solve();
    let solution = solved.get_solution();

    let status_int = match solved.status() {
        HighsModelStatus::Optimal => 0,
        HighsModelStatus::Infeasible => 1,
        HighsModelStatus::Unbounded => 2,
        _ => 3,
    };

    let obj_val = solved.objective_value() + obj_offset;

    let primal = solution.columns();
    let dual = solution.dual_rows();

    let primal_bin = floats_to_binary(primal, env);
    let dual_bin = floats_to_binary(dual, env);

    match (primal_bin, dual_bin) {
        (Some(pb), Some(db)) => Ok((ok(), (status_int, obj_val, pb, db)).encode(env)),
        _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}
