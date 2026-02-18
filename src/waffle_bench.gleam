import bench/harness.{type BenchRow}
import bench/linalg as linalg_bench
import bench/matrix as matrix_bench
import gleam/int
import gleam/io
import gleam/list
import gleam/result

@external(erlang, "bench_ffi", "argv")
fn argv() -> List(String)

fn print_section(title: String, bench: fn() -> List(BenchRow)) -> Nil {
  io.println(harness.section_header(title))
  io.println(harness.format_table(bench()))
  io.println("")
}

pub fn main() {
  let iters = case argv() |> list.first |> result.try(int.parse) {
    Ok(n) if n > 0 -> n
    _ -> 20
  }

  let sizes = [16, 64, 256, 1024]

  print_section("from_list scaling (Gleam marshalling cost)", fn() {
    matrix_bench.from_list_rows(sizes, iters)
  })

  print_section("matrix.multiply", fn() {
    matrix_bench.multiply_rows(sizes, iters)
  })

  print_section("linalg.solve", fn() { linalg_bench.solve_rows(sizes, iters) })

  print_section("linalg.lu", fn() { linalg_bench.lu_rows(sizes, iters) })

  print_section("matrix.slice", fn() { matrix_bench.slice_rows(sizes, iters) })

  print_section("matrix.vstack", fn() { matrix_bench.vstack_rows(sizes, iters) })
}
