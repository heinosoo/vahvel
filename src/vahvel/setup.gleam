//// Build the native library ahead of time: `gleam run -m vahvel/setup`.
//// vahvel builds a missing library on first use; setup also rebuilds one that
//// fails to load or has the wrong version. Pass `--force` to rebuild anyway.

import gleam/io
import gleam/list
import gleam/result
import shellout
import vahvel/internal/build
import vahvel/internal/version

pub fn main() {
  let outcome = case list.contains(shellout.arguments(), "--force") {
    True -> build.compile()
    False -> {
      use _ <- result.try(build.ensure_built())
      case version.check_nif_version() {
        Ok(True) -> Ok(io.println("vahvel: native library is up to date"))
        Ok(False) -> rebuild("does not match " <> version.package_version)
        Error(_) -> rebuild("could not be loaded")
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
