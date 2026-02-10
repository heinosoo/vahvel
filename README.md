# waffle

Linear algebra for Gleam, powered by Rust.

## What

A Gleam library for solving linear systems (`Ax = b`) using LU decomposition with partial pivoting. The heavy lifting is done by [faer](https://github.com/sarah-ek/faer-rs), a pure Rust linear algebra crate — no C/Fortran dependencies.

## Why

There is no linear algebra library in the Gleam ecosystem. faer is fast (often outperforms OpenBLAS), safe, and compiles anywhere Rust does.

## Features

- **Dirty NIFs** — matrix operations run on the DirtyCpu scheduler, never blocking the BEAM
- **Zero-copy input** — Erlang binaries are viewed directly as f64 slices
- **Smart build** — `gleam run -m waffle/setup` builds the NIF, skipping if already up to date

## Usage

```gleam
import waffle/matrix
import waffle/solver

pub fn main() {
  // Solve: 2x + y = 7, x + 3y = 9
  let assert Ok(a) = matrix.from_list([[2.0, 1.0], [1.0, 3.0]])
  let assert Ok(b) = matrix.from_list([[7.0], [9.0]])

  let assert Ok(x) = solver.solve(a, b)
  // x = [[2.4], [2.2]]
}
```

## Installation

```sh
gleam add waffle
gleam run -m waffle/setup
```

The setup script builds the native library from source using Cargo. It skips the build if the NIF is already present and the version matches. Precompiled binary downloads are planned but not yet implemented.

## Requirements

- Gleam
- Erlang/OTP
- Rust (required for building the native library)

## Status

Early development. See [ROADMAP.md](ROADMAP.md) for the implementation plan.
