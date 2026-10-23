# Waffle

A Gleam optimization library backed by [microlp](https://docs.rs/microlp/0.6.0/microlp/)
through Rustler NIFs.

The internal driver solves linear and mixed-integer linear programs. Its numeric
model contains variable domains, objective coefficients, and sparse constraint
rows. It returns an optimal solution, infeasibility, unboundedness, or an error.
There is no public modeling API yet.

See [ROADMAP.md](ROADMAP.md) for the planned redesign.

[ARCHITECTURE.md](ARCHITECTURE.md) describes how the library fits together.
Modeling API decisions are recorded in [API-DESIGN.md](API-DESIGN.md), and the
[executable modeling examples](test/model_test.gleam) exercise the internal
modeling layer. It is not a supported public API yet. Run it with `just test`.

## Development

`nix develop` provides Gleam, Erlang/OTP, Rust, and just. Alternatively, use
`direnv allow` with nix-direnv.

```sh
just        # formatting checks, Clippy, native build, and integration tests
just fmt    # format Gleam and Rust
just build  # rebuild the native library
```

The setup entry point, `gleam run -m waffle_setup`, builds a missing or
version-mismatched NIF. Use `gleam run -m waffle_setup -- --force` to rebuild at
the same version. Native libraries are built from source and stored in `priv/`.
