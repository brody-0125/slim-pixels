import 'dart:io';

import 'package:slim_pixels/slim_pixels.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run example/main.dart <library> <input> <output.jpg>',
    );
    exitCode = 64;
    return;
  }
  final pixels = SlimPixels(args[0]);
  final output = pixels.transform(File(args[1]).readAsBytesSync(), {
    'operations': [
      {
        'resize': {'width': 256, 'height': 256, 'filter': 'lanczos3'},
      },
    ],
    'format': 'jpeg',
    'quality': 90,
  });
  File(args[2]).writeAsBytesSync(output);
}
