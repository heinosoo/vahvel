//// The README's waffle stand, step by step, with explanations. README.md
//// shows lightly adapted snippets of these tests; change both together.
////
//// A stand sells waffles during a rush. Which waffles should it bake to earn
//// the most? Each step adds one idea, and each answer is a little surprising.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import waffle.{Constant, Linear, Scaled, Sum}

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
    waffle.Model(
      // Every variable needs a domain. Half a waffle doesn't sell, so both
      // counts are nonnegative integers; `None` means no upper bound.
      domain: fn(_) { waffle.Integer(Some(0), None) },
      // `Linear(coefficient, key)` is one weighted variable, and `Sum` adds
      // expressions: 3·classic + 5·chocolate.
      objective: waffle.Maximize(
        Sum([Linear(3.0, Classic), Linear(5.0, Chocolate)]),
      ),
      // Both sides of a constraint are expressions, so the 13 minutes are a
      // `Constant`: 2·classic + 3·chocolate ≤ 13.
      constraints: [
        waffle.LessEqual(
          Sum([Linear(2.0, Classic), Linear(3.0, Chocolate)]),
          Constant(13.0),
        ),
      ],
    )
  // `solve` separates answers from failures: `Ok(Infeasible)` and
  // `Ok(Unbounded)` are answers, `Error(_)` means invalid input. Only an
  // `Optimal` answer carries a solution to query.
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model)
  // Chocolate earns the most per minute, but 4 chocolate waffles leave a
  // minute unused and earn 20. Mixing in classics uses all 13 minutes.
  waffle.objective(solution) |> should.equal(21.0)
  waffle.value(solution, Chocolate) |> should.equal(Ok(3.0))
  waffle.value(solution, Classic) |> should.equal(Ok(2.0))
}

// Step 2: models from data. Berry waffles join the menu, and batter runs
// short too: 9 scoops for the rush.

type Recipe {
  Recipe(waffle: Waffle, price: Float, minutes: Float, scoops: Float)
}

const menu = [
  Recipe(Classic, 3.0, 2.0, 1.0),
  Recipe(Chocolate, 5.0, 3.0, 2.0),
  Recipe(Berry, 4.5, 2.0, 2.0),
]

type Resource {
  IronMinutes
  Batter
}

const supply = [#(IronMinutes, 13.0), #(Batter, 9.0)]

fn uses(recipe: Recipe, resource: Resource) -> Float {
  case resource {
    IronMinutes -> recipe.minutes
    Batter -> recipe.scoops
  }
}

// As models grow, keys name the decision, not just the thing: `Bake(Berry)`
// is how many berry waffles to bake. Step 3 adds a second kind of decision.
type Decision {
  Bake(Waffle)
  Station(Waffle)
}

fn domain(decision: Decision) -> waffle.Domain {
  case decision {
    Bake(_) -> waffle.Integer(Some(0), None)
    Station(_) -> waffle.Binary
  }
}

// Expressions are usually mapped over data and summed at the end.
fn sales() -> waffle.Expression(Decision) {
  list.map(menu, fn(recipe) { Linear(recipe.price, Bake(recipe.waffle)) })
  |> Sum
}

// One constraint per resource: what all waffles use stays within supply.
fn supply_limits() -> List(waffle.Constraint(Decision)) {
  list.map(supply, fn(entry) {
    let #(resource, available) = entry
    let used =
      list.map(menu, fn(recipe) {
        Linear(uses(recipe, resource), Bake(recipe.waffle))
      })
      |> Sum
    waffle.LessEqual(used, Constant(available))
  })
}

fn rush() -> waffle.Model(Decision) {
  waffle.Model(
    domain:,
    objective: waffle.Maximize(sales()),
    constraints: supply_limits(),
  )
}

pub fn models_from_data_test() {
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(rush())
  // Berry now earns the most per minute, yet filling up on berries first
  // earns only 21. The best rush bakes all three and uses every minute and
  // every scoop.
  waffle.objective(solution) |> should.equal(23.0)
  // Report by mapping over the same data that built the model.
  list.map(menu, fn(recipe) {
    #(recipe.waffle, waffle.value(solution, Bake(recipe.waffle)))
  })
  |> should.equal([
    #(Classic, Ok(3.0)),
    #(Chocolate, Ok(1.0)),
    #(Berry, Ok(2.0)),
  ])
}

// Step 3: yes-or-no decisions. Toppings need a station: melting chocolate
// costs 2.00 per rush and washing berries 1.50. A station serves at most so
// many waffles, and none if it isn't set up.

type Topping {
  Topping(waffle: Waffle, cost: Float, serves: Float)
}

const toppings = [Topping(Chocolate, 2.0, 4.0), Topping(Berry, 1.5, 6.0)]

fn station_costs() -> waffle.Expression(Decision) {
  list.map(toppings, fn(topping) {
    Linear(topping.cost, Station(topping.waffle))
  })
  |> Sum
}

fn with_stations() -> waffle.Model(Decision) {
  // Bake(waffle) ≤ serves · Station(waffle): with the station off, the binary
  // is 0 and so is the bake count.
  let station_limits =
    list.map(toppings, fn(topping) {
      waffle.LessEqual(
        Linear(1.0, Bake(topping.waffle)),
        Linear(topping.serves, Station(topping.waffle)),
      )
    })
  // Named expressions are reused as they are: profit is sales minus station
  // costs, and `..rush()` keeps the domain.
  waffle.Model(
    ..rush(),
    objective: waffle.Maximize(Sum([sales(), Scaled(-1.0, station_costs())])),
    constraints: list.append(supply_limits(), station_limits),
  )
}

pub fn yes_or_no_decisions_test() {
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(with_stations())
  // The single chocolate waffle doesn't pay for its station, so the priciest
  // waffle leaves the menu: 3 classic and 3 berry earn 22.50 − 1.50.
  waffle.objective(solution) |> should.equal(21.0)
  waffle.value(solution, Station(Chocolate)) |> should.equal(Ok(0.0))
  waffle.value(solution, Station(Berry)) |> should.equal(Ok(1.0))
  waffle.value(solution, Bake(Classic)) |> should.equal(Ok(3.0))
  waffle.value(solution, Bake(Berry)) |> should.equal(Ok(3.0))
}

// Step 4: reporting. The expressions that built the model also explain the
// result.
pub fn reporting_test() {
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(with_stations())
  waffle.evaluate(solution, sales()) |> should.equal(Ok(22.5))
  waffle.evaluate(solution, station_costs()) |> should.equal(Ok(1.5))
  // Revenue per waffle, from the same menu.
  list.map(menu, fn(recipe) {
    waffle.evaluate(solution, Linear(recipe.price, Bake(recipe.waffle)))
  })
  |> should.equal([Ok(9.0), Ok(0.0), Ok(13.5)])
  // A variable exists only once an expression references it. Classic
  // waffles need no station, so `Station(Classic)` was never referenced and
  // asking for it is an error rather than a silent zero.
  waffle.value(solution, Station(Classic)) |> should.equal(Error(Nil))
}
