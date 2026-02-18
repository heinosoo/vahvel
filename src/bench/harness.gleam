import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub type BenchRow {
  BenchRow(
    label: String,
    size: Int,
    gleam_ns: Int,
    gleam_stdev_ns: Int,
    rust_ns: Int,
    rust_stdev_ns: Int,
  )
}

@external(erlang, "bench_ffi", "monotonic_time_ns")
fn now() -> Int

pub fn run(label: String, size: Int, iterations: Int, f: fn() -> a) -> BenchRow {
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
    label: label,
    size: size,
    gleam_ns: mean_ns,
    gleam_stdev_ns: stdev(times),
    rust_ns: 0,
    rust_stdev_ns: 0,
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
  case row.rust_ns {
    0 -> "-"
    r -> format_us(r)
  }
}

fn rust_stdev_str(row: BenchRow) -> String {
  case row.rust_ns {
    0 -> "-"
    _ -> format_us(row.rust_stdev_ns)
  }
}

fn overhead_str(row: BenchRow) -> String {
  case row.rust_ns {
    0 -> "-"
    r -> format_us(row.gleam_ns - r)
  }
}

pub fn format_table(rows: List(BenchRow)) -> String {
  let header =
    string.pad_end("Operation", 20, " ")
    <> "  "
    <> string.pad_end("Size", 6, " ")
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
  let sep =
    string.repeat("-", 20)
    <> "  "
    <> string.repeat("-", 6)
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
  let body =
    rows
    |> list.map(fn(row) {
      string.pad_end(row.label, 20, " ")
      <> "  "
      <> string.pad_end(size_label(row.size), 6, " ")
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
    })
    |> string.join("\n")
  header <> "\n" <> sep <> "\n" <> body
}
