import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';

ImageResult convert(Uint8List input) => SlimPixels().transformSync(
  input,
  operations: [Resize.inside(maxWidth: 512, maxHeight: 512)],
  encoding: JpegEncoding(),
);

// Keep the closure outside the benchmark scope to avoid capturing other inputs.
Future<ImageResult> runOnce(Uint8List input) =>
    Isolate.run(() => convert(input));

Map<String, double> percentiles(List<int> values) {
  values.sort();
  return {
    'p50Ms': values[(values.length * .5).ceil() - 1] / 1000,
    'p95Ms': values[(values.length * .95).ceil() - 1] / 1000,
  };
}

Future<void> main(List<String> args) async {
  final root = args.isEmpty ? 'test/golden' : args.first;
  final inputs = List.generate(
    30,
    (i) => File('$root/rgb/$i.png').readAsBytesSync(),
  );
  final startTimes = <int>[];
  for (var i = 0; i < 10; i++) {
    final clock = Stopwatch()..start();
    final worker = await SlimPixelsWorker.start();
    startTimes.add(clock.elapsedMicroseconds);
    await worker.close();
  }
  final worker = await SlimPixelsWorker.start();
  final sync = <int>[], spawn = <int>[], persistent = <int>[], submit = <int>[];
  var checked = 0;
  try {
    // Warm all three paths. Timing excludes disk IO; every measured result is checked.
    convert(inputs.first);
    await runOnce(inputs.first);
    await worker.transform(inputs.first, encoding: JpegEncoding());
    for (var round = 0; round < 3; round++) {
      for (final input in inputs) {
        final results = <ImageResult>[];
        // Rotate order to reduce systematic warm-cache/thermal bias.
        for (var step = 0; step < 3; step++) {
          final mode = (step + round) % 3;
          final clock = Stopwatch()..start();
          final ImageResult result;
          if (mode == 0) {
            result = convert(input);
            sync.add(clock.elapsedMicroseconds);
          } else if (mode == 1) {
            result = await runOnce(input);
            spawn.add(clock.elapsedMicroseconds);
          } else {
            final future = worker.transform(
              input,
              operations: [Resize.inside(maxWidth: 512, maxHeight: 512)],
              encoding: JpegEncoding(),
            );
            submit.add(clock.elapsedMicroseconds);
            result = await future;
            persistent.add(clock.elapsedMicroseconds);
          }
          results.add(result);
        }
        if (results.map((r) => base64Encode(r.bytes)).toSet().length != 1) {
          throw StateError('Execution paths changed bytes');
        }
        checked++;
      }
    }
  } finally {
    await worker.close();
  }
  print(
    jsonEncode({
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'images': inputs.length,
      'rounds': 3,
      'equalTriples': checked,
      'inputBytes': inputs.fold<int>(0, (sum, bytes) => sum + bytes.length),
      'workerStartInSameProcess': percentiles(startTimes),
      'syncLatency': percentiles(sync),
      'isolateRunLatency': percentiles(spawn),
      'workerLatency': percentiles(persistent),
      'workerSubmitBlocking': percentiles(submit),
      'processPeakRssBytes': ProcessInfo.maxRss,
    }),
  );
}
