# Waffle

A Gleam optimization library backed by [microlp](https://docs.rs/microlp/0.6.0/microlp/)
through Rustler NIFs.

Models are plain Gleam data keyed by your own types; the API is unstable while
the package is 0.x.

```gleam
import gleam/option.{None, Some}
import waffle.{Constant, Linear, Sum}

type Product {
  Chair
  Table
}

pub fn main() {
  let domain = fn(product) {
    case product {
      Chair -> waffle.Continuous(Some(0.0), Some(2.0))
      Table -> waffle.Continuous(Some(0.0), None)
    }
  }
  let model =
    waffle.Model(
      domain:,
      objective: waffle.Maximize(
        Sum([Linear(3.0, Chair), Linear(2.0, Table), Constant(7.0)]),
      ),
      constraints: [
        waffle.LessEqual(
          Sum([Linear(1.0, Chair), Linear(1.0, Table)]),
          Constant(4.0),
        ),
      ],
    )
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model)
  waffle.objective(solution)  // 17.0
  waffle.value(solution, Chair)  // Ok(2.0)
}
```

Keys can be any Gleam value, including plain `Int`s. Here each item's list
position names its 0/1 decision:

```gleam
import gleam/list
import gleam/option.{Some}
import waffle.{Constant, Linear, Sum}

pub fn main() {
  // #(weight, value)
  let items = list.index_map([#(3.0, 5.0), #(2.0, 3.0), #(2.0, 3.0)], fn(item, i) {
    #(i, item.0, item.1)
  })
  let value = list.map(items, fn(item) { Linear(item.2, item.0) }) |> Sum
  let weight = list.map(items, fn(item) { Linear(item.1, item.0) }) |> Sum
  let model =
    waffle.Model(
      domain: fn(_) { waffle.Binary },
      objective: waffle.Maximize(value),
      constraints: [waffle.LessEqual(weight, Constant(4.0))],
    )
  let assert Ok(waffle.Optimal(solution)) = waffle.solve(model)
  waffle.objective(solution)  // 6.0: items 1 and 2
  waffle.value(solution, 0)  // Ok(0.0)
  waffle.stats(solution).nodes  // branch-and-bound nodes the solver needed
}
```

An `Int` key is a name, not a column number: columns follow the order in which
variables are first referenced.

Expressions nest, so a named expression can be reused anywhere. `Scaled` also
scales constants, and all arithmetic happens in Rust:

```gleam
import waffle.{Constant, Linear, Scaled, Sum}

let revenue = Sum([Linear(5.0, Chair), Linear(4.0, Table)])
let cost = Sum([Linear(1.0, Chair), Linear(2.0, Table), Constant(3.0)])
let profit = Sum([revenue, Scaled(-1.0, cost)])
let objective = waffle.Maximize(profit)
// After solving, evaluate either the whole expression or a breakdown:
waffle.evaluate(solution, profit)
waffle.evaluate(solution, cost)
```

Zero-scaled expressions still reference their variables. Scaling and summation
report overflow when solving or evaluating, rather than during construction.

More examples are in [test/waffle_test.gleam](test/waffle_test.gleam).
[ARCHITECTURE.md](ARCHITECTURE.md) describes how the library fits together,
[DESIGN.md](DESIGN.md) explains the design decisions, and
[ROADMAP.md](ROADMAP.md) lists planned work.

## Development

`nix develop` provides Gleam, Erlang/OTP, Rust, and just. Alternatively, use
`direnv allow` with nix-direnv.

```sh
just        # formatting checks, Clippy, native build, and integration tests
just fmt    # format Gleam and Rust
just build  # rebuild the native library
```

The setup entry point, `gleam run -m waffle/setup`, builds a missing or
version-mismatched NIF. Use `gleam run -m waffle/setup -- --force` to rebuild at
the same version. Native libraries are built from source and stored in `priv/`.
