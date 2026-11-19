# Cargo commands run inside the crate so they pick up its .cargo/config.toml,
# which keeps build output out of priv/; --manifest-path would skip it.
crate := "priv/native"

[private]
default:
    @just --list

# Lint (format checks, Clippy), then test
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
    cd {{crate}} && cargo fmt

# Format checks + clippy (read-only, CI-safe)
lint:
    gleam format --check src test
    cd {{crate}} && cargo fmt --check
    cd {{crate}} && cargo clippy --no-deps -- -D warnings

# Compile NIF from source
build:
    gleam run -m vahvel/setup -- --force

# Clean all build artifacts
clean:
    gleam clean
    cd {{crate}} && cargo clean

# Update lockfiles within current constraints
update:
    gleam deps update
    cd {{crate}} && cargo update
