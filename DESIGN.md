# Vahvel design

Why vahvel is built the way it is, for both the Gleam API and the native layer.
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
  arithmetic in Gleam, the modeling layer behaves the same everywhere.
- One place for numeric rules: a new numeric check goes in Rust, never in Gleam.

**What stays in Gleam.** Key discovery and column assignment: `domain` is a
Gleam closure a NIF can't call, and keys are arbitrary Gleam values while Rust
only sees indices. This costs one dictionary lookup per variable reference in
Gleam. Measured (`just bench`), lowering and keyed results take about 0.3 µs
per term, as much as Rust's work outside the solver; on a 21,000-row LP the
two together are about 2% of wall time, so the solver dominates.

**Rejected.**
- *Canonicalize and check in Gleam.* Needs IEEE edge-case reasoning (a
  round-to-even tie at the largest float) and target-specific behavior in the
  modeling layer. Implemented once and discarded.
- *Map keys to indices in Rust.* Rust would hash BEAM terms or JS values and
  couldn't call the `domain` closure without a second call and native state.

### Plain data; invalid states unrepresentable

**Decision.** Models are immutable Gleam values: records, custom types and
lists, built with `list.map`/`list.filter`/`list.append`/`list.group` and
varied with `..model`. Index sets are ordinary collections: no index-set DSL,
broadcasting or implicit zip truncation. Types rule out what they can:
nonlinear terms, invalid relations, references to anything but a variable key.
Rust checks the rest. No API surface exists for capabilities that don't: no
unreachable variants, no stub functions.

**Why.** The standard library already does the composition work, including
the sparse, filtered and grouped index sets Pyomo's `Set` provides, so the API
stays small, and what the types allow is what the solver accepts.

**Rejected.**
- *A builder pipeline* (`new() |> subject_to(...)`). More surface, no new
  capability.
- *Stubs for future features* (e.g. a `dual` that always errors). Unreachable
  capability.

### Outcomes are values, errors are failures

**Decision.** `solve` returns `Result(Outcome(v), SolveError(v))`. Infeasible
and unbounded models, including unsatisfiable constant rows and empty domains,
are outcomes. Only `Optimal` claims a proof; `Limited` names the budget that
stopped search and may carry an incumbent, and no incumbent does not mean
infeasible. `SolveError` separates problems in the caller's input, named by
key, constraint or limit, from `SolverFailure`, which the caller can't act on
(solver failures, internal bugs and caught panics). Evaluation has its own
error type (see "Solutions and evaluation"). Lowering cannot fail; the first
error found is reported.

**Why.** Infeasibility is a mathematical answer, not a failure. Tying the
assignment to its variant makes reading unavailable values impossible.
Either limit can expire with or without an incumbent: `Limited` factors these
four valid cases into reason and availability without four constructors.
Errors name what the caller wrote: a key, or the constraint itself, following
"A constraint is its own identity", with its position for locating it in the
list. One error type per operation lists only failures that operation can
produce.

`InvalidDomain` covers both a backend limit (integer bounds outside 32 bits)
and invalid input (a non-finite bound on a target that allows one): either way
the domain can't be solved here. It splits when a second backend gives the
distinction a use.

**Rejected.**
- *Independent status and optional values on every outcome.* Allows an optimum
  without values or an infeasible answer with them. `Option` belongs only in
  `Limited`, where both availability states are meaningful.
- *Separate `Feasible` and `Stopped` variants.* Valid, but splits handling of
  budget stops across two variants; `Limited(_, Some(solution), _)` remains a
  direct pattern for accepting an incumbent.
- *Collecting all errors.* More machinery; revisit when diagnostics need it.
- *One error type for solving and evaluation.* Every caller would handle
  failures its operation can't produce.
- *Only the constraint's position.* Meaningless for constraints mapped from
  data; the caller would index back into their list.
- *A structured `SolverFailure` reason.* The caller can't act on any of them
  differently; stopped solves become outcomes (see "Solve limits").

### API criteria and representative models

**Decision.** Judge an API change by how models read with it and by what it
adds to the public interface. Test correctness independently of examples,
including invalid inputs, numerical edge cases and deeply nested expressions.

Follow the standard library's conventions where an operation matches one, as
`value` follows `dict.get`: familiar shapes surprise less, and an
implementation that reduces to a standard function is a good sign, not a
shallow layer. A convenience function earns its place when it names a
recommended pattern for a common value source, is exactly equivalent to a core
call, and adds no policy: no defaults, validation or error translation. Such
functions make recommended patterns discoverable and cost little to maintain;
the criterion keeps them from becoming an unorganized heap.

The representative models in `test/examples/` check ergonomics; grow the set
when a model with new structure tests the API differently. JuMP, Pyomo and
MathOpt are influences, not syntax to copy: they rely on macros, operator
overloading or mutation that Gleam lacks.

**Why.** Concrete models expose ergonomic costs but only reveal what they
exercise, so they are evidence, not the sole acceptance criterion, and their
small size supports no performance claims.

## Modeling API

### Expressions are an affine tree

**Decision.** An expression is a small affine tree: `Variable`, `Linear` and
`Constant` leaves, with `Sum`, `Difference` and `Scaled` combinators.
`Sum([])` is zero. Duplicate keys and zero coefficients are allowed: Rust
canonicalizes anyway. There is no `multiply`, so every expression is affine by
construction.

```gleam
Sum([Linear(3.0, X), Linear(2.0, Y), Constant(7.0)])          // 3x + 2y + 7
list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) }) |> Sum  // Σ wᵢ pickᵢ
Difference(revenue, cost)                                    // revenue − cost
```

**Why.** Every operation takes and returns an expression, so reuse is ordinary
nesting: a named expression goes anywhere an expression does, without
flattening or copying. Weighted variables mapped over data become one `Sum`,
which ends a pipeline; unweighted sums use `list.map(keys, Variable) |> Sum`.
Sides with a single term need no wrapper (`LessEqual(x, Constant(4.0))`),
which offsets the `Sum` on sides with several. It is still plain Gleam data:
immutable, pattern-matchable, built with the standard library, and composed
without float arithmetic in Gleam.

**Naming.** `Linear` names a weighted variable by degree, so a future quadratic
term would be `Quadratic`, in its own type. `Variable` names an unweighted
reference; `Sum`, `Difference` and `Scaled` name operations. `Linear` stays a
leaf rather than `Scaled(c, Variable(key))`: weighted variables are the dominant
construction, and two constructors per term would hurt readability.
Coefficients come first, as in `3x`. Callers can rename at the import
(`import vahvel.{Linear as L, Constant as C}`), which the `Expression` docs
mention.

**Convenience forms.** `Variable` and `Difference` lower to `Linear(1.0, key)`
and `Sum([lhs, Scaled(-1.0, rhs)])`: structural expansions, not arithmetic or
simplification, so cancelled references are still validated in Rust and the
native contract gains no variants. Unary negation remains
`Scaled(-1.0, expression)`.

**Costs.** Summation needs an explicit `Sum`. Equal math has more spellings
(`x`, `Sum([x])`, `Scaled(1.0, x)`); conveniences and their expansions also
remain structurally distinct. See "A constraint is its own identity".
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
  Add a second construction style; public constructors expose the same structure
  for construction and pattern matching.
- *An opaque canonical expression with smart constructors.* Brings back the
  function-call noise and hides the structure.
- *`Dict(v, Float)`.* `dict.from_list` silently replaces duplicates, so
  `x + 2x` would become `2x`.

### Constraints relate two expressions

**Decision.** One variant per relation (`LessEqual`, `Equal`,
`GreaterEqual`), each relating two expressions, with no key:

```gleam
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
- *Rows and bounds as separate, key-driven parts* (`bound: fn(row) -> Interval`).
  Exhaustive, but splits each constraint in two.
- *A bare `Float` right-hand side.* A loose positional number, and a second form
  for expressions on both sides.

### A constraint is its own identity

**Decision.** Constraints carry no key, so `Model(v)` has one type parameter.
Where a constraint must be identified, the constraint value itself is the
identity: errors return it alongside its position, and reports key residuals
by it. The function that builds a constraint is also its lookup, as in the
production network's `capacity(factory, period)`.

**Why.** Solving and residuals need no keys, and values have structural
equality, so identity by value costs no type parameter or field on every row.

**Costs.** Equal math is not equal values: `Sum([x, y])` and `Sum([y, x])` are
different constraints. Errors can't print a short name, so they also report
the list position.

**Rejected.** *A constraint key type* (`Model(v, c)`). Readable and stable,
but ceremony on every row that nothing currently needs.

### Variables are application keys, created by reference

**Decision.** Variables are named by any Gleam value, usually a custom type
naming the decision, never by column number. A variable exists once an
expression references it, including with coefficient zero. The model supplies
`domain: fn(v) -> Domain`, typically an exhaustive `case` over the key type. A
key means something only within the model being solved; mixing up keys across
models is not detected.

**Why.** No declaration list to keep in sync with the expressions, no
unknown/duplicate variable errors, and type inference fills in the key type.
Custom-type keys are self-describing, typos don't compile, and no mutable
allocation is needed.

**Costs.** A variable never referenced doesn't exist; looking it up is
`Error(Nil)`, the same as a wrong key. Reports therefore walk the data that
built the model and take absent decisions, like the production network's
unavailable lanes, from that data. Every key a report reads is then a
variable, and a failed lookup is a bug to report, never a zero. The examples
need no API to retain or discover variables; `values(solution)` lists the
referenced ones. A model holding a closure can't be compared or printed. Key
discovery stays in Gleam because a NIF can't call the closure.

**Rejected.**
- *An explicit declaration list.* Inspectable, but duplicates the index set and
  needs unknown/duplicate checks.
- *Handles allocated by a state-threading builder.* Gleam has no mutation, and
  indexed families come back as `Dict` lookups, so keys return anyway.
- *Runtime-identified handles that detect cross-model use.* Mix-ups matter
  mainly for models assembled from independent components, and Gleam phantom
  types alone can't give fresh per-model identities.

### Domains

**Decision.** `Real` and `Integer` take optional inclusive bounds, `None`
meaning no bound. `Binary`, `NonNegativeReal` and `NonNegativeInteger` are
shorthands that lower to them and share their validation. Real and integer
bounds behave the same for the user. microlp limits integer variables to signed
32 bits, so a `None` integer bound means "no bound beyond that range": Rust
fills in `i32::MIN`/`i32::MAX`, microlp's documented convention. A truly
unbounded integer direction therefore reports `Optimal` at −2³¹ or 2³¹ − 1,
which the `Domain` docs state and a test pins.

**Why.** Users shouldn't have to guess a "large enough" integer bound, and the
backend limit belongs in one place, in Rust.

**Naming.** `Real` and `Integer` name the values a variable may take; the
driver uses the same names. The shorthands state common modeling intent, and
their names say whether values are real or integer, as Pyomo's do.
`NonNegativeInteger` retains the backend's integer limit.

**Rejected.**
- *Required integer bounds.* Honest about the backend, but asymmetric with
  real bounds.
- *Reporting an integer at the range edge as `Unbounded`.* Wrong when a
  zero-cost variable is parked at its bound among several optima.
- *A custom `Bound` type.* Its `Unbounded` clashes with `Outcome.Unbounded`;
  `Option` is the standard way to say "maybe absent".

### Solutions and evaluation

**Decision.** `value(solution, key)` returns `Result(Float, Nil)` like
`dict.get`, never a substituted zero. `evaluate(expression, lookup)` computes
an expression at the values a `fn(v) -> Result(Float, Nil)` supplies, with the
same canonicalization as solving: costs and breakdowns at a solution, or the
cost of a hand-made plan or a what-if. `evaluate_solution` and
`evaluate_dict` are that call with `value(solution, _)` and
`dict.get(values, _)` as the lookup. Evaluation fails with its own
`EvaluationError(v)`: a missing value or overflow. All values are `Float`;
integer and binary values are exact whole numbers: microlp only guarantees
them within its integrality tolerance, so the driver rounds them. The
objective is microlp's own value, not recomputed from the rounded values.

**Why.** Silent zeros hide typos. Evaluation needs a lookup, not a storage
representation: assignments may be partial, and a dictionary, a `case` over
the key type, or solution values with overrides all fit. It needs neither a
model nor domains. A lookup has one failure, absence, and its caller knows the
key, so `Nil` is exact and `value` and `dict.get` are interchangeable. The
evaluator finds keys inside the expression, so its error names the missing
one; missing values are found before the native call, so they take precedence
over overflow. Expression-first argument order lets expressions pipe into
evaluation. Exact integer values make `float.round` lossless rather than a
tolerance guess. Shared canonicalization combines duplicates before
multiplying, avoiding spurious overflow for cancelling terms.

**Residuals.** `residual(constraint, lookup)` is exactly
`evaluate(Difference(lhs, rhs), lookup)` for every relation: a constraint holds
when its residual is at most zero (`LessEqual`), zero (`Equal`) or at least
zero (`GreaterEqual`). One formula means no per-relation signs to remember, and
the constraint value keys a report of a model's rows. It gives no verdict:
solver results satisfy rows only within the solver's tolerance, and a
tolerance is a policy. Rust sums each side's constants before subtracting when
solving, while evaluation adds the negated right side term by term, so a
residual can differ in the last digits from the solver's row, and near
overflow a row that solved can have a `NonFiniteValue` residual. Matching the
row exactly would need a driver contract change.

**Costs.** A report mixing `value` and evaluation aligns their errors itself,
e.g. `result.replace_error(MissingValue(key))`, rather than chaining one shared
error type. Every evaluation pays for column discovery and sorting. How often
the lookup is called is unspecified, so lookups should be pure.

**Rejected.**
- *One error type for `value` and `evaluate`.* Chains directly, but `value`
  would list an overflow it can't produce and differ from `dict.get`.
- *A lookup with its own error type* (`EvaluationError(v, e)`). Another type
  parameter for failures, like loading data, that belong before evaluation;
  mapping them to `MissingValue` would hide them instead.
- *`value_or` and `evaluate_or` with a default.* A default is a policy that
  makes substituted zeros look recommended and, for a whole expression, hides
  which key was missing.
- *Slack with a sign per relation.* Non-negative means satisfied for
  inequalities, but `Equal` has no slack, and sign conventions differ by source.
- *Evaluating many expressions in one call to get one `Result`.* `use`,
  `list.map` and `list.try_map` already combine one `Result` per expression;
  a single call costs about 2 µs including the NIF round-trip, too little to
  justify a batch call or a Gleam fast path.
- *Integer results (`value_int`, `evaluate_int`).* Converting by value depends
  on float noise, and classifying expressions by domain does too, through their
  coefficients. A domain-based `value_int` needs a driver contract change and
  duplicated storage to save a lossless `float.round`.

### Solve limits

**Decision.** `solve(model)` is unlimited; `solve_with(model, Limits(time,
nodes))` takes optional budgets. Limits belong to a call, not the mathematical
model. Support microlp's time and node limits; it exposes no simplex iteration
limit. No resume, cancellation or gap-based stopping API. Zero budgets are
valid and still permit validation and trivial proofs.

Durations are capped at 100 years. The fixed cap keeps one deterministic,
platform-independent check. microlp adds the budget to the current `Instant`
without checking, and the clock's range varies by platform; checking that sum
ourselves would duplicate it and race the backend's own addition. No useful
budget comes near the cap.

Time covers the backend solve, excluding lowering, decoding, canonicalization
and problem construction. Checks are cooperative, so a call may exceed its
budget. Follow the backend's reported stop reason; never infer one from
counters. A proof completed at a budget boundary remains a proof.

**Why.** Callers can trade search effort for a usable incumbent without
changing the model. The unlimited entry point keeps ordinary model code
concise. A node budget gives deterministic work control, while a time budget
also covers root LP work. Neither budget is a promise to cancel the whole NIF
call by a deadline.

**Rejected.** *Emulating iteration limits with node limits or an external
worker timeout.* Neither bounds simplex pivots; a worker timeout does not
recover the native incumbent or necessarily stop native computation.

### Solve statistics

**Decision.** Stats belong to the solve outcome, not its assignment:
`Optimal(solution, stats)` and `Limited(reason, optional_solution, stats)`.
`stats(outcome)` returns `Some(stats)` for either and `None` for `Infeasible`
or `Unbounded`, whose backend error paths supply no statistics. An opaque
`Solution` contains only the objective and keyed values.

A rounded zero gap alone never upgrades `Limited` to `Optimal`. Rust computes
the gap from the objective and bound, both shifted by the objective constant;
the denominator floor of 1 avoids huge ratios near zero and deliberately
differs from microlp's `1e-10`. Non-finite optional diagnostics become `None`;
non-finite primal values remain failures.

**Why.** `Limited` with and without an incumbent needs the same statistics, so
they can't live in `Solution` alone; storing them in both would duplicate them.
The native solver does not see Vahvel's objective constant, so copying its
relative gap would misreport shifted objectives.

**Rejected.**
- *An outer report with optional stats.* Adds a wrapper and makes stats
  optional even where the variants guarantee them.
- *Zero stats for infeasible/unbounded.* Would invent data about backend work.

## Native boundary

### The driver contract

**Decision.** Rust receives indices only: domains in column order, an indexed
objective tree, and rows as `lhs relation rhs`, one per constraint so every
position maps back to a key or constraint. Keys and names never cross the
boundary. The contract changes only deliberately, in Rust and Gleam together.

Nesting depth is bounded by memory, never by a stack: both sides walk the tree
with an explicit stack (ARCHITECTURE.md: "Native boundary").

**Why.** The NIF stays numeric, small and target-independent, and Gleam needs no
float arithmetic to produce it. The tree keeps sums and scaling scopes
structural and avoids a separate instruction format and scope validation. Deep
trees are ordinary (a fold accumulating `Sum([acc, term])`), and a native stack
overflow on a small dirty-scheduler stack would crash the VM rather than return
a `SolverFailure`.

**Rejected.**
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
zeros are dropped. Every sum must be finite. Rows become
`lhs − rhs relation −constant`; the objective's constants become its offset.
Small coefficients are never dropped by an epsilon.

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
separately, so failures carry a position that Gleam maps to a key or
constraint. Invalid domains and non-finite numbers are user errors; any other
contract violation is a bug in the producer and surfaces as `SolverFailure`.
An empty domain (`lower > upper`) is `Infeasible`, not invalid.

**Why.** Only bad domains and non-finite numbers can come from user data;
everything else is a bug. Summing in Rust's `f64` turns overflow into
infinity, which the finiteness check catches without special arithmetic.
Data-driven models can legitimately produce empty ranges.

**Rejected.**
- *Validating domains again in Gleam.* Bound rules in two places.
- *Empty domains as invalid models.* Empty ranges are infeasibility.

### Building the native library

**Decision.** The NIF is built from source with Cargo when its module loads and
the library is missing; `vahvel/setup` remains for ahead-of-time builds,
mismatches and `--force`. A failed build prints its cause and leaves the module
unloaded.

**Why.** Installing, upgrading and `gleam clean` all leave the library missing,
so an explicit step would be forgotten on every one of them. The cost is a
one-time blocking build that needs Rust and network access on first use.

**Rejected.** *Returning an `Error` from `solve`.* A setup failure isn't a model
outcome. *A rebar3 wrapper package building during `gleam build`.* A second
package published in lockstep.

### NIF rules

**Decision.**
- Stable Rust, no `unsafe`.
- Compute NIFs (`driver_solve`, `driver_evaluate`) run on `DirtyCpu` schedulers:
  both decode unbounded inputs and canonicalize expressions, including sorting.
- NIFs return tagged results matching the Gleam types; Rust panics are caught
  and returned as `SolverFailure`.
- Never change an explicit bound, relax integer variables, or return non-finite
  floats to the BEAM.
- Erlang modules share one global namespace and take their name from `-module`,
  so every `.erl` file is prefixed with `vahvel_`.

**Why.** Solving and expression evaluation must not block normal schedulers,
and a panic must reach the caller as a value, not crash the VM.

## Out of scope

Not implemented, and not planned:
- *General nonlinear expressions.* The backend solves linear models; a convex
  quadratic capability would get its own type (see "Affine only").
- *Persistent native models.* Each solve is one self-contained NIF call. A
  model handle adds native state and lifetimes to save overhead that is about
  2% of wall time (see "Describe in Gleam, compute in Rust").
- *Performance guarantees.* Solve time belongs to the backend; `just bench`
  measures vahvel's own overhead but nothing promises it.
- *Reusable Gleam–Rust tooling.* The build code serves this package only.

## References

Reviewed 2026-10-25. Design influences, not interfaces to copy.

- [JuMP expressions](https://jump.dev/JuMP.jl/stable/manual/expressions/):
  specialized affine and quadratic expression types motivate capability-specific
  types. JuMP also has a general `NonlinearExpr` tree and promotes products
  rather than rejecting them.
- [Pyomo sets](https://pyomo.readthedocs.io/en/stable/explanation/modeling/math_programming/sets.html):
  indexed and sparse sets; Gleam's standard library covers the same ground.
- [JuMP variable bounds](https://jump.dev/JuMP.jl/stable/manual/variables/)
  and [MathOpt modeling](https://developers.google.com/optimization/math_opt/basic_example):
  explicit arbitrary bounds alongside readable mathematical expressions.
- [Pyomo domains](https://www.pyomo.org/s/3_PyomoFundamentals.pdf):
  distinct nonnegative real and integer domains.
- [MathOpt](https://developers.google.com/optimization/math_opt): separates
  modeling from solving and supports solver-independent models.
- [MathOpt result contract](https://developers.google.com/optimization/service/reference/rest/v1/mathopt/solveMathOptModel):
  termination, primal results and dual results are distinct concepts.
- [JuMP solutions](https://jump.dev/JuMP.jl/stable/manual/solutions/):
  availability is checked separately from termination, and certificates differ
  from values.
- [microlp 0.8.0 Solution](https://docs.rs/microlp/0.8.0/microlp/struct.Solution.html):
  LP duals and reduced costs; integer values only within tolerance; time
  limits and resumable solves exist.
