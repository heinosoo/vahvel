import gleeunit/should
import matrix

pub fn from_list_round_trip_2x2_test() {
  let input = [[1.0, 2.0], [3.0, 4.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
}

pub fn from_list_round_trip_3x3_identity_test() {
  let input = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
}

pub fn from_list_round_trip_4x2_test() {
  let input = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0], [7.0, 8.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
}

pub fn rows_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  matrix.rows(m) |> should.equal(3)
}

pub fn cols_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  matrix.cols(m) |> should.equal(2)
}

pub fn identity_2x2_test() {
  let assert Ok(m) = matrix.identity(2)
  let expected = [[1.0, 0.0], [0.0, 1.0]]
  m |> matrix.to_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(2)
  matrix.cols(m) |> should.equal(2)
}

pub fn identity_3x3_test() {
  let assert Ok(m) = matrix.identity(3)
  let expected = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
  m |> matrix.to_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(3)
  matrix.cols(m) |> should.equal(3)
}

pub fn identity_size_1_test() {
  let assert Ok(m) = matrix.identity(1)
  let expected = [[1.0]]
  m |> matrix.to_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(1)
}

pub fn from_list_empty_input_test() {
  let result = matrix.from_list([])
  result |> should.equal(Error(matrix.EmptyInput))
}

pub fn from_list_empty_row_test() {
  let result = matrix.from_list([[], []])
  result |> should.equal(Error(matrix.EmptyRow))
}

pub fn from_list_ragged_rows_test() {
  let result = matrix.from_list([[1.0], [2.0, 3.0]])
  result |> should.equal(Error(matrix.RaggedRows))
}

pub fn from_list_mixed_empty_row_test() {
  let result = matrix.from_list([[1.0, 2.0], []])
  result |> should.equal(Error(matrix.EmptyRow))
}

pub fn from_list_single_element_test() {
  let input = [[42.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(1)
}

pub fn identity_size_zero_test() {
  let result = matrix.identity(0)
  result |> should.be_error()
}

pub fn identity_size_negative_test() {
  let result = matrix.identity(-1)
  result |> should.be_error()
}

pub fn from_list_wide_matrix_test() {
  let input = [[1.0, 2.0, 3.0, 4.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(4)
}

pub fn from_list_tall_matrix_test() {
  let input = [[1.0], [2.0], [3.0], [4.0]]
  let assert Ok(m) = matrix.from_list(input)
  let output = matrix.to_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(4)
  matrix.cols(m) |> should.equal(1)
}
