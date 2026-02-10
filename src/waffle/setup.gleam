import gleam/io
import gleam/list
import shellout
import simplifile
import waffle/compile
import waffle/version

fn should_rebuild(force: Bool) -> Bool {
  case force {
    True -> {
      io.println("Force rebuild requested")
      True
    }
    False -> {
      let nif = compile.nif_path()
      case simplifile.is_file(nif) {
        Ok(False) | Error(_) -> {
          io.println("NIF not found, building from source...")
          True
        }
        Ok(True) -> {
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
      }
    }
  }
}

pub fn main() {
  let args = shellout.arguments()
  let force = list.contains(args, "--force")

  case should_rebuild(force) {
    False -> Nil
    True -> {
      case compile.do_compile() {
        Ok(_) -> io.println("Setup complete.")
        Error(msg) -> {
          io.println("Error: " <> msg)
          io.println(
            "If you don't have Rust installed, visit https://rustup.rs/",
          )
          shellout.exit(1)
        }
      }
    }
  }
}
