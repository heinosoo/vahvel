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

/// Gleam's `Option(Int)`: `none` or `{some, I}`.
#[derive(NifTaggedEnum)]
enum IntegerBound {
    None,
    Some(i32),
}

impl IntegerBound {
    /// microlp integer variables are limited to `i32`; its documented way to
    /// leave a side unbounded is `i32::MIN` or `i32::MAX`.
    fn value(&self, unbounded: i32) -> i32 {
        match self {
            Self::None => unbounded,
            Self::Some(value) => *value,
        }
    }
}

#[derive(NifTaggedEnum)]
enum Domain {
    Continuous(Bound, Bound),
    Integer(IntegerBound, IntegerBound),
}

impl Domain {
    fn is_valid(&self) -> bool {
        match self {
            Self::Continuous(lower, upper) => {
                lower.value(0.0).is_finite() && upper.value(0.0).is_finite()
            }
            Self::Integer(_, _) => true,
        }
    }

    fn is_empty(&self) -> bool {
        match self {
            Self::Continuous(lower, upper) => {
                lower.value(f64::NEG_INFINITY) > upper.value(f64::INFINITY)
            }
            Self::Integer(lower, upper) => lower.value(i32::MIN) > upper.value(i32::MAX),
        }
    }
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

impl Row {
    fn is_valid(&self, variables: usize) -> bool {
        self.rhs.is_finite()
            && self
                .terms
                .iter()
                .all(|&(i, c)| i < variables && c.is_finite() && c != 0.0)
            && self.terms.windows(2).all(|pair| pair[0].0 < pair[1].0)
    }
}

/// Variables and rows stay undecoded so a failure can report its position.
#[derive(NifRecord)]
#[tag = "model"]
struct RawModel<'a> {
    direction: Direction,
    variables: Vec<Term<'a>>,
    objective: Vec<f64>,
    offset: f64,
    rows: Vec<Term<'a>>,
}

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
enum InvalidReason {
    MalformedModel,
    InvalidObjective,
    InvalidDomain(usize),
    InvalidRow(usize),
}

#[derive(NifTaggedEnum)]
enum DriverError {
    InvalidModel(InvalidReason),
    SolverFailure(String),
}

#[rustler::nif(schedule = "DirtyCpu")]
fn driver_solve(term: Term<'_>) -> Result<Outcome, DriverError> {
    let model = decode(term).map_err(DriverError::InvalidModel)?;
    // Keep solver panics inside the tagged error contract.
    std::panic::catch_unwind(|| solve(model))
        .unwrap_or_else(|_| Err(DriverError::SolverFailure("Native solver panicked".into())))
}

/// Decode and validate the whole model before any infeasibility is reported.
fn decode(term: Term<'_>) -> Result<Model, InvalidReason> {
    let raw: RawModel = term.decode().map_err(|_| InvalidReason::MalformedModel)?;
    let variables = raw
        .variables
        .iter()
        .enumerate()
        .map(|(i, term)| {
            term.decode::<Domain>()
                .ok()
                .filter(Domain::is_valid)
                .ok_or(InvalidReason::InvalidDomain(i))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if raw.objective.len() != variables.len()
        || !raw.offset.is_finite()
        || raw.objective.iter().any(|c| !c.is_finite())
    {
        return Err(InvalidReason::InvalidObjective);
    }
    let rows = raw
        .rows
        .iter()
        .enumerate()
        .map(|(i, term)| {
            term.decode::<Row>()
                .ok()
                .filter(|row| row.is_valid(variables.len()))
                .ok_or(InvalidReason::InvalidRow(i))
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Model {
        direction: raw.direction,
        variables,
        objective: raw.objective,
        offset: raw.offset,
        rows,
    })
}

fn solve(model: Model) -> Result<Outcome, DriverError> {
    if model.variables.iter().any(Domain::is_empty) {
        return Ok(Outcome::Infeasible);
    }
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
            Domain::Integer(lower, upper) => {
                problem.add_integer_var(c, (lower.value(i32::MIN), upper.value(i32::MAX)))
            }
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
