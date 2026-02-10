# Building Waffle

## Quick Start

```bash
gleam run -m waffle/setup
```

This will automatically:
1. Check if the NIF is already built
2. Verify the NIF version matches the package version
3. Build from source if needed or if versions don't match

## Commands

### `gleam run -m waffle/setup`
User-facing setup command. Automatically handles:
- Building the NIF if it doesn't exist
- Rebuilding if the version doesn't match
- Skipping if already up-to-date

Options:
- `--force`: Force rebuild even if NIF exists and versions match

### `gleam run -m waffle/compile`
Always builds from source, regardless of current state.
Useful for development or CI.

## Version Management

The NIF includes its version (from `Cargo.toml`) and the setup script compares it with the package version (from `gleam.toml`).

If versions don't match, the NIF is automatically rebuilt. This ensures the native code stays in sync with the Gleam package.

**When bumping the version**, update all three places:
1. `version` in `gleam.toml`
2. `version` in `native/waffle/Cargo.toml`
3. `package_version` in `src/waffle/version.gleam`

`gleam test` will fail if `gleam.toml` and `version.gleam` drift apart, and `waffle/setup` will automatically rebuild the NIF if it doesn't match `Cargo.toml`.

## Requirements

To build from source:
- Rust toolchain (install from https://rustup.rs/)
- `cargo` must be in PATH

## Cross-Platform Support

The build scripts automatically detect the OS and use the correct file extension:
- Linux: `priv/waffle.so`
- macOS: `priv/waffle.dylib`
- Windows: `priv/waffle.dll`

## CI Usage

In CI, use the compile script directly:
```bash
gleam run -m waffle/compile
```

This ensures a clean build every time.
