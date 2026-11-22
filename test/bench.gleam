//// Measures what vahvel adds around the solver: lowering keys to columns, the
//// NIF call and decoding, canonicalization, validation and keyed results.
//// Overhead is wall time minus the solver's own `solve_time`. If overhead per
//// term stays flat as models grow, nothing scales superlinearly.
////
//// Models are sparse transportation LPs, so branch-and-bound doesn't
//// dominate the run time. Each measurement is repeated after warm-up runs and
//// reported as median and range. Run with `just bench`.

import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleam/time/duration
import vahvel

const sizes = [1, 10, 100, 1000]

const warmup_runs = 3

const runs = 15

pub fn main() -> Nil {
  io.println(
    "Solve overhead, transportation LP ("
    <> int.to_string(runs)
    <> " runs; times in µs, median [min–max])",
  )
  print_row([
    "size",
    "vars",
    "rows",
    "terms",
    "build",
    "wall",
    "solver",
    "overhead",
    "ns/term",
  ])
  list.each(sizes, solve_overhead)
  io.println("")
  io.println(
    "Residual of every row, size 100 (" <> int.to_string(runs) <> " runs)",
  )
  print_row(["rows", "total µs", "ns/call"])
  residual_calls(100)
}

// Model: `size` depots each supply 10 units to their own store and the next
// two around a ring, at costs 1, 2 and 3. Every store needs 8, so the model is
// feasible and its size grows linearly.

type Ship {
  Ship(depot: Int, store: Int)
}

const lanes = [#(0, 1.0), #(1, 2.0), #(2, 3.0)]

fn transport(size: Int) -> vahvel.Model(Ship) {
  let sites = int.range(from: 0, to: size, with: [], run: list.prepend)
  let ship = fn(depot, offset) { Ship(depot, { depot + offset } % size) }
  let cost =
    list.flat_map(sites, fn(depot) {
      list.map(lanes, fn(lane) { vahvel.Linear(lane.1, ship(depot, lane.0)) })
    })
  let supply =
    list.map(sites, fn(depot) {
      let sent =
        list.map(lanes, fn(lane) { vahvel.Variable(ship(depot, lane.0)) })
      vahvel.LessEqual(vahvel.Sum(sent), vahvel.Constant(10.0))
    })
  let demand =
    list.map(sites, fn(store) {
      let received =
        list.map(lanes, fn(lane) {
          vahvel.Variable(Ship({ store - lane.0 + size } % size, store))
        })
      vahvel.GreaterEqual(vahvel.Sum(received), vahvel.Constant(8.0))
    })
  vahvel.Model(
    domain: fn(_) { vahvel.NonNegativeReal },
    objective: vahvel.Minimize(vahvel.Sum(cost)),
    constraints: list.append(supply, demand),
  )
}

fn solve_overhead(size: Int) -> Nil {
  let model = transport(size)
  let samples =
    repeat(fn() {
      let #(build, _) = time(fn() { transport(size) })
      let #(wall, outcome) = time(fn() { vahvel.solve(model) })
      let assert Ok(vahvel.Optimal(solution, stats)) = outcome
      let #(seconds, nanoseconds) =
        duration.to_seconds_and_nanoseconds(stats.solve_time)
      let solver = seconds * 1_000_000_000 + nanoseconds
      #(build, wall, solver, dict.size(vahvel.values(solution)))
    })
  let assert [#(_, _, _, vars), ..] = samples
  let terms = model_terms(model)
  let overhead = summary(list.map(samples, fn(s) { s.1 - s.2 }))
  print_row([
    int.to_string(size),
    int.to_string(vars),
    int.to_string(list.length(model.constraints)),
    int.to_string(terms),
    format(summary(list.map(samples, fn(s) { s.0 }))),
    format(summary(list.map(samples, fn(s) { s.1 }))),
    format(summary(list.map(samples, fn(s) { s.2 }))),
    format(overhead),
    int.to_string(overhead.median / terms),
  ])
}

fn residual_calls(size: Int) -> Nil {
  let model = transport(size)
  let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model)
  let lookup = vahvel.value(solution, _)
  let rows = list.length(model.constraints)
  let total =
    summary(
      repeat(fn() {
        let #(elapsed, _) =
          time(fn() {
            list.each(model.constraints, fn(c) {
              let assert Ok(_) = vahvel.residual(c, lookup)
            })
          })
        elapsed
      }),
    )
  print_row([
    int.to_string(rows),
    format(total),
    int.to_string(total.median / rows),
  ])
}

// Measurement

type Summary {
  Summary(median: Int, min: Int, max: Int)
}

/// Run `measure` for the warm-up runs, discarding them, then collect `runs`
/// samples.
fn repeat(measure: fn() -> a) -> List(a) {
  int.range(from: 0, to: warmup_runs, with: Nil, run: fn(_, _) {
    measure()
    Nil
  })
  int.range(from: 0, to: runs, with: [], run: fn(samples, _) {
    [measure(), ..samples]
  })
}

fn summary(nanoseconds: List(Int)) -> Summary {
  let sorted = list.sort(nanoseconds, int.compare)
  let assert [min, ..] = sorted
  let assert [max, ..] = list.reverse(sorted)
  let assert Ok(median) =
    list.drop(sorted, list.length(sorted) / 2) |> list.first
  Summary(median:, min:, max:)
}

type TimeUnit {
  Nanosecond
}

@external(erlang, "timer", "tc")
fn timer_tc(run: fn() -> a, unit: TimeUnit) -> #(Int, a)

/// Elapsed nanoseconds and the result.
fn time(run: fn() -> a) -> #(Int, a) {
  timer_tc(run, Nanosecond)
}

// Model size: variable references, counted with duplicates as they reach the
// driver.

fn model_terms(model: vahvel.Model(v)) -> Int {
  let objective = case model.objective {
    vahvel.Minimize(e) | vahvel.Maximize(e) -> e
  }
  list.fold(model.constraints, terms(objective), fn(count, c) {
    count + terms(c.lhs) + terms(c.rhs)
  })
}

fn terms(expression: vahvel.Expression(v)) -> Int {
  case expression {
    vahvel.Variable(_) | vahvel.Linear(..) -> 1
    vahvel.Constant(_) -> 0
    vahvel.Sum(expressions) -> int.sum(list.map(expressions, terms))
    vahvel.Difference(lhs, rhs) -> terms(lhs) + terms(rhs)
    vahvel.Scaled(_, e) -> terms(e)
  }
}

// Output

fn format(summary: Summary) -> String {
  let us = fn(ns) { int.to_string(ns / 1000) }
  us(summary.median) <> " [" <> us(summary.min) <> "–" <> us(summary.max) <> "]"
}

fn print_row(cells: List(String)) -> Nil {
  cells
  |> list.map(string.pad_start(_, 25, " "))
  |> string.join(" ")
  |> io.println
}
