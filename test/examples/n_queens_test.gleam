//// Place as many queens as possible on an n × n board so that none attack
//// each other: one binary per square, at most one queen per row, column and
//// diagonal. A quick integer model built straight from index sets.

import gleam/dict
import gleam/int
import gleam/list
import gleeunit/should
import waffle.{Constant, Sum, Variable}

type Square {
  Queen(row: Int, column: Int)
}

fn board(n: Int) -> List(Square) {
  let indices = int.range(from: n - 1, to: -1, with: [], run: list.prepend)
  list.flat_map(indices, fn(row) { list.map(indices, Queen(row, _)) })
}

fn model(n: Int) -> waffle.Model(Square) {
  let squares = board(n)
  let at_most_one = fn(line: fn(Square) -> Int) {
    list.group(squares, line)
    |> dict.values
    |> list.map(fn(group) {
      waffle.LessEqual(Sum(list.map(group, Variable)), Constant(1.0))
    })
  }
  waffle.Model(
    domain: fn(_) { waffle.Binary },
    objective: waffle.Maximize(Sum(list.map(squares, Variable))),
    constraints: list.flatten([
      at_most_one(fn(q) { q.row }),
      at_most_one(fn(q) { q.column }),
      at_most_one(fn(q) { q.row - q.column }),
      at_most_one(fn(q) { q.row + q.column }),
    ]),
  )
}

fn queens(n: Int) -> List(Square) {
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model(n))
  waffle.values(solution)
  |> dict.filter(fn(_, placed) { placed == 1.0 })
  |> dict.keys
}

fn attack(a: Square, b: Square) -> Bool {
  a.row == b.row
  || a.column == b.column
  || a.row - a.column == b.row - b.column
  || a.row + a.column == b.row + b.column
}

pub fn small_boards_test() {
  list.length(queens(1)) |> should.equal(1)
  list.length(queens(2)) |> should.equal(1)
  list.length(queens(3)) |> should.equal(2)
}

pub fn full_board_test() {
  let placed = queens(8)
  list.length(placed) |> should.equal(8)
  list.combination_pairs(placed)
  |> list.any(fn(pair) { attack(pair.0, pair.1) })
  |> should.be_false
}
