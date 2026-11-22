//// Fit a line to points by minimizing the sum of absolute errors (L1
//// regression). Unlike least squares it is linear, so it is an LP, and a
//// single outlier barely moves the fit.

import gleam/list
import gleam/option.{None}
import vahvel.{Constant, Difference, Linear, Scaled, Sum, Variable}

type Point {
  Point(x: Float, y: Float)
}

// Slope and intercept describe the line; each point gets a deviation from it.
type Fit {
  Slope
  Intercept
  Deviation(point: Int)
}

fn line_fit(points: List(Point)) -> vahvel.Model(Fit) {
  // |r| is the smallest d with d ≥ r and d ≥ −r, and minimizing the
  // deviations pushes each one down to exactly that.
  let bounds =
    list.index_map(points, fn(point, i) {
      let fitted = Sum([Linear(point.x, Slope), Variable(Intercept)])
      let residual = Difference(fitted, Constant(point.y))
      [
        vahvel.GreaterEqual(Variable(Deviation(i)), residual),
        vahvel.GreaterEqual(Variable(Deviation(i)), Scaled(-1.0, residual)),
      ]
    })
  vahvel.Model(
    // A line may fall or start below zero, so its parameters are free.
    // Deviations are absolute values, so they are nonnegative.
    domain: fn(key) {
      case key {
        Slope | Intercept -> vahvel.Real(lower: None, upper: None)
        Deviation(_) -> vahvel.NonNegativeReal
      }
    },
    objective: vahvel.Minimize(
      list.index_map(points, fn(_, i) { Variable(Deviation(i)) }) |> Sum,
    ),
    constraints: list.flatten(bounds),
  )
}

pub fn outlier_test() {
  // Points on y = 2x + 1, except that the fourth reads 20 instead of 7. The
  // fit ignores it and pays its whole 13 as deviation.
  let points = [
    Point(0.0, 1.0),
    Point(1.0, 3.0),
    Point(2.0, 5.0),
    Point(3.0, 20.0),
    Point(4.0, 9.0),
  ]
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(line_fit(points))
  assert vahvel.value(solution, Slope) == Ok(2.0)
  assert vahvel.value(solution, Intercept) == Ok(1.0)
  assert vahvel.objective(solution) == 13.0
}

pub fn falling_line_test() {
  // A negative slope needs the free domain; with `NonNegativeReal` the best
  // line would be flat.
  let points = [Point(0.0, 4.0), Point(1.0, 3.0), Point(2.0, 2.0)]
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(line_fit(points))
  assert vahvel.value(solution, Slope) == Ok(-1.0)
  assert vahvel.value(solution, Intercept) == Ok(4.0)
  assert vahvel.objective(solution) == 0.0
}
