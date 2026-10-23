# Waffle — coding guide

Read `README.md` for setup and `src/waffle/internal/driver.gleam` for the internal
model contract.

- Use `just` recipes for development. Run `just fmt` and `just` before committing.
- Write idiomatic Gleam: custom types, pattern matching, `Result`, and `use`
  bindings instead of deeply nested cases. No production panics or `let assert`.
- Annotate and document public types/functions. Keep comments minimal.
- Use stable Rust and avoid unsafe code. Compute NIFs use `DirtyCpu` scheduling
  and return tagged results matching the Gleam types.
- Validate input at the NIF boundary. Never change an explicit bound, relax
  integer variables, or return nonfinite floats to the BEAM.
- Test through Gleam and the real NIF with gleeunit. Cover solver results and
  invalid input; avoid assertions on exact error wording.
- Use conventional commit messages.

## Software Design

- **Deep modules.** Keep public interfaces small and meaningful; hide complexity.
- **Information hiding.** Expose only what callers need.
- **Layers should reduce complexity.** Avoid modules that merely pass calls through
  without serving a clear architectural purpose.

## Dependency Lookup

Gleam dependency source is available locally in `build/packages/`. Look up the
installed interfaces there with `rg`:

```sh
rg -A 10 'pub fn function_name' build/packages/package_name
rg -A 30 'pub( opaque)? type TypeName' build/packages/package_name
rg '^pub (fn|type|const)' build/packages/package_name/src/module.gleam
```

Read the signature or type definition; avoid browsing implementations unless needed.
Use [docs.rs](https://docs.rs) for Rust dependency documentation.
