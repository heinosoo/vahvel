# Waffle architecture

Waffle is a Gleam library for linear and mixed-integer linear programming. Gleam
code describes models; a Rust NIF validates and solves them with
[microlp](https://docs.rs/microlp/0.6.0/microlp/). This document describes how the
pieces fit together as they are now. The reasons behind them are in
[DESIGN.md](DESIGN.md); planned work is in [ROADMAP.md](ROADMAP.md).

Status: `waffle` is the public modeling module and is unstable while the
package is 0.x. `waffle/setup` is the public build entry point. Everything below
`waffle/internal` is internal.

## Layers

```mermaid
flowchart TD
  A["Application model<br/>(custom-type keys, lists)"] --> B
  B["waffle<br/>model types, lowering, keyed solutions"] --> C
  C["waffle/internal/driver<br/>numeric contract (Gleam types)"] --> D
  D["waffle/internal/waffle_nif.erl<br/>NIF stubs, loads priv/waffle.*"] --> E
  E["native/waffle (Rust cdylib)<br/>decode, canonicalize, validate, solve"] --> F
  F["microlp<br/>simplex + branch and bound"]
```

| Layer | Files | Owns |
| --- | --- | --- |
| Modeling | `src/waffle.gleam` | Expressions, constraints, objectives and domains; lowering keys to columns; keyed solution queries |
| Numeric driver | `src/waffle/internal/driver.gleam` | The contract with Rust: domains, unsummed expressions, rows, outcomes, errors |
| Erlang FFI | `src/waffle/internal/waffle_nif.erl`, `waffle_build_ffi.erl` | Loading the shared library and the `nif_not_loaded` fallbacks; OS detection for the build |
| Native | `native/waffle/src/lib.rs`, `driver.rs` | Term decoding, canonicalization, validation, solver calls, evaluation |
| Build and setup | `src/waffle/setup.gleam`, `src/waffle/internal/build.gleam`, `src/waffle/internal/version.gleam` | Compiling the NIF, copying it to `priv/`, version checks |

Every `.erl` file is prefixed with `waffle_` (DESIGN.md: "NIF rules").

Each layer only talks to the one below it. The modeling layer never sees column
numbers from the outside, and the native layer never sees names or keys.

Gleam handles keys, columns, domains and structure; Rust does every numeric
operation: canonicalization, validation, solving, evaluation. The modeling layer
contains no float arithmetic (DESIGN.md: "Describe in Gleam, compute in Rust").

## Modeling layer

`waffle.gleam` turns a symbolic model, written with application-owned keys, into
the driver model, and maps the numeric result back to those keys. Expressions are
affine trees (`Linear(coefficient, key)`, `Constant(value)`,
`Sum(expressions)` or `Scaled(coefficient, expression)`), and constraints
relate two expressions (`LessEqual`, `Equal`, `GreaterEqual`). A
variable exists once an expression references it; the model's `domain`
function gives each variable's bounds and integrality.

```mermaid
flowchart LR
  A[Symbolic model] --> B[Assign columns on first reference]
  B --> C[Replace keys by columns, preserve tree]
  C --> D[driver.Model]
  B --> E[Column keys]
  D --> F[driver.solve]
  F --> G[Outcome with keyed solution]
  E --> G
  E --> H[Driver positions mapped to keys]
  F --> H
```

Compilation is pure, deterministic and arithmetic-free: columns follow the order
of first reference (objective, then constraints), rows follow constraint order,
and each expression becomes the same tree with keys replaced by columns.
Lowering preserves the tree shape and the depth-first order of leaves, including
duplicates and zeros, in one tail-recursive loop over an explicit stack of
frames. Scaling and summing happen in Rust. `Binary` lowers to the same integer
domain as `Integer(Some(0), Some(1))`. The column keys stay in Gleam and are
never passed to the NIF; they turn solver values into a keyed solution and
driver error positions into keys. Row positions map back to the constraints
themselves, so a `SolveError` names what the caller wrote. Solutions are
immutable snapshots indexed by the same keys, and carry the driver's statistics
with the solver time as a `Duration`. `evaluate` looks up values in Gleam and
sends the indexed expression and values to `driver_evaluate`, which shares
canonicalization with solving before multiplying by solution values.

## Numeric driver contract

`driver.gleam` defines the IR that crosses the native boundary:

- `Model(direction, variables, objective, rows)`. Variable references are
  zero-based positions in `variables`.
- `Expression` is `Linear(coefficient, index)`, `Constant(value)`,
  `Sum(expressions)` or `Scaled(coefficient, expression)`, nested to any depth.
  Indices may repeat and coefficients may be zero. The objective's constants
  are its offset.
- `Domain` is `Continuous(lower, upper)` with `Unbounded | Finite(Float)` bounds,
  or `Integer(lower, upper)` with inclusive `Option(Int)` bounds fitting signed
  32 bits; Rust turns `None` into `i32::MIN`/`i32::MAX`, microlp's integer
  range. Binary variables are `Integer(Some(0), Some(1))`. A domain with
  `lower > upper` is valid but empty and makes the model infeasible.
- `Row(lhs, relation, rhs)` relates two expressions.
- `solve` returns
  `Ok(Optimal(objective, values, stats) | Infeasible | UnboundedProblem)` or
  `Error(InvalidModel(reason) | SolverFailure(_))`. `Stats(nodes, iterations,
  nanoseconds)` copies microlp's node count, simplex iterations and elapsed
  solver time, all zero when the driver answers without calling microlp. Invalid input is distinct
  from a numerical or internal failure. The reason says where:
  `MalformedModel`, `InvalidObjective`, `InvalidDomain(variable)`,
  `InvalidRow(row)`, `NonFiniteObjective` or `NonFiniteRow(row)`, with
  zero-based positions that higher layers map back to their own names. The
  non-finite reasons are user data (an overflowing sum, or non-finite input on a
  target that allows it); the others, apart from domains, indicate a bug in the
  producer.

This contract is the single numeric interface. Higher layers produce it;
the native layer canonicalizes and enforces it.

## Native boundary

`driver_solve` canonicalizes, validates and solves a model on a dirty CPU
scheduler. `driver_evaluate` canonicalizes an indexed expression by the same
rules and computes its value at the supplied solution values, returning
`Error(Nil)` for an invalid expression or non-finite arithmetic. It also runs on
a dirty CPU scheduler because decoding and sorting are unrestricted work. The
rules NIFs follow are in DESIGN.md ("NIF rules").

**Term mapping.** Rustler derives decoders that match Gleam's Erlang
representation directly:

| Gleam | Erlang term | Rust derive |
| --- | --- | --- |
| `Minimize`, `LessEqual` (no fields) | `minimize`, `less_equal` | `NifUnitEnum` |
| `Finite(1.0)`, `Integer(Some(0), None)` | `{finite, 1.0}`, `{integer, {some, 0}, none}` | `NifTaggedEnum` |
| `Sum([..])`, `Scaled(2.0, ..)` (one node) | `{sum, [..]}`, `{scaled, 2.0, ..}` | `NifTaggedEnum` (`Node`) with `Term` children |
| `Row(..)`, `Model(..)` | `{row, ..}`, `{model, ..}` | `NifRecord` with `#[tag]` |
| `None`, `Some(1)` (`Option(Int)`) | `none`, `{some, 1}` | `NifTaggedEnum` (`IntegerBound`) |
| `Result(a, e)` | `{ok, A}`, `{error, E}` | `Result<T, E>` |

A Gleam type change must be matched in `driver.rs`, and vice versa. Expressions
are never decoded into a nested Rust value: each node's children stay `Term`s
on an explicit stack, so decoding, traversal and drop never recurse.

**Steps in `driver.rs`.**

1. Decode the model shell, then each variable domain, the objective and each
   row separately, so a failure reports its position. A term that isn't a model
   is `MalformedModel`; integer bounds outside `i32` are `InvalidDomain(i)`.
2. Canonicalize the objective and each row (`lhs − rhs`) by the rules in
   DESIGN.md ("Canonicalization"): expand the tree depth-first, multiplying
   scale factors into leaves; stable-sort terms by index, sum duplicates and
   constants in input order, then drop zeros. Every product and sum is checked. Overflow becomes infinity in
   `f64` and is reported as `NonFiniteObjective`/`NonFiniteRow(i)`; a malformed
   node or an index out of range is `InvalidObjective`/`InvalidRow(i)`. The
   objective becomes a dense vector plus offset; each row becomes sorted
   nonzero terms and a right-hand side. Everything is validated before solving,
   and nothing is clamped, rounded or relaxed.
3. Answer trivial cases directly: an empty domain or an unsatisfiable constant
   row means `Infeasible`; a model with no variables returns its offset as the
   optimum.
4. Build a microlp `Problem` and solve. microlp's infeasible and unbounded errors
   become outcomes; any other non-optimal return is a `SolverFailure`. An
   optimum carries microlp's statistics.
5. Reject non-finite objective or values instead of returning them to the BEAM.

Solver panics are caught with `catch_unwind` and returned as `SolverFailure`, so
the NIF always answers with a tagged result.

`nif_version` is a trivial NIF used for build/version checks.

## Build, loading and versions

- `just build` runs `gleam run -m waffle/internal/build`, which runs
  `cargo build --release` in `native/waffle` and copies the platform library to
  `priv/waffle.{so,dylib,dll}`.
- `gleam run -m waffle/setup` rebuilds only if the library is missing or its
  `nif_version` differs from `waffle/internal/version.package_version`;
  `--force` rebuilds anyway.
- `waffle_nif.erl` loads `priv/waffle` in its `on_load` hook. Until it is
  loaded, every stub raises `nif_not_loaded`. Its module name must match
  `rustler::init!` in `lib.rs`.
- The package version lives in `gleam.toml`, `native/waffle/Cargo.toml` and
  `src/waffle/internal/version.gleam`. The release workflow bumps all three
  together, and `version_test` checks they agree.
- Linux targets link `libstdc++` statically (`native/waffle/.cargo/config.toml`).

## Testing

All tests are gleeunit tests that go through the real NIF; there are no Rust
unit tests and no mocks.

Test files mirror the source tree, so test modules are namespaced too, except
for the representative models in `test/examples/`.

- `test/waffle_test.gleam`: gleeunit's entry point and the modeling API,
  grouped by concern: variables and keys, domains, constraints, expressions,
  outcomes and errors, solutions, and statistics.
- `test/examples/`: representative models. `readme_test` is the README's waffle
  stand in full, one test per step; `production_network_test` is a multi-period network with
  mixed variable families, sparse routes, cost breakdowns and a scenario,
  generated by size; `n_queens_test` is a small binary model built from index
  sets.
- `test/waffle/internal/driver_test.gleam`: the numeric contract, covering
  continuous and integer solves, canonicalization, offsets, infeasible and
  unbounded outcomes, constant models, positioned errors, non-finite sums,
  malformed terms and expressions, and `evaluate`.
- `test/waffle/internal/version_test.gleam`: NIF and package versions match.

## Tooling and CI

- `nix develop` (or direnv) provides Gleam, Erlang/OTP, Rust and just. The flake
  also supplies the native build toolchain, so CI and local builds match.
- `just` runs format checks, Clippy with warnings as errors, the native build,
  and tests. `just fmt` formats Gleam and Rust.
- `.github/workflows/test.yml` runs `just lint` and `just test` in the Nix dev
  shell on pushes and pull requests.
- `.github/workflows/release.yml` is manually triggered: it bumps the version,
  runs the checks, tags, and attaches a Linux x86_64 library to the GitHub
  release. That binary is built in Nix and may depend on Nix runtime paths, so
  it is not a portable prebuilt artifact; a cross-platform matrix is sketched
  in the workflow but not enabled.
