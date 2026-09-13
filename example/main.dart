import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run example/main.dart input.png output.webp');
    exitCode = 64;
    return;
  }
  final result = SlimPixels().transformSync(
    File(args[0]).readAsBytesSync(),
    operations: [Resize.inside(maxWidth: 512, maxHeight: 512)],
    encoding: const WebpLosslessEncoding(),
  );
  File(args[1]).writeAsBytesSync(result.bytes);
  stdout.writeln(
    '${result.width}x${result.height}, ${result.byteLength} bytes',
  );
}
