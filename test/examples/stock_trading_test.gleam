//// Best time to buy and sell stock: given a share's price each day, when
//// should you buy and sell, holding at most one share at a time? Each day's
//// holding follows from the day before, which chains the days together.

import gleam/list
import vahvel.{Constant, Difference, Linear, Sum, Variable}

const prices = [7.0, 1.0, 5.0, 3.0, 6.0, 4.0]

type Decision {
  Buy(day: Int)
  Sell(day: Int)
  Holding(day: Int)
}

fn trading() -> vahvel.Model(Decision) {
  // Holding(day) = Holding(day − 1) + Buy(day) − Sell(day), starting with no
  // share.
  let holdings =
    list.index_map(prices, fn(_, day) {
      let before = case day {
        0 -> Constant(0.0)
        _ -> Variable(Holding(day - 1))
      }
      vahvel.Equal(
        Variable(Holding(day)),
        Difference(Sum([before, Variable(Buy(day))]), Variable(Sell(day))),
      )
    })
  let profit =
    list.index_map(prices, fn(price, day) {
      Difference(Linear(price, Sell(day)), Linear(price, Buy(day)))
    })
    |> Sum
  vahvel.Model(
    // Holding at most one share makes every decision yes or no.
    domain: fn(_) { vahvel.Binary },
    objective: vahvel.Maximize(profit),
    constraints: holdings,
  )
}

// Buying and selling on the same day earns nothing, so the solver may do it.
// The days a share is held overnight tell the plan without that noise.
fn held(solution: vahvel.Solution(Decision)) -> List(Int) {
  list.index_map(prices, fn(_, day) { day })
  |> list.filter(fn(day) { vahvel.value(solution, Holding(day)) == Ok(1.0) })
}

pub fn many_trades_test() {
  // Buy at 1, sell at 5, buy at 3, sell at 6.
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(trading())
  assert vahvel.objective(solution) == 7.0
  assert held(solution) == [1, 3]
}

pub fn one_trade_test() {
  // With a single purchase, the best is the largest rise: buy at 1 and sell
  // at 6.
  let model = trading()
  let once =
    vahvel.LessEqual(
      list.index_map(prices, fn(_, day) { Variable(Buy(day)) }) |> Sum,
      Constant(1.0),
    )
  let assert Ok(vahvel.Optimal(solution, _)) =
    vahvel.solve(
      vahvel.Model(..model, constraints: [once, ..model.constraints]),
    )
  assert vahvel.objective(solution) == 5.0
  assert held(solution) == [1, 2, 3]
}
