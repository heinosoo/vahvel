import gleeunit/should
import waffle/matrix

// ---------------------------------------------------------------------------
// from_float_list / to_float_list round-trips
// ---------------------------------------------------------------------------

pub fn from_list_round_trip_2x2_test() {
  let input = [[1.0, 2.0], [3.0, 4.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
}

pub fn from_list_round_trip_3x3_identity_test() {
  let input = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
}

pub fn from_list_round_trip_4x2_test() {
  let input = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0], [7.0, 8.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
}

pub fn rows_test() {
  let assert Ok(m) =
    matrix.from_float_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  matrix.rows(m) |> should.equal(3)
}

pub fn cols_test() {
  let assert Ok(m) =
    matrix.from_float_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  matrix.cols(m) |> should.equal(2)
}

pub fn identity_2x2_test() {
  let assert Ok(m) = matrix.identity_float(2)
  let expected = [[1.0, 0.0], [0.0, 1.0]]
  m |> matrix.to_float_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(2)
  matrix.cols(m) |> should.equal(2)
}

pub fn identity_3x3_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let expected = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
  m |> matrix.to_float_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(3)
  matrix.cols(m) |> should.equal(3)
}

pub fn identity_size_1_test() {
  let assert Ok(m) = matrix.identity_float(1)
  let expected = [[1.0]]
  m |> matrix.to_float_list() |> should.equal(expected)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(1)
}

pub fn from_list_empty_input_test() {
  let result = matrix.from_float_list([])
  result |> should.equal(Error(matrix.EmptyInput))
}

pub fn from_list_empty_row_test() {
  let result = matrix.from_float_list([[], []])
  result |> should.equal(Error(matrix.EmptyRow))
}

pub fn from_list_ragged_rows_test() {
  let result = matrix.from_float_list([[1.0], [2.0, 3.0]])
  result |> should.equal(Error(matrix.RaggedRows))
}

pub fn from_list_mixed_empty_row_test() {
  let result = matrix.from_float_list([[1.0, 2.0], []])
  result |> should.equal(Error(matrix.RaggedRows))
}

pub fn from_list_single_element_test() {
  let input = [[42.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(1)
}

pub fn identity_size_zero_test() {
  let result = matrix.identity_float(0)
  result |> should.be_error()
}

pub fn identity_size_negative_test() {
  let result = matrix.identity_float(-1)
  result |> should.be_error()
}

pub fn from_list_wide_matrix_test() {
  let input = [[1.0, 2.0, 3.0, 4.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(1)
  matrix.cols(m) |> should.equal(4)
}

pub fn from_list_tall_matrix_test() {
  let input = [[1.0], [2.0], [3.0], [4.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let output = matrix.to_float_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(4)
  matrix.cols(m) |> should.equal(1)
}

pub fn transpose_2x3_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(mt) = matrix.transpose(m)
  let expected = [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
  mt |> matrix.to_float_list() |> should.equal(expected)
  matrix.rows(mt) |> should.equal(3)
  matrix.cols(mt) |> should.equal(2)
}

pub fn transpose_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(mt) = matrix.transpose(m)
  let expected = [[1.0, 3.0], [2.0, 4.0]]
  mt |> matrix.to_float_list() |> should.equal(expected)
  matrix.rows(mt) |> should.equal(2)
  matrix.cols(mt) |> should.equal(2)
}

pub fn transpose_round_trip_test() {
  let input = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
  let assert Ok(m) = matrix.from_float_list(input)
  let assert Ok(mt) = matrix.transpose(m)
  let assert Ok(m2) = matrix.transpose(mt)
  m2 |> matrix.to_float_list() |> should.equal(input)
}

pub fn transpose_identity_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let assert Ok(mt) = matrix.transpose(m)
  mt |> matrix.to_float_list() |> should.equal(matrix.to_float_list(m))
}

// ---------------------------------------------------------------------------
// Constructors: zeros, ones, diagonal
// ---------------------------------------------------------------------------

pub fn zeros_2x3_test() {
  let assert Ok(m) = matrix.zeros_float(2, 3)
  matrix.rows(m) |> should.equal(2)
  matrix.cols(m) |> should.equal(3)
  matrix.to_float_list(m) |> should.equal([[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
}

pub fn zeros_invalid_test() {
  matrix.zeros_float(0, 3) |> should.be_error()
  matrix.zeros_float(2, 0) |> should.be_error()
  matrix.zeros_float(-1, 2) |> should.be_error()
}

pub fn ones_2x2_test() {
  let assert Ok(m) = matrix.ones_float(2, 2)
  matrix.to_float_list(m) |> should.equal([[1.0, 1.0], [1.0, 1.0]])
}

pub fn ones_invalid_test() {
  matrix.ones_float(0, 1) |> should.be_error()
}

pub fn diagonal_test() {
  let assert Ok(m) = matrix.diagonal_float([3.0, 5.0, 7.0])
  matrix.rows(m) |> should.equal(3)
  matrix.cols(m) |> should.equal(3)
  matrix.to_float_list(m)
  |> should.equal([[3.0, 0.0, 0.0], [0.0, 5.0, 0.0], [0.0, 0.0, 7.0]])
}

pub fn diagonal_empty_test() {
  matrix.diagonal_float([]) |> should.equal(Error(matrix.EmptyInput))
}

pub fn diagonal_single_test() {
  let assert Ok(m) = matrix.diagonal_float([42.0])
  matrix.to_float_list(m) |> should.equal([[42.0]])
}

// ---------------------------------------------------------------------------
// get accessor
// ---------------------------------------------------------------------------

pub fn get_corners_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(v) = matrix.get_float(m, 0, 0)
  v |> should.equal(1.0)
  let assert Ok(v) = matrix.get_float(m, 0, 1)
  v |> should.equal(2.0)
  let assert Ok(v) = matrix.get_float(m, 1, 0)
  v |> should.equal(3.0)
  let assert Ok(v) = matrix.get_float(m, 1, 1)
  v |> should.equal(4.0)
}

pub fn get_out_of_bounds_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  matrix.get_float(m, 2, 0) |> should.be_error()
  matrix.get_float(m, 0, 2) |> should.be_error()
  matrix.get_float(m, -1, 0) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Matrix(Int) tests
// ---------------------------------------------------------------------------

pub fn from_int_list_test() {
  let input = [[1, 2], [3, 4]]
  let assert Ok(m) = matrix.from_int_list(input)
  let output = matrix.to_int_list(m)
  output |> should.equal(input)
  matrix.rows(m) |> should.equal(2)
  matrix.cols(m) |> should.equal(2)
}

pub fn get_int_test() {
  let assert Ok(m) = matrix.from_int_list([[10, 20], [30, 40]])
  let assert Ok(v) = matrix.get_int(m, 1, 0)
  v |> should.equal(30)
}

pub fn transpose_int_test() {
  let input = [[1, 2, 3], [4, 5, 6]]
  let assert Ok(m) = matrix.from_int_list(input)
  let assert Ok(mt) = matrix.transpose(m)
  let expected = [[1, 4], [2, 5], [3, 6]]
  mt |> matrix.to_int_list() |> should.equal(expected)
}
