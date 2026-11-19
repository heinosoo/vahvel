//// Detects a stale native library: one built from a different package version.

/// The package version; the release workflow keeps it equal to gleam.toml's.
pub const package_version = "0.4.0"

/// Whether the loaded NIF was built from this package version. Calling it loads
/// the NIF; `Error(Nil)` means the library could not be loaded.
pub fn check_nif_version() -> Result(Bool, Nil) {
  case nif_version() {
    Ok(nif_version) -> Ok(nif_version == package_version)
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "vahvel_build_ffi", "loaded_nif_version")
fn nif_version() -> Result(String, Nil)
