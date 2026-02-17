import gleam/float
import gleam/string
import gleeunit/should
import waffle/matrix
import waffle/sparse

pub fn from_triplets_identity_test() {
  let triplets = [#(0, 0, 1.0), #(1, 1, 1.0), #(2, 2, 1.0)]
  let assert Ok(s) = sparse.from_triplets(3, 3, triplets)
  sparse.nnz(s) |> should.equal(3)
  sparse.dims(s) |> should.equal(#(3, 3))
}

pub fn from_triplets_to_dense_round_trip_test() {
  let triplets = [#(0, 0, 1.0), #(0, 1, 2.0), #(1, 0, 3.0), #(1, 1, 4.0)]
  let assert Ok(s) = sparse.from_triplets(2, 2, triplets)
  let assert Ok(d) = sparse.to_dense(s)
  matrix.to_list(d) |> should.equal([[1.0, 2.0], [3.0, 4.0]])
}

pub fn from_triplets_empty_test() {
  let result = sparse.from_triplets(2, 2, [])
  result |> should.equal(Error(sparse.EmptyInput))
}

pub fn from_triplets_invalid_dimensions_test() {
  let result = sparse.from_triplets(0, 2, [#(0, 0, 1.0)])
  result |> should.be_error()
}

pub fn from_triplets_index_out_of_bounds_test() {
  let result = sparse.from_triplets(2, 2, [#(5, 0, 1.0)])
  result
  |> should.equal(
    Error(sparse.IndexOutOfBounds(row: 5, col: 0, rows: 2, cols: 2)),
  )
}

pub fn dims_test() {
  let assert Ok(s) = sparse.from_triplets(3, 4, [#(0, 0, 1.0)])
  sparse.dims(s) |> should.equal(#(3, 4))
  sparse.rows(s) |> should.equal(3)
  sparse.cols(s) |> should.equal(4)
}

pub fn nnz_test() {
  let triplets = [#(0, 0, 1.0), #(0, 1, 2.0), #(1, 0, 3.0)]
  let assert Ok(s) = sparse.from_triplets(2, 2, triplets)
  sparse.nnz(s) |> should.equal(3)
}

pub fn get_existing_value_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 5.0), #(1, 1, 7.0)])
  let assert Ok(v1) = sparse.get(s, 0, 0)
  v1 |> should.equal(5.0)
  let assert Ok(v2) = sparse.get(s, 1, 1)
  v2 |> should.equal(7.0)
}

pub fn get_zero_value_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 5.0)])
  let assert Ok(v) = sparse.get(s, 1, 1)
  v |> should.equal(0.0)
}

pub fn get_out_of_bounds_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.get(s, 5, 0) |> should.be_error()
}

pub fn from_dense_test() {
  let assert Ok(d) = matrix.from_list([[1.0, 0.0], [0.0, 2.0]])
  let assert Ok(s) = sparse.from_dense(d)
  sparse.nnz(s) |> should.equal(2)
  let assert Ok(round_trip) = sparse.to_dense(s)
  matrix.to_list(round_trip) |> should.equal([[1.0, 0.0], [0.0, 2.0]])
}

pub fn from_dense_all_zeros_test() {
  let assert Ok(d) = matrix.from_list([[0.0, 0.0], [0.0, 0.0]])
  let assert Ok(s) = sparse.from_dense(d)
  sparse.nnz(s) |> should.equal(0)
}

pub fn transpose_test() {
  let triplets = [#(0, 0, 1.0), #(0, 1, 2.0), #(1, 0, 3.0)]
  let assert Ok(s) = sparse.from_triplets(2, 2, triplets)
  let assert Ok(st) = sparse.transpose(s)
  sparse.dims(st) |> should.equal(#(2, 2))
  let assert Ok(d) = sparse.to_dense(st)
  matrix.to_list(d) |> should.equal([[1.0, 3.0], [2.0, 0.0]])
}

pub fn transpose_rectangular_test() {
  let assert Ok(s) = sparse.from_triplets(2, 3, [#(0, 0, 1.0), #(1, 2, 2.0)])
  let assert Ok(st) = sparse.transpose(s)
  sparse.dims(st) |> should.equal(#(3, 2))
  let assert Ok(d) = sparse.to_dense(st)
  matrix.to_list(d) |> should.equal([[1.0, 0.0], [0.0, 0.0], [0.0, 2.0]])
}

pub fn multiply_dense_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 3.0)])
  let assert Ok(d) = matrix.from_list([[1.0], [2.0]])
  let assert Ok(result) = sparse.multiply_dense(s, d)
  matrix.to_list(result) |> should.equal([[2.0], [6.0]])
}

pub fn multiply_dense_dimension_mismatch_test() {
  let assert Ok(s) = sparse.from_triplets(2, 3, [#(0, 0, 1.0)])
  let assert Ok(d) = matrix.from_list([[1.0], [2.0]])
  sparse.multiply_dense(s, d) |> should.be_error()
}

pub fn to_triplets_test() {
  let triplets = [#(0, 0, 1.0), #(1, 1, 2.0)]
  let assert Ok(s) = sparse.from_triplets(2, 2, triplets)
  let result = sparse.to_triplets(s)
  result |> should.equal(triplets)
}

pub fn multiply_sparse_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 3.0)])
  let assert Ok(b) =
    sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(0, 1, 2.0), #(1, 0, 3.0)])
  let assert Ok(result) = sparse.multiply(a, b)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[2.0, 4.0], [9.0, 0.0]])
}

pub fn multiply_sparse_identity_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 5.0), #(1, 1, 7.0)])
  let assert Ok(id) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 1.0)])
  let assert Ok(result) = sparse.multiply(a, id)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[5.0, 0.0], [0.0, 7.0]])
}

pub fn multiply_sparse_dimension_mismatch_test() {
  let assert Ok(a) = sparse.from_triplets(2, 3, [#(0, 0, 1.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.multiply(a, b) |> should.be_error()
}

pub fn add_sparse_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 2.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 3.0), #(0, 1, 4.0)])
  let assert Ok(result) = sparse.add(a, b)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[4.0, 4.0], [0.0, 2.0]])
}

pub fn add_sparse_same_pattern_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 2.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 3.0), #(1, 1, 4.0)])
  let assert Ok(result) = sparse.add(a, b)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[4.0, 0.0], [0.0, 6.0]])
}

pub fn add_sparse_dimension_mismatch_test() {
  let assert Ok(a) = sparse.from_triplets(2, 3, [#(0, 0, 1.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.add(a, b) |> should.be_error()
}

pub fn scale_sparse_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 4.0)])
  let assert Ok(scaled) = sparse.scale(s, 3.0)
  let assert Ok(dense) = sparse.to_dense(scaled)
  matrix.to_list(dense) |> should.equal([[6.0, 0.0], [0.0, 12.0]])
}

pub fn scale_sparse_by_zero_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 4.0)])
  let assert Ok(scaled) = sparse.scale(s, 0.0)
  let assert Ok(dense) = sparse.to_dense(scaled)
  matrix.to_list(dense) |> should.equal([[0.0, 0.0], [0.0, 0.0]])
}

pub fn map_sparse_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 2.0)])
  let mapped = sparse.map(s, fn(x) { x *. 10.0 })
  let assert Ok(dense) = sparse.to_dense(mapped)
  matrix.to_list(dense) |> should.equal([[10.0, 0.0], [0.0, 20.0]])
}

pub fn map_all_to_zero_test() {
  let assert Ok(s) = sparse.from_triplets(2, 3, [#(0, 0, 1.0), #(1, 2, 2.0)])
  let mapped = sparse.map(s, fn(_) { 0.0 })
  sparse.nnz(mapped) |> should.equal(0)
  let assert Ok(dense) = sparse.to_dense(mapped)
  matrix.to_list(dense)
  |> should.equal([[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
}

pub fn fold_sparse_sum_test() {
  let assert Ok(s) =
    sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(0, 1, 2.0), #(1, 0, 3.0)])
  let sum = sparse.fold(s, 0.0, fn(acc, x) { acc +. x })
  sum |> should.equal(6.0)
}

pub fn fold_sparse_max_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 5.0)])
  let max = sparse.fold(s, 0.0, fn(acc, x) { float.max(acc, x) })
  max |> should.equal(5.0)
}

pub fn fold_with_indices_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 2.0)])
  let result =
    sparse.fold_with_indices(s, [], fn(acc, row, col, val) {
      [#(row, col, val), ..acc]
    })
  result |> should.equal([#(1, 1, 2.0), #(0, 0, 1.0)])
}

pub fn subtract_sparse_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 5.0), #(1, 1, 3.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(0, 1, 1.0)])
  let assert Ok(result) = sparse.subtract(a, b)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[3.0, -1.0], [0.0, 3.0]])
}

pub fn subtract_sparse_same_pattern_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 5.0), #(1, 1, 3.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 1.0)])
  let assert Ok(result) = sparse.subtract(a, b)
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[3.0, 0.0], [0.0, 2.0]])
}

pub fn subtract_sparse_dimension_mismatch_test() {
  let assert Ok(a) = sparse.from_triplets(2, 3, [#(0, 0, 1.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.subtract(a, b) |> should.be_error()
}

pub fn row_test() {
  let assert Ok(s) =
    sparse.from_triplets(2, 3, [#(0, 0, 1.0), #(0, 2, 2.0), #(1, 1, 3.0)])
  let assert Ok(r) = sparse.row(s, 0)
  r |> should.equal([1.0, 0.0, 2.0])
  let assert Ok(r) = sparse.row(s, 1)
  r |> should.equal([0.0, 3.0, 0.0])
}

pub fn row_out_of_bounds_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.row(s, 5) |> should.be_error()
}

pub fn col_test() {
  let assert Ok(s) =
    sparse.from_triplets(2, 3, [#(0, 0, 1.0), #(0, 2, 2.0), #(1, 1, 3.0)])
  let assert Ok(c) = sparse.col(s, 0)
  c |> should.equal([1.0, 0.0])
  let assert Ok(c) = sparse.col(s, 1)
  c |> should.equal([0.0, 3.0])
  let assert Ok(c) = sparse.col(s, 2)
  c |> should.equal([2.0, 0.0])
}

pub fn col_out_of_bounds_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.col(s, 5) |> should.be_error()
}

pub fn zip_with_add_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 1.0), #(1, 1, 2.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 3.0), #(0, 1, 4.0)])
  let assert Ok(result) = sparse.zip_with(a, b, fn(x, y) { x +. y })
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[4.0, 4.0], [0.0, 2.0]])
}

pub fn zip_with_multiply_test() {
  let assert Ok(a) = sparse.from_triplets(2, 2, [#(0, 0, 2.0), #(1, 1, 3.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 5.0), #(1, 1, 4.0)])
  let assert Ok(result) = sparse.zip_with(a, b, fn(x, y) { x *. y })
  let assert Ok(dense) = sparse.to_dense(result)
  matrix.to_list(dense) |> should.equal([[10.0, 0.0], [0.0, 12.0]])
}

pub fn zip_with_dimension_mismatch_test() {
  let assert Ok(a) = sparse.from_triplets(2, 3, [#(0, 0, 1.0)])
  let assert Ok(b) = sparse.from_triplets(2, 2, [#(0, 0, 1.0)])
  sparse.zip_with(a, b, fn(x, y) { x +. y }) |> should.be_error()
}

pub fn to_string_test() {
  let assert Ok(s) = sparse.from_triplets(2, 2, [#(0, 0, 1.5), #(1, 1, 2.5)])
  let str = sparse.to_string(s)
  should.be_true(string.contains(str, "SparseMatrix 2x2:"))
  should.be_true(string.contains(str, "(0, 0): 1.5"))
  should.be_true(string.contains(str, "(1, 1): 2.5"))
}

pub fn from_triplets_duplicate_entries_summed_test() {
  let triplets = [#(0, 0, 1.0), #(0, 0, 2.0), #(1, 1, 3.0)]
  let assert Ok(s) = sparse.from_triplets(2, 2, triplets)
  let assert Ok(dense) = sparse.to_dense(s)
  matrix.to_list(dense) |> should.equal([[3.0, 0.0], [0.0, 3.0]])
}

pub fn from_triplets_negative_row_test() {
  let result = sparse.from_triplets(2, 2, [#(-1, 0, 1.0)])
  result
  |> should.equal(
    Error(sparse.IndexOutOfBounds(row: -1, col: 0, rows: 2, cols: 2)),
  )
}

pub fn from_triplets_negative_col_test() {
  let result = sparse.from_triplets(2, 2, [#(0, -1, 1.0)])
  result
  |> should.equal(
    Error(sparse.IndexOutOfBounds(row: 0, col: -1, rows: 2, cols: 2)),
  )
}
