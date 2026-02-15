# Phase 2.5: Sparse Matrix Support

**Goal:** Support sparse matrices to enable efficient solving of large-scale optimization problems.

## 1. Sparse Matrix Type
- [ ] **Define Type**
  - Create `src/waffle/sparse.gleam`.
  - Define `opaque type SparseMatrix` (likely holding CSR data: `values`, `col_indices`, `row_ptr`).
- [ ] **Construction**
  - Implement `from_triplets(List(#(Int, Int, Float))) -> SparseMatrix`.
  - *Note:* This is the most user-friendly way to build sparse matrices in Gleam.
  - Implement `to_dense(SparseMatrix) -> Matrix(Float)`.
- [ ] **NIF Implementation**
  - Add sparse matrix struct in `lib.rs` (compatible with `faer::sparse` or `highs` input format).
  - Implement conversion NIFs.

## 2. Basic Operations
- [ ] **Structural**
  - `dims(SparseMatrix) -> #(Int, Int)`
  - `transpose(SparseMatrix) -> SparseMatrix`
- [ ] **Validation**
  - Ensure indices are within bounds during construction.

## 3. Integration Prep
- [ ] **Solver Compatibility**
  - Ensure the internal Rust representation matches what `highs` expects (CSR) to minimize copying in Phase 3.


## FAQ and gotchas

### Sparse Formats (CSC vs CSR)

**Context:** Phase 2.5 introduces Sparse Matrices.
**The Conflict:**
* **`faer` (Linear Algebra):** Prefers **CSC** (Compressed Sparse Column) because it aligns with column-major algorithms.
* **`highs` (Solver):** Accepts both but often constructs models row-by-row, favoring **CSR** (Compressed Sparse Row).
* **Gleam Lists:** Naturally Row-Major (`[[row1], [row2]]`).

**Recommendation:**
* **Pick one canonical format.** Use **CSC** as the internal standard to match `faer` (your primary math engine).
* **Convert at boundaries.** Only convert to CSR when absolutely necessary (e.g., strictly required by a specific `highs` API call), or rely on `highs`'s ability to ingest CSC. Avoid maintaining two internal formats.
