import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import waffle/internal/faer/sparse as nif
import waffle/matrix

/// Errors that can occur when creating or manipulating sparse matrices.
pub type SparseError {
  /// Input was an empty list.
  EmptyInput
  /// Invalid matrix dimensions.
  InvalidDimensions(String)
  /// Index was outside matrix bounds.
  IndexOutOfBounds(row: Int, col: Int, rows: Int, cols: Int)
}

/// A sparse matrix stored in CSC (Compressed Sparse Column) format.
/// Efficient for matrices with many zero elements.
pub opaque type SparseMatrix {
  SparseMatrix(
    rows: Int,
    cols: Int,
    nnz: Int,
    col_ptr: BitArray,
    row_indices: BitArray,
    values: BitArray,
  )
}

fn pack_ints(ints: List(Int)) -> BitArray {
  list.fold(ints, <<>>, fn(acc, x) { <<acc:bits, x:int-little-size(64)>> })
}

fn pack_floats(floats: List(Float)) -> BitArray {
  list.fold(floats, <<>>, fn(acc, x) { <<acc:bits, x:float-little-size(64)>> })
}

fn read_int_at(data: BitArray, index: Int) -> Int {
  let offset = index * 8
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:int-little-size(64)>>) -> x
    _ -> 0
  }
}

fn read_float_at(data: BitArray, index: Int) -> Float {
  let offset = index * 8
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:float-little-size(64)>>) -> x
    _ -> 0.0
  }
}

/// Create a sparse matrix from a list of triplets (row, col, value).
/// Indices are 0-based. Duplicate entries at the same position are summed.
pub fn from_triplets(
  rows: Int,
  cols: Int,
  triplets: List(#(Int, Int, Float)),
) -> Result(SparseMatrix, SparseError) {
  use _ <- result.try(validate_dimensions(rows, cols))
  use _ <- result.try(validate_non_empty(triplets))
  use _ <- result.try(validate_triplet_indices(triplets, rows, cols))

  let row_indices = pack_ints(list.map(triplets, fn(t) { t.0 }))
  let col_indices = pack_ints(list.map(triplets, fn(t) { t.1 }))
  let values = pack_floats(list.map(triplets, fn(t) { t.2 }))

  use #(nnz, col_ptr, row_idx, vals) <- result.try(
    nif.sparse_from_triplets(rows, cols, row_indices, col_indices, values)
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )

  Ok(SparseMatrix(
    rows: rows,
    cols: cols,
    nnz: nnz,
    col_ptr: col_ptr,
    row_indices: row_idx,
    values: vals,
  ))
}

fn validate_dimensions(rows: Int, cols: Int) -> Result(Nil, SparseError) {
  case rows > 0 && cols > 0 {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "Dimensions must be positive, got "
        <> int.to_string(rows)
        <> "x"
        <> int.to_string(cols),
      ))
  }
}

fn validate_non_empty(
  triplets: List(#(Int, Int, Float)),
) -> Result(Nil, SparseError) {
  case list.is_empty(triplets) {
    True -> Error(EmptyInput)
    False -> Ok(Nil)
  }
}

fn validate_triplet_indices(
  triplets: List(#(Int, Int, Float)),
  rows: Int,
  cols: Int,
) -> Result(Nil, SparseError) {
  list.try_each(triplets, fn(t) {
    let #(row, col, _) = t
    case row >= 0 && row < rows && col >= 0 && col < cols {
      True -> Ok(Nil)
      False ->
        Error(IndexOutOfBounds(row: row, col: col, rows: rows, cols: cols))
    }
  })
}

/// Get the dimensions of a sparse matrix as #(rows, cols).
pub fn dims(matrix: SparseMatrix) -> #(Int, Int) {
  #(matrix.rows, matrix.cols)
}

/// Get the number of non-zero elements in a sparse matrix.
pub fn nnz(matrix: SparseMatrix) -> Int {
  matrix.nnz
}

/// Get the number of rows in a sparse matrix.
pub fn rows(matrix: SparseMatrix) -> Int {
  matrix.rows
}

/// Get the number of columns in a sparse matrix.
pub fn cols(matrix: SparseMatrix) -> Int {
  matrix.cols
}

/// Convert a sparse matrix to a dense matrix.
pub fn to_dense(sparse: SparseMatrix) -> Result(matrix.Matrix, SparseError) {
  use dense_bin <- result.try(
    nif.sparse_to_dense(
      sparse.rows,
      sparse.cols,
      sparse.nnz,
      sparse.col_ptr,
      sparse.row_indices,
      sparse.values,
    )
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )

  matrix.from_binary(sparse.rows, sparse.cols, dense_bin)
  |> result.map_error(fn(_) {
    InvalidDimensions("Failed to create dense matrix")
  })
}

/// Create a sparse matrix from a dense matrix. Zero elements are not stored.
pub fn from_dense(dense: matrix.Matrix) -> Result(SparseMatrix, SparseError) {
  let rows = matrix.rows(dense)
  let cols = matrix.cols(dense)
  let data = matrix.to_binary(dense)

  use #(nnz, col_ptr, row_idx, values) <- result.try(
    nif.sparse_from_dense(rows, cols, data)
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )

  Ok(SparseMatrix(
    rows: rows,
    cols: cols,
    nnz: nnz,
    col_ptr: col_ptr,
    row_indices: row_idx,
    values: values,
  ))
}

/// Transpose a sparse matrix (swap rows and columns).
pub fn transpose(matrix: SparseMatrix) -> Result(SparseMatrix, SparseError) {
  use #(new_rows, new_cols, nnz, col_ptr, row_idx, values) <- result.try(
    nif.sparse_transpose(
      matrix.rows,
      matrix.cols,
      matrix.nnz,
      matrix.col_ptr,
      matrix.row_indices,
      matrix.values,
    )
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )

  Ok(SparseMatrix(
    rows: new_rows,
    cols: new_cols,
    nnz: nnz,
    col_ptr: col_ptr,
    row_indices: row_idx,
    values: values,
  ))
}

/// Multiply a sparse matrix by a dense matrix.
/// Returns an error if inner dimensions do not match.
pub fn multiply_dense(
  sparse: SparseMatrix,
  dense: matrix.Matrix,
) -> Result(matrix.Matrix, SparseError) {
  case sparse.cols == matrix.rows(dense) {
    False ->
      Error(InvalidDimensions(
        "Cannot multiply "
        <> int.to_string(sparse.rows)
        <> "x"
        <> int.to_string(sparse.cols)
        <> " sparse by "
        <> int.to_string(matrix.rows(dense))
        <> "x"
        <> int.to_string(matrix.cols(dense))
        <> " dense: inner dimensions do not match",
      ))
    True -> {
      use result_bin <- result.try(
        nif.sparse_multiply_dense(
          sparse.rows,
          sparse.cols,
          sparse.nnz,
          sparse.col_ptr,
          sparse.row_indices,
          sparse.values,
          matrix.rows(dense),
          matrix.cols(dense),
          matrix.to_binary(dense),
        )
        |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
      )

      matrix.from_binary(sparse.rows, matrix.cols(dense), result_bin)
      |> result.map_error(fn(_) {
        InvalidDimensions("Failed to create result matrix")
      })
    }
  }
}

/// Get the element at the given row and column (0-indexed).
/// Returns 0.0 for elements not explicitly stored.
pub fn get(
  matrix: SparseMatrix,
  row: Int,
  col: Int,
) -> Result(Float, SparseError) {
  case row >= 0 && row < matrix.rows && col >= 0 && col < matrix.cols {
    False ->
      Error(IndexOutOfBounds(
        row: row,
        col: col,
        rows: matrix.rows,
        cols: matrix.cols,
      ))
    True -> {
      let col_start = read_int_at(matrix.col_ptr, col)
      let col_end = read_int_at(matrix.col_ptr, col + 1)

      find_value_in_column(
        matrix.row_indices,
        matrix.values,
        row,
        col_start,
        col_end,
      )
    }
  }
}

fn find_value_in_column(
  row_indices: BitArray,
  values: BitArray,
  target_row: Int,
  start: Int,
  end: Int,
) -> Result(Float, SparseError) {
  case start >= end {
    True -> Ok(0.0)
    False -> {
      let row = read_int_at(row_indices, start)
      case row == target_row {
        True -> Ok(read_float_at(values, start))
        False ->
          find_value_in_column(row_indices, values, target_row, start + 1, end)
      }
    }
  }
}

/// Convert a sparse matrix to a list of triplets (row, col, value).
pub fn to_triplets(matrix: SparseMatrix) -> List(#(Int, Int, Float)) {
  let col_ptr = matrix.col_ptr
  let row_indices = matrix.row_indices
  let values = matrix.values
  let cols = matrix.cols

  list.fold(list.range(0, cols - 1), [], fn(acc, col) {
    let col_start = read_int_at(col_ptr, col)
    let col_end = read_int_at(col_ptr, col + 1)

    list.fold(list.range(col_start, col_end - 1), acc, fn(inner_acc, idx) {
      let row = read_int_at(row_indices, idx)
      let value = read_float_at(values, idx)
      [#(row, col, value), ..inner_acc]
    })
  })
  |> list.reverse()
}

/// Multiply two sparse matrices.
/// Returns an error if inner dimensions do not match.
pub fn multiply(
  a: SparseMatrix,
  b: SparseMatrix,
) -> Result(SparseMatrix, SparseError) {
  case a.cols == b.rows {
    False ->
      Error(InvalidDimensions(
        "Cannot multiply "
        <> int.to_string(a.rows)
        <> "x"
        <> int.to_string(a.cols)
        <> " sparse by "
        <> int.to_string(b.rows)
        <> "x"
        <> int.to_string(b.cols)
        <> " sparse: inner dimensions do not match",
      ))
    True -> {
      use #(rows, cols, nnz, col_ptr, row_idx, values) <- result.try(
        nif.sparse_multiply(
          a.rows,
          a.cols,
          a.nnz,
          a.col_ptr,
          a.row_indices,
          a.values,
          b.rows,
          b.cols,
          b.nnz,
          b.col_ptr,
          b.row_indices,
          b.values,
        )
        |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
      )

      Ok(SparseMatrix(
        rows: rows,
        cols: cols,
        nnz: nnz,
        col_ptr: col_ptr,
        row_indices: row_idx,
        values: values,
      ))
    }
  }
}

/// Add two sparse matrices element-wise.
/// Returns an error if dimensions do not match.
pub fn add(
  a: SparseMatrix,
  b: SparseMatrix,
) -> Result(SparseMatrix, SparseError) {
  case a.rows == b.rows && a.cols == b.cols {
    False ->
      Error(InvalidDimensions(
        "Cannot add "
        <> int.to_string(a.rows)
        <> "x"
        <> int.to_string(a.cols)
        <> " sparse to "
        <> int.to_string(b.rows)
        <> "x"
        <> int.to_string(b.cols)
        <> " sparse: dimensions do not match",
      ))
    True -> {
      use #(rows, cols, nnz, col_ptr, row_idx, values) <- result.try(
        nif.sparse_add(
          a.rows,
          a.cols,
          a.nnz,
          a.col_ptr,
          a.row_indices,
          a.values,
          b.rows,
          b.cols,
          b.nnz,
          b.col_ptr,
          b.row_indices,
          b.values,
        )
        |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
      )

      Ok(SparseMatrix(
        rows: rows,
        cols: cols,
        nnz: nnz,
        col_ptr: col_ptr,
        row_indices: row_idx,
        values: values,
      ))
    }
  }
}

/// Subtract two sparse matrices element-wise (a - b).
/// Returns an error if dimensions do not match.
pub fn subtract(
  a: SparseMatrix,
  b: SparseMatrix,
) -> Result(SparseMatrix, SparseError) {
  case a.rows == b.rows && a.cols == b.cols {
    False ->
      Error(InvalidDimensions(
        "Cannot subtract "
        <> int.to_string(b.rows)
        <> "x"
        <> int.to_string(b.cols)
        <> " sparse from "
        <> int.to_string(a.rows)
        <> "x"
        <> int.to_string(a.cols)
        <> " sparse: dimensions do not match",
      ))
    True -> {
      use #(rows, cols, nnz, col_ptr, row_idx, values) <- result.try(
        nif.sparse_subtract(
          a.rows,
          a.cols,
          a.nnz,
          a.col_ptr,
          a.row_indices,
          a.values,
          b.rows,
          b.cols,
          b.nnz,
          b.col_ptr,
          b.row_indices,
          b.values,
        )
        |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
      )

      Ok(SparseMatrix(
        rows: rows,
        cols: cols,
        nnz: nnz,
        col_ptr: col_ptr,
        row_indices: row_idx,
        values: values,
      ))
    }
  }
}

/// Scale all non-zero elements of a sparse matrix by a scalar.
pub fn scale(
  matrix: SparseMatrix,
  scalar: Float,
) -> Result(SparseMatrix, SparseError) {
  use #(rows, cols, nnz, col_ptr, row_idx, values) <- result.try(
    nif.sparse_scale(
      matrix.rows,
      matrix.cols,
      matrix.nnz,
      matrix.col_ptr,
      matrix.row_indices,
      matrix.values,
      scalar,
    )
    |> result.map_error(fn(msg) { InvalidDimensions(msg) }),
  )

  Ok(SparseMatrix(
    rows: rows,
    cols: cols,
    nnz: nnz,
    col_ptr: col_ptr,
    row_indices: row_idx,
    values: values,
  ))
}

/// Apply a function to each non-zero element of the sparse matrix.
/// Returns a new sparse matrix with transformed values.
pub fn map(matrix: SparseMatrix, f: fn(Float) -> Float) -> SparseMatrix {
  let triplets = to_triplets(matrix)
  let mapped =
    list.map(triplets, fn(t) {
      let #(row, col, val) = t
      #(row, col, f(val))
    })

  case from_triplets(matrix.rows, matrix.cols, mapped) {
    Ok(result) -> result
    Error(_) -> matrix
  }
}

/// Fold over all non-zero elements of the sparse matrix.
/// Elements are visited in column-major order.
pub fn fold(matrix: SparseMatrix, acc: a, f: fn(a, Float) -> a) -> a {
  let values = matrix.values
  let nnz = matrix.nnz

  list.fold(list.range(0, nnz - 1), acc, fn(current, i) {
    let val = read_float_at(values, i)
    f(current, val)
  })
}

/// Fold over all non-zero elements with their indices.
/// The function receives (accumulator, row, col, value).
pub fn fold_with_indices(
  matrix: SparseMatrix,
  acc: a,
  f: fn(a, Int, Int, Float) -> a,
) -> a {
  let triplets = to_triplets(matrix)
  list.fold(triplets, acc, fn(current, t) {
    let #(row, col, val) = t
    f(current, row, col, val)
  })
}

/// Extract a single row as a list of floats.
/// Returns 0.0 for elements not explicitly stored.
pub fn row(matrix: SparseMatrix, index: Int) -> Result(List(Float), SparseError) {
  case index >= 0 && index < matrix.rows {
    False ->
      Error(InvalidDimensions(
        "row index "
        <> int.to_string(index)
        <> " out of bounds for "
        <> int.to_string(matrix.rows)
        <> "x"
        <> int.to_string(matrix.cols)
        <> " sparse matrix",
      ))
    True -> {
      let result =
        list.map(list.range(0, matrix.cols - 1), fn(col) {
          let assert Ok(v) = get(matrix, index, col)
          v
        })
      Ok(result)
    }
  }
}

/// Extract a single column as a list of floats.
/// Returns 0.0 for elements not explicitly stored.
pub fn col(matrix: SparseMatrix, index: Int) -> Result(List(Float), SparseError) {
  case index >= 0 && index < matrix.cols {
    False ->
      Error(InvalidDimensions(
        "column index "
        <> int.to_string(index)
        <> " out of bounds for "
        <> int.to_string(matrix.rows)
        <> "x"
        <> int.to_string(matrix.cols)
        <> " sparse matrix",
      ))
    True -> {
      let result =
        list.map(list.range(0, matrix.rows - 1), fn(row) {
          let assert Ok(v) = get(matrix, row, index)
          v
        })
      Ok(result)
    }
  }
}

/// Apply a binary function element-wise to two sparse matrices.
/// The result is computed by converting to dense, applying the function,
/// and converting back to sparse.
pub fn zip_with(
  a: SparseMatrix,
  b: SparseMatrix,
  f: fn(Float, Float) -> Float,
) -> Result(SparseMatrix, SparseError) {
  case a.rows == b.rows && a.cols == b.cols {
    False ->
      Error(InvalidDimensions(
        "Cannot zip "
        <> int.to_string(a.rows)
        <> "x"
        <> int.to_string(a.cols)
        <> " sparse with "
        <> int.to_string(b.rows)
        <> "x"
        <> int.to_string(b.cols)
        <> " sparse: dimensions do not match",
      ))
    True -> {
      case to_dense(a), to_dense(b) {
        Ok(a_dense), Ok(b_dense) -> {
          case matrix.zip_with(a_dense, b_dense, f) {
            Ok(zipped) -> from_dense(zipped)
            Error(e) -> Error(InvalidDimensions(matrix_error_to_string(e)))
          }
        }
        Error(e), _ -> Error(e)
        _, Error(e) -> Error(e)
      }
    }
  }
}

fn matrix_error_to_string(error: matrix.MatrixError) -> String {
  case error {
    matrix.EmptyInput -> "Matrix error: empty input"
    matrix.EmptyRow -> "Matrix error: empty row"
    matrix.RaggedRows -> "Matrix error: ragged rows"
    matrix.InvalidDimensions(msg) -> "Matrix error: " <> msg
    matrix.DimensionMismatch(msg) -> "Matrix error: " <> msg
    matrix.SingularMatrix -> "Matrix error: singular matrix"
  }
}

/// Validates that a sparse matrix is square. Returns an error if rows != cols.
pub fn validate_square(matrix: SparseMatrix) -> Result(Nil, SparseError) {
  case matrix.rows == matrix.cols {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "Expected square matrix, got "
        <> int.to_string(matrix.rows)
        <> "x"
        <> int.to_string(matrix.cols),
      ))
  }
}

/// Convert sparse matrix to a string showing non-zero entries.
/// Format: "(row, col): value" per line.
pub fn to_string(matrix: SparseMatrix) -> String {
  let triplets = to_triplets(matrix)
  let lines =
    list.map(triplets, fn(t) {
      let #(row, col, val) = t
      "("
      <> int.to_string(row)
      <> ", "
      <> int.to_string(col)
      <> "): "
      <> float_to_string(val)
    })
  case lines {
    [] ->
      "SparseMatrix "
      <> int.to_string(matrix.rows)
      <> "x"
      <> int.to_string(matrix.cols)
      <> " (empty)"
    _ ->
      "SparseMatrix "
      <> int.to_string(matrix.rows)
      <> "x"
      <> int.to_string(matrix.cols)
      <> ":\n"
      <> string.join(lines, "\n")
  }
}

fn float_to_string(x: Float) -> String {
  float.to_string(x)
}
