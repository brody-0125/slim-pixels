import 'dart:convert';
import 'dart:io';

import 'package:slim_pixels/slim_pixels.dart';

void main(List<String> args) {
  final before = SlimPixels(args[0]), after = SlimPixels(args[1]);
  final manifest =
      jsonDecode(File('${args[2]}/manifest.json').readAsStringSync()) as List;
  var passed = 0;
  for (final item in manifest) {
    final bytes = File('${args[2]}/${item['file']}').readAsBytesSync();
    final w = item['width'] as int, h = item['height'] as int;
    for (final filter in ['lanczos3', 'triangle']) {
      // JPEG RGB/Q90 now intentionally changes encoder; compare it to encoder goldens separately.
      for (final format in ['png', if (item['alpha'] == true) 'jpeg', 'webp']) {
        for (final separated in [false, true]) {
          final req = <String, Object?>{
            'operations': [
              {
                'crop': {
                  'x': w ~/ 8,
                  'y': h ~/ 8,
                  'width': w * 3 ~/ 4,
                  'height': h * 3 ~/ 4,
                },
              },
              if (separated) 'flip_horizontal',
              {
                'resize': {'width': w ~/ 4, 'height': h ~/ 4, 'filter': filter},
              },
              'rotate90',
              'flip_horizontal',
            ],
            'format': format,
            'quality': 90,
          };
          final a = before.transform(bytes, req),
              b = after.transform(bytes, req);
          if (a.length != b.length)
            throw StateError('Length mismatch ${item['file']} $filter $format');
          for (var i = 0; i < a.length; i++) {
            if (a[i] != b[i])
              throw StateError(
                'Pixel/encoding mismatch ${item['file']} $filter $format',
              );
          }
          passed++;
        }
      }
    }
  }
  stdout.writeln(
    'PASS: $passed old/new DLL encoded-byte comparisons through Dart FFI (adjacent and separated operations).',
  );
}
