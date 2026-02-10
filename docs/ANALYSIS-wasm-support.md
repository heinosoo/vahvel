# Feasibility Assessment: JavaScript/WASM Target for Waffle

## Context

Waffle is a Gleam linear algebra library that uses Rust's `faer` crate via Erlang NIFs (Native Implemented Functions). The current architecture is:

```
Gleam (public API) -> Erlang (NIF loader) -> Rust (faer computation)
```

**Question:** Can we support Gleam's JavaScript compilation target by compiling the Rust code to WebAssembly? What architectural changes would be required?

---

## TL;DR Assessment

**Feasibility:** Technically possible but with significant trade-offs

**Difficulty:** Moderate to High
- Pure compilation: Moderate (faer to WASM is straightforward)
- Full integration: High (requires dual-target architecture)
- Performance: Significant degradation (3-20x slower than native)

**Architectural Changes:** Major refactoring required
- Need separate implementations for Erlang (NIF) vs JavaScript (WASM)
- Different build pipelines for each target
- Shared Gleam API layer with target-specific backends

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
@external(erlang, "waffle_ffi", "solve_linear_system")
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

#### Current Architecture (Erlang-only)

```
src/waffle/
  matrix.gleam              # Pure Gleam (works on all targets)
  solver.gleam              # Calls Erlang NIF
  build.gleam               # Downloads/builds .so/.dylib

src/waffle_ffi.erl          # Erlang NIF loader
native/waffle/              # Rust crate with rustler
  src/lib.rs                # NIF implementation
```

#### Proposed Dual-Target Architecture

```
src/waffle/
  matrix.gleam              # Pure Gleam (unchanged)
  solver.gleam              # Uses @external for both targets
  build.gleam               # Updated for dual-target builds

src/waffle_ffi.erl          # Erlang NIF loader (Erlang target only)

native/waffle_nif/          # Rust NIF for Erlang
  Cargo.toml                # rustler dependencies
  src/lib.rs                # NIF implementation

native/waffle_wasm/         # Rust WASM for JavaScript
  Cargo.toml                # wasm-bindgen dependencies
  src/lib.rs                # WASM implementation

src/waffle_wasm.mjs         # JavaScript glue layer
```

**Key Changes:**

1. **Split Rust implementations:**
   - `waffle_nif`: Uses `rustler`, targets `cdylib` for Erlang
   - `waffle_wasm`: Uses `wasm-bindgen`, targets `wasm32-unknown-unknown`

2. **Dual `@external` declarations** (at the FFI boundary, not the public API):
   ```gleam
   @external(erlang, "waffle_ffi", "solve_linear_system")
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

| Component | Difficulty | Effort | Notes |
|-----------|-----------|--------|-------|
| **Rust WASM port** | Moderate | 2-3 days | Mostly straightforward, disable threading/SIMD |
| **wasm-bindgen setup** | Easy | 1 day | Standard tooling, well-documented |
| **JavaScript glue layer** | Moderate | 1-2 days | Handle async init, data conversion |
| **Gleam @external setup** | Easy | 0.5 days | Add second `@external` attribute |
| **Build system updates** | Moderate | 1-2 days | Target detection, dual build paths |
| **Testing on both targets** | Hard | 2-3 days | Ensure numerical consistency |
| **CI/CD updates** | Moderate | 1 day | Build WASM in GitHub Actions |
| **Documentation** | Moderate | 1 day | Document performance trade-offs |

**Total estimated effort:** 1.5-2 weeks for experienced Rust/WASM developer

---

### 5. Technical Challenges

#### Challenge 1: Binary Data Conversion

**Problem:** Gleam BitArrays are `Uint8Array` on JavaScript, but faer needs `&[f64]` slices.

**Solution:** Convert in JavaScript glue layer:
```javascript
// Gleam sends column-major f64 bytes as Uint8Array
const float64View = new Float64Array(uint8Array.buffer);
```

**Risk:** Endianness assumptions (little-endian on x86/ARM/WASM is safe).

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

### 6. Alternative Approaches

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

**Verdict:** Simplest approach if JavaScript target isn't a priority.

---

#### Option C: Server-Side Computation API

For JavaScript target, call a server endpoint that runs the Erlang version:

```gleam
@external(erlang, "waffle_ffi", "solve_linear_system")
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

### 7. Recommendations

#### Recommended Approach: Dual-Target with WASM

**If you want JavaScript support, implement WASM because:**
1. Maintains behavioral consistency across targets
2. Enables offline/client-side usage
3. Better performance than pure JS libraries
4. Aligns with Gleam's multi-target philosophy

**Implementation order:**
1. Complete Erlang/NIF implementation first (current roadmap)
2. Add WASM target as Phase 2 (after v1.0)
3. Document performance differences clearly

#### If JavaScript Support Isn't Critical:

**Stick with Erlang-only (Option B):**
- Document clearly in README: "Erlang target only"
- Focus on best-in-class Erlang/BEAM experience
- Revisit JavaScript support if users request it

---

### 8. Performance Expectations

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

### 9. Required Changes Summary

#### Major Architectural Changes:

1. **Rust codebase split:**
   - Separate NIF and WASM implementations
   - Shared faer logic, different FFI boundaries

2. **Gleam multi-target API:**
   - Add `@external(javascript, ...)` declarations
   - Maintain single public API

3. **Build system:**
   - Target detection
   - Dual build paths (cargo for NIF, wasm-pack for WASM)
   - CI updates for WASM builds

4. **JavaScript glue layer:**
   - New `.mjs` file for WASM initialization and data conversion
   - Handle async WASM loading

#### Minimal Changes:

- Pure Gleam code (matrix.gleam) requires no changes
- Public API surface remains identical
- Tests can run on both targets

---

## Conclusion

**How hard would it be?**
- Moderate difficulty - Technically straightforward but requires careful planning
- 1.5-2 weeks of focused development
- Significant testing required to ensure correctness across targets

**Would we need major architectural changes?**
- Yes, but the changes are well-structured:
  - Split Rust implementation into NIF and WASM variants
  - Add `@external` declarations for multi-target support
  - Create JavaScript glue layer
  - Update build system for dual targets

**The trade-off is clear:**
- **Benefit:** JavaScript target support enables browser/Node.js usage
- **Cost:** 1.5-2 weeks development + ongoing maintenance + 3-20x performance loss on JavaScript

**Recommendation:**
- **Phase 1:** Complete Erlang/NIF implementation (current roadmap)
- **Phase 1.5:** Gather user feedback - is JavaScript support needed?
- **Phase 2:** If yes, implement WASM support as described here
- **Document:** Set clear performance expectations for each target
