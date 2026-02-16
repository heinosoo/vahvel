import gleam/list
import gleeunit/should
import waffle/matrix
import waffle/random

pub fn uniform_dimensions_test() {
  let m = random.uniform(3, 4, 0.0, 1.0)
  matrix.rows(m) |> should.equal(3)
  matrix.cols(m) |> should.equal(4)
}

pub fn uniform_seeded_deterministic_test() {
  let m1 = random.uniform_seeded(2, 3, 0.0, 10.0, 42)
  let m2 = random.uniform_seeded(2, 3, 0.0, 10.0, 42)
  matrix.to_list(m1) |> should.equal(matrix.to_list(m2))
}

pub fn uniform_seeded_different_seeds_test() {
  let m1 = random.uniform_seeded(2, 3, 0.0, 10.0, 42)
  let m2 = random.uniform_seeded(2, 3, 0.0, 10.0, 123)
  matrix.to_list(m1) |> should.not_equal(matrix.to_list(m2))
}

pub fn normal_dimensions_test() {
  let m = random.normal(5, 2, 0.0, 1.0)
  matrix.rows(m) |> should.equal(5)
  matrix.cols(m) |> should.equal(2)
}

pub fn normal_seeded_deterministic_test() {
  let m1 = random.normal_seeded(3, 3, 5.0, 2.0, 99)
  let m2 = random.normal_seeded(3, 3, 5.0, 2.0, 99)
  matrix.to_list(m1) |> should.equal(matrix.to_list(m2))
}

pub fn bernoulli_dimensions_test() {
  let m = random.bernoulli(4, 5, 0.5)
  matrix.rows(m) |> should.equal(4)
  matrix.cols(m) |> should.equal(5)
}

pub fn bernoulli_values_are_0_or_1_test() {
  let m = random.bernoulli(10, 10, 0.5)
  let values = list.flatten(matrix.to_list(m))
  let all_valid = list.all(values, fn(x) { x == 0.0 || x == 1.0 })
  should.be_true(all_valid)
}

pub fn bernoulli_seeded_deterministic_test() {
  let m1 = random.bernoulli_seeded(3, 4, 0.7, 42)
  let m2 = random.bernoulli_seeded(3, 4, 0.7, 42)
  matrix.to_list(m1) |> should.equal(matrix.to_list(m2))
}

pub fn bernoulli_all_ones_with_p_1_test() {
  let m = random.bernoulli_seeded(3, 3, 1.0, 1)
  let values = list.flatten(matrix.to_list(m))
  let all_ones = list.all(values, fn(x) { x == 1.0 })
  should.be_true(all_ones)
}

pub fn bernoulli_all_zeros_with_p_0_test() {
  let m = random.bernoulli_seeded(3, 3, 0.0, 1)
  let values = list.flatten(matrix.to_list(m))
  let all_zeros = list.all(values, fn(x) { x == 0.0 })
  should.be_true(all_zeros)
}
