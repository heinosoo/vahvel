//// The diet problem: the cheapest day of meals that meets every nutrient
//// minimum. Servings of oats and beans can be fractional, but eggs come
//// whole, and nobody eats more than a few servings of anything.

import gleam/list
import gleam/option.{Some}
import vahvel.{Constant, Linear, Sum}

type Food {
  Oats
  Beans
  Eggs
}

type Item {
  Item(food: Food, cost: Float, protein: Float, fibre: Float)
}

const pantry = [
  Item(Oats, cost: 0.25, protein: 5.0, fibre: 4.0),
  Item(Beans, cost: 1.0, protein: 8.0, fibre: 7.0),
  Item(Eggs, cost: 0.5, protein: 6.0, fibre: 0.0),
]

// The key is the food itself: the only decision is how much of it to eat.
fn diet(protein protein: Float, fibre fibre: Float) -> vahvel.Model(Food) {
  let total = fn(amount: fn(Item) -> Float) {
    list.map(pantry, fn(item) { Linear(amount(item), item.food) }) |> Sum
  }
  vahvel.Model(
    // Limits on servings are bounds in the domain, not extra constraints.
    domain: fn(food) {
      case food {
        Oats -> vahvel.Real(lower: Some(0.0), upper: Some(4.0))
        Beans -> vahvel.Real(lower: Some(0.0), upper: Some(3.0))
        Eggs -> vahvel.Integer(lower: Some(0), upper: Some(3))
      }
    },
    objective: vahvel.Minimize(total(fn(item) { item.cost })),
    constraints: [
      vahvel.GreaterEqual(total(fn(item) { item.protein }), Constant(protein)),
      vahvel.GreaterEqual(total(fn(item) { item.fibre }), Constant(fibre)),
    ],
  )
}

fn servings(solution: vahvel.Solution(Food)) -> List(Result(Float, Nil)) {
  list.map(pantry, fn(item) { vahvel.value(solution, item.food) })
}

pub fn cheapest_day_test() {
  let assert Ok(vahvel.Optimal(solution, _)) =
    vahvel.solve(diet(protein: 40.0, fibre: 23.0))
  // Oats are the cheapest fibre but stop at 4 servings, so one serving of
  // beans covers the rest. Two eggs make up the protein.
  assert vahvel.objective(solution) == 3.0
  assert servings(solution) == [Ok(4.0), Ok(1.0), Ok(2.0)]
}

pub fn whole_eggs_test() {
  let assert Ok(vahvel.Optimal(solution, _)) =
    vahvel.solve(diet(protein: 41.0, fibre: 23.0))
  // One more gram of protein. A sixth of an egg would be cheapest, but eggs
  // are whole, and a third egg costs more than an eighth of a serving of
  // beans.
  assert vahvel.objective(solution) == 3.125
  assert servings(solution) == [Ok(4.0), Ok(1.125), Ok(2.0)]
}
