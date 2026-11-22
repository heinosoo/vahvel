use microlp::{
    ComparisonOp, OptimizationDirection, Problem, SolutionStatus, SolveOptions, SolveOutcome,
    TerminationReason,
};
use rustler::types::atom as atoms;
use rustler::{Atom, NifRecord, NifTaggedEnum, NifUnitEnum, Term};
use std::time::Duration;

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

    /// An explicit bound must be finite.
    fn is_valid(&self) -> bool {
        match self {
            Self::Unbounded => true,
            Self::Finite(value) => value.is_finite(),
        }
    }
}

/// Gleam's `Option`: `none` or `{some, Value}`. Rustler's built-in `Option`
/// expects `nil` or a bare value instead.
#[derive(NifTaggedEnum)]
enum Optional<T> {
    None,
    Some(T),
}

impl<T> From<Option<T>> for Optional<T> {
    fn from(value: Option<T>) -> Self {
        match value {
            None => Self::None,
            Some(value) => Self::Some(value),
        }
    }
}

/// An integer bound. microlp integer variables are limited to `i32`; its
/// documented way to leave a side unbounded is `i32::MIN` or `i32::MAX`.
impl Optional<i32> {
    fn value(&self, unbounded: i32) -> i32 {
        match self {
            Self::None => unbounded,
            Self::Some(value) => *value,
        }
    }
}

#[derive(NifTaggedEnum)]
enum Domain {
    Real(Bound, Bound),
    Integer(Optional<i32>, Optional<i32>),
}

impl Domain {
    fn is_valid(&self) -> bool {
        match self {
            Self::Real(lower, upper) => lower.is_valid() && upper.is_valid(),
            Self::Integer(_, _) => true,
        }
    }

    fn is_empty(&self) -> bool {
        match self {
            Self::Real(lower, upper) => lower.value(f64::NEG_INFINITY) > upper.value(f64::INFINITY),
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

/// One expression node. Children stay undecoded terms, so no nested Rust value
/// exists whose decoding, traversal or drop would recurse.
#[derive(NifTaggedEnum)]
enum Node<'a> {
    Linear(f64, usize),
    Constant(f64),
    Sum(Vec<Term<'a>>),
    Scaled(f64, Term<'a>),
}

/// Expand an expression into indexed terms and a constant. Factors accumulate
/// outer-to-inner from `1.0`; leaves are visited in depth-first input order.
/// The explicit stack keeps native stack use constant at any nesting depth.
fn expand(expression: Term<'_>, variables: usize) -> Result<(Vec<(usize, f64)>, f64), Defect> {
    let mut terms = Vec::new();
    let mut constant = 0.0;
    let mut stack = vec![(expression, 1.0)];
    while let Some((term, scale)) = stack.pop() {
        match term.decode::<Node>().map_err(|_| Defect::Invalid)? {
            Node::Linear(coefficient, index) => {
                if index >= variables {
                    return Err(Defect::Invalid);
                }
                terms.push((index, finite(coefficient * scale)?));
            }
            Node::Constant(value) => constant = finite(constant + finite(value * scale)?)?,
            // Reversed, so the first child is popped first.
            Node::Sum(children) => stack.extend(children.into_iter().rev().map(|c| (c, scale))),
            Node::Scaled(factor, child) => stack.push((child, finite(scale * factor)?)),
        }
    }
    Ok((terms, constant))
}

#[derive(NifRecord)]
#[tag = "row"]
struct RawRow<'a> {
    lhs: Term<'a>,
    relation: Relation,
    rhs: Term<'a>,
}

/// A canonical row: strictly increasing indices, nonzero finite coefficients.
struct Row {
    terms: Vec<(usize, f64)>,
    relation: Relation,
    rhs: f64,
}

enum Defect {
    /// A malformed expression or an index out of range.
    Invalid,
    NonFinite,
}

fn finite(value: f64) -> Result<f64, Defect> {
    if value.is_finite() {
        Ok(value)
    } else {
        Err(Defect::NonFinite)
    }
}

/// Expand `lhs − rhs`: lhs leaves first, then negated rhs leaves.
fn difference(
    lhs: Term<'_>,
    rhs: Term<'_>,
    variables: usize,
) -> Result<(Vec<(usize, f64)>, f64), Defect> {
    let (mut terms, lhs_constant) = expand(lhs, variables)?;
    let (rhs_terms, rhs_constant) = expand(rhs, variables)?;
    terms.extend(rhs_terms.into_iter().map(|(i, c)| (i, -c)));
    Ok((terms, finite(lhs_constant - rhs_constant)?))
}

/// Sort expanded terms by index, sum duplicates in input order and drop zeros.
fn canonical(
    (mut terms, constant): (Vec<(usize, f64)>, f64),
) -> Result<(Vec<(usize, f64)>, f64), Defect> {
    terms.sort_by_key(|&(i, _)| i);
    let mut merged: Vec<(usize, f64)> = Vec::with_capacity(terms.len());
    for (i, c) in terms {
        match merged.last_mut() {
            Some(last) if last.0 == i => last.1 = finite(last.1 + c)?,
            _ => merged.push((i, c)),
        }
    }
    merged.retain(|&(_, c)| c != 0.0);
    Ok((merged, constant))
}

/// Variables, objective and rows stay undecoded so a failure can report its
/// position.
#[derive(NifRecord)]
#[tag = "model"]
struct RawModel<'a> {
    direction: Direction,
    variables: Vec<Term<'a>>,
    objective: Term<'a>,
    rows: Vec<Term<'a>>,
}

struct Model {
    direction: Direction,
    variables: Vec<Domain>,
    objective: Vec<f64>,
    offset: f64,
    rows: Vec<Row>,
}

#[derive(NifRecord)]
#[tag = "limits"]
struct RawLimits<'a> {
    time: Optional<Term<'a>>,
    nodes: Optional<Term<'a>>,
}

fn malformed_limits() -> DriverError {
    DriverError::SolverFailure("Malformed solve limits".into())
}

fn limit_integer(term: Term<'_>, invalid: DriverError) -> Result<u64, DriverError> {
    if !term.is_integer() {
        return Err(malformed_limits());
    }
    term.decode().map_err(|_| invalid)
}

/// Far beyond any useful budget, yet well inside every platform's monotonic
/// clock, so microlp's unchecked `Instant::now() + limit` cannot overflow.
const MAX_TIME_LIMIT: Duration = Duration::from_secs(100 * 365 * 24 * 60 * 60);

fn decode_limits(term: Term<'_>) -> Result<SolveOptions, DriverError> {
    let raw: RawLimits = term.decode().map_err(|_| malformed_limits())?;
    let mut options = SolveOptions::default();
    if let Optional::Some(time) = raw.time {
        let (seconds, nanos): (Term, Term) = time.decode().map_err(|_| malformed_limits())?;
        let seconds = limit_integer(seconds, DriverError::InvalidTimeLimit)?;
        let nanos = limit_integer(nanos, DriverError::InvalidTimeLimit)?;
        if nanos >= 1_000_000_000 {
            return Err(malformed_limits());
        }
        let time = Duration::new(seconds, nanos as u32);
        if time > MAX_TIME_LIMIT {
            return Err(DriverError::InvalidTimeLimit);
        }
        options.time_limit = Some(time);
    }
    if let Optional::Some(nodes) = raw.nodes {
        options.node_limit = Some(limit_integer(nodes, DriverError::InvalidNodeLimit)?);
    }
    Ok(options)
}

/// Solve work and an optional finite gap. Elapsed nanoseconds saturate at u64::MAX.
#[derive(NifRecord)]
#[tag = "stats"]
struct Stats {
    nodes: u64,
    iterations: u64,
    nanoseconds: u64,
    gap: Optional<f64>,
}

impl Stats {
    /// No solver call: the driver proved a trivial optimum itself.
    const OPTIMAL: Self = Self {
        nodes: 0,
        iterations: 0,
        nanoseconds: 0,
        gap: Optional::Some(0.0),
    };

    fn new(stats: microlp::Stats, gap: Option<f64>) -> Self {
        Self {
            nodes: stats.nodes_solved,
            iterations: stats.lp_iterations,
            nanoseconds: u64::try_from(stats.elapsed.as_nanos()).unwrap_or(u64::MAX),
            gap: gap.into(),
        }
    }
}

#[derive(NifUnitEnum)]
enum StopReason {
    TimeLimit,
    NodeLimit,
}

fn stop_reason(reason: TerminationReason) -> Result<StopReason, DriverError> {
    match reason {
        TerminationReason::TimeLimit => Ok(StopReason::TimeLimit),
        TerminationReason::NodeLimit => Ok(StopReason::NodeLimit),
        _ => Err(DriverError::SolverFailure(
            "Unexpected solver termination".into(),
        )),
    }
}

#[derive(NifTaggedEnum)]
enum Outcome {
    Optimal(f64, Vec<f64>, Stats),
    Limited(StopReason, Optional<(f64, Vec<f64>)>, Stats),
    Infeasible,
    UnboundedProblem,
}

#[derive(NifTaggedEnum)]
enum InvalidReason {
    MalformedModel,
    InvalidObjective,
    InvalidDomain(usize),
    InvalidRow(usize),
    NonFiniteObjective,
    NonFiniteRow(usize),
}

#[derive(NifTaggedEnum)]
enum DriverError {
    InvalidModel(InvalidReason),
    InvalidTimeLimit,
    InvalidNodeLimit,
    SolverFailure(String),
}

#[rustler::nif(schedule = "DirtyCpu")]
fn driver_solve(term: Term<'_>, limits: Term<'_>) -> Result<Outcome, DriverError> {
    // Keep all native work inside the tagged error contract.
    std::panic::catch_unwind(|| {
        let options = decode_limits(limits)?;
        let model = decode(term).map_err(DriverError::InvalidModel)?;
        solve(model, options)
    })
    .unwrap_or_else(|_| Err(DriverError::SolverFailure("Native solver panicked".into())))
}

/// Decode, canonicalize and validate the whole model before any infeasibility
/// is reported.
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
    let n = variables.len();
    let (terms, offset) = expand(raw.objective, n)
        .and_then(canonical)
        .map_err(|defect| match defect {
            Defect::Invalid => InvalidReason::InvalidObjective,
            Defect::NonFinite => InvalidReason::NonFiniteObjective,
        })?;
    let mut dense = vec![0.0; n];
    for (i, c) in terms {
        dense[i] = c;
    }
    let rows = raw
        .rows
        .iter()
        .enumerate()
        .map(|(i, term)| {
            let raw: RawRow = term.decode().map_err(|_| InvalidReason::InvalidRow(i))?;
            let (terms, constant) = difference(raw.lhs, raw.rhs, n)
                .and_then(canonical)
                .map_err(|defect| match defect {
                    Defect::Invalid => InvalidReason::InvalidRow(i),
                    Defect::NonFinite => InvalidReason::NonFiniteRow(i),
                })?;
            Ok(Row {
                terms,
                relation: raw.relation,
                rhs: -constant,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Model {
        direction: raw.direction,
        variables,
        objective: dense,
        offset,
        rows,
    })
}

fn solve(model: Model, options: SolveOptions) -> Result<Outcome, DriverError> {
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
        return Ok(Outcome::Optimal(model.offset, vec![], Stats::OPTIMAL));
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
            Domain::Real(lower, upper) => problem.add_var(
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

    let solution = match problem.solve_with(options) {
        Ok(SolveOutcome::Solution(solution)) => solution,
        Ok(SolveOutcome::Interrupted(stopped)) => {
            return Ok(Outcome::Limited(
                stop_reason(stopped.termination_reason())?,
                Optional::None,
                Stats::new(stopped.stats(), None),
            ));
        }
        Err(microlp::Error::Infeasible) => return Ok(Outcome::Infeasible),
        Err(microlp::Error::Unbounded) => return Ok(Outcome::UnboundedProblem),
        Err(error) => return Err(DriverError::SolverFailure(error.to_string())),
    };
    // microlp accepts integer values within its integrality tolerance; the
    // contract promises exact whole numbers. Adding 0.0 turns -0.0 into 0.0.
    let values: Vec<_> = variables
        .iter()
        .zip(&model.variables)
        .map(|(&v, domain)| match domain {
            Domain::Real(..) => solution.var_value(v) + 0.0,
            Domain::Integer(..) => solution.var_value(v).round() + 0.0,
        })
        .collect();
    let objective = solution.objective() + model.offset;
    if !objective.is_finite() || values.iter().any(|v| !v.is_finite()) {
        return Err(DriverError::SolverFailure(
            "Nonfinite solution or objective".into(),
        ));
    }
    let stats = solution.stats();
    match (solution.status(), solution.termination_reason()) {
        (SolutionStatus::Optimal, TerminationReason::ProvenOptimal) => Ok(Outcome::Optimal(
            objective,
            values,
            Stats::new(stats, Some(0.0)),
        )),
        (SolutionStatus::Feasible, reason) => {
            let gap = stats.best_bound.and_then(|bound| {
                let bound = bound + model.offset;
                let gap = (objective - bound).abs() / objective.abs().max(1.0);
                (bound.is_finite() && gap.is_finite()).then_some(gap)
            });
            Ok(Outcome::Limited(
                stop_reason(reason)?,
                Optional::Some((objective, values)),
                Stats::new(stats, gap),
            ))
        }
        _ => Err(DriverError::SolverFailure(
            "Inconsistent solver status".into(),
        )),
    }
}

/// Shares solve canonicalization, including scaling and duplicate merging.
#[rustler::nif(schedule = "DirtyCpu")]
fn driver_evaluate(expression: Term<'_>, values: Vec<f64>) -> Result<f64, Atom> {
    let evaluate = || -> Result<f64, Defect> {
        let (terms, constant) = canonical(expand(expression, values.len())?)?;
        let mut total = 0.0;
        for (index, coefficient) in terms {
            total = finite(total + finite(coefficient * values[index])?)?;
        }
        finite(total + constant)
    };
    evaluate().map_err(|_| atoms::nil())
}
