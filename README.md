# waffle

Linear algebra for Gleam, powered by Rust.

## What

A Gleam library for solving linear systems (`Ax = b`) using LU decomposition with partial pivoting. The heavy lifting is done by [faer](https://github.com/sarah-ek/faer-rs), a pure Rust linear algebra crate — no C/Fortran dependencies.

## Why

There is no linear algebra library in the Gleam ecosystem. faer is fast (often outperforms OpenBLAS), safe, and compiles anywhere Rust does.

## Features

- **Dirty NIFs** — matrix operations run on the DirtyCpu scheduler, never blocking the BEAM
- **Zero-copy input** — Erlang binaries are viewed directly as f64 slices
- **Smart build** — precompiled binaries downloaded automatically, with cargo fallback

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
gleam run -m waffle/build
```

The build script downloads a precompiled native library for your platform. If no precompiled binary is available, it falls back to `cargo build --release` (requires Rust).

## Requirements

- Gleam
- Erlang/OTP
- Rust (only if no precompiled binary is available for your platform)

## Status

Early development. See [ROADMAP.md](ROADMAP.md) for the implementation plan.
