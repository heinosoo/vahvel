//// Random matrix generation with configurable distributions.
////
//// Generate matrices filled with random values from various distributions.
//// All functions have seeded variants for reproducibility.
////
//// ## Distributions
////
//// - `uniform(rows, cols, min, max)` — uniform distribution in [min, max)
//// - `normal(rows, cols, mean, std_dev)` — normal (Gaussian) distribution
//// - `bernoulli(rows, cols, p)` — Bernoulli (0.0 or 1.0) with probability p
////
//// ## Seeded variants
////
//// For reproducible results, use the `_seeded` variants:
////
//// ```gleam
//// let assert Ok(m1) = uniform_seeded(3, 3, 0.0, 1.0, 42)
//// let assert Ok(m2) = uniform_seeded(3, 3, 0.0, 1.0, 42)
//// // m1 == m2 (same seed produces same matrix)
//// ```

import gleam/result
import waffle/internal/random
import waffle/matrix

/// Errors that can occur during random matrix generation.
pub type RandomError {
  /// Dimensions were invalid (zero or negative).
  InvalidDimensions(message: String)
  /// Distribution parameters were invalid.
  InvalidDistribution(message: String)
}

fn classify_error(msg: String) -> RandomError {
  case msg {
    "Dimensions must be positive" -> InvalidDimensions(msg)
    "Invalid uniform distribution parameters" -> InvalidDistribution(msg)
    "Invalid normal distribution parameters" -> InvalidDistribution(msg)
    "Invalid bernoulli probability (must be in [0, 1])" ->
      InvalidDistribution(msg)
    _ -> InvalidDistribution(msg)
  }
}

fn nif_result_to_matrix(
  result: Result(#(Int, Int, BitArray), String),
) -> Result(matrix.Matrix, RandomError) {
  use #(r, c, data) <- result.try(result.map_error(result, classify_error))
  use m <- result.try(
    matrix.from_binary(r, c, data)
    |> result.map_error(fn(_) { InvalidDimensions("Failed to create matrix") }),
  )
  Ok(m)
}

/// Generate a matrix with uniformly distributed random values in [min, max).
/// Returns an error if dimensions are invalid or if min > max.
pub fn uniform(
  rows: Int,
  cols: Int,
  min: Float,
  max: Float,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.uniform(rows, cols, min, max))
}

/// Generate a matrix with uniformly distributed random values using a seed.
/// Returns an error if dimensions are invalid or if min > max.
pub fn uniform_seeded(
  rows: Int,
  cols: Int,
  min: Float,
  max: Float,
  seed: Int,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.uniform_seeded(rows, cols, min, max, seed))
}

/// Generate a matrix with normally distributed random values.
/// Returns an error if dimensions are invalid or if std_dev <= 0.
pub fn normal(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.normal(rows, cols, mean, std_dev))
}

/// Generate a matrix with normally distributed random values using a seed.
/// Returns an error if dimensions are invalid or if std_dev <= 0.
pub fn normal_seeded(
  rows: Int,
  cols: Int,
  mean: Float,
  std_dev: Float,
  seed: Int,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.normal_seeded(rows, cols, mean, std_dev, seed))
}

/// Generate a matrix with Bernoulli distributed random values (0.0 or 1.0).
/// Returns an error if dimensions are invalid or if p is not in [0, 1].
pub fn bernoulli(
  rows: Int,
  cols: Int,
  p: Float,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.bernoulli(rows, cols, p))
}

/// Generate a matrix with Bernoulli distributed random values using a seed.
/// Returns an error if dimensions are invalid or if p is not in [0, 1].
pub fn bernoulli_seeded(
  rows: Int,
  cols: Int,
  p: Float,
  seed: Int,
) -> Result(matrix.Matrix, RandomError) {
  nif_result_to_matrix(random.bernoulli_seeded(rows, cols, p, seed))
}
