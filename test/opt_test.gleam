import gleam/float
import gleam/list
import gleeunit/should
import waffle/opt

pub fn continuous_lp_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, x) = opt.add_variable(model, 3.0, 0.0, 100.0, opt.Continuous)
  let #(model, y) = opt.add_variable(model, 4.0, 0.0, 100.0, opt.Continuous)

  let assert Ok(model) =
    opt.add_constraint(model, -1000.0, 8.0, [#(x, 2.0), #(y, 3.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)

  should.be_true(float.loosely_equals(solution.objective_value, 12.0, 0.001))

  should.equal(list.length(solution.primal), 2)
  let assert [val_x, val_y] = solution.primal
  should.be_true(float.loosely_equals(val_x, 4.0, 0.001))
  should.be_true(float.loosely_equals(val_y, 0.0, 0.001))
}

pub fn ilp_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, x) = opt.add_variable(model, 0.0, 0.0, 10.0, opt.Integer)
  let #(model, y) = opt.add_variable(model, 1.0, 0.0, 10.0, opt.Integer)

  let assert Ok(model) =
    opt.add_constraint(model, -1000.0, 9.0, [#(x, 2.0), #(y, 2.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)

  should.be_true(float.loosely_equals(solution.objective_value, 4.0, 0.001))

  should.equal(list.length(solution.primal), 2)
  let assert [val_x, val_y] = solution.primal
  should.be_true(float.loosely_equals(val_y, 4.0, 0.001))
  should.be_true(float.loosely_equals(val_x, 0.0, 0.001))
}

pub fn infeasible_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, x) = opt.add_variable(model, 1.0, 0.0, 100.0, opt.Continuous)

  let assert Ok(model) = opt.add_constraint(model, 5.0, 1000.0, [#(x, 1.0)])
  let assert Ok(model) = opt.add_constraint(model, -1000.0, 3.0, [#(x, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Infeasible)
}

pub fn invalid_variable_id_test() {
  let model = opt.new()
  let #(model, x) = opt.add_variable(model, 1.0, 0.0, 10.0, opt.Continuous)

  let result = opt.add_constraint(model, 0.0, 10.0, [#(99, 1.0)])
  should.be_error(result)

  let result = opt.add_constraint(model, 0.0, 10.0, [#(x, 1.0), #(5, 2.0)])
  should.be_error(result)

  let assert Ok(model) = opt.add_constraint(model, 0.0, 10.0, [#(x, 1.0)])
  let #(model, y) = opt.add_variable(model, 2.0, 0.0, 10.0, opt.Continuous)

  let result = opt.add_constraint(model, 0.0, 10.0, [#(y, 1.0)])
  should.be_ok(result)
}

pub fn unbounded_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, _x) = opt.add_variable(model, 1.0, 0.0, 1.0e30, opt.Continuous)

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Unbounded)
}

pub fn no_constraints_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, _x) = opt.add_variable(model, 3.0, 0.0, 10.0, opt.Continuous)
  let #(model, _y) = opt.add_variable(model, -1.0, 0.0, 5.0, opt.Continuous)

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 30.0, 0.001))

  should.equal(list.length(solution.primal), 2)
  let assert [val_x, val_y] = solution.primal
  should.be_true(float.loosely_equals(val_x, 10.0, 0.001))
  should.be_true(float.loosely_equals(val_y, 0.0, 0.001))
}
