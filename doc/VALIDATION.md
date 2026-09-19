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

## Worker 통합 검증 (2026-09-13)

Windows/Linux x64의 Dart 3.10.0과 3.13.3에서 worker lifecycle JIT/AOT를 로컬 실행했습니다. 최신 SDK 양 플랫폼에서 worker의 322개 golden 바이트 일치, 12개 정책 거부, 1,000 JPEG 반복을 검사했습니다. Linux 네이티브 실패 6종은 worker 초기화/처리까지 확장했습니다. 소비자 JIT와 이동한 AOT 번들에서 worker의 네이티브 자산 로딩과 JPEG 바이트 일치를 확인했습니다.

강제 오류와 조기 종료는 임시 패키지의 비공개 포트로 주입합니다. 20회 반복 오류에서 수락한 Future 전부의 실패와 예약 해제, 늦은 응답 무시를 확인합니다. 이는 네이티브 프로세스 crash 복구나 RSS 누수 부재를 보장하는 검사는 아닙니다. 전체 SDK 패치 매트릭스는 CI에 연결했으며 원격 CI 실행 완료를 뜻하지 않습니다.

## 테스트 회귀 감지 보강 (2026-09-13)

이전 검사에서는 요청 개수 제한 삭제와 FIFO→LIFO 변경이 통과했습니다. 보강 후 정상 대조 코드는 통과하고 두 변형은 각각 C1/Q1의 지정된 단언으로 실패합니다. 이는 선정한 두 회귀에 대한 검출 확인이며 전체 mutation coverage를 뜻하지 않습니다.

Windows/Linux Dart 3.10.0·3.13.3 worker lifecycle JIT/AOT와 최신 두 OS worker fault JIT/AOT를 로컬 실행했습니다. Linux 네이티브 장애 6종도 JIT/AOT에서 시작/처리 단계와 오류 코드를 함께 확인했습니다. Linux Dart 3.10.0은 locked 실행과 별도의 downgrade 후 분석/API/smoke/worker JIT/AOT 실행을 구분했습니다.

CI에는 모든 SDK의 locked 검사, 독립 minimum 의존성 필수 작업, 최신 SDK 장애 AOT 및 선정 결함 주입 게이트를 연결했습니다. 원격 CI 전체 수행을 뜻하지 않습니다. 메모리 장기 추세 및 native hang/crash 검사는 이번 범위에 포함하지 않습니다.

## 0.1.2 배포 준비 검증

release/v0-1-2는 b01b24f의 성공한 CI 실행 34758504730에 포함된 native artifact와 해시를 적용합니다. Windows/Linux에서 별도 소비자 JIT, 해시 변조 거부, 소스 삭제 후 이동한 AOT 번들의 동기/worker JPEG golden을 다시 확인했습니다. 공개 API와 두 README의 Dart 예제, dartdoc 및 정적 분석을 확인했습니다. 이후 v0.1.2 태그와 pub.dev 0.1.2 게시가 완료되었습니다.

## 0.1.3 배포 준비 검증

cad4070은 원격 CI [35445782352](https://github.com/brody-0125/slim-pixels/actions/runs/35445782352)를 통과했습니다. native/bin은 그 실행의 Windows/Linux artifact로 교체합니다. 버전은 0.1.3이며 ABI는 2입니다. 태그 생성과 pub.dev 게시는 이 커밋 이후 단계입니다.
