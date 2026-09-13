import 'dart:convert';
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';
import 'fixture_request.dart';

void main(List<String> args) {
  final library = SlimPixels();
  final root = args[1];
  final cases =
      jsonDecode(File('$root/manifest.json').readAsStringSync()) as List;
  if (cases.length != 334) throw StateError('Incomplete regression corpus');
  final overrides =
      jsonDecode(File('$root/policy_overrides.json').readAsStringSync()) as Map;
  var passed = 0, rejected = 0, index = 0;
  for (final item in cases) {
    final input = File('$root/${item['input']}').readAsBytesSync();
    final override = overrides['$index'];
    index++;
    if (override != null) {
      try {
        transformFixture(
          library,
          input,
          Map<String, Object?>.from(item['request'] as Map),
        );
        throw StateError('Expected policy rejection at ${index - 1}');
      } on SlimPixelsException catch (e) {
        if (e.code.name != override || e.operationIndex != null) {
          throw StateError('Wrong policy rejection at ${index - 1}');
        }
      }
      rejected++;
      continue;
    }
    final expected = File('$root/${item['expected']}').readAsBytesSync();
    final actual = transformFixture(
      library,
      input,
      Map<String, Object?>.from(item['request'] as Map),
    ).bytes;
    if (actual.length != expected.length) {
      throw StateError('Golden size mismatch at $passed');
    }
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        throw StateError('Golden byte mismatch at $passed/$i');
      }
    }
    passed++;
  }
  if (rejected != 12 || passed != 322) {
    throw StateError('Incomplete policy/golden coverage');
  }
  final input = File('$root/${cases[1]['input']}').readAsBytesSync();
  final expected = File('$root/${cases[1]['expected']}').readAsBytesSync();
  for (var i = 0; i < 1000; i++) {
    final output = library.transformSync(input, encoding: JpegEncoding()).bytes;
    if (base64Encode(output) != base64Encode(expected)) {
      throw StateError('JPEG repeat drift');
    }
  }
  stdout.writeln(
    'PASS: $passed unchanged goldens, $rejected explicit policy rejections; 1000 JPEG cycles',
  );
}
