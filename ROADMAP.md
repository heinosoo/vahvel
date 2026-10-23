# Waffle roadmap

Focus: an idiomatic Gleam optimization library with a small native solver layer.
These are rough priorities; API shapes and backend choices remain open. Finished
work is removed from this file; git log keeps it. Design decisions are in
[DESIGN.md](DESIGN.md).

## Next

- **Examples and performance.** More end-to-end examples, and a construction
  benchmark on larger sparse models; `stats(solution).solve_time` separates
  solving from construction and NIF overhead. Measure the per-term key lookup that stays
  in Gleam against the work done in Rust (DESIGN.md: "Describe in Gleam, compute
  in Rust").
- **Solve limits.** Time and iteration limits with an outcome that separates
  optimal, feasible-but-unproven and stopped results (DESIGN.md: "Solve
  limits"). microlp already supports this; the driver contract changes with it.
  The gap of a feasible result goes into `Stats`.
- **Dual values.** Needs a dual-capable backend and the requirements in
  DESIGN.md ("Dual values").
- **Truly unbounded integer variables.** A `None` integer bound currently stops
  at the signed 32-bit range. Needs microlp to accept infinite integer bounds (it
  stores them as floats internally) or another backend.

## Later

- **Convex quadratic objectives.** A separate quadratic type accepted only where
  a backend supports it, and validation of supported models.
- **Clarabel.** Evaluate Clarabel with its optional faer backend alongside
  microlp; its adapter builds CSC inside Rust.
- **Solver selection.** Automatic selection based on model capabilities, with an
  explicit override and clear errors for unsupported models.
- **JS target via WASM.** Split the Rust code into a target-independent engine
  and thin adapters (Rustler, wasm-bindgen).
- **Optional solver trace.** Only if debugging needs it: forward microlp's `log`
  output to Erlang's `logger`, off by default and never including model data.
  Statistics returned as data come first.

## Open questions

- Should keys become runtime-identified handles for models assembled from
  independent components, so cross-model mix-ups are detected?
- Would key-driven rows and bounds (`bound: fn(row) -> Interval`) serve large
  indexed constraint families better than per-row constraints?
- Does a representative model need a `scale` helper for reused expressions?
- Are domain shorthands (`Binary`, `NonNegative`) worth a second spelling?
- Should errors be collected rather than reporting the first, once diagnostics
  need it?
