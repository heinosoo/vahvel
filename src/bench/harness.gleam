import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type BenchRow {
  BenchRow(
    size: Int,
    gleam_ns: Int,
    gleam_stdev_ns: Int,
    rust_result: Option(#(Int, Int)),
  )
}

@external(erlang, "bench_ffi", "monotonic_time_ns")
fn now() -> Int

pub fn run(size: Int, iterations: Int, f: fn() -> a) -> BenchRow {
  let warmup = int.max(iterations / 10, 3)
  list.repeat(Nil, warmup) |> list.each(fn(_) { f() })

  // Bulk pass: amortise two now() calls over all iterations for an accurate mean.
  let t0 = now()
  list.repeat(Nil, iterations) |> list.each(fn(_) { f() })
  let mean_ns = { now() - t0 } / iterations

  // Per-iteration pass for stdev. Timer overhead is a constant shift on every
  // sample; stdev is shift-invariant so the overhead does not inflate it.
  let times =
    list.repeat(Nil, iterations)
    |> list.map(fn(_) {
      let t0 = now()
      f()
      now() - t0
    })

  BenchRow(
    size: size,
    gleam_ns: mean_ns,
    gleam_stdev_ns: stdev(times),
    rust_result: None,
  )
}

fn stdev(times: List(Int)) -> Int {
  let n = list.length(times)
  case n {
    0 -> 0
    _ -> {
      let sum = list.fold(times, 0, fn(acc, t) { acc + t })
      let mean_f = int.to_float(sum) /. int.to_float(n)
      let variance =
        list.fold(times, 0.0, fn(acc, t) {
          let diff = int.to_float(t) -. mean_f
          acc +. diff *. diff
        })
        /. int.to_float(n)
      case float.square_root(variance) {
        Ok(s) -> float.round(s)
        Error(_) -> 0
      }
    }
  }
}

pub fn iterations_for_size(n: Int) -> Int {
  case n {
    _ if n <= 10 -> 5000
    _ if n <= 50 -> 500
    _ if n <= 100 -> 200
    _ if n <= 500 -> 50
    _ -> 10
  }
}

pub fn section_header(title: String) -> String {
  title <> "\n" <> string.repeat("=", string.length(title))
}

// Format nanoseconds as "X.Y" microseconds string. Handles negative values.
fn format_us(ns: Int) -> String {
  case ns < 0 {
    True -> "-" <> format_us(-ns)
    False -> {
      let tenths = ns / 100
      let whole = tenths / 10
      let frac = tenths % 10
      int.to_string(whole) <> "." <> int.to_string(frac)
    }
  }
}

fn size_label(size: Int) -> String {
  case size {
    0 -> "-"
    n -> int.to_string(n) <> "×" <> int.to_string(n)
  }
}

fn rust_str(row: BenchRow) -> String {
  case row.rust_result {
    None -> "-"
    Some(#(mean, _)) -> format_us(mean)
  }
}

fn rust_stdev_str(row: BenchRow) -> String {
  case row.rust_result {
    None -> "-"
    Some(#(_, stdev_ns)) -> format_us(stdev_ns)
  }
}

fn overhead_str(row: BenchRow) -> String {
  case row.rust_result {
    None -> "-"
    Some(#(rust_ns, _)) -> format_us(row.gleam_ns - rust_ns)
  }
}

fn ratio_str(row: BenchRow) -> String {
  case row.rust_result {
    None -> "-"
    Some(#(rust_ns, _)) ->
      case rust_ns > 0 {
        False -> "-"
        True -> {
          let ratio = int.to_float(row.gleam_ns) /. int.to_float(rust_ns)
          let tenths = float.round(ratio *. 10.0)
          let whole = tenths / 10
          let frac = tenths % 10
          int.to_string(whole) <> "." <> int.to_string(frac) <> "×"
        }
      }
  }
}

pub fn format_table(rows: List(BenchRow)) -> String {
  let header =
    string.pad_end("Size", 8, " ")
    <> "  "
    <> string.pad_start("Gleam (μs)", 10, " ")
    <> "  "
    <> string.pad_start("σ(μs)", 7, " ")
    <> "  "
    <> string.pad_start("Rust (μs)", 9, " ")
    <> "  "
    <> string.pad_start("σ(μs)", 7, " ")
    <> "  "
    <> string.pad_start("Overhead", 10, " ")
    <> "  "
    <> string.pad_start("Ratio", 7, " ")
  let sep =
    string.repeat("-", 8)
    <> "  "
    <> string.repeat("-", 10)
    <> "  "
    <> string.repeat("-", 7)
    <> "  "
    <> string.repeat("-", 9)
    <> "  "
    <> string.repeat("-", 7)
    <> "  "
    <> string.repeat("-", 10)
    <> "  "
    <> string.repeat("-", 7)
  let body =
    rows
    |> list.map(fn(row) {
      string.pad_end(size_label(row.size), 8, " ")
      <> "  "
      <> string.pad_start(format_us(row.gleam_ns), 10, " ")
      <> "  "
      <> string.pad_start(format_us(row.gleam_stdev_ns), 7, " ")
      <> "  "
      <> string.pad_start(rust_str(row), 9, " ")
      <> "  "
      <> string.pad_start(rust_stdev_str(row), 7, " ")
      <> "  "
      <> string.pad_start(overhead_str(row), 10, " ")
      <> "  "
      <> string.pad_start(ratio_str(row), 7, " ")
    })
    |> string.join("\n")
  header <> "\n" <> sep <> "\n" <> body
}
