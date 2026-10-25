import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import waffle/internal/driver as d

fn assert_assignment(model: d.Model, values: List(Float), objective: Float) {
  let assert Ok(d.Optimal(actual_objective, actual_values, _)) = solve(model)
  should.equal(list.length(actual_values), list.length(values))
  list.zip(actual_values, values)
  |> list.each(fn(pair) {
    should.be_true(float.loosely_equals(pair.0, pair.1, 0.000001))
  })
  should.be_true(float.loosely_equals(actual_objective, objective, 0.000001))
}

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

const max = 1.7976931348623157e308

fn bounded_model() -> d.Model {
  numeric(d.Minimize, [d.Real(d.Finite(0.0), d.Finite(10.0))], [1.0], 0.0, [])
}

fn assert_invalid(model: d.Model, reason: d.InvalidReason) {
  solve(model) |> should.equal(Error(d.InvalidModel(reason)))
}

pub fn real_maximize_with_offset_test() {
  assert_assignment(
    numeric(
      d.Maximize,
      [
        d.Real(d.Finite(0.0), d.Finite(2.0)),
        d.Real(d.Finite(0.0), d.Unbounded),
      ],
      [3.0, 2.0],
      7.0,
      [row([d.Linear(1.0, 0), d.Linear(1.0, 1)], d.LessEqual, 4.0)],
    ),
    [2.0, 2.0],
    17.0,
  )
}

pub fn minimize_equal_and_greater_equal_with_offset_test() {
  assert_assignment(
    numeric(
      d.Minimize,
      [
        d.Real(d.Unbounded, d.Unbounded),
        d.Real(d.Unbounded, d.Unbounded),
      ],
      [1.0, 2.0],
      -5.0,
      [
        row([d.Linear(1.0, 0)], d.GreaterEqual, 2.0),
        row([d.Linear(1.0, 1)], d.Equal, 1.0),
      ],
    ),
    [2.0, 1.0],
    -1.0,
  )
}

pub fn integer_is_not_relaxed_test() {
  assert_assignment(
    numeric(d.Maximize, [integer(0, 10)], [1.0], -2.0, [
      row([d.Linear(2.0, 0)], d.LessEqual, 9.0),
    ]),
    [4.0],
    2.0,
  )
}

pub fn binary_bounds_test() {
  assert_assignment(
    numeric(d.Maximize, [integer(0, 1), integer(0, 1)], [1.0, 2.0], 0.0, [
      row([d.Linear(1.0, 0), d.Linear(1.0, 1)], d.LessEqual, 1.0),
    ]),
    [0.0, 1.0],
    2.0,
  )
}

pub fn mixed_integer_model_test() {
  assert_assignment(
    numeric(
      d.Maximize,
      [d.Real(d.Finite(0.0), d.Unbounded), integer(0, 3)],
      [1.0, 2.0],
      0.0,
      [
        row([d.Linear(1.0, 0), d.Linear(1.0, 1)], d.LessEqual, 4.0),
        row([d.Linear(2.0, 0), d.Linear(1.0, 1)], d.GreaterEqual, 2.0),
      ],
    ),
    [1.0, 3.0],
    7.0,
  )
}

pub fn infeasible_model_test() {
  let model = bounded_model()
  solve(d.Model(..model, rows: [row([d.Linear(1.0, 0)], d.GreaterEqual, 20.0)]))
  |> should.equal(Ok(d.Infeasible))
}

pub fn integer_infeasible_test() {
  solve(
    numeric(d.Minimize, [integer(0, 2)], [1.0], 0.0, [
      row([d.Linear(1.0, 0)], d.Equal, 0.5),
    ]),
  )
  |> should.equal(Ok(d.Infeasible))
}

pub fn unbounded_model_test() {
  solve(
    numeric(d.Maximize, [d.Real(d.Finite(0.0), d.Unbounded)], [1.0], 0.0, []),
  )
  |> should.equal(Ok(d.UnboundedProblem))
}

pub fn unconstrained_bounded_model_test() {
  assert_assignment(bounded_model(), [0.0], 0.0)
}

pub fn negative_real_domain_test() {
  assert_assignment(
    numeric(d.Maximize, [d.Real(d.Unbounded, d.Finite(-2.0))], [1.0], 0.0, []),
    [-2.0],
    -2.0,
  )
}

pub fn negative_integer_domain_test() {
  assert_assignment(
    numeric(d.Minimize, [integer(-3, -1)], [1.0], 0.0, []),
    [-3.0],
    -3.0,
  )
}

pub fn integer_bound_endpoints_test() {
  assert_assignment(
    numeric(
      d.Minimize,
      [
        integer(-2_147_483_648, -2_147_483_648),
        integer(2_147_483_647, 2_147_483_647),
      ],
      [1.0, 1.0],
      0.0,
      [],
    ),
    [-2_147_483_648.0, 2_147_483_647.0],
    -1.0,
  )
}

pub fn constant_model_test() {
  list.each([d.Minimize, d.Maximize], fn(direction) {
    assert_assignment(numeric(direction, [], [], 7.0, []), [], 7.0)
  })
}

pub fn constant_rows_test() {
  let valid = [
    row([], d.Equal, 0.0),
    row([], d.LessEqual, 1.0),
    row([], d.GreaterEqual, -1.0),
  ]
  assert_assignment(numeric(d.Minimize, [], [], 3.0, valid), [], 3.0)
  let model = bounded_model()
  assert_assignment(d.Model(..model, rows: valid), [0.0], 0.0)
  list.each(
    [
      row([], d.Equal, 1.0),
      row([], d.LessEqual, -1.0),
      row([], d.GreaterEqual, 1.0),
    ],
    fn(row) {
      solve(numeric(d.Minimize, [], [], 0.0, [row]))
      |> should.equal(Ok(d.Infeasible))
      solve(d.Model(..model, rows: [row]))
      |> should.equal(Ok(d.Infeasible))
    },
  )
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

fn real(lower: Float, upper: Float) -> d.Domain {
  d.Real(d.Finite(lower), d.Finite(upper))
}

pub fn rows_are_canonicalized_test() {
  let x = fn(c) { d.Linear(c, 0) }
  let y = fn(c) { d.Linear(c, 1) }
  let maximize_x = fn(rows) {
    numeric(
      d.Maximize,
      [real(0.0, 10.0), real(0.0, 10.0)],
      [1.0, 0.0],
      0.0,
      rows,
    )
  }
  // Duplicates are summed: x + 2x ≤ 3.
  assert_assignment(
    maximize_x([row([x(1.0), x(2.0)], d.LessEqual, 3.0)]),
    [1.0, 0.0],
    1.0,
  )
  // Unordered indices: y + x ≤ 4 with y fixed at 1 by y ≥ 1, y ≤ 1.
  assert_assignment(
    maximize_x([
      row([y(1.0), x(1.0)], d.LessEqual, 4.0),
      row([y(1.0)], d.Equal, 1.0),
    ]),
    [3.0, 1.0],
    3.0,
  )
  // Both sides with constants: x + 3 ≤ y + 5, y = 1  ⇒  x ≤ 3.
  assert_assignment(
    maximize_x([
      d.Row(
        d.Sum([x(1.0), d.Constant(3.0)]),
        d.LessEqual,
        d.Sum([y(1.0), d.Constant(5.0)]),
      ),
      row([y(1.0)], d.Equal, 1.0),
    ]),
    [3.0, 1.0],
    3.0,
  )
  // Zero and cancelling coefficients leave a constant row: 0 ≤ -1.
  list.each([[x(0.0)], [x(-0.0)], [x(2.0), x(-2.0)]], fn(terms) {
    solve(maximize_x([row(terms, d.LessEqual, -1.0)]))
    |> should.equal(Ok(d.Infeasible))
  })
  // Terms cancelling across sides: x ≤ x.
  assert_assignment(
    maximize_x([
      d.Row(d.Sum([x(1.0)]), d.LessEqual, d.Sum([x(1.0)])),
    ]),
    [10.0, 0.0],
    10.0,
  )
}

pub fn objective_is_canonicalized_test() {
  let model =
    d.Model(
      d.Maximize,
      [real(0.0, 2.0), real(0.0, 2.0)],
      d.Sum([
        d.Linear(1.0, 1),
        d.Linear(2.0, 0),
        d.Linear(-1.0, 1),
        d.Linear(1.0, 0),
        d.Constant(3.0),
        d.Constant(4.0),
      ]),
      [],
    )
  // 3x + 0y + 7
  assert_assignment(model, [2.0, 0.0], 13.0)
}

pub fn non_finite_sums_are_reported_test() {
  let model = bounded_model()
  list.each(
    [
      d.Sum([d.Linear(max, 0), d.Linear(max, 0)]),
      d.Sum([d.Constant(max), d.Constant(max)]),
      d.Sum([d.Constant(0.0 -. max), d.Constant(0.0 -. max)]),
    ],
    fn(objective) {
      assert_invalid(
        d.Model(..model, objective: objective),
        d.NonFiniteObjective,
      )
    },
  )
  let fine = row([d.Linear(1.0, 0)], d.LessEqual, 1.0)
  list.each(
    [
      row([d.Linear(max, 0), d.Linear(max, 0)], d.LessEqual, 0.0),
      // Moving `-max·x` across sides makes it `+max·x`.
      d.Row(
        d.Sum([d.Linear(max, 0)]),
        d.LessEqual,
        d.Sum([d.Linear(0.0 -. max, 0)]),
      ),
      d.Row(
        d.Sum([d.Constant(max)]),
        d.LessEqual,
        d.Sum([d.Constant(0.0 -. max)]),
      ),
    ],
    fn(overflowing) {
      assert_invalid(
        d.Model(..model, rows: [fine, overflowing]),
        d.NonFiniteRow(1),
      )
    },
  )
}

pub fn integer_bounds_outside_32_bits_test() {
  let model = bounded_model()
  list.each(
    [
      integer(-2_147_483_649, 0),
      integer(0, 2_147_483_648),
      integer(0, 9_223_372_036_854_775_808),
    ],
    fn(domain) {
      assert_invalid(d.Model(..model, variables: [domain]), d.InvalidDomain(0))
    },
  )
}

pub fn empty_domains_are_infeasible_test() {
  let model = bounded_model()
  list.each(
    [
      d.Real(d.Finite(2.0), d.Finite(1.0)),
      integer(2, 1),
    ],
    fn(domain) {
      solve(d.Model(..model, variables: [domain]))
      |> should.equal(Ok(d.Infeasible))
    },
  )
  // Equal bounds are a single point, not empty.
  assert_assignment(
    d.Model(..model, variables: [d.Real(d.Finite(3.0), d.Finite(3.0))]),
    [3.0],
    3.0,
  )
}

pub fn invalid_positions_are_reported_test() {
  let domains = [
    integer(0, 1),
    integer(0, 1),
    integer(0, 2_147_483_648),
  ]
  assert_invalid(
    numeric(d.Minimize, domains, [1.0, 1.0, 1.0], 0.0, []),
    d.InvalidDomain(2),
  )
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

pub fn objective_overflow_is_a_solver_error_test() {
  let model =
    numeric(
      d.Minimize,
      [d.Real(d.Finite(1.0), d.Finite(1.0))],
      [1.0e308],
      1.0e308,
      [],
    )
  let assert Error(d.SolverFailure(_)) = solve(model)
}

@external(erlang, "waffle_nif", "driver_solve")
fn solve_raw_with(model: a, limits: b) -> Result(d.Outcome, d.DriverError)

fn solve_raw(model: a) -> Result(d.Outcome, d.DriverError) {
  solve_raw_with(model, d.Limits(None, None))
}

fn solve(model: d.Model) -> Result(d.Outcome, d.DriverError) {
  d.solve(model, d.Limits(None, None))
}

pub fn malformed_term_is_a_model_error_test() {
  solve_raw("not a model")
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
  solve_raw(#(1, 2, 3))
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
}

pub fn integer_without_bounds_test() {
  assert_assignment(
    numeric(d.Minimize, [d.Integer(None, Some(5))], [1.0], 0.0, [
      row([d.Linear(1.0, 0)], d.GreaterEqual, -3.5),
    ]),
    [-3.0],
    -3.0,
  )
  assert_assignment(
    numeric(d.Maximize, [d.Integer(None, None)], [1.0], 0.0, [
      row([d.Linear(1.0, 0)], d.LessEqual, 7.5),
    ]),
    [7.0],
    7.0,
  )
  let assert Ok(d.Optimal(3.0, [3.0], _)) =
    solve(numeric(d.Minimize, [d.Integer(Some(3), None)], [1.0], 0.0, []))
}

// Documents the backend limit: a missing integer bound is the edge of the
// signed 32-bit range, so an unbounded direction reports that edge as optimal.
pub fn missing_integer_bound_is_the_32_bit_range_test() {
  let assert Ok(d.Optimal(2_147_483_647.0, [2_147_483_647.0], _)) =
    solve(numeric(d.Maximize, [d.Integer(Some(0), None)], [1.0], 0.0, []))
}

pub fn evaluate_test() {
  d.evaluate(
    d.Sum([
      d.Linear(2.0, 0),
      d.Linear(-1.0, 1),
      d.Constant(1.0),
      d.Constant(0.5),
    ]),
    [3.0, 4.0],
  )
  |> should.equal(Ok(3.5))
  d.evaluate(d.Sum([]), []) |> should.equal(Ok(0.0))
  d.evaluate(d.Sum([d.Linear(0.0, 0)]), [max]) |> should.equal(Ok(0.0))
}

pub fn evaluate_non_finite_is_an_error_test() {
  list.each(
    [
      #(d.Sum([d.Linear(max, 0)]), [2.0]),
      #(d.Sum([d.Linear(max, 0), d.Linear(max, 1)]), [1.0, 1.0]),
      #(d.Sum([d.Constant(max), d.Constant(max)]), []),
      #(d.Sum([d.Linear(max, 0), d.Constant(max)]), [1.0]),
    ],
    fn(input) { d.evaluate(input.0, input.1) |> should.equal(Error(Nil)) },
  )
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
  d.evaluate(expression, [1.0]) |> should.equal(Error(Nil))
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

@external(erlang, "gleam_stdlib", "identity")
fn unchecked(term: a) -> d.Expression

pub fn evaluation_rejects_undecodable_indices_test() {
  list.each([-1, 18_446_744_073_709_551_616], fn(index) {
    d.evaluate(d.Sum([d.Linear(1.0, index)]), [1.0])
    |> should.equal(Error(Nil))
  })
}

pub fn malformed_limits_are_contract_errors_test() {
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

pub fn oversized_limits_are_typed_errors_test() {
  let huge = 18_446_744_073_709_551_616
  d.solve(bounded_model(), d.Limits(None, Some(huge)))
  |> should.equal(Error(d.InvalidNodeLimit))
  d.solve(bounded_model(), d.Limits(Some(#(huge, 0)), None))
  |> should.equal(Error(d.InvalidTimeLimit))
  d.solve(
    bounded_model(),
    d.Limits(Some(#(9_223_372_036_854_775_807, 0)), None),
  )
  |> should.equal(Error(d.InvalidTimeLimit))
  // The 100-year cap is inclusive and solves without overflowing a deadline.
  let assert Ok(d.Optimal(_, _, _)) =
    d.solve(bounded_model(), d.Limits(Some(#(3_153_600_000, 0)), None))
  d.solve(bounded_model(), d.Limits(Some(#(3_153_600_000, 1)), None))
  |> should.equal(Error(d.InvalidTimeLimit))
  // u64::MAX is valid for a node budget even though it exceeds signed i64.
  let assert Ok(d.Optimal(_, _, _)) =
    d.solve(bounded_model(), d.Limits(None, Some(18_446_744_073_709_551_615)))
}

pub fn limits_validate_before_the_model_test() {
  solve_raw_with("invalid model", d.Limits(Some(#(-1, 0)), Some(-1)))
  |> should.equal(Error(d.InvalidTimeLimit))
  solve_raw_with("invalid model", d.Limits(None, Some(-1)))
  |> should.equal(Error(d.InvalidNodeLimit))
  solve_raw_with("invalid model", d.Limits(Some(#(0, 0)), Some(0)))
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
}
