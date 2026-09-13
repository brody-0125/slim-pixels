import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_pixels.dart';

bool same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main(List<String> args) {
  final old = RawPixels(args[0]), current = RawPixels(args[1]);
  final cases = jsonDecode(File(args[2]).readAsStringSync()) as List;
  var golden = 0, unchanged = 0, pipelines = 0;
  for (final item in cases) {
    final input = File(item['input'] as String).readAsBytesSync();
    final request = <String, Object?>{
      'operations': [],
      'format': 'jpeg',
      'quality': 90,
    };
    final actual = current.transform(input, request);
    if (!same(actual, File(item['expected'] as String).readAsBytesSync())) {
      throw StateError(
        'Q90 output differs from measured optimized encoder: ${item['input']}',
      );
    }
    golden++;
    if (item['source'] != null) {
      final original = File(item['source'] as String).readAsBytesSync();
      final plan = {
        ...request,
        'operations': [
          {
            'resize': {
              'width': item['width'],
              'height': item['height'],
              'filter': 'lanczos3',
            },
          },
        ],
      };
      if (!same(current.transform(original, plan), actual)) {
        throw StateError('Product resize/encode differs from measured path');
      }
      pipelines++;
    }
    for (final quality in [75, 95]) {
      final plan = {...request, 'quality': quality};
      if (!same(current.transform(input, plan), old.transform(input, plan))) {
        throw StateError('Fallback quality $quality changed');
      }
      unchanged++;
    }
  }
  final sample = File(cases.first['input'] as String).readAsBytesSync();
  final good = <String, Object?>{
    'operations': [],
    'format': 'jpeg',
    'quality': 90,
  };
  for (final quality in [0, 101]) {
    var rejected = false;
    try {
      current.transform(sample, {...good, 'quality': quality});
    } on StateError {
      rejected = true;
    }
    if (!rejected) throw StateError('Invalid JPEG quality accepted');
  }
  final expected = current.transform(sample, good);
  for (var i = 0; i < 1000; i++) {
    if (!same(current.transform(sample, good), expected)) {
      throw StateError('Repeated output changed');
    }
  }
  stdout.writeln(
    'PASS: $golden Q90 golden FFI cases, $pipelines product resize/encode cases, $unchanged unchanged Q75/Q95 cases, invalid quality/recovery, 1000 JPEG create-copy-free cycles.',
  );
}
