//// A multi-period production and distribution network. Factories open at a
//// fixed cost and produce up to a capacity; trucks carry goods along sparse
//// routes to warehouses, which hold stock between periods to meet demand.
//// `instance(size)` generates data deterministically, so larger sizes can
//// serve as benchmark inputs.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should
import waffle.{Constant, Linear, Sum}

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

type Instance {
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
fn instance(size: Int) -> Instance {
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

type Var {
  Open(factory: Int)
  Make(factory: Int, period: Int)
  Ship(route: Route, period: Int)
  Trucks(route: Route, period: Int)
  Stock(warehouse: Int, period: Int)
}

fn domain(var: Var) -> waffle.Domain {
  case var {
    Open(_) -> waffle.Binary
    Trucks(..) -> waffle.Integer(Some(0), None)
    Make(..) | Ship(..) | Stock(..) -> waffle.Continuous(Some(0.0), None)
  }
}

type Costs {
  Costs(
    fixed: waffle.Expression(Var),
    production: waffle.Expression(Var),
    transport: waffle.Expression(Var),
    holding: waffle.Expression(Var),
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
  term: fn(a, Int) -> waffle.Expression(Var),
) -> waffle.Expression(Var) {
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

fn total(costs: Costs) -> waffle.Expression(Var) {
  Sum([costs.fixed, costs.production, costs.transport, costs.holding])
}

// Missing keys are nodes without routes: an empty index set.
fn routes_at(adjacency: Dict(Int, List(Route)), node: Int) -> List(Route) {
  dict.get(adjacency, node) |> result.unwrap([])
}

fn shipped(routes: List(Route), t: Int) -> waffle.Expression(Var) {
  list.map(routes, fn(route) { Linear(1.0, Ship(route, t)) }) |> Sum
}

fn constraints(data: Instance) -> List(waffle.Constraint(Var)) {
  let routes = available_routes(data)
  let outgoing = list.group(routes, fn(route) { route.factory })
  let incoming = list.group(routes, fn(route) { route.warehouse })
  let production =
    list.flat_map(data.factories, fn(f) {
      list.flat_map(data.periods, fn(t) {
        [
          waffle.LessEqual(
            Linear(1.0, Make(f.id, t)),
            Linear(f.capacity, Open(f.id)),
          ),
          waffle.Equal(
            Linear(1.0, Make(f.id, t)),
            shipped(routes_at(outgoing, f.id), t),
          ),
        ]
      })
    })
  let trucks =
    list.flat_map(routes, fn(route) {
      list.map(data.periods, fn(t) {
        waffle.LessEqual(
          Linear(1.0, Ship(route, t)),
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
          _ -> Linear(1.0, Stock(w.id, t - 1))
        }
        waffle.Equal(
          Sum([previous, shipped(routes_at(incoming, w.id), t)]),
          Sum([Constant(demand), Linear(1.0, Stock(w.id, t))]),
        )
      })
    })
  list.flatten([production, trucks, balance])
}

fn model(data: Instance) -> waffle.Model(Var) {
  waffle.Model(
    domain:,
    objective: waffle.Minimize(total(costs(data))),
    constraints: constraints(data),
  )
}

// Tests

fn evaluate(solution: waffle.Solution(Var), expression) -> Float {
  let assert Ok(value) = waffle.evaluate(solution, expression)
  value
}

pub fn smallest_network_test() {
  let data = instance(1)
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model(data))
  waffle.objective(solution) |> should.equal(69.0)
  // Opening is forced; 12 units at 2 each; two trucks per lane; the isolated
  // warehouse holds 4, 3 and 2 units of its initial stock.
  let costs = costs(data)
  evaluate(solution, costs.fixed) |> should.equal(20.0)
  evaluate(solution, costs.production) |> should.equal(24.0)
  evaluate(solution, costs.transport) |> should.equal(16.0)
  evaluate(solution, costs.holding) |> should.equal(9.0)
}

pub fn unavailable_lanes_have_no_variables_test() {
  let data = instance(1)
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model(data))
  // Reporting over every lane in the data must handle lanes the model never
  // referenced: their keys are not variables.
  let report =
    list.map(data.lanes, fn(lane) {
      #(lane.available, waffle.value(solution, Ship(lane.route, 1)))
    })
  list.each(report, fn(row) {
    case row {
      #(True, shipped) -> shipped |> result.is_ok |> should.be_true
      #(False, shipped) -> shipped |> should.equal(Error(Nil))
    }
  })
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
  let scenario = waffle.Model(..base, constraints: constraints(busier))
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(scenario)
  // Three more units at 2 each and one more truck on the lane costing 5.
  waffle.objective(solution) |> should.equal(80.0)
}

pub fn larger_network_test() {
  let data = instance(3)
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model(data))
  let costs = costs(data)
  let parts = [costs.fixed, costs.production, costs.transport, costs.holding]
  list.fold(parts, 0.0, fn(sum, part) { sum +. evaluate(solution, part) })
  |> float.loosely_equals(waffle.objective(solution), 0.000001)
  |> should.be_true
  waffle.values(solution)
  |> dict.to_list
  |> list.each(fn(entry) {
    case entry {
      #(Trucks(..), trucks) -> trucks |> should.equal(float.floor(trucks))
      _ -> Nil
    }
  })
}
