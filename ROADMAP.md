# Vahvel roadmap

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

### 1. Package layout and consumer installation

Scratch consumers on Linux installed from a local Git repository at a fixed
commit and from unpacked `gleam export hex-tarball` contents (as a path
dependency). Each ran setup, solved, survived `gleam clean`, `--force`, a
version mismatch and a corrupt library, and ran from an Erlang shipment. A
missing library builds on first load.

- Windows: Gleam copies `priv/` instead of linking it, so setup writes into
  the build copy and the target directory lands under `build/<mode>`. Check
  setup, `gleam export` and the loader there, or document Windows as
  unsupported.

### 2. Documentation and cleanup

- README: Git and Hex installation, Rust and linker prerequisites, the Erlang
  target requirement, setup and a first solve. Consumers need neither Nix nor
  `just`. Add troubleshooting based on the checks in section 1. Say what is
  needed at build time (Rust, a linker) versus on the runtime machine (only
  the built `priv/vahvel.*` inside the release).
- Document the 0.x compatibility policy and known limits: the integer range
  limit, solve-budget semantics and outcome handling.
- Review the generated API docs against actual behavior.
- Run the motivating Advent of Code problem on a full input and record
  correctness and solve time. Don't redistribute personal puzzle inputs.
- Remove stale comments, placeholder configuration and misleading release
  instructions.

### 3. Release process

CI runs repository checks in Nix on Linux. The release workflow bumps
versions, tags, and attaches a nonportable Nix-built library; it neither
tests an installed package nor publishes to Hex.

- Add a `just` recipe for the consumer smoke test and run it in CI with fresh
  native builds.
- Check version consistency across `gleam.toml`, `Cargo.toml` and
  `Cargo.lock`.
- Build the tarball from a clean checkout: Gleam ignores `.gitignore` for
  `priv/`, so a local `priv/vahvel.so` would ship. Test that exact tarball
  before tagging. Make the Git tag and Hex version point at the same
  revision; document publication order and retries.
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
- **JavaScript through WASM.** For a browser or JS application; covers
  loading, execution and interruption.

Runtime model handles and reusable Gleam–Rust tooling are not planned.
