/// Bounded synchronous image transforms with Dart-owned encoded results.
///
/// Use [SlimPixels.transformSync] with typed operations and encoding options.
/// Native assets support Windows and Linux x64. Run costly work in an isolate.
library;

export 'src/slim_pixels.dart'
    show
        SlimPixels,
        ImageOperation,
        Resize,
        Crop,
        Rotate,
        Flip,
        ResizeFilter,
        ImageEncoding,
        JpegEncoding,
        PngEncoding,
        WebpLosslessEncoding,
        ImageResult,
        ImageFormat,
        SlimPixelsException,
        SlimPixelsErrorCode;
