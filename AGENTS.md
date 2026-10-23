# Waffle — AI Assistant Guide

## Key Documents

| Document | What it's for |
|----------|---------------|
| This file (`AGENTS.md`) | Orient here first. Coding standards, pitfalls, getting started. |
| `README.md` | User-facing landing page with basic project and usage information. |
| `docs/ARCHITECTURE.md` | System architecture with diagrams. Human-focused onboarding. |
| `docs/ROADMAP.md` | Step-by-step implementation plan with checkboxes. |

---

## Project Overview

Waffle is a Gleam linear algebra library backed by Rust's `faer` crate via Rustler NIFs. It solves `Ax = b` using LU decomposition with partial pivoting.

Two language boundaries: Gleam → Erlang (FFI) → Rust (NIF). The Gleam side owns the public API and matrix types. The Rust side owns the computation. The Erlang layer is minimal glue for NIF loading.

This is not a wrapper around a CLI tool or external service. It is a native extension that runs inside the BEAM.

---

## Gleam Coding Standards

Write idiomatic Gleam. Concretely:

- **Pattern matching and custom types.** Model states and results as custom types. Match on them with `case` and function clauses. Types should make invalid states impossible.
- **`gleam format` is law.** Run before every commit.
- **`gleeunit` for tests.** Test functions end in `_test`. Follow the patterns in `test/`.
- **No panics, no `let assert` in production paths.** Return `Result` types. Propagate errors. `let assert` is fine in tests.
- **Type annotations on all public functions.** Format: `pub fn name(args) -> ReturnType`.
- **Minimal comments.** Write self-documenting code. Public interfaces may be documented if it aids clarity.
- **Document public interfaces.** This is a library - use `///` docstrings on all public types and functions to enable `gleam docs` generation.

### Avoiding Deep Nesting

Deeply nested case expressions (4+ levels) harm readability. Flatten control flow:

- **`use` bindings for sequential Results.** Replace nested `case` with `use x <- result.try(...)`.
  ```gleam
  use _ <- result.try(validate(x))
  use result <- result.try(compute(x))
  use _ <- result.try(save(result))
  Ok(Nil)
  ```

- **Use stdlib over explicit cases.** Prefer `result.map_error(fn)`, `result.unwrap(default)`, `result.replace(value)`.
  ```gleam
  do_thing() |> result.map_error(classify)
  ```

- **Remove unnecessary Result wrappers.** If a function never fails (uses `unwrap` with fallback), return the value directly instead of wrapping in `Result`.

- **Remove thin wrapper functions.** Inline functions that just delegate or add a single side effect, unless they serve a clear architectural purpose.

- **Boolean operators over case.** Use `force || should_rebuild()` instead of matching on booleans.

- **Multi-pattern case expressions.** Match on multiple values: `case row, list.length(row) { [], _ -> ..., _, n if n != expected -> ... }`.

See also: [Gleam language tour - Everything](https://tour.gleam.run/everything) for idiomatic patterns. 

### Software Design

- **Deep modules.** A module's public interface should be small and meaningful. Hide complexity.
- **Information hiding.** Expose only what callers need.
- **Layers should reduce complexity.** If a module just passes calls through, it is making things worse.

### File Structure

```
src/waffle/*.gleam           # Public API (matrix, linalg, sparse, random, opt, version)
src/waffle/internal/         # NIF bindings (Gleam wrappers + Erlang FFI)
src/waffle_build.gleam       # Build script (always compiles from source)
src/waffle_setup.gleam       # Setup script (builds if missing/outdated)

native/waffle/src/*.rs       # Rust NIF implementations split by domain
priv/                        # Compiled .so/.dll/.dylib (gitignored)
test/*_test.gleam            # Test modules
```

---

## Rust Coding Standards

- **Stable Rust.** No nightly features.
- **`NifResult` returns.** All NIFs return tagged tuples: `{ok, result}` or `{error, reason}`.

- **Minimal `unsafe`.** Only for zero-copy binary views. Document why each `unsafe` block is sound.
- **`cargo fmt` and `cargo clippy`.** Run before every commit.

---

## NIF Development Guidelines

- **DirtyCpu scheduling.** All compute NIFs use `#[rustler::nif(schedule = "DirtyCpu")]`. Matrix operations take >1ms and must not block the main BEAM scheduler.
- **Input validation before unsafe.** Validate binary lengths, dimensions, and alignment before creating `&[f64]` slices.
- **Tagged tuple returns.** NIFs return `{ok, binary}` or `{error, string}`. The Gleam wrapper converts these to `Result`.
- **Zero-copy input, copied output.** Input binaries are viewed in-place (no copy). Results are copied into new Erlang binaries.
- **Little-endian assumption.** f64 bytes are interpreted as little-endian. This holds on x86 and ARM.
- **Column-major layout.** Matrices are stored column-major (Fortran order), matching faer's native layout.

### NIF tuple encoding

When returning multiple values from a NIF, use nested tuples for Gleam pattern matching:

```rust
// Wrong - Gleam sees this as 4-element tuple
(atom_ok(env), rows, cols, bin).encode(env)

// Correct - Gleam pattern matches {ok, {rows, cols, bin}}
(atom_ok(env), (rows, cols, bin)).encode(env)
```

### Rust dependencies

Use [docs.rs](https://docs.rs) for Rust crate documentation. Key crates:

| Crate | Purpose | Rationale |
|-------|---------|-----------|
| `rustler` | Erlang NIF bindings | Safe Rust wrappers for NIF creation; handles type conversion |
| `faer` | Linear algebra | High-performance dense linear algebra; native column-major layout |
| `highs` | Optimization | Mixed-integer linear programming solver; CSC-friendly API; requires cmake |
| `bytemuck` | Zero-copy binary casting | Safe abstraction over `unsafe` pointer casting; eliminates UB class |
| `rand` + `rand_distr` | Quality RNG | ChaCha20 CSPRNG; efficient for large matrices; seeded variants for reproducibility |


---

## Development Workflow

The toolchain (Gleam, Erlang, Rust, just, cmake, libclang) comes from `flake.nix`; `.envrc` loads it through nix-direnv. Versions are pinned by `flake.lock` (`just upgrade` bumps it). CI runs in the same dev shell.

The project uses a `justfile` for unified dev commands across both languages. Run recipes from the project root:

**Always use `just` commands.** Don't run `gleam` or `cargo` directly. The justfile ensures:
- Both languages are formatted together
- Linting happens before tests
- The NIF is built when needed

| Command | What it does |
|---------|-------------|
| `just` | Default: format-check + lint + test (run before committing) |
| `just test` | Build NIF + run Gleam tests |
| `just fmt` | Auto-format both Gleam and Rust |
| `just lint` | Format checks + Clippy (read-only, CI-safe) |
| `just build` | Compile NIF from source (`gleam run -m waffle_build`) |
| `just bench` | Run benchmark suite (builds NIF first); `just bench 200` fixes iteration count |
| `just clean` | Clean all build artifacts |

### Underlying commands

For reference, the justfile wraps these:

```sh
# Gleam
gleam build                    # Compile
gleam check                    # Type-check without emitting
gleam test                     # Run all tests
gleam format src test          # Format source
gleam format --check src test  # Check formatting

# Rust (from project root)
cargo fmt  --manifest-path native/waffle/Cargo.toml          # Format
cargo clippy --manifest-path native/waffle/Cargo.toml        # Lint
cargo build --release --manifest-path native/waffle/Cargo.toml  # Build NIF
```

**Commit messages:** Use conventional commits format: `<type>: <description>`. Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`.

---

## Dependency Lookup

### Gleam dependencies

Use `rg` to look up function signatures and types in `build/packages/`.

| Your Goal | Required Action |
|-----------|-----------------|
| **Find a function's inputs** | `rg "pub fn function_name" build/packages/package_name` |
| **Understand a type** | `rg -A 30 "pub( opaque)? type TypeName" build/packages/package_name` |
| **Browse a module's API** | `rg "^pub (fn\|type\|const)" build/packages/package_name/src/module.gleam` |

Target the interface (`pub` lines). Stop at the signature.

### Rust dependencies

Use [docs.rs](https://docs.rs) for Rust crate documentation. See the dependency table in the NIF Development Guidelines section for key crates.

---

## Testing Strategy

### Gleam tests (public API)

- Test `matrix.from_list` / `matrix.to_list` round-trips
- Test `linalg.solve` with known solutions (e.g., identity matrix, simple 2x2, 3x3)
- Test error cases: singular matrices, dimension mismatches, empty inputs

### Integration

`gleam test` exercises the full path: Gleam → Erlang FFI → Rust NIF → faer → result back to Gleam. This provides complete coverage; Rust unit tests are not needed because the NIF layer is a thin wrapper.

### Test Writing Tips

- **Iteration order is column-major.** `fold` and `fold_with_indices` iterate column-by-column (Fortran order). When collecting results into a list, the order differs from natural row-major reading. Either:
  - Match the actual column-major order in expected output
  - Use order-insensitive checks (e.g., sort before comparing)

- **String tests should be flexible.** For `to_string` tests, prefer `string.contains()` over exact equality unless the format is critical. String representations may evolve.

- **Verify with `just`, not LSP.** After edits, the LSP may show stale errors. Run `just lint` for the real diagnostics.

---

## Known Pitfalls

### NIF not loaded

If the NIF shared library is missing from `priv/`, all NIF calls crash. The error message should tell the user to run `gleam run -m waffle_setup`. Check this first when debugging test failures.

### Binary alignment

`&[f64]` requires 8-byte alignment. Erlang binaries are typically aligned, but verify with assertions in debug builds.

### Cross-platform library extensions

The compiled NIF has different extensions per OS:
- Linux: `.so`
- macOS: `.dylib`
- Windows: `.dll`

The build script and FFI loader must handle all three.

### Column-major vs row-major

Gleam/user input is naturally row-major (`[[1, 2], [3, 4]]`). faer expects column-major. The `waffle/matrix` module must transpose during `from_list`.

### LSP stale errors

After editing imports or adding modules, the Gleam LSP may show false errors. Run `just lint` to verify—the compiler is the source of truth, not the LSP.

---

## Getting Started (for AI Assistants)

### Adding a new NIF function

1. **Rust:** Add the function in the appropriate module (`dense.rs`, `sparse.rs`, `opt.rs`, `random.rs`) with `#[rustler::nif(schedule = "DirtyCpu")]`. Return tagged tuples.
2. **Rust:** Register it in `rustler::init!` in `lib.rs`.
3. **Erlang:** Add the function stub in `src/waffle/internal/ffi/nif.erl` that raises `nif_not_loaded`.
4. **Gleam:** Add the `@external(erlang, "nif", "function_name")` binding.
5. **Test:** Write a Gleam test that calls the public API and verifies the result.

### Adding a pure Gleam function

1. Add the function in the appropriate module (`waffle/matrix.gleam`, `waffle/linalg.gleam`).
2. Write tests in `test/`.
3. No Rust or Erlang changes needed.

### Modifying the build scripts

Two build entry points:
- `src/waffle_build.gleam` — always builds from source (`gleam run -m waffle_build`). Used by CI.
- `src/waffle_setup.gleam` — builds only if NIF is missing or version mismatches (`gleam run -m waffle_setup`). Used by end users.

Changes here affect how users install the native library.
