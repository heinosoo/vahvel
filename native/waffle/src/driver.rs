use microlp::{ComparisonOp, OptimizationDirection, Problem, SolutionStatus, SolveOutcome};
use rustler::{NifRecord, NifTaggedEnum, NifUnitEnum, Term};

#[derive(NifUnitEnum)]
enum Direction {
    Minimize,
    Maximize,
}

#[derive(NifTaggedEnum)]
enum Bound {
    Unbounded,
    Finite(f64),
}

impl Bound {
    fn value(&self, unbounded: f64) -> f64 {
        match self {
            Self::Unbounded => unbounded,
            Self::Finite(value) => *value,
        }
    }
}

#[derive(NifTaggedEnum)]
enum Domain {
    Continuous(Bound, Bound),
    Integer(i32, i32),
}

#[derive(NifUnitEnum)]
enum Relation {
    LessEqual,
    Equal,
    GreaterEqual,
}

#[derive(NifRecord)]
#[tag = "row"]
struct Row {
    terms: Vec<(usize, f64)>,
    relation: Relation,
    rhs: f64,
}

#[derive(NifRecord)]
#[tag = "model"]
struct Model {
    direction: Direction,
    variables: Vec<Domain>,
    objective: Vec<f64>,
    offset: f64,
    rows: Vec<Row>,
}

#[derive(NifTaggedEnum)]
enum Outcome {
    Optimal(f64, Vec<f64>),
    Infeasible,
    UnboundedProblem,
}

#[derive(NifTaggedEnum)]
enum DriverError {
    InvalidModel(String),
    SolverFailure(String),
}

#[rustler::nif(schedule = "DirtyCpu")]
fn driver_solve(term: Term<'_>) -> Result<Outcome, DriverError> {
    let model: Model = term.decode().map_err(|_| {
        DriverError::InvalidModel("Malformed model or integer outside the supported range".into())
    })?;
    validate(&model).map_err(|message| DriverError::InvalidModel(message.into()))?;
    // Keep solver panics inside the tagged error contract.
    std::panic::catch_unwind(|| solve(model))
        .unwrap_or_else(|_| Err(DriverError::SolverFailure("Native solver panicked".into())))
}

fn validate(model: &Model) -> Result<(), &'static str> {
    if model.objective.len() != model.variables.len()
        || !model.offset.is_finite()
        || model.objective.iter().any(|c| !c.is_finite())
    {
        return Err("Expected one finite objective coefficient per variable and a finite offset");
    }
    for domain in &model.variables {
        let valid = match domain {
            Domain::Continuous(lower, upper) => {
                lower.value(0.0).is_finite()
                    && upper.value(0.0).is_finite()
                    && lower.value(f64::NEG_INFINITY) <= upper.value(f64::INFINITY)
            }
            Domain::Integer(lower, upper) => lower <= upper,
        };
        if !valid {
            return Err("Invalid variable bounds");
        }
    }
    for row in &model.rows {
        if !row.rhs.is_finite()
            || row
                .terms
                .iter()
                .any(|&(i, c)| i >= model.variables.len() || !c.is_finite() || c == 0.0)
            || row.terms.windows(2).any(|pair| pair[0].0 >= pair[1].0)
        {
            return Err(
                "Expected a finite row with ordered, unique indices and nonzero coefficients",
            );
        }
    }
    Ok(())
}

fn solve(model: Model) -> Result<Outcome, DriverError> {
    for row in model.rows.iter().filter(|row| row.terms.is_empty()) {
        let feasible = match row.relation {
            Relation::LessEqual => 0.0 <= row.rhs,
            Relation::Equal => row.rhs == 0.0,
            Relation::GreaterEqual => 0.0 >= row.rhs,
        };
        if !feasible {
            return Ok(Outcome::Infeasible);
        }
    }
    if model.variables.is_empty() {
        return Ok(Outcome::Optimal(model.offset, vec![]));
    }

    let mut problem = Problem::new(match model.direction {
        Direction::Minimize => OptimizationDirection::Minimize,
        Direction::Maximize => OptimizationDirection::Maximize,
    });
    let variables: Vec<_> = model
        .variables
        .iter()
        .zip(&model.objective)
        .map(|(domain, &c)| match domain {
            Domain::Continuous(lower, upper) => problem.add_var(
                c,
                (lower.value(f64::NEG_INFINITY), upper.value(f64::INFINITY)),
            ),
            Domain::Integer(lower, upper) => problem.add_integer_var(c, (*lower, *upper)),
        })
        .collect();
    for row in model.rows.iter().filter(|row| !row.terms.is_empty()) {
        let relation = match row.relation {
            Relation::LessEqual => ComparisonOp::Le,
            Relation::Equal => ComparisonOp::Eq,
            Relation::GreaterEqual => ComparisonOp::Ge,
        };
        problem.add_constraint(
            row.terms.iter().map(|&(i, c)| (variables[i], c)),
            relation,
            row.rhs,
        );
    }

    let solution = match problem.solve() {
        Ok(SolveOutcome::Solution(s)) if s.status() == SolutionStatus::Optimal => s,
        Ok(_) => {
            return Err(DriverError::SolverFailure(
                "Solver stopped without an optimum".into(),
            ))
        }
        Err(microlp::Error::Infeasible) => return Ok(Outcome::Infeasible),
        Err(microlp::Error::Unbounded) => return Ok(Outcome::UnboundedProblem),
        Err(error) => return Err(DriverError::SolverFailure(error.to_string())),
    };
    let values: Vec<_> = variables.iter().map(|&v| solution.var_value(v)).collect();
    let objective = solution.objective() + model.offset;
    if !objective.is_finite() || values.iter().any(|v| !v.is_finite()) {
        return Err(DriverError::SolverFailure(
            "Nonfinite solution or objective".into(),
        ));
    }
    Ok(Outcome::Optimal(objective, values))
}
