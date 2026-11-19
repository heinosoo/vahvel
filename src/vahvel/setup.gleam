//// Build the native library ahead of time: `gleam run -m vahvel/setup`.
//// vahvel builds a missing library on first use; setup also rebuilds one that
//// fails to load or has the wrong version. To rebuild anyway, run
//// `gleam run -m vahvel/setup -- --force`.

import gleam/io
import gleam/list
import gleam/result
import shellout
import vahvel/internal/build
import vahvel/internal/version

/// Builds or checks the library, printing what it did. Exits with status 1 if
/// the build fails, for example when `cargo` is not installed.
pub fn main() -> Nil {
  let outcome = case list.contains(shellout.arguments(), "--force") {
    True -> build.compile()
    False -> {
      use _ <- result.try(build.ensure_built())
      case version.check_nif_version() {
        Ok(True) -> Ok(io.println("vahvel: native library is up to date"))
        // The stale library stays loaded until the VM restarts.
        Ok(False) -> rebuild("does not match " <> version.package_version)
        // A failed load leaves the NIF module unloaded, so checking again
        // loads the rebuilt library.
        Error(_) -> {
          use _ <- result.try(rebuild("could not be loaded"))
          case version.check_nif_version() {
            Ok(True) -> Ok(Nil)
            Ok(False) ->
              Error(
                "rebuilt native library does not match "
                <> version.package_version,
              )
            Error(_) -> Error("rebuilt native library could not be loaded")
          }
        }
      }
    }
  }
  case outcome {
    Ok(_) -> Nil
    Error(message) -> {
      io.println_error("vahvel: " <> message)
      shellout.exit(1)
    }
  }
}

fn rebuild(reason: String) -> Result(Nil, String) {
  io.println("vahvel: native library " <> reason <> ", rebuilding...")
  build.compile()
}
