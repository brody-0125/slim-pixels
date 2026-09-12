import 'dart:convert';
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

void main(List<String> args) {
  final library = SlimPixels(args[0]);
  final root = args[1];
  final cases =
      jsonDecode(File('$root/manifest.json').readAsStringSync()) as List;
  if (cases.length != 334) throw StateError('Incomplete regression corpus');
  var passed = 0;
  for (final item in cases) {
    final input = File('$root/${item['input']}').readAsBytesSync();
    final expected = File('$root/${item['expected']}').readAsBytesSync();
    final actual = library.transform(
      input,
      Map<String, Object?>.from(item['request'] as Map),
    );
    if (actual.length != expected.length)
      throw StateError('Golden size mismatch at $passed');
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i])
        throw StateError('Golden byte mismatch at $passed/$i');
    }
    passed++;
  }
  final input = File('$root/${cases[1]['input']}').readAsBytesSync();
  final expected = File('$root/${cases[1]['expected']}').readAsBytesSync();
  for (var i = 0; i < 1000; i++) {
    final output = library.transform(input, {
      'operations': [],
      'format': 'jpeg',
      'quality': 90,
    });
    if (base64Encode(output) != base64Encode(expected))
      throw StateError('JPEG repeat drift');
  }
  stdout.writeln(
    'PASS: $passed product goldens; 1000 JPEG allocation/copy/free cycles',
  );
}
