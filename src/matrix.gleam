import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result

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

@external(erlang, "nif", "transpose")
fn transpose_nif(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(BitArray, String)

fn pack_floats(floats: List(Float)) -> BitArray {
  list.fold(floats, <<>>, fn(acc, x) { <<acc:bits, x:float-little-size(64)>> })
}

fn read_float_at(data: BitArray, index: Int) -> Float {
  let offset = index * 8
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:float-little-size(64)>>) -> x
    _ -> 0.0
  }
}

/// Create a matrix from a nested list. Input is row-major.
pub fn from_list(data: List(List(Float))) -> Result(Matrix, MatrixError) {
  // Validate and get dimensions
  use #(rows, cols) <- result.try(validate_and_get_dimensions(data))

  // Validate all rows have correct length
  use _ <- result.try(validate_all_rows(data, cols))

  // Pack row-major into a flat BitArray, then rearrange to column-major using transpose
  let row_major = pack_floats(list.flatten(data))
  use column_major <- result.try(
    transpose_nif(cols, rows, row_major)
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )
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
  list.try_each(data, fn(row) {
    case list.length(row) != expected_cols {
      True -> Error(RaggedRows)
      False -> Ok(Nil)
    }
  })
}

/// Convert matrix to nested list. Output is row-major.
pub fn to_list(matrix: Matrix) -> List(List(Float)) {
  let data = matrix.data
  let rows = matrix.rows
  let cols = matrix.cols

  list.map(list.range(0, rows - 1), fn(row) {
    list.map(list.range(0, cols - 1), fn(col) {
      read_float_at(data, col * rows + row)
    })
  })
}

/// Get the number of rows in a matrix.
pub fn rows(matrix: Matrix) -> Int {
  matrix.rows
}

/// Get the number of columns in a matrix.
pub fn cols(matrix: Matrix) -> Int {
  matrix.cols
}

/// Transpose a matrix (swap rows and columns).
pub fn transpose(matrix: Matrix) -> Result(Matrix, MatrixError) {
  case transpose_nif(matrix.rows, matrix.cols, matrix.data) {
    Ok(data) -> Ok(Matrix(rows: matrix.cols, cols: matrix.rows, data: data))
    Error(msg) -> Error(InvalidDimensions("Transpose failed: " <> msg))
  }
}

/// Create an n x n identity matrix.
pub fn identity(n: Int) -> Result(Matrix, MatrixError) {
  case n {
    _ if n < 1 -> Error(InvalidDimensions("Matrix size must be at least 1"))
    _ -> {
      // Iterate in column-major order: col = i / n, row = i % n
      let data =
        list.fold(list.range(0, n * n - 1), <<>>, fn(acc, i) {
          let col = i / n
          let row = i % n
          let value = case row == col {
            True -> 1.0
            False -> 0.0
          }
          <<acc:bits, value:float-little-size(64)>>
        })
      Ok(Matrix(rows: n, cols: n, data: data))
    }
  }
}

/// Create a matrix from binary data.
@internal
pub fn from_binary(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(Matrix, MatrixError) {
  let expected = rows * cols * 8
  let actual = bit_array.byte_size(data)
  case actual == expected {
    True -> Ok(Matrix(rows: rows, cols: cols, data: data))
    False ->
      Error(InvalidDimensions(
        "from_binary: expected "
        <> int.to_string(expected)
        <> " bytes but got "
        <> int.to_string(actual),
      ))
  }
}

/// Get the binary data from a matrix.
@internal
pub fn to_binary(matrix: Matrix) -> BitArray {
  matrix.data
}
