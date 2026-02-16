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

#[inline]
pub fn err_term<'a>(env: Env<'a>, e: &WaffleError) -> Term<'a> {
    (error(), e.to_string()).encode(env)
}

#[inline]
pub fn ok_mat<'a>(env: Env<'a>, mat: MatRef<'_, f64>) -> Term<'a> {
    match mat_to_binary(mat, env) {
        Some(bin) => (ok(), bin).encode(env),
        None => err_term(env, &WaffleError::AllocationFailed),
    }
}

#[inline]
pub fn ok_float<'a>(env: Env<'a>, val: f64) -> Term<'a> {
    (ok(), val).encode(env)
}

#[inline]
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

#[inline]
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

#[inline]
pub fn mat_to_binary<'a>(mat: MatRef<'_, f64>, env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(mat.nrows() * mat.ncols() * 8)?;
    let dest_bytes = owned.as_mut_slice();
    let mut offset = 0;

    for col in mat.col_iter() {
        if col.row_stride() == 1 {
            let col_slice = unsafe { std::slice::from_raw_parts(col.as_ptr(), col.nrows()) };
            let byte_len = col_slice.len() * 8;
            let src_bytes = bytemuck::cast_slice(col_slice);
            dest_bytes[offset..offset + byte_len].copy_from_slice(src_bytes);
            offset += byte_len;
        } else {
            for &val in col.iter() {
                dest_bytes[offset..offset + 8].copy_from_slice(&val.to_ne_bytes());
                offset += 8;
            }
        }
    }
    Some(owned.release(env))
}

#[inline]
pub fn floats_to_binary<'a>(data: &[f64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
    Some(owned.release(env))
}

#[inline]
pub fn u64s_to_binary<'a>(data: &[u64], env: Env<'a>) -> Option<Binary<'a>> {
    let mut owned = OwnedBinary::new(data.len() * 8)?;
    owned
        .as_mut_slice()
        .copy_from_slice(bytemuck::cast_slice(data));
    Some(owned.release(env))
}

#[inline]
pub fn has_nan_or_inf(mat: MatRef<'_, f64>) -> bool {
    mat.col_iter()
        .any(|col| col.iter().any(|&v| v.is_nan() || v.is_infinite()))
}

#[macro_export]
macro_rules! parse_mat {
    ($mat:ident, $env:expr, $rows:expr, $cols:expr, $bin:expr) => {
        let slice = $crate::utils::binary_to_cow_f64($bin.as_slice());
        if slice.len() != $rows * $cols {
            return Ok($crate::utils::err_term(
                $env,
                &$crate::utils::WaffleError::DimensionMismatch(
                    "Binary length mismatch".to_string(),
                ),
            ));
        }
        let $mat = faer::MatRef::from_column_major_slice(&slice, $rows, $cols);
    };
}
