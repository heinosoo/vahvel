import gleam/result
import gleam/string
import waffle/internal/faer/linalg/solvers
import waffle/matrix.{type Matrix, type MatrixError}

/// Errors that can occur when solving linear systems.
pub type SolverError {
  /// Coefficient matrix was not square.
  MatrixNotSquare
  /// Matrix dimensions were incompatible for solving.
  DimensionMismatch
  /// Matrix was singular (no unique solution).
  SingularMatrix
  /// Other solver error.
  InvalidSolution(String)
}

/// Solve the linear system Ax = b for x.
pub fn solve(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Matrix(Float), SolverError) {
  use Nil <- result.try(validate_dimensions(a, b))

  do_solve(a, b) |> result.map_error(classify_solver_error)
}

fn validate_dimensions(
  a: Matrix(Float),
  b: Matrix(Float),
) -> Result(Nil, SolverError) {
  let is_square = matrix.rows(a) == matrix.cols(a)
  let is_column = matrix.cols(b) == 1
  let rows_match = matrix.rows(a) == matrix.rows(b)

  case is_square, is_column && rows_match {
    True, True -> Ok(Nil)
    False, _ -> Error(MatrixNotSquare)
    _, False -> Error(DimensionMismatch)
  }
}

fn classify_solver_error(msg: String) -> SolverError {
  case string.contains(msg, "singular") {
    True -> SingularMatrix
    False -> InvalidSolution(msg)
  }
}

fn do_solve(a: Matrix(Float), b: Matrix(Float)) -> Result(Matrix(Float), String) {
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

fn matrix_error_to_string(error: MatrixError) -> String {
  case error {
    matrix.EmptyInput -> "Matrix error: empty input"
    matrix.EmptyRow -> "Matrix error: empty row"
    matrix.RaggedRows -> "Matrix error: ragged rows"
    matrix.InvalidDimensions(msg) -> "Matrix error: " <> msg
    matrix.DimensionMismatch(msg) -> "Matrix error: " <> msg
    matrix.SingularMatrix -> "Matrix error: singular matrix"
  }
}
