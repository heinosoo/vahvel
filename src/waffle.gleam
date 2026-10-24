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
/// Difference(revenue, cost)                         // revenue − cost
/// list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) }) |> Sum
/// ```
///
/// For shorter literals, rename the constructors at the import:
/// `import waffle.{Linear as L, Constant as C}`.
pub type Expression(v) {
  /// A variable with coefficient one, equivalent to `Linear(1.0, variable)`.
  Variable(variable: v)
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
  /// The sum of the expressions; the empty sum is zero.
  Sum(expressions: List(Expression(v)))
  /// Subtract rhs from lhs, equivalent to `Sum([lhs, Scaled(-1.0, rhs)])`.
  /// Both sides still reference their variables even when they cancel.
  Difference(lhs: Expression(v), rhs: Expression(v))
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
  /// A real-valued variable with optional inclusive bounds.
  Real(lower: Option(Float), upper: Option(Float))
  /// An integer-valued variable with optional inclusive bounds.
  Integer(lower: Option(Int), upper: Option(Int))
  /// A real-valued variable at least zero: `Real(Some(0.0), None)`.
  NonNegativeReal
  /// An integer-valued variable at least zero: `Integer(Some(0), None)`.
  /// The backend's signed 32-bit limit still applies.
  NonNegativeInteger
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

/// Why a model could not be solved. Infeasibility and unboundedness are
/// answers, not errors; see `Outcome`.
pub type SolveError(v) {
  /// This variable's domain can't be solved here: its integer bounds do not
  /// fit the backend's signed 32 bits, or a bound is not finite.
  InvalidDomain(v)
  /// An input or intermediate calculation is infinite or NaN.
  NonFinite(Location(v))
  /// The solver failed numerically or internally. The message is for
  /// diagnostics only.
  SolverFailure(String)
}

/// Where in a model an error occurred.
pub type Location(v) {
  InObjective
  /// The constraint, and its zero-based position in `Model.constraints`.
  InConstraint(index: Int, constraint: Constraint(v))
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

/// Why an expression could not be evaluated.
pub type EvaluationError(v) {
  /// The lookup supplied no value for this variable, which the expression
  /// references.
  MissingValue(v)
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
    Descend(Variable(key)), _ ->
      lower_loop(columns, Descend(Linear(1.0, key)), frames)
    Descend(Difference(lhs, rhs)), _ ->
      lower_loop(columns, Descend(Sum([lhs, Scaled(-1.0, rhs)])), frames)
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
    NonNegativeReal -> driver.Real(driver.Finite(0.0), driver.Unbounded)
    NonNegativeInteger -> driver.Integer(Some(0), None)
    Real(lower, upper) -> driver.Real(bound(lower), bound(upper))
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
pub fn solve(model: Model(v)) -> Result(Outcome(v), SolveError(v)) {
  let #(numeric, keys) = compile(model)
  use outcome <- result.try(
    driver.solve(numeric)
    |> result.map_error(native_error(_, keys, model.constraints)),
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
fn native_error(
  error: driver.DriverError,
  keys: List(v),
  constraints: List(Constraint(v)),
) -> SolveError(v) {
  case error {
    driver.InvalidModel(driver.InvalidDomain(index)) ->
      case list.drop(keys, index) {
        [key, ..] -> InvalidDomain(key)
        [] -> SolverFailure("Driver reported an unknown variable position")
      }
    driver.InvalidModel(driver.NonFiniteObjective) -> NonFinite(InObjective)
    driver.InvalidModel(driver.NonFiniteRow(index)) ->
      case list.drop(constraints, index) {
        [constraint, ..] -> NonFinite(InConstraint(index, constraint))
        [] -> SolverFailure("Driver reported an unknown constraint position")
      }
    driver.InvalidModel(_) -> SolverFailure("Compiled model was rejected")
    driver.SolverFailure(message) -> SolverFailure(message)
  }
}

/// Objective value including its constant terms, as reported by the solver. It
/// is not recomputed from the rounded integer values, so it can differ from
/// `evaluate_solution` of the objective expression in the last digits.
pub fn objective(solution: Solution(v)) -> Float {
  solution.objective
}

/// Statistics of the solve that produced this solution.
pub fn stats(solution: Solution(v)) -> Stats {
  solution.stats
}

/// Look up a primal value by variable key, like `dict.get`. A key that no
/// expression references is `Error(Nil)`, never zero. Integer and binary
/// variables have exact whole values, so `float.round` converts them without
/// loss.
pub fn value(solution: Solution(v), key: v) -> Result(Float, Nil) {
  dict.get(solution.values, key)
}

/// All primal values, keyed by every variable the model referenced. Integer and
/// binary variables have exact whole values.
pub fn values(solution: Solution(v)) -> Dict(v, Float) {
  solution.values
}

/// Evaluate an expression with the values `lookup` gives its variables, e.g. a
/// cost breakdown, a constraint's slack as `Difference(rhs, lhs)`, or the cost
/// of a hand-made plan. Values need not satisfy any model.
///
/// Every referenced variable needs a value, even one that cancels or is scaled
/// by zero. The first variable without one, in depth-first order, is
/// `MissingValue(key)`; unreferenced keys are never looked up.
///
/// ```gleam
/// waffle.evaluate(profit, dict.get(plan, _))
/// waffle.evaluate(profit, fn(key) {
///   case dict.get(overrides, key) {
///     Ok(value) -> Ok(value)
///     Error(Nil) -> waffle.value(solution, key)
///   }
/// })
/// ```
pub fn evaluate(
  expression: Expression(v),
  lookup: fn(v) -> Result(Float, Nil),
) -> Result(Float, EvaluationError(v)) {
  let #(columns, expression) = lower(Columns(dict.new(), []), expression)
  use values <- result.try(
    list.try_map(list.reverse(columns.keys), fn(key) {
      lookup(key) |> result.replace_error(MissingValue(key))
    }),
  )
  driver.evaluate(expression, values)
  |> result.replace_error(NonFiniteValue)
}

/// Evaluate an expression at a solution's values:
/// `evaluate(expression, value(solution, _))`.
pub fn evaluate_solution(
  expression: Expression(v),
  solution: Solution(v),
) -> Result(Float, EvaluationError(v)) {
  evaluate(expression, value(solution, _))
}

/// Evaluate an expression at the values in a dictionary:
/// `evaluate(expression, dict.get(values, _))`.
pub fn evaluate_dict(
  expression: Expression(v),
  values: Dict(v, Float),
) -> Result(Float, EvaluationError(v)) {
  evaluate(expression, dict.get(values, _))
}
