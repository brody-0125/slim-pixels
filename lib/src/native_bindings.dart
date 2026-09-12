import 'dart:ffi';

@Native<Uint32 Function()>(symbol: 'slim_abi_version')
external int abiVersion();

@Native<
  Int32 Function(
    Pointer<Uint8>,
    UintPtr,
    Pointer<Uint8>,
    UintPtr,
    Pointer<Pointer<Uint8>>,
    Pointer<UintPtr>,
  )
>(symbol: 'slim_run')
external int run(
  Pointer<Uint8> input,
  int inputLength,
  Pointer<Uint8> plan,
  int planLength,
  Pointer<Pointer<Uint8>> output,
  Pointer<UintPtr> outputLength,
);

@Native<Void Function(Pointer<Uint8>, UintPtr)>(symbol: 'slim_free')
external void free(Pointer<Uint8> buffer, int length);
