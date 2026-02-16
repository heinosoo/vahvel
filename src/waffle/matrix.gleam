import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
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

/// A matrix stored in column-major order as f64 values.
pub opaque type Matrix {
  Matrix(rows: Int, cols: Int, data: BitArray)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

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

fn dim_string(matrix: Matrix) -> String {
  int.to_string(matrix.rows) <> "x" <> int.to_string(matrix.cols)
}

/// Get the dimensions of a matrix as #(rows, cols).
pub fn dims(matrix: Matrix) -> #(Int, Int) {
  #(matrix.rows, matrix.cols)
}

/// Validates that a matrix is square. Returns an error if rows != cols.
pub fn validate_square(matrix: Matrix) -> Result(Nil, MatrixError) {
  case matrix.rows == matrix.cols {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "Expected square matrix, got " <> dim_string(matrix),
      ))
  }
}

fn validate_same_dimensions(a: Matrix, b: Matrix) -> Result(Nil, MatrixError) {
  case a.rows == b.rows && a.cols == b.cols {
    True -> Ok(Nil)
    False ->
      Error(DimensionMismatch(
        "Dimension mismatch: " <> dim_string(a) <> " vs " <> dim_string(b),
      ))
  }
}

fn validate_multipliable(a: Matrix, b: Matrix) -> Result(Nil, MatrixError) {
  case a.cols == b.rows {
    True -> Ok(Nil)
    False ->
      Error(DimensionMismatch(
        "Cannot multiply "
        <> dim_string(a)
        <> " by "
        <> dim_string(b)
        <> ": inner dimensions do not match",
      ))
  }
}

/// Validates that a matrix is symmetric. Returns an error if not square or not symmetric.
pub fn validate_symmetric(matrix: Matrix) -> Result(Nil, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows
  let is_symmetric =
    list.all(list.range(0, n - 1), fn(i) {
      list.all(list.range(i + 1, n - 1), fn(j) {
        let aij = read_float_at(matrix.data, j * n + i)
        let aji = read_float_at(matrix.data, i * n + j)
        float.loosely_equals(aij, aji, tolerating: 1.0e-10)
      })
    })
  case is_symmetric {
    True -> Ok(Nil)
    False -> Error(InvalidDimensions("Matrix is not symmetric"))
  }
}

fn nif_error_to_matrix_error(msg: String) -> MatrixError {
  case msg {
    "Matrix is singular" <> _ -> SingularMatrix
    _ -> InvalidDimensions(msg)
  }
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create a matrix from a nested list. Input is row-major.
pub fn from_list(data: List(List(Float))) -> Result(Matrix, MatrixError) {
  use #(rows, cols) <- result.try(validate_and_get_dimensions(data))
  use _ <- result.try(validate_all_rows(data, cols))
  let row_major = pack_floats(list.flatten(data))
  use column_major <- result.try(
    mat.transpose(cols, rows, row_major)
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

/// Create an n×n identity matrix.
pub fn identity(n: Int) -> Result(Matrix, MatrixError) {
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

/// Create an m×n matrix of zeros.
pub fn zeros(rows: Int, cols: Int) -> Result(Matrix, MatrixError) {
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

/// Create an m×n matrix of ones.
pub fn ones(rows: Int, cols: Int) -> Result(Matrix, MatrixError) {
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

/// Create a square diagonal matrix from a list of values.
pub fn diagonal(values: List(Float)) -> Result(Matrix, MatrixError) {
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
pub fn rows(matrix: Matrix) -> Int {
  matrix.rows
}

/// Get the number of columns in a matrix.
pub fn cols(matrix: Matrix) -> Int {
  matrix.cols
}

/// Get the element at the given row and column (0-indexed).
pub fn get(matrix: Matrix, row: Int, col: Int) -> Result(Float, MatrixError) {
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

/// Get the binary data from a matrix.
pub fn to_binary(matrix: Matrix) -> BitArray {
  matrix.data
}

/// Create a matrix from binary data.
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

// ---------------------------------------------------------------------------
// Pure operations
// ---------------------------------------------------------------------------

/// Compute the trace (sum of diagonal elements) of a square matrix.
pub fn trace(matrix: Matrix) -> Result(Float, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows
  let sum =
    list.fold(list.range(0, n - 1), 0.0, fn(acc, i) {
      acc +. read_float_at(matrix.data, i * n + i)
    })
  Ok(sum)
}

/// Transpose a matrix (swap rows and columns).
pub fn transpose(matrix: Matrix) -> Result(Matrix, MatrixError) {
  case mat.transpose(matrix.rows, matrix.cols, matrix.data) {
    Ok(data) -> Ok(Matrix(rows: matrix.cols, cols: matrix.rows, data: data))
    Error(msg) -> Error(InvalidDimensions("Transpose failed: " <> msg))
  }
}

// ---------------------------------------------------------------------------
// Arithmetic (delegates to faer/mat)
// ---------------------------------------------------------------------------

/// Element-wise matrix addition.
pub fn add(a: Matrix, b: Matrix) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_same_dimensions(a, b))
  mat.add(a.rows, a.cols, a.data, b.data)
  |> result.map(fn(data) { Matrix(rows: a.rows, cols: a.cols, data: data) })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Element-wise matrix subtraction.
pub fn subtract(a: Matrix, b: Matrix) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_same_dimensions(a, b))
  mat.subtract(a.rows, a.cols, a.data, b.data)
  |> result.map(fn(data) { Matrix(rows: a.rows, cols: a.cols, data: data) })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Scalar multiplication of a matrix.
pub fn scale(matrix: Matrix, scalar: Float) -> Result(Matrix, MatrixError) {
  mat.scale(matrix.rows, matrix.cols, matrix.data, scalar)
  |> result.map(fn(data) {
    Matrix(rows: matrix.rows, cols: matrix.cols, data: data)
  })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Matrix multiplication.
pub fn multiply(a: Matrix, b: Matrix) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_multipliable(a, b))
  mat.multiply(a.rows, a.cols, a.data, b.rows, b.cols, b.data)
  |> result.map(fn(data) { Matrix(rows: a.rows, cols: b.cols, data: data) })
  |> result.map_error(nif_error_to_matrix_error)
}

// ---------------------------------------------------------------------------
// Utilities: reshape, stack, to_string
// ---------------------------------------------------------------------------

/// Reshape a matrix to new dimensions. Total element count must match.
pub fn reshape(
  m: Matrix,
  new_rows: Int,
  new_cols: Int,
) -> Result(Matrix, MatrixError) {
  let old_total = m.rows * m.cols
  let new_total = new_rows * new_cols
  case new_total == old_total && new_rows > 0 && new_cols > 0 {
    True -> {
      let elements = list.flatten(to_list(m))
      let data = pack_to_column_major(elements, new_rows, new_cols)
      Ok(Matrix(rows: new_rows, cols: new_cols, data: data))
    }
    False ->
      Error(InvalidDimensions(
        "Cannot reshape "
        <> int.to_string(m.rows)
        <> "x"
        <> int.to_string(m.cols)
        <> " to "
        <> int.to_string(new_rows)
        <> "x"
        <> int.to_string(new_cols),
      ))
  }
}

fn pack_to_column_major(elements: List(Float), rows: Int, cols: Int) -> BitArray {
  list.fold(list.range(0, cols - 1), <<>>, fn(acc, col) {
    list.fold(list.range(0, rows - 1), acc, fn(inner_acc, row) {
      let idx = row * cols + col
      let val = list_at(elements, idx)
      <<inner_acc:bits, val:float-little-size(64)>>
    })
  })
}

fn list_at(lst: List(a), index: Int) -> a {
  case list.drop(lst, index) {
    [x, ..] -> x
    _ -> panic as "list_at: index out of bounds"
  }
}

/// Vertically stack two matrices (top on bottom). Must have same column count.
pub fn vstack(top: Matrix, bottom: Matrix) -> Result(Matrix, MatrixError) {
  case top.cols == bottom.cols {
    False ->
      Error(DimensionMismatch(
        "vstack: column count mismatch: "
        <> int.to_string(top.cols)
        <> " vs "
        <> int.to_string(bottom.cols),
      ))
    True -> {
      let cols = top.cols
      let new_rows = top.rows + bottom.rows
      let data =
        list.fold(list.range(0, cols - 1), <<>>, fn(acc, col) {
          let top_col = extract_col_bits(top.data, col, top.rows)
          let bottom_col = extract_col_bits(bottom.data, col, bottom.rows)
          <<acc:bits, top_col:bits, bottom_col:bits>>
        })
      Ok(Matrix(rows: new_rows, cols: cols, data: data))
    }
  }
}

/// Horizontally stack two matrices (left next to right). Must have same row count.
pub fn hstack(left: Matrix, right: Matrix) -> Result(Matrix, MatrixError) {
  case left.rows == right.rows {
    False ->
      Error(DimensionMismatch(
        "hstack: row count mismatch: "
        <> int.to_string(left.rows)
        <> " vs "
        <> int.to_string(right.rows),
      ))
    True -> {
      let rows = left.rows
      let new_cols = left.cols + right.cols
      let data = <<left.data:bits, right.data:bits>>
      Ok(Matrix(rows: rows, cols: new_cols, data: data))
    }
  }
}

fn extract_col_bits(data: BitArray, col: Int, rows: Int) -> BitArray {
  list.fold(list.range(0, rows - 1), <<>>, fn(acc, row) {
    let index = col * rows + row
    let val = read_float_at(data, index)
    <<acc:bits, val:float-little-size(64)>>
  })
}

/// Convert matrix to a formatted string for display.
pub fn to_string(matrix: Matrix) -> String {
  let rows = to_list(matrix)
  let formatted =
    list.map(rows, fn(row) {
      list.map(row, fn(val) { float.to_string(val) })
      |> string.join(" ")
    })
  string.join(formatted, "\n")
}

// ---------------------------------------------------------------------------
// Views & Slicing
// ---------------------------------------------------------------------------

/// Extract a submatrix from the matrix.
pub fn slice(
  matrix: Matrix,
  row_start: Int,
  row_count: Int,
  col_start: Int,
  col_count: Int,
) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_slice_bounds(
    matrix,
    row_start,
    row_count,
    col_start,
    col_count,
  ))
  let data =
    list.fold(list.range(0, col_count - 1), <<>>, fn(acc, col_offset) {
      let col = col_start + col_offset
      let col_data =
        list.fold(list.range(0, row_count - 1), <<>>, fn(inner_acc, row_offset) {
          let row = row_start + row_offset
          let index = col * matrix.rows + row
          let val = read_float_at(matrix.data, index)
          <<inner_acc:bits, val:float-little-size(64)>>
        })
      <<acc:bits, col_data:bits>>
    })
  Ok(Matrix(rows: row_count, cols: col_count, data: data))
}

fn validate_slice_bounds(
  matrix: Matrix,
  row_start: Int,
  row_count: Int,
  col_start: Int,
  col_count: Int,
) -> Result(Nil, MatrixError) {
  let row_end = row_start + row_count
  let col_end = col_start + col_count
  case
    row_start >= 0
    && row_count > 0
    && col_start >= 0
    && col_count > 0
    && row_end <= matrix.rows
    && col_end <= matrix.cols
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "slice: invalid bounds for " <> dim_string(matrix) <> " matrix",
      ))
  }
}

/// Extract a single row as a list of floats.
pub fn row(matrix: Matrix, index: Int) -> Result(List(Float), MatrixError) {
  case index >= 0 && index < matrix.rows {
    True -> {
      let result =
        list.map(list.range(0, matrix.cols - 1), fn(col) {
          read_float_at(matrix.data, col * matrix.rows + index)
        })
      Ok(result)
    }
    False ->
      Error(InvalidDimensions(
        "row index "
        <> int.to_string(index)
        <> " out of bounds for "
        <> dim_string(matrix)
        <> " matrix",
      ))
  }
}

/// Extract a single column as a list of floats.
pub fn col(matrix: Matrix, index: Int) -> Result(List(Float), MatrixError) {
  case index >= 0 && index < matrix.cols {
    True -> {
      let result =
        list.map(list.range(0, matrix.rows - 1), fn(row) {
          read_float_at(matrix.data, index * matrix.rows + row)
        })
      Ok(result)
    }
    False ->
      Error(InvalidDimensions(
        "column index "
        <> int.to_string(index)
        <> " out of bounds for "
        <> dim_string(matrix)
        <> " matrix",
      ))
  }
}

// ---------------------------------------------------------------------------
// Functional Transformations
// ---------------------------------------------------------------------------

/// Apply a function to each element of the matrix.
pub fn map(matrix: Matrix, f: fn(Float) -> Float) -> Matrix {
  let new_data =
    list.fold(list.range(0, matrix.rows * matrix.cols - 1), <<>>, fn(acc, i) {
      let val = read_float_at(matrix.data, i)
      <<acc:bits, f(val):float-little-size(64)>>
    })
  Matrix(rows: matrix.rows, cols: matrix.cols, data: new_data)
}

/// Fold over all elements of the matrix in column-major order.
pub fn fold(matrix: Matrix, acc: a, f: fn(a, Float) -> a) -> a {
  list.fold(list.range(0, matrix.rows * matrix.cols - 1), acc, fn(current, i) {
    let val = read_float_at(matrix.data, i)
    f(current, val)
  })
}

/// Fold over all elements with their row and column indices.
/// Elements are visited in column-major order.
pub fn fold_with_indices(
  matrix: Matrix,
  acc: a,
  f: fn(a, Int, Int, Float) -> a,
) -> a {
  list.fold(list.range(0, matrix.cols - 1), acc, fn(col_acc, col) {
    list.fold(list.range(0, matrix.rows - 1), col_acc, fn(row_acc, row) {
      let index = col * matrix.rows + row
      let val = read_float_at(matrix.data, index)
      f(row_acc, row, col, val)
    })
  })
}

/// Apply a binary function element-wise to two matrices.
pub fn zip_with(
  a: Matrix,
  b: Matrix,
  f: fn(Float, Float) -> Float,
) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_same_dimensions(a, b))
  let new_data =
    list.fold(list.range(0, a.rows * a.cols - 1), <<>>, fn(acc, i) {
      let va = read_float_at(a.data, i)
      let vb = read_float_at(b.data, i)
      <<acc:bits, f(va, vb):float-little-size(64)>>
    })
  Ok(Matrix(rows: a.rows, cols: a.cols, data: new_data))
}
