import gleam/float
import gleam/string
import gleeunit/should
import waffle/matrix

// ---------------------------------------------------------------------------
// from_list / to_list round-trips
// ---------------------------------------------------------------------------

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

pub fn dims_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  matrix.dims(m) |> should.equal(#(3, 2))
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
  result |> should.equal(Error(matrix.RaggedRows))
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

pub fn transpose_2x3_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(mt) = matrix.transpose(m)
  let expected = [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
  mt |> matrix.to_list() |> should.equal(expected)
  matrix.rows(mt) |> should.equal(3)
  matrix.cols(mt) |> should.equal(2)
}

pub fn transpose_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(mt) = matrix.transpose(m)
  let expected = [[1.0, 3.0], [2.0, 4.0]]
  mt |> matrix.to_list() |> should.equal(expected)
  matrix.rows(mt) |> should.equal(2)
  matrix.cols(mt) |> should.equal(2)
}

pub fn transpose_round_trip_test() {
  let input = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
  let assert Ok(m) = matrix.from_list(input)
  let assert Ok(mt) = matrix.transpose(m)
  let assert Ok(m2) = matrix.transpose(mt)
  m2 |> matrix.to_list() |> should.equal(input)
}

pub fn transpose_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(mt) = matrix.transpose(m)
  mt |> matrix.to_list() |> should.equal(matrix.to_list(m))
}

// ---------------------------------------------------------------------------
// Constructors: zeros, ones, diagonal
// ---------------------------------------------------------------------------

pub fn zeros_2x3_test() {
  let assert Ok(m) = matrix.zeros(2, 3)
  matrix.rows(m) |> should.equal(2)
  matrix.cols(m) |> should.equal(3)
  matrix.to_list(m) |> should.equal([[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
}

pub fn zeros_invalid_test() {
  matrix.zeros(0, 3) |> should.be_error()
  matrix.zeros(2, 0) |> should.be_error()
  matrix.zeros(-1, 2) |> should.be_error()
}

pub fn ones_2x2_test() {
  let assert Ok(m) = matrix.ones(2, 2)
  matrix.to_list(m) |> should.equal([[1.0, 1.0], [1.0, 1.0]])
}

pub fn ones_invalid_test() {
  matrix.ones(0, 1) |> should.be_error()
}

pub fn diagonal_test() {
  let assert Ok(m) = matrix.diagonal([3.0, 5.0, 7.0])
  matrix.rows(m) |> should.equal(3)
  matrix.cols(m) |> should.equal(3)
  matrix.to_list(m)
  |> should.equal([[3.0, 0.0, 0.0], [0.0, 5.0, 0.0], [0.0, 0.0, 7.0]])
}

pub fn diagonal_empty_test() {
  matrix.diagonal([]) |> should.equal(Error(matrix.EmptyInput))
}

pub fn diagonal_single_test() {
  let assert Ok(m) = matrix.diagonal([42.0])
  matrix.to_list(m) |> should.equal([[42.0]])
}

// ---------------------------------------------------------------------------
// get accessor
// ---------------------------------------------------------------------------

pub fn get_corners_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(v) = matrix.get(m, 0, 0)
  v |> should.equal(1.0)
  let assert Ok(v) = matrix.get(m, 0, 1)
  v |> should.equal(2.0)
  let assert Ok(v) = matrix.get(m, 1, 0)
  v |> should.equal(3.0)
  let assert Ok(v) = matrix.get(m, 1, 1)
  v |> should.equal(4.0)
}

pub fn get_out_of_bounds_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  matrix.get(m, 2, 0) |> should.be_error()
  matrix.get(m, 0, 2) |> should.be_error()
  matrix.get(m, -1, 0) |> should.be_error()
}

// ---------------------------------------------------------------------------
// trace
// ---------------------------------------------------------------------------

pub fn trace_identity_test() {
  let assert Ok(m) = matrix.identity(4)
  let assert Ok(t) = matrix.trace(m)
  t |> should.equal(4.0)
}

pub fn trace_known_matrix_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(t) = matrix.trace(m)
  t |> should.equal(5.0)
}

pub fn trace_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  matrix.trace(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Arithmetic: add, subtract, scale, multiply
// ---------------------------------------------------------------------------

pub fn add_identity_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(z) = matrix.zeros(2, 2)
  let assert Ok(result) = matrix.add(a, z)
  matrix.to_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn add_commutative_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[5.0, 6.0], [7.0, 8.0]])
  let assert Ok(ab) = matrix.add(a, b)
  let assert Ok(ba) = matrix.add(b, a)
  matrix.to_list(ab) |> should.equal(matrix.to_list(ba))
}

pub fn add_dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])
  matrix.add(a, b) |> should.be_error()
}

pub fn subtract_self_is_zeros_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = matrix.subtract(a, a)
  matrix.to_list(result) |> should.equal([[0.0, 0.0], [0.0, 0.0]])
}

pub fn scale_by_zero_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = matrix.scale(a, 0.0)
  matrix.to_list(result) |> should.equal([[0.0, 0.0], [0.0, 0.0]])
}

pub fn scale_by_two_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = matrix.scale(a, 2.0)
  matrix.to_list(result) |> should.equal([[2.0, 4.0], [6.0, 8.0]])
}

pub fn multiply_identity_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(i) = matrix.identity(2)
  let assert Ok(result) = matrix.multiply(a, i)
  matrix.to_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn multiply_known_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[5.0, 6.0], [7.0, 8.0]])
  let assert Ok(result) = matrix.multiply(a, b)
  // [1*5+2*7, 1*6+2*8] = [19, 22]
  // [3*5+4*7, 3*6+4*8] = [43, 50]
  matrix.to_list(result) |> should.equal([[19.0, 22.0], [43.0, 50.0]])
}

pub fn multiply_rectangular_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0], [3.0]])
  let assert Ok(result) = matrix.multiply(a, b)
  // [1+4+9] = [14]
  // [4+10+18] = [32]
  matrix.to_list(result) |> should.equal([[14.0], [32.0]])
  matrix.rows(result) |> should.equal(2)
  matrix.cols(result) |> should.equal(1)
}

pub fn multiply_dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_list([[1.0, 2.0]])
  // 1x2 * 1x2 should fail (inner dims: 2 != 1)
  matrix.multiply(a, b) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Utilities: reshape, vstack, hstack, to_string
// ---------------------------------------------------------------------------

pub fn reshape_2x3_to_3x2_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(reshaped) = matrix.reshape(m, 3, 2)
  matrix.rows(reshaped) |> should.equal(3)
  matrix.cols(reshaped) |> should.equal(2)
  matrix.to_list(reshaped) |> should.equal([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
}

pub fn reshape_invalid_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  matrix.reshape(m, 3, 3) |> should.be_error()
}

pub fn vstack_basic_test() {
  let assert Ok(top) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(bottom) = matrix.from_list([[3.0, 4.0]])
  let assert Ok(result) = matrix.vstack(top, bottom)
  matrix.rows(result) |> should.equal(2)
  matrix.cols(result) |> should.equal(2)
  matrix.to_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn vstack_column_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_list([[1.0]])
  matrix.vstack(a, b) |> should.be_error()
}

pub fn hstack_basic_test() {
  let assert Ok(left) = matrix.from_list([[1.0], [3.0]])
  let assert Ok(right) = matrix.from_list([[2.0], [4.0]])
  let assert Ok(result) = matrix.hstack(left, right)
  matrix.rows(result) |> should.equal(2)
  matrix.cols(result) |> should.equal(2)
  matrix.to_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn hstack_row_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])
  matrix.hstack(a, b) |> should.be_error()
}

pub fn to_string_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let s = matrix.to_string(m)
  should.be_true(string.contains(s, "1.0"))
  should.be_true(string.contains(s, "4.0"))
}

// ---------------------------------------------------------------------------
// Views & Slicing
// ---------------------------------------------------------------------------

pub fn slice_top_left_test() {
  let assert Ok(m) =
    matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]])
  let assert Ok(s) = matrix.slice(m, 0, 2, 0, 2)
  matrix.to_list(s) |> should.equal([[1.0, 2.0], [4.0, 5.0]])
}

pub fn slice_bottom_right_test() {
  let assert Ok(m) =
    matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]])
  let assert Ok(s) = matrix.slice(m, 1, 2, 1, 2)
  matrix.to_list(s) |> should.equal([[5.0, 6.0], [8.0, 9.0]])
}

pub fn slice_out_of_bounds_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  matrix.slice(m, 0, 3, 0, 2) |> should.be_error()
}

pub fn row_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(r) = matrix.row(m, 1)
  r |> should.equal([4.0, 5.0, 6.0])
}

pub fn row_out_of_bounds_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0]])
  matrix.row(m, 5) |> should.be_error()
}

pub fn col_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(c) = matrix.col(m, 1)
  c |> should.equal([2.0, 5.0])
}

pub fn col_out_of_bounds_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0]])
  matrix.col(m, 5) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Functional Transformations
// ---------------------------------------------------------------------------

pub fn map_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let result = matrix.map(m, fn(x) { x *. 2.0 })
  matrix.to_list(result) |> should.equal([[2.0, 4.0], [6.0, 8.0]])
}

pub fn fold_sum_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let sum = matrix.fold(m, 0.0, fn(acc, x) { acc +. x })
  sum |> should.equal(10.0)
}

pub fn fold_max_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 5.0], [3.0, 2.0]])
  let max = matrix.fold(m, 0.0, fn(acc, x) { float.max(acc, x) })
  max |> should.equal(5.0)
}

pub fn fold_with_indices_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let result =
    matrix.fold_with_indices(m, [], fn(acc, row, col, val) {
      [#(row, col, val), ..acc]
    })
  result
  |> should.equal([#(1, 1, 4.0), #(0, 1, 2.0), #(1, 0, 3.0), #(0, 0, 1.0)])
}

pub fn zip_with_add_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[5.0, 6.0], [7.0, 8.0]])
  let assert Ok(result) = matrix.zip_with(a, b, fn(x, y) { x +. y })
  matrix.to_list(result) |> should.equal([[6.0, 8.0], [10.0, 12.0]])
}

pub fn zip_with_multiply_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[2.0, 0.0], [1.0, 1.0]])
  let assert Ok(result) = matrix.zip_with(a, b, fn(x, y) { x *. y })
  matrix.to_list(result) |> should.equal([[2.0, 0.0], [3.0, 4.0]])
}

pub fn zip_with_dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])
  matrix.zip_with(a, b, fn(x, y) { x +. y }) |> should.be_error()
}
