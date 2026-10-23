# Waffle

Linear and mixed-integer programming for Gleam. Describe a model with plain
Gleam data, keyed by your own types, and solve it with
[microlp](https://docs.rs/microlp/0.6.0/microlp/) through a Rust NIF. The API
is unstable while the package is 0.x.

## Example

A waffle stand has 13 minutes of iron time. Classic waffles earn 3.00 and take
2 minutes; chocolate waffles earn 5.00 and take 3. How many of each?

```gleam
import gleam/option.{None, Some}
import waffle.{Constant, Linear, Sum}

type Waffle {
  Classic
  Chocolate
}

let model =
  waffle.Model(
    domain: fn(_) { waffle.Integer(Some(0), None) },
    objective: waffle.Maximize(
      Sum([Linear(3.0, Classic), Linear(5.0, Chocolate)]),
    ),
    constraints: [
      waffle.LessEqual(
        Sum([Linear(2.0, Classic), Linear(3.0, Chocolate)]),
        Constant(13.0),
      ),
    ],
  )
let assert Ok(waffle.Optimal(solution)) = waffle.solve(model)
waffle.objective(solution)  // 21.0: 3 chocolate and 2 classic
```

[test/examples/readme_test.gleam](test/examples/readme_test.gleam) grows this
into a full story, step by step with explanations: a menu from data, topping
stations as yes-or-no decisions, and a report. The snippets below come from it.

## Features

**Your own keys.** Variables are named by any Gleam value, usually a custom
type naming the decision. A variable exists once an expression references it,
and `domain` gives its values, typically with an exhaustive `case`:

```gleam
type Decision {
  Bake(Waffle)
  Station(Waffle)
}

fn domain(decision: Decision) -> waffle.Domain {
  case decision {
    Bake(_) -> waffle.Integer(Some(0), None)
    Station(_) -> waffle.Binary
  }
}
```

Domains are `Continuous` or `Integer` with optional bounds, or `Binary`.

**Expressions are data.** An expression is a small affine tree: `Linear`,
`Constant`, `Sum` and `Scaled`. Build it with the standard library, name it,
and reuse it anywhere:

```gleam
let sales =
  list.map(menu, fn(recipe) { Linear(recipe.price, Bake(recipe.waffle)) })
  |> Sum
let profit = Sum([sales, Scaled(-1.0, station_costs)])
```

**Constraints relate two expressions** with `LessEqual`, `Equal` or
`GreaterEqual`, so they read like the math. Families of constraints are mapped
over data:

```gleam
list.map(toppings, fn(topping) {
  waffle.LessEqual(
    Linear(1.0, Bake(topping.waffle)),
    Linear(topping.serves, Station(topping.waffle)),
  )
})
```

**Answers are values.** `solve` returns `Ok(Optimal(solution))`,
`Ok(Infeasible)` or `Ok(Unbounded)`; `Error(_)` is reserved for invalid input
or solver failures. Only an optimum carries a solution.

**Reporting reuses the model.** Look up values by key and evaluate the
expressions that built the model. A key no expression referenced is an error,
never a silent zero:

```gleam
waffle.evaluate(solution, sales)  // Ok(22.5)
waffle.value(solution, Bake(Berry))  // Ok(3.0)
waffle.value(solution, Station(Classic))  // Error(Nil)
waffle.stats(solution).nodes  // branch-and-bound nodes
```

**Numerics in Rust.** Gleam only describes the model; Rust sums, scales,
validates and solves it in one native call. Overflow and non-finite numbers are
reported with their location when solving or evaluating, never during
construction.

## Learn more

More examples, including a multi-period production network and N-queens, are
in [test/examples](test/examples).
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
