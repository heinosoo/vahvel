//// Contract violations that the public API can't produce: malformed terms,
//// out-of-range indices and malformed limits. Behavior reachable through
//// `vahvel.solve` is tested there.

import gleam/list
import gleam/option.{None, Some}
import vahvel/internal/driver as d

fn integer(lower: Int, upper: Int) -> d.Domain {
  d.Integer(Some(lower), Some(upper))
}

/// One objective coefficient per variable, plus an offset.
fn numeric(
  direction: d.Direction,
  variables: List(d.Domain),
  objective: List(Float),
  offset: Float,
  rows: List(d.Row),
) -> d.Model {
  let terms = list.index_map(objective, fn(c, i) { d.Linear(c, i) })
  d.Model(direction, variables, d.Sum([d.Constant(offset), ..terms]), rows)
}

/// `Σ terms relation rhs`.
fn row(terms: List(d.Expression), relation: d.Relation, rhs: Float) -> d.Row {
  d.Row(d.Sum(terms), relation, d.Sum([d.Constant(rhs)]))
}

fn bounded_model() -> d.Model {
  numeric(d.Minimize, [d.Real(d.Finite(0.0), d.Finite(10.0))], [1.0], 0.0, [])
}

fn solve(model: d.Model) -> Result(d.Outcome, d.DriverError) {
  d.solve(model, d.Limits(None, None))
}

@external(erlang, "vahvel_nif", "driver_solve")
fn solve_raw_with(model: a, limits: b) -> Result(d.Outcome, d.DriverError)

fn solve_raw(model: a) -> Result(d.Outcome, d.DriverError) {
  solve_raw_with(model, d.Limits(None, None))
}

@external(erlang, "gleam_stdlib", "identity")
fn unchecked(term: a) -> d.Expression

fn assert_invalid(model: d.Model, reason: d.InvalidReason) {
  assert solve(model) == Error(d.InvalidModel(reason))
}

pub fn objective_index_validation_test() {
  let model = bounded_model()
  list.each([1, -1], fn(index) {
    assert_invalid(
      d.Model(..model, objective: d.Sum([d.Linear(1.0, index)])),
      d.InvalidObjective,
    )
  })
  assert_invalid(numeric(d.Minimize, [], [1.0], 0.0, []), d.InvalidObjective)
}

pub fn invalid_indices_test() {
  let model = bounded_model()
  list.each([-1, 1, 9_223_372_036_854_775_808], fn(index) {
    assert_invalid(
      d.Model(..model, rows: [row([d.Linear(1.0, index)], d.Equal, 0.0)]),
      d.InvalidRow(0),
    )
  })
}

pub fn invalid_row_position_is_reported_test() {
  let model =
    numeric(d.Minimize, [integer(0, 1)], [1.0], 0.0, [
      row([d.Linear(1.0, 0)], d.LessEqual, 1.0),
      row([d.Linear(1.0, 0)], d.GreaterEqual, 0.0),
      row([d.Linear(1.0, 5)], d.Equal, 0.0),
    ])
  assert_invalid(model, d.InvalidRow(2))
}

pub fn validates_whole_model_before_infeasibility_test() {
  let model = bounded_model()
  assert_invalid(
    d.Model(..model, rows: [
      row([], d.Equal, 1.0),
      row([d.Linear(1.0, 1)], d.Equal, 0.0),
    ]),
    d.InvalidRow(1),
  )
  assert_invalid(
    d.Model(..model, variables: [integer(2, 1)], rows: [
      row([d.Linear(1.0, 1)], d.Equal, 0.0),
    ]),
    d.InvalidRow(0),
  )
}

pub fn malformed_term_is_a_model_error_test() {
  assert solve_raw("not a model") == Error(d.InvalidModel(d.MalformedModel))
  assert solve_raw(#(1, 2, 3)) == Error(d.InvalidModel(d.MalformedModel))
}

pub fn zero_scaled_indices_are_validated_test() {
  let expression = d.Sum([d.Scaled(0.0, d.Sum([d.Linear(0.0, 1)]))])
  assert_invalid(
    d.Model(..bounded_model(), objective: expression),
    d.InvalidObjective,
  )
  assert_invalid(
    d.Model(..bounded_model(), rows: [
      d.Row(expression, d.Equal, d.Sum([])),
    ]),
    d.InvalidRow(0),
  )
  assert d.evaluate(expression, [1.0]) == Error(Nil)
}

pub fn malformed_expression_is_invalid_test() {
  let model = bounded_model()
  assert_invalid(
    d.Model(..model, objective: d.Scaled(1.0, unchecked(1.5))),
    d.InvalidObjective,
  )
  assert_invalid(
    d.Model(..model, rows: [
      d.Row(d.Sum([unchecked("not an expression")]), d.Equal, d.Sum([])),
    ]),
    d.InvalidRow(0),
  )
}

pub fn evaluation_rejects_undecodable_indices_test() {
  list.each([-1, 18_446_744_073_709_551_616], fn(index) {
    assert d.evaluate(d.Sum([d.Linear(1.0, index)]), [1.0]) == Error(Nil)
  })
}

pub fn malformed_limits_are_solver_failures_test() {
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), "limits")
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), #(1, None, None))
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), d.Limits(Some(#(0, 1_000_000_000)), None))
}

// Raw constructors let these tests violate the numeric contract's field types.
type RawLimits(a, b) {
  Limits(time: a, nodes: b)
}

pub fn malformed_limit_fields_do_not_raise_badarg_test() {
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), Limits(Some("time"), None))
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), Limits(Some(#(1.0, 0)), None))
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), Limits(None, Some("nodes")))
  let assert Error(d.SolverFailure(_)) =
    solve_raw_with(bounded_model(), Limits(None, 2))
}

pub fn limits_validate_before_the_model_test() {
  assert solve_raw_with("invalid model", d.Limits(Some(#(-1, 0)), Some(-1)))
    == Error(d.InvalidTimeLimit)
  assert solve_raw_with("invalid model", d.Limits(None, Some(-1)))
    == Error(d.InvalidNodeLimit)
  assert solve_raw_with("invalid model", d.Limits(Some(#(0, 0)), Some(0)))
    == Error(d.InvalidModel(d.MalformedModel))
}
