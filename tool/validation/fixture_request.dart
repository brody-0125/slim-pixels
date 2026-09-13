import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';

ImageResult transformFixture(
  SlimPixels client,
  Uint8List input,
  Map<String, Object?> request,
) {
  final operations = <ImageOperation>[];
  for (final op in request['operations'] as List) {
    if (op is String) {
      operations.add(switch (op) {
        'rotate90' => Rotate.clockwise90,
        'rotate180' => Rotate.clockwise180,
        'rotate270' => Rotate.clockwise270,
        'flip_horizontal' => Flip.horizontal,
        'flip_vertical' => Flip.vertical,
        _ => throw StateError('Unknown fixture operation'),
      });
    } else {
      final entry = (op as Map).entries.single;
      final value = entry.value as Map;
      operations.add(switch (entry.key) {
        'crop' => Crop(
          x: value['x'] as int,
          y: value['y'] as int,
          width: value['width'] as int,
          height: value['height'] as int,
        ),
        'resize' => Resize.exact(
          width: value['width'] as int,
          height: value['height'] as int,
          filter: value['filter'] == 'triangle'
              ? ResizeFilter.triangle
              : ResizeFilter.lanczos3,
        ),
        _ => throw StateError('Unknown fixture operation'),
      });
    }
  }
  final encoding = switch (request['format']) {
    'jpeg' => JpegEncoding(quality: request['quality'] as int),
    'png' => const PngEncoding(),
    'webp' => const WebpLosslessEncoding(),
    _ => throw StateError('Unknown fixture encoding'),
  };
  return client.transformSync(
    input,
    operations: operations,
    encoding: encoding,
  );
}
