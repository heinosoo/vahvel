# Default recipe: format-check + lint + test
check: lint test

# Build NIF from source, then run Gleam tests
test: build
    gleam test

# Measure overhead around the solver (test/bench.gleam)
bench: build
    gleam run -m bench

# Auto-format both Gleam and Rust
fmt:
    gleam format src test
    cargo fmt --manifest-path native/vahvel/Cargo.toml

# Format checks + clippy (read-only, CI-safe)
lint:
    gleam format --check src test
    cargo fmt --manifest-path native/vahvel/Cargo.toml --check
    cargo clippy --no-deps --manifest-path native/vahvel/Cargo.toml -- -D warnings

# Compile NIF from source
build:
    gleam run -m vahvel/internal/build

# Clean all build artifacts
clean:
    gleam clean
    cargo clean --manifest-path native/vahvel/Cargo.toml

# Update lockfiles within current constraints
update:
    gleam deps update
    cargo update --manifest-path native/vahvel/Cargo.toml

# Upgrade dependency constraints and tooling to latest compatible versions
upgrade:
    gleam add gleam_stdlib shellout simplifile
    gleam add --dev gleeunit tom
    cargo add rustler --manifest-path native/vahvel/Cargo.toml
    cargo add microlp --no-default-features --manifest-path native/vahvel/Cargo.toml
    nix flake update
