# Vahvel roadmap

## Next

- **LP-format export.** CPLEX LP output of the lowered model, for inspection
  and cross-checking with other solvers. Needs valid, stable names derived
  from keys and deterministic output.

## Possibilities

Promoted when a real use case needs them.

- **Checking a supplied plan.** Extend evaluation to bounds, integrality and
  constraints. Needs defined tolerances and handling of missing assignments,
  numeric failures and multiple violations.
- **Model diagnostics.** Referenced variables, summaries and readable
  expressions, considered together. Try application-owned row metadata before
  adding identity to the model. Explaining infeasibility is a separate problem.
- **Indexed construction.** Helpers such as key-driven row families. Must
  handle mismatched lengths and duplicate keys; performance claims need
  measurements.
- **Backend limitations.** Before choosing a replacement solver, extend the LP
  benchmark with representative MILPs and checked small cases. The signed
  32-bit integer-domain limit stays documented.
- **Duals and quadratic objectives.** microlp 0.8 exposes LP duals and reduced
  costs, so duals need no second backend; Clarabel is a candidate for convex
  QP. Solver selection waits for a second backend. Quadratics need their own
  expression type (DESIGN.md: "Expressions are an affine tree") and convexity
  rules. Duals are queried by constraint value and need:
  - a definition (Lagrange multipliers or right-hand-side sensitivities) with
    signs per relation and objective direction;
  - bound duals and reduced costs, and a row map (the driver drops empty rows
    before calling the solver);
  - availability typed independently of primal availability, with an explicit
    "unavailable" rather than zero, NaN or invented prices;
  - no LP shadow prices for MILP incumbents; relaxations or fixed-integer
    resolves are separate, explicit models;
  - verification with analytic LPs, KKT conditions and right-hand-side
    perturbation.
- **Precompiled NIFs.** Per-target libraries in the Hex tarball (about 440 KB
  compressed each), with the Cargo build as fallback. Most of the work is CI:
  a target matrix, portable builds (pinned glibc, musl) and a load test per
  target. [niffler_precompiled](https://hex.pm/packages/niffler_precompiled)
  is a download-based alternative.
- **JavaScript through WASM.** Covers loading, execution and interruption. The
  numeric rules already live in Rust, so a WASM build shares them: split the
  driver into a target-independent engine with thin Rustler and wasm-bindgen
  adapters.
