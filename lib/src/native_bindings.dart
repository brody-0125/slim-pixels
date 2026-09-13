import 'dart:ffi';

/// Reads the native ABI contract version.
@Native<Uint32 Function()>(symbol: 'slim_abi_version')
external int abiVersion();

/// Internal ABI 2 C function signature.
typedef TransformNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Pointer<Uint8>>,
      Pointer<UintPtr>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Int32>,
    );

/// Invokes the internal ABI 2 transform.
@Native<TransformNative>(symbol: 'slim_transform')
external int run(
  Pointer<Uint8> input,
  int inputLength,
  Pointer<Uint8> plan,
  int planLength,
  Pointer<Pointer<Uint8>> output,
  Pointer<UintPtr> outputLength,
  Pointer<Uint32> width,
  Pointer<Uint32> height,
  Pointer<Uint32> format,
  Pointer<Int32> operation,
);

/// Releases an owned native output buffer.
@Native<Void Function(Pointer<Uint8>, UintPtr)>(symbol: 'slim_free')
external void free(Pointer<Uint8> buffer, int length);
