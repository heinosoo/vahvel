import gleam/bit_array
import gleam/list
import gleam/result

fn nth(list: List(a), index: Int) -> Result(a, Nil) {
  nth_rec(list, index, 0)
}

fn nth_rec(list: List(a), index: Int, current: Int) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [x, ..rest] ->
      case current == index {
        True -> Ok(x)
        False -> nth_rec(rest, index, current + 1)
      }
  }
}

/// Errors that can occur when creating or manipulating matrices.
pub type MatrixError {
  /// Input was an empty list `[]`.
  EmptyInput
  /// Matrix contained an empty row `[[]]`.
  EmptyRow
  /// Matrix rows had different lengths (ragged array).
  RaggedRows
  /// Invalid matrix dimensions.
  InvalidDimensions(String)
}

/// A matrix stored in column-major order as f64 values.
pub opaque type Matrix {
  Matrix(rows: Int, cols: Int, data: BitArray)
}

/// Create a matrix from a nested list. Input is row-major.
pub fn from_list(data: List(List(Float))) -> Result(Matrix, MatrixError) {
  // Validate and get dimensions
  use #(rows, cols) <- result.try(validate_and_get_dimensions(data))

  // Validate all rows have correct length
  use _ <- result.try(validate_all_rows(data, cols))

  // Construct matrix
  let column_major = to_column_major(data, rows, cols)
  Ok(Matrix(rows: rows, cols: cols, data: column_major))
}

fn validate_and_get_dimensions(
  data: List(List(Float)),
) -> Result(#(Int, Int), MatrixError) {
  case data {
    [] -> Error(EmptyInput)
    _ -> {
      let rows = list.length(data)
      let first_row = list.first(data) |> result.unwrap([])
      let cols = list.length(first_row)

      case cols {
        0 -> Error(EmptyRow)
        _ -> Ok(#(rows, cols))
      }
    }
  }
}

fn validate_all_rows(
  data: List(List(Float)),
  expected_cols: Int,
) -> Result(Nil, MatrixError) {
  let validate_row = fn(row: List(Float)) {
    case row, list.length(row) {
      [], _ -> Error(EmptyRow)
      _, n if n != expected_cols -> Error(RaggedRows)
      _, _ -> Ok(Nil)
    }
  }

  list.try_map(data, validate_row)
  |> result.replace(Nil)
}

fn to_column_major(data: List(List(Float)), rows: Int, cols: Int) -> BitArray {
  let row_data = list.flatten(data)
  build_column_major(row_data, rows, cols)
}

fn build_column_major(row_data: List(Float), rows: Int, cols: Int) -> BitArray {
  let list_fn = fn(i: Int) {
    let col_index = i / rows
    let row_index = i % rows
    result.unwrap(nth(row_data, row_index * cols + col_index), or: 0.0)
  }

  let values = list.map(list.range(0, rows * cols - 1), list_fn)
  pack_floats(values)
}

fn pack_floats(floats: List(Float)) -> BitArray {
  case floats {
    [] -> <<>>
    [x, ..rest] ->
      bit_array.append(to: float_to_bytes(x), suffix: pack_floats(rest))
  }
}

@external(erlang, "nif", "float_to_bytes")
fn float_to_bytes(f: Float) -> BitArray

@external(erlang, "nif", "bytes_to_float")
fn bytes_to_float(b: BitArray) -> Float

/// Convert matrix to nested list. Output is row-major.
pub fn to_list(matrix: Matrix) -> List(List(Float)) {
  let floats = unpack_floats(matrix.data)
  from_column_major(floats, matrix.rows, matrix.cols)
}

fn unpack_floats(data: BitArray) -> List(Float) {
  let byte_size = bit_array.byte_size(data)
  case byte_size {
    0 -> []
    _ -> {
      let first =
        result.unwrap(bit_array.slice(from: data, at: 0, take: 8), or: <<>>)
      let rest =
        result.unwrap(
          bit_array.slice(from: data, at: 8, take: byte_size - 8),
          or: <<>>,
        )
      [bytes_to_float(first), ..unpack_floats(rest)]
    }
  }
}

fn from_column_major(
  floats: List(Float),
  rows: Int,
  cols: Int,
) -> List(List(Float)) {
  let list_fn = fn(row: Int) { build_row(floats, row, rows, cols) }

  list.map(list.range(0, rows - 1), list_fn)
}

fn build_row(
  floats: List(Float),
  row_index: Int,
  rows: Int,
  cols: Int,
) -> List(Float) {
  let list_fn = fn(col: Int) {
    let index = col * rows + row_index
    result.unwrap(nth(floats, index), or: 0.0)
  }

  list.map(list.range(0, cols - 1), list_fn)
}

/// Get the number of rows in a matrix.
pub fn rows(matrix: Matrix) -> Int {
  matrix.rows
}

/// Get the number of columns in a matrix.
pub fn cols(matrix: Matrix) -> Int {
  matrix.cols
}

/// Create an n x n identity matrix.
pub fn identity(n: Int) -> Result(Matrix, MatrixError) {
  case n {
    _ if n < 1 -> Error(InvalidDimensions("Matrix size must be at least 1"))
    _ -> {
      let list_fn = fn(i: Int) {
        let row = i / n
        let col = i % n
        case row == col {
          True -> 1.0
          False -> 0.0
        }
      }

      let values = list.map(list.range(0, n * n - 1), list_fn)
      Ok(Matrix(rows: n, cols: n, data: pack_floats(values)))
    }
  }
}

/// Create a matrix from binary data.
@internal
pub fn from_binary(rows: Int, cols: Int, data: BitArray) -> Matrix {
  Matrix(rows: rows, cols: cols, data: data)
}

/// Get the binary data from a matrix.
@internal
pub fn to_binary(matrix: Matrix) -> BitArray {
  matrix.data
}
