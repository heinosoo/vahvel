//// Sparse matrix operations using CSC (Compressed Sparse Column) format.
////
//// Sparse matrices efficiently store matrices with many zero elements by
//// only storing non-zero values. This module uses CSC format, which is
//// optimal for column-wise operations and arithmetic with sparse matrices.
////
//// ## Creating sparse matrices
////
//// Use `from_triplets` to create from coordinate format:
////
//// ```gleam
//// let assert Ok(s) = from_triplets(3, 3, [#(0, 0, 1.0), #(1, 1, 2.0)])
//// ```
////
//// Or convert from dense: `from_dense(dense_matrix)`
////
//// ## Conversions
////
//// - `to_dense(s)` / `from_dense(m)` — convert between sparse and dense
//// - `to_triplets(s)` — extract as list of (row, col, value)
////
//// ## Operations
////
//// Arithmetic: `add`, `subtract`, `scale`, `multiply`
////
//// Matrix-vector: `multiply_dense(sparse, dense)` — sparse-dense multiplication
////
//// Transformations: `transpose`, `map`, `fold`, `fold_with_indices`
////
//// Access: `get(s, row, col)`, `row(s, index)`, `col(s, index)`
////
//// ## Error handling
////
//// Operations return `Result(a, SparseError)`. Common errors:
//// - `EmptyInput` — input was empty
//// - `InvalidDimensions` — dimensions were invalid
//// - `IndexOutOfBounds` — index outside matrix bounds

import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import waffle/internal/faer as nif
import waffle/internal/range
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

fn pack_indices(indices: List(Int)) -> BitArray {
  list.fold(indices, <<>>, fn(acc, x) { <<acc:bits, x:int-little-size(64)>> })
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

  let row_indices = pack_indices(list.map(triplets, fn(t) { t.0 }))
  let col_indices = pack_indices(list.map(triplets, fn(t) { t.1 }))
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

      Ok(find_float_in_col(
        matrix.row_indices,
        matrix.values,
        row,
        col_start,
        col_end,
      ))
    }
  }
}

/// Convert a sparse matrix to a list of triplets (row, col, value).
pub fn to_triplets(matrix: SparseMatrix) -> List(#(Int, Int, Float)) {
  let col_ptr = matrix.col_ptr
  let row_indices = matrix.row_indices
  let values = matrix.values
  let cols = matrix.cols

  int.range(from: cols - 1, to: -1, with: [], run: fn(acc, col) {
    let col_start = read_int_at(col_ptr, col)
    let col_end = read_int_at(col_ptr, col + 1)

    int.range(
      from: col_end - 1,
      to: col_start - 1,
      with: acc,
      run: fn(inner_acc, idx) {
        let row = read_int_at(row_indices, idx)
        let value = read_float_at(values, idx)
        [#(row, col, value), ..inner_acc]
      },
    )
  })
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
  use _ <- result.try(validate_same_dimensions(a, b))
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

/// Subtract two sparse matrices element-wise (a - b).
/// Returns an error if dimensions do not match.
pub fn subtract(
  a: SparseMatrix,
  b: SparseMatrix,
) -> Result(SparseMatrix, SparseError) {
  use _ <- result.try(validate_same_dimensions(a, b))
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
/// Values that become 0.0 after mapping are removed.
pub fn map(matrix: SparseMatrix, f: fn(Float) -> Float) -> SparseMatrix {
  let #(new_values, has_zeros) =
    int.range(from: 0, to: matrix.nnz, with: #(<<>>, False), run: fn(acc, i) {
      let #(bits, any_zero) = acc
      let val = f(read_float_at(matrix.values, i))
      #(<<bits:bits, val:float-little-size(64)>>, any_zero || val == 0.0)
    })
  case has_zeros {
    False -> SparseMatrix(..matrix, values: new_values)
    True -> {
      let triplets = to_triplets(SparseMatrix(..matrix, values: new_values))
      let filtered = list.filter(triplets, fn(t) { t.2 != 0.0 })
      case filtered {
        [] -> empty_sparse(matrix.rows, matrix.cols)
        _ ->
          from_triplets(matrix.rows, matrix.cols, filtered)
          |> result.unwrap(empty_sparse(matrix.rows, matrix.cols))
      }
    }
  }
}

fn empty_sparse(rows: Int, cols: Int) -> SparseMatrix {
  let col_ptr =
    int.range(from: 0, to: cols + 1, with: <<>>, run: fn(acc, _) {
      <<acc:bits, 0:int-little-size(64)>>
    })
  SparseMatrix(
    rows: rows,
    cols: cols,
    nnz: 0,
    col_ptr: col_ptr,
    row_indices: <<>>,
    values: <<>>,
  )
}

/// Fold over all non-zero elements of the sparse matrix.
/// Elements are visited in column-major order.
pub fn fold(matrix: SparseMatrix, acc: a, f: fn(a, Float) -> a) -> a {
  let values = matrix.values
  let nnz = matrix.nnz

  int.range(from: 0, to: nnz, with: acc, run: fn(current, i) {
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
  int.range(from: 0, to: matrix.cols, with: acc, run: fn(col_acc, col) {
    let col_start = read_int_at(matrix.col_ptr, col)
    let col_end = read_int_at(matrix.col_ptr, col + 1)
    int.range(from: col_start, to: col_end, with: col_acc, run: fn(row_acc, i) {
      let row = read_int_at(matrix.row_indices, i)
      let val = read_float_at(matrix.values, i)
      f(row_acc, row, col, val)
    })
  })
}

fn find_float_in_col(
  row_indices: BitArray,
  values: BitArray,
  target: Int,
  start: Int,
  end: Int,
) -> Float {
  case start >= end {
    True -> 0.0
    False ->
      case read_int_at(row_indices, start) == target {
        True -> read_float_at(values, start)
        False -> find_float_in_col(row_indices, values, target, start + 1, end)
      }
  }
}

/// Extract a single row as a list of floats.
/// Returns 0.0 for elements not explicitly stored.
pub fn row(
  matrix: SparseMatrix,
  index: Int,
) -> Result(List(Float), SparseError) {
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
        range.map(0, matrix.cols, fn(col) {
          let col_start = read_int_at(matrix.col_ptr, col)
          let col_end = read_int_at(matrix.col_ptr, col + 1)
          find_float_in_col(
            matrix.row_indices,
            matrix.values,
            index,
            col_start,
            col_end,
          )
        })
      Ok(result)
    }
  }
}

fn build_dense_col(
  row_indices: BitArray,
  values: BitArray,
  entry_idx: Int,
  entry_end: Int,
  current_row: Int,
  total_rows: Int,
  acc: List(Float),
) -> List(Float) {
  case current_row >= total_rows {
    True -> list.reverse(acc)
    False -> {
      let entry_row = case entry_idx < entry_end {
        True -> read_int_at(row_indices, entry_idx)
        False -> total_rows
      }
      case entry_row == current_row {
        True ->
          build_dense_col(
            row_indices,
            values,
            entry_idx + 1,
            entry_end,
            current_row + 1,
            total_rows,
            [read_float_at(values, entry_idx), ..acc],
          )
        False ->
          build_dense_col(
            row_indices,
            values,
            entry_idx,
            entry_end,
            current_row + 1,
            total_rows,
            [0.0, ..acc],
          )
      }
    }
  }
}

/// Extract a single column as a list of floats.
/// Returns 0.0 for elements not explicitly stored.
pub fn col(
  matrix: SparseMatrix,
  index: Int,
) -> Result(List(Float), SparseError) {
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
      let col_start = read_int_at(matrix.col_ptr, index)
      let col_end = read_int_at(matrix.col_ptr, index + 1)
      Ok(
        build_dense_col(
          matrix.row_indices,
          matrix.values,
          col_start,
          col_end,
          0,
          matrix.rows,
          [],
        ),
      )
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
  use _ <- result.try(validate_same_dimensions(a, b))
  use a_dense <- result.try(to_dense(a))
  use b_dense <- result.try(to_dense(b))
  use zipped <- result.try(
    matrix.zip_with(a_dense, b_dense, f)
    |> result.map_error(fn(e) { InvalidDimensions(matrix_error_to_string(e)) }),
  )
  from_dense(zipped)
}

fn validate_same_dimensions(
  a: SparseMatrix,
  b: SparseMatrix,
) -> Result(Nil, SparseError) {
  case a.rows == b.rows && a.cols == b.cols {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "Dimension mismatch: "
        <> int.to_string(a.rows)
        <> "x"
        <> int.to_string(a.cols)
        <> " vs "
        <> int.to_string(b.rows)
        <> "x"
        <> int.to_string(b.cols),
      ))
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

@internal
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
      <> float.to_string(val)
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

@internal
pub fn to_csc_data(
  matrix: SparseMatrix,
) -> #(Int, BitArray, BitArray, BitArray) {
  #(matrix.nnz, matrix.col_ptr, matrix.row_indices, matrix.values)
}
