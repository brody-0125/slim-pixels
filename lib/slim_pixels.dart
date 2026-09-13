/// Bounded synchronous and worker image transforms with Dart-owned encoded results.
///
/// Use [SlimPixels.transformSync] with typed operations and encoding options.
/// Use [SlimPixelsWorker] for a reusable asynchronous worker.
/// Native assets support Windows and Linux x64.
library;

export 'src/slim_pixels.dart'
    show
        SlimPixels,
        SlimPixelsWorker,
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
