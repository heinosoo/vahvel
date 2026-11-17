# Vahvel roadmap

Next milestone: publish the existing LP/MILP library on GitHub and Hex, built
from source with Rust. Keep the current Gleam modeling API unless a concrete
correctness or usability problem warrants a change.

Finished work is removed; git keeps the history. Current behavior belongs in
[ARCHITECTURE.md](ARCHITECTURE.md), decisions in [DESIGN.md](DESIGN.md), and
installation instructions in [README.md](README.md).

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
an acceptance criterion. Judge API additions by semantic clarity,
composability, predictable validation and public surface cost.

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
  analysis or convex QP. Duals must meet DESIGN.md's requirements; quadratics
  need capability-specific types and convexity rules. Clarabel is a candidate.
  Solver selection only once a second backend has a purpose.
- **Precompiled NIFs.** If requiring Rust prevents adoption. Size is not the
  obstacle (about 330 KB compressed per target); portable builds per target,
  pinned checksums and build provenance are. Keep the source build.
- **JavaScript through WASM.** For a browser or JS application; covers
  loading, execution and interruption.

Runtime model handles and reusable Gleam–Rust tooling are not planned.
