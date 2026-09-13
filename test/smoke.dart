import 'dart:io';
import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main(List<String> args) {
  // The first argument remains reserved for existing CI command compatibility.
  final slim = SlimPixels();
  final input = File(args[1]).readAsBytesSync();
  final jpeg = slim.transformSync(input, encoding: JpegEncoding());
  final golden = File(
    '${File(args[1]).parent.path}/rgb-q90.jpg',
  ).readAsBytesSync();
  check(jpeg.byteLength == golden.length, 'JPEG size');
  for (var i = 0; i < golden.length; i++) {
    check(jpeg.bytes[i] == golden[i], 'JPEG byte $i');
  }
  var rejected = 0;
  for (final call in <void Function()>[
    () {
      JpegEncoding(quality: 0);
    },
    () {
      JpegEncoding(quality: 101);
    },
    () {
      Resize.inside();
    },
    () {
      Resize.exact(width: 0, height: 1);
    },
    () {
      Crop(x: -1, y: 0, width: 1, height: 1);
    },
    () {
      slim.transformSync(Uint8List(0), encoding: const PngEncoding());
    },
    () {
      slim.transformSync(
        input,
        operations: List.filled(65, Flip.horizontal),
        encoding: const PngEncoding(),
      );
    },
  ]) {
    try {
      call();
    } on ArgumentError {
      rejected++;
    }
  }
  check(rejected == 7, 'Argument boundaries');
  void fails(
    List<ImageOperation> operations,
    SlimPixelsErrorCode code,
    int index,
  ) {
    try {
      slim.transformSync(
        input,
        operations: operations,
        encoding: const PngEncoding(),
      );
      throw StateError('Expected ${code.name}');
    } on SlimPixelsException catch (e) {
      check(e.code == code && e.operationIndex == index, 'Failure code/index');
    }
  }

  fails(
    [Crop(x: 999999, y: 0, width: 1, height: 1)],
    SlimPixelsErrorCode.cropOutOfBounds,
    0,
  );
  fails(
    [Resize.cover(width: 100, height: 100, allowUpscale: false)],
    SlimPixelsErrorCode.upscaleRequired,
    0,
  );
  fails(
    [
      Crop(x: 0, y: 0, width: 1, height: 1),
      Resize.exact(width: 2, height: 2, allowUpscale: false),
    ],
    SlimPixelsErrorCode.upscaleRequired,
    1,
  );
  final plan = <ImageOperation>[
    Crop(x: 1, y: 2, width: 12, height: 10),
    Resize.exact(width: 6, height: 5),
    Rotate.clockwise90,
    Flip.horizontal,
  ];
  final result = slim.transformSync(
    input,
    operations: plan,
    encoding: const PngEncoding(),
  );
  check(result.width == 5 && result.height == 6, 'Metadata dimensions');
  final header = ByteData.sublistView(result.bytes);
  check(
    header.getUint32(16) == result.width &&
        header.getUint32(20) == result.height,
    'PNG dimensions',
  );
  check(
    result.format == ImageFormat.png && result.mimeType == 'image/png',
    'Format',
  );
  for (final bytes in [
    result.bytes,
    result.bytes.buffer.asUint8List(),
    Uint8List.sublistView(result.bytes),
  ]) {
    try {
      bytes[0] = 0;
      throw StateError('Mutable result');
    } on UnsupportedError {
      /* Expected mutation guard. */
    }
  }
  final inside = slim.transformSync(
    input,
    operations: [Resize.inside(maxWidth: 100)],
    encoding: const PngEncoding(),
  );
  check(
    inside.width == jpeg.width && inside.height == jpeg.height,
    'Inside must not enlarge',
  );
  final cover = slim.transformSync(
    input,
    operations: [Resize.cover(width: 2, height: 3)],
    encoding: const PngEncoding(),
  );
  check(cover.width == 2 && cover.height == 3, 'Cover dimensions');
  for (var i = 0; i < 1000; i++) {
    slim.transformSync(input, operations: plan, encoding: const PngEncoding());
  }
  final fixtures = '${File(args[1]).parent.path}/contracts';
  for (final entry in {
    'animated.png': SlimPixelsErrorCode.animatedInputUnsupported,
    'animated.webp': SlimPixelsErrorCode.animatedInputUnsupported,
    'gray.png': SlimPixelsErrorCode.unsupportedPixelFormat,
    'depth16.png': SlimPixelsErrorCode.unsupportedPixelFormat,
    'transparent.png': SlimPixelsErrorCode.transparencyUnsupported,
  }.entries) {
    try {
      slim.transformSync(
        File('$fixtures/${entry.key}').readAsBytesSync(),
        encoding: JpegEncoding(),
      );
      throw StateError('Expected rejection of ${entry.key}');
    } on SlimPixelsException catch (e) {
      check(
        e.code == entry.value && e.operationIndex == null,
        'Image policy ${entry.key}',
      );
    }
  }
  final opaque = File('$fixtures/opaque.png').readAsBytesSync();
  check(
    slim.transformSync(opaque, encoding: JpegEncoding()).width == 3,
    'Opaque RGBA to JPEG',
  );
  for (final shape in [(1, 1), (2, 3), (1, 20), (20, 1)]) {
    final tiny = slim.transformSync(
      opaque,
      operations: [Resize.cover(width: shape.$1, height: shape.$2)],
      encoding: const PngEncoding(),
    );
    check(
      tiny.width == shape.$1 && tiny.height == shape.$2,
      'Fractional cover $shape',
    );
  }
  stdout.writeln(
    'PASS: typed arguments, failure codes/index, metadata, read-only bytes, resize policies, 1000 cycles',
  );
}
