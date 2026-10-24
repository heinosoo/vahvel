import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleeunit
import gleeunit/should
import waffle.{Constant, Linear, Scaled, Sum} as m

pub fn main() {
  gleeunit.main()
}

type Product {
  Chair
  Table
  Missing
}

fn nonnegative(_: v) -> m.Domain {
  m.Real(Some(0.0), None)
}

fn close(actual: Float, expected: Float) {
  float.loosely_equals(actual, expected, 0.000001) |> should.be_true
}

fn close_value(solution: m.Solution(v), key: v, expected: Float) {
  let assert Ok(actual) = m.value(solution, key)
  close(actual, expected)
}

fn base() -> m.Model(Product) {
  m.Model(domain: nonnegative, objective: m.Minimize(Sum([])), constraints: [])
}

const max = 1.7976931348623157e308

// Variables and keys

pub fn unreferenced_key_is_not_a_variable_test() {
  let model = m.Model(..base(), objective: m.Minimize(Linear(1.0, Chair)))
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  m.value(solution, Chair) |> should.equal(Ok(0.0))
  m.value(solution, Missing) |> should.equal(Error(m.NotInSolution(Missing)))
}

pub fn zero_coefficient_reference_creates_variable_test() {
  let model = m.Model(..base(), objective: m.Minimize(Linear(0.0, Chair)))
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  m.value(solution, Chair) |> should.equal(Ok(0.0))
}

pub fn keys_can_be_any_value_test() {
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(0.0), Some(1.0)) },
        objective: m.Maximize(
          Sum([Linear(1.0, #("north", 1)), Linear(2.0, #("south", 2))]),
        ),
        constraints: [],
      ),
    )
  close_value(solution, #("north", 1), 1.0)
  close_value(solution, #("south", 2), 1.0)
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Binary },
        objective: m.Maximize(Sum([Linear(1.0, "a"), Linear(2.0, "b")])),
        constraints: [
          m.LessEqual(Sum([Linear(1.0, "a"), Linear(1.0, "b")]), Constant(1.0)),
        ],
      ),
    )
  m.value(solution, "a") |> should.equal(Ok(0.0))
  m.value(solution, "b") |> should.equal(Ok(1.0))
}

pub fn int_keys_are_names_not_columns_test() {
  // The key is data: variable k may take values up to k. Key 7 is referenced
  // first, so it is column 0, yet each key still gets its own bound.
  let model =
    m.Model(
      domain: fn(k) { m.Real(Some(0.0), Some(int.to_float(k))) },
      objective: m.Maximize(Sum([Linear(1.0, 7), Linear(1.0, 3)])),
      constraints: [],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, 7, 7.0)
  close_value(solution, 3, 3.0)
  close(m.objective(solution), 10.0)
}

// Domains

pub fn domains_apply_to_their_keys_test() {
  let domain = fn(product) {
    case product {
      Chair -> m.Integer(Some(0), None)
      Table -> m.Real(None, Some(5.0))
      Missing -> m.Integer(Some(0), Some(9))
    }
  }
  // max 3·table + chair  s.t.  chair + table ≤ 7.5. With these domains the
  // optimum is table = 5, chair = 2; swapping them would make it unbounded.
  // Table is referenced first, so it is column 0 and Chair column 1.
  let model =
    m.Model(
      domain:,
      objective: m.Maximize(Sum([Linear(3.0, Table), Linear(1.0, Chair)])),
      constraints: [
        m.LessEqual(
          Sum([Linear(1.0, Chair), Linear(1.0, Table)]),
          Constant(7.5),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, Table, 5.0)
  close_value(solution, Chair, 2.0)
  close(m.objective(solution), 17.0)
}

fn only_table(domain: m.Domain) -> fn(Product) -> m.Domain {
  fn(product) {
    case product {
      Table -> domain
      Chair | Missing -> m.Real(Some(0.0), None)
    }
  }
}

fn chair_and_table() -> m.Model(Product) {
  m.Model(
    ..base(),
    objective: m.Minimize(Sum([Linear(1.0, Chair), Linear(1.0, Table)])),
  )
}

pub fn invalid_integer_domain_names_its_key_test() {
  // The driver reports column 1; the error names the key.
  let domain = only_table(m.Integer(Some(0), Some(2_147_483_648)))
  m.solve(m.Model(..chair_and_table(), domain:))
  |> should.equal(Error(m.InvalidDomain(Table)))
}

pub fn empty_domains_are_infeasible_test() {
  list.each(
    [m.Integer(Some(2), Some(1)), m.Real(Some(2.0), Some(1.0))],
    fn(domain) {
      m.solve(m.Model(..chair_and_table(), domain: only_table(domain)))
      |> should.equal(Ok(m.Infeasible))
    },
  )
}

pub fn nonnegative_domains_preserve_bounds_and_integrality_test() {
  list.each([#(m.NonNegativeReal, 2.5), #(m.NonNegativeInteger, 2.0)], fn(pair) {
    let #(domain, expected) = pair
    let model =
      m.Model(
        domain: fn(_) { domain },
        objective: m.Maximize(m.Variable(Chair)),
        constraints: [m.LessEqual(m.Variable(Chair), Constant(2.5))],
      )
    let assert Ok(m.Optimal(solution)) = m.solve(model)
    close_value(solution, Chair, expected)
    let assert Ok(m.Optimal(minimum)) =
      m.solve(m.Model(..model, objective: m.Minimize(m.Variable(Chair))))
    close_value(minimum, Chair, 0.0)
    case domain {
      m.NonNegativeInteger -> {
        let assert Ok(m.Optimal(unbounded)) =
          m.solve(m.Model(..model, constraints: []))
        close_value(unbounded, Chair, 2_147_483_647.0)
      }
      _ ->
        m.solve(m.Model(..model, constraints: []))
        |> should.equal(Ok(m.Unbounded))
    }
  })
}

pub fn real_domain_allows_negative_values_test() {
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(-2.5), Some(3.0)) },
        objective: m.Minimize(m.Variable(Chair)),
        constraints: [],
      ),
    )
  close_value(solution, Chair, -2.5)
}

// Constraints

pub fn constants_and_terms_on_both_sides_solve_test() {
  let chair = Linear(1.0, Chair)
  let table = Linear(1.0, Table)
  // min 2·chair + table + 4  s.t.  table + 3 ≥ chair + 5,  chair + 1 = 3
  // (duplicates and cancelling terms in the objective are summed)
  let model =
    m.Model(
      ..base(),
      objective: m.Minimize(
        Sum([
          chair,
          table,
          Linear(2.0, Table),
          chair,
          Linear(-2.0, Table),
          Constant(4.0),
        ]),
      ),
      constraints: [
        m.GreaterEqual(Sum([table, Constant(3.0)]), Sum([chair, Constant(5.0)])),
        m.Equal(Sum([chair, Constant(1.0)]), Constant(3.0)),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, Chair, 2.0)
  close_value(solution, Table, 4.0)
  close(m.objective(solution), 12.0)
}

pub fn identical_constraints_are_allowed_test() {
  let row = m.LessEqual(Linear(1.0, Chair), Constant(1.0))
  let model =
    m.Model(..base(), objective: m.Maximize(Linear(1.0, Chair)), constraints: [
      row,
      row,
    ])
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, Chair, 1.0)
}

// Expressions

pub fn expressions_are_reusable_test() {
  let revenue = Sum([Linear(5.0, Chair), Linear(4.0, Table)])
  let cost = Sum([Linear(1.0, Chair), Linear(2.0, Table), Constant(3.0)])
  let profit = Sum([revenue, Scaled(-1.0, cost)])
  let hours = Sum([Linear(1.0, Chair), Linear(1.0, Table)])
  let model =
    m.Model(
      domain: nonnegative,
      objective: m.Maximize(Scaled(0.5, Scaled(2.0, profit))),
      constraints: [
        m.LessEqual(Scaled(2.0, hours), Scaled(2.0, Constant(4.0))),
        m.Equal(Linear(1.0, Table), Constant(1.0)),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, Chair, 3.0)
  close_value(solution, Table, 1.0)
  close(m.objective(solution), 11.0)
  m.evaluate(solution, profit) |> should.equal(Ok(11.0))
  m.evaluate(solution, cost) |> should.equal(Ok(8.0))
  m.evaluate(solution, Sum([Scaled(2.0, Scaled(-1.0, cost)), Constant(1.0)]))
  |> should.equal(Ok(-15.0))
}

pub fn zero_and_empty_scales_test() {
  let expression = Sum([Scaled(0.0, Linear(2.0, Chair)), Scaled(3.0, Sum([]))])
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(..base(), objective: m.Minimize(expression)))
  m.value(solution, Chair) |> should.equal(Ok(0.0))
  m.evaluate(solution, expression) |> should.equal(Ok(0.0))
  m.evaluate(solution, Scaled(0.0, Linear(1.0, Missing)))
  |> should.equal(Error(m.NotInSolution(Missing)))
  m.solve(
    m.Model(
      ..base(),
      domain: fn(_) { m.Integer(Some(2), Some(1)) },
      objective: m.Minimize(expression),
    ),
  )
  |> should.equal(Ok(m.Infeasible))
}

pub fn constants_sum_in_depth_first_input_order_test() {
  // max + max overflows before − max is added.
  let overflowing =
    Sum([Sum([Constant(max), Constant(max)]), Constant(0.0 -. max)])
  m.solve(m.Model(..base(), objective: m.Minimize(overflowing)))
  |> should.equal(Error(m.NonFinite(m.InObjective)))
  // max − max + max never leaves the finite range.
  let fine = Sum([Constant(max), Sum([Constant(0.0 -. max), Constant(max)])])
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(..base(), objective: m.Minimize(fine)))
  m.objective(solution) |> should.equal(max)
}

pub fn deep_expressions_test() {
  // A sum accumulated in a fold nests once per step.
  let sum =
    int.range(0, 100_000, Linear(1.0, Chair), fn(e, _) {
      Sum([e, Linear(0.0, Chair)])
    })
  let scaled =
    int.range(0, 100_000, Linear(1.0, Chair), fn(e, _) { Scaled(1.0, e) })
  let difference_left =
    int.range(0, 100_000, m.Variable(Chair), fn(e, _) {
      m.Difference(e, Sum([]))
    })
  let difference_right =
    int.range(0, 100_000, m.Variable(Chair), fn(e, _) {
      m.Difference(Constant(2.0), e)
    })
  list.each([sum, scaled, difference_left, difference_right], fn(expression) {
    let assert Ok(m.Optimal(solution)) =
      m.solve(
        m.Model(
          domain: fn(_) { m.Binary },
          objective: m.Maximize(expression),
          constraints: [m.LessEqual(expression, Constant(1.0))],
        ),
      )
    m.objective(solution) |> should.equal(1.0)
    m.evaluate(solution, expression) |> should.equal(Ok(1.0))
  })
}

pub fn difference_composes_on_both_sides_test() {
  let expression =
    m.Difference(
      Sum([m.Variable(Chair), Constant(7.0)]),
      m.Difference(m.Variable(Table), Constant(2.0)),
    )
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(..base(), objective: m.Maximize(expression), constraints: [
        m.Equal(m.Variable(Table), Constant(3.0)),
        m.LessEqual(
          m.Difference(m.Variable(Chair), Constant(1.0)),
          m.Difference(Constant(5.0), m.Variable(Table)),
        ),
      ]),
    )
  close_value(solution, Chair, 3.0)
  close_value(solution, Table, 3.0)
  close(m.objective(solution), 9.0)
  m.evaluate(solution, expression) |> should.equal(Ok(9.0))
  m.evaluate(solution, Scaled(2.0, expression)) |> should.equal(Ok(18.0))
  m.evaluate(solution, m.Difference(m.Variable(Missing), m.Variable(Missing)))
  |> should.equal(Error(m.NotInSolution(Missing)))
}

pub fn difference_preserves_cancelled_and_zero_scaled_references_test() {
  let expression = m.Difference(m.Variable(Table), m.Variable(Table))
  let model = m.Model(..base(), objective: m.Minimize(expression))
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  m.value(solution, Table) |> should.equal(Ok(0.0))
  list.each([expression, Scaled(0.0, expression)], fn(expression) {
    m.solve(
      m.Model(
        ..model,
        domain: only_table(m.Integer(Some(0), Some(2_147_483_648))),
        objective: m.Minimize(expression),
      ),
    )
    |> should.equal(Error(m.InvalidDomain(Table)))
  })
}

pub fn difference_overflow_preserves_location_and_order_test() {
  let expression =
    m.Difference(Sum([Constant(max), Constant(max)]), Constant(max))
  m.solve(m.Model(..base(), objective: m.Minimize(expression)))
  |> should.equal(Error(m.NonFinite(m.InObjective)))
  let row = m.Equal(expression, Constant(0.0))
  m.solve(m.Model(..base(), constraints: [row]))
  |> should.equal(Error(m.NonFinite(m.InConstraint(0, row))))
  let assert Ok(m.Optimal(solution)) = m.solve(base())
  m.evaluate(solution, expression) |> should.equal(Error(m.NonFiniteValue))
  m.evaluate(solution, m.Difference(Constant(max), Constant(max)))
  |> should.equal(Ok(0.0))
}

// Outcomes and errors

pub fn explicit_outcomes_test() {
  let empty = base()
  let assert Ok(m.Optimal(solution)) = m.solve(empty)
  m.objective(solution) |> should.equal(0.0)
  m.solve(m.Model(..empty, constraints: [m.Equal(Sum([]), Constant(1.0))]))
  |> should.equal(Ok(m.Infeasible))
  m.solve(m.Model(..empty, objective: m.Maximize(Linear(1.0, Chair))))
  |> should.equal(Ok(m.Unbounded))
}

pub fn non_finite_sums_report_location_test() {
  let model = base()
  m.solve(
    m.Model(..model, objective: m.Minimize(Sum([Constant(max), Constant(max)]))),
  )
  |> should.equal(Error(m.NonFinite(m.InObjective)))
  let fine = m.LessEqual(Linear(1.0, Chair), Constant(1.0))
  // Moving `-max·chair` across sides makes it `+max·chair`.
  let overflowing = m.LessEqual(Linear(max, Chair), Linear(0.0 -. max, Chair))
  // The error names the constraint as well as its position.
  m.solve(m.Model(..model, constraints: [fine, overflowing]))
  |> should.equal(Error(m.NonFinite(m.InConstraint(1, overflowing))))
}

pub fn scaled_overflow_reports_location_test() {
  let expressions = [
    Scaled(2.0, Linear(max, Chair)),
    Scaled(2.0, Constant(max)),
    Scaled(max, Scaled(2.0, Sum([]))),
  ]
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(..base(), objective: m.Minimize(Linear(0.0, Chair))))
  list.each(expressions, fn(expression) {
    m.solve(m.Model(..base(), objective: m.Minimize(expression)))
    |> should.equal(Error(m.NonFinite(m.InObjective)))
    let row = m.Equal(Sum([]), expression)
    m.solve(m.Model(..base(), constraints: [row]))
    |> should.equal(Error(m.NonFinite(m.InConstraint(0, row))))
    m.evaluate(solution, expression) |> should.equal(Error(m.NonFiniteValue))
  })
}

// Solutions

fn solved_chairs_and_tables() -> m.Solution(Product) {
  // max 3·chair + 2·table + 7  s.t.  chair + table ≤ 4,  chair ≤ 2
  let domain = fn(product) {
    case product {
      Chair -> m.Real(Some(0.0), Some(2.0))
      Table | Missing -> m.Real(Some(0.0), None)
    }
  }
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain:,
        objective: m.Maximize(
          Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
        ),
        constraints: [
          m.LessEqual(
            Sum([Linear(1.0, Chair), Linear(1.0, Table)]),
            Constant(4.0),
          ),
        ],
      ),
    )
  solution
}

pub fn solution_values_test() {
  let solution = solved_chairs_and_tables()
  close(m.objective(solution), 17.0)
  let values = m.values(solution)
  dict.size(values) |> should.equal(2)
  dict.get(values, Chair) |> should.equal(Ok(2.0))
  close_value(solution, Table, 2.0)
}

pub fn evaluate_reports_breakdowns_and_slack_test() {
  let solution = solved_chairs_and_tables()
  // Chairs contribute 3 · 2.
  let assert Ok(chairs) = m.evaluate(solution, Linear(3.0, Chair))
  close(chairs, 6.0)
  // Slack of the hours constraint: rhs − lhs.
  let hours = Sum([Linear(1.0, Chair), Linear(1.0, Table)])
  let assert Ok(slack) =
    m.evaluate(solution, Sum([Constant(4.0), Scaled(-1.0, hours)]))
  close(slack, 0.0)
  m.evaluate(solution, Sum([])) |> should.equal(Ok(0.0))
}

pub fn evaluate_errors_test() {
  let solution = solved_chairs_and_tables()
  m.evaluate(solution, Sum([Linear(1.0, Chair), Linear(1.0, Missing)]))
  |> should.equal(Error(m.NotInSolution(Missing)))
  m.evaluate(solution, Linear(max, Chair))
  |> should.equal(Error(m.NonFiniteValue))
}

pub fn evaluation_combines_coefficients_before_multiplying_test() {
  let expression = Sum([Linear(1.0e308, Chair), Linear(-1.0e308, Chair)])
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(2.0), Some(2.0)) },
        objective: m.Minimize(expression),
        constraints: [],
      ),
    )
  m.objective(solution) |> should.equal(0.0)
  m.evaluate(solution, expression) |> should.equal(Ok(0.0))
  m.evaluate(solution, Scaled(1.0, expression)) |> should.equal(Ok(0.0))
}

// Statistics

pub fn continuous_stats_test() {
  let model =
    m.Model(
      domain: nonnegative,
      objective: m.Maximize(Sum([Linear(1.0, Chair), Linear(1.0, Table)])),
      constraints: [
        m.LessEqual(
          Sum([Linear(1.0, Chair), Linear(2.0, Table)]),
          Constant(4.0),
        ),
        m.LessEqual(
          Sum([Linear(3.0, Chair), Linear(1.0, Table)]),
          Constant(6.0),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  let stats = m.stats(solution)
  stats.nodes |> should.equal(0)
  { stats.iterations > 0 } |> should.be_true
}

pub fn integer_stats_count_branching_test() {
  // The relaxation optimum x + y = 1.5 is fractional, so the solver branches.
  let model =
    m.Model(
      domain: fn(_) { m.Integer(Some(0), Some(1)) },
      objective: m.Maximize(Sum([Linear(1.0, Chair), Linear(1.0, Table)])),
      constraints: [
        m.LessEqual(
          Sum([Linear(2.0, Chair), Linear(2.0, Table)]),
          Constant(3.0),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 1.0)
  { m.stats(solution).nodes > 0 } |> should.be_true
}

pub fn model_without_variables_has_zero_stats_test() {
  let assert Ok(m.Optimal(solution)) = m.solve(base())
  m.stats(solution)
  |> should.equal(m.Stats(
    nodes: 0,
    iterations: 0,
    solve_time: duration.nanoseconds(0),
  ))
}
