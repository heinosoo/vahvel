//// The 3 × 3 magic square: place the digits 1 to 9 so that every row, column
//// and diagonal sums to 15. There is nothing to optimize, only rules to meet,
//// so the objective is zero.

import gleam/float
import gleam/int
import gleam/list
import vahvel.{Constant, Linear, Sum, Variable}

type Cell {
  Cell(row: Int, column: Int)
}

// Whether `digit` goes in `cell`.
type Place {
  Place(cell: Cell, digit: Int)
}

const digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]

const lines = [
  // Rows
  [Cell(0, 0), Cell(0, 1), Cell(0, 2)],
  [Cell(1, 0), Cell(1, 1), Cell(1, 2)],
  [Cell(2, 0), Cell(2, 1), Cell(2, 2)],
  // Columns
  [Cell(0, 0), Cell(1, 0), Cell(2, 0)],
  [Cell(0, 1), Cell(1, 1), Cell(2, 1)],
  [Cell(0, 2), Cell(1, 2), Cell(2, 2)],
  // Diagonals
  [Cell(0, 0), Cell(1, 1), Cell(2, 2)],
  [Cell(0, 2), Cell(1, 1), Cell(2, 0)],
]

fn cells() -> List(Cell) {
  list.flat_map([0, 1, 2], fn(row) { list.map([0, 1, 2], Cell(row, _)) })
}

// The digit in a cell, as an expression: Σ d · Place(cell, d).
fn digit(cell: Cell) -> vahvel.Expression(Place) {
  list.map(digits, fn(d) { Linear(int.to_float(d), Place(cell, d)) }) |> Sum
}

fn exactly_one(places: List(Place)) -> vahvel.Constraint(Place) {
  vahvel.Equal(Sum(list.map(places, Variable)), Constant(1.0))
}

fn magic_square() -> vahvel.Model(Place) {
  let cells = cells()
  let one_digit_per_cell =
    list.map(cells, fn(cell) { exactly_one(list.map(digits, Place(cell, _))) })
  let one_cell_per_digit =
    list.map(digits, fn(d) { exactly_one(list.map(cells, Place(_, d))) })
  let lines_sum_to_15 =
    list.map(lines, fn(line) {
      vahvel.Equal(Sum(list.map(line, digit)), Constant(15.0))
    })
  vahvel.Model(
    domain: fn(_) { vahvel.Binary },
    objective: vahvel.Minimize(Sum([])),
    constraints: list.flatten([
      one_digit_per_cell,
      one_cell_per_digit,
      lines_sum_to_15,
    ]),
  )
}

pub fn magic_square_test() {
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(magic_square())
  // Read each cell's digit back through the same expression.
  let read = fn(cell) {
    let assert Ok(value) = vahvel.evaluate_solution(digit(cell), solution)
    float.round(value)
  }
  assert list.all(lines, fn(line) { int.sum(list.map(line, read)) == 15 })
  assert list.sort(list.map(cells(), read), int.compare) == digits
}

pub fn five_in_the_middle_test() {
  // Every 3 × 3 magic square has 5 in the middle, so asking for a 4 there is
  // infeasible.
  let model = magic_square()
  let four = vahvel.Equal(Variable(Place(Cell(1, 1), 4)), Constant(1.0))
  assert vahvel.solve(
      vahvel.Model(..model, constraints: [four, ..model.constraints]),
    )
    == Ok(vahvel.Infeasible)
}
