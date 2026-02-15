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
    cargo clippy --manifest-path native/waffle/Cargo.toml -- -D warnings

# Compile NIF from source
build:
    gleam run -m waffle_build

# Clean all build artifacts
clean:
    gleam clean
    cargo clean --manifest-path native/waffle/Cargo.toml
