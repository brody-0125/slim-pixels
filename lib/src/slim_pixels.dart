import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _RunC =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Pointer<Uint8>>,
      Pointer<UintPtr>,
    );
typedef _Run =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<UintPtr>,
    );
typedef _FreeC = Void Function(Pointer<Uint8>, UintPtr);
typedef _Free = void Function(Pointer<Uint8>, int);

/// Synchronous image transforms backed by the slim_pixels native library.
///
/// Calls copy inputs and outputs. Run expensive work in a worker isolate.
/// There is no persistent native image handle to dispose.
final class SlimPixels {
  /// Loads a native library and, on Windows x64, its adjacent TurboJPEG DLL.
  /// The loaded libraries remain resident for the lifetime of this isolate.
  SlimPixels(String libraryPath) {
    // Preload the adjacent dependency by absolute path; do not rely on PATH/CWD.
    if (Abi.current() == Abi.windowsX64) {
      final codec = File(
        '${File(libraryPath).absolute.parent.path}${Platform.pathSeparator}turbojpeg.dll',
      );
      if (codec.existsSync()) _libraries.add(DynamicLibrary.open(codec.path));
    }
    final library = DynamicLibrary.open(libraryPath);
    _libraries.add(library);
    _run = library.lookupFunction<_RunC, _Run>('slim_run');
    _free = library.lookupFunction<_FreeC, _Free>('slim_free');
  }
  late final _Run _run;
  final _libraries = <DynamicLibrary>[];
  late final _Free _free;

  /// Applies the JSON request contract documented in README.
  ///
  /// Returns Dart-owned encoded bytes. Throws [ArgumentError] for invalid input
  /// size and [StateError] for native validation or codec errors.
  Uint8List transform(Uint8List input, Map<String, Object?> request) {
    if (input.isEmpty || input.length > 256 * 1024 * 1024) {
      throw ArgumentError('Input must be 1..256 MiB');
    }
    final plan = utf8.encode(jsonEncode(request));
    if (plan.length > 65536) {
      throw ArgumentError('Request JSON must be at most 64 KiB');
    }
    return using((arena) {
      final source = arena<Uint8>(input.length)
        ..asTypedList(input.length).setAll(0, input);
      final config = arena<Uint8>(plan.length)
        ..asTypedList(plan.length).setAll(0, plan);
      final out = arena<Pointer<Uint8>>();
      final length = arena<UintPtr>();
      final code = _run(source, input.length, config, plan.length, out, length);
      try {
        if (code != 0) {
          throw StateError(
            out.value == nullptr
                ? 'Invalid native request'
                : utf8.decode(out.value.asTypedList(length.value)),
          );
        }
        return Uint8List.fromList(out.value.asTypedList(length.value));
      } finally {
        _free(out.value, length.value);
      }
    });
  }
}
