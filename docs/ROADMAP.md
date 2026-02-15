# Waffle — Roadmap

Step-by-step implementation plan.

> **Note:** The roadmap has been restructured (Feb 2026) to reflect a new architectural direction:
> 1. Generic Matrix types (`Matrix(a)`)
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

## Phase 1: The Robust Core (Architecture Refactor) [todo-phase-1](/docs/todo-phase-1-matrix.md)

**Goal:** Refactor the rigid `Matrix` (float-only) into a generic `Matrix(a)` to support integer masks, complex numbers, and other types in the future. Separate "Structure" from "Math".

- [ ] **Generic Matrix Type**
  - Update `src/waffle.gleam` to define opaque `type Matrix(a)`.
  - Refactor `waffle/matrix` to contain only generic structural operations (`transpose`, `dims`, `get`, `set`).
  - Ensure `from_list` and `to_list` work for any type `a`.

- [ ] **Math Module Separation**
  - Create `src/waffle/linalg.gleam` for Float-specific operations.
  - Move arithmetic (`add`, `scale`, `multiply`) and decompositions (`lu`, `qr`, `svd`) here.
  - Update NIFs to enforce Float types where strict math is required.

- [ ] **Standardization**
  - Ensure all NIFs use zero-copy viewing for input binaries where possible.
  - Audit error types to ensure consistency across modules.

---

## Phase 2: The "Numpy" Essentials (Functional API) [todo-phase-2](/docs/todo-phase-2-essentials.md)

**Goal:** Make the library "gleam-idiomatic" and ergonomic by adding functional array manipulations and statistical generation.

- [ ] **Functional Transformations**
  - `matrix.map(Matrix(a), fn(a) -> b) -> Matrix(b)` (Crucial for boolean masks, casting).
  - `matrix.fold(Matrix(a), acc, fn(acc, a) -> acc)` (Sum, max, min, etc).
  - `matrix.zip(Matrix(a), Matrix(b))` (Element-wise pairing).

- [ ] **Randomness & Distributions**
  - Create `src/waffle/random.gleam`.
  - Implement `uniform(rows, cols, min, max) -> Matrix(Float)`.
  - Implement `normal(rows, cols, mean, std_dev) -> Matrix(Float)`.
  - Implement `bernoulli(rows, cols, p) -> Matrix(Int)` (0/1 masks).

- [ ] **Views & Slicing**
  - `matrix.slice(Matrix(a), row_start, row_len, col_start, col_len) -> Matrix(a)`
  - `matrix.get_row(Matrix(a), index) -> List(a)`
  - `matrix.get_col(Matrix(a), index) -> List(a)`

- [ ] **Utilities**
  - `matrix.reshape`
  - `matrix.vstack` / `matrix.hstack`
  - Pretty printing (`to_string` with alignment).

---

## Phase 2.5: Sparse Matrix Support [todo-phase-2.5](/docs/todo-phase-2.5-sparse.md)

**Goal:** Support sparse matrices to enable efficient solving of large-scale optimization problems.

- [ ] **Sparse Types**
  - Define `SparseMatrix` type (CSR or Triplet format).
  - Implement `from_triplets(List(#(Int, Int, Float))) -> SparseMatrix`.
  - Implement `to_dense(SparseMatrix) -> Matrix(Float)`.

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
  - Support **both** `Matrix(Float)` (Dense) and `SparseMatrix` (CSR) constraints.
  - Map inputs directly to `highs::HighsModel`.
  - Return detailed solution structs (status, objective value, variable assignments).

---

## Phase 4: Polish & Publish

**Goal:** Prepare for public release on Hex.

- [ ] **Documentation**
  - Write generic module docs (`waffle/matrix`).
  - Write math module docs (`waffle/linalg`).
  - Write optimization docs (`waffle/opt`) with examples.
- [ ] **Benchmarks**
  - Compare performance against Python/NumPy for common ops.
- [ ] **Publish**
  - Final version bump.
  - `gleam publish`.

