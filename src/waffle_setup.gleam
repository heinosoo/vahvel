import gleam/io
import gleam/list
import shellout
import simplifile
import waffle/version
import waffle_build

fn should_rebuild_nif() -> Bool {
  let nif = waffle_build.nif_path()

  case simplifile.is_file(nif) {
    Ok(True) -> check_nif_version(nif)
    Ok(False) | Error(_) -> {
      io.println("NIF not found, building from source...")
      True
    }
  }
}

fn check_nif_version(nif: String) -> Bool {
  case version.check_nif_version() {
    Error(_) -> {
      io.println(
        "NIF exists but version check failed, rebuilding from source...",
      )
      True
    }
    Ok(False) -> {
      io.println(
        "NIF version mismatch (expected "
        <> version.package_version
        <> "), rebuilding from source...",
      )
      True
    }
    Ok(True) -> {
      io.println("NIF already built at " <> nif)
      False
    }
  }
}

pub fn main() {
  let args = shellout.arguments()
  let force = list.contains(args, "--force")

  case force || should_rebuild_nif() {
    False -> Nil
    True -> {
      case waffle_build.do_compile() {
        Ok(_) -> io.println("Setup complete.")
        Error(msg) -> {
          io.println("Error: " <> msg)
          shellout.exit(1)
        }
      }
    }
  }
}
