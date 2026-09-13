# slim_pixels

[![CI](https://github.com/brody-0125/slim-pixels/actions/workflows/ci.yml/badge.svg)](https://github.com/brody-0125/slim-pixels/actions/workflows/ci.yml)
![Dart](https://img.shields.io/badge/Dart-3.10.0%2B-0175C2.svg?logo=dart)
![Platforms](https://img.shields.io/badge/Platforms-Windows%20%7C%20Linux%20x64-blue)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/brody-0125/slim-pixels/blob/main/LICENSE)

English | [한국어](https://github.com/brody-0125/slim-pixels/blob/main/README.ko.md)

Resize and crop images in Dart, then encode them as JPEG, PNG, or lossless WebP. Pass encoded bytes and typed operations to get read-only output bytes with dimensions and format metadata.

## Features

- **Platforms**: Dart 3.10.0 to less than 4.0.0, with bundled native libraries for Windows and Linux x64.
- **Input formats**: Static PNG, JPEG, and WebP inputs that decode to RGB8 or RGBA8.
- **Transforms**: Exact, inside, and cover resizing; crop; rotations in 90-degree steps; horizontal and vertical flips.
- **Output formats**: JPEG, PNG, and lossless WebP.
- **Worker processing**: One reusable isolate with a bounded FIFO queue and graceful shutdown.

Use `SlimPixels.transformSync` for synchronous calls or `SlimPixelsWorker.transform` for a reusable worker isolate. Manage file I/O and batch submission in your application. Validation covers Dart CLI applications on Windows/Linux x64. Flutter application bundles, mobile platforms, macOS, and ARM remain unverified.

## Installation

For version 0.1.2, add this dependency after the release appears on pub.dev. This branch prepares the release; publication is pending.

```yaml
dependencies:
  slim_pixels: ^0.1.2
```

## Quick Start

```dart
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

void main() {
  final pixels = SlimPixels();
  final result = pixels.transformSync(
    File('input.png').readAsBytesSync(),
    operations: [Resize.inside(maxWidth: 512, maxHeight: 512)],
    encoding: const WebpLosslessEncoding(),
  );
  File('output.webp').writeAsBytesSync(result.bytes);
  print('${result.width}x${result.height}, ${result.mimeType}');
}
```

Supply `encoding` with each call. An empty operation list still decodes and re-encodes the image. To edit the result bytes, copy them with `Uint8List.fromList(result.bytes)`. A `SlimPixels` instance needs no disposal. Close a worker after use.

## Usage

### Worker processing

```dart
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

Future<void> main() async {
  final worker = await SlimPixelsWorker.start();
  try {
    final result = await worker.transform(
      await File('input.png').readAsBytes(),
      operations: [Resize.inside(maxWidth: 512)],
      encoding: JpegEncoding(quality: 90),
    );
    await File('output.jpg').writeAsBytes(result.bytes);
  } finally {
    await worker.close();
  }
}
```

A worker processes requests in FIFO order on one isolate. Its default capacity is four requests and 256 MiB of encoded input, counting the active request and the queue. Set `maxPendingRequests` and `maxPendingInputBytes` in `start()` to change these limits. A request over either limit fails with `workerCapacityExceeded` before input copying or queue admission. For a large batch, await results or submit a bounded number of requests.

Before `transform` returns, it copies the input and operation list. You can then modify your originals. Allow for this copy cost on the calling isolate. Results contain read-only Dart bytes; transfers carry no zero-copy guarantee. The input limit excludes decoded buffers and results you retain.

Call `close()` to stop accepting requests, drain accepted work, and wait for isolate exit. Repeated calls return the same Future. Calls to `transform` after closing begins fail through the returned Future with `StateError`. You can reuse a worker after an image processing error. An unexpected worker exit fails pending requests with `workerTerminated`, with no automatic retry.

`Future.timeout` ends your wait without cancelling the operation or releasing its reservation. A hung native call can delay `close()`.

## API Reference

### Processing and results

| API | Return value | Purpose |
|---|---|---|
| `SlimPixels()` | `SlimPixels` | Initialize native assets for synchronous calls. |
| `transformSync(input, operations:, encoding:)` | `ImageResult` | Decode, transform, and encode on the calling isolate. |
| `SlimPixelsWorker.start(...)` | `Future<SlimPixelsWorker>` | Start an isolate and wait for native initialization. |
| `worker.transform(input, operations:, encoding:)` | `Future<ImageResult>` | Submit a request within the worker's capacity. |
| `worker.close()` | `Future<void>` | Drain accepted work and wait for exit. |

Read `ImageResult.bytes`, `width`, `height`, `format`, `mimeType`, and `byteLength` for the encoded output and its metadata. `encoding` is required in both transform methods.

### Operations and encoding

| API | Behavior |
|---|---|
| `Resize.exact(width:, height:)` | Produce the requested dimensions, allowing aspect ratio distortion. |
| `Resize.inside(maxWidth:, maxHeight:)` | Preserve aspect ratio within the supplied bounds. Supply at least one bound. Upscaling defaults to off. |
| `Resize.cover(width:, height:)` | Fill the requested dimensions with uniform scaling and a central crop, using fractional crop coordinates. |
| `Crop(x:, y:, width:, height:)` | Select an integer pixel region from the preceding result. An out-of-bounds crop fails. |
| `Rotate.clockwise90/180/270` | Rotate clockwise. |
| `Flip.horizontal/vertical` | Flip across the selected direction. |
| `JpegEncoding(quality: 90)` | Set quality from 1 to 100. Nonopaque alpha causes failure. |
| `const PngEncoding()` | Encode the transformed pixels as PNG. |
| `const WebpLosslessEncoding()` | Encode the transformed pixels as lossless WebP. |

Resize defaults to `ResizeFilter.lanczos3`; `ResizeFilter.triangle` is also available. Exact and cover resizing allow upscaling by default. Set `allowUpscale: false` to fail a request that needs enlargement. Inside resizing rounds output dimensions down and clamps each dimension to at least one pixel.

Operations run in list order. A crop followed by a resize skips the cropped-image buffer copy and uses the crop region as the filter boundary. FFI input and output copies remain.

## Image Quality and Limits

- Resizing uses encoded color values and straight alpha. It applies neither linear-light conversion nor alpha premultiplication, so transparent edges can show color bleeding.
- The decoder rejects animation. The API does not convert grayscale or 16-bit images, apply EXIF orientation, manage ICC profiles, or preserve metadata.
- JPEG output requires opaque pixels. RGBA input with alpha values of 255 converts to RGB. Composite a background in your application if you need to remove transparency.
- RGB8 JPEG at quality 90 uses 4:4:4 sampling and per-image Huffman tables. Quality values do not imply matching bytes or file sizes across encoders.
- Encoded input must contain 1 byte to 256 MiB, with at most 64 operations. Input dimensions can reach 16,384 pixels per axis. Input, intermediate, and output images have a 32-million-pixel limit. The decoder allocation limit is 256 MiB; process memory can exceed it.
- Invalid arguments raise `ArgumentError`. Known execution failures use `SlimPixelsException`. Branch on `code`; treat `message` as diagnostic text. An operation failure has a zero-based `operationIndex`. Worker methods report call errors through their Futures.
- VM memory exhaustion, process termination, and Rust panics fall outside the recoverable exception contract.

See the [API contract](https://github.com/brody-0125/slim-pixels/blob/main/doc/API.md) for the type list, error codes, and ownership rules. Supporting documents are in Korean.

## Native Builds

`SlimPixels()` checks ABI 2. The build hook validates the two platform libraries against `SHA256SUMS.json` and bundles them without a network download. To supply a custom bundle, set `hooks.user_defines.slim_pixels.native_directory` in your application's pubspec. Hash checks verify integrity, not the publisher's identity.

For a CLI application, use `dart build cli` and distribute the entire generated `bundle/` directory. `dart compile exe` does not run build hooks. To build this package's native libraries from source:

```powershell
./tool/build.ps1
./tool/verify.ps1
```

```sh
bash tool/build-linux.sh
```

The Windows build requires MSVC and Rust 1.97.1. See [distribution requirements](https://github.com/brody-0125/slim-pixels/blob/main/doc/DISTRIBUTION.md), [CI](https://github.com/brody-0125/slim-pixels/blob/main/CI.md), and [quality gates](https://github.com/brody-0125/slim-pixels/blob/main/GATES.md). The [validation record](https://github.com/brody-0125/slim-pixels/blob/main/doc/VALIDATION.md) distinguishes local checks from CI configuration. Performance depends on the input and runtime environment.

## Testing

Run these commands from the repository root with a Dart SDK and Python:

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart run test/smoke.dart unused test/fixtures/rgb.png
dart run test/worker.dart
python tool/api_contract_check.py dart
python tool/docs_check.py dart
```

For worker AOT validation and the selected regression checks:

```sh
python tool/aot_check.py test/worker.dart
python tool/worker_fault_check.py dart --aot
python tool/worker_mutation_check.py dart
```

Use `python3` if your system has no `python` command. CI covers the supported Dart Stable patch versions on Windows/Linux, with a separate minimum-dependency job on Dart 3.10.0. Golden tests compare encoded bytes and check rejection policies. Native memory checks use a Linux harness under Valgrind.

## Contributing

See the [contribution guide](https://github.com/brody-0125/slim-pixels/blob/main/CONTRIBUTING.md), [changelog](https://github.com/brody-0125/slim-pixels/blob/main/CHANGELOG.md), and [contributors](https://github.com/brody-0125/slim-pixels/graphs/contributors).

## License

[MIT](https://github.com/brody-0125/slim-pixels/blob/main/LICENSE), copyright (c) 2026 Seokhyeon Kim. Include [third-party notices](https://github.com/brody-0125/slim-pixels/blob/main/THIRD_PARTY_NOTICES.md) and the `third_party/` directory when distributing the native binaries.
