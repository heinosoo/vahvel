//// Linear and mixed-integer programming. Describe a model with plain Gleam
//// data, keyed by your own types, and solve it with a native solver.
////
//// The API is unstable while the package is 0.x. This module describes
//// models; all numeric work happens in Rust. Design decisions are explained in
//// `DESIGN.md`.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import waffle/internal/driver

/// One term of a linear expression. An expression is a `List(Term(v))` whose
/// value is the sum of its terms; the empty list is zero. Duplicate variables
/// and zero coefficients are allowed and combined at compilation.
///
/// ```gleam
/// [Linear(3.0, X), Linear(2.0, Y), Constant(7.0)]  // 3x + 2y + 7
/// list.append(e1, e2)                               // e1 + e2
/// ```
///
/// For shorter literals, rename the constructors at the import:
/// `import waffle.{Linear as L, Constant as C}`.
pub type Term(v) {
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
}

/// A linear relation between two expressions. Constraints have no names; a
/// constraint value is its own identity.
pub type Constraint(v) {
  LessEqual(lhs: List(Term(v)), rhs: List(Term(v)))
  Equal(lhs: List(Term(v)), rhs: List(Term(v)))
  GreaterEqual(lhs: List(Term(v)), rhs: List(Term(v)))
}

/// The expression to optimize, with its direction.
pub type Objective(v) {
  Minimize(List(Term(v)))
  Maximize(List(Term(v)))
}

/// The values a variable may take. `None` means no bound on that side. Bounds
/// are inclusive; binary is `Integer(Some(0), Some(1))`. A lower bound above the
/// upper bound is an empty domain, so the model is infeasible.
///
/// The current backend limits integer variables to the signed 32-bit range:
/// explicit integer bounds must fit it, and a `None` integer bound stops at its
/// edge. An integer value at ±2³¹ therefore means that limit was reached.
pub type Domain {
  Continuous(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
}

/// Immutable symbolic input. A variable exists once an expression references
/// it, and `domain` gives the values each variable may take. Keys have
/// model-local name semantics.
pub type Model(v) {
  Model(
    domain: fn(v) -> Domain,
    objective: Objective(v),
    constraints: List(Constraint(v)),
  )
}

/// Compilation and solver failures are distinct from mathematical outcomes.
pub type Error(v) {
  /// The integer bounds of this variable's domain do not fit signed 32 bits.
  InvalidDomain(v)
  /// A summed coefficient or constant here is not finite: the sum overflowed,
  /// or (on targets that allow it) an input was already infinite or NaN.
  NonFinite(Location)
  /// The solver failed numerically or internally.
  SolverFailure(String)
}

/// Where in a model an error occurred.
pub type Location {
  InObjective
  /// Zero-based position in `Model.constraints`.
  InConstraint(index: Int)
}

/// A solution carries only values belonging to this solved snapshot.
pub opaque type Solution(v) {
  Solution(objective: Float, values: Dict(v, Float))
}

/// Only an optimum carries a queryable solution.
pub type Outcome(v) {
  Optimal(Solution(v))
  Infeasible
  Unbounded
}

/// Why an expression could not be evaluated against a solution.
pub type EvaluationError(v) {
  /// The solved model never referenced this variable, so it has no value.
  NotInSolution(v)
  /// The result is not finite: a product or sum overflowed.
  NonFiniteValue
}

/// Columns in order of first reference.
type Columns(v) {
  Columns(index: Dict(v, Int), keys: List(v))
}

fn column(columns: Columns(v), key: v) -> #(Columns(v), Int) {
  case dict.get(columns.index, key) {
    Ok(index) -> #(columns, index)
    Error(Nil) -> {
      let index = dict.size(columns.index)
      #(
        Columns(dict.insert(columns.index, key, index), [key, ..columns.keys]),
        index,
      )
    }
  }
}

/// Replace keys by columns, assigning columns to new variables. Variables with
/// zero coefficients still get a column: they are referenced. No arithmetic
/// happens here; Rust canonicalizes the expression.
fn lower(
  columns: Columns(v),
  terms: List(Term(v)),
) -> #(Columns(v), driver.Expression) {
  let #(columns, indexed, constants) = {
    use #(columns, indexed, constants), term <- list.fold(
      terms,
      #(columns, [], []),
    )
    case term {
      Constant(value) -> #(columns, indexed, [value, ..constants])
      Linear(coefficient, key) -> {
        let #(columns, index) = column(columns, key)
        #(columns, [#(index, coefficient), ..indexed], constants)
      }
    }
  }
  #(columns, driver.Expression(list.reverse(indexed), list.reverse(constants)))
}

fn row(
  columns: Columns(v),
  constraint: Constraint(v),
) -> #(Columns(v), driver.Row) {
  let #(lhs, relation, rhs) = case constraint {
    LessEqual(lhs, rhs) -> #(lhs, driver.LessEqual, rhs)
    Equal(lhs, rhs) -> #(lhs, driver.Equal, rhs)
    GreaterEqual(lhs, rhs) -> #(lhs, driver.GreaterEqual, rhs)
  }
  let #(columns, lhs) = lower(columns, lhs)
  let #(columns, rhs) = lower(columns, rhs)
  #(columns, driver.Row(lhs, relation, rhs))
}

fn bound(bound: Option(Float)) -> driver.Bound {
  case bound {
    Some(value) -> driver.Finite(value)
    None -> driver.Unbounded
  }
}

fn driver_domain(domain: Domain) -> driver.Domain {
  case domain {
    Continuous(lower, upper) -> driver.Continuous(bound(lower), bound(upper))
    Integer(lower, upper) -> driver.Integer(lower, upper)
  }
}

/// Lower to the driver model and return the variable key of each column.
/// Columns follow the order in which variables are first referenced (objective,
/// then constraints in order) and rows follow `constraints` order. Expressions
/// are passed on unsummed: all numeric work and validation happen in Rust.
fn compile(model: Model(v)) -> #(driver.Model, List(v)) {
  let #(direction, objective) = case model.objective {
    Minimize(terms) -> #(driver.Minimize, terms)
    Maximize(terms) -> #(driver.Maximize, terms)
  }
  let #(columns, objective) = lower(Columns(dict.new(), []), objective)
  let #(columns, rows) = list.map_fold(model.constraints, columns, row)
  let keys = list.reverse(columns.keys)
  let domains = list.map(keys, fn(key) { driver_domain(model.domain(key)) })
  #(driver.Model(direction, domains, objective, rows), keys)
}

/// Solve using the real microlp NIF.
pub fn solve(model: Model(v)) -> Result(Outcome(v), Error(v)) {
  let #(numeric, keys) = compile(model)
  use outcome <- result.try(
    driver.solve(numeric) |> result.map_error(native_error(_, keys)),
  )
  case outcome {
    driver.Infeasible -> Ok(Infeasible)
    driver.UnboundedProblem -> Ok(Unbounded)
    driver.Optimal(objective, values) ->
      Ok(Optimal(Solution(objective, dict.from_list(list.zip(keys, values)))))
  }
}

/// Domains and non-finite sums come from user data; any other rejection means
/// compilation produced invalid IR, which is an internal failure. Driver rows
/// correspond one-to-one to constraints.
fn native_error(error: driver.DriverError, keys: List(v)) -> Error(v) {
  case error {
    driver.InvalidModel(driver.InvalidDomain(index)) ->
      case list.drop(keys, index) {
        [key, ..] -> InvalidDomain(key)
        [] -> SolverFailure("Driver reported an unknown variable position")
      }
    driver.InvalidModel(driver.NonFiniteObjective) -> NonFinite(InObjective)
    driver.InvalidModel(driver.NonFiniteRow(index)) ->
      NonFinite(InConstraint(index))
    driver.InvalidModel(_) -> SolverFailure("Compiled model was rejected")
    driver.SolverFailure(message) -> SolverFailure(message)
  }
}

/// Objective value including its constant terms.
pub fn objective(solution: Solution(v)) -> Float {
  solution.objective
}

/// Look up a primal value by variable key. A key that no expression references
/// is an error, never zero.
pub fn value(solution: Solution(v), key: v) -> Result(Float, Nil) {
  dict.get(solution.values, key)
}

/// All primal values, keyed by every variable the model referenced.
pub fn values(solution: Solution(v)) -> Dict(v, Float) {
  solution.values
}

/// Evaluate an expression at this solution, e.g. a cost breakdown or the slack
/// of a constraint (`evaluate(solution, rhs)` minus `evaluate(solution, lhs)`).
/// Values are looked up here; the arithmetic happens in Rust.
pub fn evaluate(
  solution: Solution(v),
  expression: List(Term(v)),
) -> Result(Float, EvaluationError(v)) {
  use #(products, constants) <- result.try({
    use #(products, constants), term <- list.try_fold(expression, #([], []))
    case term {
      Constant(value) -> Ok(#(products, [value, ..constants]))
      Linear(coefficient, key) ->
        case dict.get(solution.values, key) {
          Ok(value) -> Ok(#([#(coefficient, value), ..products], constants))
          Error(Nil) -> Error(NotInSolution(key))
        }
    }
  })
  driver.evaluate(list.reverse(products), list.reverse(constants))
  |> result.replace_error(NonFiniteValue)
}
