import faer/linalg/solvers
import faer/mat
import gleam/bit_array
import gleam/float
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
  /// Matrix dimensions do not match for the operation.
  DimensionMismatch(String)
  /// Matrix is singular (not invertible).
  SingularMatrix
}

/// A matrix stored in column-major order as f64 values.
pub opaque type Matrix {
  Matrix(rows: Int, cols: Int, data: BitArray)
}

/// LU decomposition with partial pivoting: PA = LU.
pub type LU {
  LU(l: Matrix, u: Matrix, pivot: List(Int))
}

/// Thin QR decomposition: A = QR.
pub type QR {
  QR(q: Matrix, r: Matrix)
}

/// Thin SVD: A = U * diag(S) * transpose(V).
pub type SVD {
  SVD(u: Matrix, singular_values: List(Float), v: Matrix)
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

fn unpack_floats(data: BitArray, count: Int) -> List(Float) {
  list.map(list.range(0, count - 1), fn(i) { read_float_at(data, i) })
}

fn validate_square(matrix: Matrix) -> Result(Nil, MatrixError) {
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

fn validate_symmetric(matrix: Matrix) -> Result(Nil, MatrixError) {
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
@internal
pub fn to_binary(matrix: Matrix) -> BitArray {
  matrix.data
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
// Properties (delegates to faer/linalg/solvers)
// ---------------------------------------------------------------------------

/// Compute the determinant of a square matrix.
pub fn determinant(matrix: Matrix) -> Result(Float, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  solvers.determinant(matrix.rows, matrix.data)
  |> result.map_error(nif_error_to_matrix_error)
}

/// Compute the inverse of a square matrix.
pub fn inverse(matrix: Matrix) -> Result(Matrix, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows
  solvers.inverse(n, matrix.data)
  |> result.map(fn(data) { Matrix(rows: n, cols: n, data: data) })
  |> result.map_error(nif_error_to_matrix_error)
}

// ---------------------------------------------------------------------------
// Decompositions (delegates to faer/linalg/solvers)
// ---------------------------------------------------------------------------

/// LU decomposition with partial pivoting: PA = LU.
pub fn lu(matrix: Matrix) -> Result(LU, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows
  case solvers.lu(n, matrix.data) {
    Ok(#(#(l_r, l_c, l_bin), #(u_r, u_c, u_bin), #(piv_len, piv_bin))) -> {
      let pivot = unpack_pivot(piv_bin, piv_len)
      case from_binary(l_r, l_c, l_bin), from_binary(u_r, u_c, u_bin) {
        Ok(l), Ok(u) -> Ok(LU(l: l, u: u, pivot: pivot))
        _, _ -> Error(InvalidDimensions("Failed to construct LU matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

fn unpack_pivot(data: BitArray, count: Int) -> List(Int) {
  list.map(list.range(0, count - 1), fn(i) {
    let offset = i * 8
    case bit_array.slice(data, offset, 8) {
      Ok(<<v:little-size(64)>>) -> v
      _ -> 0
    }
  })
}

/// Thin QR decomposition: A = QR.
pub fn qr(matrix: Matrix) -> Result(QR, MatrixError) {
  case solvers.qr(matrix.rows, matrix.cols, matrix.data) {
    Ok(#(#(q_r, q_c, q_bin), #(r_r, r_c, r_bin))) -> {
      case from_binary(q_r, q_c, q_bin), from_binary(r_r, r_c, r_bin) {
        Ok(q), Ok(r) -> Ok(QR(q: q, r: r))
        _, _ -> Error(InvalidDimensions("Failed to construct QR matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Thin SVD: A = U * diag(S) * transpose(V).
pub fn svd(matrix: Matrix) -> Result(SVD, MatrixError) {
  case solvers.svd(matrix.rows, matrix.cols, matrix.data) {
    Ok(#(#(u_r, u_c, u_bin), #(s_len, s_bin), #(v_r, v_c, v_bin))) -> {
      let s_values = unpack_floats(s_bin, s_len)
      case from_binary(u_r, u_c, u_bin), from_binary(v_r, v_c, v_bin) {
        Ok(u), Ok(v) -> Ok(SVD(u: u, singular_values: s_values, v: v))
        _, _ -> Error(InvalidDimensions("Failed to construct SVD matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Eigenvalues of a symmetric matrix, in nondecreasing order.
pub fn symmetric_eigenvalues(matrix: Matrix) -> Result(List(Float), MatrixError) {
  use _ <- result.try(validate_square(matrix))
  use _ <- result.try(validate_symmetric(matrix))
  let n = matrix.rows
  case solvers.symmetric_eigenvalues(n, matrix.data) {
    Ok(eigenvalues_bin) -> Ok(unpack_floats(eigenvalues_bin, n))
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}
