use crate::utils::{err_term, floats_to_binary, ok, WaffleError};
use rand::distr::{Bernoulli, Uniform};
use rand::rngs::StdRng;
use rand::RngExt;
use rand::{rng, SeedableRng};
use rand_distr::Normal;
use rustler::{Encoder, Env, NifResult, Term};

fn checked_total(rows: usize, cols: usize) -> Result<usize, WaffleError> {
    if rows == 0 || cols == 0 {
        return Err(WaffleError::InvalidInput(
            "Dimensions must be positive".to_string(),
        ));
    }
    rows.checked_mul(cols)
        .ok_or_else(|| WaffleError::InvalidInput("rows * cols overflows usize".to_string()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_uniform<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    min: f64,
    max: f64,
) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Uniform::new(min, max) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput("Invalid uniform distribution parameters".to_string()),
            ))
        }
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..total).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_uniform_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    min: f64,
    max: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Uniform::new(min, max) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput("Invalid uniform distribution parameters".to_string()),
            ))
        }
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..total).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_normal<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    mean: f64,
    std_dev: f64,
) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Normal::new(mean, std_dev) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput("Invalid normal distribution parameters".to_string()),
            ))
        }
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..total).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_normal_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    mean: f64,
    std_dev: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Normal::new(mean, std_dev) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput("Invalid normal distribution parameters".to_string()),
            ))
        }
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..total).map(|_| rng.sample(dist)).collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_bernoulli<'a>(env: Env<'a>, rows: usize, cols: usize, p: f64) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Bernoulli::new(p) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput(
                    "Invalid bernoulli probability (must be in [0, 1])".to_string(),
                ),
            ))
        }
    };
    let mut rng = rng();
    let data: Vec<f64> = (0..total)
        .map(|_| if rng.sample(dist) { 1.0 } else { 0.0 })
        .collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn random_bernoulli_seeded<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    p: f64,
    seed: u64,
) -> NifResult<Term<'a>> {
    let total = match checked_total(rows, cols) {
        Ok(n) => n,
        Err(e) => return Ok(err_term(env, &e)),
    };

    let dist = match Bernoulli::new(p) {
        Ok(d) => d,
        Err(_) => {
            return Ok(err_term(
                env,
                &WaffleError::InvalidInput(
                    "Invalid bernoulli probability (must be in [0, 1])".to_string(),
                ),
            ))
        }
    };
    let mut rng = StdRng::seed_from_u64(seed);
    let data: Vec<f64> = (0..total)
        .map(|_| if rng.sample(dist) { 1.0 } else { 0.0 })
        .collect();
    match floats_to_binary(&data, env) {
        Some(bin) => Ok((ok(), (rows, cols, bin)).encode(env)),
        None => Ok(err_term(env, &WaffleError::AllocationFailed)),
    }
}
