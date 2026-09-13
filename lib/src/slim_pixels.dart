import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'codec_bindings.dart' as codec;
import 'native_bindings.dart' as native;

part 'types.dart';
part 'worker.dart';

/// Synchronous image processing with isolate-local native initialization.
///
/// No persistent image handles are exposed; no dispose call is needed.
final class SlimPixels {
  /// Prepares bundled native assets and checks ABI compatibility.
  ///
  /// Throws [SlimPixelsException] for known runtime loading or ABI failures.
  /// Build-hook failures occur before this constructor and remain build errors.
  SlimPixels() {
    if (_initialized) return;
    final int version;
    try {
      codec.codecError(nullptr);
      version = native.abiVersion();
      if (version == 2) {
        Native.addressOf<NativeFunction<native.TransformNative>>(native.run);
        Native.addressOf<
          NativeFunction<Void Function(Pointer<Uint8>, UintPtr)>
        >(native.free);
      }
      // The SDK reports loader failures as ArgumentError. Restrict conversion
      // to these native resolution calls, never the processing/validation path.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (_, stack) {
      Error.throwWithStackTrace(
        SlimPixelsException._(SlimPixelsErrorCode.nativeUnavailable),
        stack,
      );
    }
    if (version != 2) {
      throw SlimPixelsException._(SlimPixelsErrorCode.incompatibleNative);
    }
    _initialized = true;
  }
  static bool _initialized = false;

  /// Decodes [input], applies [operations] in order, and encodes the result.
  ///
  /// Input is read during the call, never mutated or retained. The result owns
  /// read-only Dart bytes. Even an empty operation list decodes and re-encodes.
  /// Supports static PNG/JPEG/WebP decoded as RGB8/RGBA8, without EXIF orientation
  /// or metadata preservation. Run costly calls in a worker isolate.
  ///
  /// Throws [ArgumentError] for empty input, input over 256 MiB, or more than
  /// 64 operations. Known execution failures throw [SlimPixelsException].
  ImageResult transformSync(
    Uint8List input, {
    List<ImageOperation> operations = const [],
    required ImageEncoding encoding,
  }) {
    _validateRequest(input, operations);
    final plan = utf8.encode(
      jsonEncode({
        'operations': operations.map((op) => op._json).toList(),
        'format': encoding._format.name,
        'quality': encoding._quality,
      }),
    );
    // Typed requests have bounded size; a protocol overflow indicates a bug.
    if (plan.length > 65536) {
      throw SlimPixelsException._(SlimPixelsErrorCode.internalFailure);
    }
    return using((arena) {
      final source = arena<Uint8>(input.length)
        ..asTypedList(input.length).setAll(0, input);
      final config = arena<Uint8>(plan.length)
        ..asTypedList(plan.length).setAll(0, plan);
      final out = arena<Pointer<Uint8>>();
      final length = arena<UintPtr>();
      final width = arena<Uint32>();
      final height = arena<Uint32>();
      final format = arena<Uint32>();
      final operation = arena<Int32>();
      out.value = nullptr;
      length.value = 0;
      try {
        final status = native.run(
          source,
          input.length,
          config,
          plan.length,
          out,
          length,
          width,
          height,
          format,
          operation,
        );
        if (status != 0) {
          final index = operation.value;
          if (index < -1 || index >= operations.length) {
            throw SlimPixelsException._(SlimPixelsErrorCode.internalFailure);
          }
          throw SlimPixelsException._(
            _statusCode(status),
            operationIndex: index < 0 ? null : index,
          );
        }
        if (out.value == nullptr ||
            length.value == 0 ||
            length.value > 256 * 1024 * 1024 ||
            width.value == 0 ||
            height.value == 0 ||
            width.value * height.value > 32000000 ||
            format.value != encoding._format._id) {
          throw SlimPixelsException._(SlimPixelsErrorCode.internalFailure);
        }
        return ImageResult._(
          Uint8List.fromList(out.value.asTypedList(length.value)),
          width.value,
          height.value,
          encoding._format,
        );
      } finally {
        native.free(out.value, length.value);
      }
    });
  }
}

SlimPixelsErrorCode _statusCode(int status) => switch (status) {
  2 => SlimPixelsErrorCode.unsupportedInput,
  3 => SlimPixelsErrorCode.animatedInputUnsupported,
  4 => SlimPixelsErrorCode.unsupportedPixelFormat,
  5 => SlimPixelsErrorCode.decodeFailed,
  6 => SlimPixelsErrorCode.cropOutOfBounds,
  7 => SlimPixelsErrorCode.upscaleRequired,
  8 => SlimPixelsErrorCode.resourceLimitExceeded,
  9 => SlimPixelsErrorCode.transparencyUnsupported,
  10 => SlimPixelsErrorCode.encodeFailed,
  _ => SlimPixelsErrorCode.internalFailure,
};

void _validateRequest(Uint8List input, List<ImageOperation> operations) {
  if (input.isEmpty || input.length > 256 * 1024 * 1024) {
    throw ArgumentError.value(
      input.length,
      'input.length',
      'Must be 1..268435456 bytes.',
    );
  }
  if (operations.length > 64) {
    throw ArgumentError.value(
      operations.length,
      'operations.length',
      'Must not exceed 64.',
    );
  }
}
