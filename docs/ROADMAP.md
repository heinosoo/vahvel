# Waffle — Roadmap

Step-by-step implementation plan.

> **Note:** The roadmap has been restructured (Feb 2026) to reflect a streamlined architecture:
> 1. Module organization mirroring `faer` structure (`matrix` + `linalg`)
> 2. Functional API & Randomness
> 3. Sparse Matrices (for efficient Optimization)
> 4. Optimization/ILP (`highs`)

---

## ✅ Completed Foundation

**Step 0 — Skeleton**
- [x] NIF round-trip (Gleam → Rust → Gleam) works.
- [x] Basic project structure and FFI glue.

**Step 1 — Matrix Type (Initial)**
- [x] `Matrix` type defined (Float-only).
- [x] Basic row/col/identity helpers.

**Step 2 — Linear Solver**
- [x] `faer` integration for `Ax=b` (LU decomposition).
- [x] DirtyCpu scheduling for non-blocking NIFs.

**Step 3 — Build System**
- [x] `waffle_setup` script for automatic NIF compilation.
- [x] Version checking between Gleam and Rust.

**Step 4 — CI/CD**
- [x] Automated testing and linting.
- [x] Release workflows for Linux binaries.

---

## ✅ Phase 1: Module Organization (mirroring `faer`) [todo-phase-1](/docs/todo-phase-1-matrix.md)

**Goal:** Reorganize modules to mirror `faer`'s structure for clarity and maintainability. Keep `Matrix` as float-only (no generics needed).

- [x] **`matrix.gleam` (mirrors `faer::Mat`)**
  - `Matrix` type (opaque, float-only).
  - Constructors: `from_list`, `to_list`, `from_binary`, `to_binary`, `identity`, `zeros`, `ones`, `diagonal`.
  - Accessors: `rows`, `cols`, `get`.
  - Structural: `transpose`.
  - Basic arithmetic: `add`, `subtract`, `multiply`, `scale`.
  - Basic properties: `trace`.

- [x] **`linalg.gleam` (mirrors `faer::linalg::*`)**
  - Decomposition types: `LU`, `QR`, `SVD`.
  - Decompositions: `lu`, `qr`, `svd`.
  - Advanced properties: `determinant`, `inverse`, `symmetric_eigenvalues`.
  - Solver: `solve(a, b)`.

- [x] **Cleanup**
  - Delete `solver.gleam` (move `solve` to `linalg.gleam`).
  - Update tests and imports.

---

## ✅ Phase 2: The "Numpy" Essentials (Functional API) [todo-phase-2](/docs/todo-phase-2-essentials.md)

**Goal:** Make the library "gleam-idiomatic" and ergonomic by adding functional array manipulations and statistical generation.

- [x] **Functional Transformations**
  - `matrix.map(Matrix, fn(Float) -> Float) -> Matrix`
  - `matrix.fold(Matrix, acc, fn(acc, Float) -> acc)` (Sum, max, min, etc).
  - `matrix.zip_with(Matrix, Matrix, fn(Float, Float) -> Float)` (Element-wise operations).

- [x] **Randomness & Distributions**
  - Create `src/waffle/random.gleam`.
  - Implement `uniform(rows, cols, min, max) -> Matrix`.
  - Implement `normal(rows, cols, mean, std_dev) -> Matrix`.
  - Implement `bernoulli(rows, cols, p) -> Matrix` (0.0/1.0 masks).

- [x] **Views & Slicing**
  - `matrix.slice(Matrix, row_start, row_len, col_start, col_len) -> Matrix`
  - `matrix.row(Matrix, index) -> List(Float)`
  - `matrix.col(Matrix, index) -> List(Float)`

- [x] **Utilities**
  - `matrix.reshape`
  - `matrix.vstack` / `matrix.hstack`
  - Pretty printing (`to_string` with alignment).

---

## Phase 2.5: Sparse Matrix Support [todo-phase-2.5](/docs/todo-phase-2.5-sparse.md)

**Goal:** Support sparse matrices to enable efficient solving of large-scale optimization problems.

- [ ] **Sparse Types**
  - Define `SparseMatrix` type (CSR or Triplet format).
  - Implement `from_triplets(List(#(Int, Int, Float))) -> SparseMatrix`.
  - Implement `to_dense(SparseMatrix) -> Matrix`.

- [ ] **Sparse Operations (Basic)**
  - Implement `transpose`, `dims` for sparse matrices.
  - *Note:* Full sparse arithmetic is deferred; focus on construction and passing to solver.

---

## Phase 3: Decision Science (ILP & Optimization) [todo-phase-3](/docs/todo-phase-3-optimization.md)

**Goal:** Add a Mixed-Integer Linear Programming (MILP) solver using `highs`.

- [ ] **Dependencies**
  - Add `highs` to `native/waffle/Cargo.toml`.
  - **Crucial:** Configure static C++ linking (`-static-libstdc++`) to ensure portability.

- [ ] **Optimization Module (`waffle/opt`)**
  - Define `Model` type for the "Standard Form" ($L \le Ax \le U$).
  - Define `VariableType` enum (`Continuous`, `Integer`).
  - Create fluent Builder API for defining problems.

- [ ] **Solver NIF**
  - Implement `solve_ilp` NIF in Rust.
  - Support **both** `Matrix` (Dense) and `SparseMatrix` (CSR) constraints.
  - Map inputs directly to `highs::HighsModel`.
  - Return detailed solution structs (status, objective value, variable assignments).

---

## Phase 4: Polish & Publish

**Goal:** Prepare for public release on Hex.

- [ ] **Documentation**
  - Write module docs (`waffle/matrix`).
  - Write module docs (`waffle/linalg`).
  - Write optimization docs (`waffle/opt`) with examples.
- [ ] **Benchmarks**
  - Compare performance against Python/NumPy for common ops.
- [ ] **Publish**
  - Final version bump.
  - `gleam publish`.
