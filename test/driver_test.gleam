import gleam/float
import gleam/list
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

fn bounded_model() -> d.Model {
  d.Model(
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
    d.Model(
      d.Maximize,
      [
        d.Continuous(d.Finite(0.0), d.Finite(2.0)),
        d.Continuous(d.Finite(0.0), d.Unbounded),
      ],
      [3.0, 2.0],
      7.0,
      [d.Row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 4.0)],
    ),
    [2.0, 2.0],
    17.0,
  )
}

pub fn minimize_equal_and_greater_equal_with_offset_test() {
  assert_assignment(
    d.Model(
      d.Minimize,
      [
        d.Continuous(d.Unbounded, d.Unbounded),
        d.Continuous(d.Unbounded, d.Unbounded),
      ],
      [1.0, 2.0],
      -5.0,
      [
        d.Row([#(0, 1.0)], d.GreaterEqual, 2.0),
        d.Row([#(1, 1.0)], d.Equal, 1.0),
      ],
    ),
    [2.0, 1.0],
    -1.0,
  )
}

pub fn integer_is_not_relaxed_test() {
  assert_assignment(
    d.Model(d.Maximize, [d.Integer(0, 10)], [1.0], -2.0, [
      d.Row([#(0, 2.0)], d.LessEqual, 9.0),
    ]),
    [4.0],
    2.0,
  )
}

pub fn binary_bounds_test() {
  assert_assignment(
    d.Model(d.Maximize, [d.Integer(0, 1), d.Integer(0, 1)], [1.0, 2.0], 0.0, [
      d.Row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 1.0),
    ]),
    [0.0, 1.0],
    2.0,
  )
}

pub fn mixed_integer_model_test() {
  assert_assignment(
    d.Model(
      d.Maximize,
      [d.Continuous(d.Finite(0.0), d.Unbounded), d.Integer(0, 3)],
      [1.0, 2.0],
      0.0,
      [
        d.Row([#(0, 1.0), #(1, 1.0)], d.LessEqual, 4.0),
        d.Row([#(0, 2.0), #(1, 1.0)], d.GreaterEqual, 2.0),
      ],
    ),
    [1.0, 3.0],
    7.0,
  )
}

pub fn infeasible_model_test() {
  let model = bounded_model()
  d.solve(d.Model(..model, rows: [d.Row([#(0, 1.0)], d.GreaterEqual, 20.0)]))
  |> should.equal(Ok(d.Infeasible))
}

pub fn integer_infeasible_test() {
  d.solve(
    d.Model(d.Minimize, [d.Integer(0, 2)], [1.0], 0.0, [
      d.Row([#(0, 1.0)], d.Equal, 0.5),
    ]),
  )
  |> should.equal(Ok(d.Infeasible))
}

pub fn unbounded_model_test() {
  d.solve(
    d.Model(
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
    d.Model(
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
    d.Model(d.Minimize, [d.Integer(-3, -1)], [1.0], 0.0, []),
    [-3.0],
    -3.0,
  )
}

pub fn integer_bound_endpoints_test() {
  assert_assignment(
    d.Model(
      d.Minimize,
      [
        d.Integer(-2_147_483_648, -2_147_483_648),
        d.Integer(2_147_483_647, 2_147_483_647),
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
    assert_assignment(d.Model(direction, [], [], 7.0, []), [], 7.0)
  })
}

pub fn constant_rows_test() {
  let valid = [
    d.Row([], d.Equal, 0.0),
    d.Row([], d.LessEqual, 1.0),
    d.Row([], d.GreaterEqual, -1.0),
  ]
  assert_assignment(d.Model(d.Minimize, [], [], 3.0, valid), [], 3.0)
  let model = bounded_model()
  assert_assignment(d.Model(..model, rows: valid), [0.0], 0.0)
  list.each(
    [
      d.Row([], d.Equal, 1.0),
      d.Row([], d.LessEqual, -1.0),
      d.Row([], d.GreaterEqual, 1.0),
    ],
    fn(row) {
      d.solve(d.Model(d.Minimize, [], [], 0.0, [row]))
      |> should.equal(Ok(d.Infeasible))
      d.solve(d.Model(..model, rows: [row]))
      |> should.equal(Ok(d.Infeasible))
    },
  )
}

pub fn objective_dimension_validation_test() {
  let model = bounded_model()
  list.each([[], [1.0, 2.0]], fn(objective) {
    assert_invalid(d.Model(..model, objective: objective), d.InvalidObjective)
  })
  assert_invalid(d.Model(d.Minimize, [], [1.0], 0.0, []), d.InvalidObjective)
}

pub fn invalid_indices_test() {
  let model = bounded_model()
  list.each([-1, 1, 9_223_372_036_854_775_808], fn(index) {
    assert_invalid(
      d.Model(..model, rows: [d.Row([#(index, 1.0)], d.Equal, 0.0)]),
      d.InvalidRow(0),
    )
  })
}

pub fn noncanonical_rows_test() {
  let model =
    d.Model(d.Minimize, [d.Integer(0, 1), d.Integer(0, 1)], [1.0, 1.0], 0.0, [])
  list.each(
    [
      [#(0, 1.0), #(0, 2.0)],
      [#(1, 1.0), #(0, 1.0)],
      [#(0, 0.0)],
      [#(0, -0.0)],
    ],
    fn(terms) {
      assert_invalid(
        d.Model(..model, rows: [d.Row(terms, d.LessEqual, 1.0)]),
        d.InvalidRow(0),
      )
    },
  )
}

pub fn integer_bounds_outside_32_bits_test() {
  let model = bounded_model()
  list.each(
    [
      d.Integer(-2_147_483_649, 0),
      d.Integer(0, 2_147_483_648),
      d.Integer(0, 9_223_372_036_854_775_808),
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
      d.Integer(2, 1),
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
    d.Integer(0, 1),
    d.Integer(0, 1),
    d.Integer(0, 2_147_483_648),
  ]
  assert_invalid(
    d.Model(d.Minimize, domains, [1.0, 1.0, 1.0], 0.0, []),
    d.InvalidDomain(2),
  )
  let model =
    d.Model(d.Minimize, [d.Integer(0, 1)], [1.0], 0.0, [
      d.Row([#(0, 1.0)], d.LessEqual, 1.0),
      d.Row([#(0, 1.0)], d.GreaterEqual, 0.0),
      d.Row([#(5, 1.0)], d.Equal, 0.0),
    ])
  assert_invalid(model, d.InvalidRow(2))
}

pub fn validates_whole_model_before_infeasibility_test() {
  let model = bounded_model()
  assert_invalid(
    d.Model(..model, rows: [
      d.Row([], d.Equal, 1.0),
      d.Row([#(1, 1.0)], d.Equal, 0.0),
    ]),
    d.InvalidRow(1),
  )
  assert_invalid(
    d.Model(..model, variables: [d.Integer(2, 1)], rows: [
      d.Row([#(1, 1.0)], d.Equal, 0.0),
    ]),
    d.InvalidRow(0),
  )
}

pub fn objective_overflow_is_a_solver_error_test() {
  let model =
    d.Model(
      d.Minimize,
      [d.Continuous(d.Finite(1.0), d.Finite(1.0))],
      [1.0e308],
      1.0e308,
      [],
    )
  let assert Error(d.SolverFailure(_)) = d.solve(model)
}

@external(erlang, "nif", "driver_solve")
fn solve_raw(model: a) -> Result(d.Outcome, d.DriverError)

pub fn malformed_term_is_a_model_error_test() {
  solve_raw("not a model")
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
  solve_raw(#(1, 2, 3))
  |> should.equal(Error(d.InvalidModel(d.MalformedModel)))
}
