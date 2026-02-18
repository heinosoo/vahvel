import bench/harness
import bench/linalg as linalg_bench
import bench/matrix as matrix_bench
import gleam/int
import gleam/io
import gleam/list
import gleam/result

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

@external(erlang, "bench_ffi", "argv")
fn argv() -> List(String)

fn iters_for(fixed: Int) -> fn(Int) -> Int {
  case fixed > 0 {
    True -> fn(_) { fixed }
    False -> harness.iterations_for_size
  }
}

pub fn main() {
  let fixed =
    argv()
    |> list.first
    |> result.try(int.parse)
    |> result.unwrap(0)
  let iters = iters_for(fixed)

  io.println("Preparing fixtures...\n")

  io.println("from_list scaling (Gleam marshalling cost)")
  io.println("==========================================")
  io.println(harness.format_table(matrix_bench.from_list_rows(iters)))
  io.println("")

  io.println("matrix.multiply — Gleam vs Rust")
  io.println("================================")
  io.println(
    harness.format_table(matrix_bench.multiply_rows(iters, rust_bench_multiply)),
  )
  io.println("")

  io.println("linalg.solve — Gleam vs Rust")
  io.println("=============================")
  io.println(
    harness.format_table(linalg_bench.solve_rows(iters, rust_bench_solve)),
  )
  io.println("")

  io.println("linalg.lu — Gleam vs Rust")
  io.println("==========================")
  io.println(harness.format_table(linalg_bench.lu_rows(iters, rust_bench_lu)))
  io.println("")
}
