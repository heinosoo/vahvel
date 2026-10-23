# Waffle roadmap

Focus: an idiomatic Gleam optimization library with a small native solver layer.
These are rough priorities; API shapes and backend choices remain open.

## Next: implement accepted API decisions

Decisions are recorded in [API-DESIGN.md](API-DESIGN.md). One commit per step,
each reviewed before the next and leaving `just` green.

1. Done. **Driver contract** (Rust and `driver.gleam`): `InvalidModel` carries
   the position of the invalid variable or row; an empty domain is
   `Infeasible`. D17.
2. Done. **Expressions and constraints:** `Term` lists, keyless
   `LessEqual`/`Equal`/`GreaterEqual`, `Minimize`/`Maximize`; remove the
   expression algebra, `multiply`, the `dual` stub, and constraint keys. D3, D5,
   D9, D11, D12, D20.
3. Done. **Variables by use:** `domain` function, modeling-layer domain types,
   and driver positions mapped back to variable keys. D7, D22.
4. Done. **Canonicalize in Rust.** The driver takes indexed, unsummed expressions
   (`Expression(terms, constants)`, rows as `lhs relation rhs`) and does all
   numeric work: `lhs − rhs`, sort, merge duplicates, drop zeros, sum constants,
   finiteness checks reported as `NonFiniteObjective`/`NonFiniteRow(row)`. The
   modeling layer drops its float arithmetic and maps those errors to
   `NonFinite(location)`. Canonicalization tests move to the driver tests. D1,
   D4, D17.
5. Done. **Solution queries:** `values`, and `evaluate` with the arithmetic in a
   small NIF. D19.

Afterwards:

- Organize design records and instructions: AGENTS.md, API-DESIGN.md and
  ARCHITECTURE.md overlap (e.g. NIF scheduling and validation rules appear in
  several places). Decide which document owns which kind of rule.
- Benchmark model construction on larger sparse models. D4.
- Revisit model-local keys versus runtime handles. D8.
- Solve-limit and dual-capable backend contracts. D24, D20.
- Truly unbounded integer variables: a `None` integer bound currently stops at
  the signed 32-bit range. Needs microlp to accept infinite integer bounds (it
  stores them as floats internally) or another backend. D22.
- JS target via Rust compiled to WASM: split the Rust code into a
  target-independent engine and thin adapters (Rustler, wasm-bindgen). D1.

## Representative models

Explore representative LP/MILP models to guide a general-purpose API.

## Symbolic modeling

Design symbolic expressions, variables, objectives, and constraints, drawing on
JuMP, Pyomo, and MathOpt while fitting Gleam's types and syntax.

## References and validation

Design variable references, indexed collections, validation, and useful diagnostics.

## Model compilation

Compile models into the canonical numeric IR, keeping solver adapters small.

## Solution access

Design solution access by variable and constraint, with explicit solve status and
availability of values.

## Solve limits

Expose solve limits and distinguish optimal, feasible, and interrupted outcomes
as needed.

## Examples, tests, and performance

Add end-to-end examples and tests for the modeling API; measure model construction
and solving on representative problems.

## Convex quadratic objectives

Explore convex quadratic objectives and how to validate supported models.

## Clarabel

Evaluate Clarabel with its optional faer backend alongside microlp.

## Solver selection

Design automatic solver selection based on model capabilities, with an explicit
override and clear errors for unsupported models.
