# Phase 1: Module Organization (mirroring `faer`) ✅ COMPLETED

**Goal:** Reorganize modules to mirror `faer`'s structure for clarity and maintainability. Keep `Matrix` as float-only (no generics needed).

## Rationale

- `Matrix` stays float-only since ILP constraint matrices are always floats.
- Module structure mirrors `faer`:
  - `matrix.gleam` ↔ `faer::Mat` (type + basic operations)
  - `linalg.gleam` ↔ `faer::linalg::*` (decompositions, solver)
- This makes the waffle-faer connection transparent and easier to maintain.

## 1. Refactor `matrix.gleam`

**Keep:**
- [x] `Matrix` type (opaque, float-only)
- [x] `MatrixError` type
- [x] Constructors: `from_list`, `to_list`, `from_binary`, `to_binary`, `identity`, `zeros`, `ones`, `diagonal`
- [x] Accessors: `rows`, `cols`, `get`
- [x] Structural: `transpose`
- [x] Basic arithmetic: `add`, `subtract`, `multiply`, `scale`
- [x] Basic properties: `trace`
- [x] Internal helpers that support the above

**Remove (move to `linalg.gleam`):**
- [x] `LU`, `QR`, `SVD` types
- [x] `determinant`, `inverse`, `lu`, `qr`, `svd`, `symmetric_eigenvalues` functions
- [x] Import of `waffle/internal/faer/linalg/solvers`

## 2. Create `linalg.gleam`

**Add:**
- [x] Types: `LU`, `QR`, `SVD`
- [x] Import `waffle/matrix` for `Matrix` and `MatrixError`
- [x] Import `waffle/internal/faer/linalg/solvers`
- [x] Functions: `determinant`, `inverse`, `lu`, `qr`, `svd`, `symmetric_eigenvalues`, `solve`
- [x] Internal helpers: `unpack_pivot`, `unpack_floats`, validation helpers

## 3. Cleanup

- [x] Delete `src/waffle/solver.gleam`
- [x] Update `test/solver_test.gleam` → `test/linalg_test.gleam`
- [x] Update imports in test files
- [x] Run tests to verify everything works

## 4. Internal NIFs

No changes needed. Already mirror `faer` structure:
- `internal/faer/mat.gleam` — basic operations
- `internal/faer/linalg/solvers.gleam` — decompositions, solver

---

## FAQ and Gotchas

### Why not generic `Matrix(a)`?

Generic matrices add complexity without benefit for our use case:
- ILP constraint matrices are always floats
- Integer-ness is a property of *variables*, not matrix elements
- `highs` works entirely with floats internally
- Even `bernoulli` masks can be `Matrix` with 0.0/1.0

### Why keep `transpose` in `matrix.gleam`?

In `faer`, `transpose` is a method on `Mat` itself, not in `linalg`. It's a structural operation, not a decomposition.
