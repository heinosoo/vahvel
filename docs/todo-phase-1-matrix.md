# Phase 1: The Robust Core (Architecture Refactor)

**Goal:** Refactor the rigid `Matrix` (float-only) into a generic `Matrix(a)` to support integer masks, complex numbers, and other types in the future. Separate "Structure" from "Math".

## 1. Generic Matrix Type
- [ ] **Refactor `src/waffle.gleam`**
  - Define opaque `type Matrix(a)`.
  - Ensure the internal `BitArray` representation can handle different types (likely by tagging or phantom types, though strictly `BitArray` is untyped, the phantom type `a` will enforce safety at the Gleam level).
- [ ] **Update `src/waffle/matrix.gleam`**
  - Refactor `from_list` to work with generic lists (may need specific decoders/encoders if using `BitArray` storage for non-floats, or keep it simple for now).
  - Update structural functions (`dims`, `get`, `set`) to be polymorphic.
  - Ensure `transpose` works on `Matrix(a)`.
- [ ] **Update Tests**
  - Verify `matrix.from_list` works for Float.
  - Verify `matrix.dims` and other helpers still pass.

## 2. Math Module Separation
- [ ] **Create `src/waffle/linalg.gleam`**
  - Move all arithmetic operations here: `add`, `scale`, `multiply`, `subtract`.
  - Move all decompositions here: `lu`, `qr`, `svd`.
  - Move properties here: `determinant`, `inverse`, `norm`, `trace`.
- [ ] **Restrict Types**
  - Ensure functions in `linalg` specifically accept `Matrix(Float)`.
- [ ] **Update NIFs (Rust)**
  - Audit `lib.rs` to ensure it correctly handles the new generic type wrapper (if representation changed).
  - Ensure `linalg` NIFs strictly expect f64 data.

## 3. Standardization & Cleanup
- [ ] **Zero-Copy Audit**
  - Review all NIFs to ensure input binaries are viewed, not copied.
- [ ] **Error Consistency**
  - Unify error types (e.g., `SingularMatrix`, `DimensionMismatch`) into a shared `waffle/error` module or keep them in their respective domains if distinct.


## FAQ and gotchas

### The "Generic Matrix" Trap

**Context:** Phase 1 involves refactoring `Matrix` to a generic `Matrix(a)` type.
**The Problem:** The underlying data is stored in a raw `BitArray`. A generic `transpose` or `get` function needs to know the byte size (stride) of each element to calculate offsets correctly.
* `Float`: 8 bytes
* `Int`: 8 bytes (usually)
* `Bool` / Small Int: 1 byte?

**Recommendation:**
* **Enforce 64-bit alignment initially.** Assume all matrix elements are 8 bytes (f64, i64). This simplifies memory management and pointer arithmetic in NIFs.
* If smaller types (e.g., `Int8` for masks) are needed later, store an explicit `element_size` field in the `Matrix` struct to handle the stride dynamically.
