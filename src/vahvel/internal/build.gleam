//// Builds the native library from the Rust crate shipped in `priv/native`.

import gleam/io
import gleam/result
import gleam/string
import shellout

type Paths {
  Paths(crate: String, target: String, built: String, nif: String)
}

@external(erlang, "vahvel_build_ffi", "dirs")
fn dirs() -> Result(#(String, String), Nil)

@external(erlang, "vahvel_build_ffi", "library_names")
fn library_names() -> #(String, String)

@external(erlang, "vahvel_build_ffi", "copy")
fn copy(from: String, to: String) -> Result(Nil, String)

@external(erlang, "filelib", "is_regular")
fn is_file(path: String) -> Bool

fn paths() -> Result(Paths, String) {
  use #(priv, package) <- result.try(
    dirs()
    |> result.replace_error("the vahvel application is not on the code path"),
  )
  let #(built, nif) = library_names()
  // Outside priv/, which ships; matches priv/native/.cargo/config.toml.
  let target = package <> "/target"
  Ok(Paths(
    crate: package <> "/priv/native",
    target:,
    built: target <> "/release/" <> built,
    nif: priv <> "/" <> nif,
  ))
}

/// Builds the library if it is missing. Called when the NIF module loads.
pub fn ensure_built() -> Result(Nil, String) {
  use paths <- result.try(paths())
  case is_file(paths.nif) {
    True -> Ok(Nil)
    False -> {
      io.println_error(
        "vahvel: building the native library from source with Cargo (first use only, may take a minute)...",
      )
      compile_at(paths)
    }
  }
}

/// Builds the library, replacing any existing one.
pub fn compile() -> Result(Nil, String) {
  result.try(paths(), compile_at)
}

fn compile_at(paths: Paths) -> Result(Nil, String) {
  use _ <- result.try(
    shellout.which("cargo")
    |> result.replace_error(
      "cargo not found; install Rust from https://rustup.rs and try again",
    ),
  )
  // An explicit target dir also overrides CARGO_TARGET_DIR, so `built` holds.
  use _ <- result.try(
    shellout.command(
      "cargo",
      ["build", "--release", "--target-dir", paths.target],
      in: paths.crate,
      opt: [shellout.LetBeStdout],
    )
    |> result.map_error(fn(err) {
      "cargo build failed (exit " <> string.inspect(err.0) <> ")"
    }),
  )
  use _ <- result.try(
    copy(paths.built, paths.nif)
    |> result.map_error(fn(reason) {
      "could not copy " <> paths.built <> " to " <> paths.nif <> ": " <> reason
    }),
  )
  io.println_error("vahvel: native library built at " <> paths.nif)
  Ok(Nil)
}
