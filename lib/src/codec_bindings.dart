import 'dart:ffi';

// Resolve the bundled codec before loading the library that depends on it.
/// Resolves the bundled codec before the processing library.
@Native<Pointer<Int8> Function(Pointer<Void>)>(symbol: 'tjGetErrorStr2')
external Pointer<Int8> codecError(Pointer<Void> handle);
