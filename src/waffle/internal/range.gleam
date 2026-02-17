/// Internal utilities for iterating over integer ranges without
/// allocating intermediate lists.
/// Map a function over `[start, stop)`, returning results in order.
pub fn map(from start: Int, to stop: Int, with f: fn(Int) -> a) -> List(a) {
  map_loop(stop - 1, start, f, [])
}

fn map_loop(current: Int, stop: Int, f: fn(Int) -> a, acc: List(a)) -> List(a) {
  case current < stop {
    True -> acc
    False -> map_loop(current - 1, stop, f, [f(current), ..acc])
  }
}

/// Check that all integers in `[start, stop)` satisfy a predicate.
/// Short-circuits on the first `False`.
pub fn all(
  from start: Int,
  to stop: Int,
  check predicate: fn(Int) -> Bool,
) -> Bool {
  case start >= stop {
    True -> True
    False ->
      case predicate(start) {
        False -> False
        True -> all(start + 1, stop, predicate)
      }
  }
}
