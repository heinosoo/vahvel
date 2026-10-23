import gleam/float
import gleam/int
import gleam/list
import gleeunit/should
import waffle/internal/driver as d
import waffle/internal/model as m

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

fn close_value(solution: m.Solution(v, c), key: v, expected: Float) {
  let assert Ok(actual) = m.value(solution, key)
  close(actual, expected)
}

pub fn production_affine_and_general_ast_test() {
  let chair = m.variable(Chair)
  let table = m.variable(Table)
  let affine =
    chair
    |> m.scale(3.0)
    |> m.add(m.scale(table, 2.0))
    |> m.add(m.constant(7.0))
  let general =
    m.sum([
      m.multiply(m.constant(3.0), chair),
      m.multiply(table, m.add(m.constant(1.0), m.constant(1.0))),
      m.constant(7.0),
    ])
  let model =
    m.Model(
      [
        #(Chair, d.Continuous(d.Finite(0.0), d.Finite(2.0))),
        #(Table, nonnegative()),
      ],
      d.Maximize,
      affine,
      [m.Constraint("hours", m.add(chair, table), d.LessEqual, m.constant(4.0))],
    )
  m.compile(m.Model(..model, objective: general))
  |> should.equal(m.compile(model))
  list.each([affine, general], fn(objective) {
    let assert Ok(m.Optimal(solution)) =
      m.solve(m.Model(..model, objective: objective))
    close(m.objective(solution), 17.0)
    close_value(solution, Chair, 2.0)
    close_value(solution, Table, 2.0)
    m.value(solution, Missing) |> should.equal(Error(m.UnknownKey))
    m.dual(solution, "hours") |> should.equal(Error(m.DualsUnsupported))
    m.dual(solution, "missing") |> should.equal(Error(m.UnknownKey))
  })
}

type Factory {
  North
  South
}

type Customer {
  East
  West
}

type Row {
  Supply(Factory)
  Demand(Customer)
}

pub fn transportation_with_tuple_keys_and_functional_sets_test() {
  let routes = [
    #(North, East, 1.0),
    #(North, West, 3.0),
    #(South, East, 4.0),
    #(South, West, 1.0),
  ]
  let variables =
    list.map(routes, fn(route) { #(#(route.0, route.1), nonnegative()) })
  let objective =
    routes
    |> list.map(fn(route) {
      m.variable(#(route.0, route.1)) |> m.scale(route.2)
    })
    |> m.sum
  let supply =
    [#(North, 3.0), #(South, 2.0)]
    |> list.map(fn(factory) {
      let lhs =
        routes
        |> list.filter(fn(route) { route.0 == factory.0 })
        |> list.map(fn(route) { m.variable(#(route.0, route.1)) })
        |> m.sum
      m.Constraint(Supply(factory.0), lhs, d.LessEqual, m.constant(factory.1))
    })
  let demand =
    [#(East, 2.0), #(West, 3.0)]
    |> list.map(fn(customer) {
      let lhs =
        routes
        |> list.filter(fn(route) { route.1 == customer.0 })
        |> list.map(fn(route) { m.variable(#(route.0, route.1)) })
        |> m.sum
      m.Constraint(Demand(customer.0), lhs, d.Equal, m.constant(customer.1))
    })
  let assert Ok(m.Optimal(solution)) =
    m.solve(m.Model(
      variables,
      d.Minimize,
      objective,
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
      d.Maximize,
      items
        |> list.map(fn(item) { m.variable(item.0) |> m.scale(item.2) })
        |> m.sum,
      [
        m.Constraint(
          "weight",
          items
            |> list.map(fn(item) { m.variable(item.0) |> m.scale(item.1) })
            |> m.sum,
          d.LessEqual,
          m.constant(4.0),
        ),
      ],
    )
  let assert Ok(m.Optimal(solution)) = m.solve(model)
  close(m.objective(solution), 6.0)
  m.value(solution, "a") |> should.equal(Ok(0.0))
  m.value(solution, "b") |> should.equal(Ok(1.0))
  m.value(solution, "c") |> should.equal(Ok(1.0))
}

fn base() -> m.Model(Product, String) {
  m.Model(
    [#(Chair, nonnegative()), #(Table, nonnegative())],
    d.Minimize,
    m.constant(0.0),
    [],
  )
}

pub fn canonical_rows_offsets_and_both_sides_test() {
  let model = base()
  let chair = m.variable(Chair)
  let table = m.variable(Table)
  let model =
    m.Model(
      ..model,
      objective: m.sum([
        m.scale(table, 2.0),
        chair,
        chair,
        m.scale(table, -2.0),
        m.constant(4.0),
      ]),
      constraints: [
        m.Constraint(
          "row",
          m.add(table, m.constant(3.0)),
          d.GreaterEqual,
          m.add(chair, m.constant(5.0)),
        ),
      ],
    )
  let assert Ok(ir) = m.compile(model)
  ir.objective |> should.equal([2.0, 0.0])
  ir.offset |> should.equal(4.0)
  ir.rows |> should.equal([d.Row([#(0, -1.0), #(1, 1.0)], d.GreaterEqual, 2.0)])
}

pub fn add_chain_matches_flat_sum_test() {
  let keys = int.range(0, 100, [], fn(keys, key) { [key, ..keys] })
  let variables = list.map(keys, fn(key) { #(key, nonnegative()) })
  let chained =
    list.fold(keys, m.constant(0.0), fn(total, key) {
      m.add(total, m.variable(key))
    })
  let flat = m.sum(list.map(keys, m.variable))
  let model: m.Model(Int, String) = m.Model(variables, d.Minimize, flat, [])
  m.compile(m.Model(..model, objective: chained))
  |> should.equal(m.compile(model))
}

pub fn reference_validation_and_duplicates_test() {
  let model = base()
  list.each(
    [
      m.variable(Missing),
      m.scale(m.variable(Missing), 0.0),
      m.multiply(m.constant(0.0), m.variable(Missing)),
    ],
    fn(expression) {
      m.compile(m.Model(..model, objective: expression))
      |> should.equal(Error(m.UnknownVariable(Missing)))
    },
  )
  m.compile(
    m.Model(..model, variables: [
      #(Chair, nonnegative()),
      #(Chair, nonnegative()),
    ]),
  )
  |> should.equal(Error(m.DuplicateVariable(Chair)))
  let row = m.Constraint("same", m.constant(0.0), d.Equal, m.constant(0.0))
  m.compile(m.Model(..model, constraints: [row, row]))
  |> should.equal(Error(m.DuplicateConstraint("same")))
  m.compile(
    m.Model(..model, constraints: [
      m.Constraint("bad", m.constant(0.0), d.Equal, m.variable(Missing)),
    ]),
  )
  |> should.equal(Error(m.UnknownVariable(Missing)))
}

pub fn nonlinear_ast_is_rejected_but_constant_products_lower_test() {
  let model = base()
  let chair = m.variable(Chair)
  let quadratic = m.multiply(chair, chair)
  m.solve(m.Model(..model, objective: quadratic))
  |> should.equal(Error(m.NonlinearExpression))
  m.compile(
    m.Model(..model, constraints: [
      m.Constraint("quadratic", quadratic, d.LessEqual, m.constant(1.0)),
    ]),
  )
  |> should.equal(Error(m.NonlinearExpression))
  let cancelled = m.add(chair, m.scale(chair, -1.0))
  let assert Ok(ir) =
    m.compile(m.Model(..model, objective: m.multiply(cancelled, chair)))
  ir.objective |> should.equal([0.0, 0.0])
  // Deliberately no polynomial simplifier: nonlinear children remain unsupported.
  m.compile(m.Model(..model, objective: m.multiply(m.constant(0.0), quadratic)))
  |> should.equal(Error(m.NonlinearExpression))
}

pub fn explicit_outcomes_and_native_validation_test() {
  let empty: m.Model(Product, String) = m.Model([], d.Minimize, m.sum([]), [])
  let assert Ok(m.Optimal(solution)) = m.solve(empty)
  m.objective(solution) |> should.equal(0.0)
  m.solve(
    m.Model(..empty, constraints: [
      m.Constraint("impossible", m.sum([]), d.Equal, m.constant(1.0)),
    ]),
  )
  |> should.equal(Ok(m.Infeasible))
  let model = base()
  m.solve(m.Model(..model, direction: d.Maximize, objective: m.variable(Chair)))
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
