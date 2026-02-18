use std::time::Instant;

use faer::prelude::Solve;
use rustler::{Binary, Encoder, Env, NifResult, Term};

use crate::parse_mat;
use crate::utils::ok;

fn mean_stdev(times: &[u64]) -> (u64, u64) {
    let n = times.len();
    if n == 0 {
        return (0, 0);
    }
    let mean = times.iter().sum::<u64>() / n as u64;
    let variance: f64 = times
        .iter()
        .map(|&t| {
            let d = t as f64 - mean as f64;
            d * d
        })
        .sum::<f64>()
        / n as f64;
    (mean, variance.sqrt().round() as u64)
}

/// Time `iterations` runs of A*B on the binaries passed from Gleam.
/// Returns `{ok, {mean_ns, stdev_ns}}`.
#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
pub fn bench_multiply_ns<'a>(
    env: Env<'a>,
    a_rows: usize,
    a_cols: usize,
    a_bin: Binary<'a>,
    b_rows: usize,
    b_cols: usize,
    b_bin: Binary<'a>,
    iterations: usize,
) -> NifResult<Term<'a>> {
    parse_mat!(a, env, a_rows, a_cols, a_bin);
    parse_mat!(b, env, b_rows, b_cols, b_bin);

    let warmup = (iterations / 10).max(1);
    for _ in 0..warmup {
        let _ = a * b;
    }

    let mut times = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let t0 = Instant::now();
        let _ = a * b;
        times.push(t0.elapsed().as_nanos() as u64);
    }

    let (mean, stdev) = mean_stdev(&times);
    Ok((ok(), (mean, stdev)).encode(env))
}

/// Time `iterations` runs of LU-solve(A, b) on the binaries passed from Gleam.
/// A is rows×cols, b is rows×1. Returns `{ok, {mean_ns, stdev_ns}}`.
#[rustler::nif(schedule = "DirtyCpu")]
pub fn bench_solve_ns<'a>(
    env: Env<'a>,
    rows: usize,
    cols: usize,
    a_bin: Binary<'a>,
    b_bin: Binary<'a>,
    iterations: usize,
) -> NifResult<Term<'a>> {
    parse_mat!(a, env, rows, cols, a_bin);
    parse_mat!(b, env, rows, 1, b_bin);

    let warmup = (iterations / 10).max(1);
    for _ in 0..warmup {
        let lu = a.partial_piv_lu();
        let _ = lu.solve(&b);
    }

    let mut times = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let t0 = Instant::now();
        let lu = a.partial_piv_lu();
        let _ = lu.solve(&b);
        times.push(t0.elapsed().as_nanos() as u64);
    }

    let (mean, stdev) = mean_stdev(&times);
    Ok((ok(), (mean, stdev)).encode(env))
}

/// Time `iterations` runs of LU decomposition of A on the binary passed from Gleam.
/// A is n×n. Returns `{ok, {mean_ns, stdev_ns}}`.
#[rustler::nif(schedule = "DirtyCpu")]
pub fn bench_lu_ns<'a>(
    env: Env<'a>,
    n: usize,
    a_bin: Binary<'a>,
    iterations: usize,
) -> NifResult<Term<'a>> {
    parse_mat!(a, env, n, n, a_bin);

    let warmup = (iterations / 10).max(1);
    for _ in 0..warmup {
        let _ = a.partial_piv_lu();
    }

    let mut times = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let t0 = Instant::now();
        let _ = a.partial_piv_lu();
        times.push(t0.elapsed().as_nanos() as u64);
    }

    let (mean, stdev) = mean_stdev(&times);
    Ok((ok(), (mean, stdev)).encode(env))
}
