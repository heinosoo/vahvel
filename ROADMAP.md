# Waffle — Roadmap

Step-by-step implementation plan. Each step builds on the previous one. Do not skip ahead.

---

## Step 0 — Skeleton (Gleam + Rust interop without faer)

Goal: Prove that a Gleam project can call a Rust NIF and get a result back.

- [ ] `gleam new waffle` — create the project
- [ ] Create `native/waffle/Cargo.toml` with `rustler` as the only dependency
- [ ] Create `native/waffle/src/lib.rs` with a trivial NIF: `add_floats(a: f64, b: f64) -> f64`
- [ ] Create `src/waffle_ffi.erl` — Erlang module that loads the NIF shared library from `priv/`
- [ ] Create `src/waffle.gleam` with `@external(erlang, "waffle_ffi", "add_floats")` binding
- [ ] Build Rust: `cd native/waffle && cargo build --release`
- [ ] Copy the shared library to `priv/`
- [ ] Write a test that calls `waffle.add_floats(1.0, 2.0)` and asserts `3.0`
- [ ] Verify `gleam test` passes

**Milestone:** NIF round-trip works. Gleam calls Rust and gets a result.

---

## Step 1 — Matrix type

Goal: Define the core Matrix type in pure Gleam. No NIF needed.

- [ ] Create `src/waffle/matrix.gleam`
- [ ] Define opaque `Matrix` type: rows, cols, data as `BitArray` (column-major f64)
- [ ] Implement `from_list(List(List(Float))) -> Result(Matrix, MatrixError)` — validates dimensions, transposes row-major input to column-major
- [ ] Implement `to_list(Matrix) -> List(List(Float))` — reverse conversion
- [ ] Implement `rows(Matrix) -> Int`, `cols(Matrix) -> Int`
- [ ] Implement `identity(n: Int) -> Matrix`
- [ ] Write tests: round-trip `from_list` → `to_list`, dimension helpers, identity matrix, error cases (ragged lists, empty input)

**Milestone:** Matrix type is usable from Gleam. All tests pass without any NIF.

---

## Step 2 — faer solver NIF

Goal: Solve `Ax = b` via LU decomposition in Rust, callable from Gleam.

- [ ] Add `faer` to `native/waffle/Cargo.toml`
- [ ] Implement `solve_linear_system` NIF in `lib.rs`:
  - `#[rustler::nif(schedule = "DirtyCpu")]`
  - Accept: rows, cols, matrix binary, rhs binary
  - Validate binary lengths
  - Zero-copy view as `&[f64]`
  - Create `faer::MatRef` (column-major)
  - LU decomposition with partial pivoting
  - Wrap in `catch_unwind` for singular matrix safety
  - Return `{ok, result_binary}` or `{error, reason}`
- [ ] Register NIF in `rustler::init!`
- [ ] Update `waffle_ffi.erl` with the new function stub
- [ ] Create `src/waffle/solver.gleam`:
  - `pub fn solve(a: Matrix, b: Matrix) -> Result(Matrix, SolverError)`
  - Validate dimensions (`a` is square, `b` rows match `a` rows)
  - Call NIF, wrap result in `Matrix`
- [ ] Tests with known solutions:
  - Identity matrix: `Ix = b` → `x = b`
  - Simple 2x2 and 3x3 systems
  - Singular matrix → error
  - Dimension mismatch → error

**Milestone:** `solver.solve` works end-to-end. Gleam → Erlang → Rust → faer → result.

---

## Step 3 — Smart build script

Goal: Users run `gleam run -m waffle/build` and get a working native library without installing Rust.

- [ ] Create `src/waffle/build.gleam` with `main()` entry point
- [ ] Detect OS and architecture (via Erlang FFI)
- [ ] Construct download URL from OS/arch/version
- [ ] Attempt HTTP download of precompiled binary
- [ ] On success: save to `priv/waffle.so` (or `.dylib`/`.dll`)
- [ ] On failure: check if `cargo` is available
- [ ] If cargo available: run `cargo build --release`, copy artifact to `priv/`
- [ ] If no cargo: print clear error message with instructions
- [ ] Test the script manually on at least one platform

**Milestone:** `gleam run -m waffle/build` produces a working `priv/waffle.so`.

---

## Step 4 — CI and precompiled binaries

Goal: Automated builds and releases for all platforms.

- [ ] GitHub Actions workflow: build NIF on Linux (x86_64), macOS (x86_64, aarch64), Windows (x86_64)
- [ ] Upload compiled binaries as release assets on tagged releases
- [ ] CI workflow: `gleam test`, `gleam format --check`, `cargo fmt --check`, `cargo clippy`
- [ ] Test that the build script can download from the release artifacts

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
