//// Low-level NIF wrappers for faer decomposition, solver, and property operations.
//// These operate on raw components (rows, cols, BitArray) — not the opaque Matrix type.
//// Use the convenience functions in `waffle/matrix` and `waffle/solver` instead.

/// Compute the determinant of an n×n matrix.
@external(erlang, "nif", "matrix_determinant")
pub fn determinant(n: Int, data: BitArray) -> Result(Float, String)

/// Compute the inverse of an n×n matrix.
/// Returns {ok, binary} or {error, "Matrix is singular"}.
@external(erlang, "nif", "matrix_inverse")
pub fn inverse(n: Int, data: BitArray) -> Result(BitArray, String)

/// LU decomposition with partial pivoting of an n×n matrix.
/// Returns {ok, {{l_rows, l_cols, l_bin}, {u_rows, u_cols, u_bin}, {n, pivot_bin}}}.
@external(erlang, "nif", "matrix_lu")
pub fn lu(
  n: Int,
  data: BitArray,
) -> Result(
  #(#(Int, Int, BitArray), #(Int, Int, BitArray), #(Int, BitArray)),
  String,
)

/// Thin QR decomposition.
/// Returns {ok, {{q_rows, q_cols, q_bin}, {r_rows, r_cols, r_bin}}}.
@external(erlang, "nif", "matrix_qr")
pub fn qr(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(#(#(Int, Int, BitArray), #(Int, Int, BitArray)), String)

/// Thin SVD decomposition.
/// Returns {ok, {{u_rows, u_cols, u_bin}, {s_len, s_bin}, {v_rows, v_cols, v_bin}}}.
@external(erlang, "nif", "matrix_svd")
pub fn svd(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(
  #(#(Int, Int, BitArray), #(Int, BitArray), #(Int, Int, BitArray)),
  String,
)

/// Eigenvalues of a symmetric matrix.
/// Returns {ok, eigenvalues_bin} where eigenvalues are in nondecreasing order.
@external(erlang, "nif", "matrix_symmetric_eigenvalues")
pub fn symmetric_eigenvalues(n: Int, data: BitArray) -> Result(BitArray, String)

/// Solve the linear system Ax = b.
@external(erlang, "nif", "solve_linear_system")
pub fn solve_linear_system(
  rows: Int,
  cols: Int,
  a_data: BitArray,
  b_data: BitArray,
) -> Result(BitArray, String)
