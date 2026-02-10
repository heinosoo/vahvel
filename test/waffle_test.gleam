import gleeunit
import gleeunit/should
import waffle

pub fn main() {
  gleeunit.main()
}

pub fn add_floats_test() {
  waffle.add_floats(1.0, 2.0)
  |> should.equal(3.0)
}
