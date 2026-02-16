# Waffle — Roadmap (targets 0.3.0)

Step-by-step implementation plan.

> **Archived:** Previous roadmaps in [archive/](archive/).

---

## Documentation

- [ ] Write module docs (`waffle/matrix`).
- [ ] Write module docs (`waffle/linalg`).
- [x] Write optimization docs (`waffle/opt`) with examples.

## Benchmarks

- [ ] Compare performance against Python/NumPy for common ops.

## Robustness

- [ ] Add `catch_unwind` wrappers around NIF compute calls to convert panics to error tuples.

## Future Enhancements

- [ ] Add builder API for `waffle/opt` with chaining (`with_int_var`, `with_eq_constraint`, `build`)

## Publish

- [ ] Final version bump.
- [ ] `gleam publish`.
