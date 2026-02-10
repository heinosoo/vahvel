/// The version of the Gleam package (from gleam.toml).
pub const package_version = "0.1.1"

/// Check if the NIF version matches the package version.
/// Returns Ok(True) if versions match, Ok(False) if they don't,
/// or Error if the NIF isn't loaded.
pub fn check_nif_version() -> Result(Bool, Nil) {
  case nif_version() {
    Ok(nif_ver) -> Ok(nif_ver == package_version)
    Error(_) -> Error(Nil)
  }
}

@external(erlang, "nif", "nif_version_result")
fn nif_version() -> Result(String, Nil)
