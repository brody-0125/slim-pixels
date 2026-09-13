part of 'slim_pixels.dart';

/// An immutable geometry operation applied to the preceding result.
///
/// Only operations supplied by this library are supported.
abstract final class ImageOperation {
  const ImageOperation._();
  Object get _json;
}

/// A resize filter applied to encoded color values without alpha correction.
final class ResizeFilter {
  const ResizeFilter._(this.name);

  /// The stable filter identifier.
  final String name;

  /// A three-lobe windowed sinc filter.
  static const lanczos3 = ResizeFilter._('lanczos3');

  /// A triangle-weighted filter.
  static const triangle = ResizeFilter._('triangle');
}

/// A resize with an explicit output size or bounding box.
final class Resize extends ImageOperation {
  Resize._(
    this._width,
    this._height,
    this._mode,
    this.allowsUpscale,
    this.filter,
  ) : super._();
  final int? _width;
  final int? _height;
  final String _mode;

  /// Whether the operation may enlarge the image.
  final bool allowsUpscale;

  /// The sampling filter.
  final ResizeFilter filter;

  /// Resizes to exactly [width] by [height] pixels, allowing aspect distortion.
  ///
  /// Dimensions must be 1..4294967295 or an [ArgumentError] is thrown.
  /// When [allowUpscale] is false, enlarging either axis fails at execution.
  factory Resize.exact({
    required int width,
    required int height,
    bool allowUpscale = true,
    ResizeFilter filter = ResizeFilter.lanczos3,
  }) {
    _dimension(width, 'width');
    _dimension(height, 'height');
    return Resize._(width, height, 'exact', allowUpscale, filter);
  }

  /// Fills [width] by [height] pixels using uniform scaling and a central crop.
  ///
  /// Dimensions must be 1..4294967295 or an [ArgumentError] is thrown.
  /// Uses fractional crop coordinates. If enlargement is needed but
  /// [allowUpscale] is false, execution fails instead of returning a smaller size.
  factory Resize.cover({
    required int width,
    required int height,
    bool allowUpscale = true,
    ResizeFilter filter = ResizeFilter.lanczos3,
  }) {
    _dimension(width, 'width');
    _dimension(height, 'height');
    return Resize._(width, height, 'cover', allowUpscale, filter);
  }

  /// Fits within [maxWidth] and [maxHeight] without cropping.
  ///
  /// At least one bound is required; each must be 1..4294967295, otherwise
  /// throws [ArgumentError]. Output dimensions are floored and clamped to one
  /// pixel. Images remain their size when smaller, unless [allowUpscale] is true.
  factory Resize.inside({
    int? maxWidth,
    int? maxHeight,
    bool allowUpscale = false,
    ResizeFilter filter = ResizeFilter.lanczos3,
  }) {
    if (maxWidth == null && maxHeight == null) {
      throw ArgumentError('At least one resize bound is required.');
    }
    if (maxWidth != null) _dimension(maxWidth, 'maxWidth');
    if (maxHeight != null) _dimension(maxHeight, 'maxHeight');
    return Resize._(maxWidth, maxHeight, 'inside', allowUpscale, filter);
  }
  @override
  Object get _json => {
    'fit': {
      'width': _width,
      'height': _height,
      'mode': _mode,
      'allow_upscale': allowsUpscale,
      'filter': filter.name,
    },
  };
}

void _dimension(int value, String name) {
  if (value < 1 || value > 0xffffffff) {
    throw ArgumentError.value(value, name, 'Must be 1..4294967295.');
  }
}

/// An integer crop in the current image, using an exclusive right/bottom edge.
final class Crop extends ImageOperation {
  /// Selects [width] by [height] pixels starting at [x], [y].
  ///
  /// Coordinates must be 0..4294967295 and sizes 1..4294967295, otherwise
  /// throws [ArgumentError]. Out-of-image regions fail during execution;
  /// they are never automatically clamped.
  Crop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) : super._() {
    for (final entry in {'x': x, 'y': y}.entries) {
      if (entry.value < 0 || entry.value > 0xffffffff) {
        throw ArgumentError.value(entry.value, entry.key);
      }
    }
    _dimension(width, 'width');
    _dimension(height, 'height');
  }

  /// The left pixel coordinate.
  final int x;

  /// The top pixel coordinate.
  final int y;

  /// The number of selected columns.
  final int width;

  /// The number of selected rows.
  final int height;
  @override
  Object get _json => {
    'crop': {'x': x, 'y': y, 'width': width, 'height': height},
  };
}

/// A clockwise rotation of the current pixels; EXIF is not interpreted.
enum Rotate implements ImageOperation {
  /// A quarter turn.
  clockwise90,

  /// A half turn.
  clockwise180,

  /// Three quarter turns.
  clockwise270;

  @override
  Object get _json => switch (this) {
    clockwise90 => 'rotate90',
    clockwise180 => 'rotate180',
    clockwise270 => 'rotate270',
  };
}

/// A reflection of the current pixels.
enum Flip implements ImageOperation {
  /// Exchanges left and right.
  horizontal,

  /// Exchanges top and bottom.
  vertical;

  @override
  Object get _json => this == horizontal ? 'flip_horizontal' : 'flip_vertical';
}

/// Immutable output encoding options supplied by this library.
abstract final class ImageEncoding {
  const ImageEncoding._();
  ImageFormat get _format;
  int get _quality => 90;
}

/// JPEG encoding options; nonopaque alpha is rejected at execution.
final class JpegEncoding extends ImageEncoding {
  /// Uses [quality] in 1..100; invalid values throw [ArgumentError].
  ///
  /// Quality does not specify an output byte size or cross-encoder equivalence.
  JpegEncoding({this.quality = 90}) : super._() {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'Must be 1..100.');
    }
  }

  /// The encoder quality value.
  final int quality;
  @override
  ImageFormat get _format => ImageFormat.jpeg;
  @override
  int get _quality => quality;
}

/// Lossless PNG encoding of the transformed pixels.
final class PngEncoding extends ImageEncoding {
  /// Creates PNG encoding options without a quality parameter.
  const PngEncoding() : super._();
  @override
  ImageFormat get _format => ImageFormat.png;
}

/// Lossless WebP encoding of the transformed pixels.
final class WebpLosslessEncoding extends ImageEncoding {
  /// Creates lossless WebP encoding options.
  const WebpLosslessEncoding() : super._();
  @override
  ImageFormat get _format => ImageFormat.webp;
}

/// An output format. Handle future formats with a default switch branch.
final class ImageFormat {
  const ImageFormat._(this.name, this.mimeType, this._id);

  /// The stable format identifier.
  final String name;

  /// The media type of the encoded bytes.
  final String mimeType;
  final int _id;

  /// JPEG output.
  static const jpeg = ImageFormat._('jpeg', 'image/jpeg', 1);

  /// PNG output.
  static const png = ImageFormat._('png', 'image/png', 2);

  /// WebP output.
  static const webp = ImageFormat._('webp', 'image/webp', 3);
}

/// An encoded image owned by Dart, with metadata from the native operation.
final class ImageResult {
  ImageResult._(Uint8List owned, this.width, this.height, this.format)
    : bytes = owned.asUnmodifiableView();

  /// Read-only encoded bytes. Copy with Uint8List.fromList to modify them.
  final Uint8List bytes;

  /// The output width in pixels.
  final int width;

  /// The output height in pixels.
  final int height;

  /// The actual output format.
  final ImageFormat format;

  /// The output media type.
  String get mimeType => format.mimeType;

  /// The encoded byte count.
  int get byteLength => bytes.lengthInBytes;
}

/// A known initialization, processing or worker failure.
final class SlimPixelsException implements Exception {
  SlimPixelsException._(this.code, {this.operationIndex});

  /// A stable code for branching; handle unrecognized future codes generically.
  final SlimPixelsErrorCode code;

  /// A zero-based user operation index, or null for other processing stages.
  final int? operationIndex;

  /// A human-readable diagnostic. Do not parse it for control flow.
  String get message => 'Image processing failed: ${code.name}.';
  @override
  String toString() => 'SlimPixelsException: $message';
}

/// A stable failure category, independent of backend error types.
final class SlimPixelsErrorCode {
  const SlimPixelsErrorCode._(this.name);

  /// The stable category identifier.
  final String name;

  /// The worker isolate could not be started.
  static const workerStartFailed = SlimPixelsErrorCode._('workerStartFailed');

  /// The active and queued inputs exceed the worker capacity.
  static const workerCapacityExceeded = SlimPixelsErrorCode._(
    'workerCapacityExceeded',
  );

  /// The worker terminated before completing its accepted work.
  static const workerTerminated = SlimPixelsErrorCode._('workerTerminated');

  /// Native assets could not be loaded.
  static const nativeUnavailable = SlimPixelsErrorCode._('nativeUnavailable');

  /// The native ABI is incompatible.
  static const incompatibleNative = SlimPixelsErrorCode._('incompatibleNative');

  /// The input container is not supported.
  static const unsupportedInput = SlimPixelsErrorCode._('unsupportedInput');

  /// Animated inputs are not supported.
  static const animatedInputUnsupported = SlimPixelsErrorCode._(
    'animatedInputUnsupported',
  );

  /// The decoded pixel format is not supported.
  static const unsupportedPixelFormat = SlimPixelsErrorCode._(
    'unsupportedPixelFormat',
  );

  /// A supported input could not be decoded.
  static const decodeFailed = SlimPixelsErrorCode._('decodeFailed');

  /// A crop exceeds the current image.
  static const cropOutOfBounds = SlimPixelsErrorCode._('cropOutOfBounds');

  /// The requested output requires forbidden enlargement.
  static const upscaleRequired = SlimPixelsErrorCode._('upscaleRequired');

  /// A processing resource limit was exceeded.
  static const resourceLimitExceeded = SlimPixelsErrorCode._(
    'resourceLimitExceeded',
  );

  /// JPEG output would discard nonopaque alpha.
  static const transparencyUnsupported = SlimPixelsErrorCode._(
    'transparencyUnsupported',
  );

  /// The output could not be encoded.
  static const encodeFailed = SlimPixelsErrorCode._('encodeFailed');

  /// The internal protocol or result is invalid.
  static const internalFailure = SlimPixelsErrorCode._('internalFailure');
}
