# Default recipe: format-check + lint + test
check: lint test

# Build NIF from source, then run Gleam tests
test: build
    gleam test

# Auto-format both Gleam and Rust
fmt:
    gleam format src test
    cargo fmt --manifest-path native/waffle/Cargo.toml

# Format checks + clippy (read-only, CI-safe)
lint:
    gleam format --check src test
    cargo fmt --manifest-path native/waffle/Cargo.toml --check
    cargo clippy --no-deps --manifest-path native/waffle/Cargo.toml -- -D warnings

# Compile NIF from source
build:
    gleam run -m waffle_build

# Run benchmarks (builds NIF first). Optional fixed iteration count: just bench 200
bench iters="20": build
    gleam run -m waffle_bench -- {{iters}}

# Clean all build artifacts
clean:
    gleam clean
    cargo clean --manifest-path native/waffle/Cargo.toml

# Update lockfiles within current constraints
update:
    gleam deps update
    cargo update --manifest-path native/waffle/Cargo.toml

# Upgrade dependency constraints and tooling to latest compatible versions
upgrade:
    gleam add gleam_stdlib shellout simplifile
    gleam add --dev gleeunit tom
    cargo add faer rustler highs bytemuck rand rand_distr --manifest-path native/waffle/Cargo.toml
    mise upgrade --bump
