# Waffle — Roadmap (targets 0.3.0)

Step-by-step implementation plan.

> **Archived:** Previous roadmaps in [archive/](archive/).

---

## Documentation

- [x] Write module docs (`waffle/matrix`).
- [x] Write module docs (`waffle/linalg`).
- [x] Write optimization docs (`waffle/opt`) with examples.

## Benchmarks

- [x] Internal harness: `just bench` compares Gleam (NIF call path) vs pure Rust for multiply, LU, and solve across matrix sizes. Measures mean ± σ; overhead is roughly constant at ~2–5 μs for small matrices.
- [ ] Compare performance against Python/NumPy for common ops.

## Future Enhancements

- [ ] Add builder API for `waffle/opt` with chaining (`with_int_var`, `with_eq_constraint`, `build`)

## Publish

- [ ] Final version bump.
- [ ] `gleam publish`.
