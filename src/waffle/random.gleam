import waffle/internal/random
import waffle/matrix

fn nif_result_to_matrix(
  result: Result(#(Int, Int, BitArray), String),
) -> matrix.Matrix {
  let assert Ok(#(r, c, data)) = result
  let assert Ok(m) = matrix.from_binary(r, c, data)
  m
}

/// Generate a matrix with uniformly distributed random values in [min, max).
pub fn uniform(rows: Int, cols: Int, min: Float, max: Float) -> matrix.Matrix {
  nif_result_to_matrix(random.uniform(rows, cols, min, max))
}

/// Generate a matrix with uniformly distributed random values using a seed.
pub fn uniform_seeded(
  rows: Int,
  cols: Int,
  min: Float,
  max: Float,
  seed: Int,
) -> matrix.Matrix {
  nif_result_to_matrix(random.uniform_seeded(rows, cols, min, max, seed))
}

/// Generate a matrix with normally distributed random values.
pub fn normal(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
) -> matrix.Matrix {
  nif_result_to_matrix(random.normal(rows, cols, mean, std_dev))
}

/// Generate a matrix with normally distributed random values using a seed.
pub fn normal_seeded(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
  seed: Int,
) -> matrix.Matrix {
  nif_result_to_matrix(random.normal_seeded(rows, cols, mean, std_dev, seed))
}

/// Generate a matrix with Bernoulli distributed random values (0.0 or 1.0).
pub fn bernoulli(rows: Int, cols: Int, p: Float) -> matrix.Matrix {
  nif_result_to_matrix(random.bernoulli(rows, cols, p))
}

/// Generate a matrix with Bernoulli distributed random values using a seed.
pub fn bernoulli_seeded(
  rows: Int,
  cols: Int,
  p: Float,
  seed: Int,
) -> matrix.Matrix {
  nif_result_to_matrix(random.bernoulli_seeded(rows, cols, p, seed))
}
