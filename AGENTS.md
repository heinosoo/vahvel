# Vahvel — contributor guide

Start here. General working rules are below; everything else lives in one place:

| You want to | Read |
| --- | --- |
| Use the library or set it up | `README.md` |
| Understand how it works now | `ARCHITECTURE.md` |
| Know why it is this way, or change the public API | `DESIGN.md` ("Modeling API"), `src/vahvel.gleam` |
| Change the driver, Rust or NIFs | `ARCHITECTURE.md` ("Numeric driver contract", "Native boundary"), `DESIGN.md` ("Native boundary") |
| Plan work or find open questions | `ROADMAP.md` |

## Workflow

- Use `just` recipes for development. Run `just fmt` and `just` before committing.
- Use conventional commit messages.
- Keep the docs in their lanes: behavior changes update `ARCHITECTURE.md`,
  decision changes update `DESIGN.md` in place, and finished roadmap items are
  removed from `ROADMAP.md`.

## Code

- Write idiomatic Gleam: custom types, pattern matching, `Result`, and `use`
  bindings instead of deeply nested cases. No production panics or `let assert`.
- Annotate and document public types/functions. Keep comments minimal.
- Describe in Gleam, compute in Rust: no float arithmetic on user data in Gleam.
  Rust and NIF rules are in `DESIGN.md` ("NIF rules").

## Testing

- Test through Gleam and the real NIF with gleeunit. Cover solver results and
  invalid input; avoid assertions on exact error wording.
- Test files mirror the source tree; test the public API through `solve`.
  The exception is `test/examples/`: representative models, one per file,
  including the README examples. Judge API changes by how they read.
- Keep tests fast (milliseconds). Performance belongs in `just bench`
  (`test/bench.gleam`), not in large or timeout-based tests.

## Software Design

- **Deep modules.** Keep public interfaces small and meaningful; hide complexity.
- **Information hiding.** Expose only what callers need.
- **Layers should reduce complexity.** Avoid modules that merely pass calls through
  without serving a clear architectural purpose.

## Dependency Lookup

Gleam dependency sources are in `build/packages/`; search signatures there with
`rg` rather than reading implementations. Rust dependencies: [docs.rs](https://docs.rs).
