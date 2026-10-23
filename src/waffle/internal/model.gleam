//// Symbolic LP/MILP modeling over the numeric driver. Not a supported public API.
//// Design decisions are recorded in `API-DESIGN.md`.

import gleam/dict.{type Dict}
import gleam/int
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
/// `import waffle/internal/model.{Linear as L, Constant as C}`.
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
  /// The solver failed numerically or internally.
  SolverFailure(String)
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

/// Columns in order of first reference.
type Columns(v) {
  Columns(index: Dict(v, Int), keys: List(v))
}

/// Summed coefficients by column, plus a constant.
type Canonical {
  Canonical(terms: Dict(Int, Float), offset: Float)
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

/// Add `sign` times each term, assigning columns to new variables. Variables
/// with zero coefficients still get a column: they are referenced.
fn accumulate(
  state: #(Columns(v), Canonical),
  terms: List(Term(v)),
  sign: Float,
) -> #(Columns(v), Canonical) {
  use #(columns, canonical), term <- list.fold(terms, state)
  case term {
    Constant(value) -> #(
      columns,
      Canonical(..canonical, offset: canonical.offset +. sign *. value),
    )
    Linear(coefficient, key) -> {
      let #(columns, index) = column(columns, key)
      let previous = dict.get(canonical.terms, index) |> result.unwrap(0.0)
      let terms =
        dict.insert(canonical.terms, index, previous +. sign *. coefficient)
      #(columns, Canonical(..canonical, terms: terms))
    }
  }
}

fn empty() -> Canonical {
  Canonical(dict.new(), 0.0)
}

fn sparse(canonical: Canonical) -> List(#(Int, Float)) {
  canonical.terms
  |> dict.to_list
  |> list.filter(fn(term) { term.1 != 0.0 })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

/// Lower `lhs relation rhs` as `lhs - rhs relation -constant`.
fn row(
  columns: Columns(v),
  constraint: Constraint(v),
) -> #(Columns(v), driver.Row) {
  let #(lhs, relation, rhs) = case constraint {
    LessEqual(lhs, rhs) -> #(lhs, driver.LessEqual, rhs)
    Equal(lhs, rhs) -> #(lhs, driver.Equal, rhs)
    GreaterEqual(lhs, rhs) -> #(lhs, driver.GreaterEqual, rhs)
  }
  let state = accumulate(#(columns, empty()), lhs, 1.0)
  let #(columns, difference) = accumulate(state, rhs, -1.0)
  #(columns, driver.Row(sparse(difference), relation, 0.0 -. difference.offset))
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

/// Lower to the numeric IR and return the variable key of each column.
fn compile_keyed(model: Model(v)) -> #(driver.Model, List(v)) {
  let #(direction, objective) = case model.objective {
    Minimize(terms) -> #(driver.Minimize, terms)
    Maximize(terms) -> #(driver.Maximize, terms)
  }
  let #(columns, objective) =
    accumulate(#(Columns(dict.new(), []), empty()), objective, 1.0)
  let #(columns, rows) = list.map_fold(model.constraints, columns, row)
  let keys = list.reverse(columns.keys)
  let numeric =
    driver.Model(
      direction,
      list.map(keys, fn(key) { driver_domain(model.domain(key)) }),
      list.index_map(keys, fn(_, index) {
        dict.get(objective.terms, index) |> result.unwrap(0.0)
      }),
      objective.offset,
      rows,
    )
  #(numeric, keys)
}

/// Lower to the numeric IR. Columns follow the order in which variables are
/// first referenced (objective, then constraints in order) and rows follow
/// `constraints` order. Numeric validation remains at the native boundary.
/// Known limitation: overflowing Gleam arithmetic is not caught here.
pub fn compile(model: Model(v)) -> Result(driver.Model, Error(v)) {
  Ok(compile_keyed(model).0)
}

/// Compile and solve using the real microlp NIF.
pub fn solve(model: Model(v)) -> Result(Outcome(v), Error(v)) {
  let #(numeric, keys) = compile_keyed(model)
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

/// Only domains come from user data; any other rejection means compilation
/// produced invalid IR, which is an internal failure.
fn native_error(error: driver.DriverError, keys: List(v)) -> Error(v) {
  case error {
    driver.InvalidModel(driver.InvalidDomain(index)) ->
      case list.drop(keys, index) {
        [key, ..] -> InvalidDomain(key)
        [] -> SolverFailure("Driver reported an unknown variable position")
      }
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
