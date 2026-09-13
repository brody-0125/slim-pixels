import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';

Future<void> expectFailure(
  Future<Object?> future,
  bool Function(Object) matches, {
  String label = 'Expected failure',
}) async {
  try {
    await future;
  } on Object catch (error) {
    if (matches(error)) return;
    rethrow;
  }
  throw StateError(label);
}

bool capacity(Object error) =>
    error is SlimPixelsException &&
    error.code == SlimPixelsErrorCode.workerCapacityExceeded;

Future<void> main(List<String> args) async {
  final input = File('test/fixtures/rgb.png').readAsBytesSync();
  final sync = SlimPixels();
  await expectFailure(
    SlimPixelsWorker.start(maxPendingRequests: 0),
    (e) => e is ArgumentError,
  );
  await expectFailure(
    SlimPixelsWorker.start(maxPendingInputBytes: 0),
    (e) => e is ArgumentError,
  );
  final worker = await SlimPixelsWorker.start(
    maxPendingRequests: 2,
    maxPendingInputBytes: input.length * 10,
  );
  try {
    final mutable = Uint8List.fromList(input);
    final operations = <ImageOperation>[Resize.exact(width: 7, height: 5)];
    final expected = sync.transformSync(
      input,
      operations: operations,
      encoding: const PngEncoding(),
    );
    final first = worker.transform(
      mutable,
      operations: operations,
      encoding: const PngEncoding(),
    );
    mutable.fillRange(0, mutable.length, 0);
    operations.clear();
    final second = worker.transform(input, encoding: JpegEncoding());
    await expectFailure(
      worker.transform(input, encoding: const PngEncoding()),
      capacity,
      label: 'C1 request count limit not enforced',
    );
    final actual = await first;
    if (base64Encode(actual.bytes) != base64Encode(expected.bytes) ||
        actual.width != 7 ||
        actual.height != 5 ||
        actual.format != ImageFormat.png) {
      throw StateError('Snapshot/metadata mismatch');
    }
    for (final view in [
      actual.bytes,
      actual.bytes.buffer.asUint8List(),
      Uint8List.sublistView(actual.bytes),
    ]) {
      try {
        view[0] = 0;
        throw StateError('Mutable result');
      } on UnsupportedError {
        /* Expected. */
      }
    }
    await second;
    await expectFailure(
      worker.transform(Uint8List(0), encoding: const PngEncoding()),
      (e) => e is ArgumentError,
    );
    await expectFailure(
      worker.transform(
        input,
        operations: List.filled(65, Flip.horizontal),
        encoding: const PngEncoding(),
      ),
      (e) => e is ArgumentError,
    );
    await expectFailure(
      worker.transform(
        input,
        operations: [Crop(x: 0, y: 0, width: 9999, height: 1)],
        encoding: const PngEncoding(),
      ),
      (e) =>
          e is SlimPixelsException &&
          e.code == SlimPixelsErrorCode.cropOutOfBounds &&
          e.operationIndex == 0,
    );
    final pending = [
      worker.transform(input, encoding: const PngEncoding()),
      worker.transform(input, encoding: const WebpLosslessEncoding()),
    ];
    final closing = worker.close();
    if (!identical(closing, worker.close())) {
      throw StateError('Close not idempotent');
    }
    await expectFailure(
      worker.transform(input, encoding: const PngEncoding()),
      (e) => e is StateError,
    );
    await Future.wait(pending);
    await closing;
  } finally {
    await worker.close();
  }
  final byteLimited = await SlimPixelsWorker.start(
    maxPendingRequests: 4,
    maxPendingInputBytes: input.length * 2,
  );
  try {
    final accepted = [
      byteLimited.transform(input, encoding: const PngEncoding()),
      byteLimited.transform(input, encoding: const PngEncoding()),
    ];
    await expectFailure(
      byteLimited.transform(Uint8List(1), encoding: const PngEncoding()),
      capacity,
    );
    await Future.wait(accepted);
    await byteLimited.transform(input, encoding: const PngEncoding());
  } finally {
    await byteLimited.close();
  }
  final tooSmall = await SlimPixelsWorker.start(
    maxPendingInputBytes: input.length - 1,
  );
  try {
    await expectFailure(
      tooSmall.transform(input, encoding: const PngEncoding()),
      capacity,
    );
  } finally {
    await tooSmall.close();
  }
  final fifo = await SlimPixelsWorker.start(maxPendingRequests: 3);
  try {
    final order = <int>[];
    final snapshot = Uint8List.fromList(input);
    final operations = <ImageOperation>[Resize.exact(width: 5, height: 7)];
    final expected = sync.transformSync(
      input,
      operations: operations,
      encoding: const PngEncoding(),
    );
    Future<ImageResult> record(int id, Future<ImageResult> result) =>
        result.then((value) {
          order.add(id);
          return value;
        });
    final jobs = [
      record(0, fifo.transform(input, encoding: const PngEncoding())),
      record(
        1,
        fifo.transform(
          snapshot,
          operations: operations,
          encoding: const PngEncoding(),
        ),
      ),
      record(2, fifo.transform(input, encoding: JpegEncoding())),
    ];
    snapshot.fillRange(0, snapshot.length, 0);
    operations.clear();
    final results = await Future.wait(jobs);
    if (order.join(',') != '0,1,2') {
      throw StateError('Q1 FIFO completion order differs');
    }
    if (base64Encode(results[1].bytes) != base64Encode(expected.bytes) ||
        results[1].width != 5 ||
        results[1].height != 7) {
      throw StateError('Q2 queued snapshot differs');
    }
    // A failed request releases both reservations and does not stop draining.
    final completed = <int>[];
    final mixed = [
      fifo.transform(input, encoding: const PngEncoding()).then((_) {
        completed.add(0);
      }),
      expectFailure(
        fifo.transform(
          input,
          operations: [Crop(x: 0, y: 0, width: 9999, height: 1)],
          encoding: const PngEncoding(),
        ),
        (e) =>
            e is SlimPixelsException &&
            e.code == SlimPixelsErrorCode.cropOutOfBounds &&
            e.operationIndex == 0,
      ).then((_) {
        completed.add(1);
      }),
      fifo.transform(input, encoding: const PngEncoding()).then((_) {
        completed.add(2);
      }),
    ];
    final closing = fifo.close();
    await Future.wait(mixed);
    await closing;
    if (completed.join(',') != '0,1,2') {
      throw StateError('Mixed drain completion order differs');
    }
    await expectFailure(
      fifo.transform(input, encoding: const PngEncoding()),
      (e) => e is StateError,
    );
  } finally {
    await fifo.close();
  }
  final recovery = await SlimPixelsWorker.start(
    maxPendingRequests: 1,
    maxPendingInputBytes: input.length,
  );
  try {
    await expectFailure(
      recovery.transform(
        input,
        operations: [Crop(x: 0, y: 0, width: 9999, height: 1)],
        encoding: const PngEncoding(),
      ),
      (e) =>
          e is SlimPixelsException &&
          e.code == SlimPixelsErrorCode.cropOutOfBounds,
    );
    await recovery.transform(input, encoding: const PngEncoding());
  } finally {
    await recovery.close();
  }
  for (var i = 0; i < 25; i++) {
    final instance = await SlimPixelsWorker.start();
    await instance.close();
    await instance.close();
  }
  print(
    'PASS: worker snapshots, immutable results, independent limits, FIFO, queued snapshots, mixed drain and 25 lifecycles',
  );
}
