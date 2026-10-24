# Waffle roadmap

Focus: an idiomatic Gleam optimization library with a small native solver layer.
These are rough priorities; API shapes and backend choices remain open. Finished
work is removed from this file; git log keeps it. Design decisions are in
[DESIGN.md](DESIGN.md).

## Next

- **Solve limits.** Time and iteration limits with an outcome that separates
  optimal, feasible-but-unproven and stopped results (DESIGN.md: "Solve
  limits"). microlp already supports this; the driver contract changes with it.
  The gap of a feasible result goes into `Stats`.
- **Performance.** Benchmark construction on larger sparse models, starting
  with the production network's `instance(size)`;
  `stats(solution).solve_time` separates solving from construction and NIF
  overhead. Measure the per-term key lookup that stays in Gleam against the work
  done in Rust (DESIGN.md: "Describe in Gleam, compute in Rust"). Benchmark
  nested expression construction and evaluation, including column discovery,
  canonicalization, NIF decoding and dirty-scheduler overhead. Use results to
  decide whether a bounded fast path for small evaluations is worthwhile.

## Later

### API

Judge additions by semantic clarity, composability, predictable validation and
public surface cost; examples provide ergonomic evidence, not the sole
acceptance criterion.

- **Checking a supplied plan.** Go beyond residuals to verdicts: check
  variable bounds, integrality and constraints. Define tolerances (solver
  results satisfy rows only within microlp's) and distinguish missing
  assignments, domain violations, constraint violations and numeric failures.
  A plan can satisfy every row while assigning fractional trucks.
- **Model inspection.** Inspect generated constraints, referenced variables and
  their domains before solving. Determine what helps diagnose incorrectly
  assembled models, and how it relates to expression printing under Diagnostics.
- **Constraint identity and metadata.** Investigate locating a generated row by
  application meaning, such as warehouse and period. Assess whether metadata
  maintained alongside constraints is sufficient before adding names or keys to
  the model; account for duplicate rows and changes across scenarios.
- **Indexed construction.** Investigate repeated mapping, grouping and filtering
  in sparse scheduling, assignment and network models. Add helpers only for
  recurring concepts with clear composition or error-prevention benefits over
  ordinary collections. Any paired-data operation must address mismatched
  lengths and duplicate keys explicitly; measure construction costs where
  performance motivates an abstraction.

### Backends

- **Dual values.** Needs a dual-capable backend and the requirements in
  DESIGN.md ("Dual values").
- **Truly unbounded integer variables.** A `None` integer bound currently stops
  at the signed 32-bit range. Needs microlp to accept infinite integer bounds (it
  stores them as floats internally) or another backend.
- **Convex quadratic objectives.** A separate quadratic type accepted only where
  a backend supports it, and validation of supported models.
- **Clarabel.** Evaluate Clarabel with its optional faer backend alongside
  microlp; its adapter builds CSC inside Rust.
- **Solver selection.** Automatic selection based on model capabilities, with an
  explicit override and clear errors for unsupported models.

### Distribution

- **Precompiled NIFs.** Download prebuilt libraries so users need no Rust
  toolchain, like Elixir's `rustler_precompiled`. Today the release binary
  isn't portable and everyone builds from source. Users then run machine code
  they can't audit against the source, so: pin each binary's checksum in the
  Hex package, build in public CI with provenance (Gleam's own releases ship
  sigstore attestations and SBOMs), and keep building from source first-class
  for users whose policies require it. Gleam's maintainers consider
  ecosystem-wide binary distribution too costly to certify
  ([gleam#3165](https://github.com/gleam-lang/gleam/discussions/3165)), so this
  stays per package. libsql_gleam and glimra ship precompiled NIFs but don't
  document how.
- **Reusable Gleam–Rust NIF tooling.** Extract the setup, build and
  version-check flow (and precompiled downloads, once they exist) into a small
  package that doesn't depend on optimization. Gleam has no build hooks, so
  other Gleam projects with Rust NIFs rebuild the same plumbing. Watch
  [Gleamler](https://github.com/chlonishe/gleamler), which generates Gleam
  bindings, types and the Erlang stub from Rust (early, and Rust becomes the
  source of the contract), and Rustler's
  [#777](https://github.com/rusterlium/rustler/pull/777), which embeds NIF
  signatures so wrapper stubs can be generated (draft, Elixir-only).
- **JS target via WASM.** Split the Rust code into a target-independent engine
  and thin adapters (Rustler, wasm-bindgen).

### Diagnostics

- **Expression printing (tentative).** Render expressions and constraints
  readably for debugging and error messages, e.g. `3·Chair + 2·Table + 7 ≤ 4`.
  Keys are arbitrary values, so callers would pass a `fn(v) -> String` or
  accept `string.inspect`. Only if debugging or diagnostics need it.
- **Optional solver trace.** Only if debugging needs it: forward microlp's `log`
  output to Erlang's `logger`, off by default and never including model data.
  Statistics returned as data come first.

## Open questions

- Should keys become runtime-identified handles for models assembled from
  independent components, so cross-model mix-ups are detected?
- Would key-driven rows and bounds (`bound: fn(row) -> Interval`) serve large
  indexed constraint families better than per-row constraints?
- Should errors be collected rather than reporting the first, once diagnostics
  need it?
