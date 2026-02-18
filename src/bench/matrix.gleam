import bench/harness.{type BenchRow, BenchRow}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import waffle/matrix

@external(erlang, "nif", "bench_multiply_ns")
fn rust_bench_multiply(
  a_rows: Int,
  a_cols: Int,
  a: BitArray,
  b_rows: Int,
  b_cols: Int,
  b: BitArray,
  iterations: Int,
) -> Result(#(Int, Int), String)

// General matrix: a[i][j] = (i+j+1)*0.01 + 1.0.
fn make_matrix(n: Int) -> matrix.Matrix {
  let rows =
    list.repeat(Nil, n)
    |> list.index_map(fn(_, i) {
      list.repeat(Nil, n)
      |> list.index_map(fn(_, j) { int.to_float(i + j + 1) *. 0.01 +. 1.0 })
    })
  let assert Ok(m) = matrix.from_list(rows)
  m
}

pub fn from_list_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let rows =
      list.repeat(Nil, n)
      |> list.index_map(fn(_, i) {
        list.repeat(Nil, n)
        |> list.index_map(fn(_, j) { int.to_float(i + j + 1) *. 0.01 +. 1.0 })
      })
    harness.run(n, iters, fn() {
      let _ = matrix.from_list(rows)
    })
  })
}

pub fn multiply_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let a = make_matrix(n)
    let gleam_row =
      harness.run(n, iters, fn() {
        let _ = matrix.multiply(a, a)
      })
    let rows = matrix.rows(a)
    let cols = matrix.cols(a)
    let data = matrix.to_binary(a)
    let rust_result = case
      rust_bench_multiply(rows, cols, data, rows, cols, data, iters)
    {
      Ok(#(mean, stdev)) -> Some(#(mean, stdev))
      Error(_) -> None
    }
    BenchRow(..gleam_row, rust_result: rust_result)
  })
}

pub fn slice_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let a = make_matrix(n)
    let q = n / 4
    let h = n / 2
    // q + h = 3/4 n <= n, so slice bounds are always valid for these inputs.

    harness.run(n, iters, fn() {
      let _ = matrix.slice(a, q, h, q, h)
    })
  })
}

pub fn vstack_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let a = make_matrix(n)
    harness.run(n, iters, fn() {
      let _ = matrix.vstack(a, a)
    })
  })
}
