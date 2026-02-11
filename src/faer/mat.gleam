//// Low-level NIF wrappers for faer matrix arithmetic operations.
//// These operate on raw components (rows, cols, BitArray) — not the opaque Matrix type.
//// Use the convenience functions in `matrix.gleam` instead.

/// Element-wise matrix addition. Both matrices must have the same dimensions.
@external(erlang, "nif", "matrix_add")
@internal
pub fn add(
  rows: Int,
  cols: Int,
  a: BitArray,
  b: BitArray,
) -> Result(BitArray, String)

/// Element-wise matrix subtraction. Both matrices must have the same dimensions.
@external(erlang, "nif", "matrix_subtract")
@internal
pub fn subtract(
  rows: Int,
  cols: Int,
  a: BitArray,
  b: BitArray,
) -> Result(BitArray, String)

/// Scalar multiplication of a matrix.
@external(erlang, "nif", "matrix_scale")
@internal
pub fn scale(
  rows: Int,
  cols: Int,
  data: BitArray,
  scalar: Float,
) -> Result(BitArray, String)

/// Matrix multiplication. a_cols must equal b_rows.
@external(erlang, "nif", "matrix_multiply")
@internal
pub fn multiply(
  a_rows: Int,
  a_cols: Int,
  a: BitArray,
  b_rows: Int,
  b_cols: Int,
  b: BitArray,
) -> Result(BitArray, String)

/// Transpose a matrix.
@external(erlang, "nif", "transpose")
@internal
pub fn transpose(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(BitArray, String)
