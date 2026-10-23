//// Symbolic LP/MILP modeling over the numeric driver. Not a supported public API.
//// Design decisions are recorded in `API-DESIGN.md`.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import waffle/internal/driver

/// Symbolic expression. Products are allowed here but rejected at compilation
/// unless one side is constant.
pub opaque type Expression(key) {
  Constant(Float)
  Variable(key)
  Sum(List(Expression(key)))
  Scale(Expression(key), Float)
  Product(Expression(key), Expression(key))
}

/// A named equation or inequality between expressions.
pub type Constraint(variable, constraint) {
  Constraint(
    constraint,
    Expression(variable),
    driver.Relation,
    Expression(variable),
  )
}

/// Immutable symbolic input; keys have model-local name semantics.
pub type Model(variable, constraint) {
  Model(
    variables: List(#(variable, driver.Domain)),
    direction: driver.Direction,
    objective: Expression(variable),
    constraints: List(Constraint(variable, constraint)),
  )
}

/// Compilation and native failures are distinct from mathematical outcomes.
pub type Error(variable, constraint) {
  DuplicateVariable(variable)
  DuplicateConstraint(constraint)
  UnknownVariable(variable)
  NonlinearExpression
  NativeError(driver.DriverError)
}

/// A solution carries only values belonging to this solved snapshot.
pub opaque type Solution(variable, constraint) {
  Solution(Float, Dict(variable, Float), Dict(constraint, Int))
}

/// Only an optimum carries a queryable solution.
pub type Outcome(variable, constraint) {
  Optimal(Solution(variable, constraint))
  Infeasible
  Unbounded
}

/// A failed lookup never substitutes a numeric zero.
pub type QueryError {
  UnknownKey
  DualsUnsupported
}

/// A literal expression.
pub fn constant(value: Float) -> Expression(key) {
  Constant(value)
}

/// A symbolic reference resolved at compilation.
pub fn variable(key: key) -> Expression(key) {
  Variable(key)
}

/// Add expressions; an empty sum is zero.
pub fn sum(expressions: List(Expression(key))) -> Expression(key) {
  Sum(expressions)
}

/// Add two expressions, with the first argument suitable for pipelines.
pub fn add(left: Expression(key), right: Expression(key)) -> Expression(key) {
  Sum([left, right])
}

/// Scale an expression by a numeric coefficient.
pub fn scale(
  expression: Expression(key),
  coefficient: Float,
) -> Expression(key) {
  Scale(expression, coefficient)
}

/// Multiply expressions; nonlinear products are rejected during compilation.
pub fn multiply(
  left: Expression(key),
  right: Expression(key),
) -> Expression(key) {
  Product(left, right)
}

type Linear {
  Linear(terms: Dict(Int, Float), offset: Float)
}

// Fold the smaller map into the larger so left-deep `add` chains stay near-linear.
fn merge(left: Linear, right: Linear) -> Linear {
  let #(large, small) = case dict.size(left.terms) >= dict.size(right.terms) {
    True -> #(left.terms, right.terms)
    False -> #(right.terms, left.terms)
  }
  let terms =
    dict.fold(small, large, fn(terms, index, value) {
      let previous = dict.get(terms, index) |> result.unwrap(0.0)
      dict.insert(terms, index, previous +. value)
    })
  Linear(terms, left.offset +. right.offset)
}

fn scaled(linear: Linear, coefficient: Float) -> Linear {
  Linear(
    dict.map_values(linear.terms, fn(_, value) { value *. coefficient }),
    linear.offset *. coefficient,
  )
}

fn sparse(linear: Linear) -> List(#(Int, Float)) {
  linear.terms
  |> dict.to_list
  |> list.filter(fn(term) { term.1 != 0.0 })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

fn lower(
  expression: Expression(v),
  columns: Dict(v, Int),
) -> Result(Linear, Error(v, c)) {
  case expression {
    Constant(value) -> Ok(Linear(dict.new(), value))
    Variable(key) -> {
      use index <- result.try(
        dict.get(columns, key)
        |> result.map_error(fn(_) { UnknownVariable(key) }),
      )
      Ok(Linear(dict.from_list([#(index, 1.0)]), 0.0))
    }
    Sum(expressions) -> {
      use total, expression <- list.try_fold(
        expressions,
        Linear(dict.new(), 0.0),
      )
      use linear <- result.try(lower(expression, columns))
      Ok(merge(total, linear))
    }
    Scale(expression, coefficient) -> {
      use linear <- result.try(lower(expression, columns))
      Ok(scaled(linear, coefficient))
    }
    Product(left, right) -> {
      use left <- result.try(lower(left, columns))
      use right <- result.try(lower(right, columns))
      case sparse(left), sparse(right) {
        [], _ -> Ok(scaled(right, left.offset))
        _, [] -> Ok(scaled(left, right.offset))
        _, _ -> Error(NonlinearExpression)
      }
    }
  }
}

fn columns(
  variables: List(#(v, driver.Domain)),
) -> Result(Dict(v, Int), Error(v, c)) {
  use columns, item <- list.try_fold(
    list.index_map(variables, fn(v, i) { #(v.0, i) }),
    dict.new(),
  )
  case dict.has_key(columns, item.0) {
    True -> Error(DuplicateVariable(item.0))
    False -> Ok(dict.insert(columns, item.0, item.1))
  }
}

fn row_keys(
  constraints: List(Constraint(v, c)),
) -> Result(Dict(c, Int), Error(v, c)) {
  use rows, item <- list.try_fold(
    list.index_map(constraints, fn(c, i) { #(c, i) }),
    dict.new(),
  )
  let Constraint(key, _, _, _) = item.0
  case dict.has_key(rows, key) {
    True -> Error(DuplicateConstraint(key))
    False -> Ok(dict.insert(rows, key, item.1))
  }
}

/// Lower to the existing IR. Numeric validation remains at the native boundary.
/// Known limitation: overflowing Gleam arithmetic is not caught here.
pub fn compile(model: Model(v, c)) -> Result(driver.Model, Error(v, c)) {
  use #(numeric, _) <- result.try(compile_keyed(model))
  Ok(numeric)
}

fn compile_keyed(
  model: Model(v, c),
) -> Result(#(driver.Model, Dict(c, Int)), Error(v, c)) {
  use columns <- result.try(columns(model.variables))
  use rows_by_key <- result.try(row_keys(model.constraints))
  use objective <- result.try(lower(model.objective, columns))
  use rows <- result.try(
    list.try_map(model.constraints, fn(constraint) {
      let Constraint(_, lhs, relation, rhs) = constraint
      use left <- result.try(lower(lhs, columns))
      use right <- result.try(lower(rhs, columns))
      let linear = merge(left, scaled(right, -1.0))
      Ok(driver.Row(sparse(linear), relation, 0.0 -. linear.offset))
    }),
  )
  let numeric =
    driver.Model(
      model.direction,
      list.map(model.variables, fn(item) { item.1 }),
      list.index_map(model.variables, fn(_, i) {
        dict.get(objective.terms, i) |> result.unwrap(0.0)
      }),
      objective.offset,
      rows,
    )
  Ok(#(numeric, rows_by_key))
}

/// Compile and solve using the real microlp NIF.
pub fn solve(model: Model(v, c)) -> Result(Outcome(v, c), Error(v, c)) {
  use #(numeric, rows) <- result.try(compile_keyed(model))
  use outcome <- result.try(
    driver.solve(numeric) |> result.map_error(NativeError),
  )
  case outcome {
    driver.Infeasible -> Ok(Infeasible)
    driver.UnboundedProblem -> Ok(Unbounded)
    driver.Optimal(objective, values) -> {
      let keys = list.map(model.variables, fn(item) { item.0 })
      Ok(
        Optimal(Solution(
          objective,
          dict.from_list(list.zip(keys, values)),
          rows,
        )),
      )
    }
  }
}

/// Objective value including its constant offset.
pub fn objective(solution: Solution(v, c)) -> Float {
  let Solution(objective, _, _) = solution
  objective
}

/// Look up a primal value by domain key.
pub fn value(solution: Solution(v, c), key: v) -> Result(Float, QueryError) {
  let Solution(_, values, _) = solution
  dict.get(values, key) |> result.map_error(fn(_) { UnknownKey })
}

/// microlp 0.6.0 has no public constraint-dual query.
pub fn dual(solution: Solution(v, c), key: c) -> Result(Float, QueryError) {
  let Solution(_, _, rows) = solution
  use _ <- result.try(
    dict.get(rows, key) |> result.map_error(fn(_) { UnknownKey }),
  )
  Error(DualsUnsupported)
}
