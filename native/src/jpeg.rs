//! Validated RGB8/Q90 encoder. Other contracts remain on image's encoder.
use image::RgbImage;
use std::{
    ffi::{CStr, c_int, c_ulong, c_void},
    ptr, slice,
};

const OPTIMIZE: c_int = 11;
const ACCURATE_DCT: c_int = 4096;
const RGB: c_int = 0;
const SUBSAMPLE_444: c_int = 0;

// libjpeg-turbo 3.2.0 turbojpeg.h. c_ulong is 32 bits on Windows.
#[cfg_attr(target_os = "windows", link(name = "turbojpeg", kind = "raw-dylib"))]
#[cfg_attr(target_os = "linux", link(name = "turbojpeg"))]
unsafe extern "C" {
    fn tjInitCompress() -> *mut c_void;
    fn tj3Set(handle: *mut c_void, param: c_int, value: c_int) -> c_int;
    fn tjCompress2(
        handle: *mut c_void,
        src: *const u8,
        width: c_int,
        pitch: c_int,
        height: c_int,
        pixel_format: c_int,
        output: *mut *mut u8,
        size: *mut c_ulong,
        subsampling: c_int,
        quality: c_int,
        flags: c_int,
    ) -> c_int;
    fn tjGetErrorStr2(handle: *mut c_void) -> *const i8;
    fn tjFree(buffer: *mut u8);
    fn tjDestroy(handle: *mut c_void) -> c_int;
}

struct Encoder {
    handle: *mut c_void,
    output: *mut u8,
}

impl Encoder {
    fn error(&self) -> String {
        let message = unsafe { tjGetErrorStr2(self.handle) };
        if message.is_null() {
            return "TurboJPEG encoding failed".into();
        }
        unsafe { CStr::from_ptr(message) }
            .to_string_lossy()
            .into_owned()
    }
}

impl Drop for Encoder {
    fn drop(&mut self) {
        unsafe {
            if !self.output.is_null() {
                tjFree(self.output);
            }
            if !self.handle.is_null() {
                tjDestroy(self.handle);
            }
        }
    }
}

pub(super) fn encode(rgb: &RgbImage) -> Result<Vec<u8>, String> {
    crate::pipeline::dimensions(rgb.width(), rgb.height())?;
    let width = c_int::try_from(rgb.width()).map_err(|_| "JPEG width exceeds native limit")?;
    let height = c_int::try_from(rgb.height()).map_err(|_| "JPEG height exceeds native limit")?;
    let mut encoder = Encoder {
        handle: unsafe { tjInitCompress() },
        output: ptr::null_mut(),
    };
    if encoder.handle.is_null() {
        return Err("TurboJPEG initialization failed".into());
    }
    if unsafe { tj3Set(encoder.handle, OPTIMIZE, 1) } != 0 {
        return Err(encoder.error());
    }
    let mut size: c_ulong = 0;
    let code = unsafe {
        tjCompress2(
            encoder.handle,
            rgb.as_raw().as_ptr(),
            width,
            0,
            height,
            RGB,
            &mut encoder.output,
            &mut size,
            SUBSAMPLE_444,
            90,
            ACCURATE_DCT,
        )
    };
    if code != 0 {
        return Err(encoder.error());
    }
    if encoder.output.is_null() || size == 0 {
        return Err("TurboJPEG returned empty output".into());
    }
    // Copy before RAII releases the native buffer and compressor, including on errors.
    Ok(unsafe { slice::from_raw_parts(encoder.output, size as usize) }.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invalid_then_valid_and_odd_dimensions() {
        assert!(encode(&RgbImage::new(0, 1)).is_err());
        let rgb = RgbImage::from_fn(17, 13, |x, y| image::Rgb([x as u8 * 11, y as u8 * 17, 91]));
        let bytes = encode(&rgb).unwrap();
        assert_eq!(
            image::load_from_memory(&bytes)
                .unwrap()
                .to_rgb8()
                .dimensions(),
            (17, 13)
        );
        for _ in 0..100 {
            assert_eq!(encode(&rgb).unwrap(), bytes);
        }
    }
}
