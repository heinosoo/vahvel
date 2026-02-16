//// Low-level NIF wrappers for faer operations.
//// These operate on raw components (rows, cols, BitArray) — not the public types.
//// Use the convenience functions in `waffle/matrix`, `waffle/sparse`, `waffle/linalg` instead.

// ---------------------------------------------------------------------------
// Dense matrix operations
// ---------------------------------------------------------------------------

/// Element-wise matrix addition. Both matrices must have the same dimensions.
@external(erlang, "nif", "matrix_add")
pub fn matrix_add(
  rows: Int,
  cols: Int,
  a: BitArray,
  b: BitArray,
) -> Result(BitArray, String)

/// Element-wise matrix subtraction. Both matrices must have the same dimensions.
@external(erlang, "nif", "matrix_subtract")
pub fn matrix_subtract(
  rows: Int,
  cols: Int,
  a: BitArray,
  b: BitArray,
) -> Result(BitArray, String)

/// Scalar multiplication of a matrix.
@external(erlang, "nif", "matrix_scale")
pub fn matrix_scale(
  rows: Int,
  cols: Int,
  data: BitArray,
  scalar: Float,
) -> Result(BitArray, String)

/// Matrix multiplication. a_cols must equal b_rows.
@external(erlang, "nif", "matrix_multiply")
pub fn matrix_multiply(
  a_rows: Int,
  a_cols: Int,
  a: BitArray,
  b_rows: Int,
  b_cols: Int,
  b: BitArray,
) -> Result(BitArray, String)

/// Transpose a matrix.
@external(erlang, "nif", "transpose")
pub fn transpose(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(BitArray, String)

/// Compute the determinant of an n×n matrix.
@external(erlang, "nif", "matrix_determinant")
pub fn matrix_determinant(n: Int, data: BitArray) -> Result(Float, String)

/// Compute the inverse of an n×n matrix.
@external(erlang, "nif", "matrix_inverse")
pub fn matrix_inverse(n: Int, data: BitArray) -> Result(BitArray, String)

/// LU decomposition with partial pivoting of an n×n matrix.
@external(erlang, "nif", "matrix_lu")
pub fn matrix_lu(
  n: Int,
  data: BitArray,
) -> Result(
  #(#(Int, Int, BitArray), #(Int, Int, BitArray), #(Int, BitArray)),
  String,
)

/// Thin QR decomposition.
@external(erlang, "nif", "matrix_qr")
pub fn matrix_qr(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(#(#(Int, Int, BitArray), #(Int, Int, BitArray)), String)

/// Thin SVD decomposition.
@external(erlang, "nif", "matrix_svd")
pub fn matrix_svd(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(
  #(#(Int, Int, BitArray), #(Int, BitArray), #(Int, Int, BitArray)),
  String,
)

/// Eigenvalues of a symmetric matrix.
@external(erlang, "nif", "matrix_symmetric_eigenvalues")
pub fn matrix_symmetric_eigenvalues(
  n: Int,
  data: BitArray,
) -> Result(BitArray, String)

/// Solve the linear system Ax = b.
@external(erlang, "nif", "solve_linear_system")
pub fn solve_linear_system(
  rows: Int,
  cols: Int,
  a_data: BitArray,
  b_data: BitArray,
) -> Result(BitArray, String)

// ---------------------------------------------------------------------------
// Sparse matrix operations
// ---------------------------------------------------------------------------

/// Build sparse matrix from triplets.
@external(erlang, "nif", "sparse_from_triplets")
pub fn sparse_from_triplets(
  rows: Int,
  cols: Int,
  row_indices: BitArray,
  col_indices: BitArray,
  values: BitArray,
) -> Result(#(Int, BitArray, BitArray, BitArray), String)

/// Convert sparse matrix to dense.
@external(erlang, "nif", "sparse_to_dense")
pub fn sparse_to_dense(
  rows: Int,
  cols: Int,
  nnz: Int,
  col_ptr: BitArray,
  row_indices: BitArray,
  values: BitArray,
) -> Result(BitArray, String)

/// Convert dense matrix to sparse.
@external(erlang, "nif", "sparse_from_dense")
pub fn sparse_from_dense(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(#(Int, BitArray, BitArray, BitArray), String)

/// Transpose a sparse matrix.
@external(erlang, "nif", "sparse_transpose")
pub fn sparse_transpose(
  rows: Int,
  cols: Int,
  nnz: Int,
  col_ptr: BitArray,
  row_indices: BitArray,
  values: BitArray,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)

/// Multiply sparse matrix by dense matrix.
@external(erlang, "nif", "sparse_multiply_dense")
pub fn sparse_multiply_dense(
  sp_rows: Int,
  sp_cols: Int,
  sp_nnz: Int,
  sp_col_ptr: BitArray,
  sp_row_indices: BitArray,
  sp_values: BitArray,
  d_rows: Int,
  d_cols: Int,
  d_data: BitArray,
) -> Result(BitArray, String)

/// Multiply two sparse matrices.
@external(erlang, "nif", "sparse_multiply")
pub fn sparse_multiply(
  a_rows: Int,
  a_cols: Int,
  a_nnz: Int,
  a_col_ptr: BitArray,
  a_row_indices: BitArray,
  a_values: BitArray,
  b_rows: Int,
  b_cols: Int,
  b_nnz: Int,
  b_col_ptr: BitArray,
  b_row_indices: BitArray,
  b_values: BitArray,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)

/// Add two sparse matrices.
@external(erlang, "nif", "sparse_add")
pub fn sparse_add(
  a_rows: Int,
  a_cols: Int,
  a_nnz: Int,
  a_col_ptr: BitArray,
  a_row_indices: BitArray,
  a_values: BitArray,
  b_rows: Int,
  b_cols: Int,
  b_nnz: Int,
  b_col_ptr: BitArray,
  b_row_indices: BitArray,
  b_values: BitArray,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)

/// Subtract two sparse matrices.
@external(erlang, "nif", "sparse_subtract")
pub fn sparse_subtract(
  a_rows: Int,
  a_cols: Int,
  a_nnz: Int,
  a_col_ptr: BitArray,
  a_row_indices: BitArray,
  a_values: BitArray,
  b_rows: Int,
  b_cols: Int,
  b_nnz: Int,
  b_col_ptr: BitArray,
  b_row_indices: BitArray,
  b_values: BitArray,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)

/// Scale a sparse matrix by a scalar.
@external(erlang, "nif", "sparse_scale")
pub fn sparse_scale(
  rows: Int,
  cols: Int,
  nnz: Int,
  col_ptr: BitArray,
  row_indices: BitArray,
  values: BitArray,
  scalar: Float,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)
