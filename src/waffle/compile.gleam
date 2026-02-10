import gleam/io
import gleam/result
import gleam/string
import shellout
import simplifile

@external(erlang, "waffle_build_ffi", "os_family")
fn os_family() -> String

fn detect_os() -> Result(String, String) {
  case os_family() {
    "win32" -> Ok("windows")
    _ -> {
      case shellout.command("uname", ["-s"], in: ".", opt: []) {
        Ok(output) -> {
          case string.trim(output) {
            "Darwin" -> Ok("macos")
            _ -> Ok("linux")
          }
        }
        Error(_) -> Ok("linux")
      }
    }
  }
}

fn source_path(os: String) -> String {
  case os {
    "windows" -> "native/waffle/target/release/waffle.dll"
    "macos" -> "native/waffle/target/release/libwaffle.dylib"
    _ -> "native/waffle/target/release/libwaffle.so"
  }
}

fn dest_path(os: String) -> String {
  case os {
    "windows" -> "priv/waffle.dll"
    "macos" -> "priv/waffle.dylib"
    _ -> "priv/waffle.so"
  }
}

pub fn nif_path() -> String {
  case detect_os() {
    Ok(os) -> dest_path(os)
    Error(_) -> "priv/waffle.so"
  }
}

pub fn do_compile() -> Result(Nil, String) {
  case shellout.which("cargo") {
    Error(_) -> {
      Error(
        "cargo not found. Please install Rust via https://rustup.rs/ and try again.",
      )
    }
    Ok(_) -> {
      io.println("Compiling Rust NIF...")
      case
        shellout.command(
          "cargo",
          ["build", "--release"],
          in: "native/waffle",
          opt: [
            shellout.LetBeStdout,
          ],
        )
      {
        Error(#(status, msg)) -> {
          Error(
            "cargo build failed (exit "
            <> string.inspect(status)
            <> "): "
            <> msg,
          )
        }
        Ok(_) -> {
          use os <- result.try(
            detect_os()
            |> result.map_error(fn(e) { "OS detection failed: " <> e }),
          )
          let src = source_path(os)
          let dest = dest_path(os)
          case simplifile.create_directory_all("priv") {
            Error(e) -> {
              Error("Failed to create priv/ directory: " <> string.inspect(e))
            }
            Ok(_) -> {
              case simplifile.copy_file(at: src, to: dest) {
                Error(e) -> {
                  Error(
                    "Failed to copy "
                    <> src
                    <> " to "
                    <> dest
                    <> ": "
                    <> string.inspect(e),
                  )
                }
                Ok(_) -> {
                  io.println("NIF compiled and copied to " <> dest)
                  Ok(Nil)
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn main() {
  case do_compile() {
    Ok(_) -> io.println("Build complete.")
    Error(msg) -> {
      io.println("Error: " <> msg)
      shellout.exit(1)
    }
  }
}
