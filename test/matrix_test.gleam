import gleam/float
import gleam/list
import gleeunit/should
import matrix

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  float.absolute_value(a -. b) <. tolerance
}

fn approx_equal_lists(a: List(Float), b: List(Float), tol: Float) -> Bool {
  list.length(a) == list.length(b)
  && list.zip(a, b)
  |> list.all(fn(pair) { approx_equal(pair.0, pair.1, tol) })
}

fn approx_equal_matrix(a: matrix.Matrix, b: matrix.Matrix, tol: Float) -> Bool {
  let a_list = list.flatten(matrix.to_list(a))
  let b_list = list.flatten(matrix.to_list(b))
  approx_equal_lists(a_list, b_list, tol)
}

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
// determinant
// ---------------------------------------------------------------------------

pub fn determinant_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(det) = matrix.determinant(m)
  should.be_true(approx_equal(det, 1.0, 1.0e-10))
}

pub fn determinant_known_2x2_test() {
  // det([[1,2],[3,4]]) = 1*4 - 2*3 = -2
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(det) = matrix.determinant(m)
  should.be_true(approx_equal(det, -2.0, 1.0e-10))
}

pub fn determinant_singular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  let assert Ok(det) = matrix.determinant(m)
  should.be_true(approx_equal(det, 0.0, 1.0e-10))
}

pub fn determinant_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  matrix.determinant(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// inverse
// ---------------------------------------------------------------------------

pub fn inverse_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(inv) = matrix.inverse(m)
  should.be_true(approx_equal_matrix(inv, m, 1.0e-10))
}

pub fn inverse_known_2x2_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(inv) = matrix.inverse(m)
  let assert Ok(product) = matrix.multiply(m, inv)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(product, i, 1.0e-10))
}

pub fn inverse_singular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  matrix.inverse(m) |> should.equal(Error(matrix.SingularMatrix))
}

pub fn inverse_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  matrix.inverse(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// LU decomposition
// ---------------------------------------------------------------------------

pub fn lu_2x2_test() {
  let assert Ok(m) = matrix.from_list([[2.0, 1.0], [4.0, 3.0]])
  let assert Ok(matrix.LU(l: l, u: u, pivot: pivot)) = matrix.lu(m)

  // L should be lower triangular with ones on diagonal
  let assert Ok(l00) = matrix.get(l, 0, 0)
  should.be_true(approx_equal(l00, 1.0, 1.0e-10))
  let assert Ok(l01) = matrix.get(l, 0, 1)
  should.be_true(approx_equal(l01, 0.0, 1.0e-10))

  // U should be upper triangular
  let assert Ok(u10) = matrix.get(u, 1, 0)
  should.be_true(approx_equal(u10, 0.0, 1.0e-10))

  // L*U should approximate P*A
  let assert Ok(lu_product) = matrix.multiply(l, u)

  // Apply pivot to reconstruct P*A
  let pa = apply_pivot(pivot, m)
  should.be_true(approx_equal_matrix(lu_product, pa, 1.0e-10))
}

fn list_at(lst: List(a), index: Int) -> a {
  let assert [item, ..] = list.drop(lst, index)
  item
}

fn apply_pivot(pivot: List(Int), m: matrix.Matrix) -> matrix.Matrix {
  let rows_list = matrix.to_list(m)
  let permuted = list.map(pivot, fn(p) { list_at(rows_list, p) })
  let assert Ok(result) = matrix.from_list(permuted)
  result
}

pub fn lu_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(matrix.LU(l: l, u: u, pivot: _pivot)) = matrix.lu(m)
  let assert Ok(i) = matrix.identity(3)
  should.be_true(approx_equal_matrix(l, i, 1.0e-10))
  should.be_true(approx_equal_matrix(u, i, 1.0e-10))
}

pub fn lu_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  matrix.lu(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// QR decomposition
// ---------------------------------------------------------------------------

pub fn qr_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(matrix.QR(q: q, r: r)) = matrix.qr(m)

  // Q^T * Q ≈ I
  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = matrix.multiply(qt, q)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  // Q * R ≈ A
  let assert Ok(qr_product) = matrix.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

pub fn qr_rectangular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  let assert Ok(matrix.QR(q: q, r: r)) = matrix.qr(m)

  // Q is 3x2 (thin), R is 2x2
  matrix.rows(q) |> should.equal(3)
  matrix.cols(q) |> should.equal(2)
  matrix.rows(r) |> should.equal(2)
  matrix.cols(r) |> should.equal(2)

  // Q^T * Q ≈ I (2x2)
  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = matrix.multiply(qt, q)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  // Q * R ≈ A
  let assert Ok(qr_product) = matrix.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

// ---------------------------------------------------------------------------
// SVD decomposition
// ---------------------------------------------------------------------------

pub fn svd_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(matrix.SVD(u: u, singular_values: s, v: v)) = matrix.svd(m)

  // U^T * U ≈ I
  let assert Ok(ut) = matrix.transpose(u)
  let assert Ok(utu) = matrix.multiply(ut, u)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(utu, i, 1.0e-10))

  // V^T * V ≈ I
  let assert Ok(vt) = matrix.transpose(v)
  let assert Ok(vtv) = matrix.multiply(vt, v)
  should.be_true(approx_equal_matrix(vtv, i, 1.0e-10))

  // Singular values should be positive and descending
  should.be_true(list.all(s, fn(x) { x >=. 0.0 }))
  should.be_true(is_descending(s))

  // U * diag(S) * V^T ≈ A
  let assert Ok(s_mat) = matrix.diagonal(s)
  let assert Ok(us) = matrix.multiply(u, s_mat)
  let assert Ok(usvt) = matrix.multiply(us, vt)
  should.be_true(approx_equal_matrix(usvt, m, 1.0e-10))
}

fn is_descending(values: List(Float)) -> Bool {
  case values {
    [] | [_] -> True
    [a, b, ..rest] -> a >=. b && is_descending([b, ..rest])
  }
}

pub fn svd_rectangular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  let assert Ok(matrix.SVD(u: u, singular_values: s, v: v)) = matrix.svd(m)

  // U is 3x2, V is 2x2, S has 2 values
  matrix.rows(u) |> should.equal(3)
  matrix.cols(u) |> should.equal(2)
  matrix.rows(v) |> should.equal(2)
  matrix.cols(v) |> should.equal(2)
  list.length(s) |> should.equal(2)

  // U * diag(S) * V^T ≈ A
  let assert Ok(s_mat) = matrix.diagonal(s)
  let assert Ok(vt) = matrix.transpose(v)
  let assert Ok(us) = matrix.multiply(u, s_mat)
  let assert Ok(usvt) = matrix.multiply(us, vt)
  should.be_true(approx_equal_matrix(usvt, m, 1.0e-10))
}

// ---------------------------------------------------------------------------
// Symmetric eigenvalues
// ---------------------------------------------------------------------------

pub fn symmetric_eigenvalues_diagonal_test() {
  let assert Ok(m) = matrix.diagonal([3.0, 1.0, 2.0])
  let assert Ok(eigenvalues) = matrix.symmetric_eigenvalues(m)
  // Eigenvalues of a diagonal matrix are the diagonal entries, sorted
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 2.0, 3.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(eigenvalues) = matrix.symmetric_eigenvalues(m)
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 1.0, 1.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_non_symmetric_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  matrix.symmetric_eigenvalues(m) |> should.be_error()
}

pub fn symmetric_eigenvalues_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  matrix.symmetric_eigenvalues(m) |> should.be_error()
}
