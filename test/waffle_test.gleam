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
  m.Continuous(Some(0.0), None)
}

fn close(actual: Float, expected: Float) {
  float.loosely_equals(actual, expected, 0.000001) |> should.be_true
}

fn close_value(solution: m.Solution(v), key: v, expected: Float) {
  let assert Ok(actual) = m.value(solution, key)
  close(actual, expected)
}

pub fn production_test() {
  let chair = Linear(1.0, Chair)
  let table = Linear(1.0, Table)
  let domain = fn(product) {
    case product {
      Chair -> m.Continuous(Some(0.0), Some(2.0))
      Table | Missing -> m.Continuous(Some(0.0), None)
    }
  }
  let model =
    m.Model(
      domain:,
      objective: m.Maximize(
        Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
      ),
      constraints: [m.LessEqual(Sum([chair, table]), Constant(4.0))],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 17.0)
  close_value(solution, Chair, 2.0)
  close_value(solution, Table, 2.0)
  // Never referenced, so it is not a variable of this model.
  m.value(solution, Missing) |> should.equal(Error(Nil))
}

pub fn solution_queries_test() {
  let chair = Linear(1.0, Chair)
  let table = Linear(1.0, Table)
  let profit = Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)])
  let hours = m.LessEqual(Sum([chair, table]), Constant(4.0))
  let domain = fn(product) {
    case product {
      Chair -> m.Continuous(Some(0.0), Some(2.0))
      Table | Missing -> m.Continuous(Some(0.0), None)
    }
  }
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(domain:, objective: m.Maximize(profit), constraints: [hours]),
    )
  let values = m.values(solution)
  dict.size(values) |> should.equal(2)
  dict.get(values, Chair) |> should.equal(m.value(solution, Chair))
  // The objective expression evaluates to the objective value.
  let assert Ok(objective) = m.evaluate(solution, profit)
  close(objective, m.objective(solution))
  // Cost breakdown: chairs contribute 3 · 2.
  let assert Ok(chairs) = m.evaluate(solution, Linear(3.0, Chair))
  close(chairs, 6.0)
  // Slack of the hours constraint: rhs − lhs.
  let assert Ok(slack) =
    m.evaluate(
      solution,
      Sum([Constant(4.0), Linear(-1.0, Chair), Linear(-1.0, Table)]),
    )
  close(slack, 0.0)
  m.evaluate(solution, Sum([])) |> should.equal(Ok(0.0))
  m.evaluate(solution, Sum([chair, Linear(1.0, Missing)]))
  |> should.equal(Error(m.NotInSolution(Missing)))
  m.evaluate(solution, Linear(1.7976931348623157e308, Chair))
  |> should.equal(Error(m.NonFiniteValue))
}

type Factory {
  North
  South
}

type Customer {
  East
  West
}

pub fn transportation_with_tuple_keys_and_functional_sets_test() {
  let routes = [
    #(North, East, 1.0),
    #(North, West, 3.0),
    #(South, East, 4.0),
    #(South, West, 1.0),
  ]
  let ship = fn(route: #(Factory, Customer, Float)) {
    Linear(1.0, #(route.0, route.1))
  }
  let supply =
    list.map([#(North, 3.0), #(South, 2.0)], fn(factory) {
      let outgoing =
        routes
        |> list.filter(fn(route) { route.0 == factory.0 })
        |> list.map(ship)
        |> Sum
      m.LessEqual(outgoing, Constant(factory.1))
    })
  let demand =
    list.map([#(East, 2.0), #(West, 3.0)], fn(customer) {
      let incoming =
        routes
        |> list.filter(fn(route) { route.1 == customer.0 })
        |> list.map(ship)
        |> Sum
      m.Equal(incoming, Constant(customer.1))
    })
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(
      domain: nonnegative,
      objective: m.Minimize(
        Sum(
          list.map(routes, fn(route) { Linear(route.2, #(route.0, route.1)) }),
        ),
      ),
      constraints: list.append(supply, demand),
    ))
  close(m.objective(solution), 7.0)
  close_value(solution, #(North, East), 2.0)
  close_value(solution, #(North, West), 1.0)
  close_value(solution, #(South, East), 0.0)
  close_value(solution, #(South, West), 2.0)
}

pub fn binary_selection_is_not_relaxed_test() {
  let items = [#("a", 3.0, 5.0), #("b", 2.0, 3.0), #("c", 2.0, 3.0)]
  let model =
    m.Model(
      domain: fn(_) { m.Binary },
      objective: m.Maximize(
        Sum(list.map(items, fn(item) { Linear(item.2, item.0) })),
      ),
      constraints: [
        m.LessEqual(
          Sum(list.map(items, fn(item) { Linear(item.1, item.0) })),
          Constant(4.0),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 6.0)
  m.value(solution, "a") |> should.equal(Ok(0.0))
  m.value(solution, "b") |> should.equal(Ok(1.0))
  m.value(solution, "c") |> should.equal(Ok(1.0))
}

// Mirrors the `Int` key example in README.md.
pub fn int_keys_test() {
  let items =
    list.index_map([#(3.0, 5.0), #(2.0, 3.0), #(2.0, 3.0)], fn(item, i) {
      #(i, item.0, item.1)
    })
  let value = list.map(items, fn(item) { Linear(item.2, item.0) }) |> Sum
  let weight = list.map(items, fn(item) { Linear(item.1, item.0) }) |> Sum
  let model =
    m.Model(
      domain: fn(_) { m.Binary },
      objective: m.Maximize(value),
      constraints: [m.LessEqual(weight, Constant(4.0))],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 6.0)
  m.value(solution, 0) |> should.equal(Ok(0.0))
  m.value(solution, 1) |> should.equal(Ok(1.0))
  m.value(solution, 2) |> should.equal(Ok(1.0))
  m.value(solution, 3) |> should.equal(Error(Nil))
}

pub fn int_keys_are_names_not_columns_test() {
  // The key is data: variable k may take values up to k. Key 7 is referenced
  // first, so it is column 0, yet each key still gets its own bound.
  let model =
    m.Model(
      domain: fn(k) { m.Continuous(Some(0.0), Some(int.to_float(k))) },
      objective: m.Maximize(Sum([Linear(1.0, 7), Linear(1.0, 3)])),
      constraints: [],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, 7, 7.0)
  close_value(solution, 3, 3.0)
  close(m.objective(solution), 10.0)
}

fn base() -> m.Model(Product) {
  m.Model(domain: nonnegative, objective: m.Minimize(Sum([])), constraints: [])
}

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

pub fn domains_apply_to_their_keys_test() {
  let domain = fn(product) {
    case product {
      Chair -> m.Integer(Some(0), None)
      Table -> m.Continuous(None, Some(5.0))
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

pub fn zero_coefficient_reference_creates_variable_test() {
  let model = m.Model(..base(), objective: m.Minimize(Linear(0.0, Chair)))
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  m.value(solution, Chair) |> should.equal(Ok(0.0))
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

const max = 1.7976931348623157e308

pub fn non_finite_sums_report_location_test() {
  let model = base()
  m.solve(
    m.Model(..model, objective: m.Minimize(Sum([Constant(max), Constant(max)]))),
  )
  |> should.equal(Error(m.NonFinite(m.InObjective)))
  let fine = m.LessEqual(Linear(1.0, Chair), Constant(1.0))
  // Moving `-max·chair` across sides makes it `+max·chair`.
  let overflowing = m.LessEqual(Linear(max, Chair), Linear(0.0 -. max, Chair))
  m.solve(m.Model(..model, constraints: [fine, overflowing]))
  |> should.equal(Error(m.NonFinite(m.InConstraint(1))))
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

pub fn explicit_outcomes_test() {
  let empty = base()
  let assert Ok(m.Optimal(solution)) = m.solve(empty)
  m.objective(solution) |> should.equal(0.0)
  m.solve(m.Model(..empty, constraints: [m.Equal(Sum([]), Constant(1.0))]))
  |> should.equal(Ok(m.Infeasible))
  m.solve(m.Model(..empty, objective: m.Maximize(Linear(1.0, Chair))))
  |> should.equal(Ok(m.Unbounded))
}

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

pub fn domains_test() {
  let model =
    m.Model(
      ..base(),
      objective: m.Minimize(Sum([Linear(1.0, Chair), Linear(1.0, Table)])),
    )
  let only_table = fn(domain) {
    fn(product) {
      case product {
        Table -> domain
        Chair | Missing -> m.Continuous(Some(0.0), None)
      }
    }
  }
  // The driver reports column 1; the error names the key.
  m.solve(
    m.Model(
      ..model,
      domain: only_table(m.Integer(Some(0), Some(2_147_483_648))),
    ),
  )
  |> should.equal(Error(m.InvalidDomain(Table)))
  list.each(
    [m.Integer(Some(2), Some(1)), m.Continuous(Some(2.0), Some(1.0))],
    fn(domain) {
      m.solve(m.Model(..model, domain: only_table(domain)))
      |> should.equal(Ok(m.Infeasible))
    },
  )
}

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
    m.solve(m.Model(..base(), constraints: [m.Equal(Sum([]), expression)]))
    |> should.equal(Error(m.NonFinite(m.InConstraint(0))))
    m.evaluate(solution, expression) |> should.equal(Error(m.NonFiniteValue))
  })
}

pub fn evaluation_combines_coefficients_before_multiplying_test() {
  let expression = Sum([Linear(1.0e308, Chair), Linear(-1.0e308, Chair)])
  let assert Ok(m.Optimal(solution)) =
    m.solve(
      m.Model(
        domain: fn(_) { m.Continuous(Some(2.0), Some(2.0)) },
        objective: m.Minimize(expression),
        constraints: [],
      ),
    )
  m.objective(solution) |> should.equal(0.0)
  m.evaluate(solution, expression) |> should.equal(Ok(0.0))
  m.evaluate(solution, Scaled(1.0, expression)) |> should.equal(Ok(0.0))
}

pub fn deep_expressions_test() {
  // A sum accumulated in a fold nests once per step.
  let sum =
    int.range(0, 100_000, Linear(1.0, Chair), fn(e, _) {
      Sum([e, Linear(0.0, Chair)])
    })
  let scaled =
    int.range(0, 100_000, Linear(1.0, Chair), fn(e, _) { Scaled(1.0, e) })
  list.each([sum, scaled], fn(expression) {
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
