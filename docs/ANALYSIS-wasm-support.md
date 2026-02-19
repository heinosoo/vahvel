# Feasibility Assessment: JavaScript/WASM Target for Waffle

## Context

Waffle is a Gleam linear algebra library that uses Rust's `faer` crate via Erlang NIFs (Native Implemented Functions). The current architecture is:

```
Gleam (public API) -> Erlang (NIF loader) -> Rust (faer/HiGHS computation)
```

**Question:** Can we support Gleam's JavaScript compilation target by compiling the Rust code to WebAssembly? What architectural changes would be required?

> **Note (updated v0.2.3):** This document was originally written when waffle only exposed `solve()`. The library has since grown to 36 NIFs across four domains (dense, sparse, opt, random). Sections that changed materially are marked.

---

## TL;DR Assessment

**Feasibility:** Technically possible but with significant trade-offs

**Difficulty:** High
- faer to WASM: Moderate (pure Rust, straightforward)
- HiGHS (`opt` module) to WASM: Hard (C++ library, separate toolchain)
- Full integration across all 36 NIFs: High (4× more scope than original estimate)
- Performance: Significant degradation (3-20x slower than native)

**Architectural Changes:** Major refactoring required
- Need separate implementations for Erlang (NIF) vs JavaScript (WASM)
- Different build pipelines for each target
- Shared Gleam API layer with target-specific backends
- The `opt` module may need to be excluded or deferred (see section 5)

---

## Detailed Analysis

### 1. Can `faer` Compile to WebAssembly?

**Yes, with caveats:**

**Advantages:**
- Pure Rust with no C/Fortran dependencies (unlike LAPACK/BLAS)
- No complex build toolchain requirements
- Falls back to scalar code when SIMD unavailable
- Linear memory model works well with WASM

**Limitations:**
- **SIMD performance loss:** faer's AVX512/AVX2 optimizations don't translate to WASM's limited SIMD (`wasm_simd128`)
- **No parallelism:** Rayon/threading won't work in WASM's single-threaded model (without Web Workers)
- **Memory constraints:** WASM limited to 4GB per instance
- **Binary size:** 5-15 MB uncompressed (2-5 MB with `wasm-opt`)

**Performance Impact:**
- Basic operations: 0.8-1.0x native speed
- Small matrix operations (<100x100): 0.3-0.5x native
- Large matrix operations (>1000x1000): 0.1-0.3x native
- LU decomposition: 0.2-0.4x native

**Verdict:** faer is the *best* candidate for WASM among Rust linear algebra libraries, but expect 3-20x performance degradation depending on matrix size.

---

### 2. Gleam Multi-Target Architecture

Gleam provides the `@external` attribute for target-specific implementations:

```gleam
@external(erlang, "nif", "solve_linear_system")
@external(javascript, "./waffle_wasm.mjs", "solveLinearSystem")
pub fn solve(a: Matrix, b: Matrix) -> Result(Matrix, SolverError)
```

**How it works:**
- Single function signature across all targets
- Compiler automatically selects the correct implementation
- Type safety enforced at compile time

**Real-world examples:**
- `gleam_crypto`: Uses Erlang's `crypto` module for Erlang target, WebCrypto API for JavaScript
- `gleam/stdlib`: Extensive use of `@external` for cross-platform support

---

### 3. Required Architectural Changes

#### Current Architecture (Erlang-only, v0.2.3)

```
src/waffle/
  matrix.gleam              # Pure Gleam dense matrix API
  linalg.gleam              # Decompositions & solvers (LU, QR, SVD, etc.)
  sparse.gleam              # CSC sparse matrix API
  opt.gleam                 # ILP solver via HiGHS
  random.gleam              # Seeded matrix generation
  internal/
    ffi/
      nif.erl               # Erlang NIF stubs (36 functions)
      platform.erl          # OS detection

native/waffle/
  Cargo.toml                # rustler + faer + highs + rand + bytemuck
  src/
    lib.rs                  # NIF init + registration
    dense.rs                # 16 NIFs: multiply, LU, QR, SVD, eigenvalues, etc.
    sparse.rs               # 9 NIFs: from_triplets, multiply_dense, add, etc.
    opt.rs                  # 2 NIFs: model serialization + HiGHS solve
    random.rs               # 6 NIFs: uniform, normal, bernoulli (+ seeded)
    bench.rs                # 3 NIFs: internal benchmarking
    utils.rs                # Shared binary conversion + validation
```

#### Proposed Dual-Target Architecture

```
src/waffle/
  matrix.gleam              # Pure Gleam (unchanged)
  linalg.gleam              # Uses @external for both targets
  sparse.gleam              # Uses @external for both targets
  opt.gleam                 # Erlang target only (see section 5)
  random.gleam              # Uses @external for both targets
  internal/
    ffi/
      nif.erl               # Erlang NIF loader (Erlang target only)

native/waffle_nif/          # Rust NIF for Erlang (current native/waffle/)
  Cargo.toml                # rustler + faer + highs + rand + bytemuck
  src/                      # dense.rs, sparse.rs, opt.rs, random.rs, etc.

native/waffle_wasm/         # Rust WASM for JavaScript (new)
  Cargo.toml                # wasm-bindgen + faer + rand + bytemuck
  src/
    lib.rs                  # wasm_bindgen exports for dense, sparse, random
    dense.rs                # WASM-adapted dense ops
    sparse.rs               # WASM-adapted sparse ops
    random.rs               # WASM-adapted random ops
    utils.rs                # Shared with NIF crate (or duplicated)

src/waffle_wasm.mjs         # JavaScript glue layer (new)
```

**Key Changes:**

1. **Split Rust implementations:**
   - `waffle_nif`: Uses `rustler`, targets `cdylib` for Erlang (rename of current crate)
   - `waffle_wasm`: Uses `wasm-bindgen`, targets `wasm32-unknown-unknown`

2. **Dual `@external` declarations** (at the FFI boundary, not the public API):
   ```gleam
   @external(erlang, "nif", "solve_linear_system")
   @external(javascript, "./waffle_wasm.mjs", "solveLinearSystem")
   fn solve_ffi(rows: Int, cols: Int, mat: BitArray, rhs: BitArray)
     -> Result(BitArray, String)
   ```

3. **JavaScript glue layer (`waffle_wasm.mjs`):**
   ```javascript
   import initSync, { solve_linear_system } from './waffle_wasm_bg.js';
   import wasmBytes from './waffle_wasm_bg.wasm';

   // Synchronous initialization at module load time.
   // Gleam's JS FFI expects synchronous return values, so async
   // init is not viable.
   initSync(wasmBytes);

   export function solveLinearSystem(rows, cols, matrixData, rhsData) {
     // Convert Gleam BitArray (Uint8Array) to Float64Array
     const matrix = new Float64Array(matrixData.buffer);
     const rhs = new Float64Array(rhsData.buffer);

     // Call WASM function
     const result = solve_linear_system(rows, cols, matrix, rhs);

     // Convert back to Uint8Array for Gleam
     return new Uint8Array(result.buffer);
   }
   ```

4. **Updated build script:**
   - Detect compilation target (Erlang vs JavaScript)
   - For Erlang: Download/build NIF as before
   - For JavaScript: Run `wasm-pack build` and copy artifacts

---

### 4. Implementation Complexity Breakdown

*Updated for v0.2.3 scope: 36 NIFs across dense, sparse, opt, and random modules.*

| Component | Difficulty | Effort | Notes |
|-----------|-----------|--------|-------|
| **Rust WASM port (dense)** | Moderate | 2-3 days | faer compiles cleanly; disable threading |
| **Rust WASM port (sparse)** | Moderate | 2-3 days | CSC data serialization across WASM boundary |
| **Rust WASM port (random)** | Easy | 1 day | rand + rand_distr compile to WASM |
| **HiGHS/opt WASM** | Hard | 3-5 days | C++ library; emscripten build; may not be worth it |
| **wasm-bindgen setup** | Easy | 1 day | Standard tooling, well-documented |
| **JavaScript glue layer** | Moderate | 2-3 days | 36 functions vs 1 in original estimate |
| **Gleam @external setup** | Easy | 1 day | Add second `@external` to each internal FFI binding |
| **Build system updates** | Moderate | 2-3 days | Target detection, dual build paths |
| **Testing on both targets** | Hard | 3-5 days | Numerical consistency across all operations |
| **CI/CD updates** | Moderate | 1-2 days | Build WASM in GitHub Actions |
| **Documentation** | Moderate | 1 day | Document performance trade-offs |

**Total estimated effort:** 4-6 weeks for experienced Rust/WASM developer (up from original 1.5-2 weeks due to 4× scope increase and HiGHS complexity)

---

### 5. The HiGHS Problem

**This is the most significant change since the original analysis.**

The `opt` module uses **HiGHS**, a C++ mixed-integer linear programming solver built via cmake. The original analysis noted faer's advantage as "Pure Rust with no C/Fortran dependencies" — that no longer applies to the full waffle package.

**Challenges with HiGHS → WASM:**
- HiGHS has experimental emscripten builds but they are not part of the standard Rust `highs` crate
- Requires a separate emscripten toolchain alongside wasm-pack
- Significantly increases build complexity
- The resulting WASM binary would be substantially larger

**Practical options for the `opt` module:**

1. **Exclude from JS target** — Return a clear `Error("opt module not supported on JavaScript target")`. Cleanest approach.
   ```gleam
   @external(erlang, "nif", "highs_solve")
   @external(javascript, "./waffle_wasm.mjs", "highsSolveNotSupported")
   fn highs_solve_ffi(...) -> Result(BitArray, String)
   ```

2. **Port separately with emscripten** — Builds HiGHS to WASM via emscripten. Significant toolchain complexity; deferred to a later phase.

3. **Replace with pure Rust ILP solver** — No pure-Rust MIP solver exists with comparable capability to HiGHS. Not a realistic option.

**Recommended:** Exclude `opt` from the initial JS target with a clear error message. Ship dense + sparse + random support first.

---

### 6. Technical Challenges

#### Challenge 1: Binary Data Conversion

**Problem:** Gleam BitArrays are `Uint8Array` on JavaScript, but faer needs `&[f64]` slices.

**Solution:** Convert in JavaScript glue layer:
```javascript
// Gleam sends column-major f64 bytes as Uint8Array
const float64View = new Float64Array(uint8Array.buffer);
```

**Risk:** Endianness assumptions (little-endian on x86/ARM/WASM is safe).

For sparse matrices, the glue layer also needs to handle multiple integer arrays (col_ptrs, row_indices as `i32`) alongside the float data array — more conversion logic than the dense case.

---

#### Challenge 2: Asynchronous WASM Initialization

**Problem:** WASM modules must be initialized asynchronously in browsers.

**Solution:** Lazy initialization in glue layer:
```javascript
let initialized = false;

export async function solveLinearSystem(...args) {
  if (!initialized) {
    await init();
    initialized = true;
  }
  return solve_linear_system(...args);
}
```

**Risk:** First call has initialization latency (~10-50ms).

**Note:** Gleam's JavaScript FFI expects synchronous return values. Async WASM
initialization would need to be handled via synchronous instantiation
(`WebAssembly.Module` + `WebAssembly.Instance` in Node.js) or a top-level
`await init()` that runs at module load time rather than lazily per-call.

---

#### Challenge 3: Singular Matrix Panics

**Problem:** faer panics on singular matrices; must catch in WASM to prevent crashing.

**Solution:** Use `catch_unwind` in Rust:
```rust
#[wasm_bindgen]
pub fn solve_linear_system(...) -> Result<Vec<f64>, String> {
    std::panic::catch_unwind(|| {
        let lu = mat_a.partial_piv_lu();
        lu.solve(mat_b)
    })
    .map_err(|_| "Singular matrix".to_string())
}
```

---

#### Challenge 4: Build Complexity

**Problem:** Need to build both NIF (for Erlang) and WASM (for JavaScript).

**Solution:** Target-aware build script:
```gleam
pub fn main() {
  case detect_target() {
    Erlang -> build_nif()
    JavaScript -> build_wasm()
  }
}

fn build_wasm() {
  // Run: wasm-pack build native/waffle_wasm --target web
  // Copy pkg/* to priv/wasm/
}
```

**Risk:** Increased CI complexity; need to build and test both targets.

---

### 7. Alternative Approaches

#### Option A: Pure JavaScript Linear Algebra Library

Instead of compiling Rust to WASM, use an existing JS library (e.g. `math.js`, `numeric.js`, `ml-matrix`).

**Pros:**
- Simpler integration (no WASM compilation)
- Smaller bundle size
- Easier debugging

**Cons:**
- Performance likely worse than WASM
- Different numerical precision/algorithms than faer
- Inconsistent behavior between Erlang and JavaScript targets

**Verdict:** Easier but less aligned with the "same behavior on all targets" goal.

---

#### Option B: Erlang-Only Library

Accept that waffle only works on the Erlang target:

```toml
# In gleam.toml
target = "erlang"  # Explicitly Erlang-only
```

**Pros:**
- No additional complexity
- Best performance
- Simpler maintenance

**Cons:**
- Cannot be used in JavaScript-compiled Gleam projects
- Limits adoption in web/Node.js contexts

**Verdict:** Simplest approach if JavaScript target isn't a priority. This is the current state.

---

#### Option C: Server-Side Computation API

For JavaScript target, call a server endpoint that runs the Erlang version:

```gleam
@external(erlang, "nif", "solve_linear_system")
@external(javascript, "./waffle_api.mjs", "solveLinearSystemRemote")
pub fn solve(a: Matrix, b: Matrix) -> Result(Matrix, SolverError)
```

**Pros:**
- Full native performance on server
- Simple JavaScript client
- Can leverage existing infrastructure

**Cons:**
- Network latency
- Requires server deployment
- Not suitable for offline/embedded use

**Verdict:** Good for web applications where server roundtrip is acceptable.

---

### 8. Recommendations

#### Recommended Approach: Phased WASM

**Phase 1 (done):** Complete Erlang/NIF implementation. ✓

**Phase 2 (current decision point):** Add WASM for dense + sparse + random only.
- Exclude `opt` module from JS target with a clear error
- This covers the most common use cases with manageable scope
- Estimated: 3-4 weeks

**Phase 3 (later):** Evaluate HiGHS WASM via emscripten if users need it.

**If JavaScript Support Isn't Critical:**

**Stick with Erlang-only (Option B):**
- Document clearly in README: "Erlang target only"
- Focus on best-in-class Erlang/BEAM experience
- Revisit JavaScript support if users request it

---

### 9. Performance Expectations

If you implement WASM support, set clear expectations:

| Matrix Size | Erlang/NIF | JavaScript/WASM | Ratio |
|-------------|------------|-----------------|-------|
| 10x10 | 10 us | 30 us | 3x slower |
| 100x100 | 500 us | 2 ms | 4x slower |
| 1000x1000 | 50 ms | 500 ms | 10x slower |
| 5000x5000 | 2 s | 40 s | 20x slower |

**Usability guidelines:**
- **Good for:** Matrices <500x500, prototyping, client-side demos
- **Acceptable for:** Matrices 500-1000, non-critical workloads
- **Not suitable for:** Matrices >1000x1000, real-time constraints

---

### 10. Required Changes Summary

#### Major Architectural Changes:

1. **Rust codebase split:**
   - Rename current `native/waffle/` to `native/waffle_nif/`
   - New `native/waffle_wasm/` crate with wasm-bindgen, covering dense + sparse + random
   - Shared `utils.rs` logic (or duplicate the small file)

2. **Gleam multi-target API:**
   - Add `@external(javascript, ...)` declarations to each internal FFI binding
   - `opt` module returns `Error` on JS target

3. **Build system:**
   - Target detection in `waffle_build.gleam` and `waffle_setup.gleam`
   - Dual build paths (cargo for NIF, wasm-pack for WASM)
   - CI updates for WASM builds

4. **JavaScript glue layer:**
   - New `waffle_wasm.mjs` for WASM initialization and data conversion
   - Handles dense (f64 arrays), sparse (mixed i32/f64 arrays), and random

#### Minimal Changes:

- Pure Gleam code (`matrix.gleam`, `sparse.gleam`, `random.gleam`) requires no changes
- Public API surface remains identical for supported modules
- Tests can run on both targets (except `opt` tests)

---

## Conclusion

**How hard would it be?**
- High difficulty overall, due to scope growth and the HiGHS dependency
- 4-6 weeks of focused development (was 1.5-2 weeks before scope expanded)
- Significant testing required to ensure correctness across targets
- The `opt` module is a blocker for full parity — pragmatic to exclude it initially

**Would we need major architectural changes?**
- Yes, but well-structured:
  - Split Rust implementation into NIF and WASM crates
  - Add `@external` declarations for multi-target support
  - Create JavaScript glue layer
  - Update build system for dual targets

**The trade-off is clear:**
- **Benefit:** JavaScript target support enables browser/Node.js usage for dense/sparse/random
- **Cost:** 4-6 weeks development + ongoing maintenance + 3-20x performance loss on JavaScript + `opt` module unavailable on JS

**Recommendation:**
- **Phase 1:** Complete Erlang/NIF implementation ✓ (done as of v0.2.3)
- **Phase 2:** Gather user feedback — is JavaScript support needed?
- **Phase 3:** If yes, implement WASM for dense + sparse + random; exclude `opt` with clear error
- **Phase 4:** Revisit HiGHS WASM only if there is demonstrated demand
- **Document:** Set clear performance expectations and module availability for each target
