import gleam/bit_array
import gleam/list
import gleam/result
import waffle/internal/faer/linalg/solvers
import waffle/matrix

/// LU decomposition with partial pivoting: PA = LU.
/// Contains the lower triangular matrix L, upper triangular matrix U,
/// and the pivot permutation as a list of row indices.
pub type LU {
  LU(l: matrix.Matrix, u: matrix.Matrix, pivot: List(Int))
}

/// Thin QR decomposition: A = QR.
/// Q is an orthogonal matrix with orthonormal columns.
/// R is an upper triangular matrix.
pub type QR {
  QR(q: matrix.Matrix, r: matrix.Matrix)
}

/// Thin SVD decomposition: A = U * diag(S) * V^T.
/// U has orthonormal columns, V has orthonormal columns,
/// and S contains the singular values in descending order.
pub type SVD {
  SVD(u: matrix.Matrix, singular_values: List(Float), v: matrix.Matrix)
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

fn unpack_floats(data: BitArray, count: Int) -> List(Float) {
  list.map(list.range(0, count - 1), fn(i) {
    let offset = i * 8
    case bit_array.slice(data, offset, 8) {
      Ok(<<x:float-little-size(64)>>) -> x
      _ -> 0.0
    }
  })
}

fn nif_error_to_matrix_error(msg: String) -> matrix.MatrixError {
  case msg {
    "Matrix is singular" <> _ -> matrix.SingularMatrix
    _ -> matrix.InvalidDimensions(msg)
  }
}

/// Compute the determinant of a square matrix.
/// Returns an error if the matrix is not square.
pub fn determinant(m: matrix.Matrix) -> Result(Float, matrix.MatrixError) {
  use _ <- result.try(matrix.validate_square(m))
  solvers.determinant(matrix.rows(m), matrix.to_binary(m))
  |> result.map_error(nif_error_to_matrix_error)
}

/// Compute the inverse of a square matrix.
/// Returns an error if the matrix is not square or is singular.
pub fn inverse(m: matrix.Matrix) -> Result(matrix.Matrix, matrix.MatrixError) {
  use _ <- result.try(matrix.validate_square(m))
  let n = matrix.rows(m)
  use data <- result.try(
    solvers.inverse(n, matrix.to_binary(m))
    |> result.map_error(nif_error_to_matrix_error),
  )
  matrix.from_binary(n, n, data)
  |> result.map_error(fn(err) { err })
}

/// Compute the LU decomposition with partial pivoting of a square matrix.
/// Returns PA = LU where P is the permutation matrix represented by the pivot.
pub fn lu(m: matrix.Matrix) -> Result(LU, matrix.MatrixError) {
  use _ <- result.try(matrix.validate_square(m))
  let n = matrix.rows(m)
  case solvers.lu(n, matrix.to_binary(m)) {
    Ok(#(#(l_r, l_c, l_bin), #(u_r, u_c, u_bin), #(piv_len, piv_bin))) -> {
      let pivot = unpack_pivot(piv_bin, piv_len)
      case
        matrix.from_binary(l_r, l_c, l_bin),
        matrix.from_binary(u_r, u_c, u_bin)
      {
        Ok(l), Ok(u) -> Ok(LU(l: l, u: u, pivot: pivot))
        _, _ ->
          Error(matrix.InvalidDimensions("Failed to construct LU matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Compute the thin QR decomposition of a matrix.
/// For an m×n matrix with m >= n, produces Q (m×n with orthonormal columns)
/// and R (n×n upper triangular).
pub fn qr(m: matrix.Matrix) -> Result(QR, matrix.MatrixError) {
  case solvers.qr(matrix.rows(m), matrix.cols(m), matrix.to_binary(m)) {
    Ok(#(#(q_r, q_c, q_bin), #(r_r, r_c, r_bin))) -> {
      case
        matrix.from_binary(q_r, q_c, q_bin),
        matrix.from_binary(r_r, r_c, r_bin)
      {
        Ok(q), Ok(r) -> Ok(QR(q: q, r: r))
        _, _ ->
          Error(matrix.InvalidDimensions("Failed to construct QR matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Compute the thin SVD decomposition of a matrix: A = U * diag(S) * V^T.
/// Singular values are returned in descending order.
pub fn svd(m: matrix.Matrix) -> Result(SVD, matrix.MatrixError) {
  case solvers.svd(matrix.rows(m), matrix.cols(m), matrix.to_binary(m)) {
    Ok(#(#(u_r, u_c, u_bin), #(s_len, s_bin), #(v_r, v_c, v_bin))) -> {
      let s_values = unpack_floats(s_bin, s_len)
      case
        matrix.from_binary(u_r, u_c, u_bin),
        matrix.from_binary(v_r, v_c, v_bin)
      {
        Ok(u), Ok(v) -> Ok(SVD(u: u, singular_values: s_values, v: v))
        _, _ ->
          Error(matrix.InvalidDimensions("Failed to construct SVD matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Compute the eigenvalues of a symmetric matrix.
/// Returns eigenvalues in non-decreasing order.
/// Returns an error if the matrix is not square or not symmetric.
pub fn symmetric_eigenvalues(
  m: matrix.Matrix,
) -> Result(List(Float), matrix.MatrixError) {
  use _ <- result.try(matrix.validate_square(m))
  use _ <- result.try(matrix.validate_symmetric(m))
  let n = matrix.rows(m)
  case solvers.symmetric_eigenvalues(n, matrix.to_binary(m)) {
    Ok(eigenvalues_bin) -> Ok(unpack_floats(eigenvalues_bin, n))
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Solve the linear system Ax = b for x.
/// A must be a square matrix, b must be a column vector with rows matching A.
/// Uses LU decomposition with partial pivoting.
pub fn solve(
  a: matrix.Matrix,
  b: matrix.Matrix,
) -> Result(matrix.Matrix, matrix.MatrixError) {
  use Nil <- result.try(validate_dimensions(a, b))
  do_solve(a, b) |> result.map_error(nif_error_to_matrix_error)
}

fn validate_dimensions(
  a: matrix.Matrix,
  b: matrix.Matrix,
) -> Result(Nil, matrix.MatrixError) {
  let is_square = matrix.rows(a) == matrix.cols(a)
  let is_column = matrix.cols(b) == 1
  let rows_match = matrix.rows(a) == matrix.rows(b)

  case is_square, is_column && rows_match {
    False, _ ->
      Error(matrix.InvalidDimensions(
        "Expected square matrix, got " <> matrix.dim_string(a),
      ))
    _, False ->
      Error(matrix.DimensionMismatch(
        "Dimension mismatch: A is "
        <> matrix.dim_string(a)
        <> ", b is "
        <> matrix.dim_string(b),
      ))
    True, True -> Ok(Nil)
  }
}

fn do_solve(a: matrix.Matrix, b: matrix.Matrix) -> Result(matrix.Matrix, String) {
  let a_data = matrix.to_binary(a)
  let b_data = matrix.to_binary(b)
  let rows = matrix.rows(a)
  let cols = matrix.cols(a)
  use result_data <- result.try(solvers.solve_linear_system(
    rows,
    cols,
    a_data,
    b_data,
  ))
  matrix.from_binary(rows, 1, result_data)
  |> result.map_error(matrix_error_to_string)
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
