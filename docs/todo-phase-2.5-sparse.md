# Phase 2.5: Sparse Matrix Support

**Goal:** Support sparse matrices to enable efficient solving of large-scale optimization problems.

**Status:** ✅ Complete

## 1. Sparse Matrix Type

- [x] **Define Type**
  - Created `src/waffle/sparse.gleam`.
  - Defined `opaque type SparseMatrix` holding CSC data: `rows`, `cols`, `nnz`, `col_ptr`, `row_indices`, `values`.
- [x] **Construction**
  - Implemented `from_triplets(List(#(Int, Int, Float))) -> SparseMatrix`.
  - Implemented `to_dense(SparseMatrix) -> Matrix`.
  - Implemented `from_dense(Matrix) -> SparseMatrix`.
- [x] **NIF Implementation**
  - Added sparse matrix NIFs in `lib.rs` using `faer::sparse::SparseColMat`.
  - Implemented conversion NIFs: `sparse_from_triplets`, `sparse_to_dense`, `sparse_from_dense`.

## 2. Basic Operations

- [x] **Structural**
  - `dims(SparseMatrix) -> #(Int, Int)`
  - `rows(SparseMatrix) -> Int`
  - `cols(SparseMatrix) -> Int`
  - `nnz(SparseMatrix) -> Int`
  - `transpose(SparseMatrix) -> SparseMatrix`
  - `get(SparseMatrix, row, col) -> Result(Float, SparseError)`
  - `to_triplets(SparseMatrix) -> List(#(Int, Int, Float))`
  - `to_string(SparseMatrix) -> String`
  - `validate_square(SparseMatrix) -> Result(Nil, SparseError)`
- [x] **Row/Column Extraction**
  - `row(SparseMatrix, index) -> Result(List(Float), SparseError)`
  - `col(SparseMatrix, index) -> Result(List(Float), SparseError)`
- [x] **Validation**
  - Indices validated within bounds during construction.
  - Returns `IndexOutOfBounds` error for invalid indices.

## 3. Arithmetic Operations

- [x] **Sparse × Dense Multiplication**
  - `multiply_dense(SparseMatrix, Matrix) -> Result(Matrix, SparseError)`
  - Implemented in Rust using `faer`'s sparse-dense matrix multiplication.

- [x] **Sparse × Sparse Multiplication**
  - `multiply(SparseMatrix, SparseMatrix) -> Result(SparseMatrix, SparseError)`
  - Implemented in Rust using `faer`'s sparse-sparse matrix multiplication.

- [x] **Sparse Addition**
  - `add(SparseMatrix, SparseMatrix) -> Result(SparseMatrix, SparseError)`
  - Element-wise addition of sparse matrices.

- [x] **Sparse Subtraction**
  - `subtract(SparseMatrix, SparseMatrix) -> Result(SparseMatrix, SparseError)`
  - Element-wise subtraction of sparse matrices.

- [x] **Scalar Multiplication**
  - `scale(SparseMatrix, Float) -> Result(SparseMatrix, SparseError)`
  - Scale all non-zero elements by a scalar.

- [x] **Element-wise Binary Operations**
  - `zip_with(SparseMatrix, SparseMatrix, fn(Float, Float) -> Float) -> Result(SparseMatrix, SparseError)`
  - Apply binary function element-wise to two sparse matrices.

## 4. Functional Transformations

- [x] **Mapping and Folding**
  - `map(SparseMatrix, fn(Float) -> Float) -> SparseMatrix`
  - `fold(SparseMatrix, acc, fn(acc, Float) -> acc) -> acc`
  - `fold_with_indices(SparseMatrix, acc, fn(acc, Int, Int, Float) -> acc) -> acc`

## 5. Integration Prep

- [x] **Solver Compatibility**
  - Internal Rust representation uses **CSC** format (matches `faer::sparse`).
  - HiGHS (Phase 3) natively supports CSC via `kHighsMatrixFormatColwise` - no format conversion needed.

## 6. API Consistency (Feb 2026)

- [x] **Removed dead code**
  - Removed unused `DuplicateEntry` variant from `SparseError`.
  - Made `dim_string()` internal (not exported).
- [x] **Added consistency with dense API**
  - `sparse.row()` / `sparse.col()` match `matrix.row()` / `matrix.col()`.
  - `sparse.to_string()` matches `matrix.to_string()`.
  - `sparse.validate_square()` for symmetry checks.
  - `sparse.zip_with()` for element-wise operations.
  - `matrix.dims()` added for consistency with `sparse.dims()`.
  - `matrix.fold_with_indices()` added for consistency with `sparse.fold_with_indices()`.

## FAQ and Gotchas

### Sparse Formats (CSC vs CSR)

**Context:** Phase 2.5 introduces Sparse Matrices.
**The Conflict:**
* **`faer` (Linear Algebra):** Prefers **CSC** (Compressed Sparse Column) because it aligns with column-major algorithms.
* **`highs` (Solver):** Accepts both but often constructs models row-by-row, favoring **CSR** (Compressed Sparse Row).
* **Gleam Lists:** Naturally Row-Major (`[[row1], [row2]]`).

**Recommendation:**
* **Pick one canonical format.** Use **CSC** as the internal standard to match `faer` (your primary math engine).
* **Convert at boundaries.** Only convert to CSR when absolutely necessary (e.g., strictly required by a specific `highs` API call), or rely on `highs`'s ability to ingest CSC. Avoid maintaining two internal formats.

**Decision:** Using CSC. HiGHS accepts CSC directly via `kHighsMatrixFormatColwise`.
