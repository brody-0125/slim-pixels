# Validation record

## ABI 2 public API worktree — 2026-09-13

These are local checks, not remote GitHub Actions results. No release or pub.dev publication was performed.

- Windows Dart 3.10.0: recommended-lint analysis, typed smoke, separate consumer JIT, invalid manifest rejection and relocated AOT bundle passed.
- Windows Dart 3.13.3: typed JIT smoke, 322 unchanged golden outputs, 12 explicit transparency rejections, 1000 JPEG repeats passed.
- Windows Dart 3.13.2: typed AOT smoke and the same 322+12 corpus passed.
- Linux WSL2 Dart 3.13.3: analysis, public consumer/10 compile-negative cases, typed JIT/AOT smoke, 322+12 JIT/AOT corpus, separate consumer/relocated AOT bundle passed.
- Linux Dart 3.10.0: typed JIT smoke passed.
- Windows/Linux Rust: six unit tests per platform passed, including integer fit bounds and fractional cover crop fusion boundaries.
- Linux ABI 2 fault injection: incompatible ABI, missing symbol, invalid binary, malformed metadata, invalid operation index, and encode failure passed. Malformed-result buffer release was checked across repeated calls.
- Linux Valgrind: 2012 raw/ABI 2 calls; 683829 allocations and frees, zero bytes at exit, zero memory errors. This does not measure the Dart VM heap.
- Public API docs: one public library, zero warnings/errors including link validation. Local documentation links and README code examples passed the final gates.

The 12 changed outcomes are recorded in test/golden/policy_overrides.json; original input/expected images and their hashes were not regenerated. The encoder itself and its historical quality thresholds were not changed. A fresh encoder performance comparison was not run for this API-only integration.

Not established: remote all-stable-patch CI, all-platform fault injection, forced allocation failure, fatal panic recovery, exhaustive floating-point/quality proof, mobile/ARM/macOS/Flutter release distribution. Current CI includes repeatable API, documentation and Linux fault-injection gates.

## ABI 1 historical results

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
