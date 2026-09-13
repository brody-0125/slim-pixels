part of 'slim_pixels.dart';

/// Sequential image processing in one persistent isolate with a bounded queue.
///
/// Call [close] to drain accepted work and release isolate resources. Native
/// calls cannot be interrupted; a hung native call can also delay closing.
final class SlimPixelsWorker {
  SlimPixelsWorker._(this._maxRequests, this._maxBytes);

  final int _maxRequests, _maxBytes;
  final _events = ReceivePort();
  final _ready = Completer<SlimPixelsWorker>();
  final _closed = Completer<void>();
  final _queue = Queue<_WorkerJob>();
  SendPort? _commands;
  _WorkerJob? _active;
  int _bytes = 0, _nextId = 0;
  bool _closing = false, _failed = false;

  /// Starts a worker and waits until its bundled native assets are ready.
  ///
  /// Limits include the active request. The byte limit counts encoded inputs,
  /// not total memory or retained results. Both limits must be positive.
  /// Initialization failures retain their [SlimPixelsErrorCode]; infrastructure
  /// failures use [SlimPixelsErrorCode.workerStartFailed].
  static Future<SlimPixelsWorker> start({
    int maxPendingRequests = 4,
    int maxPendingInputBytes = 256 * 1024 * 1024,
  }) async {
    if (maxPendingRequests <= 0 || maxPendingInputBytes <= 0) {
      throw ArgumentError('Worker limits must be positive.');
    }
    final worker = SlimPixelsWorker._(maxPendingRequests, maxPendingInputBytes);
    worker._events.listen(worker._receive);
    unawaited(
      Isolate.spawn(
        _workerMain,
        worker._events.sendPort,
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        errorsAreFatal: true,
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          worker._terminate(SlimPixelsErrorCode.workerStartFailed);
          worker._cleanup();
        },
      ),
    );
    return worker._ready.future;
  }

  /// Snapshots [input] and [operations] before returning, then processes FIFO.
  ///
  /// Validation, capacity and lifecycle errors complete the returned Future.
  /// A full queue fails with [SlimPixelsErrorCode.workerCapacityExceeded].
  /// Calls after closing fail with [StateError]. Timing out a returned Future
  /// does not cancel its work or release its reservation.
  Future<ImageResult> transform(
    Uint8List input, {
    List<ImageOperation> operations = const [],
    required ImageEncoding encoding,
  }) => Future.sync(() {
    if (_closing) throw StateError('Worker is closing or closed.');
    if (_failed) {
      throw SlimPixelsException._(SlimPixelsErrorCode.workerTerminated);
    }
    _validateRequest(input, operations);
    if (_queue.length + (_active == null ? 0 : 1) >= _maxRequests ||
        input.length > _maxBytes - _bytes) {
      throw SlimPixelsException._(SlimPixelsErrorCode.workerCapacityExceeded);
    }
    final job = _WorkerJob(
      _nextId++,
      TransferableTypedData.fromList([input]),
      List<ImageOperation>.of(operations),
      encoding,
      input.length,
    );
    _bytes += job.length;
    _queue.add(job);
    _dispatch();
    return job.result.future;
  });

  /// Rejects new work immediately, drains accepted work and awaits isolate exit.
  /// Repeated calls await the same cleanup. This does not unload OS libraries.
  Future<void> close() {
    _closing = true;
    _dispatch();
    return _closed.future;
  }

  void _dispatch() {
    if (_failed || _active != null || _commands == null) return;
    if (_queue.isNotEmpty) {
      final job = _active = _queue.removeFirst();
      _commands!.send((job.id, job.input, job.operations, job.encoding));
    } else if (_closing) {
      _commands!.send(null);
    }
  }

  void _receive(dynamic message) {
    // One event port preserves replies before the worker's exit notification.
    if (message == null) {
      if (!_closing || _active != null || _queue.isNotEmpty) _terminate();
      _cleanup();
      return;
    }
    if (message is List) {
      _terminate(
        _ready.isCompleted
            ? SlimPixelsErrorCode.workerTerminated
            : SlimPixelsErrorCode.workerStartFailed,
      );
      return;
    }
    if (_failed) return;
    if (message is SendPort) {
      _commands = message;
      _ready.complete(this);
      return;
    }
    if (!_ready.isCompleted && message is SlimPixelsException) {
      _ready.completeError(message);
      _failed = true;
      return;
    }
    if (message is! (int, Object)) {
      _terminate();
      _commands?.send(null);
      return;
    }
    final (id, response) = message;
    final job = _active;
    if (job == null || job.id != id) return;
    _active = null;
    _bytes -= job.length;
    if (response is ImageResult) {
      job.result.complete(response);
    } else if (response is SlimPixelsException) {
      job.result.completeError(response);
    } else {
      job.result.completeError(
        SlimPixelsException._(SlimPixelsErrorCode.workerTerminated),
      );
      _terminate();
      _commands?.send(null);
      return;
    }
    _dispatch();
  }

  void _terminate([
    SlimPixelsErrorCode code = SlimPixelsErrorCode.workerTerminated,
  ]) {
    _failed = true;
    final error = SlimPixelsException._(code);
    if (!_ready.isCompleted) _ready.completeError(error);
    _active?.result.completeError(error);
    _active = null;
    for (final job in _queue) {
      job.result.completeError(error);
    }
    _queue.clear();
    _bytes = 0;
  }

  void _cleanup() {
    _commands = null;
    _events.close();
    if (!_closed.isCompleted) _closed.complete();
  }
}

final class _WorkerJob {
  _WorkerJob(this.id, this.input, this.operations, this.encoding, this.length);
  final int id;
  final TransferableTypedData input;
  final List<ImageOperation> operations;
  final ImageEncoding encoding;
  final int length;
  final result = Completer<ImageResult>();
}

void _workerMain(SendPort owner) {
  final SlimPixels client;
  try {
    client = SlimPixels();
  } on SlimPixelsException catch (error) {
    owner.send(error);
    return;
  }
  final commands = ReceivePort();
  owner.send(commands.sendPort);
  commands.listen((dynamic message) {
    if (message == null) {
      commands.close();
      return;
    }
    final (
      id,
      input,
      operations,
      encoding,
    ) = message
        as (int, TransferableTypedData, List<ImageOperation>, ImageEncoding);
    try {
      owner.send((
        id,
        client.transformSync(
          input.materialize().asUint8List(),
          operations: operations,
          encoding: encoding,
        ),
      ));
    } on SlimPixelsException catch (error) {
      owner.send((id, error));
    }
  });
}
