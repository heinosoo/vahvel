# Phase 2: The "Numpy" Essentials (Functional API)

**Goal:** Make the library "gleam-idiomatic" and ergonomic by adding functional array manipulations and statistical generation.

> **Note:** Implementation order is not strict. Each area can be implemented independently.

## Implementation Approach

| Area | Approach | Reason |
|------|----------|--------|
| Functional (`map`, `fold`, `zip_with`) | Pure Gleam | Passing closures to Rust NIFs is complex; optimize later if needed |
| Randomness | NIFs | Need Rust's `rand` crate for quality RNG |
| Slicing | Pure Gleam | Simple binary operations, returns copies |
| Utilities | Pure Gleam | Reshape/stack are just binary manipulation |

**Suggested order (not strict):**
1. Utilities (`reshape`, `vstack`, `hstack`, `to_string`)
2. Views & Slicing (`slice`, `row`, `col`)
3. Functional Transformations (`map`, `fold`, `zip_with`)
4. Randomness (`uniform`, `normal`, `bernoulli`)

---

## 1. Utilities & Polish

Pure Gleam implementation. No Rust changes needed.

- [ ] **Reshape**
  - `matrix.reshape(m, rows, cols) -> Result(Matrix, MatrixError)`
  - Validate that `rows * cols == matrix.rows * matrix.cols`
  - Just update dimensions, data stays the same
- [ ] **Stacking**
  - `matrix.vstack(top, bottom) -> Result(Matrix, MatrixError)` (vertical concat)
  - `matrix.hstack(left, right) -> Result(Matrix, MatrixError)` (horizontal concat)
  - Validate matching column/row counts
- [ ] **Pretty Printing**
  - `matrix.to_string(m) -> String`
  - Align columns for readable CLI output
  - Use fixed precision (e.g., 6 decimal places)

## 2. Views & Slicing

Pure Gleam implementation. Returns copies (not views) to keep `Matrix` simple.

- [ ] **Slicing**
  - `matrix.slice(m, row_start, row_count, col_start, col_count) -> Result(Matrix, MatrixError)`
  - Validate bounds
  - Copy data into new matrix
- [ ] **Row/Col Access**
  - `matrix.row(m, index) -> Result(List(Float), MatrixError)`
  - `matrix.col(m, index) -> Result(List(Float), MatrixError)`
  - Validate index in bounds

## 3. Functional Transformations

Pure Gleam implementation. Iterate over binary data using `bit_array.slice`.

- [ ] **Map**
  - `matrix.map(m, fn(Float) -> Float) -> Matrix`
  - Apply function to each element, return new matrix
- [ ] **Fold**
  - `matrix.fold(m, acc, fn(acc, Float) -> acc) -> acc`
  - Useful for sum, max, min, any, all
- [ ] **Zip With**
  - `matrix.zip_with(a, b, fn(Float, Float) -> Float) -> Result(Matrix, MatrixError)`
  - Element-wise binary operation
  - Validate same dimensions

## 4. Randomness & Distributions

Requires Rust NIFs with `rand` crate.

- [ ] **Module Setup**
  - Create `src/waffle/random.gleam`
  - Add `rand` crate to `native/waffle/Cargo.toml`
  - Add NIF stubs to `src/waffle/internal/ffi/nif.erl`
- [ ] **Distributions**
  - `random.uniform(rows, cols, min, max) -> Matrix`
  - `random.normal(rows, cols, mean, std_dev) -> Matrix`
  - `random.bernoulli(rows, cols, p) -> Matrix` (0.0/1.0 values)
- [ ] **Seeding**
  - Optional `seed: Option(Int)` parameter on each function
  - If provided, seed the RNG before generating
  - If not provided, use system entropy (default)

---

## FAQ and Gotchas

### The "Functional" Performance Cost

**Context:** `map`, `fold`, `zip_with` are implemented in pure Gleam.
**The Trade-off:** Iterating over binary data in Gleam is slower than Rust loops.
**Recommendation:**
* **Ergonomics First.** A "slow" `matrix.map` that exists is better than a fast one that doesn't.
* **Optimize Later.** If specific operations become bottlenecks, add dedicated NIFs.

### Why Not NIFs for Functional Operations?

Passing Gleam closures to Rust NIFs is complex. Rustler supports it but the ergonomics are poor. Pure Gleam is simpler and good enough for most use cases.

### Element Type for Masks

**Context:** `bernoulli` generates random 0/1 masks.
**Recommendation:** Return `Matrix` (floats) with 0.0/1.0 values. This:
* Keeps the type system simple
* Works seamlessly with `linalg` operations
* Matches how NumPy handles masks
