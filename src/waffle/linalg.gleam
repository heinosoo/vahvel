import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import waffle/internal/faer/linalg/solvers
import waffle/internal/faer/mat
import waffle/matrix.{type Matrix, type MatrixError, InvalidDimensions}

/// LU decomposition with partial pivoting: PA = LU.
pub type LU {
  LU(l: Matrix(Float), u: Matrix(Float), pivot: List(Int))
}

/// Thin QR decomposition: A = QR.
pub type QR {
  QR(q: Matrix(Float), r: Matrix(Float))
}

/// Thin SVD: A = U * diag(S) * transpose(V).
pub type SVD {
  SVD(u: Matrix(Float), singular_values: List(Float), v: Matrix(Float))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn dim_string(matrix: Matrix(a)) -> String {
  int.to_string(matrix.rows(matrix))
  <> "x"
  <> int.to_string(matrix.cols(matrix))
}

fn validate_same_dimensions(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Nil, MatrixError) {
  case matrix.rows(a) == matrix.rows(b) && matrix.cols(a) == matrix.cols(b) {
    True -> Ok(Nil)
    False ->
      Error(matrix.DimensionMismatch(
        "Dimension mismatch: " <> dim_string(a) <> " vs " <> dim_string(b),
      ))
  }
}

fn validate_multipliable(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Nil, MatrixError) {
  case matrix.cols(a) == matrix.rows(b) {
    True -> Ok(Nil)
    False ->
      Error(matrix.DimensionMismatch(
        "Cannot multiply "
        <> dim_string(a)
        <> " by "
        <> dim_string(b)
        <> ": inner dimensions do not match",
      ))
  }
}

fn validate_square(matrix: Matrix(Float)) -> Result(Nil, MatrixError) {
  case matrix.rows(matrix) == matrix.cols(matrix) {
    True -> Ok(Nil)
    False ->
      Error(InvalidDimensions(
        "Expected square matrix, got " <> dim_string(matrix),
      ))
  }
}

fn validate_symmetric(matrix: Matrix(Float)) -> Result(Nil, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows(matrix)
  // We check symmetry by sampling or full check?
  // The original implementation did full check using read_float_at.
  // We can use matrix.get_float, but it returns Result.
  // Or we can rely on NIF to check? No, NIF for eigenvalues assumes symmetric?
  // faer::selfadjoint_eigenvalues assumes symmetric (or uses lower/upper triangle).
  // The original implementation checked it in Gleam.
  // We'll reimplement it using matrix.get_float.
  let range = list.range(0, n - 1)
  let is_symmetric =
    list.all(range, fn(i) {
      case i + 1 > n - 1 {
        True -> True
        False ->
          list.all(list.range(i + 1, n - 1), fn(j) {
            let assert Ok(aij) = matrix.get_float(matrix, i, j)
            let assert Ok(aji) = matrix.get_float(matrix, j, i)
            float.loosely_equals(aij, aji, tolerating: 1.0e-10)
          })
      }
    })
  case is_symmetric {
    True -> Ok(Nil)
    False -> Error(InvalidDimensions("Matrix is not symmetric"))
  }
}

fn nif_error_to_matrix_error(msg: String) -> MatrixError {
  case msg {
    "Matrix is singular" <> _ -> matrix.SingularMatrix
    _ -> InvalidDimensions(msg)
  }
}

fn read_float_at_offset(data: BitArray, offset: Int) -> Float {
  case bit_array.slice(data, offset, 8) {
    Ok(<<x:float-little-size(64)>>) -> x
    _ -> 0.0
  }
}

fn unpack_floats(data: BitArray, count: Int) -> List(Float) {
  list.map(list.range(0, count - 1), fn(i) { read_float_at_offset(data, i * 8) })
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

// ---------------------------------------------------------------------------
// Arithmetic (delegates to faer/mat)
// ---------------------------------------------------------------------------

/// Element-wise matrix addition.
pub fn add(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Matrix(Float), MatrixError) {
  use _ <- result.try(validate_same_dimensions(a, b))
  mat.add(
    matrix.rows(a),
    matrix.cols(a),
    matrix.to_binary(a),
    matrix.to_binary(b),
  )
  |> result.map(fn(data) {
    let assert Ok(m) = matrix.from_binary(matrix.rows(a), matrix.cols(a), data)
    m
  })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Element-wise matrix subtraction.
pub fn subtract(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Matrix(Float), MatrixError) {
  use _ <- result.try(validate_same_dimensions(a, b))
  mat.subtract(
    matrix.rows(a),
    matrix.cols(a),
    matrix.to_binary(a),
    matrix.to_binary(b),
  )
  |> result.map(fn(data) {
    let assert Ok(m) = matrix.from_binary(matrix.rows(a), matrix.cols(a), data)
    m
  })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Scalar multiplication of a matrix.
pub fn scale(
  matrix: Matrix(Float),
  scalar: Float,
) -> Result(Matrix(Float), MatrixError) {
  mat.scale(
    matrix.rows(matrix),
    matrix.cols(matrix),
    matrix.to_binary(matrix),
    scalar,
  )
  |> result.map(fn(data) {
    let assert Ok(m) =
      matrix.from_binary(matrix.rows(matrix), matrix.cols(matrix), data)
    m
  })
  |> result.map_error(nif_error_to_matrix_error)
}

/// Matrix multiplication.
pub fn multiply(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Matrix(Float), MatrixError) {
  use _ <- result.try(validate_multipliable(a, b))
  mat.multiply(
    matrix.rows(a),
    matrix.cols(a),
    matrix.to_binary(a),
    matrix.rows(b),
    matrix.cols(b),
    matrix.to_binary(b),
  )
  |> result.map(fn(data) {
    let assert Ok(m) = matrix.from_binary(matrix.rows(a), matrix.cols(b), data)
    m
  })
  |> result.map_error(nif_error_to_matrix_error)
}

// ---------------------------------------------------------------------------
// Pure operations
// ---------------------------------------------------------------------------

/// Compute the trace (sum of diagonal elements) of a square matrix.
pub fn trace(matrix: Matrix(Float)) -> Result(Float, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows(matrix)
  // We can access diagonal elements efficiently using get_float(i, i)
  let sum =
    list.fold(list.range(0, n - 1), 0.0, fn(acc, i) {
      let assert Ok(val) = matrix.get_float(matrix, i, i)
      acc +. val
    })
  Ok(sum)
}

// ---------------------------------------------------------------------------
// Properties (delegates to faer/linalg/solvers)
// ---------------------------------------------------------------------------

/// Compute the determinant of a square matrix.
pub fn determinant(matrix: Matrix(Float)) -> Result(Float, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  solvers.determinant(matrix.rows(matrix), matrix.to_binary(matrix))
  |> result.map_error(nif_error_to_matrix_error)
}

/// Compute the inverse of a square matrix.
pub fn inverse(matrix: Matrix(Float)) -> Result(Matrix(Float), MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows(matrix)
  solvers.inverse(n, matrix.to_binary(matrix))
  |> result.map(fn(data) {
    let assert Ok(m) = matrix.from_binary(n, n, data)
    m
  })
  |> result.map_error(nif_error_to_matrix_error)
}

// ---------------------------------------------------------------------------
// Decompositions (delegates to faer/linalg/solvers)
// ---------------------------------------------------------------------------

/// LU decomposition with partial pivoting: PA = LU.
pub fn lu(matrix: Matrix(Float)) -> Result(LU, MatrixError) {
  use _ <- result.try(validate_square(matrix))
  let n = matrix.rows(matrix)
  case solvers.lu(n, matrix.to_binary(matrix)) {
    Ok(#(#(l_r, l_c, l_bin), #(u_r, u_c, u_bin), #(piv_len, piv_bin))) -> {
      let pivot = unpack_pivot(piv_bin, piv_len)
      case
        matrix.from_binary(l_r, l_c, l_bin),
        matrix.from_binary(u_r, u_c, u_bin)
      {
        Ok(l), Ok(u) -> Ok(LU(l: l, u: u, pivot: pivot))
        _, _ -> Error(InvalidDimensions("Failed to construct LU matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Thin QR decomposition: A = QR.
pub fn qr(matrix: Matrix(Float)) -> Result(QR, MatrixError) {
  case
    solvers.qr(
      matrix.rows(matrix),
      matrix.cols(matrix),
      matrix.to_binary(matrix),
    )
  {
    Ok(#(#(q_r, q_c, q_bin), #(r_r, r_c, r_bin))) -> {
      case
        matrix.from_binary(q_r, q_c, q_bin),
        matrix.from_binary(r_r, r_c, r_bin)
      {
        Ok(q), Ok(r) -> Ok(QR(q: q, r: r))
        _, _ -> Error(InvalidDimensions("Failed to construct QR matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Thin SVD: A = U * diag(S) * transpose(V).
pub fn svd(matrix: Matrix(Float)) -> Result(SVD, MatrixError) {
  case
    solvers.svd(
      matrix.rows(matrix),
      matrix.cols(matrix),
      matrix.to_binary(matrix),
    )
  {
    Ok(#(#(u_r, u_c, u_bin), #(s_len, s_bin), #(v_r, v_c, v_bin))) -> {
      let s_values = unpack_floats(s_bin, s_len)
      case
        matrix.from_binary(u_r, u_c, u_bin),
        matrix.from_binary(v_r, v_c, v_bin)
      {
        Ok(u), Ok(v) -> Ok(SVD(u: u, singular_values: s_values, v: v))
        _, _ -> Error(InvalidDimensions("Failed to construct SVD matrices"))
      }
    }
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}

/// Eigenvalues of a symmetric matrix, in nondecreasing order.
pub fn symmetric_eigenvalues(
  matrix: Matrix(Float),
) -> Result(List(Float), MatrixError) {
  use _ <- result.try(validate_square(matrix))
  use _ <- result.try(validate_symmetric(matrix))
  let n = matrix.rows(matrix)
  case solvers.symmetric_eigenvalues(n, matrix.to_binary(matrix)) {
    Ok(eigenvalues_bin) -> Ok(unpack_floats(eigenvalues_bin, n))
    Error(msg) -> Error(nif_error_to_matrix_error(msg))
  }
}
