# waffle

Linear algebra for Gleam, powered by Rust.

## What

A Gleam linear algebra library. Matrix arithmetic, decompositions (LU, QR, SVD), and linear solvers — all backed by [faer](https://github.com/sarah-ek/faer-rs), a pure Rust linear algebra crate with no C/Fortran dependencies.

## Why

There is no linear algebra library in the Gleam ecosystem. faer is fast (often outperforms OpenBLAS), safe, and compiles anywhere Rust does.

## Features

- **Matrix arithmetic** — add, subtract, scale, multiply, transpose
- **Decompositions** — LU (partial pivoting), QR (thin), SVD (thin)
- **Properties** — determinant, inverse, symmetric eigenvalues, trace
- **Linear solver** — solve `Ax = b` via LU decomposition
- **Dirty NIFs** — all operations run on the DirtyCpu scheduler, never blocking the BEAM
- **Zero-copy input** — Erlang binaries are viewed directly as f64 slices
- **Smart build** — `gleam run -m waffle_setup` builds the NIF, skipping if already up to date

## Usage

```gleam
import waffle/matrix
import waffle/linalg

pub fn main() {
  let assert Ok(a) = matrix.from_list([[2.0, 1.0], [1.0, 3.0]])
  let assert Ok(b) = matrix.from_list([[7.0], [9.0]])

  // Solve Ax = b
  let assert Ok(x) = linalg.solve(a, b)

  // Arithmetic
  let assert Ok(sum) = matrix.add(a, a)
  let assert Ok(product) = matrix.multiply(a, a)

  // Decompositions and properties
  let assert Ok(linalg.LU(l, u, pivot)) = linalg.lu(a)
  let assert Ok(det) = linalg.determinant(a)
  let assert Ok(inv) = linalg.inverse(a)
}
```

## Installation

### From Hex (when published)

```sh
gleam add waffle
gleam run -m waffle_setup
```

### As a local dependency

Until published to Hex, add waffle to your `gleam.toml`:

```toml
[dependencies]
waffle = { path = "../waffle" }  # adjust path as needed
```

Then build the native library:

```sh
cd path/to/waffle
gleam run -m waffle_setup
```

The setup script builds the native library from source using Cargo. It skips the build if the NIF is already present and the version matches. Precompiled binary downloads are planned but not yet implemented.

## Requirements

- Gleam
- Erlang/OTP
- Rust (required for building the native library)

## Status

Early development. See [ROADMAP.md](ROADMAP.md) for the implementation plan.
