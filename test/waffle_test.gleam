import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import waffle.{Constant, Linear} as m

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
      domain,
      m.Maximize([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
      [m.LessEqual([chair, table], [Constant(4.0)])],
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
  let profit = [Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]
  let hours = m.LessEqual([chair, table], [Constant(4.0)])
  let domain = fn(product) {
    case product {
      Chair -> m.Continuous(Some(0.0), Some(2.0))
      Table | Missing -> m.Continuous(Some(0.0), None)
    }
  }
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(domain, m.Maximize(profit), [hours]))
  let values = m.values(solution)
  dict.size(values) |> should.equal(2)
  dict.get(values, Chair) |> should.equal(m.value(solution, Chair))
  // The objective expression evaluates to the objective value.
  let assert Ok(objective) = m.evaluate(solution, profit)
  close(objective, m.objective(solution))
  // Cost breakdown: chairs contribute 3 · 2.
  let assert Ok(chairs) = m.evaluate(solution, [Linear(3.0, Chair)])
  close(chairs, 6.0)
  // Slack of the hours constraint: rhs − lhs.
  let assert Ok(slack) =
    m.evaluate(solution, [
      Constant(4.0),
      Linear(-1.0, Chair),
      Linear(-1.0, Table),
    ])
  close(slack, 0.0)
  m.evaluate(solution, []) |> should.equal(Ok(0.0))
  m.evaluate(solution, [chair, Linear(1.0, Missing)])
  |> should.equal(Error(m.NotInSolution(Missing)))
  m.evaluate(solution, [Linear(1.7976931348623157e308, Chair)])
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
      m.LessEqual(outgoing, [Constant(factory.1)])
    })
  let demand =
    list.map([#(East, 2.0), #(West, 3.0)], fn(customer) {
      let incoming =
        routes
        |> list.filter(fn(route) { route.1 == customer.0 })
        |> list.map(ship)
      m.Equal(incoming, [Constant(customer.1)])
    })
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(
      nonnegative,
      m.Minimize(
        list.map(routes, fn(route) { Linear(route.2, #(route.0, route.1)) }),
      ),
      list.append(supply, demand),
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
      fn(_) { m.Integer(Some(0), Some(1)) },
      m.Maximize(list.map(items, fn(item) { Linear(item.2, item.0) })),
      [
        m.LessEqual(list.map(items, fn(item) { Linear(item.1, item.0) }), [
          Constant(4.0),
        ]),
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
  let model =
    m.Model(
      fn(_) { m.Integer(Some(0), Some(1)) },
      m.Maximize(list.map(items, fn(item) { Linear(item.2, item.0) })),
      [
        m.LessEqual(list.map(items, fn(item) { Linear(item.1, item.0) }), [
          Constant(4.0),
        ]),
      ],
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
      fn(k) { m.Continuous(Some(0.0), Some(int.to_float(k))) },
      m.Maximize([Linear(1.0, 7), Linear(1.0, 3)]),
      [],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, 7, 7.0)
  close_value(solution, 3, 3.0)
  close(m.objective(solution), 10.0)
}

fn base() -> m.Model(Product) {
  m.Model(nonnegative, m.Minimize([]), [])
}

pub fn constants_and_terms_on_both_sides_solve_test() {
  let chair = Linear(1.0, Chair)
  let table = Linear(1.0, Table)
  // min 2·chair + table + 4  s.t.  table + 3 ≥ chair + 5,  chair + 1 = 3
  // (duplicates and cancelling terms in the objective are summed)
  let model =
    m.Model(
      ..base(),
      objective: m.Minimize([
        chair,
        table,
        Linear(2.0, Table),
        chair,
        Linear(-2.0, Table),
        Constant(4.0),
      ]),
      constraints: [
        m.GreaterEqual([table, Constant(3.0)], [chair, Constant(5.0)]),
        m.Equal([chair, Constant(1.0)], [Constant(3.0)]),
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
    m.Model(domain, m.Maximize([Linear(3.0, Table), Linear(1.0, Chair)]), [
      m.LessEqual([Linear(1.0, Chair), Linear(1.0, Table)], [Constant(7.5)]),
    ])
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close_value(solution, Table, 5.0)
  close_value(solution, Chair, 2.0)
  close(m.objective(solution), 17.0)
}

pub fn zero_coefficient_reference_creates_variable_test() {
  let model = m.Model(..base(), objective: m.Minimize([Linear(0.0, Chair)]))
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  m.value(solution, Chair) |> should.equal(Ok(0.0))
}

pub fn identical_constraints_are_allowed_test() {
  let row = m.LessEqual([Linear(1.0, Chair)], [Constant(1.0)])
  let model =
    m.Model(..base(), objective: m.Maximize([Linear(1.0, Chair)]), constraints: [
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
    m.Model(..model, objective: m.Minimize([Constant(max), Constant(max)])),
  )
  |> should.equal(Error(m.NonFinite(m.InObjective)))
  let fine = m.LessEqual([Linear(1.0, Chair)], [Constant(1.0)])
  // Moving `-max·chair` across sides makes it `+max·chair`.
  let overflowing =
    m.LessEqual([Linear(max, Chair)], [Linear(0.0 -. max, Chair)])
  m.solve(m.Model(..model, constraints: [fine, overflowing]))
  |> should.equal(Error(m.NonFinite(m.InConstraint(1))))
}

pub fn explicit_outcomes_test() {
  let empty = base()
  let assert Ok(m.Optimal(solution)) = m.solve(empty)
  m.objective(solution) |> should.equal(0.0)
  m.solve(m.Model(..empty, constraints: [m.Equal([], [Constant(1.0)])]))
  |> should.equal(Ok(m.Infeasible))
  m.solve(m.Model(..empty, objective: m.Maximize([Linear(1.0, Chair)])))
  |> should.equal(Ok(m.Unbounded))
}

pub fn domains_test() {
  let model =
    m.Model(
      ..base(),
      objective: m.Minimize([Linear(1.0, Chair), Linear(1.0, Table)]),
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
