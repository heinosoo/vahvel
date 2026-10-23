//// Internal numeric LP/MILP contract. This is not a public modeling API.
////
//// Variable references are zero-based positions in `Model.variables`.
//// Rows must have strictly increasing indices and nonzero finite coefficients.
//// Validation and solving happen in Rust through a single dirty CPU NIF.

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

/// Relation between a sparse row and its right-hand side.
pub type Relation {
  LessEqual
  Equal
  GreaterEqual
}

/// A canonical sparse linear row. An empty row has a left-hand side of zero.
pub type Row {
  Row(terms: List(#(Int, Float)), relation: Relation, rhs: Float)
}

/// Numeric model with a separate objective vector and constant offset.
/// The objective vector has exactly one finite coefficient per variable.
/// All explicit bounds, row coefficients, right-hand sides and offsets are finite.
pub type Model {
  Model(
    direction: Direction,
    variables: List(Domain),
    objective: List(Float),
    offset: Float,
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
  /// The objective length differs from the variable count, or a coefficient
  /// or the offset is not finite.
  InvalidObjective
  /// The domain at this variable position has a non-finite bound or integer
  /// bounds outside signed 32 bits.
  InvalidDomain(variable: Int)
  /// The row at this position is not finite, references a missing variable,
  /// or is not canonical.
  InvalidRow(row: Int)
}

/// Validate and solve a canonical model with microlp's default settings.
/// The whole model is validated before any outcome is reported. Constant models
/// are valid; infeasibility (including empty domains) and unboundedness are
/// outcomes.
/// Binary variables are represented as `Integer(Some(0), Some(1))`.
@external(erlang, "nif", "driver_solve")
pub fn solve(model: Model) -> Result(Outcome, DriverError)
