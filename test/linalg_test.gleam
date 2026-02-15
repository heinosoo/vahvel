import gleam/float
import gleam/list
import gleeunit/should
import waffle/matrix
import waffle/linalg

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

fn approx_equal_matrix(a: matrix.Matrix(Float), b: matrix.Matrix(Float), tol: Float) -> Bool {
  let a_list = list.flatten(matrix.to_float_list(a))
  let b_list = list.flatten(matrix.to_float_list(b))
  approx_equal_lists(a_list, b_list, tol)
}

// ---------------------------------------------------------------------------
// trace
// ---------------------------------------------------------------------------

pub fn trace_identity_test() {
  let assert Ok(m) = matrix.identity_float(4)
  let assert Ok(t) = linalg.trace(m)
  t |> should.equal(4.0)
}

pub fn trace_known_matrix_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(t) = linalg.trace(m)
  t |> should.equal(5.0)
}

pub fn trace_non_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0]])
  linalg.trace(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Arithmetic: add, subtract, scale, multiply
// ---------------------------------------------------------------------------

pub fn add_identity_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(z) = matrix.zeros_float(2, 2)
  let assert Ok(result) = linalg.add(a, z)
  matrix.to_float_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn add_commutative_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_float_list([[5.0, 6.0], [7.0, 8.0]])
  let assert Ok(ab) = linalg.add(a, b)
  let assert Ok(ba) = linalg.add(b, a)
  matrix.to_float_list(ab) |> should.equal(matrix.to_float_list(ba))
}

pub fn add_dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_float_list([[1.0], [2.0]])
  linalg.add(a, b) |> should.be_error()
}

pub fn subtract_self_is_zeros_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = linalg.subtract(a, a)
  matrix.to_float_list(result) |> should.equal([[0.0, 0.0], [0.0, 0.0]])
}

pub fn scale_by_zero_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = linalg.scale(a, 0.0)
  matrix.to_float_list(result) |> should.equal([[0.0, 0.0], [0.0, 0.0]])
}

pub fn scale_by_two_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(result) = linalg.scale(a, 2.0)
  matrix.to_float_list(result) |> should.equal([[2.0, 4.0], [6.0, 8.0]])
}

pub fn multiply_identity_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(i) = matrix.identity_float(2)
  let assert Ok(result) = linalg.multiply(a, i)
  matrix.to_float_list(result) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn multiply_known_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(b) = matrix.from_float_list([[5.0, 6.0], [7.0, 8.0]])
  let assert Ok(result) = linalg.multiply(a, b)
  // [1*5+2*7, 1*6+2*8] = [19, 22]
  // [3*5+4*7, 3*6+4*8] = [43, 50]
  matrix.to_float_list(result) |> should.equal([[19.0, 22.0], [43.0, 50.0]])
}

pub fn multiply_rectangular_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(b) = matrix.from_float_list([[1.0], [2.0], [3.0]])
  let assert Ok(result) = linalg.multiply(a, b)
  // [1+4+9] = [14]
  // [4+10+18] = [32]
  matrix.to_float_list(result) |> should.equal([[14.0], [32.0]])
  matrix.rows(result) |> should.equal(2)
  matrix.cols(result) |> should.equal(1)
}

pub fn multiply_dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_float_list([[1.0, 2.0]])
  let assert Ok(b) = matrix.from_float_list([[1.0, 2.0]])
  // 1x2 * 1x2 should fail (inner dims: 2 != 1)
  linalg.multiply(a, b) |> should.be_error()
}

// ---------------------------------------------------------------------------
// determinant
// ---------------------------------------------------------------------------

pub fn determinant_identity_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, 1.0, 1.0e-10))
}

pub fn determinant_known_2x2_test() {
  // det([[1,2],[3,4]]) = 1*4 - 2*3 = -2
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, -2.0, 1.0e-10))
}

pub fn determinant_singular_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [2.0, 4.0]])
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, 0.0, 1.0e-10))
}

pub fn determinant_non_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0]])
  linalg.determinant(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// inverse
// ---------------------------------------------------------------------------

pub fn inverse_identity_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let assert Ok(inv) = linalg.inverse(m)
  should.be_true(approx_equal_matrix(inv, m, 1.0e-10))
}

pub fn inverse_known_2x2_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(inv) = linalg.inverse(m)
  let assert Ok(product) = linalg.multiply(m, inv)
  let assert Ok(i) = matrix.identity_float(2)
  should.be_true(approx_equal_matrix(product, i, 1.0e-10))
}

pub fn inverse_singular_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [2.0, 4.0]])
  linalg.inverse(m) |> should.equal(Error(matrix.SingularMatrix))
}

pub fn inverse_non_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0]])
  linalg.inverse(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// LU decomposition
// ---------------------------------------------------------------------------

pub fn lu_2x2_test() {
  let assert Ok(m) = matrix.from_float_list([[2.0, 1.0], [4.0, 3.0]])
  let assert Ok(linalg.LU(l: l, u: u, pivot: pivot)) = linalg.lu(m)

  // L should be lower triangular with ones on diagonal
  let assert Ok(l00) = matrix.get_float(l, 0, 0)
  should.be_true(approx_equal(l00, 1.0, 1.0e-10))
  let assert Ok(l01) = matrix.get_float(l, 0, 1)
  should.be_true(approx_equal(l01, 0.0, 1.0e-10))

  // U should be upper triangular
  let assert Ok(u10) = matrix.get_float(u, 1, 0)
  should.be_true(approx_equal(u10, 0.0, 1.0e-10))

  // L*U should approximate P*A
  let assert Ok(lu_product) = linalg.multiply(l, u)

  // Apply pivot to reconstruct P*A
  let pa = apply_pivot(pivot, m)
  should.be_true(approx_equal_matrix(lu_product, pa, 1.0e-10))
}

fn list_at(lst: List(a), index: Int) -> a {
  let assert [item, ..] = list.drop(lst, index)
  item
}

fn apply_pivot(pivot: List(Int), m: matrix.Matrix(Float)) -> matrix.Matrix(Float) {
  let rows_list = matrix.to_float_list(m)
  let permuted = list.map(pivot, fn(p) { list_at(rows_list, p) })
  let assert Ok(result) = matrix.from_float_list(permuted)
  result
}

pub fn lu_identity_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let assert Ok(linalg.LU(l: l, u: u, pivot: _pivot)) = linalg.lu(m)
  let assert Ok(i) = matrix.identity_float(3)
  should.be_true(approx_equal_matrix(l, i, 1.0e-10))
  should.be_true(approx_equal_matrix(u, i, 1.0e-10))
}

pub fn lu_non_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0]])
  linalg.lu(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// QR decomposition
// ---------------------------------------------------------------------------

pub fn qr_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(linalg.QR(q: q, r: r)) = linalg.qr(m)

  // Q^T * Q ≈ I
  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = linalg.multiply(qt, q)
  let assert Ok(i) = matrix.identity_float(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  // Q * R ≈ A
  let assert Ok(qr_product) = linalg.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

pub fn qr_rectangular_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  let assert Ok(linalg.QR(q: q, r: r)) = linalg.qr(m)

  // Q is 3x2 (thin), R is 2x2
  matrix.rows(q) |> should.equal(3)
  matrix.cols(q) |> should.equal(2)
  matrix.rows(r) |> should.equal(2)
  matrix.cols(r) |> should.equal(2)

  // Q^T * Q ≈ I (2x2)
  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = linalg.multiply(qt, q)
  let assert Ok(i) = matrix.identity_float(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  // Q * R ≈ A
  let assert Ok(qr_product) = linalg.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

// ---------------------------------------------------------------------------
// SVD decomposition
// ---------------------------------------------------------------------------

pub fn svd_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(linalg.SVD(u: u, singular_values: s, v: v)) = linalg.svd(m)

  // U^T * U ≈ I
  let assert Ok(ut) = matrix.transpose(u)
  let assert Ok(utu) = linalg.multiply(ut, u)
  let assert Ok(i) = matrix.identity_float(2)
  should.be_true(approx_equal_matrix(utu, i, 1.0e-10))

  // V^T * V ≈ I
  let assert Ok(vt) = matrix.transpose(v)
  let assert Ok(vtv) = linalg.multiply(vt, v)
  should.be_true(approx_equal_matrix(vtv, i, 1.0e-10))

  // Singular values should be positive and descending
  should.be_true(list.all(s, fn(x) { x >=. 0.0 }))
  should.be_true(is_descending(s))

  // U * diag(S) * V^T ≈ A
  let assert Ok(s_mat) = matrix.diagonal_float(s)
  let assert Ok(us) = linalg.multiply(u, s_mat)
  let assert Ok(usvt) = linalg.multiply(us, vt)
  should.be_true(approx_equal_matrix(usvt, m, 1.0e-10))
}

fn is_descending(values: List(Float)) -> Bool {
  case values {
    [] | [_] -> True
    [a, b, ..rest] -> a >=. b && is_descending([b, ..rest])
  }
}

pub fn svd_rectangular_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  let assert Ok(linalg.SVD(u: u, singular_values: s, v: v)) = linalg.svd(m)

  // U is 3x2, V is 2x2, S has 2 values
  matrix.rows(u) |> should.equal(3)
  matrix.cols(u) |> should.equal(2)
  matrix.rows(v) |> should.equal(2)
  matrix.cols(v) |> should.equal(2)
  list.length(s) |> should.equal(2)

  // U * diag(S) * V^T ≈ A
  let assert Ok(s_mat) = matrix.diagonal_float(s)
  let assert Ok(vt) = matrix.transpose(v)
  let assert Ok(us) = linalg.multiply(u, s_mat)
  let assert Ok(usvt) = linalg.multiply(us, vt)
  should.be_true(approx_equal_matrix(usvt, m, 1.0e-10))
}

// ---------------------------------------------------------------------------
// Symmetric eigenvalues
// ---------------------------------------------------------------------------

pub fn symmetric_eigenvalues_diagonal_test() {
  let assert Ok(m) = matrix.diagonal_float([3.0, 1.0, 2.0])
  let assert Ok(eigenvalues) = linalg.symmetric_eigenvalues(m)
  // Eigenvalues of a diagonal matrix are the diagonal entries, sorted
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 2.0, 3.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_identity_test() {
  let assert Ok(m) = matrix.identity_float(3)
  let assert Ok(eigenvalues) = linalg.symmetric_eigenvalues(m)
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 1.0, 1.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_non_symmetric_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0], [3.0, 4.0]])
  linalg.symmetric_eigenvalues(m) |> should.be_error()
}

pub fn symmetric_eigenvalues_non_square_test() {
  let assert Ok(m) = matrix.from_float_list([[1.0, 2.0, 3.0]])
  linalg.symmetric_eigenvalues(m) |> should.be_error()
}
