# Dart / native CI

2026-09-13 기준 지원 SDK는 Dart >=3.10.0 <4.0.0이다. `.github/workflows/ci.yml`을 패키지 저장소 루트에 두면 PR, push, 수동 실행, 매주 월요일 03:17 UTC에 실행한다. 정기 실행은 GitHub 기본 브랜치에서 동작한다.

`tool/dart_matrix.py`가 공식 stable archive를 조회해 **3.10.0부터 현재 최신 3.x까지 모든 stable patch**를 선택한다. 현재 최신은 3.13.3이며 24개 버전이다. 새 patch/minor는 다음 실행에 자동 포함된다. beta/dev는 포함하지 않는다. Dart 4가 stable이 되면 조용히 지원 범위를 늘리지 않고 명시적인 결정이 필요하도록 실패한다. API 장애·목록 누락도 빈 matrix 성공으로 처리하지 않는다.

## 실행 구성

- Windows Server 2022 x64 / Ubuntu 24.04 x64에서 Rust 1.97.1 native build와 unit test를 한 번씩 수행한다.
- Linux JPEG 코덱은 고정 커밋 c85e6b905bf237038faa936dab160ebfc5da0344에서 SIMD ON으로 빌드한다. Windows는 패키지의 고정 코덱 DLL을 사용한다.
- OS별 native artifact와 라이선스를 모든 Dart SDK job이 재사용한다. 현 시점 24 × 2 = 48개 SDK/OS 조합이며 최대 동시 실행은 6개다.
- 각 조합: dependency resolution → static analysis → JIT smoke → AOT compile → AOT smoke. JPEG Q90 golden byte equality, PNG SIMD/scalar equality, 오류 후 복구, 크기, 반복 버퍼 해제를 검사한다.
- Dart 3.10.0에서는 `pub downgrade` 후 동일 실행 검사를 수행해 의존성 하한(ffi 2.1.4)을 검증한다. 다른 버전은 lockfile을 강제한다.
- formatter 출력의 버전 차이로 옛 SDK가 실패하지 않도록 포맷 검사는 최신 stable에서만 필수로 수행한다.
- 어느 조합이든 실패하면 최종 `required` job이 실패한다. 브랜치 보호를 사용할 경우 이 job을 필수 검사로 지정한다. 0.1.2에서는 최신 SDK의 전체 golden 검사와 Linux quality/memory job도 필수로 연결했다. 상세 범위와 판정 기준은 [GATES.md](GATES.md)를 참고한다.
- native artifact 보존 기간 7일. 게시·릴리스 생성·pub.dev 업로드·외부 메시지 전송은 하지 않는다.

## 실제 검증 상태

원격 GitHub Actions는 아직 실행하지 않았다. 현재 폴더에 연결된 저장소가 없으므로 48개 원격 조합 성공을 주장하지 않는다. 이관 전 로컬 실행 범위는 [docs/VALIDATION.md](docs/VALIDATION.md)에 요약했다. 원시 로그는 기존 실험 산출물에 보존한다. GitHub hosted runner의 이미지·권한·네트워크 차이는 첫 원격 실행에서 확인해야 한다.

Linux CI는 이전 Linux 후보의 링크 변경을 라이브러리 소스에 반영해 빌드한다. ZIP에 포함된 사전 빌드 DLL은 Windows용이다. Linux용 `.so`는 `bash tool/build-linux.sh` 또는 CI artifact로 얻는다. Linux 실행 시 `LD_LIBRARY_PATH`에 두 `.so`가 있는 디렉터리를 지정한다. Docker 및 성능 임계값에 따른 merge 차단은 이 호환성 workflow에 포함하지 않는다.

## 로컬 실행

Windows: `./tool/build.ps1`, `./tool/verify.ps1`.

Linux: CMake, NASM, GCC, Rust 1.97.1 설치 후 `bash tool/build-linux.sh`.

```sh
export LD_LIBRARY_PATH="$PWD/native/bin/linux-x64"
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart run test/smoke.dart native/bin/linux-x64/libslim_pixels.so test/fixtures/rgb.png
mkdir -p build
dart compile exe test/smoke.dart -o build/smoke
./build/smoke native/bin/linux-x64/libslim_pixels.so test/fixtures/rgb.png
```

참고: [setup-dart](https://github.com/dart-lang/setup-dart), [Dart stable archive](https://dart.dev/get-dart/archive).

## Code Assets 도입 이후

현재 AOT 명령은 `dart compile exe` 대신 `python tool/aot_check.py <검증 Dart 파일> <인수...>`입니다. 모든 SDK/OS에서 별도 소비자 설치와 이동한 번들 실행도 검사합니다. v 태그에서는 전체 게이트 성공 후 플랫폼별 바이너리를 draft release로 묶습니다. 자세한 배포 계약은 `docs/DISTRIBUTION.md`를 참고하세요.
