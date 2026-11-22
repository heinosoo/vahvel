# Vahvel roadmap

Next milestone: publish the existing LP/MILP library on GitHub and Hex, built
from source with Rust. Keep the current Gleam modeling API unless a concrete
correctness or usability problem warrants a change.

Finished work is removed; git keeps the history. Current behavior belongs in
[ARCHITECTURE.md](ARCHITECTURE.md), decisions (including what is out of scope)
in [DESIGN.md](DESIGN.md), and installation instructions in
[README.md](README.md).

## First public release

A release candidate is ready when a fresh consuming project can follow the
README, build the native library, and solve a model from both a Git dependency
and the prepared Hex package. Publication itself is a separate final step.

### Release process

The release workflows have not run on GitHub yet.

- Add the `HEXPM_API_KEY` repository secret.
- Run `release`, check the consumer results, then run `publish` on the tag.
  Record the smoke-test result and fix what the first run turns up.

## Conditional follow-up work

Possibilities, not commitments. Promote an item when a real use case supplies
an acceptance criterion, and judge API additions by DESIGN.md's "API
criteria and representative models".

- **Checking a supplied plan.** Extend evaluation to bounds, integrality and
  constraints. Needs defined tolerances and handling of missing assignments,
  numeric failures and multiple violations.
- **Model diagnostics.** If generated models are hard to debug, look at
  referenced variables, summaries and readable expressions together. Try
  application-owned row metadata before adding identity to the model.
  Printing a model doesn't explain infeasibility; that needs its own guidance.
- **Indexed construction.** Helpers such as key-driven row families, if
  mapping/grouping obscures models. Must handle mismatched lengths and
  duplicate keys; performance claims need measurements.
- **Backend limitations.** If workloads hit solver or numerical limits, extend
  the LP benchmark with representative MILPs and checked small cases before
  choosing a replacement. The signed 32-bit integer-domain limit stays
  documented until it blocks an application.
- **Duals and quadratic objectives.** For applications needing sensitivity
  analysis or convex QP. microlp 0.8 exposes LP duals and reduced costs, so
  duals need no second backend; for QP, Clarabel is a candidate. Solver selection only once a second backend has a purpose.
  Quadratics need their own expression type (DESIGN.md: "Expressions are an
  affine tree") and convexity rules. Duals are queried by constraint value and
  need, before shipping:
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
- **Precompiled NIFs.** If requiring Rust prevents adoption. Size is not the
  obstacle (about 330 KB compressed per target); portable builds per target,
  pinned checksums and build provenance are. Keep the source build.
- **JavaScript through WASM.** For a browser or JS application; covers
  loading, execution and interruption. The numeric rules already live in
  Rust, so a WASM build shares them: split the driver into a
  target-independent engine with thin Rustler and wasm-bindgen adapters.
