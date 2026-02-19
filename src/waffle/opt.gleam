//// Mixed-Integer Linear Programming (MILP) solver.
////
//// ## Overview
////
//// This module provides a type-safe API for building and solving optimization
//// problems of the form:
////
//// ```text
//// minimize (or maximize)  c'x
//// subject to              Ax {<=, =, >=} b
////                         x >= lower, x <= upper
////                         x integer or continuous
//// ```
////
//// ## Quick Example
////
//// ```gleam
//// import waffle/opt
////
//// pub fn main() {
////   // Create a model
////   let model = opt.new()
////
////   // Add variables (each returns a VarId for type-safe reference)
////   let #(model, x) = opt.int_var(model, "x", 1.0, 0.0, 10.0)
////   let #(model, y) = opt.int_var(model, "y", 1.0, 0.0, 5.0)
////
////   // Add constraints
////   let assert Ok(model) = opt.add_eq_constraint(model, 5.0, [#(x, 1.0), #(y, 1.0)])
////
////   // Solve
////   let assert Ok(solution) = opt.solve(model)
////
////   // Access results
////   case solution.status {
////     opt.Optimal -> {
////       let [val_x, val_y] = solution.primal
////       // val_x = 0.0, val_y = 5.0 (minimize x + y subject to x + y = 5)
////     }
////     _ -> panic as "No solution found"
////   }
//// }
//// ```
////
//// ## Variable Management
////
//// Variables are created with `int_var` (integer) or `cont_var` (continuous).
//// Each function returns `#(Model, VarId)` - the updated model and a type-safe
//// reference to the new variable.
////
//// For batch creation, use `int_vars` or `cont_vars`:
////
//// ```gleam
//// let #(model, vars) = opt.int_vars(model, 5, "x", 1.0, 0.0, 10.0)
//// // vars = [VarId("x_0", 0), VarId("x_1", 1), ...]
//// ```
////
//// ## Constraints
////
//// Use convenience functions for common constraint types:
////
//// - `add_eq_constraint(model, value, coeffs)` — equality: sum = value
//// - `add_le_constraint(model, upper, coeffs)` — inequality: sum <= upper
//// - `add_ge_constraint(model, lower, coeffs)` — inequality: sum >= lower
//// - `add_constraint(model, lower, upper, coeffs)` — range: lower <= sum <= upper
////
//// ## Solution Access
////
//// After solving, access results via `Solution` fields:
////
//// - `status` — `Optimal`, `Infeasible`, `Unbounded`, or `Unknown`
//// - `objective_value` — the optimal objective value
//// - `primal` — list of variable values, in order added
//// - `dual` — dual values (not meaningful for MILP)

import gleam/int
import gleam/list
import gleam/order.{Eq}
import gleam/result
import waffle/internal/solver_nif as nif

type VariableType {
  Continuous
  Integer
}

/// The optimization direction.
pub type Direction {
  /// Minimize the objective function.
  Minimize
  /// Maximize the objective function.
  Maximize
}

/// The status of a solution returned by the solver.
pub type SolutionStatus {
  /// An optimal solution was found.
  Optimal
  /// The problem is infeasible (no solution exists).
  Infeasible
  /// The problem is unbounded (objective can go to infinity).
  Unbounded
  /// The solver could not determine the status.
  Unknown
}

/// A reference to a variable in an optimization model.
///
/// Variables are created by `int_var`, `cont_var`, or batch functions like `int_vars`.
/// Use `VarId` in constraint coefficients to reference variables.
pub opaque type VarId {
  VarId(name: String, id: Int)
}

/// A solution to an optimization problem.
///
/// ## Fields
///
/// - `status`: The solver status (`Optimal`, `Infeasible`, `Unbounded`, or `Unknown`)
/// - `objective_value`: The optimal objective function value
/// - `primal`: Variable values at the solution, in the order variables were added.
///   Access by position: `let [val_x, val_y, ..] = solution.primal`.
/// - `dual`: Dual values for constraints (marginal costs). Not meaningful for
///   mixed-integer programs (MILP) and will typically be empty or zero.
pub type Solution {
  Solution(
    status: SolutionStatus,
    objective_value: Float,
    primal: List(Float),
    dual: List(Float),
  )
}

/// An optimization model for linear and mixed-integer programming.
pub opaque type Model {
  Model(
    direction: Direction,
    objective_offset: Float,
    objective_coefficients: List(Float),
    constraint_triplets: List(#(Int, Int, Float)),
    constraint_bounds: List(#(Float, Float)),
    variable_bounds: List(#(Float, Float)),
    variable_types: List(VariableType),
    num_vars: Int,
    num_constraints: Int,
  )
}

/// Errors that can occur during optimization.
pub type OptError {
  /// The solver encountered an internal error.
  SolverError(String)
  /// Invalid input was provided to the model.
  InvalidInput(String)
}

/// Create a new empty optimization model with default settings.
///
/// The model defaults to minimization. Use `set_direction` to change.
pub fn new() -> Model {
  Model(
    direction: Minimize,
    objective_offset: 0.0,
    objective_coefficients: [],
    constraint_triplets: [],
    constraint_bounds: [],
    variable_bounds: [],
    variable_types: [],
    num_vars: 0,
    num_constraints: 0,
  )
}

/// Set the optimization direction (minimize or maximize).
pub fn set_direction(model: Model, direction: Direction) -> Model {
  Model(..model, direction: direction)
}

/// Get the name of a variable.
pub fn var_name(var: VarId) -> String {
  let VarId(name:, id: _) = var
  name
}

/// Add an integer variable to the model.
///
/// Returns a tuple of the updated model and a `VarId` reference.
/// The `VarId` is used in constraint coefficients.
///
/// # Example
///
/// ```gleam
/// let model = opt.new()
/// let #(model, x) = opt.int_var(model, "x", 1.0, 0.0, 10.0)
/// ```
pub fn int_var(
  model: Model,
  name: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
) -> #(Model, VarId) {
  add_variable(model, name, coeff, lower_bound, upper_bound, Integer)
}

/// Add a continuous variable to the model.
///
/// Returns a tuple of the updated model and a `VarId` reference.
/// The `VarId` is used in constraint coefficients.
///
/// # Example
///
/// ```gleam
/// let model = opt.new()
/// let #(model, x) = opt.cont_var(model, "x", 1.0, 0.0, 100.0)
/// ```
pub fn cont_var(
  model: Model,
  name: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
) -> #(Model, VarId) {
  add_variable(model, name, coeff, lower_bound, upper_bound, Continuous)
}

/// Add multiple integer variables with auto-generated names.
///
/// Names are generated as `"{prefix}_{i}"` for i in 0..count.
///
/// # Example
///
/// ```gleam
/// let model = opt.new()
/// let #(model, vars) = opt.int_vars(model, 3, "x", 1.0, 0.0, 10.0)
/// // vars = [VarId("x_0", 0), VarId("x_1", 1), ...]
/// ```
pub fn int_vars(
  model: Model,
  count: Int,
  prefix: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
) -> #(Model, List(VarId)) {
  add_vars(model, count, prefix, coeff, lower_bound, upper_bound, Integer)
}

/// Add multiple continuous variables with auto-generated names.
///
/// Names are generated as `"{prefix}_{i}"` for i in 0..count.
pub fn cont_vars(
  model: Model,
  count: Int,
  prefix: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
) -> #(Model, List(VarId)) {
  add_vars(model, count, prefix, coeff, lower_bound, upper_bound, Continuous)
}

/// Add multiple integer variables with individual bounds.
///
/// Names are generated as `"{prefix}_{i}"` for each variable.
/// Each variable has its own `(lower, upper)` bound from the bounds list.
///
/// # Example
///
/// ```gleam
/// let model = opt.new()
/// let bounds = [#(0.0, 10.0), #(0.0, 5.0), #(0.0, 7.0)]
/// let #(model, vars) = opt.int_vars_with_bounds(model, "btn", 1.0, bounds)
/// ```
pub fn int_vars_with_bounds(
  model: Model,
  prefix: String,
  coeff: Float,
  bounds: List(#(Float, Float)),
) -> #(Model, List(VarId)) {
  add_vars_with_bounds(model, prefix, coeff, bounds, Integer)
}

fn add_variable(
  model: Model,
  name: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
  var_type: VariableType,
) -> #(Model, VarId) {
  let id = model.num_vars
  let var = VarId(name:, id:)
  let new_model =
    Model(
      ..model,
      objective_coefficients: [coeff, ..model.objective_coefficients],
      variable_bounds: [#(lower_bound, upper_bound), ..model.variable_bounds],
      variable_types: [var_type, ..model.variable_types],
      num_vars: id + 1,
    )
  #(new_model, var)
}

fn add_vars(
  model: Model,
  count: Int,
  prefix: String,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
  var_type: VariableType,
) -> #(Model, List(VarId)) {
  int.range(from: count - 1, to: -1, with: #(model, []), run: fn(acc, i) {
    let #(model, vars) = acc
    let name = prefix <> "_" <> int.to_string(i)
    let #(model, var) =
      add_variable(model, name, coeff, lower_bound, upper_bound, var_type)
    #(model, [var, ..vars])
  })
}

fn add_vars_with_bounds(
  model: Model,
  prefix: String,
  coeff: Float,
  bounds: List(#(Float, Float)),
  var_type: VariableType,
) -> #(Model, List(VarId)) {
  bounds
  |> list.index_fold(#(model, []), fn(acc, bound, i) {
    let #(model, vars) = acc
    let #(lower, upper) = bound
    let name = prefix <> "_" <> int.to_string(i)
    let #(model, var) = add_variable(model, name, coeff, lower, upper, var_type)
    #(model, [var, ..vars])
  })
  |> fn(pair) {
    let #(model, vars) = pair
    #(model, list.reverse(vars))
  }
}

/// Add a constraint to the model.
///
/// The constraint is of the form: `lower <= sum(coefficients) <= upper`.
///
/// # Arguments
///
/// - `model`: The optimization model
/// - `lower`: Lower bound for the constraint expression (use `-1.0e308` for -infinity)
/// - `upper`: Upper bound for the constraint expression (use `1.0e308` for +infinity)
/// - `coefficients`: List of `(VarId, coefficient)` pairs
///
/// # Example
///
/// ```gleam
/// // 5.0 <= x + 2y <= 10.0
/// let assert Ok(model) = opt.add_constraint(model, 5.0, 10.0, [#(x, 1.0), #(y, 2.0)])
/// ```
///
/// # Errors
///
/// Returns `InvalidInput` if any VarId references a variable not in this model.
pub fn add_constraint(
  model: Model,
  lower: Float,
  upper: Float,
  coefficients: List(#(VarId, Float)),
) -> Result(Model, OptError) {
  use _ <- result.try(validate_variable_ids(coefficients, model.num_vars))
  let row_id = model.num_constraints
  let new_triplets =
    list.fold(coefficients, model.constraint_triplets, fn(acc, term) {
      let #(var, val) = term
      let VarId(name: _, id:) = var
      [#(row_id, id, val), ..acc]
    })
  Ok(
    Model(
      ..model,
      constraint_triplets: new_triplets,
      constraint_bounds: [#(lower, upper), ..model.constraint_bounds],
      num_constraints: row_id + 1,
    ),
  )
}

/// Add an equality constraint: `sum(coefficients) = value`.
///
/// # Example
///
/// ```gleam
/// let assert Ok(model) = opt.add_eq_constraint(model, 5.0, [#(x, 1.0), #(y, 1.0)])
/// ```
pub fn add_eq_constraint(
  model: Model,
  value: Float,
  coefficients: List(#(VarId, Float)),
) -> Result(Model, OptError) {
  add_constraint(model, value, value, coefficients)
}

/// Add a less-than-or-equal constraint: `sum(coefficients) <= upper`.
///
/// Shorthand for `add_constraint(model, -inf, upper, coefficients)`.
///
/// # Example
///
/// ```gleam
/// // x + y <= 10
/// let assert Ok(model) = opt.add_le_constraint(model, 10.0, [#(x, 1.0), #(y, 1.0)])
/// ```
pub fn add_le_constraint(
  model: Model,
  upper: Float,
  coefficients: List(#(VarId, Float)),
) -> Result(Model, OptError) {
  add_constraint(model, -1.0e308, upper, coefficients)
}

/// Add a greater-than-or-equal constraint: `sum(coefficients) >= lower`.
///
/// Shorthand for `add_constraint(model, lower, +inf, coefficients)`.
///
/// # Example
///
/// ```gleam
/// // x + y >= 5
/// let assert Ok(model) = opt.add_ge_constraint(model, 5.0, [#(x, 1.0), #(y, 1.0)])
/// ```
pub fn add_ge_constraint(
  model: Model,
  lower: Float,
  coefficients: List(#(VarId, Float)),
) -> Result(Model, OptError) {
  add_constraint(model, lower, 1.0e308, coefficients)
}

fn validate_variable_ids(
  coefficients: List(#(VarId, Float)),
  num_vars: Int,
) -> Result(Nil, OptError) {
  list.try_each(coefficients, fn(term) {
    let #(var, _) = term
    let VarId(name:, id:) = var
    case id >= 0 && id < num_vars {
      True -> Ok(Nil)
      False ->
        Error(InvalidInput(
          "Invalid variable '"
          <> name
          <> "' (id="
          <> int.to_string(id)
          <> ", model has "
          <> int.to_string(num_vars)
          <> " variables)",
        ))
    }
  })
}

/// Solve the optimization model.
///
/// Returns a `Solution` containing the status, objective value, and primal/dual values.
///
/// # Errors
///
/// - `InvalidInput` if the model has no variables
/// - `SolverError` if the solver encounters an internal error
///
/// # Example
///
/// ```gleam
/// case opt.solve(model) {
///   Ok(solution) -> {
///     case solution.status {
///       opt.Optimal -> // use solution.primal, solution.objective_value
///       opt.Infeasible -> // no solution exists
///       opt.Unbounded -> // objective can be improved infinitely
///       opt.Unknown -> // solver could not determine status
///     }
///   }
///   Error(opt.SolverError(msg)) -> // internal error
///   Error(opt.InvalidInput(msg)) -> // invalid model
/// }
/// ```
pub fn solve(model: Model) -> Result(Solution, OptError) {
  case model.num_vars {
    0 -> Error(InvalidInput("No variables in model"))
    _ -> {
      let direction_int = case model.direction {
        Minimize -> 0
        Maximize -> 1
      }

      let obj_coeffs = list.reverse(model.objective_coefficients)
      let obj_coeffs_bin = pack_floats(obj_coeffs)

      let var_bounds = list.reverse(model.variable_bounds)
      let var_bounds_bin = pack_float_pairs(var_bounds)

      let var_types = list.reverse(model.variable_types)
      let var_types_bin = pack_var_types(var_types)

      let triplets_bin = pack_triplets(model.constraint_triplets)
      let con_bounds_bin =
        pack_float_pairs(list.reverse(model.constraint_bounds))

      case
        nif.solve_ilp(
          direction_int,
          model.objective_offset,
          obj_coeffs_bin,
          model.num_constraints,
          model.num_vars,
          triplets_bin,
          con_bounds_bin,
          var_bounds_bin,
          var_types_bin,
        )
      {
        Ok(#(status_int, obj_val, primal_bin, dual_bin)) -> {
          let status = case status_int {
            0 -> Optimal
            1 -> Infeasible
            2 -> Unbounded
            _ -> Unknown
          }
          let primal = unpack_floats(primal_bin)
          let dual = unpack_floats(dual_bin)
          Ok(Solution(status, obj_val, primal, dual))
        }
        Error(msg) -> Error(SolverError(msg))
      }
    }
  }
}

fn pack_triplets(triplets: List(#(Int, Int, Float))) -> BitArray {
  // Sort by row, then by col
  triplets
  |> list.sort(fn(a, b) {
    case int.compare(a.0, b.0) {
      Eq -> int.compare(a.1, b.1)
      other -> other
    }
  })
  |> list.fold(<<>>, fn(acc, t) {
    let #(r, c, v) = t
    <<
      acc:bits,
      r:int-little-size(64),
      c:int-little-size(64),
      v:float-little-size(64),
    >>
  })
}

fn pack_floats(floats: List(Float)) -> BitArray {
  list.fold(floats, <<>>, fn(acc, x) { <<acc:bits, x:float-little-size(64)>> })
}

fn pack_float_pairs(pairs: List(#(Float, Float))) -> BitArray {
  list.fold(pairs, <<>>, fn(acc, pair) {
    let #(a, b) = pair
    <<acc:bits, a:float-little-size(64), b:float-little-size(64)>>
  })
}

fn pack_var_types(types: List(VariableType)) -> BitArray {
  list.fold(types, <<>>, fn(acc, t) {
    let val = case t {
      Continuous -> 0
      Integer -> 1
    }
    <<acc:bits, val:int-size(8)>>
  })
}

fn unpack_floats(data: BitArray) -> List(Float) {
  unpack_floats_loop(data, [])
}

fn unpack_floats_loop(data: BitArray, acc: List(Float)) -> List(Float) {
  case data {
    <<x:float-little-size(64), rest:bits>> ->
      unpack_floats_loop(rest, [x, ..acc])
    _ -> list.reverse(acc)
  }
}
