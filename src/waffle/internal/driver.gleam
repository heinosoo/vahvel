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

/// A continuous bound; `Unbounded` means no bound on that side.
pub type Bound {
  Unbounded
  Finite(Float)
}

/// Variable domain. Integer bounds are inclusive and must fit signed 32 bits;
/// `None` leaves that side bounded only by the signed 32-bit range, the
/// backend's integer limit. A domain whose lower bound exceeds its upper bound
/// is valid but empty, which makes the model infeasible.
pub type Domain {
  Continuous(lower: Bound, upper: Bound)
  Integer(lower: Option(Int), upper: Option(Int))
}

/// The value `Σ coefficient · variable[index] + Σ constants`. Indices may
/// repeat and appear in any order, and coefficients may be zero.
pub type Expression {
  Expression(terms: List(#(Int, Float)), constants: List(Float))
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

/// An optimal result includes the objective offset and values in variable order.
pub type Outcome {
  Optimal(objective: Float, values: List(Float))
  Infeasible
  UnboundedProblem
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
  /// A summed objective coefficient or the offset is not finite, from overflow
  /// or non-finite input.
  NonFiniteObjective
  /// A summed coefficient or constant of the row at this position is not finite.
  NonFiniteRow(row: Int)
}

/// Canonicalize, validate and solve a model with microlp's default settings.
/// The whole model is validated before any outcome is reported. Constant models
/// are valid; infeasibility (including empty domains) and unboundedness are
/// outcomes. Binary variables are represented as `Integer(Some(0), Some(1))`.
@external(erlang, "waffle_nif", "driver_solve")
pub fn solve(model: Model) -> Result(Outcome, DriverError)

/// `Σ coefficient · value + Σ constants` for `#(coefficient, value)` pairs.
/// Errors if the result is not finite, e.g. because a product or sum overflowed.
@external(erlang, "waffle_nif", "driver_evaluate")
pub fn evaluate(
  products: List(#(Float, Float)),
  constants: List(Float),
) -> Result(Float, Nil)
