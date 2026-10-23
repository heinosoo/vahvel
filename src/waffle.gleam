//// Linear and mixed-integer programming. Describe a model with plain Gleam
//// data, keyed by your own types, and solve it with a native solver.
////
//// The API is unstable while the package is 0.x.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/duration.{type Duration}
import waffle/internal/driver

/// An affine expression over variable keys. Duplicate variables and zero
/// coefficients are allowed, and expressions nest to any depth.
///
/// ```gleam
/// Sum([Linear(3.0, X), Linear(2.0, Y), Constant(7.0)])  // 3x + 2y + 7
/// Sum([revenue, Scaled(-1.0, cost)])                    // revenue − cost
/// list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) }) |> Sum
/// ```
///
/// For shorter literals, rename the constructors at the import:
/// `import waffle.{Linear as L, Constant as C}`.
pub type Expression(v) {
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
  /// The sum of the expressions; the empty sum is zero.
  Sum(expressions: List(Expression(v)))
  /// Scale an expression, including its constants. Scaling by zero still
  /// references the expression's variables.
  Scaled(coefficient: Float, expression: Expression(v))
}

/// A linear relation between two expressions. Constraints have no names; a
/// constraint value is its own identity.
pub type Constraint(v) {
  LessEqual(lhs: Expression(v), rhs: Expression(v))
  Equal(lhs: Expression(v), rhs: Expression(v))
  GreaterEqual(lhs: Expression(v), rhs: Expression(v))
}

/// The expression to optimize, with its direction.
pub type Objective(v) {
  Minimize(Expression(v))
  Maximize(Expression(v))
}

/// The values a variable may take. `None` means no bound on that side. Bounds
/// are inclusive; `Binary` is shorthand for `Integer(Some(0), Some(1))`.
/// A lower bound above the upper bound is an empty domain, so the model is
/// infeasible.
///
/// The current backend limits integer variables to the signed 32-bit range:
/// explicit integer bounds must fit it, and a `None` integer bound stops at its
/// edge. An integer value at ±2³¹ therefore means that limit was reached.
pub type Domain {
  /// An integer variable restricted to zero or one.
  Binary
  Continuous(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
}

/// A model to solve. A variable exists once an expression references it, and
/// `domain` gives its allowed values. The same key may be reused in different
/// models.
pub type Model(v) {
  Model(
    domain: fn(v) -> Domain,
    objective: Objective(v),
    constraints: List(Constraint(v)),
  )
}

/// Invalid input or a solver failure, distinct from infeasibility or unboundedness.
pub type Error(v) {
  /// The integer bounds of this variable's domain do not fit signed 32 bits.
  InvalidDomain(v)
  /// An input or intermediate calculation is infinite or NaN.
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
  Solution(objective: Float, values: Dict(v, Float), stats: Stats)
}

/// How much work the solver did. Models requiring no solver work report zeros.
pub type Stats {
  Stats(
    /// Branch-and-bound nodes solved; zero for a purely continuous model.
    nodes: Int,
    /// Simplex iterations, including the root relaxation.
    iterations: Int,
    /// Time spent inside the solver, excluding model construction and the
    /// native call.
    solve_time: Duration,
  )
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

// Keys are accumulated in reverse order of first reference.
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

// Lowering walks the tree with an explicit stack of frames, so deep
// expressions, such as sums accumulated in a fold, run in constant stack space.
type Step(v) {
  Descend(Expression(v))
  Ascend(driver.Expression)
}

type Frame(v) {
  // Lowered children in reverse order, then the children still to visit.
  InSum(lowered: List(driver.Expression), pending: List(Expression(v)))
  InScaled(coefficient: Float)
}

// Discover references in depth-first input order, including zero coefficients.
fn lower(
  columns: Columns(v),
  expression: Expression(v),
) -> #(Columns(v), driver.Expression) {
  lower_loop(columns, Descend(expression), [])
}

fn lower_loop(
  columns: Columns(v),
  step: Step(v),
  frames: List(Frame(v)),
) -> #(Columns(v), driver.Expression) {
  case step, frames {
    Descend(Linear(coefficient, key)), _ -> {
      let #(columns, index) = column(columns, key)
      lower_loop(columns, Ascend(driver.Linear(coefficient, index)), frames)
    }
    Descend(Constant(value)), _ ->
      lower_loop(columns, Ascend(driver.Constant(value)), frames)
    Descend(Sum([])), _ -> lower_loop(columns, Ascend(driver.Sum([])), frames)
    Descend(Sum([first, ..rest])), _ ->
      lower_loop(columns, Descend(first), [InSum([], rest), ..frames])
    Descend(Scaled(coefficient, expression)), _ ->
      lower_loop(columns, Descend(expression), [InScaled(coefficient), ..frames])
    Ascend(lowered), [] -> #(columns, lowered)
    Ascend(lowered), [InScaled(coefficient), ..frames] ->
      lower_loop(columns, Ascend(driver.Scaled(coefficient, lowered)), frames)
    Ascend(lowered), [InSum(done, []), ..frames] -> {
      let sum = driver.Sum(list.reverse([lowered, ..done]))
      lower_loop(columns, Ascend(sum), frames)
    }
    Ascend(lowered), [InSum(done, [next, ..rest]), ..frames] ->
      lower_loop(columns, Descend(next), [
        InSum([lowered, ..done], rest),
        ..frames
      ])
  }
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
    Binary -> driver.Integer(Some(0), Some(1))
    Continuous(lower, upper) -> driver.Continuous(bound(lower), bound(upper))
    Integer(lower, upper) -> driver.Integer(lower, upper)
  }
}

// Keep keys in column order to map results and positioned errors back to callers.
fn compile(model: Model(v)) -> #(driver.Model, List(v)) {
  let #(direction, objective) = case model.objective {
    Minimize(expression) -> #(driver.Minimize, expression)
    Maximize(expression) -> #(driver.Maximize, expression)
  }
  let #(columns, objective) = lower(Columns(dict.new(), []), objective)
  let #(columns, rows) = list.map_fold(model.constraints, columns, row)
  let keys = list.reverse(columns.keys)
  let domains = list.map(keys, fn(key) { driver_domain(model.domain(key)) })
  #(driver.Model(direction, domains, objective, rows), keys)
}

/// Solve a model, returning its optimum, infeasibility or unboundedness.
pub fn solve(model: Model(v)) -> Result(Outcome(v), Error(v)) {
  let #(numeric, keys) = compile(model)
  use outcome <- result.try(
    driver.solve(numeric) |> result.map_error(native_error(_, keys)),
  )
  case outcome {
    driver.Infeasible -> Ok(Infeasible)
    driver.UnboundedProblem -> Ok(Unbounded)
    driver.Optimal(objective, values, driver.Stats(nodes, iterations, time)) ->
      Ok(
        Optimal(Solution(
          objective,
          dict.from_list(list.zip(keys, values)),
          Stats(nodes, iterations, duration.nanoseconds(time)),
        )),
      )
  }
}

// Other model rejections indicate a bug in lowering, not invalid user input.
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

/// Statistics of the solve that produced this solution.
pub fn stats(solution: Solution(v)) -> Stats {
  solution.stats
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

/// Evaluate an expression using the solution's variable values, e.g. a cost
/// breakdown, or a constraint's slack as `Sum([rhs, Scaled(-1.0, lhs)])`.
/// Returns an error for missing variables or non-finite arithmetic.
pub fn evaluate(
  solution: Solution(v),
  expression: Expression(v),
) -> Result(Float, EvaluationError(v)) {
  let #(columns, expression) = lower(Columns(dict.new(), []), expression)
  use values <- result.try(
    list.try_map(list.reverse(columns.keys), fn(key) {
      dict.get(solution.values, key) |> result.replace_error(NotInSolution(key))
    }),
  )
  driver.evaluate(expression, values)
  |> result.replace_error(NonFiniteValue)
}
