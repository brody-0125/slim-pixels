"""Exercise private worker fault paths in a disposable package, without public hooks."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
dart = sys.argv[1] if len(sys.argv) > 1 else 'dart'
aot = '--aot' in sys.argv[2:]
with tempfile.TemporaryDirectory(prefix='slim-worker-fault-') as temporary:
    package = Path(temporary)
    for name in ('lib', 'hook', 'native/bin'):
        shutil.copytree(root / name, package / name)
    shutil.copy2(root / 'pubspec.yaml', package / 'pubspec.yaml')
    source = package / 'lib/src/slim_pixels.dart'
    text = source.read_text(encoding='utf-8')
    source.write_text(text.replace("part 'worker.dart';", "part 'worker.dart';\npart 'worker_fault_probe.dart';"), encoding='utf-8')
    (package / 'lib/src/worker_fault_probe.dart').write_text("""part of 'slim_pixels.dart';
Future<void> probe() async {
  final input = Uint8List.fromList([1]);
  for (var i = 0; i < 20; i++) {
    final worker = await SlimPixelsWorker.start();
    // A malformed private message causes an uncaught worker error and exit.
    worker._commands!.send(1);
    final jobs = List.generate(4, (_) => worker.transform(input, encoding: const PngEncoding()));
    await Future.wait(jobs.map((job) async {
      try { await job; throw StateError('Expected termination'); }
      on SlimPixelsException catch (e) {
        if (e.code != SlimPixelsErrorCode.workerTerminated) rethrow;
      }
    })).timeout(const Duration(seconds: 10));
    try {
      await worker.transform(input, encoding: const PngEncoding());
      throw StateError('Failed worker accepted work');
    } on SlimPixelsException catch (e) {
      if (e.code != SlimPixelsErrorCode.workerTerminated) rethrow;
    }
    await worker.close().timeout(const Duration(seconds: 10));
    try {
      await worker.transform(input, encoding: const PngEncoding());
      throw Exception('Closed worker accepted work');
    } on StateError { /* Expected lifecycle error. */ }
    worker._receive(null); // Duplicate exit must not complete anything twice.
    worker._receive(SlimPixelsException._(SlimPixelsErrorCode.decodeFailed));
    if (worker._active != null || worker._queue.isNotEmpty || worker._bytes != 0) {
      throw StateError('Retained reservations');
    }
  }
  final stale = await SlimPixelsWorker.start();
  final pending = stale.transform(input, encoding: const PngEncoding());
  final active = stale._active;
  stale._receive((-1, SlimPixelsException._(SlimPixelsErrorCode.encodeFailed)));
  if (!identical(active, stale._active)) throw StateError('Stale reply consumed active job');
  try { await pending; } on SlimPixelsException catch (e) {
    if (e.code != SlimPixelsErrorCode.unsupportedInput) rethrow;
  }
  await stale.close();
  // Abrupt exit with no onError notification.
  final worker = await SlimPixelsWorker.start();
  worker._commands!.send(null);
  try {
    await worker.transform(input, encoding: const PngEncoding());
    throw StateError('Expected early exit');
  } on SlimPixelsException catch (e) {
    if (e.code != SlimPixelsErrorCode.workerTerminated) rethrow;
  }
  await worker.close();
  // Hold a command before it reaches the real worker; no speed-dependent sleep.
  final held = await SlimPixelsWorker.start(maxPendingRequests: 1, maxPendingInputBytes: 1);
  final actualPort = held._commands!;
  final proxy = ReceivePort();
  final arrived = Completer<Object>();
  held._commands = proxy.sendPort;
  proxy.listen((dynamic message) { arrived.complete(message as Object); });
  try {
    var done = false;
    final original = held.transform(input, encoding: const PngEncoding());
    final observed = original.then<void>((_) { throw StateError('Invalid image succeeded'); },
      onError: (Object e, StackTrace stack) {
        if (e is! SlimPixelsException || e.code != SlimPixelsErrorCode.unsupportedInput) {
          Error.throwWithStackTrace(e, stack);
        }
        done = true;
      });
    final command = await arrived.future;
    try {
      await original.timeout(Duration.zero);
      throw StateError('Expected timeout');
    } on TimeoutException { /* The command is still held. */ }
    if (done || held._bytes != 1 || held._active == null) throw StateError('Timeout released reservation');
    try {
      await held.transform(input, encoding: const PngEncoding());
      throw StateError('Timed-out job lost capacity');
    } on SlimPixelsException catch (e) {
      if (e.code != SlimPixelsErrorCode.workerCapacityExceeded) rethrow;
    }
    held._commands = actualPort;
    actualPort.send(command);
    await observed;
    if (held._bytes != 0 || held._active != null) throw StateError('Completion retained reservation');
    // Hold a second accepted job to verify close waits for actual completion.
    final arrivedAgain = Completer<Object>();
    final proxyAgain = ReceivePort();
    held._commands = proxyAgain.sendPort;
    proxyAgain.listen((dynamic message) { arrivedAgain.complete(message as Object); });
    try {
      final second = held.transform(input, encoding: const PngEncoding()).then<void>((_) {
        throw StateError('Invalid image succeeded');
      }, onError: (Object e) {
        if (e is! SlimPixelsException || e.code != SlimPixelsErrorCode.unsupportedInput) throw e;
      });
      final commandAgain = await arrivedAgain.future;
      var closed = false;
      final closing = held.close().then((_) { closed = true; });
      try {
        await held.transform(input, encoding: const PngEncoding());
        throw Exception('Closing worker accepted work');
      } on StateError { /* Expected. */ }
      if (closed) throw StateError('Close skipped accepted job');
      held._commands = actualPort;
      actualPort.send(commandAgain);
      await second;
      await closing;
      if (held._bytes != 0 || held._active != null || held._queue.isNotEmpty) {
        throw StateError('Drain retained reservation');
      }
    } finally { proxyAgain.close(); }
  } finally {
    proxy.close();
    held._commands = actualPort;
    await held.close();
  }
  print('PASS: 20 fatal worker errors, early exit, all pending Futures and duplicate events');
}
""", encoding='utf-8')
    (package / 'bin').mkdir()
    (package / 'bin/probe.dart').write_text("import 'package:slim_pixels/src/slim_pixels.dart';\nFuture<void> main() => probe().timeout(const Duration(seconds: 30));\n", encoding='utf-8')
    subprocess.run([dart, 'pub', 'get'], cwd=package, check=True)
    if aot:
        subprocess.run([dart, 'build', 'cli', '--target=bin/probe.dart', '--output=dist'], cwd=package, check=True, timeout=180)
        executable = package / 'dist/bundle/bin' / ('probe.exe' if os.name == 'nt' else 'probe')
        subprocess.run([str(executable)], cwd=package, check=True, timeout=120)
    else:
        subprocess.run([dart, 'run', 'bin/probe.dart'], cwd=package, check=True, timeout=120)
    print('PASS: timeout reservations and held-job drain; ' + ('AOT' if aot else 'JIT'))
