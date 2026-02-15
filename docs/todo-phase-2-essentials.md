# Phase 2: The "Numpy" Essentials (Functional API)

**Goal:** Make the library "gleam-idiomatic" and ergonomic by adding functional array manipulations and statistical generation.

## 1. Functional Transformations
- [ ] **Map**
  - Implement `matrix.map(Matrix(a), fn(a) -> b) -> Matrix(b)`.
  - *Note:* This will likely require iterating through the binary data in Gleam or Rust. A Rust NIF might be faster for simple types, but a Gleam implementation is more flexible for closures.
- [ ] **Fold**
  - Implement `matrix.fold(Matrix(a), acc, fn(acc, a) -> acc)`.
  - Useful for sum, max, min, all, any.
- [ ] **Zip / Map2**
  - Implement `matrix.map2(Matrix(a), Matrix(b), fn(a, b) -> c) -> Matrix(c)`.
  - Handles element-wise operations between two matrices.

## 2. Randomness & Distributions
- [ ] **Module Setup**
  - Create `src/waffle/random.gleam`.
  - Add `rand` or `rand_distr` crate to `native/waffle/Cargo.toml`.
- [ ] **Distributions**
  - `random.uniform(rows, cols, min, max) -> Matrix(Float)`
  - `random.normal(rows, cols, mean, std_dev) -> Matrix(Float)`
  - `random.bernoulli(rows, cols, p) -> Matrix(Int)` (useful for masks).
- [ ] **Seeding**
  - Allow optional seed for reproducibility (crucial for testing).

## 3. Views & Slicing
- [ ] **Slicing**
  - Implement `matrix.slice(m, r_start, r_len, c_start, c_len) -> Matrix(a)`.
  - *Optimization:* Should this return a copy or a view? (Likely a copy for now to keep the `Matrix` type simple/owned).
- [ ] **Row/Col Access**
  - `matrix.row(m, index) -> List(a)`
  - `matrix.col(m, index) -> List(a)`

## 4. Utilities & Polish
- [ ] **Reshape**
  - `matrix.reshape(m, rows, cols) -> Result(Matrix(a), Error)`
- [ ] **Stacking**
  - `matrix.vstack(top, bottom)`
  - `matrix.hstack(left, right)`
- [ ] **Pretty Printing**
  - Implement a `to_string` function that aligns columns for readable CLI output.


## FAQ and gotchas

### The "Functional" Performance Cost

**Context:** Phase 2 adds `matrix.map` and `matrix.fold`.
**The Trade-off:** Implementing these in pure Gleam requires iterating over binary data, which is significantly slower than Rust loops.
**Recommendation:**
* **Ergonomics First.** Do not obsess over performance initially. A "slow" `matrix.map` that exists is infinitely better than a fast one that doesn't.
* **Optimize Later.** If specific operations (e.g., mapping a sigmoid function) become bottlenecks, replace them with dedicated NIFs later. Do not premature optimization block the API design.
