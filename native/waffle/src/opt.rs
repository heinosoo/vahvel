use crate::utils::{binary_to_cow_f64, err_term, floats_to_binary, ok, WaffleError};
use microlp::{ComparisonOp, OptimizationDirection, Problem};
use rustler::{Binary, Encoder, Env, NifResult, Term};
use std::panic;

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn solve_ilp<'a>(
    env: Env<'a>,
    direction: i32,
    obj_offset: f64,
    obj_coeffs_bin: Binary<'a>,
    con_rows: usize,
    con_cols: usize,
    triplets_bin: Binary<'a>,
    con_bounds_bin: Binary<'a>,
    var_bounds_bin: Binary<'a>,
    var_types_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let result = panic::catch_unwind(|| {
        solve_ilp_impl(
            env,
            direction,
            obj_offset,
            obj_coeffs_bin,
            con_rows,
            con_cols,
            triplets_bin,
            con_bounds_bin,
            var_bounds_bin,
            var_types_bin,
        )
    });

    match result {
        Ok(res) => res,
        Err(err) => {
            let msg = if let Some(s) = err.downcast_ref::<&str>() {
                format!("Panic: {}", s)
            } else if let Some(s) = err.downcast_ref::<String>() {
                format!("Panic: {}", s)
            } else {
                "Panic in solver".to_string()
            };
            Ok(err_term(env, &WaffleError::SolverError(msg)))
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn solve_ilp_impl<'a>(
    env: Env<'a>,
    direction: i32,
    obj_offset: f64,
    obj_coeffs_bin: Binary<'a>,
    con_rows: usize,
    con_cols: usize,
    triplets_bin: Binary<'a>,
    con_bounds_bin: Binary<'a>,
    var_bounds_bin: Binary<'a>,
    var_types_bin: Binary<'a>,
) -> NifResult<Term<'a>> {
    let obj_coeffs = match binary_to_cow_f64(obj_coeffs_bin.as_slice()) {
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
    let triplets_data = triplets_bin.as_slice();

    if obj_coeffs.len() != con_cols {
        return Ok(err_term(
            env,
            &WaffleError::DimensionMismatch("Objective coefficients length mismatch".to_string()),
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
    if !triplets_data.len().is_multiple_of(24) {
        return Ok(err_term(
            env,
            &WaffleError::InvalidInput("Triplets binary size not multiple of 24".to_string()),
        ));
    }

    let dir = if direction == 1 {
        OptimizationDirection::Maximize
    } else {
        OptimizationDirection::Minimize
    };

    let mut problem = Problem::new(dir);
    let mut vars = Vec::with_capacity(con_cols);

    // Add variables
    for i in 0..con_cols {
        let coeff = obj_coeffs[i];
        let lb = var_bounds[i * 2];
        let ub = var_bounds[i * 2 + 1];
        let is_int = var_types[i] == 1;

        // Handle infinity for microlp
        let lb_f64 = if lb <= -1.0e308 {
            f64::NEG_INFINITY
        } else {
            lb
        };
        let ub_f64 = if ub >= 1.0e308 { f64::INFINITY } else { ub };

        let var = if is_int {
            let lb_int = if lb <= -1.0e20 { i32::MIN } else { lb as i32 };
            let ub_int = if ub >= 1.0e20 { i32::MAX } else { ub as i32 };
            problem.add_integer_var(coeff, (lb_int, ub_int))
        } else {
            problem.add_var(coeff, (lb_f64, ub_f64))
        };
        vars.push(var);
    }

    // Add constraints
    // Triplets are sorted by row, then col.
    // Format: row (u64), col (u64), val (f64) - all little endian
    let mut triplet_chunks = triplets_data.chunks_exact(24);
    let mut next_chunk = triplet_chunks.next();

    // Reusable buffer for constraint coefficients
    let mut coeffs = Vec::new();

    for row_idx in 0..con_rows {
        coeffs.clear();
        let lb = con_bounds[row_idx * 2];
        let ub = con_bounds[row_idx * 2 + 1];

        // Collect triplets for this row
        while let Some(chunk) = next_chunk {
            let r = u64::from_le_bytes(chunk[0..8].try_into().unwrap()) as usize;
            if r == row_idx {
                let c = u64::from_le_bytes(chunk[8..16].try_into().unwrap()) as usize;
                let v = f64::from_le_bytes(chunk[16..24].try_into().unwrap());

                if c < con_cols {
                    coeffs.push((vars[c], v));
                }
                next_chunk = triplet_chunks.next();
            } else if r > row_idx {
                break; // Triplet belongs to a future row
            } else {
                // r < row_idx: should not happen if sorted
                next_chunk = triplet_chunks.next();
            }
        }

        // Add constraints based on bounds
        let lb_inf = lb <= -1.0e308;
        let ub_inf = ub >= 1.0e308;

        if !lb_inf && !ub_inf && (ub - lb).abs() < 1e-9 {
            // Equality
            problem.add_constraint(&coeffs, ComparisonOp::Eq, lb);
        } else {
            if !lb_inf {
                problem.add_constraint(&coeffs, ComparisonOp::Ge, lb);
            }
            if !ub_inf {
                problem.add_constraint(&coeffs, ComparisonOp::Le, ub);
            }
        }
    }

    match problem.solve() {
        Ok(solution) => {
            let obj_val = solution.objective() + obj_offset;
            let mut primal = Vec::with_capacity(con_cols);
            for var in &vars {
                primal.push(solution.var_value(*var));
            }
            // Duals not supported by microlp API efficiently/publicly, return 0.0s
            let dual = vec![0.0; con_rows]; // Or empty? Waffle expects list.

            let primal_bin = floats_to_binary(&primal, env);
            let dual_bin = floats_to_binary(&dual, env);

            // Status mapping: microlp returns Error on failure, Ok on success (Optimal)
            // But success might be suboptimal? No, usually optimal.
            // microlp errors: Infeasible, Unbounded, Limit, Internal.
            let status_int = 0; // Optimal

            match (primal_bin, dual_bin) {
                (Some(pb), Some(db)) => Ok((ok(), (status_int, obj_val, pb, db)).encode(env)),
                _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
            }
        }
        Err(e) => {
            let status_int = match e {
                microlp::Error::Infeasible => 1,
                microlp::Error::Unbounded => 2,
                _ => 3, // Unknown or Error
            };

            // If infeasible/unbounded, we might not have primal/dual values.
            // Waffle expects primal/dual lists.
            // We can return empty lists or zeros.
            // Return empty binaries if no solution
            let primal_bin = floats_to_binary(&[], env);
            let dual_bin = floats_to_binary(&[], env);
            match (primal_bin, dual_bin) {
                (Some(pb), Some(db)) => Ok((ok(), (status_int, 0.0, pb, db)).encode(env)),
                _ => Ok(err_term(env, &WaffleError::AllocationFailed)),
            }
        }
    }
}
