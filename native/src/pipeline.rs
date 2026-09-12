use fast_image_resize::{
    CpuExtensions, FilterType, IntoImageView, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{CroppedImage, Image},
};
use image::{DynamicImage, ImageFormat, RgbImage, RgbaImage, codecs::jpeg::JpegEncoder};
use serde::Deserialize;
use std::io::Cursor;

#[cfg(all(
    feature = "turbo-jpeg",
    any(target_os = "windows", target_os = "linux"),
    target_arch = "x86_64"
))]
use crate::jpeg;

#[derive(Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
/// Ordered geometry operations. Resize uses encoded color values.
pub enum Op {
    Resize {
        width: u32,
        height: u32,
        filter: String,
    },
    Crop {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    },
    Rotate90,
    Rotate180,
    Rotate270,
    FlipHorizontal,
    FlipVertical,
}

#[derive(Deserialize)]
/// Transform contract shared by Rust and the JSON C ABI.
pub struct Request {
    pub operations: Vec<Op>,
    pub format: String,
    pub quality: u8,
    #[serde(default)]
    pub scalar: bool,
}

pub(crate) fn dimensions(w: u32, h: u32) -> Result<(), String> {
    if w == 0 || h == 0 || u64::from(w) * u64::from(h) > 32_000_000 {
        return Err("Dimensions must be positive and at most 32 million pixels".into());
    }
    Ok(())
}

fn resize(
    src: &DynamicImage,
    w: u32,
    h: u32,
    filter: &str,
    scalar: bool,
) -> Result<DynamicImage, String> {
    resize_view(src, w, h, filter, scalar)
}

fn resize_view(
    src: &impl IntoImageView,
    w: u32,
    h: u32,
    filter: &str,
    scalar: bool,
) -> Result<DynamicImage, String> {
    dimensions(w, h)?;
    let pixel = match src.pixel_type() {
        Some(PixelType::U8x3) => PixelType::U8x3,
        Some(PixelType::U8x4) => PixelType::U8x4,
        _ => return Err("Only accepts RGB8/RGBA8 only".into()),
    };
    let filter = match filter {
        "lanczos3" => FilterType::Lanczos3,
        "triangle" => FilterType::Bilinear,
        _ => return Err("Unsupported resize filter".into()),
    };
    let mut dst = Image::new(w, h, pixel);
    let mut resizer = Resizer::new();
    if scalar {
        // None is supported on every target; never force an unsupported ISA.
        unsafe { resizer.set_cpu_extensions(CpuExtensions::None) };
    }
    // Preserve straight-channel, encoded-color-space behavior; no linear-light
    // conversion or alpha premultiplication is performed here.
    let options = ResizeOptions::new()
        .resize_alg(ResizeAlg::Convolution(filter))
        .use_alpha(false);
    resizer
        .resize(src, &mut dst, &options)
        .map_err(|e| e.to_string())?;
    let bytes = dst.into_vec();
    Ok(match pixel {
        PixelType::U8x3 => {
            DynamicImage::ImageRgb8(RgbImage::from_raw(w, h, bytes).ok_or("Invalid RGB size")?)
        }
        _ => DynamicImage::ImageRgba8(RgbaImage::from_raw(w, h, bytes).ok_or("Invalid RGBA size")?),
    })
}

fn validate_crop(img: &DynamicImage, x: u32, y: u32, w: u32, h: u32) -> Result<(), String> {
    dimensions(w, h)?;
    if u64::from(x) + u64::from(w) > u64::from(img.width())
        || u64::from(y) + u64::from(h) > u64::from(img.height())
    {
        return Err("Crop outside image".into());
    }
    Ok(())
}

/// Decode once, apply operations in order, then return owned encoded bytes.
/// Metadata and animation are not preserved. See README for limits.
pub fn process(input: &[u8], request: &Request) -> Result<Vec<u8>, String> {
    if input.is_empty() || input.len() > 256 * 1024 * 1024 || request.operations.len() > 64 {
        return Err("Invalid input or too many operations".into());
    }
    let mut reader = image::ImageReader::new(Cursor::new(input))
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    if !matches!(
        reader.format(),
        Some(ImageFormat::Png | ImageFormat::Jpeg | ImageFormat::WebP)
    ) {
        return Err("Only static PNG/JPEG/WebP inputs are in scope".into());
    }
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(16384);
    limits.max_image_height = Some(16384);
    limits.max_alloc = Some(256 * 1024 * 1024);
    reader.limits(limits);
    let mut img = reader.decode().map_err(|e| e.to_string())?;
    dimensions(img.width(), img.height())?;
    if !matches!(
        img,
        DynamicImage::ImageRgb8(_) | DynamicImage::ImageRgba8(_)
    ) {
        return Err("Only accepts RGB8/RGBA8 only".into());
    }
    let mut operations = request.operations.iter().peekable();
    while let Some(op) = operations.next() {
        // Only adjacent crop -> resize is fused; the crop remains the filter boundary.
        if let Op::Crop {
            x,
            y,
            width,
            height,
        } = op
        {
            validate_crop(&img, *x, *y, *width, *height)?;
            if let Some(Op::Resize {
                width: target_w,
                height: target_h,
                filter,
            }) = operations.peek()
            {
                let view =
                    CroppedImage::new(&img, *x, *y, *width, *height).map_err(|e| e.to_string())?;
                img = resize_view(&view, *target_w, *target_h, filter, request.scalar)?;
                operations.next();
                continue;
            }
        }
        img = match op {
            Op::Resize {
                width,
                height,
                filter,
            } => resize(&img, *width, *height, filter, request.scalar)?,
            Op::Crop {
                x,
                y,
                width,
                height,
            } => img.crop_imm(*x, *y, *width, *height),
            Op::Rotate90 => img.rotate90(),
            Op::Rotate180 => img.rotate180(),
            Op::Rotate270 => img.rotate270(),
            Op::FlipHorizontal => img.fliph(),
            Op::FlipVertical => img.flipv(),
        };
    }
    let mut out = Cursor::new(Vec::new());
    match request.format.as_str() {
        "jpeg" => {
            if !(1..=100).contains(&request.quality) {
                return Err("JPEG quality must be 1..100".into());
            }
            // Only the RGB/Q90 contract passed all encoder screening cases.
            #[cfg(all(
                feature = "turbo-jpeg",
                any(target_os = "windows", target_os = "linux"),
                target_arch = "x86_64"
            ))]
            if request.quality == 90 {
                if let DynamicImage::ImageRgb8(ref rgb) = img {
                    return jpeg::encode(rgb);
                }
            }
            img.write_with_encoder(JpegEncoder::new_with_quality(&mut out, request.quality))
                .map_err(|e| e.to_string())?;
        }
        "png" => img
            .write_to(&mut out, ImageFormat::Png)
            .map_err(|e| e.to_string())?,
        "webp" => img
            .write_to(&mut out, ImageFormat::WebP)
            .map_err(|e| e.to_string())?,
        _ => return Err("Unsupported output format".into()),
    }
    Ok(out.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fused_request_matches_materialized_crop() {
        for alpha in [false, true] {
            let src = if alpha {
                DynamicImage::ImageRgba8(RgbaImage::from_fn(37, 29, |x, y| {
                    image::Rgba([
                        (x * 7) as u8,
                        (y * 11) as u8,
                        ((x + y) * 13) as u8,
                        ((x * 3 + y) * 5) as u8,
                    ])
                }))
            } else {
                DynamicImage::ImageRgb8(RgbImage::from_fn(37, 29, |x, y| {
                    image::Rgb([(x * 7) as u8, (y * 11) as u8, ((x + y) * 13) as u8])
                }))
            };
            let mut input = Cursor::new(Vec::new());
            src.write_to(&mut input, ImageFormat::Png).unwrap();
            for (x, y, w, h) in [
                (0, 0, 37, 29),
                (0, 0, 17, 13),
                (20, 0, 17, 13),
                (0, 16, 17, 13),
                (20, 16, 17, 13),
                (36, 0, 1, 29),
                (0, 28, 37, 1),
                (36, 28, 1, 1),
            ] {
                for (tw, th) in [(1, 1), (5, 3), (51, 43)] {
                    for filter in ["lanczos3", "triangle"] {
                        for scalar in [false, true] {
                            let req = Request {
                                operations: vec![
                                    Op::Crop {
                                        x,
                                        y,
                                        width: w,
                                        height: h,
                                    },
                                    Op::Resize {
                                        width: tw,
                                        height: th,
                                        filter: filter.into(),
                                    },
                                    Op::Rotate90,
                                    Op::FlipHorizontal,
                                ],
                                format: "png".into(),
                                quality: 90,
                                scalar,
                            };
                            let expected =
                                resize(&src.crop_imm(x, y, w, h), tw, th, filter, scalar)
                                    .unwrap()
                                    .rotate90()
                                    .fliph();
                            let mut encoded = Cursor::new(Vec::new());
                            expected.write_to(&mut encoded, ImageFormat::Png).unwrap();
                            let actual = process(input.get_ref(), &req).unwrap();
                            assert_eq!(
                                actual,
                                encoded.into_inner(),
                                "ROI {x},{y},{w},{h} -> {tw},{th}, {filter}, alpha={alpha}, scalar={scalar}"
                            );
                            let decoded = image::load_from_memory(&actual).unwrap();
                            assert_eq!(
                                (decoded.width(), decoded.height(), decoded.color()),
                                (expected.width(), expected.height(), expected.color())
                            );
                            assert_eq!(decoded.as_bytes(), expected.as_bytes());
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn fused_invalid_crop_precedes_invalid_resize() {
        let src = DynamicImage::ImageRgb8(RgbImage::new(5, 5));
        let mut input = Cursor::new(Vec::new());
        src.write_to(&mut input, ImageFormat::Png).unwrap();
        let req = Request {
            operations: vec![
                Op::Crop {
                    x: u32::MAX,
                    y: 0,
                    width: 2,
                    height: 2,
                },
                Op::Resize {
                    width: 0,
                    height: 1,
                    filter: "unknown".into(),
                },
            ],
            format: "png".into(),
            quality: 90,
            scalar: false,
        };
        assert_eq!(
            process(input.get_ref(), &req).unwrap_err(),
            "Crop outside image"
        );
    }
    #[test]
    fn request_contract() {
        let src = DynamicImage::ImageRgb8(RgbImage::from_fn(17, 13, |x, y| {
            image::Rgb([x as u8, y as u8, 200])
        }));
        let mut encoded = Cursor::new(Vec::new());
        src.write_to(&mut encoded, ImageFormat::Png).unwrap();
        let req: Request = serde_json::from_str(r#"{"operations":[{"crop":{"x":1,"y":2,"width":12,"height":10}},{"resize":{"width":6,"height":5,"filter":"lanczos3"}},"rotate90","flip_horizontal"],"format":"png","quality":90}"#).unwrap();
        let result = image::load_from_memory(&process(encoded.get_ref(), &req).unwrap()).unwrap();
        assert_eq!((result.width(), result.height()), (5, 6));
        assert!(process(b"bad image", &req).is_err());
        assert!(resize(&src, 0, 1, "lanczos3", false).is_err());
        let bad: Request = serde_json::from_str(r#"{"operations":[{"crop":{"x":16,"y":0,"width":2,"height":1}}],"format":"png","quality":90}"#).unwrap();
        assert!(process(encoded.get_ref(), &bad).is_err());
        let a = resize(&src, 6, 5, "lanczos3", false).unwrap();
        let b = resize(&src, 6, 5, "lanczos3", true).unwrap();
        assert_eq!(a.as_bytes(), b.as_bytes());
    }
}
