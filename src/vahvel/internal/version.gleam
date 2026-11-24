//// Detects a stale native library: one built from a different package version.

import gleam/result

/// The package version; the release workflow keeps it equal to gleam.toml's.
pub const package_version = "0.4.1"

/// Whether the loaded NIF was built from this package version. Calling it loads
/// the NIF; `Error(Nil)` means the library could not be loaded.
pub fn check_nif_version() -> Result(Bool, Nil) {
  result.map(nif_version(), fn(version) { version == package_version })
}

@external(erlang, "vahvel_build_ffi", "loaded_nif_version")
fn nif_version() -> Result(String, Nil)
