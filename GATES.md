# 자동 품질 게이트

이 문서는 ABI 2 작업 트리의 자동화 범위와 판정 정책이다. 모든 기존 검증을 같은 종류의 보증으로 취급하지 않는다.

| 검사 | 실행 시점 | 실패 정책 |
|---|---|---|
| SDK 호환성 | 모든 stable patch × Windows/Linux, PR/push/주간/수동 | 분석·JIT·AOT·smoke 오류 시 차단 |
| 문서·공개 API | SDK별 소비자/README 분석, 최신 SDK dartdoc | 잘못된 호출 허용·문서 경고·깨진 링크 시 차단 |
| Native 실패 주입 | 최신 Linux SDK, 격리된 바이너리 6종 | 외부 예외 누출·오류 분류·버퍼 해제 실패 시 차단 |
| Rust 계약/geometry/codec unit test | OS별 native build | 실패 시 차단 |
| 322개 바이트 golden + 12개 정책 거부 | 최신 SDK Windows/Linux, JIT와 AOT | 바이트 변경 또는 지정된 거부 코드 불일치 시 차단 |
| JPEG 반복 호출 | full golden 실행마다 1000회 | 출력 변동·예외 발생 시 차단 |
| Native memory | Linux Valgrind, 2012회 raw/ABI 2 성공·오류·복구 | 메모리 오류·누수 또는 종료 시 잔여 힙이 있으면 차단 |
| Encoder Q90 | 21개 입력 × 2 bound × 3회 실행 | baseline 대비 크기 +2% 초과 또는 PSNR 감소 0.2 dB 초과 시 차단 |
| Header/byte identity | Linux encoder harness | 252개 헤더 및 raw 42개/JPEG 378개 기존 hash 불일치 시 차단 |
| 동일 구현 및 부호표 최적화 전후 픽셀 동일성 | encoder 매 실행 | 동일 구현 출력 차이 또는 optimize 전후 decoded pixel 차이 시 차단 |
| 처리 시간 | encoder 3회, warmup 2회 + 측정 7회 | 원시 결과와 속도비 보고만 수행. 시간 임계값으로 차단하지 않음 |

최종 `required` job은 matrix/native/dart/quality 중 하나라도 실패하거나 skip되면 실패한다. 저장소 브랜치 보호에서 `required`를 필수로 설정해야 실제 병합을 막을 수 있다. YAML만으로 저장소의 브랜치 보호 설정을 변경하지 않는다.

## 고정한 기준의 출처

`test/golden`의 334개 요청은 Q90 42개 + Q75/Q95 84개 + resize→encode 36개 + 기존 geometry 회귀 172개다. 이전 Windows 실험 결과 및 변경 전 DLL의 출력으로 생성했다. 입력과 예상 출력의 hash는 SHA256SUMS.json에 고정했다. 코퍼스의 출처는 tool/encoder/manifest.json 및 test/golden/provenance.json에 보존한다.

`policy_overrides.json`은 기존 투명 JPEG 12개 사례만 명시적으로 거부하도록 지정한다. 원본/기준 이미지와 해시는 유지한다. 새 타입 API의 322개 출력과 12개 거부를 모두 검사한다.

기준 출력을 CI에서 다시 생성하지 않는다. 의도적인 알고리즘 변경으로 기준이 달라지면 원시 출력·품질·라이선스·성능을 다시 검토하고 기준 변경을 별도 코드 리뷰로 처리해야 한다. JSON 기준을 변경해 테스트만 통과시키면 품질 개선을 입증한 것이 아니다.

Q75/Q95도 기존 출력 hash로 회귀를 검사하지만 Q90의 품질·용량 기준을 모두 통과했다고 선언하지 않는다. 기존 Q95 예외 2개는 그대로 남아 있다. Linux의 byte 동일성을 다른 CPU 아키텍처나 다른 codec 버전에 일반화하지 않는다.

## 재현

```sh
# 기존 CI.md의 Linux native build를 먼저 완료한다.
export LD_LIBRARY_PATH="$PWD/native/bin/linux-x64"
dart run tool/validation/golden_check.dart native/bin/linux-x64/libslim_pixels.so test/golden
bash tool/memory_gate.sh
python3 tool/quality_gate.py
```

quality_gate는 cargo 1.97.1, Python 3, GCC와 libturbojpeg.so.0가 필요하고 memory_gate는 Valgrind가 추가로 필요하다. quality_gate는 이전 build/quality/results를 덮어쓰지 않는다. 새 작업 디렉터리에서 실행하거나 보존할 결과를 먼저 옮긴 뒤 다시 실행한다. 인코더 벤치마크 harness와 제품 경로는 별개이므로 334개 사례(322개 바이트·12개 정책 거부)가 실제 Dart API를 따로 검사한다.

실패 여부와 관계없이 Actions는 가능한 메모리 로그와 encoder JSON을 14일 artifact로 보존한다. 출력 이미지 전체를 artifact에 포함하지 않으므로 실패한 출력 자체가 필요한 경우 재현 스크립트를 실행한다. 타이밍은 GitHub hosted runner의 잡음이 있으므로 참고 자료다.

## 검사하지 않는 사항

강제 OOM, allocator 실패 주입, 강제 isolate 종료, 장시간 다중 isolate RSS, malformed corpus fuzzing, Rust panic 복구는 구현·검증되지 않았다. 할당 전 픽셀 크기 검증은 추가했지만 panic=abort 정책은 유지한다. Valgrind는 C ABI/native 경로를 검사하며 Dart VM의 전체 힙을 검사하지 않는다.

원격 Actions 실행 결과와 로컬 검증은 구분한다. 이 작업 환경에는 원격 저장소가 연결돼 있지 않으므로 전체 원격 통과를 주장하지 않는다.

## 소비자 배포 게이트

모든 SDK/OS 작업은 `tool/distribution_check.py`로 경로 없는 로딩, 잘못된 해시 거부, 소스와 캐시를 삭제한 뒤 이동한 AOT 번들의 실행을 검사합니다. AOT는 `tool/aot_check.py`의 `dart build cli`를 사용합니다. 세부 조건과 미검증 범위는 `docs/DISTRIBUTION.md`에 있습니다.
