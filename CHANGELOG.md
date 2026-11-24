# Changelog

User-facing changes per release. The API is unstable while the package is
0.x, so any minor release may break it.

## Unreleased

First release on Hex.

- Describe linear and mixed-integer models as plain Gleam data, with variables
  keyed by your own types and real, integer or binary domains.
- `solve` and `solve_with` return optimal, infeasible, unbounded or
  budget-limited outcomes; `solve_with` adds time and node limits.
- Evaluate model expressions and constraint residuals at a solution or at any
  supplied values.
- Requires the Erlang target and Rust with `cargo`: the native library is
  built from source on first use, or ahead of time with
  `gleam run -m vahvel/setup`.
