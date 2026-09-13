//! C ownership boundary; processing stays in the safe Rust pipeline.
use crate::{Request, process};
use std::slice;

/// ABI contract version, independent of the Dart package version.
#[unsafe(no_mangle)]
pub extern "C" fn slim_abi_version() -> u32 {
    2
}

/// Structured ABI 2 result. Failure leaves the output empty and sets the
/// zero-based operation index, or -1 when the failure is not an operation.
///
/// # Safety
/// All output slots must be valid, writable and disjoint. Input ranges must be
/// readable. Free every non-null output once with its exact returned length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn slim_transform(
    input: *const u8,
    input_len: usize,
    plan: *const u8,
    plan_len: usize,
    output: *mut *mut u8,
    output_len: *mut usize,
    width: *mut u32,
    height: *mut u32,
    format: *mut u32,
    operation: *mut i32,
) -> i32 {
    if output.is_null()
        || output_len.is_null()
        || width.is_null()
        || height.is_null()
        || format.is_null()
        || operation.is_null()
    {
        return 11;
    }
    unsafe {
        *output = std::ptr::null_mut();
        *output_len = 0;
        *width = 0;
        *height = 0;
        *format = 0;
        *operation = -1;
    }
    if input.is_null() || plan.is_null() || input_len > 256 * 1024 * 1024 || plan_len > 65536 {
        return 11;
    }
    let request =
        match serde_json::from_slice::<Request>(unsafe { slice::from_raw_parts(plan, plan_len) }) {
            Ok(r) => r,
            Err(_) => return 11,
        };
    match crate::pipeline::transform(unsafe { slice::from_raw_parts(input, input_len) }, &request) {
        Ok(result) => {
            let boxed = result.bytes.into_boxed_slice();
            unsafe {
                *width = result.width;
                *height = result.height;
                *format = result.format;
                *output_len = boxed.len();
                *output = Box::into_raw(boxed) as *mut u8;
            }
            0
        }
        Err(e) => {
            unsafe { *operation = e.operation.map_or(-1, |i| i as i32) };
            e.code
        }
    }
}

/// Buffers must be valid for their supplied lengths. Result is an owned boxed
/// slice, including UTF-8 error text on failure; always call slim_free once.
///
/// # Safety
/// Input ranges must be readable; output slots must be writable and disjoint
/// from inputs. Each returned allocation must be freed once with its exact length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn slim_run(
    input: *const u8,
    input_len: usize,
    plan: *const u8,
    plan_len: usize,
    output: *mut *mut u8,
    output_len: *mut usize,
) -> i32 {
    if output.is_null() || output_len.is_null() {
        return 2;
    }
    unsafe {
        *output = std::ptr::null_mut();
        *output_len = 0;
    }
    if input.is_null() || plan.is_null() || input_len > 256 * 1024 * 1024 || plan_len > 65536 {
        return 2;
    }
    let result =
        serde_json::from_slice::<Request>(unsafe { slice::from_raw_parts(plan, plan_len) })
            .map_err(|e| e.to_string())
            .and_then(|req| process(unsafe { slice::from_raw_parts(input, input_len) }, &req));
    let (code, bytes) = match result {
        Ok(b) => (0, b),
        Err(e) => (1, e.into_bytes()),
    };
    let boxed = bytes.into_boxed_slice();
    unsafe {
        *output_len = boxed.len();
        *output = Box::into_raw(boxed) as *mut u8;
    }
    code
}

/// Releases a result from `slim_run`; null is a no-op.
///
/// # Safety
/// A non-null pointer and length must be the unmodified pair from `slim_run`,
/// and must not already have been freed or accessed after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn slim_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}
