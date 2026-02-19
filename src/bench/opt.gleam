import bench/harness.{type BenchRow}
import gleam/int
import gleam/list
import gleam/result
import waffle/opt

// Row sum formula: sum_j((i+j+1)*0.01) for j=0..n-1
//   = 0.01 * (n*(i+1) + n*(n-1)/2)
// Expressed in integers to avoid accumulated float error.
fn row_bound(n: Int, i: Int, fraction: Float) -> Float {
  int.to_float(n * { i + 1 } + n * { n - 1 } / 2) *. 0.01 *. fraction
}

/// Benchmark continuous LP: N variables, N dense constraints.
///
/// Constraint i: sum_j((i+j+1)*0.01 * x_j) <= 0.6 * row_sum.
/// Objective: minimize -sum(x_i). Variables in [0, 1].
///
/// The N×N dense coefficient matrix gives O(N²) data and O(N³) solve
/// work, scaling similarly to the linalg dense solvers.
pub fn solve_cont_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let #(model, vars) = opt.cont_vars(opt.new(), n, "x", -1.0, 0.0, 1.0)
    let assert Ok(model) =
      int.range(from: 0, to: n, with: Ok(model), run: fn(acc, i) {
        use m <- result.try(acc)
        let coeffs =
          list.index_map(vars, fn(v, j) {
            #(v, int.to_float(i + j + 1) *. 0.01)
          })
        opt.add_le_constraint(m, row_bound(n, i, 0.6), coeffs)
      })
    harness.run(n, iters, fn() {
      let _ = opt.solve(model)
    })
  })
}

/// Benchmark integer LP: N binary variables, N/8 dense constraints.
///
/// Same coefficient structure as the LP bench. Fewer constraints than the
/// LP case to keep branch-and-bound tractable at larger N values.
pub fn solve_ilp_rows(sizes: List(Int), iters: Int) -> List(BenchRow) {
  sizes
  |> list.map(fn(n) {
    let #(model, vars) =
      int.range(from: 0, to: n, with: #(opt.new(), []), run: fn(acc, i) {
        let #(m, vs) = acc
        let #(m, v) =
          opt.int_var(
            m,
            "x_" <> int.to_string(i),
            0.0 -. int.to_float(i + 1),
            0.0,
            1.0,
          )
        #(m, [v, ..vs])
      })
    let vars = list.reverse(vars)
    let num_constraints = int.max(1, n / 8)
    let assert Ok(model) =
      int.range(from: 0, to: num_constraints, with: Ok(model), run: fn(acc, i) {
        use m <- result.try(acc)
        let coeffs =
          list.index_map(vars, fn(v, j) {
            #(v, int.to_float(i + j + 1) *. 0.01)
          })
        opt.add_le_constraint(m, row_bound(n, i, 0.9), coeffs)
      })
    harness.run(n, iters, fn() {
      let _ = opt.solve(model)
    })
  })
}
