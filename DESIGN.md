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
  arithmetic in Gleam, the modeling layer behaves the same everywhere, and a
  future WASM build shares the Rust numeric rules.
- One place for numeric rules, which also decides where future checks belong.

**What stays in Gleam.** Key discovery and column assignment: `domain` is a
Gleam closure a NIF can't call, and keys are arbitrary Gleam values while Rust
only sees indices. This costs one dictionary lookup per variable reference in
Gleam. Measured (`just bench`), lowering and keyed results take about 0.3 µs
per term, as much as Rust's work outside the solver; on a 21,000-row LP the
two together are about 2% of wall time, so the solver dominates.

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
is `Optimal(solution, stats) | Limited(reason, Option(solution), stats) |
Infeasible | Unbounded`. A solution is a usable assignment; only `Optimal`
claims a proof. `Limited` reports `TimeLimit` or `NodeLimit` and may carry an
incumbent; no incumbent does not mean infeasible. Unsatisfiable constant rows
and empty domains are infeasibility.
`SolveError` separates user-data problems (`InvalidDomain(key)`,
`NonFinite(location)`, `InvalidTimeLimit`, `InvalidNodeLimit`) from failures
the caller can't act on
(`SolverFailure(message)`, including internal bugs and caught panics). A
location is `InObjective` or `InConstraint(index, constraint)`. Evaluation has
its own error, `EvaluationError` (see "Solutions and evaluation"). Lowering a
model cannot fail; the first error found is reported.

**Why.** Infeasibility is a mathematical answer, not a failure. Tying the
assignment to its variant makes reading unavailable values impossible.
Either limit can expire with or without an incumbent: `Limited` factors these
four valid cases into reason and availability without four constructors.
Errors name what the caller wrote: a key, or the constraint
itself, following "A constraint is its own identity", with its position for
locating it in the list. One error type per operation lists only failures that
operation can produce. The names avoid shadowing `Result`'s `Error`.

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
- *A nested invalid-limit error type.* Two flat cases identify the invalid
  budget without another public type.
- *`Result` on every expression operation.* Would make model code unreadable.
- *Collecting all errors.* More machinery; revisit when diagnostics need it.
- *One error type for solving and evaluation.* Every caller would handle
  failures its operation can't produce.
- *Only the constraint's position.* Meaningless for constraints mapped from
  data; the caller would index back into their list.
- *A structured `SolverFailure` reason.* The caller can't act on any of them
  differently; stopped solves become outcomes (see "Solve limits").

### API criteria and representative models

**Decision.** Judge API changes by semantic clarity, composability, predictable
validation, and the cost of learning and maintaining the public interface.
Conveniences should express common modeling intent and have precise meanings
in terms of the core operations. Test correctness independently of examples,
including invalid inputs, numerical edge cases and deeply nested expressions.

Follow the standard library's conventions where an operation matches one, as
`value` follows `dict.get`: familiar shapes surprise less, and an
implementation that reduces to a standard function is a good sign, not a
shallow layer. A convenience function earns its place when it names a
recommended pattern for a common value source, is exactly equivalent to a core
call, and adds no policy: no defaults, validation or error translation. Such
functions make recommended patterns discoverable and cost little to maintain;
the criterion keeps them from becoming an unorganized heap.

The representative models in `test/examples/` check ergonomics: the README's
waffle stand, a multi-period production network, and N-queens. Grow the set when
a model with new structure tests the API differently. JuMP, Pyomo and MathOpt
are influences, not syntax to copy.

**Why.** Concrete models expose ergonomic costs but only reveal what they
exercise. They provide evidence for design decisions, not the sole acceptance
criterion. Their small size supports no performance claims; other libraries
rely on macros, operator overloading or mutation that Gleam lacks.

## Modeling API

### Expressions are an affine tree

**Decision.** An expression is a small affine tree: `Variable`, `Linear` and
`Constant` leaves, with `Sum`, `Difference` and `Scaled` combinators.
`Sum([])` is zero.
Duplicate keys and zero coefficients are allowed: Rust canonicalizes anyway.
There is no `multiply`, so every expression is affine by construction.

```gleam
pub type Expression(v) {
  Variable(variable: v)
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
  Sum(expressions: List(Expression(v)))
  Difference(lhs: Expression(v), rhs: Expression(v))
  Scaled(coefficient: Float, expression: Expression(v))
}

Sum([Linear(3.0, X), Linear(2.0, Y), Constant(7.0)])          // 3x + 2y + 7
list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) }) |> Sum  // Σ wᵢ pickᵢ
Difference(revenue, cost)                                    // revenue − cost
```

**Why.** Every operation takes and returns an expression, so reuse is ordinary
nesting: a named expression goes anywhere an expression does, without
flattening or copying. Weighted variables mapped over data become one `Sum`,
which ends a pipeline; unweighted sums use `list.map(keys, Variable) |> Sum`.
Sides with a single term need no wrapper (`LessEqual(x, Constant(4.0))`), which offsets
the `Sum` on sides with several. It is still plain Gleam data: immutable,
pattern-matchable, built with the standard library, and composed without float
arithmetic in Gleam.

**Naming.** In math an affine expression is a sum of linear terms and a constant
term, and JuMP (`terms`, `constant`), Pyomo and MathOpt (`terms`, `offset`)
split it the same way. `Linear` names a weighted variable by degree, so a
future quadratic term would be `Quadratic`, in its own type. `Variable` names
an unweighted reference; `Sum`, `Difference` and `Scaled` name operations.
`Linear` stays a leaf rather than `Scaled(c, Variable(key))`:
weighted variables are the dominant construction, and two constructors per term
would hurt readability. Coefficients come first, as in `3x`. Callers can rename
at the import (`import vahvel.{Linear as L, Constant as C}`), which the
`Expression` docs mention.

**Convenience forms.** `Variable(key)` lowers to `Linear(1.0, key)`;
`Difference(lhs, rhs)` lowers to `Sum([lhs, Scaled(-1.0, rhs)])`. These are
structural expansions, not arithmetic or simplification. Both sides are visited
left-to-right, even if they cancel or are scaled by zero; all numeric checks
remain in Rust. Solving and evaluation share this lowering. The constructors
are pattern-matchable like the rest of the API and add no native expression
variants. Unary negation remains `Scaled(-1.0, expression)`.

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
- *A separate negation constructor alongside `Difference`.* Subtraction states
  the two operands directly; standalone negation already uses `Scaled(-1.0, e)`.
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

**Why.** Compilation and solving never used keys; residuals need none
(`residual(constraint, lookup)`). Identity by value removes a type parameter, a field
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

### Domains

**Decision.**

```gleam
pub type Domain {
  Binary
  Real(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
  NonNegativeReal
  NonNegativeInteger
}
```

`None` means no bound; `Binary` lowers to `Integer(Some(0), Some(1))`.
Real and integer bounds behave the same for the user. microlp limits
integer variables to signed 32 bits, so a `None` integer bound means "no bound
beyond that range": Rust fills in `i32::MIN`/`i32::MAX`, microlp's documented
convention. A truly unbounded integer direction therefore reports `Optimal` at
±2³¹, which the `Domain` docs state and a driver test pins.

**Why.** Users shouldn't have to guess a "large enough" integer bound, and the
backend limit belongs in one place, in Rust.

**Naming and conveniences.** `Real` and `Integer` name the values a variable
may take; both accept optional inclusive bounds. The driver uses the same names.
`NonNegativeReal` means `Real(Some(0.0), None)`; `NonNegativeInteger` means
`Integer(Some(0), None)` and retains the backend's integer limit. Like `Binary`,
they state common modeling intent and lower to the existing bounded domains.
Their names explicitly distinguish real and integer values.

Pyomo's `NonNegativeReals` and `NonNegativeIntegers` inform this distinction;
JuMP's variable bounds and MathOpt's explicit bounds inform keeping arbitrary
bounds available. These conveniences share the general domains' validation.

**Rejected.**
- *Required integer bounds.* Honest about the backend, but asymmetric with
  real bounds.
- *A bare `Real` plus `BoundedReal`.* Splits one domain family and would require
  the same split for integers.
- *`NonNegative` without a numeric kind.* Does not say whether values are real
  or integer.
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

### Solutions and evaluation

**Decision.** `value(solution, key)` returns `Result(Float, Nil)` like
`dict.get`, never a substituted zero. `evaluate(expression, lookup)` computes
an expression at the values a `fn(v) -> Result(Float, Nil)` supplies, with the
same canonicalization as solving: costs and breakdowns at a solution,
or the cost of a hand-made plan or a what-if. `evaluate_solution(expression,
solution)` and `evaluate_dict(expression, values)` are exactly
`evaluate(expression, value(solution, _))` and
`evaluate(expression, dict.get(values, _))`. Evaluation fails with
`EvaluationError(v)`: `MissingValue(key)` for the first referenced key without
a value, in depth-first order, or `NonFiniteValue` for overflow. All values are
`Float`; integer and binary values are exact whole numbers (microlp rounds
them), so callers convert with `float.round`. The objective is microlp's own
value, not recomputed from the rounded values.

**Why.** Silent zeros hide typos. Evaluation needs a lookup, not a storage
representation: assignments may be partial, and a dictionary, a `case` over
the key type, or solution values with overrides all fit. Evaluation computes a
value; it needs neither a model nor domains, and doesn't make an assignment
feasible. A lookup has one failure, absence, and its caller knows the key, so
`Nil` is exact and `value` and `dict.get` are interchangeable as lookups. The
evaluator finds keys inside the expression, so its error names the missing
one; overflow is a failure only evaluation has. On the BEAM floats are always
finite, so `NonFiniteValue` means overflow and names no key. Missing values
are found before the native call, so they take precedence over overflow. The
two convenience functions meet "API criteria". Expression-first argument order
lets expressions pipe into evaluation and capture bind a value source once per
report. Exact integer values make `float.round` lossless rather than a
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
- *A dictionary-only evaluator.* Materializes a collection for values that
  already have a functional form.
- *A total `fn(v) -> Float` lookup.* Can't say a value is missing.
- *An `Option(Float)` lookup.* Needs adapters for `Result`-based lookups.
- *A lookup with its own error type* (`EvaluationError(v, e)`). Another type
  parameter for failures, like loading data, that belong before evaluation;
  mapping them to `MissingValue` would hide them instead.
- *`value_or` and `evaluate_or` with a default.* A default is a policy that
  makes substituted zeros look recommended and, for a whole expression, hides
  which key was missing.
- *Slack with a sign per relation.* Non-negative means satisfied for
  inequalities, but `Equal` has no slack, and sign conventions differ by source.
- *A satisfied-or-violated result.* Needs a tolerance.
- *`residual_solution` and `residual_dict`.* Not yet needed: `residual(c,
  value(solution, _))` stays short.
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
nodes))` takes optional `Duration` and `Int` budgets. Limits belong to a call,
not the mathematical model. Support microlp's time and node limits; it exposes
no simplex iteration limit. Nodes exclude the root relaxation and do not
bound continuous LP work. No resume, cancellation or gap-based stopping API.

Rust validates time, then nodes, then the model's numeric data. Out-of-range
budgets return flat `InvalidTimeLimit` / `InvalidNodeLimit` errors. Zero is
valid and still permits validation and trivial proofs. Node counts fit `u64`;
durations are at most 100 years. Gleam passes integer seconds/nanoseconds
without floating-point conversion.

The fixed cap keeps one deterministic, platform-independent check. microlp
adds the budget to the current `Instant` without checking, and the clock's
range varies by platform; checking that sum ourselves would duplicate it and
race the backend's own addition. No useful budget comes near the cap.

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

`Stats` reports branch-and-bound nodes, simplex iterations including the root
LP, solver time as `Duration`, and `gap: Option(Float)`. An optimum has zero
gap. Without an incumbent or a finite computable bound/gap, the gap is absent.
A rounded zero gap alone never upgrades `Limited` to `Optimal`.

Rust computes the gap from the full objective and bound, both shifted by the
objective constant: `abs(objective - bound) / max(abs(objective), 1.0)`.
This is a ratio, not a percentage. The denominator floor avoids huge ratios
near zero and deliberately differs from microlp's `1e-10` floor. Non-finite
optional diagnostics become `None`; non-finite primal values remain failures.

**Why.** Solve effort and proof quality describe a run, not an assignment.
Both primal availability states need the same statistics. Keeping them in the
outcome avoids asymmetric ownership or duplicate storage. The native solver
does not see Vahvel's objective constant, so copying its relative gap would
misreport shifted objectives. Computation stays in Rust.

**Rejected.**
- *An outer report with optional stats.* Adds a wrapper and makes stats
  optional even where the variants guarantee them.
- *Zero stats for infeasible/unbounded.* Would invent data about backend work.
- *`solve_with_stats`.* Both solve entry points already collect the same data.
- *A public best bound.* Not needed for the current interface.

### The API owns its types

**Decision.** `vahvel` is the one public modeling module. Users never import
`vahvel/internal/*`, and no public function takes or returns a driver type.
Tests check behavior through `solve`, not the lowered data. Split the module only
along real boundaries, never into forwarding modules.

**Why.** Internal modules must stay free to change.

**Rejected.** *Re-exporting driver types* and *a public `compile`.* Both leak
the internal contract.

## Native boundary

### The driver contract

**Decision.** Rust receives indices only: domains in column order, an objective
expression, and rows as `lhs relation rhs`. Expressions use `Linear`,
`Constant`, `Sum` and `Scaled`, with keys replaced by indices and the public
`Variable` and `Difference` conveniences expanded during lowering. Rows
correspond one-to-one to constraints, so every solver position maps back to a key or constraint. Keys and names never
cross the boundary. Numeric limits travel separately from the model; the
result carries optional primal data only for a budget stop. The contract
changes only deliberately, in Rust and Gleam together.

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
  so every `.erl` file is prefixed with `vahvel_`.

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

### Out of scope for now

Nonlinear expressions, automatic solver selection, persistent native models and
performance promises.

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
- [microlp 0.6.0 Solution](https://docs.rs/microlp/0.6.0/microlp/struct.Solution.html):
  no public dual accessor; time limits and resumable solves exist.
- [Gleam opaque types](https://tour.gleam.run/advanced-features/opaque-types/):
  hide representation behind a small typed API.
