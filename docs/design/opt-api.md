# waffle/opt API Design

This document captures the design rationale for the `waffle/opt` module API, including cross-library research, key decisions, and tradeoffs.

---

## Design Goals

1. **Type safety** — Invalid states should be impossible or caught early
2. **Ergonomics** — Common operations should be concise and readable
3. **Idiomatic Gleam** — Follow language conventions (opaque types, Result-based errors)
4. **Debuggability** — Error messages should point to the problem, not just "invalid ID"

---

## Cross-Library Comparison

We surveyed established optimization libraries to understand common patterns:

| Library | Language | Variable Reference | Named? | Type Safe? | Notes |
|---------|----------|-------------------|--------|------------|-------|
| **JuMP** | Julia | `VariableRef` type | Yes (symbol registration) | High | Gold standard for ergonomics; macro-based containers |
| **good_lp** | Rust | `Variable` struct (Copy) | Optional | High | Lightweight; variables are Copy for easy passing |
| **PuLP** | Python | `LpVariable` object | Required | Low | Dynamic typing; `.dicts()` for batch creation |
| **CVXPY** | Python | `Variable` object | Optional | Medium | Shape-based (vectors, matrices); disciplined convex programming |
| **Haskell MIP** | Haskell | `Var` type | Required | High | Pure functional; `Var` wraps `Text` name |

### Key Observation

**Every established library wraps variable references in a distinct type.** None expose bare integer IDs to users. This is true across paradigms: imperative (Python), functional (Haskell), and mixed (Julia, Rust).

The reasons are consistent:

1. **Type safety** — Cannot accidentally use an integer from another context
2. **Self-documentation** — `x: VarId` is clearer than `x: Int`
3. **Extensibility** — Can add metadata (names, bounds) without breaking changes
4. **Error messages** — Can report "variable 'production_qty' not found" vs "invalid ID 5"

---

## Design Decisions

### 1. Opaque VarId with Name

**Decision:** `VarId` is an opaque type containing both a name and an internal ID.

```gleam
pub opaque type VarId {
  VarId(name: String, id: Int)
}
```

**Why this design:**

| Aspect | Rationale |
|--------|-----------|
| **Opaque** | Users cannot construct VarId directly; must use `int_var`, `cont_var`, or batch functions |
| **Name included** | Single source of truth; error messages can use the name without Model lookup |
| **ID included** | Internal indexing; efficient constraint matrix construction |

**Alternatives considered:**

- **VarId(Int) + names in Model**: Would require dual storage and Model access for error messages. More complex, no clear benefit.
- **String-only references**: Loses type safety entirely. Typos caught at runtime only.

### 2. No ConstraintId Type

**Decision:** Constraints do not have a dedicated reference type.

**Rationale:**

1. The current API never exposes constraint IDs to users
2. Less universal across surveyed libraries — good_lp and CVXPY don't have them
3. Adding `ConstraintId` would increase API surface without clear use case
4. Can be added later if needed (e.g., for constraint removal, dual value access by constraint)

### 3. Separate Functions for Integer and Continuous Variables

**Decision:** `int_var` and `cont_var` instead of a single `add_variable` with a type parameter.

```gleam
pub fn int_var(model, name, coeff, lower, upper) -> #(Model, VarId)
pub fn cont_var(model, name, coeff, lower, upper) -> #(Model, VarId)
```

**Why:**

1. **Common case optimization** — Most models use either all-integer or all-continuous; specifying type every time is noisy
2. **Self-documenting** — `int_var("x", ...)` immediately signals the variable type
3. **Matches PuLP pattern** — `LpInteger` and `LpContinuous` are separate constructors
4. **Name required** — Eliminates the "anonymous variable" edge case; every variable is self-documenting

### 4. Batch Helpers with Auto-Generated Names

**Decision:** Provide `int_vars`, `cont_vars`, and `int_vars_with_bounds` for batch creation.

```gleam
let #(model, vars) = opt.int_vars(model, 5, "button", 1.0, 0.0, 10.0)
// vars = [VarId("button_0", 0), VarId("button_1", 1), ...]
```

**Why:**

1. **Real-world need** — The AOC problem that motivated this redesign had 6 similar variables with different bounds
2. **Inspired by PuLP** — `LpVariable.dicts("x", range(5), ...)` returns `{0: x_0, 1: x_1, ...}`
3. **Inspired by JuMP** — `@variable(model, x[1:5])` creates indexed containers
4. **Reduces boilerplate** — No manual fold/recurse to build variable lists

### 5. Convenience Constraint Functions

**Decision:** Add `add_eq_constraint`, `add_le_constraint`, `add_ge_constraint`.

```gleam
pub fn add_eq_constraint(model, value, coefficients) -> Result(Model, OptError)
pub fn add_le_constraint(model, upper, coefficients) -> Result(Model, OptError)
pub fn add_ge_constraint(model, lower, coefficients) -> Result(Model, OptError)
```

**Why:**

1. **Equality is common** — Most constraints in the AOC problem were equalities
2. **Less repetition** — `add_constraint(model, 5.0, 5.0, ...)` is verbose for the common case
3. **Standard pattern** — All surveyed libraries have similar conveniences
4. **Clear semantics** — Function name encodes constraint type; no need to remember bound conventions

---

## What We Deferred

### Builder Pattern (Chaining)

A fluent API would allow:

```gleam
let #(model, vars) = opt.new()
  |> opt.with_int_var("x", 1.0, 0.0, 10.0)
  |> opt.with_int_var("y", 1.0, 0.0, 5.0)
  |> opt.with_eq_constraint([#("x", 1.0), #("y", 1.0)], 5.0)
  |> opt.build()
```

**Deferred because:**

1. Requires internal name-to-VarId resolution
2. The core API already works well; builder would be a convenience layer
3. Can be added later without breaking changes

### Named Constraints

Some libraries (PuLP, JuMP) allow naming constraints for later reference or inspection. We chose not to add this because:

1. Current API doesn't expose constraint references
2. No clear use case yet
3. Can be added if needed

### Batch Constraint Addition

A function to add multiple constraints in matrix form (Ax = b):

```gleam
pub fn add_eq_constraints(model, A: List(List(#(VarId, Float))), b: List(Float))
```

**Deferred because:**

1. Error handling is complex (A/b length mismatch, invalid VarIds mid-way)
2. Users can write their own helper with `list.fold`
3. Would need design discussion on atomicity semantics

---

## Error Handling

All validation happens in Gleam before calling the NIF:

| Check | Error Type | Message Example |
|-------|------------|-----------------|
| Invalid VarId | `InvalidInput` | `"Invalid variable 'x' (id=99, model has 5 variables)"` |
| No variables | `InvalidInput` | `"No variables in model"` |
| Solver failure | `SolverError` | HiGHS internal error message |

Error messages include variable names, making debugging significantly easier than bare integer IDs.

---

## Summary

| Decision | Rationale |
|----------|-----------|
| Opaque `VarId(name, id)` | Type safety + debuggability; matches all surveyed libraries |
| No `ConstraintId` | Not needed by current API; can add later |
| `int_var`/`cont_var` separation | Common case optimization; self-documenting |
| Batch helpers | Reduces boilerplate; matches PuLP/JuMP patterns |
| Convenience constraints | `add_eq_constraint` etc. reduce verbosity for common cases |
| Required names | Every variable is self-documenting |

The resulting API is type-safe, ergonomic for common cases, and extensible for future enhancements.
