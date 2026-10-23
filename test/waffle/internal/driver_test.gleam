import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import waffle/internal/driver as d

fn assert_assignment(model: d.Model, values: List(Float), objective: Float) {
  let assert Ok(d.Optimal(actual_objective, actual_values)) = d.solve(model)
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
  let terms = list.index_map(objective, fn(c, i) { #(i, c) })
  d.Model(direction, variables, d.Expression(terms, [offset]), rows)
}

/// `Σ terms relation rhs`.
fn row(terms: List(#(Int, Float)), relation: d.Relation, rhs: Float) -> d.Row {
  d.Row(d.Expression(terms, []), relation, d.Expression([], [rhs]))
}

const max = 1.7976931348623157e308

fn bounded_model() -> d.Model {
  numeric(
    d.Minimize,
    [d.Continuous(d.Finite(0.0), d.Finite(10.0))],
    [1.0],
    0.0,
    [],
  )
}

fn assert_invalid(model: d.Model, reason: d.InvalidReason) {
  d.solve(model) |> should.equal(Error(d.InvalidModel(reason)))
}

pub fn continuous_maximize_with_offset_test() {
  assert_assignment(
    numeric(
      d.Maximize,
      [
        d.Continuous(d.Finite(0.0), d.Finite(2.0)),
        d.Continuous(d.Finite(0.0), d.Unbounded),
      ],
      [3.0, 2.0],
      7.0,
      [row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 4.0)],
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
        d.Continuous(d.Unbounded, d.Unbounded),
        d.Continuous(d.Unbounded, d.Unbounded),
      ],
      [1.0, 2.0],
      -5.0,
      [
        row([#(0, 1.0)], d.GreaterEqual, 2.0),
        row([#(1, 1.0)], d.Equal, 1.0),
      ],
    ),
    [2.0, 1.0],
    -1.0,
  )
}

pub fn integer_is_not_relaxed_test() {
  assert_assignment(
    numeric(d.Maximize, [integer(0, 10)], [1.0], -2.0, [
      row([#(0, 2.0)], d.LessEqual, 9.0),
    ]),
    [4.0],
    2.0,
  )
}

pub fn binary_bounds_test() {
  assert_assignment(
    numeric(d.Maximize, [integer(0, 1), integer(0, 1)], [1.0, 2.0], 0.0, [
      row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 1.0),
    ]),
    [0.0, 1.0],
    2.0,
  )
}

pub fn mixed_integer_model_test() {
  assert_assignment(
    numeric(
      d.Maximize,
      [d.Continuous(d.Finite(0.0), d.Unbounded), integer(0, 3)],
      [1.0, 2.0],
      0.0,
      [
        row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 4.0),
        row([#(0, 2.0), #(1, 1.0)], d.GreaterEqual, 2.0),
      ],
    ),
    [1.0, 3.0],
    7.0,
  )
}

pub fn infeasible_model_test() {
  let model = bounded_model()
  d.solve(d.Model(..model, rows: [row([#(0, 1.0)], d.GreaterEqual, 20.0)]))
  |> should.equal(Ok(d.Infeasible))
}

pub fn integer_infeasible_test() {
  d.solve(
    numeric(d.Minimize, [integer(0, 2)], [1.0], 0.0, [
      row([#(0, 1.0)], d.Equal, 0.5),
    ]),
  )
  |> should.equal(Ok(d.Infeasible))
}

pub fn unbounded_model_test() {
  d.solve(
    numeric(
      d.Maximize,
      [d.Continuous(d.Finite(0.0), d.Unbounded)],
      [1.0],
      0.0,
      [],
    ),
  )
  |> should.equal(Ok(d.UnboundedProblem))
}

pub fn unconstrained_bounded_model_test() {
  assert_assignment(bounded_model(), [0.0], 0.0)
}

pub fn negative_continuous_domain_test() {
  assert_assignment(
    numeric(
      d.Maximize,
      [d.Continuous(d.Unbounded, d.Finite(-2.0))],
      [1.0],
      0.0,
      [],
    ),
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
      d.solve(numeric(d.Minimize, [], [], 0.0, [row]))
      |> should.equal(Ok(d.Infeasible))
      d.solve(d.Model(..model, rows: [row]))
      |> should.equal(Ok(d.Infeasible))
    },
  )
}

pub fn objective_index_validation_test() {
  let model = bounded_model()
  list.each([1, -1], fn(index) {
    assert_invalid(
      d.Model(..model, objective: d.Expression([#(index, 1.0)], [])),
      d.InvalidObjective,
    )
  })
  assert_invalid(numeric(d.Minimize, [], [1.0], 0.0, []), d.InvalidObjective)
}

pub fn invalid_indices_test() {
  let model = bounded_model()
  list.each([-1, 1, 9_223_372_036_854_775_808], fn(index) {
    assert_invalid(
      d.Model(..model, rows: [row([#(index, 1.0)], d.Equal, 0.0)]),
      d.InvalidRow(0),
    )
  })
}

fn continuous(lower: Float, upper: Float) -> d.Domain {
  d.Continuous(d.Finite(lower), d.Finite(upper))
}

pub fn rows_are_canonicalized_test() {
  let x = fn(c) { #(0, c) }
  let y = fn(c) { #(1, c) }
  let maximize_x = fn(rows) {
    numeric(
      d.Maximize,
      [continuous(0.0, 10.0), continuous(0.0, 10.0)],
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
        d.Expression([x(1.0)], [3.0]),
        d.LessEqual,
        d.Expression([y(1.0)], [5.0]),
      ),
      row([y(1.0)], d.Equal, 1.0),
    ]),
    [3.0, 1.0],
    3.0,
  )
  // Zero and cancelling coefficients leave a constant row: 0 ≤ -1.
  list.each([[x(0.0)], [x(-0.0)], [x(2.0), x(-2.0)]], fn(terms) {
    d.solve(maximize_x([row(terms, d.LessEqual, -1.0)]))
    |> should.equal(Ok(d.Infeasible))
  })
  // Terms cancelling across sides: x ≤ x.
  assert_assignment(
    maximize_x([
      d.Row(d.Expression([x(1.0)], []), d.LessEqual, d.Expression([x(1.0)], [])),
    ]),
    [10.0, 0.0],
    10.0,
  )
}

pub fn objective_is_canonicalized_test() {
  let model =
    d.Model(
      d.Maximize,
      [continuous(0.0, 2.0), continuous(0.0, 2.0)],
      d.Expression([#(1, 1.0), #(0, 2.0), #(1, -1.0), #(0, 1.0)], [3.0, 4.0]),
      [],
    )
  // 3x + 0y + 7
  assert_assignment(model, [2.0, 0.0], 13.0)
}

pub fn non_finite_sums_are_reported_test() {
  let model = bounded_model()
  list.each(
    [
      d.Expression([#(0, max), #(0, max)], []),
      d.Expression([], [max, max]),
      d.Expression([], [0.0 -. max, 0.0 -. max]),
    ],
    fn(objective) {
      assert_invalid(
        d.Model(..model, objective: objective),
        d.NonFiniteObjective,
      )
    },
  )
  let fine = row([#(0, 1.0)], d.LessEqual, 1.0)
  list.each(
    [
      row([#(0, max), #(0, max)], d.LessEqual, 0.0),
      // Moving `-max·x` across sides makes it `+max·x`.
      d.Row(
        d.Expression([#(0, max)], []),
        d.LessEqual,
        d.Expression([#(0, 0.0 -. max)], []),
      ),
      d.Row(
        d.Expression([], [max]),
        d.LessEqual,
        d.Expression([], [0.0 -. max]),
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
      d.Continuous(d.Finite(2.0), d.Finite(1.0)),
      integer(2, 1),
    ],
    fn(domain) {
      d.solve(d.Model(..model, variables: [domain]))
      |> should.equal(Ok(d.Infeasible))
    },
  )
  // Equal bounds are a single point, not empty.
  assert_assignment(
    d.Model(..model, variables: [d.Continuous(d.Finite(3.0), d.Finite(3.0))]),
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
      row([#(0, 1.0)], d.LessEqual, 1.0),
      row([#(0, 1.0)], d.GreaterEqual, 0.0),
      row([#(5, 1.0)], d.Equal, 0.0),
    ])
  assert_invalid(model, d.InvalidRow(2))
}

pub fn validates_whole_model_before_infeasibility_test() {
  let model = bounded_model()
  assert_invalid(
    d.Model(..model, rows: [
      row([], d.Equal, 1.0),
      row([#(1, 1.0)], d.Equal, 0.0),
    ]),
    d.InvalidRow(1),
  )
  assert_invalid(
    d.Model(..model, variables: [integer(2, 1)], rows: [
      row([#(1, 1.0)], d.Equal, 0.0),
    ]),
    d.InvalidRow(0),
  )
}

pub fn objective_overflow_is_a_solver_error_test() {
  let model =
    numeric(
      d.Minimize,
      [d.Continuous(d.Finite(1.0), d.Finite(1.0))],
      [1.0e308],
      1.0e308,
      [],
    )
  let assert Error(d.SolverFailure(_)) = d.solve(model)
}

@external(erlang, "waffle_nif", "driver_solve")
fn solve_raw(model: a) -> Result(d.Outcome, d.DriverError)

pub fn malformed_term_is_a_model_error_test() {
  solve_raw("not a model")
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
  solve_raw(#(1, 2, 3))
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
}

pub fn integer_without_bounds_test() {
  assert_assignment(
    numeric(d.Minimize, [d.Integer(None, Some(5))], [1.0], 0.0, [
      row([#(0, 1.0)], d.GreaterEqual, -3.5),
    ]),
    [-3.0],
    -3.0,
  )
  assert_assignment(
    numeric(d.Maximize, [d.Integer(None, None)], [1.0], 0.0, [
      row([#(0, 1.0)], d.LessEqual, 7.5),
    ]),
    [7.0],
    7.0,
  )
  d.solve(numeric(d.Minimize, [d.Integer(Some(3), None)], [1.0], 0.0, []))
  |> should.equal(Ok(d.Optimal(3.0, [3.0])))
}

// Documents the backend limit: a missing integer bound is the edge of the
// signed 32-bit range, so an unbounded direction reports that edge as optimal.
pub fn missing_integer_bound_is_the_32_bit_range_test() {
  d.solve(numeric(d.Maximize, [d.Integer(Some(0), None)], [1.0], 0.0, []))
  |> should.equal(Ok(d.Optimal(2_147_483_647.0, [2_147_483_647.0])))
}

pub fn evaluate_test() {
  // 2·3 − 1·4 + 1 + 0.5
  d.evaluate([#(2.0, 3.0), #(-1.0, 4.0)], [1.0, 0.5]) |> should.equal(Ok(3.5))
  d.evaluate([], []) |> should.equal(Ok(0.0))
  d.evaluate([#(0.0, max)], []) |> should.equal(Ok(0.0))
}

pub fn evaluate_non_finite_is_an_error_test() {
  list.each(
    [
      #([#(max, 2.0)], []),
      #([#(max, 1.0), #(max, 1.0)], []),
      #([], [max, max]),
      #([#(max, 1.0)], [max]),
    ],
    fn(input) { d.evaluate(input.0, input.1) |> should.equal(Error(Nil)) },
  )
}
