//// A multi-period production and distribution network. Factories open at a
//// fixed cost and produce up to a capacity; trucks carry goods along sparse
//// routes to warehouses, which hold stock between periods to meet demand.
//// `instance(size)` generates data deterministically, so larger sizes serve
//// as benchmark inputs (`test/bench.gleam`).

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleeunit/should
import vahvel.{Constant, Linear, Sum, Variable}

// Data

type Route {
  Route(factory: Int, warehouse: Int)
}

type Factory {
  Factory(id: Int, capacity: Float, fixed_cost: Float, unit_cost: Float)
}

type Warehouse {
  /// `demand` has one entry per period, starting at period 1.
  Warehouse(
    id: Int,
    initial_stock: Float,
    holding_cost: Float,
    demand: List(Float),
  )
}

type Lane {
  /// An unavailable lane is in the data but not in the model.
  Lane(route: Route, truck_cost: Float, available: Bool)
}

pub opaque type Instance {
  Instance(
    factories: List(Factory),
    warehouses: List(Warehouse),
    lanes: List(Lane),
    periods: List(Int),
    truck_capacity: Float,
  )
}

fn ids(count: Int) -> List(Int) {
  int.range(from: count, to: 0, with: [], run: list.prepend)
}

/// Factory `f` serves warehouses `2f − 1` and `2f`, and also the next
/// factory's first warehouse. The last warehouse's only lane is unavailable,
/// so it lives on its initial stock.
pub fn instance(size: Int) -> Instance {
  let factory_ids = ids(size)
  let isolated = 2 * size + 1
  let warehouses =
    list.flat_map(factory_ids, fn(f) {
      [
        Warehouse(2 * f - 1, 0.0, 1.0, [3.0, 0.0, 3.0]),
        Warehouse(2 * f, 0.0, 1.0, [2.0, 0.0, 4.0]),
      ]
    })
  let lanes =
    list.flat_map(factory_ids, fn(f) {
      let own = [
        Lane(Route(f, 2 * f - 1), 3.0, True),
        Lane(Route(f, 2 * f), 5.0, True),
      ]
      case f < size {
        True -> [Lane(Route(f, 2 * f + 1), 4.0, True), ..own]
        False -> own
      }
    })
  Instance(
    factories: list.map(factory_ids, Factory(_, 10.0, 20.0, 2.0)),
    warehouses: list.append(warehouses, [
      Warehouse(isolated, 5.0, 1.0, [1.0, 1.0, 1.0]),
    ]),
    lanes: list.append(lanes, [Lane(Route(1, isolated), 1.0, False)]),
    periods: ids(3),
    truck_capacity: 4.0,
  )
}

// Model

pub opaque type Var {
  Open(factory: Int)
  Make(factory: Int, period: Int)
  Ship(route: Route, period: Int)
  Trucks(route: Route, period: Int)
  Stock(warehouse: Int, period: Int)
}

fn domain(var: Var) -> vahvel.Domain {
  case var {
    Open(_) -> vahvel.Binary
    Trucks(..) -> vahvel.NonNegativeInteger
    Make(..) | Ship(..) | Stock(..) -> vahvel.NonNegativeReal
  }
}

type Costs {
  Costs(
    fixed: vahvel.Expression(Var),
    production: vahvel.Expression(Var),
    transport: vahvel.Expression(Var),
    holding: vahvel.Expression(Var),
  )
}

fn available_routes(data: Instance) -> List(Route) {
  data.lanes
  |> list.filter(fn(lane) { lane.available })
  |> list.map(fn(lane) { lane.route })
}

fn over_periods(
  items: List(a),
  periods: List(Int),
  term: fn(a, Int) -> vahvel.Expression(Var),
) -> vahvel.Expression(Var) {
  list.flat_map(items, fn(item) { list.map(periods, term(item, _)) }) |> Sum
}

fn costs(data: Instance) -> Costs {
  let lanes = list.filter(data.lanes, fn(lane) { lane.available })
  Costs(
    fixed: list.map(data.factories, fn(f) { Linear(f.fixed_cost, Open(f.id)) })
      |> Sum,
    production: over_periods(data.factories, data.periods, fn(f, t) {
      Linear(f.unit_cost, Make(f.id, t))
    }),
    transport: over_periods(lanes, data.periods, fn(lane, t) {
      Linear(lane.truck_cost, Trucks(lane.route, t))
    }),
    holding: over_periods(data.warehouses, data.periods, fn(w, t) {
      Linear(w.holding_cost, Stock(w.id, t))
    }),
  )
}

fn total(costs: Costs) -> vahvel.Expression(Var) {
  Sum([costs.fixed, costs.production, costs.transport, costs.holding])
}

// Missing keys are nodes without routes: an empty index set.
fn routes_at(adjacency: Dict(Int, List(Route)), node: Int) -> List(Route) {
  dict.get(adjacency, node) |> result.unwrap([])
}

fn shipped(routes: List(Route), t: Int) -> vahvel.Expression(Var) {
  list.map(routes, fn(route) { Variable(Ship(route, t)) }) |> Sum
}

// A constraint's builder is also its lookup: reports rebuild the row to read
// its residual.
fn capacity(f: Factory, t: Int) -> vahvel.Constraint(Var) {
  vahvel.LessEqual(Variable(Make(f.id, t)), Linear(f.capacity, Open(f.id)))
}

fn constraints(data: Instance) -> List(vahvel.Constraint(Var)) {
  let routes = available_routes(data)
  let outgoing = list.group(routes, fn(route) { route.factory })
  let incoming = list.group(routes, fn(route) { route.warehouse })
  let production =
    list.flat_map(data.factories, fn(f) {
      list.flat_map(data.periods, fn(t) {
        [
          capacity(f, t),
          vahvel.Equal(
            Variable(Make(f.id, t)),
            shipped(routes_at(outgoing, f.id), t),
          ),
        ]
      })
    })
  let trucks =
    list.flat_map(routes, fn(route) {
      list.map(data.periods, fn(t) {
        vahvel.LessEqual(
          Variable(Ship(route, t)),
          Linear(data.truck_capacity, Trucks(route, t)),
        )
      })
    })
  let balance =
    list.flat_map(data.warehouses, fn(w) {
      list.index_map(w.demand, fn(demand, i) {
        let t = i + 1
        let previous = case t {
          1 -> Constant(w.initial_stock)
          _ -> Variable(Stock(w.id, t - 1))
        }
        vahvel.Equal(
          Sum([previous, shipped(routes_at(incoming, w.id), t)]),
          Sum([Constant(demand), Variable(Stock(w.id, t))]),
        )
      })
    })
  list.flatten([production, trucks, balance])
}

pub fn model(data: Instance) -> vahvel.Model(Var) {
  vahvel.Model(
    domain:,
    objective: vahvel.Minimize(total(costs(data))),
    constraints: constraints(data),
  )
}

// Tests

pub fn smallest_network_test() {
  let data = instance(1)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  vahvel.objective(solution) |> should.equal(69.0)
  // Opening is forced; 12 units at 2 each; two trucks per lane; the isolated
  // warehouse holds 4, 3 and 2 units of its initial stock.
  let costs = costs(data)
  [costs.fixed, costs.production, costs.transport, costs.holding]
  |> list.map(vahvel.evaluate_solution(_, solution))
  |> should.equal([Ok(20.0), Ok(24.0), Ok(16.0), Ok(9.0)])
}

pub fn unavailable_lanes_have_no_variables_test() {
  let data = instance(1)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  // Reporting over every lane in the data must handle lanes the model never
  // referenced: their keys are not variables.
  list.each(data.lanes, fn(lane) {
    vahvel.value(solution, Ship(lane.route, 1))
    |> result.is_ok
    |> should.equal(lane.available)
  })
}

// Reporting

type PeriodPlan {
  PeriodPlan(
    period: Int,
    factories: List(FactoryPlan),
    lanes: List(LanePlan),
    stock: List(#(Int, Float)),
  )
}

type FactoryPlan {
  FactoryPlan(factory: Int, made: Float, spare: Float)
}

type LanePlan {
  Shipping(route: Route, units: Float, trucks: Int)
  /// In the data but not in the model, so it has no variables.
  Unavailable(route: Route)
}

/// The complete plan, period by period. It walks the same data that built the
/// model, so absent decisions come from the data and every key it reads is a
/// variable: a failed lookup is a bug, reported rather than read as zero.
fn plan(
  data: Instance,
  solution: vahvel.Solution(Var),
) -> Result(List(PeriodPlan), vahvel.EvaluationError(Var)) {
  let lookup = vahvel.value(solution, _)
  let read = fn(key) {
    lookup(key) |> result.replace_error(vahvel.MissingValue(key))
  }
  use t <- list.try_map(data.periods)
  use factories <- result.try(
    list.try_map(data.factories, fn(f) {
      use made <- result.try(read(Make(f.id, t)))
      // made − capacity · open: at most zero, and minus the spare capacity.
      use residual <- result.try(vahvel.residual(capacity(f, t), lookup))
      Ok(FactoryPlan(f.id, made:, spare: float.negate(residual)))
    }),
  )
  use lanes <- result.try(
    list.try_map(data.lanes, fn(lane) {
      case lane.available {
        False -> Ok(Unavailable(lane.route))
        True -> {
          use units <- result.try(read(Ship(lane.route, t)))
          use trucks <- result.try(read(Trucks(lane.route, t)))
          Ok(Shipping(lane.route, units:, trucks: float.round(trucks)))
        }
      }
    }),
  )
  use stock <- result.try(
    list.try_map(data.warehouses, fn(w) {
      read(Stock(w.id, t)) |> result.map(fn(units) { #(w.id, units) })
    }),
  )
  Ok(PeriodPlan(t, factories:, lanes:, stock:))
}

pub fn complete_plan_test() {
  let data = instance(1)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  // Holding costs make the network ship each period's demand just in time;
  // only the isolated warehouse draws down its initial stock.
  let lanes = fn(near, far, trucks) {
    [
      Shipping(Route(1, 1), near, trucks),
      Shipping(Route(1, 2), far, trucks),
      Unavailable(Route(1, 3)),
    ]
  }
  let stock = fn(isolated) { [#(1, 0.0), #(2, 0.0), #(3, isolated)] }
  plan(data, solution)
  |> should.equal(
    Ok([
      PeriodPlan(1, [FactoryPlan(1, 5.0, 5.0)], lanes(3.0, 2.0, 1), stock(4.0)),
      PeriodPlan(2, [FactoryPlan(1, 0.0, 10.0)], lanes(0.0, 0.0, 0), stock(3.0)),
      PeriodPlan(3, [FactoryPlan(1, 7.0, 3.0)], lanes(3.0, 4.0, 1), stock(2.0)),
    ]),
  )
}

pub fn plan_reports_wrong_keys_test() {
  let data = instance(1)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  // A factory the model never saw: the report fails instead of showing zeros.
  let wrong = Instance(..data, factories: [Factory(9, 10.0, 20.0, 2.0)])
  plan(wrong, solution)
  |> should.equal(Error(vahvel.MissingValue(Make(9, 1))))
}

pub fn what_if_trucks_test() {
  let data = instance(1)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  // What would the plan cost with one truck on every lane in every period?
  // Overriding values ignores feasibility; evaluation only prices them.
  let one_truck_each = fn(key) {
    case key {
      Trucks(..) -> Ok(1.0)
      _ -> vahvel.value(solution, key)
    }
  }
  let costs = costs(data)
  // Two lanes costing 3 and 5, over three periods.
  vahvel.evaluate(costs.transport, one_truck_each) |> should.equal(Ok(24.0))
  vahvel.evaluate(total(costs), one_truck_each) |> should.equal(Ok(77.0))
}

pub fn higher_demand_scenario_test() {
  let data = instance(1)
  let base = model(data)
  // Warehouse 2 needs 7 instead of 4 units in period 3.
  let busier =
    Instance(
      ..data,
      warehouses: list.map(data.warehouses, fn(w) {
        case w.id {
          2 -> Warehouse(..w, demand: [2.0, 0.0, 7.0])
          _ -> w
        }
      }),
    )
  // Costs depend only on prices, so the objective is reused.
  let scenario = vahvel.Model(..base, constraints: constraints(busier))
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(scenario)
  // Three more units at 2 each and one more truck on the lane costing 5.
  vahvel.objective(solution) |> should.equal(80.0)
}

pub fn larger_network_test() {
  let data = instance(3)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model(data))
  let costs = costs(data)
  let parts = [costs.fixed, costs.production, costs.transport, costs.holding]
  let assert Ok(values) =
    list.try_map(parts, vahvel.evaluate_solution(_, solution))
  float.sum(values)
  |> float.loosely_equals(vahvel.objective(solution), 0.000001)
  |> should.be_true
  vahvel.values(solution)
  |> dict.each(fn(key, value) {
    case key {
      Trucks(..) -> value |> should.equal(float.floor(value))
      _ -> Nil
    }
  })
}
