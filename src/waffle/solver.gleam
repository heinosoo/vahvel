import gleam/string
import waffle/matrix

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
  a: matrix.Matrix,
  b: matrix.Matrix,
) -> Result(matrix.Matrix, SolverError) {
  let a_rows = matrix.rows(a)
  let a_cols = matrix.cols(a)
  let b_rows = matrix.rows(b)

  let b_cols = matrix.cols(b)

  case a_rows != a_cols {
    True -> Error(MatrixNotSquare)
    False -> {
      case b_rows != a_rows || b_cols != 1 {
        True -> Error(DimensionMismatch)
        False -> {
          case do_solve(a, b) {
            Ok(result_matrix) -> Ok(result_matrix)
            Error(msg) -> {
              case string.contains(msg, "singular") {
                True -> Error(SingularMatrix)
                False -> Error(InvalidSolution(msg))
              }
            }
          }
        }
      }
    }
  }
}

fn do_solve(a: matrix.Matrix, b: matrix.Matrix) -> Result(matrix.Matrix, String) {
  let a_data = matrix.to_binary(a)
  let b_data = matrix.to_binary(b)
  let rows = matrix.rows(a)
  let cols = matrix.cols(a)
  let _b_cols = matrix.cols(b)

  case solve_linear_system(rows, cols, a_data, b_data) {
    Ok(result_data) -> {
      Ok(matrix.from_binary(rows, 1, result_data))
    }
    Error(msg) -> Error(msg)
  }
}

@external(erlang, "waffle_ffi", "solve_linear_system")
fn solve_linear_system(
  rows: Int,
  cols: Int,
  a_data: BitArray,
  b_data: BitArray,
) -> Result(BitArray, String)
