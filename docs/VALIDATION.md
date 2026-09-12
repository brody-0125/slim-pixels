# Validation history before repository initialization

These are local results from 2026-09-13, not GitHub Actions run results.

- Windows: Dart 3.10.0, 3.11.6, 3.12.2 and 3.13.3 analysis/JIT/AOT smoke checks passed.
- Linux WSL2: Dart 3.10.0 and 3.13.3 analysis/JIT/AOT smoke checks passed.
- Windows Dart 3.10.0 with ffi 2.1.4: dependency-floor analysis/JIT/AOT checks passed.
- Latest SDK on Windows and Linux: 334 product goldens and 1000 JPEG repetition checks passed in JIT and AOT.
- Linux Valgrind: 1006 calls, 343864 allocations/frees, zero live heap at exit and zero memory errors.
- Encoder gate: 3 x 42 Q90 quality/size checks, 252 header checks, 42 raw and 378 JPEG reference hashes passed. Timings are informational.
- An old encoder was intentionally rejected by the product golden gate.
- actionlint 1.7.12 and the SDK matrix discovery tests passed.

The original raw logs remain in the archived Codex deliverables; generated logs are not source-controlled here. Future CI uploads evidence as workflow artifacts. See [CI.md](../CI.md) and [GATES.md](../GATES.md) for reproducible procedures and exclusions. The remote 48 SDK/OS combination matrix has not yet been executed.
