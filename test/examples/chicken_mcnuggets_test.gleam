//// The Chicken McNugget problem: nuggets come in boxes of 6, 9 and 20. Which
//// amounts can be ordered exactly? One equality over integers, where "no such
//// order" is an answer, not an error.

import gleam/int
import gleam/list
import vahvel.{Constant, Linear, Sum, Variable}

type Box {
  Six
  Nine
  Twenty
}

fn order(nuggets: Int) -> vahvel.Model(Box) {
  vahvel.Model(
    domain: fn(_) { vahvel.NonNegativeInteger },
    // Of all exact orders, the one with the fewest boxes.
    objective: vahvel.Minimize(
      Sum([Variable(Six), Variable(Nine), Variable(Twenty)]),
    ),
    constraints: [
      vahvel.Equal(
        Sum([Linear(6.0, Six), Linear(9.0, Nine), Linear(20.0, Twenty)]),
        Constant(int.to_float(nuggets)),
      ),
    ],
  )
}

pub fn forty_four_test() {
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(order(44))
  assert vahvel.objective(solution) == 4.0
  assert vahvel.value(solution, Six) == Ok(1.0)
  assert vahvel.value(solution, Nine) == Ok(2.0)
  assert vahvel.value(solution, Twenty) == Ok(1.0)
}

pub fn forty_three_test() {
  assert vahvel.solve(order(43)) == Ok(vahvel.Infeasible)
}

pub fn largest_impossible_order_test() {
  // 44 to 49 can all be ordered. Adding boxes of 6 to those six reaches every
  // larger amount, so 43 is the largest order that can't be filled.
  let feasible = fn(nuggets) {
    case vahvel.solve(order(nuggets)) {
      Ok(vahvel.Optimal(..)) -> True
      _ -> False
    }
  }
  assert list.all([44, 45, 46, 47, 48, 49], feasible)
}
