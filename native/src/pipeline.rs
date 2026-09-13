#[cfg(all(
    feature = "turbo-jpeg",
    any(target_os = "windows", target_os = "linux"),
    target_arch = "x86_64"
))]
use crate::jpeg;
use fast_image_resize::{
    CpuExtensions, FilterType, IntoImageView, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{CroppedImage, Image},
};
use image::{
    DynamicImage, ImageDecoder, ImageFormat, RgbImage, RgbaImage,
    codecs::{jpeg::JpegEncoder, png::PngDecoder, webp::WebPDecoder},
};
use serde::Deserialize;
use std::io::Cursor;

#[derive(Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Op {
    Resize {
        width: u32,
        height: u32,
        filter: String,
    },
    Fit {
        width: Option<u32>,
        height: Option<u32>,
        mode: String,
        allow_upscale: bool,
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
pub struct Request {
    pub operations: Vec<Op>,
    pub format: String,
    pub quality: u8,
    #[serde(default)]
    pub scalar: bool,
}
/// Stable ABI status; messages never contain dependency diagnostics.
#[derive(Debug)]
pub struct Failure {
    pub code: i32,
    pub operation: Option<usize>,
}
impl Failure {
    fn new(code: i32) -> Self {
        Self {
            code,
            operation: None,
        }
    }
}
impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self.code {
            6 => "Crop outside image",
            7 => "Upscale required",
            8 => "Resource limit exceeded",
            _ => "Image processing failed",
        })
    }
}
pub struct Output {
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub format: u32,
}
fn failure(code: i32) -> Failure {
    Failure::new(code)
}
fn decode_error(e: image::ImageError) -> Failure {
    failure(if matches!(e, image::ImageError::Limits(_)) {
        8
    } else {
        5
    })
}
pub(crate) fn dimensions(w: u32, h: u32) -> Result<(), String> {
    if w == 0 || h == 0 || u64::from(w) * u64::from(h) > 32_000_000 {
        Err("Dimensions must be positive and at most 32 million pixels".into())
    } else {
        Ok(())
    }
}
fn bounded(w: u32, h: u32) -> Result<(), Failure> {
    dimensions(w, h).map_err(|_| failure(8))
}
fn decode(input: &[u8]) -> Result<DynamicImage, Failure> {
    let format = image::guess_format(input).map_err(|_| failure(2))?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(16384);
    limits.max_image_height = Some(16384);
    limits.max_alloc = Some(256 * 1024 * 1024);
    let mut decoder: Box<dyn ImageDecoder> = match format {
        ImageFormat::Png => {
            let d = PngDecoder::with_limits(Cursor::new(input), limits.clone())
                .map_err(decode_error)?;
            if d.is_apng().map_err(decode_error)? {
                return Err(failure(3));
            }
            Box::new(d)
        }
        ImageFormat::WebP => {
            let d = WebPDecoder::new(Cursor::new(input)).map_err(decode_error)?;
            if d.has_animation() {
                return Err(failure(3));
            }
            Box::new(d)
        }
        ImageFormat::Jpeg => Box::new(
            image::codecs::jpeg::JpegDecoder::new(Cursor::new(input)).map_err(decode_error)?,
        ),
        _ => return Err(failure(2)),
    };
    let (w, h) = decoder.dimensions();
    bounded(w, h)?;
    limits.check_dimensions(w, h).map_err(decode_error)?;
    if !matches!(
        decoder.color_type(),
        image::ColorType::Rgb8 | image::ColorType::Rgba8
    ) {
        return Err(failure(4));
    }
    // Match ImageReader's output reservation before applying remaining decoder limits.
    limits
        .reserve(decoder.total_bytes())
        .map_err(decode_error)?;
    decoder.set_limits(limits).map_err(decode_error)?;
    DynamicImage::from_decoder(decoder).map_err(decode_error)
}
fn resize_view_options(
    src: &impl IntoImageView,
    w: u32,
    h: u32,
    filter: &str,
    scalar: bool,
    cover: bool,
) -> Result<DynamicImage, Failure> {
    bounded(w, h)?;
    let pixel = match src.pixel_type() {
        Some(PixelType::U8x3) => PixelType::U8x3,
        Some(PixelType::U8x4) => PixelType::U8x4,
        _ => return Err(failure(4)),
    };
    let filter = match filter {
        "lanczos3" => FilterType::Lanczos3,
        "triangle" => FilterType::Bilinear,
        _ => return Err(failure(11)),
    };
    let mut dst = Image::new(w, h, pixel);
    let mut resizer = Resizer::new();
    if scalar {
        unsafe { resizer.set_cpu_extensions(CpuExtensions::None) };
    }
    // Keep the encoded-color, straight-channel contract.
    let mut options = ResizeOptions::new()
        .resize_alg(ResizeAlg::Convolution(filter))
        .use_alpha(false);
    if cover {
        options = options.fit_into_destination(Some((0.5, 0.5)));
    }
    resizer
        .resize(src, &mut dst, &options)
        .map_err(|_| failure(11))?;
    let bytes = dst.into_vec();
    Ok(match pixel {
        PixelType::U8x3 => {
            DynamicImage::ImageRgb8(RgbImage::from_raw(w, h, bytes).ok_or_else(|| failure(11))?)
        }
        _ => DynamicImage::ImageRgba8(RgbaImage::from_raw(w, h, bytes).ok_or_else(|| failure(11))?),
    })
}
#[cfg(test)]
fn resize(
    src: &DynamicImage,
    w: u32,
    h: u32,
    filter: &str,
    scalar: bool,
) -> Result<DynamicImage, String> {
    resize_view_options(src, w, h, filter, scalar, false).map_err(|e| e.to_string())
}
fn fit_size(
    w: u32,
    h: u32,
    tw: Option<u32>,
    th: Option<u32>,
    mode: &str,
    up: bool,
) -> Result<(u32, u32, bool), Failure> {
    if tw == Some(0) || th == Some(0) {
        return Err(failure(11));
    }
    if mode == "inside" {
        let (n, d) = match (tw, th) {
            (Some(a), Some(b)) if u64::from(a) * u64::from(h) <= u64::from(b) * u64::from(w) => {
                (a, w)
            }
            (Some(_), Some(b)) => (b, h),
            (Some(a), None) => (a, w),
            (None, Some(b)) => (b, h),
            _ => return Err(failure(11)),
        };
        let n = if up { n } else { n.min(d) };
        let a = (u64::from(w) * u64::from(n) / u64::from(d)).max(1);
        let b = (u64::from(h) * u64::from(n) / u64::from(d)).max(1);
        let a = u32::try_from(a).map_err(|_| failure(8))?;
        let b = u32::try_from(b).map_err(|_| failure(8))?;
        bounded(a, b)?;
        return Ok((a, b, false));
    }
    let (a, b) = tw.zip(th).ok_or_else(|| failure(11))?;
    if mode != "exact" && mode != "cover" {
        return Err(failure(11));
    }
    bounded(a, b)?;
    if !up && (a > w || b > h) {
        return Err(failure(7));
    }
    Ok((a, b, mode == "cover"))
}
fn resize_op(
    src: &impl IntoImageView,
    size: (u32, u32),
    op: &Op,
    scalar: bool,
) -> Option<Result<DynamicImage, Failure>> {
    match op {
        Op::Resize {
            width,
            height,
            filter,
        } => Some(resize_view_options(
            src, *width, *height, filter, scalar, false,
        )),
        Op::Fit {
            width,
            height,
            mode,
            allow_upscale,
            filter,
        } => Some(
            fit_size(size.0, size.1, *width, *height, mode, *allow_upscale)
                .and_then(|(w, h, cover)| resize_view_options(src, w, h, filter, scalar, cover)),
        ),
        _ => None,
    }
}
fn validate_crop(img: &DynamicImage, x: u32, y: u32, w: u32, h: u32) -> Result<(), Failure> {
    bounded(w, h)?;
    if u64::from(x) + u64::from(w) > u64::from(img.width())
        || u64::from(y) + u64::from(h) > u64::from(img.height())
    {
        Err(failure(6))
    } else {
        Ok(())
    }
}
pub fn transform(input: &[u8], request: &Request) -> Result<Output, Failure> {
    if input.is_empty() || input.len() > 256 * 1024 * 1024 || request.operations.len() > 64 {
        return Err(failure(11));
    }
    let format = match request.format.as_str() {
        "jpeg" => 1,
        "png" => 2,
        "webp" => 3,
        _ => return Err(failure(11)),
    };
    if format == 1 && !(1..=100).contains(&request.quality) {
        return Err(failure(11));
    }
    let mut img = decode(input)?;
    let mut i = 0;
    while i < request.operations.len() {
        let op = &request.operations[i];
        if let Op::Crop {
            x,
            y,
            width,
            height,
        } = op
        {
            validate_crop(&img, *x, *y, *width, *height).map_err(|mut e| {
                e.operation = Some(i);
                e
            })?;
            if let Some(next) = request.operations.get(i + 1) {
                let view =
                    CroppedImage::new(&img, *x, *y, *width, *height).map_err(|_| failure(11))?;
                if let Some(result) = resize_op(&view, (*width, *height), next, request.scalar) {
                    img = result.map_err(|mut e| {
                        e.operation = Some(i + 1);
                        e
                    })?;
                    i += 2;
                    continue;
                }
            }
        }
        let result = if let Some(result) =
            resize_op(&img, (img.width(), img.height()), op, request.scalar)
        {
            result
        } else {
            Ok(match op {
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
                _ => unreachable!(),
            })
        };
        img = result.map_err(|mut e| {
            e.operation = Some(i);
            e
        })?;
        i += 1;
    }
    let (width, height) = (img.width(), img.height());
    if format == 1 {
        if let DynamicImage::ImageRgba8(ref rgba) = img {
            if rgba.pixels().any(|p| p[3] != 255) {
                return Err(failure(9));
            }
            img = DynamicImage::ImageRgb8(img.to_rgb8());
        }
    }
    let mut out = Cursor::new(Vec::new());
    if format == 1 {
        #[cfg(all(
            feature = "turbo-jpeg",
            any(target_os = "windows", target_os = "linux"),
            target_arch = "x86_64"
        ))]
        if request.quality == 90 {
            if let DynamicImage::ImageRgb8(ref rgb) = img {
                return Ok(Output {
                    bytes: jpeg::encode(rgb).map_err(|_| failure(10))?,
                    width,
                    height,
                    format,
                });
            }
        }
        img.write_with_encoder(JpegEncoder::new_with_quality(&mut out, request.quality))
            .map_err(|_| failure(10))?;
    } else {
        img.write_to(
            &mut out,
            if format == 2 {
                ImageFormat::Png
            } else {
                ImageFormat::WebP
            },
        )
        .map_err(|_| failure(10))?;
    }
    Ok(Output {
        bytes: out.into_inner(),
        width,
        height,
        format,
    })
}
/// Raw research adapter; the public Dart API uses structured ABI metadata.
pub fn process(input: &[u8], request: &Request) -> Result<Vec<u8>, String> {
    transform(input, request)
        .map(|o| o.bytes)
        .map_err(|e| e.to_string())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_fit_rounding_and_limits() {
        assert_eq!(
            fit_size(3, 2, Some(2), Some(3), "cover", true).unwrap(),
            (2, 3, true)
        );
        assert_eq!(
            fit_size(17, 13, Some(8), None, "inside", false).unwrap(),
            (8, 6, false)
        );
        assert_eq!(
            fit_size(17, 13, Some(100), None, "inside", false).unwrap(),
            (17, 13, false)
        );
        assert_eq!(
            fit_size(3, 2, Some(2), Some(3), "cover", false)
                .unwrap_err()
                .code,
            7
        );
        assert_eq!(
            fit_size(1, 1, Some(u32::MAX), None, "inside", true)
                .unwrap_err()
                .code,
            8
        );
        assert!(fit_size(3, 2, None, None, "inside", false).is_err());
    }

    #[test]
    fn cover_crop_fusion_preserves_boundary() {
        let source = DynamicImage::ImageRgb8(RgbImage::from_fn(7, 5, |x, y| {
            image::Rgb([(x * 35) as u8, (y * 45) as u8, 90])
        }));
        let mut input = Cursor::new(Vec::new());
        source.write_to(&mut input, ImageFormat::Png).unwrap();
        for filter in ["lanczos3", "triangle"] {
            for (w, h) in [(2, 3), (1, 20), (20, 1), (1, 1)] {
                let request = |separated| {
                    let mut operations = vec![Op::Crop {
                        x: 2,
                        y: 1,
                        width: 3,
                        height: 2,
                    }];
                    if separated {
                        operations.extend([Op::FlipHorizontal, Op::FlipHorizontal]);
                    }
                    operations.push(Op::Fit {
                        width: Some(w),
                        height: Some(h),
                        mode: "cover".into(),
                        allow_upscale: true,
                        filter: filter.into(),
                    });
                    Request {
                        operations,
                        format: "png".into(),
                        quality: 90,
                        scalar: false,
                    }
                };
                assert_eq!(
                    process(input.get_ref(), &request(false)).unwrap(),
                    process(input.get_ref(), &request(true)).unwrap()
                );
            }
        }
    }
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
