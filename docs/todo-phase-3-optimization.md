# Phase 3: Decision Science (ILP & Optimization)

**Goal:** Add a Mixed-Integer Linear Programming (MILP) solver using `highs`.

## 1. Dependencies & Build

- [ ] **Add `highs` crate**
  - Update `native/waffle/Cargo.toml`.
- [ ] **Static Linking Configuration**
  - Create or update `.cargo/config.toml` (or `build.rs`) to force `-static-libstdc++`.
  - *Verification:* Build on Linux and check `ldd` to ensure no dependency on system `libstdc++`.

## 2. Optimization Module (`src/waffle/opt.gleam`)

- [ ] **Types**
  - Define `Model` type (opaque).
  - Define `VariableType` enum (`Continuous`, `Integer`, `Binary`).
  - Define `Direction` enum (`Minimize`, `Maximize`).
- [ ] **Builder API**
  - `opt.new() -> Model`
  - `opt.add_variable(model, type, lb, ub) -> #(Model, VariableId)` (or similar).
  - `opt.set_objective(model, coeffs, direction)`
  - `opt.add_constraint(model, coeffs, lower_bound, upper_bound)`
- [ ] **Matrix-based API (Batch)**
  - `opt.load_problem(objective_vector, constraint_matrix, bounds_vectors, variable_types)`
  - **Crucial:** `constraint_matrix` should accept `Matrix` OR `SparseMatrix`.

## 3. Solver NIF (`native/waffle/src/lib.rs`)

- [ ] **Implement `solve_ilp`**
  - Input: Float matrices (dense or sparse) for $A, b, c$, Integer/Enum list for variable types.
  - Logic:
    1. Map inputs to `highs::HighsModel` (handling CSR if sparse).
    2. Run solver (release GIL / DirtyCpu).
    3. Map `highs::HighsSolution` back to Gleam types.
- [ ] **Return Type**
  - Define a rich result type: `Result(Solution, SolverError)`.
  - `Solution` should include: primal values, objective value, status (Optimal, Infeasible, Unbounded).

## 4. Testing

- [ ] **Continuous LP Test**
  - Simple 2D region maximization.
- [ ] **Integer Test**
  - Knapsack-style problem or simple integer constraint.
- [ ] **Sparse Test**
  - Test with a large, sparse constraint matrix to ensure it doesn't OOM or crash.
