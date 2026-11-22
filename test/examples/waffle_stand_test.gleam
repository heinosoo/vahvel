//// The README's waffle stand, step by step. README.md shows lightly adapted
//// snippets of these tests; change both together.
////
//// A stand sells waffles during a rush. Which waffles should it bake to earn
//// the most? Each step adds one idea.

import gleam/dict
import gleam/list
import vahvel.{Constant, Difference, Linear, Sum, Variable}

// Variables are named by your own values. A custom type makes the names
// self-describing, and the compiler checks every `case` over them.
type Waffle {
  Classic
  Chocolate
  Berry
}

// Step 1: a first model. Classic waffles earn 3.00 and take 2 minutes on the
// iron; chocolate waffles earn 5.00 and take 3 minutes. The rush lasts 13
// minutes.
pub fn first_model_test() {
  let model =
    vahvel.Model(
      // Half a waffle doesn't sell, so both counts are nonnegative integers.
      domain: fn(_) { vahvel.NonNegativeInteger },
      // `Linear(coefficient, key)` is one weighted variable, and `Sum` adds
      // expressions: 3·classic + 5·chocolate.
      objective: vahvel.Maximize(
        Sum([Linear(3.0, Classic), Linear(5.0, Chocolate)]),
      ),
      // Both sides of a constraint are expressions, so the 13 minutes are a
      // `Constant`: 2·classic + 3·chocolate ≤ 13.
      constraints: [
        vahvel.LessEqual(
          Sum([Linear(2.0, Classic), Linear(3.0, Chocolate)]),
          Constant(13.0),
        ),
      ],
    )
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model)
  // 4 chocolate waffles earn 20 and leave a minute unused. Mixing in
  // classics uses all 13 minutes.
  assert vahvel.objective(solution) == 21.0
  assert vahvel.value(solution, Chocolate) == Ok(3.0)
  assert vahvel.value(solution, Classic) == Ok(2.0)
}

// Step 2: models from data. Berry waffles join the menu, and batter runs
// short too: 9 scoops for the rush.

type Recipe {
  Recipe(waffle: Waffle, price: Float, minutes: Float, scoops: Float)
}

const menu = [
  Recipe(Classic, price: 3.0, minutes: 2.0, scoops: 1.0),
  Recipe(Chocolate, price: 5.0, minutes: 3.0, scoops: 2.0),
  Recipe(Berry, price: 4.5, minutes: 2.0, scoops: 2.0),
]

// As models grow, keys name the decision, not just the thing: `Bake(Berry)`
// is how many berry waffles to bake. `Station` is used from Step 3 on; until
// an expression references one, it is not a variable.
type Decision {
  Bake(Waffle)
  Station(Waffle)
}

fn sales() -> vahvel.Expression(Decision) {
  list.map(menu, fn(recipe) { Linear(recipe.price, Bake(recipe.waffle)) })
  |> Sum
}

// One constraint per resource: what all waffles use stays within supply.
fn supply_limits() -> List(vahvel.Constraint(Decision)) {
  let used = fn(amount: fn(Recipe) -> Float) {
    list.map(menu, fn(recipe) { Linear(amount(recipe), Bake(recipe.waffle)) })
    |> Sum
  }
  [
    vahvel.LessEqual(used(fn(recipe) { recipe.minutes }), Constant(13.0)),
    vahvel.LessEqual(used(fn(recipe) { recipe.scoops }), Constant(9.0)),
  ]
}

pub fn models_from_data_test() {
  let model =
    vahvel.Model(
      domain: fn(_) { vahvel.NonNegativeInteger },
      objective: vahvel.Maximize(sales()),
      constraints: supply_limits(),
    )
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model)
  // Filling up on berries, the best earner per minute, earns only 21. The
  // best rush bakes all three and uses every minute and every scoop.
  assert vahvel.objective(solution) == 23.0
  // Report by mapping over the same data that built the model.
  let baked =
    list.map(menu, fn(recipe) {
      #(recipe.waffle, vahvel.value(solution, Bake(recipe.waffle)))
    })
  assert baked
    == [#(Classic, Ok(3.0)), #(Chocolate, Ok(1.0)), #(Berry, Ok(2.0))]
}

// Step 3: yes-or-no decisions. Toppings need a station: melting chocolate
// costs 2.00 per rush and washing berries 1.50. A station serves at most so
// many waffles, and none if it isn't set up.

type Topping {
  Topping(waffle: Waffle, cost: Float, serves: Float)
}

const toppings = [Topping(Chocolate, 2.0, 4.0), Topping(Berry, 1.5, 6.0)]

fn station_costs() -> vahvel.Expression(Decision) {
  list.map(toppings, fn(topping) {
    Linear(topping.cost, Station(topping.waffle))
  })
  |> Sum
}

// With two kinds of decision, an exhaustive `case` gives each its domain.
fn domain(decision: Decision) -> vahvel.Domain {
  case decision {
    Bake(_) -> vahvel.NonNegativeInteger
    Station(_) -> vahvel.Binary
  }
}

fn with_stations() -> vahvel.Model(Decision) {
  // Bake(waffle) ≤ serves · Station(waffle): with the station off, the binary
  // is 0 and so is the bake count.
  let station_limits =
    list.map(toppings, fn(topping) {
      vahvel.LessEqual(
        Variable(Bake(topping.waffle)),
        Linear(topping.serves, Station(topping.waffle)),
      )
    })
  vahvel.Model(
    domain:,
    objective: vahvel.Maximize(Difference(sales(), station_costs())),
    constraints: list.append(supply_limits(), station_limits),
  )
}

pub fn yes_or_no_decisions_test() {
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(with_stations())
  // The single chocolate waffle doesn't pay for its station, so the priciest
  // waffle leaves the menu: 3 classic and 3 berry earn 22.50 − 1.50.
  assert vahvel.objective(solution) == 21.0
  assert vahvel.value(solution, Station(Chocolate)) == Ok(0.0)
  assert vahvel.value(solution, Station(Berry)) == Ok(1.0)
  assert vahvel.value(solution, Bake(Classic)) == Ok(3.0)
  assert vahvel.value(solution, Bake(Berry)) == Ok(3.0)
}

// Step 4: reporting. The expressions that built the model also explain the
// result, and evaluate any other plan, such as one written by hand.
pub fn reporting_test() {
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(with_stations())
  assert vahvel.evaluate_solution(sales(), solution) == Ok(22.5)
  assert vahvel.evaluate_solution(station_costs(), solution) == Ok(1.5)
  // Classic waffles need no station, so `Station(Classic)` was never
  // referenced, and asking for it is an error rather than a silent zero.
  assert vahvel.value(solution, Station(Classic)) == Error(Nil)

  // 4 classic and 2 berry waffles earn 21.00 − 1.50: less than the solver's
  // plan.
  let plan =
    dict.from_list([
      #(Bake(Classic), 4.0),
      #(Bake(Chocolate), 0.0),
      #(Bake(Berry), 2.0),
      #(Station(Chocolate), 0.0),
      #(Station(Berry), 1.0),
    ])
  let profit = Difference(sales(), station_costs())
  assert vahvel.evaluate_dict(profit, plan) == Ok(19.5)
  // A residual is lhs − rhs, so a `LessEqual` holds when it is at most zero:
  // one minute and one scoop to spare.
  assert list.map(supply_limits(), vahvel.residual(_, dict.get(plan, _)))
    == [Ok(-1.0), Ok(-1.0)]
}
