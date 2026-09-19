# Changelog

English | [Korean](CHANGELOG.ko.md)

## 0.1.3

- Publish an English `CHANGELOG.md` so pub.dev Dart file conventions pass. Korean notes remain in `CHANGELOG.ko.md`.
- Allow `package:code_assets` 2.x.

## 0.1.2

- Add `SlimPixelsWorker` with a single isolate and a bounded FIFO queue. Provide input snapshots, drain-then-close, and errors for capacity overflow and unexpected worker exit.

- **Breaking:** Remove Map-based transform and runtime library-path constructors. Introduce `transformSync`, typed operations, per-format encoding options, and a read-only `ImageResult`.
- Add exact/inside/cover size policies, fractional-coordinate center crop, no-upscale, and per-operation error positions.
- Pass output size, format, and structured error codes through ABI 2. Older binaries are not compatible with the new public API.
- Reject animated images and non-opaque JPEG output. Convert opaque RGBA to RGB before JPEG encoding.
- Keep 322 existing goldens byte-identical and cover 12 transparent JPEG cases with an explicit rejection policy.
- Enable the official Dart lints and public API documentation checks. Refresh the distribution example and API contract docs.

- Validate and bundle the included native assets with a build hook, and add a constructor that needs no library path.
- Add consumer-install and relocated AOT bundle gates.
- Switch AOT verification to `dart build cli` and add a draft-release job for validated binaries.

This release prepares the first public package. It does not mean publication or a remote release has completed.

### Features

- Crop, resize, rotate, and flip from a byte-array input
- PNG, JPEG, and lossless WebP output
- Skip intermediate image copies when crop and resize are consecutive
- Resize with CPU-supported vector operations
- RGB8 JPEG quality 90 with 4:4:4 sampling and symbol-distribution Huffman tables
- Per-request buffer ownership and resource release on success and error paths
- Windows/Linux x64 binaries and source builds

### Validation and documentation

- CI covering Dart 3.10.0 through the latest 3.x stable patch
- 322 output and 12 policy-rejection regressions, encoding quality/header/hash checks, and a memory gate
- Runtime is recorded for reporting and does not block merges on a fixed performance threshold
- Documentation for request format, support range, constraints, build, and contribution
- MIT copyright: Seokhyeon Kim. Third-party licenses are kept separately

## Pre-release development notes

- **0.1.1:** Raise the SDK lower bound, fix the Linux x64 link path, and add JIT/AOT CI plus baseline JPEG checks
- **0.1.0:** Separate the Dart API from the native processing boundary, and set up image transform/encode plus build and validation scripts
