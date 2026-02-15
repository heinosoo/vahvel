import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import waffle/internal/faer/mat

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
  /// Matrix dimensions do not match for the operation.
  DimensionMismatch(String)
  /// Matrix is singular (not invertible).
  SingularMatrix
}

/// A matrix stored in column-major order as 64-bit values.
pub opaque type Matrix(a) {
  Matrix(rows: Int, cols: Int, data: BitArray)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn pack_floats(floats: List(Float)) -> BitArray {
  list.fold(floats, <<>>, fn(acc, x) { <<acc:bits, x:float-little-size(64)>> })
}

fn pack_ints(ints: List(Int)) -> BitArray {
  list.fold(ints, <<>>, fn(acc, x) { <<acc:bits, x:int-little-size(64)>> })
}

fn read_float_at(data: BitArray, index: Int) -> Float {
  let offset = index * 8
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:float-little-size(64)>>) -> x
    _ -> 0.0
  }
}

fn read_int_at(data: BitArray, index: Int) -> Int {
  let offset = index * 8
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:int-little-size(64)>>) -> x
    _ -> 0
  }
}

fn dim_string(matrix: Matrix(a)) -> String {
  int.to_string(matrix.rows) <> "x" <> int.to_string(matrix.cols)
}

fn validate_and_get_dimensions(
  data: List(List(a)),
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
  data: List(List(a)),
  expected_cols: Int,
) -> Result(Nil, MatrixError) {
  list.try_each(data, fn(row) {
    case list.length(row) != expected_cols {
      True -> Error(RaggedRows)
      False -> Ok(Nil)
    }
  })
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create a matrix of floats from a nested list. Input is row-major.
pub fn from_float_list(data: List(List(Float))) -> Result(Matrix(Float), MatrixError) {
  use #(rows, cols) <- result.try(validate_and_get_dimensions(data))
  use _ <- result.try(validate_all_rows(data, cols))
  let row_major = pack_floats(list.flatten(data))
  // We use mat.transpose to convert row-major input to column-major.
  // This works because floats are 64-bit, same as what the NIF expects/handles.
  use column_major <- result.try(
    mat.transpose(cols, rows, row_major)
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )
  Ok(Matrix(rows: rows, cols: cols, data: column_major))
}

/// Create a matrix of integers from a nested list. Input is row-major.
pub fn from_int_list(data: List(List(Int))) -> Result(Matrix(Int), MatrixError) {
  use #(rows, cols) <- result.try(validate_and_get_dimensions(data))
  use _ <- result.try(validate_all_rows(data, cols))
  let row_major = pack_ints(list.flatten(data))
  // We use mat.transpose to convert row-major input to column-major.
  // This works because ints are encoded as 64-bit.
  use column_major <- result.try(
    mat.transpose(cols, rows, row_major)
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )
  Ok(Matrix(rows: rows, cols: cols, data: column_major))
}

/// Create an n×n identity matrix of floats.
pub fn identity_float(n: Int) -> Result(Matrix(Float), MatrixError) {
  case n {
    _ if n < 1 -> Error(InvalidDimensions("Matrix size must be at least 1"))
    _ -> {
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

/// Create an m×n matrix of zeros (floats).
pub fn zeros_float(rows: Int, cols: Int) -> Result(Matrix(Float), MatrixError) {
  case rows < 1 || cols < 1 {
    True ->
      Error(InvalidDimensions(
        "Dimensions must be at least 1x1, got "
        <> int.to_string(rows)
        <> "x"
        <> int.to_string(cols),
      ))
    False -> {
      let bits = rows * cols * 64
      let data = <<0:size(bits)>>
      Ok(Matrix(rows: rows, cols: cols, data: data))
    }
  }
}

/// Create an m×n matrix of ones (floats).
pub fn ones_float(rows: Int, cols: Int) -> Result(Matrix(Float), MatrixError) {
  case rows < 1 || cols < 1 {
    True ->
      Error(InvalidDimensions(
        "Dimensions must be at least 1x1, got "
        <> int.to_string(rows)
        <> "x"
        <> int.to_string(cols),
      ))
    False -> {
      let data =
        list.fold(list.range(0, rows * cols - 1), <<>>, fn(acc, _) {
          <<acc:bits, 1.0:float-little-size(64)>>
        })
      Ok(Matrix(rows: rows, cols: cols, data: data))
    }
  }
}

/// Create a square diagonal matrix from a list of float values.
pub fn diagonal_float(values: List(Float)) -> Result(Matrix(Float), MatrixError) {
  let n = list.length(values)
  case n {
    0 -> Error(EmptyInput)
    _ -> {
      let data =
        list.index_fold(values, <<>>, fn(acc, val, col) {
          // For each column, write n values: val at row==col, 0 elsewhere
          list.fold(list.range(0, n - 1), acc, fn(inner_acc, row) {
            let value = case row == col {
              True -> val
              False -> 0.0
            }
            <<inner_acc:bits, value:float-little-size(64)>>
          })
        })
      Ok(Matrix(rows: n, cols: n, data: data))
    }
  }
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Get the number of rows in a matrix.
pub fn rows(matrix: Matrix(a)) -> Int {
  matrix.rows
}

/// Get the number of columns in a matrix.
pub fn cols(matrix: Matrix(a)) -> Int {
  matrix.cols
}

/// Get the float element at the given row and column (0-indexed).
pub fn get_float(matrix: Matrix(Float), row: Int, col: Int) -> Result(Float, MatrixError) {
  case row >= 0 && row < matrix.rows && col >= 0 && col < matrix.cols {
    True -> {
      let index = col * matrix.rows + row
      Ok(read_float_at(matrix.data, index))
    }
    False ->
      Error(InvalidDimensions(
        "Index ("
        <> int.to_string(row)
        <> ", "
        <> int.to_string(col)
        <> ") out of bounds for "
        <> dim_string(matrix)
        <> " matrix",
      ))
  }
}

/// Get the int element at the given row and column (0-indexed).
pub fn get_int(matrix: Matrix(Int), row: Int, col: Int) -> Result(Int, MatrixError) {
  case row >= 0 && row < matrix.rows && col >= 0 && col < matrix.cols {
    True -> {
      let index = col * matrix.rows + row
      Ok(read_int_at(matrix.data, index))
    }
    False ->
      Error(InvalidDimensions(
        "Index ("
        <> int.to_string(row)
        <> ", "
        <> int.to_string(col)
        <> ") out of bounds for "
        <> dim_string(matrix)
        <> " matrix",
      ))
  }
}

/// Convert matrix to nested list of floats. Output is row-major.
pub fn to_float_list(matrix: Matrix(Float)) -> List(List(Float)) {
  let data = matrix.data
  let rows = matrix.rows
  let cols = matrix.cols

  list.map(list.range(0, rows - 1), fn(row) {
    list.map(list.range(0, cols - 1), fn(col) {
      read_float_at(data, col * rows + row)
    })
  })
}

/// Convert matrix to nested list of ints. Output is row-major.
pub fn to_int_list(matrix: Matrix(Int)) -> List(List(Int)) {
  let data = matrix.data
  let rows = matrix.rows
  let cols = matrix.cols

  list.map(list.range(0, rows - 1), fn(row) {
    list.map(list.range(0, cols - 1), fn(col) {
      read_int_at(data, col * rows + row)
    })
  })
}

/// Get the binary data from a matrix.
pub fn to_binary(matrix: Matrix(a)) -> BitArray {
  matrix.data
}

/// Create a matrix from binary data.
/// Assumes data is composed of 64-bit elements (f64 or i64).
pub fn from_binary(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(Matrix(a), MatrixError) {
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

// ---------------------------------------------------------------------------
// Structure operations
// ---------------------------------------------------------------------------

/// Transpose a matrix (swap rows and columns).
/// Works for any 64-bit element type.
pub fn transpose(matrix: Matrix(a)) -> Result(Matrix(a), MatrixError) {
  case mat.transpose(matrix.rows, matrix.cols, matrix.data) {
    Ok(data) -> Ok(Matrix(rows: matrix.cols, cols: matrix.rows, data: data))
    Error(msg) -> Error(InvalidDimensions("Transpose failed: " <> msg))
  }
}
