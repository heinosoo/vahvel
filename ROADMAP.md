# Waffle roadmap

Focus: an idiomatic Gleam optimization library with a small native solver layer.
These are rough priorities; API shapes and backend choices remain open.

## Next: implement accepted API decisions

Decisions are recorded in [API-DESIGN.md](API-DESIGN.md). One commit per step,
each reviewed before the next and leaving `just` green.

1. **Driver contract** (Rust and `driver.gleam`): `InvalidModel` carries the
   position of the invalid variable or row; an empty domain is `Infeasible`.
   D17.
2. **Expressions and constraints:** `Term` lists, keyless
   `LessEqual`/`Equal`/`GreaterEqual`, `Minimize`/`Maximize`; remove the
   expression algebra, `multiply`, the `dual` stub, and constraint keys. D3, D5,
   D9, D11, D12, D20.
3. **Variables by use:** `domain` function, modeling-layer domain types, and
   driver positions mapped back to variable keys. D7, D22.
4. **Overflow checks** during compilation. D17.
5. **Solution queries:** `values` and `evaluate`. D19.

Afterwards:

- Benchmark model construction on larger sparse models. D4.
- Revisit model-local keys versus runtime handles. D8.
- Solve-limit and dual-capable backend contracts. D24, D20.
- Re-evaluate module boundaries between `model` and `driver`, e.g. whether the
  driver should own row canonicalization (sorting, merging duplicates, dropping
  zeros) once a second IR producer appears. D1, D23.

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
