import gleam/float
import gleam/list
import gleeunit/should
import waffle/internal/driver as d
import waffle/internal/model.{Constant, Linear} as m

type Product {
  Chair
  Table
  Missing
}

fn nonnegative() -> d.Domain {
  d.Continuous(d.Finite(0.0), d.Unbounded)
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
  let model =
    m.Model(
      [
        #(Chair, d.Continuous(d.Finite(0.0), d.Finite(2.0))),
        #(Table, nonnegative()),
      ],
      m.Maximize([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
      [m.LessEqual([chair, table], [Constant(4.0)])],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 17.0)
  close_value(solution, Chair, 2.0)
  close_value(solution, Table, 2.0)
  m.value(solution, Missing) |> should.equal(Error(Nil))
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
      list.map(routes, fn(route) { #(#(route.0, route.1), nonnegative()) }),
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
      list.map(items, fn(item) { #(item.0, d.Integer(0, 1)) }),
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

fn base() -> m.Model(Product) {
  m.Model(
    [#(Chair, nonnegative()), #(Table, nonnegative())],
    m.Minimize([]),
    [],
  )
}

pub fn canonical_objective_and_rows_test() {
  let chair = Linear(1.0, Chair)
  let table = Linear(1.0, Table)
  let model =
    m.Model(
      ..base(),
      objective: m.Minimize([
        Linear(2.0, Table),
        chair,
        chair,
        Linear(-2.0, Table),
        Constant(4.0),
      ]),
      constraints: [
        // table + 3 ≥ chair + 5  ⇒  -chair + table ≥ 2
        m.GreaterEqual([table, Constant(3.0)], [chair, Constant(5.0)]),
        m.Equal([chair, Constant(1.0)], [Constant(3.0)]),
        // Terms cancelling across sides leave a constant row.
        m.LessEqual([chair, table], [table, chair]),
      ],
    )
  let assert Ok(ir) = m.compile(model)
  ir.direction |> should.equal(d.Minimize)
  ir.objective |> should.equal([2.0, 0.0])
  ir.offset |> should.equal(4.0)
  ir.rows
  |> should.equal([
    d.Row([#(0, -1.0), #(1, 1.0)], d.GreaterEqual, 2.0),
    d.Row([#(0, 1.0)], d.Equal, 2.0),
    d.Row([], d.LessEqual, 0.0),
  ])
}

pub fn identical_constraints_are_separate_rows_test() {
  let row = m.LessEqual([Linear(1.0, Chair)], [Constant(1.0)])
  let assert Ok(ir) = m.compile(m.Model(..base(), constraints: [row, row]))
  ir.rows
  |> should.equal([
    d.Row([#(0, 1.0)], d.LessEqual, 1.0),
    d.Row([#(0, 1.0)], d.LessEqual, 1.0),
  ])
}

pub fn reference_validation_and_duplicates_test() {
  let model = base()
  list.each([[Linear(1.0, Missing)], [Linear(0.0, Missing)]], fn(terms) {
    m.compile(m.Model(..model, objective: m.Minimize(terms)))
    |> should.equal(Error(m.UnknownVariable(Missing)))
  })
  m.compile(
    m.Model(..model, constraints: [
      m.Equal([Constant(0.0)], [Linear(1.0, Missing)]),
    ]),
  )
  |> should.equal(Error(m.UnknownVariable(Missing)))
  m.compile(
    m.Model(..model, variables: [
      #(Chair, nonnegative()),
      #(Chair, nonnegative()),
    ]),
  )
  |> should.equal(Error(m.DuplicateVariable(Chair)))
}

pub fn explicit_outcomes_and_native_validation_test() {
  let empty: m.Model(Product) = m.Model([], m.Minimize([]), [])
  let assert Ok(m.Optimal(solution)) = m.solve(empty)
  m.objective(solution) |> should.equal(0.0)
  m.solve(m.Model(..empty, constraints: [m.Equal([], [Constant(1.0)])]))
  |> should.equal(Ok(m.Infeasible))
  let model = base()
  m.solve(m.Model(..model, objective: m.Maximize([Linear(1.0, Chair)])))
  |> should.equal(Ok(m.Unbounded))
  m.solve(m.Model(..model, variables: [#(Chair, d.Integer(0, 2_147_483_648))]))
  |> should.equal(Error(m.NativeError(d.InvalidModel(d.InvalidDomain(0)))))
  list.each(
    [d.Integer(2, 1), d.Continuous(d.Finite(2.0), d.Finite(1.0))],
    fn(domain) {
      m.solve(m.Model(..model, variables: [#(Chair, domain)]))
      |> should.equal(Ok(m.Infeasible))
    },
  )
}
