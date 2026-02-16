# Phase 3: Decision Science (ILP & Optimization)

**Goal:** Add a Mixed-Integer Linear Programming (MILP) solver using `highs`.

**Status:** Not started

## 1. Dependencies & Build

- [ ] **Add `highs` crate**
  - Update `native/waffle/Cargo.toml` to add `highs = "2.0"` (or latest).
  - The `highs` crate provides safe Rust bindings to the HiGHS solver.
- [ ] **Static Linking Configuration**
  - Create or update `.cargo/config.toml` (or `build.rs`) to force `-static-libstdc++`.
  - *Verification:* Build on Linux and check `ldd` to ensure no dependency on system `libstdc++`.

## 2. Optimization Module (`src/waffle/opt.gleam`)

- [ ] **Types**
  - Define `Model` type (opaque, wraps internal HiGHS state).
  - Define `VariableType` enum (`Continuous`, `Integer`, `Binary`).
  - Define `Direction` enum (`Minimize`, `Maximize`).
  - Define `SolutionStatus` enum (`Optimal`, `Infeasible`, `Unbounded`).
- [ ] **Builder API**
  - `opt.new() -> Model`
  - `opt.add_variable(model, type, lb, ub) -> #(Model, VariableId)`
  - `opt.set_objective(model, coeffs, direction)`
  - `opt.add_constraint(model, coeffs, lower_bound, upper_bound)`
- [ ] **Matrix-based API (Batch)**
  - `opt.solve(objective, constraint_matrix, lower_bounds, upper_bounds, variable_types)`
  - `constraint_matrix` accepts `Matrix` OR `SparseMatrix`.
  - **Note:** Our `SparseMatrix` uses CSC format, which maps naturally to `highs::ColMatrix`.

## 3. Solver NIF (`native/waffle/src/lib.rs`)

- [ ] **Use `highs` crate API**
  - Prefer `ColProblem` for CSC-friendly construction (constraints first, variables added with coefficients).
  - Alternatively, `RowProblem` for row-based construction (variables first, constraints added).
  - The crate handles HiGHS C FFI internally.
- [ ] **Implement `solve_ilp`**
  - Input: Objective vector, constraint matrix (dense or sparse), bounds, variable types.
  - For `SparseMatrix`: Convert CSC data to `highs::ColMatrix` (column-major, natural fit).
  - For `Matrix`: Convert dense data to appropriate `highs` format.
  - Run solver with `DirtyCpu` scheduling.
  - Map `HighsModelStatus` to Gleam `SolutionStatus`.
- [ ] **Return Type**
  - `Result(Solution, SolverError)`.
  - `Solution`: primal values (columns), dual values (rows), objective value, status.
  - `SolverError`: dimension mismatch, numerical issues, etc.

## 4. Matrix Format Notes

- **CSC → ColMatrix:** Our `SparseMatrix` stores data in CSC format (`col_ptr`, `row_indices`, `values`).
  - This maps directly to `highs::ColMatrix` which builds column-by-column.
  - No format conversion needed - just iterate columns and add variables.
- **Dense → ColMatrix/RowMatrix:** For `Matrix`, convert to sparse first or use dense iteration.

## 5. Testing

- [ ] **Continuous LP Test**
  - Simple 2D region maximization.
  - Example: maximize `x + 2y` subject to `3x + y <= 6`, `y + 2z <= 7`.
- [ ] **Integer Test**
  - Knapsack-style problem with integer constraints.
  - Verify integer variables return whole numbers.
- [ ] **Sparse Test**
  - Test with a large, sparse constraint matrix (e.g., 1000x1000 with 1% density).
  - Ensure no OOM or crash, and CSC path works correctly.
