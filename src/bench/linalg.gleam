import bench/harness.{type BenchRow, BenchRow}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import waffle/linalg
import waffle/matrix

@external(erlang, "nif", "bench_solve_ns")
fn rust_bench_solve(
  rows: Int,
  cols: Int,
  a: BitArray,
  b: BitArray,
  iterations: Int,
) -> Result(#(Int, Int), String)

@external(erlang, "nif", "bench_lu_ns")
fn rust_bench_lu(
  n: Int,
  a: BitArray,
  iterations: Int,
) -> Result(#(Int, Int), String)

// Diagonally dominant n×n matrix: (n+1) on diagonal, (i+j+1)*0.01 off-diagonal.
fn make_square(n: Int) -> matrix.Matrix {
  let rows =
    list.repeat(Nil, n)
    |> list.index_map(fn(_, i) {
      list.repeat(Nil, n)
      |> list.index_map(fn(_, j) {
        case i == j {
          True -> int.to_float(n + 1)
          False -> int.to_float(i + j + 1) *. 0.01
        }
      })
    })
  let assert Ok(m) = matrix.from_list(rows)
  m
}

fn make_vector(n: Int) -> matrix.Matrix {
  let assert Ok(v) = matrix.ones(n, 1)
  v
}

pub fn solve_rows(iters_for: fn(Int) -> Int) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let a = make_square(n)
    let b = make_vector(n)
    let gleam_row =
      harness.run(n, iters, fn() {
        let _ = linalg.solve(a, b)
      })
    let rust_result = case
      rust_bench_solve(
        matrix.rows(a),
        matrix.cols(a),
        matrix.to_binary(a),
        matrix.to_binary(b),
        iters,
      )
    {
      Ok(#(mean, stdev)) -> Some(#(mean, stdev))
      Error(_) -> None
    }
    BenchRow(..gleam_row, rust_result: rust_result)
  })
}

pub fn lu_rows(iters_for: fn(Int) -> Int) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let a = make_square(n)
    let gleam_row =
      harness.run(n, iters, fn() {
        let _ = linalg.lu(a)
      })
    let rust_result = case
      rust_bench_lu(matrix.rows(a), matrix.to_binary(a), iters)
    {
      Ok(#(mean, stdev)) -> Some(#(mean, stdev))
      Error(_) -> None
    }
    BenchRow(..gleam_row, rust_result: rust_result)
  })
}
