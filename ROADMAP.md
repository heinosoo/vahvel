# Waffle — Roadmap

Step-by-step implementation plan. Each step builds on the previous one. Do not skip ahead.

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

## Step 4 — CI and precompiled binaries

Goal: Automated builds and releases for all platforms.

> **Note:** Basic Linux x86_64 build was added to CI earlier (after Step 2) to keep tests passing. This step will expand that to full multi-platform support and release artifacts.

- [ ] Expand GitHub Actions workflow to build NIF on multiple platforms:
  - Linux (x86_64)
  - macOS (x86_64, aarch64)
  - Windows (x86_64)
- [ ] Upload compiled binaries as release assets on tagged releases
- [ ] Enhance CI workflow with additional checks: `cargo fmt --check`, `cargo clippy`
- [ ] Update CI to use `gleam run -m waffle/compile` instead of direct cargo commands
- [ ] Test that `gleam run -m waffle/setup` can download from the release artifacts

**Milestone:** Push a tag, binaries are built and uploaded. CI catches formatting and test failures.

---

## Step 5 — API expansion (future)

Additional linear algebra operations, each following the same NIF pattern:

- [ ] Matrix multiply (`A * B`)
- [ ] Matrix inverse
- [ ] Determinant
- [ ] Eigenvalues / eigenvectors
- [ ] SVD (singular value decomposition)
- [ ] QR decomposition
- [ ] Element-wise operations (add, subtract, scale)

Each operation: Rust NIF with DirtyCpu + catch_unwind, Gleam wrapper, tests with known results.

---

## Step 6 — Polish and publish

- [ ] Publish to Hex (`gleam publish`)
- [ ] Generate and host documentation
- [ ] Benchmarks (compare with equivalent Python/NumPy operations)
- [ ] Usage examples in README
