import gleam/float
import gleam/list
import gleeunit/should
import waffle/linalg
import waffle/matrix

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
// solve
// ---------------------------------------------------------------------------

pub fn identity_matrix_test() {
  let assert Ok(id_2x2) = matrix.identity(2)
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])
  let assert Ok(x) = linalg.solve(id_2x2, b)
  matrix.to_list(x)
  |> should.equal([[1.0], [2.0]])
}

pub fn simple_2x2_test() {
  let assert Ok(a) = matrix.from_list([[2.0, 1.0], [1.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[3.0], [2.0]])
  let assert Ok(x) = linalg.solve(a, b)

  let x_list = matrix.to_list(x)

  x_list
  |> should.equal([[1.0], [1.0]])
}

pub fn simple_3x3_test() {
  let assert Ok(a) =
    matrix.from_list([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[2.0], [3.0], [4.0]])
  let assert Ok(x) = linalg.solve(a, b)

  let x_list = matrix.to_list(x)

  x_list
  |> should.equal([[2.0], [3.0], [4.0]])
}

pub fn singular_matrix_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])

  let result = linalg.solve(a, b)

  result
  |> should.equal(Error(matrix.SingularMatrix))
}

pub fn non_square_matrix_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0]])

  let result = linalg.solve(a, b)

  result
  |> should.be_error()
}

pub fn dimension_mismatch_test() {
  let assert Ok(a) = matrix.from_list([[1.0, 0.0], [0.0, 1.0]])
  let assert Ok(b) = matrix.from_list([[1.0], [2.0], [3.0]])

  let result = linalg.solve(a, b)

  result
  |> should.be_error()
}

// ---------------------------------------------------------------------------
// determinant
// ---------------------------------------------------------------------------

pub fn determinant_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, 1.0, 1.0e-10))
}

pub fn determinant_known_2x2_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, -2.0, 1.0e-10))
}

pub fn determinant_singular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  let assert Ok(det) = linalg.determinant(m)
  should.be_true(approx_equal(det, 0.0, 1.0e-10))
}

pub fn determinant_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  linalg.determinant(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// inverse
// ---------------------------------------------------------------------------

pub fn inverse_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(inv) = linalg.inverse(m)
  should.be_true(approx_equal_matrix(inv, m, 1.0e-10))
}

pub fn inverse_known_2x2_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(inv) = linalg.inverse(m)
  let assert Ok(product) = matrix.multiply(m, inv)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(product, i, 1.0e-10))
}

pub fn inverse_singular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [2.0, 4.0]])
  linalg.inverse(m) |> should.equal(Error(matrix.SingularMatrix))
}

pub fn inverse_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  linalg.inverse(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// LU decomposition
// ---------------------------------------------------------------------------

pub fn lu_2x2_test() {
  let assert Ok(m) = matrix.from_list([[2.0, 1.0], [4.0, 3.0]])
  let assert Ok(linalg.LU(l: l, u: u, pivot: pivot)) = linalg.lu(m)

  let assert Ok(l00) = matrix.get(l, 0, 0)
  should.be_true(approx_equal(l00, 1.0, 1.0e-10))
  let assert Ok(l01) = matrix.get(l, 0, 1)
  should.be_true(approx_equal(l01, 0.0, 1.0e-10))

  let assert Ok(u10) = matrix.get(u, 1, 0)
  should.be_true(approx_equal(u10, 0.0, 1.0e-10))

  let assert Ok(lu_product) = matrix.multiply(l, u)

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
  let assert Ok(linalg.LU(l: l, u: u, pivot: _pivot)) = linalg.lu(m)
  let assert Ok(i) = matrix.identity(3)
  should.be_true(approx_equal_matrix(l, i, 1.0e-10))
  should.be_true(approx_equal_matrix(u, i, 1.0e-10))
}

pub fn lu_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  linalg.lu(m) |> should.be_error()
}

// ---------------------------------------------------------------------------
// QR decomposition
// ---------------------------------------------------------------------------

pub fn qr_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(linalg.QR(q: q, r: r)) = linalg.qr(m)

  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = matrix.multiply(qt, q)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  let assert Ok(qr_product) = matrix.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

pub fn qr_rectangular_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  let assert Ok(linalg.QR(q: q, r: r)) = linalg.qr(m)

  matrix.rows(q) |> should.equal(3)
  matrix.cols(q) |> should.equal(2)
  matrix.rows(r) |> should.equal(2)
  matrix.cols(r) |> should.equal(2)

  let assert Ok(qt) = matrix.transpose(q)
  let assert Ok(qtq) = matrix.multiply(qt, q)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(qtq, i, 1.0e-10))

  let assert Ok(qr_product) = matrix.multiply(q, r)
  should.be_true(approx_equal_matrix(qr_product, m, 1.0e-10))
}

// ---------------------------------------------------------------------------
// SVD decomposition
// ---------------------------------------------------------------------------

pub fn svd_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  let assert Ok(linalg.SVD(u: u, singular_values: s, v: v)) = linalg.svd(m)

  let assert Ok(ut) = matrix.transpose(u)
  let assert Ok(utu) = matrix.multiply(ut, u)
  let assert Ok(i) = matrix.identity(2)
  should.be_true(approx_equal_matrix(utu, i, 1.0e-10))

  let assert Ok(vt) = matrix.transpose(v)
  let assert Ok(vtv) = matrix.multiply(vt, v)
  should.be_true(approx_equal_matrix(vtv, i, 1.0e-10))

  should.be_true(list.all(s, fn(x) { x >=. 0.0 }))
  should.be_true(is_descending(s))

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
  let assert Ok(linalg.SVD(u: u, singular_values: s, v: v)) = linalg.svd(m)

  matrix.rows(u) |> should.equal(3)
  matrix.cols(u) |> should.equal(2)
  matrix.rows(v) |> should.equal(2)
  matrix.cols(v) |> should.equal(2)
  list.length(s) |> should.equal(2)

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
  let assert Ok(eigenvalues) = linalg.symmetric_eigenvalues(m)
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 2.0, 3.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_identity_test() {
  let assert Ok(m) = matrix.identity(3)
  let assert Ok(eigenvalues) = linalg.symmetric_eigenvalues(m)
  should.be_true(approx_equal_lists(eigenvalues, [1.0, 1.0, 1.0], 1.0e-10))
}

pub fn symmetric_eigenvalues_non_symmetric_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0], [3.0, 4.0]])
  linalg.symmetric_eigenvalues(m) |> should.be_error()
}

pub fn symmetric_eigenvalues_non_square_test() {
  let assert Ok(m) = matrix.from_list([[1.0, 2.0, 3.0]])
  linalg.symmetric_eigenvalues(m) |> should.be_error()
}
