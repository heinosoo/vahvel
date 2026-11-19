import gleam/list
import gleam/result
import gleeunit/should
import simplifile
import tom
import vahvel/internal/version

// On failure, rebuild with `just build`.
pub fn nif_version_matches_package_test() {
  version.check_nif_version() |> should.equal(Ok(True))
}

pub fn package_version_matches_gleam_toml_test() {
  read_toml("gleam.toml")
  |> tom.get_string(["version"])
  |> should.equal(Ok(version.package_version))
}

pub fn package_version_matches_cargo_toml_test() {
  read_toml("priv/native/Cargo.toml")
  |> tom.get_string(["package", "version"])
  |> should.equal(Ok(version.package_version))
}

pub fn package_version_matches_cargo_lock_test() {
  let assert Ok(packages) =
    read_toml("priv/native/Cargo.lock") |> tom.get_array(["package"])
  packages
  |> list.find_map(fn(package) {
    use package <- result.try(
      tom.as_table(package) |> result.replace_error(Nil),
    )
    case tom.get_string(package, ["name"]) {
      Ok("vahvel") ->
        tom.get_string(package, ["version"]) |> result.replace_error(Nil)
      _ -> Error(Nil)
    }
  })
  |> should.equal(Ok(version.package_version))
}

fn read_toml(path: String) {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(toml) = tom.parse(content)
  toml
}
