use faer::MatRef;
use rustler::atoms;
use rustler::{Binary, Encoder, Env, OwnedBinary, Term};
use std::borrow::Cow;

atoms! {
    ok,
    error
}

#[derive(Debug)]
pub enum WaffleError {
    DimensionMismatch(String),
    InvalidInput(String),
    ComputationFailed(String),
    AllocationFailed,
}

impl std::fmt::Display for WaffleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WaffleError::DimensionMismatch(msg) => write!(f, "{}", msg),
            WaffleError::InvalidInput(msg) => write!(f, "{}", msg),
            WaffleError::ComputationFailed(msg) => write!(f, "{}", msg),
            WaffleError::AllocationFailed => write!(f, "Failed to allocate result binary"),
        }
    }
}

pub fn err_term<'a>(env: Env<'a>, e: &WaffleError) -> Term<'a> {
    (error(), e.to_string()).encode(env)
}

pub fn ok_mat<'a>(env: Env<'a>, mat: MatRef<'_, f64>) -> Term<'a> {
    match mat_to_binary(mat, env) {
        Some(bin) => (ok(), bin).encode(env),
        None => err_term(env, &WaffleError::AllocationFailed),
    }
}

pub fn ok_float<'a>(env: Env<'a>, val: f64) -> Term<'a> {
    (ok(), val).encode(env)
}

pub fn binary_to_cow_f64(bin: &[u8]) -> Cow<'_, [f64]> {
    match bytemuck::try_cast_slice(bin) {
        Ok(slice) => Cow::Borrowed(slice),
        Err(_) => {
            let len = bin.len() / 8;
            let mut vec = Vec::with_capacity(len);
            let chunks = bin.chunks_exact(8);
            for chunk in chunks {
                let val = f64::from_ne_bytes(chunk.try_into().unwrap());
                vec.push(val);
            }
            Cow::Owned(vec)
        }
    }
}

pub fn binary_to_cow_i64(bin: &[u8]) -> Cow<'_, [i64]> {
    match bytemuck::try_cast_slice(bin) {
        Ok(slice) => Cow::Borrowed(slice),
        Err(_) => {
            let len = bin.len() / 8;
            let mut vec = Vec::with_capacity(len);
            let chunks = bin.chunks_exact(8);
            for chunk in chunks {
                let val = i64::from_ne_bytes(chunk.try_into().unwrap());
                vec.push(val);
            }
            Cow::Owned(vec)
        }
    }
}

pub fn binary_to_cow_u64(bin: &[u8]) -> Cow<'_, [u64]> {
    match bytemuck::try_cast_slice(bin) {
        Ok(slice) => Cow::Borrowed(slice),
        Err(_) => {
            let len = bin.len() / 8;
            let mut vec = Vec::with_capacity(len);
            let chunks = bin.chunks_exact(8);
            for chunk in chunks {
                let val = u64::from_ne_bytes(chunk.try_into().unwrap());
                vec.push(val);
            }
            Cow::Owned(vec)
        }
    }
}

pub fn mat_to_binary<'a>(mat: MatRef<'_, f64>, env: Env<'a>) -> Option<Binary<'a>> {
    let col_major: Vec<f64> = mat.col_iter().flat_map(|col| col.iter().copied()).collect();
    floats_to_binary(&col_major, env)
}

pub fn floats_to_binary<'a>(data: &[f64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
    Some(owned.release(env))
}

pub fn u64s_to_binary<'a>(data: &[u64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
    Some(owned.release(env))
}

pub fn has_nan_or_inf(mat: MatRef<'_, f64>) -> bool {
    mat.col_iter()
        .any(|col| col.iter().any(|&v| v.is_nan() || v.is_infinite()))
}
