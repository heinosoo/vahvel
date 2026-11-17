import gleam/io
import gleam/result
import gleam/string
import shellout
import simplifile

@external(erlang, "vahvel_build_ffi", "os_family")
fn os_family() -> String

fn detect_os() -> String {
  case os_family() {
    "win32" -> "windows"
    _ ->
      shellout.command("uname", ["-s"], in: ".", opt: [])
      |> result.map(fn(output) {
        case string.trim(output) {
          "Darwin" -> "macos"
          _ -> "linux"
        }
      })
      |> result.unwrap("linux")
  }
}

fn source_path(os: String) -> String {
  case os {
    "windows" -> "native/vahvel/target/release/vahvel.dll"
    "macos" -> "native/vahvel/target/release/libvahvel.dylib"
    _ -> "native/vahvel/target/release/libvahvel.so"
  }
}

fn dest_path(os: String) -> String {
  case os {
    "windows" -> "priv/vahvel.dll"
    "macos" -> "priv/vahvel.dylib"
    _ -> "priv/vahvel.so"
  }
}

pub fn nif_path() -> String {
  dest_path(detect_os())
}

pub fn do_compile() -> Result(Nil, String) {
  // Check for cargo
  use _ <- result.try(
    shellout.which("cargo")
    |> result.replace_error(
      "cargo not found. Please install Rust via https://rustup.rs/ and try again.",
    ),
  )

  // Run cargo build
  io.println("Compiling Rust NIF...")
  use _ <- result.try(
    shellout.command("cargo", ["build", "--release"], in: "native/vahvel", opt: [
      shellout.LetBeStdout,
    ])
    |> result.map_error(fn(err) {
      let #(status, msg) = err
      "cargo build failed (exit " <> string.inspect(status) <> "): " <> msg
    }),
  )

  // Detect OS
  let os = detect_os()
  let src = source_path(os)
  let dest = dest_path(os)

  // Create priv directory
  use _ <- result.try(
    simplifile.create_directory_all("priv")
    |> result.map_error(fn(e) {
      "Failed to create priv/ directory: " <> string.inspect(e)
    }),
  )

  // Copy file
  use _ <- result.try(
    simplifile.copy_file(at: src, to: dest)
    |> result.map_error(fn(e) {
      "Failed to copy " <> src <> " to " <> dest <> ": " <> string.inspect(e)
    }),
  )

  io.println("NIF compiled and copied to " <> dest)
  Ok(Nil)
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
