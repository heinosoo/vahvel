# Vahvel

Linear and mixed-integer programming for Gleam. Describe a model with plain
Gleam data, keyed by your own types, and solve it with
[microlp](https://docs.rs/microlp/0.6.0/microlp/) through a Rust NIF. The API
is unstable while the package is 0.x. *Vahvel* is Estonian for waffle.

## Example

A waffle stand has 13 minutes of iron time. Classic waffles earn 3.00 and take
2 minutes; chocolate waffles earn 5.00 and take 3. How many of each?

```gleam
import vahvel.{Constant, Linear, Sum}

type Waffle {
  Classic
  Chocolate
}

let model =
  vahvel.Model(
    domain: fn(_) { vahvel.NonNegativeInteger },
    objective: vahvel.Maximize(
      Sum([Linear(3.0, Classic), Linear(5.0, Chocolate)]),
    ),
    constraints: [
      vahvel.LessEqual(
        Sum([Linear(2.0, Classic), Linear(3.0, Chocolate)]),
        Constant(13.0),
      ),
    ],
  )
let assert Ok(vahvel.Optimal(solution, _)) = vahvel.solve(model)
vahvel.objective(solution)  // 21.0: 3 chocolate and 2 classic
```

## Installation

```sh
gleam add vahvel
```

Or depend on the repository:
`vahvel = { git = "https://github.com/heinosoo/vahvel", ref = "main" }`.

Vahvel runs on the Erlang target. Building it needs
[Rust](https://rustup.rs) with `cargo` on the `PATH` and a platform linker. The
native library is built from source the first time vahvel is loaded, or ahead
of time with `gleam run -m vahvel/setup`. A machine that only runs a built
release needs neither: the library ships inside it as `priv/vahvel.*`.

## Features

[test/examples/readme_test.gleam][readme_test] grows the example into a full
story: a menu from data, topping stations as yes-or-no decisions, a report,
and a hand-made plan. The snippets below come from it.

**Your own keys.** Variables are named by any Gleam value, usually a custom
type naming the decision. A variable exists once an expression references it,
and `domain` gives its values, typically with an exhaustive `case`:

```gleam
type Decision {
  Bake(Waffle)
  Station(Waffle)
}

fn domain(decision: Decision) -> vahvel.Domain {
  case decision {
    Bake(_) -> vahvel.NonNegativeInteger
    Station(_) -> vahvel.Binary
  }
}
```

**Expressions are data.** An expression is a small affine tree of `Variable`,
`Linear`, `Constant`, `Sum`, `Difference` and `Scaled`. Build it with the
standard library, name it, and reuse it anywhere:

```gleam
let sales =
  list.map(menu, fn(recipe) { Linear(recipe.price, Bake(recipe.waffle)) })
  |> Sum
let profit = Difference(sales, station_costs)
```

**Constraints relate two expressions** with `LessEqual`, `Equal` or
`GreaterEqual`, so they read like the math. Families of constraints are mapped
over data:

```gleam
list.map(toppings, fn(topping) {
  vahvel.LessEqual(
    Variable(Bake(topping.waffle)),
    Linear(topping.serves, Station(topping.waffle)),
  )
})
```

**Answers are values.** Infeasible and unbounded models are outcomes, not
errors; `Error(_)` means invalid input or a solver failure. `solve_with` adds
time and node budgets, and a budget stop may still carry a feasible plan:

```gleam
let assert Ok(outcome) = vahvel.solve_with(
  model,
  vahvel.Limits(time: Some(duration.seconds(2)), nodes: Some(1000)),
)
let plan = case outcome {
  vahvel.Optimal(solution, _) | vahvel.Limited(_, Some(solution), _) ->
    Some(solution)
  vahvel.Limited(_, None, _) | vahvel.Infeasible | vahvel.Unbounded -> None
}
```

**Reporting reuses the model.** Evaluate the expressions that built the model
at a solution or at any values you supply, such as a hand-made plan. A key no
expression referenced is an error, never a silent zero:

```gleam
vahvel.evaluate_solution(sales, solution)  // Ok(22.5)
vahvel.value(solution, Bake(Berry))  // Ok(3.0)
vahvel.value(solution, Station(Classic))  // Error(Nil)
vahvel.evaluate_dict(profit, plan)  // Ok(19.5)
```

**Numerics in Rust.** Gleam only describes the model; Rust sums, scales,
validates and solves it in one native call. Overflow and non-finite numbers are
reported with their location, never during construction.

## Learn more

The [API reference](https://hexdocs.pm/vahvel/vahvel.html) gives exact semantics,
including domain and budget limits. More examples, including a multi-period
production network and N-queens, are in [test/examples][examples].
[ARCHITECTURE.md][architecture] describes how the library fits together,
[DESIGN.md][design] explains the design decisions, and [ROADMAP.md][roadmap]
lists planned work.

## Development

`nix develop` provides Gleam, Erlang/OTP, Rust, and just. Alternatively, use
`direnv allow` with nix-direnv.

```sh
just        # list the recipes
just check  # formatting checks, Clippy, native build, and integration tests
just fmt    # format Gleam and Rust
just build  # rebuild the native library
```

## Acknowledgements

Vahvel is a modeling layer; the solving is done by
[microlp](https://github.com/Specy/microlp), a pure-Rust MILP solver.
[Rustler](https://github.com/rusterlium/rustler) makes the native boundary safe
to write. Thank you!

## License

Apache-2.0, see [LICENSE][license].

<!-- Absolute links: HexDocs renders this README without the repository. -->
[readme_test]: https://github.com/heinosoo/vahvel/blob/main/test/examples/readme_test.gleam
[examples]: https://github.com/heinosoo/vahvel/tree/main/test/examples
[architecture]: https://github.com/heinosoo/vahvel/blob/main/ARCHITECTURE.md
[design]: https://github.com/heinosoo/vahvel/blob/main/DESIGN.md
[roadmap]: https://github.com/heinosoo/vahvel/blob/main/ROADMAP.md
[license]: https://github.com/heinosoo/vahvel/blob/main/LICENSE
