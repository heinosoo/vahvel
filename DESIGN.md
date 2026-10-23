# Waffle design

Why waffle is built the way it is, for both the Gleam API and the native layer.
[ARCHITECTURE.md](ARCHITECTURE.md) describes how it works; this file explains
the decisions behind it. Future work and open questions live in
[ROADMAP.md](ROADMAP.md).

This file describes the current design. When a decision changes, edit its entry
in place; git keeps the history. Each entry states the decision, why, and the
alternatives that were rejected, one line each with the reason.

## Principles

### Describe in Gleam, compute in Rust

**Decision.** The Gleam layer is symbolic: it assigns columns to keys,
evaluates domains, and lowers term lists to indexed but unsummed expressions. It
does no arithmetic on user floats. Rust does all numeric work: canonicalization,
validation, solving and evaluation. The two meet in one contract, the driver
model, sent in a single NIF call.

```
Gleam: keys → columns, domain(key), term lists → indexed expressions
  │ one dirty-CPU NIF call
Rust: decode → canonicalize → validate → solve → check results
  │ values in column order | positioned error
Gleam: values → keyed Solution; positions → keys and locations
```

**Why.**
- Performance: summing and sorting in Rust is much faster than in Gleam
  dictionaries.
- Portability: float behavior differs by target. The BEAM raises on overflow and
  can't hold infinity or NaN; JS silently produces both. With no float
  arithmetic in Gleam, the modeling layer behaves the same everywhere, and a
  future WASM build shares the Rust numeric rules.
- One place for numeric rules, which also decides where future checks belong.

**What stays in Gleam.** Key discovery and column assignment: `domain` is a
Gleam closure a NIF can't call, and keys are arbitrary Gleam values while Rust
only sees indices. This costs one dictionary lookup per term in Gleam.

**Adaptability.** Moving work to Rust means changing the one contract. Presolve,
scaling, or building CSC for Clarabel stay inside Rust. Persistent native models
need a resource handle. Moving key discovery needs a two-phase protocol (Rust
reports keys, Gleam answers with domains) or another way to supply domains. A
WASM target splits the Rust code into a target-independent engine plus thin
adapters (Rustler, wasm-bindgen).

**Rejected.**
- *Canonicalize and check in Gleam.* Needs IEEE edge-case reasoning (a
  round-to-even tie at the largest float) and target-specific behavior in the
  modeling layer. Implemented once and discarded.
- *Map keys to indices in Rust.* Rust would hash BEAM terms or JS values and
  couldn't call the `domain` closure without a second call and native state.
- *A sparse matrix (CSC/CSR) for every backend.* microlp takes rows one at a
  time; only a Clarabel adapter needs CSC.

### Plain data; invalid states unrepresentable

**Decision.** Models are immutable Gleam values: records, custom types and
lists, built with `list.map`/`list.filter`/`list.append` and varied with
`..model`. Types rule out what they can: nonlinear terms, invalid relations,
references to anything but a variable key. Rust checks the rest. No API surface
exists for capabilities that don't: no unreachable variants, no stub functions.

**Why.** The standard library already does the composition work, so the API
stays small, and what the types allow is what the solver accepts.

**Rejected.**
- *A builder pipeline* (`new() |> subject_to(...)`). More surface, no new
  capability.
- *Stubs for future features* (e.g. a `dual` that always errors). Unreachable
  capability.

### Outcomes are values, errors are failures

**Decision.** `solve` returns `Result(Outcome(v), Error(v))`. `Outcome` is
`Optimal(solution) | Infeasible | Unbounded`, and only `Optimal` carries a
solution. Unsatisfiable constant rows and empty domains are infeasibility.
`Error` separates user-data problems (`InvalidDomain(key)`,
`NonFinite(location)`) from internal failures (`SolverFailure`). Lowering a
model cannot fail; the first error found is reported.

**Why.** Infeasibility is a mathematical answer, not a failure. Tying the
solution to its variant makes reading values from a non-optimal result
impossible.

**Rejected.**
- *A status enum plus optional values* (MathOpt/JuMP style). Needs separate
  availability checks that Gleam variants encode directly.
- *`Result` on every expression operation.* Would make model code unreadable.
- *Collecting all errors.* More machinery; revisit when diagnostics need it.

### Representative models drive the API

**Decision.** API changes are judged by how the production, transportation and
binary-selection models in `test/waffle_test.gleam` read. JuMP, Pyomo and
MathOpt are influences, not syntax to copy.

**Why.** Concrete models expose ergonomic costs that abstract design hides, and
they double as regression tests. They're small, so they support no performance
claims; other libraries rely on macros, operator overloading or mutation that
Gleam lacks.

## Modeling API

### Expressions are lists of terms

**Decision.** An expression is a plain `List(Term(v))`; the empty list is zero.
Duplicate keys and zero coefficients are allowed: Rust canonicalizes anyway.
Expressions are affine only; there is no `multiply`.

```gleam
pub type Term(v) {
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
}

[Linear(3.0, X), Linear(2.0, Y), Constant(7.0)]          // 3x + 2y + 7
list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) })  // Σ wᵢ pickᵢ
list.append(e1, e2)                                       // e1 + e2
```

**Why.** It's Gleam data: immutable, pattern-matchable, composed with the
standard library. Every representative model is "coefficient × key, mapped over
data". A list of *terms* is their sum, so `[x, y]` is `x + y`; the sum of two
*expressions* is `list.append(e1, e2)`. No helpers are needed to build
expressions; a `scale` helper for reused expressions waits until a model needs
it.

**Naming.** In math an affine expression is a sum of linear terms and a constant
term, and JuMP (`terms`, `constant`), Pyomo and MathOpt (`terms`, `offset`)
split it the same way. Constructors are named by degree, so a future quadratic
term would be `Quadratic`, in its own type. Coefficients come first, as in `3x`.
Verbosity is acceptable because most terms come from a `list.map`, and callers
can rename at the import (`import waffle.{Linear as L, Constant as C}`), which
the `Term` docs mention.

**Affine only.** A general tree with `multiply` was implemented and compared: it
accepted products only when one side was constant, which `Linear` already
covers, and it rejected the rest late and without context, with surprising
rules (`0 * (x * x)` rejected, `(x - x) * x` accepted). A future quadratic
capability gets its own type (`Affine × Affine → Quadratic`) accepted only where
a backend supports it.

**Rejected.**
- *Operator-style algebra* (`constant`, `variable`, `add`, `scale`, `sum`).
  Imitates operator overloading Gleam lacks; every literal needs a constructor.
- *A record of terms plus one constant.* Composition then needs a helper.
- *An opaque canonical expression with smart constructors.* Brings back the
  constructor noise.
- *`Dict(v, Float)`.* `dict.from_list` silently replaces duplicates, so
  `x + 2x` would become `2x`.
- *An expression tree.* Re-lowered per use and needs care to avoid quadratic
  merging; its only benefit, structure for printing, is unused.
- *JuMP-style promotion of products at runtime.* Needs multiple dispatch; in
  Gleam the equivalent is distinct types.
- *`Term`/`Constant`, `Var`/`Const`, `Times`/`Plus` as constructor names.*
  Shadowing the type name, abbreviations, and `Plus(-1.0)` respectively.

### Constraints relate two expressions

**Decision.** One variant per relation, with no key:

```gleam
pub type Constraint(v) {
  LessEqual(lhs: List(Term(v)), rhs: List(Term(v)))
  Equal(lhs: List(Term(v)), rhs: List(Term(v)))
  GreaterEqual(lhs: List(Term(v)), rhs: List(Term(v)))
}

LessEqual([x, y], [Constant(4.0)])     // x + y ≤ 4
LessEqual([x], [y])                    // x ≤ y
GreaterEqual([x, y], [Constant(2.0)])  // 2 ≤ x + y ≤ 5
LessEqual([x, y], [Constant(5.0)])     //   as two constraints
```

**Why.** Reads in math order, `x ≤ y` needs no rearranging, constants come from
the terms, and each constraint becomes exactly one solver row. `GreaterEqual` is
redundant with a swapped `LessEqual` but kept for readability. The cost: a ranged
row is two constraints.

**Rejected.** Compared on the three rows above.
- *An expression within an interval of numbers* (`AtMost(4.0)`,
  `Between(2.0, 5.0)`). One ranged row, but `x ≤ y` must be rearranged and the
  constant has two homes.
- *An interval whose bounds are expressions* (`AtMost([y])`). Reads like the
  chosen form plus a nesting level.
- *Rows and bounds as separate, key-driven parts* (`bound: fn(row) -> Interval`).
  Exhaustive, but splits each constraint in two; see ROADMAP.md open questions.
- *Comparison against zero.* The solver's normal form; every row rearranged by
  hand.
- *Smart constructors over an opaque type.* The chosen form behind functions,
  less inspectable.
- *A bare `Float` right-hand side.* A loose positional number, and a second form
  for expressions on both sides.

### A constraint is its own identity

**Decision.** Constraints carry no key, so `Model(v)` has one type parameter.
Where a constraint must be identified (future duals), the constraint value
itself is the key: values have structural equality and any BEAM term can key a
dictionary. The function that builds a constraint is also its lookup:

```gleam
let capacity = fn(m: Machine) { LessEqual(hours_used(m), [Constant(m.hours)]) }
// constraints: list.map(machines, capacity)
dual(solution, capacity(m2))  // future
```

**Why.** Compilation and solving never used keys; slack needs none
(`evaluate(solution, lhs)`). Identity by value removes a type parameter, a field
on every row, and the zipping that positional results would need.

**Costs.**
- Identical constraints are one key. They are also redundant, so a dual-capable
  driver merges them into one row.
- Equal math is not equal values: `[x, y]` and `[y, x]` are separate rows.
- A lookup hashes the whole row, linear in its length.
- Errors can't print a short name; they report the list position.
- Values change with data across scenarios, so an old value won't find a row in
  a new solution.

**Rejected.**
- *A constraint key type* (`Model(v, c)`). Readable and stable, but ceremony on
  every row for a feature that doesn't exist yet.
- *An optional `Named(key, constraint)` wrapper.* Mixed lists; the type
  parameter remains.
- *Positional identity only.* Users would zip results against their own lists.
- *Opaque constraints.* Opaqueness gives no identity; fresh handles need
  threaded state or impure refs.

### Variables exist by reference

**Decision.** A variable exists once an expression references it, including
with coefficient zero. The model supplies `domain: fn(v) -> Domain`, typically
an exhaustive `case` over the key type.

**Why.** No declaration list to keep in sync with the expressions, no
unknown/duplicate variable errors, and type inference fills in the key type.

**Costs.** A variable never referenced doesn't exist; querying it is an error. A
model holding a closure can't be compared or printed. Key discovery stays in
Gleam because a NIF can't call the closure.

**Rejected.**
- *An explicit declaration list.* Inspectable, but duplicates the index set and
  needs unknown/duplicate checks.
- *Handles allocated by a state-threading builder.* Gleam has no mutation, and
  indexed families come back as `Dict` lookups, so keys return anyway.

### Domains

**Decision.**

```gleam
pub type Domain {
  Continuous(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
}
```

`None` means no bound; binary is `Integer(Some(0), Some(1))`. Continuous and
integer bounds behave the same for the user. microlp limits integer variables to
signed 32 bits, so a `None` integer bound means "no bound beyond that range":
Rust fills in `i32::MIN`/`i32::MAX`, microlp's documented convention. A truly
unbounded integer direction therefore reports `Optimal` at ±2³¹, which the
`Domain` docs state and a driver test pins.

**Why.** Users shouldn't have to guess a "large enough" integer bound, and the
backend limit belongs in one place, in Rust.

**Rejected.**
- *Required integer bounds.* Honest about the backend, but asymmetric with
  continuous bounds.
- *Filling in `None` integer bounds in Gleam.* A backend limit in the modeling
  layer.
- *Reporting an integer at the range edge as `Unbounded`.* Wrong when a
  zero-cost variable is parked at its bound among several optima.
- *A custom `Bound` type.* Its `Unbounded` clashes with `Outcome.Unbounded`;
  `Option` is the standard way to say "maybe absent".
- *`Binary`, `NonNegative` shorthands.* Second spellings of the general form.

### Keys are application values, local to a model

**Decision.** Variables are named by any Gleam value: custom types
(`Ship(Factory, Customer)`), tuples, strings or `Int`s. A key is a name, never a
column number; columns follow the order of first reference. A key means
something only within the model being solved; reusing one across models or
scenarios is fine, and mixing them up is not detected.

**Why.** Domain keys are self-describing and exhaustive, custom-type typos don't
compile, and no mutable allocation is needed. Gleam phantom types alone can't
give fresh per-model identities.

**Rejected.**
- *Solver column numbers.* Expose ordering to application code.
- *Runtime-identified handles that detect cross-model use.* An open question for
  models assembled from independent components; see ROADMAP.md.

### Index sets are plain collections

**Decision.** Index sets are ordinary `List`, `Dict`, tuples and custom types.
No index-set DSL, broadcasting, or implicit zip truncation. Network sums use
`list.group` or precomputed adjacency rather than filtering every route per
node. Any future indexed helper rejects duplicate keys, and a dot-product helper
rejects unequal lengths.

**Why.** The standard library already covers sparse, filtered and grouped index
sets, the role Pyomo's `Set` plays.

### Objective carries its direction

**Decision.** The objective is `Minimize(expression)` or `Maximize(expression)`.

**Why.** One concept, one value: direction and expression can't drift apart.

### Solutions

**Decision.** `value(solution, key)` returns a `Result`, never a substituted
zero. `values(solution)` returns all values keyed by variable.
`evaluate(solution, expression)` computes costs, breakdowns and slacks: Gleam
looks up values, reporting `NotInSolution(key)`, and a small NIF sums
`#(coefficient, value)` pairs, reporting `NonFiniteValue`. Solutions are
immutable snapshots.

**Why.** Silent zeros hide typos. Evaluating expressions is more useful for
reporting than single lookups. Passing pairs instead of indices leaves the NIF
with no malformed-input case.

### The API owns its types

**Decision.** `waffle` is the one public modeling module. Users never import
`waffle/internal/*`, and no public function takes or returns a driver type.
Tests check behavior through `solve`, not the lowered data. Split the module only
along real boundaries, never into forwarding modules.

**Why.** Internal modules must stay free to change.

**Rejected.** *Re-exporting driver types* and *a public `compile`.* Both leak
the internal contract.

## Native boundary

### The driver contract

**Decision.** Rust receives indices only: domains in column order, an objective
expression, and rows as `lhs relation rhs`, where each expression is
`Expression(terms, constants)`, unsummed and unordered. Rows correspond
one-to-one to constraints, so every solver position maps back to a key or
constraint. Keys and names never cross the boundary. The contract changes only
deliberately, in Rust and Gleam together.

**Why.** The NIF stays numeric, small and target-independent, and Gleam needs no
float arithmetic to produce it.

**Rejected.**
- *Passing names to the native layer.* No benefit for microlp, and it ties Rust
  to BEAM terms.
- *A canonical model produced by Gleam.* Gleam would do float arithmetic.

### Canonicalization

**Decision.** Rust stable-sorts terms by index, sums duplicates in input order
(starting from `0.0`), sums constants, checks finiteness, then drops exact zeros.
Rows become `lhs − rhs relation −constant`; the objective's constants become its
offset. Small coefficients are never dropped by an epsilon. Zero-coefficient
terms still have their index validated.

**Why.** Deterministic results; an epsilon would silently change the model;
validating cancelled terms keeps mistakes from vanishing.

**Cost.** Summing in input order can report an overflow another order would
avoid (`max + max − max`). Reordering would make results depend on more than
the input.

**Rejected.** *Epsilon cleanup of near-zero coefficients.* Silent model mutation.

### Validation and errors

**Decision.** Rust is the single place for numeric checks: bounds, integer
range, indices, finiteness of sums and results. It decodes each domain and row
separately, so failures carry a position:
- `InvalidDomain(variable)` for integer bounds outside 32 bits, mapped to
  `InvalidDomain(key)`;
- `NonFiniteObjective` and `NonFiniteRow(row)` for overflowing sums or
  non-finite input, mapped to `NonFinite(InObjective | InConstraint(index))`;
- `MalformedModel`, `InvalidObjective` and `InvalidRow(row)` for contract
  violations, which mean a bug in the producer and surface as `SolverFailure`.

An empty domain (`lower > upper`) is `Infeasible`, not invalid.

**Why.** Only bad domains and non-finite numbers can come from user data on
today's targets; everything else is a bug. BEAM floats are always finite and
raise on overflow; JS floats aren't. Summing in Rust's `f64` turns overflow into
infinity, which the finiteness check catches without special arithmetic.
Data-driven models can legitimately produce empty ranges.

**Rejected.**
- *Validating domains again in Gleam.* Bound rules in two places.
- *Overflow checks in Gleam before each addition.* Implemented and discarded;
  see the first principle.
- *Per-target FFI* (catch `badarith` on the BEAM, `isFinite` on JS). Two
  implementations of one rule.
- *Empty domains as invalid models.* Empty ranges are infeasibility.

### NIF rules

**Decision.**
- Stable Rust, no `unsafe`.
- Compute NIFs (`driver_solve`) run on `DirtyCpu` schedulers. NIFs whose work is
  small and linear in their input (`driver_evaluate`) run on normal schedulers.
- NIFs return tagged results matching the Gleam types; Rust panics are caught
  and returned as `SolverFailure`.
- Never change an explicit bound, relax integer variables, or return non-finite
  floats to the BEAM.
- Erlang modules share one global namespace and take their name from `-module`,
  so every `.erl` file is prefixed with `waffle_`.

**Why.** Long solves must not block normal schedulers, while dirty scheduling
would cost more than a single evaluation. A NIF that crashes takes down the
caller, so every failure must be a value.

## Deferred, with requirements

### Dual values

microlp 0.6.0 exposes no dual values, so there is no `dual` function. When a
backend provides them, they're queried by constraint value (see "A constraint is
its own identity"). Before shipping:
- define whether values are Lagrange multipliers or right-hand-side
  sensitivities, with signs per relation and objective direction;
- cover bound duals and reduced costs, and map transformed rows back (the driver
  drops empty rows before calling microlp, so it needs its own row map);
- make dual availability typed and independent of primal availability;
- remember MILP incumbents have no LP shadow prices; relaxations or
  fixed-integer resolves are separate, explicit models;
- verify with analytic LPs, KKT conditions and right-hand-side perturbation.

An explicit "unavailable" result always beats zero, NaN or invented prices.

### Solve limits

No time or iteration limits yet. When added, the outcome separates why solving
stopped from what data is available: optimal, feasible but unproven
(`Feasible(solution, gap)`), and stopped without a primal value
(`Stopped(reason)`). A time limit is not infeasibility, and a feasible incumbent
is not optimal. Today the driver treats any unexpected non-optimal return as a
`SolverFailure`. microlp 0.6.0 already supports `set_time_limit`, `solve_with`,
`TerminationReason`, `InterruptedSolve` and `resume`.

### Out of scope for now

Nonlinear expressions, automatic solver selection, persistent native models and
performance promises. Each is a separate ROADMAP.md item.

## References

Reviewed 2026-10-23. Design influences, not interfaces to copy.

- [JuMP expressions](https://jump.dev/JuMP.jl/stable/manual/expressions/):
  specialized affine and quadratic expression types motivate capability-specific
  types. JuMP also has a general `NonlinearExpr` tree and promotes products
  rather than rejecting them.
- [Pyomo sets](https://pyomo.readthedocs.io/en/stable/explanation/modeling/math_programming/sets.html):
  indexed and sparse sets; Gleam's standard library covers the same ground.
- [MathOpt](https://developers.google.com/optimization/math_opt): separates
  modeling from solving and supports solver-independent models.
- [MathOpt result contract](https://developers.google.com/optimization/service/reference/rest/v1/mathopt/solveMathOptModel):
  termination, primal results and dual results are distinct concepts.
- [JuMP solutions](https://jump.dev/JuMP.jl/stable/manual/solutions/):
  availability is checked separately from termination, and certificates differ
  from values.
- [microlp 0.6.0 Solution](https://docs.rs/microlp/0.6.0/microlp/struct.Solution.html):
  no public dual accessor; time limits and resumable solves exist.
- [Gleam opaque types](https://tour.gleam.run/advanced-features/opaque-types/):
  hide representation behind a small typed API.
