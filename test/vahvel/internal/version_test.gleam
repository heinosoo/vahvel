import gleam/io
import gleeunit/should
import simplifile
import tom
import vahvel/internal/version

pub fn nif_version_matches_package_test() {
  case version.check_nif_version() {
    Ok(True) -> should.be_true(True)
    Ok(False) -> {
      io.println(
        "NIF version mismatch - expected "
        <> version.package_version
        <> ", rebuild with: just build",
      )
      should.be_true(False)
    }
    Error(_) -> {
      io.println("NIF not loaded - run: gleam run -m vahvel/setup")
      should.be_true(False)
    }
  }
}

pub fn package_version_matches_gleam_toml_test() {
  let assert Ok(toml_str) = simplifile.read("gleam.toml")
  let assert Ok(toml) = tom.parse(toml_str)
  let assert Ok(gleam_toml_version) = tom.get_string(toml, ["version"])

  gleam_toml_version
  |> should.equal(version.package_version)
}
