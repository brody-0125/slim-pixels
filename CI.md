# Dart / native CI

2026-09-13 기준 지원 SDK는 Dart >=3.10.0 <4.0.0이다. `.github/workflows/ci.yml`을 패키지 저장소 루트에 두면 PR, push, 수동 실행, 매주 월요일 03:17 UTC에 실행한다. 정기 실행은 GitHub 기본 브랜치에서 동작한다.

`tool/dart_matrix.py`가 공식 stable archive를 조회해 **3.10.0부터 현재 최신 3.x까지 모든 stable patch**를 선택한다. 현재 최신은 3.13.4이며 25개 버전이다. 새 patch/minor는 다음 실행에 자동 포함된다. beta/dev는 포함하지 않는다. Dart 4가 stable이 되면 조용히 지원 범위를 늘리지 않고 명시적인 결정이 필요하도록 실패한다. API 장애·목록 누락도 빈 matrix 성공으로 처리하지 않는다.

## 실행 구성

- Windows Server 2022 x64 / Ubuntu 24.04 x64에서 Rust 1.97.1 native build와 unit test를 한 번씩 수행한다.
- Linux JPEG 코덱은 고정 커밋 c85e6b905bf237038faa936dab160ebfc5da0344에서 SIMD ON으로 빌드한다. Windows는 패키지의 고정 코덱 DLL을 사용한다.
- OS별 native artifact와 라이선스를 모든 Dart SDK job이 재사용한다. 현 시점 25 × 2 = 50개 SDK/OS 조합이며 최대 동시 실행은 6개다.
- 각 조합: dependency resolution → static analysis → JIT smoke → AOT compile → AOT smoke. JPEG Q90 golden byte equality, PNG SIMD/scalar equality, 오류 후 복구, 크기, 반복 버퍼 해제를 검사한다.
- 모든 SDK는 루트 lockfile을 강제한다. 별도 Linux / Dart 3.10.0 minimum 작업에서 pub downgrade 후 분석·API·동기/worker JIT/AOT를 실행한다. 해석한 lockfile과 의존성 목록은 artifact로 보관한다.
- formatter 출력의 버전 차이로 옛 SDK가 실패하지 않도록 포맷 검사는 최신 stable에서만 필수로 수행한다.
- 어느 조합이든 실패하면 최종 `required` job이 실패한다. 브랜치 보호를 사용할 경우 이 job을 필수 검사로 지정한다. 0.1.2에서는 최신 SDK의 전체 golden 검사와 Linux quality/memory job도 필수로 연결했다. 상세 범위와 판정 기준은 [GATES.md](GATES.md)를 참고한다.
- native artifact 보존 기간 7일. 게시·릴리스 생성·pub.dev 업로드·외부 메시지 전송은 하지 않는다.

## 실제 검증 상태

main의 cad4070은 [원격 CI](https://github.com/brody-0125/slim-pixels/actions/runs/35445782352)를 통과했습니다. 릴리스 준비 커밋의 CI는 별도 검증 대상입니다. 이전 로컬 기록은 [doc/VALIDATION.md](doc/VALIDATION.md)에 보존합니다.

패키지에는 Windows/Linux x64 바이너리를 포함합니다. build hook이 플랫폼 자산을 번들링하므로 소비자 실행에 LD_LIBRARY_PATH 설정을 요구하지 않습니다. 네이티브 C 검증 harness는 자체 링크 환경을 설정합니다. 성능 측정값은 보고용이며 merge 차단 임계치가 아닙니다.

## 로컬 실행

Windows: `./tool/build.ps1`, `./tool/verify.ps1`.

Linux: CMake, NASM, GCC, Rust 1.97.1 설치 후 `bash tool/build-linux.sh`.

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart run test/smoke.dart native/bin/linux-x64/libslim_pixels.so test/fixtures/rgb.png
python3 tool/aot_check.py test/smoke.dart unused test/fixtures/rgb.png
dart run test/worker.dart
```

참고: [setup-dart](https://github.com/dart-lang/setup-dart), [Dart stable archive](https://dart.dev/get-dart/archive).

## Code Assets 도입 이후

현재 AOT 명령은 `dart compile exe` 대신 `python tool/aot_check.py <검증 Dart 파일> <인수...>`입니다. 모든 SDK/OS에서 별도 소비자 설치와 이동한 번들 실행도 검사합니다. v 태그에서는 전체 게이트 성공 후 플랫폼별 바이너리를 draft release로 묶습니다. 자세한 배포 계약은 `doc/DISTRIBUTION.md`를 참고하세요.

## ABI 2 공개 계약

SDK smoke는 typed API의 인자·오류 위치·결과 메타데이터·읽기 전용 바이트·애니메이션/투명도 정책을 검사한다. golden 게이트는 322개 동일 출력과 12개 명시적 정책 거부를 검사한다. 공식 recommended lint와 공개 문서 lint를 사용하며, 최신 SDK에서 dartdoc도 생성한다.

## Worker 비동기 게이트

SDK 매트릭스의 Windows/Linux 각 작업에서 `test/worker.dart`를 JIT/AOT로 실행합니다. snapshot, 읽기 전용 결과, 개수·입력 바이트 한도, 일반 오류 후 재사용, drain close와 반복 start/close를 검사합니다. `tool/worker_fault_check.py`는 임시 패키지 안에서만 비공개 프로토콜에 오류를 주입해 비정상 종료·늦은 응답·대기 Future 정리를 검사합니다. 제품에는 테스트용 공개 API가 없습니다.

최신 SDK에서는 `golden_check.dart ... --worker`를 JIT/AOT로 추가 실행합니다. 별도 소비자 JIT와 소스 삭제 후 이동한 AOT 번들도 worker JPEG 결과를 검사합니다. Linux의 네이티브 실패 주입 6종은 worker 초기화와 처리 경로를 함께 확인합니다.

`tool/validation/worker_benchmark.dart`는 수동 AOT 측정 도구입니다. 디스크 I/O를 제외하고 30개 RGB 입력, inside 512×512, JPEG quality 90으로 sync/Isolate.run/worker를 3회 비교하며 모든 출력 바이트를 대조합니다. 처리 순서를 회전합니다. 머신별 시간은 CI 통과 임계치로 사용하지 않습니다. RSS는 세 경로 전체 프로세스의 peak이며 worker 단독 메모리나 누수 지표가 아닙니다.

## Worker 계약 보강 게이트

- 요청 개수와 입력 합계 제한을 독립 설정하고 N/N+1, B/B+1, 단일 입력 L-1/L, 오류 후 예약 재사용을 검사합니다.
- active 1 + queued 2 이상의 완료 순서, 대기 입력/작업 스냅샷, 성공·오류·성공 drain 및 종료 완료 후 제출을 검사합니다.
- 비공개 임시 probe는 요청 전달을 보류하여 timeout 이후 예약 유지와 실제 완료 후 해제, close 대기를 머신 속도와 무관하게 검사합니다.
- worker fault는 기존 모든 SDK/OS JIT에 최신 SDK 두 OS AOT를 추가합니다. native failure 6종은 최신 Linux JIT/AOT에서 초기화/처리 단계를 구분합니다.
- 최신 Linux에서 `tool/worker_mutation_check.py dart`를 실행합니다. 정상 대조 실행은 통과하고 개수 제한 삭제와 LIFO 변형은 지정된 C1/Q1 단언으로 실패해야 합니다. 빌드 실패나 timeout은 검출 성공이 아닙니다.
- minimum 작업도 required 집계에 포함합니다. CI 전체 원격 실행 여부는 로컬 검증 결과와 별도로 기록합니다.
