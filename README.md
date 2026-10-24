# Waffle

Linear and mixed-integer programming for Gleam. Describe a model with plain
Gleam data, keyed by your own types, and solve it with
[microlp](https://docs.rs/microlp/0.6.0/microlp/) through a Rust NIF. The API
is unstable while the package is 0.x.

## Example

A waffle stand has 13 minutes of iron time. Classic waffles earn 3.00 and take
2 minutes; chocolate waffles earn 5.00 and take 3. How many of each?

```gleam
import waffle.{Constant, Linear, Sum}

type Waffle {
  Classic
  Chocolate
}

let model =
  waffle.Model(
    domain: fn(_) { waffle.NonNegativeInteger },
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
stations as yes-or-no decisions, a report, and a hand-made plan. The snippets
below come from it.

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
    Bake(_) -> waffle.NonNegativeInteger
    Station(_) -> waffle.Binary
  }
}
```

Domains are `Real` or `Integer` with optional inclusive bounds, or `Binary`.
`NonNegativeReal` and `NonNegativeInteger` specify a zero lower bound and no
explicit upper bound. For example, `Real(Some(-2.5), Some(3.0))` allows real
values from −2.5 to 3; `None` leaves that side unbounded. Integer domains are
currently limited to the backend's signed 32-bit range.

**Expressions are data.** An expression is a small affine tree: `Variable`,
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
  waffle.LessEqual(
    Variable(Bake(topping.waffle)),
    Linear(topping.serves, Station(topping.waffle)),
  )
})
```

**Answers are values.** `solve` returns `Ok(Optimal(solution))`,
`Ok(Infeasible)` or `Ok(Unbounded)`; `Error(_)` is reserved for invalid input
or solver failures. Only an optimum carries a solution.

**Reporting reuses the model.** Look up values by key and evaluate the
expressions that built the model, at a solution or at any values you supply,
such as a hand-made plan. A key no expression referenced is an error, never a
silent zero:

```gleam
waffle.evaluate_solution(sales, solution)  // Ok(22.5)
waffle.value(solution, Bake(Berry))  // Ok(3.0)
waffle.value(solution, Station(Classic))  // Error(Nil)
waffle.evaluate_dict(profit, plan)  // Ok(19.5)
waffle.stats(solution).nodes  // branch-and-bound nodes
```

`evaluate(expression, lookup)` takes any `fn(key) -> Result(Float, Nil)`, for
example solution values with some overridden.

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
