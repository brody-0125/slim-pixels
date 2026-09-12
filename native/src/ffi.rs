//! C ownership boundary; processing stays in the safe Rust pipeline.
use crate::{Request, process};
use std::slice;

/// ABI contract version, independent of the Dart package version.
#[unsafe(no_mangle)]
pub extern "C" fn slim_abi_version() -> u32 {
    1
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
