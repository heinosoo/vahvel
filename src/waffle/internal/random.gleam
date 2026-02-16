@external(erlang, "nif", "random_uniform")
pub fn uniform(
  rows: Int,
  cols: Int,
  min: Float,
  max: Float,
) -> Result(#(Int, Int, BitArray), String)

@external(erlang, "nif", "random_uniform_seeded")
pub fn uniform_seeded(
  rows: Int,
  cols: Int,
  min: Float,
  max: Float,
  seed: Int,
) -> Result(#(Int, Int, BitArray), String)

@external(erlang, "nif", "random_normal")
pub fn normal(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
) -> Result(#(Int, Int, BitArray), String)

@external(erlang, "nif", "random_normal_seeded")
pub fn normal_seeded(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
  seed: Int,
) -> Result(#(Int, Int, BitArray), String)

@external(erlang, "nif", "random_bernoulli")
pub fn bernoulli(
  rows: Int,
  cols: Int,
  p: Float,
) -> Result(#(Int, Int, BitArray), String)

@external(erlang, "nif", "random_bernoulli_seeded")
pub fn bernoulli_seeded(
  rows: Int,
  cols: Int,
  p: Float,
  seed: Int,
) -> Result(#(Int, Int, BitArray), String)
