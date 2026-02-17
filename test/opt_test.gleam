import gleam/float
import gleam/list
import gleeunit/should
import waffle/opt

pub fn continuous_lp_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, x) = opt.cont_var(model, "x", 3.0, 0.0, 100.0)
  let #(model, y) = opt.cont_var(model, "y", 4.0, 0.0, 100.0)

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

  let #(model, x) = opt.int_var(model, "x", 0.0, 0.0, 10.0)
  let #(model, y) = opt.int_var(model, "y", 1.0, 0.0, 10.0)

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

  let #(model, x) = opt.cont_var(model, "x", 1.0, 0.0, 100.0)

  let assert Ok(model) = opt.add_constraint(model, 5.0, 1000.0, [#(x, 1.0)])
  let assert Ok(model) = opt.add_constraint(model, -1000.0, 3.0, [#(x, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Infeasible)
}

pub fn unbounded_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, _x) = opt.cont_var(model, "x", 1.0, 0.0, 1.0e30)

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Unbounded)
}

pub fn no_constraints_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, _x) = opt.cont_var(model, "x", 3.0, 0.0, 10.0)
  let #(model, _y) = opt.cont_var(model, "y", -1.0, 0.0, 5.0)

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 30.0, 0.001))

  should.equal(list.length(solution.primal), 2)
  let assert [val_x, val_y] = solution.primal
  should.be_true(float.loosely_equals(val_x, 10.0, 0.001))
  should.be_true(float.loosely_equals(val_y, 0.0, 0.001))
}

pub fn eq_constraint_test() {
  let model = opt.new()

  let #(model, x) = opt.int_var(model, "x", 1.0, 0.0, 10.0)
  let #(model, y) = opt.int_var(model, "y", 1.0, 0.0, 10.0)

  let assert Ok(model) =
    opt.add_eq_constraint(model, 5.0, [#(x, 1.0), #(y, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 5.0, 0.001))
}

pub fn le_constraint_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Maximize)

  let #(model, x) = opt.int_var(model, "x", 1.0, 0.0, 10.0)

  let assert Ok(model) = opt.add_le_constraint(model, 5.0, [#(x, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 5.0, 0.001))
}

pub fn ge_constraint_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Minimize)

  let #(model, x) = opt.int_var(model, "x", 1.0, 0.0, 10.0)

  let assert Ok(model) = opt.add_ge_constraint(model, 3.0, [#(x, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 3.0, 0.001))
}

pub fn int_vars_test() {
  let model = opt.new()

  let #(model, vars) = opt.int_vars(model, 3, "x", 1.0, 0.0, 10.0)

  should.equal(list.length(vars), 3)

  let assert [x0, x1, x2] = vars
  should.equal(opt.var_name(x0), "x_0")
  should.equal(opt.var_name(x1), "x_1")
  should.equal(opt.var_name(x2), "x_2")

  let assert Ok(model) =
    opt.add_eq_constraint(model, 15.0, [#(x0, 1.0), #(x1, 1.0), #(x2, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, 15.0, 0.001))
}

pub fn int_vars_with_bounds_test() {
  let model = opt.new()

  let bounds = [#(0.0, 5.0), #(0.0, 3.0), #(0.0, 7.0)]
  let #(model, vars) = opt.int_vars_with_bounds(model, "btn", 1.0, bounds)

  should.equal(list.length(vars), 3)

  let assert [b0, b1, b2] = vars
  should.equal(opt.var_name(b0), "btn_0")
  should.equal(opt.var_name(b1), "btn_1")
  should.equal(opt.var_name(b2), "btn_2")

  let assert Ok(model) =
    opt.add_eq_constraint(model, 8.0, [#(b0, 1.0), #(b1, 1.0), #(b2, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
}

pub fn le_constraint_negative_test() {
  let model = opt.new()
  let model = opt.set_direction(model, opt.Minimize)

  let #(model, x) = opt.cont_var(model, "x", 1.0, -10.0, 10.0)

  let assert Ok(model) = opt.add_le_constraint(model, 5.0, [#(x, 1.0)])

  let assert Ok(solution) = opt.solve(model)

  should.equal(solution.status, opt.Optimal)
  should.be_true(float.loosely_equals(solution.objective_value, -10.0, 0.001))
}

pub fn cont_vars_test() {
  let model = opt.new()

  let #(_model, vars) = opt.cont_vars(model, 2, "z", 1.0, 0.0, 100.0)

  should.equal(list.length(vars), 2)

  let assert [z0, z1] = vars
  should.equal(opt.var_name(z0), "z_0")
  should.equal(opt.var_name(z1), "z_1")
}
