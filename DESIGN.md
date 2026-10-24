# Waffle design

Why waffle is built the way it is, for both the Gleam API and the native layer.
[ARCHITECTURE.md](ARCHITECTURE.md) describes how it works; this file explains
the decisions behind it. Future work and open questions live in
[ROADMAP.md](ROADMAP.md).

This file describes the current design. When a decision changes, edit its entry
in place; git keeps the history. Each entry states the decision, why, and the
alternatives that were rejected, one line each with the reason. When a decision
changes, recheck the rejections elsewhere whose reasons depended on it.

## Principles

### Describe in Gleam, compute in Rust

**Decision.** The Gleam layer is symbolic: it assigns columns to keys,
evaluates domains, and lowers expressions to indexed but unsummed trees. It does
no arithmetic on user floats. Rust does all numeric work: canonicalization,
validation, solving and evaluation. The two meet in one contract, the driver
model, sent in a single NIF call.

```
Gleam: keys → columns, domain(key), expressions → indexed expressions
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
only sees indices. This costs one dictionary lookup per variable reference in
Gleam.

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

**Decision.** `solve` returns `Result(Outcome(v), SolveError(v))`. `Outcome`
is `Optimal(solution) | Infeasible | Unbounded`, and only `Optimal` carries a
solution. Unsatisfiable constant rows and empty domains are infeasibility.
`SolveError` separates user-data problems (`InvalidDomain(key)`,
`NonFinite(location)`) from failures the caller can't act on
(`SolverFailure(message)`, including internal bugs and caught panics). A
location is `InObjective` or `InConstraint(index, constraint)`. Querying a
solution has its own error, `QueryError` (see "Solutions"). Lowering a model
cannot fail; the first error found is reported.

**Why.** Infeasibility is a mathematical answer, not a failure. Tying the
solution to its variant makes reading values from a non-optimal result
impossible. Errors name what the caller wrote: a key, or the constraint
itself, following "A constraint is its own identity", with its position for
locating it in the list. One error type per operation lists only failures that
operation can produce. The names avoid shadowing `Result`'s `Error`.

`InvalidDomain` covers both a backend limit (integer bounds outside 32 bits)
and invalid input (a non-finite bound on a target that allows one): either way
the domain can't be solved here. It splits when a second backend gives the
distinction a use.

**Rejected.**
- *A status enum plus optional values* (MathOpt/JuMP style). Needs separate
  availability checks that Gleam variants encode directly.
- *`Result` on every expression operation.* Would make model code unreadable.
- *Collecting all errors.* More machinery; revisit when diagnostics need it.
- *One error type for solving and querying.* Every caller would handle
  failures its operation can't produce.
- *Only the constraint's position.* Meaningless for constraints mapped from
  data; the caller would index back into their list.
- *A structured `SolverFailure` reason.* The caller can't act on any of them
  differently; stopped solves become outcomes (see "Solve limits").

### Representative models drive the API

**Decision.** API and design changes are judged by how the representative
models in `test/examples/` read: the README's waffle stand, a multi-period
production network, and N-queens. The set grows when a model with new structure
(time-indexed scheduling, say) tests the API differently. JuMP, Pyomo and
MathOpt are influences, not syntax to copy.

**Why.** Concrete models expose ergonomic costs that abstract design hides, and
they double as regression tests. They only reveal what they exercise: a set
without expression reuse hides the value of composition. They're small, so they
support no performance claims; other libraries rely on macros, operator
overloading or mutation that Gleam lacks.

## Modeling API

### Expressions are an affine tree

**Decision.** An expression is a small tree: two leaves, `Linear` and
`Constant`, and two affine combinators, `Sum` and `Scaled`. `Sum([])` is zero.
Duplicate keys and zero coefficients are allowed: Rust canonicalizes anyway.
There is no `multiply`, so every expression is affine by construction.

```gleam
pub type Expression(v) {
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
  Sum(expressions: List(Expression(v)))
  Scaled(coefficient: Float, expression: Expression(v))
}

Sum([Linear(3.0, X), Linear(2.0, Y), Constant(7.0)])          // 3x + 2y + 7
list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) }) |> Sum  // Σ wᵢ pickᵢ
Sum([revenue, Scaled(-1.0, cost)])                            // revenue − cost
```

**Why.** Every operation takes and returns an expression, so reuse is ordinary
nesting: a named expression goes anywhere an expression does, without
flattening or copying. Every representative model is "coefficient × key, mapped
over data"; the mapped list becomes one `Sum`, which ends a pipeline. Sides with
a single term need no wrapper (`LessEqual(x, Constant(4.0))`), which offsets
the `Sum` on sides with several. It is still plain Gleam data: immutable,
pattern-matchable, built with the standard library, and composed without float
arithmetic in Gleam.

**Naming.** In math an affine expression is a sum of linear terms and a constant
term, and JuMP (`terms`, `constant`), Pyomo and MathOpt (`terms`, `offset`)
split it the same way. Leaves are named by degree, so a future quadratic term
would be `Quadratic`, in its own type; `Sum` and `Scaled` name the two affine
combinators. `Linear` stays a leaf rather than `Scaled(c, Variable(key))`:
weighted variables are the dominant construction, and two constructors per term
would hurt readability. Coefficients come first, as in `3x`. Callers can rename
at the import (`import waffle.{Linear as L, Constant as C}`), which the
`Expression` docs mention.

**Costs.** Summation needs an explicit `Sum`. Equal math has more spellings
(`x`, `Sum([x])`, `Scaled(1.0, x)`); see "A constraint is its own identity".
Trees can be as deep as the data; see "The driver contract".

**Affine only.** A general tree with `multiply` was implemented and compared: it
accepted products only when one side was constant, which `Linear` and `Scaled`
cover, and it rejected the rest late and without context, with surprising
rules (`0 * (x * x)` rejected, `(x - x) * x` accepted). A future quadratic
capability gets its own type (`Affine × Affine → Quadratic`) accepted only where
a backend supports it.

**Rejected.**
- *A list of terms, nested through a `Scaled` term.* A list is an expression
  but `Scaled` is a term, so whole expressions combine through `list.append` or
  `Scaled(1.0, e)`, and a single term can't stand where an expression is
  expected. Flat lists alone can't scale a reused expression without float
  arithmetic in Gleam.
- *Operator-style functions* (`constant`, `variable`, `add`, `scale`, `sum`).
  Imitate operator overloading Gleam lacks and hide the structure; the tree
  composes the same way with pattern-matchable constructors.
- *A record of terms plus one constant.* Composition then needs a helper.
- *An opaque canonical expression with smart constructors.* Brings back the
  function-call noise and hides the structure.
- *`Dict(v, Float)`.* `dict.from_list` silently replaces duplicates, so
  `x + 2x` would become `2x`.
- *A general algebra tree.* Unnecessary operators and late nonlinear errors;
  the affine tree cannot express a product of variables.
- *`Scaled(coefficient, Variable(key))` instead of `Linear`.* Two constructors
  for the most common term.
- *JuMP-style promotion of products at runtime.* Needs multiple dispatch; in
  Gleam the equivalent is distinct types.
- *`Term`, `Var`/`Const`, `Times`/`Plus` as leaf names.* A vague name,
  abbreviations, and `Plus(-1.0)` respectively.

### Constraints relate two expressions

**Decision.** One variant per relation, with no key:

```gleam
pub type Constraint(v) {
  LessEqual(lhs: Expression(v), rhs: Expression(v))
  Equal(lhs: Expression(v), rhs: Expression(v))
  GreaterEqual(lhs: Expression(v), rhs: Expression(v))
}

LessEqual(Sum([x, y]), Constant(4.0))     // x + y ≤ 4
LessEqual(x, y)                           // x ≤ y
GreaterEqual(Sum([x, y]), Constant(2.0))  // 2 ≤ x + y ≤ 5
LessEqual(Sum([x, y]), Constant(5.0))     //   as two constraints
```

**Why.** Reads in math order, `x ≤ y` needs no rearranging, a constant is an
ordinary expression, and each constraint becomes exactly one solver row.
`GreaterEqual` is redundant with a swapped `LessEqual` but kept for readability.
The cost: a ranged row is two constraints.

**Rejected.** Compared on the three rows above.
- *An expression within an interval of numbers* (`AtMost(4.0)`,
  `Between(2.0, 5.0)`). One ranged row, but `x ≤ y` must be rearranged and the
  constant has two homes.
- *An interval whose bounds are expressions* (`AtMost(y)`). Reads like the
  chosen form plus a nesting level.
- *Rows and bounds as separate, key-driven parts* (`bound: fn(row) -> Interval`).
  Exhaustive, but splits each constraint in two.
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
let capacity = fn(m: Machine) { LessEqual(hours_used(m), Constant(m.hours)) }
// constraints: list.map(machines, capacity)
dual(solution, capacity(m2))  // future
```

**Why.** Compilation and solving never used keys; slack needs none
(`evaluate(solution, lhs)`). Identity by value removes a type parameter, a field
on every row, and the zipping that positional results would need.

**Costs.**
- Identical constraints are one key. They are also redundant, so a dual-capable
  driver merges them into one row.
- Equal math is not equal values: `Sum([x, y])`, `Sum([y, x])` and
  `Sum([Sum([x]), y])` are separate rows.
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

**Costs.** A variable never referenced doesn't exist; querying it is
`NotInSolution(key)`. Reports that iterate the data rather than the model meet
such keys, like the production network's unavailable lanes, and handle them
through `value`'s `Result`; the examples have not needed a way to retain
unreferenced variables. A model holding a closure can't be compared or
printed. Key discovery stays in Gleam because a NIF can't call the closure.

**Rejected.**
- *An explicit declaration list.* Inspectable, but duplicates the index set and
  needs unknown/duplicate checks.
- *Handles allocated by a state-threading builder.* Gleam has no mutation, and
  indexed families come back as `Dict` lookups, so keys return anyway.

### Domains

**Decision.**

```gleam
pub type Domain {
  Binary
  Continuous(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
}
```

`None` means no bound; `Binary` lowers to `Integer(Some(0), Some(1))`.
Continuous and integer bounds behave the same for the user. microlp limits
integer variables to signed 32 bits, so a `None` integer bound means "no bound
beyond that range": Rust fills in `i32::MIN`/`i32::MAX`, microlp's documented
convention. A truly unbounded integer direction therefore reports `Optimal` at
±2³¹, which the `Domain` docs state and a driver test pins.

**Why.** Users shouldn't have to guess a "large enough" integer bound, and the
backend limit belongs in one place, in Rust.

**Convenience forms.** `Binary` states modeling intent and shares the integer
implementation. Further shorthands, such as `NonNegative`, are judged by caller
readability, not rejected for being a second spelling.

**Rejected.**
- *Required integer bounds.* Honest about the backend, but asymmetric with
  continuous bounds.
- *Filling in `None` integer bounds in Gleam.* A backend limit in the modeling
  layer.
- *Reporting an integer at the range edge as `Unbounded`.* Wrong when a
  zero-cost variable is parked at its bound among several optima.
- *A custom `Bound` type.* Its `Unbounded` clashes with `Outcome.Unbounded`;
  `Option` is the standard way to say "maybe absent".

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
- *Runtime-identified handles that detect cross-model use.* Mix-ups matter
  mainly for models assembled from independent components.

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
zero: an unreferenced key is `NotInSolution(key)`. `evaluate(solution,
expression)` computes costs, breakdowns and slacks with the same
canonicalization as solving. `value` and `evaluate` share `QueryError(v)`. All
values are `Float`; integer and binary values are exact whole numbers (microlp
rounds them), so callers convert with `float.round`. The objective is
microlp's own value, not recomputed from the rounded values.

**Why.** Silent zeros hide typos. A shared error type lets a report chain both
with `use … <- result.try`, and the error names the missing key. Exact integer
values make `float.round` lossless rather than a tolerance guess. Shared
canonicalization combines duplicates before multiplying, avoiding spurious
overflow for cancelling terms. The cost is column discovery and sorting on
every evaluation.

**Rejected.**
- *`value_or` and `evaluate_or` with a default.* Forwarding wrappers around
  `result.unwrap` that make substituted zeros look recommended; a default for a
  whole expression also hides which key was missing.
- *Evaluating many expressions in one call to get one `Result`.* `use` already
  chains one `Result` per expression.
- *Integer results (`value_int`, `evaluate_int`).* Converting by value depends
  on float noise, and classifying expressions by domain does too, through their
  coefficients. A domain-based `value_int` needs a driver contract change and
  duplicated storage to save a lossless `float.round`.

### Solve statistics

**Decision.** `stats(solution)` returns a public `Stats` record: branch-and-bound
nodes (zero for pure LP), simplex iterations including the root LP, and solver
time as a `gleam/time/duration.Duration`. There is one `solve`; statistics
travel inside the opaque `Solution`. `Infeasible` and `Unbounded` carry none.

**Why.** microlp collects statistics on every solve, so a second solve function
without them would save nothing and double the surface for later options.
Inside `Solution` they leave `solve` and `Outcome` unchanged for callers who
ignore them. microlp 0.6.0 reports infeasibility and unboundedness as errors
without statistics, and empty domains and constant rows never reach it, so
stats on those variants would be invented or partial. Solver time lets
benchmarks separate solving from construction and NIF overhead.

**Rejected.**
- *`solve_with_stats` alongside `solve`.* Two entry points for the same work.
- *Stats on every `Outcome` variant, or `#(Outcome, Stats)`.* Forces every
  caller to handle data most ignore, with nothing real to put in `Infeasible`.
- *Best bound and gap.* For an optimum they are the objective and zero; the gap
  returns with `Feasible` (see "Solve limits").
- *Time as `Int` microseconds.* `Duration` states the unit in the type.

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
expression, and rows as `lhs relation rhs`. Expressions mirror the public tree
with keys replaced by indices. Rows correspond one-to-one to constraints, so
every solver position maps back to a key or constraint. Keys and names never
cross the boundary. The contract changes only deliberately, in Rust and Gleam
together.

Nesting depth is bounded by memory, never by a stack. Gleam lowers the tree in
one tail-recursive loop over an explicit stack of frames. Rust decodes one node
at a time, keeping children as undecoded terms on a `Vec` stack, so no nested
Rust value exists whose decoding, traversal or drop would recurse.

**Why.** The NIF stays numeric, small and target-independent, and Gleam needs no
float arithmetic to produce it. The tree keeps sums and scaling scopes
structural and avoids a separate instruction format and scope validation. Deep
trees are ordinary (a fold accumulating `Sum([acc, term])`), and a native stack
overflow on a small dirty-scheduler stack would crash the VM rather than return
a `SolverFailure`.

**Rejected.**
- *Passing names to the native layer.* No benefit for microlp, and it ties Rust
  to BEAM terms.
- *A canonical model produced by Gleam.* Gleam would do float arithmetic.
- *Rustler-derived recursive decoding into a Rust tree.* Each nesting level
  costs native stack in decoding, traversal and drop.
- *A larger native stack* (the `stacker` crate or a big-stack thread). Raises
  the limit or adds a dependency instead of removing the recursion.

### Canonicalization

**Decision.** Rust expands the expression tree in depth-first input order.
Factors multiply outer-to-inner from `1.0`, then multiply each leaf coefficient
or constant; `Sum` contributes no factor. Each intermediate product must be
finite, including accumulated factors over empty sums; zero scales do not skip
references or validation. Constants sum in depth-first input order from `0.0`.
Terms are stable-sorted by index, duplicates sum in input order, then exact
zeros are dropped. Every sum must be finite. Rows become `lhs − rhs relation −constant`; the objective's
constants become its offset. Small coefficients are never dropped by an epsilon.

Scaling distributes over leaves before canonicalization. It is not a promise of
exact real arithmetic: nesting and regrouping can affect rounding, underflow or
overflow. Both solve and evaluate use these same rules.

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
- `InvalidDomain(variable)` for integer bounds outside 32 bits or non-finite
  bounds, mapped to `InvalidDomain(key)`;
- `NonFiniteObjective` and `NonFiniteRow(row)` for overflowing products/sums or
  non-finite input, mapped to `NonFinite(InObjective)` or
  `NonFinite(InConstraint(row, constraint))`;
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
- Compute NIFs (`driver_solve`, `driver_evaluate`) run on `DirtyCpu` schedulers.
  Both decode unrestricted inputs and canonicalize expressions, including sorting.
- NIFs return tagged results matching the Gleam types; Rust panics are caught
  and returned as `SolverFailure`.
- Never change an explicit bound, relax integer variables, or return non-finite
  floats to the BEAM.
- Erlang modules share one global namespace and take their name from `-module`,
  so every `.erl` file is prefixed with `waffle_`.

**Why.** Solving and expression evaluation must not block normal schedulers.
Benchmarks can justify a bounded fast path for small evaluations later. Solver
panics are caught so callers receive a failure value.

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
(`Feasible(solution)`), and stopped without a primal value
(`Stopped(reason, stats)`, from microlp's `InterruptedSolve`). The gap of a
feasible result belongs in its `Stats`, not in the variant. A time limit is not
infeasibility, and a feasible incumbent is not optimal. Today the driver treats
any unexpected non-optimal return as a `SolverFailure`. microlp 0.6.0 already supports `set_time_limit`, `solve_with`,
`TerminationReason`, `InterruptedSolve` and `resume`.

### Out of scope for now

Nonlinear expressions, automatic solver selection, persistent native models and
performance promises.

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
