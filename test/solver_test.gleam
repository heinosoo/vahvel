import gleeunit/should
import matrix
import solver

pub fn identity_matrix_test() {
  let assert Ok(id_2x2) = matrix.identity(2)
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])
  let assert Ok(x) = solver.solve(id_2x2, b)
  matrix.to_list(x)
  |> should.equal([[1.0], [2.0]])
}

pub fn simple_2x2_test() {
  let assert Ok(a) = matrix.from_list([[2.0, 1.0], [1.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[3.0], [2.0]])
  let assert Ok(x) = solver.solve(a, b)

  let x_list = matrix.to_list(x)

  x_list
  |> should.equal([[1.0], [1.0]])
}

pub fn simple_3x3_test() {
  let assert Ok(a) =
    matrix.from_list([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[2.0], [3.0], [4.0]])
  let assert Ok(x) = solver.solve(a, b)

  let x_list = matrix.to_list(x)

  x_list
  |> should.equal([[2.0], [3.0], [4.0]])
}

pub fn singular_matrix_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])

  let result = solver.solve(a, b)

  result
  |> should.equal(Error(solver.SingularMatrix))
}

pub fn non_square_matrix_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])

  let result = solver.solve(a, b)

  result
  |> should.equal(Error(solver.MatrixNotSquare))
}

pub fn dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 0.0], [0.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0], [3.0]])

  let result = solver.solve(a, b)

  result
  |> should.equal(Error(solver.DimensionMismatch))
}
