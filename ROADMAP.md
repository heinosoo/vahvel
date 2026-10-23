# Waffle roadmap

Focus: an idiomatic Gleam optimization library with a small native solver layer.
These are rough priorities; API shapes and backend choices remain open.

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
