import gleam/int
import gleam/list
import gleam/result
import gleam/string
import waffle/internal/highs as nif
import waffle/sparse

/// The type of a decision variable in an optimization model.
pub type VariableType {
  /// A continuous variable can take any value within its bounds.
  Continuous
  /// An integer variable must take integer values within its bounds.
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
  /// The problem is unbounded (objective can be improved infinitely).
  Unbounded
  /// The solver could not determine the status.
  Unknown
}

/// A solution to an optimization problem.
///
/// For integer programs (MILP), the `dual` values are not meaningful
/// and will typically be empty or zero.
pub type Solution {
  Solution(
    status: SolutionStatus,
    objective_value: Float,
    primal: List(Float),
    dual: List(Float),
  )
}

/// An optimization model for linear and mixed-integer programming.
///
/// Build a model using `new()`, `add_variable`, and `add_constraint`,
/// then solve it with `solve()`.
pub type Model {
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
  /// The input was invalid (e.g., no variables, invalid variable references).
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

/// Add a variable to the model.
///
/// Returns a tuple of the updated model and the variable's ID (0-indexed).
/// The ID can be used to reference this variable in constraints.
///
/// # Arguments
/// - `model`: The optimization model
/// - `coeff`: The coefficient of this variable in the objective function
/// - `lower_bound`: The minimum allowed value for this variable
/// - `upper_bound`: The maximum allowed value for this variable
/// - `var_type`: Whether the variable is continuous or integer
pub fn add_variable(
  model: Model,
  coeff: Float,
  lower_bound: Float,
  upper_bound: Float,
  var_type: VariableType,
) -> #(Model, Int) {
  let id = model.num_vars
  let new_model =
    Model(
      ..model,
      objective_coefficients: [coeff, ..model.objective_coefficients],
      variable_bounds: [#(lower_bound, upper_bound), ..model.variable_bounds],
      variable_types: [var_type, ..model.variable_types],
      num_vars: id + 1,
    )
  #(new_model, id)
}

/// Add a constraint to the model.
///
/// The constraint is of the form: `lower_bound <= sum(coefficients) <= upper_bound`.
///
/// # Arguments
/// - `model`: The optimization model
/// - `lower_bound`: The minimum value for the constraint expression
/// - `upper_bound`: The maximum value for the constraint expression
/// - `coefficients`: List of (variable_id, coefficient) pairs
///
/// # Errors
/// Returns an error if any variable ID is invalid (out of bounds).
pub fn add_constraint(
  model: Model,
  lower_bound: Float,
  upper_bound: Float,
  coefficients: List(#(Int, Float)),
) -> Result(Model, OptError) {
  use _ <- result.try(validate_variable_ids(coefficients, model.num_vars))
  let row_id = model.num_constraints
  let new_triplets =
    list.fold(coefficients, model.constraint_triplets, fn(acc, term) {
      let #(col_id, val) = term
      [#(row_id, col_id, val), ..acc]
    })
  Ok(
    Model(
      ..model,
      constraint_triplets: new_triplets,
      constraint_bounds: [
        #(lower_bound, upper_bound),
        ..model.constraint_bounds
      ],
      num_constraints: row_id + 1,
    ),
  )
}

fn validate_variable_ids(
  coefficients: List(#(Int, Float)),
  num_vars: Int,
) -> Result(Nil, OptError) {
  list.try_each(coefficients, fn(term) {
    let #(var_id, _) = term
    case var_id >= 0 && var_id < num_vars {
      True -> Ok(Nil)
      False ->
        Error(InvalidInput(
          "Invalid variable ID "
          <> int.to_string(var_id)
          <> " (model has "
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
/// - `InvalidInput` if the model has no variables or invalid structure
/// - `SolverError` if the solver encounters an internal error
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

      use #(nnz, col_ptr, row_idx, vals, con_bounds_bin) <- result.try(
        build_constraint_data(model),
      )

      case
        nif.solve_ilp(
          direction_int,
          model.objective_offset,
          obj_coeffs_bin,
          model.num_constraints,
          model.num_vars,
          nnz,
          col_ptr,
          row_idx,
          vals,
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

fn build_constraint_data(
  model: Model,
) -> Result(#(Int, BitArray, BitArray, BitArray, BitArray), OptError) {
  case model.num_constraints {
    0 -> Ok(empty_csc_data(model.num_vars))
    _ -> {
      use con_matrix <- result.try(
        sparse.from_triplets(
          model.num_constraints,
          model.num_vars,
          model.constraint_triplets,
        )
        |> result.map_error(fn(e) {
          InvalidInput(
            "Failed to build constraint matrix: " <> string.inspect(e),
          )
        }),
      )
      let #(n, cp, ri, v) = sparse.to_csc_data(con_matrix)
      let cb = pack_float_pairs(list.reverse(model.constraint_bounds))
      Ok(#(n, cp, ri, v, cb))
    }
  }
}

fn empty_csc_data(
  num_vars: Int,
) -> #(Int, BitArray, BitArray, BitArray, BitArray) {
  let col_ptr = pack_ints(list.repeat(0, num_vars + 1))
  #(0, col_ptr, <<>>, <<>>, <<>>)
}

fn pack_ints(ints: List(Int)) -> BitArray {
  list.fold(ints, <<>>, fn(acc, x) { <<acc:bits, x:int-little-size(64)>> })
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
