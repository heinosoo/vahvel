# Waffle — Roadmap

Step-by-step implementation plan. Each step builds on the previous one. Do not skip ahead.

> **Note:** This roadmap shows the original implementation path. The current codebase has been reorganized for clarity:
> - Modules moved from `src/waffle/*.gleam` to `src/*.gleam` (flat structure)
> - `compile.gleam` renamed to `build.gleam` (Erlang module name collision)
> - FFI files consolidated into `src/ffi/` directory (`nif.erl` and `platform.erl`)
> - Module references updated (`waffle/module` → `module`, `waffle_ffi` → `nif`)

---

## Step 0 — ~Skeleton~ (Gleam + Rust interop without faer) ✅

Goal: Prove that a Gleam project can call a Rust NIF and get a result back.

- [x] `gleam new waffle` — create the project
- [x] Create `native/waffle/Cargo.toml` with `rustler` as the only dependency
- [x] Create `native/waffle/src/lib.rs` with a trivial NIF: `add_floats(a: f64, b: f64) -> f64`
- [x] Create `src/waffle_ffi.erl` — Erlang module that loads the NIF shared library from `priv/`
- [x] Create `src/waffle.gleam` with `@external(erlang, "waffle_ffi", "add_floats")` binding
- [x] Build Rust: `cd native/waffle && cargo build --release`
- [x] Copy the shared library to `priv/`
- [x] Write a test that calls `waffle.add_floats(1.0, 2.0)` and asserts `3.0`
- [x] Verify `gleam test` passes

**Milestone:** NIF round-trip works. Gleam calls Rust and gets a result.

---

## Step 1 — ~Matrix type~ ✅

Goal: Define the core Matrix type in pure Gleam. No NIF needed.

- [x] Create `src/waffle/matrix.gleam`
- [x] Define opaque `Matrix` type: rows, cols, data as `BitArray` (column-major f64)
- [x] Implement `from_list(List(List(Float))) -> Result(Matrix, MatrixError)` — validates dimensions, transposes row-major input to column-major
- [x] Implement `to_list(Matrix) -> List(List(Float))` — reverse conversion
- [x] Implement `rows(Matrix) -> Int`, `cols(Matrix) -> Int`
- [x] Implement `identity(n: Int) -> Result(Matrix, MatrixError)`
- [x] Add helper functions to `waffle_ffi.erl` for float ↔ binary conversion
- [x] Write tests: round-trip `from_list` → `to_list`, dimension helpers, identity matrix, error cases (ragged lists, empty input)

**Milestone:** Matrix type is usable from Gleam. All tests pass without any NIF.

---

## Step 2 — ~faer solver NIF~ ✅

Goal: Solve `Ax = b` via LU decomposition in Rust, callable from Gleam.

- [x] Add `faer` to `native/waffle/Cargo.toml`
- [x] Implement `solve_linear_system` NIF in `lib.rs`:
  - `#[rustler::nif(schedule = "DirtyCpu")]`
  - Accept: rows, cols, matrix binary, rhs binary
  - Validate binary lengths
  - Build matrices from column-major binary data
  - LU decomposition with partial pivoting
  - Wrap in `catch_unwind` for singular matrix safety
  - Return `{ok, result_binary}` or `{error, reason}`
- [x] Register NIF in `rustler::init!`
- [x] Update `waffle_ffi.erl` with the new function stub
- [x] Create `src/waffle/solver.gleam`:
  - `pub fn solve(a: Matrix, b: Matrix) -> Result(Matrix, SolverError)`
  - Validate dimensions (`a` is square, `b` rows match `a` rows)
  - Call NIF, wrap result in `Matrix`
- [x] Tests with known solutions:
  - Identity matrix: `Ix = b` → `x = b`
  - Simple 2x2 and 3x3 systems
  - Singular matrix → error
  - Dimension mismatch → error

**Milestone:** `solver.solve` works end-to-end. Gleam → Erlang → Rust → faer → result.

---

## Step 3 — ~Smart build script~ ✅

Goal: Users run `gleam run -m waffle/setup` and get a working native library without installing Rust.

- [x] Create `src/waffle/compile.gleam` with `main()` entry point and `pub fn do_compile()` function
  - Check if `cargo` is available
  - Run `cargo build --release` in `native/waffle/`
  - Copy artifact to `priv/waffle.so` (or `.dylib`/`.dll`)
  - Print clear error message with instructions if cargo not available
- [x] Create `src/waffle/setup.gleam` with `main()` entry point
  - Check if NIF exists and version matches (via `waffle/version`)
  - If missing or version mismatch: fall back to `compile.do_compile()`
  - Support `--force` flag for manual rebuilds
  - (HTTP download of precompiled binaries deferred to Step 4)
- [x] Add NIF version embedding (`nif_version` NIF returns `CARGO_PKG_VERSION`)
- [x] Add version tests to catch drift between `gleam.toml`, `version.gleam`, and `Cargo.toml`
- [x] Test both scripts manually on at least one platform

**Milestone:** `gleam run -m waffle/setup` produces a working `priv/waffle.so`. `gleam run -m waffle/compile` always builds from source (useful for CI, development, or users who prefer local builds).

---

## Step 4 — ~CI lanes~ ✅

Goal: Automated test and release CI lanes.

> **Note:** Multi-platform builds (macOS, Windows) are deferred — a commented-out matrix placeholder is in `release.yml`.

- [x] Update CI test workflow to use `gleam run -m waffle/compile` instead of direct cargo commands
- [x] Add Rust quality checks to test lane: `cargo fmt --check`, `cargo clippy -- -D warnings`
- [x] Create release workflow (`workflow_dispatch`) that bumps version in all 3 files, runs tests, tags, and creates a GitHub Release
- [x] Upload Linux x86_64 NIF binary as release asset
- [ ] Expand to multi-platform matrix (macOS, Windows) — placeholder added, deferred
- [ ] Update `waffle/setup` to download precompiled binaries from release assets — deferred

**Milestone:** Test lane catches formatting/lint/test failures. Release lane bumps version, tags, and publishes a GitHub Release with NIF binary.

---

## Step 5 — ~API expansion~ ✅

Additional linear algebra operations, each following the same NIF pattern:

- [x] Matrix multiply (`A * B`)
- [x] Matrix inverse
- [x] Determinant
- [x] Eigenvalues (symmetric)
- [x] SVD (singular value decomposition)
- [x] QR decomposition
- [x] Element-wise operations (add, subtract, scale)
- [x] Transpose

Each operation: Rust NIF with DirtyCpu + catch_unwind, Gleam wrapper, tests with known results.

---

## Step 6 — ILP Solver (Highs)

Goal: Solve Mixed-Integer Linear Programming (MILP) problems using the HiGHS C++ solver, bundled in the same NIF.

- [ ] Add `highs` dependency to `native/waffle/Cargo.toml`
- [ ] **Crucial:** Configure static C++ linking (`-static-libstdc++`) in `native/waffle/.cargo/config.toml` or `build.rs`.
      *Rationale:* `highs` depends on the C++ runtime. Statically linking it ensures the `.so` remains portable across different Linux distributions.
- [ ] Create `src/waffle/optimization.gleam`
  - Define types for the "Standard Form": Minimize $c^T x$ subject to $L \le Ax \le U$.
  - `pub fn solve_ilp(objective: Matrix, constraints: Matrix, ...) -> Result(Solution, Error)`
- [ ] Implement `solve_ilp` NIF in `lib.rs`:
  - `#[rustler::nif(schedule = "DirtyCpu")]`
  - Accept `faer` matrix data directly (zero-copy inputs where possible).
  - Map Gleam matrices to HiGHS model.
  - Return `{ok, solution_vector}` or `{error, status}`.
- [ ] Tests:
  - Simple LP (continuous variables only).
  - Simple ILP (integer constraints, e.g., maximize $x+y$ where $2x+2y \le 9$ and $x,y \in \mathbb{Z}$).

**Milestone:** Users can solve optimization problems. The library now covers both Linear Algebra and Operations Research.

---

## Step 7 — Polish and publish

- [ ] Publish to Hex (`gleam publish`)
- [ ] Generate and host documentation
- [ ] Benchmarks (compare with equivalent Python/NumPy operations)
- [ ] Usage examples in README

