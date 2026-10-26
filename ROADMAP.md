# Waffle roadmap

Next milestone: publish the existing LP/MILP library on GitHub and Hex, built
from source with Rust. Keep the current Gleam modeling API unless a concrete
correctness or usability problem warrants a change.

Finished work is removed; git keeps the history. Current behavior belongs in
[ARCHITECTURE.md](ARCHITECTURE.md), decisions in [DESIGN.md](DESIGN.md), and
installation instructions in [README.md](README.md).

## First public release

A release candidate is ready when a fresh consuming project can follow the
README, build the native library, and solve a model from both a Git dependency
and the prepared Hex package. Publication itself is a separate final step.

### 1. Name, license, metadata

These shape everything below, so settle them first.

- Confirm the Hex package name. `waffle` is probably taken by an Elixir
  library; a rename touches the Gleam package, `code:priv_dir(waffle)`, the
  NIF file name, the Cargo crate and the docs.
- Choose a license and add its text. Replace the placeholder `gleam.toml`
  metadata (description, license, repository) and align the Cargo metadata.

### 2. Package layout and consumer installation

Gleam's Hex package contains only `src/`, `priv/`, the README and
`gleam.toml`, so `native/` is missing from it; Git dependencies hide this.
A scratch test showed that a crate under `priv/` ships, `.cargo/config.toml`
included. `src/waffle/internal/build.gleam` also resolves paths relative to
the working directory, while the loader uses `code:priv_dir(waffle)`.

- Move the crate under `priv/`. Only the built library joins it there;
  Cargo's target directory (gigabytes) stays outside, since `priv/` ships
  with every deployment.
- Resolve sources and the output library inside the installed dependency, and
  verify that setup writes where the runtime loads, including after
  `gleam clean`.
- From a fresh project outside this checkout, install from Git at a fixed
  commit, then from the prepared Hex tarball. Run setup and a small solve
  without borrowing this checkout's build artifacts.
- Inspect the tarball: Rust sources, Cargo manifest and lockfile, `.cargo`
  config, Erlang FFI and license; no compiled libraries or build output.
- Check first setup, repeated setup, `--force`, version mismatch, and clear
  guidance for a missing Rust toolchain or an unloadable NIF (`on_load` as
  well as the version check).
- Check that a built consuming application runs with the NIF in its release.
  Document what is needed at build time versus on the runtime machine.

### 3. Documentation and cleanup

- README: Git and Hex installation, Rust and linker prerequisites, the Erlang
  target requirement, setup and a first solve. Consumers need neither Nix nor
  `just`. Add troubleshooting based on the checks in section 2.
- Document the 0.x compatibility policy and known limits: the integer range
  limit, solve-budget semantics and outcome handling.
- Review the generated API docs against actual behavior.
- Run the motivating Advent of Code problem on a full input and record
  correctness and solve time. Don't redistribute personal puzzle inputs.
- Remove stale comments, placeholder configuration and misleading release
  instructions.

### 4. Release process

CI runs repository checks in Nix on Linux. The release workflow bumps
versions, tags, and attaches a nonportable Nix-built library; it neither
tests an installed package nor publishes to Hex.

- Add a `just` recipe for the consumer smoke test and run it in CI with fresh
  native builds.
- Check version consistency across `gleam.toml`, `Cargo.toml` and
  `Cargo.lock`.
- Test the exact tarball before tagging. Make the Git tag and Hex version
  point at the same revision; document publication order and retries.
- Drop the binary attachment from the release workflow.
- Document or automate Hex and API-doc publication, with release notes on
  requirements and limitations.
- After publishing, smoke-test the real Hex download and record the result.

## Conditional follow-up work

Possibilities, not commitments. Promote an item when a real use case supplies
an acceptance criterion. Judge API additions by semantic clarity,
composability, predictable validation and public surface cost.

- **Checking a supplied plan.** Extend evaluation to bounds, integrality and
  constraints. Needs defined tolerances and handling of missing assignments,
  numeric failures and multiple violations.
- **Model diagnostics.** If generated models are hard to debug, look at
  referenced variables, summaries and readable expressions together. Try
  application-owned row metadata before adding identity to the model.
  Printing a model doesn't explain infeasibility; that needs its own guidance.
- **Indexed construction.** Helpers such as key-driven row families, if
  mapping/grouping obscures models. Must handle mismatched lengths and
  duplicate keys; performance claims need measurements.
- **Backend limitations.** If workloads hit solver or numerical limits, extend
  the LP benchmark with representative MILPs and checked small cases before
  choosing a replacement. The signed 32-bit integer-domain limit stays
  documented until it blocks an application.
- **Duals and quadratic objectives.** For applications needing sensitivity
  analysis or convex QP. Duals must meet DESIGN.md's requirements; quadratics
  need capability-specific types and convexity rules. Clarabel is a candidate.
  Solver selection only once a second backend has a purpose.
- **Precompiled NIFs.** If requiring Rust prevents adoption. Size is not the
  obstacle (about 330 KB compressed per target); portable builds per target,
  pinned checksums and build provenance are. Keep the source build.
- **Automatic build via a rebar3 wrapper.** If the explicit setup step proves
  annoying, a rebar3 native package with a `cargo` pre-hook could build during
  `gleam build`. Verify first that Gleam runs rebar3 hooks; costs a second
  package published in lockstep.
- **JavaScript through WASM.** For a browser or JS application; covers
  loading, execution and interruption.

Runtime model handles and reusable Gleam–Rust tooling are not planned.
