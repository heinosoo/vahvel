//// Internal numeric LP/MILP contract. This is not a public modeling API.
////
//// Variable references are zero-based positions in `Model.variables`.
//// Expressions are not canonical: Rust sums duplicates, sorts, drops zeros and
//// moves constants, so callers do no float arithmetic. Validation, solving and
//// all numeric work happen in Rust through a single dirty CPU NIF.

import gleam/option.{type Option}

/// Optimization direction.
pub type Direction {
  Minimize
  Maximize
}

/// A real-valued bound; `Unbounded` means no bound on that side.
pub type Bound {
  Unbounded
  Finite(Float)
}

/// Variable domain. Integer bounds are inclusive and must fit signed 32 bits;
/// `None` leaves that side bounded only by the signed 32-bit range, the
/// backend's integer limit. A domain whose lower bound exceeds its upper bound
/// is valid but empty, which makes the model infeasible.
pub type Domain {
  Real(lower: Bound, upper: Bound)
  Integer(lower: Option(Int), upper: Option(Int))
}

/// An unsummed expression with variable keys replaced by column indices. The
/// tree mirrors the public expression; Rust performs all scaling and summation,
/// visiting leaves in depth-first input order.
pub type Expression {
  Linear(coefficient: Float, variable: Int)
  Constant(value: Float)
  Sum(expressions: List(Expression))
  Scaled(coefficient: Float, expression: Expression)
}

/// Relation between the two sides of a row.
pub type Relation {
  LessEqual
  Equal
  GreaterEqual
}

/// A linear row `lhs relation rhs`.
pub type Row {
  Row(lhs: Expression, relation: Relation, rhs: Expression)
}

/// Numeric model. The objective's constants are its offset.
pub type Model {
  Model(
    direction: Direction,
    variables: List(Domain),
    objective: Expression,
    rows: List(Row),
  )
}

/// An optimal result includes the objective offset, values in variable order
/// and solve statistics.
pub type Outcome {
  Optimal(objective: Float, values: List(Float), stats: Stats)
  Infeasible
  UnboundedProblem
}

/// Branch-and-bound nodes, simplex iterations and time spent in the solver.
/// All zero when the driver answers a model without calling the solver.
pub type Stats {
  Stats(nodes: Int, iterations: Int, nanoseconds: Int)
}

/// Invalid IR is distinct from a numerical or internal solver failure.
pub type DriverError {
  InvalidModel(reason: InvalidReason)
  SolverFailure(String)
}

/// Where the IR violates this contract. Positions are zero-based.
pub type InvalidReason {
  /// The term does not have the shape of a `Model`.
  MalformedModel
  /// The objective is malformed or references a missing variable.
  InvalidObjective
  /// The domain at this variable position has a non-finite bound or integer
  /// bounds outside signed 32 bits.
  InvalidDomain(variable: Int)
  /// The row at this position is malformed or references a missing variable.
  InvalidRow(row: Int)
  /// An objective coefficient, scale or offset is not finite, from overflow
  /// or non-finite input.
  NonFiniteObjective
  /// A coefficient, scale or constant of the row at this position is not finite.
  NonFiniteRow(row: Int)
}

/// Canonicalize, validate and solve a model with microlp's default settings.
/// The whole model is validated before any outcome is reported. Constant models
/// are valid; infeasibility (including empty domains) and unboundedness are
/// outcomes. Binary variables are represented as `Integer(Some(0), Some(1))`.
@external(erlang, "waffle_nif", "driver_solve")
pub fn solve(model: Model) -> Result(Outcome, DriverError)

/// Canonicalize with the same rules as solve, then evaluate at indexed values.
/// Invalid expressions or non-finite intermediate products/sums are errors.
@external(erlang, "waffle_nif", "driver_evaluate")
pub fn evaluate(
  expression: Expression,
  values: List(Float),
) -> Result(Float, Nil)
