//// The 0/1 knapsack: pick the most valuable items that fit within a weight
//// capacity. Ten items are already enough for a solve budget to stop the
//// search early, holding a good pick that isn't proven best, or none at all.

import gleam/list
import gleam/option.{None, Some}
import vahvel.{Constant, Linear, Sum}

// An item is its own key, so no two items may be equal. Give them names if
// two could weigh and be worth the same.
type Item {
  Item(weight: Float, value: Float)
}

// A standard test instance, P01 from John Burkardt's knapsack data sets.
const items = [
  Item(weight: 23.0, value: 92.0),
  Item(weight: 31.0, value: 57.0),
  Item(weight: 29.0, value: 49.0),
  Item(weight: 44.0, value: 68.0),
  Item(weight: 53.0, value: 60.0),
  Item(weight: 38.0, value: 43.0),
  Item(weight: 63.0, value: 67.0),
  Item(weight: 85.0, value: 84.0),
  Item(weight: 89.0, value: 87.0),
  Item(weight: 82.0, value: 72.0),
]

fn knapsack() -> vahvel.Model(Item) {
  vahvel.Model(
    domain: fn(_) { vahvel.Binary },
    objective: vahvel.Maximize(
      list.map(items, fn(item) { Linear(item.value, item) }) |> Sum,
    ),
    constraints: [
      vahvel.LessEqual(
        list.map(items, fn(item) { Linear(item.weight, item) }) |> Sum,
        Constant(165.0),
      ),
    ],
  )
}

// Every outcome is a value, so one `case` turns it into a pick or a reason.
fn pick(budget: vahvel.Limits) -> Result(vahvel.Solution(Item), String) {
  case vahvel.solve_with(knapsack(), budget) {
    Ok(vahvel.Optimal(solution, _))
    | Ok(vahvel.Limited(_, Some(solution), _)) -> Ok(solution)
    Ok(vahvel.Limited(_, None, _)) -> Error("no pick within the budget")
    Ok(vahvel.Infeasible) -> Error("nothing fits")
    Ok(vahvel.Unbounded) -> Error("value is unbounded")
    Error(_) -> Error("invalid model")
  }
}

pub fn best_pick_test() {
  let assert Ok(solution) = pick(vahvel.Limits(time: None, nodes: None))
  assert vahvel.objective(solution) == 309.0
  let picked =
    list.filter(items, fn(item) { vahvel.value(solution, item) == Ok(1.0) })
  assert list.map(picked, fn(item) { item.value })
    == [92.0, 57.0, 49.0, 68.0, 43.0]
}

pub fn budgets_test() {
  // Eight branch-and-bound nodes find a pick but not the proof that it is
  // best, and here it is short of the optimum.
  let assert Ok(solution) = pick(vahvel.Limits(time: None, nodes: Some(8)))
  assert vahvel.objective(solution) <. 309.0
  // With no nodes at all, search stops before it finds any pick.
  assert pick(vahvel.Limits(time: None, nodes: Some(0)))
    == Error("no pick within the budget")
}
