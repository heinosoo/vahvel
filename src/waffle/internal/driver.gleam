//// Internal numeric LP/MILP contract. This is not a public modeling API.
////
//// Variable references are zero-based positions in `Model.variables`.
//// Rows must have strictly increasing indices and nonzero finite coefficients.
//// Validation and solving happen in Rust through a single dirty CPU NIF.

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

/// Variable domain. Integer bounds are inclusive and must fit signed 32 bits.
pub type Domain {
  Continuous(lower: Bound, upper: Bound)
  Integer(lower: Int, upper: Int)
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
  InvalidModel(String)
  SolverFailure(String)
}

/// Validate and solve a canonical model with microlp's default settings.
/// Constant models are valid; infeasibility and unboundedness are outcomes.
/// Binary variables are represented as `Integer(0, 1)`.
@external(erlang, "nif", "driver_solve")
pub fn solve(model: Model) -> Result(Outcome, DriverError)
