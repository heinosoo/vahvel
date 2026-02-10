/// The version of the Gleam package (from gleam.toml).
pub const package_version = "0.1.1"

/// Check if the NIF version matches the package version.
/// Returns Ok(True) if versions match, Ok(False) if they don't,
/// or Error if the NIF isn't loaded.
pub fn check_nif_version() -> Result(Bool, Nil) {
  case nif_version_safe() {
    Ok(nif_ver) -> Ok(nif_ver == package_version)
    Error(_) -> Error(Nil)
  }
}

/// Get the NIF version, returning Error if the NIF isn't loaded.
fn nif_version_safe() -> Result(String, Nil) {
  case nif_version() {
    version -> Ok(version)
  }
}

@external(erlang, "waffle_ffi", "nif_version")
fn nif_version() -> String
