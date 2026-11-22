import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleeunit
import vahvel.{Constant, Difference, Linear, Scaled, Sum, Variable} as m

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
  assert float.loosely_equals(actual, expected, 0.000001)
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
  let model = m.Model(..base(), objective: m.Minimize(Variable(Chair)))
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  assert m.value(solution, Chair) == Ok(0.0)
  assert m.value(solution, Missing) == Error(Nil)
}

pub fn zero_coefficient_reference_creates_variable_test() {
  let model = m.Model(..base(), objective: m.Minimize(Linear(0.0, Chair)))
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  assert m.value(solution, Chair) == Ok(0.0)
}

pub fn keys_can_be_any_value_test() {
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(0.0), Some(1.0)) },
        objective: m.Maximize(
          Sum([Variable(#("north", 1)), Linear(2.0, #("south", 2))]),
        ),
        constraints: [],
      ),
    )
  close_value(solution, #("north", 1), 1.0)
  close_value(solution, #("south", 2), 1.0)
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Binary },
        objective: m.Maximize(Sum([Variable("a"), Linear(2.0, "b")])),
        constraints: [
          m.LessEqual(Sum([Variable("a"), Variable("b")]), Constant(1.0)),
        ],
      ),
    )
  assert m.value(solution, "a") == Ok(0.0)
  assert m.value(solution, "b") == Ok(1.0)
}

pub fn int_keys_are_names_not_columns_test() {
  // The key is data: variable k may take values up to k. Key 7 is referenced
  // first, so it is column 0, yet each key still gets its own bound.
  let model =
    m.Model(
      domain: fn(k) { m.Real(Some(0.0), Some(int.to_float(k))) },
      objective: m.Maximize(Sum([Variable(7), Variable(3)])),
      constraints: [],
    )
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
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
      objective: m.Maximize(Sum([Linear(3.0, Table), Variable(Chair)])),
      constraints: [
        m.LessEqual(Sum([Variable(Chair), Variable(Table)]), Constant(7.5)),
      ],
    )
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
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
    objective: m.Minimize(Sum([Variable(Chair), Variable(Table)])),
  )
}

pub fn integer_domains_span_the_signed_32_bit_range_test() {
  let pin = fn(value) { m.Integer(Some(value), Some(value)) }
  let domain = fn(product) {
    case product {
      Chair -> pin(-2_147_483_648)
      Table | Missing -> pin(2_147_483_647)
    }
  }
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(m.Model(..chair_and_table(), domain:))
  assert m.value(solution, Chair) == Ok(-2_147_483_648.0)
  assert m.value(solution, Table) == Ok(2_147_483_647.0)
  // The driver reports column 1; the error names the key.
  list.each(
    [
      m.Integer(Some(-2_147_483_649), Some(0)),
      m.Integer(Some(0), Some(2_147_483_648)),
      m.Integer(Some(0), Some(9_223_372_036_854_775_808)),
    ],
    fn(domain) {
      assert m.solve(m.Model(..chair_and_table(), domain: only_table(domain)))
        == Error(m.InvalidDomain(Table))
    },
  )
}

pub fn integer_domains_with_missing_bounds_test() {
  let solve_chair = fn(domain, objective, constraint) {
    let assert Ok(m.Optimal(solution, _)) =
      m.solve(
        m.Model(domain: fn(_) { domain }, objective:, constraints: [constraint]),
      )
    m.value(solution, Chair)
  }
  assert solve_chair(
      m.Integer(None, Some(5)),
      m.Minimize(Variable(Chair)),
      m.GreaterEqual(Variable(Chair), Constant(-3.5)),
    )
    == Ok(-3.0)
  assert solve_chair(
      m.Integer(None, None),
      m.Maximize(Variable(Chair)),
      m.LessEqual(Variable(Chair), Constant(7.5)),
    )
    == Ok(7.0)
}

pub fn empty_domains_are_infeasible_test() {
  list.each(
    [m.Integer(Some(2), Some(1)), m.Real(Some(2.0), Some(1.0))],
    fn(domain) {
      assert m.solve(m.Model(..chair_and_table(), domain: only_table(domain)))
        == Ok(m.Infeasible)
    },
  )
}

pub fn nonnegative_domains_preserve_bounds_and_integrality_test() {
  list.each([#(m.NonNegativeReal, 2.5), #(m.NonNegativeInteger, 2.0)], fn(pair) {
    let #(domain, expected) = pair
    let model =
      m.Model(
        domain: fn(_) { domain },
        objective: m.Maximize(Variable(Chair)),
        constraints: [m.LessEqual(Variable(Chair), Constant(2.5))],
      )
    let assert Ok(m.Optimal(solution, _)) = m.solve(model)
    close_value(solution, Chair, expected)
    let assert Ok(m.Optimal(minimum, _)) =
      m.solve(m.Model(..model, objective: m.Minimize(Variable(Chair))))
    close_value(minimum, Chair, 0.0)
    case domain {
      m.NonNegativeInteger -> {
        let assert Ok(m.Optimal(unbounded, _)) =
          m.solve(m.Model(..model, constraints: []))
        close_value(unbounded, Chair, 2_147_483_647.0)
      }
      _ -> {
        assert m.solve(m.Model(..model, constraints: [])) == Ok(m.Unbounded)
      }
    }
  })
}

pub fn real_domain_allows_negative_values_test() {
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(-2.5), Some(3.0)) },
        objective: m.Minimize(Variable(Chair)),
        constraints: [],
      ),
    )
  close_value(solution, Chair, -2.5)
}

// Constraints

pub fn constants_and_terms_on_both_sides_solve_test() {
  let chair = Variable(Chair)
  let table = Variable(Table)
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
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  close_value(solution, Chair, 2.0)
  close_value(solution, Table, 4.0)
  close(m.objective(solution), 12.0)
}

pub fn rows_without_variables_are_checked_directly_test() {
  // Rows whose terms are absent or cancel never reach the solver; Rust checks
  // their constants itself.
  list.each(
    [
      m.Equal(Sum([]), Constant(0.0)),
      m.LessEqual(Constant(0.0), Constant(1.0)),
      m.GreaterEqual(Constant(0.0), Constant(-1.0)),
      m.LessEqual(Variable(Chair), Variable(Chair)),
    ],
    fn(row) {
      let assert Ok(m.Optimal(_, _)) =
        m.solve(m.Model(..base(), constraints: [row]))
    },
  )
  list.each(
    [
      m.Equal(Constant(0.0), Constant(1.0)),
      m.LessEqual(Constant(0.0), Constant(-1.0)),
      m.GreaterEqual(Constant(0.0), Constant(1.0)),
      m.LessEqual(Linear(-0.0, Chair), Constant(-1.0)),
      m.LessEqual(
        Sum([Linear(2.0, Chair), Linear(-2.0, Chair)]),
        Constant(-1.0),
      ),
    ],
    fn(row) {
      assert m.solve(m.Model(..base(), constraints: [row])) == Ok(m.Infeasible)
    },
  )
}

pub fn identical_constraints_are_allowed_test() {
  let row = m.LessEqual(Variable(Chair), Constant(1.0))
  let model =
    m.Model(..base(), objective: m.Maximize(Variable(Chair)), constraints: [
      row,
      row,
    ])
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  close_value(solution, Chair, 1.0)
}

// Expressions

pub fn expressions_are_reusable_test() {
  let revenue = Sum([Linear(5.0, Chair), Linear(4.0, Table)])
  let cost = Sum([Variable(Chair), Linear(2.0, Table), Constant(3.0)])
  let profit = Difference(revenue, cost)
  let hours = Sum([Variable(Chair), Variable(Table)])
  let model =
    m.Model(
      domain: nonnegative,
      objective: m.Maximize(Scaled(0.5, Scaled(2.0, profit))),
      constraints: [
        m.LessEqual(Scaled(2.0, hours), Scaled(2.0, Constant(4.0))),
        m.Equal(Variable(Table), Constant(1.0)),
      ],
    )
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  close_value(solution, Chair, 3.0)
  close_value(solution, Table, 1.0)
  close(m.objective(solution), 11.0)
  assert m.evaluate_solution(profit, solution) == Ok(11.0)
  assert m.evaluate_solution(cost, solution) == Ok(8.0)
  assert m.evaluate_solution(
      Sum([Scaled(2.0, Scaled(-1.0, cost)), Constant(1.0)]),
      solution,
    )
    == Ok(-15.0)
}

pub fn zero_and_empty_scales_test() {
  let expression = Sum([Scaled(0.0, Linear(2.0, Chair)), Scaled(3.0, Sum([]))])
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(m.Model(..base(), objective: m.Minimize(expression)))
  assert m.value(solution, Chair) == Ok(0.0)
  assert m.evaluate_solution(expression, solution) == Ok(0.0)
  assert m.evaluate_solution(Scaled(0.0, Variable(Missing)), solution)
    == Error(m.MissingValue(Missing))
  assert m.solve(
      m.Model(
        ..base(),
        domain: fn(_) { m.Integer(Some(2), Some(1)) },
        objective: m.Minimize(expression),
      ),
    )
    == Ok(m.Infeasible)
}

pub fn constants_sum_in_depth_first_input_order_test() {
  // max + max overflows before − max is added.
  let overflowing =
    Sum([Sum([Constant(max), Constant(max)]), Constant(0.0 -. max)])
  assert m.solve(m.Model(..base(), objective: m.Minimize(overflowing)))
    == Error(m.NonFinite(m.InObjective))
  // max − max + max never leaves the finite range.
  let fine = Sum([Constant(max), Sum([Constant(0.0 -. max), Constant(max)])])
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(m.Model(..base(), objective: m.Minimize(fine)))
  assert m.objective(solution) == max
}

pub fn deep_expressions_test() {
  // A sum accumulated in a fold nests once per step.
  let sum =
    int.range(0, 100_000, Variable(Chair), fn(e, _) {
      Sum([e, Linear(0.0, Chair)])
    })
  let scaled =
    int.range(0, 100_000, Variable(Chair), fn(e, _) { Scaled(1.0, e) })
  let difference_left =
    int.range(0, 100_000, Variable(Chair), fn(e, _) { Difference(e, Sum([])) })
  let difference_right =
    int.range(0, 100_000, Variable(Chair), fn(e, _) {
      Difference(Constant(2.0), e)
    })
  list.each([sum, scaled, difference_left, difference_right], fn(expression) {
    let assert Ok(m.Optimal(solution, _)) =
      m.solve(
        m.Model(
          domain: fn(_) { m.Binary },
          objective: m.Maximize(expression),
          constraints: [m.LessEqual(expression, Constant(1.0))],
        ),
      )
    assert m.objective(solution) == 1.0
    assert m.evaluate_solution(expression, solution) == Ok(1.0)
  })
}

pub fn difference_composes_on_both_sides_test() {
  let expression =
    Difference(
      Sum([Variable(Chair), Constant(7.0)]),
      Difference(Variable(Table), Constant(2.0)),
    )
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(..base(), objective: m.Maximize(expression), constraints: [
        m.Equal(Variable(Table), Constant(3.0)),
        m.LessEqual(
          Difference(Variable(Chair), Constant(1.0)),
          Difference(Constant(5.0), Variable(Table)),
        ),
      ]),
    )
  close_value(solution, Chair, 3.0)
  close_value(solution, Table, 3.0)
  close(m.objective(solution), 9.0)
  assert m.evaluate_solution(expression, solution) == Ok(9.0)
  assert m.evaluate_solution(Scaled(2.0, expression), solution) == Ok(18.0)
  assert m.evaluate_solution(
      Difference(Variable(Missing), Variable(Missing)),
      solution,
    )
    == Error(m.MissingValue(Missing))
}

pub fn difference_preserves_cancelled_and_zero_scaled_references_test() {
  let expression = Difference(Variable(Table), Variable(Table))
  let model = m.Model(..base(), objective: m.Minimize(expression))
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  assert m.value(solution, Table) == Ok(0.0)
  list.each([expression, Scaled(0.0, expression)], fn(expression) {
    assert m.solve(
        m.Model(
          ..model,
          domain: only_table(m.Integer(Some(0), Some(2_147_483_648))),
          objective: m.Minimize(expression),
        ),
      )
      == Error(m.InvalidDomain(Table))
  })
}

pub fn difference_overflow_preserves_location_and_order_test() {
  let expression =
    Difference(Sum([Constant(max), Constant(max)]), Constant(max))
  assert m.solve(m.Model(..base(), objective: m.Minimize(expression)))
    == Error(m.NonFinite(m.InObjective))
  let row = m.Equal(expression, Constant(0.0))
  assert m.solve(m.Model(..base(), constraints: [row]))
    == Error(m.NonFinite(m.InConstraint(0, row)))
  assert m.evaluate_dict(expression, dict.new()) == Error(m.NonFiniteValue)
  assert m.evaluate_dict(Difference(Constant(max), Constant(max)), dict.new())
    == Ok(0.0)
}

// Outcomes and errors

pub fn infeasible_and_unbounded_are_outcomes_without_stats_test() {
  let empty = base()
  let assert Ok(m.Optimal(solution, _)) = m.solve(empty)
  assert m.objective(solution) == 0.0
  let assert Ok(infeasible) =
    m.solve(m.Model(..empty, constraints: [m.Equal(Sum([]), Constant(1.0))]))
  assert infeasible == m.Infeasible
  assert m.stats(infeasible) == None
  let assert Ok(unbounded) =
    m.solve(m.Model(..empty, objective: m.Maximize(Variable(Chair))))
  assert unbounded == m.Unbounded
  assert m.stats(unbounded) == None
}

pub fn solver_proves_infeasibility_test() {
  // Neither model is trivially infeasible, so the backend must prove it.
  assert m.solve(
      m.Model(..base(), objective: m.Minimize(Variable(Chair)), constraints: [
        m.LessEqual(Variable(Chair), Constant(-1.0)),
      ]),
    )
    == Ok(m.Infeasible)
  assert m.solve(
      m.Model(
        domain: fn(_) { m.Integer(Some(0), Some(2)) },
        objective: m.Minimize(Variable(Chair)),
        constraints: [m.Equal(Variable(Chair), Constant(0.5))],
      ),
    )
    == Ok(m.Infeasible)
}

pub fn non_finite_sums_report_location_test() {
  let model = base()
  assert m.solve(
      m.Model(
        ..model,
        objective: m.Minimize(Sum([Constant(max), Constant(max)])),
      ),
    )
    == Error(m.NonFinite(m.InObjective))
  let fine = m.LessEqual(Variable(Chair), Constant(1.0))
  // Moving `-max·chair` across sides makes it `+max·chair`.
  let overflowing = m.LessEqual(Linear(max, Chair), Linear(0.0 -. max, Chair))
  // The error names the constraint as well as its position.
  assert m.solve(m.Model(..model, constraints: [fine, overflowing]))
    == Error(m.NonFinite(m.InConstraint(1, overflowing)))
}

pub fn scaled_overflow_reports_location_test() {
  let expressions = [
    Scaled(2.0, Linear(max, Chair)),
    Scaled(2.0, Constant(max)),
    Scaled(max, Scaled(2.0, Sum([]))),
  ]
  let values = dict.from_list([#(Chair, 0.0)])
  list.each(expressions, fn(expression) {
    assert m.solve(m.Model(..base(), objective: m.Minimize(expression)))
      == Error(m.NonFinite(m.InObjective))
    let row = m.Equal(Sum([]), expression)
    assert m.solve(m.Model(..base(), constraints: [row]))
      == Error(m.NonFinite(m.InConstraint(0, row)))
    assert m.evaluate_dict(expression, values) == Error(m.NonFiniteValue)
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
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(
        domain:,
        objective: m.Maximize(
          Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
        ),
        constraints: [
          m.LessEqual(Sum([Variable(Chair), Variable(Table)]), Constant(4.0)),
        ],
      ),
    )
  solution
}

pub fn solution_values_test() {
  let solution = solved_chairs_and_tables()
  close(m.objective(solution), 17.0)
  let values = m.values(solution)
  assert dict.size(values) == 2
  assert dict.get(values, Chair) == Ok(2.0)
  close_value(solution, Table, 2.0)
}

pub fn evaluate_reports_breakdowns_test() {
  let solution = solved_chairs_and_tables()
  // Chairs contribute 3 · 2.
  let assert Ok(chairs) = m.evaluate_solution(Linear(3.0, Chair), solution)
  close(chairs, 6.0)
  assert m.evaluate_solution(Sum([]), solution) == Ok(0.0)
}

pub fn evaluate_errors_test() {
  let solution = solved_chairs_and_tables()
  assert m.evaluate_solution(
      Sum([Variable(Chair), Variable(Missing)]),
      solution,
    )
    == Error(m.MissingValue(Missing))
  assert m.evaluate_solution(Linear(max, Chair), solution)
    == Error(m.NonFiniteValue)
}

pub fn evaluation_combines_coefficients_before_multiplying_test() {
  let expression = Sum([Linear(1.0e308, Chair), Linear(-1.0e308, Chair)])
  let assert Ok(m.Optimal(solution, _)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Real(Some(2.0), Some(2.0)) },
        objective: m.Minimize(expression),
        constraints: [],
      ),
    )
  assert m.objective(solution) == 0.0
  assert m.evaluate_solution(expression, solution) == Ok(0.0)
  assert m.evaluate_solution(Scaled(1.0, expression), solution) == Ok(0.0)
}

// Evaluation against supplied values

pub fn evaluate_with_a_function_test() {
  // Values need not respect any domain: fractional chairs are fine.
  let lookup = fn(product) {
    case product {
      Chair -> Ok(1.5)
      Table -> Ok(2.0)
      Missing -> Error(Nil)
    }
  }
  assert m.evaluate(
      Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(1.0)]),
      lookup,
    )
    == Ok(9.5)
  assert m.evaluate(Variable(Missing), lookup) == Error(m.MissingValue(Missing))
}

pub fn evaluate_dict_ignores_unreferenced_entries_test() {
  let plan = dict.from_list([#(Chair, 2.0), #(Table, 3.0), #(Missing, 9.0)])
  assert m.evaluate_dict(Difference(Linear(4.0, Table), Variable(Chair)), plan)
    == Ok(10.0)
  assert m.evaluate_dict(Variable(Table), dict.new())
    == Error(m.MissingValue(Table))
}

pub fn evaluate_reports_the_first_missing_reference_test() {
  let plan = dict.from_list([#(Chair, 1.0)])
  // Depth-first: the nested Table comes before Missing.
  assert m.evaluate_dict(
      Sum([Variable(Chair), Sum([Variable(Table)]), Variable(Missing)]),
      plan,
    )
    == Error(m.MissingValue(Table))
  // A difference visits its left side first.
  assert m.evaluate_dict(Difference(Variable(Missing), Variable(Table)), plan)
    == Error(m.MissingValue(Missing))
  // Cancelled and zero-scaled references still need values.
  assert m.evaluate_dict(Difference(Variable(Table), Variable(Table)), plan)
    == Error(m.MissingValue(Table))
  assert m.evaluate_dict(Scaled(0.0, Variable(Table)), plan)
    == Error(m.MissingValue(Table))
}

pub fn constants_need_no_values_test() {
  let nothing = fn(_) { Error(Nil) }
  assert m.evaluate(Sum([Constant(2.0), Scaled(3.0, Sum([]))]), nothing)
    == Ok(2.0)
  assert m.evaluate(Sum([]), nothing) == Ok(0.0)
}

pub fn missing_values_take_precedence_over_overflow_test() {
  let overflowing = Sum([Constant(max), Constant(max), Variable(Missing)])
  assert m.evaluate_dict(overflowing, dict.new())
    == Error(m.MissingValue(Missing))
  assert m.evaluate_dict(overflowing, dict.from_list([#(Missing, 0.0)]))
    == Error(m.NonFiniteValue)
}

pub fn supplied_values_can_overflow_test() {
  let plan = dict.from_list([#(Chair, max)])
  assert m.evaluate_dict(Linear(2.0, Chair), plan) == Error(m.NonFiniteValue)
  assert m.evaluate_dict(Sum([Linear(2.0, Chair), Linear(-1.0, Chair)]), plan)
    == Ok(max)
}

pub fn overrides_compose_with_solution_values_test() {
  let solution = solved_chairs_and_tables()
  let overrides = dict.from_list([#(Chair, 0.0)])
  let lookup = fn(product) {
    case dict.get(overrides, product) {
      Ok(value) -> Ok(value)
      Error(Nil) -> m.value(solution, product)
    }
  }
  // Table keeps its solved value of 2; Chair is overridden to 0.
  assert m.evaluate(Sum([Linear(3.0, Chair), Linear(2.0, Table)]), lookup)
    == Ok(4.0)
  assert m.evaluate(Variable(Missing), lookup) == Error(m.MissingValue(Missing))
}

// Residuals

pub fn residual_is_lhs_minus_rhs_for_every_relation_test() {
  let plan = dict.get(dict.from_list([#(Chair, 2.0), #(Table, 3.0)]), _)
  let both = Sum([Variable(Chair), Variable(Table)])
  assert m.residual(m.LessEqual(both, Constant(4.0)), plan) == Ok(1.0)
  assert m.residual(m.GreaterEqual(both, Constant(4.0)), plan) == Ok(1.0)
  assert m.residual(m.Equal(Variable(Chair), Constant(2.0)), plan) == Ok(0.0)
  // Constants and variables on both sides: 2 + 1 − (3 + 5).
  assert m.residual(
      m.LessEqual(
        Sum([Variable(Chair), Constant(1.0)]),
        Sum([Variable(Table), Constant(5.0)]),
      ),
      plan,
    )
    == Ok(-5.0)
}

pub fn residual_errors_test() {
  let plan = dict.get(dict.from_list([#(Chair, 1.0)]), _)
  assert m.residual(m.LessEqual(Variable(Chair), Variable(Table)), plan)
    == Error(m.MissingValue(Table))
  // Cancelling sides still reference their variables.
  assert m.residual(m.Equal(Variable(Missing), Variable(Missing)), plan)
    == Error(m.MissingValue(Missing))
  // Moving `-max·chair` across sides makes it `+max·chair`.
  let overflowing = m.LessEqual(Linear(max, Chair), Linear(0.0 -. max, Chair))
  assert m.residual(overflowing, plan) == Error(m.NonFiniteValue)
  assert m.evaluate(Difference(overflowing.lhs, overflowing.rhs), plan)
    == Error(m.NonFiniteValue)
}

pub fn residual_at_a_solution_test() {
  let solution = solved_chairs_and_tables()
  // The hours constraint binds at the optimum.
  let hours =
    m.LessEqual(Sum([Variable(Chair), Variable(Table)]), Constant(4.0))
  let assert Ok(residual) = m.residual(hours, m.value(solution, _))
  close(residual, 0.0)
}

// Statistics

pub fn continuous_stats_test() {
  let model =
    m.Model(
      domain: nonnegative,
      objective: m.Maximize(Sum([Variable(Chair), Variable(Table)])),
      constraints: [
        m.LessEqual(Sum([Variable(Chair), Linear(2.0, Table)]), Constant(4.0)),
        m.LessEqual(Sum([Linear(3.0, Chair), Variable(Table)]), Constant(6.0)),
      ],
    )
  let assert Ok(outcome) = m.solve(model)
  let assert m.Optimal(_, stats) = outcome
  assert m.stats(outcome) == Some(stats)
  assert stats.nodes == 0
  assert stats.iterations > 0
}

pub fn integer_stats_count_branching_test() {
  let assert Ok(m.Optimal(solution, stats)) = m.solve(knapsack())
  close(m.objective(solution), 309.0)
  assert stats.nodes > 0
}

pub fn integer_values_are_exact_test() {
  // microlp reports integer values within its integrality tolerance (here
  // Chair ≈ 4e-7) and can return -0.0; values come back exact and as 0.0.
  let model =
    m.Model(
      domain: fn(_) { m.Binary },
      objective: m.Maximize(Sum([Variable(Chair), Variable(Table)])),
      constraints: [
        m.LessEqual(
          Sum([Linear(2.0, Chair), Linear(2.0, Table)]),
          Constant(3.0),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution, _)) = m.solve(model)
  assert_binary(solution, [Chair, Table])
}

pub fn model_without_variables_has_zero_stats_test() {
  let assert Ok(m.Optimal(_, stats)) = m.solve(base())
  assert stats
    == m.Stats(
      nodes: 0,
      iterations: 0,
      solve_time: duration.nanoseconds(0),
      gap: Some(0.0),
    )
}

// Solve limits

pub fn zero_node_budget_returns_no_fractional_assignment_test() {
  let assert Ok(outcome) =
    m.solve_with(knapsack(), m.Limits(time: None, nodes: Some(0)))
  let assert m.Limited(m.NodeLimit, primal, stats) = outcome
  assert stats.nodes == 0
  assert stats.iterations > 0
  assert m.stats(outcome) == Some(stats)
  // The root relaxation is fractional. A root heuristic may still supply an
  // integral incumbent, but never the relaxation itself.
  case primal {
    Some(solution) -> assert_binary(solution, knapsack_keys())
    None -> {
      assert stats.gap == None
    }
  }
}

fn assert_binary(solution: m.Solution(v), keys: List(v)) {
  list.each(keys, fn(key) {
    let assert Ok(value) = m.value(solution, key)
    assert value == 0.0 || value == 1.0
  })
}

pub fn zero_time_budget_has_stats_but_no_assignment_test() {
  let assert Ok(m.Limited(m.TimeLimit, None, stats)) =
    m.solve_with(
      knapsack(),
      m.Limits(time: Some(duration.nanoseconds(0)), nodes: None),
    )
  assert stats.gap == None
}

pub fn negative_limits_are_rejected_time_first_test() {
  assert m.solve_with(base(), m.Limits(Some(duration.nanoseconds(-1)), None))
    == Error(m.InvalidTimeLimit)
  assert m.solve_with(base(), m.Limits(None, Some(-1)))
    == Error(m.InvalidNodeLimit)
  assert m.solve_with(base(), m.Limits(Some(duration.seconds(-1)), Some(-1)))
    == Error(m.InvalidTimeLimit)
}

pub fn zero_limits_preserve_validation_and_trivial_answers_test() {
  let limits = m.Limits(Some(duration.nanoseconds(0)), Some(0))
  let assert Ok(m.Optimal(solution, stats)) = m.solve_with(base(), limits)
  close(m.objective(solution), 0.0)
  assert stats.gap == Some(0.0)
  assert stats.nodes == 0
  let invalid =
    m.Model(
      ..base(),
      objective: m.Minimize(Sum([Constant(max), Constant(max)])),
    )
  assert m.solve_with(invalid, limits) == Error(m.NonFinite(m.InObjective))
  assert m.solve_with(invalid, m.Limits(None, Some(-1)))
    == Error(m.InvalidNodeLimit)
  assert m.solve_with(
      m.Model(..base(), constraints: [m.Equal(Constant(1.0), Constant(0.0))]),
      limits,
    )
    == Ok(m.Infeasible)
}

// The P01 instance (optimum 309): large enough that presolve and root cuts
// don't settle it, so the search branches and finds incumbents before the
// proof.
const knapsack_items = [
  #(92.0, 23.0),
  #(57.0, 31.0),
  #(49.0, 29.0),
  #(68.0, 44.0),
  #(60.0, 53.0),
  #(43.0, 38.0),
  #(67.0, 63.0),
  #(84.0, 85.0),
  #(87.0, 89.0),
  #(72.0, 82.0),
]

fn knapsack_keys() -> List(Int) {
  list.index_map(knapsack_items, fn(_, i) { i })
}

fn knapsack() -> m.Model(Int) {
  let terms = fn(pick: fn(#(Float, Float)) -> Float) {
    list.index_map(knapsack_items, fn(item, i) { Linear(pick(item), i) })
    |> Sum
  }
  m.Model(
    domain: fn(_) { m.Binary },
    objective: m.Maximize(terms(fn(item) { item.0 })),
    constraints: [m.LessEqual(terms(fn(item) { item.1 }), Constant(165.0))],
  )
}

// The smallest node budget at which `model` stops with an unproven incumbent.
// Searching keeps tests independent of the backend's branching order; a
// fixture that is proven before any budget yields an incumbent fails here.
fn incumbent_budget(model: m.Model(v), nodes: Int) -> Int {
  case m.solve_with(model, m.Limits(None, Some(nodes))) {
    Ok(m.Limited(m.NodeLimit, Some(_), _)) -> nodes
    outcome -> {
      let assert Ok(m.Limited(m.NodeLimit, None, _)) = outcome
      incumbent_budget(model, nodes + 1)
    }
  }
}

pub fn explicit_unlimited_and_generous_time_match_unlimited_solve_test() {
  let model = knapsack()
  let assert Ok(m.Optimal(expected, _)) = m.solve(model)
  list.each(
    [m.Limits(None, None), m.Limits(Some(duration.seconds(60)), None)],
    fn(limits) {
      let assert Ok(outcome) = m.solve_with(model, limits)
      let assert m.Optimal(actual, stats) = outcome
      assert m.values(actual) == m.values(expected)
      assert m.objective(actual) == m.objective(expected)
      assert stats.gap == Some(0.0)
      assert m.stats(outcome) == Some(stats)
    },
  )
}

pub fn zero_nodes_allow_continuous_and_root_integral_optima_test() {
  list.each([m.NonNegativeReal, m.NonNegativeInteger], fn(domain) {
    let model =
      m.Model(
        domain: fn(_) { domain },
        objective: m.Minimize(Variable(Chair)),
        constraints: [m.GreaterEqual(Variable(Chair), Constant(2.0))],
      )
    let assert Ok(m.Optimal(solution, stats)) =
      m.solve_with(model, m.Limits(None, Some(0)))
    close_value(solution, Chair, 2.0)
    assert stats.nodes == 0
    assert stats.gap == Some(0.0)
  })
}

pub fn proof_completed_at_the_node_budget_remains_a_proof_test() {
  let model = knapsack()
  let assert Ok(m.Optimal(expected, unlimited)) = m.solve(model)
  assert unlimited.nodes > 0
  let assert Ok(m.Optimal(solution, stats)) =
    m.solve_with(model, m.Limits(None, Some(unlimited.nodes)))
  assert m.values(solution) == m.values(expected)
  assert stats.nodes == unlimited.nodes
  let assert Ok(m.Limited(m.NodeLimit, _, _)) =
    m.solve_with(model, m.Limits(None, Some(unlimited.nodes - 1)))
}

pub fn both_limits_report_the_backend_stop_reason_test() {
  let assert Ok(m.Limited(m.TimeLimit, None, _)) =
    m.solve_with(knapsack(), m.Limits(Some(duration.seconds(0)), Some(100)))
  let assert Ok(m.Limited(m.NodeLimit, _, _)) =
    m.solve_with(knapsack(), m.Limits(Some(duration.seconds(60)), Some(0)))
  Nil
}

pub fn limits_preserve_infeasible_and_unbounded_answers_test() {
  let infeasible =
    m.Model(
      ..base(),
      domain: fn(_) { m.Real(Some(3.0), Some(2.0)) },
      objective: m.Minimize(Variable(Chair)),
    )
  assert m.solve_with(infeasible, m.Limits(Some(duration.seconds(0)), Some(0)))
    == Ok(m.Infeasible)
  let unbounded = m.Model(..base(), objective: m.Maximize(Variable(Chair)))
  assert m.solve_with(unbounded, m.Limits(None, Some(0))) == Ok(m.Unbounded)
}

// The offset never reaches the backend, so every shift of one model finds the
// same incumbent and bound at the same budget; only the gap's denominator,
// Vahvel's full objective, changes.
pub fn limited_incumbent_is_queryable_and_gap_uses_full_objective_test() {
  let model = knapsack()
  let assert m.Maximize(objective) = model.objective
  let absolute_gap = fn(solution, stats: m.Stats) {
    let assert Some(gap) = stats.gap
    gap *. float.max(float.absolute_value(m.objective(solution)), 1.0)
  }
  list.each([1.0, -1.0], fn(sign) {
    let expression = fn(offset) {
      Sum([Scaled(sign, objective), Constant(offset)])
    }
    let shifted = fn(offset) {
      let objective = case sign {
        1.0 -> m.Maximize(expression(offset))
        _ -> m.Minimize(expression(offset))
      }
      m.Model(..model, objective: objective)
    }
    let nodes = incumbent_budget(shifted(0.0), 0)
    let limited = fn(offset) {
      let assert Ok(outcome) =
        m.solve_with(shifted(offset), m.Limits(None, Some(nodes)))
      let assert m.Limited(m.NodeLimit, Some(solution), stats) = outcome
      assert m.stats(outcome) == Some(stats)
      assert stats.nodes <= nodes
      let assert Ok(evaluated) =
        m.evaluate_solution(expression(offset), solution)
      close(evaluated, m.objective(solution))
      #(solution, stats)
    }
    let #(unshifted, unshifted_stats) = limited(0.0)
    assert_binary(unshifted, knapsack_keys())
    list.each(model.constraints, fn(constraint) {
      let assert Ok(residual) = m.residual(constraint, m.value(unshifted, _))
      assert residual <=. 0.000001
    })
    let unshifted_gap = absolute_gap(unshifted, unshifted_stats)
    assert unshifted_gap >. 0.0
    list.each([-18.0, 100.0], fn(offset) {
      let #(solution, stats) = limited(offset)
      assert m.values(solution) == m.values(unshifted)
      close(m.objective(solution), m.objective(unshifted) +. offset)
      close(absolute_gap(solution, stats), unshifted_gap)
    })
  })
}

pub fn rounded_zero_gap_does_not_claim_optimality_test() {
  let model = knapsack()
  let assert m.Maximize(objective) = model.objective
  let shifted =
    m.Model(..model, objective: m.Maximize(Sum([objective, Constant(1.0e100)])))
  let nodes = incumbent_budget(model, 0)
  let assert Ok(m.Limited(m.NodeLimit, Some(_), stats)) =
    m.solve_with(shifted, m.Limits(None, Some(nodes)))
  assert stats.gap == Some(0.0)
}

pub fn zero_time_continuous_solve_exposes_no_partial_iterate_test() {
  let model = m.Model(..knapsack(), domain: fn(_) { m.NonNegativeReal })
  let assert Ok(m.Limited(m.TimeLimit, None, stats)) =
    m.solve_with(model, m.Limits(Some(duration.nanoseconds(0)), None))
  assert stats.gap == None
}

pub fn oversized_limits_are_rejected_test() {
  let huge = 18_446_744_073_709_551_616
  assert m.solve_with(base(), m.Limits(None, Some(huge)))
    == Error(m.InvalidNodeLimit)
  assert m.solve_with(base(), m.Limits(Some(duration.seconds(huge)), None))
    == Error(m.InvalidTimeLimit)
  // The 100-year cap is inclusive and reaches the backend without overflowing
  // its deadline.
  let cap = duration.seconds(3_153_600_000)
  let assert Ok(m.Optimal(_, _)) =
    m.solve_with(chair_and_table(), m.Limits(Some(cap), None))
  assert m.solve_with(
      chair_and_table(),
      m.Limits(Some(duration.add(cap, duration.nanoseconds(1))), None),
    )
    == Error(m.InvalidTimeLimit)
  // u64::MAX is a valid node budget even though it exceeds signed i64.
  let assert Ok(m.Optimal(_, _)) =
    m.solve_with(
      chair_and_table(),
      m.Limits(None, Some(18_446_744_073_709_551_615)),
    )
  Nil
}

pub fn nonfinite_optimal_objective_is_a_failure_test() {
  // Coefficient and constant are finite, but the solver's objective plus the
  // constant overflows.
  let model =
    m.Model(
      domain: fn(_) { m.Real(Some(1.0), Some(1.0)) },
      objective: m.Minimize(Sum([Linear(1.0e308, Chair), Constant(1.0e308)])),
      constraints: [],
    )
  let assert Error(m.SolverFailure(_)) = m.solve(model)
  Nil
}

pub fn nonfinite_limited_objective_remains_a_failure_test() {
  let model = knapsack()
  let assert m.Maximize(objective) = model.objective
  // Every incumbent takes an item, so it is worth at least 4e306 and adding
  // `max` overflows. The offset alone doesn't change the backend's search.
  let huge =
    m.Model(
      ..model,
      objective: m.Maximize(Scaled(1.0e305, objective)),
      constraints: [
        m.GreaterEqual(Sum(list.map(knapsack_keys(), Variable)), Constant(1.0)),
        ..model.constraints
      ],
    )
  let nodes = incumbent_budget(huge, 0)
  let overflowing =
    m.Model(
      ..huge,
      objective: m.Maximize(Sum([Scaled(1.0e305, objective), Constant(max)])),
    )
  let assert Error(m.SolverFailure(_)) =
    m.solve_with(overflowing, m.Limits(None, Some(nodes)))
}
