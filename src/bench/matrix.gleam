import bench/harness.{type BenchRow, BenchRow}
import gleam/int
import gleam/list
import waffle/matrix

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

pub fn from_list_rows(iters_for: fn(Int) -> Int) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let rows =
      list.repeat(Nil, n)
      |> list.index_map(fn(_, i) {
        list.repeat(Nil, n)
        |> list.index_map(fn(_, j) { int.to_float(i + j + 1) *. 0.01 +. 1.0 })
      })
    harness.run("matrix.from_list", n, iters, fn() {
      let _ = matrix.from_list(rows)
    })
  })
}

pub fn multiply_rows(
  iters_for: fn(Int) -> Int,
  rust_bench: fn(Int, Int, BitArray, Int, Int, BitArray, Int) ->
    Result(#(Int, Int), String),
) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let a = make_matrix(n)
    let gleam_row =
      harness.run("matrix.multiply", n, iters, fn() {
        let _ = matrix.multiply(a, a)
      })
    let rows = matrix.rows(a)
    let cols = matrix.cols(a)
    let data = matrix.to_binary(a)
    let #(rust_ns, rust_stdev_ns) = case
      rust_bench(rows, cols, data, rows, cols, data, iters)
    {
      Ok(#(mean, stdev)) -> #(mean, stdev)
      Error(_) -> #(0, 0)
    }
    BenchRow(..gleam_row, rust_ns: rust_ns, rust_stdev_ns: rust_stdev_ns)
  })
}

pub fn slice_rows(iters_for: fn(Int) -> Int) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let a = make_matrix(n)
    let q = n / 4
    let h = n / 2
    // q + h = 3/4 n <= n, so slice bounds are always valid for these inputs.

    harness.run("matrix.slice", n, iters, fn() {
      let _ = matrix.slice(a, q, h, q, h)
    })
  })
}

pub fn vstack_rows(iters_for: fn(Int) -> Int) -> List(BenchRow) {
  [10, 50, 100, 500]
  |> list.map(fn(n) {
    let iters = iters_for(n)
    let a = make_matrix(n)
    harness.run("matrix.vstack", n, iters, fn() {
      let _ = matrix.vstack(a, a)
    })
  })
}
