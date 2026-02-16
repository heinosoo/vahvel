@external(erlang, "nif", "solve_ilp")
pub fn solve_ilp(
  direction: Int,
  obj_offset: Float,
  obj_coeffs_bin: BitArray,
  con_rows: Int,
  con_cols: Int,
  con_nnz: Int,
  con_col_ptr_bin: BitArray,
  con_row_idx_bin: BitArray,
  con_vals_bin: BitArray,
  con_bounds_bin: BitArray,
  var_bounds_bin: BitArray,
  var_types_bin: BitArray,
) -> Result(#(Int, Float, BitArray, BitArray), String)
