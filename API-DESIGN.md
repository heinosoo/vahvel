# Waffle modeling API decisions

One entry per decision. [ARCHITECTURE.md](ARCHITECTURE.md) gives the overall
picture; this file is the record of what was decided, why, and what was rejected.

Status values:

- **Implemented**: decided and reflected in `src/waffle/internal/model.gleam`.
- **Accepted**: decided, not yet implemented.
- **Open**: under discussion; the leading candidate is listed first.

| # | Decision | Status |
| --- | --- | --- |
| [D1](#d1-describe-in-gleam-compute-in-rust) | Describe in Gleam, compute in Rust | Accepted |
| [D2](#d2-representative-models-drive-the-api) | Representative models drive the API | Implemented |
| [D3](#d3-affine-only-expressions) | Affine-only expressions | Implemented |
| [D4](#d4-eager-canonical-expression-representation) | Eager canonical expression representation | Partly implemented |
| [D5](#d5-expressions-are-lists-of-terms) | Expressions are lists of terms | Implemented |
| [D6](#d6-application-keys-as-references) | Application keys as references | Implemented |
| [D7](#d7-variables-declared-by-use-with-a-domain-function) | Variables declared by use, with a domain function | Implemented |
| [D8](#d8-keys-are-model-local-names) | Keys are model-local names | Implemented |
| [D9](#d9-constraints-have-no-keys-a-constraint-is-its-own-identity) | Constraints have no keys; a constraint is its own identity | Implemented |
| [D10](#d10-model-is-an-immutable-record) | Model is an immutable record | Implemented |
| [D11](#d11-objective-carries-its-direction) | Objective carries its direction | Implemented |
| [D12](#d12-constraint-construction) | Constraint construction | Implemented |
| [D13](#d13-errors-are-reported-at-compilation) | Errors are reported at compilation | Implemented |
| [D14](#d14-deterministic-column-and-row-order) | Deterministic column and row order | Implemented |
| [D15](#d15-canonical-compilation-rules) | Canonical compilation rules | Implemented |
| [D16](#d16-names-and-provenance-stay-in-gleam) | Names and provenance stay in Gleam | Implemented |
| [D17](#d17-numeric-validation-boundary) | Numeric validation boundary | Partly implemented |
| [D18](#d18-outcomes-are-separate-from-errors) | Outcomes are separate from errors | Implemented |
| [D19](#d19-solution-queries) | Solution queries | Partly implemented |
| [D20](#d20-no-dual-values-until-a-backend-provides-them) | No dual values until a backend provides them | Implemented |
| [D21](#d21-plain-gleam-collections-for-index-sets) | Plain Gleam collections for index sets | Implemented |
| [D22](#d22-the-api-owns-its-domain-types) | The API owns its domain types | Implemented |
| [D23](#d23-one-module-until-real-boundaries-appear) | One module until real boundaries appear | Implemented |
| [D24](#d24-solve-limits-are-deferred) | Solve limits are deferred | Accepted |
| [D25](#d25-out-of-scope) | Out of scope | Accepted |

## D1. Describe in Gleam, compute in Rust

**Decision.** The Gleam modeling layer is symbolic only: it assigns columns to
keys, evaluates domains, and lowers term lists to indexed but unsummed
expressions. It does no arithmetic on user floats. The Rust driver does all
numeric work: canonicalization (`lhs − rhs`, sorting, merging duplicates,
dropping zeros, summing constants), validation, solving, and evaluation. They
meet in one contract, the driver model, sent in a single NIF call. That contract
changes only deliberately, in Rust and Gleam together.

```
Gleam modeling layer: keys → columns, domain(key), term lists → indexed expressions
  │ one dirty-CPU NIF call
Rust: decode (Rustler adapter) → canonicalize → validate → solve → check results
  │ values in column order | positioned error
Gleam modeling layer: values → keyed Solution; positions → keys and locations
```

**Why.**
- Performance: summing and sorting in Rust is much faster than Gleam
  dictionaries.
- Portability: float behavior differs by target (the BEAM raises on overflow and
  can't hold infinity or NaN; JS silently produces both). With no float
  arithmetic in Gleam, the modeling layer behaves identically everywhere, and a
  future WASM build shares the same Rust numeric rules.
- One place for numeric rules, which also decides where future checks belong.

**What stays in Gleam.** Key discovery and column assignment, because `domain`
is a Gleam closure a NIF can't call (D7), and because keys are arbitrary Gleam
values while the Rust engine only sees indices. This costs one dictionary lookup
per term in Gleam; the construction benchmark (D4) should measure it.

**Adaptability.** Moving more work to Rust means changing the one contract.
Presolve, scaling, or building CSC for Clarabel stay inside Rust and are
invisible to Gleam. Persistent native models would need a resource handle
(D25). Moving key discovery would need a two-phase protocol or a different way
to supply domains (D7). A future WASM target would split the Rust code into a
target-independent engine plus thin adapters (Rustler, wasm-bindgen).

**Alternatives.**
- *Canonicalize and check in Gleam* (earlier code, and a discarded overflow
  check). Needs IEEE edge-case reasoning (a round-to-even tie at the largest
  float) and target-specific behavior in the modeling layer.
- *Map keys to indices in Rust as well.* Rust would hash Rustler terms (or JS
  values under WASM) and could not call the `domain` closure without a second
  call and native state.
- *Direct matrix/row generators as the user API.* Exposes column order,
  coefficient aggregation, and matrix dimensions to application code.
- *Build a sparse matrix (CSC/CSR) for every backend.* microlp takes rows one at
  a time; only a Clarabel adapter needs CSC.

## D2. Representative models drive the API

**Decision.** API shape is judged against executable models in
`test/model_test.gleam`:

| Model | Decisions and constraints | What it tests |
| --- | --- | --- |
| Production LP | Product quantities, resource capacity, profit | Scalar composition, bounds, objective offset, named results |
| Transportation LP | Shipments on allowed routes, supply and demand | Tuple/custom-type keys, sparse index sets, grouped sums, equality rows |
| Binary selection MILP | Choose items within a weight budget | Functional construction, binary domains, integrality |
| Degenerate/invalid models | Empty sums, cancelling terms, empty and invalid domains | Validation and explicit outcomes |

Tests also cover objective offsets, expressions on both sides of a constraint,
repeated and cancelling terms, empty models, infeasible and unbounded models, and
invalid domains through the real NIF. The transportation model is built from
allowed routes, not a dense Cartesian product followed by filtering. These small
examples support no performance claim.

**Why.** Concrete models expose ergonomic costs that abstract design hides, and
double as regression tests through the real NIF.

**Alternatives.** Design from other libraries' APIs (JuMP, Pyomo, MathOpt). Used
as influences only; their syntax relies on macros, operator overloading or
mutation that Gleam lacks.

## D3. Affine-only expressions

**Decision.** Expressions are affine. There is no `multiply` on expressions. A
future quadratic capability gets its own type, e.g. `multiply: Affine, Affine ->
Quadratic`, accepted only where a backend supports it (the objective).

**Why.** The earlier code exposed both forms, and the same production objective
compiled to identical IR either way:

```gleam
// affine operations
chair |> m.scale(3.0) |> m.add(m.scale(table, 2.0)) |> m.add(m.constant(7.0))
// general tree
m.sum([
  m.multiply(m.constant(3.0), chair),
  m.multiply(table, m.add(m.constant(1.0), m.constant(1.0))),
  m.constant(7.0),
])
```

The general tree is easy to represent; its cost is semantic ambiguity and late
rejection. `multiply` is only useful for constant × expression, which scaling
already covers. Errors arrive at compilation without context, and the acceptance
rule (a product is accepted when one lowered side has no nonzero variable
coefficients, checked inside-out, with no polynomial simplification) surprises:
`0 * (x * x)` is rejected while `(x - x) * x` is accepted. Separate types give a
compile-time guarantee. Quadratic or conic IR is likewise an explicit future
capability, not squeezed into the linear row format.

**Alternatives.**
- *General symbolic AST with compile-time rejection* (earlier code). Flexible
  syntax, weak guarantees, contextless `NonlinearExpression` errors.
- *JuMP-style promotion* to a richer expression type at runtime. Natural with
  multiple dispatch; in Gleam the equivalent is distinct types, which is this
  decision.

## D4. Eager canonical expression representation

**Decision.** No expression tree. Expressions are flat term lists (D5). Gleam
lowers them to indexed term lists in one pass; Rust canonicalizes them once by
sorting and merging (D1). Cost is linear in the number of terms in Gleam plus a
sort in Rust, and nothing recurses.

**Why.** Predictable cost, no recursion at compile time, and no re-lowering of
nested structure for each use. The tree's only benefit, structure for diagnostics
or printing, is unused.

**Alternatives.**
- *Affine AST lowered at compilation* (earlier code). Preserves structure, but
  shared subexpressions are re-lowered per use, and `add` chains need care to
  avoid quadratic merging. Deep or shared trees were never benchmarked.

## D5. Expressions are lists of terms

**Status.** Accepted.

**Decision.** An expression is a plain `List(Term(v))`; the empty list is zero.
A term is either a coefficient times a variable key or a constant. Duplicate
keys and zero coefficients are allowed, because compilation canonicalizes
anyway (D15).

```gleam
pub type Term(v) {
  Linear(coefficient: Float, variable: v)
  Constant(value: Float)
}

let x = Linear(1.0, X)
let y = Linear(1.0, Y)
[x, y]                                  // x + y
[Linear(3.0, X), Linear(2.0, Y), Constant(7.0)]   // 3x + 2y + 7
list.map(items, fn(i) { Linear(i.weight, Pick(i.id)) })  // Σ wᵢ pickᵢ
list.append(e1, e2)                     // e1 + e2
list.flatten([e1, e2, [Constant(-1.0)]]) // e1 + e2 - 1
```

**Why.** It's Gleam data: immutable, pattern-matchable, built with `list.map`,
combined with `list.append`/`list.flatten`, filtered with `list.filter`. Every
model written so far is "coefficient × key, mapped over data", which is data
rather than algebra. The current operations (`constant`, `variable`, `add`,
`sum`, `scale`) imitated an operator-overloaded algebra that Gleam cannot express
concisely.

**Sums.** A list of *terms* is their sum, so `[x, y]` is `x + y`. Expressions are
lists themselves, so the sum of two *expressions* is `list.append(e1, e2)`, not
`[e1, e2]`, which would be a list of lists. No `sum` helper is needed.

**Helpers.** None are needed to build expressions. The one operation the
standard library can't express in a single call is scaling a reused expression,
e.g. negating `cost` in `revenue - cost`, since a `list.map` has to handle both
variants. Add `m.scale(expression, factor)` when a representative model needs
it. No `simplify` or rebalancing step either: compilation canonicalizes in
linear time. Canonicalizing early would only pay off for a large expression full
of duplicates that is reused in many rows; revisit if a benchmark shows that.

**What types rule out.** Nonlinear terms (D3) and references to anything other
than a variable key. Non-finite coefficients need no type: BEAM floats are
always finite, and overflow while combining terms is a compile error (D17).

**Naming.** In math, an affine expression is a sum of *linear terms*
(coefficient × variable) and a *constant term*. Libraries split it the same way:
JuMP's `AffExpr` has `terms` and `constant`, Pyomo's `LinearExpression` has
`constant`, `linear_coefs` and `linear_vars`, and MathOpt's `LinearExpression`
has `terms` and `offset`. `Term` is the type, and constructors are named by
degree: `Linear` and `Constant`. A future degree-two term would be `Quadratic`,
in a separate type (D3).

Verbosity is acceptable because most terms are built from data in a `list.map`,
not written as literals, and callers who want brevity can rename constructors
at the import, which works for both construction and pattern matching:

```gleam
import waffle/model.{Linear as L, Constant as C}
[L(3.0, X), L(2.0, Y), C(7.0)]
```

The `Term` doc comment should mention this. Alternatives:
- `Term`/`Constant`: the constructor shadows the type name, and a constant is a
  term too.
- `Var`/`Const` or `Lin`/`Const`: short, but abbreviations go against Gleam's
  full-word convention (`Some`, `None`, `Ok`, `Error`), `Var` is not a variable,
  and `Lin` isn't a word anyone says.
- `Times(3.0, X)`/`Plus(7.0)`: reads aloud well, `Plus(-1.0)` less so.

**Order.** Coefficient first, as in math notation (`3x`) and JuMP's
`add_to_expression!(expr, coef, var)`. Sparse solver interfaces put the index
first (microlp's `(var, coef)` pairs, the driver's `#(index, coef)`); that stays
internal.

**Option B: a record with terms and a constant.**
`Linear(terms: List(#(Float, v)), constant: Float)`. One canonical place for the
constant, but combining needs a helper (append terms *and* add constants), so
the standard library no longer covers composition.

**Option C: opaque canonical expression with smart constructors.**
`m.linear([m.term(3.0, Chair)], constant: 7.0)` returning an opaque type that
holds merged coefficients. Can enforce canonical form and finiteness at
construction, but brings back constructor noise and needs `add`/`scale`/`sum`
again; it is the current API with a different representation.

**Option D: keep the current algebra.** Familiar from JuMP/Pyomo, noisy in Gleam
because every literal and reference needs a constructor.

**Rejected: `Dict(v, Float)` as the expression.** `dict.from_list` silently
replaces duplicate keys, so `[#(x, 1.0), #(x, 2.0)]` would mean `2x`, not `3x`.

**Rejected for now: `m.term(key)` for a coefficient of one.** `Linear(1.0, X)`
is short enough.

## D6. Application keys as references

**Decision.** Variables are referenced by application-owned keys of a generic
type, e.g. `Ship(Factory, Customer)`, never by solver column numbers.

**Why.** Domain keys are self-describing, work with exhaustive pattern matching,
and need no mutable allocation. With custom-type keys, typos do not compile.

**Alternatives.**
- *Handles allocated by a state-threading builder* (`use x <- m.new_variable(d)`).
  Valid by construction, but Gleam has no mutation, so state must be threaded,
  and indexed families come back as `Dict(key, Expression)` lookups returning
  `Result`, so keys return anyway.
- *String names.* Untyped; typos become runtime errors.

## D7. Variables declared by use, with a domain function

**Decision.** A variable exists when an expression references it. The model
supplies `domain: fn(v) -> Domain`, typically an exhaustive `case` over the key
type. Columns are assigned in order of first appearance.

**Why.** Removes `UnknownVariable`, `DuplicateVariable`, and listing indexed
families twice (once to declare, once to reference). Type inference fills in the
key type from the domain function.

**Costs.** A variable never referenced does not exist; querying it reports an
unknown key. A model holding a closure cannot be compared with `should.equal` or
printed. Because a NIF can't call the closure, key discovery and column
assignment stay in Gleam (D1); moving them to Rust later would need a two-phase
protocol or another way to supply domains.

**Alternatives.**
- *Explicit declaration list* (earlier code). Inspectable and comparable, but
  duplicates the index set and needs unknown/duplicate checks.
- *Allocated handles* (see D6).

## D8. Keys are model-local names

**Decision.** A key names a variable or constraint within the model being
compiled. The same key can be reused across models or scenarios; using an
expression against a different model is not detected.

**Why.** Avoids global identity and mutable allocation. Gleam phantom types alone
cannot give fresh per-model identities.

**Alternatives.** Opaque runtime-identified handles that detect cross-model use.
Revisit before stabilizing, using models assembled from independent components.

## D9. Constraints have no keys; a constraint is its own identity

**Decision.** Constraints carry no explicit key, and `Model(v)` has a single
type parameter for variable keys. Where a constraint must be identified (future
duals, D20), the constraint value itself is the key: constraints are immutable
values with structural equality, and any BEAM term can key a dictionary.

```gleam
let capacity = fn(m: Machine) { LessEqual(hours_used(m), [Constant(m.hours)]) }
// constraints: list.map(machines, capacity)
m.dual(solution, capacity(m2))  // future: the builder function is the lookup
```

**Why.** In the earlier code keys only fed the duplicate check and the `dual`
stub (removed by D20); compilation and solving never used them. Slack needs no
key either: `evaluate(solution, lhs)` (D19). Identity by value removes the second
type parameter, a field on every constraint, and the parallel-list zipping that
positional results would need.

**Costs.**
- Structurally equal constraints are the same key. They are also mathematically
  redundant, so once duals exist compilation merges them into one row and both
  return the same dual (D16).
- Equal math is not equal values: `[x, y]` and `[y, x]` are separate rows with
  separate duals. Lookups work because callers rebuild the value the same way.
- A lookup hashes the whole row, linear in its length. The value-to-row map is
  built once per solution, only when needed.
- Error messages cannot print a short name; they report the list position and
  an abbreviated constraint (D17).
- Values are not stable across scenarios: changing `m2.hours` yields a different
  constraint, so an old value does not find a row in a new solution.

**Alternatives.**
- *Separate constraint key type* (`Model(v, c)`, earlier code). Readable names,
  stable across scenarios, but ceremony on every row for a feature that does
  not exist yet.
- *Optional `Named(key, constraint)` wrapper.* Mixed named/unnamed lists and the
  second type parameter remains.
- *Positional identity only* (results in input order). Always available
  internally (D14), but users zip results against their own lists.
- *Opaque constraints.* Opaqueness gives no identity: equal contents still
  compare equal, and fresh handles need threaded state or impure refs (D6).

## D10. Model is an immutable record

**Decision.** A model is a plain immutable record of fields (domain, objective,
constraints), built with ordinary Gleam values and updated with `..model`.

**Why.** No hidden state, easy to build with `list.map`/`list.flatten`, easy to
derive scenarios.

**Alternatives.** A builder pipeline (`m.new() |> m.subject_to(...)`). Reads well
but adds API surface without new capability.

## D11. Objective carries its direction

**Decision.** The objective is `Minimize(expression)` or `Maximize(expression)`,
replacing separate `direction` and `objective` fields.

**Why.** One concept in one value; changing one without the other is impossible.

**Alternatives.** Separate fields (earlier code).

## D12. Constraint construction

**Decision.** A constraint relates two expressions, one variant per relation,
with no key (D9):

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
D5, invalid relations are unrepresentable, and each constraint compiles to
exactly one driver row. `GreaterEqual` is redundant with a swapped `LessEqual`
but kept for readability. It replaces the positional
`Constraint(key, lhs, relation, rhs)`, which was noisy and exposed the driver's
`Relation`.

**Costs.** A ranged row is two constraints, so it has two identities and,
later, two duals.

### Alternatives considered

A bare `Float` right-hand side was rejected as the main form. The options were
compared while constraints still had keys; with D9 the keys simply disappear.
They use D5's term lists, with `x = Linear(1.0, X)` and `y = Linear(1.0, Y)`.

**Criteria.**
- Common case (expression against a constant) reads like the math.
- `x ≤ y` is expressible without rearranging by hand.
- Invalid or redundant states are unrepresentable.
- One constraint key maps to one driver row, so future duals stay one value per
  key (D16, D20). The driver has no ranged rows, and neither does microlp.
- It also works for variable domains, or at least doesn't conflict with them.

Each option writes the same three rows:

1. `x + y ≤ 4`
2. `x ≤ y`
3. `2 ≤ x + y ≤ 5`

**Option A: relation variants between two expressions.**

```gleam
pub type Constraint(v, c) {
  LessEqual(key: c, lhs: List(Term(v)), rhs: List(Term(v)))
  Equal(key: c, lhs: List(Term(v)), rhs: List(Term(v)))
  GreaterEqual(key: c, lhs: List(Term(v)), rhs: List(Term(v)))
}

LessEqual("r1", [x, y], [Constant(4.0)])
LessEqual("r2", [x], [y])
GreaterEqual("r3_lo", [x, y], [Constant(2.0)])
LessEqual("r3_hi", [x, y], [Constant(5.0)])
```

Reads in math order, `x ≤ y` is direct, and maps one-to-one to driver rows.
`GreaterEqual` is redundant with swapped `LessEqual`, kept for readability.
A ranged row needs two constraints with two keys.

**Option B: an expression within an interval of numbers.**

```gleam
pub type Interval { AtMost(Float) AtLeast(Float) Exactly(Float) Between(Float, Float) }

Constraint("r1", [x, y], AtMost(4.0))
Constraint("r2", [x, Linear(-1.0, Y)], AtMost(0.0))
Constraint("r3", [x, y], Between(2.0, 5.0))
```

Canonical LP form `l ≤ a·x ≤ u`; continuous variable domains can reuse
`Interval`. `x ≤ y` must be rearranged by hand. Constants in the expression (D5)
move into the interval at compilation, so the constant has two places to live.
`Between(a, a)` duplicates `Exactly(a)`; `Between` needs two driver rows under
one key.

**Option C: an interval whose bounds are expressions.**

```gleam
pub type Bound(v) { AtMost(List(Term(v))) AtLeast(List(Term(v))) Exactly(List(Term(v))) }

Constraint("r1", [x, y], AtMost([Constant(4.0)]))
Constraint("r2", [x], AtMost([y]))
Constraint("r3_lo", [x, y], AtLeast([Constant(2.0)]))
Constraint("r3_hi", [x, y], AtMost([Constant(5.0)]))
```

Merges A and B: one constraint type, `x ≤ y` is direct, and constants come from
D5. Costs are the same as A's, plus one nesting level. A `Between` variant is
left out on purpose so that one key stays one row.

**Option D: rows and their bounds as separate, key-driven parts.**

```gleam
type Row { R1 R2 R3 }

m.Model(
  rows: [#(R1, [x, y]), #(R2, [x, Linear(-1.0, Y)]), #(R3, [x, y])],
  bound: fn(row) {
    case row {
      R1 -> AtMost(4.0)
      R2 -> AtMost(0.0)
      R3 -> Between(2.0, 5.0)
    }
  },
  ..
)
```

Mirrors D7's domain function: an exhaustive `case` guarantees every kind of row
has a bound, and indexed keys can carry their data (`Capacity(machine)` →
`AtMost(machine.hours)`). It splits each constraint across two places, reads
worse for one-off rows, and still needs B's or C's bound type.

**Option E: comparison against zero.**

```gleam
Constraint("r1", [x, y, Constant(-4.0)], NonPositive)
Constraint("r2", [x, Linear(-1.0, Y)], NonPositive)
Constraint("r3_lo", [x, y, Constant(-2.0)], NonNegative)
Constraint("r3_hi", [x, y, Constant(-5.0)], NonPositive)
```

The solver's normal form. Minimal and unambiguous, but every row is rearranged
by hand.

**Option F: smart constructors over an opaque constraint.**

```gleam
m.at_most("r1", [x, y], [Constant(4.0)])
m.at_most("r2", [x], [y])
```

Can validate at construction and hide representation, but it's A behind
functions, less inspectable, and not pattern-matchable.

**Outcome.** A was chosen. Written with plain examples, C reads the same as A
plus a nesting level. B's single ranged row didn't outweigh rearranging `x ≤ y`
and giving the constant two homes. D is worth revisiting for large indexed
families.

## D13. Errors are reported at compilation

**Decision.** Expression operations are pure and infallible. Compilation
resolves and validates the model and returns typed errors through `Result`. The
first error found is reported.

**Why.** A `Result` on every addition would make model code unreadable.

**Alternatives.** Collect all errors. Better diagnostics, more machinery;
revisit with D17's contextual errors.

## D14. Deterministic column and row order

**Decision.** Columns follow the order in which variables are first referenced,
objective first, then constraints in list order (D7); rows follow constraint
list order. Dictionary iteration never decides order.

**Why.** Reproducible IR, solver behavior, and test expectations.

**Alternatives.** None seriously considered; `Dict` order is unspecified.

## D15. Canonical compilation rules

**Decision.** Compilation combines repeated coefficients, drops exact zeros,
sorts sparse indices, lowers `lhs relation rhs` as `lhs - rhs` with the constant
moved to the right-hand side, and keeps the objective constant as a separate
offset. Small nonzero coefficients are never dropped by an epsilon. References
inside zero-scaled or cancelling expressions are still validated.

**Why.** The driver requires canonical rows; an epsilon would silently change the
model; validating cancelled references keeps typos from vanishing.

**Alternatives.** Epsilon cleanup of near-zero coefficients. Rejected as silent
model mutation.

## D16. Names and provenance stay in Gleam

**Decision.** Variable keys, the key-to-column map, and the constraint-to-row
map stay on the Gleam side and are never solver inputs. Rows follow constraint
order (D14), so solver row *i* always maps back to an input constraint. Any row
transformation (merging identical constraints, splitting, scaling) keeps a
reverse map for dual recovery. The Rust driver drops empty rows before calling
microlp, so a dual-capable driver also needs its own row map.

**Why.** The NIF stays numeric and small; queries by key or constraint value
need no native support. Keys are arbitrary Gleam values, while the Rust engine
stays target-independent by seeing only indices (D1).

**Alternatives.** Passing names to the native layer. No benefit for microlp, and
it would tie the Rust engine to BEAM terms.

## D17. Numeric validation boundary

**Decision.**
- Rust is the single place for numeric checks (D1): bounds, integer range,
  indices, finiteness of inputs and of canonicalized sums, and finite results.
  No clamping or integrality relaxation.
- The NIF reports *where* a model is invalid: `InvalidModel` carries
  `MalformedModel`, `InvalidObjective`, `InvalidDomain(variable)` or
  `InvalidRow(row)`. Rust decodes each domain and row separately so even decode
  failures (integer bounds outside 32 bits) have a position. The modeling layer
  maps positions back to variable keys or constraint positions.
- Non-finite numbers, whether a sum overflowed while canonicalizing or (under a
  future JS/WASM target) an input was already infinite or NaN, are user-data
  errors distinct from invalid IR: the driver reports `NonFiniteObjective` or
  `NonFiniteRow(row)`, and the modeling layer returns
  `NonFinite(InObjective | InConstraint(index))`. Rust summing in `f64`
  produces infinity instead of raising, so the finiteness check catches
  overflow without special arithmetic.
- An empty domain (`lower > upper`, continuous or integer) is an `Infeasible`
  outcome, not an invalid model, consistent with unsatisfiable constant rows
  (D18). Integer bounds outside 32 bits remain invalid: that is a backend
  limit, not math.

**Why.** On the BEAM, floats are always finite (infinity and NaN can't be
parsed, decoded, or produced) and overflow raises `badarith`. On JS, overflow
silently produces infinity and NaN is possible. Doing no float arithmetic in
Gleam (D1) removes the crash on the BEAM and the target difference, and
Rust's finiteness checks become meaningful rather than defensive. The invalid
inputs a user can produce are bad domains and non-finite numbers; everything
else would be a waffle bug. Positions from Rust keep each rule in one place
while still naming the offending key.

**Alternatives.**
- *Validate domains again in Gleam* (`InvalidDomain(key)` without Rust changes).
  Rejected: bound rules would live in two places.
- *Make invalid domains unrepresentable* via D22's own domain type. Covers
  `Binary` and `NonNegative`, but a general `Between(lower, upper)` and the
  integer range still need checking.
- *Check overflow in Gleam before each addition.* Implemented and discarded:
  correct on both targets, but required reasoning about a round-to-even tie at
  the largest float inside the modeling layer.
- *Per-target FFI* (catch `badarith` on the BEAM, `isFinite` on JS). Two
  implementations of one rule, and Gleam still does the arithmetic.
- *Treat `lower > upper` as invalid* (current Rust behavior). Data-driven models
  can legitimately produce empty ranges; that's infeasibility.

## D18. Outcomes are separate from errors

**Decision.** `solve` returns `Result(Outcome, Error)`. `Outcome` is
`Optimal(solution) | Infeasible | Unbounded`; only `Optimal` carries a solution.
No unreachable variants are added to resemble other APIs.

**Why.** Infeasibility is a mathematical answer, not a failure. That includes
unsatisfiable constant rows and empty variable domains (D17). Tying the solution
to the variant makes it impossible to read values from a non-optimal result.

**Alternatives.** A status enum plus nullable values (MathOpt/JuMP style).
Needs separate availability checks; Gleam variants encode that directly. When
limits arrive (D24), add `Feasible(solution, gap)` and `Stopped(reason)`.

## D19. Solution queries

**Decision.** Values are queried by the same application key and return
`Result`, never a substituted zero. Solutions are immutable snapshots.
Accepted additions: `values(solution) -> Dict(v, Float)` and
`evaluate(solution, expression)` for computing costs, slacks and breakdowns.
`evaluate` multiplies coefficients by values, which can overflow, so per D1 the
arithmetic happens in Rust: Gleam maps keys to values, and a small NIF computes
the sum and reports non-finite results.

**Why.** Silent zeros hide typos. Evaluating expressions is more useful than
single-key lookups for reporting.

**Alternatives.** `value -> Float` with a default. Rejected for the same reason.

## D20. No dual values until a backend provides them

**Decision.** Remove the `dual` stub. microlp 0.6.0 has no public dual accessor,
and a function that always returns an error is an unreachable capability.

**Why.** Consistent with D18: no API surface for unavailable features.

**Identity when duals arrive.** Duals are queried by constraint value (D9):
`dual(solution, constraint)`, with identical constraints merged into one row.

**Requirements before shipping duals.** Define whether values are Lagrange
multipliers or RHS sensitivities; signs per relation and objective direction;
bound duals and reduced costs; transformations back to original rows; typed
availability independent of primal availability. MILP incumbents carry no LP
shadow prices; relaxations or fixed-integer resolves are separate, explicit
models. Verify with analytic LPs, KKT conditions, and RHS perturbation. An
explicit unavailable result is always preferable to zero, NaN, or invented
prices. Building an explicit dual model and solving it with microlp is possible
but needs its own transformation and validation tests.

**Alternatives.** Keep the stub returning `DualsUnsupported` (earlier code).

## D21. Plain Gleam collections for index sets

**Decision.** Index sets are ordinary `List`, `Dict`, tuples and custom types.
No index-set DSL, broadcasting, magic attribute lookup, or implicit zip
truncation. Network sums use `list.group` or precomputed adjacency instead of
filtering every route per node. A future indexed helper rejects duplicate keys;
a dot-product helper rejects unequal lengths; keyed coefficient records are
preferred over parallel lists.

**Why.** Gleam's standard library already covers sparse, filtered and grouped
index sets (the role Pyomo's `Set` plays).

**Alternatives.** A Pyomo/JuMP-style indexed container API. More surface, little
gain over `list.map`.

## D22. The API owns its domain types

**Decision.** Users never import `waffle/internal/driver`. The modeling API
defines its own domain, objective and error types and maps them to the driver.
The domain is

```gleam
pub type Domain {
  Continuous(lower: Option(Float), upper: Option(Float))
  Integer(lower: Option(Int), upper: Option(Int))
}
```

with `None` meaning no bound and binary written as `Integer(Some(0), Some(1))`.
Continuous and integer bounds work the same way for the user. microlp limits
integer variables to the signed 32-bit range, so a `None` integer bound means
"no bound beyond that range": Rust fills in `i32::MIN`/`i32::MAX`, microlp's
documented convention, keeping the backend limit in one place. A truly
unbounded integer direction therefore reports `Optimal` at ±2³¹ instead of
`Unbounded`; the `Domain` docs say so, and a driver test pins the behavior until
a backend supports unbounded integers. Driver
errors are mapped too: an invalid domain position becomes `InvalidDomain(key)`,
and any other `InvalidModel` reason means compilation produced invalid IR, so it
surfaces as `SolverFailure`.

**Why.** Internal modules must stay free to change.

**Alternatives.**
- *Re-export driver types* (earlier code used them directly).
- *Mirror the driver's `Bound` type* (`Unbounded | Finite(Float)`). Its
  `Unbounded` constructor clashes with `Outcome`'s `Unbounded`; `Option` is the
  standard library's way to say "maybe absent".
- *Required integer bounds* (`Integer(lower: Int, upper: Int)`). Honest about
  the backend, but continuous and integer bounds would behave differently, and
  users would have to guess a "large enough" bound and notice when it is hit.
- *Fill in `None` integer bounds in Gleam.* Puts a backend limit in the
  modeling layer.
- *Treat an integer value at the range edge as `Unbounded`.* Wrong when a
  variable with zero cost is merely parked at its bound among several optima.
- *A `Binary` variant.* Readable, but a second spelling of
  `Integer(Some(0), Some(1))`.
- *Typed shorthands* (`NonNegative`, `Free`). Same redundancy; add only if
  representative models show the general form is too noisy.

## D23. One module until real boundaries appear

**Decision.** Keep the modeling layer in one module. Split later along real
boundaries (expressions, model compilation, solution queries), never into
forwarding modules that mirror another library's namespace.

**Why.** Responsibilities are still small; premature splitting adds pass-through
layers.

## D24. Solve limits are deferred

**Decision.** No time or iteration limits yet. When added, the outcome separates
why solving stopped from what data is available: optimal, feasible but unproven,
and stopped without a primal value. A time limit is not infeasibility, and a
feasible incumbent is not optimal. Today the driver treats any unexpected
non-optimal native return as a solver failure. The driver contract and its
Rust encoding change together. microlp 0.6.0 already supports `set_time_limit`,
`solve_with`, `TerminationReason`, `InterruptedSolve` and `resume`.

**Why.** Limits change the outcome type; designing them before the model API
settles would churn both.

## D25. Out of scope

**Decision.** Not part of the current work: nonlinear expressions, QP, automatic
solver selection, persistent native model resources, solver replacement, and
performance promises.

**Why.** Each is a separate roadmap item; see [ROADMAP.md](ROADMAP.md).

## Research

Reviewed 2026-10-23. These are design influences, not interfaces to copy.

- [JuMP expressions](https://jump.dev/JuMP.jl/stable/manual/expressions/): specialized
  affine/quadratic expression representations motivate capability-specific types.
  JuMP also has a general `NonlinearExpr` tree and promotes products to a richer
  expression type rather than rejecting them, a counterpoint to compile-time
  rejection (D3).
- [Pyomo sets](https://pyomo.readthedocs.io/en/stable/explanation/modeling/math_programming/sets.html):
  indexed and sparse sets motivate domain-driven collections; Gleam already has
  the functional primitives needed (D21).
- [MathOpt](https://developers.google.com/optimization/math_opt): separates modeling
  from solving and supports solver-independent models.
- [MathOpt result contract](https://developers.google.com/optimization/service/reference/rest/v1/mathopt/solveMathOptModel):
  termination, primal results, and dual results are distinct concepts (D18).
- [JuMP solutions](https://jump.dev/JuMP.jl/stable/manual/solutions/): availability
  must be checked independently of termination, and certificates differ from values.
- [microlp 0.6.0 Solution](https://docs.rs/microlp/0.6.0/microlp/struct.Solution.html):
  current backend capabilities and absence of a public dual accessor; time limits
  and interrupted/resumable solves are already supported by the crate (D20, D24).
- [Gleam opaque types](https://tour.gleam.run/advanced-features/opaque-types/):
  hide representation while preserving a small typed API.
