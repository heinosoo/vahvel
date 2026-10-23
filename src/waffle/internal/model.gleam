//// Symbolic LP/MILP modeling over the numeric driver. Not a supported public API.
//// Design decisions are recorded in `API-DESIGN.md`.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
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

/// Immutable symbolic input; keys have model-local name semantics.
pub type Model(v) {
  Model(
    variables: List(#(v, driver.Domain)),
    objective: Objective(v),
    constraints: List(Constraint(v)),
  )
}

/// Compilation and native failures are distinct from mathematical outcomes.
pub type Error(v) {
  DuplicateVariable(v)
  UnknownVariable(v)
  NativeError(driver.DriverError)
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

/// Summed coefficients by column, plus a constant.
type Canonical {
  Canonical(terms: Dict(Int, Float), offset: Float)
}

/// Add `sign` times each term, resolving every variable reference, including
/// zero-coefficient ones, so invalid keys never disappear.
fn accumulate(
  canonical: Canonical,
  terms: List(Term(v)),
  sign: Float,
  columns: Dict(v, Int),
) -> Result(Canonical, Error(v)) {
  use canonical, term <- list.try_fold(terms, canonical)
  case term {
    Constant(value) ->
      Ok(Canonical(..canonical, offset: canonical.offset +. sign *. value))
    Linear(coefficient, key) -> {
      use index <- result.try(
        dict.get(columns, key) |> result.replace_error(UnknownVariable(key)),
      )
      let previous = dict.get(canonical.terms, index) |> result.unwrap(0.0)
      let terms =
        dict.insert(canonical.terms, index, previous +. sign *. coefficient)
      Ok(Canonical(..canonical, terms: terms))
    }
  }
}

fn lower(
  terms: List(Term(v)),
  columns: Dict(v, Int),
) -> Result(Canonical, Error(v)) {
  accumulate(Canonical(dict.new(), 0.0), terms, 1.0, columns)
}

fn sparse(canonical: Canonical) -> List(#(Int, Float)) {
  canonical.terms
  |> dict.to_list
  |> list.filter(fn(term) { term.1 != 0.0 })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

fn columns(
  variables: List(#(v, driver.Domain)),
) -> Result(Dict(v, Int), Error(v)) {
  use columns, #(key, index) <- list.try_fold(
    list.index_map(variables, fn(variable, index) { #(variable.0, index) }),
    dict.new(),
  )
  case dict.has_key(columns, key) {
    True -> Error(DuplicateVariable(key))
    False -> Ok(dict.insert(columns, key, index))
  }
}

/// Lower `lhs relation rhs` as `lhs - rhs relation -constant`.
fn row(
  constraint: Constraint(v),
  columns: Dict(v, Int),
) -> Result(driver.Row, Error(v)) {
  let #(lhs, relation, rhs) = case constraint {
    LessEqual(lhs, rhs) -> #(lhs, driver.LessEqual, rhs)
    Equal(lhs, rhs) -> #(lhs, driver.Equal, rhs)
    GreaterEqual(lhs, rhs) -> #(lhs, driver.GreaterEqual, rhs)
  }
  use difference <- result.try(lower(lhs, columns))
  use difference <- result.try(accumulate(difference, rhs, -1.0, columns))
  Ok(driver.Row(sparse(difference), relation, 0.0 -. difference.offset))
}

/// Lower to the numeric IR. Columns follow `variables` order and rows follow
/// `constraints` order. Numeric validation remains at the native boundary.
/// Known limitation: overflowing Gleam arithmetic is not caught here.
pub fn compile(model: Model(v)) -> Result(driver.Model, Error(v)) {
  use columns <- result.try(columns(model.variables))
  let #(direction, objective) = case model.objective {
    Minimize(terms) -> #(driver.Minimize, terms)
    Maximize(terms) -> #(driver.Maximize, terms)
  }
  use objective <- result.try(lower(objective, columns))
  use rows <- result.try(
    list.try_map(model.constraints, fn(constraint) { row(constraint, columns) }),
  )
  Ok(driver.Model(
    direction,
    list.map(model.variables, fn(variable) { variable.1 }),
    list.index_map(model.variables, fn(_, index) {
      dict.get(objective.terms, index) |> result.unwrap(0.0)
    }),
    objective.offset,
    rows,
  ))
}

/// Compile and solve using the real microlp NIF.
pub fn solve(model: Model(v)) -> Result(Outcome(v), Error(v)) {
  use numeric <- result.try(compile(model))
  use outcome <- result.try(
    driver.solve(numeric) |> result.map_error(NativeError),
  )
  case outcome {
    driver.Infeasible -> Ok(Infeasible)
    driver.UnboundedProblem -> Ok(Unbounded)
    driver.Optimal(objective, values) -> {
      let keys = list.map(model.variables, fn(variable) { variable.0 })
      Ok(Optimal(Solution(objective, dict.from_list(list.zip(keys, values)))))
    }
  }
}

/// Objective value including its constant terms.
pub fn objective(solution: Solution(v)) -> Float {
  solution.objective
}

/// Look up a primal value by variable key. An unknown key is an error, never zero.
pub fn value(solution: Solution(v), key: v) -> Result(Float, Nil) {
  dict.get(solution.values, key)
}
