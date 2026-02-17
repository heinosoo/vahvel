# waffle

Linear algebra for Gleam, powered by Rust.

## What

A Gleam linear algebra library. Matrix arithmetic, decompositions (LU, QR, SVD), and linear solvers — backed by [faer](https://github.com/sarah-ek/faer-rs), a pure Rust linear algebra crate. Also includes optimization via [HiGHS](https://highs.dev).

## Why

There is no linear algebra library in the Gleam ecosystem. faer is fast (often outperforms OpenBLAS), safe, and has no BLAS/LAPACK dependencies.

## Features

- **Matrix arithmetic** — add, subtract, scale, multiply, transpose
- **Sparse matrices** — CSC format, sparse arithmetic, conversion to/from dense
- **Decompositions** — LU (partial pivoting), QR (thin), SVD (thin)
- **Properties** — determinant, inverse, symmetric eigenvalues, trace
- **Linear solver** — solve `Ax = b` via LU decomposition
- **Random generation** — uniform, normal, bernoulli distributions
- **Optimization (ILP)** — linear and mixed-integer programming via HiGHS
- **Dirty NIFs** — all operations run on the DirtyCpu scheduler, never blocking the BEAM
- **Zero-copy input** — Erlang binaries are viewed directly as f64 slices
- **Smart build** — `gleam run -m waffle_setup` builds the NIF, skipping if already up to date

## Usage

```gleam
import waffle/matrix
import waffle/linalg
import waffle/sparse
import waffle/random
import waffle/opt

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

  // Sparse matrices (efficient for matrices with many zeros)
  let assert Ok(s) = sparse.from_triplets(3, 3, [#(0, 0, 1.0), #(1, 1, 2.0), #(2, 2, 3.0)])
  let assert Ok(dense) = sparse.to_dense(s)

  // Random generation
  let noise = random.normal(100, 100, 0.0, 1.0)

  // Optimization (mixed-integer linear programming)
  let model = opt.new() |> opt.set_direction(opt.Maximize)
  let #(model, x) = opt.cont_var(model, "x", 3.0, 0.0, 10.0)
  let #(model, y) = opt.int_var(model, "y", 2.0, 0.0, 10.0)
  let assert Ok(model) = opt.add_le_constraint(model, 15.0, [#(x, 1.0), #(y, 1.0)])
  let assert Ok(solution) = opt.solve(model)
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
- Rust (install via https://rustup.rs/)
- cmake (required to build the native library)

## Status

Early development. See [docs/ROADMAP.md](docs/ROADMAP.md) for the implementation plan.

## Learn More

- [Architecture](docs/ARCHITECTURE.md) — System design, data flow, and key decisions
