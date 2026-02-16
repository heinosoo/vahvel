@external(erlang, "nif", "sparse_from_triplets")
pub fn sparse_from_triplets(
  rows: Int,
  cols: Int,
  row_indices: BitArray,
  col_indices: BitArray,
  values: BitArray,
) -> Result(#(Int, BitArray, BitArray, BitArray), String)

@external(erlang, "nif", "sparse_to_dense")
pub fn sparse_to_dense(
  rows: Int,
  cols: Int,
  nnz: Int,
  col_ptr: BitArray,
  row_indices: BitArray,
  values: BitArray,
) -> Result(BitArray, String)

@external(erlang, "nif", "sparse_from_dense")
pub fn sparse_from_dense(
  rows: Int,
  cols: Int,
  data: BitArray,
) -> Result(#(Int, BitArray, BitArray, BitArray), String)

@external(erlang, "nif", "sparse_transpose")
pub fn sparse_transpose(
  rows: Int,
  cols: Int,
  nnz: Int,
  col_ptr: BitArray,
  row_indices: BitArray,
  values: BitArray,
) -> Result(#(Int, Int, Int, BitArray, BitArray, BitArray), String)

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
